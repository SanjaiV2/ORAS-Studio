import SwiftUI

// MARK: — Modèle dresseur (a/0/3/8)

struct TrainerData: Identifiable {
    let id: Int                  // index dans le GARC
    var aiFlags: UInt16          // comportement IA (bitfield)
    var moneyFactor: UInt8       // multiplicateur de récompense
    var battleType: UInt8        // 0=simple, 1=double
    var items: [UInt16]          // jusqu'à 4 items de combat
    var partyCount: UInt16       // nombre de Pokémon dans l'équipe
    var rawData: Data            // octets bruts pour réécriture

    var isDouble: Bool { battleType != 0 }
    var displayName: String { String(format: "Dresseur %04d", id) }

    var aiDescription: String {
        var parts: [String] = []
        if aiFlags & 0x0001 != 0 { parts.append("Basique") }
        if aiFlags & 0x0002 != 0 { parts.append("Statistiques") }
        if aiFlags & 0x0004 != 0 { parts.append("Changement") }
        if aiFlags & 0x0008 != 0 { parts.append("Aléatoire") }
        if aiFlags & 0x0010 != 0 { parts.append("Légendaire") }
        if aiFlags & 0x0040 != 0 { parts.append("Trap") }
        if aiFlags & 0x0080 != 0 { parts.append("Cautious") }
        if aiFlags & 0x0100 != 0 { parts.append("Smart") }
        return parts.isEmpty ? "Aucune IA" : parts.joined(separator: ", ")
    }

    static func parse(index: Int, data: Data) -> TrainerData? {
        guard data.count >= 6 else { return nil }
        func u16(_ o: Int) -> UInt16 {
            guard o + 1 < data.count else { return 0 }
            return data.withUnsafeBytes { $0.load(fromByteOffset: o, as: UInt16.self) }
        }
        let ai        = u16(0)
        let money     = data.count > 2 ? data[2] : 0
        let battleT   = data.count > 3 ? data[3] : 0
        var items: [UInt16] = []
        if data.count >= 12 {
            for i in 0..<4 { items.append(u16(4 + i * 2)) }
        }
        let partyCount = data.count >= 10 ? u16(8) : 0

        return TrainerData(
            id: index,
            aiFlags: ai,
            moneyFactor: money,
            battleType: battleT,
            items: items,
            partyCount: partyCount,
            rawData: data
        )
    }
}

// MARK: — Vue principale

struct TrainerEditorView: View {
    @EnvironmentObject var controller: ProjectController

    @State private var trainers: [TrainerData] = []
    @State private var selectedID: Int?
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var searchText = ""
    @State private var isSaving = false
    @State private var saveStatus: SaveStatus?

    enum SaveStatus: Equatable {
        case success
        case failure(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if isLoading {
                ProgressView("Chargement des dresseurs…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = loadError {
                errorView(err)
            } else {
                HSplitView {
                    trainerList.frame(minWidth: 180, maxWidth: 220)
                    trainerDetail
                }
            }
        }
        .task { await loadTrainers() }
    }

    // MARK: — Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Rechercher dresseur…", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            }
            Spacer()
            if let status = saveStatus {
                Group {
                    switch status {
                    case .success:
                        Label("Sauvegardé", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    case .failure(let msg):
                        Label(msg, systemImage: "xmark.circle.fill").foregroundStyle(.red)
                    }
                }.font(.callout).transition(.opacity)
            }
            Button {
                Task { await saveSelectedTrainer() }
            } label: {
                Label(isSaving ? "Sauvegarde…" : "Sauvegarder",
                      systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSaving || selectedID == nil)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.regularMaterial)
    }

    // MARK: — Liste des dresseurs

    private var filteredTrainers: [TrainerData] {
        if searchText.isEmpty { return trainers }
        let q = searchText.lowercased()
        return trainers.filter { String($0.id).contains(q) }
    }

    private var trainerList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Dresseurs")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(trainers.count)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(.regularMaterial)
            Divider()

            List(filteredTrainers, selection: $selectedID) { trainer in
                HStack(spacing: 8) {
                    Text(String(format: "%04d", trainer.id))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if trainer.isDouble {
                        Image(systemName: "person.2.fill")
                            .imageScale(.small)
                            .foregroundStyle(.orange)
                    }
                    Text("\(trainer.partyCount)×")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .tag(trainer.id)
            }
            .listStyle(.sidebar)
        }
    }

    // MARK: — Détail dresseur

