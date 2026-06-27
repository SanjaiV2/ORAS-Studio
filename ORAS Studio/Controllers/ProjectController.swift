import SwiftUI
import AppKit

@MainActor
final class ProjectController: ObservableObject {

    // MARK: — État publié

    @Published private(set) var project: ORASProject?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var recentProjects: [URL] = []

    // MARK: — UserDefaults key

    private let recentProjectsKey = "recentProjects"
    private let maxRecentProjects = 5

    // MARK: — Init

    init() {
        loadRecentProjects()
    }

    // MARK: — Ouvrir via NSOpenPanel (sandbox-safe)

    func openProject() {
        let panel = NSOpenPanel()
        panel.title = "Sélectionner un dossier ORAS extrait"
        panel.message = "Choisissez le dossier racine contenant le sous-dossier « romfs »."
        panel.prompt = "Ouvrir"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            await loadProject(from: url)
        }
    }

    // MARK: — Chargement asynchrone

    func loadProject(from url: URL) async {
        isLoading = true
        errorMessage = nil

        do {
            let loaded = try await ORASProject.load(from: url)
            project = loaded
            addToRecents(url)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: — Projets récents

    private func addToRecents(_ url: URL) {
        var recents = recentProjects.filter { $0 != url }
        recents.insert(url, at: 0)
        if recents.count > maxRecentProjects {
            recents = Array(recents.prefix(maxRecentProjects))
        }
        recentProjects = recents
        saveRecentProjects()
    }

    private func saveRecentProjects() {
        let bookmarks = recentProjects.compactMap { url -> Data? in
            try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
        UserDefaults.standard.set(bookmarks, forKey: recentProjectsKey)
    }

    private func loadRecentProjects() {
        guard let bookmarks = UserDefaults.standard.array(forKey: recentProjectsKey) as? [Data] else { return }
        recentProjects = bookmarks.compactMap { data -> URL? in
            var stale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) else { return nil }
            _ = url.startAccessingSecurityScopedResource()
            return url
        }
    }
}
