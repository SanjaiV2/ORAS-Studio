import SwiftUI
import UniformTypeIdentifiers
import SceneKit

// MARK: — Bouton de palette de tuile (extrait pour éviter la surcharge du type-checker)

private struct TilePaletteButton: View {
    let type: TileType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: type.sfSymbol)
                    .foregroundStyle(tileIconColor)
                Text(type.displayName).font(.caption2)
            }
            .padding(5)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(type.displayName)
    }

    private var tileIconColor: Color {
        type.rawValue == TileType.passable.rawValue ? .secondary : type.tileColor
    }
}

// MARK: — Éditeur de zones : caméras BCAM + grilles de collision

struct ZoneEditorView: View {
    @EnvironmentObject var controller: ProjectController

    @State private var selectedTab: ZoneTab = .camera
    @State private var bcam: BCamFile = .newFile(name: "nouveau")
    @State private var collision: CollisionMap = .defaultMap()
    @State private var bcamDirty = false
    @State private var collDirty = false
    @State private var saveStatus: String?
    @State private var saveIsError = false
    @State private var showBCAMImport = false
    @State private var showCollImport = false

    enum ZoneTab: String, CaseIterable {
        case camera    = "Caméra"
        case collision = "Collision"
    }

    var body: some View {
        VStack(spacing: 0) {
            topTabBar
            Divider()
            switch selectedTab {
            case .camera:    cameraEditorView
            case .collision: collisionEditorView
            }
        }
        .fileImporter(
            isPresented: $showBCAMImport,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                importBCAM(from: url)
            }
        }
        .fileImporter(
            isPresented: $showCollImport,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                importCollision(from: url)
            }
        }
    }

    // MARK: — Tab bar

    private var topTabBar: some View {
        HStack(spacing: 0) {
            ForEach(ZoneTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                    saveStatus = nil
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab == .camera ? "video.fill" : "square.grid.3x3.fill")
                        Text(tab.rawValue)
                        if (tab == .camera && bcamDirty) || (tab == .collision && collDirty) {
                            Circle().fill(.orange).frame(width: 6, height: 6)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(selectedTab == tab
                        ? Color.accentColor.opacity(0.15)
                        : Color.clear)
                    .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            // Statut sauvegarde global
            if let status = saveStatus {
                Label(status, systemImage: saveIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(saveIsError ? .red : .green)
                    .font(.callout)
                    .padding(.horizontal, 12)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .background(.regularMaterial)
    }

    // ══════════════════════════════════════════════════════════════════
    // MARK: — Onglet CAMÉRA
    // ══════════════════════════════════════════════════════════════════

    private var cameraEditorView: some View {
        HStack(spacing: 0) {
            keyframeListPanel.frame(width: 205)
            Divider()
            cameraDetailPanel.frame(maxWidth: .infinity)
        }
    }

    // — Panneau gauche : liste des keyframes

    private var keyframeListPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Keyframes")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(bcam.keyframes.count)")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(.regularMaterial)
            Divider()

            List(selection: $selectedKFID) {
                ForEach($bcam.keyframes) { $kf in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kf.timeLabel)
                            .font(.system(.callout, design: .monospaced))
                            .fontWeight(.medium)
                        Text(String(format: "X:%.0f  Y:%.0f  Z:%.0f", kf.posX, kf.posY, kf.posZ))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    .tag(kf.id)
                }
                .onMove { from, to in
                    bcam.keyframes.move(fromOffsets: from, toOffset: to)
                    bcamDirty = true
                }
                .onDelete { offsets in
                    bcam.keyframes.remove(atOffsets: offsets)
                    selectedKFID = bcam.keyframes.first?.id
                    bcamDirty = true
                }
            }
            .listStyle(.sidebar)

            Divider()
            HStack(spacing: 10) {
                Button {
                    let last = bcam.keyframes.last
                    let newKF = BCamFile.Keyframe(
                        frame:    (last?.frame ?? 0) + 30,
                        posX:     last?.posX ?? 0,
                        posY:     last?.posY ?? 100,
                        posZ:     last?.posZ ?? 0,
                        pitch:    last?.pitch ?? -45,
                        yaw:      (last?.yaw ?? 0) + 30,
                        roll:     last?.roll ?? 0,
                        fov:      last?.fov ?? 60
                    )
                    bcam.keyframes.append(newKF)
                    selectedKFID = newKF.id
                    bcamDirty = true
                } label: {
                    Image(systemName: "plus").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered)

                Button {
                    if let id = selectedKFID {
                        bcam.keyframes.removeAll { $0.id == id }
                        selectedKFID = bcam.keyframes.last?.id
                        bcamDirty = true
                    }
                } label: {
                    Image(systemName: "minus").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered)
                .disabled(bcam.keyframes.count <= 1)
            }
            .padding(8)
            .background(.regularMaterial)
        }
    }

    @State private var selectedKFID: UUID? = nil

    // — Panneau droit : édition d'un keyframe + aperçu

    @ViewBuilder
    private var cameraDetailPanel: some View {
        if let binding = selectedKFBinding {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    cameraPreviewCanvas(kf: binding.wrappedValue)
                    Divider()
                    frameStepperRow(kf: binding)
                    paramSection("Position",  sf: "move.3d") {
                        vecSliderRow("X", val: binding.posX, range: -2000...2000)
                        vecSliderRow("Y", val: binding.posY, range: -500...500,  unit: "m")
                        vecSliderRow("Z", val: binding.posZ, range: -2000...2000)
                    }
                    paramSection("Rotation",  sf: "rotate.3d") {
                        vecSliderRow("Pitch",  val: binding.pitch, range: -90...90, unit: "°")
                        vecSliderRow("Yaw",    val: binding.yaw,   range: 0...360,  unit: "°")
                        vecSliderRow("Roll",   val: binding.roll,  range: -180...180, unit: "°")
                    }
                    paramSection("Optique",   sf: "camera.fill") {
                        vecSliderRow("FOV",    val: binding.fov,      range: 10...120, unit: "°")
                        vecSliderRow("Near",   val: binding.nearClip, range: 0.01...10, unit: "u", step: 0.01)
                        vecSliderRow("Far",    val: binding.farClip,  range: 10...5000, unit: "u")
                    }
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { cameraToolbar }
        } else {
            ContentUnavailableView(
                "Sélectionnez un keyframe",
                systemImage: "video",
                description: Text("Choisissez un keyframe dans la liste ou créez-en un.")
            )
            .safeAreaInset(edge: .bottom, spacing: 0) { cameraToolbar }
        }
    }

    private func frameStepperRow(kf: Binding<BCamFile.Keyframe>) -> some View {
        HStack {
            Label("Frame", systemImage: "film")
            Spacer()
            Stepper(value: kf.frame, in: 0...9999, step: 1) {
                Text(kf.wrappedValue.timeLabel)
                    .font(.system(.body, design: .monospaced))
            }
            .onChange(of: kf.wrappedValue.frame) { _, _ in bcamDirty = true }
        }
    }

    @ViewBuilder
    private func paramSection(_ title: String, sf: String, @ViewBuilder content: () -> some View) -> some View {
        GroupBox {
            content()
        } label: {
            Label(title, systemImage: sf).font(.headline).foregroundStyle(.secondary)
        }
    }

    private func vecSliderRow(_ label: String,
                               val: Binding<Float>,
                               range: ClosedRange<Float>,
                               unit: String = "",
                               step: Float = 1) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(.callout, design: .monospaced))
                .frame(width: 50, alignment: .trailing)
                .foregroundStyle(.secondary)
            Slider(value: val, in: range, step: step)
                .onChange(of: val.wrappedValue) { _, _ in bcamDirty = true }
            Text(String(format: step < 1 ? "%.2f%@" : "%.0f%@", val.wrappedValue, unit))
                .font(.system(.callout, design: .monospaced))
                .frame(width: 70, alignment: .trailing)
        }
    }

    // Aperçu 2D : vue de dessus + vue de côté
    private func cameraPreviewCanvas(kf: BCamFile.Keyframe) -> some View {
        HStack(spacing: 16) {
            // Vue de dessus (plan XZ)
            cameraView2D(title: "Dessus", xVal: kf.posX, yVal: kf.posZ,
                         arrowAngle: Double(kf.yaw), range: 2000,
                         color: .blue)
            // Vue de côté (plan YZ / pitch)
            cameraView2D(title: "Côté", xVal: kf.posZ, yVal: kf.posY,
                         arrowAngle: Double(kf.pitch) + 90, range: 500,
                         color: .orange)
        }
    }

    private func cameraView2D(title: String, xVal: Float, yVal: Float,
                               arrowAngle: Double, range: Float, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Canvas { ctx, size in
                let cx = size.width / 2;  let cy = size.height / 2
                let scale = Double(size.width) / Double(range * 2)

                // Grille légère
                ctx.stroke(Path { p in p.move(to: .init(x: 0, y: cy)); p.addLine(to: .init(x: size.width, y: cy)) },
                           with: .color(.secondary.opacity(0.25)), lineWidth: 0.5)
                ctx.stroke(Path { p in p.move(to: .init(x: cx, y: 0)); p.addLine(to: .init(x: cx, y: size.height)) },
                           with: .color(.secondary.opacity(0.25)), lineWidth: 0.5)

                // Point caméra
                let px = cx + Double(xVal) * scale
                let py = cy - Double(yVal) * scale
                ctx.fill(Path(ellipseIn: .init(x: px-5, y: py-5, width: 10, height: 10)), with: .color(color))

                // Flèche direction
                let angleRad = arrowAngle * .pi / 180
                let arrowLen: Double = 30
                let ex = px + sin(angleRad) * arrowLen
                let ey = py - cos(angleRad) * arrowLen
                ctx.stroke(Path { p in p.move(to: .init(x: px, y: py)); p.addLine(to: .init(x: ex, y: ey)) },
                           with: .color(color.opacity(0.8)), lineWidth: 2)
            }
            .frame(width: 140, height: 140)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var cameraToolbar: some View {
        HStack(spacing: 10) {
            Button { showBCAMImport = true } label: {
                Label("Importer .bcam", systemImage: "square.and.arrow.down")
            }.buttonStyle(.bordered)

            Button { exportBCAM() } label: {
                Label("Exporter .bcam", systemImage: "square.and.arrow.up")
            }.buttonStyle(.bordered)
            .disabled(bcam.keyframes.isEmpty)

            Spacer()

            Text("\(bcam.keyframes.count) kf — \(String(format: "%.1fs", bcam.durationSeconds))")
                .font(.callout).foregroundStyle(.secondary)

            Button { saveBCAM() } label: {
                Label(bcamDirty ? "Sauvegarder*" : "Sauvegardé",
                      systemImage: "square.and.arrow.down.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!bcamDirty)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.regularMaterial)
    }

    private var selectedKFBinding: Binding<BCamFile.Keyframe>? {
        guard let id = selectedKFID ?? bcam.keyframes.first?.id,
              let idx = bcam.keyframes.firstIndex(where: { $0.id == id })
        else { return nil }
        if selectedKFID == nil { selectedKFID = bcam.keyframes[idx].id }
        return Binding(get: { bcam.keyframes[idx] },
                       set: { bcam.keyframes[idx] = $0 })
    }

    // ══════════════════════════════════════════════════════════════════
    // MARK: — Onglet COLLISION
    // ══════════════════════════════════════════════════════════════════

    @State private var selectedTileType: TileType = .blocked
    @State private var brushRadius: Int = 0
    @State private var tileSize: CGFloat = 22

    // Zone selector state
    @State private var zoneIDs: [Int] = []
    @State private var selectedZoneID: Int? = nil
    @State private var loadingZones = false
    @State private var background: ZoneBackground = .none
    @State private var entityMarkers: [ZoneEntityMarker] = []
    @State private var show3D: Bool = false
    @State private var bchMeshes: [BCHParser.MeshData] = []

    private var collisionEditorView: some View {
        VStack(spacing: 0) {
            collisionToolbar
            Divider()
            HStack(spacing: 0) {
                zoneListPanel.frame(width: 180)
                Divider()
                collisionLegend.frame(width: 160)
                Divider()
                ZStack {
                    if show3D {
                        ZoneSceneKitView(
                            collisionMap: collision,
                            bchMeshes: bchMeshes,
                            entityMarkers: entityMarkers,
                            background: background
                        )
                    } else {
                        ScrollView([.horizontal, .vertical]) {
                            CollisionGridCanvas(
                                map: $collision,
                                tileSize: tileSize,
                                selectedType: $selectedTileType,
                                brushRadius: $brushRadius,
                                onChange: { collDirty = true },
                                backgroundStyle: background,
                                entityOverlay: entityMarkers
                            )
                            .padding(10)
                        }
                    }
                }
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: 6) {
                        Button {
                            show3D = false
                        } label: {
                            Label("Grille", systemImage: "square.grid.3x3.fill")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .tint(show3D ? .secondary : .accentColor)

                        Button {
                            show3D = true
                        } label: {
                            Label("3D", systemImage: "cube.fill")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .tint(show3D ? .accentColor : .secondary)
                    }
                    .padding(8)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .task { await loadZoneList() }
    }

    // MARK: — Zone list panel

    private var zoneListPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Zones").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if loadingZones { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(.regularMaterial)
            Divider()
            if zoneIDs.isEmpty && !loadingZones {
                Text("Aucun projet")
                    .font(.caption).foregroundStyle(.tertiary)
                    .padding()
                Spacer()
            } else {
                List(zoneIDs, id: \.self, selection: $selectedZoneID) { id in
                    Text(ZoneDictionary.label(for: id))
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .tag(id)
                }
                .listStyle(.sidebar)
                .onChange(of: selectedZoneID) { _, id in
                    bchMeshes = []
                    show3D = false
                    if let id { Task { await loadZone(id: id) } }
                }
            }
        }
    }

    private var collisionToolbar: some View {
        HStack(spacing: 12) {
            // Pinceau
            Label("Pinceau :", systemImage: "paintbrush.fill").foregroundStyle(.secondary)
            Picker("Rayon", selection: $brushRadius) {
                Text("1×1").tag(0)
                Text("3×3").tag(1)
                Text("5×5").tag(2)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 160)

            Divider().frame(height: 20)

            // Palette de types
            ForEach(TileType.allCases) { type in
                TilePaletteButton(type: type, isSelected: selectedTileType == type) {
                    selectedTileType = type
                }
            }

            Spacer()

            // Zoom
            Label("Zoom", systemImage: "magnifyingglass").foregroundStyle(.secondary)
            Slider(value: $tileSize, in: 12...40, step: 2)
                .frame(width: 80)

            Divider().frame(height: 20)

            // I/O
            Button { showCollImport = true } label: {
                Label("Importer", systemImage: "square.and.arrow.down")
            }.buttonStyle(.bordered)

            Button { exportCollision() } label: {
                Label("Exporter", systemImage: "square.and.arrow.up")
            }.buttonStyle(.bordered)

            Button { saveCollision() } label: {
                Label(collDirty ? "Sauvegarder*" : "Sauvegardé",
                      systemImage: "square.and.arrow.down.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!collDirty)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(.regularMaterial)
    }

    // Légende + redimensionnement
    private var collisionLegend: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Légende")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.vertical, 7)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(TileType.allCases) { type in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(type.tileColor == Color.white.opacity(0.05)
                                    ? AnyShapeStyle(Color.secondary.opacity(0.15))
                                    : AnyShapeStyle(type.tileColor))
                                .overlay(RoundedRectangle(cornerRadius: 3).stroke(.secondary.opacity(0.4), lineWidth: 0.5))
                                .frame(width: 16, height: 16)
                            Text(type.displayName).font(.callout)
                            Spacer()
                            Text(String(format: "0x%02X", type.rawValue))
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(10)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Dimensions")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("L")
                    Stepper("\(collision.width)", value: Binding(
                        get: { collision.width },
                        set: { collision.resize(newWidth: max(4, $0), newHeight: collision.height); collDirty = true }
                    ), in: 4...128)
                }
                HStack {
                    Text("H")
                    Stepper("\(collision.height)", value: Binding(
                        get: { collision.height },
                        set: { collision.resize(newWidth: collision.width, newHeight: max(4, $0)); collDirty = true }
                    ), in: 4...128)
                }

                Button("Réinitialiser") {
                    collision = .defaultMap(width: collision.width, height: collision.height)
                    collDirty = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(maxWidth: .infinity)
            }
            .padding(10)
        }
    }

    // ══════════════════════════════════════════════════════════════════
    // MARK: — I/O BCAM
    // ══════════════════════════════════════════════════════════════════

    private func importBCAM(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            let data = try Data(contentsOf: url)
            bcam = try BCamFile.parse(data: data, name: url.deletingPathExtension().lastPathComponent)
            selectedKFID = bcam.keyframes.first?.id
            bcamDirty = false
            showSave("BCAM importé : \(bcam.name)")
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func exportBCAM() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.data]
        panel.nameFieldStringValue = "\(bcam.name).bcam"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try bcam.encode().write(to: url)
                bcamDirty = false
                showSave("BCAM exporté")
            } catch { showError(error.localizedDescription) }
        }
    }

    private func saveBCAM() {
        // Sauvegarde dans le dossier du projet (sous-dossier "cameras/")
        guard let project = controller.project else {
            exportBCAM(); return
        }
        let cameraDir = project.romfsURL.appending(path: "cameras", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: cameraDir,
                                                    withIntermediateDirectories: true)
            let dest = cameraDir.appending(path: "\(bcam.name).bcam")
            try bcam.encode().write(to: dest)
            bcamDirty = false
            showSave("BCAM sauvegardé")
        } catch { showError(error.localizedDescription) }
    }

    // ══════════════════════════════════════════════════════════════════
    // MARK: — I/O Collision
    // ══════════════════════════════════════════════════════════════════

    private func importCollision(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            let data = try Data(contentsOf: url)
            collision = try CollisionMap.parse(data: data)
            collDirty = false
            showSave("Collision importée (\(collision.width)×\(collision.height))")
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func exportCollision() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.data]
        panel.nameFieldStringValue = "collision.coll"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try collision.encode().write(to: url)
                collDirty = false
                showSave("Collision exportée")
            } catch { showError(error.localizedDescription) }
        }
    }

    private func saveCollision() {
        guard let project = controller.project else {
            exportCollision(); return
        }
        let collDir = project.romfsURL.appending(path: "collision", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: collDir, withIntermediateDirectories: true)
            let dest = collDir.appending(path: "map.coll")
            try collision.encode().write(to: dest)
            collDirty = false
            showSave("Collision sauvegardée (\(collision.width)×\(collision.height) tuiles)")
        } catch { showError(error.localizedDescription) }
    }

    // ══════════════════════════════════════════════════════════════════
    // MARK: — Chargement des zones depuis le GARC a/0/1/3
    // ══════════════════════════════════════════════════════════════════

    private func loadZoneList() async {
        guard let project = controller.project else { return }
        loadingZones = true
        if let garc = try? await project.garc(at: "a/0/1/3") {
            zoneIDs = garc.entries.map { $0.id }
        }
        loadingZones = false
    }

    private func loadZone(id: Int) async {
        guard let project = controller.project else { return }
        guard let garc = try? await project.garc(at: "a/0/1/3"),
              let entry = garc.entries.first(where: { $0.id == id }),
              let sub = entry.subFiles.first else { return }

        // Capture les bytes bruts sur le main actor, puis décompresse + parse hors thread
        let rawData = sub.rawData
        struct ZoneResult {
            var bg: ZoneBackground; var markers: [ZoneEntityMarker]; var gridW, gridH: Int
            var modelEntry: Int  // u16[2] de ZoneData → index GARC a/2/5/7
        }
        let result = await Task.detached(priority: .userInitiated) { () -> ZoneResult in
            let decompressed = LZ11Decompressor.decompressIfNeeded(rawData)
            guard decompressed.count >= 8,
                  decompressed[0] == UInt8(ascii: "Z"),
                  decompressed[1] == UInt8(ascii: "O")
            else { return ZoneResult(bg: .none, markers: [], gridW: 40, gridH: 30, modelEntry: 0) }

            let sectionCount = Int(decompressed.withUnsafeBytes {
                $0.loadUnaligned(fromByteOffset: 2, as: UInt16.self) })
            let sec0Off = sectionCount >= 1
                ? Int(decompressed.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self) })
                : 4

            // u16[2] à (sec0Off+4) = index du modèle terrain dans GARC a/2/5/7
            var modelEntry = 0
            if sec0Off + 6 <= decompressed.count {
                modelEntry = Int(decompressed.withUnsafeBytes {
                    $0.loadUnaligned(fromByteOffset: sec0Off + 4, as: UInt16.self)
                })
            }

            var gridW = 40, gridH = 30
            if sec0Off + 10 <= decompressed.count {
                let rawW = Int(decompressed.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: sec0Off + 6, as: UInt16.self) })
                let rawH = Int(decompressed.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: sec0Off + 8, as: UInt16.self) })
                let knownSize = ZoneDictionary.defaultSize(for: id)
                if knownSize.w != 40 || knownSize.h != 30 {
                    gridW = knownSize.w; gridH = knownSize.h
                } else {
                    gridW = (rawW > 4 && rawW < 200) ? max(20, rawW) : 40
                    gridH = (rawH > 4 && rawH < 200) ? max(15, rawH) : 30
                }
            }

            let isKnownCave   = [21, 22, 23, 51, 52, 62, 69, 70, 79, 80, 103].contains(id)
            let isKnownWater  = (68...72).contains(id) || (75...78).contains(id)
            let isKnownIndoor = [0, 1, 2, 3, 9, 14, 15, 16, 17, 19, 21, 22, 23,
                                 29, 33, 34, 47, 55, 66, 74, 82].contains(id)
            let bg: ZoneBackground
            if isKnownCave        { bg = .cave }
            else if isKnownWater  { bg = .water }
            else if isKnownIndoor { bg = .indoor }
            else                  { bg = .outdoor }

            let markers = ZoneEditorView.parseEntityMarkers(from: decompressed, gridW: gridW, gridH: gridH)
            return ZoneResult(bg: bg, markers: markers, gridW: gridW, gridH: gridH, modelEntry: modelEntry)
        }.value

        background    = result.bg
        entityMarkers = result.markers
        collision     = .defaultMap(width: result.gridW, height: result.gridH)
        collDirty     = false
        Task { await loadTerrainMeshes(zoneID: id, tmEntry: result.modelEntry) }
    }

    private func loadTerrainMeshes(zoneID: Int, tmEntry: Int) async {
        guard let project = controller.project else { return }
        print("[TERRAIN] zone=\(zoneID) tmEntry=\(tmEntry) — start")

        // ── 1. Terrain principal : PCContainer dans a/0/0/8 ──────────────────────────
        // Chaque zone N a 15 entrées consécutives [N*15 .. N*15+14].
        // La grande entrée "PC\x02\x00" (>50 KB) contient le BCH terrain à l'offset u32[4].
        // GARCFile.readEntry lit uniquement l'entrée voulue sans charger les 1 GB du GARC.
        let garc008URL = project.romfsURL.appending(path: "a/0/0/8")
        if FileManager.default.fileExists(atPath: garc008URL.path(percentEncoded: false)) {
            let base008 = zoneID * 15
            for k in 0..<15 {
                let idx = base008 + k
                let rawData = await Task.detached(priority: .userInitiated) {
                    GARCFile.readEntry(idx, from: garc008URL) ?? Data()
                }.value
                guard rawData.count > 0 else { continue }
                let dec = LZ11Decompressor.decompressIfNeeded(rawData)
                // Sélection : magic PC\x02\x00 ET fichier décompressé >50 KB
                guard dec.count > 50_000, dec.count >= 16,
                      dec[0] == 0x50, dec[1] == 0x43, dec[2] == 0x02, dec[3] == 0x00 else { continue }
                // Lecture des offsets PCContainer : u32[4]=bch1Start, u32[8]=bch1End
                let bch1Start = Int(dec.withUnsafeBytes {
                    $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self) })
                let bch1End   = Int(dec.withUnsafeBytes {
                    $0.loadUnaligned(fromByteOffset: 8, as: UInt32.self) })
                guard bch1Start >= 0x10, bch1Start + 3 < dec.count,
                      bch1End > bch1Start, bch1End <= dec.count else { continue }
                // Vérification magic BCH à l'offset
                guard dec[bch1Start] == 0x42, dec[bch1Start+1] == 0x43,
                      dec[bch1Start+2] == 0x48 else { continue }
                // BCH1 : terrain principal
                let bch1Data = dec.subdata(in: bch1Start..<bch1End)
                print("[TERRAIN] a/0/0/8[\(idx)] PC BCH1: \(bch1Data.count) B")
                var allMeshes = await Task.detached(priority: .userInitiated) {
                    BCHParser.parseWithTextures(fileData: bch1Data, isTM: false)
                }.value
                // BCH2 : géométrie complémentaire (si présente juste après BCH1)
                let bch3Off = Int(dec.withUnsafeBytes {
                    $0.loadUnaligned(fromByteOffset: 12, as: UInt32.self) })
                let bch2End = (bch3Off > bch1End && bch3Off <= dec.count) ? bch3Off : dec.count
                if bch1End + 3 < dec.count,
                   dec[bch1End] == 0x42, dec[bch1End+1] == 0x43, dec[bch1End+2] == 0x48 {
                    let bch2Data = dec.subdata(in: bch1End..<bch2End)
                    print("[TERRAIN] PC BCH2: \(bch2Data.count) B")
                    let meshes2 = await Task.detached(priority: .userInitiated) {
                        BCHParser.parseWithTextures(fileData: bch2Data, isTM: false)
                    }.value
                    print("[TERRAIN] BCH2 → \(meshes2.count) meshes \(meshes2.reduce(0){$0+$1.vertices.count}) vtx")
                    allMeshes.append(contentsOf: meshes2)
                }
                let meshes = allMeshes
                let vtxCount = meshes.reduce(0) { $0 + $1.vertices.count }
                print("[TERRAIN] PC total → \(meshes.count) meshes \(vtxCount) vertices")
                if !meshes.isEmpty {
                    // Bounding box pour calibrer l'échelle vs grille tuiles
                    var mnX: Float = .infinity, mxX: Float = -.infinity
                    var mnY: Float = .infinity, mxY: Float = -.infinity
                    var mnZ: Float = .infinity, mxZ: Float = -.infinity
                    for m in meshes { for v in m.vertices {
                        mnX = min(mnX, v.position.x); mxX = max(mxX, v.position.x)
                        mnY = min(mnY, v.position.y); mxY = max(mxY, v.position.y)
                        mnZ = min(mnZ, v.position.z); mxZ = max(mxZ, v.position.z)
                    }}
                    print("[TERRAIN] BBox X[\(mnX)…\(mxX)] Y[\(mnY)…\(mxY)] Z[\(mnZ)…\(mxZ)]")
                    // Normaliser les vertices en espace-tuile :
                    // Le terrain BCH est en coordonnées monde 3DS (X symétrique autour de 0,
                    // Z légèrement décalé). On recentre en X et Z, et on applique un scale
                    // uniforme pour que l'étendue X couvre exactement collision.width tuiles.
                    let cX = (mnX + mxX) / 2
                    let cZ = (mnZ + mxZ) / 2
                    let halfExtX = (mxX - mnX) / 2
                    let tileHalfW = Float(collision.width) / 2
                    let autoScale: Float = (halfExtX > 0 && collision.width > 0)
                        ? tileHalfW / halfExtX : 1.0
                    print("[TERRAIN] autoScale=\(autoScale) (tileW=\(collision.width) bcbhXHalf=\(halfExtX))")
                    var normalised = meshes.map { mesh -> BCHParser.MeshData in
                        var m = mesh
                        m.vertices = mesh.vertices.map { v in
                            var vd = v
                            vd.position = SIMD3(
                                (v.position.x - cX) * autoScale,
                                v.position.y * autoScale,
                                (v.position.z - cZ) * autoScale)
                            return vd
                        }
                        return m
                    }

                    // ── Textures ETC1 : scan des conteneurs PT de la même zone ──
                    // La géométrie BCH (PC k=4) n'embarque pas de textures ; elles sont
                    // dans des fichiers PT séparés (k=0 est le plus grand, meilleure résolution).
                    var externalTextures: [CGImage?] = []
                    var bestPTSize = 0
                    for ptK in 0..<15 {
                        let ptIdx = base008 + ptK
                        let ptRaw = await Task.detached(priority: .userInitiated) {
                            GARCFile.readEntry(ptIdx, from: garc008URL) ?? Data()
                        }.value
                        guard ptRaw.count > 0 else { continue }
                        let ptDec = LZ11Decompressor.decompressIfNeeded(ptRaw)
                        // PT magic : 0x50 0x54
                        guard ptDec.count >= 16,
                              ptDec[0] == 0x50, ptDec[1] == 0x54 else { continue }
                        // Garder le PT avec le plus de données (résolution maximale)
                        guard ptDec.count > bestPTSize else { continue }
                        let textures = await Task.detached(priority: .userInitiated) {
                            BCHParser.extractTextures(from: ptDec)
                        }.value
                        if !textures.isEmpty {
                            externalTextures = textures
                            bestPTSize = ptDec.count
                            print("[TERRAIN] PT k=\(ptK)[\(ptIdx)] → \(textures.count) textures (\(ptDec.count) B)")
                        }
                    }
                    // Appliquer les textures PT aux meshes normalisés
                    if !externalTextures.isEmpty {
                        normalised = normalised.map { mesh in
                            var m = mesh
                            let ti = Int(mesh.materialIndex) % externalTextures.count
                            m.texture = externalTextures[ti]
                            return m
                        }
                        let withTex = normalised.filter { $0.texture != nil }.count
                        print("[TERRAIN] ✓ \(withTex)/\(normalised.count) meshes texturés (PT ext.)")
                    }
                    bchMeshes = normalised
                    return
                }
            }
        }

        // ── 2. Fallback : TM container a/2/5/7 (props/décors) ──────────────────────
        // TM[tmEntry] sc≥2 → terrain BCH en section 1 ; sc=1 → terrain BCH en section 0.
        do {
            let garc = try await project.garc(at: "a/2/5/7")
            guard tmEntry < garc.entries.count,
                  let sub = garc.entries[tmEntry].subFiles.first else {
                print("[TERRAIN] TM[\(tmEntry)] hors bornes ou sans sous-fichier")
                throw CancellationError()
            }
            print("[TERRAIN] TM a/2/5/7[\(tmEntry)] trouvé (\(sub.rawData.count) bytes)")
            let rawData = sub.rawData
            let meshes = await Task.detached(priority: .userInitiated) {
                let raw = LZ11Decompressor.decompressIfNeeded(rawData)
                return BCHParser.parseWithTextures(fileData: raw, isTM: true)
            }.value
            print("[TERRAIN] TM → \(meshes.count) meshes \(meshes.reduce(0){$0+$1.vertices.count}) vertices")
            if !meshes.isEmpty {
                bchMeshes = meshes
                return
            }
        } catch {
            print("[TERRAIN] a/2/5/7 inaccessible : \(error.localizedDescription)")
        }

        // ── 3. Dernier recours : AD package a/0/1/4 ────────────────────────────────
        guard let adGarc = try? await project.garc(at: "a/0/1/4"),
              zoneID < adGarc.entries.count,
              let adSub = adGarc.entries[zoneID].subFiles.first else { return }
        print("[TERRAIN] fallback AD a/0/1/4[\(zoneID)]")
        let adRaw = adSub.rawData
        let meshes = await Task.detached(priority: .userInitiated) {
            let adData = LZ11Decompressor.decompressIfNeeded(adRaw)
            let bchs = ADParser.extractBCHSections(from: adData)
            return bchs.flatMap { BCHParser.parseWithTextures(fileData: $0, isTM: false) }
        }.value
        bchMeshes = meshes
    }

    private static func parseEntityMarkers(from zoData: Data, gridW: Int, gridH: Int) -> [ZoneEntityMarker] {
        guard zoData.count > 8 else { return [] }
        let sectionCount = Int(zoData.withUnsafeBytes {
            $0.loadUnaligned(fromByteOffset: 2, as: UInt16.self)
        })
        guard sectionCount >= 2 else { return [] }
        let sec1Off = Int(zoData.withUnsafeBytes {
            $0.loadUnaligned(fromByteOffset: 8, as: UInt32.self)
        })
        let sec2Off = sectionCount >= 3
            ? Int(zoData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 12, as: UInt32.self) })
            : zoData.count
        guard sec1Off < sec2Off, sec2Off <= zoData.count, sec1Off + 20 < zoData.count else { return [] }

        var markers: [ZoneEntityMarker] = []
        // Format ZO section 1 (confirmé par dump hex) :
        // +0  u32 : taille totale données entités (ex. 580)
        // +4  u8  : furni_count
        // +5  u8  : npc_count
        // +6  u8  : warp_count
        // +7  u8  : trigger_count
        // +8..+19 : inconnu (12 bytes)
        // +20 : données entités (furniture → NPC → warp → trigger)
        let furniCount = Int(zoData[sec1Off + 4])
        let npcCount   = Int(zoData[sec1Off + 5])
        let warpCount  = Int(zoData[sec1Off + 6])
        let trigCount  = Int(zoData[sec1Off + 7])

        guard furniCount < 200, npcCount < 200, warpCount < 200, trigCount < 200 else { return [] }

        // Struct sizes confirmed: 1×40 + 11×48 + 1×12 = 580 = entityDataSize
        // Warp struct: src_x u8 +0, src_y u8 +1, dst_x u8 +2, dst_y u8 +3, dst_zone u16 +4, dst_warp u16 +6
        let furniSize = 40
        let npcSize   = 48
        let warpSize  = 12
        let trigSize  = 16
        var offset = sec1Off + 20  // 20-byte header

        // Furniture: objID u16 +0, x u16 +2, y u16 +4
        for _ in 0..<furniCount {
            guard offset + furniSize <= sec2Off else { break }
            let objID = zoData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self) }
            let x = Int(zoData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset + 2, as: UInt16.self) })
            let y = Int(zoData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset + 4, as: UInt16.self) })
            let tileX = x / 8; let tileY = y / 8
            if tileX < gridW * 8 && tileY < gridH * 8 {
                markers.append(ZoneEntityMarker(x: tileX, y: tileY, kind: .furniture, objID: objID))
            }
            offset += furniSize
        }
        // NPC: X u16 +0x0C, Y u16 +0x0E
        for _ in 0..<npcCount {
            guard offset + npcSize <= sec2Off else { break }
            let x = Int(zoData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset + 0x0C, as: UInt16.self) })
            let y = Int(zoData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset + 0x0E, as: UInt16.self) })
            let tileX = x / 8; let tileY = y / 8
            if tileX < gridW * 8 && tileY < gridH * 8 {
                markers.append(ZoneEntityMarker(x: tileX, y: tileY, kind: .npc))
            }
            offset += npcSize
        }
        // Warp: src_x u8 +0, src_y u8 +1
        for _ in 0..<warpCount {
            guard offset + warpSize <= sec2Off else { break }
            let x = Int(zoData[offset])
            let y = Int(zoData[offset + 1])
            let tileX = x / 8; let tileY = y / 8
            if tileX < gridW * 8 && tileY < gridH * 8 {
                markers.append(ZoneEntityMarker(x: tileX, y: tileY, kind: .warp))
            }
            offset += warpSize
        }
        // Trigger: x u16 +0, y u16 +2 (offsets à confirmer)
        for _ in 0..<trigCount {
            guard offset + trigSize <= sec2Off else { break }
            let x = Int(zoData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self) })
            let y = Int(zoData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset + 2, as: UInt16.self) })
            let tileX = x / 8; let tileY = y / 8
            if tileX < gridW * 8 && tileY < gridH * 8 {
                markers.append(ZoneEntityMarker(x: tileX, y: tileY, kind: .trigger))
            }
            offset += trigSize
        }
        return markers
    }

    // ══════════════════════════════════════════════════════════════════
    // MARK: — Helpers
    // ══════════════════════════════════════════════════════════════════

    private func showSave(_ msg: String) {
        saveIsError = false
        withAnimation { saveStatus = msg }
    }
    private func showError(_ msg: String) {
        saveIsError = true
        withAnimation { saveStatus = msg }
    }
}
