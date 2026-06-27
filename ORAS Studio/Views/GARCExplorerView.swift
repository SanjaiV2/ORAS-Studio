import SwiftUI

// MARK: — Vue principale de l'explorateur GARC

struct GARCExplorerView: View {
    @EnvironmentObject var controller: ProjectController

    // MARK: — État de navigation

    @State private var selectedGARCPath: String?
    @State private var loadedArchive: GARCFile?
    @State private var loadError: String?
    @State private var isLoading = false
    @State private var selectedEntryIndex: Int?
    @State private var selectedSubIndex: Int = 0

    // MARK: — GARCs connus (chemin relatif depuis romfs/)

    private struct KnownGARC: Identifiable {
        let id = UUID()
        let label: String
        let path: String       // relatif à romfs/
        let icon: String
        let color: Color
    }

    private let knownGARCs: [KnownGARC] = [
        KnownGARC(label: "Zones & NPCs",     path: "a/0/1/3", icon: "map.fill",          color: .blue),
        KnownGARC(label: "Field scripts",    path: "a/0/1/2", icon: "doc.text.fill",      color: .purple),
        KnownGARC(label: "Banques de texte", path: "a/0/7/0", icon: "text.bubble.fill",   color: .green),
        KnownGARC(label: "Objets",           path: "a/0/2/7", icon: "bag.fill",           color: .yellow),
        KnownGARC(label: "Dresseurs",        path: "a/0/5/5", icon: "person.2.fill",      color: .red),
        KnownGARC(label: "Rencontres",       path: "a/0/3/7", icon: "leaf.fill",          color: .orange),
    ]

    // MARK: — Layout 3 colonnes (pas de NavigationSplitView imbriqué)

    var body: some View {
        HStack(spacing: 0) {
            garcListColumn
            Divider()
            entriesColumn
            Divider()
            detailColumn
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .onChange(of: selectedGARCPath) { _, path in
            guard let path else { return }
            Task { await loadGARC(at: path) }
        }
    }

    // MARK: — Colonne 1 : liste des GARCs

    private var garcListColumn: some View {
        VStack(spacing: 0) {
            columnHeader("Archives GARC", icon: "archivebox")
            List(knownGARCs, selection: $selectedGARCPath) { garc in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(garc.label).fontWeight(.medium)
                        Text("romfs/\(garc.path)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: garc.icon)
                        .foregroundStyle(garc.color)
                }
                .tag(garc.path)
            }
            .listStyle(.sidebar)
        }
        .frame(width: 210)
    }

    // MARK: — Colonne 2 : entrées du GARC sélectionné

    @ViewBuilder
    private var entriesColumn: some View {
        VStack(spacing: 0) {
            let title = selectedGARCPath.map { "romfs/\($0)" } ?? "Entrées"
            columnHeader(title, icon: "list.bullet")

            if isLoading {
                Spacer()
                ProgressView("Lecture de l'archive…").padding()
                Spacer()
            } else if let err = loadError {
                ContentUnavailableView {
                    Label("Erreur de lecture", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                } description: { Text(err) }
            } else if let archive = loadedArchive {
                entryList(archive: archive)
            } else {
                ContentUnavailableView(
                    "Sélectionnez une archive",
                    systemImage: "archivebox",
                    description: Text("Choisissez un fichier GARC dans la liste à gauche.")
                )
            }
        }
        .frame(minWidth: 240, idealWidth: 280, maxWidth: 340)
    }

    private func entryList(archive: GARCFile) -> some View {
        List(archive.entries, selection: $selectedEntryIndex) { entry in
            EntryRow(entry: entry)
                .tag(entry.id)
        }
        .listStyle(.inset)
        .overlay(alignment: .bottom) {
            HStack {
                Text("\(archive.entries.count) entrées · \(archive.fileCount) sous-fichiers")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("v\(String(format: "%04X", archive.version.rawValue))")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.regularMaterial)
        }
    }

    // MARK: — Colonne 3 : détail du sous-fichier

    @ViewBuilder
    private var detailColumn: some View {
        if let archive = loadedArchive,
           let idx = selectedEntryIndex,
           let entry = archive[idx] {
            SubFileDetailView(
                entry: entry,
                selectedSubIndex: $selectedSubIndex
            )
        } else {
            ContentUnavailableView(
                "Sélectionnez une entrée",
                systemImage: "doc.badge.arrow.up",
                description: Text("Choisissez une entrée dans la liste pour voir son contenu binaire.")
            )
            .frame(minWidth: 320)
        }
    }

    // MARK: — Helpers

    @ViewBuilder
    private func columnHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).imageScale(.small)
            Text(title)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.regularMaterial)
        Divider()
    }

    // MARK: — Chargement GARC

    private func loadGARC(at relativePath: String) async {
        guard let project = controller.project else { return }
        isLoading = true
        loadError = nil
        loadedArchive = nil
        selectedEntryIndex = nil
        selectedSubIndex = 0

        do {
            let garc = try await project.garc(at: relativePath)
            loadedArchive = garc
        } catch {
            loadError = error.localizedDescription
        }

        isLoading = false
    }
}

