#!/usr/bin/env python3
"""Test-only OS oracle for directory-report; no production code is imported."""
import os
import stat
import sys

root = os.fsencode(sys.argv[1])
depth = int(sys.argv[2]) if len(sys.argv) > 2 else 64
prefix = bytes.fromhex(sys.argv[3]) if len(sys.argv) > 3 else b""
suffix = bytes.fromhex(sys.argv[4]) if len(sys.argv) > 4 else b""
wanted = sys.argv[5] if len(sys.argv) > 5 else "all"

def kind(mode):
    for predicate, name in ((stat.S_ISREG, "file"), (stat.S_ISDIR, "directory"),
                            (stat.S_ISLNK, "symlink"), (stat.S_ISFIFO, "fifo"),
                            (stat.S_ISSOCK, "socket"), (stat.S_ISCHR, "character"),
                            (stat.S_ISBLK, "block")):
        if predicate(mode):
            return name
    return "unknown"

rows = []
if depth:
    for current, directories, files in os.walk(root, followlinks=False):
        relative = os.path.relpath(current, root)
        components = [] if relative == b"." else relative.split(b"/")
        current_depth = len(components)
        if current_depth >= depth:
            directories[:] = []
            continue
        for name in directories + files:
            metadata = os.stat(os.path.join(current, name), follow_symlinks=False)
            category = kind(metadata.st_mode)
            if name.startswith(prefix) and name.endswith(suffix) and (wanted == "all" or category == wanted):
                path = b"/".join(components + [name])
                seconds, nanos = divmod(metadata.st_mtime_ns, 1_000_000_000)
                rows.append((path, category, current_depth + 1, metadata.st_size,
                             metadata.st_mode, metadata.st_ino, seconds, nanos))
        if current_depth + 1 >= depth:
            directories[:] = []
print("path_hex\tkind\tdepth\tsize\tmode\tinode\tmtime_sec\tmtime_nsec")
for row in sorted(rows):
    path, category, level, size, mode, inode, seconds, nanos = row
    print(f"{path.hex()}\t{category}\t{level}\t{size}\t{mode:o}\t{inode}\t{seconds}\t{nanos}")
