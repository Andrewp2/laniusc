"""Exact rational RGBA resize reference; test-only, independent of native passes.

Consumer tests may import resize_rgba(bytes, sw, sh, dw, dh, filter). No corpus
or subprocess is constructed at import time. Filters are 0/1/2 or their names.
"""
from __future__ import annotations

from collections import Counter
from dataclasses import dataclass, replace
from fractions import Fraction as F
from functools import lru_cache
from itertools import product
from pathlib import Path
import random
import struct
import subprocess
import sys

SEED = 0x1A6E0261113
MAGIC = 0x696D67726573697A
END = 0x656E64726573697A
MASK = (1 << 64) - 1
BACKING = 8192
NAMES = ('nearest', 'bilinear', 'area')


def half_up(value):
    """Nearest integer, nonnegative exact ties upward; no floating point."""
    assert value >= 0
    return (2 * value.numerator + value.denominator) // (2 * value.denominator)


@lru_cache(maxsize=1024)
def weights(source, target, filter):
    """A declarative destination-by-source matrix, with each row summing to1."""
    rows = []
    for d in range(target):
        center = F(2 * d + 1, 2) * source / target
        if filter == 0:
            selected = center.numerator // center.denominator
            row = tuple(F(i == selected) for i in range(source))
        elif filter == 1:
            at = min(F(source - 1), max(F(0), center - F(1, 2)))
            row = tuple(max(F(0), 1 - abs(at - i)) for i in range(source))
        else:
            left, right = F(d * source, target), F((d + 1) * source, target)
            row = tuple(max(F(0), min(right, i + 1) - max(left, i)) / (right - left)
                        for i in range(source))
        assert sum(row) == 1 and all(x >= 0 for x in row)
        rows.append(row)
    return tuple(rows)


@lru_cache(maxsize=8192)
def weighted_pixel(samples):
    alpha = sum(weight * pixel[3] for pixel, weight in samples)
    if not alpha:
        return bytes(4)
    colors = [half_up(sum(weight * pixel[3] * pixel[c] for pixel, weight in samples) / alpha)
              for c in range(3)]
    return bytes(colors + [half_up(alpha)])


def resize_rgba(pixels: bytes, sw: int, sh: int, dw: int, dh: int, filter: int | str) -> bytes:
    """Direct two-dimensional exact evaluation, with no intermediate raster."""
    if isinstance(filter, str):
        filter = NAMES.index(filter)
    assert min(sw, sh, dw, dh) > 0 and filter in range(3)
    assert len(pixels) == 4 * sw * sh
    if (sw, sh) == (dw, dh):
        return pixels
    source = tuple(tuple(pixels[i:i + 4]) for i in range(0, len(pixels), 4))
    # Sparse rows only omit mathematically zero weights; Area's weights above
    # come from intersections with every source cell, not a production sweep.
    horizontal = [tuple((i, w) for i, w in enumerate(row) if w) for row in weights(sw, dw, filter)]
    vertical = [tuple((j, w) for j, w in enumerate(row) if w) for row in weights(sh, dh, filter)]
    output = bytearray()
    for ys in vertical:
        for xs in horizontal:
            samples = tuple((source[j * sw + i], wx * wy) for j, wy in ys for i, wx in xs)
            output += bytes(samples[0][0]) if filter == 0 else weighted_pixel(samples)
    return bytes(output)


@dataclass(frozen=True)
class Case:
    sw: int
    sh: int
    dw: int
    dh: int
    filter: int
    layout: int
    pixels: bytes
    padding: int = 0
    cropped: int = 0
    invalid: int = 0
    group: str = ''


def pattern(width, height, mode, salt=0):
    rng = random.Random(SEED ^ salt)
    pixels = []
    for y in range(height):
        for x in range(width):
            index = y * width + x
            if mode == 0:
                p = (x * 59 % 256, y * 83 % 256, (index * 71 + 13) % 256, 255)
            elif mode == 1:
                p = (255 * ((x + y) % 2), 255 * (x % 2), 255 * (y % 2), 255)
            elif mode == 2:
                p = (211, 37, 129, (0, 1, 254, 255)[index % 4])
            elif mode == 3:
                p = ((index * 31) % 256, (index * 113) % 256, 255, 0)
            elif mode == 4:
                p = tuple(rng.randrange(256) for _ in range(3)) + (rng.choice((0, 1, 2, 127, 128, 254, 255)),)
            elif mode == 5:
                p = (255, 11, 73, 1) if index == (width * height) // 2 else (0, 249, 255, 0)
            else:
                p = (17, 89, 203, 137)
            pixels.extend(p)
    return bytes(pixels)


