# Generic owned sets

`alloc::hash_set::HashSet<T>` and `alloc::tree_set::TreeSet<T>` own independent
resizable table storage. HashSet requires lawful `Hash<T>` and `Eq<T>` keys;
TreeSet requires a lawful total `Ord<T>`. Equal keys must hash equally, and the
relations must stay stable while a key is stored. Hash iteration order is
unspecified. Tree cursors visit keys in order.

## Representatives and ownership

Both sets implement the [fallible iterator sink](stdlib-iterator-collection-sinks.md).
An equivalent element rejects with the corresponding map engine's
`SinkError::Duplicate`; the stored representative remains unchanged. Allocation
failure is wrapped in `SinkError::Storage(Error)`. Bounded transfer returns the
incoming item and accepted-prefix progress, so callers can recover or release
rejected owners explicitly before source resumption.

Insertion makes every supplied or displaced representative explicit:

| Operation | Successful result | Ownership |
| --- | --- | --- |
| `try_insert(key)` | `None` when newly stored; `Some(key)` when an equivalent representative was already present | An existing representative stays stored. The supplied key is returned on duplicate. |
| `try_replace(key)` | `None` when newly stored; `Some(old)` when replaced | The supplied representative is stored; the displaced representative is returned. |
| `get(key)` | `Some(stored)` or `None` | The copy borrows any resources nested in the stored key. |
| `remove(key)` | `Some(stored)` or `None` | Returns the removed stored representative. The lookup argument remains a shallow lookup copy. |
| Tree `pop_first()` / `pop_last()` | `Some(stored)` or `None` | Returns the removed endpoint representative. |

On insertion `Err`, the supplied key remains with the caller and the set is
unchanged. Returned `Option<T>` values do not automatically destroy keys. A
manually owned String or another resource nested in a returned key needs the
same explicit cleanup as before insertion. By-value handle copies alias one
backing allocation; keep exactly one active owner.

`try_clone` and all algebra operations allocate independent container storage
and make **shallow key copies**. Resources nested in those copies remain
borrowed from their original owners. Keep those resources live and immutable
until every borrowing result is finished. Destroy result table storage before
reclaiming source-owned key resources. These operations do not implement deep
cloning or automatic destruction.

`clear` and `destroy` release no nested key resources. Remove or pop owning keys
and destroy their resources explicitly first. `destroy` releases the container
allocation and resets the handle for reuse. For example, a TreeSet of owned
Strings can be drained with `pop_first`, destroying each returned String, then
destroyed itself. A HashSet can take a fresh cursor, read one key, remove it,
and discard that cursor before repeating.

## Operations

Both sets expose `new<T>()`, fallible `with_capacity<T>(capacity)`, `borrow`,
`len`, `is_empty`, `capacity`, `contains`, `get`, the two insertion operations,
`remove`, `iter`, `try_reserve`, `try_shrink_to_fit`, `try_clone`, `clear`, and
`destroy`. Capacity reservation is for additional distinct keys. Negative
capacities return the underlying map's `InvalidCapacity`; unrepresentable
capacities return `CapacityOverflow` before allocation. Allocation failures
return `AllocationFailed`.

HashSet iteration uses `Iter<T>::next`. TreeSet uses
`Cursor<T>::next`, `next_back`, and `is_empty`, and adds `first`, `last`,
`pop_first`, `pop_last`, `lower_bound` (first key greater than or equal to the
query), `upper_bound` (first strictly greater key), and `range(lower, upper)`.
Ranges are half-open `[lower, upper)`; equivalent bounds are empty and descending
bounds return `alloc::tree_map::Error::InvalidRange`. Front/back consumption
shares one interval and never returns its middle element twice.

Mutations or destruction invalidate outstanding cursors and borrowed key views.
A recoverable allocation failure preserves contents, length, capacity, backing
allocation, and existing cursors. A duplicate retaining insertion changes
nothing. There is no trap recovery: a failing user hash/comparison, violated
owner invariant, or assertion terminates the native process.

