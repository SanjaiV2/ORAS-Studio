import Foundation

// MARK: — Décodeur / Encodeur de caméra BCAM (Binary CAMera Animation)
// Format des caméras de survol de map ORAS/XY (Nintendo 3DS propriétaire).
//
// Layout binaire (little-endian) :
//   +0x00  magic      u32  = 0x4D414342 ("BCAM")
//   +0x04  version    u16  = 1
//   +0x06  kfCount    u16  (nombre de keyframes)
//   +0x08  flags      u32  (réservé)
//   +0x0C  loopStart  u32  (frame de début de boucle, 0 = pas de boucle)
//   [Per keyframe — 40 bytes each, starting at 0x10]
//   +0x00  frame      u32  (indice de frame à 30 fps)
//   +0x04  posX       f32  (coordonnée X monde, unités 3DS)
//   +0x08  posY       f32  (coordonnée Y monde = hauteur)
//   +0x0C  posZ       f32  (coordonnée Z monde)
//   +0x10  pitch      f32  (inclinaison en degrés, -90..+90)
//   +0x14  yaw        f32  (rotation horizontale en degrés, 0..360)
//   +0x18  roll       f32  (rotation longitudinale en degrés, -180..+180)
//   +0x1C  fov        f32  (champ de vision en degrés, 10..120)
//   +0x20  nearClip   f32  (plan de coupe proche, typiquement 0.1)
//   +0x24  farClip    f32  (plan de coupe lointain, typiquement 1000)

struct BCamFile {
    static let magic: UInt32    = 0x4D414342   // "BCAM"
    static let version: UInt16  = 1
    static let headerSize       = 16
    static let keyframeStride   = 40

    var name: String
    var loopStart: UInt32       // 0 = pas de boucle
    var keyframes: [Keyframe]

    // MARK: — Keyframe

    struct Keyframe: Identifiable, Equatable {
        let id: UUID

        /// Indice de frame à 30 fps (ex. 30 = 1 seconde)
        var frame: Int

        // Position de la caméra dans l'espace monde (unités 3DS ≈ décimètres)
        var posX: Float
        var posY: Float
        var posZ: Float

        // Orientation d'Euler (degrés)
        var pitch: Float    // inclinaison verticale
        var yaw:   Float    // rotation horizontale
        var roll:  Float    // rotation longitudinale

        var fov:      Float  // champ de vision (degrés)
        var nearClip: Float  // plan proche
        var farClip:  Float  // plan lointain

        var timeSeconds: Double { Double(frame) / 30.0 }
        var timeLabel: String { String(format: "%.2fs  (f%d)", timeSeconds, frame) }

        init(frame: Int = 0,
             posX: Float = 0, posY: Float = 100, posZ: Float = 0,
             pitch: Float = -45, yaw: Float = 0, roll: Float = 0,
             fov: Float = 60, nearClip: Float = 0.1, farClip: Float = 1000) {
            self.id       = UUID()
            self.frame    = frame
            self.posX     = posX;   self.posY  = posY;  self.posZ  = posZ
            self.pitch    = pitch;  self.yaw   = yaw;   self.roll  = roll
            self.fov      = fov
            self.nearClip = nearClip
            self.farClip  = farClip
        }
    }

    var totalFrames: Int { keyframes.map(\.frame).max() ?? 0 }
    var durationSeconds: Double { Double(totalFrames) / 30.0 }

    // MARK: — Parse

    static func parse(data: Data, name: String) throws -> BCamFile {
        guard data.count >= headerSize else { throw Error.dataTooShort }
        func u16(_ o: Int) -> UInt16 { data.withUnsafeBytes { $0.load(fromByteOffset: o, as: UInt16.self) } }
        func u32(_ o: Int) -> UInt32 { data.withUnsafeBytes { $0.load(fromByteOffset: o, as: UInt32.self) } }
        func f32(_ o: Int) -> Float  { data.withUnsafeBytes { $0.load(fromByteOffset: o, as: Float.self) } }

        let magic = u32(0)
        guard magic == BCamFile.magic else { throw Error.invalidMagic(magic) }
        let ver = u16(4)
        guard ver >= 1 && ver <= 2 else { throw Error.unsupportedVersion(ver) }

        let kfCount   = Int(u16(6))
        let loopStart = u32(12)
        guard data.count >= headerSize + kfCount * keyframeStride else { throw Error.dataTooShort }

        var keyframes: [Keyframe] = []
        for i in 0..<kfCount {
            let b = headerSize + i * keyframeStride
            keyframes.append(Keyframe(
                frame:    Int(u32(b)),
                posX:     f32(b +  4), posY:  f32(b + 8), posZ: f32(b + 12),
                pitch:    f32(b + 16), yaw:   f32(b + 20), roll: f32(b + 24),
                fov:      f32(b + 28),
                nearClip: f32(b + 32), farClip: f32(b + 36)
            ))
        }
        return BCamFile(name: name, loopStart: loopStart, keyframes: keyframes)
    }

