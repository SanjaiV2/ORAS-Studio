import SwiftUI
import SceneKit

struct ZoneSceneKitView: View {
    let collisionMap: CollisionMap
    let bcmdlVertices: [SCNVector3]
    let entityMarkers: [ZoneEntityMarker]
    let background: ZoneBackground

    var body: some View {
        SceneView(
            scene: buildScene(),
            options: [
                .allowsCameraControl,
                .autoenablesDefaultLighting,
                .temporalAntialiasingEnabled
            ]
        )
        .background(Color.black)
    }

    // MARK: — Construction de la scène

    private func buildScene() -> SCNScene {
        let scene = SCNScene()

        let mapW = CGFloat(collisionMap.width)
        let mapH = CGFloat(collisionMap.height)
        let cx   = mapW / 2
        let cz   = mapH / 2

        // ── Sky dome ──
        if let sky = ProceduralTextureKit.skyDomeGeometry(background: background) {
            sky.position = SCNVector3(cx, -200, cz)
            scene.rootNode.addChildNode(sky)
        }

        // ── Fog atmosphérique (outdoor / water) ──
        if background == .outdoor || background == .water {
            scene.fogColor = background == .water
                ? NSColor(red: 0.15, green: 0.42, blue: 0.76, alpha: 1)
                : NSColor(red: 0.78, green: 0.90, blue: 0.98, alpha: 1)
            scene.fogStartDistance = max(mapW, mapH) * 0.95
            scene.fogEndDistance   = max(mapW, mapH) * 2.8
        }

        // ── Terrain : sol texturé + relief 3D (arbres, murs, eau) ──
        let terrain = BCMDLHelper.makeCollisionGeometry(from: collisionMap, background: background)
        scene.rootNode.addChildNode(terrain)

        // ── Entités 3D volumétriques ──
        for marker in entityMarkers {
            if let node = makeEntityNode(marker: marker) {
                scene.rootNode.addChildNode(node)
            }
        }

        // ── Overlay BCH optionnel (données TM brutes) ──
        if !bcmdlVertices.isEmpty {
            addBCMDLOverlay(to: scene, mapW: mapW, mapH: mapH)
        }

        // ── Caméra perspective 3/4 isométrique ──
        let cam = SCNCamera()
        cam.fieldOfView = 50
        cam.zNear = 0.3
        cam.zFar  = 1500
        cam.wantsDepthOfField = false
        let camNode = SCNNode(); camNode.camera = cam
        let dist    = max(mapW, mapH) * 1.15
        camNode.position = SCNVector3(cx, dist * 0.80, cz + dist * 0.58)
        camNode.look(at: SCNVector3(cx, 0, cz))
        scene.rootNode.addChildNode(camNode)

        // ── Éclairage 3-points ──
        addLighting(to: scene)

        return scene
    }

    // MARK: — Éclairage

    private func addLighting(to scene: SCNScene) {
        // Ambiant
        let amb = SCNLight(); amb.type = .ambient
        amb.intensity = 420
        amb.color = NSColor(red: 0.65, green: 0.70, blue: 0.78, alpha: 1)
        let ambNode = SCNNode(); ambNode.light = amb
        scene.rootNode.addChildNode(ambNode)

        // Soleil directionnel principal
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

        // Fill sky
        let fill = SCNLight(); fill.type = .directional
        fill.color     = NSColor(red: 0.55, green: 0.73, blue: 0.98, alpha: 1)
        fill.intensity = background == .cave ? 160 : 310
        let fillNode = SCNNode(); fillNode.light = fill
        fillNode.eulerAngles = SCNVector3(CGFloat.pi / 5, -CGFloat.pi / 3, 0)
        scene.rootNode.addChildNode(fillNode)
    }

    // MARK: — Entités 3D typées