## Queries and algebra

`equals`, `is_subset`, and `is_disjoint` compare membership. The fallible
`try_union`, `try_intersection`, `try_difference`, and
`try_symmetric_difference` return new sets. Both sources are read only; passing
one source as both operands is supported. Union and intersection keep the left
representative of equivalent keys. Difference keeps left-only representatives;
symmetric difference keeps the representative from whichever side contains the
key exclusively.

Every allocating operation constructs its destination before publishing it.
On failure, partial destination storage is released and both sources remain
unchanged. There is no in-place algebra API and no synonymous removal alias.

## Shared map engine boundary

The map modules remain the only implementations of allocation, hashing,
probing, tombstones, AVL links/rotations, and ordered cursor traversal. Sets
contain nongeneric scalar owner state, bound to the facade's key type `T`, and
use a private unit payload through the map's key-state helpers. Each helper
creates a temporary typed map view, delegates to that same map engine, and
writes every owner field back before returning, including recoverable errors.
Cursor helpers likewise delegate to the existing typed map cursors.

`KeyStorage`, `KeyCursor`, and the map `key_*` family are an internal module
boundary. Do not construct, copy, edit, mix schemas, or call these helpers from
application code. Exactly one typed facade owns its state; temporary typed
views never escape or become separate owners. Native key-width guards detect
layout mismatch; width equality is **not type identity** and does not authorize
reinterpreting another key type. These helpers are not an erased-container API.
There are no per-key-type implementations or copied map storage algorithms.

## Execution evidence and earlier dependency

`tests/stdlib_owned_sets_execution.rs` checks both original map controls, the
complete set operations, representative and resource ownership, an independent
mixed-operation model with deliberately colliding hashes, and failure of every
observed native allocation. The fixtures cover zero-sized lawful keys, wide
scalar keys, and mixed records containing manually owned Strings. Resource
traces check allocation address and size and detect leaks or double frees.

The model runs 3,200 operations across 25 edit/query/algebra commands with seed
`0x5e722026`, comparing both set engines with an independent ordered membership
and representative model. The allocation sweep covers growth, tombstone
reclamation, reserve/shrink, clone, all four algebra operations, self-aliasing,
capacity construction, and a resource-owning supplied key. Existing map
contracts, models, and allocation-failure gates also remain green. These native
execution tests target Linux x86-64.

The former nested `HashMap<T, Unit>` / `TreeMap<T, Unit>` wrapper shape remains
recorded in the [earlier compiler repros and controls](../tests/fixtures/stdlib_compiler_state/owned_sets/README.md).
The [owner-state admission](../tests/fixtures/stdlib_compiler_state/foundation_admission/README.md)
records the successful factoring lead, its exact base-source/compiler hashes,
and archived-base reproduction instructions. The production implementation
uses that shared state boundary; it does not claim that the earlier nested
receiver shape or general imported generic iterator/IO adapters were repaired.

## Existing consumers

The distinct-value programs use the production sets while preserving their
input, output, and error contracts:

- [Unsigned wrapping checksum](../sample_programs/unique_unsigned_total.lani): `HashSet<u32>` and canonical `core::u32::wrapping_add`.
- [Distinct Unicode scalar count](../sample_programs/unique_unicode_count.lani): `HashSet<char>`, including supplementary scalars and NUL.
- [Wide unsigned sum](../sample_programs/wide_unsigned_distinct_sum.lani): `TreeSet<core::wide_u64::WideU64>`.
- [Wide signed sum](../sample_programs/wide_signed_distinct_sum.lani): `TreeSet<core::wide_i64::WideI64>`.

The focused `distinct_consumers_keep_unicode_and_wide_identity_on_checked_sets`
execution group checks full-width identity, malformed input, native allocation
and I/O faults, and cleanup.
