# Iterator reduction and bounded-fold contract

This increment fills the main-library reduction/reverse-fold gap using the
existing [canonical iterator and callback traits](stdlib-iterators.md). It also
adds bounded folds for resumable processing. It does not change cursor layouts,
existing traversal methods, existing fold bodies, compiler IR, ABI or proofs.
Runtime evidence and remaining target/compiler boundaries are recorded in the
[fold guide](stdlib-iterator-folds.md); the full library roadmap remains open.

## Public surface in `core::iter`

```lani
pub struct FoldProgress<A> { accumulator:A, folded:u64, exhausted:bool }
pub struct FoldFailure<E> { folded:u64, error:E }
```

Use the existing `Folder<A,T>` and `TryFolder<A,T,E>`, whose callbacks always
receive accumulator first, item second. All functions borrow source and folder.
Initial accumulators and returned values follow existing shallow value/cleanup
authority rules.

| API | Result and required bounds |
| --- | --- |
| `reduce<I,F,T>(source:&I,folder:&F)` | `Option<T>`; `I:Iterator<T>, F:Folder<T,T>` |
| `try_reduce<I,F,T,E>(source:&I,folder:&F)` | `Result<Option<T>,E>`; `I:Iterator<T>, F:TryFolder<T,T,E>` |
| `rfold<I,F,T,A>(source:&I,initial:A,folder:&F)` | `A`; `I:Iterator<T>, I:DoubleEndedIterator<T>, F:Folder<A,T>` |
| `try_rfold<I,F,T,A,E>(source:&I,initial:A,folder:&F)` | `Result<A,E>`; both source bounds and `F:TryFolder<A,T,E>` |
| `fold_up_to<I,F,T,A>(source:&I,initial:A,folder:&F,limit:u64)` | `FoldProgress<A>`; `I:Iterator<T>, F:Folder<A,T>` |
| `try_fold_up_to<I,F,T,A,E>(source:&I,initial:A,folder:&F,limit:u64)` | `Result<FoldProgress<A>,FoldFailure<E>>`; `I:Iterator<T>, F:TryFolder<A,T,E>` |
| `rfold_up_to<I,F,T,A>(source:&I,initial:A,folder:&F,limit:u64)` | `FoldProgress<A>`; both source bounds and `F:Folder<A,T>` |
| `try_rfold_up_to<I,F,T,A,E>(source:&I,initial:A,folder:&F,limit:u64)` | `Result<FoldProgress<A>,FoldFailure<E>>`; both source bounds and `F:TryFolder<A,T,E>` |

Append these definitions to the module so existing declaration source locations
remain stable. The existing Folder comment can be generalized from left folds
to folds; there is no new callback protocol or compatibility alias.

## Reduction and direction

Reduction first pulls one item from the front. Empty yields None (or Ok(None))
without invoking the folder. A singleton returns that item without a callback.
For a longer sequence, the first item is the accumulator and every later item
is folded in front-to-back order. No synthetic identity/default T is required.
Fallible reduction returns Err immediately when the callback does.

Reverse folds call only `next_back`, consuming the shared remaining sequence
from back to front. Callback argument order stays `(accumulator,item)`: for
`[a,b,c]`, the result is `f(f(f(initial,c),b),a)`. The operation need not be
associative or commutative. Both source bounds name the same T explicitly;
neither exact-size nor clone/destruction traits are required. Existing front
and back consumers can resume the remaining middle sequence between calls.

The unbounded reduction and reverse-fold meanings follow Rust's
[reduce/try_reduce](https://doc.rust-lang.org/std/iter/trait.Iterator.html#method.reduce)
and [rfold/try_rfold](https://doc.rust-lang.org/std/iter/trait.DoubleEndedIterator.html#method.rfold)
principles. Lanius uses borrowed source-defined callback traits and explicit
Result errors, rather than closures, implicit moves or generic Try residuals.
The bounded progress/error envelopes below are Lanius-specific contracts.

## Quotas, progress and error effects

Every bounded call makes at most limit direct pulls from its selected end, with
at most one callback for each Some. A zero quota does not query source metadata,
pull, call the folder, allocate, retire anything or probe EOF; it returns the
unchanged initial accumulator, folded=0, exhausted=false.

FoldProgress.folded counts successful callback applications in this call only.
The returned accumulator includes those applications. exhausted=true means an
actual None was observed. Reaching the quota stops immediately with
exhausted=false, including when the last allowed Some happened to be the final
item. There is no extra EOF probe, peek or remaining-count query at that point.
Exact-size metadata supplies no exception to this observable behavior.

On callback Err, stop immediately without another source pull or callback.
FoldFailure.folded counts earlier Ok applications, excluding the failing one.
The source has already consumed the failing item. The attempted callback count
is folded+1 and never exceeds limit; this addition is representable. The error
is transferred exactly as supplied by the callback, without rollback. Resume
the source from its next still-unconsumed value after handling the error.

Counters are u64. Increment only while folded<limit; limit=u64::MAX cannot wrap
the progress counter. Source/callback cost is not bounded by these quotas: a
single pull or callback can do arbitrary work. Unbounded variants require the
caller to provide a terminating sequence or accept nontermination.

## Ownership and generality

The iterator layer never allocates, clones, invokes Destroy or silently retires
the source, callback, item, accumulator or error. A callback receives the current
accumulator and item under the existing cleanup-transfer convention. It must
release, retain or return every owned resource it consumes, on both Ok and Err.
An E may carry the actual updated accumulator and rejected/current item for
recovery. The library must not use older shallow aliases after an error.

The caller keeps borrowed backing and folder context live, avoids upstream
mutation/reentrancy through aliases, and cleans up returned accumulators/errors
and the source's remaining owner. A zero-progress result can still carry an
owned accumulator; it is not permission to duplicate cleanup authority. No new
runtime resource-checking framework is introduced. Scalars, compound values,
nested generic accumulators/errors and explicit owning-cursor recovery need
actual execution tests; unsupported compiler compositions get a minimal
reproduction and dependency report, not type-specific library specialization.

## Executable acceptance

- Normal/edge contracts: empty/singleton/multiple reduction, noncommutative
  reverse order, mixed-end resumption, zero/exact/over/Max quota, no hidden EOF
  or metadata queries, callback ordering and immediate error effects.
- Independent finite-sequence/state models across source kinds, callback
  policies, quotas, chunk resumptions, selected adapters and both directions.
  Observe source position, exact progress, errors and callback trace, not just
  final sums.
- Explicit generic bounds rejection for missing/wrong-item Iterator,
  DoubleEndedIterator and callback traits, with actual runtime controls.
- Owned accumulator/error/cursor tests: callback allocation failure recovers
  the actual updated owner and current item, leaves the correct source suffix
  or prefix, and releases all selected actual mappings. Pure callbacks must
  trigger no allocation services. Finite traces are not lifetime/leak proofs.
- A real bounded byte-summary program composes byte views, both bounded
  fallible directions, checked counters, CLI/CSV formatting and native I/O.
  Output is staged and failures are explicit.

Root owns serialized compiler/native runs, each under two minutes. Use focused
new gates and selected current fold/reverse regressions because the shared
iterator module changes. No unrelated broad GPU/performance reruns. Current
executable target scope is native Linux x86_64 CPU output from the GPU compiler.
