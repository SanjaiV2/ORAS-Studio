import Foundation

// MARK: — Mobilier de zone (ZO Section 1 — Furniture, 22 bytes each)

struct ZoneFurniture: Identifiable, Codable {
    var id = UUID()
    var objID: UInt16
    var xPos: UInt16
    var yPos: UInt16
    var zPos: UInt16
    var facing: UInt8
    var unknown: [UInt8]    // 5 bytes
    var scriptID: UInt16
    var unknown2: [UInt8]   // 6 bytes

    static func makeDefault() -> ZoneFurniture {
        ZoneFurniture(objID: 0, xPos: 0, yPos: 0, zPos: 0,
                      facing: 0, unknown: [0,0,0,0,0],
                      scriptID: 0, unknown2: [0,0,0,0,0,0])
    }
}

// MARK: — PNJ de zone (0x30 = 48 bytes each)

struct ZoneNPC: Identifiable, Codable {
    var id = UUID()
    var npcID: UInt16
    var modelID: UInt16
    var movePerms: UInt16
    var movePerms2: UInt16
    var spawnFlag: UInt16    // flag histoire requis pour apparition
    var scriptIndex: UInt16  // index field script (a/0/1/2)
    var faceDir: UInt16
    var sightRange: UInt16
    var unknown: [UInt8]     // 24 bytes
    var xPos: UInt16
    var yPos: UInt16
    var unknown2: [UInt8]    // 4 bytes

    static func makeDefault() -> ZoneNPC {
        ZoneNPC(npcID: 0, modelID: 0, movePerms: 0, movePerms2: 0,
                spawnFlag: 0, scriptIndex: 0, faceDir: 0, sightRange: 0,
                unknown: Array(repeating: 0, count: 24),
                xPos: 0, yPos: 0,
                unknown2: [0,0,0,0])
    }
}

// MARK: — Warp (12 bytes each)

struct ZoneWarp: Identifiable, Codable {
    var id = UUID()
    var destZone: UInt16
    var destWarp: UInt16
    var xPos: UInt16
    var yPos: UInt16
    var width: UInt8
    var height: UInt8
    var unknown: [UInt8]  // 2 bytes

    static func makeDefault() -> ZoneWarp {
        ZoneWarp(destZone: 0, destWarp: 0, xPos: 0, yPos: 0, width: 1, height: 1, unknown: [0,0])
    }
}

// MARK: — Trigger de marche (16 bytes each)

struct ZoneWalkTrigger: Identifiable, Codable {
    var id = UUID()
    var scriptIndex: UInt16  // index field script (a/0/1/2)
    var unknown: UInt16
    var xPos: UInt16
    var yPos: UInt16
    var width: UInt16
    var height: UInt16
    var unknown2: [UInt8]    // 4 bytes

    static func makeDefault() -> ZoneWalkTrigger {
        ZoneWalkTrigger(scriptIndex: 0, unknown: 0, xPos: 0, yPos: 0,
                        width: 1, height: 1, unknown2: [0,0,0,0])
    }
}

// MARK: — Ensemble des entités d'une zone (ZO Section 1)

struct ZoneEntities {
    var furniture:    [ZoneFurniture]
    var npcs:         [ZoneNPC]
    var warps:        [ZoneWarp]
    var walkTriggers: [ZoneWalkTrigger]

