import Foundation
import SceneKit
import CoreGraphics

// Port fidèle de Ohana3DS-Rebirth/BCH.cs — extraction géométrie + textures ETC1.
// Supporte ORAS (backwardCompatibility = 0x21), conteneur TM (BCH à offset 0x80).

struct BCHParser {

    // MARK: — Types publics

    struct VertexData {
        var position: SIMD3<Float>
        var normal:   SIMD3<Float>
        var uv:       SIMD2<Float>
        var color:    SIMD4<Float> = SIMD4(1, 1, 1, 1)   // vertex color (AO bakée)
    }

    struct MeshData {
        var vertices:      [VertexData]
        var indices:       [UInt32]
        var materialIndex: UInt16
        var texture:       CGImage? = nil   // décodé par parseWithTextures()
    }

    // MARK: — Point d'entrée

    static func parse(fileData: Data, isTM: Bool = false) -> [MeshData] {
        // Copie mutable — la relocation patche les offsets en place (comme Ohana3DS)
        var b: [UInt8]
        if isTM {
            // Format TM (PkmnContainer) :  "TM" + sectionCount(u16) + offsets[sectionCount+1](u32 each)
            // section[i] start = u32 at [4 + i*4] ;  section[i] end = u32 at [4 + (i+1)*4]
            // Pour sc≥2 : terrain BCH en section 1 (Ohana3DS GR.cs : container.content[1])
            // Pour sc=1 : terrain BCH directement en section 0
            guard fileData.count >= 12,
                  fileData[0] == 0x54, fileData[1] == 0x4D else { return [] }  // "TM"
            let sectionCount = Int(fileData.withUnsafeBytes {
                $0.loadUnaligned(fromByteOffset: 2, as: UInt16.self)
            })
            guard sectionCount >= 1 else { return [] }
            let sec0Start = Int(fileData.withUnsafeBytes {
                $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self)
            })
            let sec0End = Int(fileData.withUnsafeBytes {
                $0.loadUnaligned(fromByteOffset: 8, as: UInt32.self)
            })
            if sectionCount >= 2 {
                // Section 1 = terrain principal
                let sec1Start = sec0End
                let sec1End = Int(fileData.withUnsafeBytes {
                    $0.loadUnaligned(fromByteOffset: 12, as: UInt32.self)
                })
                guard sec1Start < sec1End, sec1End <= fileData.count else { return [] }
                b = Array(fileData[sec1Start..<sec1End])
            } else {
                // Section 0 unique = terrain direct (zones sc=1)
                guard sec0Start < sec0End, sec0End <= fileData.count else { return [] }
                b = Array(fileData[sec0Start..<sec0End])
            }
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
        print("[BCH] size=\(b.count) isTM=\(isTM) modPtrOff=0x\(String(modPtrOff,radix:16)) modCount=\(modCount)")

        var result: [MeshData] = []
        for mi in 0..<modCount {
            let modelOff = Int(ru32(b, modPtrOff + mi * 4))
            let meshes = parseModel(b, at: modelOff, bc: bc)
            result.append(contentsOf: meshes)
        }
        return result
    }

    // MARK: — extractTextures : lit uniquement les textures d'un BCH (typiquement un conteneur PT)

