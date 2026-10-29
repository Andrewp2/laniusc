"""Focused native decode comparison; invokes a supplied compress_bytes executable.

Run from the repository root with EXECUTABLE LABEL. This is a test/measurement
harness; system zlib only generates independent compressed inputs.
"""
from pathlib import Path
import hashlib
import json
import os
import random
import statistics
import subprocess
import sys
import time
import zlib

exe, label = sys.argv[1:]
root = Path('target/stdlib-work/inflate-stream-native-compare')
root.mkdir(parents=True, exist_ok=True)
cpu = min(os.sched_getaffinity(0))
os.sched_setaffinity(0, {cpu})
block = bytes(range(256)) + b'entry,id,value\nexample,123,456\n'
size = 1048576
values = {'repeated': (block * ((size + len(block) - 1) // len(block)))[:size],
          'random': random.Random(0x1F1A7E2026).randbytes(size)}
rows = []
started = time.monotonic()
for name, expected in values.items():
    for format, window in [('raw', -15), ('zlib', 15), ('gzip', 31)]:
        encoder = zlib.compressobj(6, zlib.DEFLATED, window)
        encoded = encoder.compress(expected) + encoder.flush()
        assert zlib.decompress(encoded, window) == expected
        times = []
        for run in range(4):
            assert time.monotonic() - started < 80
            before = time.perf_counter()
            actual = subprocess.run([exe, '-d', '--format', format], input=encoded,
                                    capture_output=True, timeout=12, check=False)
            elapsed = time.perf_counter() - before
            assert actual.returncode == 0 and actual.stderr == b'' and actual.stdout == expected, (
                label, name, format, actual.returncode, actual.stderr, len(actual.stdout))
            if run:
                times.append(elapsed)
        row = dict(corpus=name, format=format, input=len(encoded), output=len(expected),
                   sha256=hashlib.sha256(expected).hexdigest(), seconds=times,
                   median=statistics.median(times), minimum=min(times), maximum=max(times))
        rows.append(row)
        print(f'{label} {name} {format}: {len(encoded)} -> {len(expected)}, '
              f'median={row["median"]:.6f}s range={min(times):.6f}..{max(times):.6f}s', flush=True)
report = dict(label=label, cpu=cpu, executable=str(Path(exe).resolve()),
              executable_sha256=hashlib.sha256(Path(exe).read_bytes()).hexdigest(),
              warmups=1, samples=3, rows=rows)
(root / (label + '.json')).write_text(json.dumps(report, indent=2) + '\n')
print(f'cpu={cpu}; verified six workloads, each one warmup and three timed native processes')
