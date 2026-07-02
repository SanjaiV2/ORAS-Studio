import Foundation

// Entités de zone — ZO section 1 (« Overworld Setup & Script »).
//
// Format réel (réf. pk3DS OWSEStructs.ZoneEntities) :
//   +0x00 length i32
//   +0x04 furnitureCount u8 · npcCount u8 · warpCount u8 · triggerCount u8
//   +0x08 trigger2Count i32
//   +0x0C Furniture[0x14 chacun] · NPC[0x30] · Warp[0x18] · Trigger1[0x18]
//         · Trigger2[0x18] · puis blob script (opaque, préservé)

// MARK: — Mobilier (0x14 octets)

struct ZoneFurniture: Identifiable, Codable {
    var id = UUID()
    var scriptID: UInt16     // +0x00
    var objID: UInt16        // +0x02
    var unknown: [UInt8]     // +0x04..0x08 (4 octets)
    var xPos: UInt16         // +0x08
    var yPos: UInt16         // +0x0A
    var zPos: UInt16         // +0x0C (WX)
    var facing: UInt8        // +0x0E (bas de WY)
    var unknown2: [UInt8]    // +0x0F..0x14 (5 octets)

    static func makeDefault() -> ZoneFurniture {
        ZoneFurniture(scriptID: 0, objID: 0, unknown: [0,0,0,0],
                      xPos: 0, yPos: 0, zPos: 0, facing: 0,
                      unknown2: [0,0,0,0,0])
    }
}

// MARK: — PNJ (0x30 octets)

struct ZoneNPC: Identifiable, Codable {
    var id = UUID()
    var npcID: UInt16        // +0x00
    var modelID: UInt16      // +0x02
    var movePerms: UInt16    // +0x04
    var movePerms2: UInt16   // +0x06
    var spawnFlag: UInt16    // +0x08 — flag histoire requis pour apparition
    var scriptIndex: UInt16  // +0x0A — banque storytext du dialogue (PNJ simple)
    var faceDir: UInt16      // +0x0C
    var sightRange: UInt16   // +0x0E
    var unknown: [UInt8]     // +0x10..0x28 (24 octets : leashes de déplacement…)
    var xPos: UInt16         // +0x28
    var yPos: UInt16         // +0x2A
    var unknown2: [UInt8]    // +0x2C..0x30 (4 octets : angle float)

    static func makeDefault() -> ZoneNPC {
        ZoneNPC(npcID: 0, modelID: 0, movePerms: 0, movePerms2: 0,
                spawnFlag: 0, scriptIndex: 0, faceDir: 0, sightRange: 0,
                unknown: Array(repeating: 0, count: 24),
                xPos: 0, yPos: 0,
                unknown2: [0,0,0,0])
    }
}

// MARK: — Warp (0x18 octets)

struct ZoneWarp: Identifiable, Codable {
    var id = UUID()
    var destZone: UInt16     // +0x00 DestinationMap
    var destWarp: UInt16     // +0x02 DestinationTileIndex
    var unknown: [UInt8]     // +0x04..0x0C (8 octets)
    var xPos: UInt16         // +0x0C
    var yPos: UInt16         // +0x0E
    var width: UInt8         // +0x10
    var height: UInt8        // +0x11
    var unknown2: [UInt8]    // +0x12..0x18 (6 octets)

    static func makeDefault() -> ZoneWarp {
        ZoneWarp(destZone: 0, destWarp: 0, unknown: Array(repeating: 0, count: 8),
                 xPos: 0, yPos: 0, width: 1, height: 1,
                 unknown2: Array(repeating: 0, count: 6))
    }
}

// MARK: — Déclencheur de marche (Trigger1, 0x18 octets)

struct ZoneWalkTrigger: Identifiable, Codable {
    var id = UUID()
    var scriptIndex: UInt16  // +0x00 — sub-script du ZO[2]
    var unknown: UInt16      // +0x02
    var unknownMid: [UInt8]  // +0x04..0x0C (8 octets : Constant, U6, U8…)
    var xPos: UInt16         // +0x0C
    var yPos: UInt16         // +0x0E
    var width: UInt16        // +0x10
    var height: UInt16       // +0x12
    var unknown2: [UInt8]    // +0x14..0x18 (4 octets)

