import SwiftUI

// MARK: — Vue principale de l'éditeur de dialogues

struct DialogueEditorView: View {
    @EnvironmentObject var controller: ProjectController

    // ── Navigation ──────────────────────────────────────────────
    @State private var garcPath     = "a/0/8/2"
    @State private var selectedBankID: Int?
    @State private var selectedLineID: Int?

    // ── Données ─────────────────────────────────────────────────
    @State private var loadedGARC:  GARCFile?
    @State private var banks:       [PPTXTBank] = []
    @State private var isLoading    = false
    @State private var loadError:   String?

    // ── Filtre / recherche ───────────────────────────────────────
    @State private var searchText      = ""
    @State private var showOnlyEdited  = false

    // ── Sauvegarde ───────────────────────────────────────────────
    @State private var isSaving     = false
    @State private var saveStatus:  SaveStatus?

    enum SaveStatus: Equatable {
        case success
        case failure(String)
    }

    // ── GARCs de texte
    // OR  : a/0/8/ → /0=JPN /1=ENG /2=FRE /3=ITA /4=GER /5=ESP /6=KOR
    // AS  : a/0/7/ → /1=JPN /2=JPN /3=ENG /4=FRE /5=ITA /6=GER /7=ESP /8=KOR
    private let textGARCs: [(label: String, path: String)] = [
        ("Textes FR — OR (a/0/8/2)",  "a/0/8/2"),
        ("Textes EN — OR (a/0/8/1)",  "a/0/8/1"),
        ("Textes FR — AS (a/0/7/4)",  "a/0/7/4"),
        ("Textes EN — AS (a/0/7/3)",  "a/0/7/3"),
    ]

