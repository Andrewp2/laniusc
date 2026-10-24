# Owned vectors

`alloc::vec::Vec<T>` provides owned, growable generic storage in Lanius.
Mutating methods borrow the actual owner. Recoverable failures return Result;
callers do not compare lengths to discover whether an operation failed.
Execution evidence covers **x86_64 Linux using the GPU compiler**. It does not
establish GPU execution of user programs or support on other hosts.

## Ownership and borrowing

Keep one active owner of each allocation. A copied Vec handle aliases the same
storage; it is not a second owner. `borrow()` supplies a reference for mutating
helpers. Successful growth, shrink, edits and destruction invalidate earlier
views. Failed fallible edits preserve contents, capacity and existing views.
The language does not enforce these lifetime rules.

Values copy shallowly. `try_clone` creates independent vector storage, but does
not clone resources nested in the entries. `get`, `at`, `first`, `last` and views
return borrowed shallow copies. `pop`, `set`, `remove` and `swap_remove` transfer
the removed entry to the caller. A failed push, insertion or replacement leaves
the incoming entry with the caller. Destroy nested owned resources exactly once;
clear, truncate, shrinking resize and destroy do not invoke element destructors.

`try_extend` copies a complete `View<T>` atomically, including a view into the
same vector. Growth retains the old allocation until every source element is
copied. Inputs must borrow valid initialized storage. Extension and resize can
duplicate nested handles; the caller must choose a consistent ownership policy.

```lanius
let values: alloc::vec::Vec<i64> = alloc::vec::new();
let added: core::result::Result<i32, alloc::vec::Error> = values.try_push(42);
// Handle added before relying on the new entry.
let removed: core::option::Option<i64> = values.pop();
values.destroy();
```

## API contracts

| Operation | Behavior |
| --- | --- |
| `new<T>()` | Empty owner, no allocation |
| `with_capacity<T>(capacity)` | Result containing empty storage for at least the requested entries |
| `from_view<T>(view)` | Result containing independent storage with shallow entry copies |
| `borrow()` | Reference to the owner |
| `len()`, `capacity()`, `is_empty()` | Initialized count and storage capacity |
| `as_slice()`, `as_view()` | Borrow initialized storage; the View retains its logical count |
| `get(index)`, `get_or(index, fallback)` | Optional shallow copy or explicit fallback |
| `at(index)` | Shallow copy; invalid indices invoke `core::panic` |
| `first()`, `last()` | Optional shallow copies; None when empty |
| `try_reserve(additional)` | Reserve for `len + additional`; return resulting capacity |
| `try_push(item)` | Append and return the new length |
| `try_extend(view)` | Append all entries and return the new length |
| `set(index, item)` | Replace and return the previous entry |
| `pop()` | Transfer the last entry, or None when empty |
| `try_insert(index, item)` | Insert at `0..=len`, shift the suffix, return the new length |
| `remove(index)` | Transfer an entry and shift the suffix left |
| `swap_remove(index)` | Transfer an entry and move the last entry into its position |
| `truncate(length)` | Keep at most the requested prefix; return the actual length |
| `try_resize(length, fill)` | Set length, shallow-copying fill into any new entries |
| `clear()` | Discard initialized entries, retain storage |
| `try_shrink_to_fit()` | Reduce nonzero-sized storage to length; return capacity |
| `try_clone()` | Result containing independent backing storage |
| `destroy()` | Release storage and reset to empty, with zero capacity |
| `reverse()`, `sort()` | Reorder in place; sort is ascending and unstable |
| `index_of(item)`, `contains(item)` | Equality-based lookup; index is -1 when absent |
| `is_sorted()` | Check nondecreasing order |
| `lower_bound(item)`, `upper_bound(item)` | Insertion boundaries in a sorted vector |
| `binary_search(item)` | First equivalent entry in a sorted vector, or -1 |

Fallible edits return `Result<_, Error>`. Errors are `Bounds`,
`InvalidCapacity`, `CapacityOverflow`, and `AllocationFailed`. Negative reserve
or constructor capacity is InvalidCapacity. Negative truncate/resize lengths
and invalid edit indices are Bounds. Truncate at or beyond the current length
succeeds and returns the unchanged length. Empty extension succeeds without
allocation. These successful no-ops are part of the contract.

Length and capacity are i32. Storage is limited to `i32::MAX` bytes, so the
maximum entry count depends on `size_of<T>()`. Overflow is checked before
allocation or mutation. Zero-sized entries allocate nothing; a positive
reservation establishes capacity `i32::MAX`, and shrink retains that capacity.
Their logical lengths and overflow checks still apply.

