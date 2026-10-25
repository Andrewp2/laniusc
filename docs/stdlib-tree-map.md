# Ordered maps

`alloc::tree_map::TreeMap<K, V>` is an AVL ordered map implemented in Lanius.
It supports logarithmic searches and edits, ordered traversal from either end,
half-open key ranges and linear construction from sorted entries. Allocation
failures return explicit Results and preserve the original map.

Execution evidence covers **x86_64 Linux using the GPU compiler**. It does not
establish GPU execution of user programs or support on other hosts. The tree
algorithm uses portable values; storage uses the existing allocator bindings.

## Ordering and ownership

Key operations require `K: core::cmp::Ord<K>` and use `K::lt`. The relation must
be a stable strict weak order: keys are equivalent when neither is less than
the other. Equivalent-key `try_insert` replaces both the key and value, returning
the previous `Entry<K, V>`. Values need no comparison implementation. Do not
mutate stored keys, including their borrowed backing, in a way that changes
ordering. Floating-point NaNs require an explicit ordering wrapper; the current
floating-point execution fixture uses finite values.

Keep one active owner of each allocation. Copying the map handle aliases its
storage; it does not clone it. `borrow()` returns a reference to the actual
owner. The compiler does not enforce unique ownership or automatic destruction.

Entries copy shallowly. Lookup, bounds, endpoints and cursors return borrowed
copies. Removal and replacement transfer responsibility for the previous key
and value. A failed insertion leaves its inputs with the caller. Clear and
destroy never call key or value destructors. Drain and destroy nested resources
explicitly when the map owns them. Cloning and sorted construction allocate
independent node storage but shallow-copy keys and values; callers must choose
a consistent ownership policy for those nested resources.

The [iterator sink](stdlib-iterator-collection-sinks.md) accepts `Entry<K,V>`
with an explicit unique-key policy: equivalent keys reject unchanged with
`SinkError::Duplicate`, preserving the stored key and value. Allocation failures
are `SinkError::Storage(Error)`. Bounded transfer retains the accepted prefix
and returns the incoming rejected entry for recovery. Its source must remain
valid independently of destination edits.

Cursors borrow the map. Successful edits invalidate earlier cursors; failed
fallible edits preserve them, contents and capacity. Owners and key backing
must outlive cursors. `next` and `next_back` consume opposite ends without
overlap; either returns None repeatedly after exhaustion. Range bounds are
used during cursor construction and are not retained. Shared iterator-trait
integration remains a separate compiler dependency.

## API contracts

| Operation | Behavior |
| --- | --- |
| `new<K, V>()` | Empty owner without allocation |
| `with_capacity<K, V>(capacity)` | Result containing empty storage for the requested entry count |
| `from_sorted<K, V>(view)` | Independent node storage with shallow copies; require strictly increasing, unique keys |
| `borrow()` | Reference to the actual owner |
| `len()`, `capacity()`, `is_empty()` | Live entry count, reserved node count and emptiness |
| `contains_key(key)` | Whether an equivalent key exists |
| `get(key)`, `get_entry(key)` | Optional borrowed value or complete entry |
| `first()`, `last()` | Optional borrowed smallest or largest entry |
| `lower_bound(key)`, `upper_bound(key)` | First entry at least equal to, or strictly greater than, the key |
| `iter()` | Borrowed cursor over all entries in key order |
| `range(lower, upper)` | Result containing a cursor over `[lower, upper)`; equivalent bounds yield empty |
| `try_reserve(additional)` | Reserve for `len + additional`; return resulting capacity |
| `try_insert(key, value)` | Result containing the replaced entry, or None for a new key |
| `remove(key)` | Transfer the equivalent entry, or None |
| `pop_first()`, `pop_last()` | Transfer the smallest or largest entry, or None |
| `clear()` | Remove all entries, retaining storage and calling no element destructors |
| `try_clone()` | Result containing independent node storage with shallow entry copies |
| `try_shrink_to_fit()` | Compact to capacity equal to length; return capacity |
| `destroy()` | Free node storage and reset the owner; repeated calls on that same owner are harmless |
| Cursor `is_empty()`, `next()`, `next_back()` | Check exhaustion or borrow the next entry from either end |

Errors are `InvalidCapacity` for a negative request, `CapacityOverflow` when
the requested node storage exceeds the supported size, `AllocationFailed`,
`InvalidOrder` for equivalent or descending adjacent sorted-input keys, and
`InvalidRange` when upper precedes lower. Sorted input is validated before
allocation. Empty construction, lookup and traversal do not allocate. The
initial View must satisfy its physical backing and lifetime preconditions.

Storage requests are limited to `i32::MAX` bytes, divided by the size of the
node for the selected key/value types. Node metadata takes space even when
both types have zero size. Replacement and removal never allocate. New entries
reuse freed nodes before extending the initialized region; geometric capacity
growth occurs only when the map is full. There is no success-shaped fallback
for a failed allocation.

## Algorithm and costs

