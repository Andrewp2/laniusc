# Ownership-aware replacement sinks

Status: **proposal only**. The new interfaces below are not implemented or
executable. This proposes the next iteration work after the accepted
[scan/nested increment](library-nested-iteration-plan.md).
The complete standard and extended library goal remains
open. This document changes no production or test source and records no new
execution receipt.

## Problem and existing source contracts

The existing [bounded transfer](stdlib-iterator-transfer.md) uses
`Iterator<T>` and `TrySink<T,E>`. A sink's `None` accepts the incoming item;
`Some(error)` rejects it without retaining it or publishing a partial insertion.
`try_transfer_up_to` returns that rejected incoming item and the accepted prefix.
The [map/set sinks](stdlib-iterator-collection-sinks.md) deliberately reject
duplicates and preserve the stored representative. Keep these contracts.

The canonical collection methods already implement replacement:

| Existing operation | Successful absent key | Successful equivalent key | Failure |
| --- | --- | --- | --- |
| [HashMap.try_insert](../stdlib/alloc/hash_map.lani) | Stores incoming key and value; `Ok(None)` | Stores **both incoming key and value**; returns the complete old `Entry<K,V>` | Returns `Error`; caller retains inputs; collection unchanged |
| [TreeMap.try_insert](../stdlib/alloc/tree_map.lani) | Same | Same; replacement does not allocate collection storage | Same |
| [HashSet.try_replace](../stdlib/alloc/hash_set.lani) | Stores incoming representative; `Ok(None)` | Stores incoming representative; returns the old representative | Returns hash-map `Error`; caller retains input; set unchanged |
| [TreeSet.try_replace](../stdlib/alloc/tree_set.lani) | Same | Same | Returns tree-map `Error`; caller retains input; set unchanged |

Hash-map replacement also returns before reserve/growth. The set methods
delegate through their existing canonical key-storage/map engines. Set
`try_insert` has a different policy: an equivalent key preserves the old stored
representative and returns the **supplied incoming** representative. It must not
implement the proposed replacement sink.

The two map `Entry` types remain distinct nominal types. Returning only an old
map value would lose the old key's cleanup authority. All four selected
destinations can return the same complete item type they accept.

The missing composition is a bounded transfer which can retain a displaced
owner and distinguish failure before insertion from failure after a committed
replacement. A replacement followed by failed delivery cannot be represented
as ordinary `TrySink` rejection: the incoming item now belongs to the map/set,
so returning it as the rejected item would duplicate cleanup authority.

## Recommended shared boundary

These names and signatures are proposed for contract review, not frozen APIs:

```lani
pub trait TryReplaceSink<T,E> {
    pub fn try_replace_item(&self, item:T)
        -> core::result::Result<core::option::Option<T>,E>;
}

pub struct ReplacementProgress { committed:u64, replaced:u64 }
pub struct ReplacementTransfer { progress:ReplacementProgress, exhausted:bool }
pub enum ReplacementFailure<T,RE,DE> {
    Rejected(ReplacementProgress,T,RE),
    Undelivered(ReplacementProgress,T,DE),
}

pub fn try_replace_up_to<I,R,D,T,RE,DE>(source:&I, replacement:&R,
    displaced:&D, limit:u64)
    -> core::result::Result<ReplacementTransfer,ReplacementFailure<T,RE,DE>>
    where I: Iterator<T>, R: TryReplaceSink<T,RE>, D: TrySink<T,DE>;
```

The new trait is a destination contract, not another iterator protocol. The
displaced-item destination uses the existing `TrySink` contract. No new source,
mapper, destruction or transaction engine is needed.

The distinct member name `try_replace_item` avoids colliding with the sets'
existing inherent `try_replace` methods. Public trait implementations must use
the language's matching public visibility. This is ordinary source admission,
not a reason to alter compiler dispatch or add compatibility aliases.

### One-item replacement contract

- `Err(error)` rejects before committing: the destination retains neither
  incoming cleanup authority nor a partial insertion. Existing contents,
  capacity and valid views remain unchanged for the selected collection
  implementations. Counters may record the attempt. Nested shared payloads
  are shallow values; arbitrary callback effects are not rolled back.
