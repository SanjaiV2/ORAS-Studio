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
        scene.background.contents = NSColor.black

        let mapW = CGFloat(collisionMap.width)
        let mapH = CGFloat(collisionMap.height)
        let center = SCNVector3(mapW / 2, 0, mapH / 2)

        // ── Sky dome ──
        if let sky = ProceduralTextureKit.skyDomeGeometry(background: background) {
            sky.position = SCNVector3(mapW / 2, -200, mapH / 2)
            scene.rootNode.addChildNode(sky)
        }

        // ── Fog ──
        if background == .outdoor || background == .water {
            scene.fogColor = background == .water
                ? NSColor(red: 0.15, green: 0.40, blue: 0.75, alpha: 1)
                : NSColor(red: 0.75, green: 0.88, blue: 0.98, alpha: 1)
            scene.fogStartDistance = max(mapW, mapH) * 0.9
            scene.fogEndDistance   = max(mapW, mapH) * 2.5
        }

        // ── Étape 1 + 2 : Terrain voxel (relief automatique par grille) ──
        let terrainNode = BCMDLHelper.makeCollisionGeometry(from: collisionMap, background: background)
        scene.rootNode.addChildNode(terrainNode)

        // ── Étape 3 : Entités 3D volumétriques (zéro point jaune) ──
        let entitiesNode = SCNNode()
        for marker in entityMarkers {
            entitiesNode.addChildNode(makeEntityNode(marker: marker))
        }
        scene.rootNode.addChildNode(entitiesNode)

        // ── Overlay BCH (données TM brutes, si disponibles) ──
        if !bcmdlVertices.isEmpty {
            addBCMDLOverlay(to: scene, mapW: mapW, mapH: mapH)
        }

        // ── Caméra perspective 3/4 isométrique ──
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

        // ── Éclairage 3-points ──
        addLighting(to: scene)

        return scene
    }

    // MARK: — Éclairage

    private func addLighting(to scene: SCNScene) {
        let amb = SCNLight(); amb.type = .ambient
        amb.intensity = 350
        amb.color = NSColor(red: 0.65, green: 0.68, blue: 0.75, alpha: 1)
        let ambNode = SCNNode(); ambNode.light = amb
        scene.rootNode.addChildNode(ambNode)

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

        let fill = SCNLight(); fill.type = .directional
        fill.color = NSColor(red: 0.55, green: 0.72, blue: 0.98, alpha: 1)
        fill.intensity = background == .cave ? 150 : 280
        let fillNode = SCNNode(); fillNode.light = fill
        fillNode.eulerAngles = SCNVector3(CGFloat.pi / 5, -CGFloat.pi / 3, 0)
        scene.rootNode.addChildNode(fillNode)
    }

    // MARK: — Entités 3D typées (Étape 3 — zéro point jaune)

    private func makeEntityNode(marker: ZoneEntityMarker) -> SCNNode {
        let root = SCNNode()
        let tx = Float(marker.x) + 0.5
        let tz = Float(marker.y) + 0.5

        switch marker.kind {

        // ── Arbre (flora) ou bâtiment selon zone ──
        case .furniture:
            if isTree(objID: marker.objID) {
                root.addChildNode(makeTree(x: tx, z: tz))
            } else {
                root.addChildNode(makeBuilding(x: tx, z: tz))
            }

        // ── PNJ : silhouette corps + tête ──
        case .npc:
            // Corps
            let bodyGeo = SCNBox(width: 0.45, height: 0.80, length: 0.25, chamferRadius: 0.06)
            let bodyMat = SCNMaterial()
            bodyMat.diffuse.contents = NSColor(red: 0.97, green: 0.61, blue: 0.12, alpha: 1)
            bodyGeo.materials = [bodyMat]
            let bodyNode = SCNNode(geometry: bodyGeo)
            bodyNode.position = SCNVector3(tx, 0.5, tz)
            // Tête
            let headGeo = SCNSphere(radius: 0.22)
            let headMat = SCNMaterial()
            headMat.diffuse.contents = NSColor(red: 0.96, green: 0.80, blue: 0.65, alpha: 1)
            headGeo.materials = [headMat]
            let headNode = SCNNode(geometry: headGeo)
            headNode.position = SCNVector3(tx, 1.10, tz)
            root.addChildNode(bodyNode); root.addChildNode(headNode)

        // ── Warp : tore bleu + pilier lumineux ──
        case .warp:
            let ring = SCNTorus(ringRadius: 0.42, pipeRadius: 0.08)
            let ringMat = SCNMaterial()
            ringMat.diffuse.contents = NSColor(red: 0.20, green: 0.55, blue: 1.0, alpha: 0.9)
            ringMat.emission.contents = NSColor(red: 0.05, green: 0.25, blue: 0.60, alpha: 1)
            ringMat.shininess = 0.95; ringMat.isDoubleSided = true
            ring.materials = [ringMat]
            let ringNode = SCNNode(geometry: ring)
            ringNode.eulerAngles = SCNVector3(-Float.pi/6, 0, 0)
            ringNode.position = SCNVector3(tx, 0.55, tz)
            // Pilier
            let beam = SCNCylinder(radius: 0.04, height: 1.5)
            let beamMat = SCNMaterial()
            beamMat.diffuse.contents  = NSColor(red: 0.35, green: 0.70, blue: 1.0, alpha: 0.6)
            beamMat.emission.contents = NSColor(red: 0.35, green: 0.70, blue: 1.0, alpha: 0.6)
            beamMat.isDoubleSided = true
            beam.materials = [beamMat]
            let beamNode = SCNNode(geometry: beam)
            beamNode.position = SCNVector3(tx, 0.75, tz)
            root.addChildNode(ringNode); root.addChildNode(beamNode)

        // ── Trigger : marqueur jaune plat au sol ──
        case .trigger:
            let geo = SCNBox(width: 0.80, height: 0.04, length: 0.80, chamferRadius: 0)
            let mat = SCNMaterial()
            mat.diffuse.contents = NSColor(red: 1.0, green: 0.90, blue: 0.10, alpha: 0.75)
            mat.emission.contents = NSColor(red: 0.40, green: 0.35, blue: 0.00, alpha: 1)
            geo.materials = [mat]
            let node = SCNNode(geometry: geo)
            node.position = SCNVector3(tx, 0.04, tz)
            node.eulerAngles = SCNVector3(0, Float.pi/4, 0)
            root.addChildNode(node)
        }

        return root
    }

    // MARK: — Volumes entités

    // Arbre ORAS : tronc cylindrique marron + feuillage sphère verte
    private func makeTree(x: Float, z: Float) -> SCNNode {
        let tree = SCNNode()
        // Tronc
        let trunk = SCNCylinder(radius: 0.12, height: 1.2)
        let trunkMat = SCNMaterial()
        trunkMat.diffuse.contents = NSColor(red: 0.38, green: 0.24, blue: 0.12, alpha: 1)
        trunk.materials = [trunkMat]
        let trunkNode = SCNNode(geometry: trunk)
        trunkNode.position = SCNVector3(x, 0.6, z)   // centré à mi-hauteur
        // Feuillage
        let foliage = SCNSphere(radius: 0.55)
        let foliageMat = SCNMaterial()
        foliageMat.diffuse.contents = NSColor(red: 0.18, green: 0.58, blue: 0.15, alpha: 1)
        foliageMat.specular.contents = NSColor(white: 0.1, alpha: 1)
        foliage.materials = [foliageMat]
        let foliageNode = SCNNode(geometry: foliage)
        foliageNode.position = SCNVector3(x, 1.75, z) // au-dessus du tronc
        tree.addChildNode(trunkNode); tree.addChildNode(foliageNode)
        return tree
    }

    // Bâtiment / infrastructure : bloc gris avec fenêtres
    private func makeBuilding(x: Float, z: Float) -> SCNNode {
        let building = SCNNode()
        // Corps principal
        let geo = SCNBox(width: 0.80, height: 1.4, length: 0.80, chamferRadius: 0.06)
        let mat = SCNMaterial()
        mat.diffuse.contents = NSColor(red: 0.85, green: 0.85, blue: 0.87, alpha: 1)
        mat.specular.contents = NSColor(white: 0.2, alpha: 1)
        mat.shininess = 0.3
        geo.materials = [mat]
        let body = SCNNode(geometry: geo)
        body.position = SCNVector3(x, 0.7, z)
        // Toit
        let roof = SCNPyramid(width: 0.90, height: 0.40, length: 0.90)
        let roofMat = SCNMaterial()
        roofMat.diffuse.contents = NSColor(red: 0.70, green: 0.22, blue: 0.20, alpha: 1)
        roof.materials = [roofMat]
        let roofNode = SCNNode(geometry: roof)
        roofNode.position = SCNVector3(x, 1.6, z)
        building.addChildNode(body); building.addChildNode(roofNode)
        return building
    }

    // Heuristique : objID < 100 → flore/arbre ; sinon → infrastructure
    private func isTree(objID: UInt16) -> Bool {
        if background == .outdoor { return objID < 100 }
        if background == .cave    { return false }
        return objID < 50
    }

    // MARK: — Overlay BCH point cloud

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
        if let geo = BCMDLHelper.makePointCloud(vertices: adjusted,
            color: NSColor(red: 1.0, green: 0.88, blue: 0.25, alpha: 0.85)) {
            scene.rootNode.addChildNode(SCNNode(geometry: geo))
        }
    }
}