def transpose(data, width, height):
    return b''.join(data[(y * width + x) * 4:(y * width + x + 1) * 4]
                    for x in range(width) for y in range(height))


def reflect(data, width, height, vertical=False):
    return b''.join(data[(y * width + x) * 4:(y * width + x + 1) * 4]
                    for y in (range(height - 1, -1, -1) if vertical else range(height))
                    for x in (range(width) if vertical else range(width - 1, -1, -1)))


def corpus():
    cases = []
    for index, (sw, sh, dw, dh) in enumerate(product(range(1, 5), repeat=4)):
        cases.append(Case(sw, sh, dw, dh, index % 3, index % 2,
                          pattern(sw, sh, index % 7, index), index % 8, index % 2))
    witnesses = [
        (2, 2, 1, 1, bytes((0, 0, 0, 255) * 3 + (1, 1, 1, 255))),
        (3, 1, 1, 1, bytes((255, 0, 0, 1, 0, 255, 0, 0, 0, 0, 255, 0))),
        (2, 1, 4, 1, bytes((0, 0, 255, 0, 255, 0, 0, 1))),
        (2, 1, 1, 1, bytes((0, 0, 0, 255, 255, 255, 255, 255))),
        (2, 1, 2, 1, bytes((191, 37, 9, 0, 13, 251, 99, 0))),
        (2, 1, 3, 1, bytes((191, 37, 9, 0, 13, 251, 99, 0))),
        (3, 2, 2, 3, pattern(3, 2, 4, 867)),
        (2, 2, 3, 3, pattern(2, 2, 2)),
    ]
    for sw, sh, dw, dh, pixels in witnesses:
        for filter, layout in product(range(3), range(2)):
            cases.append(Case(sw, sh, dw, dh, filter, layout, pixels, 3, 1))
    shapes = [(1, 1, 7, 5), (1, 7, 5, 1), (7, 1, 1, 5), (1, 9, 1, 4),
              (9, 1, 4, 1), (3, 5, 11, 2), (11, 2, 3, 5), (13, 7, 3, 5),
              (3, 5, 13, 7), (7, 7, 2, 2), (2, 2, 7, 7), (5, 4, 5, 4),
              (2, 3, 2, 3), (1, 1, 1, 1), (5, 6, 5, 2), (6, 5, 2, 5)]
    for index, (sw, sh, dw, dh) in enumerate(shapes):
        for filter, layout in product(range(3), range(2)):
            cases.append(Case(sw, sh, dw, dh, filter, layout, pattern(sw, sh, index % 7, index + 100),
                              (index + 1) % 8, index % 2))
    rng = random.Random(SEED)
    for index in range(64):
        sw, sh, dw, dh = (rng.randrange(1, 14) for _ in range(4))
        cases.append(Case(sw, sh, dw, dh, index % 3, index % 2,
                          pattern(sw, sh, 4, rng.randrange(1 << 32)), rng.randrange(8), rng.randrange(2)))
    # Companion inputs are themselves executed natively; host checks additionally
    # establish finite transpose/reflection relations between complete results.
    for index in range(12):
        sw, sh, dw, dh = (rng.randrange(1, 9) for _ in range(4))
        pixels = pattern(sw, sh, 4, index + 900)
        for filter in range(3):
            group = f'{index}:{filter}'
            base = Case(sw, sh, dw, dh, filter, index % 2, pixels, index % 8, 1, group=group + ':base')
            cases.append(base)
            cases.append(replace(base, sw=sh, sh=sw, dw=dh, dh=dw,
                                 pixels=transpose(pixels, sw, sh), group=group + ':transpose'))
            if filter:
                cases.append(replace(base, pixels=reflect(pixels, sw, sh), group=group + ':horizontal'))
                cases.append(replace(base, pixels=reflect(pixels, sw, sh, True), group=group + ':vertical'))
    # Small source images keep exact2D evaluation cheap while both selected
    # separable orientations cross inner-axis tiles at255/256/257.
    for edge in (255, 256, 257):
        for transposed in (0, 1):
            sw, sh, dw, dh = (3, 2, edge, edge + 1)
            if transposed:
                sw, sh, dw, dh = sh, sw, dh, dw
            cases.append(Case(sw, sh, dw, dh, 2, transposed, pattern(sw, sh, 4, edge), 7, 1))
    # Bad metadata must reject before dimensions or sampling; all physical
    # backing here remains real and alive. Direct/resource gates cover OOM.
    for invalid, filter in product(range(1, 9), range(3)):
        cases.append(Case(2, 3, 0 if invalid % 2 else 2147483647, 2, filter, invalid % 2,
                          pattern(2, 3, 0), 3, 1, invalid))
    for dw, dh in ((0, 1), (-1, 2), (2, 0), (536870912, 1), (536870911, 2), (2147483647, 1)):
        for layout in (0, 1):
            cases.append(Case(2, 3, dw, dh, layout, layout, pattern(2, 3, 0), 3, 1))
    assert len(cases) == 626
    assert all(len(c.pixels) <= 1024 for c in cases)
    assert all(c.invalid or min(c.dw, c.dh) <= 0 or c.dw * c.dh > 536870911 or c.dw * c.dh <= 70000 for c in cases)
    return cases


