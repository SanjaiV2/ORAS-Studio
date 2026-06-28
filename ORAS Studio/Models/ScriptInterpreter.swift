import Foundation

// MARK: — Type de paramètre pour édition type-aware

enum ArgumentKind: String {
    case none      = "—"
    case dialogID  = "Dialogue #"
    case flagID    = "Flag ID"
    case itemID    = "Objet ID"
    case varID     = "Variable"
    case delta     = "Delta"
    case trainerID = "Dresseur ID"
    case count     = "Quantité"
    case raw       = "Valeur"

    var sfSymbol: String {
        switch self {
        case .none:      return "minus"
        case .dialogID:  return "text.bubble"
        case .flagID:    return "flag.fill"
        case .itemID:    return "bag.fill"
        case .varID:     return "square.stack"
        case .delta:     return "arrow.right"
        case .trainerID: return "person.fill"
        case .count:     return "number"
        case .raw:       return "0.square"
        }
    }
}

// MARK: — Modèle ZoneScript

struct ZoneScript: Identifiable {
    static let fireFlyMagic: UInt32 = 0x0A0AF1E0

    let id: Int
    let ptrOffset: UInt16
    let ptrCount: UInt16
    let instrStart: Int
    let moveStart: Int
    let subScripts: [SubScript]
    var rawSectionData: Data

    // MARK: SubScript

    struct SubScript: Identifiable {
        let id: Int
        let byteOffset: Int
        var instructions: [Instruction]

        var label: String { String(format: "Script %d  (@ 0x%04X)", id, byteOffset) }
    }

    // MARK: Instruction — identité UUID pour SwiftUI ForEach+Binding

    struct Instruction: Identifiable {
        let id: UUID
        var rawValue: UInt32

        init(rawValue: UInt32) {
            self.id = UUID()
            self.rawValue = rawValue
        }

        var opcode: UInt32 { rawValue & 0x3FF }
        var arg: Int32 { Int32(bitPattern: rawValue) >> 10 }

        var name: String { FireFlyOpcode.name(for: opcode) }
        var argKind: ArgumentKind { FireFlyOpcode.argKind(for: opcode) }
        var isUnknown: Bool { FireFlyOpcode.table[opcode] == nil }
        var isShowMessage: Bool { opcode == 0x05A }
        var isReturn: Bool { opcode == 0x030 }
        var isJump: Bool { [UInt32(0x081), 0x082, 0x083, 0x084, 0x085].contains(opcode) }
        var isFlag: Bool { [UInt32(0x061), 0x062, 0x063].contains(opcode) }

        mutating func setOpcode(_ op: UInt32) {
            rawValue = (UInt32(bitPattern: arg) << 10) | (op & 0x3FF)
        }
        mutating func setArg(_ a: Int32) {
            rawValue = (UInt32(bitPattern: a) << 10) | opcode
        }

        static func make(opcode: UInt32, arg: Int32 = 0) -> Instruction {
            Instruction(rawValue: (UInt32(bitPattern: arg) << 10) | (opcode & 0x3FF))
        }
    }
}

// MARK: — Table des opcodes FireFly (pk3DS + XY/ORAS research)

enum FireFlyOpcode {
    struct Info {
        let name: String
        let description: String
        let argKind: ArgumentKind
    }

