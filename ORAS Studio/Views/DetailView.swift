import SwiftUI

struct DetailView: View {
    let section: SidebarSection?
    @EnvironmentObject var controller: ProjectController

    var body: some View {
        Group {
            if controller.project == nil {
                if let result = controller.validationResult, !result.isValid {
                    ValidationErrorView(result: result)
                } else {
                    WelcomeView()
                }
            } else if let section {
                sectionContent(for: section)
            } else {
                ContentUnavailableView(
                    "Sélectionnez une section",
                    systemImage: "sidebar.left",
                    description: Text("Choisissez un type de données dans la barre latérale.")
                )
            }
        }
    }

    // MARK: — Dispatch par section

    @ViewBuilder
    private func sectionContent(for section: SidebarSection) -> some View {
        switch section {
        case .zones:      ZoneEditorView()
        case .scripts:    ScriptEditorView()
        case .text:       DialogueEditorView()
        case .encounters: PlaceholderView(section: section, milestone: "Milestone 3")
        case .items:      PlaceholderView(section: section, milestone: "Milestone 4")
        case .trainers:   TrainerEditorView()
        case .explorer:   GARCExplorerView()
        }
    }
}

// MARK: — Vue erreur de validation

struct ValidationErrorView: View {
    let result: ORASValidator.ValidationResult
    @EnvironmentObject var controller: ProjectController

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                // Icône
                ZStack {
                    Circle()
                        .fill(.orange.opacity(0.15))
                        .frame(width: 84, height: 84)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(.orange)
                }

                // Titre
                VStack(spacing: 6) {
                    Text("Dossier invalide")
                        .font(.title2).bold()
                    Text("Ce dossier ne correspond pas à un jeu ORAS extrait.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                // Tableau de vérification
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(result.checks) { check in
                            CheckRow(check: check)
                            if check.id != result.checks.last?.id {
                                Divider()
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } label: {
                    Label("Vérification du contenu", systemImage: "checklist")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 520)

                // Actions
                VStack(spacing: 10) {
                    Button {
                        controller.openProject()
                    } label: {
                        Label("Choisir un autre dossier…", systemImage: "folder.badge.plus")
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Text("Sélectionnez le dossier contenant « romfs » (extraction ninfs) ou le dossier titleID de Citra (ex. 000400000011C500).")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(40)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}

// MARK: — Ligne de vérification individuelle

private struct CheckRow: View {
    let check: ORASValidator.Check

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: check.passed ? "checkmark.circle.fill" : (check.isRequired ? "xmark.circle.fill" : "minus.circle.fill"))
                .foregroundStyle(check.passed ? .green : (check.isRequired ? .red : .secondary))
                .font(.system(size: 18))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(check.name).fontWeight(.medium)
                    if check.isRequired {
                        Text("REQUIS")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(check.passed ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                            .foregroundStyle(check.passed ? .green : .red)
                            .clipShape(.capsule)
                    }
                }
                Text(check.relativePath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(check.description)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: — Placeholder section

private struct PlaceholderView: View {
    let section: SidebarSection
    let milestone: String

    var body: some View {
        ContentUnavailableView {
            Label(section.rawValue, systemImage: section.icon)
                .foregroundStyle(section.color)
        } description: {
            Text("L'éditeur « \(section.rawValue) » arrivera dans \(milestone).")
                .foregroundStyle(.secondary)
        }
    }
}