def source(c):
    stride = (c.sw + 2 * c.cropped) * 4 + c.padding
    start = 3 + c.cropped * (stride + 4)
    length = (c.sh - 1) * stride + 4 * c.sw
    backing = bytearray((193 + i * 19) & 255 for i in range(BACKING))
    for y in range(c.sh):
        backing[start + y * stride:start + y * stride + 4 * c.sw] = c.pixels[y * 4 * c.sw:(y + 1) * 4 * c.sw]
    sw, sh = c.sw, c.sh
    if c.invalid == 1: start = -1
    elif c.invalid == 2: length = -1
    elif c.invalid == 3: start = 2147483647
    elif c.invalid == 4: stride = c.sw * 4 - 1
    elif c.invalid == 5: sh = 0
    elif c.invalid == 6: sw = 2147483647
    elif c.invalid == 7: length = c.sw * 4 - 1
    elif c.invalid == 8: sh += 100000
    return (sw, sh, stride, start, length, -8 if c.layout == 0 else 1), bytes(backing)


def admission(c):
    if c.invalid: return 1
    if min(c.dw, c.dh) <= 0: return 2
    if c.dw * c.dh > 536870911: return 3
    return 0


class Writer:
    def __init__(self): self.data = bytearray(); self.marks = {}
    def mark(self, label): self.marks.setdefault(label, len(self.data))
    def word(self, value): self.data += struct.pack('<Q', value & MASK)
    def blob(self, value, label):
        if value: self.mark(label)
        self.data += value


def expected(cases, reference=resize_rgba):
    w = Writer(); counts = Counter(); w.word(MAGIC); w.word(len(cases)); related = {}
    for index, c in enumerate(cases):
        w.mark('case ordinal'); w.word(index)
        metadata, backing = source(c)
        w.mark('source metadata')
        for value in metadata: w.word(value)
        code = admission(c); w.mark('status'); w.word(code)
        if code:
            counts['rejected'] += 1
            w.blob(backing, 'rejected source guard')
        else:
            counts['admitted'] += 1; counts[NAMES[c.filter]] += 1
            counts['identity'] += (c.sw, c.sh) == (c.dw, c.dh)
            counts['cropped'] += c.cropped
            full = reference(c.pixels, c.sw, c.sh, c.dw, c.dh, c.filter)
            assert len(full) == 4 * c.dw * c.dh
            counts['output_pixels'] += c.dw * c.dh
            w.mark('result metadata')
            for value in (c.dw, c.dh, c.dw * 4, 0, len(full), 1): w.word(value)
            w.blob(full, 'RGBA output'); w.blob(backing, 'source preservation')
            w.blob(full, 'output after source edit')
            w.blob(bytes(x ^ 165 for x in backing), 'source after output edit')
            w.blob(bytes(x ^ 90 for x in full), 'edited independent output')
            if c.group: related[c.group] = (c, full)
        w.mark('source final metadata')
        for value in metadata: w.word(value)
    # No nearest reflection assertion: exact midpoint ties select right/down.
    for name, (c, full) in related.items():
        prefix, relation = name.rsplit(':', 1)
        if relation == 'base': continue
        base, before = related[prefix + ':base']
        want = transpose(before, base.dw, base.dh) if relation == 'transpose' else reflect(before, base.dw, base.dh, relation == 'vertical')
        assert full == want, ('metamorphic relation', name)
        counts['relations'] += 1
    w.word(END)
    return bytes(w.data), w.marks, counts


def packet(cases):
    data = bytearray(struct.pack('<2Q', MAGIC, len(cases)))
    for c in cases:
        values = (c.sw, c.sh, c.dw, c.dh, c.filter, c.layout, c.padding, c.cropped, c.invalid, len(c.pixels))
        data += struct.pack('<10Q', *(x & MASK for x in values)) + c.pixels
    return bytes(data)