    /// Extrait et décode les textures d'un fichier BCH sans parser la géométrie.
    /// Le BCH peut être brut OU encapsulé dans un conteneur PT (cherche la magic BCH).
    /// Format réel ORAS (bc=0x21) : le "struct texture" est un tableau de triplets
    /// (gpu_cmd_ptr, cmd_count) pointant vers des buffers de commandes PICA200.
    /// Les vraies dimensions + adresse + format se lisent dans les registres GPU :
    ///   REG 0x82 → taille (width en bits 31-16, height en bits 15-0)
    ///   REG 0x85 → adresse absolue des pixels (bit 31 = marqueur reloc, à masquer)
    ///   REG 0x8E → format PICA (7=L8, 12=ETC1, 13=ETC1A4)
    static func extractTextures(from fileData: Data) -> [CGImage?] {
        let bchStart = findBCHStart(in: fileData)
        guard bchStart >= 0 else {
            print("[BCH TEX] aucun magic BCH dans \(fileData.count) B")
            return []
        }
        var b = Array(fileData[bchStart...])
        guard b.count > 0x48,
              b[0] == 0x42, b[1] == 0x43, b[2] == 0x48 else { return [] }

        let bc         = b[4]
        let mainHdrOff = ru32(b, 8)
        let strTblOff  = ru32(b, 12)
        let gpuCmdOff  = ru32(b, 16)
        let dataOff    = ru32(b, 20)
        var p = 24
        var dataExtOff: UInt32 = 0
        if bc > 0x20 { dataExtOff = ru32(b, p); p += 4 }
        let relTblOff = ru32(b, p); p += 4
        p += 16; if bc > 0x20 { p += 4 }
        let relTblLen = ru32(b, p)

        applyRelocation(&b, relTblOff: relTblOff, relTblLen: relTblLen, bc: bc,
                        mainHdrOff: mainHdrOff, strTblOff: strTblOff,
                        gpuCmdOff: gpuCmdOff, dataOff: dataOff, dataExtOff: dataExtOff)

        let texPtrTableOff = Int(ru32(b, Int(mainHdrOff) + 36))
        let texCount       = Int(ru32(b, Int(mainHdrOff) + 40))
        print("[BCH TEX] mainHdr=0x\(String(mainHdrOff,radix:16))"
            + " gpuCmd=0x\(String(gpuCmdOff,radix:16))"
            + " data=0x\(String(dataOff,radix:16))"
            + " texPtrOff=0x\(String(texPtrTableOff,radix:16)) count=\(texCount)")

        guard texPtrTableOff > 0, texCount > 0,
              texPtrTableOff + texCount * 4 <= b.count else { return [] }

        var results: [CGImage?] = Array(repeating: nil, count: texCount)
        for ti in 0..<texCount {
            let tsOff = Int(ru32(b, texPtrTableOff + ti * 4))
            guard tsOff > 0, tsOff + 8 <= b.count else { continue }

            // tsOff pointe vers un triplet (gpu_cmd_ptr, cmd_count_u32).
            // gpu_cmd_ptr est relocalisé → adresse absolue dans b[].
            let cmdBufPtr = Int(ru32(b, tsOff))
            guard cmdBufPtr >= 0, cmdBufPtr + 8 <= b.count else { continue }

            // Scanner les commandes GPU PICA200 : paires (data_u32, header_u32)
            // header bits 15-0 = registre ; on cherche 0x82, 0x85, 0x8E
            var width = 0, height = 0, fmt = 7, dataAddr = 0
            let cmdEnd = min(cmdBufPtr + 96, b.count - 7)  // au plus ~12 commandes
            var off = cmdBufPtr
            while off < cmdEnd {
                let cmdData = ru32(b, off)
                let cmdHdr  = ru32(b, off + 4)
                let reg     = Int(cmdHdr & 0xFFFF)
                switch reg {
                case 0x82:  // TEX0_SIZE : width en bits 31-16, height en bits 15-0
                    width  = Int((cmdData >> 16) & 0xFFFF)
                    height = Int(cmdData & 0xFFFF)
                case 0x85:  // TEX0_ADDR : adresse absolue (bit 31 = marqueur reloc 0x27)
                    dataAddr = Int(cmdData & 0x7FFFFFFF)
                case 0x8E:  // TEX0_FORMAT : 7=L8, 12=ETC1, 13=ETC1A4
                    fmt = Int(cmdData & 0xF)
                default: break
                }
                off += 8
            }

            guard width > 0, height > 0, dataAddr > 0, dataAddr < b.count else {
                print("[BCH TEX \(ti)] skip — w=\(width) h=\(height) addr=0x\(String(dataAddr,radix:16))")
                continue
            }
            print("[BCH TEX \(ti)] \(width)×\(height) fmt=\(fmt) addr=0x\(String(dataAddr,radix:16))")

            // Octets par pixel selon format PICA200
            let bpp: Int
            switch fmt {
            case 0:  bpp = 4   // RGBA8888
            case 1:  bpp = 3   // RGB888
            case 5:  bpp = 2   // IA8
            case 7:  bpp = 1   // L8
            case 12: bpp = 0   // ETC1 (0.5 byte/pixel, traité séparément)
            case 13: bpp = 0   // ETC1A4 (1 byte/pixel, traité séparément)
            default: bpp = 0
            }

            switch fmt {
            case 0, 1, 5, 7:   // RGBA8, RGB888, IA8, L8 — swizzle Z-order 8×8
                let sz = width * height * bpp
                guard sz > 0, dataAddr + sz <= b.count else { continue }
                results[ti] = decodePICATiled(
                    data: Data(b[dataAddr..<(dataAddr + sz)]),
                    width: width, height: height, fmt: fmt)
                if results[ti] != nil {
                    let fmtName = fmt == 0 ? "RGBA8" : fmt == 1 ? "RGB888" : fmt == 5 ? "IA8" : "L8"
                    print("[BCH TEX \(ti)] ✓ \(fmtName) \(width)×\(height)")
                }

            case 12:  // ETC1 : 0.5 octet/pixel (blocs 4×4 8 bytes)
                let sz = (width * height) / 2
                guard dataAddr + sz <= b.count else { continue }
                results[ti] = ETC1Decoder.decode(
                    data: Data(b[dataAddr..<(dataAddr + sz)]),
                    width: width, height: height, hasAlpha: false)
                if results[ti] != nil { print("[BCH TEX \(ti)] ✓ ETC1 \(width)×\(height)") }

            case 13:  // ETC1A4 : 1 octet/pixel (blocs 4×4 16 bytes)
                let sz = width * height
                guard dataAddr + sz <= b.count else { continue }
                results[ti] = ETC1Decoder.decode(
                    data: Data(b[dataAddr..<(dataAddr + sz)]),
                    width: width, height: height, hasAlpha: true)
                if results[ti] != nil { print("[BCH TEX \(ti)] ✓ ETC1A4 \(width)×\(height)") }

            default:
                print("[BCH TEX \(ti)] format PICA \(fmt) non supporté")
            }
        }
        return results
    }

