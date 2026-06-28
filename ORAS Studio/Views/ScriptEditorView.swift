import SwiftUI

// MARK: — Éditeur de scripts FireFly (section MapScript des zones ZO)

struct ScriptEditorView: View {
    @EnvironmentObject var controller: ProjectController

    // Données chargées
    @State private var zones: [(index: Int, script: ZoneScript)] = []
    @State private var isLoading = false
    @State private var loadError: String?

    // Sélection
    @State private var selectedZoneID: Int?
    @State private var selectedSubID: Int?

    // État d'édition (sub-script actuellement ouvert)
    @State private var editableInstructions: [ZoneScript.Instruction] = []
    @State private var isDirty = false

    // Sauvegarde
    @State private var isSaving = false
    @State private var saveMessage: String?
    @State private var saveIsError = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Chargement des scripts de zone…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = loadError {
                loadErrorView(err)
            } else {
                HStack(spacing: 0) {
                    zoneListColumn.frame(width: 160)
                    Divider()
                    subScriptColumn.frame(width: 205)
                    Divider()
                    instructionEditorColumn.frame(maxWidth: .infinity)
                }
            }
        }
        .task { await loadAllScripts() }
    }

    // MARK: — Colonne 1 : liste des zones

    private var zoneListColumn: some View {
        VStack(spacing: 0) {
            columnHeader("Zones", icon: "map.fill", count: zones.count)
            List(zones, id: \.index, selection: $selectedZoneID) { item in
                HStack(spacing: 6) {
                    Text(String(format: "%03d", item.index))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("\(item.script.ptrCount)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    if item.script.subScripts.contains(where: { $0.instructions.contains(where: \.isShowMessage) }) {
                        Image(systemName: "text.bubble.fill")
                            .imageScale(.small)
                            .foregroundStyle(.green.opacity(0.7))
                    }
                }
                .tag(item.index)
            }
            .listStyle(.sidebar)
        }
        .onChange(of: selectedZoneID) { _, _ in
            selectedSubID = nil
            editableInstructions = []
            isDirty = false
        }
    }

    // MARK: — Colonne 2 : liste des sub-scripts

    @ViewBuilder
    private var subScriptColumn: some View {
        VStack(spacing: 0) {
            columnHeader("Sub-scripts", icon: "doc.text.fill",
                         count: selectedZone?.subScripts.count ?? 0)
            if let zone = selectedZone {
                List(zone.subScripts, selection: $selectedSubID) { sub in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(String(format: "#%02d", sub.id))
                                .font(.system(.callout, design: .monospaced))
                                .fontWeight(.semibold)
                            Text(String(format: "@ 0x%04X", sub.byteOffset))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 6) {
                            Text("\(sub.instructions.count) instr.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            if sub.instructions.contains(where: \.isShowMessage) {
                                Label("Dialogue", systemImage: "text.bubble.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                            }
                            if sub.instructions.contains(where: \.isFlag) {
                                Label("Flag", systemImage: "flag.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.purple)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                    .tag(sub.id)
                }
                .listStyle(.sidebar)
            } else {
                ContentUnavailableView("Sélectionnez une zone", systemImage: "map")
            }
        }
        .onChange(of: selectedSubID) { _, newID in
            guard let zone = selectedZone, let id = newID,
                  let sub = zone.subScripts.first(where: { $0.id == id }) else { return }
            editableInstructions = sub.instructions
            isDirty = false
            saveMessage = nil
        }
    }

    // MARK: — Colonne 3 : éditeur d'instructions

    @ViewBuilder
    private var instructionEditorColumn: some View {
        if let zone = selectedZone, let subID = selectedSubID,
           let sub = zone.subScripts.first(where: { $0.id == subID }) {
            VStack(spacing: 0) {
                editorHeader(zone: zone, sub: sub)
                Divider()
                editorToolbar
                Divider()
                instructionList
            }
        } else {
            ContentUnavailableView(
                "Sélectionnez un sub-script",
                systemImage: "doc.text",
                description: Text("Choisissez une zone puis un sub-script pour éditer ses instructions FireFly.")
            )
        }
    }

    // En-tête info
    private func editorHeader(zone: ZoneScript, sub: ZoneScript.SubScript) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text.fill").foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text("Zone \(String(format: "%03d", zone.id))")
                        .fontWeight(.semibold)
                    Text("—")
                        .foregroundStyle(.secondary)
                    Text(String(format: "Script #%02d  @ 0x%04X", sub.id, sub.byteOffset))
                        .font(.system(.callout, design: .monospaced))
                }
                Text("\(editableInstructions.count) instructions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isDirty {
                Label("Modifié", systemImage: "pencil.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.regularMaterial)
    }

    // Barre d'outils
    private var editorToolbar: some View {
        HStack(spacing: 10) {
            // Ajouter instruction
            Button {
                let instr = ZoneScript.Instruction.make(opcode: 0x000)
                editableInstructions.append(instr)
                isDirty = true
            } label: {
                Label("Ajouter", systemImage: "plus.circle")
            }
            .buttonStyle(.bordered)

            // Insertion rapide post-game
            quickInsertMenu

            Spacer()

            // Statut sauvegarde
            if let msg = saveMessage {
                Label(msg, systemImage: saveIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(saveIsError ? .red : .green)
                    .font(.callout)
                    .transition(.opacity)
            }

            // Sauvegarder
            Button {
                Task { await saveCurrentSubScript() }
            } label: {
                if isSaving {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Label("Sauvegarder", systemImage: "square.and.arrow.down")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSaving || !isDirty)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.background)
    }

    // Menu insertion rapide
    private var quickInsertMenu: some View {
        Menu {
            Section("Scripts complets") {
                Button("Script minimal (Begin + Return)") {
                    insertMany([.make(opcode: 0x02E), .make(opcode: 0x030)])
                }
                Button("Dialogue simple (ShowMessage + Close + WaitButton)") {
                    insertMany([.make(opcode: 0x05A, arg: 0),
                                .make(opcode: 0x05B),
                                .make(opcode: 0x05C)])
                }
                Button("Fondu + Dialogue + Fondu") {
                    insertMany([.make(opcode: 0x07B),
                                .make(opcode: 0x05A, arg: 0),
                                .make(opcode: 0x05B),
                                .make(opcode: 0x05C),
                                .make(opcode: 0x07C)])
                }
            }
            Section("Conditions post-game (flags Seko)") {
                Button("CheckFlag — Ligue battue (0x0861)") {
                    insertMany([.make(opcode: 0x061, arg: 0x0861)])
                }
                Button("SetFlag — Anomalie Seko (0x0900)") {
                    insertMany([.make(opcode: 0x062, arg: 0x0900)])
                }
                Button("SetFlag — Route 114 enquêtée (0x0901)") {
                    insertMany([.make(opcode: 0x062, arg: 0x0901)])
                }
                Button("SetFlag — Dialga localisé (0x0902)") {
                    insertMany([.make(opcode: 0x062, arg: 0x0902)])
                }
                Button("SetFlag — Suite terminée (0x090F)") {
                    insertMany([.make(opcode: 0x062, arg: 0x090F)])
                }
            }
            Section("Pattern If/Else") {
                Button("If Flag == 1 → JE +2 sinon JMP End") {
                    insertMany([.make(opcode: 0x061, arg: 0),   // CheckFlag(?)
                                .make(opcode: 0x082, arg: 1),   // JE +1 (skip JMP)
                                .make(opcode: 0x081, arg: 2),   // JMP +2 (jump to end)
                                .make(opcode: 0x030)])           // Return
                }
            }
        } label: {
            Label("Insertion rapide", systemImage: "wand.and.stars")
        }
        .menuStyle(.borderedButton)
    }

    // Liste des instructions éditables
    private var instructionList: some View {
        List {
            ForEach($editableInstructions) { $instr in
                InstructionRowView(
                    index: editableInstructions.firstIndex(where: { $0.id == instr.id }) ?? 0,
                    instr: $instr,
                    onDelete: {
                        editableInstructions.removeAll { $0.id == instr.id }
                        isDirty = true
                    },
                    onChange: { isDirty = true }
                )
            }
            .onMove { from, to in
                editableInstructions.move(fromOffsets: from, toOffset: to)
                isDirty = true
            }
            .onDelete { offsets in
                editableInstructions.remove(atOffsets: offsets)
                isDirty = true
            }
        }
        .listStyle(.inset)
        .environment(\.defaultMinListRowHeight, 38)
    }

    // MARK: — Erreur de chargement

    private func loadErrorView(_ msg: String) -> some View {
        ContentUnavailableView {
            Label("Erreur de chargement", systemImage: "xmark.circle.fill").foregroundStyle(.red)
        } description: {
            Text(msg)
        } actions: {
            Button("Réessayer") { Task { await loadAllScripts() } }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: — Header colonne

    @ViewBuilder
    private func columnHeader(_ title: String, icon: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(.secondary)
            Text(title)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(count)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(.regularMaterial)
        Divider()
    }

    // MARK: — Computed

    private var selectedZone: ZoneScript? {
        guard let id = selectedZoneID else { return nil }
        return zones.first(where: { $0.index == id })?.script
    }

    // MARK: — Helpers

    private func insertMany(_ instrs: [ZoneScript.Instruction]) {
        editableInstructions.append(contentsOf: instrs)
        isDirty = true
    }

    // MARK: — Chargement

    private func loadAllScripts() async {
        guard let project = controller.project else { return }
        isLoading = true; loadError = nil; zones = []
        do {
            let garc = try await project.garc(at: "a/0/1/3")
            var loaded: [(index: Int, script: ZoneScript)] = []
            for entry in garc.entries {
                guard let sub = entry.subFiles.first else { continue }
                let raw = LZ11Decompressor.decompressIfNeeded(sub.rawData)
                guard raw.count >= 8,
                      raw[0] == UInt8(ascii: "Z"), raw[1] == UInt8(ascii: "O") else { continue }
                let secCount = Int(raw.withUnsafeBytes { $0.load(fromByteOffset: 2, as: UInt16.self) })
                guard secCount > 2 else { continue }
                if let script = try? ScriptInterpreter.parseZone(zoData: raw, zoneIndex: entry.id) {
                    loaded.append((index: entry.id, script: script))
                }
            }
            zones = loaded
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: — Sauvegarde + compilation

    private func saveCurrentSubScript() async {
        guard let project = controller.project,
              let zoneID = selectedZoneID,
              let subID = selectedSubID,
              let zoneInfo = zones.first(where: { $0.index == zoneID })
        else { return }

        isSaving = true; saveMessage = nil

        do {
            // Charger le GARC brut
            var garc = try await project.garc(at: "a/0/1/3")
            guard let entry = garc.entries.first(where: { $0.id == zoneID }),
                  let subFile = entry.subFiles.first else {
                throw NSError(domain: "ScriptEditor", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Entrée GARC zone \(zoneID) introuvable"])
            }

            let wasCompressed = LZ11Decompressor.isLZ11(subFile.rawData)
            let zoData = LZ11Decompressor.decompressIfNeeded(subFile.rawData)

            // Remplacer les instructions du sub-script sélectionné
            var updatedSubs = zoneInfo.script.subScripts
            if let idx = updatedSubs.firstIndex(where: { $0.id == subID }) {
                updatedSubs[idx] = ZoneScript.SubScript(
                    id: subID,
                    byteOffset: updatedSubs[idx].byteOffset,
                    instructions: editableInstructions
                )
            }

            // Recompiler section 2
            let newSection2 = ScriptInterpreter.recompileSection(
                template: zoneInfo.script,
                subScripts: updatedSubs
            )

            // Reconstruire le ZO complet
            let newZoData = ScriptInterpreter.reconstructZO(zoData: zoData, newSection2: newSection2)

            // Ré-emballer avec LZ11 si l'original était compressé
            let finalData = wasCompressed ? LZ11Decompressor.compress(newZoData) : newZoData

            // Écrire dans le GARC puis sur disque
            garc.updateSubFile(entry: zoneID, sub: 0, data: finalData)
            try project.writeGARC(garc, at: "a/0/1/3")

            isDirty = false
            saveIsError = false
            saveMessage = wasCompressed ? "Sauvegardé (LZ11)" : "Sauvegardé"

            // Rafraîchir le modèle local
            if let zoneIdx = zones.firstIndex(where: { $0.index == zoneID }),
               let updatedScript = try? ScriptInterpreter.parseZone(zoData: newZoData, zoneIndex: zoneID) {
                zones[zoneIdx] = (index: zoneID, script: updatedScript)
            }
        } catch {
            saveIsError = true
            saveMessage = error.localizedDescription
        }

        isSaving = false
    }
}

// MARK: — Ligne d'instruction éditable

struct InstructionRowView: View {
    let index: Int
    @Binding var instr: ZoneScript.Instruction
    let onDelete: () -> Void
    let onChange: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Numéro + indicateur couleur
            Text(String(format: "%02d", index))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 22, alignment: .trailing)

            RoundedRectangle(cornerRadius: 3)
                .fill(opcodeColor)
                .frame(width: 6, height: 22)

            // Sélecteur d'opcode
            opcodeMenu
                .frame(width: 140)

            Spacer(minLength: 0)

            // Champ d'argument (selon le type)
            if instr.argKind != .none {
                argEditor
            }

            // Supprimer
            Button(action: onDelete) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red.opacity(0.75))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    // MARK: Menu opcode

    private var opcodeMenu: some View {
        Menu(instr.name) {
            Section("Contrôle de flux") {
                ForEach(FireFlyOpcode.flowGroup, id: \.self) { op in
                    Button(FireFlyOpcode.name(for: op)) { applyOpcode(op) }
                }
            }
            Section("Dialogue") {
                ForEach(FireFlyOpcode.dialogGroup, id: \.self) { op in
                    Button(FireFlyOpcode.name(for: op)) { applyOpcode(op) }
                }
            }
            Section("Flags") {
                ForEach(FireFlyOpcode.flagGroup, id: \.self) { op in
                    Button(FireFlyOpcode.name(for: op)) { applyOpcode(op) }
                }
            }
            Section("Variables") {
                ForEach(FireFlyOpcode.variableGroup, id: \.self) { op in
                    Button(FireFlyOpcode.name(for: op)) { applyOpcode(op) }
                }
            }
            Section("Combat") {
                ForEach(FireFlyOpcode.battleGroup, id: \.self) { op in
                    Button(FireFlyOpcode.name(for: op)) { applyOpcode(op) }
                }
            }
            Section("Effets") {
                ForEach(FireFlyOpcode.effectGroup, id: \.self) { op in
                    Button(FireFlyOpcode.name(for: op)) { applyOpcode(op) }
                }
            }
            Section("Autre") {
                ForEach(FireFlyOpcode.miscGroup, id: \.self) { op in
                    Button(FireFlyOpcode.name(for: op)) { applyOpcode(op) }
                }
            }
        }
        .menuStyle(.borderlessButton)
    }

    // MARK: Champ argument type-aware

    @ViewBuilder
    private var argEditor: some View {
        HStack(spacing: 4) {
            Image(systemName: instr.argKind.sfSymbol)
                .imageScale(.small)
                .foregroundStyle(.secondary)
                .frame(width: 14)

            TextField(argPlaceholder, text: argBinding)
                .textFieldStyle(.roundedBorder)
                .frame(width: argFieldWidth)
                .font(.system(.body, design: .monospaced))
                .multilineTextAlignment(.trailing)
        }
    }

    private var argBinding: Binding<String> {
        Binding(
            get: { argDisplayText },
            set: { text in
                if let val = parseArgText(text) {
                    instr.setArg(val)
                    onChange()
                }
            }
        )
    }

    private var argDisplayText: String {
        let a = instr.arg
        switch instr.argKind {
        case .flagID, .itemID:
            return String(format: "0x%04X", UInt32(bitPattern: a) & 0xFFFF)
        case .dialogID, .trainerID, .count:
            return String(a)
        case .delta:
            return a >= 0 ? "+\(a)" : "\(a)"
        case .raw, .varID:
            return String(format: "0x%X", UInt32(bitPattern: a))
        case .none:
            return ""
        }
    }

    private var argPlaceholder: String {
        switch instr.argKind {
        case .flagID, .itemID: return "0x0000"
        case .dialogID:        return "0"
        case .delta:           return "±0"
        default:               return "0"
        }
    }

    private var argFieldWidth: CGFloat {
        switch instr.argKind {
        case .flagID, .itemID: return 68
        case .delta:           return 52
        default:               return 60
        }
    }

    private func parseArgText(_ text: String) -> Int32? {
        let s = text.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "+", with: "")
        if s.hasPrefix("0x") || s.hasPrefix("0X") {
            guard let u = UInt32(s.dropFirst(2), radix: 16) else { return nil }
            return Int32(bitPattern: u)
        }
        return Int32(s)
    }

    // MARK: Helpers

    private func applyOpcode(_ op: UInt32) {
        instr.setOpcode(op)
        onChange()
    }

    private var opcodeColor: Color {
        if instr.isReturn     { return .red }
        if instr.isShowMessage{ return .green }
        if instr.isJump       { return .orange }
        if instr.isFlag       { return .purple }
        if instr.opcode == 0x02E { return .blue }
        if instr.isUnknown    { return .secondary.opacity(0.4) }
        return .secondary.opacity(0.2)
    }
}