The implementation follows the [AVL height-balance rule](https://adtinfo.org/libavl.html/AVL-Balancing-Rule.html)
and repairs the parent links described by [parent-pointer rotations](https://adtinfo.org/libavl.html/PBST-Rotations.html).
Nodes use arena indices, cached heights and a free list. Rotations update the
upper link, pivot, previous root and middle subtree before refreshing heights.
Deleting a node with two children transfers its successor entry into the node,
unlinks the successor and rebalances upward. Indices survive storage relocation.

Sorted construction links midpoint subtrees using a fixed interval stack. Its
depth is bounded by the i32 entry count. Clone traverses live entries in order
and builds a compact balanced tree without comparing keys. Shrink builds that
replacement before releasing the original allocation.

| Operation | Cost, excluding the cost of copying or comparing one entry |
| --- | --- |
| Lookup, bounds, first/last | O(log n) |
| New insertion | Amortized O(log n); a growth allocation also copies initialized nodes |
| Replacement, removal, endpoint pop | O(log n) |
| Reserve that grows storage | O(used), including holes below the initialized high-water mark; `used <= capacity` |
| Full traversal | O(n), with no key comparisons |
| One cursor step | O(log n) worst case; amortized O(1) during traversal |
| Range setup and consumption of k entries | O(log n + k) |
| Sorted construction, clone, nonempty shrink | O(n) |
| Clear | O(1), without element destruction |

The old `std::map` was removed after its repository callers migrated to checked
`alloc::hash_map` owners and explicit order vectors where their output needs
first-seen order. See [collection migration](stdlib-legacy-collections.md).
[Ordered sets](stdlib-owned-sets.md) delegate to this map's storage and cursor
engine. Entry APIs and lookup through a distinct borrowed key type remain work.

## Executable evidence

`tests/stdlib_tree_map_execution.rs` has eight passing execution groups:

- A 6,000-command reference model compares complete ordered contents, results,
  mixed-ended iteration and ranges with Rust's BTreeMap after every command.
  Its deterministic seed is `0x7aee2026`.
- Generic key/value tests cover all ten integer widths, bool, char, finite f32,
  owned strings, records containing u64/Option<bool>/byte arrays, empty records
  and nested vectors. A custom comparator checks equivalent-key replacement.
- Allocation denial checks every observed allocation in construction, growth,
  reserve, clone, shrink and sorted construction, including preservation of
  existing cursors. Traces verify that every successful allocation is released.
- Empty and invalid requests run with all allocation attempts denied.
- Ascending, descending and alternating-extreme orders each exercise 32,768
  keys through insertion, search, removal, reuse and endpoint draining. Each
  search/edit has a logarithmic comparison bound. Each workload reserves once
  and attempts no further allocation.
- Sorted construction of 65,536 entries takes exactly 65,535 comparisons.
  Both sorted construction and repeated insertion run with exactly two whole
  program allocations: the source vector and the tree. Destroying the source
  before traversal checks independent node storage.
- The word-count application has independent output comparisons, UTF-8 and
  resource-boundary cases, allocation denial, interrupted I/O, failed I/O and
  zero-progress writes. Its failure paths release all observed allocations.

Run the focused suite with a bounded command:

```sh
timeout --kill-after=2s 100s env CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 cargo test --locked --test stdlib_tree_map_execution -- --nocapture
```

This requires the GPU compiler's normal Vulkan environment and `strace` for
allocation and I/O injection. No compiler IR, extractor, proofs or ABI changed
for this module.

### Construction measurements

On an AMD Ryzen 9 5950X, nine alternating runs of the compiled
`tree_map_bulk.lani` fixture gave these medians for 65,536 entries:

| Construction path | Key comparisons during construction | Whole-program CPU time |
| --- | ---: | ---: |
| `from_sorted` | 65,535 | 32.31 ms |
| Repeated `try_insert` after reserve | 1,966,082 | 312.06 ms |

CPU time is child user plus system time, measured without syscall tracing.
Both programs also build and destroy the input vector, traverse the map,
remove endpoints, perform a lookup and free storage. These are whole-program
measurements, not isolated construction timings or compiler performance claims.
The sorted path is selected with no arguments; an extra argument selects
repeated insertion. Comparison and allocation bounds are deterministic test
gates; the measured timing is evidence, not a test threshold.

## Sorted word counts

`sample_programs/word_counts.lani` combines streams, owned byte storage, UTF-8
validation, borrowed word splitting, TreeMap ranges and decimal formatting.
It reads stdin and emits `word<TAB>count<LF>` in byte-lexicographic order.
The optional two arguments select `[lower, upper)`.

Words are delimited by the six ASCII whitespace bytes (9–13 and 32). Case,
NUL and other Unicode bytes are preserved; there is no normalization. Keys
borrow the input buffer, which stays alive until the map is destroyed.

Limits are 1 MiB of input, 65,536 distinct words and 256 UTF-8 bytes per range
argument. Input validation and counting finish before output begins. Exit 2
means invalid input, arguments or a limit; 3 means I/O failure; 4 means an
allocation failure. Output may be a prefix after a write failure.

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc sample_programs/word_counts.lani --stdlib-root stdlib -o target/stdlib-work/word-counts
printf 'pear apple pear banana\n' | timeout 5s target/stdlib-work/word-counts
printf 'pear apple pear banana\n' | timeout 5s target/stdlib-work/word-counts apple pear
```

The first run prints apple:1, banana:1 and pear:2 as tab-separated rows. The
second excludes pear at the upper bound.
