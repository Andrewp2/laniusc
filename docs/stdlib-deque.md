# Owned deques

`alloc::deque::Deque<T>` is a growable ring buffer implemented in Lanius.
Both ends support constant-time removal and amortized constant-time insertion.
Mutating methods borrow the actual owner. Allocation and bounds failures return
explicit Results; removing from an empty deque returns None.

Execution evidence covers **x86_64 Linux using the GPU compiler**. It does not
establish GPU execution of user programs or support on other hosts.

## Ownership and views

Keep one active owner of each allocation. A copied Deque handle aliases its
storage and must not be destroyed separately. `borrow()` lets a helper mutate
the owner. These lifetime rules are conventions; the compiler does not enforce
unique ownership, immutable views or automatic destruction.

Entries copy shallowly. `get`, `at`, `front`, `back`, views and cursors borrow
their entries. Pop, replacement, removal and splitting transfer the removed
entries to the caller. A failed insertion leaves the incoming value with the
caller. Destroy each nested resource exactly once. Clear, truncate, shrinking
resize and destroy do not invoke element destructors.

Cloning creates independent ring storage but shallow-copies entries. Extension
and growing resize can also duplicate nested handles. Choose a consistent
ownership policy for those entries. Splitting transfers the suffix without
duplicating active ownership of its entries.

`as_views()` returns two counted slices whose concatenation is the logical
front-to-back sequence. Either may be empty. The split point is an implementation
detail. `iter()` provides a borrowed cursor with `next`, `next_back` and
`remaining`; the ends never overlap, and exhaustion remains None. The cursor
also implements the [shared iterator protocol](stdlib-collection-iterators.md).

Successful edits invalidate earlier views and cursors. Failed fallible edits
preserve them, contents and capacity. Owners must outlive their views. Inputs
must satisfy the counted slice's physical backing and lifetime requirements.
Self-extension is supported: front extension preserves the source view's order,
and growth retains the old allocation until all source entries have been copied.
Without growth, extension writes only into previously uninitialized slots.

## API contracts

The [fallible iterator sink](stdlib-iterator-transfer.md) implements
`TrySink<T,Error>` by appending at the back with `try_push_back`. Bounded
transfer retains any earlier accepted prefix and returns the rejected item on
failure. A rejected insertion preserves the deque's state and old views;
successful insertions follow the invalidation rules above. Source backing must
remain valid independently of those edits.

```lanius
let queue: alloc::deque::Deque<i64> = alloc::deque::new();
let added: core::result::Result<i32, alloc::deque::Error> =
    queue.try_push_back(42);
// Handle added before relying on the inserted value.
let removed: core::option::Option<i64> = queue.pop_front();
queue.destroy();
```

| Operation | Behavior |
| --- | --- |
| `new<T>()` | Empty owner, no allocation |
| `with_capacity<T>(capacity)` | Result containing empty storage for at least the requested count |
| `from_view<T>(view)` | Independent storage containing shallow copies in view order |
| `borrow()` | Reference to the actual owner |
| `len()`, `capacity()`, `is_empty()` | Initialized count and available storage |
| `get(index)`, `get_or(index, fallback)` | Optional shallow copy or explicit fallback |
| `at(index)` | Shallow copy; invalid indices invoke core panic |
| `front()`, `back()` | Optional shallow copies of the endpoints |
| `as_views()`, `iter()` | Borrow the complete logical sequence |
| `try_reserve(additional)` | Reserve for `len + additional`; return resulting capacity |
| `try_push_front(item)`, `try_push_back(item)` | Insert at an endpoint; return new length |
| `pop_front()`, `pop_back()` | Transfer an endpoint, or None when empty |
| `set(index, item)` | Replace and return the previous entry |
| `swap(left, right)` | Exchange two valid positions; return Ok(true) |
| `try_insert(index, item)` | Insert at `0..=len`; return new length |
| `remove(index)` | Transfer one entry, preserving remaining order |
| `swap_remove_front(index)`, `swap_remove_back(index)` | Transfer one entry, filling its position from the named endpoint; order may change |
| `try_extend_front(view)`, `try_extend_back(view)` | Prepend or append the whole view atomically; return new length |
| `truncate(length)` | Retain at most the requested prefix; return actual length |
| `try_resize(length, fill)` | Set length, shallow-copying fill into new entries at the back |
| `rotate_left(count)`, `rotate_right(count)` | Rotate by `0..=len`; return unchanged length |
| `reverse()` | Reverse logical order in place |
| `clear()` | Discard entries and retain capacity |
| `try_shrink_to_fit()` | Reduce nonzero-sized storage to length; return capacity |
| `try_make_contiguous()` | Return one counted view; wrapped nonzero-sized storage may allocate |
| `try_clone()` | Independent storage containing shallow entry copies |
| `try_split_off(index)` | Transfer suffix `index..len` into independent storage; retain the prefix and original capacity |
| `index_of(item)`, `contains(item)` | Equality lookup; absent index is -1; requires PartialEq |
| `destroy()` | Release storage and reset the owner to empty |

