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
    }

    private func buildScene() -> SCNScene {
        let scene = SCNScene()

        // Gradient de fond selon le type de zone
        switch background {
        case .outdoor:
            scene.background.contents = NSColor(red: 0.47, green: 0.72, blue: 0.95, alpha: 1.0)
        case .indoor:
            scene.background.contents = NSColor(red: 0.22, green: 0.20, blue: 0.18, alpha: 1.0)
        case .cave:
            scene.background.contents = NSColor(red: 0.08, green: 0.07, blue: 0.06, alpha: 1.0)
        case .water:
            scene.background.contents = NSColor(red: 0.10, green: 0.30, blue: 0.65, alpha: 1.0)
        default:
            scene.background.contents = NSColor(red: 0.12, green: 0.12, blue: 0.16, alpha: 1.0)
        }

        let mapW = CGFloat(collisionMap.width)
        let mapH = CGFloat(collisionMap.height)

        // Géométrie de collision 3D haute-fidélité
        let collNode = BCMDLHelper.makeCollisionGeometry(from: collisionMap)
        scene.rootNode.addChildNode(collNode)

        // Vertices BCH/TM en overlay (nuage de points si disponibles)
        if !bcmdlVertices.isEmpty {
            addBCMDLPointCloud(to: scene, mapW: mapW, mapH: mapH)
        }

        // Entités : sphères avec émission colorée et tige verticale
        for marker in entityMarkers {
            let markerColor: NSColor
            switch marker.kind {
            case .npc:       markerColor = .systemOrange
            case .furniture: markerColor = NSColor(red: 0.6, green: 0.38, blue: 0.12, alpha: 1)
            case .warp:      markerColor = .systemBlue
            case .trigger:   markerColor = .systemYellow
            }

            // Tige (cylindre fin)
            let cyl = SCNCylinder(radius: 0.05, height: 1.2)
            let cylMat = SCNMaterial()
            cylMat.diffuse.contents = markerColor.withAlphaComponent(0.6)
            cyl.materials = [cylMat]
            let cylNode = SCNNode(geometry: cyl)
            cylNode.position = SCNVector3(CGFloat(marker.x) + 0.5, 0.6, CGFloat(marker.y) + 0.5)
            scene.rootNode.addChildNode(cylNode)

            // Sphère au sommet
            let sphere = SCNSphere(radius: 0.35)
            let mat = SCNMaterial()
            mat.diffuse.contents = markerColor
            mat.emission.contents = markerColor.withAlphaComponent(0.5)
            sphere.materials = [mat]
            let node = SCNNode(geometry: sphere)
            node.position = SCNVector3(CGFloat(marker.x) + 0.5, 1.4, CGFloat(marker.y) + 0.5)
            scene.rootNode.addChildNode(node)
        }

        // Caméra perspective 3/4 vue isométrique (angle jeu Pokémon)
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 50
        cameraNode.camera?.zNear = 0.5
        cameraNode.camera?.zFar = 1000
        let camDist = max(mapW, mapH) * 1.15
        cameraNode.position = SCNVector3(
            mapW / 2,
            camDist * 0.72,
            mapH / 2 + camDist * 0.62
        )
        cameraNode.look(at: SCNVector3(mapW / 2, 0, mapH / 2))
        scene.rootNode.addChildNode(cameraNode)

        // Lumière ambiante douce
        let ambNode = SCNNode()
        let amb = SCNLight()
        amb.type = .ambient
        amb.color = NSColor(white: 0.45, alpha: 1)
        amb.intensity = 500
        ambNode.light = amb
        scene.rootNode.addChildNode(ambNode)

        // Lumière directionnelle principale (soleil)
        let sunNode = SCNNode()
        let sun = SCNLight()
        sun.type = .directional
        sun.color = NSColor(red: 1.0, green: 0.97, blue: 0.90, alpha: 1.0)
        sun.intensity = 900
        sun.castsShadow = true
        sun.shadowRadius = 3.0
        sun.shadowColor = NSColor(white: 0, alpha: 0.35)
        sunNode.light = sun
        sunNode.eulerAngles = SCNVector3(-CGFloat.pi / 3.5, CGFloat.pi / 6, 0)
        scene.rootNode.addChildNode(sunNode)

        // Lumière de remplissage (sky fill — contre-lumière douce)
        let fillNode = SCNNode()
        let fill = SCNLight()
        fill.type = .directional
        fill.color = NSColor(red: 0.65, green: 0.75, blue: 0.95, alpha: 1.0)
        fill.intensity = 250
        fillNode.light = fill
        fillNode.eulerAngles = SCNVector3(CGFloat.pi / 4, -CGFloat.pi / 3, 0)
        scene.rootNode.addChildNode(fillNode)

        return scene
    }

    // Point cloud BCH/TM — centré et scalé sur la zone de collision
    private func addBCMDLPointCloud(to scene: SCNScene, mapW: CGFloat, mapH: CGFloat) {
        let count = CGFloat(bcmdlVertices.count)
        guard count > 0 else { return }

        let sumX = bcmdlVertices.reduce(CGFloat(0)) { $0 + $1.x }
        let sumY = bcmdlVertices.reduce(CGFloat(0)) { $0 + $1.y }
        let sumZ = bcmdlVertices.reduce(CGFloat(0)) { $0 + $1.z }
        let cx = sumX / count
        let cy = sumY / count
        let cz = sumZ / count

        let maxX = bcmdlVertices.map { abs($0.x - cx) }.max() ?? 1
        let maxZ = bcmdlVertices.map { abs($0.z - cz) }.max() ?? 1
        let sx: CGFloat = maxX > 0.1 ? (mapW * 0.48) / maxX : 1
        let sz: CGFloat = maxZ > 0.1 ? (mapH * 0.48) / maxZ : 1
        let scale = min(sx, sz)

        let adjusted: [SCNVector3] = Array(bcmdlVertices.prefix(4000)).map { v in
            SCNVector3(
                (v.x - cx) * scale + mapW / 2,
                (v.y - cy) * 0.3 + 3.0,
                (v.z - cz) * scale + mapH / 2
            )
        }

        if let geo = BCMDLHelper.makePointCloud(
            vertices: adjusted,
            color: NSColor(red: 1.0, green: 0.85, blue: 0.2, alpha: 0.9)
        ) {
            scene.rootNode.addChildNode(SCNNode(geometry: geo))
        }
    }
}