    /// Vérifie rapidement si un fichier PT/BCH contient des textures couleur (RGB/RGBA/IA8).
    /// Utilisé pour prioriser les conteneurs PT couleur sur les conteneurs L8 gris.
    static func hasColorTextures(in fileData: Data) -> Bool {
        let bchStart = findBCHStart(in: fileData)
        guard bchStart >= 0 else { return false }
        let b = Array(fileData[bchStart...])
        guard b.count > 0x48, b[0] == 0x42, b[1] == 0x43, b[2] == 0x48 else { return false }
        let bc = b[4]
        let mainHdrOff = ru32(b, 8)
        let gpuCmdOff  = ru32(b, 16)
        let dataOff    = ru32(b, 20)
        var p2 = 24; var dataExtOff2: UInt32 = 0
        if bc > 0x20 { dataExtOff2 = ru32(b, p2); p2 += 4 }
        let relTblOff = ru32(b, p2); p2 += 4; p2 += 16; if bc > 0x20 { p2 += 4 }
        let relTblLen = ru32(b, p2)
        var bMut = b
        applyRelocation(&bMut, relTblOff: relTblOff, relTblLen: relTblLen, bc: bc,
                        mainHdrOff: mainHdrOff, strTblOff: ru32(b, 12),
                        gpuCmdOff: gpuCmdOff, dataOff: dataOff, dataExtOff: dataExtOff2)
        let texPtrOff = Int(ru32(bMut, Int(mainHdrOff) + 36))
        let texCount  = Int(ru32(bMut, Int(mainHdrOff) + 40))
        guard texPtrOff > 0, texCount > 0 else { return false }
        for ti in 0..<texCount {
            let tsOff = Int(ru32(bMut, texPtrOff + ti * 4))
            guard tsOff > 0, tsOff + 8 <= bMut.count else { continue }
            let cmdBufPtr = Int(ru32(bMut, tsOff))
            guard cmdBufPtr > 0, cmdBufPtr + 8 <= bMut.count else { continue }
            var off2 = cmdBufPtr
            while off2 + 8 <= min(cmdBufPtr + 96, bMut.count) {
                let reg = Int(ru32(bMut, off2 + 4) & 0xFFFF)
                if reg == 0x8E {
                    let fmt = Int(ru32(bMut, off2) & 0xF)
                    if fmt == 0 || fmt == 1 || fmt == 5 { return true }  // RGB/RGBA/IA8
                    break
                }
                off2 += 8
            }
        }
        return false
    }

