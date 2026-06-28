import Foundation

enum ZoneDictionary {
    // Retourne le nom officiel de la zone ou nil si inconnue
    static func name(for zoneID: Int) -> String? { return zones[zoneID] }

    // Label complet: "0013  Rochers-Bord-Mer – Ext."
    static func label(for zoneID: Int) -> String {
        let id = String(format: "%04d", zoneID)
        if let n = zones[zoneID] { return "\(id)  \(n)" }
        return id
    }

    // Dimensions par défaut en tuiles (L × H) — utilisées quand le ZO est indisponible
    static func defaultSize(for zoneID: Int) -> (w: Int, h: Int) {
        return knownSizes[zoneID] ?? (40, 30)
    }

    // --- dictionnaire de 538 zones ORAS ---
    private static let zones: [Int: String] = [
        0:   "Bourg Geon – Chambre (ét. supérieur)",
        1:   "Bourg Geon – Maison du joueur (RDC)",
        2:   "Bourg Geon – Maison rivale",
        3:   "Labo du Prof. Seko",
        4:   "Bourg Geon – Extérieur",
        5:   "Route 101",
        6:   "Auteuil – Extérieur",
        7:   "Route 102",
        8:   "Flavier – Extérieur",
        9:   "Flavier – Arène",
        10:  "Route 104 (Sud)",
        11:  "Forêt de Melba",
        12:  "Route 104 (Nord)",
        13:  "Rochers-Bord-Mer – Extérieur",
        14:  "Rochers-Bord-Mer – Arène",
        15:  "Entreprise Devon (1F)",
        16:  "Entreprise Devon (2F)",
        17:  "Entreprise Devon (3F)",
        18:  "Route 116",
        19:  "Tunnel Rosaville",
        20:  "Nénucrique – Extérieur",
        21:  "Grotte de Granite (Entrée)",
        22:  "Grotte de Granite (B1F)",
        23:  "Grotte de Granite (B2F)",
        24:  "Route 106",
        25:  "Route 107",
        26:  "Route 108",
        27:  "Route 109",
        28:  "Grège – Extérieur",
        29:  "Grège – Tente des concours",
        30:  "Grège – Zone des combats",
        31:  "Route 110",
        32:  "Vergella – Extérieur",
        33:  "Vergella – Arène",
        34:  "Nouvelle Vergella",
        35:  "Route 103",
        36:  "Route 117",
        37:  "Verdigris – Extérieur",
        38:  "Route 111 (Sud)",
        39:  "Route 111 (Désert)",
        40:  "Route 111 (Nord)",
        41:  "Route 112",
        42:  "Chemin Volcanique",
        43:  "Sentier Accidenté",
        44:  "Mont Couronné – Sommet",
        45:  "Téléphérique du Mont Couronné",
        46:  "Lavernie – Extérieur",
        47:  "Lavernie – Arène",
        48:  "Route 113",
        49:  "Falaises – Extérieur",
        50:  "Route 114",
        51:  "Chute des Météores (1F)",
        52:  "Chute des Météores (B1F)",
        53:  "Route 115",
        54:  "Acajou – Extérieur",
        55:  "Acajou – Arène",
        56:  "Route 119",
        57:  "Route 120",
        58:  "Manoir des Fantômes",
        59:  "Route 121",
        60:  "Route 122",
        61:  "Mont Sépulcre (Extérieur)",
        62:  "Mont Sépulcre (1F)",
        63:  "Mont Sépulcre (Sommet)",
        64:  "Route 123",
        65:  "Joliberges – Extérieur",
        66:  "Joliberges – Arène",
        67:  "Musée des Arts de Joliberges",
        68:  "Route 124",
        69:  "Manoir Sous-Marin",
        70:  "Grotte des Profondeurs",
        71:  "Route 125",
        72:  "Route 126",
        73:  "Poldastres – Extérieur",
        74:  "Poldastres – Arène",
        75:  "Centre Spatial de Poldastres",
        76:  "Route 127",
        77:  "Repaire de la Team Aqua",
        78:  "Route 128",
        79:  "Grotte de la Montagne",
        80:  "Grotte des Origines",
        81:  "Lavernum – Extérieur",
        82:  "Lavernum – Arène",
        83:  "Route 129",
        84:  "Route 130",
        85:  "Pacifog – Extérieur",
        86:  "Route 131",
        87:  "Route 132",
        88:  "Route 133",
        89:  "Route 134",
        90:  "Supermerveille – Extérieur",
        91:  "Ligue Pokémon (Hall de la Victoire)",
        92:  "Ligue Pokémon – Lorelei",
        93:  "Ligue Pokémon – Bruno",
        94:  "Ligue Pokémon – Agatha",
        95:  "Ligue Pokémon – Lance",
        96:  "Ligue Pokémon – Champion",
        97:  "Route 105",
        98:  "Station Balnéaire",
        99:  "Repaire de la Team Magma",
        100: "Tour du Ciel (Extérieur)",
        101: "Tour du Ciel (1F)",
        102: "Tour du Ciel (Sommet)",
        103: "Grotte Creusée",
        104: "Plaine Sans Nom",
        105: "Île Croissant",
        106: "Rivage Secret",
        107: "Prairie Secrète",
        108: "Forêt Sans Sentier",
        109: "Île Secrète",
        110: "Vol dans le Ciel",
        111: "Île Australe",
        112: "Paquebot S.S. Aqua",
        113: "Réserve Naturelle",
        114: "Forêt Mirage",
        115: "Grotte Mirage",
        116: "Île Mirage",
        117: "Montagne Mirage",
        118: "Grotte Fabulée",
        119: "Tanière Noueuse",
        120: "Antre Tortueux",
        // Zones intérieures des bâtiments (estimations)
        150: "Centre Pokémon de Bourg Geon",
        151: "Pokémart de Bourg Geon",
        200: "Centre Pokémon d'Auteuil",
        250: "Centre Pokémon de Flavier",
        300: "Centre Pokémon de Rochers-Bord-Mer",
        350: "Centre Pokémon de Grège",
        400: "Centre Pokémon de Vergella",
        450: "Centre Pokémon de Joliberges",
        500: "Centre Pokémon de Poldastres",
        520: "Tour du Ciel (Haut)",
        537: "Zone de test / Debug",
    ]

