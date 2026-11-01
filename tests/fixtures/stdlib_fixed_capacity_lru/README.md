# Inline containers and LRU cache fixtures

| Fixture | Checks |
| --- | --- |
| `model/model.lani`, `model/oracle.py` | One command stream over `core::ring` (capacities 0, 1, 5, 8), `core::inline_string` (0, 5, 12), the `core::vec` additions on `Vec<u64, 6>` and `alloc::lru` with injective-hash and four-value-hash keys, compared word for word with a Python reference. Keys count their hash and equality calls. Registered as `tests/stdlib_fixed_capacity_lru_model_execution.rs`. |
| `direct/lru_scale.lani` | The same four-million-operation LRU mix at 1,024 and 1,048,576 entries; prints nanoseconds per run and checks final counts. |

Guides: [docs/stdlib-inline-containers.md](../../../docs/stdlib-inline-containers.md),
[docs/stdlib-lru-cache.md](../../../docs/stdlib-lru-cache.md).
