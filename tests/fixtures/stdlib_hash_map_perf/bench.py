"""Python dict on bench.lani's workload: same keys, same phases, same checks."""
import time

N = 1 << 20
SPREAD = 11400714819323198485
MASK = (1 << 64) - 1


def phases(label, key, miss_key):
    table = {}
    keys = [key(i) for i in range(N)]
    misses = [miss_key(i) for i in range(N)]
    t = time.perf_counter_ns()
    for i, k in enumerate(keys):
        table[k] = i
    print(label, 'insert', time.perf_counter_ns() - t)
    t = time.perf_counter_ns()
    total = 0
    for k in keys:
        total += table[k]
    print(label, 'hit', time.perf_counter_ns() - t)
    assert total == N * (N - 1) // 2
    t = time.perf_counter_ns()
    found = 0
    for k in misses:
        if k in table:
            found += 1
    print(label, 'miss', time.perf_counter_ns() - t)
    assert found == 0
    t = time.perf_counter_ns()
    for k in keys[0::2]:
        del table[k]
    print(label, 'remove_half', time.perf_counter_ns() - t)
    t = time.perf_counter_ns()
    found = 0
    for k in keys:
        if k in table:
            found += 1
    print(label, 'half_hit', time.perf_counter_ns() - t)
    assert found == N // 2
    t = time.perf_counter_ns()
    for k in keys[1::2]:
        del table[k]
    print(label, 'remove_rest', time.perf_counter_ns() - t)
    assert not table


phases('u64', lambda i: ((i + 1) * SPREAD) & MASK, lambda i: ((i + N + 1) * SPREAD) & MASK)
phases('i32', lambda i: (i * 2654435761) % N, lambda i: i + N)
