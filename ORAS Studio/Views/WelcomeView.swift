import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var controller: ProjectController

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            logo
            Spacer().frame(height: 32)
            headline
            Spacer().frame(height: 40)
            recentProjectsList
            Spacer().frame(height: 32)
            openButton
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    // MARK: — Sous-vues

    private var logo: some View {
        ZStack {
            Circle()
                .fill(.blue.gradient)
                .frame(width: 84, height: 84)
                .shadow(color: .blue.opacity(0.3), radius: 12, y: 4)
            Image(systemName: "archivebox.fill")
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(.white)
        }
    }

    private var headline: some View {
        VStack(spacing: 6) {
            Text("ORAS Remastered")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("Éditeur de fichiers Pokémon Omega Ruby / Alpha Sapphire")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var recentProjectsList: some View {
        GroupBox {
            if controller.recentProjects.isEmpty {
                Text("Aucun projet récent")
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(controller.recentProjects, id: \.self) { url in
                        Button {
                            Task { await controller.loadProject(from: url) }
                        } label: {
                            HStack {
                                Image(systemName: "folder")
                                    .foregroundStyle(.blue)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(url.lastPathComponent)
                                        .fontWeight(.medium)
                                    Text(url.path(percentEncoded: false))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)

                        if url != controller.recentProjects.last {
                            Divider()
                        }
                    }
                }
            }
        } label: {
            Text("Projets récents")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 480)
    }

    private var openButton: some View {
        Button {
            controller.openProject()
        } label: {
            Label("Ouvrir un projet ORAS…", systemImage: "folder.badge.plus")
                .font(.title3)
                .padding(.horizontal, 12)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut("o", modifiers: .command)
    }
}

#Preview {
    WelcomeView()
        .environmentObject(ProjectController())
        .frame(width: 700, height: 500)
}