    /// Décode un buffer de pixels PICA200 stocké en tuiles Z-order 8×8 pixels.
    /// Supporte RGBA8 (fmt=0), RGB888 (fmt=1), IA8 (fmt=5), L8 (fmt=7).
    /// L'axe Y est inversé (convention OpenGL → top-down pour CGImage).
    private static func decodePICATiled(data: Data, width: Int, height: Int, fmt: Int) -> CGImage? {
        guard width > 0, height > 0, width % 8 == 0, height % 8 == 0 else { return nil }
        let bpp = fmt == 0 ? 4 : fmt == 1 ? 3 : fmt == 5 ? 2 : 1  // bytes per pixel
        let tilesX = width  / 8
        let tilesY = height / 8
        let hasAlpha = (fmt == 0 || fmt == 5)
        var rgba = [UInt8](repeating: 255, count: width * height * 4)

        for ty in 0..<tilesY {
            let imgTileY = tilesY - 1 - ty   // inversion Y (OpenGL → top-down)
            for tx in 0..<tilesX {
                let tileBase = (ty * tilesX + tx) * 64 * bpp
                for p in 0..<64 {
                    let srcIdx = tileBase + p * bpp
                    guard srcIdx + bpp <= data.count else { break }
                    let lx = (p & 1) | ((p >> 1) & 2) | ((p >> 2) & 4)
                    let ly = ((p >> 1) & 1) | ((p >> 2) & 2) | ((p >> 3) & 4)
                    let imgX = tx * 8 + lx
                    let imgY = imgTileY * 8 + ly
                    guard imgX < width, imgY < height else { continue }
                    let dstIdx = (imgY * width + imgX) * 4
                    switch fmt {
                    case 0:   // RGBA8 : mémoire PICA200 = A,B,G,R (little-endian 32-bit → byte order ABGR)
                        rgba[dstIdx]   = data[srcIdx+3]   // R
                        rgba[dstIdx+1] = data[srcIdx+2]   // G
                        rgba[dstIdx+2] = data[srcIdx+1]   // B
                        rgba[dstIdx+3] = data[srcIdx]     // A
                    case 1:   // RGB888 : mémoire PICA200 = B,G,R (ordre BGR, pas RGB)
                        rgba[dstIdx]   = data[srcIdx+2]   // R
                        rgba[dstIdx+1] = data[srcIdx+1]   // G
                        rgba[dstIdx+2] = data[srcIdx]     // B
                        rgba[dstIdx+3] = 255
                    case 5:   // IA8 : byte 0 = Alpha, byte 1 = Intensity (PICA200 IA8)
                        let a = data[srcIdx], i = data[srcIdx+1]
                        rgba[dstIdx] = i; rgba[dstIdx+1] = i; rgba[dstIdx+2] = i; rgba[dstIdx+3] = a
                    default:  // L8
                        let v = data[srcIdx]
                        rgba[dstIdx] = v; rgba[dstIdx+1] = v; rgba[dstIdx+2] = v; rgba[dstIdx+3] = 255
                    }
                }
            }
        }

        let cs  = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: hasAlpha
            ? CGImageAlphaInfo.premultipliedLast.rawValue
            : CGImageAlphaInfo.noneSkipLast.rawValue)
        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(width: width, height: height,
                       bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: cs, bitmapInfo: info, provider: provider,
                       decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Cherche le premier offset d'un magic BCH ("BCH\0") dans un Data.
    /// Permet de trouver le BCH à l'intérieur d'un conteneur PT/PB/PK.
    static func findBCHStart(in data: Data) -> Int {
        // Recherche rapide de la séquence 0x42 0x43 0x48
        for i in 0..<(data.count - 4) {
            if data[i] == 0x42, data[i+1] == 0x43, data[i+2] == 0x48 { return i }
        }
        return -1
    }

    // MARK: — parseWithTextures : variante de parse() qui extrait aussi les textures ETC1

    /// Comme parse(), mais charge et décode les textures ETC1/ETC1A4 embarquées dans le BCH,
    /// et assigne chaque texture au bon mesh via son materialIndex.
    static func parseWithTextures(fileData: Data, isTM: Bool = false) -> [MeshData] {
        // ── Même extraction TM que parse() ──
        var b: [UInt8]
        if isTM {
            guard fileData.count >= 12,
                  fileData[0] == 0x54, fileData[1] == 0x4D else { return [] }
            let sectionCount = Int(fileData.withUnsafeBytes {
                $0.loadUnaligned(fromByteOffset: 2, as: UInt16.self) })
            guard sectionCount >= 1 else { return [] }
            let sec0Start = Int(fileData.withUnsafeBytes {
                $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self) })
            let sec0End = Int(fileData.withUnsafeBytes {
                $0.loadUnaligned(fromByteOffset: 8, as: UInt32.self) })
            if sectionCount >= 2 {
                let sec1Start = sec0End
                let sec1End = Int(fileData.withUnsafeBytes {
                    $0.loadUnaligned(fromByteOffset: 12, as: UInt32.self) })
                guard sec1Start < sec1End, sec1End <= fileData.count else { return [] }
                b = Array(fileData[sec1Start..<sec1End])
            } else {
                guard sec0Start < sec0End, sec0End <= fileData.count else { return [] }
                b = Array(fileData[sec0Start..<sec0End])
            }
        } else {
            b = Array(fileData)
        }

        guard b.count > 0x44,
              b[0] == 0x42, b[1] == 0x43, b[2] == 0x48 else { return [] }

        let bc         = b[4]
        let mainHdrOff = ru32(b, 8)
        let strTblOff  = ru32(b, 12)
        let gpuCmdOff  = ru32(b, 16)
        let dataOff    = ru32(b, 20)

        var p = 24
        var dataExtOff: UInt32 = 0
        if bc > 0x20 { dataExtOff = ru32(b, p); p += 4 }
        let relTblOff = ru32(b, p); p += 4
        p += 16
        if bc > 0x20 { p += 4 }
        let relTblLen = ru32(b, p)

        applyRelocation(&b, relTblOff: relTblOff, relTblLen: relTblLen, bc: bc,
                        mainHdrOff: mainHdrOff, strTblOff: strTblOff,
                        gpuCmdOff: gpuCmdOff, dataOff: dataOff, dataExtOff: dataExtOff)

        // ── Extraction des textures ──
        // Main header layout réel (bc=0x21, vérifié sur données ORAS) :
        //   +0  modelsPointerOffset, +4 modelsCount
        //   +36 (0x24) texturesPointerOffset   ← PAS +60 comme dans Ohana3DS docs
        //   +40 (0x28) texturesCount
        //   Les textures sont souvent dans un BCH séparé (conteneur PT),
        //   pas dans le BCH géométrie (conteneur PC).
        let texPtrTableOff = Int(ru32(b, Int(mainHdrOff) + 36))
        let texCount       = Int(ru32(b, Int(mainHdrOff) + 40))
        print("[BCH TEX] texPtrTableOff=0x\(String(texPtrTableOff, radix:16)) texCount=\(texCount)")

        // Tableau indexé par position dans la liste (0..texCount-1)
        var textures: [CGImage?] = Array(repeating: nil, count: max(texCount, 1))
        // Mapping absOffset du struct textures → index dans textures[]
        var texByPtr: [Int: Int] = [:]

        if texPtrTableOff > 0 && texCount > 0 && texPtrTableOff + texCount * 4 <= b.count {
            for ti in 0..<texCount {
                let texStructOff = Int(ru32(b, texPtrTableOff + ti * 4))
                guard texStructOff > 0, texStructOff + 0x24 <= b.count else { continue }

                let dataAbsOff = Int(ru32(b, texStructOff + 0x00))
                let mipCount   = Int(ru32(b, texStructOff + 0x04))
                // +0x0C : encodage PICA200 (12=ETC1, 13=ETC1A4, 2=RGB565…)
                let fmtWord    = Int(ru32(b, texStructOff + 0x0C))
                let dataSize   = Int(ru32(b, texStructOff + 0x10))
                let height     = Int(ru16(b, texStructOff + 0x18))
                let width      = Int(ru16(b, texStructOff + 0x1A))
                let nameAbsOff = Int(ru32(b, texStructOff + 0x20))

                let name = readCString(b, at: nameAbsOff)
                print("[BCH TEX \(ti)] struct=0x\(String(texStructOff,radix:16))"
                    + " dataOff=0x\(String(dataAbsOff,radix:16))"
                    + " fmt=\(fmtWord) sz=\(dataSize) \(width)×\(height) mips=\(mipCount) name='\(name)'")

                texByPtr[texStructOff] = ti

                guard width > 0, height > 0, dataAbsOff > 0,
                      dataAbsOff < b.count else { continue }

                let pixelData = Data(b[dataAbsOff..<min(dataAbsOff + max(dataSize, width*height), b.count)])

                // Détecter ETC1 (0xC=12) ou ETC1A4 (0xD=13)
                // Si fmtWord == 0 essayer de deviner depuis la taille
                let fmt = fmtWord & 0xFF
                let isETC1A4 = (fmt == 13) || (dataSize > 0 && dataSize == width * height)
                let isETC1   = (fmt == 12) || (dataSize > 0 && dataSize == width * height / 2)

                if isETC1 || isETC1A4 || fmt == 0 {
                    let hasAlpha = isETC1A4 && !isETC1
                    textures[ti] = ETC1Decoder.decode(data: pixelData,
                                                       width: width, height: height,
                                                       hasAlpha: hasAlpha)
                    if textures[ti] != nil {
                        print("[BCH TEX \(ti)] décodé ETC1\(hasAlpha ? "A4" : "") \(width)×\(height) ✓")
                    }
                } else {
                    print("[BCH TEX \(ti)] format non-ETC1 (\(fmt)) — ignoré pour l'instant")
                }
            }
        }

        // ── Parsing des modèles (identique à parse()) avec assignation texture ──
        let modPtrOff = Int(ru32(b, Int(mainHdrOff)))
        let modCount  = Int(ru32(b, Int(mainHdrOff) + 4))
        print("[BCH] size=\(b.count) isTM=\(isTM) modPtrOff=0x\(String(modPtrOff,radix:16)) modCount=\(modCount) [withTextures]")

        // Trouver la table de matériaux du premier modèle pour mapper matIdx→texture
        var matTexMap: [UInt16: CGImage?] = [:]
        if modCount > 0 {
            let modelOff  = Int(ru32(b, modPtrOff))
            let matTblOff = Int(ru32(b, modelOff + 52))
            let matTblCnt = Int(ru32(b, modelOff + 56))
            print("[BCH MAT] matTblOff=0x\(String(matTblOff,radix:16)) matTblCnt=\(matTblCnt)")

            for mi in 0..<matTblCnt {
                guard matTblOff > 0, matTblOff + (mi+1)*4 <= b.count else { break }
                let matStructOff = Int(ru32(b, matTblOff + mi * 4))
                guard matStructOff > 0, matStructOff + 0x30 <= b.count else { continue }

                // Tentative de trouver le pointeur vers la texture dans le struct matériau.
                // On cherche un pointeur qui correspond à un struct texture connu (texByPtr).
                var foundTex: CGImage? = nil
                // Scan des premiers u32 du struct matériau pour trouver un ptr vers une texture
                for fieldOff in stride(from: 0, to: min(0x80, b.count - matStructOff), by: 4) {
                    let ptr = Int(ru32(b, matStructOff + fieldOff))
                    if let texIdx = texByPtr[ptr], texIdx < textures.count {
                        foundTex = textures[texIdx]
                        print("[BCH MAT \(mi)] trouvé texture idx=\(texIdx) à champ +0x\(String(fieldOff,radix:16))")
                        break
                    }
                }
                // Fallback : matIdx → texIdx par modulo
                if foundTex == nil && !textures.isEmpty {
                    foundTex = textures[mi % textures.count]
                }
                matTexMap[UInt16(mi)] = foundTex
            }
        }

        var result: [MeshData] = []
        for mi in 0..<modCount {
            let modelOff = Int(ru32(b, modPtrOff + mi * 4))
            var meshes = parseModel(b, at: modelOff, bc: bc)
            // Assigner texture via matTexMap
            for i in 0..<meshes.count {
                let matIdx = meshes[i].materialIndex
                if let texOpt = matTexMap[matIdx] {
                    meshes[i].texture = texOpt
                } else if !textures.isEmpty {
                    meshes[i].texture = textures[Int(matIdx) % textures.count]
                }
            }
            result.append(contentsOf: meshes)
        }
        return result
    }