    static let table: [UInt32: Info] = [
        0x000: Info(name: "Nop",           description: "Aucune opération",               argKind: .none),
        0x02E: Info(name: "Begin",         description: "Début de sub-script",             argKind: .none),
        0x02F: Info(name: "End",           description: "Fin de sub-script",               argKind: .none),
        0x030: Info(name: "Return",        description: "Retour au script appelant",        argKind: .none),
        0x031: Info(name: "CallFunc",      description: "Appel sous-routine (delta rel.)",  argKind: .delta),
        0x032: Info(name: "CallStd",       description: "Appel fonction standard",          argKind: .raw),
        0x033: Info(name: "JumpTable",     description: "Saut via table d'index",           argKind: .raw),
        0x036: Info(name: "SetWork",       description: "Assigne valeur de travail",        argKind: .raw),
        0x040: Info(name: "CheckSeenPoke", description: "Vérifie Pokémon vu (NatDex ID)",  argKind: .raw),
        0x048: Info(name: "CheckCaughtP",  description: "Vérifie Pokémon capturé",          argKind: .raw),
        0x050: Info(name: "GiveItem",      description: "Donne objet au joueur",            argKind: .itemID),
        0x05A: Info(name: "ShowMessage",   description: "Affiche un dialogue",              argKind: .dialogID),
        0x05B: Info(name: "CloseMessage",  description: "Ferme la boîte de dialogue",       argKind: .none),
        0x05C: Info(name: "WaitButton",    description: "Attendre appui bouton A/B",        argKind: .none),
        0x05D: Info(name: "WaitTime",      description: "Attendre N frames",                argKind: .count),
        0x061: Info(name: "CheckFlag",     description: "Vérifie un flag histoire",         argKind: .flagID),
        0x062: Info(name: "SetFlag",       description: "Active un flag histoire",          argKind: .flagID),
        0x063: Info(name: "ClearFlag",     description: "Désactive un flag histoire",       argKind: .flagID),
        0x064: Info(name: "GetVar",        description: "Lit une variable de scénario",     argKind: .varID),
        0x065: Info(name: "SetVar",        description: "Écrit une variable de scénario",   argKind: .varID),
        0x06F: Info(name: "StartBattle",   description: "Lance combat dresseur (ID)",       argKind: .trainerID),
        0x070: Info(name: "CheckBattle",   description: "Vérifie résultat combat (0=gagné)",argKind: .none),
        0x07B: Info(name: "FadeOut",       description: "Fondu au noir",                    argKind: .none),
        0x07C: Info(name: "FadeIn",        description: "Retour depuis fondu",              argKind: .none),
        0x081: Info(name: "JMP",           description: "Saut inconditionnel (delta rel.)", argKind: .delta),
        0x082: Info(name: "JE",            description: "Saut si égal (delta rel.)",        argKind: .delta),
        0x083: Info(name: "JNE",           description: "Saut si différent (delta rel.)",   argKind: .delta),
        0x084: Info(name: "JGT",           description: "Saut si supérieur (delta rel.)",   argKind: .delta),
        0x085: Info(name: "JLT",           description: "Saut si inférieur (delta rel.)",   argKind: .delta),
        0x087: Info(name: "CheckVar",      description: "Vérifie variable",                 argKind: .varID),
        0x090: Info(name: "PlaySound",     description: "Joue un son (ID)",                 argKind: .raw),
        0x0BC: Info(name: "PushConst",     description: "Empile constante (arg = valeur)",  argKind: .raw),
        0x0BD: Info(name: "GetGlobal3",    description: "Lit variable globale 3",           argKind: .none),
        0x0BE: Info(name: "GetWorkValue",  description: "Lit valeur de travail",            argKind: .none),
        0x0BF: Info(name: "AdjustStack",   description: "Ajuste le stack (N slots)",        argKind: .raw),
        0x0C0: Info(name: "SetWorkValue",  description: "Écrit valeur de travail",          argKind: .raw),
        0x0C1: Info(name: "StoreResult",   description: "Stocke résultat",                  argKind: .none),
    ]

    static func name(for opcode: UInt32) -> String {
        table[opcode]?.name ?? String(format: "UNK_%03X", opcode)
    }
    static func description(for opcode: UInt32) -> String {
        table[opcode]?.description ?? "Opcode inconnu"
    }
    static func argKind(for opcode: UInt32) -> ArgumentKind {
        table[opcode]?.argKind ?? .raw
    }

    // Groupes pour le menu de sélection d'opcode
    static let flowGroup:     [UInt32] = [0x02E, 0x02F, 0x030, 0x031, 0x081, 0x082, 0x083, 0x084, 0x085]
    static let dialogGroup:   [UInt32] = [0x05A, 0x05B, 0x05C, 0x05D]
    static let flagGroup:     [UInt32] = [0x061, 0x062, 0x063]
    static let variableGroup: [UInt32] = [0x064, 0x065, 0x087, 0x036]
    static let battleGroup:   [UInt32] = [0x06F, 0x070]
    static let effectGroup:   [UInt32] = [0x07B, 0x07C, 0x090]
    static let miscGroup:     [UInt32] = [0x000, 0x032, 0x033, 0x040, 0x048, 0x050, 0x0BC, 0x0BE, 0x0BF, 0x0C0, 0x0C1]
}

