import SwiftUI

// MARK: — Constructeur de field scripts (a/0/1/2)

struct ScriptBuilderView: View {
    @EnvironmentObject var controller: ProjectController

    // Données chargées
    @State private var fieldScripts: [(index: Int, script: FieldScript)] = []
    @State private var isLoading = false
    @State private var loadError: String?

    // Sélection
    @State private var selectedZoneIndex: Int?
    @State private var selectedSubIndex: Int?

    // Édition en cours
    @State private var editableScript: FieldScript?
    @State private var editableInstructions: [ZoneScript.Instruction] = []
    @State private var isDirty = false

    // Sauvegarde
    @State private var isSaving = false
    @State private var saveMessage: String?
    @State private var saveIsError = false

    // Sheets
    @State private var showAddInstructionSheet = false
    @State private var showTemplateSheet = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Chargement des field scripts…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = loadError {
                errorView(err)
            } else {
                HStack(spacing: 0) {
                    zoneListColumn.frame(width: 160)
                    Divider()
                    subScriptColumn.frame(width: 200)
                    Divider()
                    instructionColumn.frame(maxWidth: .infinity)
                }
            }
        }
        .task { await loadAllFieldScripts() }
    }

    // MARK: — Colonne 1 : zones

    private var zoneListColumn: some View {
        VStack(spacing: 0) {
            columnHeader("Zones", icon: "map.fill", count: fieldScripts.count)

            List(fieldScripts, id: \.index, selection: $selectedZoneIndex) { item in
                HStack(spacing: 6) {
                    Text(String(format: "%03d", item.index))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("\(item.script.subScripts.count)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .tag(item.index)
            }
            .listStyle(.sidebar)
        }
        .onChange(of: selectedZoneIndex) { _, idx in
            selectedSubIndex = nil
            editableInstructions = []
            isDirty = false
            saveMessage = nil
            if let i = idx {
                editableScript = fieldScripts.first(where: { $0.index == i })?.script
            } else {
                editableScript = nil
            }
        }
    }

    // MARK: — Colonne 2 : sub-scripts

    @ViewBuilder
    private var subScriptColumn: some View {
        VStack(spacing: 0) {
            columnHeader("Sub-scripts", icon: "doc.text.fill",
                         count: editableScript?.subScripts.count ?? 0)

            if let script = editableScript {
                List(script.subScripts, id: \.id, selection: $selectedSubIndex) { sub in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(String(format: "#%02d", sub.id))
                                .font(.system(.callout, design: .monospaced))
                                .fontWeight(.semibold)
                            subScriptBadge(sub)
                        }
                        Text("\(sub.instructions.count) instr.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                    .tag(sub.id)
                }
                .listStyle(.sidebar)

                Divider()

                Button {
                    addSubScript()
                } label: {
                    Label("Nouveau sub-script", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(8)
            } else {
                ContentUnavailableView("Sélectionnez une zone", systemImage: "map")
            }
        }
        .onChange(of: selectedSubIndex) { _, newID in
            guard let script = editableScript, let id = newID,
                  let sub = script.subScripts.first(where: { $0.id == id }) else {
                editableInstructions = []
                return
            }
            editableInstructions = sub.instructions
            isDirty = false
            saveMessage = nil
        }
    }

    @ViewBuilder
    private func subScriptBadge(_ sub: ZoneScript.SubScript) -> some View {
        if sub.instructions.contains(where: \.isShowMessage) {
            Label("Dialogue", systemImage: "text.bubble.fill")
                .font(.caption2).foregroundStyle(.green)
        }
        if sub.instructions.contains(where: \.isFlag) {
            Label("Flag", systemImage: "flag.fill")
                .font(.caption2).foregroundStyle(.purple)
        }
    }

    // MARK: — Colonne 3 : instructions

    @ViewBuilder
    private var instructionColumn: some View {
        if editableScript != nil, let subID = selectedSubIndex,
           let sub = editableScript?.subScripts.first(where: { $0.id == subID }) {
            VStack(spacing: 0) {
                instructionHeader(sub: sub)
                Divider()
                instructionToolbar
                Divider()
                instructionList
            }
        } else {
            ContentUnavailableView(
                "Sélectionnez un sub-script",
                systemImage: "doc.text",
                description: Text("Choisissez une zone et un sub-script pour éditer les instructions FireFly.")
            )
        }
    }

    private func instructionHeader(sub: ZoneScript.SubScript) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "terminal.fill").foregroundStyle(.indigo)
            VStack(alignment: .leading, spacing: 1) {
                Text("Sub-script #\(sub.id)").fontWeight(.semibold)
                Text("\(editableInstructions.count) instructions")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if isDirty {
                Label("Modifié", systemImage: "pencil.circle.fill")
                    .font(.callout).foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.regularMaterial)
    }

    private var instructionToolbar: some View {
        HStack(spacing: 10) {
            Button { showAddInstructionSheet = true } label: {
                Label("Ajouter", systemImage: "plus.circle")
            }
            .buttonStyle(.bordered)
            .sheet(isPresented: $showAddInstructionSheet) {
                AddInstructionSheet { instr in
                    editableInstructions.append(instr)
                    isDirty = true
                }
            }

            Button { showTemplateSheet = true } label: {
                Label("Modèles", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .sheet(isPresented: $showTemplateSheet) {
                TemplateSheet { template in
                    editableInstructions.append(contentsOf: template)
                    isDirty = true
                }
            }

            Spacer()

            if let msg = saveMessage {
                Label(msg, systemImage: saveIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(saveIsError ? .red : .green)
                    .font(.callout)
            }

            Button {
                Task { await saveCurrentSubScript() }
            } label: {
                if isSaving { ProgressView().scaleEffect(0.7) }
                else { Label("Sauvegarder", systemImage: "square.and.arrow.down") }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSaving || !isDirty)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.background)
    }

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

    // MARK: — Helpers UI

    private func columnHeader(_ title: String, icon: String, count: Int) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(.secondary)
                Text(title).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                Spacer()
                Text("\(count)").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(.regularMaterial)
            Divider()
        }
    }

    private func errorView(_ msg: String) -> some View {
        ContentUnavailableView {
            Label("Erreur", systemImage: "xmark.circle.fill").foregroundStyle(.red)
        } description: {
            Text(msg)
        } actions: {
            Button("Réessayer") { Task { await loadAllFieldScripts() } }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: — Chargement

    private func loadAllFieldScripts() async {
        guard let project = controller.project else { return }
        isLoading = true; loadError = nil; fieldScripts = []

        do {
            let garc = try await project.garc(at: "a/0/1/2")
            var loaded: [(index: Int, script: FieldScript)] = []
            for entry in garc.entries {
                guard let sub = entry.subFiles.first else { continue }
                let data = LZ11Decompressor.decompressIfNeeded(sub.rawData)
                if let script = FieldScript.parse(from: data, zoneIndex: entry.id) {
                    loaded.append((index: entry.id, script: script))
                }
            }
            fieldScripts = loaded
        } catch {
            loadError = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: — Ajout sub-script

    private func addSubScript() {
        editableScript?.addSubScript()
        // Synchroniser dans la liste principale
        if let zoneIdx = selectedZoneIndex,
           let idx = fieldScripts.firstIndex(where: { $0.index == zoneIdx }),
           let script = editableScript {
            fieldScripts[idx] = (index: zoneIdx, script: script)
        }
        isDirty = true
    }

    // MARK: — Sauvegarde

    private func saveCurrentSubScript() async {
        guard let project = controller.project,
              let zoneIdx = selectedZoneIndex,
              let subID = selectedSubIndex,
              var script = editableScript else { return }

        isSaving = true; saveMessage = nil

        do {
            // Mettre à jour les instructions dans le script
            if let subIdx = script.subScripts.firstIndex(where: { $0.id == subID }) {
                script.subScripts[subIdx] = ZoneScript.SubScript(
                    id: subID,
                    byteOffset: script.subScripts[subIdx].byteOffset,
                    instructions: editableInstructions
                )
            }

            let encodedData = script.encode()
            var garc = try await project.garc(at: "a/0/1/2")

            // Vérifier si l'entrée était compressée
            let wasCompressed = garc.entries.first(where: { $0.id == zoneIdx })
                .flatMap { $0.subFiles.first }
                .map { LZ11Decompressor.isLZ11($0.rawData) } ?? false
            let finalData = wasCompressed ? LZ11Decompressor.compress(encodedData) : encodedData

            garc.updateSubFile(entry: zoneIdx, sub: 0, data: finalData)
            try project.writeGARC(garc, at: "a/0/1/2")

            // Mettre à jour le cache local
            editableScript = script
            if let idx = fieldScripts.firstIndex(where: { $0.index == zoneIdx }) {
                fieldScripts[idx] = (index: zoneIdx, script: script)
            }

            isDirty = false; saveIsError = false
            saveMessage = "Sauvegardé"
        } catch {
            saveIsError = true
            saveMessage = error.localizedDescription
        }

        isSaving = false
    }
}

// MARK: — Sheet : Ajouter une instruction

private struct AddInstructionSheet: View {
    let onAdd: (ZoneScript.Instruction) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedOpcode: UInt32 = 0x02E
    @State private var argText: String = "0"

    var body: some View {
        VStack(spacing: 0) {
            Text("Ajouter une instruction").font(.headline).padding()
            Divider()

            Form {
                Section("Opcode") {
                    opcodeGroupPicker("Contrôle de flux", group: FireFlyOpcode.flowGroup)
                    opcodeGroupPicker("Dialogue",         group: FireFlyOpcode.dialogGroup)
                    opcodeGroupPicker("Flags",            group: FireFlyOpcode.flagGroup)
                    opcodeGroupPicker("Variables",        group: FireFlyOpcode.variableGroup)
                    opcodeGroupPicker("Combat",           group: FireFlyOpcode.battleGroup)
                    opcodeGroupPicker("Effets",           group: FireFlyOpcode.effectGroup)
                    opcodeGroupPicker("Autre",            group: FireFlyOpcode.miscGroup)
                }
                if FireFlyOpcode.argKind(for: selectedOpcode) != .none {
                    Section("Argument") {
                        TextField("Valeur (hex ou décimal)", text: $argText)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Button("Annuler") { dismiss() }
                Spacer()
                Button("Ajouter") {
                    let arg = parseArg(argText)
                    onAdd(.make(opcode: selectedOpcode, arg: arg))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 420, height: 480)
    }

    @ViewBuilder
    private func opcodeGroupPicker(_ label: String, group: [UInt32]) -> some View {
        Picker(label, selection: $selectedOpcode) {
            ForEach(group, id: \.self) { op in
                Text(FireFlyOpcode.name(for: op)).tag(op)
            }
        }
    }

    private func parseArg(_ text: String) -> Int32 {
        let s = text.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "+", with: "")
        if s.hasPrefix("0x") || s.hasPrefix("0X") {
            if let u = UInt32(s.dropFirst(2), radix: 16) { return Int32(bitPattern: u) }
        }
        return Int32(s) ?? 0
    }
}

// MARK: — Sheet : Gabarits de scripts

private struct TemplateSheet: View {
    let onApply: ([ZoneScript.Instruction]) -> Void
    @Environment(\.dismiss) private var dismiss

    private let templates: [(name: String, instructions: [ZoneScript.Instruction])] = [
        ("Dialogue simple",
         [.make(opcode: 0x02E),
          .make(opcode: 0x05A, arg: 0),
          .make(opcode: 0x05B),
          .make(opcode: 0x05C),
          .make(opcode: 0x030)]),
        ("Fade + dialogue",
         [.make(opcode: 0x02E),
          .make(opcode: 0x07B),
          .make(opcode: 0x05A, arg: 0),
          .make(opcode: 0x05B),
          .make(opcode: 0x05C),
          .make(opcode: 0x07C),
          .make(opcode: 0x030)]),
        ("Cinématique complète",
         [.make(opcode: 0x02E),
          .make(opcode: 0x07B),
          .make(opcode: 0x090, arg: 0),
          .make(opcode: 0x05A, arg: 0),
          .make(opcode: 0x05B),
          .make(opcode: 0x05C),
          .make(opcode: 0x05D, arg: 30),
          .make(opcode: 0x07C),
          .make(opcode: 0x030)]),
        ("Condition flag (If/JE)",
         [.make(opcode: 0x02E),
          .make(opcode: 0x061, arg: 0),
          .make(opcode: 0x082, arg: 1),
          .make(opcode: 0x081, arg: 2),
          .make(opcode: 0x030)]),
        ("SetFlag post-game Seko",
         [.make(opcode: 0x02E),
          .make(opcode: 0x062, arg: 0x0900),
          .make(opcode: 0x030)]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Text("Gabarits de scripts").font(.headline).padding()
            Divider()
            List(templates, id: \.name) { tmpl in
                Button {
                    onApply(tmpl.instructions)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tmpl.name).fontWeight(.medium)
                        Text("\(tmpl.instructions.count) instructions : " +
                             tmpl.instructions.map { FireFlyOpcode.name(for: $0.opcode) }.joined(separator: " → "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            Divider()
            HStack {
                Spacer()
                Button("Fermer") { dismiss() }
            }
            .padding()
        }
        .frame(width: 480, height: 360)
    }
}
