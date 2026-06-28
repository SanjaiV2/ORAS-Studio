import Foundation
import SceneKit

struct BCMDLHelper {

    // Extrait les positions 3D depuis un fichier TM (a/2/5/7) ou buffer générique.
    // Format TM : "TM" magic → BCH à l'offset 0x80.
    // On scanne les triples f32 valides en excluant les vecteurs unitaires (normales).
    static func extractVertices(from data: Data) -> [SCNVector3] {
        guard data.count >= 32 else { return [] }

        // Détecter le format TM (terrain mesh ORAS) : magic "TM" à l'offset 0
        let isTM: Bool = data.count >= 2
            && data[0] == 0x54   // 'T'
            && data[1] == 0x4D   // 'M'

        // Pour TM: le BCH utile commence à 0x80 et la zone de vertex intéressante
        // est entre 0x80 et la fin du fichier. On saute le header NW4C/BCH (64B).
        let scanStart = isTM ? 0x80 : 0
        let verts = heuristicScan(data: data, startAt: scanStart, excludeNormals: true)
        return deduplicate(verts)
    }

    // Filtre strict : position valide, ni nulle ni vecteur unitaire (normale)
    private static func isPositionVertex(x: Float, y: Float, z: Float) -> Bool {
        guard x.isFinite && y.isFinite && z.isFinite else { return false }
        let mag = x*x + y*y + z*z
        guard mag > 0.25 else { return false }               // skip near-zero
        guard abs(x) < 150 && abs(y) < 150 && abs(z) < 150 else { return false }
        // Exclure les vecteurs unitaires (normales BCH : longueur ≈ 1)
        let len = mag.squareRoot()
        if abs(len - 1.0) < 0.02 { return false }
        return true
    }

    // Scan heuristique stride=4 — collecte toutes les positions valides
    private static func heuristicScan(data: Data, startAt: Int, excludeNormals: Bool) -> [SCNVector3] {
        var verts: [SCNVector3] = []
        var i = startAt
        while i + 12 <= data.count {
            let x = data.withUnsafeBytes { $0.load(fromByteOffset: i,     as: Float.self) }
            let y = data.withUnsafeBytes { $0.load(fromByteOffset: i + 4, as: Float.self) }
            let z = data.withUnsafeBytes { $0.load(fromByteOffset: i + 8, as: Float.self) }
            if excludeNormals ? isPositionVertex(x: x, y: y, z: z)
                               : (x.isFinite && y.isFinite && z.isFinite) {
                verts.append(SCNVector3(CGFloat(x), CGFloat(y), CGFloat(z)))
            }
            i += 4
        }
        return verts
    }

    // Déduplique à 0.1 unité près
    private static func deduplicate(_ verts: [SCNVector3]) -> [SCNVector3] {
        var seen = Set<String>()
        return verts.filter { v in
            let key = String(format: "%.1f,%.1f,%.1f", v.x, v.y, v.z)
            return seen.insert(key).inserted
        }
    }

    // Crée une SCNGeometry point cloud depuis les vertices
    static func makePointCloud(vertices: [SCNVector3], color: NSColor = .systemGreen) -> SCNGeometry? {
        guard !vertices.isEmpty else { return nil }

        // Convertit en tableau de Float (compatible SCNGeometrySource sur toutes plateformes)
        var floatData = [Float]()
        floatData.reserveCapacity(vertices.count * 3)
        for v in vertices {
            floatData.append(Float(v.x))
            floatData.append(Float(v.y))
            floatData.append(Float(v.z))
        }
        let byteData = Data(bytes: floatData, count: floatData.count * MemoryLayout<Float>.size)

        let source = SCNGeometrySource(
            data: byteData,
            semantic: .vertex,
            vectorCount: vertices.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: 4,
            dataOffset: 0,
            dataStride: 12
        )

        let indices = Array(0..<vertices.count).map { UInt32($0) }
        let element = SCNGeometryElement(
            data: Data(bytes: indices, count: indices.count * MemoryLayout<UInt32>.size),
            primitiveType: .point,
            primitiveCount: vertices.count,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )
        element.pointSize = 3.0
        element.minimumPointScreenSpaceRadius = 1.5
        element.maximumPointScreenSpaceRadius = 4.0

        let geo = SCNGeometry(sources: [source], elements: [element])
        let mat = SCNMaterial()
        mat.emission.contents = color
        mat.diffuse.contents = color
        mat.isDoubleSided = true
        mat.blendMode = .alpha
        geo.materials = [mat]
        return geo
    }

