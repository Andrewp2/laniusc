# Exact remaining iterator counts

`core::iter::ExactSizeIterator<T>` adds a portable `u64` count of the values
that an iterator can still yield. It composes with the existing
[forward and reverse protocols](stdlib-iterators.md). All four focused library
gates and all four real byte-sampling application gates pass on the finite
Linux x86_64 profile below. This is native CPU output from the GPU compiler.

## Contract and bounds

```lani
pub trait ExactSizeIterator<T> {
    pub fn remaining_count(&self) -> u64;
}
```

An implementation supplies `Iterator<T>` for the same item type. Generic
callers name both bounds explicitly:

```lani
fn exact_count<I,T>(source: &I) -> u64
    where I: core::iter::Iterator<T>, I: core::iter::ExactSizeIterator<T> {
    return source.remaining_count();
}
```

In valid state, `remaining_count()` equals the number of future `Some` values
before permanent `None`, assuming valid source/callback behavior and no
intervening external consumption or mutation. For a double-ended source,
front and back consume this one count together, without crossing or counting
an item twice. A successful output consumes one count. The result is exact,
not an upper bound, a quota, a byte size or the original collection length.
Every supported count fits `u64`; counts are independent of host pointer width.
Construct cursors through their factories and keep metadata valid: ordered
slice bounds, positive chunk/window width and unmodified library state.
Count queries return `u64`, not a recoverable validation result. They neither
repair forged state nor prove that every claimed element has live backing.

The query is observational: it does not change traversal or cache state,
pull from either end, invoke callbacks, read an item payload, allocate, perform
host I/O or release an owner. An adapter may query its source's
`remaining_count()`; that source must obey the same contract. Library leaves
read maintained scalar metadata in constant time. Adapters add bounded local
work plus any delegated count query; they do not scan the remaining items.
An exact count supplies no time bound on a later source pull or callback.

This shares Rust's [exact remaining-length principle](https://doc.rust-lang.org/std/iter/trait.ExactSizeIterator.html).
Lanius deliberately uses `remaining_count` and fixed `u64`, rather than Rust's
`len`/`usize`; it spells both trait bounds instead of using a supertrait.
There is no `TrustedLen`-like memory-safety authority. Callers still check
integer conversions, byte-size multiplication, limits, capacity and each
write through the normal safe APIs. A wrong user implementation cannot
authorize unchecked memory access.

## Sources

| Source | Exact remainder |
| --- | --- |
| `Empty<T>` | `0` |
| `Once<T>` | `1` before consumption, then `0`; querying does not copy the item |
| `RangeI32` | Widened `end-position`, including all `2^32` values in the full inclusive i32 range |
| `core::slice::Iter<T>` | Shared `back-front` element count after front/back pulls or explicit advancement |
| `core::slice::Chunks<T>` | Remaining chunk count, including a final short chunk |
| `core::slice::Windows<T>` | Remaining complete overlapping window count |
| `alloc::vec::IntoIter<T>` | Its existing maintained live-item remainder |
| Deque `Cursor<T>` / `IntoIter<T>` | Remaining logical entries across wraparound; both ends share the count |
| HashMap / HashSet `IntoIter` | Remaining live entries/keys, not remaining buckets or backing capacity |
| TreeMap / TreeSet `IntoIter` | Remaining owned entries/keys after either supported pull direction |
| BinaryHeap `IntoIter<T>` | Remaining owned items, with its existing `T: Ord<T>` bound |

For chunks/windows let `n` be the remaining element span and `w>0` the
factory-validated width. Chunk count is `n/w + (n%w != 0 ? 1 : 0)`; window
count is zero when `n<w`, otherwise `n-w+1`. These count yielded views, not
the total number of elements across those views. Chunks and Windows remain
forward-only. Factories that return the canonical slice iterator inherit
that iterator's count contract.

Borrowed hash/tree cursors are outside this increment: their current state
does not maintain the required constant-time remainder. No item scan or
additional traversal-state field is introduced to make them appear exact.

## Adapter formulas

Let `n` be the source's **current** exact remainder. A locally exhausted
adapter reports zero without reviving its source. The following conditional
implementations retain all existing traversal/callback bounds:

