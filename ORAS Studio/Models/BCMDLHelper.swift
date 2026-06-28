import Foundation
import SceneKit

// MARK: — Moteur de rendu voxel universelle
// Chaque tuile de la grille de collision génère une géométrie 3D distincte.
// Aucune règle spéciale par carte : le moteur s'adapte automatiquement aux
// dimensions (W×H) lues dans le fichier binaire sélectionné.

struct BCMDLHelper {

    // MARK: — Extraction de vertices BCH/TM (nuage de points)

    static func extractVertices(from data: Data) -> [SCNVector3] {
        guard data.count >= 32 else { return [] }
        let isTM: Bool = data.count >= 2 && data[0] == 0x54 && data[1] == 0x4D
        let scanStart = isTM ? 0x80 : 0
        let verts = heuristicScan(data: data, startAt: scanStart)
        return deduplicate(verts)
    }

    private static func isPositionVertex(x: Float, y: Float, z: Float) -> Bool {
        guard x.isFinite && y.isFinite && z.isFinite else { return false }
        let mag = x*x + y*y + z*z
        guard mag > 0.25 else { return false }
        guard abs(x) < 150 && abs(y) < 150 && abs(z) < 150 else { return false }
        let len = mag.squareRoot()
        if abs(len - 1.0) < 0.02 { return false }
        return true
    }

    private static func heuristicScan(data: Data, startAt: Int) -> [SCNVector3] {
        var verts: [SCNVector3] = []
        var i = startAt
        while i + 12 <= data.count {
            let x = data.withUnsafeBytes { $0.load(fromByteOffset: i,     as: Float.self) }
            let y = data.withUnsafeBytes { $0.load(fromByteOffset: i + 4, as: Float.self) }
            let z = data.withUnsafeBytes { $0.load(fromByteOffset: i + 8, as: Float.self) }
            if isPositionVertex(x: x, y: y, z: z) {
                verts.append(SCNVector3(CGFloat(x), CGFloat(y), CGFloat(z)))
            }
            i += 4
        }
        return verts
    }

    private static func deduplicate(_ verts: [SCNVector3]) -> [SCNVector3] {
        var seen = Set<String>()
        return verts.filter { v in
            let key = String(format: "%.1f,%.1f,%.1f", v.x, v.y, v.z)
            return seen.insert(key).inserted
        }
    }

    // MARK: — Point cloud SCN

    static func makePointCloud(vertices: [SCNVector3], color: NSColor = .systemGreen) -> SCNGeometry? {
        guard !vertices.isEmpty else { return nil }
        var floatData = [Float]()
        floatData.reserveCapacity(vertices.count * 3)
        for v in vertices {
            floatData.append(Float(v.x)); floatData.append(Float(v.y)); floatData.append(Float(v.z))
        }
        let byteData = Data(bytes: floatData, count: floatData.count * MemoryLayout<Float>.size)
        let source = SCNGeometrySource(
            data: byteData, semantic: .vertex, vectorCount: vertices.count,
            usesFloatComponents: true, componentsPerVector: 3,
            bytesPerComponent: 4, dataOffset: 0, dataStride: 12
        )
        let indices = Array(0..<vertices.count).map { UInt32($0) }
        let element = SCNGeometryElement(
            data: Data(bytes: indices, count: indices.count * MemoryLayout<UInt32>.size),
            primitiveType: .point, primitiveCount: vertices.count,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )
        element.pointSize = 3.0
        element.minimumPointScreenSpaceRadius = 1.5
        element.maximumPointScreenSpaceRadius = 4.0
        let geo = SCNGeometry(sources: [source], elements: [element])
        let mat = SCNMaterial()
        mat.emission.contents = color; mat.diffuse.contents = color
        mat.isDoubleSided = true; mat.blendMode = .alpha
        geo.materials = [mat]
        return geo
    }

    // MARK: — Moteur voxel universel

