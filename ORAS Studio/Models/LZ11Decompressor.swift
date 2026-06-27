import Foundation

/// Port exact de Reference/lz11.py — algorithme Nintendo LZ11 (3DS/GBA).
enum LZ11Decompressor {

    // MARK: — Erreurs

    enum Error: LocalizedError {
        case notLZ11(firstByte: UInt8)
        case unexpectedEndOfInput(offset: Int)
        case invalidBackReference(displacement: Int, outputSize: Int)

        var errorDescription: String? {
            switch self {
            case .notLZ11(let b):
                return "Données non-LZ11 : premier octet 0x\(String(format: "%02X", b)) (attendu 0x11)."
            case .unexpectedEndOfInput(let off):
                return "Fin de données inattendue à l'offset \(off)."
            case .invalidBackReference(let d, let sz):
                return "Référence arrière invalide : déplacement \(d) > taille sortie \(sz)."
            }
        }
    }

    // MARK: — Interface publique

    static func isLZ11(_ data: Data) -> Bool {
        data.first == 0x11
    }

    /// Décompresse si LZ11, sinon retourne les données telles quelles.
    static func decompressIfNeeded(_ data: Data) -> Data {
        guard isLZ11(data) else { return data }
        return (try? decompress(data)) ?? data
    }

    // MARK: — Décompression LZ11

    static func decompress(_ data: Data) throws -> Data {
        guard !data.isEmpty else { throw Error.unexpectedEndOfInput(offset: 0) }
        guard data[0] == 0x11 else { throw Error.notLZ11(firstByte: data[0]) }
        guard data.count >= 4 else { throw Error.unexpectedEndOfInput(offset: 1) }

        // Taille décompressée sur 3 octets (little-endian)
        var decompSize = Int(data[1]) | (Int(data[2]) << 8) | (Int(data[3]) << 16)
        var pos = 4

        // Taille étendue sur 4 octets si les 3 premiers valent 0
        if decompSize == 0 {
            guard pos + 4 <= data.count else { throw Error.unexpectedEndOfInput(offset: pos) }
            decompSize = Int(data[pos])
                | (Int(data[pos + 1]) << 8)
                | (Int(data[pos + 2]) << 16)
                | (Int(data[pos + 3]) << 24)
            pos = 8
        }

        var out = [UInt8]()
        out.reserveCapacity(decompSize)
        let n = data.count

        while out.count < decompSize, pos < n {
            // Octet de drapeaux : 8 blocs, MSB en premier
            let flags = data[pos]; pos += 1

            for bit in 0..<8 {
                guard out.count < decompSize, pos < n else { break }

                if (flags & (0x80 >> bit)) == 0 {
                    // ── Octet littéral ──
                    out.append(data[pos]); pos += 1

                } else {
                    // ── Référence arrière ──
                    guard pos < n else { throw Error.unexpectedEndOfInput(offset: pos) }
                    let b0 = Int(data[pos]); pos += 1
                    let indicator = b0 >> 4

                    let count: Int
                    let disp: Int

                    switch indicator {

                    case 0:
                        // Type 0 : longueur moyenne  (count ∈ [0x11, 0x110])
                        guard pos + 2 <= n else { throw Error.unexpectedEndOfInput(offset: pos) }
                        let b1 = Int(data[pos]); pos += 1
                        let b2 = Int(data[pos]); pos += 1
                        count = ((b0 & 0xF) << 4 | (b1 >> 4)) + 0x11
                        disp  = ((b1 & 0xF) << 8 | b2) + 1

                    case 1:
                        // Type 1 : grande longueur  (count ∈ [0x111, 0x10110])
                        guard pos + 3 <= n else { throw Error.unexpectedEndOfInput(offset: pos) }
                        let b1 = Int(data[pos]); pos += 1
                        let b2 = Int(data[pos]); pos += 1
                        let b3 = Int(data[pos]); pos += 1
                        count = ((b0 & 0xF) << 12 | b1 << 4 | (b2 >> 4)) + 0x111
                        disp  = ((b2 & 0xF) << 8 | b3) + 1

                    default:
                        // Type 2 : LZSS standard  (count ∈ [1, 18])
                        guard pos < n else { throw Error.unexpectedEndOfInput(offset: pos) }
                        let b1 = Int(data[pos]); pos += 1
                        count = (b0 >> 4) + 1
                        disp  = ((b0 & 0xF) << 8 | b1) + 1
                    }

                    let start = out.count - disp
                    guard start >= 0 else {
                        throw Error.invalidBackReference(displacement: disp, outputSize: out.count)
                    }
                    // Copie potentiellement chevauchante (implémentation fidèle au Python)
                    for i in 0..<count {
                        guard out.count < decompSize else { break }
                        out.append(out[start + i])
                    }
                }
            }
        }

        return Data(out)
    }
}
