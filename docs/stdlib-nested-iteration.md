# Scan and nested iteration

`core::iter` implements stateful scan and nested traversal through the existing
[`Iterator<T>` and `Mapper<T,U>` protocols](stdlib-iterators.md). Production
source is frozen at `7256a394...`. Two direct public-adapter smoke programs
compile and execute; three semantic/model Rust tests, all four real-program
tests and all four direct strict-owner oracle groups also pass. This accepts
the selected increment on the finite native profile below; the full library
goal remains open. The earlier user-module admission prototypes have
their own narrow scope in the [increment plan](library-nested-iteration-plan.md).
They do not establish the production implementation's runtime behavior.

The adapters allocate no storage themselves. Sources, callbacks, retirement
policies and yielded values keep their own allocation and cleanup contracts.
Constructors invoke no source or callback and require no initial inner value.

## Public adapters

All functions below are in `core::iter`. `Option` and `Result` refer to the
canonical `core::option` and `core::result` types.

| Constructor | Required bounds | Iterator item |
| --- | --- | --- |
| `scan<I,M,T,U>(source:&I, mapper:&M) -> Scan<I,M,T,U>` | `I:Iterator<T>`, `M:Mapper<T,Option<U>>` | `U` |
| `try_scan<I,M,T,U,E>(source:&I, mapper:&M) -> TryScan<I,M,T,U,E>` | `I:Iterator<T>`, `M:Mapper<T,Result<Option<U>,E>>` | `Result<U,E>` |
| `try_flatten<I,J,R,T,E>(source:&I, retirement:&R) -> TryFlatten<I,J,R,T,E>` | `I:Iterator<J>`, `J:Iterator<T>`, `R:InnerRetirement<J,E>` | `Result<T,E>` |
| `try_flat_map<I,M,R,S,J,T,E>(source:&I, mapper:&M, retirement:&R) -> TryFlatMap<I,M,R,S,J,T,E>` | `I:Iterator<S>`, `M:Mapper<S,Result<J,E>>`, `J:Iterator<T>`, `R:InnerRetirement<J,E>` | `Result<T,E>` |

Every adapter supplies `borrow() -> &Self` for composition. The nested adapters
also supply active-owner recovery and finishing methods described below.
Construction returns the adapter directly; callback failures are yielded during
iteration. Mapping and retirement share the caller-selected error type `E`;
a tagged enum can preserve distinct causes.

## Stateful scan

The mapper owns its mutable scan state. Scan borrows that mapper and its source;
it does not copy the state into a separate accumulator. Each nonterminal
`next()` makes at most one `I.next()` call and, for a successful input, at most
one `M.apply(input)` call. The table describes those direct calls; an upstream
adapter's own `next()` can perform additional work.

| Observation | `Scan.next()` | `TryScan.next()` | Later calls |
| --- | --- | --- | --- |
| Source returns `None` | `None`, no callback | `None`, no callback | `None`, no source/callback calls |
| Callback selects a value | Callback `Some(value)` yields `Some(value)` | Callback `Ok(Some(value))` yields `Some(Ok(value))` | Continue |
| Callback stops | Callback `None` yields `None` | Callback `Ok(None)` yields `None` | `None`, no source/callback calls |
| Callback fails | Not part of this callback type | Callback `Err(error)` yields `Some(Err(error))` once | `None`, no source/callback calls |

A stopping or failing callback has already consumed its current source item.
There is no rollback or extra source probe. Returning `None` ends a scan;
`filter_map` has its separate skip-and-continue contract.

The caller manages consumed input owners, replaced callback state, outputs and
errors. Stopping does not implicitly destroy any of them. If a callback
replaces an owned accumulator, it must transfer or release the previous owner
itself. A returned error remains available to the caller after the adapter
fuses; its cleanup is also explicit.

## Inner retirement

An owning collection cursor can retain backing after it first returns `None`.
Before acquiring another inner, nested traversal transfers that exhausted
cursor to the caller's retirement policy:

```lani
pub struct RetireFailure<J,E> { inner:J, error:E }

pub trait InnerRetirement<J,E> {
    pub fn try_retire(&self, inner:J) -> Option<RetireFailure<J,E>>;
}
```

