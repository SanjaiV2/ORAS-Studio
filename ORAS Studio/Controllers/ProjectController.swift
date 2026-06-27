import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ProjectController: ObservableObject {

    // MARK: — État publié

    @Published private(set) var project: ORASProject?
    @Published private(set) var validationResult: ORASValidator.ValidationResult?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var recentProjects: [URL] = []
    @Published var showingFilePicker = false

    // MARK: — Clés UserDefaults (namespaced)

    private let bookmarkKey = "com.sanjai.ORASRemastered.projectBookmark"
    private let recentsKey  = "com.sanjai.ORASRemastered.recentPaths"

    // URL dont on gère le cycle de vie via startAccessingSecurityScopedResource
    private var scopedURL: URL?

    // MARK: — Init / deinit

    init() {
        loadRecentPaths()
        Task { await restoreFromBookmark() }
    }

    deinit {
        scopedURL?.stopAccessingSecurityScopedResource()
    }

    // MARK: — Interface publique

    func openProject() {
        showingFilePicker = true
    }

    /// Rouvre un projet récent via le signet sauvegardé si disponible,
    /// sinon ouvre le sélecteur de fichier pour re-demander l'accès.
    func openRecent(_ url: URL) {
        Task { await tryRestoreOrPick(url) }
    }

    /// Rappel du composant .fileImporter de SwiftUI
    func handlePickerResult(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let err):
            // L'utilisateur a annulé ou une erreur système s'est produite
            guard (err as? CocoaError)?.code != .userCancelled else { return }
            errorMessage = err.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            Task { await importFromPicker(url) }
        }
    }

    // MARK: — Restauration projet récent

    private func tryRestoreOrPick(_ targetURL: URL) async {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else {
            openProject(); return
        }
        isLoading = true
        var stale = false
        if let resolved = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale),
           resolved.resolvingSymlinksInPath().path == targetURL.resolvingSymlinksInPath().path,
           resolved.startAccessingSecurityScopedResource() {
            await performLoad(url: resolved)
            isLoading = false
            return
        }
        isLoading = false
        openProject()
    }

    // MARK: — Import depuis le picker

    private func importFromPicker(_ url: URL) async {
        isLoading = true
        errorMessage = nil
        validationResult = nil

        // 1. Créer un signet persistant pendant qu'on a accès implicite via le picker
        do {
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
        } catch {
            errorMessage = "Impossible de créer le signet sécurisé : \(error.localizedDescription)"
            isLoading = false
            return
        }

        // 2. Résoudre immédiatement le signet pour obtenir une URL au cycle de vie maîtrisé
        do {
            var stale = false
            let scopedURL = try URL(
                resolvingBookmarkData: UserDefaults.standard.data(forKey: bookmarkKey)!,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            guard scopedURL.startAccessingSecurityScopedResource() else {
                throw ORASError.loadFailed("Accès sécurisé refusé par macOS.")
            }
            await performLoad(url: scopedURL)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: — Restauration au démarrage depuis UserDefaults

    private func restoreFromBookmark() async {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        isLoading = true

        do {
            var stale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )

            guard url.startAccessingSecurityScopedResource() else {
                isLoading = false
                return
            }

            // Rafraîchir le signet si périmé
            if stale {
                if let fresh = try? url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                ) {
                    UserDefaults.standard.set(fresh, forKey: bookmarkKey)
                }
            }

            await performLoad(url: url)

        } catch {
            // Signet invalide ou révoqué — on efface pour ne pas boucler
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
        }

        isLoading = false
    }

    // MARK: — Chargement + validation centralisés

    private func performLoad(url: URL) async {
        // Libérer l'ancienne ressource scopée
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = url

        // Validation structurelle
        let result = ORASValidator.validate(url)
        validationResult = result

        guard result.isValid else {
            project = nil
            return
        }

        // Chargement du projet (préchargement des GARCs essentiels)
        do {
            let loaded = try await ORASProject.load(from: url)
            project = loaded
            addToRecents(url)
        } catch {
            errorMessage = error.localizedDescription
            project = nil
        }
    }

    // MARK: — Projets récents (chemins uniquement, pas de bookmarks)

    private func addToRecents(_ url: URL) {
        var paths = recentProjects.map(\.path).filter { $0 != url.path }
        paths.insert(url.path, at: 0)
        let trimmed = Array(paths.prefix(5))
        recentProjects = trimmed.map { URL(fileURLWithPath: $0) }
        UserDefaults.standard.set(trimmed, forKey: recentsKey)
    }

    private func loadRecentPaths() {
        guard let paths = UserDefaults.standard.stringArray(forKey: recentsKey) else { return }
        recentProjects = paths.map { URL(fileURLWithPath: $0) }
    }
}
