import SwiftUI

// MARK: — Onglets entités

private enum EntityTab: String, CaseIterable {
    case furniture = "Meubles"
    case npcs      = "NPCs"
    case warps     = "Warps"
    case triggers  = "Triggers"

    var icon: String {
        switch self {
        case .furniture: "cube.box.fill"
        case .npcs:      "person.fill"
        case .warps:     "arrow.triangle.2.circlepath"
        case .triggers:  "bolt.fill"
        }
    }
}

// MARK: — Éditeur d'entités de zone

struct EntityEditorView: View {
    @EnvironmentObject var controller: ProjectController

    // Données chargées
    @State private var zoneItems: [(index: Int, zoData: Data, wasCompressed: Bool)] = []
    @State private var isLoading = false
    @State private var loadError: String?

    // Sélection
    @State private var selectedZoneIndex: Int?
    @State private var selectedTab: EntityTab = .npcs
    @State private var selectedEntityID: UUID?

    // Entités éditables de la zone courante
    @State private var currentEntities: ZoneEntities?
    @State private var isDirty = false
    @State private var isSaving = false
    @State private var saveMessage: String?
    @State private var saveIsError = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Chargement des zones…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = loadError {
                errorView(err)
            } else {
                HStack(spacing: 0) {
                    zoneListColumn.frame(width: 180)
                    Divider()
                    entityListColumn
                    Divider()
                    entityDetailColumn.frame(minWidth: 280)
                }
            }
        }
        .task { await loadZones() }
    }

    // MARK: — Colonne 1 : liste des zones

    private var zoneListColumn: some View {
        VStack(spacing: 0) {
            columnHeader("Zones", icon: "map.fill", count: zoneItems.count)
            List(zoneItems, id: \.index, selection: $selectedZoneIndex) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(ZoneDictionary.label(for: item.index))
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                }
                .tag(item.index)
            }
            .listStyle(.sidebar)
        }
        .onChange(of: selectedZoneIndex) { _, newIdx in
            selectedEntityID = nil
            isDirty = false
            saveMessage = nil
            if let idx = newIdx {
                loadEntities(for: idx)
            } else {
                currentEntities = nil
            }
        }
    }

    // MARK: — Colonne 2 : liste des entités (avec onglets)

    @ViewBuilder
    private var entityListColumn: some View {
        VStack(spacing: 0) {
            if currentEntities != nil {
                // Barre d'outils supérieure
                HStack(spacing: 8) {
                    Picker("", selection: $selectedTab) {
                        ForEach(EntityTab.allCases, id: \.self) { tab in
                            Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    Spacer()

                    Button {
                        addEntity()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.bordered)
                    .help("Ajouter une entité")

                    Button {
                        removeSelectedEntity()
                    } label: {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.bordered)
                    .disabled(selectedEntityID == nil)
                    .help("Supprimer la sélection")
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(.regularMaterial)

                Divider()

                entityList
            } else {
                ContentUnavailableView("Sélectionnez une zone", systemImage: "map")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 200, maxWidth: 260)
        .onChange(of: selectedTab) { _, _ in selectedEntityID = nil }
    }

    @ViewBuilder
    private var entityList: some View {
        if let entities = currentEntities {
            switch selectedTab {
            case .furniture:
                List(entities.furniture, selection: $selectedEntityID) { f in
                    entityRow(icon: "cube.box.fill", color: .brown,
                               title: String(format: "Meuble #%04X", f.objID),
                               subtitle: "X:\(f.xPos) Y:\(f.yPos)  Script:\(f.scriptID)")
                    .tag(f.id)
                }
                .listStyle(.sidebar)

            case .npcs:
                List(entities.npcs, selection: $selectedEntityID) { n in
                    entityRow(icon: "person.fill", color: .blue,
                               title: String(format: "NPC #%04d (model %d)", n.npcID, n.modelID),
                               subtitle: "X:\(n.xPos) Y:\(n.yPos)  Flag:0x\(String(format: "%04X", n.spawnFlag))")
                    .tag(n.id)
                }
                .listStyle(.sidebar)

            case .warps:
                List(entities.warps, selection: $selectedEntityID) { w in
                    entityRow(icon: "arrow.triangle.2.circlepath", color: .purple,
                               title: "→ Zone \(ZoneDictionary.label(for: Int(w.destZone)))",
                               subtitle: "Warp \(w.destWarp)  X:\(w.xPos) Y:\(w.yPos)")
                    .tag(w.id)
                }
                .listStyle(.sidebar)

            case .triggers:
                List(entities.walkTriggers, selection: $selectedEntityID) { t in
                    entityRow(icon: "bolt.fill", color: .orange,
                               title: "Trigger → Script \(t.scriptIndex)",
                               subtitle: "X:\(t.xPos) Y:\(t.yPos)  \(t.width)×\(t.height)")
                    .tag(t.id)
                }
                .listStyle(.sidebar)
            }
        }
    }

    // MARK: — Colonne 3 : formulaire d'édition

    @ViewBuilder
    private var entityDetailColumn: some View {
        if let entities = currentEntities, let eid = selectedEntityID {
            VStack(spacing: 0) {
                saveBar
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch selectedTab {
                        case .furniture:
                            if let idx = entities.furniture.firstIndex(where: { $0.id == eid }) {
                                FurnitureForm(furniture: bindingFurniture(idx))
                            }
                        case .npcs:
                            if let idx = entities.npcs.firstIndex(where: { $0.id == eid }) {
                                NPCForm(npc: bindingNPC(idx))
                            }
                        case .warps:
                            if let idx = entities.warps.firstIndex(where: { $0.id == eid }) {
                                WarpForm(warp: bindingWarp(idx))
                            }
                        case .triggers:
                            if let idx = entities.walkTriggers.firstIndex(where: { $0.id == eid }) {
                                TriggerForm(trigger: bindingTrigger(idx))
                            }
                        }
                    }
                    .padding(16)
                }
            }
        } else {
            ContentUnavailableView(
                "Sélectionnez une entité",
                systemImage: "cursorarrow",
                description: Text("Choisissez une entité dans la liste pour l'éditer.")
            )
        }
    }

    private var saveBar: some View {
        HStack(spacing: 10) {
            if isDirty {
                Label("Modifié", systemImage: "pencil.circle.fill")
                    .font(.callout).foregroundStyle(.orange)
            }
            Spacer()
            if let msg = saveMessage {
                Label(msg, systemImage: saveIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(saveIsError ? .red : .green)
                    .font(.callout)
            }
            Button {
                Task { await saveZone() }
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
        .background(.regularMaterial)
    }

    // MARK: — Bindings sur les entités

    private func bindingFurniture(_ idx: Int) -> Binding<ZoneFurniture> {
        Binding(
            get: { currentEntities?.furniture[idx] ?? .makeDefault() },
            set: { currentEntities?.furniture[idx] = $0; isDirty = true }
        )
    }

    private func bindingNPC(_ idx: Int) -> Binding<ZoneNPC> {
        Binding(
            get: { currentEntities?.npcs[idx] ?? .makeDefault() },
            set: { currentEntities?.npcs[idx] = $0; isDirty = true }
        )
    }

    private func bindingWarp(_ idx: Int) -> Binding<ZoneWarp> {
        Binding(
            get: { currentEntities?.warps[idx] ?? .makeDefault() },
            set: { currentEntities?.warps[idx] = $0; isDirty = true }
        )
    }

    private func bindingTrigger(_ idx: Int) -> Binding<ZoneWalkTrigger> {
        Binding(
            get: { currentEntities?.walkTriggers[idx] ?? .makeDefault() },
            set: { currentEntities?.walkTriggers[idx] = $0; isDirty = true }
        )
    }

    // MARK: — Helpers UI

    private func entityRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(.callout)).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

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
            Label("Erreur de chargement", systemImage: "xmark.circle.fill").foregroundStyle(.red)
        } description: {
            Text(msg)
        } actions: {
            Button("Réessayer") { Task { await loadZones() } }.buttonStyle(.borderedProminent)
        }
    }

    // MARK: — Chargement

    private func loadZones() async {
        guard let project = controller.project else { return }
        isLoading = true; loadError = nil; zoneItems = []

        do {
            let garc = try await project.garc(at: "a/0/1/3")
            var items: [(index: Int, zoData: Data, wasCompressed: Bool)] = []
            for entry in garc.entries {
                guard let sub = entry.subFiles.first else { continue }
                let wasCompressed = LZ11Decompressor.isLZ11(sub.rawData)
                let raw = LZ11Decompressor.decompressIfNeeded(sub.rawData)
                guard raw.count >= 8,
                      raw[0] == UInt8(ascii: "Z"), raw[1] == UInt8(ascii: "O"),
                      raw.withUnsafeBytes({ $0.load(fromByteOffset: 2, as: UInt16.self) }) >= 2
                else { continue }
                items.append((index: entry.id, zoData: raw, wasCompressed: wasCompressed))
            }
            zoneItems = items
        } catch {
            loadError = error.localizedDescription
        }

        isLoading = false
    }

    private func loadEntities(for zoneIdx: Int) {
        guard let item = zoneItems.first(where: { $0.index == zoneIdx }),
              let sec1 = ZoneEntities.extractSection1(from: item.zoData) else {
            currentEntities = ZoneEntities(furniture: [], npcs: [], warps: [], walkTriggers: [])
            return
        }
        currentEntities = ZoneEntities.parse(from: sec1)
            ?? ZoneEntities(furniture: [], npcs: [], warps: [], walkTriggers: [])
    }

    // MARK: — Ajout / suppression

    private func addEntity() {
        isDirty = true
        switch selectedTab {
        case .furniture: currentEntities?.furniture.append(.makeDefault())
        case .npcs:      currentEntities?.npcs.append(.makeDefault())
        case .warps:     currentEntities?.warps.append(.makeDefault())
        case .triggers:  currentEntities?.walkTriggers.append(.makeDefault())
        }
    }

    private func removeSelectedEntity() {
        guard let eid = selectedEntityID else { return }
        selectedEntityID = nil
        isDirty = true
        currentEntities?.furniture.removeAll    { $0.id == eid }
        currentEntities?.npcs.removeAll         { $0.id == eid }
        currentEntities?.warps.removeAll        { $0.id == eid }
        currentEntities?.walkTriggers.removeAll { $0.id == eid }
    }

    // MARK: — Sauvegarde

    private func saveZone() async {
        guard let project = controller.project,
              let zoneIdx = selectedZoneIndex,
              let item = zoneItems.first(where: { $0.index == zoneIdx }),
              let entities = currentEntities else { return }

        isSaving = true; saveMessage = nil

        do {
            let newSec1   = entities.encode()
            let newZoData = ZoneEntities.reconstructZO(zoData: item.zoData, newSection1: newSec1)
            let finalData = item.wasCompressed ? LZ11Decompressor.compress(newZoData) : newZoData

            var garc = try await project.garc(at: "a/0/1/3")
            garc.updateSubFile(entry: zoneIdx, sub: 0, data: finalData)
            try project.writeGARC(garc, at: "a/0/1/3")

            // Mettre à jour le cache local
            if let idx = zoneItems.firstIndex(where: { $0.index == zoneIdx }) {
                zoneItems[idx] = (index: zoneIdx, zoData: newZoData, wasCompressed: item.wasCompressed)
            }

            isDirty = false; saveIsError = false
            saveMessage = item.wasCompressed ? "Sauvegardé (LZ11)" : "Sauvegardé"
        } catch {
            saveIsError = true
            saveMessage = error.localizedDescription
        }

        isSaving = false
    }
}

// MARK: — Formulaire Furniture

private struct FurnitureForm: View {
    @Binding var furniture: ZoneFurniture

    var body: some View {
        GroupBox("Mobilier") {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("ObjID").foregroundStyle(.secondary)
                    HexU16Field(label: "ObjID", value: $furniture.objID)
                }
                GridRow {
                    Text("Position X").foregroundStyle(.secondary)
                    U16Field(value: $furniture.xPos)
                }
                GridRow {
                    Text("Position Y").foregroundStyle(.secondary)
                    U16Field(value: $furniture.yPos)
                }
                GridRow {
                    Text("Hauteur Z").foregroundStyle(.secondary)
                    U16Field(value: $furniture.zPos)
                }
                GridRow {
                    Text("Orientation").foregroundStyle(.secondary)
                    FacingPicker(value: $furniture.facing)
                }
                GridRow {
                    Text("Script ID").foregroundStyle(.secondary)
                    U16Field(value: $furniture.scriptID)
                }
            }
            .padding(4)
        }
    }
}

