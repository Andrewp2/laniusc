#!/usr/bin/env python3
"""Derive the UTS #46 IDNA mapping table from the vendored Unicode 17 UCD.

UTS #46 section 6 derives IdnaMappingTable.txt from UCD properties; this
program applies that derivation (base mapping from NFKC_Casefold with the
label-separator, Bidi_Control and U+1E9E exceptions; the base valid set; the
exclusion and deviation sets; then the iterated status closure) and writes
extended/ext/idna_data.lani with each code point's status, Bidi_Class and
mapping. No host Unicode database or IDNA library is used. The production
IDNA processing is in extended/ext/url.lani.
"""
import argparse
import gzip
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
UCD = ROOT / "data/unicode/17.0.0"
TARGET = ROOT / "extended/ext/idna_data.lani"
BIDI = "L R AL EN ES ET AN CS NSM BN B S WS ON LRE LRO RLE RLO PDF LRI RLI FSI PDI".split()
VALID, MAPPED, IGNORED, DEVIATION, DISALLOWED = range(5)
SEPARATORS = (0xFF0E, 0x3002, 0xFF61)
DEVIATIONS = (0x200C, 0x200D, 0x00DF, 0x03C2)
PER_CHUNK = 720


def read(name):
    manifest = json.loads((UCD / "manifest.json").read_text())
    assert manifest["unicode_version"] == "17.0.0"
    record = next(x for x in manifest["files"] if x["file"] == name + ".gz")
    compressed = (UCD / record["file"]).read_bytes()
    assert hashlib.sha256(compressed).hexdigest() == record["gzip_sha256"]
    original = gzip.decompress(compressed)
    assert len(original) == record["bytes"]
    assert hashlib.sha256(original).hexdigest() == record["sha256"]
    return original.decode("utf-8")


def entries(text):
    for raw in text.splitlines():
        line = raw.split("#", 1)[0].strip()
        if line:
            fields = [x.strip() for x in line.split(";")]
            bounds = fields[0].split("..")
            yield range(int(bounds[0], 16), int(bounds[-1], 16) + 1), fields[1:]


def prop(text, name):
    return {cp for span, fields in entries(text) if fields[0] == name for cp in span}


def unicode_data():
    category, bidi = {}, {}
    first = None
    for line in read("UnicodeData.txt").splitlines():
        fields = line.split(";")
        cp = int(fields[0], 16)
        if fields[1].endswith(", First>"):
            first = cp
            continue
        span = range(first, cp + 1) if fields[1].endswith(", Last>") else range(cp, cp + 1)
        for x in span:
            category[x], bidi[x] = fields[2], fields[4]
    return category, bidi


def derive():
    category, bidi = unicode_data()
    normalization = read("DerivedNormalizationProps.txt")
    casefold = {}
    for span, fields in entries(normalization):
        if fields[0] == "NFKC_CF":
            value = tuple(int(x, 16) for x in fields[1].split()) if fields[1] else ()
            for cp in span:
                casefold[cp] = value
    changes = prop(normalization, "Changes_When_NFKC_Casefolded")
    props = read("PropList.txt")
    bidi_control = prop(props, "Bidi_Control")
    ids = prop(props, "IDS_Unary_Operator") | prop(props, "IDS_Binary_Operator") | prop(props, "IDS_Trinary_Operator")
    assert bidi_control and ids

    def base(cp):
        if cp in SEPARATORS:
            return (0x2E,)
        if cp in bidi_control:
            return (cp,)
        if cp == 0x1E9E:
            return (0xDF,)
        return casefold.get(cp, (cp,))

    every = range(0x110000)
    valid_base = {cp for cp in every if cp not in changes}
    valid_base.add(0xDF)
    valid_base -= {cp for cp in every if category.get(cp, "Cn")[0] in "CZ"}
    valid_base -= ids
    valid_base |= set(range(0x80)) - {0x2E}
    # FULL STOP is a label separator, not a valid label character, so scalars
    # whose mapping contains one (U+2024, U+2488, ...) are disallowed.
    valid_base.discard(0x2E)
    excluded = {0xFFFC, 0xFFFD} | set(range(0xE0001, 0xE0080))
    status, mapping = [DISALLOWED] * 0x110000, [()] * 0x110000
    for cp in every:
        value = base(cp)
        if cp in DEVIATIONS:
            status[cp] = DEVIATION
        elif cp in excluded or category.get(cp, "Cn") == "Cn":
            status[cp] = DISALLOWED
        elif cp not in (0x2E,) + SEPARATORS and any(x not in valid_base for x in value):
            status[cp] = DISALLOWED
        elif not value:
            status[cp] = IGNORED
        elif value == (cp,):
            status[cp] = VALID
        else:
            status[cp], mapping[cp] = MAPPED, value
    changed = True
    while changed:
        changed = False
        allowed = {cp for cp in every if status[cp] in (VALID, DEVIATION)}
        for cp in every:
            if status[cp] == MAPPED and any(x not in allowed for x in mapping[cp]):
                status[cp], mapping[cp], changed = DISALLOWED, (), True
    return status, mapping, bidi