| Adapter | Additional requirements and count |
| --- | --- |
| `Rev<I,T>` | Source implements Iterator, DoubleEndedIterator and ExactSizeIterator for `T`; count is `n` |
| `Map<I,M,T,U>` | Source implements Iterator/ExactSizeIterator for `T`, mapper implements `Mapper<T,U>`; count is `n`, with no mapper call |
| `Take<I,T>` | Source implements Iterator/ExactSizeIterator for `T`; count is `min(n, remaining_limit)` |
| `Skip<I,T>` | Same source bounds; count is zero when `n<=pending_skip`, otherwise `n-pending_skip` |
| `StepBy<I,T>` | Same source bounds; uses the first/subsequent formulas below |
| `Peekable<I,T>` | Same source bounds; source count plus one occupied cache slot, without filling or consuming the cache |

These bounds must use the same source item type. Map's result trait is
`ExactSizeIterator<U>`. A source that only has a similarly named inherent
method, or implements the trait for another item type, does not satisfy the
bound. Exact size does not create reverse traversal: Take, Skip, StepBy and
Peekable retain their existing forward-only protocol.

### StepBy before and after the first output

`step_by(source, step)` rejects zero and stores `skip=step-1`. Before its first
pull, it selects the first item immediately:

```text
count = 0                         if n == 0
count = 1 + (n-1)/step             otherwise
```

After its first pull, each next output first skips `step-1` source items:

```text
count = n/step
```

The first form avoids overflowing `n+step-1`. For ten source items and step
three, the initial count is four. After yielding the first item the source
has nine remaining and the count is three. If only two source items then
remain, count is zero: those items are pending discards, not future outputs.
A query never performs those discards. A later `next()` can still do work
before returning None, even when the exact output count is zero. The same
distinction applies to Skip with more pending skips than available input.

The source evaluates the initial ceiling with quotient/remainder and the
subsequent count with integer division; neither requires an overflowing sum.

### Peekable and cache ownership

