import Foundation

// Édition RÉELLE de la collision (permissions de déplacement) des maps ORAS.
//
// Un fichier GR (a/0/3/9) est un mini conteneur : magic "GR" + count(u16) +
// offsets u32 × (count+1), header paddé de zéros jusqu'à offsets[0] (=128),
// sections dos-à-dos. Round-trip byte-perfect vérifié sur le ROM.
//
// GR[0] = tilemap de déplacement : width(u16) + height(u16) + width×height u32.
// Chaque u32 encode la permission/le comportement d'une tuile (réf. pk3DS
// MapMatrix.Entry). Valeurs canoniques relevées empiriquement sur le ROM :
//   0x00000020  sol praticable (Centres Pokémon, villes)
//   0x01000021  bloqué / hors-map (le « noir » de pk3DS)
//   0x3D180006  herbes hautes (rencontres, Route 101)
//   0x3D1A0006  eau navigable (mer, Surf)
//   0x911C0030  glace glissante (grotte d113)

// MARK: — Mini conteneur GR

struct GRContainer {
    var sections: [Data]
    var firstSectionOffset: Int   // = offsets[0] (128 observé partout)

    static func parse(_ raw: Data) -> GRContainer? {
        guard raw.count > 8, raw[0] == 0x47, raw[1] == 0x52 else { return nil }  // "GR"
        let count = Int(raw.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 2, as: UInt16.self) })
        guard count > 0, count < 64, 4 + (count + 1) * 4 <= raw.count else { return nil }
        var offsets: [Int] = []
        for i in 0...count {
            offsets.append(Int(raw.withUnsafeBytes {
                $0.loadUnaligned(fromByteOffset: 4 + i * 4, as: UInt32.self)
            }))
        }
        guard let first = offsets.first, first >= 4 + (count + 1) * 4 else { return nil }
        var sections: [Data] = []
        for i in 0..<count {
            guard offsets[i] <= offsets[i+1], offsets[i+1] <= raw.count else { return nil }
            sections.append(raw.subdata(in: offsets[i]..<offsets[i+1]))
        }
        return GRContainer(sections: sections, firstSectionOffset: first)
    }

    func repack() -> Data {
        var out = Data()
        out.append(contentsOf: [0x47, 0x52])                       // "GR"
        var cnt = UInt16(sections.count)
        withUnsafeBytes(of: &cnt) { out.append(contentsOf: $0) }
        var pos = firstSectionOffset
        var offs: [UInt32] = [UInt32(pos)]
        for s in sections { pos += s.count; offs.append(UInt32(pos)) }
        for var o in offs { withUnsafeBytes(of: &o) { out.append(contentsOf: $0) } }
        out.append(Data(repeating: 0, count: firstSectionOffset - out.count))
        for s in sections { out.append(s) }
        return out
    }
}

// MARK: — Tilemap de déplacement (GR[0])

struct GRTileMap {
    var width:  Int
    var height: Int
    var tiles:  [UInt32]   // index = y * width + x

    init?(section0: Data) {
        guard section0.count >= 4 else { return nil }
        let w = Int(section0.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt16.self) })
        let h = Int(section0.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 2, as: UInt16.self) })
        guard w > 0, h > 0, w <= 256, h <= 256,
              4 + w * h * 4 <= section0.count else { return nil }
        width = w; height = h
        tiles = (0..<(w * h)).map { i in
            section0.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4 + i * 4, as: UInt32.self) }
        }
    }

    /// Ré-encode en préservant les octets au-delà du tableau de tuiles (le cas échéant).
    func encode(original: Data) -> Data {
        var out = Data(capacity: original.count)
        var w = UInt16(width), h = UInt16(height)
        withUnsafeBytes(of: &w) { out.append(contentsOf: $0) }
        withUnsafeBytes(of: &h) { out.append(contentsOf: $0) }
        for var t in tiles { withUnsafeBytes(of: &t) { out.append(contentsOf: $0) } }
        let tail = 4 + width * height * 4
        if tail < original.count { out.append(original.subdata(in: tail..<original.count)) }
        return out
    }
}

// MARK: — Correspondance valeurs u32 ↔ TileType de l'éditeur

enum ORASTileValue {

    /// Valeur canonique écrite quand l'utilisateur peint un type.
    static func rawValue(for type: TileType) -> UInt32 {
        switch type {
        case .passable:  return 0x00000020
        case .blocked:   return 0x01000021
        case .tallGrass: return 0x3D180006
        case .water:     return 0x3D1A0006
        case .surfable:  return 0x3D1A0006
        case .waterfall: return 0x3D1A0006   // pas de valeur dédiée identifiée — eau
        case .hole:      return 0x01000021   // pas de valeur dédiée identifiée — bloqué
        case .ice:       return 0x911C0030
        case .sand:      return 0x00000020   // pas de valeur dédiée identifiée — praticable
        }
    }

