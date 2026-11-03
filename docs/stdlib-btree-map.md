# B-tree ordered map and set

`alloc::btree_map::BTreeMap<K, V>` is an ordered map stored as a B+ tree, and
`alloc::btree_set::BTreeSet<T>` is the [set](#set) on the same tree. The map
has the same ordering rules, `Entry`/`Cursor` shape and error style as
[`alloc::tree_map`](stdlib-tree-map.md), the AVL map. Use it when a workload
iterates, looks keys up in key order, or looks them up in no particular order.
For lookups in insertion order the AVL map is faster, because of how its nodes
are allocated (see [Where lookup time goes](#where-lookup-time-goes)).

Execution evidence covers **x86_64 Linux using the GPU compiler** only.

## API

| Call | Effect | Cost |
| --- | --- | --- |
| `new()` | Empty map, no allocation | O(1) |
| `len()`, `is_empty()`, `node_capacity()` | Entry count; nodes allocated (16 entries each) | O(1) |
| `try_insert(key, value)` | `Ok(None)` for a new key. An equivalent key replaces the stored key and value and returns `Ok(Some(old))` | O(log n) |
| `get(key)`, `get_entry(key)`, `contains_key(key)` | Point lookup | O(log n) |
| `remove(key)` | `Some(entry)` with ownership of the removed key and value | O(log n) |
| `first()`, `last()`, `pop_first()`, `pop_last()` | Endpoints | O(1) / O(log n) |
| `lower_bound(key)`, `upper_bound(key)` | First entry `>= key` / `> key` | O(log n) |
| `iter()` | Cursor over every entry | O(1) to create |
| `range(lower, upper)` | Cursor over `[lower, upper)`. `Err(InvalidRange)` when `upper < lower`; equivalent bounds give an empty cursor | O(log n) to create |
| `from_sorted(view)` | Build from a `core::slice::View<Entry<K, V>>` of strictly increasing keys. `Err(InvalidOrder)` for an equal or descending neighbor, checked before anything is allocated | O(n) |
| `try_clone()` | Independent, exactly sized copy. Keys and values copy shallowly | O(n) |
| `builder(count)` | A `Builder<K, V>` for exactly `count` entries: `push(key, value)` in strictly increasing key order, then `finish()` returns the map. `remaining()` counts what is left, and `destroy()` abandons a partial build | O(n) in total |
| `clear()` | Drop every entry and keep the allocation | O(1) |
| `destroy()` | Release the allocation | O(1) |

`Cursor<K, V>` implements `core::iter::Iterator` (`next`) and
`DoubleEndedIterator` (`next_back`), and `is_empty()` reports when the two
ends have met. Steps are O(1), because leaves are linked in both directions.
Any edit to the map invalidates its cursors.

`Error` is one of:

- `CapacityOverflow`: the node arrays would pass `i32::MAX` bytes;
- `AllocationFailed`;
- `InvalidRange`: a reversed range, a negative builder count or a malformed view;
- `InvalidOrder`: `from_sorted` input that is not strictly increasing.

The map implements both iterator sinks for `Entry<K, V>`:

- **`core::iter::TrySink`** rejects an equivalent key with `SinkError::Duplicate` and keeps the stored entry. An insert error comes back as `SinkError::Storage(Error)`.
- **`core::iter::TryReplaceSink`** replaces the key and value and returns the old entry, as `try_insert` does.

## Ordering and ownership

Keys need `K: core::cmp::Ord<K>`, and only `K::lt` is called. As with
`tree_map`, the relation must be a stable strict weak order. Two keys are
equivalent when neither is less than the other. Values need no trait.

Entries copy shallowly. Lookups, endpoints and cursors return borrowed copies.
`remove`, the pops and replacement hand the old key and value to the caller.
`clear` and `destroy` never destroy keys or values, so drain the map first when
it owns nested resources. Copying the map handle aliases its storage. Keep one
active owner.

## Layout

The map keeps four parallel arrays indexed by node number:

- **keys:** `16n + j`.
- **values:** `16n + j`, used in leaves only.
- **links:** 24 `i32` words per node. Word 1 holds the next leaf, or the next free node when the node is on the free list. Word 2 holds the previous leaf, and words 3–19 hold the 17 children of an inner node.
- **counts:** one `i32` per node, placed after the links in the same allocation, so a lookup's reads of the count stay in cache.

The arrays grow by doubling. Each growth copies the used nodes and frees the
old arrays. Inner key `j` separates child `j`, where every key is below it,
from child `j + 1`, where every key is at least it. Searches binary-search each
node and descend in one loop with no calls besides `K::lt`.

Nodes hold between 8 and 16 keys, except the root.

- **Insert:** a full leaf splits 9/8, and a full inner node splits 8/1/8, with the middle key moving up. A new root is added when the old root splits.
- **Remove:** a node with fewer than 8 keys borrows from a sibling with spare keys, or else merges with one. Merges continue up the tree, and an empty inner root collapses into its only child.
- **Free list:** freed nodes go on the free list and are reused before new nodes.

### Sorted construction

`builder(n)` reserves every node the finished tree needs, so `push` and
`finish` never allocate:

- **Leaves:** `ceil(n/16)` of them, holding 8–16 entries.
- **Inner levels:** each has `ceil(c/17)` nodes for the `c` nodes below, holding 9–17 children.
- **Spread:** entries and children are spread evenly over each level, which stays within the bounds that edits keep.
- **Separators:** each one is the smallest key under the child to its right.

`from_sorted`, `try_clone` and the set algebra all build through it. A built
map with fewer than four nodes still gets the four nodes of a first
allocation.

### Atomic failure

Before an insert changes anything, it reserves `height + 1` nodes, enough for
one split per level plus a new root. If that allocation fails, the call returns
`Err(AllocationFailed)`. The map, the caller's key and value, and the node
capacity are all unchanged. Replacement, removal, lookup and iteration never
allocate. `try_clone` and `from_sorted` either return a complete map or
allocate nothing.

### Memory

A node takes `16·size_of(KeyCell<K>) + 16·size_of(ValueCell<V>) + 100` bytes.
A key or value narrower than 8 bytes still takes an 8-byte word. For `u64` keys
and values that is 356 bytes per node, or 22–40 bytes per entry depending on
how full the leaves are. Inner nodes also carry unused value slots. Memory is
never returned until `destroy`.

## Set

`alloc::btree_set::BTreeSet<T>` holds the keys of a `BTreeMap<T, Nothing>`.
The value is zero-sized, so the value array is a single word. Its
representative rules follow [`alloc::tree_set`](stdlib-tree-map.md):

- **Insert:** `try_insert(key)` returns `Ok(None)` when it stores the key. When an equal key is already stored, it keeps the stored representative and returns `Ok(Some(supplied))`.
- **Replace:** `try_replace(key)` stores the supplied key and returns the displaced one.
- **Lookups and removal:** `get` returns the stored representative. `remove`, `pop_first` and `pop_last` hand it to the caller.

The rest of the API is `new`, `from_sorted(View<T>)`, `len`, `is_empty`,
`node_capacity`, `contains`, `first`, `last`, `lower_bound`, `upper_bound`,
`iter`, `range`, `try_clone`, `clear` and `destroy`. `Cursor<T>` is an
`Iterator` and a `DoubleEndedIterator`, and the two sinks work as for the map.
Errors are `alloc::btree_map::Error` and `SinkError`.

`try_union`, `try_intersection`, `try_difference` and
`try_symmetric_difference` work in two linear passes:

- **Count:** merge both sets in key order and count the result.
- **Build:** merge again into an exactly sized builder.

That is O(n + m) comparisons, against O((n + m) log(n + m)) for `tree_set`'s
insert-per-key approach. For equal keys the left operand's representative is
kept. An operand may alias the other. On `Err` nothing is allocated and both
sources are unchanged. `is_subset`, `is_disjoint` and `equals` are linear merges
that stop at the first deciding key.

## Tests

`tests/stdlib_btree_map_execution.rs` runs five fixtures in
`tests/fixtures/stdlib_btree_map/`:

- **`model.lani`** runs random inserts, replacements, removals and pops against `alloc::tree_map` as the reference, over key spaces of 40, 3,000 and 200,000. After every phase it compares length, endpoints, `lower_bound`/`upper_bound`, forward, backward and mixed iteration, and random ranges. It then drains the map and refills it. Two deliberate bugs were caught: a range cursor's back position off by one (exit 119), and a wrong divider when borrowing from the right sibling (exit 103).
- **`types.lani`** covers:
  - every signed and unsigned width, `isize`, `usize`, `bool`, `char` and `TotalF32`, plus `String` keys and values;
  - 600 record values across splits and merges;
  - a record key with its own `Ord`, where an equivalent insert replaces the stored key;
  - zero-sized keys and values, including a 5,000-key set with a range count.
- **`failure.lani`** works without fault injection. It lowers the soft `RLIMIT_AS` to 48 MiB and inserts until the map returns `AllocationFailed`. It then checks that the length, the node capacity, every entry, both cursor directions and lookups are unchanged, and that replacing an existing key still works. It also calls `try_clone` under the limit. In practice that returns `AllocationFailed` with the map unchanged; a clone that does fit is checked to be complete. Finally it restores the limit, retries the failed insert (which succeeds) and drains the map.
- **`bulk.lani`** runs `from_sorted` at 22 sizes that sit around every leaf and inner-node boundary, from 0 to 70,000. Each built map is checked entry by entry from both ends, along with its misses, endpoints and exact node count. It is cloned and the clone edited independently, then edited at random against `alloc::tree_map`, so removal repair runs on built nodes, and cloned again. The fixture also covers order errors at four positions, a negative builder count, an abandoned partial build and both sinks. A wrong separator key was caught (trap).
- **`set.lani`** runs 30,000 random inserts, replacements, removals and queries (bounds, endpoints, ranges) against `alloc::tree_set` over three key spaces. Each set is then cloned and drained from both ends. It checks all four set operations, `is_subset`, `is_disjoint` and `equals` on twelve random pairs, including empty and aliased operands, plus `from_sorted`, the sinks and the representative rules on a record key. Two deliberate bugs were caught: wrong difference sides (exit 43), and the right operand's representative winning a union (exit 65).

All five fixtures exit 0 when built with the resident compiler. The Rust test
also runs the shared x86 jump check on each executable. As of 11-02 that check
rejects the dead CRT-bridge calls (`call 0x400088`) that every multi-object
executable currently contains. That is a linker issue being handled on `lang`,
the same failure seen in `alloc_vec` and `alloc_deque`. It is not a map defect.

## Performance

`tests/fixtures/stdlib_btree_map_perf/bench.lani` uses 1,048,576 keys and
`bench.cpp` runs the same workload on `std::map` (g++ -O2). The AVL column is
the same bench with `alloc::tree_map` substituted. It extends the
[tree map bench](stdlib-tree-map.md) with three more phases:

- **scattered:** look up every key in the order `(i·40503) mod N`;
- **sorted** (i32 only): look up every key in key order;
- **iterate:** walk every entry in key order.

The table shows best-of-3 times in milliseconds on the RTX 3070 laptop's CPU,
at load average 7–10. Other jobs share the machine, and repeated runs of the
same binary differ by up to 20%.

| Phase | BTreeMap | TreeMap (AVL) | std::map |
| --- | ---: | ---: | ---: |
| u64 insert | 687 | 770 | 104 |
| u64 hit (insertion order) | 517 | 293 | 46 |
| u64 scattered | 688 | 752 | 565 |
| u64 miss | 513 | 281 | 47 |
| u64 iterate | 95 | 209 | 106 |
| u64 remove half | 452 | 446 | 72 |
| u64 half hit | 471 | 313 | 130 |
| u64 remove rest | 387 | 396 | 68 |
| i32 insert | 759 | 867 | 69 |
| i32 hit (insertion order) | 538 | 289 | 50 |
| i32 scattered | 696 | 806 | 441 |
| i32 sorted (key order) | 270 | 349 | 129 |
| i32 miss | 201 | 185 | 10 |
| i32 iterate | 98 | 216 | 108 |
| i32 remove half | 414 | 415 | 58 |
| i32 half hit | 524 | 284 | 82 |
| i32 remove rest | 363 | 377 | 49 |

### Where lookup time goes

**Iteration and key-order lookups** are the B+ tree's best cases. Iteration is
about 2.2x faster than the AVL map and slightly faster than `std::map`.
Lookups in key order are 23% faster than AVL.

**Insertion order is not key order.** Both key sets come from Fibonacci
hashing of the insertion index, so successive "hit" lookups are spread across
the key space. A tree with one node per key, allocated in that order, still
gets locality from it. The nodes on successive search paths sit next to
nodes the previous search touched, so `std::map` is faster in insertion order
(50 ms) than in key order (129 ms). A B+ tree leaf holds keys inserted at many
different times, so it gets no such benefit. Its insertion-order time is about
the same as its scattered time. Scattered lookups are 8–14% faster than AVL.

**The remaining cost is generated code.** A probe with 4,096 keys, which stay
in cache, took about 210 ns per `get` for both Lanius maps and 44 ns for
`std::map`. Both trees make about log₂ n key comparisons. Each binary-search
step in `find` was 46 instructions plus a call to the 4-instruction
`i32::lt`:

- about 27 of them were stack loads and stores;
- the step re-copied the key view's three-word header (data, length, stride) into fresh stack slots on every `keys[i]`;
- it did a bounds check and a 64-bit `imul` by the run-time stride;
- it spilled `low`, `high` and `middle` and reloaded them;
- it ended with a jump to a jump.

g++ does the same step in about eight register instructions with the
comparison inlined. The library did build four views per `get`, and each view
was a call plus two header copies. `find` now builds its key and link views
inline and reads the counts through the links view, and `get` builds its value
view inline. That is about 5% faster in cache (1,830 to 1,740 ms for 8M gets)
and within noise at 1M keys.

The x86 backend then removed four of those costs (branch codegen1):

- the link writes a tiny leaf callee such as `i32::lt` or `u64::lt` (register-only, at most nine bytes) over its call slot;
- a view local written once is read from its own stack home, so there is no header copy;
- locals get the callee-saved registers by loop-weighted reads, so `low` and `high` live in R13 and R14;
- a branch to a jump goes straight to that jump's target.

After codegen1 a step was 37 instructions on one arm and 36 on the other,
with 18 or 19 stack operands. The cached probe went from 1,725 to 1,352 ms
for 8M gets (161 ns per `get`), and key-order lookups at 1M keys from 265 to
200 ns.

Branch codegen2 then freed the registers those spills were waiting for:

- a read the backend serves from the declaration's own home (a coalesced alias, or a parameter no call reaches) no longer holds a temporary register;
- an integer call argument takes a register instead of a stack home;
- a temporary needs a callee-saved register only when a call lies in its interval or in a loop that holds it;
- in a function with calls, parameters and locals share the four callee-saved registers by loop-weighted reads, so `low`, `high`, `middle` and `key` all get one;
- a call result that a branch tests at once stays in RAX.

A step is now 31 instructions on one arm and 34 on the other, with 6 stack
operands. Three of those operands read the key view's header, one reads `base`
(five hot declarations compete for four callee-saved registers), and two store
and reload the element address. Interleaved minimums on a shared machine:

| Probe phase (ms) | lang before codegen1 | codegen1 | codegen2 | `std::map` |
| --- | ---: | ---: | ---: | ---: |
| cached, 8M gets | 1,697 | 1,364 | 991 (118 ns per `get`) | 369 |
| 1M keys, key order | 263 | 199 | 126 | 133 |
| 1M keys, insertion order | 587 | 413 | 331 | 49 |
| 1M keys, scattered | 714 | 537 | 413 | 510 |

**Branch mispredictions, not instructions, were most of the cached cost.**
`perf` is not available to us here (`perf_event_paranoid` is 4), so variants
were timed instead. On the cached probe, the branching `find` took 815 ms with
the probe's keys and 375 ms when every get used the same key, so all its
branches were predicted. The same B-tree `find` compiled by g++ -O2 on the
same tree, still with branches, took 453 and 100 ms: about 350 ms of
mispredictions in both compilers. A branching node search therefore cannot
reach `std::map` (350 ms). The same search written with a select (g++ emits
CMOV) took 232 ms.

Branch codegen3 therefore:

- turns `if (c) { x = a; } else { x = b; }` and `if (c) { x = a; }` into a CMOV when the arms are a few arithmetic rows that cannot trap, call or write memory. The condition can be any 32-bit integer comparison or any Boolean value (a call result too), and a `!` is folded in. `if (c) { return a; } return b;` (or with `else`) becomes a CMOV into EAX when `c` compares values that were not just loaded, so `core::i32::min` and `max` are 7-byte bodies the link splices into their call slots. A return chosen by a call result or a loaded value stays a branch: it is usually a predictable found test, and as a CMOV it waits for a cache-missing key (the 1M-key scattered probe went 402 to 503 ms until this rule);
- computes the address of an index into a local view defined once by `slice_from_raw_parts` without the stride word (shift and subtract instead of a 64-bit `imul`);
- keeps an element address read only by the next field load in RAX instead of a stack slot;
- compares a bounds-checked index with the length in place, and gives `main` and other functions without parameters registers.

`find` now searches each node of a tree with at most 2,048 nodes (about
470 KB of keys and links, the size of the L2 cache) by halving a window whose
length depends only on the node's count, moving its start with a select. No
branch depends on the key. Larger trees keep the branching search
(`find_branching`). There the lookups wait on memory, and a branching search
lets the processor run ahead into the next loads. A select search at 1M keys
was about 25% slower in scattered and key order. `descend` and `lower_slot`
(insert, remove, bounds) keep their branches for the same reason.

| Probe phase (ms) | codegen2 | codegen3 | `std::map` |
| --- | ---: | ---: | ---: |
| cached, 8M gets | 986 | 651 (78 ns per `get`) | 369 |
| 1M keys, key order | 125 | 108 | 133 |
| 1M keys, insertion order | 314 | 301 | 49 |
| 1M keys, scattered | 386 | 376 | 510 |

The bench's phases moved by -27% to +14% against codegen2 on a shared
machine, within its run-to-run noise; inserts and 1M-key lookups were mostly
faster. A select step still has about 20 instructions
against g++'s 8. The `i32::lt` splice yields a 0/1 value (`setl; movzx`) that
the select then tests again, because the comparison is in another compile
unit and cannot be inlined before the link.

On the tree-map benchmark at 1M keys, B+ tree i32 hits went from 555 ms
(before codegen1) to 412 ms, and u64 hits from 681 to 376 ms. AVL i32 hits went
from 302 to 239 ms, and AVL u64 hits from 318 to 207 ms.