Removal never shrinks storage. Empty nonzero-sized shrink frees it. Repeated
destroy on the same reset owner is harmless, and that owner can be reused.
Destroying a stale copied handle is invalid. Checked indexing uses the native
panic contract, currently SIGILL on x86_64 Linux, rather than a recoverable error.
Use `get` for ordinary absence.

Equality lookup requires PartialEq; sorting and ordered searches require lawful
Ord and sorted input. Native floats support IEEE membership. Float sorting uses
`core::float_order::TotalF32` or `TotalF64`, whose bit equality distinguishes
signed zero and NaN payloads. Comparisons do not allocate. See
[comparison contracts](stdlib-comparison.md).

## Storage and complexity

Capacity and fallible reserve follow the familiar
[vector contract](https://doc.rust-lang.org/std/vec/struct.Vec.html#method.try_reserve):
the reservation is additional to length, and failure preserves contents.
Lanius differs in its i32 limits, manual ownership, explicit fallible edits,
shallow nested copies and signed-index errors.

Element layout can depend on capacity, so relocation copies typed entries into
a fresh allocation rather than reinterpreting or reallocating raw bytes.
The allocator must support the current eight-byte alignment contract. Growth
is geometric for push/insert/extension. Reserve and nonempty shrink copy O(n)
entries when relocating. Clone is O(n). Push is amortized O(1); insertion and
ordered removal shift O(n) entries; swap removal and pop are O(1).

Sorting and binary searches reuse core slice algorithms. Heapsort is O(n log n),
in place and unstable. Its child-existence guard now runs before multiplying
the parent index, avoiding signed index overflow near the count limit.
Ordered searches are O(log n); equality search and sortedness checks are O(n).
These bounds assume constant-cost element copies and comparisons.

## Migration and remaining dependencies

String, owned byte streams, extended CSV/JSON, the CSV report, whitespace
normalizer and window report now use this vector. Their errors are checked
directly. Pre-reserved internal copies unwrap operations only where validated
bounds and reserved capacity make them infallible.

`std::vec` remains for two recorded boundaries and compiler regression fixtures:

- The verified compiler and its extractor explicitly identify
  `std::vec::Vec`. Removing it requires changing that separate proof/extraction
  contract, which this stdlib work does not modify.
- The attempted binary-heap migration captured a GPU compiler replay layout
  error. Its reproduction is separate from production code and has not been
  revalidated after the latest compiler changes; the heap retains its tested
  backing vector.

Ordinary vector examples now use `alloc::vec`. The legacy linear maps/sets and
specialized byte/text owners were removed after their consumers
[migrated to checked APIs](stdlib-legacy-collections.md). The deque has its own
fallible alloc API.

The new vector's counted view is constructed directly from its valid owner
state. An alternative nested Result factory triggers a separate compiler
limitation in small programs; the reproduction and successful controls are in
[vec_view_dependency](../tests/fixtures/stdlib_foundation/vec_view_dependency/README.md).
See [library-dependencies.md](library-dependencies.md) for both compiler issues.

## Execution evidence

On 2026-10-22, four groups in `tests/stdlib_alloc_vec_execution.rs` passed:

- API contracts: empty owners, all edits, returned removed values, invalid
  bounds/capacity, overflow, self-extension with and without growth, clone
  independence, searches, sorting, shrink, clear, destruction and reuse.
  Generic helpers mutate the borrowed owner; popping a nested Vec transfers
  its ownership and permits further edits before explicit destruction.
- Types: all ten integer widths, bool, char, finite f32, String and records
  containing i64, Option<bool> and arrays. Zero-sized entries require zero
  allocations under syscall tracing. Minimal direct and generic-wrapper view
  programs ensure large fixtures do not mask the view-construction dependency.
- Stateful model: 6,000 commands spanning 19 operations, comparing every result
  and complete vector state with an independent Rust vector. Seed `0x7ec02026`,
  32-bit LCG `1664525*x + 1013904223`, with integer extrema, duplicates, invalid
  indices, overflow, self-aliasing, clone, sorting and reuse.
- Fault injection: every observed allocation and all later allocations fail in
  turn across construction, growth, reserve, shrink, insertion, resize,
  self-extension and clone. Old views, contents and capacity are checked after
  errors, and syscall traces require all successful allocations to be freed.
- Panic boundary: empty, negative and past-end `at` calls terminate with the
  documented native panic signal.

Rust and Python provide test/reference infrastructure only; the library behavior
is implemented in Lanius. The model has an explicit ten-second native timeout
because it writes every vector state. Other native cases use the short test
timeout. GPU compilation is bounded separately.

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test stdlib_alloc_vec_execution -- --nocapture
```

Focused migrated-consumer suites also cover String, byte streams, text
composition, CSV, streaming CSV, JSON, CSV reporting and window reporting,
including their existing allocation and I/O fault checks. Their supported
features and limits remain documented in their own module guides.
