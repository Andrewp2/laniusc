"""Python `sorted` reference for core::slice pdqsort, the core::slice stable
run-adaptive merge sort and alloc::slice::sort_by.

Unstable output must equal sorted(keys). Stable outputs are the original
indices and must equal sorted(range(n), key=keys.__getitem__), which Python
guarantees stable. Comparator calls are recorded per algorithm and pattern
next to Python's own comparison count for the same input (a key wrapper that
counts __lt__). Structural bounds are checked: the stable sort makes exactly
n-1 comparisons on sorted and strictly descending input, and every sort stays
within 2 n log2 n + 2 n comparisons. McIlroy's adversary drives pdqsort; its
count must stay within 4 n log2 n + 2 n, which only the heapsort fallback
guarantees (a quadratic sort would make about n^2/2 calls).
"""
from __future__ import annotations

import math
import random
import struct
import subprocess
import sys

SEED = 0x5027_2026_1031
MASK = (1 << 64) - 1
ALGORITHMS = {0: "pdq", 1: "stable", 2: "alloc_merge"}


def fail(message):
    raise SystemExit(f"sort-algorithms-model: {message}")


class Counted:
    calls = 0
    __slots__ = ("key",)

    def __init__(self, key):
        self.key = key

    def __lt__(self, other):
        Counted.calls += 1
        return self.key < other.key


def python_comparisons(keys):
    Counted.calls = 0
    sorted(Counted(k) for k in keys)
    return Counted.calls


def median_of_three_killer(n):
    # Musser's sequence that defeats plain median-of-3 quicksort.
    k = n // 2
    keys = [0] * n
    for i in range(1, k + 1):
        if i % 2:
            keys[i - 1] = i
            keys[i] = k + i
        keys[k + i - 1] = 2 * i
    return keys[:n]


