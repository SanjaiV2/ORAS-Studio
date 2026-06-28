import Foundation

// MARK: — Erreurs

enum ORASError: LocalizedError {
    case notORASRomFS
    case missingGARC(String)
    case invalidGARC(String)
    case loadFailed(String)

    var errorDescription: String? {
        switch self {
        case .notORASRomFS:
            "Le dossier sélectionné ne contient pas de dossier 'romfs' ORAS valide."
        case .missingGARC(let path):
            "GARC introuvable : \(path)"
        case .invalidGARC(let path):
            "Fichier GARC corrompu ou invalide : \(path)"
        case .loadFailed(let reason):
            "Échec du chargement : \(reason)"
        }
    }
}

// MARK: — Modèle de projet

@MainActor
final class ORASProject: ObservableObject {

    let rootURL: URL
    let name: String
    let romfsURL: URL

    // GARCs indexés par chemin relatif depuis romfs/
    private(set) var loadedGARCs: [String: GARCFile] = [:]

    // GARC paths connus (relatifs au dossier romfs)
    enum KnownGARC {
        static let zoneData       = "a/0/1/3"  // ZO (données de zones)
        static let fieldScripts   = "a/0/1/2"  // Field scripts (NPC interactions)
        static let textBanks      = "a/0/2/7"  // Dialogues / textes
        static let wildEncounters = "a/0/3/7"  // Rencontres sauvages
        static let trainerData    = "a/0/5/5"  // Données dresseurs
        static let itemData       = "a/1/9/7"  // Données objets (776 entrées × 36 bytes)
    }

    // MARK: — Init

    init(rootURL: URL, name: String, romfsURL: URL) {
        self.rootURL = rootURL
        self.name = name
        self.romfsURL = romfsURL
    }

    // MARK: — Chargement

    static func load(from url: URL) async throws -> ORASProject {
        guard let romfsURL = ORASValidator.detectRomfsURL(url) else {
            throw ORASError.notORASRomFS
        }
        let project = ORASProject(rootURL: url, name: url.lastPathComponent, romfsURL: romfsURL)
        try await project.preloadEssentialGARCs()
        return project
    }

    // MARK: — Préchargement

    private func preloadEssentialGARCs() async throws {
        let essential = [KnownGARC.zoneData, KnownGARC.fieldScripts]
        for path in essential {
            let url = romfsURL.appending(path: path)
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
                // Non-fatal en dev : GARC sera chargé à la demande
                continue
            }
            if let data = try? Data(contentsOf: url),
               let garc = try? GARCFile(data: data) {
                loadedGARCs[path] = garc
            }
        }
    }

    // MARK: — Écriture GARC (resérialise et écrit sur disque)

    func writeGARC(_ garc: GARCFile, at relativePath: String) throws {
        let url = romfsURL.appending(path: relativePath)
        let binary = garc.serialize()
        try binary.write(to: url, options: .atomic)
        loadedGARCs[relativePath] = garc
    }

    // MARK: — Accès GARC paresseux

    func garc(at relativePath: String) async throws -> GARCFile {
        if let cached = loadedGARCs[relativePath] { return cached }
        let url = romfsURL.appending(path: relativePath)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw ORASError.missingGARC(relativePath)
        }
        let data = try Data(contentsOf: url)
        do {
            let garc = try GARCFile(data: data)
            loadedGARCs[relativePath] = garc
            return garc
        } catch {
            throw ORASError.invalidGARC(relativePath)
        }
    }
}
