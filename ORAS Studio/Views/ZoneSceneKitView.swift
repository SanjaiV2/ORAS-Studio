import SwiftUI
import SceneKit

struct ZoneSceneKitView: View {
    let collisionMap: CollisionMap
    let bcmdlVertices: [SCNVector3]    // vide = utiliser collision seulement
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

        // Fond selon le type de zone
        let bgColor: NSColor
        switch background {
        case .outdoor:
            bgColor = NSColor(red: 0.6, green: 0.8, blue: 0.5, alpha: 1.0)
        case .indoor:
            bgColor = NSColor(red: 0.8, green: 0.7, blue: 0.6, alpha: 1.0)
        case .cave:
            bgColor = NSColor(red: 0.15, green: 0.12, blue: 0.10, alpha: 1.0)
        default:
            bgColor = NSColor(red: 0.15, green: 0.15, blue: 0.2, alpha: 1.0)
        }
        scene.background.contents = bgColor

        let mapW = CGFloat(collisionMap.width)
        let mapH = CGFloat(collisionMap.height)

        // Plan de sol
        let floor = SCNFloor()
        floor.reflectivity = 0.0
        let floorMat = SCNMaterial()
        let floorColor: NSColor = background == .outdoor
            ? NSColor(red: 0.55, green: 0.75, blue: 0.45, alpha: 1.0)
            : NSColor(red: 0.7, green: 0.65, blue: 0.55, alpha: 1.0)
        floorMat.diffuse.contents = floorColor
        floor.materials = [floorMat]
        let floorNode = SCNNode(geometry: floor)
        scene.rootNode.addChildNode(floorNode)

        // Géométrie de collision (murs, eau, herbes en 3D)
        let collNode = BCMDLHelper.makeCollisionGeometry(from: collisionMap)
        scene.rootNode.addChildNode(collNode)

        // Vertices BCMDL en overlay semi-transparent (si disponibles)
        if !bcmdlVertices.isEmpty {
            addBCMDLPointCloud(to: scene, mapW: mapW, mapH: mapH)
        }

        // Entités (NPCs, warps, furniture)
        for marker in entityMarkers {
            let sphere = SCNSphere(radius: 0.4)
            let mat = SCNMaterial()
            let markerColor: NSColor
            switch marker.kind {
            case .npc:       markerColor = .systemOrange
            case .furniture: markerColor = .systemBrown
            case .warp:      markerColor = .systemBlue
            case .trigger:   markerColor = .systemYellow
            }
            mat.diffuse.contents = markerColor
            mat.emission.contents = markerColor
            sphere.materials = [mat]
            let node = SCNNode(geometry: sphere)
            node.position = SCNVector3(CGFloat(marker.x), 1.2, CGFloat(marker.y))
            scene.rootNode.addChildNode(node)
        }

        // Caméra isométrique (légèrement inclinée pour la 3D)
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.usesOrthographicProjection = true
        cameraNode.camera?.orthographicScale = Double(max(mapW, mapH)) * 0.6
        cameraNode.camera?.zFar = 500
        let camDist = max(mapW, mapH)
        cameraNode.position = SCNVector3(
            mapW / 2,
            camDist * 0.9,
            mapH / 2 + camDist * 0.4
        )
        cameraNode.look(at: SCNVector3(mapW / 2, 0, mapH / 2))
        scene.rootNode.addChildNode(cameraNode)

        // Lumière ambiante
        let ambLight = SCNLight()
        ambLight.type = .ambient
        ambLight.intensity = 400
        let ambNode = SCNNode()
        ambNode.light = ambLight
        scene.rootNode.addChildNode(ambNode)

        // Lumière directionnelle
        let dirLight = SCNLight()
        dirLight.type = .directional
        dirLight.intensity = 800
        let dirNode = SCNNode()
        dirNode.light = dirLight
        dirNode.eulerAngles = SCNVector3(-CGFloat.pi / 3, CGFloat.pi / 4, 0)
        scene.rootNode.addChildNode(dirNode)

        return scene
    }

    // Ajoute le nuage de points BCMDL, centré sur la carte de collision
    private func addBCMDLPointCloud(to scene: SCNScene, mapW: CGFloat, mapH: CGFloat) {
        let centerX = mapW / 2
        let centerZ = mapH / 2

        // Centre du nuage de points
        let sumX = bcmdlVertices.reduce(CGFloat(0)) { $0 + $1.x }
        let sumZ = bcmdlVertices.reduce(CGFloat(0)) { $0 + $1.z }
        let count = CGFloat(bcmdlVertices.count)
        let cloudCX = sumX / count
        let cloudCZ = sumZ / count

        // Échelle pour ajuster aux dimensions de la carte
        let xs = bcmdlVertices.map { abs($0.x - cloudCX) }
        let zs = bcmdlVertices.map { abs($0.z - cloudCZ) }
        let maxX = xs.max() ?? 1
        let maxZ = zs.max() ?? 1
        let scaleX: CGFloat = maxX > 0 ? (mapW * 0.45) / maxX : 1
        let scaleZ: CGFloat = maxZ > 0 ? (mapH * 0.45) / maxZ : 1
        let scale = min(scaleX, scaleZ)

        // Translater et scaler les vertices
        let adjusted: [SCNVector3] = bcmdlVertices.map { v in
            SCNVector3(
                (v.x - cloudCX) * scale + centerX,
                v.y * 0.5 + 2.0,   // légèrement au-dessus du sol
                (v.z - cloudCZ) * scale + centerZ
            )
        }

        // Limiter à 5000 points pour les perfs
        let limited = Array(adjusted.prefix(5000))

        if let geo = BCMDLHelper.makePointCloud(vertices: limited,
                                                 color: NSColor.systemYellow.withAlphaComponent(0.85)) {
            let pointNode = SCNNode(geometry: geo)
            scene.rootNode.addChildNode(pointNode)
        }
    }
}