Errors are `Bounds`, `InvalidCapacity`, `CapacityOverflow` and
`AllocationFailed`. Negative constructor/reserve capacities are InvalidCapacity,
including when spare storage exists. Negative lengths and invalid edit,
rotation or split indices are Bounds. Requests exceeding the entry or byte
budget fail before allocation or mutation. Checked `at` uses the native panic
contract, currently SIGILL; use `get` for ordinary absence.

Truncating beyond the current length, rotating by zero or length, empty extension,
and reserving already available capacity are documented successful no-ops.
Empty pops return None. An empty split suffix allocates nothing. Removal never
shrinks capacity; empty nonzero-sized shrink releases the allocation.

Counts are i32 and allocated storage is limited to `i32::MAX` bytes. The maximum
entry count therefore depends on `size_of<T>()`. Zero-sized entries allocate
nothing; a positive reservation establishes capacity `i32::MAX`, and shrink
retains it. Destroy resets any owner to zero capacity and permits reuse;
repeated destruction of that same reset owner is harmless.

## Storage and complexity

The ring uses logical ordinals and a wrapping head. Index calculations avoid
overflowing `head + ordinal`. Capacity-dependent element layouts require typed
element copies when moving storage, rather than raw byte reallocation. The
allocator must support the current eight-byte alignment contract.

Pop, endpoint lookup, indexed lookup/replacement, swap and swap removal take
O(1). Push is amortized O(1) with geometric growth. Insertion and ordered removal
shift the closer end: O(min(index, len-index)) plus any allocation/copy on growth.
Reserve and shrink copy O(len) when relocating; clone and split copy their
output entries. Extension is O(input length), plus O(len) when growing.

Rotations use O(min(count, len-count)) moves without allocation, or O(1) when
the ring is full. Reverse and equality search are O(len); cursors advance in
O(1). These bounds assume constant-cost element copies and comparisons.

Already contiguous storage stays in place. A wrapped `try_make_contiguous`
copies into a fresh allocation of the same capacity, preserving the owner on
allocation failure. This deliberate fallible API is simpler than rotating
partially initialized generic storage in place. Zero-sized storage needs no
allocation. Future in-place optimization must preserve this observable contract.

The familiar reserve, endpoint and logical-order conventions are described by
the [Rust VecDeque reference](https://doc.rust-lang.org/std/collections/struct.VecDeque.html).
Lanius uses signed bounds, explicit fallible edits and manual ownership; its
contiguity operation may allocate and its remove operation reports Bounds.

## Migration and executable evidence

The previous `std::deque` module has been removed. Its silent unchanged-owner
failure convention is replaced by Results and removed-value returns. All ten
recent-values examples now import `alloc::deque` and check push/constructor
errors directly. No forwarding compatibility module was introduced.

The focused suites exercise these contracts on x86_64 Linux:

- `stdlib_alloc_deque_execution`: ordinary and invalid operations; wrapped
  growth; aliased extension at both ends; nested owned vectors; all ten integer
  widths, bool, char, finite f32, String and records containing i64, arrays and
  Option<bool>; checked-index panics; zero-sized storage under allocation denial.
- Allocation fault injection fails every observed allocation and all subsequent
  allocations across constructor, endpoint growth, insertion, reserve, extension,
  contiguity, clone, split, resize and shrink. It checks old views, cursors,
  contents and capacity after failure, and traces every allocation's release.
- Reserved edits cover both aliased extension directions without growth and
  reject invalid operations without changing existing cursors. FIFO workloads
  use 4,096 and 65,536 i64 entries, each performing 262,144 pop/push pairs and
  verifying every removed and remaining value. Each run allocates once; all
  subsequent allocation attempts are denied by syscall injection.
  Nine alternating native runs on the Ryzen 9 5950X measured median process CPU
  time of 46.66 ms and 54.47 ms respectively, including initialization and final
  traversal. These are whole-workload measurements, not per-operation latency
  guarantees or GPU compiler benchmarks.
- `stdlib_deque_stateful_execution`: 6,000 commands across 29 operations,
  comparing each returned result and full contents against Rust VecDeque.
  Seed `0xdec02026`, LCG `1664525*x + 1013904223`; includes integer extrema,
  duplicates, negative/out-of-range indices, overflow, self-extension, rotations,
  split, clone and reuse. Every state also checks the two views and mixed-ended
  cursor traversal.
- `stdlib_deque_execution`: ten real recent-value programs combine the deque
  with decimal/UTF-8 parsing, byte utilities and native I/O. Cases include empty
  input, repeated wraps, malformed data, numeric limits and Unicode output
  failure. Additional fault tests check allocation failure and cleanup in the
  boolean and Unicode programs.

The old source-text public-function-count test was removed; a call name in a
file does not establish runtime coverage. Six separate allocation fixtures were
replaced by the complete failure sweep. The old generated 48-command programs
were replaced by a runtime command model plus separate generic payload coverage.

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test stdlib_alloc_deque_execution \
    --test stdlib_deque_stateful_execution --test stdlib_deque_execution -- --nocapture
```

Rust/Python are harness/reference infrastructure only. The deque implementation
is Lanius. Native model output has an explicit ten-second timeout and the large
allocation-traced workload has three seconds; ordinary cases retain the short
native timeout. Each GPU compilation is separately bounded.
