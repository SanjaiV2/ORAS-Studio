import Foundation

// MARK: — Field Script standalone (a/0/1/2)
//
// Format identique à la Section 2 des fichiers ZO (FireFly), mais le magic
// 0x0A0AF1E0 est directement à l'offset 0 (pas à l'offset 4 comme dans les ZO).
//
// Binaire :
//   [0x00] magic      u32  = 0x0A0AF1E0
//   [0x04] length     i32  (taille totale du fichier)
//   [0x08] ptrOffset  u16  (offset table pointeurs)
//   [0x0A] ptrCount   u16  (nombre de sub-scripts)
//   [0x0C] instrStart i32  (offset début bytecode VLI)
//   [0x10] moveStart  i32  (offset données mouvement)
//   [0x14] finalOff   i32
//   [0x18] allocMem   i32
//   [ptrOffset]       ptrCount × i32  (offsets dans le pool décompressé, en bytes)
//   [instrStart]      bytecode VLI compressé
//   [moveStart]       données mouvement (copiées à l'identique)

struct FieldScript {
    static let magic: UInt32 = 0x0A0AF1E0

    var subScripts: [ZoneScript.SubScript]
    var zoneIndex:  Int

    // Méta-données pour re-encoder fidèlement
    var ptrOffset: UInt16   // offset de la table de pointeurs (≥ 28)
    var moveData:  Data     // données copiées après instrEnd

    // MARK: — Parse

    static func parse(from data: Data, zoneIndex: Int) -> FieldScript? {
        guard data.count >= 0x1C else { return nil }

        func u16(_ o: Int) -> UInt16 {
            data.withUnsafeBytes { $0.load(fromByteOffset: o, as: UInt16.self) }
        }
        func u32(_ o: Int) -> UInt32 {
            data.withUnsafeBytes { $0.load(fromByteOffset: o, as: UInt32.self) }
        }
        func i32(_ o: Int) -> Int32 {
            data.withUnsafeBytes { $0.load(fromByteOffset: o, as: Int32.self) }
        }

        guard u32(0) == magic else { return nil }

        let ptrOffset  = u16(8)
        let ptrCount   = Int(u16(10))
        let instrStart = Int(i32(12))
        let moveStart  = Int(i32(16))

        guard instrStart >= 0, instrStart <= data.count,
              moveStart >= instrStart else { return nil }

        // Table de pointeurs
        var ptrs: [Int] = []
        for i in 0..<ptrCount {
            let off = Int(ptrOffset) + i * 4
            guard off + 4 <= data.count else { break }
            ptrs.append(Int(i32(off)))
        }

        // Décompression VLI du pool d'instructions
        let instrEnd = min(moveStart, data.count)
        let pool = ScriptInterpreter.vliDecompress(data: Data(data[instrStart..<instrEnd]))
        let sortedPtrs = ptrs.map { $0 / 4 }.sorted()

        var subScripts: [ZoneScript.SubScript] = []
        for (idx, ptr) in ptrs.enumerated() {
            let startIdx = max(0, ptr / 4)
            let nextIdx: Int
            if let pos = sortedPtrs.firstIndex(of: startIdx), pos + 1 < sortedPtrs.count {
                nextIdx = sortedPtrs[pos + 1]
            } else {
                nextIdx = pool.count
            }
            let sliceStart = min(startIdx, pool.count)
            let sliceEnd   = min(nextIdx,  pool.count)
            var instrs: [ZoneScript.Instruction] = []
            for raw in pool[sliceStart..<sliceEnd] {
                instrs.append(ZoneScript.Instruction(rawValue: raw))
                if raw & 0x3FF == 0x030 { break }  // Return
            }
            subScripts.append(ZoneScript.SubScript(id: idx, byteOffset: ptr, instructions: instrs))
        }

        let moveData = moveStart < data.count ? Data(data[moveStart...]) : Data()

        return FieldScript(
            subScripts: subScripts,
            zoneIndex: zoneIndex,
            ptrOffset: ptrOffset,
            moveData: moveData
        )
    }

    // MARK: — Encode

    func encode() -> Data {
        // 1. Aplatir les instructions en pool + calculer les pointeurs
        var pool: [UInt32] = []
        var pointers: [Int32] = []
        for sub in subScripts {
            pointers.append(Int32(pool.count * 4))
            for instr in sub.instructions { pool.append(instr.rawValue) }
        }

        // 2. Compression VLI
        let compressed = ScriptInterpreter.vliCompress(pool)

        // 3. Calcul des offsets
        let ptrCount      = UInt16(pointers.count)
        let ptrTableSize  = Int(ptrCount) * 4
        let ptrTableEnd   = Int(ptrOffset) + ptrTableSize
        let newInstrStart = (ptrTableEnd + 3) & ~3   // aligné sur 4 octets
        let newMoveStart  = newInstrStart + compressed.count
        let totalSize     = newMoveStart + moveData.count

        // 4. Construction binaire
        var out = Data(count: max(totalSize, 28))

        out.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: FieldScript.magic,    toByteOffset: 0,  as: UInt32.self)
            ptr.storeBytes(of: Int32(totalSize),      toByteOffset: 4,  as: Int32.self)
            ptr.storeBytes(of: ptrOffset,             toByteOffset: 8,  as: UInt16.self)
            ptr.storeBytes(of: ptrCount,              toByteOffset: 10, as: UInt16.self)
            ptr.storeBytes(of: Int32(newInstrStart),  toByteOffset: 12, as: Int32.self)
            ptr.storeBytes(of: Int32(newMoveStart),   toByteOffset: 16, as: Int32.self)
            ptr.storeBytes(of: Int32(totalSize),      toByteOffset: 20, as: Int32.self)
            ptr.storeBytes(of: Int32(totalSize),      toByteOffset: 24, as: Int32.self)
            for (i, p) in pointers.enumerated() {
                ptr.storeBytes(of: p, toByteOffset: Int(ptrOffset) + i * 4, as: Int32.self)
            }
        }

        if !compressed.isEmpty {
            out.replaceSubrange(newInstrStart..<(newInstrStart + compressed.count), with: compressed)
        }
        if !moveData.isEmpty {
            out.replaceSubrange(newMoveStart..<(newMoveStart + moveData.count), with: moveData)
        }

        return out
    }

    // MARK: — Script vide par défaut

    static func empty(zoneIndex: Int) -> FieldScript {
        let sub = ZoneScript.SubScript(
            id: 0,
            byteOffset: 0,
            instructions: [
                .make(opcode: 0x02E),  // Begin
                .make(opcode: 0x030)   // Return
            ]
        )
        // ptrOffset standard = 28 (taille du header : 4+4+2+2+4+4+4+4 bytes)
        return FieldScript(subScripts: [sub], zoneIndex: zoneIndex, ptrOffset: 28, moveData: Data())
    }

    // MARK: — Ajout d'un sub-script

    mutating func addSubScript() {
        let newID = subScripts.count
        subScripts.append(ZoneScript.SubScript(
            id: newID,
            byteOffset: 0,
            instructions: [
                .make(opcode: 0x02E),  // Begin
                .make(opcode: 0x030)   // Return
            ]
        ))
    }
}
