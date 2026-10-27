# Replacement sinks and displaced owners

Status: the selected replacement increment is implemented and accepted on its
finite native Linux x86_64 profile. Public admission, semantic/shape checks,
negative-bound compiler tests, strict owner/OOM campaigns and the real
latest-values application pass through separate receipts below. Direct oracle
groups are not Rust-libtest receipts. The full library goal remains open, and
a separate zero-sized return-call compiler dependency is documented below.
The [increment plan](library-replacement-sinks-plan.md) records the five exact
production hashes and implementation boundary.

Replacement stores an incoming item and can return a complete displaced item.
The bounded helper delivers each displaced owner through the existing
[`TrySink`](stdlib-iterator-transfer.md) protocol before taking another source
item. A failure reports whether storage rejected the incoming item or delivery
rejected an old item after replacement committed. These two outcomes carry
different cleanup authority.

## Public API

All declarations below belong to `core::iter`. `Result` and `Option` refer to
the canonical core types.

```lani
pub trait TryReplaceSink<T,E> {
    pub fn try_replace_item(&self, item:T) -> Result<Option<T>,E>;
}

pub struct ReplacementProgress { committed:u64, replaced:u64 }
pub struct ReplacementTransfer { progress:ReplacementProgress, exhausted:bool }
pub enum ReplacementFailure<T,RE,DE> {
    Rejected(ReplacementProgress,T,RE),
    Undelivered(ReplacementProgress,T,DE),
}

pub fn try_replace_up_to<I,R,D,T,RE,DE>(
    source:&I, replacement:&R, displaced:&D, limit:u64
) -> Result<ReplacementTransfer,ReplacementFailure<T,RE,DE>>
    where I:Iterator<T>, R:TryReplaceSink<T,RE>, D:TrySink<T,DE>;
```

`RE` is the replacement error type; `DE` is the displaced-delivery error type.
They may differ and may contain independent owners or borrowed data. The
incoming and displaced item have the same complete type `T`. No Clone,
Destroy, default-value or new iterator protocol is required by this helper.

## One replacement and representative identity

`try_replace_item` has the following contract:

| Result | Incoming item | Displaced item |
| --- | --- | --- |
| `Err(error)` | Rejected intact; destination retains neither its cleanup authority nor a partial insertion. | None. Existing storage remains unchanged. |
| `Ok(None)` | Committed to the destination. | No previous item existed. |
| `Ok(Some(old))` | Committed to the destination. | Complete old item transfers to the caller. |

For the selected collections, errors also preserve capacity and previously
valid views. Arbitrary callback instrumentation or effects on independently
shared payloads are not rolled back. Successful mutation follows each
collection's ordinary view-invalidation rules.

For optional item type `T`, `Ok(Some(None))` displaces a real optional item;
`Ok(None)` means no displacement. Nested Result/Option values are ordinary data.

The selected collection implementations delegate to the canonical methods:

| Destination | Item | Replacement error | Existing delegate and bounds |
| --- | --- | --- | --- |
| `alloc::hash_map::HashMap<K,V>` | `hash_map::Entry<K,V>` | `hash_map::Error` | `try_insert(key,value)`; `K:Hash<K> + Eq<K>` |
| `alloc::tree_map::TreeMap<K,V>` | `tree_map::Entry<K,V>` | `tree_map::Error` | `try_insert(key,value)`; `K:Ord<K>` |
| `alloc::hash_set::HashSet<T>` | `T` | `hash_map::Error` | `try_replace(item)`; `T:Hash<T> + Eq<T>` |
| `alloc::tree_set::TreeSet<T>` | `T` | `tree_map::Error` | `try_replace(item)`; `T:Ord<T>` |

Maps replace **both key and value**, returning the complete old Entry. An
equivalent logical key can have a different stored representative and owner.
For example, a new key record with identity 7 and new metadata replaces the old
identity-7 record; the old record and its old value both come back. Returning
only the old value would lose the old key's cleanup authority. Hash-map and
tree-map Entry are distinct nominal types; the item and error identities must
match the selected destination. Map values acquire no new trait bounds.