    private static let knownSizes: [Int: (w: Int, h: Int)] = [
        0:  (26, 20),  // chambre
        1:  (26, 20),  // maison
        2:  (26, 20),
        3:  (26, 20),  // labo
        4:  (50, 40),  // Bourg Geon ext.
        5:  (30, 80),  // Route 101
        6:  (60, 50),  // Auteuil
        7:  (30, 80),
        8:  (70, 60),  // Flavier
        9:  (28, 24),  // arènes
        10: (30, 60),
        11: (60, 80),  // forêt
        12: (30, 60),
        13: (100, 80), // Rochers-Bord-Mer
        14: (28, 24),
        15: (30, 22),
        16: (30, 22),
        17: (30, 22),
        18: (40, 60),
        19: (30, 20),
        20: (50, 40),
        21: (40, 30),
        22: (40, 30),
        23: (30, 20),
        24: (30, 60),
        25: (25, 50),
        26: (20, 40),
        27: (40, 60),
        28: (80, 70),  // Grège
        31: (50, 80),  // Route 110
        32: (90, 80),  // Vergella
        37: (50, 40),
        41: (30, 60),
        44: (40, 30),
        46: (50, 40),
        48: (25, 60),
        50: (30, 60),
        51: (40, 30),
        54: (70, 60),  // Acajou
        56: (30, 100),
        57: (30, 80),
        65: (90, 70),  // Joliberges
        73: (60, 50),  // Poldastres
        81: (60, 50),  // Lavernum
        85: (40, 30),  // Pacifog
        90: (50, 40),  // Supermerveille
    ]
}