    // MARK: Parse depuis les données brutes de la Section 1
    static func parse(from data: Data) -> ZoneEntities? {
        guard data.count >= 12 else { return nil }

        func u8(_ o: Int) -> UInt8 { data[o] }
        func u16(_ o: Int) -> UInt16 {
            data.withUnsafeBytes { $0.load(fromByteOffset: o, as: UInt16.self) }
        }
        func u32(_ o: Int) -> UInt32 {
            data.withUnsafeBytes { $0.load(fromByteOffset: o, as: UInt32.self) }
        }

        let furnitureCount = Int(u32(0))
        let npcCount       = Int(u32(4))
        let warpCount      = Int(u32(8))
        var cursor = 12

        // Furniture (22 bytes each)
        var furniture: [ZoneFurniture] = []
        for _ in 0..<furnitureCount {
            guard cursor + 22 <= data.count else { break }
            furniture.append(ZoneFurniture(
                objID:    u16(cursor),
                xPos:     u16(cursor + 2),
                yPos:     u16(cursor + 4),
                zPos:     u16(cursor + 6),
                facing:   u8(cursor + 8),
                unknown:  Array(data[(cursor + 9)..<(cursor + 14)]),
                scriptID: u16(cursor + 14),
                unknown2: Array(data[(cursor + 16)..<(cursor + 22)])
            ))
            cursor += 22
        }

        // NPCs (48 bytes each)
        var npcs: [ZoneNPC] = []
        for _ in 0..<npcCount {
            guard cursor + 48 <= data.count else { break }
            npcs.append(ZoneNPC(
                npcID:       u16(cursor),
                modelID:     u16(cursor + 2),
                movePerms:   u16(cursor + 4),
                movePerms2:  u16(cursor + 6),
                spawnFlag:   u16(cursor + 8),
                scriptIndex: u16(cursor + 10),
                faceDir:     u16(cursor + 12),
                sightRange:  u16(cursor + 14),
                unknown:     Array(data[(cursor + 16)..<(cursor + 40)]),
                xPos:        u16(cursor + 40),
                yPos:        u16(cursor + 42),
                unknown2:    Array(data[(cursor + 44)..<(cursor + 48)])
            ))
            cursor += 48
        }

        // Warps (12 bytes each)
        var warps: [ZoneWarp] = []
        for _ in 0..<warpCount {
            guard cursor + 12 <= data.count else { break }
            warps.append(ZoneWarp(
                destZone: u16(cursor),
                destWarp: u16(cursor + 2),
                xPos:     u16(cursor + 4),
                yPos:     u16(cursor + 6),
                width:    u8(cursor + 8),
                height:   u8(cursor + 9),
                unknown:  Array(data[(cursor + 10)..<(cursor + 12)])
            ))
            cursor += 12
        }

        // Walk triggers (précédés d'un u32 count)
        guard cursor + 4 <= data.count else {
            return ZoneEntities(furniture: furniture, npcs: npcs, warps: warps, walkTriggers: [])
        }
        let triggerCount = Int(u32(cursor))
        cursor += 4

        var walkTriggers: [ZoneWalkTrigger] = []
        for _ in 0..<triggerCount {
            guard cursor + 16 <= data.count else { break }
            walkTriggers.append(ZoneWalkTrigger(
                scriptIndex: u16(cursor),
                unknown:     u16(cursor + 2),
                xPos:        u16(cursor + 4),
                yPos:        u16(cursor + 6),
                width:       u16(cursor + 8),
                height:      u16(cursor + 10),
                unknown2:    Array(data[(cursor + 12)..<(cursor + 16)])
            ))
            cursor += 16
        }

        return ZoneEntities(furniture: furniture, npcs: npcs, warps: warps, walkTriggers: walkTriggers)
    }

