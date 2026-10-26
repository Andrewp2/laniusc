# Opt-in deep cloning and release for ordered sets

**Accepted on native Linux x86-64 using the GPU compiler**, with all five
groups passing on 2026-10-25. Ten compilation jobs produced eight strict-checked
ELF programs and two expected source rejections, followed by 17 native process
runs. This establishes the tested native profile; it does not establish Wasm
or GPU execution of user programs.

`alloc::clone_tree_set` applies the [explicit clone protocols](stdlib-clone.md)
to `alloc::tree_set::TreeSet<T>`. Import it in composition entries and generic
consumers that select its implementations. Ordinary `TreeSet.try_clone()`
continues to copy keys shallowly, and ordinary `destroy()` releases only node
storage. The [set representative contracts](stdlib-owned-sets.md) are unchanged.

## Surface

```lanius
alloc::clone_tree_set::try_clone<T,E>(source: &TreeSet<T>)
    -> Result<TreeSet<T>,alloc::clone_tree_set::Error<E>>
    where T: Ord<T>, T: Eq<T>, T: TryClone<T,E>, T: Destroy<T>

alloc::clone_tree_set::destroy_tree_set<T>(owner: &TreeSet<T>)
    where T: Destroy<T>
```

The module provides `TryClone<TreeSet<T>,Error<E>>` for `TreeSet<T>` with the
helper's bounds and `Destroy<TreeSet<T>>` with only `T: Destroy<T>`. Destruction
needs no equality, ordering or clone implementation. Use explicit type/error
arguments or a complete expected Result to select the leaf's error contract.
Empty input still requires the selected static implementations.

String keys use their existing `TryClone<String,alloc::string::Error>` and
Destroy implementations. Both the direct helper and an imported generic
consumer use the same construction and cleanup path.

## Construction, identity and errors

The helper reserves final node storage for the source's live key count before
calling any leaf clone. It visits keys in sorted logical order, excluding
physical holes and spare capacity. Each successful leaf must be an
independent owner with the same logical value and representative content.

Before insertion, the helper requires `T::eq(source_key,cloned_key)` and
neither `T::lt` direction. It also checks that the previous cloned key is
strictly less than the new clone. The final set is built through ordinary
checked insertion into its reserved backing. A duplicate representative
returned by insertion is rejected and released; it is never silently dropped.

```lanius
pub enum Error<E> {
    Storage(alloc::tree_map::Error),
    Element(i32,E),
    ChangedKey(i32)
}
```

| Error | Meaning and rollback |
| --- | --- |
| `Storage(error)` | Node reservation or checked insertion failed; any fresh clone and all completed destination owners are released |
| `Element(index,error)` | Leaf cloning failed at the zero-based sorted logical index; the completed prefix and node backing are released |
| `ChangedKey(index)` | A source-to-clone Eq/Ord or adjacent-order check failed, or insertion returned a duplicate clone; that clone, the completed prefix and backing are released |

A failing leaf releases its own partial result. The helper extracts E before
rollback and returns it unchanged. E can own a String or other memory, which
the caller inspects and releases separately. It must not borrow a partial
destination or completed prefix that cleanup releases. Cleanup order is not
a public guarantee.

Stable, lawful Eq/Ord and clone implementations remain preconditions. The
guards detect the stated identity/order failures; they do not validate
arbitrary broken comparators or every observable property of a leaf. The
source, its keys and other aliases must remain physically backed and read-only
through the call, including callbacks. Source contents, representatives,
length, capacity, existing key views and cursors survive success or recoverable
failure.

## Ownership, mutation and release

Each successful cloned key owns its resources independently of source keys
and other results. Source keys may instead be borrowed shallow descriptors.
Such a source owns its outer backing only: release the separate original key
owners once, rather than recursively destroying borrowed entries.

`destroy_tree_set(&actual_owner)` visits initialized live keys, invokes Destroy,
releases node backing and resets the actual set to empty with zero capacity.
The cursor follows integer links without comparing released keys. It requires
one distinct active owner per key and no reentrant mutation of the set.
Repeating release on the same reset owner is harmless. The by-value Destroy
implementation consumes its descriptor and cannot reset stale aliases. Old
key copies and cursors become invalid.