- `Ok(None)` commits a new item and returns no displaced item.
- `Ok(Some(old))` commits the incoming item and transfers the complete old
  item's cleanup authority to the caller. It is not the incoming item returned
  by duplicate-preserving set insertion.
- No clone or `Destroy` is implicit. An application may supply borrowed aliases
  or independently owned items, as with existing collection APIs.
- Nested option/result values stay ordinary data. For optional `T`,
  `Ok(Some(None))` is a displacement of a real optional item, distinct from
  `Ok(None)` with no displacement.

Proposed standard implementations:

| Destination | `T` | `RE` | Delegate unchanged |
| --- | --- | --- | --- |
| `HashMap<K,V>` | `hash_map::Entry<K,V>` | `hash_map::Error` | `try_insert(item.key,item.value)` |
| `TreeMap<K,V>` | `tree_map::Entry<K,V>` | `tree_map::Error` | `try_insert(item.key,item.value)` |
| `HashSet<T>` | `T` | `hash_map::Error` | `try_replace(item)` |
| `TreeSet<T>` | `T` | `tree_map::Error` | `try_replace(item)` |

Use their existing exact Hash/Eq/Ord bounds. Add no bound on map values and no
Clone/Destroy requirement. Duplicate is successful replacement, so these
implementations use raw storage `Error`, not the duplicate-rejecting
`SinkError`. Preserve all existing insertion and `TrySink` bodies. In particular,
do not implement replacement by removing an entry and reinserting another one.

### Bounded transfer and failure ownership

One shared helper performs these steps:

1. Pull one immediate source item.
2. Attempt replacement once.
3. On success, increment `committed`. If an old item exists, increment
   `replaced` and attempt to deliver it once through `displaced.try_accept`.
4. Continue only after that old item has been accepted, or when no old item
   existed. Stop immediately on either failure.

| Result | Progress | Returned `T` | Where the current incoming item belongs |
| --- | --- | --- | --- |
| `Rejected(progress,incoming,RE)` | Only earlier successful commits/displacements | The complete incoming item | Caller; replacement destination did not retain it |
| `Undelivered(progress,old,DE)` | **Includes the current committed replacement and its displacement** | The complete displaced old item | Replacement destination; it must not also be returned as caller-owned input |
| `Ok(transfer)` | All commits and all their successful old-item deliveries | None | Replacement destination |

Earlier commits and successful old-item deliveries remain in their respective
destinations. There is no rollback, cross-destination atomicity or cleanup on
error. A failed delivery must honor `TrySink`: it has not retained the old item
or published a partial insertion. A raw partial-write stream therefore cannot
be presented as this sink merely by wrapping `write_all`; use a conforming
staging collection and deliver bytes separately.

Both failure variants have already consumed the current source item. Recovery
is different:

- **Rejected:** retry or release the returned incoming item before resuming
  the source. A successful retry may itself produce an old item to handle.
- **Undelivered:** retry delivery, retain elsewhere or release the returned
  **old** item. Do not repeat the replacement: it already committed. Resolve
  that item before resuming, preserving journal order when order matters.

The helper retains no pending owner after returning. Error payloads and item
payloads use normal shallow ownership; backing borrowed by either must remain
live until final use. Copying the failure is not another cleanup authority.
Errors may own independent resources or borrow other live storage, subject to
those same lifetime rules. The caller owns the unconsumed source remainder and
an owning source cursor's retained allocation, even after observed exhaustion.

### Quotas and arithmetic

All progress is relative to this call, excluding preexisting destination items.
`replaced <= committed <= limit`. A source `None` sets `exhausted=true`; reaching
the quota sets it false without another EOF probe. Zero touches none of the
three objects. At most `limit` immediate source calls and replacement attempts
occur, and at most `replaced` displaced-destination attempts occur.

Increment `committed` only after a successful replacement while it is less
than `limit`. Increment `replaced` only for a displacement belonging to that
commit. This establishes both increments are safe even for `u64::MAX`; never
form `limit+1` or narrow the quota. On Undelivered, one old item is pending, so
successful deliveries during this call equal `replaced-1`; otherwise they equal
`replaced`. An observed EOF can require one call beyond the successful commit
count, still within the call quota.

