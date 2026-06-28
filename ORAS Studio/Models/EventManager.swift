import Foundation
import SwiftUI

// MARK: — Flags d'histoire connus dans ORAS

struct StoryFlag: Identifiable, Codable {
    let id: Int              // ID numérique du flag en mémoire de jeu
    var name: String
    var description: String
    let category: Category

    enum Category: String, Codable, CaseIterable {
        case mainStory    = "Histoire principale"
        case deltaEpisode = "Épisode Delta"
        case postGame     = "Post-game Seko"
        case gym          = "Arènes"
    }

    var categoryColor: Color {
        switch category {
        case .mainStory:    .blue
        case .deltaEpisode: .purple
        case .postGame:     .orange
        case .gym:          .green
        }
    }
}

// MARK: — Condition post-game

struct PostGameCondition: Identifiable {
    let id: UUID
    var name: String
    var description: String
    var requiredFlags: Set<Int>     // flags qui doivent être actifs
    var forbiddenFlags: Set<Int>    // flags qui doivent être inactifs

    func isMet(activeFlags: Set<Int>) -> Bool {
        requiredFlags.isSubset(of: activeFlags) &&
        forbiddenFlags.isDisjoint(with: activeFlags)
    }
}

// MARK: — Gestionnaire d'événements post-game

@MainActor
final class EventManager: ObservableObject {

    static let shared = EventManager()

    @Published var knownFlags: [StoryFlag] = EventManager.defaultFlags
    @Published var conditions: [PostGameCondition] = EventManager.sekoConditions
    @Published var simulatedActiveFlags: Set<Int> = []

    // MARK: — Flags connus d'ORAS (valeurs basées sur la structure interne du jeu)

    static let defaultFlags: [StoryFlag] = [
        // — Histoire principale
        StoryFlag(id: 0x0800, name: "Intro terminée",
                  description: "Le joueur a dépassé l'intro du Professeur Seko.",
                  category: .mainStory),
        StoryFlag(id: 0x0801, name: "Premier Pokémon choisi",
                  description: "Le joueur a reçu son Pokémon de départ.",
                  category: .mainStory),
        StoryFlag(id: 0x083E, name: "Arène 1 validée (Olivier)",
                  description: "Badge Pierre obtenu (Rosaville).",
                  category: .gym),
        StoryFlag(id: 0x083F, name: "Arène 2 validée (Ondine)",
                  description: "Badge Cascade obtenu (Rivamar).",
                  category: .gym),
        StoryFlag(id: 0x0840, name: "Arène 3 validée (Voltigo)",
                  description: "Badge Voltage obtenu (Lavandia).",
                  category: .gym),
        StoryFlag(id: 0x0841, name: "Arène 4 validée (Théo)",
                  description: "Badge Chaleur obtenu (Doublonville).",
                  category: .gym),
        StoryFlag(id: 0x0842, name: "Arène 5 validée (Norma)",
                  description: "Badge Équilibre obtenu (Verchamps).",
                  category: .gym),
        StoryFlag(id: 0x0843, name: "Arène 6 validée (Sidonie)",
                  description: "Badge Plume obtenu (Altobord).",
                  category: .gym),
        StoryFlag(id: 0x0844, name: "Arène 7 validée (Baldo)",
                  description: "Badge Glacier obtenu (Nixville).",
                  category: .gym),
        StoryFlag(id: 0x0845, name: "Arène 8 validée (Wallace)",
                  description: "Badge Pluie obtenu (Nénuvar).",
                  category: .gym),
        StoryFlag(id: 0x0860, name: "Top 4 vaincu",
                  description: "Le joueur a vaincu les 4 membres du Top 4.",
                  category: .mainStory),
        StoryFlag(id: 0x0861, name: "Champion vaincu",
                  description: "Le joueur est inscrit au Hall of Fame.",
                  category: .mainStory),

        // — Épisode Delta
        StoryFlag(id: 0x0870, name: "Épisode Delta commencé",
                  description: "Rencontre avec Zinnia après le Hall of Fame.",
                  category: .deltaEpisode),
        StoryFlag(id: 0x0875, name: "Rayquaza apprivoisé",
                  description: "Rayquaza a avalé la Météorite de Désir.",
                  category: .deltaEpisode),
        StoryFlag(id: 0x087A, name: "Météore dévié",
                  description: "Rayquaza a Méga-Évolué et détruit la météorite.",
                  category: .deltaEpisode),
        StoryFlag(id: 0x087F, name: "Épisode Delta terminé",
                  description: "Déoxys vaincu, Zinnia partie. Post-game débloqué.",
                  category: .deltaEpisode),

        // — Post-game Seko (flags custom de notre suite)
        StoryFlag(id: 0x0900, name: "[SEKO] Anomalie détectée",
                  description: "Le Professeur Seko a détecté la première distorsion temporelle.",
                  category: .postGame),
        StoryFlag(id: 0x0901, name: "[SEKO] Route 114 enquêtée",
                  description: "Le joueur a enquêté sur la Route 114.",
                  category: .postGame),
        StoryFlag(id: 0x0902, name: "[SEKO] Dialga localisé",
                  description: "Dialga a été localisé dans la distorsion temporelle.",
                  category: .postGame),
        StoryFlag(id: 0x0903, name: "[SEKO] Palkia localisé",
                  description: "Palkia a été localisé dans la distorsion spatiale.",
                  category: .postGame),
        StoryFlag(id: 0x0904, name: "[SEKO] Giratina vaincu",
                  description: "Giratina a été repoussé dans le Monde Distorsion.",
                  category: .postGame),
        StoryFlag(id: 0x090F, name: "[SEKO] Suite terminée",
                  description: "Toute la suite post-game a été complétée.",
                  category: .postGame),
    ]

