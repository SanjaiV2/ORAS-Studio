import SwiftUI

// MARK: — Sections disponibles dans la barre latérale

enum SidebarSection: String, Hashable, CaseIterable, Identifiable {
    case zones       = "Zones"
    case scripts     = "Scripts"
    case text        = "Textes"
    case encounters  = "Rencontres sauvages"
    case items       = "Objets"
    case trainers    = "Dresseurs"
    case explorer    = "Explorateur GARC"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .zones:      "map.fill"
        case .scripts:    "doc.text.fill"
        case .text:       "text.bubble.fill"
        case .encounters: "leaf.fill"
        case .items:      "bag.fill"
        case .trainers:   "person.2.fill"
        case .explorer:   "archivebox.fill"
        }
    }

    var color: Color {
        switch self {
        case .zones:      .blue
        case .scripts:    .purple
        case .text:       .green
        case .encounters: .orange
        case .items:      .yellow
        case .trainers:   .red
        case .explorer:   .mint
        }
    }
}

// MARK: — Vue

struct SidebarView: View {
    @Binding var selectedSection: SidebarSection?
    @EnvironmentObject var controller: ProjectController

    var body: some View {
        List(SidebarSection.allCases, selection: $selectedSection) { section in
            Label {
                Text(section.rawValue)
            } icon: {
                Image(systemName: section.icon)
                    .foregroundStyle(section.color)
            }
            .tag(section)
        }
        .listStyle(.sidebar)
        .navigationTitle(controller.project?.name ?? "ORAS Remastered")
        .disabled(controller.project == nil)
        .overlay {
            if controller.project == nil {
                noProjectOverlay
            }
        }
    }

    private var noProjectOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("Aucun projet ouvert")
                .font(.headline)
                .foregroundStyle(.secondary)
            Button("Ouvrir…") {
                controller.openProject()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}