    // MARK: — Matériaux (noms de textures par matériau)

    struct MaterialInfo {
        var name:     String   // nom du matériau (ex. "chip_kusa")
        var texture0: String   // texture principale (ex. "c108_old_kusa")
        var texture1: String   // texture secondaire de blend ("" si absente)
    }

    /// Extrait la table des matériaux d'un BCH géométrie (bc ≥ 0x21).
    /// Entrées de 0x2C octets à materialsTableOffset (modelOff+52) :
    ///   +0x1C = ptr nom texture0, +0x20 = ptr nom texture1, +0x28 = ptr nom matériau
    /// (pointeurs absolus après relocation flag 1 → table de chaînes).
    /// L'index = mesh.materialIndex.
    static func parseMaterials(fileData: Data) -> [MaterialInfo] {
        var b = [UInt8](fileData)
        guard b.count > 0x44, b[0] == 0x42, b[1] == 0x43, b[2] == 0x48 else { return [] }

        let bc         = b[4]
        let mainHdrOff = ru32(b, 8)
        let strTblOff  = ru32(b, 12)
        let gpuCmdOff  = ru32(b, 16)
        let dataOff    = ru32(b, 20)
        var p = 24
        var dataExtOff: UInt32 = 0
        if bc > 0x20 { dataExtOff = ru32(b, p); p += 4 }
        let relTblOff = ru32(b, p); p += 4
        p += 16
        if bc > 0x20 { p += 4 }
        let relTblLen = ru32(b, p)

        applyRelocation(&b, relTblOff: relTblOff, relTblLen: relTblLen, bc: bc,
                        mainHdrOff: mainHdrOff, strTblOff: strTblOff,
                        gpuCmdOff: gpuCmdOff, dataOff: dataOff, dataExtOff: dataExtOff)

        let modPtrOff = Int(ru32(b, Int(mainHdrOff)))
        let modCount  = Int(ru32(b, Int(mainHdrOff) + 4))
        guard modCount > 0 else { return [] }
        let modelOff  = Int(ru32(b, modPtrOff))
        guard modelOff + 60 <= b.count else { return [] }

        let matTblOff = Int(ru32(b, modelOff + 52))
        let matCnt    = Int(ru32(b, modelOff + 56))
        guard matTblOff > 0, matCnt > 0, matCnt < 512,
              matTblOff + matCnt * 0x2C <= b.count else { return [] }

        var result: [MaterialInfo] = []
        for mi in 0..<matCnt {
            let base = matTblOff + mi * 0x2C
            result.append(MaterialInfo(
                name:     readCString(b, at: Int(ru32(b, base + 0x28))),
                texture0: readCString(b, at: Int(ru32(b, base + 0x1C))),
                texture1: readCString(b, at: Int(ru32(b, base + 0x20)))))
        }
        return result
    }

