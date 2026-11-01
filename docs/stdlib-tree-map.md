# Ordered maps

`alloc::tree_map::TreeMap<K, V>` is an AVL ordered map implemented in Lanius.
It supports logarithmic searches and edits, ordered traversal from either end,
half-open key ranges and linear construction from sorted entries. Allocation
failures return explicit Results and preserve the original map.

Execution evidence covers **x86_64 Linux using the GPU compiler**. It does not
establish GPU execution of user programs or support on other hosts. The tree
algorithm uses portable values; storage uses the existing allocator bindings.

## Ordering and ownership

Insertion and same-key operations require `K: core::cmp::Ord<K>` and use
`K::lt`. The new borrowed point queries use an explicit `Comparator<K,Q>`
while preserving this stored-key ordering. The relation must
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
used during cursor construction and are not retained. Later
[shared iterator-trait integration](stdlib-collection-iterators.md) has separate
accepted evidence.

## Borrowed point queries

[Borrowed collection lookup](stdlib-borrowed-lookup.md) adds `contains_key_by`,
`get_by`, `get_entry_by`, `remove_by` and `update_value_by` for a distinct Q.
Their borrowed `Comparator<K,Q>` receives stored key first, query second,
once per visited node. It must partition stored order into Less, optionally
Equal, then Greater and identify at most one stored key class. Getters borrow
the stored representative; removal transfers the actual entry; update retains
the original key and reinstalls V on every normal callback return.
`alloc::string::TextKey` supplies String/Text policy. All sixteen map/set
methods pass the nine-group library acceptance and migrated application
on native Linux x86_64 CPU output. Ordered bounds and ranges take
heterogeneous queries separately, through the navigation contract below.

## Ordered navigation

[Ordered navigation](stdlib-ordered-navigation.md) adds `last_at_most`,
`last_below`, `lower_bound_by`, `upper_bound_by`, `last_at_most_by`,
`last_below_by`, `range_bounds` and `range_bounds_by`. Interval ends are
`core::range::Bound<K>` (or `Bound<Q>`) values: Included, Excluded or
Unbounded, so `Included(i32::MAX)` is reachable. Navigation policies order
stored keys as Less*, Equal*, Greater*; unlike point lookup, an Equal run may
hold several keys, such as a String prefix family. Calls are one per visited
node per descent, plus one front check for a bounded range. Nothing allocates.
The same intervals can be removed in place (`remove_range`,
`remove_range_by`; shallow discard, capacity kept, no allocation) or moved
with their cleanup authority to a new exact-capacity owner
(`try_extract_range`, `try_extract_range_by`, `try_split_off`); failed
extraction leaves the source unchanged.

## API contracts

| Operation | Behavior |
| --- | --- |
| `new<K, V>()` | Empty owner without allocation |
| `with_capacity<K, V>(capacity)` | Result containing empty storage for the requested entry count |
| `from_sorted<K, V>(view)` | Independent node storage with shallow copies; require strictly increasing, unique keys |
| `try_init_sorted(view)` | Initialize an empty actual owner with strictly increasing entries, reusing reserved storage; return the entry count |
| `borrow()` | Reference to the actual owner |
| `len()`, `capacity()`, `is_empty()` | Live entry count, reserved node count and emptiness |
| `contains_key(key)` | Whether an equivalent key exists |
| `get(key)`, `get_entry(key)` | Optional borrowed value or complete entry |
| `update_value(key, update)` | One lookup; missing returns None, present reinstalls callback Pair.first and returns Some(Pair.second), preserving the stored key; [current evidence](stdlib-map-updates.md) |
| `first()`, `last()` | Optional borrowed smallest or largest entry |
| `lower_bound(key)`, `upper_bound(key)` | First entry at least equal to, or strictly greater than, the key |
| `iter()` | Borrowed cursor over all entries in key order |
| `range(lower, upper)` | Result containing a cursor over `[lower, upper)`; equivalent bounds yield empty |
| `last_at_most(key)`, `last_below(key)` | Last entry at most equal to, or strictly less than, the key |
| `lower_bound_by`, `upper_bound_by`, `last_at_most_by`, `last_below_by` | The four searches with a `Comparator<K,Q>` query; see [ordered navigation](stdlib-ordered-navigation.md) |
| `range_bounds(lower, upper)` | Result containing a cursor between two `Bound<K>` ends; InvalidRange only when upper is strictly less than lower |
| `range_bounds_by(lower, upper, policy)` | Cursor between two `Bound<Q>` ends; disjoint or reversed bounds are empty |
| `remove_range(lower, upper)`, `remove_range_by(lower, upper, policy)` | Remove the `range_bounds`/`range_bounds_by` interval shallowly, without allocation; return the count (same-key form in a Result with InvalidRange) |
| `try_extract_range(lower, upper)`, `try_extract_range_by(lower, upper, policy)` | Move that interval with its cleanup authority into a new owner of exactly its size; Err leaves the source unchanged |
| `try_split_off(at)` | `try_extract_range(Included(at), Unbounded)` |
| `try_reserve(additional)` | Reserve for `len + additional`; return resulting capacity |
| `try_insert(key, value)` | Result containing the replaced entry, or None for a new key |
| `remove(key)` | Transfer the equivalent entry, or None |
| `pop_first()`, `pop_last()` | Transfer the smallest or largest entry, or None |
| `clear()` | Remove all entries, retaining storage and calling no element destructors |
| `try_clone()` | Result containing independent node storage with shallow entry copies |
| `try_shrink_to_fit()` | Compact to capacity equal to length; return capacity |
| `destroy()` | Free node storage and reset the owner; repeated calls on that same owner are harmless |
| Cursor `is_empty()`, `next()`, `next_back()` | Check exhaustion or borrow the next entry from either end |

