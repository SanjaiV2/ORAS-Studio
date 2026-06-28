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
    │   ├── SidebarView.swift          ← navigation latérale + sections (incl. Explorateur GARC)
    │   ├── WelcomeView.swift          ← écran accueil (aucun projet ouvert)
    │   ├── DetailView.swift           ← vue détail + ValidationErrorView
    │   └── GARCExplorerView.swift     ← explorateur 3 colonnes : archive | entrées | hex ✅
    ├── Models/
    │   ├── ORASProject.swift          ← état du projet ouvert + erreurs
    │   ├── GARCFile.swift             ← parseur GARC binaire complet ✅
    │   ├── LZ11Decompressor.swift     ← port exact de Reference/lz11.py ✅
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

| Section (`SidebarSection`) | Données cibles | GARC | Statut |
|---------------------------|----------------|------|--------|
| Zones | Entités, scripts, rencontres par zone | `romfs/a/0/1/3` | Milestone 3 |
| Scripts | Scripts de zone (format ZO + bytecode FireFly) | `romfs/a/0/1/3` | Milestone 3 |
| Textes | Banques de dialogue et descriptions | `romfs/a/0/7/0` etc. | Milestone 2 |
| Rencontres sauvages | Tables de Pokémon par zone/méthode | `romfs/a/0/1/3` | Milestone 3 |
| Objets | Propriétés et données des items | `romfs/a/0/2/7` | Milestone 4 |
| Dresseurs | Équipes et IA des dresseurs | `romfs/a/0/5/5` | Milestone 4 |
| **Explorateur GARC** | Navigation binaire de toutes les archives | tous | **✅ Phase 2** |

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

## Phase 2 — Moteur de décodage binaire ✅ TERMINÉ

### Moteur GARC + LZ11 ✅
- [x] `GARCFile.swift` — parseur binaire complet (DataReader, FATO, FATB, FIMB)
  - Header : magic `CRAG`, headerSize(u32), version(u16), dataOffset(u32)
  - FATO : entryCount(u16), offsets[]
  - FATB : vector(u32) bitmask, sub-entrées = start(u32) + end(u32) + length(u32)
  - Versions 0x0400 (ORAS/XY) et 0x0600 (SM/USUM) supportées
- [x] `LZ11Decompressor.swift` — port exact de `Reference/lz11.py`
  - Indicateur 0 : longueur moyenne (count + 0x11)
  - Indicateur 1 : grande longueur (count + 0x111)
  - Indicateur ≥2 : LZSS standard (count + 1)
  - Copie chevauchante fidèle (invariant LZ Nintendo)

### Explorateur GARC ✅
- [x] `GARCExplorerView.swift` — 3 colonnes HStack
  - Colonne 1 (210 pt) : liste des 6 GARCs connus avec icônes colorées
  - Colonne 2 (240–340 pt) : entrées avec badges LZ11/multi-sub + taille
  - Colonne 3 (≥320 pt) : métadonnées + décompression on-demand + hex dump 16-colonnes
- [x] `SidebarSection.explorer` — icône `archivebox.fill`, couleur `.mint`
- [x] `DetailView.swift` — dispatch `.explorer → GARCExplorerView()`

---

## Phase 3 — Éditeur de dialogues ✅ TERMINÉ

### Décodeur / encodeur PPTXT ✅
- [x] `BCTTextDecoder.swift` — `PPTXTDecoder` + `PPTXTLine` + `PPTXTBank`
  - Chiffrement XOR rotatif 3 bits (port de `Reference/pptxt.py`)
  - Balises : `\n` saut de ligne, `\r` retour boîte, `\c` effacement, `[VAR XXXX]`, `[WAIT n]`
  - `displayText` : balises → symboles visuels (↵, {JOUEUR}, {RIVAL}, ⏳…)
- [x] `BCTTextEncoder.swift` — `PPTXTEncoder` + `GARCFile.serialize()`
  - Réencode textes édités → PPTXT binaire chiffré
  - Sérialiseur GARC complet (header v0400, FATO, FATB, FIMB, alignement 4 octets)
  - `GARCFile.updateSubFile()` + `ORASProject.writeGARC()` pour l'écriture disque

### Éditeur de dialogues ✅
- [x] `DialogueEditorView.swift` — éditeur 2 colonnes
  - Colonne gauche (180 pt) : liste des banques avec badge de modification (•)
  - Zone principale : `Table` macOS avec colonnes # | Texte original | Nouvelle histoire
  - Champs `TextField` inline avec surbrillance orange pour les lignes modifiées
  - Barre d'outils : sélecteur d'archive, recherche fulltext, filtre "modifiés uniquement"
  - Bouton "Sauvegarder" → PPTXTEncoder → GARCFile.serialize() → écriture disque
- [x] `DetailView.swift` — dispatch `.text → DialogueEditorView()`
- [x] `GARCFile` — `entries`, `subFiles`, `rawData` rendus `var` pour mutation

---

## Phase 4 — Éditeur de scripts et logique événementielle ✅ TERMINÉ

### Interpréteur FireFly ✅
- [x] `ScriptInterpreter.swift` — parseur complet du format FireFly (section 2 des fichiers ZO)
  - `ZoneScript` : structure complète (ptrOffset, ptrCount, instrStart, moveStart, subScripts)
  - `Instruction` : opcode (10 bits bas) + arg (22 bits hauts, signé), flags isReturn/isShowMessage/isJump
  - `FireFlyOpcode.table` : 30+ opcodes connus (Begin, Return, CallFunc, ShowMessage, SetFlag, JMP…)
  - `vliDecompress()` : port exact de pk3DS QuickDecompress (bytecode 7-bit VLI)
  - `parseZone()` : lit le header ZO → section 2 → décompresse pool → construit sub-scripts triés

