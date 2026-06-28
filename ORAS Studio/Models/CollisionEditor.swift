import Foundation
import SwiftUI

// MARK: — Types de tuile de collision ORAS

enum TileType: UInt8, CaseIterable, Identifiable {
    case passable  = 0x00
    case blocked   = 0x80
    case tallGrass = 0x01
    case water     = 0x04
    case surfable  = 0x05
    case waterfall = 0x06
    case hole      = 0x10
    case ice       = 0x20
    case sand      = 0x40

    var id: UInt8 { rawValue }

    var displayName: String {
        switch self {
        case .passable:  "Passable"
        case .blocked:   "Bloqué"
        case .tallGrass: "Herbes"
        case .water:     "Eau"
        case .surfable:  "Surf"
        case .waterfall: "Cascade"
        case .hole:      "Trou"
        case .ice:       "Glace"
        case .sand:      "Sable"
        }
    }

    var tileColor: Color {
        switch self {
        case .passable:  .white.opacity(0.05)
        case .blocked:   .red.opacity(0.75)
        case .tallGrass: .green.opacity(0.6)
        case .water:     .blue.opacity(0.45)
        case .surfable:  .cyan.opacity(0.55)
        case .waterfall: .indigo.opacity(0.6)
        case .hole:      .black.opacity(0.8)
        case .ice:       .mint.opacity(0.55)
        case .sand:      .yellow.opacity(0.55)
        }
    }

    var sfSymbol: String {
        switch self {
        case .passable:  "checkmark.circle"
        case .blocked:   "xmark.circle.fill"
        case .tallGrass: "leaf.fill"
        case .water:     "drop.fill"
        case .surfable:  "wave.3.right"
        case .waterfall: "arrow.down.to.line"
        case .hole:      "circle.fill"
        case .ice:       "snowflake"
        case .sand:      "circle.dotted"
        }
    }

    // Résolution d'un octet brut vers le type le plus proche
    static func from(byte: UInt8) -> TileType {
        if let exact = TileType(rawValue: byte) { return exact }
        return byte >= 0x80 ? .blocked : .passable
    }
}

// MARK: — Grille de collision

struct CollisionMap: Equatable {
    var width:  Int
    var height: Int
    private(set) var tiles: [[TileType]]   // tiles[y][x], y=0 en haut

    // MARK: Init

    init(width: Int, height: Int, fill: TileType = .passable) {
        self.width  = max(1, width)
        self.height = max(1, height)
        self.tiles  = Array(repeating: Array(repeating: fill, count: self.width), count: self.height)
    }

    // MARK: Accès

    func inBounds(x: Int, y: Int) -> Bool { x >= 0 && x < width && y >= 0 && y < height }

    subscript(x: Int, y: Int) -> TileType {
        get { inBounds(x: x, y: y) ? tiles[y][x] : .passable }
        set { if inBounds(x: x, y: y) { tiles[y][x] = newValue } }
    }

    // MARK: Peinture (brush carré)

    mutating func paint(x: Int, y: Int, radius: Int, type: TileType) {
        for dy in -radius...radius {
            for dx in -radius...radius {
                self[x + dx, y + dy] = type
            }
        }
    }

    // MARK: Redimensionnement

    mutating func resize(newWidth: Int, newHeight: Int, fill: TileType = .passable) {
        var newTiles = Array(repeating: Array(repeating: fill, count: newWidth), count: newHeight)
        for y in 0..<min(height, newHeight) {
            for x in 0..<min(width, newWidth) {
                newTiles[y][x] = tiles[y][x]
            }
        }
        width = newWidth; height = newHeight; tiles = newTiles
    }

    // MARK: Sérialisation binaire
    //
    // Format : magic(4) + width(u16) + height(u16) + tiles[height × width × 1 octet]
    //          ← byte offset (x + y*width) →  valeur = TileType.rawValue

    static let magic: UInt32 = 0x4C4C4F43   // "COLL"

    static func parse(data: Data) throws -> CollisionMap {
        guard data.count >= 8 else { throw ParseError.dataTooShort }
        func u32(_ o: Int) -> UInt32 { data.withUnsafeBytes { $0.load(fromByteOffset: o, as: UInt32.self) } }
        func u16(_ o: Int) -> UInt16 { data.withUnsafeBytes { $0.load(fromByteOffset: o, as: UInt16.self) } }

        guard u32(0) == CollisionMap.magic else { throw ParseError.invalidMagic }
        let w = Int(u16(4)); let h = Int(u16(6))
        guard w > 0, h > 0, w <= 512, h <= 512 else { throw ParseError.invalidDimensions(w, h) }
        guard data.count >= 8 + w * h else { throw ParseError.dataTooShort }

        var map = CollisionMap(width: w, height: h)
        for y in 0..<h {
            for x in 0..<w {
                map.tiles[y][x] = TileType.from(byte: data[8 + y * w + x])
            }
        }
        return map
    }

    func encode() -> Data {
        var out = Data(count: 8 + width * height)
        out.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: CollisionMap.magic, toByteOffset: 0, as: UInt32.self)
            ptr.storeBytes(of: UInt16(width),      toByteOffset: 4, as: UInt16.self)
            ptr.storeBytes(of: UInt16(height),     toByteOffset: 6, as: UInt16.self)
        }
        for y in 0..<height {
            for x in 0..<width {
                out[8 + y * width + x] = tiles[y][x].rawValue
            }
        }
        return out
    }

    // MARK: Grille par défaut (20×15, bordure bloquée)

    static func defaultMap(width: Int = 20, height: Int = 15) -> CollisionMap {
        var map = CollisionMap(width: width, height: height, fill: .passable)
        for x in 0..<width  { map[x, 0] = .blocked; map[x, height - 1] = .blocked }
        for y in 0..<height { map[0, y] = .blocked; map[width - 1, y]  = .blocked }
        return map
    }

    // MARK: — Erreurs

    enum ParseError: LocalizedError {
        case dataTooShort
        case invalidMagic
        case invalidDimensions(Int, Int)

        var errorDescription: String? {
            switch self {
            case .dataTooShort:           "Données de collision trop courtes"
            case .invalidMagic:           "Magic 'COLL' absent — fichier non reconnu"
            case .invalidDimensions(let w, let h): "Dimensions invalides : \(w)×\(h)"
            }
        }
    }
}

