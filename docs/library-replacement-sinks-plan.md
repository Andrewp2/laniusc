# Ownership-aware replacement sinks

Status: **selected increment accepted on the finite native Linux x86_64
profile**. The frozen five-file implementation passes direct public admission,
two semantic Rust gates, five negative-bound compiler tests, strict owner/OOM
campaigns and the real latest-values application. Direct oracle campaigns are
not claimed as Rust-libtest execution. The full standard and extended library
goal remains open; the separate zero-sized return-call compiler dependency
below is retained. The [contract guide](stdlib-replacement-sinks.md) owns API,
cleanup, failure and target details.

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
implement the selected replacement sink.

The two map `Entry` types remain distinct nominal types. Returning only an old
map value would lose the old key's cleanup authority. All four selected
destinations can return the same complete item type they accept.

The missing composition is a bounded transfer which can retain a displaced
owner and distinguish failure before insertion from failure after a committed
replacement. A replacement followed by failed delivery cannot be represented
as ordinary `TrySink` rejection: the incoming item now belongs to the map/set,
so returning it as the rejected item would duplicate cleanup authority.

## Frozen shared boundary

The selected names and signatures are implemented at the source freeze below.
The current finite executable receipts are recorded below:

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

Selected standard implementations:

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
alone proves this API is blocked. In particular, an older generic
`Vec.at` extraction and imported finish-result shape have retained captures;
prefer already canonical cursor/typed-view ownership paths in the fixtures.
Preserve any newly failing minimal source before classifying it. Routine source
visibility, duplicate receiver-pattern or inference errors are not compiler
bugs. Do not change compiler IR, ABI, proofs, extraction or runtime here.

Production ownership is limited to:

- `core::iter`: one destination trait, progress/result types and one bounded
  helper using the existing Iterator/TrySink protocols.
- Four existing alloc map/set modules: thin public trait implementations only;
  canonical insertion/storage algorithms and existing rejection sinks unchanged.
- Dedicated guide plus overview/roadmap/reference updates after implementation
  and actual receipts. Root README and human policy files remain untouched.

## Current source freeze and first admission

The five production files are frozen; static review finds 109 added lines and
no deleted or changed existing bodies. There is no compiler/runtime change.

| Production file | SHA-256 |
| --- | --- |
| `stdlib/core/iter.lani` | `a6fc9e0d63c55088c66eb70d33b425a224d4672c4cd32743cfcad3639bac79af` |
| `stdlib/alloc/hash_map.lani` | `f3e6b36340c74402bbdb970619800b85e3c70980b529d8f3bae3602afca91095` |
| `stdlib/alloc/hash_set.lani` | `eeba04ae4a8f6cef1469c67269f5dcb3c6eefa30632cebda9d0fdf595979f3d0` |
| `stdlib/alloc/tree_map.lani` | `01904e6481ceb83c025990b832e755f3eb8c6e7b9ddf71db04d951f63faed02c` |
| `stdlib/alloc/tree_set.lani` | `bd3cec1c95ceb32ef46909a3c2b533187967e5138c33690b7928cdf8750212ee` |

Two direct CLI/native programs execute through those actual modules:

| Scope | Source prefix | Compile/native receipts under `target/stdlib-work/` | ELF prefix |
| --- | --- | --- | --- |
| Public helper with caller-defined pre/postcommit failures, quotas/EOF, actual HashMap/TreeSet representatives and existing HashMap TrySink policy | `a1a17538...` | `replacement-public-smoke-first.log`, `replacement-public-smoke-native-first.log` | `8386070d...` |
| Small TreeMap/String/error-owner composition | `7b7f5c98...` | `replacement-owners-admission-first.log`, `replacement-owners-admission-native-first.log` | `b6173242...` |

Both ELFs exit zero. These are direct admission programs, not Rust-libtest or
full model/facade campaign receipts. The owning program has no strict live
mapping/FD ledger or allocation-failure acceptance; the later strict campaign
has separate receipts below. Five
negative-bound Rust tests separately pass in 5.67s in
`replacement-bounds-first.log`; its command also includes a 1m00s test-profile
build. They assert helper-call LNC0008 labels for wrong Entry identity, missing
key Hash, wrong raw replacement error, displaced item and displaced error. No
native behavior is inferred from expected compiler rejection.
Existing collection and earlier nested-iteration receipts retain their old
source scopes; the new smoke checks only its explicit older-policy control.

