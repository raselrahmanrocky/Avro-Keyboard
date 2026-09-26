#!/usr/bin/env python3
"""Build a multi-resolution .ico from a single-resolution 32bpp .ico.

Windows picks the *closest* size out of an icon and scales it itself when the
requested size is missing, which is what makes a single 128x128 icon look
blurry in the 16x16 Explorer list view, the notification area and the taskbar
at non-100% DPI.  Shipping one image per size Windows actually asks for (16px
at 100%, 20 at 125%, 24 at 150%, 32 at 200%, 48 at 300%, plus the shell's
32/48/64/128 views) avoids that scaling entirely.

Only the Python standard library is used, so the icon can be regenerated on
any machine:

    python tools/make_multi_size_ico.py Converter.ico Converter.ico

Downscaling is an exact area-average over the covered source pixels with
premultiplied alpha, so edges stay clean instead of picking up a dark or light
fringe.  The 1-bit AND mask is derived from the alpha channel for the benefit
of the classic Win32 icon path.
"""
import math
import struct
import sys

DEFAULT_SIZES = (16, 20, 24, 28, 32, 40, 48, 64, 128)


def _floor(v):
    """floor() that tolerates 2.999999996 from an inexact scale factor."""
    return math.floor(v + 1e-9)


def _ceil(v):
    return math.ceil(v - 1e-9)


def read_ico(path):
    """Return [(width, height, rgba_bytes)] for every BMP entry in the file."""
    with open(path, "rb") as fh:
        data = fh.read()
    reserved, kind, count = struct.unpack_from("<HHH", data, 0)
    if reserved != 0 or kind != 1:
        raise ValueError("%s is not an icon file" % path)
    images = []
    for i in range(count):
        w, h, _colors, _res, _planes, bpp, size, offset = struct.unpack_from(
            "<BBBBHHII", data, 6 + i * 16)
        w = w or 256
        h = h or 256
        entry = data[offset:offset + size]
        if entry[:4] != b"\x28\x00\x00\x00":
            raise ValueError(
                "%s entry %d is not a 32bpp DIB (PNG entries are unsupported)"
                % (path, i))
        if bpp != 32:
            raise ValueError("%s entry %d is %d bpp, expected 32" % (path, i, bpp))
        dib_h, = struct.unpack_from("<i", entry, 8)
        if dib_h != 2 * h:
            raise ValueError("%s entry %d is not a 32bpp icon image" % (path, i))
        # Rows are stored bottom-up, BGRA order.
        rgba = bytearray(w * h * 4)
        row = w * 4
        for y in range(h):
            src = 40 + (h - 1 - y) * row
            for x in range(w):
                b, g, r, a = entry[src + x * 4:src + x * 4 + 4]
                dst = (y * w + x) * 4
                rgba[dst:dst + 4] = bytes((r, g, b, a))
        images.append((w, h, bytes(rgba)))
    return images


def scaled(master, source_size, size):
    """Area-average the master down to `size` x `size` (premultiplied)."""
    src = master
    factor = source_size / float(size)
    out = bytearray(size * size * 4)
    for oy in range(size):
        y0, y1 = oy * factor, (oy + 1) * factor
        sy0 = _floor(y0)
        sy1 = min(source_size, _ceil(y1))
        for ox in range(size):
            x0, x1 = ox * factor, (ox + 1) * factor
            sx0 = _floor(x0)
            sx1 = min(source_size, _ceil(x1))
            acc_a = acc_r = acc_g = acc_b = 0.0
            weight = 0.0
            for sy in range(sy0, sy1):
                wy = min(y1, sy + 1) - max(y0, sy)
                if wy <= 0:
                    continue
                base = sy * source_size * 4
                for sx in range(sx0, sx1):
                    wx = min(x1, sx + 1) - max(x0, sx)
                    if wx <= 0:
                        continue
                    w = wx * wy
                    weight += w
                    p = base + sx * 4
                    a = src[p + 3] / 255.0
                    acc_a += a * w
                    acc_r += src[p] * a * w
                    acc_g += src[p + 1] * a * w
                    acc_b += src[p + 2] * a * w
            d = (oy * size + ox) * 4
            if acc_a > 0.0:
                out[d] = min(255, int(round(acc_r / acc_a)))
                out[d + 1] = min(255, int(round(acc_g / acc_a)))
                out[d + 2] = min(255, int(round(acc_b / acc_a)))
            out[d + 3] = min(255, int(round(acc_a / weight * 255.0)))
    return bytes(out)


def dib(rgba, size):
    """Serialise one icon image: BITMAPINFOHEADER + XOR bitmap + AND mask."""
    header = struct.pack("<IiiHHIIiiII", 40, size, size * 2, 1, 32, 0,
                         size * size * 4, 0, 0, 0, 0)
    xor = bytearray()
    for y in range(size - 1, -1, -1):
        for x in range(size):
            p = (y * size + x) * 4
            r, g, b, a = rgba[p:p + 4]
            xor += bytes((b, g, r, a))
    stride = ((size + 31) // 32) * 4
    mask = bytearray()
    for y in range(size - 1, -1, -1):
        row = bytearray(stride)
        for x in range(size):
            if rgba[(y * size + x) * 4 + 3] < 128:
                row[x >> 3] |= 0x80 >> (x & 7)  # 1 = transparent
        mask += row
    return header + bytes(xor) + bytes(mask)


def write_ico(path, images):
    """images: [(size, dib_bytes)] - written as a standard .ico container."""
    dir_size = 6 + 16 * len(images)
    offset = dir_size
    entries = bytearray()
    payload = bytearray()
    for size, data in images:
        entries += struct.pack("<BBBBHHII", size if size < 256 else 0,
                               size if size < 256 else 0, 0, 0, 1, 32,
                               len(data), offset)
        payload += data
        offset += len(data)
    with open(path, "wb") as fh:
        fh.write(struct.pack("<HHH", 0, 1, len(images)))
        fh.write(entries)
        fh.write(payload)


def main(argv):
    if len(argv) < 2 or len(argv) > 3:
        print(__doc__)
        return 2
    src, dst = argv[0], argv[1] if len(argv) > 1 else argv[0]
    sizes = [int(a) for a in argv[2].split(",")] if len(argv) > 2 else DEFAULT_SIZES
    images = read_ico(src)
    size, master = max((w, px) for w, h, px in images if w == h)
    print("master: %dx%d from %s" % (size, size, src))
    out = []
    for s in sorted({s for s in sizes if s <= size}):
        px = master if s == size else scaled(master, size, s)
        out.append((s, dib(px, s)))
        print("  %3dpx  %6d bytes" % (s, len(out[-1][1])))
    write_ico(dst, out)
    print("wrote %s (%d images, %d bytes)" % (dst, len(out),
          sum(len(d) for _, d in out) + 6 + 16 * len(out)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
