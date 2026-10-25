# Ordered-map deep-clone fixtures

These sources belong to `tests/stdlib_clone_tree_map_execution.rs`. They use
the production stdlib root and this directory as a durable user module root.
All five canonical groups passed on native Linux x86-64 using the GPU compiler
on 2026-10-25: eleven compilation jobs, eight strict-checked ELF programs,
three expected source rejections and 24 native process runs. The
[module guide](../../../../docs/stdlib-clone-tree-map.md) gives the API and
ownership contracts.

- `contracts.lani`: String keys, String and nested Vec<String> values,
  borrowed duplicates, physical holes, shallow ordinary clone, actual-owner
  transfers and reinstall after mutation, pop ownership, deep reset and reuse.
- `empty.lani`, `zero_sized.lani`, `destroy_only.lani`: no-allocation empty
  cloning; one lawful zero-sized key equivalence class; minimal Destroy bounds.
- `init_sorted.lani`, `init_sorted_allocation.lani`: canonical empty-map
  initialization rejects metadata/order/nonempty cases atomically, reuses
  reserved backing, and retains the empty owner after allocation failure.
- `allocation_paths.lani`: 15 reached allocation attempts, including both
  container reservations before leaves, sorted key clones and nested value
  Vec/String clones. Output contains Entry/String size_of and an actual typed
  result tag; Rust injects ENOMEM once at every reached position and checks
  exact lifetime/address/length balance.
- `owned_errors.lani`: each of three sorted indices fails in key or value
  cloning before or after a partial leaf String; error messages remain owned
  after source and destination release. Changed keys reject before value
  cloning. Source insertion order and a removed node differ from logical order.
- The three negative fixtures reject absent opt-in or leaf protocols at the
  actual consumer. Empty runtime input does not waive trait prerequisites.

Borrowed source aliases deliberately use outer destruction plus separately
owned original Strings. Recursive release is valid only for independently
owned successful destinations. All mutating nested owners are transferred
before growth and their updated descriptors are reinstalled before cleanup.

## Acceptance and diagnostic history

The accepted logs under `target/stdlib-work/` are
`clone-tree-map-contracts-fixed.log` (four contract entries, 9.83 s) and
`clone-tree-map-failures-current.log` (four remaining active groups, 13.47 s).
The latter also records an ignored temporary manual probe; that test has been
removed without changing the five canonical groups or their assertions.

Only `probe_deep_string.lani` remains as a minimal historical reduction. It
calls deep cloning directly for one String-key/String-value entry, preserving
separate borrowed source ownership and releasing the independent result. It
does not need imported generic consumer dispatch or nested values.

The original contract and minimal entry failed with LNC0047 replay detail 6:
`clone-tree-map-contracts-first.log` and `tree-clone-probe-deep-string.log`.
The dump showed a missing layout for Vec<Entry<String,String>> although Entry
itself had a complete payload. Explicit local type annotations alone still
failed (`clone-tree-map-contracts-annotated.log`, 4.75 s); the original helper
is retained at `clone-tree-map-pre-annotation.lani` with SHA256
`189a1dea2b1832a7166c8d77bae79adc0271d80317ec3b3dc703462c294368ee`.

The compiler then reattached the portable local nominal identity to its
canonical defining declaration before deriving layout from checked fields.
The same minimal entry passed strict native checks and balanced allocation
lifetimes (`tree-clone-probe-deep-string-after-rebind.log`, 5.78 s). The full
group subsequently exposed an independent zero-sized-constructor defect
(`clone-tree-map-contracts-retained.log`): x86 emission used constructor field
count as payload width. Its correction admitted the unchanged ZST assertions and the
full accepted groups. Neither annotation-only source changes nor caller
materialization are claimed as compiler repairs. Redundant exploratory
entries/helpers and the temporary ignored driver were removed after diagnosis.