// MARK: — Parseur / Compilateur

enum ScriptInterpreter {

    enum ParseError: LocalizedError {
        case invalidMagic(UInt32)
        case dataTooShort
        case invalidZone

        var errorDescription: String? {
            switch self {
            case .invalidMagic(let m): "Magic invalide : 0x\(String(m, radix: 16, uppercase: true))"
            case .dataTooShort:        "Données section trop courtes"
            case .invalidZone:         "Fichier ZO invalide ou section MapScript absente"
            }
        }
    }

    // MARK: VLI Décompresseur (port de pk3DS QuickDecompress)
    static func vliDecompress(data: Data) -> [UInt32] {
        var result: [UInt32] = []
        var j = 0
        var x: UInt32 = 0
        for b8 in data {
            let b = UInt32(b8)
            let v = b & 0x7F
            j += 1
            if j == 1 {
                x = (v & 0x40) != 0 ? (0xFFFFFF80 | v) : v
            } else {
                x = (x << 7) | v
            }
            if (b & 0x80) == 0 {
                result.append(x)
                j = 0; x = 0
            }
        }
        return result
    }

    // MARK: VLI Compresseur (inverse exact de QuickDecompress)
    // Encode chaque UInt32 comme un entier signé 32-bit en VLI big-endian 7-bit.
    static func vliCompress(_ instructions: [UInt32]) -> Data {
        var out = Data()
        for v in instructions {
            var sv = Int32(bitPattern: v)
            var groups: [UInt8] = []
            var safetyCount = 0
            repeat {
                groups.append(UInt8(truncatingIfNeeded: sv & 0x7F))
                sv >>= 7  // décalage arithmétique (conserve le signe)
                safetyCount += 1
            } while safetyCount < 6 &&
                    !(sv == 0  && (groups.last! & 0x40) == 0) &&
                    !(sv == -1 && (groups.last! & 0x40) != 0)
            groups.reverse()
            for (i, byte) in groups.enumerated() {
                out.append(i < groups.count - 1 ? byte | 0x80 : byte)
            }
        }
        return out
    }

    // MARK: Parser
    static func parseZone(zoData: Data, zoneIndex: Int) throws -> ZoneScript {
        guard zoData.count >= 8 else { throw ParseError.dataTooShort }
        func u16(_ d: Data, _ o: Int) -> UInt16 { d.withUnsafeBytes { $0.load(fromByteOffset: o, as: UInt16.self) } }
        func u32(_ d: Data, _ o: Int) -> UInt32 { d.withUnsafeBytes { $0.load(fromByteOffset: o, as: UInt32.self) } }
        func i32(_ d: Data, _ o: Int) -> Int32  { d.withUnsafeBytes { $0.load(fromByteOffset: o, as: Int32.self) } }

        let sectionCount = Int(u16(zoData, 2))
        guard sectionCount > 2 else { throw ParseError.invalidZone }

        let sec2Offset = Int(u32(zoData, 4 + 2 * 4))
        let secSlice = Data(zoData.dropFirst(sec2Offset))
        guard secSlice.count >= 0x1C else { throw ParseError.dataTooShort }
        let magic = u32(secSlice, 4)
        guard magic == ZoneScript.fireFlyMagic else { throw ParseError.invalidMagic(magic) }

        let ptrOffset  = u16(secSlice, 8)
        let ptrCount   = u16(secSlice, 10)
        let instrStart = Int(i32(secSlice, 12))
        let moveStart  = Int(i32(secSlice, 16))

        var ptrs: [Int] = []
        for i in 0..<Int(ptrCount) {
            ptrs.append(Int(i32(secSlice, Int(ptrOffset) + i * 4)))
        }

        let instrEnd = max(instrStart, min(moveStart, secSlice.count))
        let pool = vliDecompress(data: Data(secSlice[instrStart..<instrEnd]))
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

        return ZoneScript(id: zoneIndex, ptrOffset: ptrOffset, ptrCount: ptrCount,
                          instrStart: instrStart, moveStart: moveStart,
                          subScripts: subScripts, rawSectionData: secSlice)
    }