    // MARK: — Encode

    func encode() -> Data {
        let size = BCamFile.headerSize + keyframes.count * BCamFile.keyframeStride
        var out = Data(count: size)
        out.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: BCamFile.magic,          toByteOffset: 0,  as: UInt32.self)
            ptr.storeBytes(of: BCamFile.version,        toByteOffset: 4,  as: UInt16.self)
            ptr.storeBytes(of: UInt16(keyframes.count), toByteOffset: 6,  as: UInt16.self)
            ptr.storeBytes(of: UInt32(0),               toByteOffset: 8,  as: UInt32.self)
            ptr.storeBytes(of: loopStart,               toByteOffset: 12, as: UInt32.self)
            for (i, kf) in keyframes.enumerated() {
                let b = BCamFile.headerSize + i * BCamFile.keyframeStride
                ptr.storeBytes(of: UInt32(kf.frame), toByteOffset: b,      as: UInt32.self)
                ptr.storeBytes(of: kf.posX,          toByteOffset: b +  4, as: Float.self)
                ptr.storeBytes(of: kf.posY,          toByteOffset: b +  8, as: Float.self)
                ptr.storeBytes(of: kf.posZ,          toByteOffset: b + 12, as: Float.self)
                ptr.storeBytes(of: kf.pitch,         toByteOffset: b + 16, as: Float.self)
                ptr.storeBytes(of: kf.yaw,           toByteOffset: b + 20, as: Float.self)
                ptr.storeBytes(of: kf.roll,          toByteOffset: b + 24, as: Float.self)
                ptr.storeBytes(of: kf.fov,           toByteOffset: b + 28, as: Float.self)
                ptr.storeBytes(of: kf.nearClip,      toByteOffset: b + 32, as: Float.self)
                ptr.storeBytes(of: kf.farClip,       toByteOffset: b + 36, as: Float.self)
            }
        }
        return out
    }

    // MARK: — Interpolation linéaire entre deux keyframes

    func interpolated(atFrame targetFrame: Int) -> Keyframe? {
        guard !keyframes.isEmpty else { return nil }
        if keyframes.count == 1 { return keyframes[0] }
        let sorted = keyframes.sorted { $0.frame < $1.frame }
        guard targetFrame >= sorted.first!.frame else { return sorted.first }
        guard targetFrame <= sorted.last!.frame  else { return sorted.last }
        for i in 0..<sorted.count - 1 {
            let a = sorted[i]; let b = sorted[i + 1]
            if targetFrame >= a.frame && targetFrame <= b.frame {
                let span = Float(b.frame - a.frame)
                guard span > 0 else { return a }
                let t = Float(targetFrame - a.frame) / span
                return Keyframe(
                    frame:    targetFrame,
                    posX:     lerp(a.posX, b.posX, t),
                    posY:     lerp(a.posY, b.posY, t),
                    posZ:     lerp(a.posZ, b.posZ, t),
                    pitch:    lerp(a.pitch, b.pitch, t),
                    yaw:      lerpAngle(a.yaw, b.yaw, t),
                    roll:     lerp(a.roll, b.roll, t),
                    fov:      lerp(a.fov, b.fov, t),
                    nearClip: a.nearClip,
                    farClip:  a.farClip
                )
            }
        }
        return sorted.last
    }

    private func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }
    private func lerpAngle(_ a: Float, _ b: Float, _ t: Float) -> Float {
        var delta = b - a
        while delta >  180 { delta -= 360 }
        while delta < -180 { delta += 360 }
        return a + delta * t
    }

    // MARK: — Nouveau fichier par défaut

    static func newFile(name: String) -> BCamFile {
        BCamFile(name: name, loopStart: 0, keyframes: [
            Keyframe(frame: 0,  posX: 0, posY: 150, posZ: 0, pitch: -60, yaw: 45, fov: 55),
            Keyframe(frame: 60, posX: 0, posY: 80,  posZ: 0, pitch: -30, yaw: 0,  fov: 60)
        ])
    }

    // MARK: — Erreurs

    enum Error: LocalizedError {
        case dataTooShort
        case invalidMagic(UInt32)
        case unsupportedVersion(UInt16)

        var errorDescription: String? {
            switch self {
            case .dataTooShort:             "Fichier BCAM trop court"
            case .invalidMagic(let m):      "Magic invalide : 0x\(String(m, radix: 16, uppercase: true))"
            case .unsupportedVersion(let v):"Version BCAM non supportée : \(v)"
            }
        }
    }
}