// MARK: — Ligne d'entrée

private struct EntryRow: View {
    let entry: GARCEntry

    private var totalSize: Int { entry.subFiles.reduce(0) { $0 + $1.size } }
    private var hasLZ11: Bool { entry.subFiles.contains { $0.isLZ11Compressed } }

    var body: some View {
        HStack(spacing: 8) {
            Text(String(format: "%04d", entry.id))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)

            Spacer()

            // Badge LZ11
            if hasLZ11 {
                Text("LZ11")
                    .font(.caption2).fontWeight(.semibold)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(.blue.opacity(0.12))
                    .foregroundStyle(.blue)
                    .clipShape(.capsule)
            }

            // Badge multi-sous-fichiers
            if entry.subFiles.count > 1 {
                Text("\(entry.subFiles.count)×")
                    .font(.caption2)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(.secondary.opacity(0.15))
                    .foregroundStyle(.secondary)
                    .clipShape(.capsule)
            }

            // Taille totale
            Text(formatSize(totalSize))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
        }
    }

    private func formatSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.2f MB", Double(bytes) / 1_048_576)
    }
}

// MARK: — Détail d'une entrée / sous-fichier

private struct SubFileDetailView: View {
    let entry: GARCEntry
    @Binding var selectedSubIndex: Int

    @State private var decompressedData: Data?
    @State private var decompressError: String?
    @State private var isDecompressing = false

