import Foundation

// MARK: — Erreurs de parsing

enum GARCParseError: LocalizedError {
    case tooShort
    case badMagic(got: [UInt8], expected: String)
    case unknownVersion(UInt16)
    case outOfBounds(context: String)

    var errorDescription: String? {
        switch self {
        case .tooShort:
            return "Fichier trop court pour être une archive GARC valide."
        case .badMagic(let got, let expected):
            let hex = got.map { String(format: "%02X", $0) }.joined(separator: " ")
            return "Magic invalide : attendu « \(expected) », lu [\(hex)]."
        case .unknownVersion(let v):
            return "Version GARC inconnue : \(String(format: "0x%04X", v)) (attendu 0x0400 ou 0x0600)."
        case .outOfBounds(let ctx):
            return "Lecture hors limites (\(ctx))."
        }
    }
}

// MARK: — Archive GARC
//
// Format binaire (little-endian), référence : Reference/garc_unpack.py
//
// ┌─────────────────────────────────────────────────────┐
// │  GARC header (headerSize bytes)                     │
// │  [0x00] magic       uint32  = "CRAG"               │
// │  [0x04] headerSize  uint32                          │
// │  [0x08] endianMark  uint16  = 0xFEFF               │
// │  [0x0A] version     uint16  = 0x0400 ou 0x0600     │
// │  [0x0C] chunkCount  uint32  = 4                    │
// │  [0x10] dataOffset  uint32  ← base absolue FIMB   │
// │  [0x14] fileSize    uint32                          │
// │  [0x18] …champs version…                           │
// ├─────────────────────────────────────────────────────┤
// │  FATO chunk ("OTAF")                                │
// │  fatoSize    uint32 ; entryCount uint16 ; pad uint16│
// │  offsets[entryCount]  uint32 each                  │
// ├─────────────────────────────────────────────────────┤
// │  FATB chunk ("BTAF")                                │
// │  fatbSize uint32 ; fileCount uint32                 │
// │  for i in entryCount:                              │
// │    vector   uint32  (bitmask des sous-fichiers)    │
// │    for each set bit:  start uint32, end uint32, len uint32 │
// ├─────────────────────────────────────────────────────┤
// │  FIMB chunk ("BMIF") + data brut                   │
// └─────────────────────────────────────────────────────┘

struct GARCFile {

    // MARK: — Types

    enum Version: UInt16 {
        case v0400 = 0x0400   // ORAS, XY
        case v0600 = 0x0600   // SM, USUM
    }

    // MARK: — Données du fichier

    let version: Version
    var fileCount: Int             // total de sous-fichiers (champ FATB)
    var entries: [GARCEntry]       // entrées indexées

    // MARK: — Init / parsing

    init(data: Data) throws {
        var r = DataReader(data: data)

        // ── En-tête GARC ──
        let magic = try r.readBytes(4)
        guard magic == [0x43, 0x52, 0x41, 0x47] else {  // "CRAG"
            throw GARCParseError.badMagic(got: magic, expected: "CRAG")
        }
        let headerSize = Int(try r.readU32())
        let _          = try r.readU16()  // endian mark (0xFEFF)
        let versionRaw = try r.readU16()
        guard let ver  = Version(rawValue: versionRaw) else {
            throw GARCParseError.unknownVersion(versionRaw)
        }
        let _          = try r.readU32()  // chunk count
        let dataOffset = Int(try r.readU32())
        let _          = try r.readU32()  // file size total
        // Champs spécifiques à la version — on les saute en allant directement à headerSize
        r.seek(to: headerSize)

        // ── Chunk FATO ──
        let fatoMagic = try r.readBytes(4)
        guard fatoMagic == [0x4F, 0x54, 0x41, 0x46] else {  // "OTAF"
            throw GARCParseError.badMagic(got: fatoMagic, expected: "OTAF")
        }
        let fatoSize   = Int(try r.readU32())
        let entryCount = Int(try r.readU16())
        let _          = try r.readU16()  // padding
        // Table d'offsets FATO (non utilisée ici — on utilise les offsets FATB directement)
        r.seek(to: headerSize + fatoSize)

        // ── Chunk FATB ──
        let fatbMagic = try r.readBytes(4)
        guard fatbMagic == [0x42, 0x54, 0x41, 0x46] else {  // "BTAF"
            throw GARCParseError.badMagic(got: fatbMagic, expected: "BTAF")
        }
        let _ = try r.readU32()   // fatbSize
        let fileCount = Int(try r.readU32())
        // r.position est maintenant sur fatb_base

        var entries = [GARCEntry]()
        entries.reserveCapacity(entryCount)

        for i in 0..<entryCount {
            let vector = try r.readU32()
            var subFiles = [GARCSubFile]()

            for bit in 0..<32 {
                guard (vector >> bit) & 1 == 1 else { continue }
                let start  = Int(try r.readU32())
                let end    = Int(try r.readU32())  // non utilisé mais doit être consommé
                let length = Int(try r.readU32())
                _ = end

                let absStart = dataOffset + start
                let absEnd   = absStart + length
                guard absStart >= 0, absEnd <= data.count else {
                    throw GARCParseError.outOfBounds(context: "entrée[\(i)] bit[\(bit)]")
                }
                subFiles.append(GARCSubFile(
                    bitIndex: bit,
                    rawData: data.subdata(in: absStart..<absEnd)
                ))
            }
            entries.append(GARCEntry(id: i, subFiles: subFiles))
        }

        self.version   = ver
        self.fileCount = fileCount
        self.entries   = entries
    }