    // MARK: — Conditions d'activation de la suite Seko

    static let sekoConditions: [PostGameCondition] = [
        PostGameCondition(
            id: UUID(),
            name: "Scène d'ouverture Seko",
            description: "Seko contacte le joueur dès qu'il sort du Hall of Fame.",
            requiredFlags: [0x0861],
            forbiddenFlags: [0x0900]
        ),
        PostGameCondition(
            id: UUID(),
            name: "Apparition de Seko au labo",
            description: "Seko est présent au labo avec ses relevés d'énergie.",
            requiredFlags: [0x0861, 0x0870],
            forbiddenFlags: [0x0901]
        ),
        PostGameCondition(
            id: UUID(),
            name: "Portail Route 114 actif",
            description: "La distorsion temporelle est visible sur la Route 114.",
            requiredFlags: [0x0900],
            forbiddenFlags: [0x0901]
        ),
        PostGameCondition(
            id: UUID(),
            name: "Boss Dialga disponible",
            description: "Dialga peut être combattu dans la distorsion.",
            requiredFlags: [0x0901],
            forbiddenFlags: [0x0902]
        ),
        PostGameCondition(
            id: UUID(),
            name: "Fin de la suite",
            description: "Toutes les distorsions sont résolues.",
            requiredFlags: [0x0902, 0x0903, 0x0904],
            forbiddenFlags: [0x090F]
        ),
    ]

    // MARK: — Simulation de flags

    func toggleFlag(_ flagID: Int) {
        if simulatedActiveFlags.contains(flagID) {
            simulatedActiveFlags.remove(flagID)
        } else {
            simulatedActiveFlags.insert(flagID)
        }
    }

    func simulatePostGameStart() {
        simulatedActiveFlags = [0x0861, 0x087F]
    }

    func resetSimulation() {
        simulatedActiveFlags = []
    }

    func activeConditions() -> [PostGameCondition] {
        conditions.filter { $0.isMet(activeFlags: simulatedActiveFlags) }
    }
}