    private var currentSub: GARCSubFile? {
        entry.subFiles.indices.contains(selectedSubIndex) ? entry.subFiles[selectedSubIndex] : nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if entry.subFiles.count > 1 { subFilePicker }
                if let sub = currentSub { subFileContent(sub: sub) }
            }
            .padding(20)
        }
        .frame(minWidth: 320, maxWidth: .infinity)
        .onChange(of: entry.id) { _, _ in reset() }
        .onChange(of: selectedSubIndex) { _, _ in reset() }
    }

    // MARK: — En-tête

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Entrée \(String(format: "%04d", entry.id))")
                .font(.title3).bold()
            Text("\(entry.subFiles.count) sous-fichier\(entry.subFiles.count > 1 ? "s" : "")")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: — Sélecteur de sous-fichier (si plusieurs)

    private var subFilePicker: some View {
        Picker("Sous-fichier", selection: $selectedSubIndex) {
            ForEach(Array(entry.subFiles.enumerated()), id: \.offset) { i, sub in
                Text("Sub \(i) — bit \(sub.bitIndex) — \(formatSize(sub.size))")
                    .tag(i)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: — Contenu du sous-fichier

    private func subFileContent(sub: GARCSubFile) -> some View {
        VStack(alignment: .leading, spacing: 16) {

            // Méta-données
            GroupBox("Informations") {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    metaRow("Taille brute",  "\(sub.size) octets (\(formatSize(sub.size)))")
                    metaRow("Compression",   sub.isLZ11Compressed ? "LZ11 Nintendo" : "Aucune")
                    if let dec = sub.estimatedDecompressedSize {
                        metaRow("Taille décompressée", "\(dec) octets (\(formatSize(dec)))")
                        metaRow("Ratio", String(format: "× %.2f", Double(dec) / Double(sub.size)))
                    }
                    metaRow("Premier octet", String(format: "0x%02X", sub.rawData.first ?? 0))
                }
                .padding(4)
            }

            // Bouton de décompression
            if sub.isLZ11Compressed {
                HStack {
                    Button {
                        Task { await decompress(sub: sub) }
                    } label: {
                        Label(
                            isDecompressing ? "Décompression en cours…" : "Décompresser LZ11",
                            systemImage: "wand.and.rays"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isDecompressing || decompressedData != nil)

                    if let dec = decompressedData {
                        Label("\(dec.count) octets", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.callout)
                    }
                    if let err = decompressError {
                        Label(err, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }

            // Aperçu hexadécimal
            GroupBox {
                HexDumpView(data: decompressedData ?? sub.rawData, maxBytes: 512)
            } label: {
                HStack {
                    Label(
                        decompressedData != nil ? "Données décompressées" : "Données brutes",
                        systemImage: "number"
                    )
                    .font(.headline).foregroundStyle(.secondary)
                    Spacer()
                    if (decompressedData ?? sub.rawData).count > 512 {
                        Text("(512 premiers octets)")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).font(.system(.body, design: .monospaced))
        }
    }

    // MARK: — Décompression

    private func decompress(sub: GARCSubFile) async {
        isDecompressing = true
        decompressError = nil
        do {
            decompressedData = try LZ11Decompressor.decompress(sub.rawData)
        } catch {
            decompressError = error.localizedDescription
        }
        isDecompressing = false
    }

    private func reset() {
        decompressedData = nil
        decompressError = nil
    }

    private func formatSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.2f MB", Double(bytes) / 1_048_576)
    }
}

// MARK: — Affichage hexadécimal

private struct HexDumpView: View {
    let data: Data
    let maxBytes: Int

    private var bytes: [UInt8] { Array(data.prefix(maxBytes)) }

    var body: some View {
        let rows = stride(from: 0, to: bytes.count, by: 16).map { Int($0) }
        VStack(alignment: .leading, spacing: 1) {
            // En-tête de colonnes
            HStack(spacing: 0) {
                Text("Offset  ")
                Text("00 01 02 03 04 05 06 07  08 09 0A 0B 0C 0D 0E 0F")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("  ASCII")
            }
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.tertiary)
            Divider()

            ForEach(rows, id: \.self) { offset in
                HStack(alignment: .top, spacing: 0) {
                    // Offset
                    Text(String(format: "%04X  ", offset))
                        .foregroundStyle(.secondary)

                    // Hex bytes (groupés par 8)
                    Text(hexSegment(offset: offset))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // ASCII
                    Text("  " + asciiSegment(offset: offset))
                        .foregroundStyle(.secondary)
                }
                .font(.system(.caption, design: .monospaced))
            }
        }
        .padding(10)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
        .clipShape(.rect(cornerRadius: 6))
    }

    // Octets hex avec espace entre les groupes de 8
    private func hexSegment(offset: Int) -> String {
        let end = min(offset + 16, bytes.count)
        let line = bytes[offset..<end]
        var parts: [String] = []
        for (i, b) in line.enumerated() {
            parts.append(String(format: "%02X", b))
            if i == 7 { parts.append(" ") }  // espace central
        }
        // Compléter jusqu'à 16 octets pour alignement
        let missing = 16 - line.count
        for i in 0..<missing {
            parts.append("  ")
            if line.count + i == 7 { parts.append(" ") }
        }
        return parts.joined(separator: " ")
    }

    // Représentation ASCII (. pour les non-imprimables)
    private func asciiSegment(offset: Int) -> String {
        let end = min(offset + 16, bytes.count)
        return bytes[offset..<end].map { b in
            (0x20...0x7E).contains(b) ? String(UnicodeScalar(b)) : "."
        }.joined()
    }
}
