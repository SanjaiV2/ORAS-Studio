import Foundation
import SceneKit

// Port fidèle de Ohana3DS-Rebirth/BCH.cs — extraction géométrie uniquement.
// Supporte ORAS (backwardCompatibility = 0x21), conteneur TM (BCH à offset 0x80).

struct BCHParser {

    // MARK: — Types publics

    struct VertexData {
        var position: SIMD3<Float>
        var normal:   SIMD3<Float>
        var uv:       SIMD2<Float>
    }

    struct MeshData {
        var vertices:      [VertexData]
        var indices:       [UInt32]
        var materialIndex: UInt16
    }

    // MARK: — Point d'entrée

    static func parse(fileData: Data, isTM: Bool = false) -> [MeshData] {
        // Copie mutable — la relocation patche les offsets en place (comme Ohana3DS)
        var b: [UInt8]
        if isTM {
            // Format TM (PkmnContainer) :  "TM" + sectionCount(u16) + offsets[sectionCount+1](u32 each)
            // section[i] start = u32 at [4 + i*4] ;  section[i] end = u32 at [4 + (i+1)*4]
            // Le terrain principal est en section 1 (Ohana3DS GR.cs : container.content[1])
            guard fileData.count >= 14,
                  fileData[0] == 0x54, fileData[1] == 0x4D else { return [] }  // "TM"
            let sectionCount = Int(fileData.withUnsafeBytes {
                $0.loadUnaligned(fromByteOffset: 2, as: UInt16.self)
            })
            guard sectionCount >= 2 else { return [] }
            let sec1Start = Int(fileData.withUnsafeBytes {
                $0.loadUnaligned(fromByteOffset: 8, as: UInt32.self)
            })
            let sec1End = Int(fileData.withUnsafeBytes {
                $0.loadUnaligned(fromByteOffset: 12, as: UInt32.self)
            })
            guard sec1Start < sec1End, sec1End <= fileData.count else { return [] }
            b = Array(fileData[sec1Start..<sec1End])
        } else {
            b = Array(fileData)
        }

        guard b.count > 0x44 else { return [] }

        guard b.count > 8, b[0] == 0x42, b[1] == 0x43, b[2] == 0x48 else { return [] }

        // Ohana3DS IOUtils.readString(input, 0) ne déplace PAS la position (advancePosition=false).
        // Ensuite Seek(4) → pos=4, puis ReadByte() → bc est à l'octet 4, pas 8.
        let bc         = b[4]           // backwardCompatibility = 0x21 pour ORAS
        let mainHdrOff = ru32(b, 8)     // = 0x44 (header principal des modèles)
        let strTblOff  = ru32(b, 12)    // = 0x1b40
        let gpuCmdOff  = ru32(b, 16)    // = 0x1e40
        let dataOff    = ru32(b, 20)    // = 0x3380

        var p = 24
        var dataExtOff: UInt32 = 0
        if bc > 0x20 { dataExtOff = ru32(b, p); p += 4 }   // = 0x5100, p=28
        let relTblOff = ru32(b, p); p += 4                  // = 0x1afc, p=32
        p += 16                              // skip mainHdrLen+strTblLen+gpuCmdLen+dataLen
        if bc > 0x20 { p += 4 }             // skip dataExtendedLength
        let relTblLen = ru32(b, p)           // = 80

        applyRelocation(&b, relTblOff: relTblOff, relTblLen: relTblLen, bc: bc,
                        mainHdrOff: mainHdrOff, strTblOff: strTblOff,
                        gpuCmdOff: gpuCmdOff, dataOff: dataOff, dataExtOff: dataExtOff)

        let modPtrOff = Int(ru32(b, Int(mainHdrOff)))
        let modCount  = Int(ru32(b, Int(mainHdrOff) + 4))

        var result: [MeshData] = []
        for mi in 0..<modCount {
            let modelOff = Int(ru32(b, modPtrOff + mi * 4))
            result.append(contentsOf: parseModel(b, at: modelOff, bc: bc))
        }
        return result
    }

    // MARK: — Conversion SceneKit

    static func toSCNNode(meshes: [MeshData], scale: Float = 1.0) -> SCNNode {
        let root = SCNNode()
        for mesh in meshes {
            guard !mesh.vertices.isEmpty else { continue }
            guard let geo = buildGeometry(mesh: mesh, scale: scale) else { continue }
            let mat = SCNMaterial()
            mat.diffuse.contents  = NSColor(red: 0.62, green: 0.54, blue: 0.44, alpha: 1)
            mat.specular.contents = NSColor(white: 0.15, alpha: 1)
            mat.shininess = 0.25
            mat.isDoubleSided = true
            geo.materials = [mat]
            root.addChildNode(SCNNode(geometry: geo))
        }
        return root
    }