The [scoped value update](stdlib-map-updates.md) retains the exact representative
key, node links/heights, free list, count, capacity and backing. A present value
is lent exclusively to one callback; its latest descriptor is reinstalled on
every normal return, including a separate Result error. End prior borrows and
cursors first, and do not access the map or change key ordering during the
callback. All seven new library gates pass on the finite native Linux x86_64 profile;
the dedicated guide records their scope and the accepted 103-case application. The older receipts below do not establish this method.

Errors are `InvalidCapacity` for a negative request, `CapacityOverflow` when
the requested node storage exceeds the supported size, `AllocationFailed`,
`InvalidOrder` for equivalent or descending adjacent sorted-input keys,
`InvalidRange` when upper precedes lower or sorted-input View metadata is
invalid, and `NotEmpty` when sorted initialization receives a nonempty owner.
Sorted input is validated before allocation. Empty construction, lookup and traversal do not allocate. The
initial View must satisfy its physical backing and lifetime preconditions.

`try_init_sorted` is the canonical empty-owner construction boundary used by
`from_sorted` and the opt-in [deep-clone helper](stdlib-clone-tree-map.md).
Its View must not alias the destination's backing allocation. It rejects a
nonempty destination before inspecting input, then rejects negative or
overflowing View metadata, excessive counts and non-increasing adjacent keys
before reserving or writing. Every error preserves the destination, its
capacity and the input. Successful initialization copies entries shallowly and
uses the existing linear midpoint builder. If capacity already covers the
input count, initialization allocates nothing. Entries removed by `clear` or
pop remain the caller's nested-resource responsibility. The focused canonical
initialization group passed its two native entry fixtures in 5.55 seconds,
including allocation denial and reservation reuse. The separate deep-clone
gate now passes all five groups, including zero-sized keys/values, nested
owners and every reached allocation failure; its guide records both compiler
repairs and the execution receipts.

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
| `update_value` | O(log n) lookup plus one callback and constant reinstall; no rebalance |
| Reserve that grows storage | O(used), including holes below the initialized high-water mark; `used <= capacity` |
| Full traversal | O(n), with no key comparisons |
| One cursor step | O(log n) worst case; amortized O(1) during traversal |
| Range setup and consumption of k entries | O(log n + k) |
| Sorted construction, clone, nonempty shrink | O(n) |
| Clear | O(1), without element destruction |

Lookup walks the tree with `K::lt` and reads one node per level from an
untyped view of the node storage. Insertion and removal stop rebalancing at
the first ancestor whose height is unchanged after its repair; above that
node no balance factor changes.

## Performance at one million keys

[`bench.lani`](../tests/fixtures/stdlib_tree_map_perf/bench.lani) runs the
[hash map benchmark](stdlib-hash-collections.md#performance-at-one-million-keys)
keys and phases on this map, and
[`bench.cpp`](../tests/fixtures/stdlib_tree_map_perf/bench.cpp) runs them on
`std::map` (g++ -O2). Best of three interleaved rounds on 2026-10-31 on the
development laptop, in milliseconds, at load average 17-19:

| Phase | before | after | C++ |
| --- | ---: | ---: | ---: |
| u64 insert | 2930 | 860 | 106 |
| u64 hit | 642 | 347 | 51 |
| u64 miss | 641 | 314 | 50 |
| u64 remove half | 1908 | 539 | 83 |
| u64 half hit | 624 | 351 | 205 |
| u64 remove rest | 1571 | 466 | 75 |
| i32 insert | 3086 | 1029 | 86 |
| i32 hit | 703 | 349 | 50 |
| i32 miss | 588 | 213 | 11 |
| i32 remove half | 1872 | 525 | 53 |
| i32 half hit | 669 | 342 | 102 |
| i32 remove rest | 1635 | 467 | 48 |

Before, lookup went through the `NaturalKey` comparator, which builds an
`Ordering` for every node, each node view came from
`typed_slice_from_storage` (about 23 ns for its stride probe), and
rebalancing always climbed to the root. A lookup step, about 20 levels deep
at a million keys, now costs about 17 ns, against about 2.5 ns for `std::map`. The gap comes from
the same backend costs as the hash map's: each node is copied through
memory and every value round-trips through the stack.

The old `std::map` was removed after its repository callers migrated to checked
`alloc::hash_map` owners and explicit order vectors where their output needs
first-seen order. See [collection migration](stdlib-legacy-collections.md).
[Ordered sets](stdlib-owned-sets.md) delegate to this map's storage and cursor
engine. Broader Entry handles and heterogeneous ordered bounds/ranges remain
work. Distinct borrowed-key point lookup has the separate contract and
acceptance above; scoped value update retains its explicit callback policy.

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
