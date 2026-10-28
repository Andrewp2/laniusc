#!/usr/bin/env python3
"""Run each M0 benchmark binary N times; print min and median wall time,
peak RSS and the checksum line.

usage: run_bench.py DIR N NAME...

DIR holds binaries built from src/:
    laniusc --stdlib-root stdlib --emit x86_64 src/NAME.lani -o DIR/NAME
"""
import os, statistics, subprocess, sys, time
d, n, names = sys.argv[1], int(sys.argv[2]), sys.argv[3:]
print('benchmark\tmin_s\tmedian_s\tpeak_rss_kb\tchecksum')
for name in names:
    times, rss, out = [], 0, None
    for _ in range(n):
        start = time.perf_counter()
        stdout = subprocess.run([os.path.join(d, name)], stdout=subprocess.PIPE, check=True).stdout
        times.append(time.perf_counter() - start)
        out = stdout.decode().strip()
    # Peak RSS of one more run, measured alone.
    timed = subprocess.run(['/usr/bin/time', '-f', '%M', os.path.join(d, name)], stdout=subprocess.DEVNULL,
                           stderr=subprocess.PIPE, text=True)
    rss = int(timed.stderr.strip().split()[-1])
    print(f'{name}\t{min(times):.3f}\t{statistics.median(times):.3f}\t{rss}\t{out}')