The bound does not constrain work inside an iterator adapter, user hashing,
ordering, comparison, replacement or delivery callback. Bound an upstream
source separately when one `next` can scan many raw items. The helper itself
allocates no storage and performs no host calls. Collection growth and a
displaced collector's growth retain their existing fallible costs.

### Lifetimes and effects

Require the existing stable key laws. Stored keys cannot change hash/equality/
ordering while resident. Sources and callbacks must not reenter the helper or
mutate peer destinations. Source and destination backing must not invalidate
one another: do not iterate a borrowed view into either mutating collection,
and use separate backing owners for replacement storage and the displaced
collector. Views into a successfully edited collection follow its normal
invalidation rules even when replacement allocated nothing.

No publication or destructor may observe an intermediate old shallow copy as
another live owner. After success the incoming copy is inactive in the helper;
after accepted delivery its old-item copy is inactive. On rejection the returned
owner remains intact. These are manual ownership contracts, not language-enforced
lifetimes or automatic destruction.

## Alternatives and why this shape is smaller

1. **Change `TrySink` to replace silently:** loses displaced owners and changes
   already accepted duplicate behavior. Keep the distinct policies explicit.
2. **Replace and deliver inside a normal `TrySink`:** a delivery failure would
   claim rejection after insertion and make `TransferError.rejected` an alias
   of the newly stored owner. A tagged error alone cannot fix the old contract.
3. **Pre-reserve, roll back or transact both destinations:** reservation cannot
   prevent all logical delivery errors. Rollback adds mutation/ownership rules
   and cannot undo arbitrary callback effects. No current transaction boundary
   promises this behavior.
4. **Retain pending old items in a new owning adapter:** adds storage, capacity,
   stop/destroy and retry state unnecessarily. Returning one pending owner on
   error keeps the operation bounded and matches existing transfer recovery.
5. **Automatically destroy old items:** excludes fallible resource cleanup and
   hides ownership policy. An explicit caller-supplied sink can release owners
   if its contract permits; the generic helper must not impose it.
6. **Use a distinct displaced type parameter:** all four selected operations
   return their complete incoming item type. Keep that smallest useful contract
   first. A sink that extracts only an old map value must still explicitly
   resolve the old key; no alternate type may silently discard it.

Ordinary direct insertion remains useful for single updates. The bounded helper
adds the shared recovery contract for a stream of updates. It is not an alias
for duplicate rejection or a new implementation of a map/set algorithm.

## First admission and implementation boundaries

Before a large campaign, compile and execute a small caller of the **actual
stdlib-classified** helper and actual map/set implementations with a
caller-defined displaced `TrySink`. A user-module prototype alone cannot admit
this imported generic composition. Exercise both failures, empty/zero quota,
one successful displacement and recovery with exact progress and callbacks.

Then cover all four concrete facades and generic forwarding with nested/wide
items, a separately owned String error and optional errors. Receiving annotations
must not invent a different source item or trait error identity. Use distinct
receiver patterns for distinct caller implementations. Reject wrong map Entry
identity, key bounds, replacement error, displaced item and displaced error.

The existing dependency ledger records selected generic source shapes; none
alone proves this proposed API is blocked. In particular, an older generic
`Vec.at` extraction and imported finish-result shape have retained captures;
prefer already canonical cursor/typed-view ownership paths in the fixtures.
Preserve any newly failing minimal source before classifying it. Routine source
visibility, duplicate receiver-pattern or inference errors are not compiler
bugs. Do not change compiler IR, ABI, proofs, extraction or runtime here.

Proposed production ownership is small:

- `core::iter`: one destination trait, progress/result types and one bounded
  helper using the existing Iterator/TrySink protocols.
- Four existing alloc map/set modules: thin public trait implementations only;
  canonical insertion/storage algorithms and existing rejection sinks unchanged.
- Dedicated guide plus overview/roadmap/reference updates after implementation
  and actual receipts. Root README and human policy files remain untouched.

## Acceptance obligations

The following are required future evidence, not completed tests or proofs.

### State model and exact ownership

Use an independent finite queue/dictionary model. Equality identity and stored
representative metadata must differ, with collision-heavy hash keys and ordered
tree keys. Compare the complete old/new keys and values, not only logical keys.
Repeated updates to one identity must yield old representatives in update order
and leave the latest supplied representative stored.

