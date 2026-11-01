# Sort algorithm fixtures

| Fixture | Checks |
| --- | --- |
| `model.lani`, `oracle.py` | pdqsort (`core::slice::sort_unstable_by`), the stable run-adaptive merge sort (`core::slice::sort_stable_by`) and `alloc::slice::sort_by` on 19 patterns at 29 sizes, plus McIlroy's adversary, against Python `sorted`. Records comparator calls and checks their bounds. `--table` prints per-pattern counts at n = 20,000. Registered as `tests/stdlib_sort_algorithms_model_execution.rs`. |
| `bench.lani` | Native time and comparator calls for 100,000 u64 keys on seven patterns, for the three `_by` sorts and the natural-order `sort_unstable` and `sort_stable`. Each run checks order and a permutation checksum. |

Guide: [docs/stdlib-sort-algorithms.md](../../../docs/stdlib-sort-algorithms.md).