def pattern(name, n, rng):
    if n == 0:
        return []
    if name == "random":
        return [rng.getrandbits(64) for _ in range(n)]
    if name == "dup2":
        return [rng.randrange(2) for _ in range(n)]
    if name == "dup16":
        return [rng.randrange(16) for _ in range(n)]
    if name == "sqrt_distinct":
        return [rng.randrange(max(1, int(math.isqrt(n)))) for _ in range(n)]
    if name == "sorted":
        return sorted(rng.getrandbits(32) for _ in range(n))
    if name == "reversed":
        return sorted((rng.getrandbits(32) for _ in range(n)), reverse=True)
    if name == "strict_descending":
        return list(range(n, 0, -1))
    if name == "descending_dups":
        return sorted((rng.randrange(max(1, n // 4)) for _ in range(n)), reverse=True)
    if name == "equal":
        return [7] * n
    if name == "organ_pipe":
        half = n // 2
        return list(range(half)) + list(range(n - half, 0, -1))
    if name == "sawtooth":
        width = max(1, rng.choice([3, 16, 100]))
        return [i % width for i in range(n)]
    if name == "reverse_sawtooth":
        width = max(1, rng.choice([3, 16, 100]))
        return [width - i % width for i in range(n)]
    if name == "few_swaps":
        keys = list(range(n))
        for _ in range(max(1, n // 100)):
            a, b = rng.randrange(n), rng.randrange(n)
            keys[a], keys[b] = keys[b], keys[a]
        return keys
    if name == "sorted_tail":
        keys = list(range(n))
        tail = max(1, n // 20)
        keys[n - tail:] = [rng.randrange(n) for _ in range(tail)]
        return keys
    if name == "push_front":
        return list(range(1, n)) + [0] if n else []
    if name == "random_runs":
        keys = []
        while len(keys) < n:
            run = sorted(rng.randrange(1000) for _ in range(rng.randrange(1, 200)))
            keys += run if rng.random() < 0.5 else run[::-1]
        return keys[:n]
    if name == "m3_killer":
        return median_of_three_killer(n)
    if name == "zigzag":
        return [i if i % 2 == 0 else n - i for i in range(n)]
    if name == "extremes":
        return [rng.choice([0, MASK, 1 << 63, (1 << 63) - 1, 1]) for _ in range(n)]
    fail(f"pattern {name}")


PATTERNS = ["random", "dup2", "dup16", "sqrt_distinct", "sorted", "reversed", "strict_descending",
            "descending_dups", "equal", "organ_pipe", "sawtooth", "reverse_sawtooth", "few_swaps",
            "sorted_tail", "push_front", "random_runs", "m3_killer", "zigzag", "extremes"]
SIZES = [0, 1, 2, 3, 4, 5, 8, 15, 20, 21, 23, 24, 25, 31, 32, 33, 47, 63, 64, 65, 100, 127, 128, 129,
         200, 513, 1000, 4096, 20000]
ADVERSARY_SIZES = [24, 100, 129, 1000, 4096, 20000]


def bound(n, factor=2):
    return 0 if n < 2 else int(factor * n * math.log2(n) + 2 * n)


def main():
    binary = sys.argv[1]
    rng = random.Random(SEED)
    cases = []
    for name in PATTERNS:
        for n in SIZES:
            keys = pattern(name, n, rng)
            for algorithm in ALGORITHMS:
                cases.append((name, n, algorithm, keys))
    for n in ADVERSARY_SIZES:
        cases.append(("adversary", n, 3, None))
    stdin = bytearray()
    for name, n, algorithm, keys in cases:
        stdin += struct.pack("<QQ", n, algorithm)
        if keys is not None:
            stdin += struct.pack(f"<{n}Q", *keys)
    run = subprocess.run([binary], input=bytes(stdin), capture_output=True, timeout=120)
    if run.returncode != 0 or run.stderr:
        fail(f"exit {run.returncode} stderr {run.stderr[:200]!r}")
    words = list(struct.unpack(f"<{len(run.stdout) // 8}Q", run.stdout))
    at = 0
    totals = {name: 0 for name in ALGORITHMS.values()}
    python_total = 0
    by_pattern = {}
    adversary = []
    python_cache = {}
    for name, n, algorithm, keys in cases:
        calls = words[at]
        at += 1
        if algorithm == 3:
            # Up to floor(log2 n) linear bad partitions precede the heapsort
            # fallback, so the adversary bound is 4 n log2 n + 2 n.
            if calls > bound(n, 4):
                fail(f"adversary n={n}: {calls} calls > {bound(n, 4)}")
            adversary.append((n, calls))
            continue
        got = words[at:at + n]
        at += n
        if algorithm == 0:
            if got != sorted(keys):
                fail(f"pdq {name} n={n}: wrong order")
        else:
            if got != sorted(range(n), key=keys.__getitem__):
                fail(f"{ALGORITHMS[algorithm]} {name} n={n}: not the stable order")
        if calls > bound(n):
            fail(f"{ALGORITHMS[algorithm]} {name} n={n}: {calls} calls > {bound(n)}")
        if algorithm == 1 and name in ("sorted", "strict_descending", "equal") and n >= 2 and calls != n - 1:
            fail(f"stable {name} n={n}: {calls} calls, expected {n - 1}")
        totals[ALGORITHMS[algorithm]] += calls
        key = (name, n)
        if key not in python_cache:
            python_cache[key] = python_comparisons(keys)
            python_total += python_cache[key]
        if n == SIZES[-1]:
            by_pattern.setdefault(name, {})[ALGORITHMS[algorithm]] = calls
            by_pattern[name]["python"] = python_cache[key]
    if words[at:] != [255, len(cases)]:
        fail("trailer")
    print(f"sort-algorithms-model cases={len(cases)} patterns={len(PATTERNS)} sizes={len(SIZES)} "
          f"pdq_calls={totals['pdq']} stable_calls={totals['stable']} alloc_merge_calls={totals['alloc_merge']} "
          f"python_calls={python_total} adversary=" + ",".join(f"{n}:{c}" for n, c in adversary)
          + f" seed={SEED:#x}")
    if "--table" in sys.argv:
        n = SIZES[-1]
        print(f"comparisons at n={n}: pattern pdq stable alloc_merge python")
        for name in PATTERNS:
            row = by_pattern[name]
            print(f"  {name} {row['pdq']} {row['stable']} {row['alloc_merge']} {row['python']}")


if __name__ == "__main__":
    main()
