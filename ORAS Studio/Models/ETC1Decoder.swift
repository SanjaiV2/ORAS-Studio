import Foundation
import CoreGraphics

// Décodeur ETC1 / ETC1A4 pour textures 3DS (PICA200 GPU).
// Les textures BCH sont stockées en ordre linéaire, convention OpenGL (rangée 0 = bas visuel).
// On produit un CGImage top-down (convention macOS/SceneKit) en inversant l'axe Y des blocs.
// Référence : Ohana3DS-Rebirth/TextureCodec.cs, Citra GPU::Texture::DecodeETC1.
struct ETC1Decoder {

    // Table des modifiers ETC1 — index codeword → [petite_modif, grande_modif]
    private static let modTable: [[Int]] = [
        [2, 8], [5, 17], [9, 29], [13, 42],
        [18, 60], [24, 80], [33, 106], [47, 183]
    ]

    // MARK: — Point d'entrée

    /// Décode un buffer ETC1 (ou ETC1A4) en RGBA8 CGImage.
    /// - width/height : doivent être des multiples de 4 (taille d'un bloc).
    /// - hasAlpha : true = ETC1A4 (16 bytes/bloc avec 8 bytes alpha), false = ETC1 (8 bytes/bloc).
    /// - Retourne nil si les données sont trop courtes ou les dimensions invalides.
    static func decode(data: Data, width: Int, height: Int, hasAlpha: Bool) -> CGImage? {
        guard width > 0, height > 0, width % 4 == 0, height % 4 == 0 else { return nil }

        let blocksX = width  / 4
        let blocksY = height / 4
        let bytesPerBlock = hasAlpha ? 16 : 8
        let required = blocksX * blocksY * bytesPerBlock
        guard data.count >= required else {
            print("[ETC1] données insuffisantes: \(data.count) < \(required) pour \(width)×\(height) hasAlpha=\(hasAlpha)")
            return nil
        }

        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        var offset = 0

        // La rangée de blocs 0 = bas visuel (OpenGL) → on la mappe en haut de l'image CGImage
        // en utilisant imgBlockRow = blocksY - 1 - blockRow
        for blockRow in 0..<blocksY {
            let imgBlockRow = blocksY - 1 - blockRow      // inversion Y
            for blockCol in 0..<blocksX {
                var alphaData: UInt64 = 0
                if hasAlpha {
                    alphaData = readBE64(data, offset)
                    offset += 8
                }
                let high = readBE32(data, offset)
                let low  = readBE32(data, offset + 4)
                offset += 8

                decodeBlock(high: high, low: low,
                            alphaData: alphaData, hasAlpha: hasAlpha,
                            into: &rgba,
                            imgBlockRow: imgBlockRow, blockCol: blockCol,
                            imgWidth: width)
            }
        }

        return makeImage(rgba: rgba, width: width, height: height, premultiplied: hasAlpha)
    }

    // MARK: — Décodage d'un bloc 4×4

