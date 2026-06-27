import Foundation

// MARK: — Validateur de structure RomFS ORAS

enum ORASValidator {

    // MARK: — Types

    struct ValidationResult {
        let checks: [Check]
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

    // MARK: — Chemins connus d'ORAS (relatifs au dossier root/romfs/)

    private static let knownPaths: [(name: String, path: String, desc: String, required: Bool)] = [
        ("Dossier romfs",     "romfs",        "Racine du système de fichiers 3DS",      true),
        ("Archive principale","romfs/a",      "Répertoire des archives GARC",            true),
        ("Données de zones",  "romfs/a/0/1/3","GARC ZoneData (NPC, warps, triggers)",   true),
        ("Field scripts",     "romfs/a/0/1/2","GARC scripts NPC et événements",          true),
        ("Banques de texte",  "romfs/a/0/7/0","GARC textes (dialogues, descriptions)",  true),
        ("Données objets",    "romfs/a/0/2/7","GARC propriétés des items",              false),
        ("Données dresseurs", "romfs/a/0/5/5","GARC équipes dresseurs",                 false),
    ]

    // MARK: — Validation

    static func validate(_ rootURL: URL) -> ValidationResult {
        let fm = FileManager.default

        let checks = knownPaths.map { entry -> Check in
            let url = rootURL.appending(path: entry.path, directoryHint: .inferFromPath)
            let exists = fm.fileExists(atPath: url.path(percentEncoded: false))
            return Check(
                name: entry.name,
                relativePath: entry.path,
                description: entry.desc,
                isRequired: entry.required,
                passed: exists
            )
        }

        return ValidationResult(checks: checks)
    }
}
