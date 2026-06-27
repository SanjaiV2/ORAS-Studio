import SwiftUI

struct DetailView: View {
    let section: SidebarSection?
    @EnvironmentObject var controller: ProjectController

    var body: some View {
        Group {
            if controller.project == nil {
                WelcomeView()
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
        case .zones:
            PlaceholderView(section: section, milestone: "Milestone 2")
        case .scripts:
            PlaceholderView(section: section, milestone: "Milestone 3")
        case .text:
            PlaceholderView(section: section, milestone: "Milestone 2")
        case .encounters:
            PlaceholderView(section: section, milestone: "Milestone 3")
        case .items:
            PlaceholderView(section: section, milestone: "Milestone 4")
        case .trainers:
            PlaceholderView(section: section, milestone: "Milestone 4")
        }
    }
}

// MARK: — Placeholder

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
