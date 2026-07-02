import Foundation

// ══════════════════════════════════════════════════════════════════
// Cinématiques — modèle, section script ZO[2] et compilateur/injecteur
// ══════════════════════════════════════════════════════════════════
//
// Deux niveaux de fiabilité, assumés dans l'UI :
//  • DONNÉES (fiable, prouvé en jeu) : dialogue d'un PNJ = banque storytext
//    (le champ scriptIndex du PNJ EST l'index de banque — vérifié : PNJ 251
//    ↔ a/0/8/x bank 251). On écrit le texte via PPTXT dans les langues voulues.
//  • BYTECODE (expérimental) : séquences injectées dans le pool FireFly de la
//    section ZO[2] (fondu, attente, flags…) + clonage de sub-scripts existants
//    avec rebasage des deltas. Injection mécaniquement propre (round-trip
//    vérifié) ; la sémantique des opcodes reste à valider en jeu.

// MARK: — Modèle de cinématique

struct Cinematic {
    var zoneID: Int
    var trigger: CineTrigger
    var steps: [CineStep]
}

enum CineTrigger: Hashable {
    case npcDialogue(npcIndex: Int)      // parler à un PNJ (fiable)
    case walkTrigger(triggerIndex: Int)  // marcher sur un déclencheur (bytecode)

    var label: String {
        switch self {
        case .npcDialogue(let i): return "Parler au PNJ #\(i)"
        case .walkTrigger(let i): return "Marcher sur le déclencheur #\(i)"
        }
    }
}

enum CineStep: Identifiable, Hashable {
    case dialogue(text: String)
    case fadeOut
    case fadeIn
    case wait(frames: Int)
    case setFlag(id: Int)
    case clearFlag(id: Int)
    case playSound(id: Int)
    case cloneSub(zoneID: Int, subIndex: Int)

    var id: Int { hashValue }

    var isDataOnly: Bool {
        if case .dialogue = self { return true }
        return false
    }

    var label: String {
        switch self {
        case .dialogue(let t):     return "💬 Dialogue : « \(t.prefix(40))\(t.count > 40 ? "…" : "") »"
        case .fadeOut:             return "🌑 Fondu au noir"
        case .fadeIn:              return "🌕 Retour du fondu"
        case .wait(let f):         return "⏱ Attendre \(f) frames"
        case .setFlag(let id):     return "🚩 Activer le flag \(id)"
        case .clearFlag(let id):   return "🏳️ Désactiver le flag \(id)"
        case .playSound(let id):   return "🔊 Jouer le son \(id)"
        case .cloneSub(let z, let s): return "🎬 Séquence clonée : zone \(z), script #\(s)"
        }
    }
}

// MARK: — Section script FireFly (ZO[2])
//
// Layout (offsets relatifs au début de la section, préfixe longueur inclus) :
//   +0x00 length i32 · +0x04 magic 0x0A0AF1E0 · +0x08 ptrOffset u16 ·
//   +0x0A ptrCount u16 · +0x0C instrStart i32 (offset FICHIER du pool VLI) ·
//   +0x10 moveStart i32 (offset décompressé : moveStart-instrStart = taille
//   décompressée du pool) · +0x14 finalOffset i32 · +0x18 allocatedMemory i32 ·
//   +ptrOffset : ptrCount × u32 (offsets octets dans le pool décompressé) ·
//   +instrStart : pool compressé VLI · puis données mouvement (opaques).

struct FireFlySection {
    static let magic: UInt32 = 0x0A0AF1E0

    var header: Data          // les instrStart premiers octets (header + table ptr)
    var pool: [UInt32]        // instructions décompressées
    var tail: Data            // données après le pool compressé (mouvement…)

    var ptrOffset: Int  { Int(u16(header, 8)) }
    var ptrCount: Int   { Int(u16(header, 10)) }
    var instrStart: Int { Int(u32(header, 12)) }
    var moveStart: Int  { Int(u32(header, 16)) }

    var pointers: [Int] {
        (0..<ptrCount).map { Int(u32(header, ptrOffset + $0 * 4)) }
    }

    static func parse(_ section: Data) -> FireFlySection? {
        guard section.count >= 0x1C, u32(section, 4) == magic else { return nil }
        let instrStart = Int(u32(section, 12))
        let moveStart  = Int(u32(section, 16))
        let count = (moveStart - instrStart) / 4
        guard instrStart >= 0x1C, instrStart <= section.count,
              count > 0, count < 500_000 else { return nil }

        // décompresser exactement `count` valeurs en suivant la consommation
        var pool: [UInt32] = []
        pool.reserveCapacity(count)
        var x: UInt32 = 0
        var j = 0
        var consumed = instrStart
        for b8 in section[instrStart...] {
            let b = UInt32(b8)
            consumed += 1
            let v = b & 0x7F
            j += 1
            if j == 1 { x = (v & 0x40) != 0 ? (0xFFFFFF80 | v) : v }
            else      { x = (x << 7) | v }
            if (b & 0x80) == 0 {
                pool.append(x); j = 0; x = 0
                if pool.count == count { break }
            }
        }
        guard pool.count == count else { return nil }
        return FireFlySection(
            header: section.subdata(in: 0..<instrStart),
            pool: pool,
            tail: section.subdata(in: consumed..<section.count))
    }