    // MARK: Réencode en Data binaire
    func encode() -> Data {
        var out = Data()

        func w8(_ v: UInt8) { out.append(v) }
        func w16(_ v: UInt16) {
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { out.append(contentsOf: $0) }
        }
        func w32(_ v: UInt32) {
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { out.append(contentsOf: $0) }
        }
        func pad(_ arr: [UInt8], _ n: Int) -> [UInt8] {
            arr.count >= n ? Array(arr.prefix(n)) : arr + Array(repeating: UInt8(0), count: n - arr.count)
        }

        // Header 12 bytes
        w32(UInt32(furniture.count))
        w32(UInt32(npcs.count))
        w32(UInt32(warps.count))

        // Furniture (22 bytes each)
        for f in furniture {
            w16(f.objID); w16(f.xPos); w16(f.yPos); w16(f.zPos)
            w8(f.facing)
            out.append(contentsOf: pad(f.unknown, 5))
            w16(f.scriptID)
            out.append(contentsOf: pad(f.unknown2, 6))
        }

        // NPCs (48 bytes each)
        for n in npcs {
            w16(n.npcID); w16(n.modelID); w16(n.movePerms); w16(n.movePerms2)
            w16(n.spawnFlag); w16(n.scriptIndex); w16(n.faceDir); w16(n.sightRange)
            out.append(contentsOf: pad(n.unknown, 24))
            w16(n.xPos); w16(n.yPos)
            out.append(contentsOf: pad(n.unknown2, 4))
        }

        // Warps (12 bytes each)
        for w in warps {
            w16(w.destZone); w16(w.destWarp); w16(w.xPos); w16(w.yPos)
            w8(w.width); w8(w.height)
            out.append(contentsOf: pad(w.unknown, 2))
        }

        // Walk triggers
        w32(UInt32(walkTriggers.count))
        for t in walkTriggers {
            w16(t.scriptIndex); w16(t.unknown); w16(t.xPos); w16(t.yPos)
            w16(t.width); w16(t.height)
            out.append(contentsOf: pad(t.unknown2, 4))
        }

        return out
    }

    // MARK: Reconstruction du fichier ZO complet (remplace Section 1)
    static func reconstructZO(zoData: Data, newSection1: Data) -> Data {
        guard zoData.count >= 4 else { return zoData }

        func u16(_ d: Data, _ o: Int) -> UInt16 {
            d.withUnsafeBytes { $0.load(fromByteOffset: o, as: UInt16.self) }
        }
        func u32(_ d: Data, _ o: Int) -> UInt32 {
            d.withUnsafeBytes { $0.load(fromByteOffset: o, as: UInt32.self) }
        }

        let sectionCount = Int(u16(zoData, 2))
        guard sectionCount >= 2 else { return zoData }

        var sections: [Data] = []
        for i in 0..<sectionCount {
            let start = Int(u32(zoData, 4 + i * 4))
            let end   = i + 1 < sectionCount
                ? Int(u32(zoData, 4 + (i + 1) * 4))
                : zoData.count
            sections.append(Data(zoData[start..<min(end, zoData.count)]))
        }
        sections[1] = newSection1

        let headerSize = 4 + sectionCount * 4
        var cursor = headerSize
        var newOffsets: [UInt32] = []
        for sec in sections {
            newOffsets.append(UInt32(cursor))
            cursor += sec.count
        }

        var out = Data(count: cursor)
        out[0] = UInt8(ascii: "Z"); out[1] = UInt8(ascii: "O")
        out.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: UInt16(sectionCount), toByteOffset: 2, as: UInt16.self)
            for (i, off) in newOffsets.enumerated() {
                ptr.storeBytes(of: off, toByteOffset: 4 + i * 4, as: UInt32.self)
            }
        }
        var pos = headerSize
        for sec in sections {
            out.replaceSubrange(pos..<(pos + sec.count), with: sec)
            pos += sec.count
        }
        return out
    }

    // MARK: Extraction de la Section 1 depuis un ZO
    static func extractSection1(from zoData: Data) -> Data? {
        guard zoData.count >= 4,
              zoData[0] == UInt8(ascii: "Z"),
              zoData[1] == UInt8(ascii: "O") else { return nil }

        func u16(_ o: Int) -> UInt16 {
            zoData.withUnsafeBytes { $0.load(fromByteOffset: o, as: UInt16.self) }
        }
        func u32(_ o: Int) -> UInt32 {
            zoData.withUnsafeBytes { $0.load(fromByteOffset: o, as: UInt32.self) }
        }

        let sectionCount = Int(u16(2))
        guard sectionCount >= 2 else { return nil }

        let sec1Start = Int(u32(8))
        let sec2Start = sectionCount >= 3 ? Int(u32(12)) : zoData.count
        guard sec1Start < sec2Start, sec2Start <= zoData.count else { return nil }
        return Data(zoData[sec1Start..<sec2Start])
    }
}
