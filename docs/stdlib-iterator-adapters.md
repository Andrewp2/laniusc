# Borrowed iterator adapters

`core::iter` provides `map`, `zip`, `enumerate` and `enumerate_from` for the
existing [`Iterator<T>` protocol](stdlib-iterators.md). They allocate nothing
and borrow their source cursor objects. Map also borrows a source-defined
mapper. [Collection and Text cursors](stdlib-collection-iterators.md) use the
same protocol.

| Factory | Bounds | Adapter item |
| --- | --- | --- |
| `map<I,M,T,U>(source:&I, mapper:&M) -> Map<I,M,T,U>` | `I:Iterator<T>`, `M:Mapper<T,U>` | `U` |
| `zip<A,B,T,U>(left:&A, right:&B) -> Zip<A,B,T,U>` | `A:Iterator<T>`, `B:Iterator<U>` | `core::pair::Pair<T,U>` |
| `enumerate<I,T>(source:&I) -> Enumerate<I,T>` | `I:Iterator<T>` | `core::pair::Pair<u64,T>` |
| `enumerate_from<I,T>(source:&I, first_index:u64) -> Enumerate<I,T>` | `I:Iterator<T>` | `core::pair::Pair<u64,T>` |

Each adapter provides `borrow()` for further adapters or generic consumers.
Pair fields are `first` and `second`. Construction makes no source or mapper
calls. Only the shared trait implements `next`; ordinary `.next()` calls work.

## Map and mutable callback context

`Mapper` is declared in `core::function`, shared with
[lazy Option/Result composition](stdlib-lazy-outcomes.md). The old
`core::iter::Mapper` path has no compatibility alias. Historical test receipts
below retain their original source scope.

```lani
pub trait Mapper<T, U> {
    pub fn apply(&self, value: T) -> U;
}
```

A mapper is an ordinary nominal type implementing this trait. Its fields can
contain borrowed application state, just as existing test and I/O callbacks
do. The `&self` receiver permits updating that state under Lanius's current
manual borrow rules. For example:

```lani
struct Totals { calls: u64 }
struct Widen { totals: &Totals }
pub impl core::function::Mapper<i32, i64> for Widen {
    pub fn apply(&self, value: i32) -> i64 {
        let totals: &Totals = self.totals;
        totals.calls += 1;
        return value as i64;
    }
}
```

While active, Map makes one source `next` call. A successful item causes exactly
one mapper call and returns `Some(mapped_value)`. An upstream `None` latches
completion without calling the mapper. Later calls query neither object.

`U` can be any supported value type, including arrays, records, Option and
Result. Mapping to `None` returns `Some(None)`; mapping to `Err(error)` returns
`Some(Err(error))`. Both are ordinary items and iteration continues. A consumer
chooses how to handle them. A callback trap occurs after the source item was
consumed and terminates the call without rollback.

Map imposes no purity or allocation rule on the callback. Its own work is
constant apart from one source call and at most one mapper call. Those calls
supply their own work and termination guarantees. Typed bounds retain the
exact input and output types; an implementation for another `T` or `U` cannot
satisfy the factory's requirements.

## Zip order and exhaustion

Zip pulls left first. If left returns `None`, Zip ends without querying right.
Otherwise it pulls right and returns the pair when both items are present.
Right `None` ends Zip after the left item has already been consumed. That
unpaired shallow value receives no implicit destruction.

Either `None` latches completion. Later calls query neither source, including
when those sources would record additional calls at EOF. Each active Zip call
makes at most one direct call to each source, in left/right order.

Both references can identify the same source cursor. With ordinary sequential
use, Zip then yields consecutive pairs: `(0,1)`, `(2,3)`, and so on. For an odd
source length, its last item is consumed as an unpaired left item when the
right pull observes EOF. Zip neither restarts nor copies either cursor.

## Enumeration and index overflow

`enumerate` labels the first item zero. `enumerate_from` labels it with the
supplied `first_index`; this constructor does not skip source items. A caller
can use it to continue numbering a separately selected report chunk.

The index is `u64`. `u64::MAX` is a valid final index. After yielding that index,
the adapter pulls again to distinguish exact EOF from an additional item:

| First index | Source items | Outcome |
| --- | --- | --- |
| `MAX` | none | `None` |
| `MAX` | `a` | `Some((MAX,a))`, then `None` |
| `MAX-1` | `a,b` | indexes `MAX-1`, `MAX`, then `None` |
| `MAX` | `a,b` | yield `a` at `MAX`; consume `b`, then panic before returning another item |

This policy never wraps or saturates an index and never reports overflow as
successful EOF. It uses a separate flag after `MAX` instead of forming
`MAX + 1`. The additional item must be consumed to distinguish it from EOF.
The panic does not unwind or destroy that item.

Each active call makes one direct upstream call. Ordinary EOF latches
completion and later calls make no upstream call. A Take wrapped around
Enumerate can stop before the overflow probe: after its successful quota is
used, Take returns `None` without querying Enumerate or its source.

## Borrowing, copies and cleanup

The source cursor object must outlive every adapter borrowing it. Map's mapper
object and any state borrowed by that mapper must also remain alive. Nested
adapters must stay alive until their downstream borrowers finish. Backing
storage retains its source API's lifetime and invalidation rules; the adapters
do not enforce them or permit otherwise invalid owner mutations.

