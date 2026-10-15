#!/usr/bin/env python3
"""Resolve merge conflicts in the kernel budget files.

usage (during a conflicted merge): tools/merge_inlined_budget.py

Rewrites crates/laniusc-shaders/inlined_size_budget.txt and
crates/laniusc-shaders/local_array_budget.txt. Each kernel keeps the lower of
the two sides' limits; a kernel that either side dropped (because it now fits
the default) stays dropped. No kernel is added. A side that has no such file
yet takes the other side's.
"""
import subprocess

PATHS = ("crates/laniusc-shaders/inlined_size_budget.txt", "crates/laniusc-shaders/local_array_budget.txt")


def load(rev, path):
    shown = subprocess.run(["git", "show", f"{rev}:{path}"], capture_output=True, text=True)
    if shown.returncode != 0:
        return None
    header = [line for line in shown.stdout.splitlines() if line.startswith("#")]
    limits = {}
    for line in shown.stdout.splitlines():
        fields = line.split("#")[0].split()
        if len(fields) == 2:
            limits[fields[1]] = int(fields[0])
    return header, limits


for path in PATHS:
    ours, theirs = load("HEAD", path), load("MERGE_HEAD", path)
    if ours is None and theirs is None:
        continue
    header = (ours or theirs)[0]
    ours = ours[1] if ours else theirs[1]
    theirs = theirs[1] if theirs else ours
    merged = {key: min(ours[key], theirs[key]) for key in set(ours) & set(theirs)}
    lines = header + [f"{limit} {key}" for key, limit in sorted(merged.items(), key=lambda item: (-item[1], item[0]))]
    open(path, "w").write("\n".join(lines) + "\n")
    print(f"{path}: ours {len(ours)}, theirs {len(theirs)} -> {len(merged)} kernels")
