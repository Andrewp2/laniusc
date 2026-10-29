# Shared iterators

`stdlib/core/iter.lani` executes on **x86_64 Linux**, with native CPU programs
compiled by the GPU compiler. Five focused test groups cover its shared generic
protocol, borrowed adapters, state models, owner aliases and bound rejections.
Additional [selection and fold gates](stdlib-iterator-selection.md) cover lazy
predicates, searches, accumulation and typed early failure.
[Fallible collection gates](stdlib-iterator-transfer.md) cover bounded transfer
into fixed vectors, owned vectors and deques, including rejection recovery.
[Map, set and heap sink gates](stdlib-iterator-collection-sinks.md) additionally
check unique-key policies, retained representatives and both heap orders.
This is native CPU execution evidence; it does not establish user-program GPU
execution or other targets. The newly implemented
[double-ended protocol and Rev](#double-ended-traversal) have separate current
verification status below; historical forward-only groups do not establish
those additions by themselves.
The [exact-size protocol](stdlib-exact-size-iterators.md) separately specifies
`remaining_count() -> u64` for selected finite sources and adapters; its
current verification status and exclusions are in that guide.
The separate [reduction and bounded-fold increment](stdlib-iterator-folds.md)
adds front reduction, reverse folds and bounded forward/reverse progress with
explicit consumed-item errors. All seven new library and four byte-summary
application gates pass on native Linux x86_64, with selected old regressions
and the compiler inference dependency recorded separately. Older receipts
here retain their source/API scope.

The new [sequence comparison consumers](stdlib-iterator-sequences.md) add
equality, total/partial lexicographic order and adjacent sortedness through the
same protocol. All eight new library tests, all 119 program cases and three
selected migrated-consumer regressions pass on native Linux x86_64.
Exact left/right pulls, retained previous items and discarded-owner cleanup
are explicit, separately from the historical receipts here.

[Collection, Text and bitset cursors](stdlib-collection-iterators.md) implement
the same protocol. Their separate native gates check mixed traversal,
compound map entries, borrowed String aliases and byte/scalar view behavior.

[Predicate slice segmentation](stdlib-slice-segmentation.md) adds forward
`Iterator<View<T>>` implementations here for `core::slice::Split`,
`SplitInclusive` and `ChunkBy`. Their checked factories live in core::slice
and invoke no callback; Mapper capability is required only when iterating.
Unary predicates classify separator elements, while ChunkBy uses the existing
Mapper over an adjacent Pair. Exact lazy call order, between-pull aliases and
shared predicate context are explicit. All eight new library gates pass,
including 5,496 independent model cases and exact live-owner cleanup; the
binary record-summary program passes four groups/94 native cases. No reverse
or exact-size capability is added for these stateful-predicate cursors.

`core::iter` connects borrowed slice cursors, finite i32 range cursors, borrowed
adapters and bounded consumers through one explicit protocol:

```lani
pub trait Iterator<T> {
    pub fn next(&self) -> core::option::Option<T>;
}
```

`Some(item)` advances the source by one logical element. `None` means exhausted.
An implementation must be **fused**: after its first `None`, every later `next`
must also return `None`. Implementations can record calls, so fused exhaustion
does not promise that repeated calls have no other effects. There is no error
variant in this protocol. A fallible source needs a separately chosen error
contract; it must not silently turn a failure into successful exhaustion.

The adapters themselves allocate nothing and invoke no host services. Sources
and [mapping callbacks](stdlib-iterator-adapters.md) supply their own per-call
behavior, allocation, cost and termination.
Lanius `for` syntax retains its existing compiler lowering; declaring this trait
does not automatically extend `for` to custom iterator types.

## Double-ended traversal

```text
pub trait DoubleEndedIterator<T> {
    pub fn next_back(&self) -> core::option::Option<T>;
}

pub fn rev<I,T>(source: &I) -> Rev<I,T>
    where I: Iterator<T>, I: DoubleEndedIterator<T>;
```

An implementation participating in this paired protocol supplies both traits
for the same item type. Generic functions name both bounds explicitly; the
current language does not infer Iterator from DoubleEndedIterator or use
supertrait syntax here. A backward-only or differently typed implementation
does not satisfy `rev`.

`next` consumes the first remaining logical item and `next_back` consumes the
last. They use the **same remainder**, may be interleaved and cannot yield the
middle item twice. **None from either direction permanently exhausts both**.
This is a source contract even when callers use the two traits independently;
forging cursor state or reentering it from a callback is outside that contract.

The design follows Rust's official
[DoubleEndedIterator](https://doc.rust-lang.org/std/iter/trait.DoubleEndedIterator.html)
shared-range model and [Rev](https://doc.rust-lang.org/std/iter/struct.Rev.html)
direction inversion. Lanius deliberately strengthens exhaustion: Rust permits
later values after None, while this paired Lanius protocol requires permanent
exhaustion at both ends. Rust also makes Iterator a supertrait; Lanius spells
out both generic bounds. Reverse traversal alone supplies no exact-size trait.

### Borrowed Rev

`rev` borrows the actual source cursor. Construction makes no source/callback
call, allocates no storage and captures no items. `Rev::borrow()` supports
further borrowed composition. Its `next()` calls source `next_back()`; its
`next_back()` calls source `next()`. Each active pull makes at most one direct
source call. One local done flag latches the first None in either direction;
subsequent pulls make no source calls. Two nested Rev adapters restore the
original direction over the source's current remainder, without rewinding it.

```lani
let values: [i32; 4] = [2, 3, 5, 7];
let source: core::slice::Iter<i32> =
    core::result::unwrap(core::iter::from_slice<i32>(values, 4));
let backwards: core::iter::Rev<core::slice::Iter<i32>,i32> =
    core::iter::rev<core::slice::Iter<i32>,i32>(source.borrow());
let last: core::option::Option<i32> = backwards.next(); // Some(7)
let first: core::option::Option<i32> = backwards.next_back(); // Some(2)
// The shared source remainder is now [3, 5].
```

Source cursor objects, mapper/predicate contexts and all backing owners outlive
these borrowed adapters. Do not reenter a cursor or mutate it concurrently.
Sequential pulls through another valid borrow observe the same remainder.
Copying Rev copies its local done flag and keeps the same borrowed source;
it creates no independent source or cleanup authority. Ending a Rev borrow
neither drains the source nor releases its storage. There is no item cache,
implicit cloning, automatic destruction or snapshot of the input.

Reverse pulls preserve the source's item policy. Borrowed cursors yield shallow
aliases; owning cursors transfer cleanup authority for each yielded item.
Discarding a transferred item in a filter or consumer still requires explicit
caller/callback cleanup. Owning-cursor finish/destroy releases only its actual
remainder; exhaustion through Rev does not itself release retained backing.

### Implementations and composition

| Source or adapter | Reverse contract |
| --- | --- |
| `Empty<T>` / `Once<T>` | Empty is exhausted in both directions; Once has one shared consumed flag |
| `RangeI32` | Front/back consume the captured ascending interval; widened endpoint arithmetic handles inclusive i32 extrema |
| `core::slice::Iter<T>` | Uses its existing shared front/back indices, native stride and backing bounds; Vec/Text borrowed factories return this same cursor |
| `alloc::vec::IntoIter<T>` | Transfers the last remaining item through the canonical trait method; retains explicit finish/destroy policy |
| Deque `Cursor<T>` / `IntoIter<T>` | Borrowed/owning back access retains the same wrapped logical remainder |
| TreeMap/TreeSet borrowed and owning cursors | Back pulls the largest remaining entry/key; ordering and owner-release policy remain those of the canonical tree cursors |
| `Map` / `Filter` / `FilterMap` | Reverse support requires the source to implement both traits, plus the existing typed callback bound |
| `Chain<A,B,T>` | Requires both traits for both sources; front drains left then right, back drains right then left, sharing each source's exhausted flag |

Map invokes its callback once per successful source pull. Filter and FilterMap
scan in the requested direction until a match/output or source exhaustion.
Callbacks run in **pull order**. Stateful callbacks can therefore produce
different values/selections under different front/back schedules; there is no
promise that changing direction simply reverses an earlier callback history.
Chain makes at most two direct source pulls per call. Callback/inner work is
not a wall-time bound, and filtering can scan arbitrarily many source items.
A downstream Take limits yielded matches, not scanned items; use a finite
source or place Take between Rev and Filter when scanned-input work needs its
own explicit bound.

`Take`, `Skip`, `Zip` and `Enumerate` remain forward-only. Place them after Rev
when the desired operation is bounded or indexed reverse traversal, such as
`rev -> filter -> take -> enumerate`. This does not make `rev(take(...))`
available. Other cursor/adapter families gain no backward trait merely from
having a forward implementation or an inherent metadata method. Generic reverse
iteration under the backward trait alone carries no `remaining()` or exact
cardinality promise.
Generic exact counts require the separate `ExactSizeIterator<T>` bound;
reverse support by itself does not supply it. Rev/Map can preserve both
traits under their respective source bounds. Take/Skip/StepBy/Peekable gain
conditional exact counts while retaining their existing forward-only pulls.

### Current reverse verification

All four `stdlib_reverse_iterator_execution` Rust tests pass through actual
GPU compilation and Linux x86_64 CPU execution, across two disjoint filtered
commands. The model test passes in 9.40s; the other three pass in 11.74s.
These are runtime tests, not build-only admission.

| Registered gate | Accepted finite scope |
| --- | --- |
| Pure contracts | `contracts.lani` executes five scenario functions and current `extra_contracts.lani` executes four in separate raw processes. Compound/nested values, mixed ends, range extrema, callback order, empty/aliased Chain, packed/negative-stride bytes and zero-sized values pass with no mmap/munmap calls |
| Collection ownership | Four scenario functions check borrowed String aliases, explicit owning transfers/destruction, wrapped Deque and tree ranges/ordered owners, plus remaining-owner recovery. All seven actual backing allocations match successful releases by full address and size; Rev adds no hidden clone/drop |
| Independent model | 7,740 commands compared with a host VecDeque reference cover mixed ends, partially consumed sources, chained remainders and double reverse |
| Exact trait bounds | Forward-only and wrong-backward-item sources each reject with `LNC0008` at their own Rev construction |

Receipts under `target/stdlib-work/` are `reverse-model-rust-first.log` and
`reverse-contracts-rust-formatted.log`. Accepted core/slice sources are
`c2db69bc…`/`b9f2f9c2…`; contract/extra/collection producers are
`5c682a05…`/`9f6ac75a…`/`bea024ff…`. Earlier direct native runs are admission
and diagnostic history for these same cases, not additional Rust tests or
extra distinct coverage. The first extra-contract source had three scenario
functions, including both-empty Chain; the final source adds packed/strided
byte and zero-sized Unit coverage as its fourth scenario.

Selected old forward contracts and `core_slice_view.lani` compile and execute
again after method migration. The existing `tree_map_basic.lani` also passes
without a direct core::iter import, preserving transitive method visibility.
These focused controls do not claim a broad old-suite rerun.

After adding the separate [exact-size capability](stdlib-exact-size-iterators.md),
the unchanged independent reverse model passes its one selected registered
test in 7.27s against current core source `be05d6c2…`: 7,740 commands, in
`target/stdlib-work/exact-size-reverse-regression.log`. This adds no claim
that the other historical reverse/forward groups were rerun.

The [real timeline program](#latest-matching-timeline-application) separately
passes all four registered Rust tests and its 71 process cases. No new
allocation-failure campaign, automatic lifetime/cleanup enforcement, formal
proof or user-program GPU runtime follows. Target evidence remains native
Linux x86_64; source callbacks, backing validity and bounded work retain the
explicit preconditions above.

### Canonical method and compiler boundary

Slice and collection cursor `next`/`next_back` calls now resolve to their single
public trait implementations. The `.next_back()` call spelling is unchanged.
The compiler currently rejects a same-named inherent and trait method in the
same module (`LNC0027`); keeping the old slice inherent method alongside the
new imported trait also produced ambiguous resolution. The
[minimal duplicate-method reduction](../tests/fixtures/stdlib_compiler_state/inherent_trait_name/reject_duplicate.lani)
and [single-trait control](../tests/fixtures/stdlib_compiler_state/inherent_trait_name/trait_only.lani)
retain that narrow boundary. The current direct reverse contracts compile and
execute with the canonical trait methods. No compiler change or general generic
payload limitation is claimed. Backward behavior has one canonical implementation.

## Items, copies and lifetime

Every returned item is an ordinary shallow Lanius value copy. The protocol does
not deep-clone it, infer cleanup authority or invoke `core::clone::Destroy`.
Each source states whether an item borrows resources or transfers cleanup
authority. Borrowed collection cursors can yield a String alias while its
original owner retains the sole release duty.

[Vec and deque owning cursors](stdlib-owning-iterators.md) explicitly transfer
their source's item cleanup authority on each successful pull. Keep one active
owning handle. Yielded items, including ones later discarded by an adapter,
are no longer in that cursor's cleanup range. Skipping, filtering, unmatched
Zip items, searches, folds and bounded consumption never insert Destroy calls.
They can leak transferred owners unless the caller or callback releases or
tracks them. The owning-cursor Destroy helpers only release the remainder;
they cannot recover previously discarded items.

`core::slice::Iter<T>` contains a copied slice descriptor and cursor state. The original
View record can go out of scope, but its physical backing must remain alive,
initialized and valid. Destroying or reallocating the backing owner invalidates
the cursor. Valid alias mutations are observed by later reads; elements are not
snapshotted. `RangeI32` captures numeric bounds and has no external backing.

Copy semantics depend on the cursor:

| Copied value | State after copying |
| --- | --- |
| `core::slice::Iter<T>` | Independent positions; same backing elements |
| `core::slice::Split<T,P>` / `SplitInclusive<T,P>` / `ChunkBy<T,P>` | Independent positions; same live backing and borrowed predicate/context; prior boundaries remain fixed while later calls observe permitted edits |
| `RangeI32` | Independent positions over captured numeric bounds |
| `alloc::vec::IntoIter<T>` / `alloc::deque::IntoIter<T>` | Aliased storage and cleanup authority; only one active handle is permitted |
| `Take<I,T>` | Independent quota/done flags; same borrowed source cursor |
| `Rev<I,T>` | Independent done flag; same borrowed source cursor and shared front/back remainder |
| `Chain<A,B,T>` | Independent per-source exhaustion/done flags; same borrowed source cursors |
| `Map<I,M,T,U>` | Independent done flag; same borrowed source and mapper/context |
| `Zip<A,B,T,U>` | Independent done flag; same borrowed source cursors |
| `Enumerate<I,T>` | Independent index/done flags; same borrowed source cursor |
| `Filter<I,P,T>` / `FilterMap<I,M,T,U>` | Independent done flags; same borrowed source and callback |
| `Skip<I,T>` | Independent skip budget/done flag; same borrowed source |
| `TakeWhile<I,P,T>` / `SkipWhile<I,P,T>` | Independent boundary/phase/done flags; same borrowed source and predicate |

Adapters contain borrowed references. The source cursor object itself must
outlive the adapter, and a nested adapter must outlive every adapter borrowing
it. A Map's mapper and any context it borrows must also remain alive.
Lanius does not enforce these lifetimes. Returning an adapter that refers to a
local cursor is invalid even when the underlying array remains alive.

Sequentially interleaving adapters borrowing one cursor is permitted. The next
call observes that cursor's current position. A chain can borrow the same
cursor on both sides: it reads the cursor on the left until `None`, then sees
the already exhausted cursor on the right. It does not restart or copy it.
Concurrent access and mutation of cursor fields are outside these contracts.

Use constructors and preserve their state invariants. Public record fields are
not a protected ownership or validation boundary; forging or corrupting cursor
state can invalidate arithmetic, indexing and exhaustion guarantees.

## Slice cursors

| API | Contract |
| --- | --- |
| `from_slice<T>(values:[T], count:i32)` | `Result<core::slice::Iter<T>,slice::ViewError>`; select a prefix |
| `from_view<T>(view:slice::View<T>)` | Same result; retain this view's start/count and native stride |
| `core::slice::Iter<T>::borrow(&self)` | Borrow this cursor for adapters or consumers |
| `core::slice::Iter<T>::remaining(&self)` | Exact remaining logical count, i32 |
| `core::slice::Iter<T>::next(&self)` | Shallow front element, then advance; fused at zero remaining |
| `core::slice::Iter<T>::next_back(&self)` | Shallow back element, then retreat; shares the same remaining interval |

Both constructors reject negative count metadata. `from_view` also rejects a
negative start or an end beyond `i32::MAX`. It checks those conditions before
constructing a cursor and without reading an element. Errors are
`slice::ViewError::Bounds`; the module introduces no duplicate bounds enum.
Empty logical ranges are accepted and make no element reads.

`from_slice<T>` constructs a typed public `View<T>` with start zero and delegates
to `from_view<T>`, which performs all logical metadata checks before constructing
the cursor. Both constructors therefore use the same validation rules without
an intermediate `Result<View<T>,ViewError>`.

These checks do not prove physical backing. The initial slice must actually
back every claimed element, including a nonzero view start. There is no source
slice-length projection here. A logical overclaim can pass construction and
then trap at ordinary native indexing. Neither `remaining` nor a successful
constructor certifies an allocation size.

The checked factories and owner-proven Vec/Text factories return the same
canonical `core::slice::Iter<T>` as `View.iter()`. Both `next` and `next_back`
are canonical shared trait methods implemented in `core::iter`; skipping and
metadata methods live in `core::slice`. There is no same-named inherent backward
method. Import `core::iter` where the shared protocol is used. This keeps one
front/back cursor state without an import cycle or duplicate public methods.
Access preserves the native descriptor, stride and physical bounds. Packed
bytes, strided stack values, compound records and zero-sized items follow
the existing indexing contract. See [cursor integration](stdlib-cursor-integration.md).

```lani
let values: [i32; 4] = [2, 3, 5, 7];
let source: core::slice::Iter<i32> =
    core::result::unwrap(core::iter::from_slice<i32>(values, 4));
let prefix: core::iter::Take<core::slice::Iter<i32>, i32> =
    core::iter::take<core::slice::Iter<i32>, i32>(source.borrow(), 2);
let first: core::option::Option<i32> = prefix.next(); // Some(2)
let skipped: core::iter::Advance =
    core::iter::advance_up_to<core::iter::Take<core::slice::Iter<i32>, i32>, i32>(prefix.borrow(), 2);
// skipped == { advanced: 1, exhausted: true }; source.remaining() == 2.
```

Generic constructor item `T` can be constrained only by a return type or trait
bound, rather than a value argument. Use ordinary symbolic type parameters in
generic helpers, and explicit type arguments or a complete receiving annotation
at calls. The examples make those arguments explicit; no per-type overloads or
concrete witness wrappers are part of the API.

## Finite i32 ranges

`range_i32(Range<i32>) -> RangeI32` captures a half-open interval `[start,end)`.
`range_i32_inclusive(RangeInclusive<i32>) -> RangeI32` captures `[start,end]`.
Forward `next` advances upwards by exactly one; `next_back` consumes the
highest remaining value. Reversed bounds are empty; equal bounds
are empty for the half-open form and yield one element for the inclusive form.
Later changes to the original range record do not change the cursor.

`RangeI32` provides `borrow`, `next`, `next_back`, `remaining() -> u64` and
`advance(count:u64) -> u64`. The latter skips `min(count, remaining)` elements
in O(1), returns the exact skipped count and does not read or produce items.
This is distinct from the generic consumer, which calls `next` for each item.

All i32 endpoints are supported. Each endpoint is widened to i64 before any
subtraction or inclusive `end + 1`. The full inclusive interval contains
4294967296 elements; the full half-open interval contains 4294967295.
For constructed valid state, remaining is always 0..4294967296. `advance`
clamps its u64 request to that remaining count before converting the skipped
amount to i64. `next` tests exhaustion before incrementing and uses the i64
sentinel 2147483648 after yielding `i32::MAX` once. No step wraps in i32.

```lani
let bounds: core::range::RangeInclusive<i32> =
    core::range::range_inclusive<i32>(-2147483648, 2147483647);
let source: core::iter::RangeI32 = core::iter::range_i32_inclusive(bounds);
let skipped: u64 = source.advance(4294967295); // O(1), one item remains
let last: core::option::Option<i32> = source.next(); // Some(2147483647)
let end: core::option::Option<i32> = source.next(); // None forever
```

These are finite, concrete i32 cursors. The range records' generic
membership/partial-order contracts do not imply a generic successor operation.
Backward traversal uses this same interval through `next_back` or Rev. This
module defines no float, arbitrary-record or custom-step iteration policy.

## Borrowed adapters

[Map, Zip and checked Enumerate](stdlib-iterator-adapters.md) extend the same
protocol with source-defined transformation, left-first pairing and u64 index
labels. Their guide specifies callback, unmatched-item, copy and overflow
behavior. All adapters retain the shallow ownership rules above.

### Take

`take<I,T>(source:&I, count:u64) -> Take<I,T> where I:Iterator<T>` yields at
most `count` successful items. Construction makes no source call. A zero quota
returns `None` immediately, without querying the source. Each `Some` decreases
the quota by one. The first upstream `None` is latched; subsequent calls do
not query upstream. Exhausting the quota also requires no extra upstream probe.

`remaining_limit() -> u64` reports the remaining successful-item quota. It is
not an exact source cardinality. A prematurely exhausted Take can retain a
nonzero quota. `borrow()` permits another adapter to borrow the Take itself.
When its source also implements `ExactSizeIterator<T>`, the separate
`remaining_count()` query reports the smaller of current source cardinality
and quota; it neither consumes items nor changes `remaining_limit()`.

Each `next` invokes at most one direct upstream `next`.

### Chain

`chain<A,B,T>(left:&A, right:&B) -> Chain<A,B,T>` requires both sources to
implement `Iterator<T>`. It yields left items until the first left `None`,
then right items. The same call that observes left `None` queries the right.
It never queries left again. Right `None` is latched, after which neither
source is queried. Construction makes no source call.

Each `next` invokes at most two direct upstream `next` calls. Nested adapters
retain their own bounds; this is not a global execution-time bound on arbitrary
user implementations. `borrow()` permits further composition.

The adapters' own done/phase flags enforce their terminal behavior. Source
implementations still owe the protocol's fused law. Public mutation that
rewinds an exhausted leaf or resurrects an adapter invalidates that law.

## Bounded consumption

`advance_up_to<I,T>(source:&I, limit:u64) -> Advance` requires `I:Iterator<T>`.
It reads and discards up to `limit` items, stopping on the first `None`.
`Advance` contains:

| Field | Meaning |
| --- | --- |
| `advanced:u64` | Number of successful items consumed in this call |
| `exhausted:bool` | This call observed a `None` |

A zero limit makes no source calls and returns `(0,false)`. If exactly `limit`
items succeed, the result is `(limit,false)` even if the next call would return
`None`: there is no extra exhaustion probe. If `None` occurs first,
`advanced < limit`, `exhausted` is true, and direct source-call count is
`advanced + 1`. The total number of direct source calls never exceeds `limit`.

Counts cannot overflow: only a successful call made while `advanced < limit`
increments the counter. `u64::MAX` is a permitted limit. It is a call bound,
not a practical deadline; callers must choose an appropriate resource limit.
The source method itself must terminate for each call. The consumer does not
release shallow owner handles that it discards and cannot cancel an in-progress
source call.

Construction and metadata methods are O(1), as are leaf `next` calls. Adapter
work is O(number of direct upstream calls), and `advance_up_to` is
O(number of calls made), in addition to the upstream method's work.

## Latest matching timeline application

The [timeline-tail program](stdlib-timeline-tail.md) composes a borrowed slice
cursor through `rev -> filter -> take -> enumerate` and canonical CSV output.
It selects newest matching records without building a reversed copy. The CSV
table and entry-vector backing outlive every borrowed cursor/callback; output
is staged independently before those owners are destroyed. Its own guide
records schema, byte/record/output limits and I/O behavior. Four direct native
groups pass separately: model 25, rejection 24, CLI 20 and I/O 2 cases, including
exact caps, count zero, UTF-8/CSV content, directory-stdin failure and a closed
stdout reader. The final application also passes all four registered Rust
runtime tests in 9.15s, including their strict executable check. These cover
the same 71 cases and are separate from the iterator protocol tests. Accepted
source is `6579274d…`, ELF `aca6fc83…` and oracle `233d98e2…`; final runtime
receipt is `target/stdlib-work/timeline-tail-rust-final.log`. Earlier raw runs
do not add another 71 distinct cases.

## Range-statistics application

The [range-statistics program](stdlib-range-stats.md) parses i32 endpoints and a
quota, walks an inclusive RangeI32 through borrowed Take, then writes a CSV
count and i64 sum through checked formatting and complete output. The quota is
at most one million. It accepts the full i32 endpoint domain, with reversed
bounds and zero quota producing an empty selection.

A separate compilation supplies 41 native cases, including million-item
positive/negative sums, exact stdout comparisons against an i128 arithmetic
reference, malformed arguments, both argument-allocation failures and checked
output/signal-policy failures. Argument snapshots are released on each path.
This is separate evidence from the five module groups below.

## Native acceptance

The original groups below used the earlier `SliceIter<T>` wrapper. Current
[canonical cursor integration](stdlib-cursor-integration.md) returns
`core::slice::Iter<T>` directly and records its separate execution evidence.

`tests/stdlib_iterator_execution.rs` and its seven fixtures under
`tests/fixtures/stdlib_foundation/iterators/` passed all five focused groups on
x86_64 Linux using compiler checkpoint
`59612b3431d7b0cdff16a6faecf881f62a675503`. Every successful ELF passed the
unchanged common x86 jump checker before native execution. Logs are under
`target/stdlib-work/iterator-admission/`:

| Focused group | Accepted behavior | Time | Log |
| --- | --- | --- | --- |
| Imported admission | Nested Take, Chain, local implementation, generic consumers, compound payload and terminal range; native exit 0 | 5.52 s | `imported-direct-view.log` |
| Cursor/adapter contracts | Metadata preflight, live backing and leaf forks, zero-query poison source, quotas, fused/no-overread calls, shared aliases, packed/strided bytes, ZSTs and O(1) full-domain range skips; zero mmap/munmap calls | 4.75 s | `contracts.log` |
| Independent models | All 6602 sequence/state cases match the host references; native exit 0 | 4.99 s | `model.log` |
| Owner aliases and physical bounds | Source String backing remains usable after consuming shallow aliases, with exactly one source allocation and its matching release; separate native physical overclaim exits 101 | 5.42 s | `owners-physical-byte-length.log` |
| Exact item bounds | Both missing Iterator and wrong-item Iterator<bool> cases reject with LNC0008 at their own `advance_up_to` call | 3.70 s | `bounds.log` |

These groups contain seven compilation jobs: five successful ELFs and two
expected source-local rejections. The five native processes include the
intentional physical-bounds exit 101. Durations are focused gate wall times,
not runtime throughput measurements.

The 6602 model commands comprise 3375 finite concatenation/prefix cases,
275 interleaved copied-adapter schedules, 2592 exhaustive small range/skip
cases and 360 extreme-endpoint/O(1)-skip cases. The sequence reference defines
the finite concatenation and its consumed prefix independently. The schedule
reference tracks separate adapter quotas over one shared source. Wide interval
references compute cardinality and skips in i64/u64 without enumerating a
billion-element interval.

### Preserved compiler boundary

The original constructor first wrapped `View<T>` in a Result and used generic
`is_err`, `unwrap` and `unwrap_err` helpers. A minimal direct SliceIter<i32>
entry reached LNC0047 because the nested `View<i32>` replay argument lacked a
complete native layout witness; `SliceIter<i32>` itself already had a known
five-word width. The passing inherent slice control and debug evidence are
preserved with the exact original module and entry in
[the compiler-state capture](../tests/fixtures/stdlib_compiler_state/iterator_view_result/README.md).

The direct typed View construction described above removes that redundant
Result composition and centralizes validation in the existing `from_view`.
It preserves the generic API, errors and physical-backing caller contract.
The current full admission passes; this library simplification does not claim
a compiler fix for the captured original composition.

Two initial failures were fixture mistakes, corrected before the accepted
gates: LNC0021 required public implementations/members for the public trait,
and LNC0027 rejected the nonexistent `String.len` call, corrected to `byte_len`.
Their logs remain `imported.log` and `owners-physical.log`; they are not compiler
dependencies. Historical `iterator_dependency` sources and controls remain
unchanged. No broad slice, range or stdlib suite was rerun for this admission.