Copying an adapter copies its local terminal/index state and keeps the same
references. Map copies share source progress and mapper context. Zip copies
share source progress while independently observing and latching EOF.
Enumerate copies share source progress but have independent index counters;
interleaving them can produce the same index for different items. Leaf cursor
copies retain their existing independent positions.

All inputs, outputs and Pair fields are shallow values. The adapters never
clone, move unique ownership, or call `Destroy`, including for a Zip left item
whose right partner is absent. `advance_up_to` also discards shallow output
values without destruction. Mapper/output cleanup authority remains the
application's responsibility.

In particular, if a mapper creates fresh sole owner handles, the application
must retain a cleanup authority for every created owner, including outputs
that a downstream Zip or bounded consumer may discard. A mapper can record
those owners in caller-managed context. Returning an owner handle alone does
not make the adapter a release authority. The ownership fixture instead maps
borrowed aliases of one independently retained String owner and destroys that
owner exactly once after all uses.

Sequential interleaving through shared references is permitted. Concurrent or
reentrant mutation of an adapter while its `next` is active is outside these
contracts. Preserve constructor invariants; public fields do not make forged
state or rewinding an exhausted adapter valid.

## Verification

The focused
[`stdlib_iterator_adapter_execution` driver](../tests/stdlib_iterator_adapter_execution.rs)
uses native x86_64 Linux programs compiled by the GPU compiler. Every emitted
ELF passes the unchanged common x86 jump checker before execution.

All four focused groups passed using compiler checkpoint
`3415fb76a46672a11d8049306bd911f450ead355` with these adapter source additions.

| Group | Accepted behavior | Gate time | Local log |
| --- | --- | --- | --- |
| Typed callbacks and ownership | Generic record/array/Option/Result outputs; mutable borrowed context; copies and aliases; Map/Zip/Enumerate/Take composition; exact EOF at `MAX`; no extra Take probe; exactly one source String allocation and its sole matching release after the unpaired-left alias case | 5.81 s | `contracts.log` |
| Independent models | All 1,008 sequence/call-order commands passed in one native process, including shared progress, copied terminal/index state, mapper calls and left/right event order | 5.23 s | `models.log` |
| Overflow witness | Exact stdout `a!b` followed by SIGILL: first item returned at `MAX`, extra source `Some` consumed, no second result returned | 3.72 s | `overflow.log` |
| Exact bounds | Wrong mapper input/output and wrong Zip item rejected with `LNC0008` at their own factory calls | 3.54 s | `bounds.log` |

These groups performed six compilation jobs: three produced strict-checked
ELFs and three produced the intended bound rejections. The three generated
programs each ran once, including the intentional overflow trap. The 1,008
model commands are inputs within one process, not separate native executions.
The Rust driver build took 1.25 s.

Logs and the shader manifest are local ignored artifacts under
`target/stdlib-work/iterator-adapter-admission/`; they are not checked in.
`pre-spv.sha256` contains 918 shader entries and has manifest digest
`ea02569e143cb458cc50aa68bdc280fc331e55c69c2bc80367ff15cf4f898d07`.
After all gates, `sha256sum --check --status` confirmed every listed shader was
unchanged. The accepted executable was
`target/stdlib-build/debug/deps/stdlib_iterator_adapter_execution-af4d98f4824f4a1e`.

Create the local log directory first when reproducing these commands:

```sh
mkdir -p target/stdlib-work/iterator-adapter-admission
```

The recorded build command, run from the repository root, was:

```sh
timeout --kill-after=2s 100s \
  flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s \
  env CARGO_TARGET_DIR=/home/andrew-peterson/code/laniusc/target/stdlib-build \
    CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  cargo test --test stdlib_iterator_adapter_execution --no-run \
  > target/stdlib-work/iterator-adapter-admission/build.log 2>&1
```

Each exact test used the following bounded launcher, with no additional
test-thread flag. Define the function, then run each invocation separately;
each invocation has its own 100 s outer limit:

```sh
adapter_test_binary=target/stdlib-build/debug/deps/stdlib_iterator_adapter_execution-af4d98f4824f4a1e
run_adapter_gate() {
  timeout --kill-after=2s 100s \
    flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
    timeout --kill-after=2s 60s \
    env RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
    "$adapter_test_binary" --exact "$1" --nocapture \
    > "target/stdlib-work/iterator-adapter-admission/$2.log" 2>&1
}
run_adapter_gate typed_callbacks_composition_and_shallow_owner_contracts_execute contracts
run_adapter_gate adapter_sequences_and_exact_pull_order_match_independent_models models
run_adapter_gate enumerate_consumes_the_unindexable_item_before_checked_panic overflow
run_adapter_gate mapper_and_zip_bounds_require_exact_input_and_output_items bounds
```

The separate [range-dot application](stdlib-range-dot.md) reuses Zip, Take, Map
and Enumerate to compute a checked dot product from two inclusive i32 ranges.
Its acceptance used one strict-checked ELF and 67 native cases; those runs are
separate from the adapter groups above.

This evidence concerns native CPU programs. User-program GPU execution and
other targets remain separate. `for` retains its existing compiler lowering.

The [Rust Iterator documentation](https://doc.rust-lang.org/std/iter/trait.Iterator.html)
provides a semantic reference for the familiar adapter names. The explicit
contracts above define Lanius's borrowed mapper objects, fused terminal state
and checked `u64` enumeration policy.