The policy receives the actual current `J` by value, including the mutations
made by its terminal `next()`. There is one active position/cleanup authority.

- Returning `None` means retirement is complete. The policy has released or
  explicitly disarmed all cleanup authority carried by this inner. A borrowed
  cursor with no owned resources can have an explicitly resource-free policy.
- Returning `Some(RetireFailure { inner, error })` transfers back the actual
  updated, valid inner and a separately owned error. Partial retirement may
  already have occurred. The returned inner must expose the remaining recovery
  authority; returning an older shallow copy is invalid.

The policy must not retain a second active alias of the transferred inner.
There is no automatic `Destroy`, deep clone, implicit rollback or retirement
retry. The engine requires no default value, layout knowledge, per-cursor
implementation or additional borrowing trait for `J`.

## Nested traversal and error order

Both nested adapters share one traversal engine, holding at most one active
inner. `TryFlatten` takes that inner directly from its outer source.
`TryFlatMap` first maps a consumed outer item to `Result<J,E>`.

For every local inner call, the engine moves the active `J` into a local and
clears its stored slot before invoking `J.next()`. It then follows this order:

| Result | State and observable action |
| --- | --- |
| Inner yields `Some(item)` | Restore the mutated local inner, then yield `Some(Ok(item))`. |
| Inner yields `None`; retirement succeeds | Consume that inner's authority, then acquire the next outer item. No earlier inner copy is reused. |
| Inner yields `None`; retirement fails | Restore only the policy-returned updated inner, yield `Some(Err(error))` once, and fuse. No next outer item is acquired. |
| No active inner; outer yields an item | `TryFlatten` installs it; `TryFlatMap` calls its mapper once and installs the returned inner. Continue within this `next()`. |
| Flat-map callback returns `Err(error)` | Yield `Some(Err(error))` once and fuse with no active inner. The consumed outer item is not restored. |
| No active inner; outer yields `None` | Return `None` and fuse. |

After normal exhaustion, a mapping error or a retirement error, all later
`next()` calls return `None` without source, mapper, inner or retirement calls.
The error item is not converted to successful exhaustion on its first call.
An outer iterator can itself yield a Result as an ordinary item; these adapters
do not automatically unwrap an unrelated outer error protocol.

The flat-map callback owns cleanup of any partially constructed inner when it
returns an error. On retirement failure, `has_active()` remains true even
though iteration is fused. An active slot describes a retained `J` value;
it does not imply that the inner still has elements or any particular amount
of allocated backing.

## Early stop and recovery

The following methods apply to both `TryFlatten` and `TryFlatMap`:

| Method | Contract |
| --- | --- |
| `has_active() -> bool` | Inspect whether an inner is retained, without advancing anything. |
| `take_active() -> Option<J>` | Clear and transfer the actual active inner, and permanently close this adapter, including when the returned Option is `None`. No source, inner or policy call occurs. |
| `try_finish() -> Option<NestedFinishError>` | If active, return `Some(NestedFinishError::Active)` and preserve all state. Otherwise close and return `None`, without consuming the outer. Repeated successful finish is inert. |

An item-producing inner is still active after yielding its final item. A later
call must observe its `None` before normal retirement occurs. Consequently,
stopping a downstream `take` or fold can leave inner backing to recover.
`try_finish()` reports that condition rather than discarding the inner.

To stop early or handle a retirement error:

1. Keep any yielded value/error backing valid until its last use.
2. Call `take_active()` to transfer the retained inner and close the adapter.
3. Resume, recover or explicitly retire that returned inner under its own
   contract. Resolve any returned error owner's cleanup independently.
4. Retain the borrowed outer's remaining cleanup authority. It is positioned
   after the already transferred inner, or after the item consumed by a failed
   mapper. A fresh adapter can continue from the next outer item.

Finishing and taking do not drain, destroy, finish or close the outer. Abandoning
an active nested adapter performs no cleanup. Successful recovery does not
reopen the original fused adapter or repeat its saved error.

## Lifetimes, aliases and callbacks