    static func makeDefault() -> ZoneWalkTrigger {
        ZoneWalkTrigger(scriptIndex: 0, unknown: 0,
                        unknownMid: Array(repeating: 0, count: 8),
                        xPos: 0, yPos: 0, width: 1, height: 1,
                        unknown2: [0,0,0,0])
    }
}

// MARK: — Ensemble des entités d'une zone (ZO section 1)

struct ZoneEntities {
    var furniture:    [ZoneFurniture]
    var npcs:         [ZoneNPC]
    var warps:        [ZoneWarp]
    var walkTriggers: [ZoneWalkTrigger]

    // Préservés tels quels pour un ré-encodage fidèle
    var lengthField:  UInt32 = 0     // +0x00 (ajusté du delta de taille à l'encode)
    var trigger2Raw:  Data   = Data()  // Trigger2[] (0x18 × count) — opaque
    var scriptBlob:   Data   = Data()  // blob script en fin de section — opaque

    init(furniture: [ZoneFurniture], npcs: [ZoneNPC], warps: [ZoneWarp],
         walkTriggers: [ZoneWalkTrigger]) {
        self.furniture = furniture; self.npcs = npcs
        self.warps = warps; self.walkTriggers = walkTriggers
    }

    // MARK: Parse depuis la section 1 (utiliser extractSection1 d'abord)

