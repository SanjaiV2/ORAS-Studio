import Foundation
import CoreGraphics

// Décodeur de textures PICA200 (format 3DS) pour tous les encodages rencontrés
// dans les BCH ORAS. Les formats compressés ETC1/ETC1A4 sont délégués à ETC1Decoder.
//
// Les formats non-compressés utilisent le "swizzle" morton du GPU PICA :
// l'image est découpée en tuiles 8×8 pixels, et à l'intérieur de chaque tuile
// les 64 pixels sont rangés en ordre morton (Z-order).
struct PICATextureDecoder {

    // Formats PICA (registre GPUREG_TEXUNIT0_FORMAT, 4 bits bas)
    enum Format: Int {
        case rgba8   = 0
        case rgb8    = 1
        case rgba5551 = 2
        case rgb565  = 3
        case rgba4   = 4
        case la8     = 5
        case hilo8   = 6
        case l8      = 7
        case a8      = 8
        case la4     = 9
        case l4      = 10
        case a4      = 11
        case etc1    = 12
        case etc1a4  = 13
    }

    /// Taille en octets d'une texture w×h dans un format donné.
    static func byteSize(format: Format, width: Int, height: Int) -> Int {
        let px = width * height
        switch format {
        case .rgba8:            return px * 4
        case .rgb8:             return px * 3
        case .rgba5551, .rgb565, .rgba4, .la8, .hilo8:
                                return px * 2
        case .l8, .a8, .la4:    return px
        case .l4, .a4, .etc1:   return px / 2
        case .etc1a4:           return px
        }
    }

    /// Décode un buffer en CGImage RGBA. Retourne nil si format inconnu / données courtes.
    static func decode(data: Data, width: Int, height: Int, format: Format) -> CGImage? {
        guard width > 0, height > 0 else { return nil }

        switch format {
        case .etc1:
            return ETC1Decoder.decode(data: data, width: width, height: height, hasAlpha: false)
        case .etc1a4:
            return ETC1Decoder.decode(data: data, width: width, height: height, hasAlpha: true)
        default:
            return decodeSwizzled(data: data, width: width, height: height, format: format)
        }
    }

    // MARK: — Formats non-compressés (swizzle morton 8×8)

    private static func decodeSwizzled(data: Data, width: Int, height: Int,
                                       format: Format) -> CGImage? {
        let bytes = [UInt8](data)
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        let bpp  = bytesPerPixel(format)          // peut être fractionnaire (L4/A4)

        let tilesX = (width + 7) / 8
        let tilesY = (height + 7) / 8

        var hasAlpha = false
        for ty in 0..<tilesY {
            for tx in 0..<tilesX {
                let tileIndex = ty * tilesX + tx
                // offset (en pixels) du début de la tuile dans le buffer linéaire
                let tilePixelBase = tileIndex * 64
                for m in 0..<64 {
                    let (dx, dy) = mortonDecode(m)
                    let px = tx * 8 + dx
                    let py = ty * 8 + dy
                    guard px < width, py < height else { continue }

                    let pixelIndex = tilePixelBase + m
                    let (r, g, b, a) = readPixel(bytes, pixelIndex: pixelIndex,
                                                 bpp: bpp, format: format)
                    if a != 255 { hasAlpha = true }
                    let idx = (py * width + px) * 4
                    rgba[idx]   = r
                    rgba[idx+1] = g
                    rgba[idx+2] = b
                    rgba[idx+3] = a
                }
            }
        }
        return ETC1Decoder.makeImage(rgba: rgba, width: width, height: height,
                                     premultiplied: hasAlpha)
    }

    private static func mortonDecode(_ i: Int) -> (Int, Int) {
        let x = (i & 0x1) | ((i >> 1) & 0x2) | ((i >> 2) & 0x4)
        let y = ((i >> 1) & 0x1) | ((i >> 2) & 0x2) | ((i >> 3) & 0x4)
        return (x, y)
    }

    private static func bytesPerPixel(_ f: Format) -> Double {
        switch f {
        case .rgba8: return 4
        case .rgb8:  return 3
        case .rgba5551, .rgb565, .rgba4, .la8, .hilo8: return 2
        case .l8, .a8, .la4: return 1
        case .l4, .a4: return 0.5
        default: return 1
        }
    }

    private static func readPixel(_ b: [UInt8], pixelIndex: Int, bpp: Double,
                                  format: Format) -> (UInt8, UInt8, UInt8, UInt8) {
        func b8(_ o: Int) -> Int { o < b.count ? Int(b[o]) : 0 }

        switch format {
        case .rgba8:
            let o = pixelIndex * 4
            return (UInt8(b8(o+3)), UInt8(b8(o+2)), UInt8(b8(o+1)), UInt8(b8(o)))
        case .rgb8:
            let o = pixelIndex * 3
            return (UInt8(b8(o+2)), UInt8(b8(o+1)), UInt8(b8(o)), 255)
        case .rgb565:
            let o = pixelIndex * 2
            let v = b8(o) | (b8(o+1) << 8)
            let r = ((v >> 11) & 0x1F) * 255 / 31
            let g = ((v >> 5)  & 0x3F) * 255 / 63
            let bl = (v & 0x1F) * 255 / 31
            return (UInt8(r), UInt8(g), UInt8(bl), 255)
        case .rgba5551:
            let o = pixelIndex * 2
            let v = b8(o) | (b8(o+1) << 8)
            let r = ((v >> 11) & 0x1F) * 255 / 31
            let g = ((v >> 6)  & 0x1F) * 255 / 31
            let bl = ((v >> 1) & 0x1F) * 255 / 31
            let a = (v & 1) * 255
            return (UInt8(r), UInt8(g), UInt8(bl), UInt8(a))
        case .rgba4:
            let o = pixelIndex * 2
            let v = b8(o) | (b8(o+1) << 8)
            let r = ((v >> 12) & 0xF) * 17
            let g = ((v >> 8)  & 0xF) * 17
            let bl = ((v >> 4) & 0xF) * 17
            let a = (v & 0xF) * 17
            return (UInt8(r), UInt8(g), UInt8(bl), UInt8(a))
        case .la8:
            let o = pixelIndex * 2
            let l = b8(o+1); let a = b8(o)
            return (UInt8(l), UInt8(l), UInt8(l), UInt8(a))
        case .hilo8:
            let o = pixelIndex * 2
            return (UInt8(b8(o+1)), UInt8(b8(o)), 0, 255)
        case .l8:
            let l = b8(pixelIndex)
            return (UInt8(l), UInt8(l), UInt8(l), 255)
        case .a8:
            let a = b8(pixelIndex)
            return (255, 255, 255, UInt8(a))
        case .la4:
            let v = b8(pixelIndex)
            let l = (v >> 4) * 17; let a = (v & 0xF) * 17
            return (UInt8(l), UInt8(l), UInt8(l), UInt8(a))
        case .l4:
            let byte = b8(pixelIndex / 2)
            let nib = (pixelIndex & 1) == 0 ? (byte & 0xF) : (byte >> 4)
            let l = nib * 17
            return (UInt8(l), UInt8(l), UInt8(l), 255)
        case .a4:
            let byte = b8(pixelIndex / 2)
            let nib = (pixelIndex & 1) == 0 ? (byte & 0xF) : (byte >> 4)
            let a = nib * 17
            return (255, 255, 255, UInt8(a))
        default:
            return (0, 0, 0, 255)
        }
    }
}
