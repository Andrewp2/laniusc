# Opt-in deep cloning and release for ordered maps

**Accepted on native Linux x86-64 using the GPU compiler**, with all five
canonical groups passing on 2026-10-25. Eleven compilation jobs produced eight
strict-checked ELF programs and three expected source rejections, followed by
24 native process runs. This establishes the tested native profile; it does
not establish Wasm or GPU execution of user programs.

`alloc::clone_tree_map` applies the [explicit clone protocols](stdlib-clone.md)
to `alloc::tree_map::TreeMap<K,V>`. Import it in the composition entry and
generic consumers that select its implementations. Ordinary map `try_clone()`
still copies entries shallowly, and ordinary `destroy()` releases node storage
without destroying keys or values.

## Surface

```lanius
alloc::clone_tree_map::try_clone<K,V,KE,VE>(source: &TreeMap<K,V>)
    -> Result<TreeMap<K,V>,alloc::clone_tree_map::Error<KE,VE>>
    where K: Ord<K>, K: Eq<K>, K: TryClone<K,KE>, K: Destroy<K>,
          V: TryClone<V,VE>, V: Destroy<V>

alloc::clone_tree_map::destroy_tree_map<K,V>(owner: &TreeMap<K,V>)
    where K: Destroy<K>, V: Destroy<V>
```

The module also provides `TryClone<TreeMap<K,V>,Error<KE,VE>>` for
`TreeMap<K,V>` with the helper's prerequisites, and
`Destroy<TreeMap<K,V>>` with only key/value Destroy prerequisites. Destruction
does not require cloning, equality or ordering. Error parameters select the
exact key and value protocols; use explicit arguments or a complete Result
annotation. Empty input still requires the selected static implementations.

String keys and values use their existing protocols. A value such as
`Vec<String>` requires the [opt-in Vec implementations](stdlib-nested-clone.md)
and has `alloc::clone::Error<alloc::string::Error>` as its value error. Nested
maps compose through this module's implementations in the same way.

## Construction and errors

The helper reserves final node storage and a staging `Vec<Entry<K,V>>` for the
source's live entry count before invoking a key or value clone. It visits the
source in sorted logical order, skipping physical holes and spare capacity.
Each entry clones its key first. Before cloning its value, the helper requires
`K::eq(source_key,cloned_key)` and neither `K::lt` direction. Then it clones the
value and stages the whole owned pair.

After all leaves succeed, `TreeMap::try_init_sorted` validates adjacent cloned
order and builds a balanced tree in the reserved final storage. That canonical
builder performs no allocation when the reserved capacity is sufficient. The
helper releases only staging backing after transferring its pairs to the map.
It does not sort or perform repeated logarithmic insertion.

```lanius
pub enum StorageError {
    Entries(alloc::vec::Error),
    Map(alloc::tree_map::Error)
}
pub enum Error<KE,VE> {
    Storage(StorageError),
    Key(i32,KE),
    Value(i32,VE),
    ChangedKey(i32)
}
```

| Error | Meaning and rollback |
| --- | --- |
| `Storage(Map(error))` | Final node reservation or canonical initialization failed; every completed pair and staging allocation is released |
| `Storage(Entries(error))` | Staging reservation or append failed; final backing and every completed pair are released |
| `Key(index,error)` | The key clone failed at the zero-based sorted entry index; completed pairs are released |
| `Value(index,error)` | The value clone failed; its fresh cloned key and all completed pairs are released |
| `ChangedKey(index)` | The cloned key failed the source-to-clone Eq/Ord equivalence checks, before that entry's value clone; the key and completed pairs are released |

A leaf clone releases its own partial result on failure. The helper extracts
KE or VE before rollback and returns it unchanged. An error can own a String
or another allocation; the caller inspects and releases that separate owner.
It must not borrow the failed destination or a completed prefix that cleanup
will release. Cleanup order is not a public guarantee.

Stable, lawful Eq/Ord and clone implementations remain preconditions. These
checks detect a changed cloned key; they cannot validate arbitrary broken
comparison implementations. A final adjacent-order rejection is
`Storage(Map(InvalidOrder))`, rather than a changed-key index. Source structure,
length, capacity, leaf contents and existing borrowed views remain unchanged
on success or recoverable failure. The source and its aliases must remain
physically backed and read-only throughout the call, including during leaf
callbacks.

## Ownership and release

Every successful destination key and value owns its resources independently
of the source and other cloned entries. A source map may instead contain
borrowed leaf descriptors, including repeated value handles. Release such a
source's outer storage and its separate original owners once; recursively
destroying borrowed leaves would be invalid.