def summary(cases, counts):
    fields = ('admitted', 'rejected', 'nearest', 'bilinear', 'area', 'identity', 'cropped', 'output_pixels', 'relations')
    return 'image-resize-model cases=%d ' % len(cases) + ' '.join('%s=%d' % (name, counts[name]) for name in fields) + ' layouts=2 seed=0x%x\n' % SEED


def verify(actual, wanted):
    if actual != wanted:
        offset = next((i for i, (a, b) in enumerate(zip(actual, wanted)) if a != b), min(len(actual), len(wanted)))
        raise AssertionError(('complete output mismatch', offset, len(actual), len(wanted), actual[offset:offset + 24].hex(), wanted[offset:offset + 24].hex()))


def rejected(label, actual, wanted):
    try: verify(actual, wanted)
    except AssertionError: return
    raise AssertionError('accepted corruption: ' + label)


def controls(cases):
    wanted, marks, counts = expected(cases)
    verify(wanted, wanted)
    rejected('truncated', wanted[:-1], wanted); rejected('trailing', wanted + b'\0', wanted)
    for name, offset in marks.items():
        bad = bytearray(wanted); bad[offset] ^= 1; rejected(name, bytes(bad), wanted)
    # Analytically constructed semantic alternatives regenerate complete result
    # observations for reached witnesses, including both independence snapshots.
    semantics = [
        ('row rounding', Case(2, 2, 1, 1, 2, 0, bytes((0, 0, 0, 255) * 3 + (1, 1, 1, 255))), bytes((1, 1, 1, 255))),
        ('truncate final tie', Case(2, 1, 1, 1, 1, 1, bytes((0, 0, 0, 255, 255, 255, 255, 255))), bytes((127, 127, 127, 255))),
        ('nearest lower tie', Case(2, 1, 1, 1, 0, 0, bytes((1, 2, 3, 4, 91, 92, 93, 94))), bytes((1, 2, 3, 4))),
        ('straight alpha average', Case(2, 1, 1, 1, 1, 0, bytes((255, 0, 0, 255, 0, 0, 255, 0))), bytes((128, 0, 128, 128))),
        ('rounded alpha denominator', Case(2, 1, 1, 1, 2, 0, bytes((255, 0, 0, 1, 0, 0, 255, 0))), bytes((128, 0, 0, 1))),
        ('discard positive alpha color', Case(3, 1, 1, 1, 2, 1, bytes((255, 0, 0, 1, 0, 255, 0, 0, 0, 0, 255, 0))), bytes(4)),
        ('identity hidden color loss', Case(1, 1, 1, 1, 1, 1, bytes((191, 37, 9, 0))), bytes(4)),
        ('corner coordinate', Case(2, 1, 3, 1, 1, 1, bytes((0, 0, 0, 255, 255, 255, 255, 255))), bytes((0, 0, 0, 255, 170, 170, 170, 255, 255, 255, 255, 255))),
    ]
    for name, case, alternative in semantics:
        baseline, _, _ = expected([case])
        bad, _, _ = expected([case], lambda *args: alternative)
        rejected(name, bad, baseline)
    assert resize_rgba(bytes((255, 0, 0, 1, 0, 0, 255, 0, 0, 255, 0, 0)), 3, 1, 1, 1, 'area') == bytes((255, 0, 0, 0))
    assert resize_rgba(bytes((0, 0, 255, 0, 255, 0, 0, 1)), 2, 1, 4, 1, 'bilinear') == bytes((0, 0, 0, 0, 255, 0, 0, 0, 255, 0, 0, 1, 255, 0, 0, 1))
    total = 2 + len(marks) + len(semantics)
    print(summary(cases, counts), end='')
    print('cpu-controls=%d rejected=%d bytes=%d' % (total, total, len(wanted)))


def main():
    cases = corpus()
    if len(sys.argv) == 2 and sys.argv[1] == 'controls':
        controls(cases); return
    assert len(sys.argv) == 2
    wanted, _, counts = expected(cases)
    run = subprocess.run([str(Path(sys.argv[1]).resolve())], input=packet(cases), stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE, timeout=75, check=False)
    assert run.returncode == 0, ('native status', run.returncode, run.stderr[:2048])
    assert not run.stderr, ('native stderr', run.stderr[:2048])
    verify(run.stdout, wanted)
    print(summary(cases, counts), end='')


if __name__ == '__main__':
    main()