Sets store the supplied new representative and return the old representative.
Their existing duplicate-preserving `try_insert` and `TrySink` policies keep
their own contracts. Replacement uses the raw collection Error type rather
than the duplicate-rejecting SinkError. No remove/reinsert algorithm, duplicate
precheck or automatic destruction is added. Canonical replacement of an
already equivalent key returns before collection growth; absent insertion and
the displaced destination retain their own fallible allocation costs.

## Bounded transfer and commit order

For each immediate source item, the helper attempts one replacement. A
successful store increments `committed`. A returned old item increments
`replaced`, then receives exactly one `displaced.try_accept(old)` attempt.
The next source pull occurs only after that delivery succeeds or when there
was no old item. Replacement and delivery errors stop immediately.

| Helper outcome | Progress includes | Returned item and cleanup authority | Current incoming item |
| --- | --- | --- | --- |
| `Rejected(progress,incoming,error)` | Earlier successful commits and displacements only. | Complete incoming item remains caller-owned. | Not retained by replacement storage. |
| `Undelivered(progress,old,error)` | The current committed replacement and its displacement. | Complete old item remains caller-owned; delivery did not retain it. | Already belongs to replacement storage. |
| `Ok(transfer)` | Every successful store and its successfully handled displacement. | No pending item retained by the helper. | Belongs to replacement storage. |

Both failure variants have consumed the current source item. Earlier commits
and accepted displaced items stay in their respective destinations. A failed
delivery never makes the already committed incoming item caller-owned again.
There is no rollback or transaction across the two destinations.

The displaced destination must honor the existing TrySink rejection contract:
on failure it has retained no old-item authority and published no partial
insertion; the returned item remains valid for recovery. On success it assumes
that item's cleanup policy, whether storage, transfer or complete release.
A partial-output writer cannot satisfy rejection by simply wrapping
`write_all`: an accepted byte prefix cannot be undone. A conforming staging
destination can accept owners first and perform external output separately.

## Progress, quotas and EOF

All counts describe this call and exclude preexisting destination items:

```text
0 <= replaced <= committed <= limit
```

`committed` counts new insertions and replacements. `replaced` counts returned
old items, including the one whose delivery failed. Consequently, successful
delivery calls equal `replaced - 1` on Undelivered and `replaced` otherwise.
Undelivered always has at least one replacement.

| Stop condition | Progress and effects | `exhausted` |
| --- | --- | --- |
| Limit zero | Counts zero; no source, replacement or delivery call. | `false` |
| Actual source `None` before quota | Keep all prior progress; no replacement/delivery for that None. | `true` |
| Quota reached | Return immediately; no extra EOF probe. | `false` |
| Replacement/delivery error | Return the corresponding failure and exact progress; no later peer call. | Not part of a failure payload. |

A quota equal to the source's exact remaining length still reports
`exhausted=false` because no None was observed. With a positive quota, an empty
source makes one source call and returns exhausted with zero progress.

At most `limit` immediate source calls and replacement attempts occur; delivery
attempts equal `replaced`. An EOF observation can use one call beyond the
successful commit count while remaining within the quota. The implementation
increments only while `committed < limit` and preserves the count invariant.
The full `u64::MAX` quota requires no `limit+1`, narrowing, wrapping or saturation.

Under stable key laws and no independent destination edits, selected collection
length follows `final_len = initial_len + committed - replaced`. This does not
count displaced storage length when its sink chooses to release accepted items.

## Recovery without repeated replacement

After **Rejected**, handle the returned incoming item first. Retry it through
the replacement contract, retain it elsewhere, or explicitly release it. A
successful retry can itself displace an old item that needs delivery. Resume
the source only after resolving those obligations; it already advanced past
the rejected incoming item.