    private static func buildGeometry(mesh: MeshData, scale: Float) -> SCNGeometry? {
        let vCount = mesh.vertices.count
        guard vCount > 0 else { return nil }

        var posBuf  = [Float](); posBuf.reserveCapacity(vCount * 3)
        var normBuf = [Float](); normBuf.reserveCapacity(vCount * 3)
        var uvBuf   = [Float](); uvBuf.reserveCapacity(vCount * 2)

        for v in mesh.vertices {
            posBuf  += [v.position.x * scale, v.position.y * scale, v.position.z * scale]
            normBuf += [v.normal.x, v.normal.y, v.normal.z]
            uvBuf   += [v.uv.x, 1.0 - v.uv.y]   // flip V pour SceneKit
        }

        let posData  = Data(bytes: posBuf,  count: posBuf.count  * 4)
        let normData = Data(bytes: normBuf, count: normBuf.count * 4)
        let uvData   = Data(bytes: uvBuf,   count: uvBuf.count   * 4)

        let posSrc  = SCNGeometrySource(data: posData,  semantic: .vertex,
            vectorCount: vCount, usesFloatComponents: true,
            componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12)
        let normSrc = SCNGeometrySource(data: normData, semantic: .normal,
            vectorCount: vCount, usesFloatComponents: true,
            componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12)
        let uvSrc   = SCNGeometrySource(data: uvData,   semantic: .texcoord,
            vectorCount: vCount, usesFloatComponents: true,
            componentsPerVector: 2, bytesPerComponent: 4, dataOffset: 0, dataStride: 8)

        var idx32 = mesh.indices
        let idxData = Data(bytes: &idx32, count: idx32.count * 4)
        let element = SCNGeometryElement(data: idxData,
            primitiveType: .triangles,
            primitiveCount: idx32.count / 3,
            bytesPerIndex: 4)

        return SCNGeometry(sources: [posSrc, normSrc, uvSrc], elements: [element])
    }

    // MARK: — Table de relocation

    private static func applyRelocation(_ b: inout [UInt8],
                                         relTblOff: UInt32, relTblLen: UInt32, bc: UInt8,
                                         mainHdrOff: UInt32, strTblOff: UInt32,
                                         gpuCmdOff: UInt32, dataOff: UInt32, dataExtOff: UInt32) {
        var o = Int(relTblOff)
        let end = Int(relTblOff) + Int(relTblLen)
        while o + 4 <= end && o + 4 <= b.count {
            let entry  = ru32(b, o)
            let offset = entry & 0x1FFFFFF
            let flags  = UInt8(entry >> 25)
            o += 4

            // Patch 1 : pointeurs dans la section mainHeader
            let mPos = Int(offset) * 4 + Int(mainHdrOff)
            if mPos + 4 <= b.count {
                switch flags {
                case 0:
                    wu32(&b, mPos, ru32(b, mPos) &+ mainHdrOff)
                case 1:
                    let bPos = Int(offset) + Int(mainHdrOff)
                    if bPos + 4 <= b.count { wu32(&b, bPos, ru32(b, bPos) &+ strTblOff) }
                case 2:
                    wu32(&b, mPos, ru32(b, mPos) &+ gpuCmdOff)
                case 7, 12:
                    wu32(&b, mPos, ru32(b, mPos) &+ dataOff)
                default: break
                }
            }

            // Patch 2 : adresses vertex/index dans les commandes GPU
            let gPos = Int(offset) * 4 + Int(gpuCmdOff)
            if gPos + 4 <= b.count && bc >= 0x21 {
                switch flags {
                case 0x25, 0x26:
                    wu32(&b, gPos, ru32(b, gPos) &+ dataOff)
                case 0x27:
                    let v = ru32(b, gPos) &+ dataOff
                    wu32(&b, gPos, (v & 0x7FFFFFFF) | 0x80000000)
                case 0x28:
                    wu32(&b, gPos, (ru32(b, gPos) &+ dataOff) & 0x7FFFFFFF)
                case 0x2B:
                    wu32(&b, gPos, ru32(b, gPos) &+ dataExtOff)
                case 0x2C:
                    let v = ru32(b, gPos) &+ dataExtOff
                    wu32(&b, gPos, (v & 0x7FFFFFFF) | 0x80000000)
                case 0x2D:
                    wu32(&b, gPos, (ru32(b, gPos) &+ dataExtOff) & 0x7FFFFFFF)
                default: break
                }
            }
        }
    }