    private static func decodeBlock(high: UInt32, low: UInt32,
                                    alphaData: UInt64, hasAlpha: Bool,
                                    into rgba: inout [UInt8],
                                    imgBlockRow: Int, blockCol: Int, imgWidth: Int) {
        let flip = (high >> 24) & 1 != 0
        let diff = (high >> 25) & 1 != 0

        // Deux couleurs de base du bloc
        var r0, g0, b0, r1, g1, b1: Int

        if diff {
            // Mode différentiel : couleur 0 = 5 bits, couleur 1 = couleur 0 + delta signé 3 bits
            let rb = Int((high >> 27) & 0x1F)
            let gb = Int((high >> 19) & 0x1F)
            let bb = Int((high >> 11) & 0x1F)
            r0 = (rb << 3) | (rb >> 2)     // expansion 5→8 bits
            g0 = (gb << 3) | (gb >> 2)
            b0 = (bb << 3) | (bb >> 2)
            let r1b = clamp(rb + signExt3((high >> 24) & 0x7), 0, 31)
            let g1b = clamp(gb + signExt3((high >> 16) & 0x7), 0, 31)
            let b1b = clamp(bb + signExt3((high >> 8)  & 0x7), 0, 31)
            r1 = (r1b << 3) | (r1b >> 2)
            g1 = (g1b << 3) | (g1b >> 2)
            b1 = (b1b << 3) | (b1b >> 2)
        } else {
            // Mode individuel : deux couleurs 4 bits indépendantes, répliquées en 8 bits
            let r0n = Int((high >> 28) & 0xF); r0 = r0n | (r0n << 4)
            let g0n = Int((high >> 20) & 0xF); g0 = g0n | (g0n << 4)
            let b0n = Int((high >> 12) & 0xF); b0 = b0n | (b0n << 4)
            let r1n = Int((high >> 24) & 0xF); r1 = r1n | (r1n << 4)
            let g1n = Int((high >> 16) & 0xF); g1 = g1n | (g1n << 4)
            let b1n = Int((high >> 8)  & 0xF); b1 = b1n | (b1n << 4)
        }

        // Table des modificateurs (codeword pour chaque sous-bloc)
        let cw0 = Int((high >> 5) & 0x7)
        let cw1 = Int((high >> 2) & 0x7)

        // 16 pixels en ordre colonne-majeur : bit index = col*4 + row
        for pixCol in 0..<4 {
            for pixRow in 0..<4 {
                let pixBit = pixCol * 4 + pixRow
                let msb = Int((low >> (16 + pixBit)) & 1)
                let lsb = Int((low >> pixBit) & 1)
                let sel = (msb << 1) | lsb

                // flip=0 : sous-bloc 0 = colonnes 0-1, sous-bloc 1 = colonnes 2-3
                // flip=1 : sous-bloc 0 = rangées 0-1, sous-bloc 1 = rangées 2-3
                let inBlock1 = flip ? (pixRow >= 2) : (pixCol >= 2)
                let baseR = inBlock1 ? r1 : r0
                let baseG = inBlock1 ? g1 : g0
                let baseB = inBlock1 ? b1 : b0
                let cw    = inBlock1 ? cw1 : cw0
                let mod   = modTable[cw]

                let delta: Int
                switch sel {
                case 0: delta = -mod[1]    // négatif grand
                case 1: delta = -mod[0]    // négatif petit
                case 2: delta =  mod[0]    // positif petit
                default: delta = mod[1]    // positif grand
                }

                let r = UInt8(clamp(baseR + delta, 0, 255))
                let g = UInt8(clamp(baseG + delta, 0, 255))
                let b = UInt8(clamp(baseB + delta, 0, 255))

                let a: UInt8
                if hasAlpha {
                    // ETC1A4 : 4 bits par pixel en ordre bit-séquentiel, Big-Endian
                    let bits = Int((alphaData >> (pixBit * 4)) & 0xF)
                    a = UInt8(bits | (bits << 4))   // expansion 4→8 bits
                } else {
                    a = 255
                }

                let dstX = blockCol * 4 + pixCol
                let dstY = imgBlockRow * 4 + pixRow
                let idx  = (dstY * imgWidth + dstX) * 4
                guard idx + 3 < rgba.count else { continue }
                rgba[idx]   = r
                rgba[idx+1] = g
                rgba[idx+2] = b
                rgba[idx+3] = a
            }
        }
    }

    // MARK: — Helpers

    private static func readBE32(_ data: Data, _ off: Int) -> UInt32 {
        guard off + 4 <= data.count else { return 0 }
        return UInt32(data[off]) << 24 | UInt32(data[off+1]) << 16
             | UInt32(data[off+2]) << 8  | UInt32(data[off+3])
    }

    private static func readBE64(_ data: Data, _ off: Int) -> UInt64 {
        UInt64(readBE32(data, off)) << 32 | UInt64(readBE32(data, off + 4))
    }

    private static func signExt3(_ v: UInt32) -> Int {
        let i = Int(v & 7); return i >= 4 ? i - 8 : i
    }

    private static func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int {
        max(lo, min(hi, v))
    }

    private static func makeImage(rgba: [UInt8], width: Int, height: Int,
                                  premultiplied: Bool) -> CGImage? {
        let cs   = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: premultiplied
            ? CGImageAlphaInfo.premultipliedLast.rawValue
            : CGImageAlphaInfo.noneSkipLast.rawValue)
        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(width: width, height: height,
                       bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4,
                       space: cs, bitmapInfo: info,
                       provider: provider, decode: nil,
                       shouldInterpolate: true, intent: .defaultIntent)
    }
}
