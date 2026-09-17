"""Probe a legacy Bangla ANSI font (TrueType) without fontTools.

Prints the family name, the cmap subtables, and -- for every codepoint the
font actually covers in the ranges a Bangla ANSI mapping uses -- the glyph id
and glyph name.  A mapping's declared ANSI codes can then be checked against
the font that the mapping is meant to be typed with.

Usage: font_probe.py <font.ttf> [range ...]   (ranges like 0x20-0xFF)
"""
import struct
import sys


def read_tables(data):
    num_tables = struct.unpack(">H", data[4:6])[0]
    tables = {}
    for i in range(num_tables):
        off = 12 + i * 16
        tag = data[off:off + 4].decode("latin-1")
        _, toff, tlen = struct.unpack(">III", data[off + 4:off + 16])
        tables[tag] = (toff, tlen)
    return tables


def parse_cmap(data, toff):
    version, num = struct.unpack(">HH", data[toff:toff + 4])
    subtables = []
    for i in range(num):
        pid, eid, off = struct.unpack(">HHI", data[toff + 4 + i * 8:toff + 12 + i * 8])
        subtables.append((pid, eid, toff + off))
    best = {}
    for pid, eid, off in subtables:
        fmt = struct.unpack(">H", data[off:off + 2])[0]
        mapping = {}
        if fmt == 4:
            segx2 = struct.unpack(">H", data[off + 6:off + 8])[0]
            seg = segx2 // 2
            ends = struct.unpack(">%dH" % seg, data[off + 14:off + 14 + segx2])
            starts = struct.unpack(">%dH" % seg, data[off + 16 + segx2:off + 16 + segx2 * 2])
            deltas = struct.unpack(">%dh" % seg, data[off + 16 + segx2 * 2:off + 16 + segx2 * 3])
            iro = off + 16 + segx2 * 3
            ranges = struct.unpack(">%dH" % seg, data[iro:iro + segx2])
            for s in range(seg):
                for c in range(starts[s], min(ends[s], 0xFFFF) + 1):
                    if c == 0xFFFF:
                        continue
                    if ranges[s] == 0:
                        g = (c + deltas[s]) & 0xFFFF
                    else:
                        addr = iro + ranges[s] + (c - starts[s]) * 2
                        g = struct.unpack(">H", data[addr:addr + 2])[0]
                        if g:
                            g = (g + deltas[s]) & 0xFFFF
                    if g:
                        mapping[c] = g
        elif fmt == 12:
            ngroups = struct.unpack(">I", data[off + 12:off + 16])[0]
            for i in range(ngroups):
                s, e, sg = struct.unpack(">III", data[off + 16 + i * 12:off + 28 + i * 12])
                for c in range(s, min(e, s + 5000) + 1):
                    mapping[c] = sg + (c - s)
        elif fmt == 6:
            first, count = struct.unpack(">HH", data[off + 6:off + 10])
            for i in range(count):
                g = struct.unpack(">H", data[off + 10 + i * 2:off + 12 + i * 2])[0]
                if g:
                    mapping[first + i] = g
        elif fmt == 0:
            for c in range(256):
                g = data[off + 6 + c]
                if g:
                    mapping[c] = g
        if mapping:
            key = (pid, eid, fmt)
            best[key] = mapping
    return best


def parse_post_names(data, toff, tlen):
    names = {}
    if toff + 32 > len(data):
        return names
    ver = struct.unpack(">I", data[toff:toff + 4])[0]
    numGlyphs = struct.unpack(">H", data[toff + 32:toff + 34])[0]
    if ver == 0x00020000:
        idx = []
        p = toff + 34
        for i in range(numGlyphs):
            idx.append(struct.unpack(">H", data[p:p + 2])[0])
            p += 2
        pascal = data[p:toff + tlen]
        custom = {}
        q = 0
        while q < len(pascal):
            ln = pascal[q]
            custom[258 + len(custom)] = pascal[q + 1:q + 1 + ln].decode("latin-1")
            q += 1 + ln
        STD = ["", ".notdef", ".null", "nonmarkingreturn", "space", "exclam", "quotedbl",
               "numbersign", "dollar", "percent", "ampersand", "quotesingle", "parenleft",
               "parenright", "asterisk", "plus", "comma", "hyphen", "period", "slash",
               "zero", "one", "two", "three", "four", "five", "six", "seven", "eight",
               "nine", "colon", "semicolon", "less", "equal", "greater", "question", "at"]
        for i, g in enumerate(idx):
            if g == 0:
                names[i] = ".notdef"
            elif g < len(STD):
                names[i] = STD[g]
            else:
                names[i] = custom.get(g, "custom%d" % g)
    elif ver == 0x00010000:
        STD = ["", ".notdef", ".null", "nonmarkingreturn", "space", "exclam", "quotedbl",
               "numbersign", "dollar", "percent", "ampersand", "quotesingle", "parenleft",
               "parenright", "asterisk", "plus", "comma", "hyphen", "period", "slash",
               "zero", "one", "two", "three", "four", "five", "six", "seven", "eight",
               "nine", "colon", "semicolon", "less", "equal", "greater", "question", "at",
               "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O",
               "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "bracketleft",
               "backslash", "bracketright", "asciicircum", "underscore", "grave", "a", "b",
               "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q",
               "r", "s", "t", "u", "v", "w", "x", "y", "z", "braceleft", "bar",
               "braceright", "asciitilde"]
        for i in range(numGlyphs):
            names[i] = STD[i] if i < len(STD) else "custom%d" % i
    return names


def parse_name_family(data, toff):
    out = []
    fmt, count, stroff = struct.unpack(">HHH", data[toff:toff + 6])
    for i in range(count):
        rec = data[toff + 6 + i * 12:toff + 18 + i * 12]
        pid, eid, lid, nid, ln, off = struct.unpack(">HHHHHH", rec)
        if nid in (1, 4):
            raw = data[toff + stroff + off:toff + stroff + off + ln]
            try:
                txt = raw.decode("utf-16-be") if pid == 3 else raw.decode("latin-1")
            except Exception:
                continue
            out.append((nid, txt))
    return out


def main():
    path = sys.argv[1]
    want = []
    for arg in sys.argv[2:]:
        if "-" in arg:
            lo, hi = arg.split("-")
            want.append((int(lo, 0), int(hi, 0)))
        else:
            want.append((int(arg, 0), int(arg, 0)))
    data = open(path, "rb").read()
    tables = read_tables(data)
    print("file:", path)
    print("tags:", " ".join(sorted(tables)))
    if "name" in tables:
        for nid, txt in parse_name_family(data, tables["name"][0]):
            print("  name(%d): %s" % (nid, txt))
    names = parse_post_names(data, *tables["post"]) if "post" in tables else {}
    cmaps = parse_cmap(data, tables["cmap"][0])
    for key in sorted(cmaps):
        print("  cmap pid=%d eid=%d fmt=%d: %d codepoints" % (key + (len(cmaps[key]),)))
    # prefer the 3/1 (Windows BMP) subtable
    chosen = None
    for key in sorted(cmaps):
        if key[0] == 3 and key[1] == 1:
            chosen = cmaps[key]
    if chosen is None:
        chosen = max(cmaps.values(), key=len)
    for lo, hi in want:
        print("--- range U+%04X..U+%04X ---" % (lo, hi))
        for c in range(lo, hi + 1):
            if c in chosen:
                g = chosen[c]
                print("   %04X  glyph %5d  %s" % (c, g, names.get(g, "?")))


if __name__ == "__main__":
    main()
