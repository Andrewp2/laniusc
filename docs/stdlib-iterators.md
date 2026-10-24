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
execution or other targets.

[Collection, Text and bitset cursors](stdlib-collection-iterators.md) implement
the same protocol. Their separate native gates check mixed traversal,
compound map entries, borrowed String aliases and byte/scalar view behavior.

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

## Items, copies and lifetime

Every returned item is an ordinary shallow Lanius value copy. Returning or
discarding it does not deep-clone, transfer unique ownership, or invoke
`core::clone::Destroy`. For a String or other owner handle, a yielded handle can
alias the original owner. Keep one release authority and destroy that owner
once, after all uses of borrowed aliases. This API does not make an owning
collection drain or automatically release elements skipped by a consumer.

`core::slice::Iter<T>` contains a copied slice descriptor and cursor state. The original
View record can go out of scope, but its physical backing must remain alive,
initialized and valid. Destroying or reallocating the backing owner invalidates
the cursor. Valid alias mutations are observed by later reads; elements are not
snapshotted. `RangeI32` captures numeric bounds and has no external backing.

Copy semantics depend on the cursor:

| Copied value | State after copying |
| --- | --- |
| `core::slice::Iter<T>` | Independent positions; same backing elements |
| `RangeI32` | Independent positions over captured numeric bounds |
| `Take<I,T>` | Independent quota/done flags; same borrowed source cursor |
| `Chain<A,B,T>` | Independent phase/done flags; same borrowed source cursors |
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
| `core::slice::Iter<T>::next(&self)` | Shallow current element, then advance; fused at zero remaining |

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
canonical `core::slice::Iter<T>` as `View.iter()`. Its forward trait method
lives in `core::iter`; backward access, skipping and metadata methods live in
`core::slice`. Import `core::iter` where the shared protocol is used. This
keeps one cursor state and one forward transition without an import cycle.
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
Both advance upwards by exactly one. Reversed bounds are empty; equal bounds
are empty for the half-open form and yield one element for the inclusive form.
Later changes to the original range record do not change the cursor.

`RangeI32` provides `borrow`, `next`, `remaining() -> u64` and
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
This module defines no float, arbitrary-record, descending or custom-step
iteration policy.

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