    /// Ré-encode. Si le pool n'a pas changé, reproduit l'original à l'octet
    /// (même compresseur VLI). Ajuste moveStart/finalOffset/allocatedMemory
    /// et length du delta de taille décompressée.
    func encode(originalPoolCount: Int) -> Data {
        let deltaBytes = (pool.count - originalPoolCount) * 4
        var h = header
        putU32(&h, 16, UInt32(moveStart + deltaBytes))                     // moveStart
        putU32(&h, 20, u32(header, 20) &+ UInt32(bitPattern: Int32(deltaBytes)))  // finalOffset
        putU32(&h, 24, u32(header, 24) &+ UInt32(bitPattern: Int32(deltaBytes)))  // allocatedMemory
        let compressed = ScriptInterpreter.vliCompress(pool)
        var out = Data()
        out.append(h)
        out.append(compressed)
        out.append(tail)
        // length (+0x00) : conserve la sémantique d'origine (delta appliqué)
        let originalLength = u32(header, 0)
        let sizeDelta = Int32(out.count) - Int32(instrStart + (moveStart - instrStart)) // approx si length ≈ taille fichier
        _ = sizeDelta
        putU32(&out, 0, originalLength &+ UInt32(bitPattern: Int32(deltaBytes)))
        return out
    }

    /// Ajoute un sub-script (doit se terminer par Return) à la fin du pool et
    /// fait pointer l'entrée `pointerIndex` de la table dessus.
    mutating func appendSub(_ instructions: [UInt32], redirectPointer pointerIndex: Int) {
        let newPtr = pool.count * 4
        pool.append(contentsOf: instructions)
        putU32(&header, ptrOffset + pointerIndex * 4, UInt32(newPtr))
    }

    /// Extrait les instructions du sub `index` (jusqu'au prochain pointeur ou fin).
    func subInstructions(at index: Int) -> [UInt32] {
        let ptrs = pointers.map { $0 / 4 }
        guard index < ptrs.count else { return [] }
        let start = ptrs[index]
        let next = ptrs.filter { $0 > start }.min() ?? pool.count
        guard start < pool.count else { return [] }
        return Array(pool[start..<min(next, pool.count)])
    }

    /// Rebase un sub-script cloné : les CallFunc/JMP dont la cible sort du sub
    /// (routines communes du pool source) ne peuvent pas être rebasés vers un
    /// autre pool — on ne clone donc qu'au sein de la MÊME zone, où les cibles
    /// externes restent valides après rebasage delta' = (oldPos+delta) - newPos.
    static func rebase(_ instructions: [UInt32], from oldStart: Int, to newStart: Int,
                       subLength: Int) -> [UInt32] {
        let jumpOpcodes: Set<UInt32> = [0x031, 0x081, 0x082, 0x083, 0x084, 0x085]
        return instructions.enumerated().map { (i, instr) in
            let op = instr & 0x3FF
            guard jumpOpcodes.contains(op) else { return instr }
            var delta = Int32(bitPattern: instr) >> 10
            let oldPos = oldStart + i
            let target = oldPos + Int(delta)
            let isInternal = target >= oldStart && target < oldStart + subLength
            if !isInternal {
                // conserver la cible absolue dans le pool
                let newPos = newStart + i
                delta = Int32(target - newPos)
            }
            return (UInt32(bitPattern: delta << 10)) | op
        }
    }
}

// MARK: — Helpers binaires

private func u16(_ d: Data, _ o: Int) -> UInt16 {
    guard o + 2 <= d.count else { return 0 }
    return d.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt16.self) }
}
private func u32(_ d: Data, _ o: Int) -> UInt32 {
    guard o + 4 <= d.count else { return 0 }
    return d.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt32.self) }
}
private func putU32(_ d: inout Data, _ o: Int, _ v: UInt32) {
    guard o + 4 <= d.count else { return }
    var x = v
    withUnsafeBytes(of: &x) { d.replaceSubrange(o..<(o + 4), with: $0) }
}

// MARK: — Conteneur mini ZO (remplacement d'une section)

enum ZOContainer {
    /// Sections du mini « ZO ».
    static func sections(_ zo: Data) -> [Data]? {
        guard zo.count > 8, zo[0] == 0x5A, zo[1] == 0x4F else { return nil }
        let cnt = Int(u16(zo, 2))
        guard cnt > 0, cnt < 16 else { return nil }
        var offs: [Int] = []
        for i in 0...cnt { offs.append(Int(u32(zo, 4 + i * 4))) }
        guard offs.allSatisfy({ $0 <= zo.count }), offs == offs.sorted() else { return nil }
        return (0..<cnt).map { zo.subdata(in: offs[$0]..<offs[$0 + 1]) }
    }