    // MARK: — Layout

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HSplitView {
                bankList
                    .frame(minWidth: 180, maxWidth: 200)
                lineEditor
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: garcPath) { _, _ in Task { await loadGARC() } }
        .task { await loadGARC() }
    }

    // MARK: — Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            // Sélecteur d'archive texte
            Picker("Archive", selection: $garcPath) {
                ForEach(textGARCs, id: \.path) { g in
                    Text(g.label).tag(g.path)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 200)

            Divider().frame(height: 20)

            // Barre de recherche
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Rechercher dans les textes…", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(.quaternary)
            .clipShape(.capsule)
            .frame(maxWidth: 260)

            Toggle("Modifiés uniquement", isOn: $showOnlyEdited)
                .toggleStyle(.checkbox)

            Spacer()

            // Indicateur de modifications
            if let bank = selectedBank {
                if bank.modifiedCount > 0 {
                    Label("\(bank.modifiedCount) modifiée\(bank.modifiedCount > 1 ? "s" : "")",
                          systemImage: "pencil.circle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
            }

            // Statut de sauvegarde
            if let status = saveStatus {
                Group {
                    switch status {
                    case .success:
                        Label("Sauvegardé", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .failure(let msg):
                        Label(msg, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .help(msg)
                    }
                }
                .font(.callout)
                .transition(.opacity)
            }

            // Bouton sauvegarder
            Button {
                Task { await saveCurrentBank() }
            } label: {
                Label(isSaving ? "Sauvegarde…" : "Sauvegarder",
                      systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSaving || selectedBank?.isModified != true)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.regularMaterial)
    }

    // MARK: — Liste des banques (colonne gauche)

    private var bankList: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Banques")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                if isLoading { ProgressView().controlSize(.mini) }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(.regularMaterial)
            Divider()

            if let err = loadError {
                ContentUnavailableView {
                    Label("Erreur", systemImage: "xmark.circle.fill").foregroundStyle(.red)
                } description: { Text(err).font(.caption) }
            } else {
                List(banks, selection: $selectedBankID) { bank in
                    BankRow(bank: bank).tag(bank.id)
                }
                .listStyle(.sidebar)
            }
        }
    }

    // MARK: — Éditeur de lignes (zone principale)

    @ViewBuilder
    private var lineEditor: some View {
        if let bank = selectedBank {
            VStack(spacing: 0) {
                bankHeader(bank: bank)
                Divider()
                linesTable(bank: bank)
            }
        } else {
            ContentUnavailableView(
                "Sélectionnez une banque",
                systemImage: "text.bubble",
                description: Text("Choisissez une banque de texte dans la liste pour afficher et modifier ses lignes.")
            )
        }
    }

    private func bankHeader(bank: PPTXTBank) -> some View {
        HStack(spacing: 16) {
            Label("Banque \(String(format: "%04d", bank.id))",
                  systemImage: "doc.text.fill")
                .font(.headline)
            Text("·").foregroundStyle(.secondary)
            Text("\(bank.lines.count) lignes")
                .foregroundStyle(.secondary)
            if bank.isModified {
                Text("·").foregroundStyle(.secondary)
                Text("\(bank.modifiedCount) modifiée\(bank.modifiedCount > 1 ? "s" : "")")
                    .foregroundStyle(.orange)
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func linesTable(bank: PPTXTBank) -> some View {
        let lines = filteredLines(bank: bank)
        return Table(lines, selection: $selectedLineID) {
            TableColumn("#") { line in
                Text(String(format: "%04d", line.id))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(line.isModified ? Color.orange : Color.secondary)
            }
            .width(min: 50, ideal: 55, max: 70)

            TableColumn("Texte original") { line in
                Text(line.displayText)
                    .lineLimit(2)
                    .foregroundStyle(line.isModified ? .secondary : .primary)
                    .help(line.original)
            }

            TableColumn("Nouvelle histoire") { line in
                lineEditField(line: line, bankID: bank.id)
            }
        }
    }

    // TextField lié à la ligne dans la banque (mutation via index)
    private func lineEditField(line: PPTXTLine, bankID: Int) -> some View {
        let binding = Binding<String>(
            get: {
                banks.first(where: { $0.id == bankID })?
                    .lines.first(where: { $0.id == line.id })?.text ?? ""
            },
            set: { newValue in
                guard let bi = banks.firstIndex(where: { $0.id == bankID }),
                      let li = banks[bi].lines.firstIndex(where: { $0.id == line.id })
                else { return }
                banks[bi].lines[li].text = newValue
                saveStatus = nil
            }
        )
        return TextField("", text: binding, axis: .vertical)
            .textFieldStyle(.plain)
            .padding(.horizontal, 4)
            .background(line.isModified ? Color.orange.opacity(0.08) : Color.clear)
            .clipShape(.rect(cornerRadius: 4))
    }

    // MARK: — Helpers

    private var selectedBank: PPTXTBank? {
        guard let id = selectedBankID else { return nil }
        return banks.first { $0.id == id }
    }

    private func filteredLines(bank: PPTXTBank) -> [PPTXTLine] {
        var lines = bank.lines
        if showOnlyEdited  { lines = lines.filter { $0.isModified } }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            lines = lines.filter {
                $0.text.lowercased().contains(q) ||
                $0.original.lowercased().contains(q)
            }
        }
        return lines
    }

    // MARK: — Chargement GARC + décodage des banques

    private func loadGARC() async {
        guard let project = controller.project else { return }
        isLoading = true; loadError = nil; banks = []; loadedGARC = nil
        selectedBankID = nil; selectedLineID = nil; saveStatus = nil

        do {
            let garc = try await project.garc(at: garcPath)
            loadedGARC = garc

            // Décoder chaque entrée comme PPTXT (LZ11 si nécessaire)
            var decoded: [PPTXTBank] = []
            for entry in garc.entries {
                guard let sub = entry.subFiles.first else { continue }
                let raw  = LZ11Decompressor.decompressIfNeeded(sub.rawData)
                if let lines = try? PPTXTDecoder.decode(raw) {
                    decoded.append(PPTXTBank(id: entry.id, lines: lines))
                } else {
                    // Entrée non-PPTXT (binaire brut) — affichage vide
                    decoded.append(PPTXTBank(id: entry.id, lines: []))
                }
            }
            banks = decoded
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: — Sauvegarde

    private func saveCurrentBank() async {
        guard let project = controller.project,
              let bankID  = selectedBankID,
              let bi      = banks.firstIndex(where: { $0.id == bankID }),
              var garc    = loadedGARC
        else { return }

        isSaving = true; saveStatus = nil

        do {
            let bank        = banks[bi]
            let encoded     = try PPTXTEncoder.encode(bank.lines)
            garc.updateSubFile(entry: bankID, sub: 0, data: encoded)
            loadedGARC      = garc
            try project.writeGARC(garc, at: garcPath)

            // Marquer les lignes comme non-modifiées (origin = text actuel)
            for li in banks[bi].lines.indices {
                banks[bi].lines[li] = PPTXTLine(
                    id:       banks[bi].lines[li].id,
                    text:     banks[bi].lines[li].text,
                    original: banks[bi].lines[li].text
                )
            }
            withAnimation { saveStatus = .success }
        } catch {
            withAnimation { saveStatus = .failure(error.localizedDescription) }
        }
        isSaving = false
    }
}

// MARK: — Ligne de banque dans la liste

private struct BankRow: View {
    let bank: PPTXTBank

    var body: some View {
        HStack(spacing: 8) {
            Text(String(format: "%04d", bank.id))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(bank.lines.isEmpty ? .tertiary : .primary)

            Spacer()

            if bank.isModified {
                Circle().fill(.orange).frame(width: 7, height: 7)
            }
            if bank.lines.isEmpty {
                Image(systemName: "nosign").imageScale(.small).foregroundStyle(.tertiary)
            } else {
                Text("\(bank.lines.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
