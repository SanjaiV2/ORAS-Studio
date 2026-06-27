import struct

def decompress(data):
    if data[0] != 0x11:
        return data
    decompressed_size = data[1] | (data[2] << 8) | (data[3] << 16)
    pos = 4
    if decompressed_size == 0:
        decompressed_size = struct.unpack_from("<I", data, 4)[0]
        pos = 8
    out = bytearray()
    n = len(data)
    while len(out) < decompressed_size and pos < n:
        flags = data[pos]; pos += 1
        for bit in range(8):
            if len(out) >= decompressed_size:
                break
            if pos >= n:
                break
            if (flags & (0x80 >> bit)) == 0:
                out.append(data[pos]); pos += 1
            else:
                b0 = data[pos]; pos += 1
                indicator = b0 >> 4
                if indicator == 0:
                    b1 = data[pos]; pos += 1
                    b2 = data[pos]; pos += 1
                    count = ((b0 & 0xF) << 4 | (b1 >> 4)) + 0x11
                    disp = ((b1 & 0xF) << 8 | b2) + 1
                elif indicator == 1:
                    b1 = data[pos]; pos += 1
                    b2 = data[pos]; pos += 1
                    b3 = data[pos]; pos += 1
                    count = ((b0 & 0xF) << 12 | b1 << 4 | (b2 >> 4)) + 0x111
                    disp = ((b2 & 0xF) << 8 | b3) + 1
                else:
                    b1 = data[pos]; pos += 1
                    count = (b0 >> 4) + 1
                    disp = ((b0 & 0xF) << 8 | b1) + 1
                start = len(out) - disp
                for i in range(count):
                    out.append(out[start + i])
    return bytes(out)

if __name__ == "__main__":
    import sys
    with open(sys.argv[1], "rb") as f:
        data = f.read()
    out = decompress(data)
    with open(sys.argv[2], "wb") as f:
        f.write(out)
    print(f"decompressed {len(data)} -> {len(out)} bytes")