    // Crée la géométrie de collision 3D haute-fidélité avec textures procédurales
    static func makeCollisionGeometry(from map: CollisionMap,
                                       background: ZoneBackground = .none) -> SCNNode {
        let root = SCNNode()
        let ts: Float = 1.0  // tile size

        // Sol de base texturé selon le type de zone
        let floorGeo = SCNPlane(width: CGFloat(ts * Float(map.width)),
                                height: CGFloat(ts * Float(map.height)))
        let floorMat = SCNMaterial()
        switch background {
        case .outdoor:
            floorMat.diffuse.contents = ProceduralTextureKit.grassTexture(size: 64)
        case .indoor:
            floorMat.diffuse.contents = ProceduralTextureKit.floorTileTexture(indoor: true)
        case .cave:
            floorMat.diffuse.contents = ProceduralTextureKit.stoneWallTexture(size: 64)
        case .water:
            floorMat.diffuse.contents = ProceduralTextureKit.waterTexture(size: 64)
        default:
            floorMat.diffuse.contents = ProceduralTextureKit.floorTileTexture(indoor: false)
        }
        floorMat.diffuse.wrapS = .repeat
        floorMat.diffuse.wrapT = .repeat
        floorMat.diffuse.contentsTransform = SCNMatrix4MakeScale(
            CGFloat(map.width) / 4, CGFloat(map.height) / 4, 1)
        floorMat.specular.contents = NSColor(white: 0.1, alpha: 1)
        floorMat.shininess = 0.05
        floorGeo.materials = [floorMat]
        let floorNode = SCNNode(geometry: floorGeo)
        floorNode.eulerAngles.x = -.pi / 2
        floorNode.position = SCNVector3(CGFloat(ts * Float(map.width) / 2), -0.01,
                                        CGFloat(ts * Float(map.height) / 2))
        root.addChildNode(floorNode)

        // Tuiles spéciales uniquement
        for y in 0..<map.height {
            for x in 0..<map.width {
                let tile = map[x, y]
                guard tile != .passable else { continue }

                struct TileSpec {
                    var h: Float; var y0: Float
                    var texture: NSImage?
                    var color: NSColor
                    var emR: Float = 0
                    var shininess: CGFloat = 0.1
                    var isTransparent: Bool = false
                }
                let spec: TileSpec
                switch tile {
                case .blocked:
                    spec = TileSpec(h: 2.8, y0: 1.4,
                                    texture: ProceduralTextureKit.stoneWallTexture(),
                                    color: NSColor(red: 0.55, green: 0.48, blue: 0.42, alpha: 1))
                case .tallGrass:
                    spec = TileSpec(h: 0.40, y0: 0.20,
                                    texture: ProceduralTextureKit.grassTexture(),
                                    color: NSColor(red: 0.22, green: 0.62, blue: 0.16, alpha: 1))
                case .water:
                    spec = TileSpec(h: 0.10, y0: -0.03,
                                    texture: ProceduralTextureKit.waterTexture(),
                                    color: NSColor(red: 0.15, green: 0.40, blue: 0.90, alpha: 0.80),
                                    shininess: 0.8, isTransparent: true)
                case .surfable:
                    spec = TileSpec(h: 0.10, y0: -0.03,
                                    texture: ProceduralTextureKit.waterTexture(),
                                    color: NSColor(red: 0.10, green: 0.55, blue: 0.95, alpha: 0.80),
                                    emR: 0.05, shininess: 0.9, isTransparent: true)
                case .waterfall:
                    spec = TileSpec(h: 2.2, y0: 1.1,
                                    texture: ProceduralTextureKit.waterTexture(),
                                    color: NSColor(red: 0.30, green: 0.58, blue: 0.98, alpha: 0.85),
                                    emR: 0.20, shininess: 0.7, isTransparent: true)
                case .hole:
                    spec = TileSpec(h: 0.06, y0: -0.12,
                                    texture: nil,
                                    color: NSColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1))
                case .ice:
                    spec = TileSpec(h: 0.12, y0: 0.06,
                                    texture: ProceduralTextureKit.iceTexture(),
                                    color: NSColor(red: 0.72, green: 0.93, blue: 0.97, alpha: 0.85),
                                    emR: 0.10, shininess: 0.95, isTransparent: true)
                case .sand:
                    spec = TileSpec(h: 0.20, y0: 0.10,
                                    texture: ProceduralTextureKit.sandTexture(),
                                    color: NSColor(red: 0.92, green: 0.82, blue: 0.50, alpha: 1))
                default:
                    spec = TileSpec(h: 0.10, y0: 0.05, texture: nil, color: .gray)
                }

                let gap: CGFloat = tile == .blocked ? 0.02 : 0.05
                let box = SCNBox(width:  CGFloat(ts) - gap,
                                 height: CGFloat(spec.h),
                                 length: CGFloat(ts) - gap,
                                 chamferRadius: tile == .blocked ? 0.05 : 0.08)
                let mat = SCNMaterial()
                if let tex = spec.texture {
                    mat.diffuse.contents = tex
                    mat.diffuse.wrapS = .repeat; mat.diffuse.wrapT = .repeat
                } else {
                    mat.diffuse.contents = spec.color
                }
                if spec.emR > 0 {
                    mat.emission.contents = spec.color.withAlphaComponent(CGFloat(spec.emR))
                }
                mat.specular.contents = NSColor.white
                mat.shininess = spec.shininess
                mat.isDoubleSided = tile == .waterfall
                if spec.isTransparent { mat.transparency = tile == .hole ? 1.0 : 0.85 }
                box.materials = [mat]

                let node = SCNNode(geometry: box)
                node.position = SCNVector3(
                    CGFloat(Float(x) * ts + ts / 2),
                    CGFloat(spec.y0),
                    CGFloat(Float(y) * ts + ts / 2)
                )
                root.addChildNode(node)
            }
        }

        // Bordure décorative (mur de cadre autour de la zone)
        addZoneBorder(to: root, width: map.width, height: map.height, tileSize: ts)
        return root
    }

    private static func addZoneBorder(to root: SCNNode, width: Int, height: Int, tileSize: Float) {
        let w = Float(width) * tileSize
        let h = Float(height) * tileSize
        let wallH: Float = 0.5
        let wallT: Float = 0.15
        let wallColor = NSColor(red: 0.3, green: 0.28, blue: 0.25, alpha: 0.6)
        let wallMat = SCNMaterial()
        wallMat.diffuse.contents = wallColor
        wallMat.isDoubleSided = true

        func wall(pos: SCNVector3, ww: CGFloat, wl: CGFloat) {
            let box = SCNBox(width: ww, height: CGFloat(wallH), length: wl, chamferRadius: 0)
            box.materials = [wallMat]
            let n = SCNNode(geometry: box)
            n.position = pos
            root.addChildNode(n)
        }

        // 4 côtés
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
