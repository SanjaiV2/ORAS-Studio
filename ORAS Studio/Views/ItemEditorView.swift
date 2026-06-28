import SwiftUI

// MARK: — Éditeur d'objets ORAS (propriétés + boutiques)

struct ItemEditorView: View {
    @EnvironmentObject var controller: ProjectController

    @State private var items: [ItemData] = []
    @State private var selectedID: Int?
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var searchText = ""
    @State private var selectedCategory: ItemData.DisplayCategory = .all
    @State private var isSaving = false
    @State private var saveStatus: SaveStatus?
    @State private var isDirty = false
    @State private var loadedGARC: GARCFile?
    @State private var loadedGARCPath: String = "a/1/9/7"

    enum SaveStatus: Equatable {
        case success
        case failure(String)
    }

    // GARC des données d'objets ORAS (776 entrées × 36 bytes, version 0x0400)
    private let garcCandidates = ["a/1/9/7"]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            Group {
                if isLoading {
                    ProgressView("Chargement des objets…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = loadError {
                    errorView(err)
                } else if items.isEmpty {
                    ContentUnavailableView(
                        "Aucun objet chargé",
                        systemImage: "bag.badge.questionmark",
                        description: Text("Le GARC d'objets (a/1/9/7) ne contient aucune entrée valide.")
                    )
                } else {
                    HStack(spacing: 0) {
                        itemListPanel.frame(width: 240)
                        Divider()
                        itemDetailPanel.frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .task { await loadItems() }
    }

    // MARK: — Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Rechercher un objet…", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            }
            Spacer()
            Text("\(filteredItems.count) / \(items.count)")
                .font(.callout).foregroundStyle(.secondary)
            if isDirty {
                Label("Modifié", systemImage: "pencil.circle.fill")
                    .foregroundStyle(.orange).font(.callout)
            }
            if let status = saveStatus {
                switch status {
                case .success:
                    Label("Sauvegardé", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green).font(.callout).transition(.opacity)
                case .failure(let msg):
                    Label(msg, systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red).font(.callout).help(msg)
                }
            }
            Button { Task { await saveItems() } } label: {
                Label(isSaving ? "Sauvegarde…" : "Sauvegarder",
                      systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSaving || !isDirty)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.regularMaterial)
    }

    // MARK: — Panneau gauche : catégories + liste

    private var itemListPanel: some View {
        VStack(spacing: 0) {
            categoryPicker
            Divider()
            if filteredItems.isEmpty {
                ContentUnavailableView(
                    "Aucun objet",
                    systemImage: "bag.badge.questionmark"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredItems, selection: $selectedID) { item in
                    ItemListRow(item: item).tag(item.id)
                }
                .listStyle(.sidebar)
            }
            Divider()
            // Barre bas : ajouter
            HStack(spacing: 8) {
                Button { addItem() } label: {
                    Label("Dupliquer", systemImage: "plus.square.on.square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(selectedID == nil)

                Button { resetSelectedItem() } label: {
                    Label("Réinitialiser", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(selectedID == nil)
            }
            .padding(8)
            .background(.regularMaterial)
        }
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(ItemData.DisplayCategory.allCases) { cat in
                    CategoryChip(
                        cat: cat,
                        isSelected: selectedCategory == cat,
                        count: cat == .all ? items.count : items.filter { $0.displayCategory == cat }.count
                    ) {
                        selectedCategory = cat
                        selectedID = nil
                    }
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
        }
        .background(.regularMaterial)
    }

    // MARK: — Panneau droit : détail

    @ViewBuilder
    private var itemDetailPanel: some View {
        if let id = selectedID, let binding = itemBinding(id: id) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    itemHeader(item: binding.wrappedValue)
                    Divider()
                    generalSection(binding: binding)
                    fieldSection(binding: binding)
                    battleSection(binding: binding)
                    holdSection(binding: binding)
                    rawSection(data: binding.wrappedValue.rawData)
                }
                .padding(20)
            }
        } else {
            ContentUnavailableView(
                "Sélectionnez un objet",
                systemImage: "bag",
                description: Text("Choisissez un objet dans la liste pour modifier ses propriétés.")
            )
        }
    }

    // En-tête
    private func itemHeader(item: ItemData) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(item.displayCategory.color.opacity(0.15))
                    .frame(width: 56, height: 56)
                Image(systemName: item.displayCategory.icon)
                    .font(.system(size: 24))
                    .foregroundStyle(item.displayCategory.color)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.title2).bold()
                HStack(spacing: 8) {
                    Text(String(format: "ID #%04d", item.id))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    if item.price > 0 {
                        Label(String(format: "%d ₽", Int(item.price) * 10),
                              systemImage: "dollarsign.circle")
                            .font(.caption).foregroundStyle(.orange)
                    } else {
                        Text("Invendable")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
                Text(item.displayCategory.rawValue)
                    .font(.caption2)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(item.displayCategory.color.opacity(0.15))
                    .foregroundStyle(item.displayCategory.color)
                    .clipShape(.capsule)
            }
            Spacer()
        }
    }

    // Section Général
    private func generalSection(binding: Binding<ItemData>) -> some View {
        GroupBox {
            VStack(spacing: 12) {
                // Prix
                HStack {
                    Label("Prix (raw)", systemImage: "dollarsign.circle")
                    Spacer()
                    Stepper {
                        Text("\(binding.wrappedValue.price)  →  \(Int(binding.wrappedValue.price) * 10) ₽")
                            .font(.system(.callout, design: .monospaced))
                    } onIncrement: {
                        if binding.wrappedValue.price < 9990 {
                            binding.wrappedValue.price += 10
                            isDirty = true
                        }
                    } onDecrement: {
                        if binding.wrappedValue.price >= 10 {
                            binding.wrappedValue.price -= 10
                            isDirty = true
                        }
                    }
                }
                Divider()
                // Poche
                HStack {
                    Label("Poche du sac", systemImage: "bag.fill")
                    Spacer()
                    Picker("", selection: binding.bagPocket) {
                        Text("0 – Général").tag(UInt8(0))
                        Text("1 – Objets tenus").tag(UInt8(1))
                        Text("2 – Divers").tag(UInt8(2))
                        Text("3 – PP / Soins").tag(UInt8(3))
                        Text("4 – Balls").tag(UInt8(4))
                        Text("5 – Courrier").tag(UInt8(5))
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 170)
                    .onChange(of: binding.wrappedValue.bagPocket) { _, _ in isDirty = true }
                }
                Divider()
                // Consommable
                HStack {
                    Label("Consommable", systemImage: "flame.fill")
                    Spacer()
                    Toggle("", isOn: Binding(
                        get:  { binding.wrappedValue.consumable != 0 },
                        set:  { binding.wrappedValue.consumable = $0 ? 1 : 0; isDirty = true }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
            }
            .padding(.vertical, 4)
        } label: {
            Label("Général", systemImage: "info.circle.fill").foregroundStyle(.secondary)
        }
    }

    // Section Terrain
    private func fieldSection(binding: Binding<ItemData>) -> some View {
        GroupBox {
            byteRow("Effet terrain", icon: "figure.walk",
                    value: binding.wrappedValue.fieldEffect) { v in
                binding.wrappedValue.fieldEffect = v; isDirty = true
            }
            .padding(.vertical, 4)
        } label: {
            Label("Terrain (overworld)", systemImage: "map.fill").foregroundStyle(.secondary)
        }
    }

    // Section Combat
    private func battleSection(binding: Binding<ItemData>) -> some View {
        GroupBox {
            VStack(spacing: 10) {
                byteRow("Effet combat",    icon: "bolt.fill",
                        value: binding.wrappedValue.battleEffect) { v in
                    binding.wrappedValue.battleEffect = v; isDirty = true
                }
                Divider()
                byteRow("Puissance",       icon: "gauge.open.with.lines.needle.33percent",
                        value: binding.wrappedValue.battlePower) { v in
                    binding.wrappedValue.battlePower = v; isDirty = true
                }
                Divider()
                byteRow("Type de ciblage", icon: "scope",
                        value: binding.wrappedValue.battleType) { v in
                    binding.wrappedValue.battleType = v; isDirty = true
                }
                Divider()
                byteRow("Probabilité",     icon: "percent",
                        value: binding.wrappedValue.battleChance) { v in
                    binding.wrappedValue.battleChance = v; isDirty = true
                }
                Divider()
                byteRow("Usage combat",    icon: "hand.raised.fill",
                        value: binding.wrappedValue.battleUsage) { v in
                    binding.wrappedValue.battleUsage = v; isDirty = true
                }
            }
            .padding(.vertical, 4)
        } label: {
            Label("Combat", systemImage: "bolt.shield.fill").foregroundStyle(.secondary)
        }
    }

    // Section Objet tenu
    private func holdSection(binding: Binding<ItemData>) -> some View {
        GroupBox {
            VStack(spacing: 10) {
                byteRow("Effet tenu",     icon: "hand.point.up.left.fill",
                        value: binding.wrappedValue.holdEffect) { v in
                    binding.wrappedValue.holdEffect = v; isDirty = true
                }
                Divider()
                byteRow("Paramètre tenu", icon: "slider.horizontal.3",
                        value: binding.wrappedValue.holdParam) { v in
                    binding.wrappedValue.holdParam = v; isDirty = true
                }
            }
            .padding(.vertical, 4)
        } label: {
            Label("Objet tenu (held)", systemImage: "hand.point.up.left").foregroundStyle(.secondary)
        }
    }

    // Hex dump brut
    private func rawSection(data: Data) -> some View {
        GroupBox {
            let rows = stride(from: 0, to: min(data.count, 64), by: 16).map { start -> String in
                let end = min(start + 16, data.count)
                let hex = data[start..<end].map { String(format: "%02X", $0) }.joined(separator: " ")
                return String(format: "%04X: %@", start, hex)
            }
            VStack(alignment: .leading, spacing: 2) {
                ForEach(rows, id: \.self) { row in
                    Text(row)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        } label: {
            Label("Données brutes (hex)", systemImage: "doc.text.below.ecg.fill")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: — Composant générique byte row

    private func byteRow(_ label: String, icon: String,
                          value: UInt8, onSet: @escaping (UInt8) -> Void) -> some View {
        HStack {
            Label(label, systemImage: icon)
            Spacer()
            Stepper {
                Text(String(format: "0x%02X  (%d)", value, value))
                    .font(.system(.callout, design: .monospaced))
                    .frame(width: 90, alignment: .trailing)
            } onIncrement: {
                if value < 255 { onSet(value + 1) }
            } onDecrement: {
                if value > 0   { onSet(value - 1) }
            }
        }
    }

    // MARK: — Erreur

    private func errorView(_ msg: String) -> some View {
        ContentUnavailableView {
            Label("Erreur de chargement", systemImage: "xmark.circle.fill").foregroundStyle(.red)
        } description: { Text(msg) } actions: {
            Button("Réessayer") { Task { await loadItems() } }.buttonStyle(.borderedProminent)
        }
    }

    // MARK: — Computed

    private var filteredItems: [ItemData] {
        var list = items
        if selectedCategory != .all {
            list = list.filter { $0.displayCategory == selectedCategory }
        }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            list = list.filter {
                $0.name.lowercased().contains(q) ||
                String($0.id).contains(q)
            }
        }
        return list
    }

    private func itemBinding(id: Int) -> Binding<ItemData>? {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return nil }
        return Binding(get: { items[idx] }, set: { items[idx] = $0 })
    }

    // MARK: — Actions

    private func addItem() {
        guard let id = selectedID,
              let source = items.first(where: { $0.id == id }) else { return }
        let newID = (items.map(\.id).max() ?? 0) + 1
        var dup = source.duplicated(newID: newID)
        dup.name = String(format: "Objet %04d", newID)
        items.append(dup)
        selectedID = newID
        isDirty = true
    }

    private func resetSelectedItem() {
        guard let id = selectedID,
              let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let originalRaw = Data(repeating: 0, count: max(items[idx].rawData.count, ItemData.strideSize))
        if let reset = ItemData.parse(index: id, data: originalRaw, name: items[idx].name) {
            items[idx] = reset
            isDirty = true
        }
    }

    // MARK: — Chargement

    private func loadItems() async {
        guard let project = controller.project else { return }
        isLoading = true; loadError = nil; items = []; loadedGARC = nil

        // Noms : banque 114 de a/0/7/3 (FR, 776 lignes confirmées)
        var itemNames: [Int: String] = [:]
        if let textGARC = try? await project.garc(at: "a/0/7/3"),
           let sub = textGARC.entries.first(where: { $0.id == 114 })?.subFiles.first {
            let raw = LZ11Decompressor.decompressIfNeeded(sub.rawData)
            if let lines = try? PPTXTDecoder.decode(raw) {
                for line in lines where !line.text.isEmpty {
                    itemNames[line.id] = line.text
                }
            }
        }

        // Essai des chemins candidats du GARC d'objets
        var lastError: Error?
        for path in garcCandidates {
            do {
                let garc = try await project.garc(at: path)
                let parsed = garc.entries.compactMap { entry -> ItemData? in
                    guard let sub = entry.subFiles.first else { return nil }
                    return ItemData.parse(index: entry.id,
                                         data: sub.rawData,
                                         name: itemNames[entry.id] ?? "")
                }
                if !parsed.isEmpty {
                    loadedGARC = garc
                    loadedGARCPath = path
                    items = parsed
                    isLoading = false
                    return
                }
            } catch {
                lastError = error
            }
        }
        loadError = lastError?.localizedDescription
            ?? "GARC d'objets introuvable (a/1/9/7) — ouvrir le dossier romfs complet"
        isLoading = false
    }

    // MARK: — Sauvegarde

    private func saveItems() async {
        guard let project = controller.project, var garc = loadedGARC else { return }
        isSaving = true; saveStatus = nil
        do {
            for item in items {
                garc.updateSubFile(entry: item.id, sub: 0, data: item.encode())
            }
            try project.writeGARC(garc, at: loadedGARCPath)
            loadedGARC = garc
            isDirty = false
            withAnimation { saveStatus = .success }
        } catch {
            withAnimation { saveStatus = .failure(error.localizedDescription) }
        }
        isSaving = false
    }
}

// MARK: — Chip de catégorie

private struct CategoryChip: View {
    let cat: ItemData.DisplayCategory
    let isSelected: Bool
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: cat.icon)
                    .imageScale(.small)
                    .foregroundStyle(isSelected ? cat.color : .secondary)
                Text(cat.rawValue)
                    .font(.caption).fontWeight(isSelected ? .semibold : .regular)
                if count > 0 && cat != .all {
                    Text("\(count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(isSelected ? cat.color.opacity(0.15) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? cat.color.opacity(0.4) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: — Ligne de liste d'objet

private struct ItemListRow: View {
    let item: ItemData

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.displayCategory.icon)
                .imageScale(.small)
                .foregroundStyle(item.displayCategory.color)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.callout).lineLimit(1)
                Text(String(format: "#%04d", item.id))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if item.price > 0 {
                Text("\(Int(item.price) * 10)₽")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