def records(status, mapping, bidi):
    """Ranges of equal status and Bidi_Class whose single-scalar mappings
    advance with the code point. Sequence mappings get a range each."""
    pool, out = [], []
    for cp in range(0x110000):
        s = status[cp]
        b = BIDI.index(bidi.get(cp, "L")) if s in (VALID, DEVIATION) else 0
        if s == MAPPED and len(mapping[cp]) > 1:
            assert len(mapping[cp]) <= 255
            out.append([cp, s, b, len(pool), len(mapping[cp])])
            pool.extend(mapping[cp])
            continue
        target = mapping[cp][0] if s == MAPPED else 0
        length = 1 if s == MAPPED else 0
        if out:
            last = out[-1]
            if last[1] == s and last[2] == b and last[4] == length and (s != MAPPED or last[3] + cp - last[0] == target):
                continue
        out.append([cp, s, b, target, 1 if s == MAPPED else 0])
    return out, pool


def dispatch(name, text, width):
    size = PER_CHUNK * width
    parts = [text[i:i + size] for i in range(0, len(text), size)] or [""]
    lines = [f"// {len(text) // width} records of {width} hex digits.", f"fn {name}_chunk(index: i32) -> [u8] {{"]
    for number, part in enumerate(parts):
        lines.append(f"    if (index == {number}) {{ let text: str = \"{part}\"; "
                     f"return core::mem::typed_slice_from_raw_parts(core::mem::string_data_ptr(text), {len(part)}); }}")
    lines.append(f"    let empty: str = \"\"; return core::mem::typed_slice_from_raw_parts(core::mem::string_data_ptr(empty), 0);")
    lines.append("}")
    lines.append(f"fn {name}(record: i32, at: i32, width: i32) -> u32 {{ return number({name}_chunk(record / {PER_CHUNK}), (record % {PER_CHUNK}) * {width} + at, width); }}")
    return lines


def generate():
    status, mapping, bidi = derive()
    out, pool = records(status, mapping, bidi)
    table = "".join("%06X%X%02X%06X%02X" % (start, s, b, value, length) for start, s, b, value, length in out)
    data = "".join("%06X" % x for x in pool)
    counts = [status.count(k) for k in range(5)]
    lines = [
        "// Generated by tools/unicode17/generate_idna.py; do not edit.",
        "// UTS #46 section 6 derivation over the Unicode Character Database 17.0.0,",
        "// https://www.unicode.org/Public/17.0.0/ucd/",
        "// Copyright (c) 1991-2025 Unicode, Inc. Unicode and the Unicode Logo are",
        "// registered trademarks of Unicode, Inc. in the U.S. and other countries.",
        "// Distributed under the Unicode License v3; see data/unicode/17.0.0/LICENSE.txt.",
        f"// Status counts: valid {counts[0]}, mapped {counts[1]}, ignored {counts[2]}, deviation {counts[3]}, disallowed {counts[4]}.",
        "// A record is start (6), status (1: 0 valid, 1 mapped, 2 ignored, 3 deviation,",
        "// 4 disallowed), Bidi_Class (2, index into " + " ".join(BIDI) + "),",
        "// value (6) and length (2). Mapped length 1: the scalar maps to value plus its",
        "// offset from start. Longer: value indexes length scalars in the pool.",
        "module ext::idna_data;",
        "import core::mem;",
        "",
        "fn number(data: [u8], at: i32, width: i32) -> u32 {",
        "    let value: u32 = 0; let index: i32 = 0;",
        "    while (index < width) {",
        "        let byte: u8 = data[at + index]; let digit: u32 = (byte - 48) as u32;",
        "        if (byte >= 65) { digit = (byte - 55) as u32; }",
        "        value = value * 16 + digit; index += 1;",
        "    }",
        "    return value;",
        "}",
    ]
    lines += dispatch("table", table, 17)
    lines += dispatch("pool", data, 6)
    lines += [
        f"pub const RECORDS: i32 = {len(out)};",
        f"pub const POOL: i32 = {len(pool)};",
        "// The record covering value (precondition: value <= 0x10FFFF).",
        "pub fn find(value: u32) -> i32 {",
        "    let low: i32 = 0; let high: i32 = RECORDS - 1;",
        "    while (low < high) {",
        "        let middle: i32 = (low + high + 1) / 2;",
        "        if (table(middle, 0, 6) <= value) { low = middle; } else { high = middle - 1; }",
        "    }",
        "    return low;",
        "}",
        "pub fn start(record: i32) -> u32 { return table(record, 0, 6); }",
        "pub fn status(record: i32) -> u32 { return table(record, 6, 1); }",
        "pub fn bidi(record: i32) -> u32 { return table(record, 7, 2); }",
        "pub fn value(record: i32) -> u32 { return table(record, 9, 6); }",
        "pub fn length(record: i32) -> u32 { return table(record, 15, 2); }",
        "pub fn pooled(index: i32) -> u32 { return pool(index, 0, 6); }",
        "",
    ]
    return "\n".join(lines), status, mapping, bidi


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--dump", help="write 'cp status mapping' lines for verification")
    args = parser.parse_args()
    source, status, mapping, bidi = generate()
    if args.dump:
        with open(args.dump, "w") as handle:
            for cp in range(0x110000):
                handle.write("%X %d %s\n" % (cp, status[cp], " ".join("%X" % x for x in mapping[cp])))
    if args.check:
        assert TARGET.read_text() == source, f"stale generated table: {TARGET}"
    elif not args.dump:
        TARGET.write_text(source)
