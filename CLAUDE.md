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
| Bundle ID | `fr.oras.studio` |

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
    ├── ContentView.swift              ← NavigationSplitView racine
    ├── Views/
    │   ├── SidebarView.swift          ← navigation latérale + sections
    │   ├── WelcomeView.swift          ← écran accueil (aucun projet ouvert)
    │   └── DetailView.swift           ← vue détail (dispatch par section)
    ├── Models/
    │   ├── ORASProject.swift          ← état du projet ouvert + erreurs
    │   └── GARCFile.swift             ← modèle fichier GARC + stub LZ11
    ├── Controllers/
    │   └── ProjectController.swift    ← ouverture dossier, sandbox, récents
    ├── Assets.xcassets/
    ├── ORAS_Studio.entitlements       ← sandbox + lecture fichiers user
    └── Info.plist
```

---

## Architecture

### Pattern MVVM + Controller

```
View (SwiftUI)  ←→  Controller (@MainActor ObservableObject)  ←→  Model (struct/class)
SidebarView          ProjectController                              ORASProject
DetailView           ──── openProject() → NSOpenPanel              GARCFile
WelcomeView          ──── loadProject() async throws               GARCEntry
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
| Dresseurs | Équipes et IA des dresseurs | `romfs/a/0/1/5` |

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
2. **Accès fichiers** — uniquement via `NSOpenPanel` (entitlement `user-selected.read-only`)
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

## Prochaines étapes (Milestone 2)

- [ ] Implémenter `GARCParser.swift` (lecture complète GARC + FIMB)
- [ ] Implémenter `LZ11.swift` (décompression depuis `Reference/lz11.py`)
- [ ] Vue liste des zones (`ZoneListView.swift`)
- [ ] Modèle `ZoneObject.swift` (sections ZO)
- [ ] Tests unitaires pour GARC et LZ11
