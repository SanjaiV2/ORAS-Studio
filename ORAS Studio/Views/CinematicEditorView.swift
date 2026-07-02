import SwiftUI

// ══════════════════════════════════════════════════════════════════
// Éditeur de cinématiques — timeline d'actions + déclencheur + injection
// ══════════════════════════════════════════════════════════════════

struct CinematicEditorView: View {
    @EnvironmentObject var controller: ProjectController

    // Zones
    @State private var zoneIDs: [Int] = []
    @State private var selectedZone: Int?

    // Contenu de la zone sélectionnée
    @State private var npcs: [ZoneNPC] = []
    @State private var scriptSection: FireFlySection?
    @State private var zoData: Data = Data()

    // Cinématique en cours
    @State private var trigger: CineTrigger = .npcDialogue(npcIndex: 0)
    @State private var steps: [CineStep] = []

    // UI
    @State private var showAddStep = false
    @State private var dialogueDraft = ""
    @State private var waitDraft = 60
    @State private var flagDraft = 0x800
    @State private var soundDraft = 0
    @State private var cloneDraft = 0
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var isInjecting = false

    private var isExperimental: Bool { steps.contains { !$0.isDataOnly } }

    var body: some View {
        HSplitView {
            zoneColumn.frame(minWidth: 190, maxWidth: 230)
            triggerColumn.frame(minWidth: 230, maxWidth: 280)
            timelineColumn.frame(minWidth: 380, maxWidth: .infinity)
        }
        .task { await loadZones() }
    }

    // MARK: — Colonne 1 : zones

    private var zoneColumn: some View {
        VStack(spacing: 0) {
            header("Zones", icon: "map.fill")
            List(zoneIDs, id: \.self, selection: $selectedZone) { id in
                Text(ZoneDictionary.label(for: id))
                    .font(.system(.caption, design: .monospaced))
                    .tag(id)
            }
            .listStyle(.sidebar)
        }
        .onChange(of: selectedZone) { _, id in
            if let id { Task { await loadZone(id) } }
        }
    }

    // MARK: — Colonne 2 : déclencheur

