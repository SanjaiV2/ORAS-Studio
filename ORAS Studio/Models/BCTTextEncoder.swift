import Foundation

// MARK: — Encodeur PPTXT
// Port de Reference/pptxt.py — reconstruit le binaire chiffré depuis du texte édité

enum PPTXTEncoder {

    // Réordonnancement (encodage) — inverse de PPTXTDecoder.unremap
    private static let remap: [UInt32: UInt16] = [
        0x202F: 0xE07F,
        0x2026: 0xE08D,
        0x2642: 0xE08E,
        0x2640: 0xE08F,
    ]

    // MARK: — Interface publique

    /// Réencode une banque de lignes PPTXTLine en fichier PPTXT binaire.
    static func encode(_ lines: [PPTXTLine]) throws -> Data {
        try encode(lines.map { $0.text })
    }

    /// Réencode une liste de textes bruts en fichier PPTXT binaire.
    static func encode(_ texts: [String]) throws -> Data {
        let sdo = 0x10
        var key: UInt16 = PPTXTDecoder.keyBase
        var lineBlobs: [Data] = []

        for text in texts {
            let dec = try lineToData(text)
            var enc = PPTXTDecoder.crypt(dec, key: key)
            // Aligner à 4 octets (exigence du format)
            if enc.count % 4 == 2 { enc += Data([0x00, 0x00]) }
            lineBlobs.append(enc)
            key = key &+ PPTXTDecoder.keyAdvance
        }

        let n             = lineBlobs.count
        let recBytesLen   = 8 * n
        let totalBlob     = lineBlobs.reduce(Data(), +)
        let sectionLen    = 4 + recBytesLen + totalBlob.count

        // ── Header (16 octets) ──────────────────────────────────
        var out = Data()
        out += u16le(1)                      // text_sections = 1
        out += u16le(UInt16(n))              // line_count
        out += u32le(UInt32(sectionLen))     // total_length
        out += u32le(0)                      // initial_key = 0
        out += u32le(UInt32(sdo))            // sdo (section data offset = 0x10)

        // ── Section header à sdo ─────────────────────────────────
        out += u32le(UInt32(sectionLen))

        // ── Table des records (8 octets × n) ────────────────────
        // offset relatif à sdo, exprimé comme i32
        var offsetCursor = 4 + recBytesLen
        for blob in lineBlobs {
            out += i32le(Int32(offsetCursor))
            out += u16le(UInt16(blob.count / 2))
            out += Data([0x00, 0x00])        // padding
            offsetCursor += blob.count
        }

        out += totalBlob
        return out
    }

    // MARK: — Conversion texte → bytes bruts (avant chiffrement)

    private static func lineToData(_ text: String) throws -> Data {
        var out = Data()
        var i   = text.startIndex

        while i < text.endIndex {
            let ch = text[i]
            text.formIndex(after: &i)

            switch ch {

            case "[":
                // Balise variable : [VAR XXXX], [WAIT n], [~ n]
                guard let end = text[i...].firstIndex(of: "]") else {
                    out += u16le(0x005B)  // '[' littéral si pas de fermeture
                    continue
                }
                let varText = String(text[i..<end])
                out += try encodeVariable(varText)
                i = text.index(after: end)

            case "\\":
                guard i < text.endIndex else { break }
                let esc = text[i]; text.formIndex(after: &i)
                switch esc {
                case "n":   out += u16le(0x000A)  // saut de ligne
                case "\\":  out += u16le(0x005C)  // backslash littéral
                case "[":   out += u16le(0x005B)  // crochet littéral
                case "r":   // retour de boîte
                    out += u16le(PPTXTDecoder.keyVariable)
                    out += u16le(1)
                    out += u16le(PPTXTDecoder.keyTextReturn)
                case "c":   // effacement boîte
                    out += u16le(PPTXTDecoder.keyVariable)
                    out += u16le(1)
                    out += u16le(PPTXTDecoder.keyTextClear)
                default:
                    throw PPTXTError.badEscapeSequence(esc)
                }

            default:
                let val    = ch.unicodeScalars.first!.value
                let mapped = remap[val] ?? UInt16(val & 0xFFFF)
                out += u16le(mapped)
            }
        }

        out += u16le(PPTXTDecoder.keyTerminator)
        return out
    }

    // MARK: — Encodage des balises variables

    private static func encodeVariable(_ varText: String) throws -> Data {
        var out = Data()

        if varText.hasPrefix("~ ") {
            let line = UInt16(varText.dropFirst(2)) ?? 0
            out += u16le(PPTXTDecoder.keyVariable) + u16le(1)
            out += u16le(PPTXTDecoder.keyTextNull) + u16le(line)
            return out
        }

        if varText.hasPrefix("WAIT ") {
            let t = UInt16(varText.dropFirst(5)) ?? 0
            out += u16le(PPTXTDecoder.keyVariable) + u16le(1)
            out += u16le(PPTXTDecoder.keyTextWait) + u16le(t)
            return out
        }

        if varText.hasPrefix("VAR ") {
            let rest = String(varText.dropFirst(4))
            if let bracket = rest.firstIndex(of: "(") {
                let varname = String(rest[..<bracket])
                let argsRaw = String(rest[rest.index(after: bracket)...].dropLast())
                let varval  = UInt16(varname, radix: 16) ?? 0
                let args    = argsRaw.split(separator: ",").compactMap { UInt16($0, radix: 16) }
                out += u16le(PPTXTDecoder.keyVariable)
                out += u16le(UInt16(1 + args.count))
                out += u16le(varval)
                for a in args { out += u16le(a) }
            } else {
                let varval = UInt16(rest, radix: 16) ?? 0
                out += u16le(PPTXTDecoder.keyVariable) + u16le(1) + u16le(varval)
            }
            return out
        }

        throw PPTXTError.unknownVariable(varText)
    }

