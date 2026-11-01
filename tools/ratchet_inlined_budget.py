#!/usr/bin/env python3
"""Lower the kernel budgets to the figures of the last shader build.

usage: tools/ratchet_inlined_budget.py [--profile release|debug]

Reads target/laniusc-shader-artifacts/<profile>/inlined_sizes.txt (written by the
shader build) and rewrites each line of both budget files to min(limit, measured):

- crates/laniusc-shaders/inlined_size_budget.txt: fully inlined instructions.
  Kernels that now fit the 40k default lose their line, except headroom lines
  (a limit under the default, kept for a kernel that was split to make room).
- crates/laniusc-shaders/local_array_budget.txt: per-thread local array bytes.
  Kernels that now have no local arrays (the default, 0) lose their line.

Limits never go up and no kernel is added (a headroom line is added by hand); a kernel that grew past its limit
fails the build before this script ever sees it.
"""
import argparse
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
BUDGETS = (
    # (file, column of inlined_sizes.txt, default limit, what)
    (ROOT / "crates/laniusc-shaders/inlined_size_budget.txt", 0, 40_000, "fully inlined instructions"),
    (ROOT / "crates/laniusc-shaders/local_array_budget.txt", 3, 0, "local array bytes"),
)

parser = argparse.ArgumentParser()
parser.add_argument("--profile", default="release")
args = parser.parse_args()

report = ROOT / "target/laniusc-shader-artifacts" / args.profile / "inlined_sizes.txt"
rows = {}
for line in report.read_text().splitlines():
    fields = line.split()
    # inlined own limit local llimit kernel
    if len(fields) == 6 and fields[0].isdigit():
        rows[fields[5]] = [int(field) for field in fields[:5]]
if not rows:
    sys.exit(f"{report} has no six-column rows; rebuild the shaders first")

for budget, column, default, what in BUDGETS:
    header, kept, dropped, lowered = [], [], [], 0
    for line in budget.read_text().splitlines():
        fields = line.split("#")[0].split()
        if len(fields) != 2:
            header.append(line)
            continue
        limit, key = int(fields[0]), fields[1]
        measured = rows.get(key, [None] * 5)[column]
        # A line under the default caps a kernel that was split to make
        # room; it stays. A line over the default goes once the kernel fits.
        if measured is None or (measured <= default and limit > default):
            dropped.append(key)
            continue
        if measured < limit:
            lowered += 1
        kept.append((min(limit, measured), key))
    kept.sort(key=lambda item: (-item[0], item[1]))
    budget.write_text("\n".join(header + [f"{limit} {key}" for limit, key in kept]) + "\n")
    print(f"{budget.name}: {len(kept)} kernels over {default} {what} ({lowered} lowered), "
          f"{len(dropped)} now fit", file=sys.stderr)
    for key in dropped:
        print(f"  fits: {key}", file=sys.stderr)
