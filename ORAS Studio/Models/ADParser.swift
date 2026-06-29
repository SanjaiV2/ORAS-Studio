import Foundation

// Parses the "AD\x0c\0" zone terrain format stored in GARC a/0/1/4.
// Each entry is an LZ11-compressed package containing:
//   - Header (bytes 0..firstOffset): magic + table of u32 section offsets
//   - Metadata section (~256 bytes)
//   - One or more embedded BCH terrain meshes
//   - Float tables, camera data, and other auxiliary sections
struct ADParser {

    // Returns all BCH Data blobs embedded in the AD file, largest first.
    // The largest BCH is the main terrain; smaller ones are detail models.
    static func extractBCHSections(from data: Data) -> [Data] {
        guard data.count > 8,
              data[0] == 0x41, data[1] == 0x44  // "AD"
        else { return [] }

        // Collect section boundary offsets from the header (bytes 4, 8, 12, …)
        // The header extends until firstOffset; stop at 0 values or > fileSize.
        var offsets: [Int] = []
        var i = 4
        while i + 4 <= min(data.count, 256) {
            let off = Int(data.withUnsafeBytes {
                $0.loadUnaligned(fromByteOffset: i, as: UInt32.self)
            })
            if off == 0 { break }
            offsets.append(off)
            i += 4
        }
        guard offsets.count >= 2 else { return [] }

        // Enumerate consecutive pairs; pick those whose data starts with BCH magic.
        var bchSections: [Data] = []
        for j in 0 ..< offsets.count - 1 {
            let start = offsets[j]
            let end   = offsets[j + 1]
            guard start < end, end <= data.count, end - start > 8 else { continue }
            // BCH magic: "BCH\0"
            guard data[start]   == 0x42,
                  data[start+1] == 0x43,
                  data[start+2] == 0x48,
                  data[start+3] == 0x00
            else { continue }
            bchSections.append(data[start ..< end])
        }

        // Return largest first so callers can use bchSections[0] as main terrain.
        return bchSections.sorted { $0.count > $1.count }
    }
}