// MARK: — Style de fond pour la grille de collision

enum ZoneBackground: Equatable {
    case none
    case outdoor   // vert clair (herbe)
    case indoor    // beige (plancher)
    case cave      // gris foncé
    case water     // bleu clair

    var baseColor: Color {
        switch self {
        case .none:    return .clear
        case .outdoor: return Color(red: 0.72, green: 0.85, blue: 0.60).opacity(0.25)
        case .indoor:  return Color(red: 0.92, green: 0.82, blue: 0.68).opacity(0.30)
        case .cave:    return Color(red: 0.35, green: 0.32, blue: 0.30).opacity(0.30)
        case .water:   return Color(red: 0.45, green: 0.70, blue: 0.92).opacity(0.25)
        }
    }

    var gridColor: Color {
        switch self {
        case .none:    return Color(white: 0.5, opacity: 0.25)
        case .outdoor: return Color(red: 0.40, green: 0.60, blue: 0.25, opacity: 0.20)
        case .indoor:  return Color(red: 0.60, green: 0.45, blue: 0.25, opacity: 0.20)
        case .cave:    return Color(white: 0.25, opacity: 0.30)
        case .water:   return Color(red: 0.20, green: 0.50, blue: 0.80, opacity: 0.20)
        }
    }
}

// MARK: — Marqueur d'entité de zone (NPC, furniture, warp, trigger)

struct ZoneEntityMarker: Identifiable {
    enum Kind { case npc, furniture, warp, trigger }
    let id = UUID()
    let x: Int          // en tuiles
    let y: Int          // en tuiles
    let kind: Kind
    var objID: UInt16 = 0  // prop object ID (furniture only — distingue arbre vs bâtiment)

    var color: Color {
        switch kind {
        case .npc:       return .orange
        case .furniture: return Color(red: 0.6, green: 0.4, blue: 0.2)
        case .warp:      return .blue
        case .trigger:   return .yellow
        }
    }
}

// MARK: — Vue Canvas de la grille (réutilisée dans ZoneEditorView)

struct CollisionGridCanvas: View {
    @Binding var map: CollisionMap
    var tileSize: CGFloat
    @Binding var selectedType: TileType
    @Binding var brushRadius: Int
    let onChange: () -> Void

    // Fond optionnel et overlay d'entités
    var backgroundStyle: ZoneBackground = .none
    var entityOverlay: [ZoneEntityMarker] = []

    var body: some View {
        Canvas { ctx, size in
            // 1. Remplissage du fond
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .color(backgroundStyle.baseColor))

            // 2. Motif de points tous les 2 tuiles (texture légère pour les fonds non-vides)
            if backgroundStyle != .none {
                let dotColor = backgroundStyle.gridColor
                for row in stride(from: 0, through: map.height, by: 2) {
                    for col in stride(from: 0, through: map.width, by: 2) {
                        let cx = CGFloat(col) * tileSize
                        let cy = CGFloat(row) * tileSize
                        ctx.fill(Path(ellipseIn: CGRect(x: cx - 1, y: cy - 1, width: 2, height: 2)),
                                 with: .color(dotColor))
                    }
                }
            }

            // 3. Tuiles de collision (passable et blocked à 0.75 opacity pour laisser apparaître le fond)
            for y in 0..<map.height {
                for x in 0..<map.width {
                    let tile = map[x, y]
                    let rect = CGRect(x: CGFloat(x) * tileSize,
                                     y: CGFloat(y) * tileSize,
                                     width: tileSize, height: tileSize)
                    let color: Color
                    if backgroundStyle != .none &&
                       (tile == .passable || tile == .blocked) {
                        color = tile.tileColor.opacity(0.75)
                    } else {
                        color = tile.tileColor
                    }
                    ctx.fill(Path(rect), with: .color(color))
                }
            }

            // 4. Marqueurs d'entités (petits cercles colorés de 6px de rayon)
            for marker in entityOverlay {
                let cx = CGFloat(marker.x) * tileSize + tileSize / 2
                let cy = CGFloat(marker.y) * tileSize + tileSize / 2
                let r: CGFloat = 6
                let markerRect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
                ctx.fill(Path(ellipseIn: markerRect), with: .color(marker.color))
                ctx.stroke(Path(ellipseIn: markerRect),
                           with: .color(.white.opacity(0.8)), lineWidth: 1)
            }

            // 5. Grille (lignes) avec couleur selon le fond
            for y in 0..<map.height {
                for x in 0..<map.width {
                    let rect = CGRect(x: CGFloat(x) * tileSize,
                                     y: CGFloat(y) * tileSize,
                                     width: tileSize, height: tileSize)
                    ctx.stroke(Path(rect),
                               with: .color(backgroundStyle.gridColor),
                               lineWidth: 0.5)
                }
            }
        }
        .frame(width: CGFloat(map.width) * tileSize,
               height: CGFloat(map.height) * tileSize)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { val in
                    let x = Int(val.location.x / tileSize)
                    let y = Int(val.location.y / tileSize)
                    if map.inBounds(x: x, y: y) {
                        map.paint(x: x, y: y, radius: brushRadius, type: selectedType)
                        onChange()
                    }
                }
        )
    }
}
