# Iterator lookahead and reductions

`core::iter` adds a one-item `Peekable<I,T>` adapter, relative position search
and minimum/maximum reductions. Its four library groups and the sample group
have passing native Linux x86_64 receipts through the GPU compiler, recorded
separately below. Other targets and user-program GPU execution have separate
acceptance requirements.

The existing [iterator protocol](stdlib-iterators.md), callback lifetimes and
shallow-value ownership rules apply. `StepBy` remains the existing
[source adapter](stdlib-iterator-sources.md).

## Lookahead API

```lanius
pub enum PeekableError { Cached }
pub struct Peekable<I,T> {
    source: &I,
    cached: core::option::Option<T>,
    done: bool,
}
pub fn peekable<I,T>(source: &I) -> Peekable<I,T> where I: Iterator<T>;
```

Construction is lazy and allocates nothing. The adapter borrows the source
cursor object; that object, its backing and any callback context must outlive
the adapter and its borrowed observations.

| Operation | Effect |
| --- | --- |
| `borrow()` | Borrow this active adapter |
| `peek() -> Option<T>` | Observe a borrowed shallow item; fill an empty cache with at most one upstream pull |
| `has_cached() -> bool` | Inspect the cache without polling |
| `next() -> Option<T>` | Transfer a cached item first; otherwise pull upstream at most once |
| `take_cached() -> Option<T>` | Transfer only the cached item; never poll or close |
| `try_finish() -> Option<PeekableError>` | Reject a cached item, or close this adapter without polling/cleaning upstream |

Repeated peeks retain the same item without another source call. For optional
items, cached `Some(None)` is a real item; it differs from an empty cache.
The first upstream `None` latches exhaustion. Further peeks and pulls return
`None` without polling upstream. `next` and `take_cached` clear the actual cache
before returning its item.

`peek` returns a shallow value descriptor, not a separately owned clone.
It grants no cleanup authority. Treat it as read-only and end its aliases
before transferring, mutating or destroying the cached item. A primitive
value already cached is a snapshot of that value; nested borrowed data keeps
its ordinary aliasing and lifetime contract.

If an owning source transfers an item during the first peek, the adapter now
holds that item's cleanup authority. It is no longer in the upstream owner's
remaining cleanup range. Keep one active ownership-bearing adapter handle;
copied descriptors do not create another owner or independent traversal.
The language does not enforce these rules.

## Cache recovery and source resumption

`try_finish` returns `Some(PeekableError::Cached)` while an item is cached. It
preserves the item and every state field. Consume it with `next` or recover it
with `take_cached` before trying again. `take_cached` leaves the adapter active
and transfers no uncached upstream item.

With an empty cache, finish latches this adapter closed and returns `None`,
even when upstream still has items. It never polls, drains, closes or frees the
borrowed source. Finish is harmless when repeated on that same closed adapter.
Resume the upstream cursor at its current position after closing the adapter.
Recover or consume a cached owner before destroying its upstream backing.
Never resume upstream behind an active cache: the cached value logically
precedes upstream's unread remainder.