Generate zero, exact, larger and MAX quotas; empty and prepopulated targets;
new insertion, replacement, precommit failure and failed old-item delivery.
Interleave retries and resumed calls. Check source position and effect traces:
no delivery on insertion failure or absent-key insertion, exactly one delivery
attempt per displacement, and no later source/peer call after failure. A retry
of Undelivered must not perform another replacement.

Useful invariants, assuming no independent destination edits, are:

- `final_len = initial_len + committed - replaced` for each selected map/set.
- Every original owner appears exactly once among replacement contents,
  accepted displaced contents, returned failure item, and unconsumed source.
- An Undelivered error leaves the **new** representative in replacement storage
  and the **old** representative solely in the failure.
- A Rejected error leaves storage and prior valid cursors unchanged and returns
  the complete current incoming owner.

Include optional items/errors, nested Result/Option values, wide arrays and
zero-sized payloads so absence, rejection and displacement tags cannot collapse.
Public library calls must execute, not just type-check.

### Native resources and reached allocation failures

Use genuinely independent String key/value owners, old/new representative
owners, an owning input cursor, displaced collection storage and an owned error.
At a first pre-exit checkpoint, stop before retry or cleanup so the host can
verify the failure owner/error, committed new representative, accepted history
and every legitimately retained allocation. After host ACK, recover or release
those owners, the source remainder/backing and both destinations. A final
checkpoint must prove exact balance before another ACK permits exit. Reuse the
current strict full-width syscall-site/address/requested-length ledger; do not
replace it with destructor counters or process-exit cleanup.

Bind allocation injections to baseline phase, live owner and reached native
site. Separately deny every observed replacement-growth allocation and every
observed displaced-collector growth allocation. Check exact typed causes,
preserved ownership/progress and successful retry before source resumption.
The second class must produce Undelivered with current commit included. A
complete replacement at full collection capacity must still need no collection
storage growth. An intentionally unreached armed denial can establish that
specific no-allocation control, but cannot count as reached fault coverage.

Split finite campaigns into independently bounded gates; root runs compiler and
native commands under the shared lock, each below two minutes. Add narrow
regression checks for the existing duplicate-rejecting transfer policy and
direct map/set representative replacement. Do not run a broad workspace suite
without a concrete remaining risk. Report measured allocations/callback counts,
not a universal throughput or compiler-performance claim.

## Real program: latest values with displaced history

Propose `sample_programs/library/latest_values.lani`: a bounded stdin utility
which processes UTF-8 `key<TAB>value` rows, retains the latest value per key and
emits displaced entries in update order followed by a key-sorted final snapshot.
Freeze its exact record/escaping grammar and CLI bounds before implementation.

Use existing Text/decimal/stdio modules to validate bounded input and arguments,
then create independent owned String keys and values in an owned Entry vector.
An owning source transfers entries to `TreeMap<String,String>` through the new
helper. A bounded displaced-history sink uses the existing TrySink contract and
an owned vector of complete old tree-map Entries. It must reject before retaining
an item when its explicit history bound or allocation fails.

Stage normal output before delivery. On a precommit error, preserve/release the
returned incoming entry; on failed history delivery, preserve/release the old
entry while recognizing the latest update already resides in the map. Clean
both String fields of every owned entry, both destinations, the returned error
and the source remainder/backing exactly once. The library fixtures demonstrate
retry; the CLI may fail with no normal stdout after safely cleaning its partial
in-memory state. Final stdout write failure can expose a confirmed prefix and
must report it honestly rather than promise rollback.

Independent application cases should cover repeated keys with distinct owned
representatives, empty values, invalid UTF-8/records, exact/exceeded input/row/
history/output/I/O budgets, final ordering and complete displaced history. A
history rejection after a known successful replacement is a required causal
case. Include every reached source/map/history/output allocation denial, short
I/O, EINTR, hard errors and real EPIPE through existing signal/stream APIs.

Initial target evidence should be stated as native Linux x86_64 CPU programs
emitted by the GPU compiler. No user-program GPU, other-host or executable new
API claim follows from this plan. Further iterator families, collection owners,
host services and the full library goal remain separate unfinished work.
