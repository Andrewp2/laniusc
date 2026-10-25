# Ordered-set deep-clone fixtures

These sources belong to `tests/stdlib_clone_tree_set_execution.rs`, using the
production stdlib and this directory as a durable user root. All five groups
passed on native Linux x86-64 using the GPU compiler on 2026-10-25: ten
compilation jobs, eight strict-checked ELF programs, two expected source
rejections and 17 native process runs. The
[module guide](../../../../docs/stdlib-clone-tree-set.md) records
the API, typed errors, ownership and O(n log n) construction cost.

- `contracts.lani` covers Strings, generic trait selection, holes/spare
  capacity, shallow ordinary clone, independent key mutation by transfer and
  reinstall, popped ownership, actual-owner reset/reuse and explicit release.
- `empty.lani`, `zero_sized.lani`, `destroy_only.lani` cover zero-allocation
  empty cloning, one lawful ZST equivalence class and minimal Destroy bounds.
- `allocation_paths.lani` reports success or an actual typed error tag. Rust
  checks its nine reached allocations and injects ENOMEM at every position.
  There is one final destination reservation before any leaf cloning and no
  scratch backing. Source cursors, key bytes and capacity are checked before
  separate cleanup; every mapping address and requested size must balance.
- `owned_errors.lani` checks three logical indices across before/after-partial
  leaf failure and independent Eq/Ord changes. Six owned five-byte errors must
  outlive both source and failed-destination cleanup; six ChangedKey cases
  release the current clone and completed prefix exactly once.
- `cost.lani` reports comparison/equality/clone/release counts at 64 and 512
  keys. Exactly four backing allocations cover the two source/result pairs.
  `model.lani` executes 512 bounded ordered states, including live holes,
  replacement, removal, bounds, pop, reserve, clear and more than 100 deep
  clones. Full internal array snapshots and Rust BTreeMap output comparisons
  check membership and representative preservation.
- `no_opt_in.lani` and `contradictory_error.lani` reject missing destruction
  implementations and contradictory selected E at the actual source call.

Only independently owned destination keys use recursive release. Source
fixtures with borrowed leaves release outer backing and separate originals
once. The comparison/model keys own no nested allocations; their shared count
slice is explicitly borrowed test instrumentation. No shared engine or raw
schema reinterpretation is implemented here.

## Acceptance receipts

Logs under `target/stdlib-work/` record the first contract group in
`clone-tree-set-contracts-first.log` (9.61 s) and the remaining four groups in
`clone-tree-set-model-failures-current.log` (10.73 s). The latter uses corrected
fixture whitespace and records the expected AssignMismatch inside the passing
contradictory-error group. The canonical assertions were retained. Times
include compilation and verification, not isolated operation benchmarks.
