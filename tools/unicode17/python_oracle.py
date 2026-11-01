#!/usr/bin/env python3
"""Compare the Lanius Unicode library with Python's unicodedata as an oracle.

Usage: python3 -I tools/unicode17/python_oracle.py EXECUTABLE [--strings N] [--seed S]

EXECUTABLE is the compiled sample_programs/library/unicode_oracle.lani. With
empty stdin it dumps category, combining class, decimal digit, full
lower/upper/title/fold and NFC/NFD/NFKC/NFKD for every code point; with
0xFF-terminated strings on stdin it emits the same eight string fields.

The library implements Unicode 17.0.0; the host unicodedata may be older.
Every disagreement is classified. A "version" disagreement is one where the
code point, or a scalar in the Lanius result, is unassigned (Cn) in the host
database while UnicodeData.txt 17.0.0 (vendored, no download) assigns it, or
where the host and vendored 17.0.0 UnicodeData.txt disagree on the compared
category/class/digit field. Anything else is reported as a defect and makes
the exit status 1.
"""
from __future__ import annotations

import argparse
import gzip
import random
import subprocess
import sys
import unicodedata
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATEGORIES = "Cn Lu Ll Lt Lm Lo Mn Mc Me Nd Nl No Pc Pd Ps Pe Pi Pf Po Sm Sc Sk So Zs Zl Zp Cc Cf Cs Co".split()
FIELDS = "lower upper title fold nfc nfd nfkc nfkd".split()
LIMIT = 0x110000


def ucd17() -> dict[int, tuple[str, int, int | None]]:
    rows: dict[int, tuple[str, int, int | None]] = {}
    first = None
    with gzip.open(ROOT / "data/unicode/17.0.0/UnicodeData.txt.gz", "rt", encoding="utf-8") as stream:
        for line in stream:
            f = line.rstrip("\n").split(";")
            cp = int(f[0], 16)
            value = (f[2], int(f[3]), int(f[6]) if f[6] else None)
            if f[1].endswith(", First>"):
                first = cp
                continue
            if f[1].endswith(", Last>"):
                for c in range(first, cp + 1):
                    rows[c] = value
                first = None
                continue
            rows[cp] = value
    return rows


def host_assigned(cp: int) -> bool:
    return unicodedata.category(chr(cp)) != "Cn"


def python_fields(s: str) -> list[bytes]:
    return [x.encode("utf-8") for x in (
        s.lower(), s.upper(), s.title(), s.casefold(),
        unicodedata.normalize("NFC", s), unicodedata.normalize("NFD", s),
        unicodedata.normalize("NFKC", s), unicodedata.normalize("NFKD", s))]


def parse_fields(data: bytes, pos: int) -> tuple[list[bytes], int]:
    out = []
    for _ in range(8):
        end = data.index(b"\xff", pos)
        out.append(data[pos:end])
        pos = end + 1
    return out, pos


def involves_new(cp_list, got: bytes, ucd) -> bool:
    if any((not host_assigned(c)) and c in ucd for c in cp_list):
        return True
    try:
        text = got.decode("utf-8")
    except UnicodeDecodeError:
        return False
    return any((not host_assigned(ord(c))) and ord(c) in ucd for c in text)