    /// Reconstruit le ZO avec une section remplacée (offsets recalculés,
    /// alignement 4 conservé entre sections comme dans l'original).
    static func replacingSection(_ zo: Data, index: Int, with newSection: Data) -> Data? {
        guard var secs = sections(zo), index < secs.count else { return nil }
        let cnt = secs.count
        secs[index] = newSection
        let headerLen = 4 + (cnt + 1) * 4
        let firstOff = Int(u32(zo, 4))   // conserve le padding d'origine du header
        var out = Data()
        out.append(contentsOf: [0x5A, 0x4F])                       // "ZO"
        var c = UInt16(cnt)
        withUnsafeBytes(of: &c) { out.append(contentsOf: $0) }
        var pos = firstOff
        var offs: [UInt32] = [UInt32(pos)]
        var padded: [Data] = []
        for (i, s) in secs.enumerated() {
            var sec = s
            if i < cnt - 1 {
                while (pos + sec.count) % 4 != 0 { sec.append(0) }
            }
            padded.append(sec)
            pos += sec.count
            offs.append(UInt32(pos))
        }
        for var o in offs { withUnsafeBytes(of: &o) { out.append(contentsOf: $0) } }
        out.append(Data(repeating: 0, count: max(0, firstOff - headerLen)))
        for s in padded { out.append(s) }
        return out
    }
}

// MARK: — Compilateur de cinématiques

enum CinematicCompiler {

    struct CompileResult {
        var storytextEdits: [(bank: Int, line: Int, text: String)]   // voie données
        var bytecodeInstructions: [UInt32]                            // voie bytecode
        /// Plages clonées dans bytecodeInstructions → position source dans le pool
        /// (pour rebasage des deltas à l'injection).
        var clonedRanges: [(range: Range<Int>, sourceStart: Int)]
        var experimental: Bool
    }

    enum CompileError: LocalizedError {
        case noSteps
        case dialogueNeedsNPC
        case bytecodeNeedsWalkTrigger
        case cloneOtherZone

        var errorDescription: String? {
            switch self {
            case .noSteps:               return "La cinématique est vide."
            case .dialogueNeedsNPC:      return "Un dialogue nécessite le déclencheur « Parler au PNJ »."
            case .bytecodeNeedsWalkTrigger:
                return "Les étapes fondu/attente/flag/son/séquence nécessitent le déclencheur « Marcher sur le déclencheur » (voie bytecode)."
            case .cloneOtherZone:
                return "Le clonage de séquence n'est possible que depuis la même zone (les appels référencent le pool local)."
            }
        }
    }

    /// Compile la timeline. Vérifie la cohérence trigger/étapes.
    static func compile(_ cine: Cinematic,
                        npcBank: Int?,
                        sourceSection: FireFlySection?) throws -> CompileResult {
        guard !cine.steps.isEmpty else { throw CompileError.noSteps }

        var texts: [(Int, Int, String)] = []
        var code:  [UInt32] = []
        var cloned: [(Range<Int>, Int)] = []
        var hasBytecode = false

        for step in cine.steps {
            switch step {
            case .dialogue(let text):
                guard case .npcDialogue = cine.trigger, let bank = npcBank else {
                    throw CompileError.dialogueNeedsNPC
                }
                // ligne 1 = dialogue principal du PNJ (convention observée)
                texts.append((bank, 1, text))

            case .fadeOut:
                code.append(make(0x07B)); hasBytecode = true
            case .fadeIn:
                code.append(make(0x07C)); hasBytecode = true
            case .wait(let frames):
                code.append(make(0x05D, arg: Int32(frames))); hasBytecode = true
            case .setFlag(let id):
                code.append(make(0x062, arg: Int32(id))); hasBytecode = true
            case .clearFlag(let id):
                code.append(make(0x063, arg: Int32(id))); hasBytecode = true
            case .playSound(let id):
                code.append(make(0x090, arg: Int32(id))); hasBytecode = true

            case .cloneSub(let zid, let sub):
                guard zid == cine.zoneID else { throw CompileError.cloneOtherZone }
                guard let section = sourceSection else { throw CompileError.bytecodeNeedsWalkTrigger }
                let instrs = section.subInstructions(at: sub)
                guard !instrs.isEmpty else { break }
                let body = Array(instrs.dropLast())   // sans le Return final
                cloned.append((code.count..<(code.count + body.count),
                               section.pointers[sub] / 4))
                code.append(contentsOf: body)
                hasBytecode = true
            }
        }

        if hasBytecode {
            guard case .walkTrigger = cine.trigger else {
                throw CompileError.bytecodeNeedsWalkTrigger
            }
            var full: [UInt32] = [make(0x02E)]   // Begin
            full.append(contentsOf: code)
            full.append(make(0x030))             // Return
            code = full
            // décaler les plages clonées du Begin inséré en tête
            cloned = cloned.map { (($0.0.lowerBound + 1)..<($0.0.upperBound + 1), $0.1) }
        }

        return CompileResult(storytextEdits: texts,
                             bytecodeInstructions: code,
                             clonedRanges: cloned,
                             experimental: hasBytecode)
    }

    private static func make(_ opcode: UInt32, arg: Int32 = 0) -> UInt32 {
        (UInt32(bitPattern: arg << 10)) | (opcode & 0x3FF)
    }
}
