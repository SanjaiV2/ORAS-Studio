import Foundation
import SceneKit
import AppKit

// Moteur de rendu voxel universel — même logique pour toutes les cartes.
// Architecture : 1 plan de sol texturé (color-map pixel/tile) + objets 3D
// par-dessus. Aucun flattenedClone() qui corrompt les matériaux.

struct BCMDLHelper {

    // MARK: — Point cloud (données brutes BCH/TM)

    static func extractVertices(from data: Data) -> [SCNVector3] {
        guard data.count >= 32 else { return [] }
        let isTM = data.count >= 2 && data[0] == 0x54 && data[1] == 0x4D
        return deduplicate(heuristicScan(data: data, startAt: isTM ? 0x80 : 0))
    }

    private static func isPositionVertex(x: Float, y: Float, z: Float) -> Bool {
        guard x.isFinite && y.isFinite && z.isFinite else { return false }
        let mag = x*x + y*y + z*z
        guard mag > 0.25, abs(x) < 150, abs(y) < 150, abs(z) < 150 else { return false }
        return abs(mag.squareRoot() - 1.0) >= 0.02
    }

    private static func heuristicScan(data: Data, startAt: Int) -> [SCNVector3] {
        var out: [SCNVector3] = []
        var i = startAt
        while i + 12 <= data.count {
            let x = data.withUnsafeBytes { $0.load(fromByteOffset: i,     as: Float.self) }
            let y = data.withUnsafeBytes { $0.load(fromByteOffset: i + 4, as: Float.self) }
            let z = data.withUnsafeBytes { $0.load(fromByteOffset: i + 8, as: Float.self) }
            if isPositionVertex(x: x, y: y, z: z) {
                out.append(SCNVector3(CGFloat(x), CGFloat(y), CGFloat(z)))
            }
            i += 4
        }
        return out
    }

    private static func deduplicate(_ verts: [SCNVector3]) -> [SCNVector3] {
        var seen = Set<String>()
        return verts.filter {
            seen.insert(String(format: "%.1f,%.1f,%.1f", $0.x, $0.y, $0.z)).inserted
        }
    }

    static func makePointCloud(vertices: [SCNVector3], color: NSColor = .systemGreen) -> SCNGeometry? {
        guard !vertices.isEmpty else { return nil }
        var floatBuf = [Float]()
        floatBuf.reserveCapacity(vertices.count * 3)
        for v in vertices { floatBuf += [Float(v.x), Float(v.y), Float(v.z)] }
        let data = Data(bytes: floatBuf, count: floatBuf.count * 4)
        let src = SCNGeometrySource(data: data, semantic: .vertex,
            vectorCount: vertices.count, usesFloatComponents: true,
            componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12)
        let idx = Array(0..<vertices.count).map { UInt32($0) }
        let el = SCNGeometryElement(
            data: Data(bytes: idx, count: idx.count * 4),
            primitiveType: .point, primitiveCount: vertices.count, bytesPerIndex: 4)
        el.pointSize = 3; el.minimumPointScreenSpaceRadius = 1.5; el.maximumPointScreenSpaceRadius = 4
        let geo = SCNGeometry(sources: [src], elements: [el])
        let mat = SCNMaterial()
        mat.emission.contents = color; mat.diffuse.contents = color
        mat.isDoubleSided = true; mat.blendMode = .alpha
        geo.materials = [mat]
        return geo
    }

    // MARK: — Moteur de rendu universel

    // Étape 1 : génère la texture de sol (1 pixel = 1 tuile × 8)
    // Étape 2 : place la geometry 3D (arbres, murs, eau)
    // Adapte automatiquement à n'importe quelle dimension W×H.
    static func makeCollisionGeometry(from map: CollisionMap,
                                       background: ZoneBackground = .none) -> SCNNode {
        let container = SCNNode()
        let W = map.width, H = map.height
        let ts: CGFloat = 1.0

        // ── Étape 1 : plan de sol unique avec color-map ──
        let floorGeo  = SCNPlane(width: CGFloat(W) * ts, height: CGFloat(H) * ts)
        let floorMat  = SCNMaterial()
        floorMat.diffuse.contents  = makeGroundTexture(map: map)  // CGImage, thread-safe
        floorMat.diffuse.wrapS    = .clamp
        floorMat.diffuse.wrapT    = .clamp
        floorMat.isDoubleSided    = true
        floorMat.specular.contents = NSColor(white: 0.05, alpha: 1)
        floorGeo.materials = [floorMat]
        let floorNode = SCNNode(geometry: floorGeo)
        floorNode.eulerAngles.x = -.pi / 2
        floorNode.position = SCNVector3(CGFloat(W) * ts / 2, 0, CGFloat(H) * ts / 2)
        container.addChildNode(floorNode)

        // ── Étape 2 : sculpture 3D case par case ──
        // Classification des blocs (flood-fill) : petit composant → arbre, grand → mur
        let treeMap = classifyBlockedTiles(map)

        for gy in 0..<H {
            for gx in 0..<W {
                let tile = map[gx, gy]
                let px = Float(gx) + 0.5
                let pz = Float(gy) + 0.5

                switch tile {
                case .blocked:
                    if treeMap[gx][gy] {
                        // Arbre : cylindre tronc + sphère feuillage
                        container.addChildNode(makeTreeNode(x: px, z: pz))
                    } else {
                        // Mur / falaise / bâtiment selon le contexte de la zone
                        container.addChildNode(makeWallNode(
                            x: px, z: pz,
                            isOutdoor: background == .outdoor || background == .water))
                    }

                case .water, .surfable:
                    // Overlay transparent bleu au-dessus du sol
                    let wNode = makeWaterOverlay(x: px, z: pz)
                    container.addChildNode(wNode)

                case .waterfall:
                    // Mur d'eau vertical translucide
                    container.addChildNode(makeWaterfallNode(x: px, z: pz))

                case .ice:
                    // Plan légèrement surélevé brillant
                    container.addChildNode(makeIceOverlay(x: px, z: pz))

                default:
                    break   // passable/herbes/sable/trou = dessiné dans la texture uniquement
                }
            }
        }

        // Cadre décoratif
        addBorder(to: container, width: W, height: H)
        return container
    }