Keep the source cursor object, mapper, retirement policy and any borrowed
context alive through their use. An inner returned by flat-map must not borrow
callback-local backing that expires on return. Caller-owned backing for a
borrowed inner must remain valid independently of its copied cursor descriptor.

A yielded item can borrow from its inner. Such a borrow must end before a later
call retires that backing; the adapter does not extend the backing's lifetime.
Transferred item owners instead follow the source cursor's explicit ownership
contract. The engine does not retire already yielded owners on the caller's
behalf. Errors can also carry owners or borrows, with their own lifetime rules.

Keep one active handle for each ownership-bearing nested adapter. Copying it
shallowly aliases the stored inner and does not grant another cleanup authority.
Scan copies share the same upstream source and callback state; they are not
independent stateful computations. Use constructors and preserve their state
invariants.

Sources and callbacks must not reenter the adapter being advanced, taken or
finished. In particular, the active slot is deliberately empty while its sole
authority is in a local or retirement callback. There is no runtime reentrancy
guard or concurrent-access guarantee. Independently advancing or retiring an
active inner alias is also invalid.

## Work and resource bounds

The adapter's storage is fixed metadata plus at most one `J`; nested traversal
allocates nothing itself. Callback and source allocations, borrowed backing,
returned item/error owners and retirement work remain outside that claim.

One nested `next()` can cross many empty inners, calling retirement for each.
An infinite sequence of empty inners can keep it from returning. A downstream
output quota does not bound outer acquisition or retirement. A bounded program
must bound the outer traversal and each source/callback operation; infinite
nonempty inners need their own consumption policy. These adapters introduce no
implicit byte, work, callback, time or allocation allowance.

## Verification status

The public implementation is source-frozen at SHA-256
`7256a39462db691ece403a6d9a409947f7fafa7919783be474d510f1bf63ce3c`.
Two direct smoke programs import the actual stdlib and execute successfully:

| Scope | Compile receipt under `target/stdlib-work/` | Native receipt in the same directory |
| --- | --- | --- |
| Public Scan/TryScan scalar state and boundary composition | `nested-public-scan-smoke-visibility-retry.log` | `nested-public-scan-smoke-native-first.log` |
| Public TryFlatten/TryFlatMap scalar state, boundaries and active recovery | `nested-public-nested-smoke-first.log` | `nested-public-nested-smoke-native-first.log` |

Both native ELFs exit zero. They are direct CLI/native controls, not passing
Rust libtests or the broader model/owner/application campaign. Their ELF hash
prefixes are `dcb2c42b...` (scan) and `bd055701...` (nested); the observed CLI is
`1c2718d4...`. The [increment plan](library-nested-iteration-plan.md) retains
full admission provenance and the separate earlier user-module receipts.

The first production scan admission rejected the private implementation of the
public Mapper trait used by an internal identity helper. Making that
implementation public while keeping its type private corrected the visibility
declaration; public signatures and traversal semantics were unchanged. This
was a source visibility correction, not a compiler repair or a general
restriction on generic nested traversal.

The selected target for new gates is native Linux x86_64 CPU execution of
programs emitted by the GPU compiler. No other host or user-program GPU
execution is established by that compilation route.

### Accepted semantic and real-program gates

All three semantic/payload Rust tests pass in 9.31s in
`target/stdlib-work/nested-public-models-shapes-first.log`:

| Public-adapter scope | Executed evidence |
| --- | --- |
| Nested state model | 360 binary command scenarios compare action snapshots, shared-outer state and complete source/mapper/retirement traces against independent sequence/deque models. |
| Scan state model | 672 binary command scenarios compare shared source consumption, stateful callbacks, stop/error order, resumption and fused effects. |
| Generic payloads | Executable value/count checks cover nested Option/Result/arrays, wide signed/unsigned fields, actual nonzero strided Views and zero-sized items. |

The [semantic fixture guide](../tests/fixtures/stdlib_foundation/nested_iteration/README.md)
records exact filters and hashes. The 9.31s belongs to the combined three-test
command. Its two registered smoke tests were filtered out because the separate
direct CLI/native receipts above already cover their execution. This is three
passing Rust tests plus two direct programs, not a passing all-five libtest run.
Eighteen CPU model controls are separate from native Lanius execution.

