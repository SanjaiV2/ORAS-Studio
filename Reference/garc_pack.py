import struct
from garc_unpack import parse_garc


def repack_garc(path, overrides):
    """overrides: dict {(entry_idx, sub_idx): new_bytes}. Returns full new GARC file bytes.
    Preserves header/FATO/FATB structure; only rewrites file data lengths/offsets and FIMB payload."""
    g = parse_garc(path)
    data = g["data"]
    version = g["version"]
    if version != 0x0400:
        raise ValueError(f"only GARC version 4 (gen6) supported, got {version:#x}")

    header_size = struct.unpack_from("<I", data, 4)[0]
    off = header_size
    fato_header_size, = struct.unpack_from("<I", data, off + 4)
    entry_count, padding = struct.unpack_from("<HH", data, off + 8)
    fato_off = off + 0xC
    fato_offsets = [struct.unpack_from("<I", data, fato_off + i * 4)[0] for i in range(entry_count)]
    off2 = off + fato_header_size

    fatb_header_size, = struct.unpack_from("<I", data, off2 + 4)
    file_count, = struct.unpack_from("<I", data, off2 + 8)
    fatb_base = off2 + 0xC

    # Re-walk entries, replacing content where overridden, recomputing start/end/length.
    new_fatb = bytearray()
    new_fimb = bytearray()
    cursor = 0
    largest_unpadded = 0
    pos = fatb_base
    for i in range(entry_count):
        vector, = struct.unpack_from("<I", data, pos)
        pos += 4
        new_fatb += struct.pack("<I", vector)
        for b in range(32):
            if not (vector >> b) & 1:
                continue
            start, end, length = struct.unpack_from("<III", data, pos)
            pos += 12
            key = (i, b)
            if key in overrides:
                payload = overrides[key]
            else:
                payload = data[g["data_offset"] + start: g["data_offset"] + start + length]
            real_len = len(payload)
            largest_unpadded = max(largest_unpadded, real_len)
            pad = (-real_len) % 4
            padded = payload + b"\xFF" * pad
            new_start = cursor
            new_end = cursor + len(padded)
            new_fatb += struct.pack("<III", new_start, new_end, real_len)
            new_fimb += padded
            cursor = new_end

    fatb_total_header_size = 0xC + len(new_fatb)
    assert fatb_total_header_size == fatb_header_size, (
        f"FATB size changed ({fatb_total_header_size} != {fatb_header_size}); "
        "adding/removing subfiles is not supported by this packer"
    )

    out = bytearray()
    out += b"CRAG"
    out += struct.pack("<I", header_size)
    out += struct.pack("<HH", 0xFEFE if False else 0xFEFF, version)
    out += struct.pack("<I", 4)  # chunk count
    data_offset_field_pos = len(out)
    out += struct.pack("<I", 0)  # data_offset placeholder
    file_size_field_pos = len(out)
    out += struct.pack("<I", 0)  # file_size placeholder
    out += struct.pack("<I", largest_unpadded)
    while len(out) < header_size:
        out += b"\x00"

    out += b"OTAF"
    out += struct.pack("<I", fato_header_size)
    out += struct.pack("<HH", entry_count, padding)
    for o in fato_offsets:
        out += struct.pack("<I", o)
    while len(out) < header_size + fato_header_size:
        out += b"\x00"

    out += b"BTAF"
    out += struct.pack("<I", fatb_header_size)
    out += struct.pack("<I", file_count)
    out += bytes(new_fatb)

    out += b"BMIF"
    out += struct.pack("<I", 0xC)
    out += struct.pack("<I", len(new_fimb))

    data_offset = len(out)
    struct.pack_into("<I", out, data_offset_field_pos, data_offset)

    out += bytes(new_fimb)
    struct.pack_into("<I", out, file_size_field_pos, len(out))

    return bytes(out)


if __name__ == "__main__":
    import sys
    path = sys.argv[1]
    out_path = sys.argv[2]
    new_data = repack_garc(path, {})
    with open(out_path, "wb") as f:
        f.write(new_data)
    orig = open(path, "rb").read()
    print("identical to original (no overrides):", new_data == orig, len(new_data), len(orig))