    // MARK: — Textures externes (BCH des fichiers AD de a/0/1/4)

    struct TextureInfo {
        var name:     String
        var image:    CGImage
        var width:    Int
        var height:   Int
        var isOpaque: Bool
        var byteSize: Int
    }

    /// Décode toutes les textures d'un BCH « texture » séparé (ex. a/0/3/2[grIdx]).
    /// Les dimensions/format de chaque texture sont lus depuis son buffer de commandes
    /// GPU (registres 0x082 taille, 0x08E format) ; les données pixel sont rangées
    /// séquentiellement à partir de la section data.
    static func parseTextureBCH(fileData: Data) -> [TextureInfo] {
        var b = [UInt8](fileData)
        guard b.count > 0x44, b[0] == 0x42, b[1] == 0x43, b[2] == 0x48 else { return [] }

        let bc         = b[4]
        let mainHdrOff = ru32(b, 8)
        let strTblOff  = ru32(b, 12)
        let gpuCmdOff  = ru32(b, 16)
        let dataOff    = ru32(b, 20)

        var p = 24
        var dataExtOff: UInt32 = 0
        if bc > 0x20 { dataExtOff = ru32(b, p); p += 4 }
        let relTblOff = ru32(b, p); p += 4
        p += 16
        if bc > 0x20 { p += 4 }
        let relTblLen = ru32(b, p)

        applyRelocation(&b, relTblOff: relTblOff, relTblLen: relTblLen, bc: bc,
                        mainHdrOff: mainHdrOff, strTblOff: strTblOff,
                        gpuCmdOff: gpuCmdOff, dataOff: dataOff, dataExtOff: dataExtOff)

        let texPtrTableOff = Int(ru32(b, Int(mainHdrOff) + 36))
        let texCount       = Int(ru32(b, Int(mainHdrOff) + 40))
        guard texPtrTableOff > 0, texCount > 0, texCount < 512,
              texPtrTableOff + texCount * 4 <= b.count else { return [] }

        // Dictionnaire des noms de textures (mainHdr+44) : nœud de 0xC octets
        // (refBit u32, left u16, right u16, nameOff u32 absolu). Nœud 0 = racine ;
        // entrées = nœuds 1..texCount, dans l'ordre de la table des pointeurs.
        let texNameDictOff = Int(ru32(b, Int(mainHdrOff) + 44))
        var texNames = [String](repeating: "", count: texCount)
        if texNameDictOff > 0, texNameDictOff + (texCount + 1) * 0xC <= b.count {
            for i in 0..<texCount {
                let node = texNameDictOff + (i + 1) * 0xC
                texNames[i] = readCString(b, at: Int(ru32(b, node + 8)))
            }
        }

        var result: [TextureInfo] = []
        var cursor = Int(dataOff)

        for ti in 0..<texCount {
            let sOff = Int(ru32(b, texPtrTableOff + ti * 4))
            guard sOff > 0, sOff + 8 <= b.count else { break }

            // Le struct texture = suite de paires (offsetCommandes, nbMots) relatives à
            // gpuCmdOff. On lit les paramètres bruts des registres (0x082 taille, 0x08E format)
            // sans passer par le masquage PICA — les buffers texture font des écritures pleines.
            // Les offsets de buffer sont déjà absolus après la relocation (flag 2 → +gpuCmdOff).
            var cmds = [UInt32: UInt32]()
            var pi = 0
            while pi < 6, sOff + pi * 8 + 8 <= b.count {
                let cbAbs = Int(ru32(b, sOff + pi * 8))
                let wc    = Int(ru32(b, sOff + pi * 8 + 4))
                if wc == 0 || wc > 0x100 { break }
                readRawPICARegisters(b, at: cbAbs, wordCount: wc, into: &cmds)
                pi += 1
            }

            let size = cmds[0x082] ?? 0
            let w = Int(size & 0xFFFF)
            let h = Int((size >> 16) & 0xFFFF)
            let fmtRaw = Int((cmds[0x08E] ?? 0) & 0xF)
            // Taille indéterminable → on ne peut plus suivre le layout séquentiel : stop.
            guard w > 0, h > 0,
                  let fmt = PICATextureDecoder.Format(rawValue: fmtRaw) else { break }

            let nbytes = PICATextureDecoder.byteSize(format: fmt, width: w, height: h)
            guard cursor + nbytes <= b.count else { break }
            let chunk = Data(b[cursor..<cursor + nbytes])
            cursor += nbytes

            let opaque: Bool
            switch fmt {
            case .etc1, .rgb565, .rgb8, .l8, .hilo8: opaque = true
            default: opaque = false
            }

            if let img = PICATextureDecoder.decode(data: chunk, width: w, height: h, format: fmt) {
                result.append(TextureInfo(name: texNames[ti], image: img, width: w, height: h,
                                          isOpaque: opaque, byteSize: nbytes))
            }
        }
        return result
    }

