# Deep cloning hash map memory owners

`alloc::clone_hash_map` adds explicit deep cloning and destruction to
`alloc::hash_map::HashMap<K,V>`. A successful clone owns independent keys,
values and table storage. Ordinary map `try_clone`, removal and `destroy`
keep their existing shallow behavior.

All four focused execution groups passed on Linux x86-64 through the GPU
compiler. The implementation is Lanius and uses the existing map and allocator
interfaces; runtime acceptance here covers that native target only.

## API and imports

Import `alloc::clone_hash_map` in the entry and in generic consumers that
select its protocol implementations. Nested vector values also require
`alloc::clone_vec` where their implementation is selected.

```lanius
pub enum Error<KE,VE> {
    Storage(alloc::hash_map::Error),
    Key(i32,KE),
    Value(i32,VE),
    ChangedKey(i32)
}

pub fn try_clone<K,V,KE,VE>(source: &alloc::hash_map::HashMap<K,V>)
    -> core::result::Result<alloc::hash_map::HashMap<K,V>,Error<KE,VE>>
    where K: core::hash::Hash<K>, K: core::cmp::Eq<K>,
          K: core::clone::TryClone<K,KE>, K: core::clone::Destroy<K>,
          V: core::clone::TryClone<V,VE>, V: core::clone::Destroy<V>;

pub fn destroy_hash_map<K,V>(owner: &alloc::hash_map::HashMap<K,V>)
    where K: core::clone::Destroy<K>, V: core::clone::Destroy<V>;
```

The same module implements
`TryClone<HashMap<K,V>,Error<KE,VE>>` with those clone bounds, and
`Destroy<HashMap<K,V>>` with only the two Destroy bounds. `KE` and `VE` select
the key and value error types independently. They need not be the same type.

For `HashMap<String,String>`, the selected error is
`Error<alloc::string::Error,alloc::string::Error>`. For
`HashMap<String,Vec<String>>`, it is
`Error<alloc::string::Error,alloc::clone::Error<alloc::string::Error>>`.
Nested failures retain both the map's live-entry ordinal and the vector's
element index.

## Source and key identity

The source is a read-only borrowed descriptor. The caller keeps its owners
alive and immutable throughout cloning. Success and recoverable failure
preserve source contents, stored key representatives, table fields and
existing borrowed views. The source may contain repeated borrowed value
descriptors: every successful leaf clone must still return a separate owner.
The source's actual owners remain the caller's responsibility.

Keys must obey lawful, stable Eq and Hash implementations. Equal keys must
hash equally, and a successful key clone must preserve the source key's
logical equality and hash. Cloning, hashing, comparison and destruction must
not reenter or mutate the map being processed.

After cloning each key, the helper checks its equality and hash against the
source key and checks for an equal key already in the destination. These
checks precede value cloning. A failed check returns `ChangedKey(index)` and
releases that key and the completed destination. An unexpected insertion
replacement also returns `ChangedKey` after releasing both affected pairs.
The helper never silently returns a clone with fewer entries. These checks
detect changed identity along the executed path; they cannot validate
arbitrary broken Eq, Hash, clone or ownership implementations.

Cloning follows `source.iter()` order. Each reported index counts only live
entries from zero, excluding deleted and empty buckets. It is neither a bucket
number nor an insertion-order promise. Collision chains and deletion holes do
not alter that definition. A successful clone preserves the stored key's
logical value; its capacity and traversal order may differ from the source.

## Failure ownership and allocation

The helper reserves destination table capacity for `source.len()` before any
leaf clone. It clones the key before the value of each pair. For valid stable
keys, later insertions require no table growth.

| Error | Meaning and cleanup |
| --- | --- |
| `Storage(error)` | Preserve the exact map capacity, overflow or allocation error; release any completed destination owners. |
| `Key(index,error)` | Key cloning failed at this live-entry ordinal; release completed destination pairs. |
| `Value(index,error)` | Value cloning failed at this ordinal; release its already cloned key and completed destination pairs. |
| `ChangedKey(index)` | Key identity checks or an unexpected replacement failed; release all owners acquired by this call. |

The failing leaf is responsible for its own partial construction. Its returned
error remains independently owned after map cleanup. An error may own memory
or borrow caller storage, but it must not borrow a partial destination that
cleanup releases. The helper retains the exact error payload without invoking
Destroy on it. The caller inspects and releases any error-owned resources
under that leaf's contract. Cleanup order is not an API guarantee.

