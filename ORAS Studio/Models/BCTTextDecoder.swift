import Foundation

// MARK: — Format PPTXT (banques de dialogue ORAS)
// Port de Reference/pptxt.py — chiffrement XOR rotatif + balises variables

// MARK: — Erreurs

enum PPTXTError: LocalizedError {
    case fileTooShort(needed: Int, got: Int)
    case notPPTXT(textSections: Int, initialKey: UInt32)
    case sectionLengthMismatch(expected: UInt32, got: UInt32)
    case badEscapeSequence(Character)
    case unknownVariable(String)

    var errorDescription: String? {
        switch self {
        case .fileTooShort(let n, let g):
            return "Fichier trop court : \(g) octets (minimum \(n) requis)."
        case .notPPTXT(let s, let k):
            return "Pas un fichier PPTXT valide (sections=\(s), initialKey=\(k))."
        case .sectionLengthMismatch(let e, let g):
            return "Incohérence de longueur : attendu \(e), lu \(g)."
        case .badEscapeSequence(let c):
            return "Séquence d'échappement inconnue : \\\(c)"
        case .unknownVariable(let s):
            return "Balise variable inconnue : [\(s)]"
        }
    }
}

// MARK: — Modèles

struct PPTXTLine: Identifiable {
    let id: Int
    var text: String        // texte éditable (balises préservées)
    let original: String    // référence immutable pour détecter les modifications

    var isModified: Bool { text != original }