    // MARK: — Parsing du modèle

    private static func parseModel(_ b: [UInt8], at modelOff: Int, bc: UInt8) -> [MeshData] {
        // Layout bchModelHeader (bc >= 0x21) :
        // +0  flags(1), skeletonScalingType(1), silhouetteMaterialEntries(2)
        // +4  worldTransform : 12 × f32 = 48 octets
        // +52 materialsTableOffset(4)
        // +56 materialsTableEntries(4)
        // +60 materialsNameOffset(4)
        // +64 verticesTableOffset(4)  ←
        // +68 verticesTableEntries(4) ←
        guard modelOff + 72 <= b.count else { return [] }
        let vtxTblOff = Int(ru32(b, modelOff + 64))
        let vtxTblCnt = Int(ru32(b, modelOff + 68))

        var result: [MeshData] = []
        for oi in 0..<vtxTblCnt {
            // bchObjectEntry : 0x38 octets
            let base = vtxTblOff + oi * 0x38
            guard base + 0x38 <= b.count else { break }

            let matID    = ru16(b, base + 0)
            let entFlags = ru16(b, base + 2)
            if bc != 8 && (entFlags & 1) != 0 { continue }   // silhouette

            let vshCmdOff  = Int(ru32(b, base + 8))
            let vshCmdWC   = Int(ru32(b, base + 12))
            let faceHdrOff = Int(ru32(b, base + 16))
            let faceHdrCnt = Int(ru32(b, base + 20))

            let vshSet = parsePICACommands(b, at: vshCmdOff, wordCount: vshCmdWC)

            // Uniforms : reg6 = positionOffset [W,Z,Y,X], reg7 = scales [...,posScale,...,tex0Scale]
            let reg6 = vshSet.floatUniforms[6] ?? []
            let reg7 = vshSet.floatUniforms[7] ?? []
            let posScale  = reg7.count >= 5 ? reg7[reg7.count - 5] : 1.0
            let posOffX   = reg6.count >= 1 ? reg6[reg6.count - 1] : 0.0
            let posOffY   = reg6.count >= 2 ? reg6[reg6.count - 2] : 0.0
            let posOffZ   = reg6.count >= 3 ? reg6[reg6.count - 3] : 0.0
            let tex0Scale = reg7.count >= 1 ? reg7[reg7.count - 1] : 1.0

            // Vertex buffer (VSH commands)
            let vtxAddr   = Int(vshSet.cmds[0x203] ?? 0)
            let stride0   = vshSet.cmds[0x205] ?? 0
            let vtxStride = Int((stride0 >> 16) & 0xFF)
            let totalAttr = Int(stride0 >> 28)
            guard vtxAddr > 0, vtxStride > 0, totalAttr > 0 else { continue }

            // Permutation principale (0x2BB | 0x2BC<<32)
            let mPermLo = UInt64(vshSet.cmds[0x2BB] ?? 0)
            let mPermHi = UInt64(vshSet.cmds[0x2BC] ?? 0)
            let mainPerm = mPermLo | (mPermHi << 32)

            // Format des attributs (0x201 | 0x202<<32)
            let fmtLo  = UInt64(vshSet.cmds[0x201] ?? 0)
            let fmtHi  = UInt64(vshSet.cmds[0x202] ?? 0)
            let fmtAll = fmtLo | (fmtHi << 32)

            // Permutation buffer 0 (0x204 | low16(0x205)<<32)
            let bPermLo = UInt64(vshSet.cmds[0x204] ?? 0)
            let bPermHi = UInt64((vshSet.cmds[0x205] ?? 0) & 0xFFFF)
            let bufPerm = bPermLo | (bPermHi << 32)

            // Face groups (index buffers dans PICA commands séparés)
            let hasFaces = faceHdrCnt > 0
            var faceGroups: [(idxAddr: Int, idxIs16: Bool, idxTotal: Int)] = []

            if hasFaces {
                for f in 0..<faceHdrCnt {
                    let faceBase = faceHdrOff + f * 0x34
                    guard faceBase + 0x34 <= b.count else { break }
                    // faceHeaderOffset à +0x2C, faceHeaderWordCount à +0x30
                    let fhOff = Int(ru32(b, faceBase + 0x2C))
                    let fhWC  = Int(ru32(b, faceBase + 0x30))
                    let idxSet = parsePICACommands(b, at: fhOff, wordCount: fhWC)
                    let idxCfg   = idxSet.cmds[0x227] ?? 0
                    let idxAddr  = Int(idxCfg & 0x7FFFFFFF)
                    let idxIs16  = (idxCfg >> 31) == 1   // 1=unsignedShort, 0=unsignedByte
                    let idxTotal = Int(idxSet.cmds[0x228] ?? 0)
                    if idxAddr > 0 && idxTotal > 0 {
                        faceGroups.append((idxAddr, idxIs16, idxTotal))
                    }
                }
            } else {
                // Table alternative sans PICA commands (format simplifié)
                let altBase = vtxTblOff + vtxTblCnt * 0x38 + oi * 0x1C + 0x10
                if altBase + 8 <= b.count {
                    let idxAddr  = Int(ru32(b, altBase))
                    let idxTotal = Int(ru32(b, altBase + 4))
                    if idxAddr > 0 && idxTotal > 0 {
                        faceGroups.append((idxAddr, true, idxTotal))   // toujours u16 ici
                    }
                }
            }

            for fg in faceGroups {
                guard let mesh = buildMesh(b,
                    vtxAddr: vtxAddr, vtxStride: vtxStride, totalAttr: totalAttr,
                    mainPerm: mainPerm, fmtAll: fmtAll, bufPerm: bufPerm,
                    posScale: posScale, posOffX: posOffX, posOffY: posOffY, posOffZ: posOffZ,
                    tex0Scale: tex0Scale,
                    idxAddr: fg.idxAddr, idxIs16: fg.idxIs16, idxTotal: fg.idxTotal,
                    materialIndex: matID) else { continue }
                result.append(mesh)
            }
        }
        return result
    }