// MARK: — Formulaire NPC

private struct NPCForm: View {
    @Binding var npc: ZoneNPC
    @ObservedObject private var eventManager = EventManager.shared

    var body: some View {
        GroupBox("PNJ") {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("NPC ID").foregroundStyle(.secondary)
                    U16Field(value: $npc.npcID)
                }
                GridRow {
                    Text("Modèle").foregroundStyle(.secondary)
                    U16Field(value: $npc.modelID)
                }
                GridRow {
                    Text("Position X").foregroundStyle(.secondary)
                    U16Field(value: $npc.xPos)
                }
                GridRow {
                    Text("Position Y").foregroundStyle(.secondary)
                    U16Field(value: $npc.yPos)
                }
                GridRow {
                    Text("Direction").foregroundStyle(.secondary)
                    FacingPicker(value: Binding(
                        get: { UInt8(npc.faceDir & 0xFF) },
                        set: { npc.faceDir = UInt16($0) }
                    ))
                }
                GridRow {
                    Text("Flag spawn").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        HexU16Field(label: "Flag", value: $npc.spawnFlag)
                        if let flag = eventManager.knownFlags.first(where: { $0.id == Int(npc.spawnFlag) }) {
                            Text(flag.name).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                GridRow {
                    Text("Script field").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        U16Field(value: $npc.scriptIndex)
                        Text("→ field script #\(npc.scriptIndex) dans a/0/1/2")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                GridRow {
                    Text("Portée vision").foregroundStyle(.secondary)
                    U16Field(value: $npc.sightRange)
                }
            }
            .padding(4)
        }
    }
}

// MARK: — Formulaire Warp

private struct WarpForm: View {
    @Binding var warp: ZoneWarp