    // MARK: — Helpers d'écriture binaire little-endian

    static func u16le(_ v: UInt16) -> Data {
        Data([UInt8(v & 0xFF), UInt8(v >> 8)])
    }

    static func u32le(_ v: UInt32) -> Data {
        Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF),
              UInt8((v >> 16) & 0xFF), UInt8(v >> 24)])
    }

    private static func i32le(_ v: Int32) -> Data {
        u32le(UInt32(bitPattern: v))
    }
}

// MARK: — Sérialiseur GARC (reconstruit le fichier binaire depuis GARCFile)

extension GARCFile {

    /// Rééncode l'intégralité de l'archive en binaire réinjecable dans le romfs.
    func serialize() -> Data {
        // headerSize v0400 : 0x1C (inclut le champ largest_unpadded à 0x18)
        let headerSz = 0x1C

        // ── Collecte des données alignées à 4 octets ────────────
        var allSubData = Data()
        // (start, end, length, bitIndex) par sous-fichier dans l'ordre des entrées
        var subLayouts: [(start: Int, end: Int, length: Int, bit: Int)] = []

        for entry in entries {
            for sub in entry.subFiles {
                let start  = allSubData.count
                let length = sub.rawData.count
                let padded = (length + 3) & ~3        // arrondi à 4 octets
                allSubData += sub.rawData
                if padded > length {
                    allSubData += Data(repeating: 0xFF, count: padded - length)
                }
                subLayouts.append((start: start, end: start + padded,
                                   length: length, bit: sub.bitIndex))
            }
        }

        // ── Construction des entrées FATB + offsets FATO ─────────
        var fatbEntries  = Data()
        var fatoOffsets: [Int] = []
        var subIdx = 0

        for entry in entries {
            fatoOffsets.append(fatbEntries.count)
            var vector: UInt32 = 0
            for sub in entry.subFiles { vector |= 1 << UInt32(sub.bitIndex) }
            fatbEntries += PPTXTEncoder.u32le(vector)
            for _ in entry.subFiles {
                let lay = subLayouts[subIdx]; subIdx += 1
                fatbEntries += PPTXTEncoder.u32le(UInt32(lay.start))
                fatbEntries += PPTXTEncoder.u32le(UInt32(lay.end))
                fatbEntries += PPTXTEncoder.u32le(UInt32(lay.length))
            }
        }

        // ── Calcul des tailles de chunks ──────────────────────────
        let entryCount  = entries.count
        let totalSubs   = entries.reduce(0) { $0 + $1.subFiles.count }
        let fatoSize    = 4 + 4 + 2 + 2 + entryCount * 4
        let fatbSize    = 4 + 4 + 4 + fatbEntries.count
        let fimbHdrSize = 12   // magic(4) + fimbHeaderSize(4) + fimbDataSize(4)
        let dataOffset  = headerSz + fatoSize + fatbSize + fimbHdrSize
        let fileSize    = dataOffset + allSubData.count

        // largest_unpadded : taille max non-paddée
        let largestUnpadded = subLayouts.map(\.length).max() ?? 0

        var out = Data()

        // ── Header GARC ───────────────────────────────────────────
        out += Data([0x43, 0x52, 0x41, 0x47])          // "CRAG"
        out += PPTXTEncoder.u32le(UInt32(headerSz))     // headerSize
        out += PPTXTEncoder.u16le(0xFEFF)               // endian mark
        out += PPTXTEncoder.u16le(version.rawValue)     // version
        out += PPTXTEncoder.u32le(4)                    // chunk count
        out += PPTXTEncoder.u32le(UInt32(dataOffset))   // data offset
        out += PPTXTEncoder.u32le(UInt32(fileSize))     // file size
        out += PPTXTEncoder.u32le(UInt32(largestUnpadded)) // v0400 extra field

        // ── FATO ─────────────────────────────────────────────────
        out += Data([0x4F, 0x54, 0x41, 0x46])           // "OTAF"
        out += PPTXTEncoder.u32le(UInt32(fatoSize))
        out += PPTXTEncoder.u16le(UInt16(entryCount))
        out += PPTXTEncoder.u16le(0)                    // padding
        for o in fatoOffsets { out += PPTXTEncoder.u32le(UInt32(o)) }

        // ── FATB ─────────────────────────────────────────────────
        out += Data([0x42, 0x54, 0x41, 0x46])           // "BTAF"
        out += PPTXTEncoder.u32le(UInt32(fatbSize))
        out += PPTXTEncoder.u32le(UInt32(totalSubs))
        out += fatbEntries

        // ── FIMB ─────────────────────────────────────────────────
        out += Data([0x42, 0x4D, 0x49, 0x46])           // "BMIF"
        out += PPTXTEncoder.u32le(UInt32(fimbHdrSize + allSubData.count)) // fimbHeaderSize
        out += PPTXTEncoder.u32le(UInt32(allSubData.count))               // fimbDataSize
        out += allSubData

        return out
    }

    /// Met à jour les données brutes d'un sous-fichier (pour ré-injection PPTXT).
    mutating func updateSubFile(entry: Int, sub: Int = 0, data newData: Data) {
        guard entries.indices.contains(entry),
              entries[entry].subFiles.indices.contains(sub) else { return }
        entries[entry].subFiles[sub].rawData = newData
    }
}