These explicit recovery/finish rules adapt familiar lookahead behavior to
Lanius's manual ownership. Rust's primary
[`Peekable` documentation](https://doc.rust-lang.org/std/iter/struct.Peekable.html)
describes conventional repeated peeking; Lanius exposes shallow observations
and explicit cleanup authority rather than Rust references and automatic drop.

## Position search and overflow

```lanius
pub fn position<I,P,T>(source: &I,predicate: &P) -> Option<u64>
    where I: Iterator<T>, P: Mapper<T,bool>;
pub fn position_from<I,P,T>(source: &I,predicate: &P,first_index: u64) -> Option<u64>
    where I: Iterator<T>, P: Mapper<T,bool>;
```

`position` labels this call's first remaining item zero. `position_from`
labels it `first_index` without skipping anything. Each representable item is
pulled, passed to the predicate once and consumed. The first true result
returns its index without another source poll. No match consumes through the
first `None`. A later call starts relative to the then-current remainder.

`u64::MAX` is a valid index. After a nonmatching item at MAX, a subsequent
`None` is normal exhaustion. A subsequent `Some` is consumed and then panics
**before its predicate call**. No addition or index wraps. This matches the
existing `Enumerate` overflow policy. The scalar trap witness establishes
ordering only; it makes no claim of owner cleanup after panic.

Position returns no consumed item. For an owning source, the predicate or
caller must separately retain/release every consumed owner, including a match.
There is no implicit `Destroy`.

## Minimum and maximum

`min<I,T>(source)` and `max<I,T>(source)` require `T: core::cmp::Ord<T>`.
Native floats do not satisfy that total-order bound; use an explicit lawful
comparison policy or the [float-order wrappers](api/core/float_order.md).

Custom comparison uses the canonical trait in `core::ordering`:

```lanius
// Declared in core::ordering.
pub trait Comparator<L,R> {
    pub fn compare(&self,left: L,right: R) -> core::ordering::Ordering;
}
pub fn min_by<I,C,T>(source: &I,comparator: &C) -> Option<T>
    where I: Iterator<T>, C: core::ordering::Comparator<T,T>;
pub fn max_by<I,C,T>(source: &I,comparator: &C) -> Option<T>
    where I: Iterator<T>, C: core::ordering::Comparator<T,T>;
```

The [slice-ordering increment](stdlib-slice-ordering.md) moves and generalizes
this trait so the same protocol also supports heterogeneous queries.
Implementations and bounds migrate directly; there is no old
`core::iter::Comparator<T>` alias. The historical receipts below retain their
original source scope; current migration checks are recorded in the new guide.

All four return `None` for empty input. Otherwise they consume through the
first upstream `None` and return one original representative. Minimum keeps
the **first** tied representative; maximum keeps the **last**. The tie policy
also appears in Rust's primary
[`Iterator` reference](https://doc.rust-lang.org/std/iter/trait.Iterator.html#method.min).

Custom reducers make exactly n−1 comparison calls for n nonempty inputs, in
`(current winner,new source item)` order. No comparison runs for an empty or
singleton source. A callback must provide a consistent total ordering and
preserve the shallow values needed by later calls and the result. The callback
and any borrowed context must remain alive throughout the reduction.

The reducers allocate nothing, clone nothing and destroy nothing. For borrowed
String items, the winner remains an alias of its original owner. Reducing an
owning cursor does not clean up discarded owners: use a separate caller or
callback policy to retain or release them. Finite input is required to finish;
source and callback cost or termination are outside the reduction's control.

## Focused execution evidence

The historical freeze has passing evidence for all five groups in
`tests/stdlib_iterator_lookahead_execution.rs` across separate runs:

- Nested optional items, lazy construction, cached finish rejection, cache
  recovery, no-poll finish, source resumption and relative/MAX position edges;
  three actual-call predicate/comparator/Ord bound rejections.
- 1,280 complete four-action schedules over short sources, 320 extrema cases
  with independent tie/operand-order oracles and 180 position cases.
- Ten distinct String owners plus three vector backings, with exact mapping
  identities. Recovered cache owners survive upstream cleanup; borrowed
  extrema aliases are released only by their original owner.
- A scalar overflow program observes `aPb` before checked panic: MAX's source
  item and predicate, then the unindexable source item without its predicate.
- The [column extrema sample](stdlib-column-extrema.md), including validation,
  limits, all four reached allocation-failure positions and output failure
  behavior. Its 24 process cases include explicit reached write injections.

| Receipt under `target/stdlib-work/` | Result | Time |
| --- | --- | --- |
| `iterator-lookahead-first.log` | Four library groups passed; sample group failed its final short-write harness assertion | 15.67 s |
| `column-extrema-write-faults-corrected.log` | App-only rerun failed its new injected-trace count parser | 5.72 s |
| `column-extrema-injection-parser-corrected.log` | App-only group passed with all cases and fault assertions active | 6.51 s |

The initial driver omitted `write` from its strace selection, so write fault
injection was not reached. Adding it exposed a second harness bug: the count
parser selected the closing parenthesis in `(INJECTED)` rather than the syscall
arguments. The corrected parser uses the syscall/result separator. The final
gate requires exactly one actual injected stdout write with the requested
EINTR or synthetic result, followed by the correctly sized successful retry.
Library and sample production source remained unchanged throughout these runs.

The driver retains the shared strict ELF checker. Allocation ledgers and
bounded independent models give finite evidence, not a proof of all iterator
programs.

The [canonical comparator migration](stdlib-slice-ordering.md) separately
passes three selected current tests in 16.23s under
`slice-ordering-iterator-migration-regression.log`: the 1,280 schedules /
320 extrema / 180 position model, cached/borrowed owner cleanup and exact
capability rejections. Two unrelated tests were filtered; the historical
sample and overflow-trap receipts above were not rerun. The current fixtures
implement `core::ordering::Comparator<T,T>` directly.
