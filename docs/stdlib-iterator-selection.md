# Iterator selection, searches and folds

`core::iter` supplies borrowed selection adapters and consuming operations over
the shared `Iterator<T>` protocol. Their implementation is Lanius, with no
allocation or host service in the iterator machinery. Source and callback
implementations can perform their own effects.

## Selection adapters

| Factory | Callback bound | Item |
| --- | --- | --- |
| `filter<I,P,T>(source:&I,predicate:&P) -> Filter<I,P,T>` | `P:Mapper<T,bool>` | original `T` |
| `filter_map<I,M,T,U>(source:&I,mapper:&M) -> FilterMap<I,M,T,U>` | `M:Mapper<T,Option<U>>` | selected `U` |
| `skip<I,T>(source:&I,count:u64) -> Skip<I,T>` | none | `T` after the skipped prefix |
| `take_while<I,P,T>(source:&I,predicate:&P) -> TakeWhile<I,P,T>` | `P:Mapper<T,bool>` | accepted prefix of `T` |
| `skip_while<I,P,T>(source:&I,predicate:&P) -> SkipWhile<I,P,T>` | `P:Mapper<T,bool>` | `T` starting with the first false item |

Every factory also requires `I:Iterator<T>`. Each returned type provides
`borrow()` for downstream adapters and consumers. Import `core::iter` for the
shared `next` implementations. Construction makes no source or callback calls.
Selection reuses `core::function::Mapper<T,U>`; no separate predicate
trait or closure runtime is required.

Filter tests each successful source item once and returns the first accepted
item. FilterMap similarly calls its mapper once per successful source item,
skipping outer `None` results. Mapping to `Some(None)` yields an ordinary
`Option` item whose value is `None`. Mapping to `Some(Err(error))` yields an
ordinary Result item; it does not end iteration or implicitly propagate errors.

Skip lazily consumes exactly `count` successful source items before yielding
the next one. Zero skips nothing. A finite source shorter than the requested
prefix ends at its first `None`. `u64::MAX` is accepted without narrowing,
adding one, wrapping or enumerating beyond a finite source's exhaustion.

TakeWhile consumes and tests its first false item, then permanently returns
`None`. That boundary item is not returned to the caller. SkipWhile yields its
first false item and then forwards the rest without further predicate calls.
Both stop testing when the source ends.

All five adapters latch source exhaustion. Later calls make no source or
callback calls. Copying an adapter copies its local phase, budget and terminal
state while retaining references to the same source and callback. Interleaved
copies therefore share source progress but can independently observe EOF,
skip prefixes, or reach predicate boundaries.

One call can scan many source items. A rejecting infinite Filter/FilterMap or
an infinite matching SkipWhile prefix need not return. Skip can consume up to
its remaining u64 budget before returning an item. Putting Take *before*
selection bounds direct source pulls; putting Take afterward limits selected
outputs. Bounded downstream consumption does not establish a work limit for
an arbitrary upstream implementation or callback.

## Searches and boolean consumers

| Function | Callback bound | Result |
| --- | --- | --- |
| `find<I,P,T>(source:&I,predicate:&P)` | `P:Mapper<T,bool>` | `Option<T>` |
| `find_map<I,M,T,U>(source:&I,mapper:&M)` | `M:Mapper<T,Option<U>>` | `Option<U>` |
| `any<I,P,T>(source:&I,predicate:&P)` | `P:Mapper<T,bool>` | `bool` |
| `all<I,P,T>(source:&I,predicate:&P)` | `P:Mapper<T,bool>` | `bool` |

These functions also require `I:Iterator<T>`. Find consumes and returns the
first matching item. FindMap skips mapper `None` values and returns the first
`Some`, preserving any nested Option/Result payload. Any returns at the first
true result; All returns at the first false result. The decisive item has been
consumed; no extra source or callback probe occurs before returning. If no
decision is reached earlier, the operation consumes through source EOF.
Empty-source identities are `None`, `None`, `false` and `true`, respectively.

Consumers borrow their source object. After a successful search or a boolean
short circuit, a direct source pull resumes at the following item. They do not
rewind, independently fuse, or copy the source. Calling a consumer again is a
new operation over the remaining source state.

## Accumulation and typed errors

```lanius
pub trait Folder<A,T> {
    pub fn apply(&self,accumulator:A,value:T) -> A;
}
pub trait TryFolder<A,T,E> {
    pub fn try_apply(&self,accumulator:A,value:T) -> core::result::Result<A,E>;
}
```

`fold<I,F,T,A>(source:&I,initial:A,folder:&F) -> A` requires
`I:Iterator<T>` and `F:Folder<A,T>`. It folds left in source order, always
passing the accumulator first and current item second. The empty result is
`initial`. Arithmetic and overflow policy belong to the callback.

`try_fold<I,F,T,A,E>(source:&I,initial:A,folder:&F) -> Result<A,E>` instead
requires `F:TryFolder<A,T,E>`. Each `Ok` replaces the accumulator. The first
`Err` is returned intact, after consuming that item and without another source
or callback call. The next direct source pull resumes at the following item.
Source EOF returns `Ok(accumulator)`, including `Ok(initial)` for an empty
source. There is no rollback. The error need not include the previous
accumulator; callers decide which partial state to retain in `E` or context.