    // MARK: — Texture de sol (color-map, thread-safe)

    // Utilise CGContext directement — aucune dépendance NSGraphicsContext/main thread.
    private static func makeGroundTexture(map: CollisionMap) -> CGImage? {
        let px = 8
        let W = map.width, H = map.height
        let imgW = W * px, imgH = H * px

        guard let ctx = CGContext(
            data: nil, width: imgW, height: imgH,
            bitsPerComponent: 8, bytesPerRow: imgW * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }

        let cs = CGColorSpaceCreateDeviceRGB()
        for gy in 0..<H {
            for gx in 0..<W {
                let comps: [CGFloat]
                switch map[gx, gy] {
                case .passable, .blocked: comps = [0.290, 0.478, 0.220, 1]
                case .tallGrass:          comps = [0.180, 0.370, 0.140, 1]
                case .water, .surfable:   comps = [0.220, 0.600, 0.870, 1]
                case .waterfall:          comps = [0.300, 0.640, 0.910, 1]
                case .hole:               comps = [0.060, 0.055, 0.070, 1]
                case .ice:                comps = [0.670, 0.890, 0.920, 1]
                case .sand:               comps = [0.780, 0.680, 0.420, 1]
                }
                if let color = CGColor(colorSpace: cs, components: comps) {
                    ctx.setFillColor(color)
                }
                let ry = (H - 1 - gy) * px   // Y=0 bas pour NSImage / SCNMaterial
                ctx.fill(CGRect(x: gx * px, y: ry, width: px, height: px))
            }
        }
        return ctx.makeImage()
    }

    // MARK: — Classification des tuiles bloquées (BFS)
    // Composant connexe ≤ 8 tuiles → arbre/rocher ; > 8 → mur/bâtiment.

    private static func classifyBlockedTiles(_ map: CollisionMap) -> [[Bool]] {
        let W = map.width, H = map.height
        var result  = Array(repeating: Array(repeating: false, count: H), count: W)
        var visited = Array(repeating: Array(repeating: false, count: H), count: W)

        for sy in 0..<H {
            for sx in 0..<W {
                guard map[sx, sy] == .blocked, !visited[sx][sy] else { continue }
                var component: [(Int, Int)] = []
                var queue = [(sx, sy)]
                visited[sx][sy] = true
                var head = 0
                while head < queue.count {
                    let (cx, cy) = queue[head]; head += 1
                    component.append((cx, cy))
                    for (dx, dz) in [(0,1),(0,-1),(1,0),(-1,0)] {
                        let nx = cx + dx, ny = cy + dz
                        guard nx >= 0 && nx < W && ny >= 0 && ny < H else { continue }
                        guard !visited[nx][ny] && map[nx, ny] == .blocked  else { continue }
                        visited[nx][ny] = true
                        queue.append((nx, ny))
                    }
                }
                let isTree = component.count <= 8
                for (tx, ty) in component { result[tx][ty] = isTree }
            }
        }
        return result
    }

    // MARK: — Géométries 3D

