import Foundation
import AppKit
import CoreGraphics

// Bibliothèque de textures procédurales pour la vue 3D de l'éditeur de zones.
// Remplace les couleurs plates par des matériaux détaillés qui imitent l'esthétique ORAS.

enum ProceduralTextureKit {

    // MARK: — Textures de tuiles

    static func grassTexture(size: Int = 64) -> NSImage {
        return draw(size: size) { ctx in
            // Sol herbeux de base
            ctx.setFillColor(NSColor(red: 0.36, green: 0.62, blue: 0.24, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

            // Variation noise — brins d'herbe
            var rng = SeededRandom(seed: 0x4772617373)
            for _ in 0..<(size * 3) {
                let x = CGFloat(rng.next() % size)
                let y = CGFloat(rng.next() % size)
                let dark = (rng.next() % 2) == 0
                ctx.setFillColor(NSColor(red: dark ? 0.28 : 0.42,
                                         green: dark ? 0.52 : 0.70,
                                         blue: dark ? 0.18 : 0.30,
                                         alpha: 0.6).cgColor)
                let w = CGFloat(1 + rng.next() % 3)
                let h = CGFloat(2 + rng.next() % 5)
                ctx.fill(CGRect(x: x, y: y, width: w, height: h))
            }
            // Quelques fleurs blanches/jaunes
            for _ in 0..<6 {
                let x = CGFloat(rng.next() % (size - 3))
                let y = CGFloat(rng.next() % (size - 3))
                ctx.setFillColor(NSColor(white: 0.95, alpha: 0.8).cgColor)
                ctx.fillEllipse(in: CGRect(x: x, y: y, width: 2.5, height: 2.5))
            }
        }
    }

    static func stoneWallTexture(size: Int = 64) -> NSImage {
        return draw(size: size) { ctx in
            // Fond pierre gris
            ctx.setFillColor(NSColor(red: 0.48, green: 0.44, blue: 0.38, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

            // Lignes de mortier horizontales
            ctx.setFillColor(NSColor(red: 0.32, green: 0.29, blue: 0.25, alpha: 1).cgColor)
            let brickH = 10
            for row in stride(from: 0, to: size, by: brickH) {
                ctx.fill(CGRect(x: 0, y: row, width: size, height: 1))
            }
            // Lignes verticales décalées (alternance rangées)
            let brickW = 16
            for row in stride(from: 0, to: size, by: brickH) {
                let off = ((row / brickH) % 2 == 0) ? 0 : brickW / 2
                for col in stride(from: off, to: size, by: brickW) {
                    ctx.fill(CGRect(x: col, y: row, width: 1, height: brickH))
                }
            }
            // Légère variation de couleur par brique
            var rng = SeededRandom(seed: 0x5374636B)
            for row in stride(from: 1, to: size, by: brickH) {
                let off = ((row / brickH) % 2 == 0) ? 0 : brickW / 2
                for col in stride(from: off, to: size, by: brickW) {
                    let v = CGFloat(rng.next() % 10) / 100.0
                    ctx.setFillColor(NSColor(red: 0.48+v, green: 0.44+v, blue: 0.38+v, alpha: 0.25).cgColor)
                    ctx.fill(CGRect(x: col+1, y: row+1, width: brickW-2, height: brickH-2))
                }
            }
        }
    }

    static func waterTexture(size: Int = 64) -> NSImage {
        return draw(size: size) { ctx in
            // Fond eau profonde
            ctx.setFillColor(NSColor(red: 0.10, green: 0.38, blue: 0.82, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

            // Reflets de surface — vagues horizontales
            ctx.setFillColor(NSColor(red: 0.35, green: 0.65, blue: 0.98, alpha: 0.5).cgColor)
            for row in stride(from: 5, to: size, by: 10) {
                let path = CGMutablePath()
                path.move(to: CGPoint(x: 0, y: CGFloat(row)))
                for x in stride(from: 0, to: size, by: 4) {
                    let y = CGFloat(row) + sin(Double(x) * 0.4) * 2.0
                    path.addLine(to: CGPoint(x: CGFloat(x), y: y))
                }
                path.addLine(to: CGPoint(x: CGFloat(size), y: CGFloat(row + 2)))
                path.addLine(to: CGPoint(x: 0, y: CGFloat(row + 2)))
                path.closeSubpath()
                ctx.addPath(path); ctx.fillPath()
            }
        }
    }

    static func sandTexture(size: Int = 64) -> NSImage {
        return draw(size: size) { ctx in
            ctx.setFillColor(NSColor(red: 0.92, green: 0.82, blue: 0.58, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
            var rng = SeededRandom(seed: 0x53616E64)
            for _ in 0..<200 {
                let x = CGFloat(rng.next() % size); let y = CGFloat(rng.next() % size)
                let v = CGFloat(rng.next() % 8) / 100.0
                ctx.setFillColor(NSColor(red: 0.88+v, green: 0.78+v, blue: 0.52+v, alpha: 0.4).cgColor)
                ctx.fillEllipse(in: CGRect(x: x, y: y, width: 2, height: 1))
            }
        }
    }

    static func iceTexture(size: Int = 64) -> NSImage {
        return draw(size: size) { ctx in
            ctx.setFillColor(NSColor(red: 0.78, green: 0.92, blue: 0.98, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
            ctx.setFillColor(NSColor(white: 1.0, alpha: 0.5).cgColor)
            for y in stride(from: 0, to: size, by: 12) {
                ctx.fill(CGRect(x: 0, y: y, width: size, height: 1))
            }
            var rng = SeededRandom(seed: 0x49636521)
            for _ in 0..<8 {
                let x = CGFloat(rng.next() % size); let y = CGFloat(rng.next() % size)
                ctx.setFillColor(NSColor(white: 1.0, alpha: 0.35).cgColor)
                ctx.fillEllipse(in: CGRect(x: x-4, y: y-4, width: 8, height: 8))
            }
        }
    }

    static func floorTileTexture(indoor: Bool, size: Int = 64) -> NSImage {
        return draw(size: size) { ctx in
            let base = indoor
                ? NSColor(red: 0.82, green: 0.76, blue: 0.65, alpha: 1)
                : NSColor(red: 0.72, green: 0.68, blue: 0.60, alpha: 1)
            ctx.setFillColor(base.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
            // Grille de carrelage
            ctx.setFillColor(NSColor(red: 0.55, green: 0.50, blue: 0.42, alpha: 0.4).cgColor)
            let tileSize = 16
            for x in stride(from: 0, to: size, by: tileSize) {
                ctx.fill(CGRect(x: x, y: 0, width: 1, height: size))
            }
            for y in stride(from: 0, to: size, by: tileSize) {
                ctx.fill(CGRect(x: 0, y: y, width: size, height: 1))
            }
        }
    }

    // MARK: — Création de scène Sky Dome

    static func skyDomeGeometry(background: ZoneBackground) -> SCNNode? {
        let sphere = SCNSphere(radius: 800)
        sphere.segmentCount = 24

        let mat = SCNMaterial()
        mat.diffuse.contents = skyGradientImage(background: background)
        mat.isDoubleSided = true
        mat.lightingModel = .constant   // pas d'éclairage sur le ciel
        sphere.materials = [mat]

        let node = SCNNode(geometry: sphere)
        node.scale = SCNVector3(-1, 1, 1)   // retourner vers l'intérieur
        return node
    }

    // Thread-safe : utilise CGContext directement, pas NSGraphicsContext.
    private static func skyGradientImage(background: ZoneBackground) -> CGImage? {
        let sz = 256
        guard let ctx = CGContext(
            data: nil, width: sz, height: sz,
            bitsPerComponent: 8, bytesPerRow: sz * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }

        let (top, bot): ([CGFloat], [CGFloat])
        switch background {
        case .outdoor:
            top = [0.30, 0.58, 0.95, 1]; bot = [0.72, 0.88, 0.98, 1]
        case .cave:
            top = [0.04, 0.03, 0.02, 1]; bot = [0.10, 0.08, 0.06, 1]
        case .indoor:
            top = [0.08, 0.08, 0.10, 1]; bot = [0.18, 0.17, 0.15, 1]
        case .water:
            top = [0.05, 0.20, 0.55, 1]; bot = [0.15, 0.40, 0.80, 1]
        default:
            top = [0.05, 0.05, 0.08, 1]; bot = [0.12, 0.12, 0.16, 1]
        }

        let cs = CGColorSpaceCreateDeviceRGB()
        if let botColor = CGColor(colorSpace: cs, components: bot),
           let topColor = CGColor(colorSpace: cs, components: top),
           let grad = CGGradient(colorsSpace: cs,
                                  colors: [botColor, topColor] as CFArray,
                                  locations: [0, 1]) {
            ctx.drawLinearGradient(grad,
                start: CGPoint(x: sz/2, y: 0),
                end:   CGPoint(x: sz/2, y: sz),
                options: [])
        }

        if background == .outdoor {
            let cloud = CGColor(colorSpace: cs, components: [1.0, 1.0, 1.0, 0.35])!
            ctx.setFillColor(cloud)
            for cxPos in stride(from: 20, to: sz, by: 80) {
                let cyPos = sz - 60 - (cxPos % 30)
                ctx.fillEllipse(in: CGRect(x: cxPos, y: cyPos, width: 50, height: 18))
                ctx.fillEllipse(in: CGRect(x: cxPos+15, y: cyPos-10, width: 30, height: 20))
            }
        }

        return ctx.makeImage()
    }

    // MARK: — Utilitaire de dessin (main thread uniquement — pour les fonctions NSImage ci-dessus)

    private static func draw(size: Int, _ block: (CGContext) -> Void) -> NSImage {
        let s = CGFloat(size)
        let image = NSImage(size: NSSize(width: s, height: s))
        image.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext { block(ctx) }
        image.unlockFocus()
        return image
    }
}

// MARK: — Générateur pseudo-aléatoire déterministe (seed fixe → textures reproductibles)

private struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> Int {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Int((state >> 33) & 0x7FFFFFFF)
    }
}

// Importer SceneKit ici pour le sky dome
import SceneKit