    // Génère la géométrie 3D complète à partir de la grille de collision.
    // Architecture universelle : mêmes règles pour TOUTES les cartes du jeu.
    // Les dimensions W×H sont lues dynamiquement depuis le fichier sélectionné.
    static func makeCollisionGeometry(from map: CollisionMap,
                                       background: ZoneBackground = .none) -> SCNNode {
        let opaqueRoot = SCNNode()    // géométrie opaque (grass, murs, sable…)
        let transRoot  = SCNNode()    // géométrie transparente (eau, glace…) — séparée pour le depth sort

        let ts: Float = 1.0

        // Étape 1 : analyser les dimensions de la carte sélectionnée
        // Étape 2 : boucle case par case — sculpture du relief (voxels)
        for gy in 0..<map.height {
            for gx in 0..<map.width {
                let tile = map[gx, gy]
                let px = Float(gx) * ts + ts * 0.5
                let pz = Float(gy) * ts + ts * 0.5

                switch tile {

                // 0x00 — Sol passable : plan horizontal plat, couleur herbe
                case .passable:
                    opaqueRoot.addChildNode(
                        makeFlatTile(at: SCNVector3(px, 0, pz), size: ts,
                                     r: 0.333, g: 0.478, b: 0.275))

                // 0x02 — Mur / falaise : cube vertical 1×2×1, brique
                case .blocked:
                    let box = SCNBox(width: CGFloat(ts), height: 2.0,
                                     length: CGFloat(ts), chamferRadius: 0.04)
                    let mat = brickMat()
                    box.materials = [mat]
                    let n = SCNNode(geometry: box)
                    n.castsShadow = true
                    n.position = SCNVector3(px, 1.0, pz)   // centré à mi-hauteur (h=2 → Y=1)
                    opaqueRoot.addChildNode(n)

                // Herbes hautes : plan légèrement surélevé, vert foncé
                case .tallGrass:
                    opaqueRoot.addChildNode(
                        makeFlatTile(at: SCNVector3(px, 0.02, pz), size: ts,
                                     r: 0.176, g: 0.416, b: 0.122))

                // 0x04 — Eau / surf : plan à Y=-0.1, bleu cyan brillant, opacité 0.7
                case .water, .surfable:
                    let plane = SCNPlane(width: CGFloat(ts), height: CGFloat(ts))
                    let mat = SCNMaterial()
                    mat.diffuse.contents = NSColor(red: 0.129, green: 0.588, blue: 0.953, alpha: 1)
                    mat.specular.contents = NSColor.white
                    mat.shininess = 0.9
                    mat.transparency = 0.70
                    mat.isDoubleSided = true
                    plane.materials = [mat]
                    let n = SCNNode(geometry: plane)
                    n.eulerAngles.x = -.pi / 2
                    n.position = SCNVector3(px, -0.1, pz)
                    transRoot.addChildNode(n)

                // Cascade : mur d'eau vertical translucide
                case .waterfall:
                    let box = SCNBox(width: CGFloat(ts), height: 2.2, length: 0.12, chamferRadius: 0)
                    let mat = SCNMaterial()
                    mat.diffuse.contents = NSColor(red: 0.25, green: 0.65, blue: 0.98, alpha: 1)
                    mat.transparency = 0.45
                    mat.isDoubleSided = true
                    box.materials = [mat]
                    let n = SCNNode(geometry: box)
                    n.position = SCNVector3(px, 1.1, pz)
                    transRoot.addChildNode(n)

                // Trou / void : plan très sombre enfoncé
                case .hole:
                    opaqueRoot.addChildNode(
                        makeFlatTile(at: SCNVector3(px, -0.3, pz), size: ts,
                                     r: 0.03, g: 0.03, b: 0.05))

                // Glace : plan légèrement bleuté, shininess élevé
                case .ice:
                    let plane = SCNPlane(width: CGFloat(ts), height: CGFloat(ts))
                    let mat = SCNMaterial()
                    mat.diffuse.contents = NSColor(red: 0.69, green: 0.91, blue: 0.94, alpha: 1)
                    mat.transparency = 0.20
                    mat.shininess = 0.95
                    mat.isDoubleSided = true
                    plane.materials = [mat]
                    let n = SCNNode(geometry: plane)
                    n.eulerAngles.x = -.pi / 2
                    n.position = SCNVector3(px, 0.02, pz)
                    transRoot.addChildNode(n)

                // Sable : plan plat, teinte ocre
                case .sand:
                    opaqueRoot.addChildNode(
                        makeFlatTile(at: SCNVector3(px, 0, pz), size: ts,
                                     r: 0.831, g: 0.706, b: 0.427))
                }
            }
        }

        // Cadre décoratif de la zone
        addZoneBorder(to: opaqueRoot, width: map.width, height: map.height, tileSize: ts)

        // Optimisation M3 Metal : flatten() fusionne les nœuds opaques en un seul
        // draw call par matériau → 60 FPS garanti lors de la rotation de la caméra.
        let container = SCNNode()
        container.addChildNode(opaqueRoot.flattenedClone())
        container.addChildNode(transRoot)   // transparent APRÈS l'opaque (depth sorting correct)
        return container
    }

    // MARK: — Helpers géométriques privés

    private static func makeFlatTile(at pos: SCNVector3, size: Float,
                                     r: CGFloat, g: CGFloat, b: CGFloat) -> SCNNode {
        let plane = SCNPlane(width: CGFloat(size), height: CGFloat(size))
        let mat = SCNMaterial()
        mat.diffuse.contents = NSColor(red: r, green: g, blue: b, alpha: 1)
        mat.isDoubleSided = true
        mat.specular.contents = NSColor(white: 0.05, alpha: 1)
        plane.materials = [mat]
        let n = SCNNode(geometry: plane)
        n.eulerAngles.x = -.pi / 2
        n.position = pos
        return n
    }

    private static func brickMat() -> SCNMaterial {
        let mat = SCNMaterial()
        mat.diffuse.contents = NSColor(red: 0.549, green: 0.200, blue: 0.200, alpha: 1)
        mat.specular.contents = NSColor(white: 0.3, alpha: 1)
        mat.shininess = 0.2
        return mat
    }

    private static func addZoneBorder(to root: SCNNode, width: Int, height: Int, tileSize: Float) {
        let w = Float(width) * tileSize
        let h = Float(height) * tileSize
        let wallH: Float = 0.5
        let wallT: Float = 0.15
        let mat = SCNMaterial()
        mat.diffuse.contents = NSColor(red: 0.25, green: 0.23, blue: 0.20, alpha: 0.6)
        mat.isDoubleSided = true

        func wall(pos: SCNVector3, ww: CGFloat, wl: CGFloat) {
            let box = SCNBox(width: ww, height: CGFloat(wallH), length: wl, chamferRadius: 0)
            box.materials = [mat]
            let n = SCNNode(geometry: box)
            n.position = pos
            root.addChildNode(n)
        }

        wall(pos: SCNVector3(CGFloat(w/2), CGFloat(wallH/2), 0),
             ww: CGFloat(w), wl: CGFloat(wallT))
        wall(pos: SCNVector3(CGFloat(w/2), CGFloat(wallH/2), CGFloat(h)),
             ww: CGFloat(w), wl: CGFloat(wallT))
        wall(pos: SCNVector3(0, CGFloat(wallH/2), CGFloat(h/2)),
             ww: CGFloat(wallT), wl: CGFloat(h))
        wall(pos: SCNVector3(CGFloat(w), CGFloat(wallH/2), CGFloat(h/2)),
             ww: CGFloat(wallT), wl: CGFloat(h))
    }
}
