#!/usr/bin/env python3
"""Resolve a merge conflict in crates/laniusc-shaders/inlined_size_budget.txt.

usage (during a conflicted merge): tools/merge_inlined_budget.py

Each kernel keeps the lower of the two sides' limits; a kernel that either side
dropped (because it now fits the 40k default) stays dropped. No kernel is added.
"""
import subprocess

PATH = "crates/laniusc-shaders/inlined_size_budget.txt"


def load(rev):
    text = subprocess.run(["git", "show", f"{rev}:{PATH}"], capture_output=True, text=True, check=True).stdout
    header = [line for line in text.splitlines() if line.startswith("#")]
    limits = {}
    for line in text.splitlines():
        fields = line.split("#")[0].split()
        if len(fields) == 2:
            limits[fields[1]] = int(fields[0])
    return header, limits


base_rev = subprocess.run(["git", "merge-base", "HEAD", "MERGE_HEAD"], capture_output=True, text=True,
                          check=True).stdout.strip()
header, ours = load("HEAD")
_, theirs = load("MERGE_HEAD")
_, base = load(base_rev)
merged = {}
for key in set(ours) & set(theirs):
    merged[key] = min(ours[key], theirs[key])
lines = header + [f"{limit} {key}" for key, limit in sorted(merged.items(), key=lambda item: -item[1])]
open(PATH, "w").write("\n".join(lines) + "\n")
print(f"base {len(base)}, ours {len(ours)}, theirs {len(theirs)} -> {len(merged)} kernels")