An occupied cache contributes one output even though the source has already
consumed it. `peek()` can move an item from source to cache without changing
the adapter's total remainder. `next()` or `take_cached()` removes that one
output. An item whose type is Option can be `Some(None)` in the cache and
still counts as one; an absent cache counts as zero. Querying an empty cache
does not call `peek()` or inspect a payload. Successful `try_finish()` closes
an empty cache; a cached owner must first be consumed or explicitly recovered.
The existing [cache recovery and source-resumption policy](stdlib-iterator-lookahead.md#cache-recovery-and-source-resumption)
still applies: never resume upstream behind an active cache. A count query
does not release a cached alias or change its ordering/cleanup authority.
Valid cache/source states keep the total representable in `u64`. If a
nonconforming source claims `u64::MAX` remaining while a cache is occupied,
the implementation traps instead of wrapping the sum; the query is not a
fallible repair API for forged state.

## Aliases, owners and exclusions

Borrowed adapters refer to the actual source cursor. Legitimate sequential
source consumption **between** adapter calls is allowed under the existing
source/adapter lifetime, order and ownership rules; the next query sees the
current remainder with that adapter's own quota/skip state applied. Peekable
permits no upstream resumption behind an active cache: consume/recover that
item and follow its existing finish/resumption policy. A previously returned
count is not a reservation against other handles.
Do not reset, forge, retire or mutate traversal state through an independent
alias while an adapter depends on it. A mapper must not independently advance,
retire or mutate upstream traversal during `apply`; stateful output/logging is allowed.
Reentrant or concurrent mutation is outside the manual contract.

Cursor metadata snapshots still follow each factory's existing policy; counts
do not turn them into live views of a collection's structural changes. Keep
source, callback context and all backing owners live through their borrowed
uses. Readable physical bounds remain a caller precondition. Count queries
neither clone nor destroy items; owning cursors keep their existing explicit
transfer, recovery and finish/destroy rules. Skip/StepBy still discard shallow
values during traversal, so transferred owners need a deliberate cleanup
policy. Counting them does not add one.

| Excluded surface | Reason |
| --- | --- |
| `Zip` | Two borrowed inputs may alias the same cursor. With four shared items, zip can yield two pairs while `min(4,4)` would predict four |
| `Chain` | Two valid `u64` source counts can have a nonrepresentable sum; there is no saturating or wrapped exact count |
| `Repeat` and unbounded sources | No finite full cardinality |
| Filter/FilterMap, while adapters, Scan/TryScan and nested iteration | Future callbacks, stopping or inner production determine cardinality |
| Checked-index `Enumerate` | Its current index-limit failure policy is not this total exact-count contract |

Rust's official [Chain exclusion](https://doc.rust-lang.org/std/iter/trait.ExactSizeIterator.html#when-shouldnt-an-adapter-be-exactsizeiterator)
uses the same representability concern. Lanius also excludes Zip because its
borrowed source aliases differ from Rust's owned-adapter assumptions. No
length is guessed, clamped, saturated or substituted for these exclusions.

## Executable evidence and target

All four `stdlib_exact_size_iterator_execution` gates pass across two
receipts, with core source `be05d6c2…`:

| Gate | Accepted finite scope |
| --- | --- |
| Pure contracts | Six bounded scenario functions cover full-domain i32/u64 counts, huge steps/skips/quotas, shared-source resumption under the existing rules, cache recovery/finish, compound/optional/zero-size items and chunk/window boundaries; the mmap/mremap/munmap/brk trace is empty |
| Collection owners | Existing O(1) remainders follow mixed supported pulls, explicit transfer, recovery and finish on all selected collection cursors; every observed backing allocation has a matching successful release by full address and size |
| Independent model | 10,714 cases and 35,922 steps across 18 modes, seed `0xe5ac72026`, compare values, exact before/after counts and source/mapper effects |
| Capability rejection | Five fixtures reject with `LNC0008` at the marked call: missing exact capability, wrong item type, Filter, Chain and Zip |

The reference counts a fully isolated sequence/deque copy by draining it,
rather than reproducing the library's count formulas. Model schedules cover
both ends where supported, partial sources, composed skip/step/take,
Map/Rev, repeated queries, Peekable inspection/recovery/finish and exhaustion.
The pure contract's deliberately unreadable item descriptor is only a no-read
control: it is never pulled and supplies no permission to dereference invalid
backing. Packed positive and fixed negative byte strides are exercised in
separate valid-backed controls.

The three nonmodel gates pass in 11.82s in
`target/stdlib-work/exact-size-runtime-accepted.log`. That command also records
one model compile failure caused by a fixture visibility error. After fixing
that fixture, the isolated model test passes in 8.44s in
`target/stdlib-work/exact-size-model-visibility-fixed.log`. These are four
accepted distinct tests across receipts, not an all-pass combined command.
Final contract/collection/model sources are
`43e59a04…`/`a6e0e74a…`/`719f6d7f…`. Earlier attempts overlap these tests and
add no distinct cases.
The [fixture guide](../tests/fixtures/stdlib_foundation/exact_size_iterators/README.md)
defines the finite test boundary; no new owning-allocation failure campaign
or automatic cleanup guarantee follows.

The unchanged independent reverse model also passes its one selected
registered test in 7.27s against current source: 7,740 VecDeque-reference
commands, recorded in `target/stdlib-work/exact-size-reverse-regression.log`.
This is not a rerun of the full old reverse suite.

The real [sample-bytes program](stdlib-sample-bytes.md) composes a slice cursor,
optional Rev, Skip, StepBy and Take. It reserves using the final exact count,
keeps checked pushes and an independent byte bound, and verifies output
length before publication. It owns independent input/output vectors and makes
no reversed copy. All four registered application tests pass in 9.44s,
covering 95 process cases: model37/limits3/CLI39/I/O16, including binary bytes,
integer boundaries, I/O faults and two reached allocation denials. Source is
`f2dc4738…`; the receipt is
`target/stdlib-work/sample-bytes-runtime-first.log`. CPU oracle controls are
separate from Lanius execution and are not added to those case counts.

Supported evidence is native Linux x86_64 execution. The count implementations
add no compiler change, host service or allocator dependency; the real program
composes existing owned storage and host streams. Other targets, unchecked
memory trust, automatic lifetime/destruction, formal proof and user-program
GPU execution remain unclaimed.

### Narrow compiler dependency

The focused model retains a narrow
[chained generic Option receiver reduction](../tests/fixtures/stdlib_compiler_state/chained_generic_option/README.md):
`source.next().is_some()` rejects with `LNC0027`, while an explicitly typed
`Option<T>` local control compiles and exits zero. The model uses that local;
its semantics are unchanged. This is a receiver-resolution dependency, not
evidence of a general generic payload/storage failure, and this increment
changes no compiler production code.
