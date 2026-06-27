# ORAS Studio — CLAUDE.md

## Vue d'ensemble du projet

**ORAS Studio** est une application macOS professionnelle destinée au Mac App Store,
permettant d'éditer les fichiers du jeu Pokémon Omega Ruby / Alpha Sapphire (3DS).

| Paramètre | Valeur |
|-----------|--------|
| Langage | Swift 5.9+ |
| UI | SwiftUI (AppKit pour interopérabilité ciblée) |
| Cible | macOS 14.0+ (Sonoma), Apple Silicon M3 |
| Pattern | MVVM + Controllers |
| Distribution | Mac App Store (sandbox activé) |
| Bundle ID | `com.sanjai.ORASRemastered` |

---

## Structure du dépôt

```
ORAS-Remastered/
├── CLAUDE.md                          ← ce fichier
├── .gitignore
├── Reference/                         ← scripts Python de référence pour les formats
│   ├── garc_unpack.py                 ← format GARC (archive de données)
│   ├── garc_pack.py
│   ├── lz11.py                        ← compression LZ11 (zones/scripts)
│   └── pptxt.py                       ← format textes (MSGDAT/MSGNARCCHAR)
├── ORAS Studio.xcodeproj/
│   └── project.pbxproj
└── ORAS Studio/
    ├── ORASStudioApp.swift            ← point d'entrée @main
    ├── ContentView.swift              ← NavigationSplitView + .fileImporter
    ├── Views/
    │   ├── SidebarView.swift          ← navigation latérale + sections
    │   ├── WelcomeView.swift          ← écran accueil (aucun projet ouvert)
    │   └── DetailView.swift           ← vue détail + ValidationErrorView
    ├── Models/
    │   ├── ORASProject.swift          ← état du projet ouvert + erreurs
    │   ├── GARCFile.swift             ← modèle fichier GARC + LZ11
    │   └── ORASValidator.swift        ← validation structure RomFS ORAS ✅
    ├── Controllers/
    │   └── ProjectController.swift    ← Security-Scoped Bookmarks, validation, récents ✅
    ├── Assets.xcassets/
    ├── ORAS_Studio.entitlements       ← sandbox + lecture/écriture fichiers user
    └── Info.plist
```

---

## Architecture

### Pattern MVVM + Controller

```
View (SwiftUI)  ←→  Controller (@MainActor ObservableObject)  ←→  Model (struct/class)
SidebarView          ProjectController                              ORASProject
DetailView           ──── openProject() → .fileImporter            GARCFile
WelcomeView          ──── handlePickerResult() → bookmark          ORASValidator
ValidationErrorView  ──── restoreFromBookmark() (auto au boot)     GARCEntry
```

- Les **Views** ne contiennent aucune logique métier.
- Le **ProjectController** est injecté via `.environmentObject()` à la racine.
- Les **Models** sont des types valeur (struct) sauf `ORASProject` qui est une classe
  `@MainActor` car il publie des changements d'état.

### Sections éditables (roadmap)

| Section (`SidebarSection`) | Données cibles | GARC |
|---------------------------|----------------|------|
| Zones | Entités, scripts, rencontres par zone | `romfs/a/0/1/3` |
| Scripts | Scripts de zone (format ZO + bytecode FireFly) | `romfs/a/0/1/3` |
| Textes | Banques de dialogue et descriptions | `romfs/a/0/7/0` etc. |
| Rencontres sauvages | Tables de Pokémon par zone/méthode | `romfs/a/0/1/3` |
| Objets | Propriétés et données des items | `romfs/a/0/2/7` |
| Dresseurs | Équipes et IA des dresseurs | `romfs/a/0/5/5` |

---

## Formats de fichiers clés

### GARC (Generic ARChive)
- Magic: `GARC` (little-endian `CRAG` en octets : `43 52 41 47`)
- Structure: Header → FABT (File Allocation Block Table) → FATO → FATB → FIMB (data)
- Référence Python : `Reference/garc_unpack.py`

### LZ11 (compression Nintendo)
- Premier octet `0x11` = marqueur LZ11
- Décompression par blocs de 8 drapeaux
- Référence Python : `Reference/lz11.py`

### ZO (Zone Object) — Zones
- Magic: `ZO` (2 octets) + section_count (u16) + offsets (u32 × N)
- 5 sections : ZoneData | ZoneEntities | MapScript | WildEncounters | Unknown
- ZoneEntities : header 12 octets + entités (Furniture/NPC/Warp/Trigger) + Script blob

### Textes (MSGDAT)
- Référence Python : `Reference/pptxt.py`
- Encodage custom sur 15 bits + caractères spéciaux

---

## Contraintes Mac App Store

1. **Sandbox activé** — `com.apple.security.app-sandbox = true`
2. **Accès fichiers** — via `.fileImporter` SwiftUI + Security-Scoped Bookmarks persistants
3. **Hardened Runtime** — obligatoire (`ENABLE_HARDENED_RUNTIME = YES`)
4. **Pas de copyright Nintendo** — l'app ne redistribue aucun fichier ROM ou binaire du jeu
5. **Pas de JIT** — pas d'entitlement `allow-jit`

---

## Règles de développement

- Commits fréquents et atomiques (une fonctionnalité = un commit)
- Push groupé en fin de session
- Ne JAMAIS committer : fichiers ROM `.3ds`, fichiers extraits du jeu, `.bin` Nintendo
- Commenter uniquement le POURQUOI (pas le QUOI — le code parle de lui-même)
- Tests unitaires dans `ORAS StudioTests/` dès qu'un parseur est implémenté

---

## Milestone 1 — Socle applicatif ✅ TERMINÉ

### Étape 1.1 — Squelette SwiftUI ✅
- [x] `CLAUDE.md` planification et architecture
- [x] Structure dossiers Views / Models / Controllers
- [x] `ORASStudioApp.swift` — `@main`, toolbar unifiée, Cmd+O
- [x] `ContentView.swift` — `NavigationSplitView` racine
- [x] `SidebarView.swift` — `SidebarSection` enum + sidebar
- [x] `WelcomeView.swift` — écran accueil, projets récents
- [x] `DetailView.swift` — dispatch par section / placeholder

### Étape 1.2 — Accès sécurisé sandbox ✅
- [x] `ProjectController.swift` rewrite complet
  - `.fileImporter` SwiftUI (remplace NSOpenPanel)
  - `bookmarkData(options: .withSecurityScope)` → `UserDefaults`
  - `restoreFromBookmark()` au démarrage (auto-reopen)
  - Gestion du cycle de vie `startAccessingSecurityScopedResource` / `stopAccessingSecurityScopedResource`
  - Rafraîchissement signet si périmé (`stale`)

### Étape 1.3 — Validation du dossier ORAS ✅
- [x] `ORASValidator.swift` — `ValidationResult` + `Check` (required/optional)
  - Vérifie : `romfs/`, `romfs/a/`, `romfs/a/0/1/3`, `romfs/a/0/1/2`, `romfs/a/0/7/0`
  - Affichage des checks passés/échoués avec badge REQUIS
- [x] `ValidationErrorView` dans `DetailView.swift`
  - Liste des checks avec icône ✅ / ❌
  - Bouton "Choisir un autre dossier"

---

## Milestone 2 — Éditeur de zones

- [ ] Implémenter `GARCParser.swift` (lecture complète GARC + FIMB)
- [ ] Implémenter `LZ11.swift` (décompression depuis `Reference/lz11.py`)
- [ ] Vue liste des zones (`ZoneListView.swift`)
- [ ] Modèle `ZoneObject.swift` (sections ZO)
- [ ] Tests unitaires pour GARC et LZ11