    private func makeEntityNode(marker: ZoneEntityMarker) -> SCNNode? {
        let tx = Float(marker.x) + 0.5
        let tz = Float(marker.y) + 0.5

        switch marker.kind {

        // Furniture : arbre (outdoor) ou objet générique (indoor/cave)
        case .furniture:
            if background == .outdoor || background == .water {
                // Même rendu que les arbres des tuiles bloquées
                return BCMDLHelper.makeTreeNode(x: tx, z: tz)
            } else {
                return makeGenericFurniture(x: tx, z: tz)
            }

        // PNJ : silhouette corps + tête
        case .npc:
            let root = SCNNode()
            let body = SCNCylinder(radius: 0.20, height: 0.70)
            let bMat = SCNMaterial()
            bMat.diffuse.contents = NSColor(red: 0.97, green: 0.60, blue: 0.10, alpha: 1)
            body.materials = [bMat]
            let bNode = SCNNode(geometry: body); bNode.position = SCNVector3(tx, 0.45, tz)
            let head = SCNSphere(radius: 0.21)
            let hMat = SCNMaterial()
            hMat.diffuse.contents = NSColor(red: 0.97, green: 0.80, blue: 0.64, alpha: 1)
            head.materials = [hMat]
            let hNode = SCNNode(geometry: head); hNode.position = SCNVector3(tx, 1.02, tz)
            root.addChildNode(bNode); root.addChildNode(hNode)
            return root

        // Warp : disque bleu lumineux au sol
        case .warp:
            let root = SCNNode()
            let disc = SCNCylinder(radius: 0.42, height: 0.04)
            let dMat = SCNMaterial()
            dMat.diffuse.contents  = NSColor(red: 0.20, green: 0.55, blue: 1.0, alpha: 0.85)
            dMat.emission.contents = NSColor(red: 0.05, green: 0.22, blue: 0.55, alpha: 1)
            dMat.shininess = 0.9; dMat.isDoubleSided = true
            disc.materials = [dMat]
            let dNode = SCNNode(geometry: disc); dNode.position = SCNVector3(tx, 0.03, tz)
            root.addChildNode(dNode)
            return root

        // Trigger : marqueur jaune plat au sol
        case .trigger:
            let geo = SCNPlane(width: 0.80, height: 0.80)
            let mat = SCNMaterial()
            mat.diffuse.contents  = NSColor(red: 1.0, green: 0.90, blue: 0.10, alpha: 0.80)
            mat.emission.contents = NSColor(red: 0.38, green: 0.32, blue: 0.00, alpha: 1)
            mat.isDoubleSided = true
            geo.materials = [mat]
            let node = SCNNode(geometry: geo)
            node.eulerAngles.x = -.pi / 2
            node.position = SCNVector3(tx, 0.05, tz)
            return node
        }
    }

    // Objet générique (meubles, comptoirs, lit…)
    private func makeGenericFurniture(x: Float, z: Float) -> SCNNode {
        let box = SCNBox(width: 0.65, height: 0.65, length: 0.65, chamferRadius: 0.08)
        let mat = SCNMaterial()
        mat.diffuse.contents = NSColor(red: 0.78, green: 0.68, blue: 0.52, alpha: 1)
        mat.specular.contents = NSColor(white: 0.2, alpha: 1)
        mat.shininess = 0.3
        box.materials = [mat]
        let node = SCNNode(geometry: box)
        node.position = SCNVector3(x, 0.42, z)
        return node
    }

    // MARK: — Overlay BCH

    private func addBCMDLOverlay(to scene: SCNScene, mapW: CGFloat, mapH: CGFloat) {
        let count = CGFloat(bcmdlVertices.count)
        guard count > 0 else { return }
        let cx = bcmdlVertices.reduce(CGFloat(0)) { $0 + $1.x } / count
        let cy = bcmdlVertices.reduce(CGFloat(0)) { $0 + $1.y } / count
        let cz = bcmdlVertices.reduce(CGFloat(0)) { $0 + $1.z } / count
        let maxX = bcmdlVertices.map { abs($0.x - cx) }.max() ?? 1
        let maxZ = bcmdlVertices.map { abs($0.z - cz) }.max() ?? 1
        let scale = min(
            maxX > 0.1 ? (mapW * 0.46) / maxX : 1,
            maxZ > 0.1 ? (mapH * 0.46) / maxZ : 1
        )
        let adjusted: [SCNVector3] = Array(bcmdlVertices.prefix(3000)).map { v in
            SCNVector3((v.x - cx) * scale + mapW / 2,
                       (v.y - cy) * 0.25 + 2.8,
                       (v.z - cz) * scale + mapH / 2)
        }
        if let geo = BCMDLHelper.makePointCloud(
            vertices: adjusted,
            color: NSColor(red: 1.0, green: 0.88, blue: 0.25, alpha: 0.85)) {
            scene.rootNode.addChildNode(SCNNode(geometry: geo))
        }
    }
}