An empty source returns an empty map without table allocation or key/value
callbacks. A nonempty map still allocates its hash table when keys and values
are zero-sized; the table needs occupancy metadata. Map capacity limits remain
those of `alloc::hash_map`, and nested costs remain those of the leaf protocols.
There is no aggregate nested-memory quota or execution deadline in this API.

With well-distributed lawful hashes, container work is expected O(n), plus
key hashing/comparison and leaf clone costs. Collisions can make lookups and
insertions O(n²) overall. Iteration and cleanup also scan table buckets. A
panic, invalid borrowed storage or a violating callback does not have the
recoverable cleanup guarantee.

## Destruction and mutation

`destroy_hash_map(actual_owner.borrow())` visits each live stored pair,
releases its key and value once, frees table storage and resets the actual
owner to empty with zero capacity. It walks live descriptors directly rather
than looking up keys after destroying them. It requires no Hash, Eq or
TryClone bound, allocates nothing, and permits repeated calls on the same
reset owner.

Every key and value must be one distinct active owner under its Destroy
implementation. A map holding borrowed String or vector descriptors is not
eligible merely because those types implement Destroy. Release such a map's
table shallowly and release its separate source owners once. A successful
deep clone satisfies the independent-owner requirement when its leaf
implementations honor the protocols.

End cursors and borrowed entry views before deep destruction. Old entry
copies, table views and owner aliases become invalid. Trait
`Destroy::destroy_value` consumes its passed descriptor; it cannot reset other
shallow copies elsewhere. Use the borrowed-owner helper when the active map
variable must be reset for reuse.

Remove a pair to transfer its owners before changing a key or growing a
nested String/vector. Reinsert the updated descriptors and handle the
insertion result, including any displaced pair. A copied descriptor returned
by `get` or iteration is a borrow; growing it can leave the descriptor stored
inside the map stale. The fixtures transfer a row out, transfer its String
out, grow the String, then restore both owners before recursive release.

These operations follow the existing [clone protocols](stdlib-clone.md),
[nested Vec ownership](stdlib-nested-clone.md) and
[manual ownership conventions](library-api-conventions.md). They add no
automatic moves, destructors or compiler-enforced uniqueness.

## Focused verification

[`tests/stdlib_clone_hash_map_execution.rs`](../tests/stdlib_clone_hash_map_execution.rs)
uses the production stdlib and the
[hash map clone fixtures](../tests/fixtures/stdlib_foundation/clone_hash_map).
Its four runtime groups cover:

- String keys, shared borrowed String/nested Vec source values, independently
  owned destination leaves, imported generic TryClone/Destroy consumers,
  transfer and reinstallation after mutation, source preservation and repeated
  actual-owner destruction.
- Constant-hash collisions, deleted buckets, stored key representatives,
  distinct key/value error types, every selected live-entry ordinal and both
  leaf construction stages. Errors own binary String messages inspected only
  after source and destination cleanup. Separate checks reject changed Eq or
  hash identity before value cloning. Two deliberately unlawful callback cases
  exercise defensive duplicate/replacement cleanup without admitting those
  callbacks as lawful map keys.
- Every allocation reached by a bounded String/Vec/map fixture, including
  source setup, table reservation, key leaves, nested vector reservation and
  nested String leaves. Each injected ENOMEM must report the exact typed
  Storage/Key/Value/Element path and preserve the source before cleanup.
  Runtime type widths and observed table requests determine byte expectations.
- Empty maps whose leaf callbacks trap if invoked, and a nonempty lawful
  zero-sized key/value map whose source and clone own separate tables.

Each native process has a five-second timeout. Every produced ELF passes the
unchanged strict native transfer checker. The `strace` ledger checks every
successful mapping's exact address and requested length against its unmapping,
requires no remaining mappings, and checks that independently owned error
messages are released after other owners.

Native acceptance on 2026-10-25 covers Linux x86-64 user programs compiled by
the GPU compiler. The String/nested-value group passed 1/1 in 7.46 seconds;
the remaining three groups passed 3/3 in 11.71 seconds. This includes all 14
reached allocation-failure positions, 18 owned key/value errors, six Eq/hash
identity changes, two defensive duplicate/replacement cases, collision and
tombstone success, and the empty/zero-sized paths. The source implementation
does not impose a platform-specific ABI, but execution on other targets has
not been established. These receipts do not establish Wasm or GPU execution
of user programs.

Logs are `target/stdlib-work/clone-hash-map-contracts-first.log` and
`target/stdlib-work/clone-hash-map-failures.log`.

The serialized focused gate, after the required compiler build, is:

```sh
timeout --kill-after=2s 110s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test stdlib_clone_hash_map_execution -- --nocapture --test-threads=1
```
