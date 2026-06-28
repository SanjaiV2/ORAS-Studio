import Foundation

// MARK: — Validateur de structure RomFS ORAS

enum ORASValidator {

    // MARK: — Types

    struct ValidationResult {
        let checks: [Check]
        let detectedRomfsURL: URL?
        var isValid: Bool { checks.filter(\.isRequired).allSatisfy(\.passed) }
        var failedRequired: [Check] { checks.filter { $0.isRequired && !$0.passed } }
    }

    struct Check: Identifiable {
        let id = UUID()
        let name: String
        let relativePath: String
        let description: String
        let isRequired: Bool
        let passed: Bool
    }

    // MARK: — Chemins requis (relatifs au dossier romfs détecté)

    private static let knownPaths: [(name: String, path: String, desc: String, required: Bool)] = [
        ("Archive principale","a",      "Répertoire des archives GARC",           true),
        ("Données de zones",  "a/0/1/3","GARC ZoneData (NPC, warps, triggers)",  true),
        ("Field scripts",     "a/0/1/2","GARC scripts NPC et événements",         false),
        ("Banques de texte",  "a/0/7/0","GARC textes (dialogues, descriptions)", true),
        ("Données objets",    "a/0/2/7","GARC propriétés des items",             false),
        ("Données dresseurs", "a/0/5/5","GARC équipes dresseurs",                false),
    ]

    // MARK: — Détection du dossier romfs (deux formats supportés)

    /// Retourne l'URL du dossier romfs à partir du dossier root sélectionné.
    /// - Format standard   : root/romfs/a/ (export CTRtool/ninfs)
    /// - Format Citra dump : root/a/       (dossier titleID extrait directement)
    static func detectRomfsURL(_ rootURL: URL) -> URL? {
        let fm = FileManager.default

        // Format standard : sous-dossier "romfs/" contenant "a/"
        let withSubdir = rootURL.appending(path: "romfs", directoryHint: .isDirectory)
        if fm.fileExists(atPath: withSubdir.appending(path: "a").path(percentEncoded: false)) {
            return withSubdir
        }

        // Format Citra dump : le dossier sélectionné EST le romfs (a/ directement dedans)
        if fm.fileExists(atPath: rootURL.appending(path: "a").path(percentEncoded: false)) {
            return rootURL
        }

        return nil
    }

    // MARK: — Validation

    static func validate(_ rootURL: URL) -> ValidationResult {
        let fm = FileManager.default
        let romfsURL = detectRomfsURL(rootURL)

        let checks = knownPaths.map { entry -> Check in
            let exists: Bool
            if let base = romfsURL {
                let url = base.appending(path: entry.path, directoryHint: .inferFromPath)
                exists = fm.fileExists(atPath: url.path(percentEncoded: false))
            } else {
                exists = false
            }
            return Check(
                name: entry.name,
                relativePath: entry.path,
                description: entry.desc,
                isRequired: entry.required,
                passed: exists
            )
        }

        return ValidationResult(checks: checks, detectedRomfsURL: romfsURL)
    }
}