Items, accumulators and errors can be different supported types, including
records, arrays and nested Option/Result values. Exact generic callback bounds
apply to every argument and result type.

## Borrowing, effects and cleanup

Keep source, callback and nested adapter objects alive while borrowed. Their
backing storage and any referenced callback context must also remain valid.
The existing [iterator contract](stdlib-iterators.md) and source-specific
invalidation rules apply. Sequential interleaving is supported; concurrent or
reentrant mutation during an active call is outside these contracts. Public
state fields do not permit forged invariants or restarting a fused adapter.

Callbacks receive shallow values, including for boolean tests. Nothing here
clones an owner, transfers unique release authority, or calls `Destroy`.
Rejected and skipped items, replaced accumulators, and a failed fold's old
accumulator receive no implicit cleanup. Retain explicit cleanup authority for
every resource, including fresh owners a callback creates but omits from its
result. A callback trap occurs after source consumption, without rollback or
unwinding.

Naming and ordinary selection/fold behavior follow the familiar
[Iterator interfaces](https://doc.rust-lang.org/std/iter/trait.Iterator.html).
Lanius uses nominal callback traits, explicit generic item parameters and its
manual shallow ownership model. The contracts above define its behavior.

## Native verification

The focused [selection driver](../tests/stdlib_iterator_selection_execution.rs)
emits two strict-checked native ELFs. Its typed contract covers compound
records/arrays, full-width values, nested Option/Result outputs, packed and
strided byte views, zero-sized items, lazy construction and borrowed mutable
context. One separately retained String owner passes through yielded and
discarded items; its exact trace contains one allocation and one matching
release. The model uses standard host iterator selection over shared traced
sources, with a separate Fuse for each copied adapter. It compares complete
outputs and source/callback state and event order across 960 commands,
including empty/all-reject prefixes, boundaries, copied phases and MAX skips.
Both gates passed with the final compiler changes in 7.69 seconds.

The [consumer driver](../tests/stdlib_iterator_consumer_execution.rs) emits two
more strict-checked ELFs. It verifies distinct compound item, accumulator and
error types, nested Option/Result payloads, empty identities, exact short
circuits, noncommutative folds and one retained String owner's sole release.
Its 714 independent model commands compare decisions, typed errors, prior
accumulators, callback/source counts, source resumption, remaining folds and
complete effect traces. Both gates passed with the final compiler changes in
9.30 seconds.

These are four native processes; the command counts describe inputs within
the two model processes. Test support Rust supplies orchestration and oracles;
the APIs and callbacks under test execute as Lanius.

The [exact-bound driver](../tests/stdlib_iterator_selection_bounds.rs) also
passes four intended `LNC0008` rejections in 4.23 seconds. The cases require a
boolean filter result, the requested optional mapped item, the exact fold
accumulator and the exact fallible-fold error type. Each diagnostic must name
its own factory call; an unrelated callback-body error cannot satisfy it.

Admission also exposed and repaired a
[generic call assignment context failure](compiler-iterator-assignment-context.md).
The unchanged positive reducer and an exact incompatible-destination rejection
pass together in 8.60 seconds. The full selection model was retained unchanged
through that repair. Eight additional direct/unconditional/branch observations
also pass with exact Option predicates and call counts. The compiler guide records the initial failures, type
authority checks, neighboring regressions and performance scope.

The [column-sum application](stdlib-column-sum.md) uses the real Split, Filter,
Map<Result> and TryFolder implementations over bounded stdin. Its guide records
the normal, invalid-input, allocation and I/O failure gates.

Runtime logs are local ignored artifacts under
`target/stdlib-work/iterator-selection-admission/`: `selection-final.log` and
`consumers-final.log`. The final drivers were rebuilt against the current
compiler; the source checkpoint is `28eee336` plus the two compiler repairs
documented above and these library additions. Rebuild before directly invoking
a cached executable. Each gate uses an outer 100-second timeout, the shared
GPU lock with a 35-second wait, a 60-second inner timeout, and
`LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000`. The native child processes also have
their own bounded timeouts.

For example, after the compiler dependencies are built, run the two native
selection gates from the repository root:

```sh
mkdir -p target/stdlib-work
timeout --kill-after=2s 100s flock -E 75 -w 35 \
  target/stdlib-work/library-gpu.lock timeout --kill-after=2s 60s \
  env CARGO_TARGET_DIR=target/stdlib-build CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
  cargo test --test stdlib_iterator_selection_execution -- \
  --test-threads=1 --nocapture
```

Use the same command with `--test stdlib_iterator_consumer_execution` for the
two consumer gates, or `--test stdlib_iterator_selection_bounds` for the four
source-local bound checks. The application and compiler guides record their
separate invocations and limits.

Supported execution evidence is **x86_64 Linux native CPU output from the GPU
compiler**. These checks establish no user-program GPU execution or other
platform support. Library machinery allocates nothing; source and callback
effects remain governed by their own contracts. Automatic ownership and
language-level `for` integration remain separate work.
