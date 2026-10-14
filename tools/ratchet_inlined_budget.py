#!/usr/bin/env python3
"""Lower crates/laniusc-shaders/inlined_size_budget.txt to the sizes of the last build.

usage: tools/ratchet_inlined_budget.py [--profile release|debug]

Reads target/laniusc-shader-artifacts/<profile>/inlined_sizes.txt (written by the
shader build) and rewrites each budget line to min(limit, measured size). Kernels
that now fit the 40k default lose their line. Limits never go up; a kernel that grew
past its limit fails the build before this script ever sees it.
"""
import argparse
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
BUDGET = ROOT / "crates/laniusc-shaders/inlined_size_budget.txt"
DEFAULT_LIMIT = 40_000

parser = argparse.ArgumentParser()
parser.add_argument("--profile", default="release")
args = parser.parse_args()

report = ROOT / "target/laniusc-shader-artifacts" / args.profile / "inlined_sizes.txt"
measured = {}
for line in report.read_text().splitlines():
    fields = line.split()
    if len(fields) == 4 and fields[0].isdigit():
        measured[fields[3]] = int(fields[0])

header, kept, dropped, lowered = [], [], [], 0
for line in BUDGET.read_text().splitlines():
    fields = line.split("#")[0].split()
    if len(fields) != 2:
        header.append(line)
        continue
    limit, key = int(fields[0]), fields[1]
    size = measured.get(key)
    if size is None or size <= DEFAULT_LIMIT:
        dropped.append(key)
        continue
    if size < limit:
        lowered += 1
    kept.append((min(limit, size), key))

kept.sort(reverse=True)
BUDGET.write_text("\n".join(header + [f"{limit} {key}" for limit, key in kept]) + "\n")
print(f"{len(kept)} kernels over {DEFAULT_LIMIT} ({lowered} lowered), {len(dropped)} now fit", file=sys.stderr)
for key in dropped:
    print(f"  fits: {key}", file=sys.stderr)