    @ViewBuilder
    private var trainerDetail: some View {
        if let idx = selectedID,
           let binding = trainerBinding(id: idx) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // En-tête
                    HStack {
                        Image(systemName: "person.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading) {
                            Text(String(format: "Dresseur %04d", idx))
                                .font(.title2).bold()
                            Text(binding.wrappedValue.aiDescription)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    Divider()

                    // Paramètres de combat
                    GroupBox("Combat") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("Type de combat", systemImage: "bolt.fill")
                                Spacer()
                                Picker("", selection: binding.battleType) {
                                    Text("Simple").tag(UInt8(0))
                                    Text("Double").tag(UInt8(1))
                                }
                                .pickerStyle(.segmented)
                                .frame(maxWidth: 180)
                            }
                            HStack {
                                Label("Facteur argent", systemImage: "dollarsign.circle")
                                Spacer()
                                Stepper(
                                    "\(binding.wrappedValue.moneyFactor)×",
                                    value: binding.moneyFactor,
                                    in: 1...20
                                )
                            }
                            HStack {
                                Label("Pokémon dans l'équipe", systemImage: "pawprint.fill")
                                Spacer()
                                Text("\(binding.wrappedValue.partyCount)")
                                    .foregroundStyle(.secondary)
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    // Flags IA
                    GroupBox("Intelligence Artificielle") {
                        AIFlagsEditor(aiFlags: binding.aiFlags)
                            .padding(.vertical, 4)
                    }

                    // Items de combat
                    GroupBox("Items de combat") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(0..<binding.wrappedValue.items.count, id: \.self) { i in
                                HStack {
                                    Text("Item \(i + 1)")
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    TextField("0",
                                              value: itemBinding(trainerID: idx, itemIndex: i),
                                              formatter: hexFormatter)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)
                                    .font(.system(.body, design: .monospaced))
                                }
                            }
                            Text("0 = aucun item · les autres valeurs = ID d'item ORAS")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity)
            }
        } else {
            ContentUnavailableView(
                "Sélectionnez un dresseur",
                systemImage: "person.fill",
                description: Text("Choisissez un dresseur dans la liste pour modifier ses paramètres.")
            )
        }
    }

    // MARK: — Erreur

    private func errorView(_ msg: String) -> some View {
        ContentUnavailableView {
            Label("Erreur", systemImage: "xmark.circle.fill").foregroundStyle(.red)
        } description: { Text(msg) } actions: {
            Button("Réessayer") { Task { await loadTrainers() } }.buttonStyle(.borderedProminent)
        }
    }

    // MARK: — Helpers

    private func trainerBinding(id: Int) -> Binding<TrainerData>? {
        guard let idx = trainers.firstIndex(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { trainers[idx] },
            set: { trainers[idx] = $0 }
        )
    }

    private func itemBinding(trainerID: Int, itemIndex: Int) -> Binding<UInt16> {
        Binding(
            get: {
                trainers.first(where: { $0.id == trainerID })?.items[safe: itemIndex] ?? 0
            },
            set: { newVal in
                guard let idx = trainers.firstIndex(where: { $0.id == trainerID }),
                      itemIndex < trainers[idx].items.count else { return }
                trainers[idx].items[itemIndex] = newVal
            }
        )
    }

    private let hexFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimum = 0; f.maximum = 65535
        return f
    }()

    // MARK: — Chargement

    private func loadTrainers() async {
        guard let project = controller.project else { return }
        isLoading = true; loadError = nil; trainers = []
        do {
            let garc = try await project.garc(at: "a/0/3/8")
            trainers = garc.entries.compactMap { entry -> TrainerData? in
                guard let sub = entry.subFiles.first else { return nil }
                return TrainerData.parse(index: entry.id, data: sub.rawData)
            }
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: — Sauvegarde

    private func saveSelectedTrainer() async {
        guard let project = controller.project,
              let id = selectedID,
              let trainer = trainers.first(where: { $0.id == id })
        else { return }

        isSaving = true; saveStatus = nil
        do {
            var garc = try await project.garc(at: "a/0/3/8")
            // Reconstruire les données binaires du dresseur
            let rawCount = max(16, trainer.rawData.count)
            var raw = Data(repeating: 0, count: rawCount)
            raw.withUnsafeMutableBytes { ptr in
                ptr.storeBytes(of: trainer.aiFlags,      toByteOffset: 0, as: UInt16.self)
                ptr.storeBytes(of: trainer.moneyFactor,  toByteOffset: 2, as: UInt8.self)
                ptr.storeBytes(of: trainer.battleType,   toByteOffset: 3, as: UInt8.self)
                for (i, item) in trainer.items.prefix(4).enumerated() {
                    ptr.storeBytes(of: item, toByteOffset: 4 + i * 2, as: UInt16.self)
                }
                if rawCount >= 10 {
                    ptr.storeBytes(of: trainer.partyCount, toByteOffset: 8, as: UInt16.self)
                }
            }
            garc.updateSubFile(entry: id, sub: 0, data: raw)
            try project.writeGARC(garc, at: "a/0/3/8")
            withAnimation { saveStatus = .success }
        } catch {
            withAnimation { saveStatus = .failure(error.localizedDescription) }
        }
        isSaving = false
    }
}

// MARK: — Éditeur de flags IA

private struct AIFlagsEditor: View {
    @Binding var aiFlags: UInt16

    private let flagDefs: [(bit: Int, label: String)] = [
        (0, "IA basique"),  (1, "Statistiques"),  (2, "Changement de Poké"),
        (3, "Aléatoire"),   (6, "Stratégie"),      (7, "Prudent"),
        (8, "Intelligent"), (9, "Expert"),          (12, "Légendaire"),
    ]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(flagDefs, id: \.bit) { flag in
                Toggle(flag.label, isOn: Binding(
                    get: { aiFlags & (1 << flag.bit) != 0 },
                    set: { on in
                        if on { aiFlags |= 1 << flag.bit }
                        else  { aiFlags &= ~(1 << flag.bit) }
                    }
                ))
                .toggleStyle(.checkbox)
                .font(.callout)
            }
        }
    }
}

// MARK: — Extension safe subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