    private var triggerColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("Déclencheur", icon: "bolt.fill")
            if selectedZone == nil {
                ContentUnavailableView("Choisissez une zone", systemImage: "map")
            } else {
                List {
                    Section("Parler à un PNJ  ·  fiable") {
                        if npcs.isEmpty { Text("Aucun PNJ dans cette zone").foregroundStyle(.tertiary) }
                        ForEach(Array(npcs.enumerated()), id: \.offset) { (i, npc) in
                            // banque storytext valide = dialogue simple éditable ;
                            // au-delà = PNJ à script complexe (non éditable en v1)
                            let simple = npc.scriptIndex < 637
                            triggerRow(.npcDialogue(npcIndex: i),
                                       title: simple ? "PNJ #\(i)  💬" : "PNJ #\(i)  ⚙️",
                                       subtitle: simple
                                           ? "dialogue simple · banque \(npc.scriptIndex) · pos (\(npc.xPos / 18),\(npc.yPos / 18))"
                                           : "script complexe (\(npc.scriptIndex)) — non éditable")
                        }
                    }
                    Section("Marcher sur un déclencheur  ·  ⚠︎ expérimental") {
                        let n = scriptSection?.ptrCount ?? 0
                        if n == 0 { Text("Aucun script de zone").foregroundStyle(.tertiary) }
                        ForEach(0..<n, id: \.self) { i in
                            triggerRow(.walkTrigger(triggerIndex: i),
                                       title: "Déclencheur #\(i)",
                                       subtitle: "\(scriptSection?.subInstructions(at: i).count ?? 0) instructions")
                        }
                    }
                }
            }
        }
    }

    private func triggerRow(_ t: CineTrigger, title: String, subtitle: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(trigger == t ? .bold : .regular))
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if trigger == t { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
        }
        .contentShape(Rectangle())
        .onTapGesture { trigger = t }
    }

    // MARK: — Colonne 3 : timeline

    private var timelineColumn: some View {
        VStack(spacing: 0) {
            HStack {
                header("Timeline", icon: "film.stack")
                Spacer()
                if isExperimental {
                    Label("Expérimental", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                        .help("Les étapes autres que Dialogue injectent du bytecode dont l'effet en jeu reste à valider.")
                }
                Menu {
                    Button("💬 Dialogue…") { dialogueDraft = ""; showAddStep = true }
                    Divider()
                    Button("🌑 Fondu au noir") { steps.append(.fadeOut) }
                    Button("🌕 Retour du fondu") { steps.append(.fadeIn) }
                    Button("⏱ Attendre 60 frames") { steps.append(.wait(frames: waitDraft)) }
                    Button("🚩 Activer flag…") { steps.append(.setFlag(id: flagDraft)) }
                    Button("🔊 Jouer un son") { steps.append(.playSound(id: soundDraft)) }
                    if let s = scriptSection, s.ptrCount > 0, let z = selectedZone {
                        Menu("🎬 Cloner une séquence de la zone") {
                            ForEach(0..<s.ptrCount, id: \.self) { i in
                                Button("Script #\(i) (\(s.subInstructions(at: i).count) instr.)") {
                                    steps.append(.cloneSub(zoneID: z, subIndex: i))
                                }
                            }
                        }
                    }
                } label: {
                    Label("Ajouter", systemImage: "plus.circle.fill")
                }
                .padding(.trailing, 10)
            }

            Divider()

            if steps.isEmpty {
                ContentUnavailableView("Timeline vide",
                    systemImage: "film",
                    description: Text("Ajoutez des étapes : dialogue, fondu, attente…"))
            } else {
                List {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { (i, step) in
                        HStack {
                            Text("\(i + 1)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                                .frame(width: 22)
                            Text(step.label).font(.callout)
                            Spacer()
                            if !step.isDataOnly {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundStyle(.orange).font(.caption)
                            }
                        }
                    }
                    .onMove { steps.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { steps.remove(atOffsets: $0) }
                }
            }

            Divider()

            HStack {
                if let msg = statusMessage {
                    Label(msg, systemImage: statusIsError ? "xmark.octagon.fill" : "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(statusIsError ? .red : .green)
                        .lineLimit(2)
                }
                Spacer()
                Button {
                    Task { await inject() }
                } label: {
                    if isInjecting { ProgressView().controlSize(.small) }
                    else { Label("Injecter dans le jeu", systemImage: "arrow.down.doc.fill") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(steps.isEmpty || selectedZone == nil || isInjecting)
            }
            .padding(10)
        }
        .sheet(isPresented: $showAddStep) { dialogueSheet }
    }

    private var dialogueSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Texte du dialogue").font(.headline)
            Text("Écrit dans la banque de textes du PNJ (français + anglais). \\n = saut de ligne.")
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $dialogueDraft)
                .font(.body)
                .frame(width: 420, height: 120)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            HStack {
                Spacer()
                Button("Annuler") { showAddStep = false }
                Button("Ajouter") {
                    if !dialogueDraft.isEmpty { steps.append(.dialogue(text: dialogueDraft)) }
                    showAddStep = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(dialogueDraft.isEmpty)
            }
        }
        .padding(20)
    }

    private func header(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption)
            Text(title).font(.caption.weight(.semibold))
            Spacer()
        }
        .padding(8)
        .background(.quaternary.opacity(0.35))
    }

    // MARK: — Chargement

    private func loadZones() async {
        guard let project = controller.project else { return }
        if let garc = try? await project.garc(at: "a/0/1/3") {
            zoneIDs = garc.entries.map(\.id)
        }
    }

    private func loadZone(_ id: Int) async {
        guard let project = controller.project else { return }
        steps = []
        statusMessage = nil
        guard let garc = try? await project.garc(at: "a/0/1/3"),
              let raw = garc.rawData(entry: id) else { return }
        let zo = LZ11Decompressor.decompressIfNeeded(raw)
        zoData = zo
        npcs = ZoneEntities.extractSection1(from: zo).flatMap { ZoneEntities.parse(from: $0) }?.npcs ?? []
        if let secs = ZOContainer.sections(zo), secs.count >= 3 {
            scriptSection = FireFlySection.parse(secs[2])
        } else {
            scriptSection = nil
        }
        trigger = npcs.isEmpty ? .walkTrigger(triggerIndex: 0) : .npcDialogue(npcIndex: 0)
    }

    // MARK: — Injection

    private func inject() async {
        guard let project = controller.project, let zoneID = selectedZone else { return }
        isInjecting = true
        defer { isInjecting = false }

        do {
            let npcBank: Int? = {
                if case .npcDialogue(let i) = trigger, i < npcs.count {
                    return Int(npcs[i].scriptIndex)
                }
                return nil
            }()
            let cine = Cinematic(zoneID: zoneID, trigger: trigger, steps: steps)
            let result = try CinematicCompiler.compile(cine, npcBank: npcBank,
                                                       sourceSection: scriptSection)

            // ── Voie données : textes de dialogue (FR + EN) ──
            for edit in result.storytextEdits {
                for garcPath in ["a/0/8/2", "a/0/8/1"] {     // FR, EN
                    var garc = try await project.garc(at: garcPath)
                    guard edit.bank < garc.entries.count else {
                        throw NSError(domain: "Cinematic", code: 1, userInfo: [
                            NSLocalizedDescriptionKey:
                            "Ce PNJ référence la banque \(edit.bank), hors limites (\(garc.entries.count) banques). " +
                            "Son dialogue n'est pas une simple banque de texte — choisissez un autre PNJ (banque < \(garc.entries.count))."
                        ])
                    }
                    guard let bankData = garc.decompressedData(entry: edit.bank) else { continue }
                    var lines = try PPTXTDecoder.decode(bankData).map(\.text)
                    while lines.count <= edit.line { lines.append("") }
                    lines[edit.line] = edit.text
                    let encoded = try PPTXTEncoder.encode(lines)
                    garc.updateSubFile(entry: edit.bank, data: encoded)
                    try project.writeGARC(garc, at: garcPath)
                    copyToMods(project: project, relativePath: garcPath)
                }
            }

            // ── Voie bytecode : injection dans ZO[2] ──
            if case .walkTrigger(let trigIndex) = trigger, !result.bytecodeInstructions.isEmpty {
                guard var section = scriptSection else {
                    throw CinematicCompiler.CompileError.bytecodeNeedsWalkTrigger
                }
                let originalCount = section.pool.count
                // rebasage des séquences clonées : conserver les cibles absolues
                // (routines communes du pool) depuis la nouvelle position du corps
                var instrs = result.bytecodeInstructions
                let newSubStart = section.pool.count
                for (range, sourceStart) in result.clonedRanges {
                    let body = Array(instrs[range])
                    let rebased = FireFlySection.rebase(
                        body,
                        from: sourceStart,
                        to: newSubStart + range.lowerBound,
                        subLength: body.count)
                    instrs.replaceSubrange(range, with: rebased)
                }
                section.appendSub(instrs, redirectPointer: trigIndex)
                let newSection = section.encode(originalPoolCount: originalCount)
                guard let newZO = ZOContainer.replacingSection(zoData, index: 2, with: newSection) else {
                    throw CinematicCompiler.CompileError.noSteps
                }
                let compressed = LZ11Decompressor.compress(newZO)
                let garcURL = project.romfsURL.appending(path: "a/0/1/3")
                let garcData = try Data(contentsOf: garcURL)
                let rebuilt = try GARCSurgeon.replacingEntries(in: garcData,
                                                               replacements: [zoneID: compressed])
                try rebuilt.write(to: garcURL, options: .atomic)
                copyToMods(project: project, relativePath: "a/0/1/3")
            }

            let expNote = result.experimental ? " (bytecode expérimental — à valider en jeu)" : ""
            statusMessage = "Cinématique injectée : \(result.storytextEdits.count) texte(s), "
                + "\(result.bytecodeInstructions.count) instruction(s)\(expNote)"
            statusIsError = false
        } catch {
            statusMessage = error.localizedDescription
            statusIsError = true
        }
    }

    private func copyToMods(project: ORASProject, relativePath: String) {
        let src = project.romfsURL.appending(path: relativePath)
        let dst = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Citra/load/mods/000400000011C400/romfs/\(relativePath)")
        try? FileManager.default.createDirectory(at: dst.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: dst)
        try? FileManager.default.copyItem(at: src, to: dst)
    }
}