    /// Lit les derniers paramètres bruts écrits sur chaque registre PICA d'un buffer
    /// de commandes (param, header). Gère l'écriture en rafale (extra + consecutive).
    private static func readRawPICARegisters(_ b: [UInt8], at startOff: Int,
                                             wordCount: Int, into regs: inout [UInt32: UInt32]) {
        var pos = startOff
        let end = startOff + wordCount * 4
        while pos + 8 <= end && pos + 8 <= b.count {
            let parameter = ru32(b, pos)
            let header    = ru32(b, pos + 4)
            pos += 8
            let id     = header & 0xFFFF
            let extra  = Int((header >> 20) & 0x7FF)
            let consec = (header >> 31) != 0
            regs[id] = parameter

            var curId = id
            for _ in 0..<extra {
                guard pos + 4 <= b.count else { break }
                if consec { curId &+= 1 }
                regs[curId] = ru32(b, pos)
                pos += 4
            }
            // Alignement 8 octets entre paires de commandes
            if ((pos - startOff) & 7) != 0 { pos = (pos + 7) & ~7 }
        }
    }

    // MARK: — Conversion SceneKit

    static func toSCNNode(meshes: [MeshData], scale: Float = 1.0) -> SCNNode {
        let root = SCNNode()
        for mesh in meshes {
            guard !mesh.vertices.isEmpty else { continue }
            guard let geo = buildGeometry(mesh: mesh, scale: scale) else { continue }
            let mat = SCNMaterial()
            if let tex = mesh.texture {
                mat.diffuse.contents  = tex
                mat.diffuse.wrapS     = .repeat
                mat.diffuse.wrapT     = .repeat
                mat.specular.contents = NSColor(white: 0.08, alpha: 1)
                mat.shininess = 0.12
            } else {
                mat.diffuse.contents  = NSColor(red: 0.62, green: 0.54, blue: 0.44, alpha: 1)
                mat.specular.contents = NSColor(white: 0.15, alpha: 1)
                mat.shininess = 0.25
            }
            mat.isDoubleSided = true
            mat.lightingModel = .blinn
            geo.materials = [mat]
            root.addChildNode(SCNNode(geometry: geo))
        }
        return root
    }

