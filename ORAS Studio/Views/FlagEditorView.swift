import SwiftUI

// MARK: — Éditeur / simulateur de flags histoire

struct FlagEditorView: View {
    @ObservedObject private var eventManager = EventManager.shared
    @State private var selectedCategory: StoryFlag.Category?
    @State private var showCopySheet = false

    var body: some View {
        HSplitView {
            categoryColumn
                .frame(minWidth: 180, maxWidth: 220)
            flagDetailColumn
                .frame(minWidth: 400, maxWidth: .infinity)
        }
    }

    // MARK: — Colonne gauche : catégories

    private var categoryColumn: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Catégories")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(.regularMaterial)
            Divider()

            List(StoryFlag.Category.allCases, id: \.self, selection: $selectedCategory) { cat in
                HStack(spacing: 8) {
                    Circle()
                        .fill(categoryColor(cat))
                        .frame(width: 8, height: 8)
                    Text(cat.rawValue)
                    Spacer()
                    let count = eventManager.knownFlags.filter { $0.category == cat }.count
                    let active = eventManager.knownFlags
                        .filter { $0.category == cat && eventManager.simulatedActiveFlags.contains($0.id) }
                        .count
                    Text("\(active)/\(count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(cat as StoryFlag.Category?)
            }
            .listStyle(.sidebar)

            Divider()

            // Actions globales
            VStack(spacing: 6) {
                Button("Post-game (début)") {
                    eventManager.simulatePostGameStart()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)

                Button("Réinitialiser") {
                    eventManager.resetSimulation()
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .frame(maxWidth: .infinity)
            }
            .padding(10)
        }
    }

    // MARK: — Colonne droite : flags + conditions

    @ViewBuilder
    private var flagDetailColumn: some View {
        VSplitView {
            flagListPane
                .frame(minHeight: 200)
            conditionsPane
                .frame(minHeight: 140)
        }
    }

    // Liste des flags de la catégorie sélectionnée
    private var flagListPane: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Flags")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Copier SetFlag") {
                    showCopySheet = true
                }
                .buttonStyle(.bordered)
                .font(.caption)
                .disabled(eventManager.simulatedActiveFlags.isEmpty)
                .sheet(isPresented: $showCopySheet) {
                    CopyFlagSheet()
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(.regularMaterial)
            Divider()

            let flags = filteredFlags
            if flags.isEmpty {
                ContentUnavailableView("Sélectionnez une catégorie", systemImage: "flag.fill")
            } else {
                List(flags) { flag in
                    FlagRow(flag: flag,
                            isActive: eventManager.simulatedActiveFlags.contains(flag.id)) {
                        eventManager.toggleFlag(flag.id)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    // Conditions post-game
    private var conditionsPane: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Conditions post-game Seko")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(.regularMaterial)
            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(eventManager.conditions) { condition in
                        let met = condition.isMet(activeFlags: eventManager.simulatedActiveFlags)
                        HStack(spacing: 10) {
                            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(met ? .green : .secondary)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(condition.name).font(.callout).fontWeight(.medium)
                                Text(condition.description)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        Divider()
                    }
                }
            }
        }
    }

    // MARK: — Computed

    private var filteredFlags: [StoryFlag] {
        guard let cat = selectedCategory else { return eventManager.knownFlags }
        return eventManager.knownFlags.filter { $0.category == cat }
    }

    private func categoryColor(_ cat: StoryFlag.Category) -> Color {
        switch cat {
        case .mainStory:    .blue
        case .deltaEpisode: .purple
        case .postGame:     .orange
        case .gym:          .green
        }
    }
}

// MARK: — Ligne de flag

private struct FlagRow: View {
    let flag: StoryFlag
    let isActive: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { isActive }, set: { _ in onToggle() }))
                .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(String(format: "0x%04X", flag.id))
                        .font(.system(.callout, design: .monospaced))
                        .fontWeight(.semibold)
                    Text(flag.name)
                }
                Text(flag.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Circle()
                .fill(isActive ? flag.categoryColor : .clear)
                .overlay(Circle().stroke(flag.categoryColor.opacity(0.5)))
                .frame(width: 10, height: 10)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
    }
}

// MARK: — Sheet : copier les SetFlag

private struct CopyFlagSheet: View {
    @ObservedObject private var eventManager = EventManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Text("Instructions SetFlag à insérer").font(.headline).padding()
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Copiez ces instructions dans l'éditeur de scripts (ScriptBuilder) :")
                        .font(.callout).foregroundStyle(.secondary).padding(.bottom, 4)

                    ForEach(sortedActiveFlags, id: \.self) { flagID in
                        let name = eventManager.knownFlags.first(where: { $0.id == flagID })?.name
                            ?? String(format: "Flag 0x%04X", flagID)
                        HStack {
                            Text("SetFlag")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.purple)
                            Text(String(format: "0x%04X", flagID))
                                .font(.system(.body, design: .monospaced))
                            Text("— \(name)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding()
            }

            Divider()
            HStack {
                Spacer()
                Button("Fermer") { dismiss() }
            }
            .padding()
        }
        .frame(width: 500, height: 350)
    }

    private var sortedActiveFlags: [Int] {
        eventManager.simulatedActiveFlags.sorted()
    }
}
