import Foundation

// MARK: — GARC File Format
// Magic: "CRAG" (0x47415243 little-endian)
// Reference: Reference/garc_unpack.py

struct GARCFile {
    let entries: [GARCEntry]

    // MARK: — Parse

    init?(data: Data) {
        guard data.count >= 0x1C else { return nil }
        let magic = data.loadLE(UInt32.self, at: 0)
        guard magic == 0x47415243 else { return nil } // "CRAG"

        let headerSize  = data.loadLE(UInt16.self, at: 0x04)
        let entryCount  = data.loadLE(UInt32.self, at: 0x10)
        let dataOffset  = data.loadLE(UInt32.self, at: 0x14)

        guard headerSize >= 0x1C,
              Int(dataOffset) <= data.count else { return nil }

        // FATO table starts right after header
        let fatoOffset = Int(headerSize)
        guard fatoOffset + 8 <= data.count else { return nil }
        // Skip FATO magic/size, read FATB
        let fatbOffset = fatoOffset + 0x0C + Int(entryCount) * 4
        guard fatbOffset + 8 <= data.count else { return nil }

        var entries: [GARCEntry] = []
        var fatbPos = fatbOffset + 0x0C

        for _ in 0..<Int(entryCount) {
            guard fatbPos + 4 <= data.count else { break }
            let bits = data.loadLE(UInt32.self, at: fatbPos)
            fatbPos += 4
            var subEntries: [GARCSubEntry] = []
            for bit in 0..<32 {
                guard (bits >> bit) & 1 == 1 else { continue }
                guard fatbPos + 8 <= data.count else { break }
                let start = data.loadLE(UInt32.self, at: fatbPos)
                let end   = data.loadLE(UInt32.self, at: fatbPos + 4)
                fatbPos += 8
                let absStart = Int(dataOffset) + Int(start)
                let absEnd   = Int(dataOffset) + Int(end)
                guard absStart <= absEnd, absEnd <= data.count else { continue }
                subEntries.append(GARCSubEntry(data: data.subdata(in: absStart..<absEnd)))
            }
            entries.append(GARCEntry(subEntries: subEntries))
        }

        self.entries = entries
    }

    // MARK: — Convenience

    subscript(index: Int) -> GARCEntry? {
        guard entries.indices.contains(index) else { return nil }
        return entries[index]
    }

    func rawData(entry: Int, sub: Int = 0) -> Data? {
        guard let e = self[entry], e.subEntries.indices.contains(sub) else { return nil }
        return e.subEntries[sub].data
    }

    func decompressedData(entry: Int, sub: Int = 0) -> Data? {
        guard let raw = rawData(entry: entry, sub: sub) else { return nil }
        return LZ11.decompress(raw) ?? raw
    }
}

// MARK: — Entry types

struct GARCEntry {
    let subEntries: [GARCSubEntry]
}

struct GARCSubEntry {
    let data: Data
    var isLZ11Compressed: Bool { data.first == 0x11 }
}

// MARK: — LZ11 decompression stub

enum LZ11 {
    static func decompress(_ data: Data) -> Data? {
        guard data.count >= 4, data[0] == 0x11 else { return nil }
        let decompSize = Int(data[1]) | (Int(data[2]) << 8) | (Int(data[3]) << 16)
        guard decompSize > 0 else { return nil }

        var out = [UInt8]()
        out.reserveCapacity(decompSize)
        var i = 4

        while out.count < decompSize, i < data.count {
            let flags = data[i]; i += 1
            for bit in stride(from: 7, through: 0, by: -1) {
                guard out.count < decompSize, i < data.count else { break }
                if (flags >> bit) & 1 == 0 {
                    out.append(data[i]); i += 1
                } else {
                    guard i + 1 < data.count else { return nil }
                    let b0 = Int(data[i]); let b1 = Int(data[i+1]); i += 2
                    let indicator = b0 >> 4
                    var length: Int
                    var offset: Int
                    if indicator == 1 {
                        guard i + 2 < data.count else { return nil }
                        let b2 = Int(data[i]); let b3 = Int(data[i+1]); i += 2
                        length = (((b0 & 0xF) << 12) | (b1 << 4) | (b2 >> 4)) + 0x111
                        offset = (((b2 & 0xF) << 8) | b3) + 1
                    } else if indicator == 0 {
                        let b2 = Int(data[i]); i += 1
                        length = (((b0 & 0xF) << 4) | (b1 >> 4)) + 0x11
                        offset = (((b1 & 0xF) << 8) | b2) + 1
                    } else {
                        length = indicator + 1
                        offset = (((b0 & 0xF) << 8) | b1) + 1
                    }
                    let base = out.count - offset
                    guard base >= 0 else { return nil }
                    for j in 0..<length {
                        out.append(out[base + (j % offset)])
                    }
                }
            }
        }

        return Data(out)
    }
}

// MARK: — Data helpers

private extension Data {
    func loadLE<T: FixedWidthInteger>(_ type: T.Type, at offset: Int) -> T {
        guard offset + MemoryLayout<T>.size <= count else { return 0 }
        return subdata(in: offset..<(offset + MemoryLayout<T>.size))
            .withUnsafeBytes { $0.load(as: T.self).littleEndian }
    }
}