    // Lit une chaîne C (null-terminated) depuis b[] à l'offset donné.
    private static func readCString(_ b: [UInt8], at offset: Int) -> String {
        guard offset > 0, offset < b.count else { return "" }
        var end = offset
        while end < b.count && b[end] != 0 { end += 1 }
        return String(bytes: b[offset..<end], encoding: .utf8) ?? ""
    }

    private static func buildGeometry(mesh: MeshData, scale: Float) -> SCNGeometry? {
        let vCount = mesh.vertices.count
        guard vCount > 0 else { return nil }

        var posBuf  = [Float](); posBuf.reserveCapacity(vCount * 3)
        var normBuf = [Float](); normBuf.reserveCapacity(vCount * 3)
        var uvBuf   = [Float](); uvBuf.reserveCapacity(vCount * 2)
        var colBuf  = [Float](); colBuf.reserveCapacity(vCount * 4)
        var hasColor = false

        for v in mesh.vertices {
            posBuf  += [v.position.x * scale, v.position.y * scale, v.position.z * scale]
            normBuf += [v.normal.x, v.normal.y, v.normal.z]
            uvBuf   += [v.uv.x, 1.0 - v.uv.y]   // flip V pour SceneKit
            colBuf  += [v.color.x, v.color.y, v.color.z, v.color.w]
            if v.color != SIMD4<Float>(1, 1, 1, 1) { hasColor = true }
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

        var sources = [posSrc, normSrc, uvSrc]
        // SceneKit module la diffuse par la source .color → applique l'AO/teinte bakée.
        if hasColor {
            let colData = Data(bytes: colBuf, count: colBuf.count * 4)
            sources.append(SCNGeometrySource(data: colData, semantic: .color,
                vectorCount: vCount, usesFloatComponents: true,
                componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: 16))
        }

        var idx32 = mesh.indices
        let idxData = Data(bytes: &idx32, count: idx32.count * 4)
        let element = SCNGeometryElement(data: idxData,
            primitiveType: .triangles,
            primitiveCount: idx32.count / 3,
            bytesPerIndex: 4)

        return SCNGeometry(sources: sources, elements: [element])
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
            // Block B : second command set (vertex buffer setup séparé dans certains BCH)
            let vshCmdOff2 = Int(ru32(b, base + 24))
            let vshCmdWC2  = Int(ru32(b, base + 28))

            var vshSet = parsePICACommands(b, at: vshCmdOff, wordCount: vshCmdWC)
            if vshCmdOff2 > 0 && vshCmdWC2 > 0 {
                let vshSet2 = parsePICACommands(b, at: vshCmdOff2, wordCount: vshCmdWC2)
                // Fusionner : Block B complète Block A (vertex buffer souvent dans Block B)
                for (k, v) in vshSet2.cmds where vshSet.cmds[k] == nil || vshSet.cmds[k] == 0 {
                    vshSet.cmds[k] = v
                }
                for (k, v) in vshSet2.floatUniforms where vshSet.floatUniforms[k] == nil {
                    vshSet.floatUniforms[k] = v
                }
            }

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
                case 3:   // vertex color (AO/teinte bakée) — u8 0-255 ou float 0-1
                    let s: Float = aType == 3 ? 1.0 : (1.0 / 255.0)
                    vd.color = SIMD4<Float>(cv[0] * s, cv[1] * s, cv[2] * s,
                                            nComp >= 4 ? cv[3] * s : 1.0)
                case 4:   // texCoord0
                    vd.uv = SIMD2<Float>(cv[0] * tex0Scale, cv[1] * tex0Scale)
                default:  break   // tangent, bone data ignorés pour le terrain
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
