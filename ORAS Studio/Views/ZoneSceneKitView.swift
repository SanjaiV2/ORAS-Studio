import SwiftUI
import SceneKit
import AppKit

// Wrapper SCNView propre — pas de prepare() (race condition emptyScene vs builtScene).
// La scène est construite dans Task.detached, donc l'assignation directe est rapide.
private struct SCNViewRepresentable: NSViewRepresentable {
    let scene: SCNScene

    func makeNSView(context: Context) -> SCNView {
        let v = SCNView()
        v.allowsCameraControl = true
        v.autoenablesDefaultLighting = false
        v.antialiasingMode = .multisampling4X
        v.backgroundColor = NSColor(white: 0.96, alpha: 1)
        v.showsStatistics = false
        return v
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        guard nsView.scene !== scene else { return }
        nsView.scene = scene
    }
}

struct ZoneSceneKitView: View {
    let collisionMap: CollisionMap
    let bchMeshes: [BCHParser.MeshData]
    let entityMarkers: [ZoneEntityMarker]
    let background: ZoneBackground

    @State private var scene   = SCNScene()
    @State private var building = false

    var body: some View {
        ZStack {
            SCNViewRepresentable(scene: scene)

            if building {
                ProgressView("Construction…")
                    .padding(14)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        // Déclenche une reconstruction uniquement quand les données changent
        .task(id: sceneKey) {
            building = true
            let map    = collisionMap
            let meshes = bchMeshes
            let marks  = entityMarkers
            let bg     = background
            let built  = await Task.detached(priority: .userInitiated) {
                Self.buildScene(collisionMap: map, bchMeshes: meshes,
                                entityMarkers: marks, background: bg)
            }.value
            scene   = built
            building = false
        }
    }

    private var sceneKey: String {
        "\(collisionMap.width)x\(collisionMap.height)-\(background)-\(bchMeshes.count)-\(entityMarkers.count)"
    }

    // MARK: — Construction statique (thread-safe, appelée depuis Task.detached)

    nonisolated static func buildScene(collisionMap: CollisionMap,
                           bchMeshes: [BCHParser.MeshData],
                           entityMarkers: [ZoneEntityMarker],
                           background: ZoneBackground) -> SCNScene {
        let scene = SCNScene()
        let W = collisionMap.width, H = collisionMap.height
        let cx = CGFloat(W) / 2, cz = CGFloat(H) / 2

        // ── Terrain voxel tuile par tuile ──
        let terrain = makeVoxelTerrain(map: collisionMap, background: background)
        scene.rootNode.addChildNode(terrain)

        // ── Géométrie réelle BCH (terrain 3DS) si disponible ──
        if !bchMeshes.isEmpty {
            let bchNode = BCHParser.toSCNNode(meshes: bchMeshes, scale: 1.0 / 16.0)
            bchNode.position = SCNVector3(0, 0, 0)
            scene.rootNode.addChildNode(bchNode)
        }

        // ── Entités 3D ──
        for marker in entityMarkers {
            if let node = makeEntityNode(marker: marker, background: background) {
                scene.rootNode.addChildNode(node)
            }
        }

        // ── Caméra isométrique front-right (style exemple) ──
        let cam = SCNCamera()
        cam.fieldOfView = 55
        cam.zNear = 0.5; cam.zFar = 2000
        let camNode = SCNNode(); camNode.camera = cam
        let ext = max(CGFloat(W), CGFloat(H))
        // Légèrement décalé à droite, bien en avant et en hauteur
        camNode.position = SCNVector3(cx + ext * 0.15, ext * 0.70, cz + ext * 0.90)
        camNode.look(at: SCNVector3(cx, 0, cz))
        scene.rootNode.addChildNode(camNode)

        // ── Éclairage ──
        addLighting(to: scene, background: background)

        return scene
    }

    // MARK: — Rendu voxel (1 SCNBox par tuile)

    private static func makeVoxelTerrain(map: CollisionMap,
                                          background: ZoneBackground) -> SCNNode {
        let root = SCNNode()
        let isTree = classifyBlockedTiles(map)

        // Matériaux partagés pour limiter les draw calls
        let matGrass    = mat(r:0.34, g:0.60, b:0.22)
        let matTallGrass = mat(r:0.24, g:0.50, b:0.15)
        let matSand     = mat(r:0.90, g:0.80, b:0.54)
        let matIce      = mat(r:0.70, g:0.88, b:0.96)
        let matCliff    = mat(r:0.62, g:0.35, b:0.18)  // terracotta brun-orange
        let matWater    = mat(r:0.18, g:0.52, b:0.88, alpha:0.88)
        let matWaterfall = mat(r:0.26, g:0.60, b:0.96, alpha:0.75)
        let matHole     = mat(r:0.06, g:0.05, b:0.07)

        for gy in 0..<map.height {
            for gx in 0..<map.width {
                let tile = map[gx, gy]
                let x = Float(gx) + 0.5
                let z = Float(gy) + 0.5

                switch tile {
                case .passable:
                    root.addChildNode(voxel(x:x, z:z, h:0.40, m:matGrass))
                case .tallGrass:
                    root.addChildNode(voxel(x:x, z:z, h:0.44, m:matTallGrass))
                case .sand:
                    root.addChildNode(voxel(x:x, z:z, h:0.38, m:matSand))
                case .ice:
                    root.addChildNode(voxel(x:x, z:z, h:0.40, m:matIce))
                case .hole:
                    root.addChildNode(voxel(x:x, z:z, h:0.10, m:matHole))
                case .blocked:
                    if isTree[gx][gy] {
                        // Sous la végétation, sol herbeux visible
                        root.addChildNode(voxel(x:x, z:z, h:0.40, m:matGrass))
                        root.addChildNode(treeNode(x:x, z:z))
                    } else {
                        // Falaise / mur terracotta haute
                        root.addChildNode(voxel(x:x, z:z, h:1.80, m:matCliff))
                    }
                case .water, .surfable:
                    root.addChildNode(voxel(x:x, z:z, h:0.28, m:matWater))
                case .waterfall:
                    root.addChildNode(voxel(x:x, z:z, h:1.60, m:matWaterfall))
                }
            }
        }
        return root
    }

    // Crée un SCNBox centré sur (x, z) avec la hauteur donnée
    private static func voxel(x: Float, z: Float, h: Float, m: SCNMaterial) -> SCNNode {
        let box = SCNBox(width: 0.98, height: CGFloat(h), length: 0.98, chamferRadius: 0.02)
        box.materials = [m]
        let n = SCNNode(geometry: box)
        n.position = SCNVector3(x, h / 2, z)
        return n
    }

    // Matériau diffuse simple (partageable)
    private static func mat(r: CGFloat, g: CGFloat, b: CGFloat, alpha: CGFloat = 1) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents  = NSColor(red: r, green: g, blue: b, alpha: alpha)
        m.specular.contents = NSColor(white: 0.12, alpha: 1)
        m.shininess = 0.20
        m.lightingModel = .blinn
        m.isDoubleSided = false
        return m
    }

    // BFS : composants ≤8 tuiles bloquées → arbre ; plus grand → mur
    private static func classifyBlockedTiles(_ map: CollisionMap) -> [[Bool]] {
        let W = map.width, H = map.height
        var result  = Array(repeating: Array(repeating: false, count: H), count: W)
        var visited = Array(repeating: Array(repeating: false, count: H), count: W)
        for sy in 0..<H {
            for sx in 0..<W {
                guard map[sx, sy] == .blocked, !visited[sx][sy] else { continue }
                var comp: [(Int,Int)] = []; var q = [(sx,sy)]; visited[sx][sy] = true; var head = 0
                while head < q.count {
                    let (cx,cy) = q[head]; head += 1; comp.append((cx,cy))
                    for (dx,dz) in [(0,1),(0,-1),(1,0),(-1,0)] {
                        let nx=cx+dx, ny=cy+dz
                        guard nx>=0, nx<W, ny>=0, ny<H, !visited[nx][ny], map[nx,ny] == .blocked else { continue }
                        visited[nx][ny] = true; q.append((nx,ny))
                    }
                }
                let isT = comp.count <= 8
                for (tx,ty) in comp { result[tx][ty] = isT }
            }
        }
        return result
    }

    // Arbre : tronc cylindre + sphère feuillage
    private static func treeNode(x: Float, z: Float) -> SCNNode {
        let root = SCNNode()
        let trunk = SCNCylinder(radius: 0.12, height: 0.50)
        let tMat  = mat(r:0.32, g:0.19, b:0.09)
        trunk.materials = [tMat]
        let tNode = SCNNode(geometry: trunk); tNode.position = SCNVector3(x, 0.65, z)
        let foliage = SCNSphere(radius: 0.56)
        let fMat    = mat(r:0.18, g:0.44, b:0.12)
        foliage.materials = [fMat]
        let fNode = SCNNode(geometry: foliage); fNode.position = SCNVector3(x, 1.22, z)
        root.addChildNode(tNode); root.addChildNode(fNode)
        return root
    }

    // MARK: — Éclairage 3-points

    private static func addLighting(to scene: SCNScene, background: ZoneBackground) {
        let amb = SCNLight(); amb.type = .ambient
        amb.intensity = 500
        amb.color = NSColor(white: 1.0, alpha: 1)
        scene.rootNode.addChildNode(SCNNode().then { $0.light = amb })

        let sun = SCNLight(); sun.type = .directional
        sun.color = NSColor(red: 1.0, green: 0.96, blue: 0.88, alpha: 1)
        sun.intensity = background == .cave ? 300 : 1100
        sun.castsShadow = true
        sun.shadowRadius = 2
        sun.shadowColor  = NSColor(white: 0, alpha: 0.30)
        sun.shadowSampleCount = 4
        sun.shadowMapSize  = CGSize(width: 2048, height: 2048)
        let sunNode = SCNNode(); sunNode.light = sun
        // Vient de l'avant-droite-haut (comme dans l'exemple)
        sunNode.eulerAngles = SCNVector3(-CGFloat.pi / 4, CGFloat.pi / 6, 0)
        scene.rootNode.addChildNode(sunNode)

        let fill = SCNLight(); fill.type = .directional
        fill.color     = NSColor(red: 0.60, green: 0.75, blue: 1.0, alpha: 1)
        fill.intensity = 280
        let fillNode = SCNNode(); fillNode.light = fill
        fillNode.eulerAngles = SCNVector3(CGFloat.pi / 6, -CGFloat.pi / 4, 0)
        scene.rootNode.addChildNode(fillNode)
    }

    // MARK: — Entités 3D

    private static func makeEntityNode(marker: ZoneEntityMarker,
                                        background: ZoneBackground) -> SCNNode? {
        let tx = Float(marker.x) + 0.5
        let tz = Float(marker.y) + 0.5

        switch marker.kind {
        case .furniture:
            return (background == .outdoor || background == .water)
                ? treeNode(x: tx, z: tz)
                : makeFurniture(x: tx, z: tz)

        case .npc:
            let root = SCNNode()
            let body = SCNCylinder(radius: 0.18, height: 0.65)
            body.materials = [mat(r:0.97, g:0.60, b:0.10)]
            let bNode = SCNNode(geometry: body); bNode.position = SCNVector3(tx, 0.73, tz)
            let head  = SCNSphere(radius: 0.20)
            head.materials = [mat(r:0.97, g:0.80, b:0.65)]
            let hNode = SCNNode(geometry: head); hNode.position = SCNVector3(tx, 1.20, tz)
            root.addChildNode(bNode); root.addChildNode(hNode)
            return root

        case .warp:
            let disc = SCNCylinder(radius: 0.40, height: 0.05)
            disc.materials = [mat(r:0.20, g:0.55, b:1.0, alpha:0.85)]
            let n = SCNNode(geometry: disc); n.position = SCNVector3(tx, 0.43, tz)
            return n

        case .trigger:
            let geo = SCNPlane(width: 0.82, height: 0.82)
            geo.materials = [mat(r:1.0, g:0.90, b:0.10, alpha:0.80)]
            let n = SCNNode(geometry: geo)
            n.eulerAngles.x = -CGFloat.pi / 2
            n.position = SCNVector3(tx, 0.42, tz)
            return n
        }
    }

    private static func makeFurniture(x: Float, z: Float) -> SCNNode {
        let box = SCNBox(width: 0.60, height: 0.60, length: 0.60, chamferRadius: 0.06)
        box.materials = [mat(r:0.76, g:0.66, b:0.50)]
        let n = SCNNode(geometry: box); n.position = SCNVector3(x, 0.70, z)
        return n
    }
}

// Petit helper pour configurer un node inline sans variable intermédiaire
private extension SCNNode {
    func then(_ block: (SCNNode) -> Void) -> SCNNode { block(self); return self }
}
