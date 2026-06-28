import Foundation
import SceneKit

struct BCMDLHelper {

    // Extrait les positions 3D depuis un buffer NW4C ou vertex raw
    // Retourne les vertices (x, y, z) dans le système de coordonnées jeu
    static func extractVertices(from data: Data) -> [SCNVector3] {
        guard data.count >= 32 else { return [] }

        // Détecter le type : NW4C (commence avec header 0x1C/0xFEFF) ou raw floats
        let isNW4C: Bool
        if data.count >= 8 {
            let hdrSz = data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self) }
            let bom   = data.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt16.self) }
            isNW4C = (hdrSz == 0x1C && bom == 0xFEFF)
        } else {
            isNW4C = false
        }

        let startOffset = isNW4C ? 0x1000 : 0  // NW4C vertex data après header+sections
        let stride = 32  // 12B pos + 12B normal + 8B UV

        var verts: [SCNVector3] = []
        var off = startOffset
        while off + 12 <= data.count {
            let x = data.withUnsafeBytes { $0.load(fromByteOffset: off,     as: Float.self) }
            let y = data.withUnsafeBytes { $0.load(fromByteOffset: off + 4, as: Float.self) }
            let z = data.withUnsafeBytes { $0.load(fromByteOffset: off + 8, as: Float.self) }

            if isValidVertex(x: x, y: y, z: z) {
                verts.append(SCNVector3(CGFloat(x), CGFloat(y), CGFloat(z)))
            }
            off += stride
        }

        // Si pas assez de résultats, tenter un scan heuristique (stride 4)
        if verts.count < 10 {
            verts = heuristicScan(data: data, startAt: startOffset)
        }

        return deduplicate(verts)
    }

    // Filtre les valeurs aberrantes
    private static func isValidVertex(x: Float, y: Float, z: Float) -> Bool {
        guard x.isFinite && y.isFinite && z.isFinite else { return false }
        guard x != 0 || y != 0 || z != 0 else { return false }  // skip zero
        let range: Float = 200.0
        return abs(x) < range && abs(y) < range && abs(z) < range
    }

    // Scan heuristique : essaie stride=4 et cherche des triplets cohérents
    private static func heuristicScan(data: Data, startAt: Int) -> [SCNVector3] {
        var verts: [SCNVector3] = []
        var i = startAt
        while i + 12 <= data.count {
            let x = data.withUnsafeBytes { $0.load(fromByteOffset: i,     as: Float.self) }
            let y = data.withUnsafeBytes { $0.load(fromByteOffset: i + 4, as: Float.self) }
            let z = data.withUnsafeBytes { $0.load(fromByteOffset: i + 8, as: Float.self) }
            if isValidVertex(x: x, y: y, z: z) {
                verts.append(SCNVector3(CGFloat(x), CGFloat(y), CGFloat(z)))
            }
            i += 4
        }
        return verts
    }

    // Supprime les doublons (à 0.01 près)
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

    // Crée la géométrie de collision 3D (fallback si pas de BCMDL)
    static func makeCollisionGeometry(from map: CollisionMap) -> SCNNode {
        let root = SCNNode()
        let tileSize: Float = 1.0

        for y in 0..<map.height {
            for x in 0..<map.width {
                let tile = map[x, y]
                guard tile != .passable else { continue }

                let height: Float
                let color: NSColor
                switch tile {
                case .blocked:          height = 1.5; color = NSColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 0.7)
                case .tallGrass:        height = 0.3; color = NSColor(red: 0.2, green: 0.7, blue: 0.2, alpha: 0.6)
                case .water, .surfable: height = 0.1; color = NSColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 0.6)
                case .waterfall:        height = 0.8; color = NSColor(red: 0.3, green: 0.5, blue: 1.0, alpha: 0.7)
                case .hole:             height = 0.1; color = NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 0.9)
                case .ice:              height = 0.15; color = NSColor(red: 0.6, green: 0.9, blue: 0.9, alpha: 0.6)
                case .sand:             height = 0.2; color = NSColor(red: 0.9, green: 0.8, blue: 0.3, alpha: 0.6)
                default:                height = 0.1; color = NSColor.gray
                }

                let box = SCNBox(width: CGFloat(tileSize * 0.9), height: CGFloat(height),
                                 length: CGFloat(tileSize * 0.9), chamferRadius: 0.05)
                let mat = SCNMaterial()
                mat.diffuse.contents = color
                mat.emission.contents = color.withAlphaComponent(0.1)
                mat.isDoubleSided = true
                box.materials = [mat]

                let node = SCNNode(geometry: box)
                node.position = SCNVector3(
                    CGFloat(Float(x) * tileSize + tileSize / 2),
                    CGFloat(height / 2),
                    CGFloat(Float(y) * tileSize + tileSize / 2)
                )
                root.addChildNode(node)
            }
        }
        return root
    }
}