    static func parse(from data: Data) -> ZoneEntities? {
        guard data.count >= 12 else { return nil }

        func u8(_ o: Int) -> UInt8 { data[data.startIndex + o] }
        func u16(_ o: Int) -> UInt16 {
            data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt16.self) }
        }
        func u32(_ o: Int) -> UInt32 {
            data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt32.self) }
        }
        func bytes(_ r: Range<Int>) -> [UInt8] {
            [UInt8](data.subdata(in: (data.startIndex + r.lowerBound)..<(data.startIndex + r.upperBound)))
        }

        let lengthField    = u32(0)
        let furnitureCount = Int(u8(4))
        let npcCount       = Int(u8(5))
        let warpCount      = Int(u8(6))
        let triggerCount   = Int(u8(7))
        let trigger2Count  = Int(u32(8))
        var cursor = 12

        let needed = furnitureCount * 0x14 + npcCount * 0x30
                   + warpCount * 0x18 + triggerCount * 0x18 + trigger2Count * 0x18
        guard 12 + needed <= data.count, trigger2Count < 4096 else { return nil }

        var furniture: [ZoneFurniture] = []
        for _ in 0..<furnitureCount {
            furniture.append(ZoneFurniture(
                scriptID: u16(cursor),
                objID:    u16(cursor + 2),
                unknown:  bytes((cursor + 4)..<(cursor + 8)),
                xPos:     u16(cursor + 8),
                yPos:     u16(cursor + 10),
                zPos:     u16(cursor + 12),
                facing:   u8(cursor + 14),
                unknown2: bytes((cursor + 15)..<(cursor + 20))))
            cursor += 0x14
        }

        var npcs: [ZoneNPC] = []
        for _ in 0..<npcCount {
            npcs.append(ZoneNPC(
                npcID:       u16(cursor),
                modelID:     u16(cursor + 2),
                movePerms:   u16(cursor + 4),
                movePerms2:  u16(cursor + 6),
                spawnFlag:   u16(cursor + 8),
                scriptIndex: u16(cursor + 10),
                faceDir:     u16(cursor + 12),
                sightRange:  u16(cursor + 14),
                unknown:     bytes((cursor + 16)..<(cursor + 40)),
                xPos:        u16(cursor + 40),
                yPos:        u16(cursor + 42),
                unknown2:    bytes((cursor + 44)..<(cursor + 48))))
            cursor += 0x30
        }

        var warps: [ZoneWarp] = []
        for _ in 0..<warpCount {
            warps.append(ZoneWarp(
                destZone: u16(cursor),
                destWarp: u16(cursor + 2),
                unknown:  bytes((cursor + 4)..<(cursor + 12)),
                xPos:     u16(cursor + 12),
                yPos:     u16(cursor + 14),
                width:    u8(cursor + 16),
                height:   u8(cursor + 17),
                unknown2: bytes((cursor + 18)..<(cursor + 24))))
            cursor += 0x18
        }

        var walkTriggers: [ZoneWalkTrigger] = []
        for _ in 0..<triggerCount {
            walkTriggers.append(ZoneWalkTrigger(
                scriptIndex: u16(cursor),
                unknown:     u16(cursor + 2),
                unknownMid:  bytes((cursor + 4)..<(cursor + 12)),
                xPos:        u16(cursor + 12),
                yPos:        u16(cursor + 14),
                width:       u16(cursor + 16),
                height:      u16(cursor + 18),
                unknown2:    bytes((cursor + 20)..<(cursor + 24))))
            cursor += 0x18
        }

        var result = ZoneEntities(furniture: furniture, npcs: npcs,
                                  warps: warps, walkTriggers: walkTriggers)
        result.lengthField = lengthField
        let t2End = cursor + trigger2Count * 0x18
        result.trigger2Raw = data.subdata(
            in: (data.startIndex + cursor)..<(data.startIndex + min(t2End, data.count)))
        result.scriptBlob = t2End < data.count
            ? data.subdata(in: (data.startIndex + t2End)..<data.endIndex)
            : Data()
        return result
    }

    // MARK: Ré-encode la section 1 complète

    func encode() -> Data {
        var out = Data()
        func w8(_ v: UInt8)  { out.append(v) }
        func w16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { out.append(contentsOf: $0) } }
        func w32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { out.append(contentsOf: $0) } }
        func pad(_ arr: [UInt8], _ n: Int) -> [UInt8] {
            arr.count >= n ? Array(arr.prefix(n)) : arr + Array(repeating: UInt8(0), count: n - arr.count)
        }

        // header — lengthField ajusté du delta de taille des 4 tableaux
        let bodySize = furniture.count * 0x14 + npcs.count * 0x30
                     + warps.count * 0x18 + walkTriggers.count * 0x18
                     + trigger2Raw.count
        _ = bodySize
        w32(lengthField)
        w8(UInt8(furniture.count)); w8(UInt8(npcs.count))
        w8(UInt8(warps.count));     w8(UInt8(walkTriggers.count))
        w32(UInt32(trigger2Raw.count / 0x18))

        for f in furniture {
            w16(f.scriptID); w16(f.objID)
            out.append(contentsOf: pad(f.unknown, 4))
            w16(f.xPos); w16(f.yPos); w16(f.zPos)
            w8(f.facing)
            out.append(contentsOf: pad(f.unknown2, 5))
        }
        for n in npcs {
            w16(n.npcID); w16(n.modelID); w16(n.movePerms); w16(n.movePerms2)
            w16(n.spawnFlag); w16(n.scriptIndex); w16(n.faceDir); w16(n.sightRange)
            out.append(contentsOf: pad(n.unknown, 24))
            w16(n.xPos); w16(n.yPos)
            out.append(contentsOf: pad(n.unknown2, 4))
        }
        for w in warps {
            w16(w.destZone); w16(w.destWarp)
            out.append(contentsOf: pad(w.unknown, 8))
            w16(w.xPos); w16(w.yPos)
            w8(w.width); w8(w.height)
            out.append(contentsOf: pad(w.unknown2, 6))
        }
        for t in walkTriggers {
            w16(t.scriptIndex); w16(t.unknown)
            out.append(contentsOf: pad(t.unknownMid, 8))
            w16(t.xPos); w16(t.yPos); w16(t.width); w16(t.height)
            out.append(contentsOf: pad(t.unknown2, 4))
        }
        out.append(trigger2Raw)
        out.append(scriptBlob)
        return out
    }

    // MARK: Reconstruction du fichier ZO complet (remplace la section 1)

    static func reconstructZO(zoData: Data, newSection1: Data) -> Data {
        ZOContainer.replacingSection(zoData, index: 1, with: newSection1) ?? zoData
    }

    // MARK: Extraction de la section 1 depuis un ZO

    static func extractSection1(from zoData: Data) -> Data? {
        guard let secs = ZOContainer.sections(zoData), secs.count >= 2 else { return nil }
        return secs[1]
    }
}
