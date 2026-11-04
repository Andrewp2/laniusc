#!/usr/bin/env python3
"""Differential mutation test: mutate words of a certificate, compare the
Lanius checker's verdict with certlib.check's.  mutate.py CHECKER CERT N SEED"""
import random, struct, subprocess, sys
sys.path.insert(0, __import__('os').path.dirname(__file__))
import certlib
checker, path, n, seed = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
w = certlib.read(path)
rng = random.Random(seed)
agree = rejected = 0
for t in range(n):
    m = w.__copy__()
    i = rng.randrange(8, len(m))
    old = m[i]
    m[i] = rng.choice([old + 1, max(old - 1, 0), rng.randrange(0, 64), rng.randrange(0, 1 << 31), 0x7FFFFFFF])
    try:
        ref = certlib.check(m)
    except (AssertionError, IndexError):
        ref = False
    got = subprocess.run([checker], input=m.tobytes(), capture_output=True).returncode
    if (got == 0) == bool(ref) and got in (0, 1):
        agree += 1
    else:
        print('DISAGREE at word', i, old, '->', m[i], 'ref', ref, 'lanius rc', got)
    rejected += got != 0
print(f'mutants {n}, agree {agree}, rejected {rejected}')