Set accessors return borrowed shallow keys. Transfer a complete key with
remove or pop before an owning mutation, especially before growth or a change
to its ordering value, then insert the updated descriptor. A popped or replaced
key remains owned by the caller and survives release of the remaining set.
An unsuccessful insertion retains its supplied input; duplicate retaining
insertion returns that supplied key for recovery. These ordinary ownership
rules also apply outside the deep-clone module.

There are no implicit moves, automatic Drop or cleanup after a trap. Destroy
must terminate without allocation, panic or reportable failure. Resources with
fallible close operations require their own protocols.

## Construction cost and limits

For n live keys, construction performs O(n log n) comparisons and tree work,
plus leaf cloning and failure cleanup. It uses O(n) destination node storage
with no staging allocation. One node reservation precedes all leaf calls;
subsequent checked inserts reuse that reserved capacity. Deep release takes
O(n) traversal plus leaf release costs, without comparisons or repeated AVL
removal.

This implementation reuses TreeSet's existing shared map engine. There is no
new sorted-key initialization API, exposed unit payload, copied Node layout,
raw schema cast or parallel balancing algorithm. Linear bulk construction
would require a separate canonical sorted-key engine boundary; it is not the
construction cost claimed here. The choice of checked inserts is independent
of compiler replay behavior.

Node counts and allocation bytes retain the map engine's existing i32 limits.
There is no aggregate nested-memory quota or deadline. Empty cloning allocates
nothing and calls no leaf. A lawful zero-sized key has only one distinct
equivalence class; a nonempty set still allocates structural node metadata.

## Native acceptance evidence

`tests/stdlib_clone_tree_set_execution.rs` uses the production stdlib and
`tests/fixtures/stdlib_foundation/clone_tree_set/` as its durable user root.
It keeps the unchanged common strict native ELF checker. Five passing groups
cover ten compilation jobs: eight positive programs and two expected source
rejections. The positive fixtures cover 17 native process runs:

- String owners, imported generic protocol selection, source holes and spare
  capacity, ordinary shallow clone behavior, independent edits through actual
  transfer/reinstall, pop ownership, repeated reset, reuse, empty/ZST behavior,
  and destruction without clone or comparison bounds.
- Nine reached allocation positions: four original Strings, source backing,
  one final destination reservation and three leaf clones. Each injected ENOMEM
  checks exact Storage/Element errors, sorted indices, source views/capacity
  and balanced live address/request-length mappings.
- Six owned errors across three sorted indices and two partial-construction
  stages, plus six Eq-only/Ord-only changed-key cases. Clone/release counters
  check exact prefix/current-owner cleanup. Error message mappings are released
  only after all source and destination mappings have ended.
- Construction at 64 and 512 keys, with reported comparison/equality/clone/
  release counts and exactly one source plus one destination backing allocation
  per size. A 512-state ordered edit/query/clone model checks full contents
  against an independent array model internally and compares every emitted
  count/representative digest with Rust BTreeMap.
- Absent opt-in destruction and a contradictory explicitly selected leaf error
  reject at their actual source calls, even on empty input.

The cost checks make the chosen construction path observable; they are not a
timing benchmark. The comparison counter keys borrow test instrumentation and
own no nested allocation; String fixtures establish real independent memory
ownership.

The accepted receipts are under `target/stdlib-work/`:

| Receipt | Scope | Elapsed |
| --- | --- | ---: |
| `clone-tree-set-contracts-first.log` | Contract group: four native entries covering String owners, empty/ZST and Destroy-only bounds | 9.61 s |
| `clone-tree-set-model-failures-current.log` | Remaining four groups: all reached allocations, owned errors/key changes, ordered model/construction counts and source rejections | 10.73 s |

These times include compilation and checks, not isolated operation benchmarks.
The latter receipt uses the corrected fixture whitespace; it records the
expected AssignMismatch diagnostic inside the passing contradictory-error
group. The canonical assertions were retained.