    var body: some View {
        GroupBox("Portail de téléportation") {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Zone dest.").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        U16Field(value: $warp.destZone)
                        Text(ZoneDictionary.label(for: Int(warp.destZone)))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                GridRow {
                    Text("Warp dest.").foregroundStyle(.secondary)
                    U16Field(value: $warp.destWarp)
                }
                GridRow {
                    Text("Position X").foregroundStyle(.secondary)
                    U16Field(value: $warp.xPos)
                }
                GridRow {
                    Text("Position Y").foregroundStyle(.secondary)
                    U16Field(value: $warp.yPos)
                }
                GridRow {
                    Text("Largeur").foregroundStyle(.secondary)
                    U8Stepper(value: $warp.width)
                }
                GridRow {
                    Text("Hauteur").foregroundStyle(.secondary)
                    U8Stepper(value: $warp.height)
                }
            }
            .padding(4)
        }
    }
}

// MARK: — Formulaire Walk Trigger

private struct TriggerForm: View {
    @Binding var trigger: ZoneWalkTrigger

    var body: some View {
        GroupBox("Trigger de marche") {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Script field").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        U16Field(value: $trigger.scriptIndex)
                        Text("→ field script #\(trigger.scriptIndex) dans a/0/1/2")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                GridRow {
                    Text("Position X").foregroundStyle(.secondary)
                    U16Field(value: $trigger.xPos)
                }
                GridRow {
                    Text("Position Y").foregroundStyle(.secondary)
                    U16Field(value: $trigger.yPos)
                }
                GridRow {
                    Text("Largeur").foregroundStyle(.secondary)
                    U16Field(value: $trigger.width)
                }
                GridRow {
                    Text("Hauteur").foregroundStyle(.secondary)
                    U16Field(value: $trigger.height)
                }
            }
            .padding(4)
        }
    }
}

