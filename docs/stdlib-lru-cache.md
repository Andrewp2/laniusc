# LRU cache

`alloc::lru::LruCache<K, V>` holds at most a fixed number of entries and
evicts the least recently used one when a new key arrives at a full cache.
Keys need `core::hash::Hash<K>` and `core::cmp::Eq<K>`.

```lani
let cache: alloc::lru::LruCache<Key, u64> = alloc::lru::with_capacity<Key, u64>(128).unwrap();
let outcome: alloc::lru::Put<Key, u64> = cache.put(key, 7);
let hit: core::option::Option<u64> = cache.get(key);   // also makes key the newest
cache.destroy();
```

## Structure

One node arena holds every entry. Each node sits on two intrusive lists at
once: its hash bucket's chain (singly linked) and the recency list from
newest to oldest (doubly linked). The bucket table has the least power of two
at least the capacity, so the load factor never exceeds one and chains are
short. Nodes store the key's full 32-bit hash; equality runs only for nodes
whose stored hash matches. Removed nodes go on a free list.

The cache does not use `alloc::hash_map::HashMap` as its index. That map
reclaims tombstones by rehashing into a new allocation and clears its whole
table when its last entry is removed, so lookups through it could allocate or
take time proportional to the capacity. The intrusive chains have no
tombstones: removal unlinks the node.

## Operations

| Operation | Behavior |
| --- | --- |
| `with_capacity<K, V>(limit)` | The only allocations: the node arena and the bucket table. InvalidCapacity below 1, CapacityOverflow above 2^30 entries or 2^31 - 1 bytes, AllocationFailed (anything allocated is released) |
| `len`, `capacity`, `is_empty`, `is_full` | Counts and predicates |
| `put(key, value)` | Store as the newest entry and return `Put`: `Inserted`; `Replaced(old)` when an equivalent key was stored (the new key is stored, the old entry is returned intact); `Evicted(oldest)` when the cache was full |
| `get(key)` | Value copy, and the entry becomes the newest |
| `touch(key)` | Make the entry the newest; false when absent |
| `peek(key)`, `contains(key)` | Read without changing recency |
| `remove(key)` | Transfer the entry, or None |
| `pop_oldest` | Transfer the entry `put` would evict next |
| `oldest`, `newest` | Copies of the two ends |
| `iter` | Borrowed `Cursor`: `next()` newest first, `next_back()` oldest first, one shared remainder; `ExactSizeIterator` |
| `clear` | Discard every entry shallowly; capacity is kept |
| `destroy` | Release both allocations; entries are not destroyed |

**Eviction order** is exact: recency is changed only by `put`, `get` and
`touch`, each of which makes its entry the newest; `peek`, `contains`, `oldest`,
`newest` and iteration never change it. `put` on a full cache evicts the
oldest entry, after looking the key up, so replacing a stored key never
evicts.

**Cost.** Every operation except construction, `clear` and `destroy` does one
hash, one bucket-chain walk and a constant number of list relinks. With load
at most one, the expected chain length is below one node for well-distributed
hashes, so each operation is O(1) expected; a hash function that maps many
keys to one value degrades the walk to the number of colliding keys. No
operation after construction allocates, frees, rehashes or touches more than
a constant number of nodes. `clear` takes one step per stored entry.

**Ownership.** Keys and values are shallow copies; no destructor runs. Entries
returned by `put`, `remove` and `pop_oldest` transfer their cleanup authority
to the caller. Drain owners with `pop_oldest` before `destroy`. Cursors borrow
the cache: end them before mutating it.

## Evidence

`tests/fixtures/stdlib_fixed_capacity_lru/model/model.lani` and `oracle.py`
(registered as `tests/stdlib_fixed_capacity_lru_model_execution.rs`) compare
96 seeded cases and 11,346 commands, 78,931 response words, exactly with a
Python reference. The LRU reference is an `OrderedDict` kept oldest first.
The LRU part runs 5,913 operations over 24 caches of capacity 1 to 64: 741
hits, 3,106 misses, 282 replacements, 378 evictions, 963 snapshots
(3,637 entries listed in both directions) and 1,890 two-ended cursor pulls,
plus 168 capacity probes (0, -1, above 2^30 and above the byte limit).

Keys count their own hash and equality calls. Every keyed operation hashes
exactly once and every other operation not at all. For keys with injective
hashes, equality runs exactly once per successful lookup and never on a
miss. For keys whose hash takes only four values, the 1,568 equality calls
are each checked to lie between the hit count and the number of stored keys
with the same hash. Four corrupted transcripts are rejected. Five
deliberately broken engines all fail the model: `get` without promotion,
eviction of the newest entry, the wrong victim for a full front overwrite of
a ring, truncating pushes that split a scalar, and a swap-remove that keeps
the old length. The oracle and native process take 0.21 s.

`tests/fixtures/stdlib_fixed_capacity_lru/direct/lru_scale.lani` runs the same
four-million-operation mix (puts with eviction, gets, touches, removes) at
1,024 and 1,048,576 entries and prints nanoseconds. On the laptop target
it measured 1.78 s and 3.53 s: 0.44 and 0.88 µs per operation for a 1,024
times larger cache whose 52 MB arena no longer fits in the CPU caches.

All receipts use the prebuilt compiler through `lcc` on native Linux x86_64.
The registered Rust test was not compiled or run (no cargo in this
increment); its expected summary is the oracle's output above.
