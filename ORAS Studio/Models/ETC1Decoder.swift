import Foundation
import CoreGraphics

// Décodeur ETC1 / ETC1A4 pour textures 3DS (PICA200 GPU).
//
// Format vérifié sur les données ORAS (a/0/3/2) :
//   • Chaque bloc couleur ETC1 = 8 octets lus en little-endian 64 bits.
//   • flip = bit32, diff = bit33, codewords = bits 34-39, indices pixels = bits 0-31.
//   • Les blocs 4×4 sont rangés en tuiles 8×8 (4 blocs par tuile) en ordre morton :
//     (0,0), (1,0), (0,1), (1,1).
//   • ETC1A4 : 8 octets alpha (4 bits/pixel, little-endian) AVANT les 8 octets couleur.
// Référence : Citra GPU::Texture::DecodeETC1, SPICA ETC1.cs.
struct ETC1Decoder {

    // Table des modifiers ETC1 — index codeword → [petite_modif, grande_modif]
    private static let modTable: [[Int]] = [
        [2, 8], [5, 17], [9, 29], [13, 42],
        [18, 60], [24, 80], [33, 106], [47, 183]
    ]

    /// Décode un buffer ETC1 (ou ETC1A4) en RGBA8 CGImage.
    /// - width/height : multiples de 4 (arrondis à la tuile 8×8 en interne).
    /// - hasAlpha : true = ETC1A4 (16 octets/bloc), false = ETC1 (8 octets/bloc).
    static func decode(data: Data, width: Int, height: Int, hasAlpha: Bool) -> CGImage? {
        guard width > 0, height > 0 else { return nil }

        let bytes = [UInt8](data)
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        var offset = 0

        // Parcours par tuiles 8×8, 4 sous-blocs 4×4 en ordre morton
        let tilesX = (width  + 7) / 8
        let tilesY = (height + 7) / 8
        for ty in 0..<tilesY {
            for tx in 0..<tilesX {
                for t in 0..<4 {
                    let bx = (t & 1) * 4          // colonne du sous-bloc dans la tuile
                    let by = (t >> 1) * 4          // rangée du sous-bloc

                    var alpha64: UInt64 = 0xFFFFFFFFFFFFFFFF
                    if hasAlpha {
                        alpha64 = readLE64(bytes, offset)
                        offset += 8
                    }
                    let block = readLE64(bytes, offset)
                    offset += 8

                    decodeBlock(block: block, alpha64: alpha64, hasAlpha: hasAlpha,
                                into: &rgba,
                                originX: tx * 8 + bx, originY: ty * 8 + by,
                                imgWidth: width, imgHeight: height)
                }
            }
        }

        return makeImage(rgba: rgba, width: width, height: height, premultiplied: hasAlpha)
    }

    // MARK: — Décodage d'un bloc 4×4

    private static func decodeBlock(block: UInt64, alpha64: UInt64, hasAlpha: Bool,
                                    into rgba: inout [UInt8],
                                    originX: Int, originY: Int,
                                    imgWidth: Int, imgHeight: Int) {
        let flip = (block >> 32) & 1 != 0
        let diff = (block >> 33) & 1 != 0

        var r0, g0, b0, r1, g1, b1: Int
        if diff {
            let rb = Int((block >> 59) & 0x1F)
            let gb = Int((block >> 51) & 0x1F)
            let bb = Int((block >> 43) & 0x1F)
            r0 = (rb << 3) | (rb >> 2)
            g0 = (gb << 3) | (gb >> 2)
            b0 = (bb << 3) | (bb >> 2)
            let r1b = clamp(rb + signExt3(UInt32((block >> 56) & 7)), 0, 31)
            let g1b = clamp(gb + signExt3(UInt32((block >> 48) & 7)), 0, 31)
            let b1b = clamp(bb + signExt3(UInt32((block >> 40) & 7)), 0, 31)
            r1 = (r1b << 3) | (r1b >> 2)
            g1 = (g1b << 3) | (g1b >> 2)
            b1 = (b1b << 3) | (b1b >> 2)
        } else {
            let r0n = Int((block >> 60) & 0xF); r0 = r0n | (r0n << 4)
            let g0n = Int((block >> 52) & 0xF); g0 = g0n | (g0n << 4)
            let b0n = Int((block >> 44) & 0xF); b0 = b0n | (b0n << 4)
            let r1n = Int((block >> 56) & 0xF); r1 = r1n | (r1n << 4)
            let g1n = Int((block >> 48) & 0xF); g1 = g1n | (g1n << 4)
            let b1n = Int((block >> 40) & 0xF); b1 = b1n | (b1n << 4)
        }

        let cw0 = Int((block >> 37) & 0x7)
        let cw1 = Int((block >> 34) & 0x7)

        for pixCol in 0..<4 {
            for pixRow in 0..<4 {
                let pixBit = pixCol * 4 + pixRow
                let lsb = Int((block >> pixBit) & 1)
                let msb = Int((block >> (pixBit + 16)) & 1)
                let sel = (msb << 1) | lsb

                let inBlock1 = flip ? (pixRow >= 2) : (pixCol >= 2)
                let baseR = inBlock1 ? r1 : r0
                let baseG = inBlock1 ? g1 : g0
                let baseB = inBlock1 ? b1 : b0
                let cw    = inBlock1 ? cw1 : cw0
                let mod   = modTable[cw]

                let delta: Int
                switch sel {
                case 0:  delta = -mod[1]
                case 1:  delta = -mod[0]
                case 2:  delta =  mod[0]
                default: delta =  mod[1]
                }

                let r = UInt8(clamp(baseR + delta, 0, 255))
                let g = UInt8(clamp(baseG + delta, 0, 255))
                let b = UInt8(clamp(baseB + delta, 0, 255))
                let a: UInt8
                if hasAlpha {
                    let av = Int((alpha64 >> (pixBit * 4)) & 0xF)
                    a = UInt8(av | (av << 4))
                } else {
                    a = 255
                }

                let dstX = originX + pixCol
                let dstY = originY + pixRow
                guard dstX < imgWidth, dstY < imgHeight else { continue }
                let idx = (dstY * imgWidth + dstX) * 4
                rgba[idx]   = r
                rgba[idx+1] = g
                rgba[idx+2] = b
                rgba[idx+3] = a
            }
        }
    }

    // MARK: — Helpers

    private static func readLE64(_ b: [UInt8], _ off: Int) -> UInt64 {
        guard off + 8 <= b.count else {
            var v: UInt64 = 0
            for i in 0..<8 where off + i < b.count { v |= UInt64(b[off + i]) << (8 * i) }
            return v
        }
        return UInt64(b[off])
            | UInt64(b[off+1]) << 8  | UInt64(b[off+2]) << 16 | UInt64(b[off+3]) << 24
            | UInt64(b[off+4]) << 32 | UInt64(b[off+5]) << 40 | UInt64(b[off+6]) << 48
            | UInt64(b[off+7]) << 56
    }

    private static func signExt3(_ v: UInt32) -> Int {
        let i = Int(v & 7); return i >= 4 ? i - 8 : i
    }

    private static func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int {
        max(lo, min(hi, v))
    }

    static func makeImage(rgba: [UInt8], width: Int, height: Int,
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