The real [flatten_sum program](stdlib-flatten-sum.md) passes all four focused
Rust tests, totaling 219 process group cases across two commands:

- `nested-flatten-sum-models-bounds-first.log`: models 138 and bounds 54, 8.51s.
- `nested-flatten-sum-allocations-faults-first.log`: allocations 11 (baseline
  plus all ten reached source OOMs) and faults 16, 8.23s.

These receipts are under `target/stdlib-work/` and include overlapping setup
and baselines. The earlier three-row/four-value smoke overlaps and is not added
to 219. Application source is `946043fe...`, with the same `core::iter` source.
It transfers physical Vec rows into owning cursors, retires exhausted backing,
uses TryScan checked totals and releases active/outer remainders before bounded
output. The app ledger verifies explicit source unmaps before traced exit; it
has no live ACK checkpoint. Its scalar AppError owns no heap payload, so these
cases do not establish the direct owned-error recovery contract. Eighteen app
CPU controls are also separate from runtime acceptance.

### Accepted strict owner groups

All four oracle groups pass directly against one retained native ELF. These are
not four passing Rust libtests: the driver build/admission and its earlier
failed oracle attempt have separate scope. The accepted probe is
`e92ee3b8...`, ELF `3d99ec69...`, oracle `eb37f142...`, with unchanged production
core source. The [owner fixture guide](../tests/fixtures/stdlib_execution/nested_iteration_owners/README.md)
records full identities and the acknowledged live-process protocol.

| Direct group | Accepted group cases | Individually reached OOMs | Receipt under `target/stdlib-work/` |
| --- | ---: | ---: | --- |
| Lifecycle | 14 | 0 | `nested-owners-lifecycle-lazy-count-retry.log` |
| Flatten allocation failures | 30 | 28 | `nested-owners-flatten-oom-first.log` |
| Vec flat-map allocation failures | 56 | 52 | `nested-owners-flatmap-vec-oom-first.log` |
| Wrapped Deque flat-map allocation failures | 56 | 52 | `nested-owners-flatmap-deque-oom-first.log` |

The total is **156 group cases, including overlapping baselines, and 132
individually reached OOM runs**. This is neither 156 independent properties nor
132 distinct allocation sites. Real Vec/Deque/String owners verify actual
partial-inner recovery, retirement before another outer acquisition, early
resumption, and independent held output/error lifetime and release. Strict
instruction/size/prefix/phase-bound source ledgers and acknowledged live
`/proc` checkpoints require explicit cleanup before exit. Allocation in traversal
is allowed only inside identified mapper/retirement callbacks; the adapter
itself acquires no heap scratch. Forty-one CPU oracle controls are separate.

The first fixture rejected before ELF/native emission because it used an
unsupported applied `where Make<J>:` subject; the grammar requires a bare
identifier. Its correction borrows an explicit generic mapper `M`. Typed local
`J`/Option values and reinstallation then correct generic-cursor field calls
in the fixture. No production or compiler source changed. The emitted probe
stayed unchanged through oracle-only corrections to lazy/eager allocation
counts. Exact reached-fault binding, live ownership and ledger assertions were
preserved. The failed attempts are retained in the
[isolation guide](../tests/fixtures/stdlib_compiler_state/nested_iteration_owners/README.md);
they do not establish a general generic-type restriction or a native library
owner-cleanup failure.

### Separate application observation

One untraced run of the accepted application processes 65,536 values in 3,072
physical rows, including 2,048 empty rows: 133,120 input bytes and 382,110 output
bytes. Its **0.157614975s** includes launch, stdin, parsing, ownership traversal,
formatting and stdout capture; exact total validation occurs outside the timer.
The receipt is `target/stdlib-work/nested-flatten-sum-scale-first.log`.
It is one local process observation, adds no finite fault-group case or source
allocation count, and establishes no compiler speed or general performance
ratio. Full workload/caps are in the [application guide](stdlib-flatten-sum.md#separate-scale-observation).

These finite native Linux x86_64 receipts accept this selected increment.
Replacement sinks, further iterator work and the complete library goal remain
open in the [roadmap](library-roadmap.md).
