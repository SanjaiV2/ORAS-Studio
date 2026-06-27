import struct, sys, os

def parse_garc(path):
    with open(path, "rb") as f:
        data = f.read()
    magic = data[0:4]
    assert magic == b"CRAG", f"bad magic {magic}"
    header_size, endian, version, chunk_count, data_offset, file_size = struct.unpack_from("<IHHIII", data, 4)
    # fixed fields above consume 24 bytes (4+4+2+2+4+4+4); header_size marks total header length
    # (including version-specific trailing fields), i.e. the offset where OTAF begins.
    if version == 0x0400:
        largest_unpadded, = struct.unpack_from("<I", data, 24)
    elif version == 0x0600:
        largest_padded, largest_unpadded, pad_to = struct.unpack_from("<III", data, 24)
    else:
        raise ValueError(f"unknown version {version:#x}")
    off = header_size

    assert data[off:off+4] == b"OTAF"
    fato_header_size, = struct.unpack_from("<I", data, off+4)
    entry_count, padding = struct.unpack_from("<HH", data, off+8)
    fato_off = off + 0xC
    offsets = []
    for i in range(entry_count):
        o, = struct.unpack_from("<I", data, fato_off + i*4)
        offsets.append(o)
    off = off + fato_header_size

    assert data[off:off+4] == b"BTAF", data[off:off+4]
    fatb_header_size, = struct.unpack_from("<I", data, off+4)
    file_count, = struct.unpack_from("<I", data, off+8)
    fatb_base = off + 0xC

    entries = []  # list of list of (start,end,length)
    pos = fatb_base
    for i in range(entry_count):
        vector, = struct.unpack_from("<I", data, pos)
        pos += 4
        subs = []
        for b in range(32):
            if not (vector >> b) & 1:
                continue
            start, end, length = struct.unpack_from("<III", data, pos)
            pos += 12
            subs.append((b, start, end, length))
        entries.append(subs)
    off = off + fatb_header_size

    assert data[off:off+4] == b"BMIF", data[off:off+4]
    fimb_header_size, = struct.unpack_from("<I", data, off+4)
    fimb_data_size, = struct.unpack_from("<I", data, off+8)

    return {
        "data": data,
        "data_offset": data_offset,
        "entries": entries,
        "version": version,
        "file_count": file_count,
        "entry_count": entry_count,
    }

if __name__ == "__main__":
    path = sys.argv[1]
    g = parse_garc(path)
    print(f"version={g['version']:#x} entry_count={g['entry_count']} file_count={g['file_count']} data_offset={g['data_offset']:#x}")
    if len(sys.argv) > 2 and sys.argv[2] == "--list":
        for i, subs in enumerate(g["entries"][:50]):
            print(i, subs)
    if len(sys.argv) > 2 and sys.argv[2] == "--extract":
        outdir = sys.argv[3]
        os.makedirs(outdir, exist_ok=True)
        data = g["data"]
        do = g["data_offset"]
        for i, subs in enumerate(g["entries"]):
            for b, start, end, length in subs:
                fname = f"{i:04d}" if len(subs) == 1 else f"{i:04d}_{b:02d}"
                with open(os.path.join(outdir, fname + ".bin"), "wb") as out:
                    out.write(data[do+start:do+start+length])