    // MARK: Compilateur section 2 (MapScript)
    // Reconstruit les données binaires de la section FireFly depuis un tableau de sub-scripts édités.
    static func recompileSection(template: ZoneScript, subScripts: [ZoneScript.SubScript]) -> Data {
        // 1. Aplatir les instructions en pool + calculer les pointeurs
        var pool: [UInt32] = []
        var pointers: [Int32] = []
        for sub in subScripts {
            pointers.append(Int32(pool.count * 4))  // byte offset dans le pool décompressé
            for instr in sub.instructions { pool.append(instr.rawValue) }
        }

        // 2. VLI compresser
        let compressed = vliCompress(pool)

        // 3. Recalculer les offsets de section
        let ptrTableSize   = Int(template.ptrCount) * 4
        let ptrTableEnd    = Int(template.ptrOffset) + ptrTableSize
        let newInstrStart  = (ptrTableEnd + 3) & ~3   // aligné sur 4 octets
        let moveData: Data = template.moveStart < template.rawSectionData.count
            ? Data(template.rawSectionData[template.moveStart...]) : Data()
        let newMoveStart   = newInstrStart + compressed.count
        let totalSize      = newMoveStart + moveData.count

        // 4. Construire le binaire
        var out = Data(count: totalSize)

        // Copier l'en-tête original (magic, ptrOffset, ptrCount)
        let hdrLen = min(Int(template.ptrOffset), template.rawSectionData.count)
        template.rawSectionData.withUnsafeBytes { src in
            out.withUnsafeMutableBytes { dst in
                _ = memcpy(dst.baseAddress!, src.baseAddress!, hdrLen)
            }
        }

        // Patcher les champs recalculés
        out.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: Int32(totalSize),     toByteOffset: 0,  as: Int32.self)
            ptr.storeBytes(of: Int32(newInstrStart), toByteOffset: 12, as: Int32.self)
            ptr.storeBytes(of: Int32(newMoveStart),  toByteOffset: 16, as: Int32.self)
            ptr.storeBytes(of: Int32(totalSize),     toByteOffset: 20, as: Int32.self)
            ptr.storeBytes(of: Int32(totalSize),     toByteOffset: 24, as: Int32.self)
            for (i, p) in pointers.enumerated() {
                ptr.storeBytes(of: p, toByteOffset: Int(template.ptrOffset) + i * 4, as: Int32.self)
            }
        }

        // Instructions compressées
        out.replaceSubrange(newInstrStart..<(newInstrStart + compressed.count), with: compressed)

        // Données de mouvement (copiées à l'identique)
        if !moveData.isEmpty {
            out.replaceSubrange(newMoveStart..<(newMoveStart + moveData.count), with: moveData)
        }

        return out
    }

    // MARK: Reconstruction du fichier ZO complet
    // Remplace la section 2 (MapScript) par la section recompilée.
    static func reconstructZO(zoData: Data, newSection2: Data) -> Data {
        guard zoData.count >= 4 else { return zoData }
        func u16(_ d: Data, _ o: Int) -> UInt16 { d.withUnsafeBytes { $0.load(fromByteOffset: o, as: UInt16.self) } }
        func u32(_ d: Data, _ o: Int) -> UInt32 { d.withUnsafeBytes { $0.load(fromByteOffset: o, as: UInt32.self) } }

        let sectionCount = Int(u16(zoData, 2))
        guard sectionCount > 2 else { return zoData }

        var sections: [Data] = []
        for i in 0..<sectionCount {
            let start = Int(u32(zoData, 4 + i * 4))
            let end   = i + 1 < sectionCount ? Int(u32(zoData, 4 + (i + 1) * 4)) : zoData.count
            sections.append(Data(zoData[start..<min(end, zoData.count)]))
        }
        sections[2] = newSection2

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
}
