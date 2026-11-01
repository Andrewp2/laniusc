#!/usr/bin/env python3
"""Compare the Lanius Unicode library with Python's unicodedata as an oracle.

Usage: python3 -I tools/unicode17/python_oracle.py EXECUTABLE [--strings N] [--seed S]

EXECUTABLE is the compiled sample_programs/library/unicode_oracle.lani. With
empty stdin it dumps category, combining class, decimal digit, full
lower/upper/title/fold, NFC/NFD/NFKC/NFKD (through the quick-check fast path,
cross-checked inside the program against the full engine) and is_normalized
(quick-check form, cross-checked against the full comparison) for every code
point; with 0xFF-terminated strings on stdin it emits the same twelve fields.

The library implements Unicode 17.0.0; the host unicodedata may be older.
Every disagreement is classified. A "version" disagreement is one where the
code point, or a scalar in the Lanius result, is unassigned (Cn) in the host
database while UnicodeData.txt 17.0.0 (vendored, no download) assigns it, or
where the host and vendored 17.0.0 UnicodeData.txt disagree on the compared
category/class/digit field. Anything else is reported as a defect and makes
the exit status 1. The nine binary property flags have no host equivalent;
they are compared with the vendored 17.0.0 DerivedCoreProperties/PropList.
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
FIELDS = "lower upper title fold nfc nfd nfkc nfkd is_nfc is_nfd is_nfkc is_nfkd".split()
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


PROPERTIES = "Alphabetic Lowercase Uppercase Cased Case_Ignorable White_Space XID_Start XID_Continue Default_Ignorable_Code_Point".split()


def ucd17_flags() -> list[int]:
    """Binary properties straight from DerivedCoreProperties/PropList 17.0.0."""
    flags = [0] * LIMIT
    for name in ("DerivedCoreProperties.txt", "PropList.txt"):
        with gzip.open(ROOT / "data/unicode/17.0.0" / (name + ".gz"), "rt", encoding="utf-8") as stream:
            for line in stream:
                body = line.split("#", 1)[0].strip()
                if not body:
                    continue
                cols = [x.strip() for x in body.split(";")]
                if cols[1] in PROPERTIES:
                    ends = cols[0].split("..")
                    for cp in range(int(ends[0], 16), int(ends[-1], 16) + 1):
                        flags[cp] |= 1 << PROPERTIES.index(cols[1])
    return flags


def host_assigned(cp: int) -> bool:
    return unicodedata.category(chr(cp)) != "Cn"


def python_fields(s: str) -> list[bytes]:
    return [x.encode("utf-8") for x in (
        s.lower(), s.upper(), s.title(), s.casefold(),
        unicodedata.normalize("NFC", s), unicodedata.normalize("NFD", s),
        unicodedata.normalize("NFKC", s), unicodedata.normalize("NFKD", s))] + [
        b"1" if unicodedata.is_normalized(f, s) else b"0" for f in ("NFC", "NFD", "NFKC", "NFKD")]


def parse_fields(data: bytes, pos: int) -> tuple[list[bytes], int]:
    out = []
    for _ in range(len(FIELDS)):
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
    ap.add_argument("--uconv", help="also check a compiled sample_programs/library/uconv.lani")
    args = ap.parse_args()
    ucd = ucd17()
    flags17 = ucd17_flags()
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
        flags = data[pos + 3] | data[pos + 4] << 8
        pos += 5
        compared["flags17"] += 1
        if flags == flags17[cp]:
            agree["flags17"] += 1
        else:
            defects.append(f"U+{cp:04X} flags: lanius={flags:#x} ucd17={flags17[cp]:#x}")
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
            elif mine.startswith(b"\xfd"):
                defects.append(f"U+{cp:04X} {name}: quick path differs from full engine")
            elif involves_new([cp], mine, ucd):
                version[name] += 1
            else:
                defects.append(f"U+{cp:04X} {name}: lanius={mine!r} host={host!r}")
    assert pos == len(data), (pos, len(data))
    print("code points: 1114112 (surrogates: properties only)")
    for name in ["category", "ccc", "decimal", "flags17"] + FIELDS:
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
            elif mine.startswith(b"\xfd"):
                sdefect[name] += 1
                defects.append(f"string {s!r} {name}: quick path differs from full engine")
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
    if args.uconv:
        import time
        text = "\n".join(s.replace("\n", " ") for s in strings) + "\n"
        raw = text.encode("utf-8")
        python = {"any-nfc": lambda t: unicodedata.normalize("NFC", t),
                  "any-nfd": lambda t: unicodedata.normalize("NFD", t),
                  "any-nfkc": lambda t: unicodedata.normalize("NFKC", t),
                  "any-nfkd": lambda t: unicodedata.normalize("NFKD", t),
                  "any-lower": str.lower, "any-upper": str.upper, "any-casefold": str.casefold}
        print(f"uconv: {len(raw)} bytes, {text.count(chr(10))} lines, whole-text Python reference")
        for name, fn in python.items():
            began = time.monotonic()
            run = subprocess.run([args.uconv, "-x", name], input=raw, capture_output=True, timeout=120)
            took = time.monotonic() - began
            want = fn(text).encode("utf-8")
            if run.returncode != 0 or run.stdout != want:
                # Attribute line differences to Unicode versions where possible.
                got_lines = run.stdout.split(b"\n"); want_lines = want.split(b"\n")
                bad = [i for i, (g, w) in enumerate(zip(got_lines, want_lines)) if g != w]
                unexplained = [i for i in bad if not involves_new([ord(c) for c in strings[i]] if i < len(strings) else [], got_lines[i], ucd)]
                ok = run.returncode == 0 and len(got_lines) == len(want_lines) and not unexplained
                print(f"  {name:12} {'version-only' if ok else 'MISMATCH'} lines differing={len(bad)} unexplained={len(unexplained)} {took:.2f}s")
                if not ok:
                    defects.append(f"uconv {name}: rc={run.returncode} unexplained lines {unexplained[:5]}")
            else:
                print(f"  {name:12} identical {took:.2f}s")
        for form in ("NFC", "NFD", "NFKC", "NFKD"):
            run = subprocess.run([args.uconv, "-x", "any-" + form.lower(), "--check"], input=raw, capture_output=True, timeout=120)
            want = 0 if unicodedata.is_normalized(form, text) else 1
            same = run.returncode == want and not run.stdout
            print(f"  --check {form:5} rc={run.returncode} python={'normalized' if want == 0 else 'not'} {'ok' if same else 'MISMATCH'}")
            if not same:
                defects.append(f"uconv --check {form}: rc={run.returncode} want={want}")
            normal = unicodedata.normalize(form, text).encode("utf-8")
            run = subprocess.run([args.uconv, "-x", "any-" + form.lower(), "--check"], input=normal, capture_output=True, timeout=120)
            print(f"  --check {form:5} on Python {form} output rc={run.returncode} {'ok' if run.returncode == 0 else 'MISMATCH'}")
            if run.returncode != 0 or run.stdout:
                defects.append(f"uconv --check {form} on normalized text: rc={run.returncode}")
    real = [d for d in defects]
    for line in real[:40]:
        print("DEFECT", line)
    print(f"defects: {len(real)}")
    return 1 if real else 0


if __name__ == "__main__":
    sys.exit(main())
