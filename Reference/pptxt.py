import struct

KEY_BASE = 0x7C89
KEY_ADVANCE = 0x2983
KEY_VARIABLE = 0x0010
KEY_TERMINATOR = 0x0000
KEY_TEXTRETURN = 0xBE00
KEY_TEXTCLEAR = 0xBE01
KEY_TEXTWAIT = 0xBE02
KEY_TEXTNULL = 0xBDFF

REMAP = {0x202F: 0xE07F, 0x2026: 0xE08D, 0x2642: 0xE08E, 0x2640: 0xE08F}
UNREMAP = {v: k for k, v in REMAP.items()}


def _crypt(data, key):
    out = bytearray(len(data))
    for i in range(0, len(data), 2):
        val = struct.unpack_from("<H", data, i)[0] ^ key
        struct.pack_into("<H", out, i, val)
        key = ((key << 3) | (key >> 13)) & 0xFFFF
    return bytes(out)


def decode(data, remap_chars=True):
    """Parse a PPTXT message-bank file. Returns list of raw strings (with escape codes preserved)."""
    text_sections, line_count = struct.unpack_from("<HH", data, 0)
    total_length, initial_key = struct.unpack_from("<II", data, 4)
    sdo = struct.unpack_from("<I", data, 0xC)[0]
    if initial_key != 0 or text_sections != 1:
        raise ValueError("not a PPTXT text file")
    section_length = struct.unpack_from("<I", data, sdo)[0]
    if section_length != total_length:
        raise ValueError("section/total length mismatch")

    rec_base = sdo + 4
    lines = []
    key = KEY_BASE
    for i in range(line_count):
        off, length = struct.unpack_from("<iH", data, rec_base + i * 8)
        off += sdo
        enc = data[off:off + length * 2]
        dec = _crypt(enc, key)
        lines.append(_parse_line(dec, remap_chars))
        key = (key + KEY_ADVANCE) & 0xFFFF
    return lines


def _parse_line(data, remap_chars):
    out = []
    i = 0
    while i < len(data):
        val = struct.unpack_from("<H", data, i)[0]
        if val == KEY_TERMINATOR:
            break
        i += 2
        if val == KEY_VARIABLE:
            s, i = _parse_variable(data, i)
            out.append(s)
        elif val == ord('\n'):
            out.append("\\n")
        elif val == ord('\\'):
            out.append("\\\\")
        elif val == ord('['):
            out.append("\\[")
        else:
            if remap_chars and val in UNREMAP:
                val = UNREMAP[val]
            out.append(chr(val))
    return "".join(out)


def _parse_variable(data, i):
    count = struct.unpack_from("<H", data, i)[0]; i += 2
    variable = struct.unpack_from("<H", data, i)[0]; i += 2
    if variable == KEY_TEXTRETURN:
        return "\\r", i
    if variable == KEY_TEXTCLEAR:
        return "\\c", i
    if variable == KEY_TEXTWAIT:
        time = struct.unpack_from("<H", data, i)[0]; i += 2
        return f"[WAIT {time}]", i
    if variable == KEY_TEXTNULL:
        line = struct.unpack_from("<H", data, i)[0]; i += 2
        return f"[~ {line}]", i

    args = []
    remaining = count - 1
    while remaining > 0:
        arg = struct.unpack_from("<H", data, i)[0]; i += 2
        args.append(f"{arg:04X}")
        remaining -= 1
    s = f"[VAR {variable:04X}"
    if args:
        s += "(" + ",".join(args) + ")"
    s += "]"
    return s, i


def _line_to_data(text, remap_chars):
    out = bytearray()
    i = 0
    n = len(text)
    while i < n:
        ch = text[i]; i += 1
        if ch == '[':
            end = text.index(']', i)
            var_text = text[i:end]
            out += _encode_variable(var_text)
            i = end + 1
        elif ch == '\\':
            esc = text[i]; i += 1
            if esc == 'n':
                out += struct.pack("<H", ord('\n'))
            elif esc == '\\':
                out += struct.pack("<H", ord('\\'))
            elif esc == '[':
                out += struct.pack("<H", ord('['))
            elif esc == 'r':
                out += struct.pack("<HHH", KEY_VARIABLE, 1, KEY_TEXTRETURN)
            elif esc == 'c':
                out += struct.pack("<HHH", KEY_VARIABLE, 1, KEY_TEXTCLEAR)
            else:
                raise ValueError("bad escape: \\" + esc)
        else:
            val = ord(ch)
            if remap_chars and val in REMAP:
                val = REMAP[val]
            out += struct.pack("<H", val)
    out += struct.pack("<H", KEY_TERMINATOR)
    return bytes(out)


def _encode_variable(var_text):
    if var_text.startswith("~ "):
        line = int(var_text[2:])
        return struct.pack("<HHHH", KEY_VARIABLE, 1, KEY_TEXTNULL, line)
    if var_text.startswith("WAIT "):
        t = int(var_text[5:])
        return struct.pack("<HHHH", KEY_VARIABLE, 1, KEY_TEXTWAIT, t)
    if var_text.startswith("VAR "):
        rest = var_text[4:]
        bracket = rest.find('(')
        if bracket < 0:
            varval = int(rest, 16)
            return struct.pack("<HHH", KEY_VARIABLE, 1, varval)
        varname = rest[:bracket]
        varval = int(varname, 16)
        args = rest[bracket+1:-1].split(',')
        vals = [KEY_VARIABLE, 1 + len(args), varval] + [int(a, 16) for a in args]
        return struct.pack(f"<{len(vals)}H", *vals)
    raise ValueError("unknown variable: " + var_text)


def encode(lines, remap_chars=True):
    """Build a PPTXT message-bank file from a list of strings."""
    sdo = 0x10
    key = KEY_BASE
    line_blobs = []
    for text in lines:
        dec = _line_to_data(text or "", remap_chars)
        enc = bytearray(_crypt(dec, key))
        if len(enc) % 4 == 2:
            enc += b"\x00\x00"
        line_blobs.append(bytes(enc))
        key = (key + KEY_ADVANCE) & 0xFFFF

    n = len(line_blobs)
    rec_bytes_len = 8 * n
    data_start = sdo + 4 + rec_bytes_len
    total_blob = b"".join(line_blobs)
    section_total_len = 4 + rec_bytes_len + len(total_blob)

    out = bytearray(sdo)
    struct.pack_into("<HHIII", out, 0, 1, n, section_total_len, 0, sdo)
    out += struct.pack("<I", section_total_len)  # SectionLength at sdo
    offset_cursor = 4 + rec_bytes_len
    for blob in line_blobs:
        out += struct.pack("<iH2x", offset_cursor, len(blob) // 2)
        offset_cursor += len(blob)
    out += total_blob
    return bytes(out)


if __name__ == "__main__":
    import sys
    data = open(sys.argv[1], "rb").read()
    for i, line in enumerate(decode(data)):
        print(i, repr(line))
