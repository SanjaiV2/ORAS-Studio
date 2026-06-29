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
        v.backgroundColor = NSColor(red: 0.25, green: 0.30, blue: 0.62, alpha: 1)
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
        "\(collisionMap.width)x\(collisionMap.height)-\(background)-\(entityMarkers.count)-\(bchMeshes.count)"
    }

    // MARK: — Construction statique (thread-safe, appelée depuis Task.detached)

    nonisolated static func buildScene(collisionMap: CollisionMap,
                           bchMeshes: [BCHParser.MeshData],
                           entityMarkers: [ZoneEntityMarker],
                           background: ZoneBackground) -> SCNScene {
        let scene = SCNScene()
        let W = collisionMap.width, H = collisionMap.height
        let cx = CGFloat(W) / 2, cz = CGFloat(H) / 2

        if !bchMeshes.isEmpty {
            // ── Géométrie BCH réelle (textured quand texture != nil) ──
            // Les meshes sont déjà normalisés en espace-tuile, centrés sur (0,0,0).
            // On translate vers (cx, 0, cz) pour coïncider avec les marqueurs d'entités.
            let bchNode = BCHParser.toSCNNode(meshes: bchMeshes, scale: 1.0)
            bchNode.position = SCNVector3(cx, 0, cz)
            scene.rootNode.addChildNode(bchNode)

            // Fond discret sous le terrain BCH
            let oceanPlane = SCNPlane(width: CGFloat(W + 20), height: CGFloat(H + 20))
            oceanPlane.materials = [mat(r:0.25, g:0.30, b:0.62, alpha:1.0)]
            let oceanNode = SCNNode(geometry: oceanPlane)
            oceanNode.eulerAngles.x = -CGFloat.pi / 2
            oceanNode.position = SCNVector3(cx, -0.5, cz)
            scene.rootNode.addChildNode(oceanNode)
        } else {
            // ── Fallback : terrain voxel tuile par tuile ──
            let terrain = makeVoxelTerrain(map: collisionMap, background: background)
            scene.rootNode.addChildNode(terrain)

            let oceanPlane = SCNPlane(width: CGFloat(W + 20), height: CGFloat(H + 20))
            oceanPlane.materials = [mat(r:0.25, g:0.30, b:0.62, alpha:1.0)]
            let oceanNode = SCNNode(geometry: oceanPlane)
            oceanNode.eulerAngles.x = -CGFloat.pi / 2
            oceanNode.position = SCNVector3(cx, -0.05, cz)
            scene.rootNode.addChildNode(oceanNode)
        }

        // ── Entités 3D (toujours affichées) ──
        for marker in entityMarkers {
            if let node = makeEntityNode(marker: marker, background: background) {
                scene.rootNode.addChildNode(node)
            }
        }

        // ── Caméra isométrique haut-arrière (angle ~60°, style ORAS map viewer) ──
        let cam = SCNCamera()
        cam.fieldOfView = 50
        cam.zNear = 0.5; cam.zFar = 2000
        let camNode = SCNNode(); camNode.camera = cam
        let ext = max(CGFloat(W), CGFloat(H))
        camNode.position = SCNVector3(cx + ext * 0.08, ext * 0.95, cz + ext * 0.55)
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
        let isTree = classifyBlockedTiles(map, outdoor: background == .outdoor)

        // Matériaux partagés (palette ORAS approximée)
        let matGrass     = mat(r:0.26, g:0.55, b:0.18)   // vert herbe ORAS
        let matTallGrass = mat(r:0.18, g:0.44, b:0.12)   // herbes hautes
        let matSand      = mat(r:0.87, g:0.74, b:0.44)   // sable/plage
        let matIce       = mat(r:0.70, g:0.88, b:0.96)
        let matCliff     = mat(r:0.65, g:0.28, b:0.12)   // terracotta route/falaise
        let matWater     = mat(r:0.14, g:0.46, b:0.84, alpha:0.92)  // eau ORAS
        let matWaterfall = mat(r:0.20, g:0.55, b:0.92, alpha:0.80)
        let matHole      = mat(r:0.06, g:0.05, b:0.07)

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

    // BFS : composants de tuiles bloquées.
    // Outdoor : seuil 50 (grandes forêts = arbres) ; indoor/cave : seuil 8 (murs épais).
    private static func classifyBlockedTiles(_ map: CollisionMap, outdoor: Bool) -> [[Bool]] {
        let W = map.width, H = map.height
        var result  = Array(repeating: Array(repeating: false, count: H), count: W)
        var visited = Array(repeating: Array(repeating: false, count: H), count: W)
        let threshold = outdoor ? 80 : 8
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
                let isT = comp.count <= threshold
                for (tx,ty) in comp { result[tx][ty] = isT }
            }
        }
        return result
    }

    // Arbre : boule feuillage teal (style ORAS — pas de tronc visible d'en haut)
    private static func treeNode(x: Float, z: Float) -> SCNNode {
        let root = SCNNode()
        // Sol herbeux sous l'arbre (déjà ajouté par l'appelant pour .blocked)
        // Ombre / base sombre
        let shadow = SCNCylinder(radius: 0.48, height: 0.04)
        shadow.materials = [mat(r:0.08, g:0.22, b:0.06, alpha:0.60)]
        let sNode = SCNNode(geometry: shadow); sNode.position = SCNVector3(x, 0.42, z)
        // Feuillage principal : sphère teal foncé, grand
        let foliage = SCNSphere(radius: 0.62)
        foliage.materials = [mat(r:0.12, g:0.42, b:0.28)]  // teal foncé ORAS
        let fNode = SCNNode(geometry: foliage); fNode.position = SCNVector3(x, 1.10, z)
        // Reflet lumineux (petite sphère claire au-dessus)
        let highlight = SCNSphere(radius: 0.22)
        highlight.materials = [mat(r:0.22, g:0.58, b:0.38)]
        let hNode = SCNNode(geometry: highlight); hNode.position = SCNVector3(x, 1.58, z)
        root.addChildNode(sNode); root.addChildNode(fNode); root.addChildNode(hNode)
        return root
    }

    // MARK: — Éclairage 3-points

    private static func addLighting(to scene: SCNScene, background: ZoneBackground) {
        let amb = SCNLight(); amb.type = .ambient
        amb.intensity = background == .cave ? 700 : 550
        amb.color = NSColor(white: 1.0, alpha: 1)
        scene.rootNode.addChildNode(SCNNode().then { $0.light = amb })

        // Soleil presque vertical (angle ORAS map viewer ≈ 70° du sol)
        let sun = SCNLight(); sun.type = .directional
        sun.color = NSColor(red: 1.0, green: 0.97, blue: 0.90, alpha: 1)
        sun.intensity = background == .cave ? 250 : 1200
        sun.castsShadow = true
        sun.shadowRadius = 1.5
        sun.shadowColor  = NSColor(white: 0, alpha: 0.25)
        sun.shadowSampleCount = 4
        sun.shadowMapSize  = CGSize(width: 2048, height: 2048)
        let sunNode = SCNNode(); sunNode.light = sun
        // Lumière venant de l'arrière-gauche-haut (typique vue ORAS)
        sunNode.eulerAngles = SCNVector3(-CGFloat.pi * 0.38, -CGFloat.pi / 5, 0)
        scene.rootNode.addChildNode(sunNode)

        // Lumière de remplissage douce (côté avant)
        let fill = SCNLight(); fill.type = .directional
        fill.color     = NSColor(red: 0.55, green: 0.70, blue: 1.0, alpha: 1)
        fill.intensity = 320
        let fillNode = SCNNode(); fillNode.light = fill
        fillNode.eulerAngles = SCNVector3(CGFloat.pi / 5, CGFloat.pi / 4, 0)
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
