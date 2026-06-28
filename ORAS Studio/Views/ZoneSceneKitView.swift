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

        // Fond opaque (masqué par le sky dome)
        scene.background.contents = NSColor.black

        let mapW = CGFloat(collisionMap.width)
        let mapH = CGFloat(collisionMap.height)
        let center = SCNVector3(mapW / 2, 0, mapH / 2)

        // ── 1. Sky dome ──
        if let sky = ProceduralTextureKit.skyDomeGeometry(background: background) {
            sky.position = SCNVector3(mapW / 2, -200, mapH / 2)
            scene.rootNode.addChildNode(sky)
        }

        // ── 2. Fog (outdoor uniquement) ──
        if background == .outdoor || background == .water {
            scene.fogColor = background == .water
                ? NSColor(red: 0.15, green: 0.40, blue: 0.75, alpha: 1)
                : NSColor(red: 0.70, green: 0.85, blue: 0.98, alpha: 1)
            scene.fogStartDistance = max(mapW, mapH) * 0.8
            scene.fogEndDistance   = max(mapW, mapH) * 2.5
        }

        // ── 3. Terrain de collision texturé ──
        let collNode = BCMDLHelper.makeCollisionGeometry(from: collisionMap, background: background)
        scene.rootNode.addChildNode(collNode)

        // ── 4. Entités 3D typées ──
        for marker in entityMarkers {
            let entityNode = makeEntityNode(marker: marker)
            scene.rootNode.addChildNode(entityNode)
        }

        // ── 5. Nuage de points BCH (si extrait) ──
        if !bcmdlVertices.isEmpty {
            addBCMDLOverlay(to: scene, mapW: mapW, mapH: mapH)
        }

        // ── 6. Caméra perspective 3/4 isométrique (angle ORAS) ──
        let cam = SCNCamera()
        cam.fieldOfView = 48
        cam.zNear = 0.3
        cam.zFar  = 1500
        cam.wantsDepthOfField = false
        let camNode = SCNNode()
        camNode.camera = cam
        let dist = max(mapW, mapH) * 1.2
        camNode.position = SCNVector3(mapW / 2, dist * 0.70, mapH / 2 + dist * 0.65)
        camNode.look(at: center)
        scene.rootNode.addChildNode(camNode)

        // ── 7. Éclairage 3-points de qualité ──
        addLighting(to: scene)

        return scene
    }

    // MARK: — Éclairage

    private func addLighting(to scene: SCNScene) {
        // Ambiant doux
        let amb = SCNLight(); amb.type = .ambient
        amb.intensity = 350
        amb.color = NSColor(red: 0.65, green: 0.68, blue: 0.75, alpha: 1)
        let ambNode = SCNNode(); ambNode.light = amb
        scene.rootNode.addChildNode(ambNode)

        // Soleil principal
        let sun = SCNLight(); sun.type = .directional
        sun.color = NSColor(red: 1.0, green: 0.96, blue: 0.88, alpha: 1)
        sun.intensity = background == .cave ? 200 : 900
        sun.castsShadow = (background != .cave)
        sun.shadowRadius = 4
        sun.shadowColor = NSColor(white: 0, alpha: 0.40)
        sun.shadowSampleCount = 8
        let sunNode = SCNNode(); sunNode.light = sun
        sunNode.eulerAngles = SCNVector3(-CGFloat.pi / 3.2, CGFloat.pi / 5, 0)
        scene.rootNode.addChildNode(sunNode)

        // Fill sky
        let fill = SCNLight(); fill.type = .directional
        fill.color = NSColor(red: 0.55, green: 0.72, blue: 0.98, alpha: 1)
        fill.intensity = background == .cave ? 150 : 280
        let fillNode = SCNNode(); fillNode.light = fill
        fillNode.eulerAngles = SCNVector3(CGFloat.pi / 5, -CGFloat.pi / 3, 0)
        scene.rootNode.addChildNode(fillNode)
    }

    // MARK: — Entités 3D typées

    private func makeEntityNode(marker: ZoneEntityMarker) -> SCNNode {
        let root = SCNNode()
        let tx = CGFloat(marker.x) + 0.5
        let tz = CGFloat(marker.y) + 0.5

        switch marker.kind {

        case .npc:
            // Silhouette de personnage : corps + tête + bras
            let bodyGeo = SCNBox(width: 0.45, height: 0.80, length: 0.25, chamferRadius: 0.06)
            let headGeo = SCNSphere(radius: 0.22)
            let bodyMat = SCNMaterial(); bodyMat.diffuse.contents = NSColor(red: 0.98, green: 0.62, blue: 0.12, alpha: 1)
            bodyMat.emission.contents = NSColor(red: 0.30, green: 0.18, blue: 0.02, alpha: 1)
            let headMat = SCNMaterial(); headMat.diffuse.contents = NSColor(red: 0.95, green: 0.80, blue: 0.65, alpha: 1)
            bodyGeo.materials = [bodyMat]; headGeo.materials = [headMat]
            let bodyNode = SCNNode(geometry: bodyGeo); bodyNode.position = SCNVector3(0, 0.5, 0)
            let headNode = SCNNode(geometry: headGeo); headNode.position = SCNVector3(0, 1.10, 0)
            root.addChildNode(bodyNode); root.addChildNode(headNode)
            root.position = SCNVector3(tx, 0, tz)

        case .furniture:
            // Objet générique : cube stylisé brun
            let geo = SCNBox(width: 0.7, height: 0.7, length: 0.7, chamferRadius: 0.10)
            let mat = SCNMaterial()
            mat.diffuse.contents = NSColor(red: 0.62, green: 0.42, blue: 0.22, alpha: 1)
            mat.specular.contents = NSColor.white; mat.shininess = 0.3
            geo.materials = [mat]
            let node = SCNNode(geometry: geo); node.position = SCNVector3(tx, 0.45, tz)
            root.addChildNode(node)
            root.position = SCNVector3(0, 0, 0)

        case .warp:
            // Portail : anneau (tore) bleu lumineux
            let ring = SCNTorus(ringRadius: 0.42, pipeRadius: 0.08)
            let mat = SCNMaterial()
            mat.diffuse.contents = NSColor(red: 0.20, green: 0.55, blue: 1.0, alpha: 0.9)
            mat.emission.contents = NSColor(red: 0.05, green: 0.25, blue: 0.60, alpha: 1)
            mat.specular.contents = NSColor.white; mat.shininess = 0.95
            mat.isDoubleSided = true
            ring.materials = [mat]
            let ringNode = SCNNode(geometry: ring)
            ringNode.eulerAngles = SCNVector3(-Float.pi/6, 0, 0)
            ringNode.position = SCNVector3(tx, 0.55, tz)
            // Pilier de lumière vertical
            let beam = SCNCylinder(radius: 0.04, height: 1.5)
            let beamMat = SCNMaterial()
            beamMat.diffuse.contents  = NSColor(red: 0.35, green: 0.70, blue: 1.0, alpha: 0.6)
            beamMat.emission.contents = NSColor(red: 0.35, green: 0.70, blue: 1.0, alpha: 0.6)
            beamMat.isDoubleSided = true
            beam.materials = [beamMat]
            let beamNode = SCNNode(geometry: beam); beamNode.position = SCNVector3(tx, 0.75, tz)
            root.addChildNode(ringNode); root.addChildNode(beamNode)
            root.position = SCNVector3(0, 0, 0)

        case .trigger:
            // Zone de déclenchement : losange jaune plat au sol
            let geo = SCNBox(width: 0.80, height: 0.04, length: 0.80, chamferRadius: 0)
            let mat = SCNMaterial()
            mat.diffuse.contents = NSColor(red: 1.0, green: 0.90, blue: 0.10, alpha: 0.75)
            mat.emission.contents = NSColor(red: 0.40, green: 0.35, blue: 0.00, alpha: 1)
            geo.materials = [mat]
            let node = SCNNode(geometry: geo); node.position = SCNVector3(tx, 0.04, tz)
            node.eulerAngles = SCNVector3(0, Float.pi/4, 0)
            root.addChildNode(node)
            root.position = SCNVector3(0, 0, 0)
        }

        return root
    }

    // MARK: — Overlay BCH point cloud (données TM brutes)

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
            color: NSColor(red: 1.0, green: 0.88, blue: 0.25, alpha: 0.85)
        ) {
            scene.rootNode.addChildNode(SCNNode(geometry: geo))
        }
    }
}
