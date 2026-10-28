# Iterator reductions and bounded folds

This increment adds eight consumers to `core::iter`, using the existing
[iterator and callback traits](stdlib-iterators.md). The fixed
[fold contract](library-iterator-fold-plan.md) defines their behavior.
All seven new library and four application gates pass on native Linux
x86_64. This finite increment is accepted.
Earlier reverse, exact-size and selection/fold receipts retain their own
source/API scope. The full standard and extended library goal remains open.

## API and callback bounds

```lani
pub struct FoldProgress<A> { accumulator:A, folded:u64, exhausted:bool }
pub struct FoldFailure<E> { folded:u64, error:E }
```

Every function borrows its source and folder. `Folder<A,T>::apply` takes
`(accumulator,item)` and returns `A`; `TryFolder<A,T,E>::try_apply` takes the
same arguments and returns `Result<A,E>`. There is no new callback protocol.

| Function | Result | Required bounds |
| --- | --- | --- |
| `reduce<I,F,T>(source:&I,folder:&F)` | `Option<T>` | `I:Iterator<T>`, `F:Folder<T,T>` |
| `try_reduce<I,F,T,E>(source:&I,folder:&F)` | `Result<Option<T>,E>` | `I:Iterator<T>`, `F:TryFolder<T,T,E>` |
| `rfold<I,F,T,A>(source:&I,initial:A,folder:&F)` | `A` | `I:Iterator<T>`, `I:DoubleEndedIterator<T>`, `F:Folder<A,T>` |
| `try_rfold<I,F,T,A,E>(source:&I,initial:A,folder:&F)` | `Result<A,E>` | Both source bounds above, `F:TryFolder<A,T,E>` |
| `fold_up_to<I,F,T,A>(source:&I,initial:A,folder:&F,limit:u64)` | `FoldProgress<A>` | `I:Iterator<T>`, `F:Folder<A,T>` |
| `try_fold_up_to<I,F,T,A,E>(source:&I,initial:A,folder:&F,limit:u64)` | `Result<FoldProgress<A>,FoldFailure<E>>` | `I:Iterator<T>`, `F:TryFolder<A,T,E>` |
| `rfold_up_to<I,F,T,A>(source:&I,initial:A,folder:&F,limit:u64)` | `FoldProgress<A>` | `I:Iterator<T>`, `I:DoubleEndedIterator<T>`, `F:Folder<A,T>` |
| `try_rfold_up_to<I,F,T,A,E>(source:&I,initial:A,folder:&F,limit:u64)` | `Result<FoldProgress<A>,FoldFailure<E>>` | Both source bounds above, `F:TryFolder<A,T,E>` |

All paths are in `core::iter`. Reverse consumers name both source traits with
the same `T` explicitly. They require neither exact-size metadata nor a
clone/destruction/default-value trait. Arithmetic, overflow and domain errors
belong to the supplied callback's policy.

## Reduction and reverse order

`reduce` pulls the first front item as its initial accumulator. Empty input
returns `None`; a singleton returns that item. Neither case invokes the
folder. Longer inputs fold subsequent items in front-to-back order, with no
synthetic identity or default `T`. `try_reduce` returns `Ok(None)` for empty,
`Ok(Some(item))` for a singleton, and propagates the first callback error.

Reverse folds use only `next_back`. For remaining items `[a,b,c]`, the result
is:

```text
f(f(f(initial,c),b),a)
```

Callback argument order remains accumulator first. No associativity or
commutativity is required. Forward and reverse consumers share the same
remaining cursor state, so callers can consume a front prefix, fold a back
suffix and later resume the middle. Existing cursor/cache/backing rules still
apply, including the [Peekable source-resumption policy](stdlib-iterator-lookahead.md).