    /// Version lisible : balises converties en symboles visuels
    var displayText: String {
        var s = text
        s = s.replacingOccurrences(of: "\\n", with: "↵")
        s = s.replacingOccurrences(of: "\\r", with: "⏎")
        s = s.replacingOccurrences(of: "\\c", with: "⬜")
        s = s.replacingOccurrences(
            of: #"\[VAR 0100[^\]]*\]"#, with: "{JOUEUR}", options: .regularExpression)
        s = s.replacingOccurrences(
            of: #"\[VAR 0101[^\]]*\]"#, with: "{RIVAL}",  options: .regularExpression)
        s = s.replacingOccurrences(
            of: #"\[VAR ([^\]]+)\]"#,    with: "{$1}",    options: .regularExpression)
        s = s.replacingOccurrences(
            of: #"\[WAIT (\d+)\]"#,      with: "⏳$1",    options: .regularExpression)
        s = s.replacingOccurrences(
            of: #"\[~ (\d+)\]"#,         with: "→$1",    options: .regularExpression)
        return s.isEmpty ? "(vide)" : s
    }
}

struct PPTXTBank: Identifiable {
    let id: Int             // index de l'entrée GARC
    var lines: [PPTXTLine]

    var isModified:    Bool { lines.contains { $0.isModified } }
    var modifiedCount: Int  { lines.filter   { $0.isModified }.count }
}

// MARK: — Décodeur PPTXT

enum PPTXTDecoder {

    // ── Constantes de chiffrement (depuis pptxt.py) ──────────────────────

    static let keyBase:       UInt16 = 0x7C89
    static let keyAdvance:    UInt16 = 0x2983
    static let keyVariable:   UInt16 = 0x0010
    static let keyTerminator: UInt16 = 0x0000
    static let keyTextReturn: UInt16 = 0xBE00
    static let keyTextClear:  UInt16 = 0xBE01
    static let keyTextWait:   UInt16 = 0xBE02
    static let keyTextNull:   UInt16 = 0xBDFF

    // Réordonnancement inverse (décodage)
    private static let unremap: [UInt16: UInt32] = [
        0xE07F: 0x202F,   // espace insécable étroit
        0xE08D: 0x2026,   // points de suspension …
        0xE08E: 0x2642,   // ♂
        0xE08F: 0x2640,   // ♀
    ]

    // MARK: — Interface publique

    /// Décode un fichier PPTXT en liste de lignes (balises préservées).
    static func decode(_ data: Data) throws -> [PPTXTLine] {
        guard data.count >= 0x10 else {
            throw PPTXTError.fileTooShort(needed: 0x10, got: data.count)
        }

        let textSections = readU16(data, 0)
        let lineCount    = Int(readU16(data, 2))
        let totalLength  = readU32(data, 4)
        let initialKey   = readU32(data, 8)
        let sdo          = Int(readU32(data, 0x0C))

        guard textSections == 1, initialKey == 0 else {
            throw PPTXTError.notPPTXT(textSections: Int(textSections), initialKey: initialKey)
        }
        guard data.count >= sdo + 4 else {
            throw PPTXTError.fileTooShort(needed: sdo + 4, got: data.count)
        }

        let sectionLength = readU32(data, sdo)
        guard sectionLength == totalLength else {
            throw PPTXTError.sectionLengthMismatch(expected: totalLength, got: sectionLength)
        }

        let recBase = sdo + 4
        var lines: [PPTXTLine] = []
        var key = keyBase

        for i in 0..<lineCount {
            let recOff = recBase + i * 8
            guard recOff + 6 <= data.count else { break }

            let relOff = Int(readI32(data, recOff))
            let length = Int(readU16(data, recOff + 4))
            let absOff = relOff + sdo
            let absEnd = absOff + length * 2

            guard absOff >= 0, absEnd <= data.count else {
                lines.append(PPTXTLine(id: i, text: "", original: ""))
                key = key &+ keyAdvance
                continue
            }

            let enc  = data[absOff..<absEnd]
            let dec  = crypt(enc, key: key)
            let text = parseLine(dec)
            lines.append(PPTXTLine(id: i, text: text, original: text))
            key = key &+ keyAdvance
        }
        return lines
    }

    // MARK: — Chiffrement XOR + rotation de 3 bits (partagé avec l'encodeur)

    static func crypt(_ data: Data, key: UInt16) -> Data {
        guard data.count >= 2 else { return data }
        var out = Data(count: data.count)
        var k   = key
        var i   = data.startIndex
        var o   = 0
        while i + 1 <= data.endIndex - 1 {
            let raw = UInt16(data[i]) | (UInt16(data[i + 1]) << 8)
            let val = raw ^ k
            out[o]     = UInt8(val & 0xFF)
            out[o + 1] = UInt8(val >> 8)
            k = (k << 3) | (k >> 13)   // rotation gauche 3 bits
            i = data.index(i, offsetBy: 2)
            o += 2
        }
        return out
    }

    // MARK: — Parsing d'une ligne déchiffrée

    private static func parseLine(_ data: Data) -> String {
        var out = ""
        var i   = 0
        while i + 1 < data.count {
            let val = readU16(data, i)
            if val == keyTerminator { break }
            i += 2
            if val == keyVariable {
                let (s, newI) = parseVariable(data, i)
                out += s; i = newI
            } else if val == 0x000A {
                out += "\\n"
            } else if val == 0x005C {
                out += "\\\\"
            } else if val == 0x005B {
                out += "\\["
            } else {
                let mapped = unremap[val].map { UInt32($0) } ?? UInt32(val)
                if let scalar = Unicode.Scalar(mapped) {
                    out += String(scalar)
                }
            }
        }
        return out
    }

    // MARK: — Parsing d'une variable (balise spéciale)

    private static func parseVariable(_ data: Data, _ start: Int) -> (String, Int) {
        var i = start
        guard i + 3 < data.count else { return ("[VAR?]", i) }
        let count    = readU16(data, i); i += 2
        let variable = readU16(data, i); i += 2
        switch variable {
        case keyTextReturn: return ("\\r", i)
        case keyTextClear:  return ("\\c", i)
        case keyTextWait:
            guard i + 1 < data.count else { return ("[WAIT ?]", i) }
            let time = readU16(data, i); i += 2
            return ("[WAIT \(time)]", i)
        case keyTextNull:
            guard i + 1 < data.count else { return ("[~ ?]", i) }
            let line = readU16(data, i); i += 2
            return ("[~ \(line)]", i)
        default:
            var args: [String] = []
            var remaining = Int(count) - 1
            while remaining > 0, i + 1 < data.count {
                args.append(String(format: "%04X", readU16(data, i)))
                i += 2; remaining -= 1
            }
            var s = String(format: "[VAR %04X", variable)
            if !args.isEmpty { s += "(" + args.joined(separator: ",") + ")" }
            return (s + "]", i)
        }
    }

    // MARK: — Helpers de lecture little-endian (accessibles au package)

    static func readU16(_ data: Data, _ offset: Int) -> UInt16 {
        let base = data.startIndex
        guard offset + 1 < data.count else { return 0 }
        return UInt16(data[base + offset]) | (UInt16(data[base + offset + 1]) << 8)
    }

    static func readU32(_ data: Data, _ offset: Int) -> UInt32 {
        let base = data.startIndex
        guard offset + 3 < data.count else { return 0 }
        return UInt32(data[base + offset])
            | (UInt32(data[base + offset + 1]) << 8)
            | (UInt32(data[base + offset + 2]) << 16)
            | (UInt32(data[base + offset + 3]) << 24)
    }

    static func readI32(_ data: Data, _ offset: Int) -> Int32 {
        Int32(bitPattern: readU32(data, offset))
    }
}
