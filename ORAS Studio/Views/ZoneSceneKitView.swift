import SwiftUI
import SceneKit

struct ZoneSceneKitView: View {
    let collisionMap: CollisionMap
    let bchMeshes: [BCHParser.MeshData]
    let entityMarkers: [ZoneEntityMarker]
    let background: ZoneBackground

    @State private var scene   = SCNScene()
    @State private var building = false

    var body: some View {
        ZStack {
            SceneView(
                scene: scene,
                options: [
                    .allowsCameraControl,
                    .autoenablesDefaultLighting,
                    .temporalAntialiasingEnabled
                ]
            )
            .background(Color.black)

            if building {
                ProgressView("Construction…")
                    .padding(14)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        // Déclenche une reconstruction uniquement quand les données changent
        .task(id: sceneKey) {
            building = true
            let map   = collisionMap
            let meshes = bchMeshes
            let marks = entityMarkers
            let bg    = background
            let built = await Task.detached(priority: .userInitiated) {
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
        let mapW  = CGFloat(collisionMap.width)
        let mapH  = CGFloat(collisionMap.height)
        let cx    = mapW / 2
        let cz    = mapH / 2

        // ── Sky dome ──
        if let sky = ProceduralTextureKit.skyDomeGeometry(background: background) {
            sky.position = SCNVector3(cx, -200, cz)
            scene.rootNode.addChildNode(sky)
        }

        // ── Brouillard atmosphérique ──
        if background == .outdoor || background == .water {
            scene.fogColor = background == .water
                ? NSColor(red: 0.15, green: 0.42, blue: 0.76, alpha: 1)
                : NSColor(red: 0.78, green: 0.90, blue: 0.98, alpha: 1)
            scene.fogStartDistance = max(mapW, mapH) * 0.95
            scene.fogEndDistance   = max(mapW, mapH) * 2.8
        }

        // ── Terrain de collision (sol + relief 3D) ──
        let terrain = BCMDLHelper.makeCollisionGeometry(from: collisionMap, background: background)
        scene.rootNode.addChildNode(terrain)

        // ── Entités 3D ──
        for marker in entityMarkers {
            if let node = makeEntityNode(marker: marker, background: background) {
                scene.rootNode.addChildNode(node)
            }
        }

        // ── Géométrie réelle BCH (terrain 3DS) ──
        if !bchMeshes.isEmpty {
            let bchNode = BCHParser.toSCNNode(meshes: bchMeshes, scale: 1.0 / 16.0)
            // Pas de décalage supplémentaire : les vertices BCH sont déjà dans l'espace tuile après scale
            bchNode.position = SCNVector3(0, 0, 0)
            scene.rootNode.addChildNode(bchNode)
        }

        // ── Caméra perspective 3/4 ──
        let cam = SCNCamera()
        cam.fieldOfView = 50
        cam.zNear = 0.3; cam.zFar = 1500
        cam.wantsDepthOfField = false
        let camNode = SCNNode(); camNode.camera = cam
        let dist = max(mapW, mapH) * 1.15
        camNode.position = SCNVector3(cx, dist * 0.80, cz + dist * 0.58)
        camNode.look(at: SCNVector3(cx, 0, cz))
        scene.rootNode.addChildNode(camNode)

        // ── Éclairage 3-points ──
        addLighting(to: scene, background: background)

        return scene
    }

    // MARK: — Éclairage (statique)

    private static func addLighting(to scene: SCNScene, background: ZoneBackground) {
        let amb = SCNLight(); amb.type = .ambient
        amb.intensity = 420
        amb.color = NSColor(red: 0.65, green: 0.70, blue: 0.78, alpha: 1)
        scene.rootNode.addChildNode(SCNNode().then { $0.light = amb })

        let sun = SCNLight(); sun.type = .directional
        sun.color = NSColor(red: 1.0, green: 0.97, blue: 0.90, alpha: 1)
        sun.intensity = background == .cave ? 250 : 980
        sun.castsShadow = background != .cave
        sun.shadowRadius = 3
        sun.shadowColor  = NSColor(white: 0, alpha: 0.35)
        sun.shadowSampleCount = 8
        let sunNode = SCNNode(); sunNode.light = sun
        sunNode.eulerAngles = SCNVector3(-CGFloat.pi / 3.5, CGFloat.pi / 5, 0)
        scene.rootNode.addChildNode(sunNode)

        let fill = SCNLight(); fill.type = .directional
        fill.color     = NSColor(red: 0.55, green: 0.73, blue: 0.98, alpha: 1)
        fill.intensity = background == .cave ? 160 : 310
        let fillNode = SCNNode(); fillNode.light = fill
        fillNode.eulerAngles = SCNVector3(CGFloat.pi / 5, -CGFloat.pi / 3, 0)
        scene.rootNode.addChildNode(fillNode)
    }

    // MARK: — Entités 3D (statique)

    private static func makeEntityNode(marker: ZoneEntityMarker,
                                        background: ZoneBackground) -> SCNNode? {
        let tx = Float(marker.x) + 0.5
        let tz = Float(marker.y) + 0.5

        switch marker.kind {
        case .furniture:
            return (background == .outdoor || background == .water)
                ? BCMDLHelper.makeTreeNode(x: tx, z: tz)
                : makeGenericFurniture(x: tx, z: tz)

        case .npc:
            let root = SCNNode()
            let body = SCNCylinder(radius: 0.20, height: 0.70)
            let bMat = SCNMaterial(); bMat.diffuse.contents = NSColor(red: 0.97, green: 0.60, blue: 0.10, alpha: 1)
            body.materials = [bMat]
            let bNode = SCNNode(geometry: body); bNode.position = SCNVector3(tx, 0.45, tz)
            let head  = SCNSphere(radius: 0.21)
            let hMat  = SCNMaterial(); hMat.diffuse.contents = NSColor(red: 0.97, green: 0.80, blue: 0.64, alpha: 1)
            head.materials = [hMat]
            let hNode = SCNNode(geometry: head); hNode.position = SCNVector3(tx, 1.02, tz)
            root.addChildNode(bNode); root.addChildNode(hNode)
            return root

        case .warp:
            let disc = SCNCylinder(radius: 0.42, height: 0.04)
            let dMat = SCNMaterial()
            dMat.diffuse.contents  = NSColor(red: 0.20, green: 0.55, blue: 1.0, alpha: 0.85)
            dMat.emission.contents = NSColor(red: 0.05, green: 0.22, blue: 0.55, alpha: 1)
            dMat.shininess = 0.9; dMat.isDoubleSided = true
            disc.materials = [dMat]
            let dNode = SCNNode(geometry: disc); dNode.position = SCNVector3(tx, 0.03, tz)
            return dNode

        case .trigger:
            let geo = SCNPlane(width: 0.80, height: 0.80)
            let mat = SCNMaterial()
            mat.diffuse.contents  = NSColor(red: 1.0, green: 0.90, blue: 0.10, alpha: 0.80)
            mat.emission.contents = NSColor(red: 0.38, green: 0.32, blue: 0.00, alpha: 1)
            mat.isDoubleSided = true
            geo.materials = [mat]
            let node = SCNNode(geometry: geo)
            node.eulerAngles.x = -CGFloat.pi / 2
            node.position = SCNVector3(tx, 0.05, tz)
            return node
        }
    }

    private static func makeGenericFurniture(x: Float, z: Float) -> SCNNode {
        let box = SCNBox(width: 0.65, height: 0.65, length: 0.65, chamferRadius: 0.08)
        let mat = SCNMaterial()
        mat.diffuse.contents  = NSColor(red: 0.78, green: 0.68, blue: 0.52, alpha: 1)
        mat.specular.contents = NSColor(white: 0.2, alpha: 1); mat.shininess = 0.3
        box.materials = [mat]
        let node = SCNNode(geometry: box); node.position = SCNVector3(x, 0.42, z)
        return node
    }
}

// Petit helper pour configurer un node inline sans variable intermédiaire
private extension SCNNode {
    func then(_ block: (SCNNode) -> Void) -> SCNNode { block(self); return self }
}