## Accepted finite campaigns

| Surface | Current accepted scope | Receipts under `target/stdlib-work/` |
| --- | --- | --- |
| Semantic Rust gates | One model test/53 scenarios in 9.73s and one actual wide/optional/zero-sized shape and four-facade duplicate-policy test in 9.49s | `replacement-model-typed-prime-retry.log`, `replacement-shapes-local-projection-retry.log` |
| Strict owners | Five direct groups: lifecycle20, HashMap63, TreeMap57, HashSet41, TreeSet38; 219 group cases with overlapping baselines and 183 individually reached OOMs | `replacement-owners-{lifecycle,hash-map-oom,tree-map-oom,hash-set-oom,tree-set-oom}-first.log` |
| Real latest-values program | Four direct groups: models136, bounds61, allocations34 (baseline plus33 reached OOMs), faults17; 248 group cases with overlap | `replacement-latest-values-models-first.log`, `replacement-latest-values-bounds-live-order-retry.log`, `replacement-latest-values-allocations-first.log`, `replacement-latest-values-faults-first.log` |

The owner lifecycle contains 16 healthy cases and four intentionally unreached
allocation-denial controls. Those four establish the specific no-growth
replacement behavior, not reached fault coverage. The five owner and four app
groups reuse retained native ELFs and are not five/four passing Rust libtests.
Their registered drivers build together with `--no-run` in 3.42s
(`replacement-app-owner-driver-build-first.log`), separately from runtime.
CPU controls number 18 semantic, 45 resource and 26 application.

The first model fixture needed a typed Result local. Its initial shape helper
exposed a separate import-free `(Progress,Unit,Unit)->Unit` return-call issue:
compilation succeeds but native execution traps; changing only the separate
control's return to u64 executes. Actual public Failure/Result Unit construction
and direct caller projection are correct and retain all shape assertions.
The [minimal reproduction](../tests/fixtures/stdlib_compiler_state/replacement_zst_return/README.md)
and [dependency ledger](library-dependencies.md) preserve that specific compiler
boundary; no production or compiler source changed to admit this API.

Independent review strengthened the app's owner witness: trusted allocation
ordinals bind to the original full-trace mmap, and old/new/remainder owners must
exist before the first positive diagnostic write and survive its complete
record. The corrected 61-case bounds rerun passes with app/ELF unchanged. Module
and fixture guides retain exact hashes, initial failures and ledger scope.

## Acceptance obligations

The finite campaigns above satisfy the selected obligations below. They are
not universal proofs, complete compiler-generic acceptance or other-host support.

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

The implemented [latest_values program](stdlib-latest-values.md) reads bounded
strict UTF-8 `key<TAB>value` rows, stores independent String key/value owners in
TreeMap, and collects complete displaced entries in update order. Its staged
output emits history followed by a key-sorted latest snapshot. Rejected and
Undelivered cleanup preserve both old/new fields, errors and source remainders;
a failed old-item delivery does not repeat the committed replacement.

All four direct application campaigns pass the 248 group cases above. The
bounded history-zero diagnostic proves the new value is already stored while
the old and remainder owners remain live, before explicit cleanup. Its oracle
provides trace-exit release evidence; the separate strict-owner fixture supplies
live acknowledged `/proc` checkpoints. The application guide owns exact grammar,
eight CLI caps, output/error policy, source identities and receipt mechanics.

One separate untraced observation processes 4,096 rows/512 keys, returning 3,584
displacements and 512 snapshot entries: 49,152 input bytes and 65,536 output
bytes. Its 0.087919031s includes launch, stdin, input validation, String owners,
map/history processing, staging and stdout capture; independent exact-output
validation is outside the timer. `replacement-latest-values-scale-first.log`
records this one local sample. It adds no group case, measured allocation/RSS
count or compiler/general speed ratio.

The accepted target is native Linux x86_64 CPU programs emitted by the GPU
compiler. No user-program GPU or broader-host support follows. Further iterator
families, collection owners, host services and the full library goal remain
separate unfinished work.
