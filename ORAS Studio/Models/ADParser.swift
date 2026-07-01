import Foundation

// Parse les fichiers « AD » (magic "AD\x0c\0") du GARC a/0/1/4.
// Un AD = une AIRE du monde (partagée par plusieurs zones) contenant :
//   - un header avec table d'offsets de sections
//   - plusieurs sections BCH embarquées (modèles + TEXTURES de l'aire)
//   - tables auxiliaires (caméra, floats…)
// C'est LA source des textures du terrain (index = ZoneData+0x02 « MapArea »).
struct ADParser {

    /// Retourne toutes les sections BCH embarquées, par scan du magic "BCH\0".
    /// Chaque section s'étend jusqu'au BCH suivant (ou la fin du fichier) —
    /// suffisant pour le parsing, qui borne ses lectures via les tailles internes.
    static func extractBCHSections(from data: Data) -> [Data] {
        guard data.count > 8,
              data[0] == 0x41, data[1] == 0x44  // "AD"
        else { return [] }

        let bytes = [UInt8](data)
        var starts: [Int] = []
        var i = 0
        while i + 4 <= bytes.count {
            if bytes[i] == 0x42, bytes[i+1] == 0x43, bytes[i+2] == 0x48, bytes[i+3] == 0x00 {
                starts.append(i)
                i += 4
            } else {
                i += 1
            }
        }
        guard !starts.isEmpty else { return [] }

        var sections: [Data] = []
        for (j, start) in starts.enumerated() {
            let end = j + 1 < starts.count ? starts[j + 1] : bytes.count
            guard end - start > 0x44 else { continue }
            sections.append(Data(bytes[start..<end]))
        }
        return sections
    }
}