    // MARK: — Construction d'un mesh depuis vertex + index buffers

    private static func buildMesh(_ b: [UInt8],
                                   vtxAddr: Int, vtxStride: Int, totalAttr: Int,
                                   mainPerm: UInt64, fmtAll: UInt64, bufPerm: UInt64,
                                   posScale: Float, posOffX: Float, posOffY: Float, posOffZ: Float,
                                   tex0Scale: Float,
                                   idxAddr: Int, idxIs16: Bool, idxTotal: Int,
                                   materialIndex: UInt16) -> MeshData? {
        guard idxAddr + idxTotal * (idxIs16 ? 2 : 1) <= b.count else { return nil }

        var verts:  [VertexData] = []
        var inds:   [UInt32]     = []
        var remap:  [Int: UInt32] = [:]

        for fi in 0..<idxTotal {
            let rawIdx: Int
            if idxIs16 {
                rawIdx = Int(ru16(b, idxAddr + fi * 2))
            } else {
                rawIdx = Int(b[idxAddr + fi])
            }

            if let existing = remap[rawIdx] { inds.append(existing); continue }

            let vertBase = vtxAddr + rawIdx * vtxStride
            guard vertBase + vtxStride <= b.count else { break }

            var vd  = VertexData(position: .zero, normal: .zero, uv: .zero)
            var cur = vertBase

            for ai in 0..<totalAttr {
                let localSlot = Int((bufPerm >> (ai * 4)) & 0xF)
                let mainSlot  = Int((mainPerm >> (localSlot * 4)) & 0xF)
                let nibble    = UInt8((fmtAll >> (localSlot * 4)) & 0xF)
                let aType     = nibble & 0x3
                let nComp     = Int(nibble >> 2) + 1

                var cv = [Float](repeating: 0, count: 4)
                for c in 0..<nComp {
                    guard cur < b.count else { break }
                    switch aType {
                    case 0:                                          // signedByte
                        cv[c] = Float(Int8(bitPattern: b[cur])); cur += 1
                    case 1:                                          // unsignedByte
                        cv[c] = Float(b[cur]); cur += 1
                    case 2:                                          // signedShort
                        cv[c] = Float(Int16(bitPattern: ru16(b, cur))); cur += 2
                    default:                                         // float32
                        cv[c] = rf32(b, cur); cur += 4
                    }
                }

                switch mainSlot {
                case 0:   // position
                    vd.position = SIMD3<Float>(
                        cv[0] * posScale + posOffX,
                        cv[1] * posScale + posOffY,
                        cv[2] * posScale + posOffZ)
                case 1:   // normal
                    vd.normal = SIMD3<Float>(cv[0], cv[1], cv[2])
                case 4:   // texCoord0
                    vd.uv = SIMD2<Float>(cv[0] * tex0Scale, cv[1] * tex0Scale)
                default:  break   // tangent, color, bone data ignorés pour le terrain
                }
            }

            let newIdx = UInt32(verts.count)
            verts.append(vd)
            remap[rawIdx] = newIdx
            inds.append(newIdx)
        }

        guard !verts.isEmpty else { return nil }
        return MeshData(vertices: verts, indices: inds, materialIndex: materialIndex)
    }