The unbounded reduction and reverse-fold principles follow Rust's official
[reduce/try_reduce](https://doc.rust-lang.org/std/iter/trait.Iterator.html#method.reduce)
and [rfold/try_rfold](https://doc.rust-lang.org/std/iter/trait.DoubleEndedIterator.html#method.rfold)
contracts. Lanius uses borrowed sources, named source-defined callback traits
and explicit `Result` errors. The bounded progress/failure envelopes below
are Lanius contracts.

Unbounded variants consume until an actual `None` or callback error. Callers
must supply terminating sources and callbacks to guarantee completion.
An infinite source can make an unbounded consumer run forever.

## Quotas and observable progress

Every bounded call performs at most `limit` direct pulls from its selected
end. A `Some` causes one callback; an observed `None` stops immediately.

| Outcome | Progress and source effects |
| --- | --- |
| `limit==0` | Unchanged initial accumulator, `folded=0`, `exhausted=false`; no pull, metadata query, callback, allocation, retirement or EOF probe |
| An actual `None` before the quota | `exhausted=true`; `folded` counts successful applications before that observation |
| The last allowed `Some` succeeds | Stop immediately with `folded==limit`, `exhausted=false`; no extra EOF probe |
| Callback error | Stop immediately; the failing item is already consumed and the error envelope counts only earlier successful applications |

`FoldProgress.accumulator` includes exactly its `folded` successful callback
applications. Counts are local to this call, not cumulative cursor counts.
`exhausted=true` records an observed `None`. When a quota happens to consume
the final item, the result still says `exhausted=false`; another nonzero call
can observe EOF. No peek or `remaining_count()` query changes that rule, even
for an exact-size source. A `None` observation itself spends one direct pull.

For example, a quota of two over three front items folds two and leaves the
third. A second quota of one folds that item but still reports
`exhausted=false`. A third nonzero call observes `None`, returns its supplied
initial accumulator with `folded=0` and reports `exhausted=true`.

The counters are `u64`. A callback is attempted only while `folded<limit`;
incrementing a successful count cannot wrap, including `limit=u64::MAX`.
For an error, `folded+1` is the number of attempted callbacks and is also
representable. This contract does not imply that an executable test performs
`u64::MAX` pulls.

The quota bounds direct calls only. One adapter pull can scan many upstream
items, and a source or callback can allocate or perform arbitrary work.
Bound those operations separately when needed; the quota supplies no
instruction, memory or wall-clock budget.

## Errors, consumed items and recovery

On callback error, every fallible consumer returns immediately without
another pull or callback. The failing item has already left the source.
Forward resumption starts at the next unconsumed front item; reverse
resumption starts at the next unconsumed back item. Neither path retries the
failed item or rolls back source/callback effects.

`try_reduce` and `try_rfold` transfer the callback's `E` directly. The bounded
variants return:

```text
FoldFailure { folded: earlier_successful_callbacks, error: callback_error }
```

The failure envelope supplies no built-in accumulator or rejected-item field.
If recovery needs either owner, `E` must carry the **actual updated**
accumulator and current item supplied to the callback. It may include work
performed inside the failed callback; `folded` still excludes that callback.
Handle that error before resuming the remaining source. No earlier shallow
accumulator alias becomes valid cleanup authority after failure.

## Manual ownership

The consumer layer itself allocates no storage, calls no `Clone`/`Destroy`
and adds no source-retirement call. Pulls and callbacks retain their existing
allocation/cleanup effects. Initial accumulators, yielded items, callback
arguments and returned envelopes follow the language's shallow-value rules.
An item yielded by a borrowed cursor can be only a shallow alias of its source
owner. Passing it by value grants no new cleanup authority. Owning cursors
transfer actual item ownership under their existing protocol; callbacks must
follow the source's ownership policy.

A callback must release, retain or return each owned resource it consumes,
on success and failure. Replacing an accumulator does not automatically
destroy its old backing. Returning an error does not automatically destroy
the current item. A zero-progress result can still carry an owned initial
accumulator; it does not create an independent owner copy.

Keep source backing and folder context live and avoid reentrant source
mutation through aliases during a call. Between calls, resume the shared
remainder under the source/adapter's normal rules. Clean up returned
accumulators/errors and any remaining owning cursor explicitly. No automatic
lifetime, move, destruction or runtime-resource checker is added.

The type surface is generic. Supported scalar/compound/nested-owner
compositions still require executable evidence; this guide makes no blanket
claim that every compiler generic composition is supported.

## Verification and remaining scope

All seven new registered library tests pass on the source identity below:

| New library gate | Accepted receipt under `target/stdlib-work/` |
| --- | --- |
| Pure semantics and two negative-bound groups | Three tests, 9.13s; `iterator-fold-contracts-first.log` |
| Owning cursor/recovery and two allocation-denial groups | Three tests, 7.62s; `iterator-fold-owners-first.log` |
| Independent sequence/state model | One test, 9.10s; `iterator-fold-model-first.log` |

The pure fixture executes all eight APIs without allocation services,
including compound/nested item, accumulator and error types and an empty
Infallible error type. Two negative groups reject eight invalid source/
callback-bound compositions. These concrete witnesses establish no blanket
support for arbitrary compiler generic compositions.

The independent model covers 10,696 cases and 37,104 state commands over four
source forms, seed `0xf01d20261029`, in one batched native process. It uses
materialized deques and observable state rather than the Lanius fold bodies.
Metered slice subviews, mapped ranges, a reverse mapped range and mapped
slices check progress, actual EOF, source polls/positions, mapper/callback
counts, absent metadata queries, callback argument order, exact error
identity and mixed-end resumption. The [model fixture guide](../tests/fixtures/stdlib_foundation/iterator_folds/README.md)
records the finite corpus and source identities. These are state-model
commands, not additional shell commands or native processes.

The owner gates execute all eight APIs with actual String-owning Vec cursor
values and nested accumulator/error recovery. Pre-reserved pure fold phases
perform neither allocation nor release services. Two fault groups each run
one baseline and 12 reached mmap denials: 24 selected denials across Vec
setup and callback growth paths, with full address/size cleanup before exit.
A history-growth failure specifically returns the actual updated/reallocated
values owner and popped current item after the first push succeeded, preserving
correct remaining front/back source values. These finite traces establish
neither arbitrary failure schedules nor a lifetime/leak proof.

Two selected current-source regression gates also pass:

| Existing gate | Accepted receipt under `target/stdlib-work/` |
| --- | --- |
| Typed consumer effects, nested values and single-owner cleanup | One test, 7.26s; `iterator-fold-old-consumer-typed-error.log` |
| Reverse compound values, ranges, callback order and empty-chain contracts | One test, 10.96s; `iterator-fold-old-reverse.log`; zero allocation services |

No broad reverse model, owner or bounds suite rerun is claimed. Earlier
iterator receipts retain their historical source/API scope. The accepted
`stdlib/core/iter.lani` SHA-256 is
`1c9ab092a890bda7fa61bdc102034802309421df746df90370f2719e8d294627`.

### Compiler inference dependency

The [reduced inline error-record case](../tests/fixtures/stdlib_foundation/iterator_fold_dependency/README.md)
reproduces `LNC0006` for a generic `step.unwrap_err()` nested directly inside
a record field and outer `Result::Err`. Binding `let error:E` first compiles
and executes wide-u64 error/progress and successful i32 assertions. The
library uses that typed local without restricting its API or payload types.
This remains an expression-context inference dependency; compiler production
source was not changed.

Two registered dependency checks pass in 4.39s, recorded in
`target/stdlib-work/iterator-fold-dependency-corrected.log`: one reproduced
diagnostic and one native positive control. They are not two executing source
forms. The inline test also permits correct execution after a compiler repair;
it does not require valid source to remain rejected.

### Real byte-summary composition

The [byte-summary program](stdlib-byte-summary.md) repeatedly calls bounded
fallible folds over a canonical byte cursor in either direction, checks
progress and stages its CSV summary before native output. Its four registered
application groups pass across two focused receipts:

| Group | Cases | Accepted receipt under `target/stdlib-work/` |
| --- | ---: | --- |
| Model | 40 | One test, 9.92s; `iterator-fold-byte-summary-model.log` |
| CLI, bounds and I/O | 32 + 1 + 14 | Three tests, 9.33s; `iterator-fold-byte-summary-boundaries.log`, model filtered |

These are 87 unique native process cases using application source `78788a61`.
They cover exact 4 MiB/oversized input, real read/write errors and retries,
16,384 persistent read-EINTR attempts and four selected reached allocation
denials. Full traces match observed releases by address and size; the
summary-only persistent-EINTR trace does not observe allocation releases.
The earlier application syntax-admission failure supplies no native receipt.
Library model/owner and application cases retain separate scopes.

The executable target is native Linux x86_64 CPU output produced by the GPU
compiler. Device-side GPU execution, broader targets, formal proofs,
automatic ownership and arbitrary failure schedules remain unclaimed. The
full standard and extended library roadmap remains open.