### Gestionnaire d'événements post-game ✅
- [x] `EventManager.swift` — `@MainActor ObservableObject` singleton
  - `StoryFlag` : flags connus ORAS (0x0800–0x090F : histoire, Delta Episode, arènes, post-game Seko)
  - `PostGameCondition` : conditions à flags requis/interdits avec `isMet(activeFlags:)`
  - `sekoConditions` : 5 conditions ordonnées de la suite post-game (scène Seko → boss Dialga → fin)
  - Simulation de flags : `toggleFlag()`, `simulatePostGameStart()`, `resetSimulation()`

### Éditeur de scripts (vue) ✅
- [x] `ScriptEditorView.swift` — éditeur 3 colonnes `HSplitView`
  - Colonne 1 (max 200 pt) : liste des zones ZO avec compteur de scripts
  - Colonne 2 (max 260 pt) : sub-scripts avec offset hex + badge « Dialogue » si ShowMessage
  - Colonne 3 (flexible) : `Table` des instructions avec opcode coloré (rouge=Return, vert=ShowMessage, orange=JMP)
  - Chargement : `a/0/1/3` → LZ11Decompressor → ScriptInterpreter.parseZone()
- [x] `DetailView.swift` — dispatch `.scripts → ScriptEditorView()`

### Éditeur de dresseurs (vue) ✅
- [x] `TrainerEditorView.swift` — éditeur 2 colonnes `HSplitView`
  - `TrainerData` : modèle 16-byte (aiFlags u16, moneyFactor u8, battleType u8, items[4] u16, partyCount u16)
  - Colonne gauche : liste filtrée par ID avec badge double/simple et compteur de Pokémon
  - Détail : `GroupBox` Combat (type battle, facteur argent) + IA (`AIFlagsEditor` grille de checkboxes)
  - Items de combat : 4 `TextField` avec `NumberFormatter`
  - Sauvegarde : reconstruit le binaire 16-byte et écrit dans `a/0/3/8`
- [x] `DetailView.swift` — dispatch `.trainers → TrainerEditorView()`

---

---

## Phase 5 — Éditeur d'environnement et de cinématiques ✅ TERMINÉ

### Décodeur / Encodeur BCAM ✅
- [x] `BCAMDecoder.swift` — `BCamFile` + `Keyframe` + parse/encode complet
  - Magic `0x4D414342` ("BCAM"), version u16, frameCount u16, loopStart u32
  - Per keyframe (40 bytes) : frame(u32) + posX/Y/Z(f32) + pitch/yaw/roll(f32) + fov(f32) + near/far(f32)
  - `interpolated(atFrame:)` : interpolation linéaire entre keyframes (lerpAngle pour yaw)
  - `encode() -> Data` : ré-encodage binaire byte-perfect + `newFile()` par défaut

### Éditeur de collisions ✅
- [x] `CollisionEditor.swift` — `TileType` enum + `CollisionMap` struct + `CollisionGridCanvas`
  - `TileType` : 9 types (Passable/Bloqué/Herbes/Eau/Surf/Cascade/Trou/Glace/Sable) avec couleurs SwiftUI
  - Format binaire : magic `COLL` + width(u16) + height(u16) + tiles[w×h × 1 byte]
  - `paint(x:y:radius:type:)` : pinceau carré (rayon 0/1/2)
  - `resize(newWidth:newHeight:)` : redimensionnement avec préservation du contenu
  - `CollisionGridCanvas` : Canvas SwiftUI haute performance + DragGesture pour peindre

### Éditeur de zones (vue) ✅
- [x] `ZoneEditorView.swift` — éditeur 2 onglets (Caméra / Collision)
  - **Onglet Caméra** :
    - Panneau gauche : liste des keyframes avec drag-to-reorder + add/delete
    - Panneau droit : Stepper de frame + sliders Position (X/Y/Z) + Rotation (Pitch/Yaw/Roll) + FOV/Near/Far
    - Aperçu 2D Canvas : vue de dessus (plan XZ, yaw) + vue de côté (plan YZ, pitch)
    - Import/Export .bcam + sauvegarde dans `romfs/cameras/`
  - **Onglet Collision** :
    - Palette de 9 types de tuiles + sélecteur de taille de pinceau (1×1 / 3×3 / 5×5)
    - Grille scrollable avec zoom (12–40 px/tuile)
    - Panneau légende + Stepper redimensionnement L/H
    - Import/Export .coll + sauvegarde dans `romfs/collision/`
- [x] `DetailView.swift` — dispatch `.zones → ZoneEditorView()`
- [x] `LZ11Decompressor.swift` — `compress()` ajouté (LZ11 littéral → valide pour le jeu)

---

## Milestone 3 — Éditeur de zones (entités)

- [ ] `ZoneObject.swift` — modèle ZO (5 sections : ZoneData, ZoneEntities, MapScript, WildEncounters, Unknown)
- [ ] `ZoneListView.swift` — liste des zones avec recherche
- [ ] `ZoneEntityEditorView.swift` — éditeur NPC/Warp/Trigger
- [ ] Tests unitaires pour GARCFile, LZ11Decompressor, PPTXTDecoder