    // MARK: — Lecteur de commandes PICA200

    struct PICACommandSet {
        var cmds:         [UInt32: UInt32]   // commandId → dernière valeur écrite
        var floatUniforms:[UInt32: [Float]]  // registre → valeurs accumulées (ordre push)
    }

    private static func parsePICACommands(_ b: [UInt8], at startOff: Int, wordCount: Int) -> PICACommandSet {
        var cmds          = [UInt32: UInt32]()
        var floatUniforms = [UInt32: [Float]]()
        var currentReg:   UInt32 = 0
        var pendingFloats = [Float]()

        var pos       = startOff
        var wordsRead = 0

        while wordsRead < wordCount && pos + 8 <= b.count {
            let parameter = ru32(b, pos)
            let header    = ru32(b, pos + 4)
            pos += 8; wordsRead += 2

            let id    = UInt32(header & 0xFFFF)
            let mask  = (header >> 16) & 0xF
            let extra = Int((header >> 20) & 0x7FF)
            let consec = (header >> 31) != 0

            cmds[id] = maskedWrite(cmds[id] ?? 0, parameter, mask)

            if id == 0x2C0 { currentReg = parameter & 0x7FFFFFFF }
            if id == 0x2C1 { pendingFloats.append(rf32u(cmds[id] ?? 0)) }
            if id == 0x23D { break }   // blockEnd

            var curId = id
            for _ in 0..<extra {
                guard pos + 4 <= b.count else { break }
                if consec { curId &+= 1 }
                let ep = ru32(b, pos); pos += 4; wordsRead += 1
                cmds[curId] = maskedWrite(cmds[curId] ?? 0, ep, mask)
                if curId > 0x2C0 && curId < 0x2C9 {
                    pendingFloats.append(rf32u(cmds[curId] ?? 0))
                }
            }

            if !pendingFloats.isEmpty {
                floatUniforms[currentReg, default: []].append(contentsOf: pendingFloats)
                pendingFloats.removeAll()
            }

            // Alignement 8 octets entre paires de commandes
            if (pos & 7) != 0 {
                pos = (pos + 7) & ~7
                wordsRead = (pos - startOff) / 4
            }
        }

        return PICACommandSet(cmds: cmds, floatUniforms: floatUniforms)
    }

    // Écriture masquée : les 4 bits bas sont sélectivement mis à jour par mask (fidèle à Ohana3DS)
    private static func maskedWrite(_ old: UInt32, _ new: UInt32, _ mask: UInt32) -> UInt32 {
        (old & (~mask & 0xF)) | (new & (0xFFFFFFF0 | mask))
    }

    // MARK: — Helpers de lecture d'octets (little-endian)

    private static func ru32(_ b: [UInt8], _ o: Int) -> UInt32 {
        guard o >= 0, o + 4 <= b.count else { return 0 }
        return UInt32(b[o]) | (UInt32(b[o+1]) << 8) | (UInt32(b[o+2]) << 16) | (UInt32(b[o+3]) << 24)
    }

    private static func ru16(_ b: [UInt8], _ o: Int) -> UInt16 {
        guard o >= 0, o + 2 <= b.count else { return 0 }
        return UInt16(b[o]) | (UInt16(b[o+1]) << 8)
    }

    private static func rf32(_ b: [UInt8], _ o: Int) -> Float {
        Float(bitPattern: ru32(b, o))
    }

    private static func rf32u(_ bits: UInt32) -> Float {
        Float(bitPattern: bits)
    }

    private static func wu32(_ b: inout [UInt8], _ o: Int, _ val: UInt32) {
        guard o >= 0, o + 4 <= b.count else { return }
        b[o]   = UInt8(val & 0xFF)
        b[o+1] = UInt8((val >> 8)  & 0xFF)
        b[o+2] = UInt8((val >> 16) & 0xFF)
        b[o+3] = UInt8((val >> 24) & 0xFF)
    }
}