After **Undelivered**, handle the returned old item only. Retry its delivery,
retain it elsewhere, or release it. **Do not repeat the committed replacement.**
Its new representative is already stored; repeating the update would produce
another displacement and can duplicate or invalidate owner authority. Resolve
the pending old item before resuming when delivery order matters.

The helper retains no pending owner after return. Release returned error
owners independently, and keep backing borrowed by an item or error alive
through its last use. Failure copies are shallow aliases, not new cleanup
authorities. An owning source's unconsumed items and retained backing remain
the caller's responsibility, including after observed exhaustion.

For maps, explicit cleanup must account for both String/resource fields of
every incoming, stored, displaced, rejected and unconsumed Entry. No automatic
clone or destruction resolves those obligations. Use independent active owners,
or a separately retained external authority when values are borrowed aliases.

## Lifetimes, effects and resource bounds

Keep source, both destinations, callbacks and backing alive and distinct for
the call. Do not iterate a borrowed view into either mutating destination or
make one destination's storage invalidate the other. Stored key hash/equality/
ordering must remain stable and lawful. Sources and callbacks, including key
operations, must not reenter the helper or mutate peer destinations.

The helper's own contract is fixed local metadata with no allocation or host
call. Work and allocations inside an upstream adapter, hash/order callback,
replacement operation or displaced collector remain outside that claim. A
single source `next()` can scan many leaf items. This is an immediate-call
quota, with no implicit byte, CPU, native-memory or wall-clock bound. Collection
and collector growth preserve their existing typed allocation failures.

## Verification status