// MARK: — Composants UI réutilisables

private struct U16Field: View {
    @Binding var value: UInt16
    var body: some View {
        TextField("", value: $value, format: .number)
            .textFieldStyle(.roundedBorder)
            .frame(width: 80)
    }
}

private struct HexU16Field: View {
    let label: String
    @Binding var value: UInt16
    var body: some View {
        TextField(label, text: Binding(
            get: { String(format: "0x%04X", value) },
            set: { s in
                let t = s.hasPrefix("0x") || s.hasPrefix("0X") ? String(s.dropFirst(2)) : s
                if let v = UInt16(t, radix: 16) { value = v }
                else if let v = UInt16(t) { value = v }
            }
        ))
        .textFieldStyle(.roundedBorder)
        .frame(width: 80)
        .font(.system(.body, design: .monospaced))
    }
}

private struct U8Stepper: View {
    @Binding var value: UInt8
    var body: some View {
        Stepper("\(value)", value: Binding(
            get: { Int(value) },
            set: { value = UInt8(max(0, min(255, $0))) }
        ), in: 0...255)
        .frame(width: 100)
    }
}

private struct FacingPicker: View {
    @Binding var value: UInt8
    let directions = [(0, "Sud"), (1, "Nord"), (2, "Ouest"), (3, "Est"), (4, "Aléatoire")]
    var body: some View {
        Picker("", selection: $value) {
            ForEach(directions, id: \.0) { dir in
                Text(dir.1).tag(UInt8(dir.0))
            }
            Text("Autre (\(value))").tag(value)
        }
        .frame(width: 120)
        .labelsHidden()
    }
}