    // Arbre : tronc cylindrique marron + sphère feuillage vert foncé
    static func makeTreeNode(x: Float, z: Float) -> SCNNode {
        let root = SCNNode()
        // Tronc
        let trunk = SCNCylinder(radius: 0.13, height: 0.55)
        let tMat  = SCNMaterial()
        tMat.diffuse.contents = NSColor(red: 0.33, green: 0.20, blue: 0.10, alpha: 1)
        trunk.materials = [tMat]
        let tNode = SCNNode(geometry: trunk)
        tNode.position = SCNVector3(x, 0.28, z)
        // Feuillage
        let foliage = SCNSphere(radius: 0.60)
        let fMat    = SCNMaterial()
        fMat.diffuse.contents = NSColor(red: 0.145, green: 0.440, blue: 0.120, alpha: 1)
        fMat.specular.contents = NSColor(white: 0.08, alpha: 1)
        foliage.materials = [fMat]
        let fNode = SCNNode(geometry: foliage)
        fNode.position = SCNVector3(x, 0.85, z)
        root.addChildNode(tNode)
        root.addChildNode(fNode)
        return root
    }

    // Mur / bloc : bâtiment pour les grands groupes de tuiles bloquées
    static func makeWallNode(x: Float, z: Float, isOutdoor: Bool) -> SCNNode {
        let h: CGFloat = isOutdoor ? 1.0 : 1.5
        let box = SCNBox(width: 0.96, height: h, length: 0.96, chamferRadius: 0.04)
        let mat = SCNMaterial()
        // Outdoor → brun falaise/roche ; Indoor → gris béton
        mat.diffuse.contents = isOutdoor
            ? NSColor(red: 0.46, green: 0.34, blue: 0.22, alpha: 1)
            : NSColor(red: 0.62, green: 0.60, blue: 0.58, alpha: 1)
        mat.specular.contents = NSColor(white: 0.15, alpha: 1)
        mat.shininess = 0.15
        box.materials = [mat]
        let node = SCNNode(geometry: box)
        node.position = SCNVector3(x, Float(h / 2), z)
        node.castsShadow = true
        return node
    }

    // Overlay eau translucide
    private static func makeWaterOverlay(x: Float, z: Float) -> SCNNode {
        let geo = SCNPlane(width: 0.98, height: 0.98)
        let mat = SCNMaterial()
        mat.diffuse.contents  = NSColor(red: 0.20, green: 0.62, blue: 0.91, alpha: 1)
        mat.transparency      = 0.55
        mat.shininess         = 0.92
        mat.specular.contents = NSColor.white
        mat.isDoubleSided     = true
        geo.materials = [mat]
        let n = SCNNode(geometry: geo)
        n.eulerAngles.x = -.pi / 2
        n.position = SCNVector3(x, 0.02, z)
        return n
    }

    // Mur d'eau vertical
    private static func makeWaterfallNode(x: Float, z: Float) -> SCNNode {
        let box = SCNBox(width: 0.95, height: 2.0, length: 0.12, chamferRadius: 0)
        let mat = SCNMaterial()
        mat.diffuse.contents = NSColor(red: 0.28, green: 0.64, blue: 0.96, alpha: 1)
        mat.transparency = 0.42
        mat.isDoubleSided = true
        box.materials = [mat]
        let n = SCNNode(geometry: box)
        n.position = SCNVector3(x, 1.0, z)
        return n
    }

    // Overlay glace brillant
    private static func makeIceOverlay(x: Float, z: Float) -> SCNNode {
        let geo = SCNPlane(width: 0.98, height: 0.98)
        let mat = SCNMaterial()
        mat.diffuse.contents  = NSColor(red: 0.72, green: 0.93, blue: 0.97, alpha: 1)
        mat.transparency      = 0.30
        mat.shininess         = 0.98
        mat.specular.contents = NSColor.white
        mat.isDoubleSided     = true
        geo.materials = [mat]
        let n = SCNNode(geometry: geo)
        n.eulerAngles.x = -.pi / 2
        n.position = SCNVector3(x, 0.03, z)
        return n
    }

    // Cadre décoratif autour de la zone
    private static func addBorder(to root: SCNNode, width: Int, height: Int) {
        let W = Float(width), H = Float(height)
        let bh: Float = 0.4
        let mat = SCNMaterial()
        mat.diffuse.contents = NSColor(red: 0.22, green: 0.18, blue: 0.14, alpha: 1)
        mat.isDoubleSided = true

        func wall(_ pos: SCNVector3, _ ww: CGFloat, _ wl: CGFloat) {
            let box = SCNBox(width: ww, height: CGFloat(bh), length: wl, chamferRadius: 0)
            box.materials = [mat]
            let n = SCNNode(geometry: box); n.position = pos
            root.addChildNode(n)
        }
        wall(SCNVector3(CGFloat(W/2), CGFloat(bh/2), 0),  CGFloat(W + 0.3), 0.3)
        wall(SCNVector3(CGFloat(W/2), CGFloat(bh/2), CGFloat(H)), CGFloat(W + 0.3), 0.3)
        wall(SCNVector3(0, CGFloat(bh/2), CGFloat(H/2)),  0.3, CGFloat(H + 0.3))
        wall(SCNVector3(CGFloat(W), CGFloat(bh/2), CGFloat(H/2)), 0.3, CGFloat(H + 0.3))
    }
}
