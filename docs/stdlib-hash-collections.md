# Hash maps

`alloc::hash_map::HashMap<K, V>` provides generic hashed lookup with explicit
allocation errors. It owns one table allocation and has no host-service
dependency beyond the allocator.

## Key contracts

Stored-key insertion and same-key queries use `core::cmp::Eq<K>` and
`core::hash::Hash<K>`. The borrowed query methods below instead name Q and
a policy, while preserving the stored-key laws.
Equality must be reflexive, symmetric and transitive. Equal keys must have the
same hash. Hash/equality-relevant key contents must stay unchanged while stored.

Hash implementations exist for all integer widths, bool, char and owned String.
Narrow/32-bit integers use their widened 32-bit pattern. 64-bit integers and
size types fold the high word into the low one, multiply by an odd constant
and keep the product's high word (one multiply instead of eight FNV steps). String hashes its exact
UTF-8 bytes, including NUL, without normalization. Floating-point types have
no default Hash implementation; their existing IEEE equality is not an
equivalence relation for NaNs.

String hashing uses [FNV-1a](https://www.rfc-editor.org/rfc/rfc9923.html).
Hashing is deterministic and noncryptographic. This table does not provide
randomized or collision-resistant hashing for adversarial keys.

## Borrowed point queries

[Borrowed collection lookup](stdlib-borrowed-lookup.md) adds `contains_key_by`,
`get_by`, `get_entry_by`, `remove_by` and `update_value_by`. Q hashes once per
operation; a borrowed `Mapper<Pair<K,Q>,bool>` compares stored key first and
query second only after the full cached hash matches. Matching keys must have
the query hash and belong to one stored equivalence class. Queries allocate
no owned key; getters borrow stored representatives, and removal transfers
the actual stored entry. `alloc::string::TextKey` supplies String/Text policy.
All nine borrowed-lookup library groups and the migrated application pass
on native Linux x86_64 CPU output; the dedicated guide defines their scope.
The dedicated guide records current evidence separately from the older
hash-map receipts below.

## API and ownership

The map's [iterator sink](stdlib-iterator-collection-sinks.md) accepts
`Entry<K,V>` and rejects existing keys with `SinkError::Duplicate`, preserving
both the stored key and value. Storage failures are `SinkError::Storage(Error)`.
The ordinary `try_insert` operation below still returns a displaced entry on
replacement. Bounded transfer retains the accepted prefix and returns any
rejected incoming entry for explicit recovery.

```lanius
let counts: alloc::hash_map::HashMap<i32, i32> = alloc::hash_map::new();
let added: core::result::Result<
    core::option::Option<alloc::hash_map::Entry<i32, i32>>,
    alloc::hash_map::Error> = counts.try_insert(7, 12);
// Handle allocation errors and any displaced entry.
let count: core::option::Option<i32> = counts.get(7);
counts.destroy();
```

| Operation | Behavior |
| --- | --- |
| `new()` | Empty map, no allocation |
| `borrow()` | Reference to the actual owner for mutating helpers |
| `len()`, `is_empty()`, `capacity()` | Live size and capacity in entries |
| `contains_key(key)`, `get(key)` | Presence and optional copied value |
| `get_entry(key)` | Optional copied `Entry { key, value }`, including the stored key |
| `update_value(key, update)` | One lookup; missing returns None, present reinstalls callback Pair.first and returns Some(Pair.second), preserving the stored key; [current evidence](stdlib-map-updates.md) |
| `try_insert(key, value)` | Result containing the displaced entry, or None for a new key |
| `remove(key)` | Optional removed entry; does not allocate |
| `try_reserve(additional)` | Reserve for additional distinct keys; return resulting capacity |
| `try_shrink_to_fit()` | Compact to the smallest supported table for the live entries |
| `try_clone()` | Independent table allocation containing shallow key/value copies |
| `iter()`, `Iter.next()` | Borrowed scan returning optional copied entries |
| `clear()` | Discard entries, retain allocated capacity |
| `destroy()` | Free table storage and reset the owner for reuse |

Replacing an existing key does not allocate, even when the table is at capacity.
Both its old key and old value are returned. A failed insertion retains the
supplied key/value with the caller and preserves every existing entry and the
table allocation. Reserve, shrink and clone failures also preserve the source.

The [scoped value update](stdlib-map-updates.md) can grow or replace an owned
value without removing its key. End prior borrows/cursors first; the callback
returns the latest V descriptor even when its separate result is an error.
The callback may not reenter this map or change key identity through aliases.
All seven new library gates pass on the finite native Linux x86_64 profile;
the dedicated guide records their scope and the accepted 103-case application. Older receipts below do not establish it.

The map copies values and does **not** deeply clone or destroy allocations
inside them. The application chooses their ownership:

- Borrowed keys/values must remain alive while the map uses them. The reporting
  application borrows group names owned by its group vector.
- For owned keys/values, transfer responsibility on successful insertion,
  destroy displaced/removed resources exactly once, and visit remaining
  entries to destroy their resources before clearing or destroying the table.
- Query/iterator results are shallow copies. Do not destroy a queried owned
  value while the table still needs it.
- Cloning the table does not create independent copies of nested resources.

A plain map-handle copy also aliases table storage. Keep one active owner.
Use `&HashMap` through `borrow()` when a helper may grow it. Destroying the
same reset handle twice is harmless; destroying stale copied handles is invalid.
These lifetime rules are not compiler-enforced.

Iteration order is unspecified. Every map mutation invalidates existing
iterators; reserve/shrink may relocate entries even when logical contents stay
the same. Repeated `next()` after exhaustion returns None. Iterators neither
allocate nor own table storage.

## Algorithm, capacity and failure

The table is a SwissTable-style open-addressed table, after
[Abseil's flat_hash_map design](https://abseil.io/about/design/swisstables).
One allocation holds the cells (cached 32-bit hash, key, value) and one
control byte per cell: empty, deleted, or seven bits of the spread hash. The
map multiplies a key's 32-bit hash by 2^64 divided by the golden ratio, so
identity hashes such as i32's still spread; the product's top seven bits are
the control tag and bits 32 and up pick the first group.

Probing reads aligned groups of eight control bytes as one u64 word and
matches them with SWAR bit tricks: the tag match is
`(x - 0x01..01) & !x & 0x80..80` on `x = word ^ tag * 0x01..01`, an empty
byte has its top two bits set, and the lowest marked byte comes from one
multiply. Only cells whose tag matches are read; their cached hash is
compared before key equality runs, so equality still sees only entries with
the same full hash. A probe ends at the first group that holds an empty
byte. Later groups follow triangular offsets, which visit every group of a
power-of-two group count once. One bounds-checked word load covers eight
cells, and building the two raw views needs no per-type stride probe.

At most half the cells are nonempty, counting deleted cells, so a probe
almost always ends in its first group. Removing an entry empties its cell
when the group already holds an empty byte (no probe path runs through such
a group); otherwise the cell becomes a deleted marker. Removing the last
entry resets every marker. Shrinking is explicit, so removal never fails
allocation.

Capacity counts permitted live entries, not physical slots. Deleted markers
can require an allocation to rebuild at the same capacity. Successful reserve
reclaims enough markers to allow the requested number of new distinct inserts.
Empty shrink frees storage. These details do not establish iteration order.

Errors are InvalidCapacity for negative additional capacity, CapacityOverflow
when counts or per-type storage exceed supported bounds, and AllocationFailed
when the allocator returns no storage. Table bytes are limited to `i32::MAX`;
the maximum entry count depends on the concrete key/value layout.

Lookup and mutation are expected constant time with well-distributed hashes,
with linear worst-case probes (every group, when all hashes collide). Rehash/clone/clear/iteration scan table capacity.
There is no constant-time guarantee for malicious or pathological hash functions.

## Execution evidence

On 2026-10-22, the two groups in `tests/stdlib_hash_map_execution.rs` passed
on x86_64 Linux using the GPU compiler:

- Basic APIs, stored false versus absence, replacement keys, independent
  table copies, invalid capacity and empty shrink/reset.
- 1,024 deterministic operations checked against a direct-index model.
  Every key hashes identically. Checks cover wraparound probing, deletion,
  reinsertion, growth, shrink, clone and iteration after each operation.
- Nested record values containing u64, an array and Option<bool>, integer
  widths, String keys/values, and a zero-sized record payload.
- Every allocation failed in turn across growth, deleted-marker cleanup,
  cloning, reserve and shrink. Existing contents and capacity are verified;
  syscall traces check complete cleanup, including owned String replacement.
- The CSV reporter uses this map and retains output order in a separate vector.

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test stdlib_hash_map_execution -- --nocapture
```

Native execution is established for x86_64 Linux. GPU user-program execution
and other hosts remain unverified. Keyed hashing and automatic destruction
remain work. Distinct borrowed-key point lookup has its separate contract and
acceptance above. Later
[shared cursor integration](stdlib-collection-iterators.md) and
[opt-in deep cleanup](stdlib-clone-hash-map.md) have separate accepted evidence.

## Performance at one million keys

[`bench.lani`](../tests/fixtures/stdlib_hash_map_perf/bench.lani) times six
phases on 1,048,576 keys: u64 keys spread by an odd multiplier, then dense i32
keys 0..N in shuffled order. [`bench.py`](../tests/fixtures/stdlib_hash_map_perf/bench.py)
(Python dict) and [`bench.cpp`](../tests/fixtures/stdlib_hash_map_perf/bench.cpp)
(`std::unordered_map`, g++ -O2) run the same keys, phases and checks.
Best of three interleaved rounds on 2026-10-31 on the development laptop,
in milliseconds per phase. Other jobs shared the machine (load average 17-20).

| Phase | before | after | C++ | Python |
| --- | ---: | ---: | ---: | ---: |
| u64 insert | 811 | 503 | 212 | 262 |
| u64 hit | 458 | 284 | 27 | 196 |
| u64 miss | 425 | 129 | 33 | 209 |
| u64 remove half | 239 | 144 | 83 | 111 |
| u64 half hit | 599 | 204 | 26 | 232 |
| u64 remove rest | 263 | 170 | 75 | 124 |
| i32 insert | 727 | 428 | 178 | 231 |
| i32 hit | 435 | 286 | 18 | 145 |
| i32 miss | 158 | 88 | 27 | 17 |
| i32 remove half | 205 | 199 | 39 | 41 |
| i32 half hit | did not finish | 258 | 20 | 204 |
| i32 remove rest | did not finish | 184 | 31 | 38 |

Before, linear probing with the identity i32 hash packed the dense keys into
one run of a million slots. After half were removed, each lookup of a removed
key scanned tombstones to the end of the run; the phase had not finished
after four minutes. Group probing with the spread hash ends at the first
group with an empty byte.

The remaining gap to C++ is mostly generated code, not probing. In the
current x86_64 backend every named constant is a call, aggregates (slices,
records, Option, Result) are copied through memory with `rep movsq`, constant
shift amounts keep their range check, and every value round-trips through the
stack. On a cache-resident 1,024-key map, a hit costs about 50 ns and a miss
about 27 ns. Hits at one million keys add a cache miss on the cell. Python and C++ also gain from this benchmark's order: they store entries
in insertion order, so in-order lookups touch memory sequentially.

[`model.lani`](../tests/fixtures/stdlib_hash_map_perf/model.lani) and its
[`oracle.py`](../tests/fixtures/stdlib_hash_map_perf/oracle.py) check five
seeded histories (219,000 operations: 92,116 inserts, 93,885 removes, 32,999
lookups) against a Python dict, word for word. Each history is insert-heavy,
then remove-heavy, then mixed. Two use u64 keys, and three use keys whose
hashes all collide, fall into seven classes, or are the identity. The
histories also cover checkpoints of length and an order-free iteration
digest, shrink, clone, clear, and partial `take_iter` consumption followed
by `take_remaining`. Making removal always empty the cell, which breaks
probe paths, fails the oracle at operation 16,402.

## Hash sets and the earlier wrapper dependency

[HashSet](stdlib-owned-sets.md) now executes through this map's shared owner-state
boundary, including representative ownership, algebra and allocation failures.
The earlier nested generic wrapper shape remains preserved in the
[dependency reproduction](../tests/fixtures/stdlib_foundation/hash_set_dependency/README.md).
The production factoring does not repair that compiler source shape or establish
general imported generic adapter support.
