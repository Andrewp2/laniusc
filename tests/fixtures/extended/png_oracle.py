"""Independent test generator and Pillow decoder; never used by production code."""
import io
import struct
import sys
import zlib


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


def paeth(a, b, c):
    p = a + b - c
    return min((a, b, c), key=lambda v: abs(p - v))


def make(width, height, depth, color, interlace, filtering, transparency=True):
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[color]
    maximum = (1 << depth) - 1
    palette = [(i * 53 % 256, i * 97 % 256, i * 149 % 256) for i in range(min(1 << depth, 19))]
    samples = []
    for y in range(height):
        row = []
        for x in range(width):
            values = [(x * 7129 + y * 43891 + c * 23459 + (x * y + 17) * 97) & maximum for c in range(channels)]
            if color == 3:
                values = [(x + y * 3) % len(palette)]
            row.append(values)
        samples.append(row)
    key = samples[0][0]
    alpha = [(i * 67) % 256 for i in range(max(1, len(palette) - 3))]
    trns = b""
    if transparency and color in (0, 2):
        # PNG 3 requires decoders to mask unused high tRNS sample bits.
        trns = b"".join(struct.pack(">H", v | (65535 ^ maximum)) for v in key)
    if transparency and color == 3:
        trns = bytes(alpha)
    passes = [(0, 0, 1, 1)] if not interlace else [(0, 0, 8, 8), (4, 0, 8, 8), (0, 4, 4, 8), (2, 0, 4, 4), (0, 2, 2, 4), (1, 0, 2, 2), (0, 1, 1, 2)]
    raw = bytearray()
    for sx, sy, dx, dy in passes:
        xs, ys = list(range(sx, width, dx)), list(range(sy, height, dy))
        if not xs or not ys:
            continue
        previous = b""
        for y in ys:
            values = [v for x in xs for v in samples[y][x]]
            if depth == 16:
                row = b"".join(struct.pack(">H", v) for v in values)
            elif depth == 8:
                row = bytes(values)
            else:
                row = bytearray((len(values) * depth + 7) // 8)
                for i, v in enumerate(values):
                    row[i * depth // 8] |= v << (8 - depth - i * depth % 8)
                row = bytes(row)
            bpp = max(1, (channels * depth + 7) // 8)
            f = filtering if filtering < 5 else y % 5
            raw.append(f)
            for i, value in enumerate(row):
                a = row[i - bpp] if i >= bpp else 0
                b = previous[i] if previous else 0
                c = previous[i - bpp] if previous and i >= bpp else 0
                predictor = [0, a, b, (a + b) // 2, paeth(a, b, c)][f]
                raw.append((value - predictor) % 256)
            previous = row
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, depth, color, 0, 0, interlace))
    if color == 3:
        png += chunk(b"PLTE", bytes(v for rgb in palette for v in rgb))
    if trns:
        png += chunk(b"tRNS", trns)
    compressed = zlib.compress(bytes(raw), 6)
    # Deliberately split the zlib header, stream, and checksum across chunks.
    for part in [compressed[:1], b"", compressed[1:-2], compressed[-2:]]:
        png += chunk(b"IDAT", part)
    png += chunk(b"IEND", b"")
    expected = bytearray()
    scale = lambda v: (v * 255 + maximum // 2) // maximum
    for row in samples:
        for values in row:
            if color == 3:
                i = values[0]
                rgba = (*palette[i], alpha[i] if transparency and i < len(alpha) else 255)
            elif color in (0, 4):
                rgba = (scale(values[0]),) * 3 + (scale(values[1]) if color == 4 else 0 if transparency and values == key else 255,)
            else:
                rgba = tuple(scale(v) for v in values[:3]) + (scale(values[3]) if color == 6 else 0 if transparency and values == key else 255,)
            expected.extend(rgba)
    return png, bytes(expected)


def generate():
    from PIL import Image
    for color, depths in [(0, [1, 2, 4, 8, 16]), (2, [8, 16]), (3, [1, 2, 4, 8]), (4, [8, 16]), (6, [8, 16])]:
        for depth in depths:
            for interlace in [0, 1]:
                for filtering in range(5):
                    for w, h in [(13, 11), (1, 1), (2, 7), (7, 2)]:
                        png, expected = make(w, h, depth, color, interlace, filtering)
                        # Pillow independently checks all RGBA8 cases. It drops
                        # low bytes for RGB16, so exact16 rescaling uses samples.
                        if depth == 8 and color in (4, 6):
                            image = Image.open(io.BytesIO(png)).convert("RGBA")
                            assert image.tobytes() == expected
                        sys.stdout.buffer.write(struct.pack("<IIII", w, h, len(png), len(expected)) + png + expected)


if __name__ == "__main__":
    if sys.argv[1] == "generate":
        generate()
    else:
        from PIL import Image
        image = Image.open(io.BytesIO(sys.stdin.buffer.read())).convert("RGBA")
        sys.stdout.buffer.write(struct.pack("<II", *image.size) + image.tobytes())