    // MARK: — Accesseurs

    subscript(index: Int) -> GARCEntry? {
        entries.indices.contains(index) ? entries[index] : nil
    }

    /// Données brutes d'un sous-fichier (par index de bit dans le vecteur).
    func rawData(entry: Int, sub: Int = 0) -> Data? {
        guard let e = self[entry] else { return nil }
        return e.subFiles.first(where: { $0.bitIndex == sub })?.rawData
            ?? e.subFiles[safe: sub]?.rawData
    }

    /// Données décompressées (LZ11 si détecté, sinon brutes).
    func decompressedData(entry: Int, sub: Int = 0) -> Data? {
        guard let raw = rawData(entry: entry, sub: sub) else { return nil }
        return LZ11Decompressor.decompressIfNeeded(raw)
    }
}

// MARK: — Entrée GARC

struct GARCEntry: Identifiable {
    let id: Int
    var subFiles: [GARCSubFile]

    /// Alias de compatibilité
    var subEntries: [GARCSubFile] { subFiles }
}

// MARK: — Sous-fichier GARC

struct GARCSubFile: Identifiable {
    let id = UUID()
    let bitIndex: Int
    var rawData: Data

    var size: Int { rawData.count }
    /// Alias de compatibilité
    var data: Data { rawData }
    var isLZ11Compressed: Bool { LZ11Decompressor.isLZ11(rawData) }

    /// Taille décompressée estimée depuis l'en-tête LZ11 (sans décompresser).
    var estimatedDecompressedSize: Int? {
        guard rawData.count >= 4, rawData[0] == 0x11 else { return nil }
        let size = Int(rawData[1]) | (Int(rawData[2]) << 8) | (Int(rawData[3]) << 16)
        if size == 0, rawData.count >= 8 {
            return rawData.withUnsafeBytes {
                Int($0.loadUnaligned(fromByteOffset: 4, as: UInt32.self).littleEndian)
            }
        }
        return size
    }

    func decompress() throws -> Data {
        try LZ11Decompressor.decompress(rawData)
    }
}

/// Alias de compatibilité avec l'ancien nom.
typealias GARCSubEntry = GARCSubFile

// MARK: — Lecteur de données séquentiel

private struct DataReader {
    private let data: Data
    private(set) var position: Int

    init(data: Data) { self.data = data; position = 0 }

    mutating func seek(to pos: Int) { position = pos }

    mutating func readU8() throws -> UInt8 {
        guard position < data.count else { throw GARCParseError.outOfBounds(context: "u8 à \(position)") }
        defer { position += 1 }
        return data[position]
    }

    mutating func readU16() throws -> UInt16 {
        guard position + 2 <= data.count else { throw GARCParseError.outOfBounds(context: "u16 à \(position)") }
        let v = data.subdata(in: position..<position + 2)
            .withUnsafeBytes { $0.load(as: UInt16.self) }
        position += 2
        return UInt16(littleEndian: v)
    }

    mutating func readU32() throws -> UInt32 {
        guard position + 4 <= data.count else { throw GARCParseError.outOfBounds(context: "u32 à \(position)") }
        let v = data.subdata(in: position..<position + 4)
            .withUnsafeBytes { $0.load(as: UInt32.self) }
        position += 4
        return UInt32(littleEndian: v)
    }

    mutating func readBytes(_ count: Int) throws -> [UInt8] {
        guard position + count <= data.count else { throw GARCParseError.outOfBounds(context: "\(count) bytes à \(position)") }
        let result = Array(data[position..<position + count])
        position += count
        return result
    }
}

// MARK: — Extension utilitaire

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
