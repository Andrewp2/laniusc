# B-tree ordered map

`alloc::btree_map::BTreeMap<K, V>` is an ordered map stored as a B+ tree. It
has the same ordering rules, `Entry`/`Cursor` shape and error style as
[`alloc::tree_map`](stdlib-tree-map.md), the AVL map. Use it when a workload
iterates in key order or looks keys up in no particular order. For lookups in
insertion order the AVL map is currently faster (see [Performance](#performance)).

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
| `clear()` | Drop every entry and keep the allocation | O(1) |
| `destroy()` | Release the allocation | O(1) |

`Cursor<K, V>` implements `core::iter::Iterator` (`next`) and
`DoubleEndedIterator` (`next_back`), and `is_empty()` reports when the two
ends have met. Steps are O(1), because leaves are linked in both directions. Any edit to the map invalidates its
cursors.

`Error` is `CapacityOverflow` (the node arrays would pass `i32::MAX` bytes),
`AllocationFailed` or `InvalidRange`.

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

### Atomic failure

Before an insert changes anything, it reserves `height + 1` nodes, enough for
one split per level plus a new root. If that allocation fails, the call returns
`Err(AllocationFailed)`. The map, the caller's key and value, and the node
capacity are all unchanged. Replacement, removal, lookup and iteration never
allocate.

### Memory

A node takes `16·size_of(KeyCell<K>) + 16·size_of(ValueCell<V>) + 100` bytes.
A key or value narrower than 8 bytes still takes an 8-byte word. For `u64` keys
and values that is 356 bytes per node, or 22–40 bytes per entry depending on
how full the leaves are. Inner nodes also carry unused value slots. Memory is
never returned until `destroy`.

## Tests

`tests/stdlib_btree_map_execution.rs` runs three fixtures in
`tests/fixtures/stdlib_btree_map/`:

- **`model.lani`** runs random inserts, replacements, removals and pops against `alloc::tree_map` as the reference, over key spaces of 40, 3,000 and 200,000. After every phase it compares length, endpoints, `lower_bound`/`upper_bound`, forward, backward and mixed iteration, and random ranges. It then drains the map and refills it. Two deliberate bugs were caught: a range cursor's back position off by one (exit 119), and a wrong divider when borrowing from the right sibling (exit 103).
- **`types.lani`** covers:
  - every signed and unsigned width, `isize`, `usize`, `bool`, `char` and `TotalF32`, plus `String` keys and values;
  - 600 record values across splits and merges;
  - a record key with its own `Ord`, where an equivalent insert replaces the stored key;
  - zero-sized keys and values, including a 5,000-key set with a range count.
- **`failure.lani`** works without fault injection. It lowers the soft `RLIMIT_AS` to 48 MiB and inserts until the map returns `AllocationFailed`. It then checks that the length, the node capacity, every entry, both cursor directions and lookups are unchanged, and that replacing an existing key still works. Finally it restores the limit, retries the failed insert (which succeeds) and drains the map.

All three fixtures exit 0 when built with the resident compiler. The Rust test
also runs the shared x86 jump check on each executable. As of 11-02 that check
rejects the dead CRT-bridge calls (`call 0x400088`) that every multi-object
executable currently contains. That is a linker issue being handled on `lang`,
the same failure seen in `alloc_vec` and `alloc_deque`. It is not a map defect.

## Performance

`tests/fixtures/stdlib_btree_map_perf/bench.lani` uses 1,048,576 keys and
`bench.cpp` runs the same workload on `std::map` (g++ -O2). The AVL column is
the same bench with `alloc::tree_map` substituted. It extends the
[tree map bench](stdlib-tree-map.md) with two more phases:

- **scattered:** look up every key in the order `(i·40503) mod N`;
- **iterate:** walk every entry in key order.

The table shows best-of-3 times in milliseconds on the RTX 3070 laptop's CPU,
at load average 7–8.

| Phase | BTreeMap | TreeMap (AVL) | std::map |
| --- | ---: | ---: | ---: |
| u64 insert | 860 | 772 | 109 |
| u64 hit (insertion order) | 676 | 303 | 50 |
| u64 scattered | 845 | 900 | 570 |
| u64 miss | 619 | 281 | 48 |
| u64 iterate | 95 | 210 | 108 |
| u64 remove half | 489 | 458 | 80 |
| u64 half hit | 562 | 321 | 144 |
| u64 remove rest | 487 | 399 | 76 |
| i32 insert | 861 | 922 | 70 |
| i32 hit (insertion order) | 670 | 309 | 51 |
| i32 scattered | 752 | 974 | 589 |
| i32 miss | 170 | 186 | 11 |
| i32 iterate | 96 | 221 | 110 |
| i32 remove half | 497 | 445 | 62 |
| i32 half hit | 584 | 303 | 93 |
| i32 remove rest | 474 | 394 | 49 |

How to read the table:

- **Iteration** is the clear win: about 2.2x faster than the AVL map and slightly faster than `std::map`, because leaves are contiguous runs of 16 entries.
- **Scattered lookups** are 6–23% faster than the AVL map.
- **Lookups in insertion order** are about 2x slower than the AVL map. The AVL map and `std::map` allocate nodes in insertion order, so a lookup in that order walks memory sequentially. The B-tree's binary search within nodes has no such locality, and when all keys fit in cache (4,096 keys) both maps take about 200 ns per `get`.
- **Against `std::map`**, most of the remaining gap is generated code. The backend lowers each `K::lt` and each slice access with more instructions than g++. That is a compiler-side cost, which the map's layout can't remove.