`destroy_tree_map(&actual_owner)` visits live pairs, invokes key/value Destroy,
releases node storage and resets the actual map to empty with zero capacity.
Traversal uses integer node links and never compares already released keys.
Every entry must be a distinct active owner; no alias may mutate the map
during release. Repeating the helper on the same reset owner is harmless.
The by-value Destroy implementation consumes its descriptor and cannot reset
other stale copies. Old cursors, views and borrowed entries become invalid.

Map accessors return borrowed shallow descriptors. A key must be outside the
map while its ordering value changes: transfer its complete pair with remove
or pop, then reinstall through insertion. Value-only growth or replacement can
use the new [scoped update](stdlib-map-updates.md), whose callback must return
the latest V descriptor even when its separate R is a Result error. Its current
runtime scope is recorded separately in that guide. Growing an ordinary
accessor copy can still leave a stale stored descriptor. For a nested Vec value,
also transfer and reinstall any growing child String before returning the Vec.
A popped or replaced pair belongs to the caller and survives destruction of
the remaining map. The older clone receipts below retain their original scope.

There are no implicit moves, automatic Drop or panic cleanup. Destroy must
terminate without allocation, panic or reportable failure. Fallible resource
close operations require their own protocols.

## Costs and bounds

Excluding leaf operations and comparisons, clone construction takes O(n) work
and O(n) staging space for n live entries. Both backing reservations precede
leaf calls. Canonical initialization and rollback use the existing container
storage operations. Deep destruction takes O(n) traversal plus leaf release
costs, with no repeated AVL removal or comparisons.

Container counts and allocation bytes retain their existing i32 limits.
There is no aggregate nested-memory quota or deadline. An empty map clone
allocates nothing and invokes no leaves. Zero-sized keys can represent only
one distinct equivalence class under a lawful order; a map of such keys still
needs node metadata storage. Zero-sized staging entries follow Vec's existing
allocation-free capacity policy.

## Native acceptance evidence

`tests/stdlib_clone_tree_map_execution.rs` uses the production stdlib and the
durable `tests/fixtures/stdlib_foundation/clone_tree_map/` user root. It retains
the common strict native ELF checker. The five passing groups cover:

- String keys with String and nested Vec<String> values, repeated borrowed
  source values, holes, shallow-method behavior, independent mutation through
  transfer/reinstall, popped ownership, actual-owner reset/reuse, empty and
  valid zero-sized paths, and Destroy without clone/comparison prerequisites.
- Canonical sorted initialization rejecting nonempty owners, duplicates,
  reversed order and bad metadata without mutation; 24 initializations sharing
  one reserved allocation; allocation failure preserving an empty owner.
- A 15-allocation baseline and ENOMEM injection at every reached allocation,
  checking exact storage/key/value/nested-element errors, sorted indices,
  source contents/views/capacity and balanced live address/request-length
  ledgers. Runtime size_of establishes public record widths.
- Twelve owned key/value errors over three sorted indices and two partial
  leaf stages, plus three changed-key cases. Clone-call logs check key-before-
  value order and that changed-key rejection precedes value cloning. Each
  five-byte error mapping must outlive destination and source cleanup.
- Missing opt-in implementations and missing value clone or destruction
  prerequisites rejected at their actual source calls, including empty input.

The accepted receipts are under `target/stdlib-work/`:

| Receipt | Scope | Elapsed |
| --- | --- | ---: |
| `clone-tree-map-contracts-fixed.log` | Contract group: four native entries covering String/nested values, empty, ZST and Destroy-only bounds | 9.83 s |
| `clone-tree-map-failures-current.log` | Four remaining active groups: canonical init, all reached allocation failures, owned errors/changed keys and source rejections | 13.47 s |

These durations include compilation and checks, not isolated operation
benchmarks. The second historical receipt also lists the temporary diagnostic
probe as ignored; that probe harness has since been removed. The five active
groups and their assertions are unchanged.

The first admission exposed two compiler defects: portable local nominal
identity was not reattached to its defining declaration for checked layout,
and x86 constructor emission conflated field count with payload width. The
first caused LNC0047 detail 6 for the helper's Vec<Entry<String,String>>;
after its repair, the second caused the zero-sized contract fixture to fail
at native execution. Both were corrected before the receipts above passed.
Explicit helper-local types did not resolve the replay failure by themselves.
The retained [minimal diagnostic entry](../tests/fixtures/stdlib_foundation/clone_tree_map/probe_deep_string.lani)
and [fixture history](../tests/fixtures/stdlib_foundation/clone_tree_map/README.md)
record that sequence without adding a production workaround or weakening the
canonical assertions. Other compiler dependency entries retain their own
status.