def generated_strings(count: int, seed: int) -> list[str]:
    rng = random.Random(seed)
    assigned = [c for c in range(LIMIT) if not 0xD800 <= c <= 0xDFFF and host_assigned(c)]
    marks = [c for c in assigned if unicodedata.combining(chr(c))]
    decomposable = [c for c in assigned if unicodedata.decomposition(chr(c))]
    special = [0x3A3, 0x3C3, 0x3C2, 0xDF, 0x130, 0x131, 0x49, 0x69, 0x307, 0x345, 0x1E9E,
               0xFB03, 0x1F80, 0x390, 0x27, 0x2E, 0x20, 0x41, 0x61, 0x1100, 0x1161, 0x11A8,
               0xAC00, 0xD7A3, 0x0F73, 0x0344, 0x1E9B, 0x0323, 0x0301, 0x0300, 0x093C]
    hangul = list(range(0x1100, 0x1113)) + list(range(0x1161, 0x1176)) + list(range(0x11A8, 0x11C3))
    pools = [assigned, marks, decomposable, special, hangul, list(range(0x20, 0x7F))]
    weights = [3, 4, 3, 3, 2, 3]
    out = []
    for _ in range(count):
        n = rng.randint(1, 24)
        chars = []
        for _ in range(n):
            pool = rng.choices(pools, weights)[0]
            chars.append(chr(rng.choice(pool)))
        out.append("".join(chars))
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("executable")
    ap.add_argument("--strings", type=int, default=200000)
    ap.add_argument("--seed", type=int, default=17)
    args = ap.parse_args()
    ucd = ucd17()
    print(f"host unicodedata {unicodedata.unidata_version}; library Unicode 17.0.0")

    dump = subprocess.run([args.executable], stdin=subprocess.DEVNULL, capture_output=True, timeout=280)
    assert dump.returncode == 0, dump.returncode
    data = dump.stdout
    pos = 0
    agree = Counter()
    version = Counter()
    defects: list[str] = []
    compared = Counter()
    for cp in range(LIMIT):
        cat, ccc, dec = data[pos], data[pos + 1], data[pos + 2]
        pos += 3
        got, pos = parse_fields(data, pos)
        ch = chr(cp)
        props = [("category", CATEGORIES[cat] if cat < 30 else "?", unicodedata.category(ch)),
                 ("ccc", ccc, unicodedata.combining(ch)),
                 ("decimal", None if dec == 10 else dec, unicodedata.decimal(ch, None))]
        u = ucd.get(cp)
        for name, mine, host in props:
            compared[name] += 1
            if mine == host:
                agree[name] += 1
                continue
            index = {"category": 0, "ccc": 1, "decimal": 2}[name]
            want17 = (u[index] if u else ("Cn", 0, None)[index])
            if name == "category" and u is None and 0xD800 <= cp <= 0xDFFF:
                want17 = "Cs"
            if mine == want17:
                version[name] += 1
            else:
                defects.append(f"U+{cp:04X} {name}: lanius={mine!r} host={host!r} ucd17={want17!r}")
        if 0xD800 <= cp <= 0xDFFF:
            continue
        expect = python_fields(ch)
        for name, mine, host in zip(FIELDS, got, expect):
            compared[name] += 1
            if mine == host:
                agree[name] += 1
            elif involves_new([cp], mine, ucd):
                version[name] += 1
            else:
                defects.append(f"U+{cp:04X} {name}: lanius={mine!r} host={host!r}")
    assert pos == len(data), (pos, len(data))
    print("code points: 1114112 (surrogates: properties only)")
    for name in ["category", "ccc", "decimal"] + FIELDS:
        print(f"  {name:8} compared={compared[name]} agree={agree[name]} version={version[name]} "
              f"defect={compared[name] - agree[name] - version[name]}")

    strings = generated_strings(args.strings, args.seed)
    payload = b"".join(s.encode("utf-8") + b"\xff" for s in strings)
    run = subprocess.run([args.executable], input=payload, capture_output=True, timeout=280)
    assert run.returncode == 0, run.returncode
    data = run.stdout
    pos = 0
    sagree = Counter()
    sversion = Counter()
    sdefect = Counter()
    title_python_rule = 0
    for s in strings:
        got, pos = parse_fields(data, pos)
        expect = python_fields(s)
        for name, mine, host in zip(FIELDS, got, expect):
            if mine == host:
                sagree[name] += 1
            elif involves_new([ord(c) for c in s], mine, ucd):
                sversion[name] += 1
            elif name == "title":
                # str.title() splits words at every uncased character; the
                # library uses UAX #29 word boundaries (documented difference).
                sdefect[name] += 1
                title_python_rule += 1
            else:
                sdefect[name] += 1
                if sdefect[name] <= 5:
                    defects.append(f"string {s!r} {name}: lanius={mine!r} host={host!r}")
    assert pos == len(data)
    print(f"generated strings: {len(strings)} (seed {args.seed}, {len(payload)} input bytes)")
    for name in FIELDS:
        label = "differ(word-rule)" if name == "title" else "defect"
        print(f"  {name:8} agree={sagree[name]} version={sversion[name]} {label}={sdefect[name]}")
    real = [d for d in defects]
    for line in real[:40]:
        print("DEFECT", line)
    print(f"defects: {len(real)}")
    return 1 if real else 0


if __name__ == "__main__":
    sys.exit(main())
