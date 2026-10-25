# Owning hash map and set iteration

`HashMap.take_iter()` and `HashSet.take_iter()` transfer table storage and all
unconsumed entry cleanup authority into an owning cursor. The actual source
becomes an empty, zero-capacity owner that can be reused independently. A map
cursor yields `Entry<K,V>`; a set cursor yields `T`. Each successful pull
transfers that entry or key exactly once, in unspecified forward table order.

All four focused groups have passing native Linux x86-64 receipts through the
production GPU compiler. Three passed in the initial mixed run; the model group
passed separately after explicit insertion type annotations. These are distinct
receipts, not one all-green suite run.

## Public API

| Map | Set |
| --- | --- |
| `alloc::hash_map::IntoIter<K,V>` | `alloc::hash_set::IntoIter<T>` |
| `hash_map::IntoIterError::Remaining(i32)` | `hash_set::IntoIterError::Remaining(i32)` |
| `HashMap<K,V>.take_iter()` | `HashSet<T>.take_iter()` |
| `Iterator<Entry<K,V>>::next(&self)` | `Iterator<T>::next(&self)` |
| `take_remaining() -> HashMap<K,V>` | `take_remaining() -> HashSet<T>` |

Both cursor types provide `borrow()`, `remaining() -> i32`, `capacity() -> i32`,
`is_empty() -> bool`, and `try_finish() -> Option<IntoIterError>`. Import
`core::iter` and the relevant collection module when selecting their Iterator
implementations, including in generic consumers.

These transfer and lifecycle operations require no Hash, Eq, TryClone or
Destroy bound. Creating or inserting keys into an ordinary table still has its
existing Hash/Eq requirements. Owning iteration also works with nonempty
zero-sized keys and values; their table metadata still requires storage.

## Lifecycle and recovery

End all borrowed entry/key and ordinary cursor use before calling `take_iter`.
The source no longer owns the transferred table. It can allocate independent
storage and be reused without affecting the owning cursor. Old shallow copies
of the source must remain inactive.

`next()` removes one initialized entry before returning it. The caller acquires
its key/value cleanup authority, and the cursor's remaining count decreases.
After it returns `None`, all later pulls return `None`. Exhaustion alone leaves
the backing table and its capacity in the cursor.

`try_finish()` behaves as follows:

- If live entries remain, return `Some(Remaining(count))` without changing the
  cursor, its scan position, remaining entries or allocation.
- If no live entries remain, release the table and reset the cursor to an empty,
  zero-capacity state. Repeated finish calls succeed without another release.

`take_remaining()` transfers the same allocation and unconsumed entries into a
normal map or set in O(1). It preserves capacity and tombstones, including slots
already consumed by the cursor, then disarms the actual cursor. Recovering again
from that disarmed cursor returns a fresh empty owner with no allocation.
An exhausted cursor can recover an empty table with its capacity still retained;
it does not have to free that storage first.

The shared map engine changes consumed Full slots to Deleted and retains the
occupied-slot count. This preserves probe chains for remaining colliding keys.
Recovery performs no key hashing, comparison, allocation or rehash. Sets use the
existing nongeneric key-storage boundary and temporary typed map cursor views;
the private unit value and slot representation do not escape into set APIs.

After recovery, ordinary insertion can legitimately allocate or rehash at the
same capacity to reclaim tombstones. Spare capacity is distinct from empty
never-used slots: the engine's reserve policy considers occupied slots as well
as live entries. Handle insertion failures and returned/displaced owners under
the ordinary map/set contract.

`take_iter` and `take_remaining` are O(1); finishing an empty cursor performs one
storage release when backing exists. A full forward traversal scans at most the
table's bucket count. One pull can scan many empty or deleted slots. These
operations add no allocation and never clone or destroy yielded entries
automatically.

## Explicit cleanup of unconsumed owners

The opt-in clone modules provide:

```lani
pub fn destroy_hash_map_iter<K,V>(
    owner: &alloc::hash_map::IntoIter<K,V>)
    where K: core::clone::Destroy<K>, V: core::clone::Destroy<V>;

pub fn destroy_hash_set_iter<T>(
    owner: &alloc::hash_set::IntoIter<T>)
    where T: core::clone::Destroy<T>;
```

Each helper first recovers and disarms the actual cursor, then invokes the
existing deep owner destructor on the remainder. It releases only unconsumed
entries and their table. It performs no key comparisons or hashing after a leaf
has been released. Destroy callbacks must remain infallible, allocation-free,
and free of reentrant mutation of the owner being processed.

For a map of independent String owners, release each yielded pair separately,
then release the unconsumed remainder:

```lani
import alloc::clone_hash_map;
import alloc::hash_map;
import alloc::string;
import core::iter;

fn release_one_then_remainder(owner: &alloc::hash_map::HashMap<alloc::string::String,alloc::string::String>) {
    let cursor = owner.take_iter();
    let first = cursor.next();
    if (first.is_some()) {
        let entry = first.unwrap(); entry.key.destroy(); entry.value.destroy();
    }
    alloc::clone_hash_map::destroy_hash_map_iter<alloc::string::String,alloc::string::String>(cursor.borrow());
}
```

Deep cleanup requires one active cleanup authority for every stored owner.
Borrowed duplicate handles do not qualify. Yielded items remain the caller's
responsibility even after the cursor or its remaining table is released.
Ordinary table clone, clear and destroy retain their existing shallow policy.
There is no automatic Drop or move tracking. Copies of an owning cursor alias
one owner; they cannot independently pull, recover or release the same owners.

## Rejected sink transfers

`try_transfer_up_to` consumes the rejected item from its source before returning
`TransferError`. The sink retains only its accepted prefix. Release or recover
`error.rejected` before resuming the same cursor; the cursor's remaining owners
are still live. Deep remainder cleanup cannot recover an item already yielded
to the sink or returned in the error. Accepted items retain their own cleanup
authority after the source cursor is finished.

## Focused verification

The Linux x86-64 gate is:

```sh
cargo test --test stdlib_owning_hash_execution -- --test-threads=1
```

| Receipt | Observed result | Reported duration |
| --- | --- | --- |
| [`owning-hash-native.log`](../target/stdlib-work/owning-hash-native.log) | Contracts, String ownership/transfer, and empty/ZST groups passed; the original untyped model failed compilation with LNC0006, so this suite run failed overall | 11.98 seconds |
| [`owning-hash-model-typed.log`](../target/stdlib-work/owning-hash-model-typed.log) | The focused typed model passed all 5,368 cases; the other three groups were filtered out | 5.85 seconds |

The accepted model explicitly binds the inserted value as `i64` and its exact
Result type before unwrapping. It preserves the value `-9223372036854775807`,
its bit pattern `0x8000000000000001`, and the original oracle. This source form
has native acceptance; no compiler fix for the original nested call is claimed.
The [compiler-context record](../tests/fixtures/stdlib_compiler_state/hash_insert_context/README.md)
retains the original expression and an executed primitive-key reproducer:
the nested call still rejects with LNC0006, while the explicitly typed CLI
control compiles and exits 0 with the same exact i64 payload.

Four groups compile four entry programs through the production compiler, keeping
the strict shared native executable checker:

- Direct and imported generic Iterator use, source reset and independent reuse,
  partial recovery through wrapped collision chains, prior tombstones, occupied
  count preservation, reinsertion with deliberate spare headroom, exhausted
  recovery, repeated finish and repeated recovery.
- Twelve actual independent String owners across three tables. All setup
  allocations precede cursor operations; Hash/Eq callbacks trap afterward.
  Yielded owners remain live after deep remaining cleanup. A sink rejects its
  second transfer, the caller releases that owner, and the same cursor resumes.
  An address/size ledger requires exactly 15 setup mappings and matching releases
  with no double release. A second execution refuses every mmap after setup and
  requires no attempted allocation or injected failure.
- Empty and reserved empty tables of types with no key traits, deep helpers for
  a type with only Destroy, and nonempty zero-sized map/set owners. Exact leaf
  release events distinguish yielded owners from unconsumed cleanup.
- 5,368 bounded map/set setup, consumption, finish, recovery and mutation cases.
  A simple key-to-value model checks representatives, wide scalar payloads,
  lookup validity, transferred owner sets and preserved metadata without modeling
  buckets or requiring an iteration order. Final drains must transfer every
  recovered or reinserted entry exactly once. Full occupied tables may rehash
  after recovery; cursor operations themselves must not allocate.

The CPU oracle sanity check passed all 5,368 cases using an alternate sequence
model and varied forward/reverse pull and drain observations. It validates the
prepared oracle and does not execute the Lanius helpers. These finite cases do
not prove arbitrary callback protocols or invalid owner aliases safe, or
establish runtime acceptance on other targets.

Sources: [map](../stdlib/alloc/hash_map.lani),
[set](../stdlib/alloc/hash_set.lani),
[map cleanup](../stdlib/alloc/clone_hash_map.lani),
[set cleanup](../stdlib/alloc/clone_hash_set.lani),
[execution gate](../tests/stdlib_owning_hash_execution.rs), and
[fixtures](../tests/fixtures/stdlib_foundation/owning_hash/).