    /// Classification d'une valeur du ROM pour l'affichage.
    /// Règles empiriques (byte0 = flags de passage, byte2 = type de terrain).
    static func tileType(for raw: UInt32) -> TileType {
        if raw == 0x01000021 { return .blocked }        // hors-map / mur
        let b0 = raw & 0xFF
        let b2 = (raw >> 16) & 0xFF
        switch b0 {
        case 0x01: return .blocked                       // meubles, obstacles
        case 0x30: return .ice                           // glace glissante
        case 0x06: return b2 == 0x1A ? .surfable : .tallGrass
        default:   return .passable
        }
    }
}

// MARK: — Réécriture chirurgicale d'un GARC v0400 (gros fichiers)
//
// Remplace le contenu d'entrées (sous-fichier bit 0) sans reconstruire ni
// parser toutes les entrées : recopie le fichier en ajustant FATB (start/end/
// length), le header FIMB, fileSize et largestUnpadded. Alignement 4 octets
// conservé entre entrées (padding 0xFF, convention garc_pack.py).

enum GARCSurgeon {

    enum SurgeonError: LocalizedError {
        case invalidGARC(String)
        var errorDescription: String? {
            switch self { case .invalidGARC(let m): return "GARC invalide : \(m)" }
        }
    }

    /// Remplace les sous-fichiers bit 0 des entrées données et retourne le binaire complet.
    static func replacingEntries(in data: Data, replacements: [Int: Data]) throws -> Data {
        func u16(_ o: Int) -> Int { Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt16.self) }) }
        func u32(_ o: Int) -> Int { Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt32.self) }) }

        guard data.count > 0x20,
              data[0] == 0x43, data[1] == 0x52, data[2] == 0x41, data[3] == 0x47 else {
            throw SurgeonError.invalidGARC("magic")
        }
        let headerSize = u32(4)
        let dataOffset = u32(16)

        let fatoStart = headerSize
        guard data[fatoStart] == 0x4F else { throw SurgeonError.invalidGARC("FATO") }
        let fatoSize   = u32(fatoStart + 4)
        let entryCount = u16(fatoStart + 8)

        let fatbStart = fatoStart + fatoSize
        guard data[fatbStart] == 0x42 else { throw SurgeonError.invalidGARC("FATB") }
        let fatbSize = u32(fatbStart + 4)

        // Parcours FATB : collecter (posFATB, start, end, length) de chaque sous-fichier
        struct Sub { var fatbPos: Int; var start: Int; var length: Int; var entry: Int; var bit: Int }
        var subs: [Sub] = []
        var pos = fatbStart + 12
        for e in 0..<entryCount {
            let vector = u32(pos); pos += 4
            for bit in 0..<32 where (vector >> bit) & 1 == 1 {
                subs.append(Sub(fatbPos: pos, start: u32(pos), length: u32(pos + 8), entry: e, bit: bit))
                pos += 12
            }
        }

        // Nouvelles données FIMB : recopier chaque sous-fichier dans l'ordre des starts,
        // en substituant les remplacés. (Les starts FATB sont relatifs à dataOffset.)
        let ordered = subs.enumerated().sorted { $0.element.start < $1.element.start }
        var newFATB = data.subdata(in: fatbStart..<(fatbStart + fatbSize))
        var fimb = Data()
        fimb.reserveCapacity(data.count - dataOffset)
        var largest = 0

        func putU32(_ v: Int, at off: Int, in d: inout Data) {
            var x = UInt32(v)
            withUnsafeBytes(of: &x) { d.replaceSubrange(off..<(off + 4), with: $0) }
        }

        for (_, sub) in ordered {
            let payload: Data
            if sub.bit == 0, let rep = replacements[sub.entry] {
                payload = rep
            } else {
                let abs = dataOffset + sub.start
                payload = data.subdata(in: abs..<(abs + sub.length))
            }
            // aligner le début de chaque sous-fichier à 4 octets (padding 0xFF)
            while fimb.count % 4 != 0 { fimb.append(0xFF) }
            let newStart = fimb.count
            fimb.append(payload)
            largest = max(largest, payload.count)

            let rel = sub.fatbPos - fatbStart
            putU32(newStart, at: rel, in: &newFATB)                      // start
            putU32(newStart + payload.count, at: rel + 4, in: &newFATB)  // end
            putU32(payload.count, at: rel + 8, in: &newFATB)             // length
        }
        // padding final (fin de fichier alignée à 4)
        while fimb.count % 4 != 0 { fimb.append(0xFF) }

        // Assemblage : header + FATO inchangé + FATB ajusté + header FIMB + data
        var out = Data(capacity: dataOffset + fimb.count)
        out.append(data.subdata(in: 0..<fatoStart))          // header GARC
        out.append(data.subdata(in: fatoStart..<fatbStart))  // FATO
        out.append(newFATB)                                  // FATB
        var fimbHeader = data.subdata(in: (fatbStart + fatbSize)..<dataOffset)
        putU32(fimb.count, at: 8, in: &fimbHeader)           // FIMB dataSize
        out.append(fimbHeader)
        out.append(fimb)

        putU32(out.count, at: 20, in: &out)                  // fileSize
        let oldLargest = u32(24)
        putU32(max(oldLargest, largest), at: 24, in: &out)   // largestUnpadded
        return out
    }
}