Core source is frozen at
`a6fc9e0d63c55088c66eb70d33b425a224d4672c4cd32743cfcad3639bac79af`,
with the four thin collection implementations recorded in the
[source-freeze table](library-replacement-sinks-plan.md#current-source-freeze-and-first-admission).
Two direct CLI/native programs compile and exit zero:

| Direct admission | Compile log under `target/stdlib-work/` | Native log in the same directory |
| --- | --- | --- |
| Public helper, caller-defined failures, quota/EOF and actual HashMap/TreeSet representative behavior | `replacement-public-smoke-first.log` | `replacement-public-smoke-native-first.log` |
| Small TreeMap/String/error-owner composition | `replacement-owners-admission-first.log` | `replacement-owners-admission-native-first.log` |

The public source/ELF prefixes are `a1a17538...`/`8386070d...`; the owning
source/ELF prefixes are `7b7f5c98...`/`b6173242...`. The public smoke also checks
its existing duplicate-preserving HashMap TrySink path. These two programs
establish imported public composition and their explicit assertions, not an
all-four-facade campaign, a Rust-libtest run or strict resource/OOM evidence.
The owning control has no live mapping ledger. No compiler source changed.

Five negative-bound Rust tests pass in 5.67s in
`target/stdlib-work/replacement-bounds-first.log`. The same command includes a
1m00s test-profile build; 5.67s is its test phase. Each asserts LNC0008 at the
helper call for wrong nominal map Entry, missing key Hash, wrong raw replacement
error, wrong displaced item or wrong displaced error. These are expected
compiler-rejection receipts, not native execution. The
[bounds fixture guide](../tests/fixtures/stdlib_foundation/replacement_sink_bounds/README.md)
records exact filters and diagnostics.

### Semantic and generic-shape execution

Two Rust tests pass separately: the 53-scenario state/representative model in
9.73s (`replacement-model-typed-prime-retry.log`) and wide/optional/zero-sized
payload and four-facade duplicate-policy checks in 9.49s
(`replacement-shapes-local-projection-retry.log`). Source prefixes are
`143ce22b...` and `36239e34...`. The
[semantic fixture guide](../tests/fixtures/stdlib_foundation/replacement_sinks/README.md)
records exact behavior and source identities; 18 CPU controls are separate.

The model fixture needed a typed Result receiving local. An unnecessary
Unit-returning shape helper exposed a separate compiler/runtime call boundary:
import-free `(Progress,Unit,Unit)->Unit` compiles but traps natively, while the
same arguments/callee assertion with a u64 return executes. Direct public
Failure/Result Unit construction and caller-local projection work; the accepted
shape retains Unit item and both error types, exact progress, counts and retry.
No public item is padded or replaced. The
[minimal reproduction](../tests/fixtures/stdlib_compiler_state/replacement_zst_return/README.md)
and [dependency ledger](library-dependencies.md) keep this specific limitation
open without changing compiler or replacement implementation.

### Strict owner and reached-allocation campaigns

Five direct Python groups pass against one retained probe/ELF/oracle
(`86a0d81e...`/`e62aeff4...`/`e10ee099...`). These are not five passing Rust libtests.

| Direct group | Group cases | Individually reached OOMs | Receipt under `target/stdlib-work/` |
| --- | ---: | ---: | --- |
| Lifecycle | 20 | 0 | `replacement-owners-lifecycle-first.log` |
| HashMap | 63 | 59 | `replacement-owners-hash-map-oom-first.log` |
| TreeMap | 57 | 53 | `replacement-owners-tree-map-oom-first.log` |
| HashSet | 41 | 37 | `replacement-owners-hash-set-oom-first.log` |
| TreeSet | 38 | 34 | `replacement-owners-tree-set-oom-first.log` |

These total **219 group cases with overlapping baselines and 183 individually
reached OOM runs**, including recovery in each facade. Lifecycle contains 16
healthy cases and four deliberately unreached denials establishing replacement
without growth at the tested full capacity. Those four are not reached faults.

The [owner fixture guide](../tests/fixtures/stdlib_execution/replacement_sinks/README.md)
records complete old/new key/value ownership, separate owned errors, accepted
history and source remainders before recovery. Strict full-width instruction/
size/prefix/phase ledgers bind every reached denial and explicit release. Live
acknowledged checkpoints verify pending owners before retry and exact balance
before exit. Displaced-growth failure includes the current commit and returns
only the old item; recovery does not repeat replacement. Forty-five CPU oracle
controls are separate from native execution.

### Real latest-values application

The [latest_values guide](stdlib-latest-values.md) records strict UTF-8 TSV,
eight CLI caps and complete staged history/snapshot output. Four direct oracle
groups pass on app `62fce749...`/retained ELF `e5d70d...`, not four Rust libtests:
models136, bounds61, allocations34 (baseline plus33 reached OOMs) and faults17.
These are **248 group cases with overlapping baselines**. Logs are
`replacement-latest-values-models-first.log`,
`replacement-latest-values-bounds-live-order-retry.log`,
`replacement-latest-values-allocations-first.log` and
`replacement-latest-values-faults-first.log` under `target/stdlib-work/`.

Independent review corrected the bounds witness to require each old/new/
remainder allocation to precede the first actual positive diagnostic write and
remain live through the complete record, with trusted full-trace mmap identity.
The strengthened 61-case rerun passes with source/ELF unchanged. This is app
trace-exit cleanup evidence, distinct from the direct owners' live checkpoints.
Twenty-six CPU app controls are separate. Registered app/owner drivers build
together with `--no-run` in 3.42s (`replacement-app-owner-driver-build-first.log`);
that build is not native Rust-libtest execution.

A separate 4,096-row/512-key untraced run observes 3,584 displacements and 512
snapshot entries, 49,152 input/65,536 output bytes, in 0.087919031s. The timer
includes launch, stdin, input validation, owners, maps/history, staging and
stdout capture; independent exact-output checking is outside it. Receipt:
`replacement-latest-values-scale-first.log`. This one sample adds no group case,
measured allocation/RSS count, compiler benchmark or general ratio.

The selected finite replacement increment is accepted. Initial target evidence
is native Linux x86_64 CPU execution emitted by the GPU compiler; user GPU-kernel
or broader-host support is not established. Further library families and the
complete goal remain open in the [roadmap](library-roadmap.md).
