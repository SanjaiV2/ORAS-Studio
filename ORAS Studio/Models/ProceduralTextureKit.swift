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

    private static func skyGradientImage(background: ZoneBackground) -> NSImage {
        let size = 256
        return draw(size: size) { ctx in
            // Gradient vertical : bas → haut
            let (top, bot): (NSColor, NSColor)
            switch background {
            case .outdoor:
                top = NSColor(red: 0.30, green: 0.58, blue: 0.95, alpha: 1)
                bot = NSColor(red: 0.72, green: 0.88, blue: 0.98, alpha: 1)
            case .cave:
                top = NSColor(red: 0.04, green: 0.03, blue: 0.02, alpha: 1)
                bot = NSColor(red: 0.10, green: 0.08, blue: 0.06, alpha: 1)
            case .indoor:
                top = NSColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1)
                bot = NSColor(red: 0.18, green: 0.17, blue: 0.15, alpha: 1)
            case .water:
                top = NSColor(red: 0.05, green: 0.20, blue: 0.55, alpha: 1)
                bot = NSColor(red: 0.15, green: 0.40, blue: 0.80, alpha: 1)
            default:
                top = NSColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1)
                bot = NSColor(red: 0.12, green: 0.12, blue: 0.16, alpha: 1)
            }
            // Dessin gradient
            let colors = [bot.cgColor, top.cgColor] as CFArray
            let locs: [CGFloat] = [0, 1]
            if let cs = CGColorSpace(name: CGColorSpace.sRGB),
               let grad = CGGradient(colorsSpace: cs, colors: colors, locations: locs) {
                ctx.drawLinearGradient(grad,
                    start: CGPoint(x: size/2, y: 0),
                    end:   CGPoint(x: size/2, y: size),
                    options: [])
            }
            // Quelques nuages simples (outdoor seulement)
            if background == .outdoor {
                ctx.setFillColor(NSColor(white: 1.0, alpha: 0.35).cgColor)
                for cx in stride(from: 20, to: size, by: 80) {
                    let cy = size - 60 - (cx % 30)
                    ctx.fillEllipse(in: CGRect(x: cx, y: cy, width: 50, height: 18))
                    ctx.fillEllipse(in: CGRect(x: cx+15, y: cy-10, width: 30, height: 20))
                }
            }
        }
    }

    // MARK: — Utilitaire de dessin

    private static func draw(size: Int, _ block: (CGContext) -> Void) -> NSImage {
        let s = CGFloat(size)
        let image = NSImage(size: NSSize(width: s, height: s))
        image.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            block(ctx)
        }
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
