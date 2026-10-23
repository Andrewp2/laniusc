# Hash maps

`alloc::hash_map::HashMap<K, V>` provides generic hashed lookup with explicit
allocation errors. It owns one table allocation and has no host-service
dependency beyond the allocator.

## Key contracts

Keys implement `core::cmp::Eq<K>` and `core::hash::Hash<K>`.
Equality must be reflexive, symmetric and transitive. Equal keys must have the
same hash. Hash/equality-relevant key contents must stay unchanged while stored.

Hash implementations exist for all integer widths, bool, char and owned String.
Narrow/32-bit integers use their widened 32-bit pattern; 64-bit integers and
size types hash a little-endian 64-bit representation. String hashes its exact
UTF-8 bytes, including NUL, without normalization. Floating-point types have
no default Hash implementation; their existing IEEE equality is not an
equivalence relation for NaNs.

String and 64-bit hashing use [FNV-1a](https://www.rfc-editor.org/rfc/rfc9923.html).
Hashing is deterministic and noncryptographic. This table does not provide
randomized or collision-resistant hashing for adversarial keys.

## API and ownership

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

The table uses linear probing with empty/deleted/full states, following the
algorithm described in [Open Data Structures, section 5.2](https://opendatastructures.org/versions/edition-0.1f/ods-cpp/5_2_Linear_Probing.html).
At most half its slots are nonempty, counting deleted slots. Searches are
bounded by the slot count, including when every key collides.

This implementation caches full hashes, folds their high bits into the index,
and rebuilds transactionally before a write would exceed the load bound.
Removing an entry leaves a deleted marker; removing the last entry resets the
markers. Shrinking is explicit, so removal never fails allocation.

Capacity counts permitted live entries, not physical slots. Deleted markers
can require an allocation to rebuild at the same capacity. Successful reserve
reclaims enough markers to allow the requested number of new distinct inserts.
Empty shrink frees storage. These details do not establish iteration order.

Errors are InvalidCapacity for negative additional capacity, CapacityOverflow
when counts or per-type storage exceed supported bounds, and AllocationFailed
when the allocator returns no storage. Table bytes are limited to `i32::MAX`;
the maximum entry count depends on the concrete key/value layout.

Lookup and mutation are expected constant time with well-distributed hashes,
with linear worst-case probes. Rehash/clone/clear/iteration scan table capacity.
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
and other hosts remain unverified. Keyed hashing, automatic/deep destruction,
borrowed-key lookup and shared iterator-protocol integration remain work.

## Hash sets and the earlier wrapper dependency

[HashSet](stdlib-owned-sets.md) now executes through this map's shared owner-state
boundary, including representative ownership, algebra and allocation failures.
The earlier nested generic wrapper shape remains preserved in the
[dependency reproduction](../tests/fixtures/stdlib_foundation/hash_set_dependency/README.md).
The production factoring does not repair that compiler source shape or establish
general imported generic adapter support.
