# Deep cloning hash set memory owners

`alloc::clone_hash_set` opts `alloc::hash_set::HashSet<T>` into explicit deep
cloning and destruction. A successful clone owns separate table storage and
independent keys with the same logical values and representatives. Ordinary
set cloning, insertion, removal and destruction retain their shallow policy.

All three focused execution groups passed on native Linux x86-64 through the
production GPU compiler. Runtime acceptance here covers that tested native
profile.

## API and selection

```lani
pub enum Error<E> {
    Storage(alloc::hash_map::Error),
    Element(i32,E),
    ChangedKey(i32)
}

pub fn try_clone<T,E>(source: &alloc::hash_set::HashSet<T>)
    -> core::result::Result<alloc::hash_set::HashSet<T>,Error<E>>
    where T: core::hash::Hash<T>, T: core::cmp::Eq<T>,
          T: core::clone::TryClone<T,E>, T: core::clone::Destroy<T>;

pub fn destroy_hash_set<T>(owner: &alloc::hash_set::HashSet<T>)
    where T: core::clone::Destroy<T>;
```

The same module implements `TryClone<HashSet<T>,Error<E>>` with those clone
bounds, and `Destroy<HashSet<T>>` with only the `Destroy<T>` bound. Destruction
does not require cloning, equality or hashing. It walks stored descriptors
directly, releases each key, then resets the actual outer owner through the
ordinary storage release. It never looks up a key after releasing its memory.

Import `alloc::clone_hash_set` in the composition entry and each generic
consumer selecting these implementations. String's existing leaf protocols
are selected by importing `alloc::string`:

```lani
import alloc::clone_hash_set;
import alloc::hash_set;
import alloc::string;
import core::result;

fn duplicate(source: &alloc::hash_set::HashSet<alloc::string::String>)
    -> core::result::Result<alloc::hash_set::HashSet<alloc::string::String>,alloc::clone_hash_set::Error<alloc::string::Error>> {
    return alloc::clone_hash_set::try_clone<alloc::string::String,alloc::string::Error>(source);
}
```

## Source representatives and identity

Keep source owners alive and immutable throughout cloning, including mutation
through aliases. Source contents, representatives, capacity and existing
iteration observations remain unchanged on success or recoverable failure.
The helper uses only public set operations over the existing shared map engine.
It adds no bucket representation, layout casts or alternate hashing engine.

Cloning follows `source.iter()` order. Each error index counts live entries
from zero, excluding tombstones and empty slots. It is not a bucket number or
an insertion-order promise. Destination capacity and traversal order may differ
from the source, while each stored representative's logical value is preserved.

Equality and hashing must be lawful and stable: equal keys hash equally, and
a successful leaf clone preserves equality and the hash of its source key.
Clone, Eq, Hash and Destroy callbacks must not reenter or mutate either set.
After each leaf succeeds, the helper checks Eq and hash identity and checks
for an existing equal destination key before insertion. A failed check returns
`ChangedKey(index)` after releasing the current key and completed destination.
If insertion unexpectedly returns a key, that returned owner is also released
separately before destination cleanup. The helper never silently succeeds with
fewer entries. These checks do not validate arbitrary broken traits or owner
aliases.

## Allocation and rollback

The destination reserves capacity for the complete source length before calling
any leaf. Empty sets require no table allocation or leaf calls. A nonempty set
of zero-sized keys still allocates a table for slot metadata; each leaf receives
its own clone and destruction call.

| Error | Cleanup contract |
| --- | --- |
| `Storage(error)` | Preserve the underlying capacity, overflow or allocation error; release acquired destination owners. |
| `Element(index,error)` | Release the completed destination prefix and table; transfer the leaf's `E` unchanged. |
| `ChangedKey(index)` | Release the current cloned key and completed destination owners. |

On `Err(E)`, the failing leaf is responsible for releasing its own partial
construction. `E` keeps its own lifetime and cleanup contract. It may contain
independently owned memory or borrow caller storage, but cannot borrow a partial
destination that rollback releases. The caller releases any owned error payload.

Each destination key must be a separate owner. A source may contain keys that
borrow the same nested backing while their distinct Eq identities remain valid;
each successful clone must still acquire independent backing. Such borrowed
source handles do not gain cleanup authority. Release their actual original
owners once, and release only the source's outer table shallowly.

All selected `Destroy` implementations must finish without allocation, panic
or reportable failure. These are explicit memory-owner protocols; they do not
introduce automatic cleanup, moves, reference counting or fallible resource
closing. There is no aggregate quota on nested key allocations. Iteration scans
the source table, and Eq/Hash collisions retain the shared engine's costs.

## Transfer before mutation and release

Lookups and iterator results borrow stored keys. Transfer a key with `remove`
before changing its bytes or growing its backing storage, then reinstall the
updated descriptor with `try_insert` or `try_replace`. Handle any returned
duplicate/displaced owner and failed input according to the ordinary set API.
Changing Eq or Hash identity while a key remains installed violates the set's
contract.

Call `destroy_hash_set(owner.borrow())` on the actual active owner to leave it
empty and reusable. Repeating it on that reset owner does nothing. By-value
`Destroy<HashSet<T>>` consumes only the passed descriptor; stale shallow aliases
cannot be reused or destroyed afterward. Deep destruction requires cleanup
authority for every live entry. Copies of an owner are aliases, not extra owners.

## Focused execution gate

The Linux x86-64 gate is:

```sh
cargo test --test stdlib_clone_hash_set_execution -- --test-threads=1
```

Receipt: [`target/stdlib-work/clone-hash-set-native.log`](../target/stdlib-work/clone-hash-set-native.log)
records three passed groups and no failures in 15.05 seconds. The run compiled
four entry programs and completed 43 native executions, including 557 model
cases within one process, six owned error paths, and all 39 reached allocation
failure positions.

Three groups compile four entry programs through the production compiler and
retain the strict shared native executable checker:

- Imported generic TryClone/Destroy selection for String keys, transfer before
  mutation, source independence, popped-owner lifetime, and repeated reset.
- Empty poison leaves, a type with only Destroy, and nonempty zero-sized keys.
  Mapping traces distinguish allocation-free empty sets from two independently
  owned nonempty zero-sized tables.
- Collision chains with a deletion hole, six owned errors across three live
  ordinals and two partial-construction stages, and a full successful clone.
  The generic error payload includes a high-bit integer, an array and its own
  String. All 39 reached allocation attempts are failed individually. Typed
  errors identify the exact failed stage and live ordinal. An address/size
  ledger checks complete cleanup, no double release and no new allocation
  after failure; the caller releases E after all other owners are gone.
- 557 bounded sequence/failure cases for insert, replace and remove. A simple
  key-to-representative map determines values; observed iteration supplies only
  the error ordinal definition. Clone events, cleanup owner sets and unchanged
  source observations are checked without modeling buckets. Deliberately
  unlawful Eq/hash clones also exercise ChangedKey and duplicate cleanup; they
  do not relax the lawful-trait preconditions.

These finite tests do not prove arbitrary leaf protocols or callback behavior
valid, or establish runtime acceptance on other targets.

The CPU oracle sanity check passed all 557 cases against an alternate sequence
model with both forward and reversed traversal observations, and checked all
39 allocation-path tags. That check validates the prepared oracle; it does not
execute the Lanius helper.

Sources: [implementation](../stdlib/alloc/clone_hash_set.lani),
[execution gate](../tests/stdlib_clone_hash_set_execution.rs), and
[fixtures](../tests/fixtures/stdlib_foundation/clone_hash_set/).
