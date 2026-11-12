# Reactive graph kernel

`ext::reactive_graph` is the first executable foundation for the
[reactive native UI framework](extended-ui-plan.md). It tracks dependencies,
settles memo/effect work and owns graph metadata. It is **not yet** a public
`Signal<T>`/`Memo<T>` value layer, widget toolkit, renderer or closure runtime.
User values, callback captures and their destruction are not stored here.

The verified execution profile is native Linux x86_64, compiled by the GPU
compiler. The resulting program executes on the CPU. This module uses the
allocator but no window, Vulkan, Rust runtime, JSON transport or native UI
library. User-program GPU execution and other targets have not been tested.

## Graph and evaluation

`create(node_capacity, edge_capacity)` allocates one graph with a root scope.
`create_node(scope, kind)` adds a scope, source, memo or effect. Sources start
clean, memos start unevaluated, and effects start queued. Only scopes own child
nodes; the dependency graph is independent of this ownership tree.

A driver implements `Evaluate::evaluate(id, graph) -> Result<bool, Error>`.
`read(id, driver)` brings a source/memo current, records the read for the active
observer and returns its version. The driver reads its own typed value storage
after this succeeds. `read_untracked` refreshes without subscribing the current
observer; nested memo computations still track their own dependencies.
A successful memo callback returns whether its output changed; this controls its
version. An effect's Boolean is ignored. The driver must commit its value only
after its fallible reads/computation succeed. The kernel cannot roll back
arbitrary external side effects.

This driver interface is an internal execution boundary. Tests use a small
interpreter to exercise many graph shapes; applications should not have to
maintain a callback-ID switch. A higher layer still needs typed value ownership
and callback integration. Lanius now provides owned `move` closures and
`alloc::callback` storage with uniform signatures. Those supply deferred
invocation; the UI layer still needs scope registration, typed value cleanup
and exactly-once callback destruction. See the framework plan.

`publish(source, changed)` announces a write. `changed=false` does no graph
work. Equality is the value layer's explicit decision, not a hidden comparison
of arbitrary types. That layer must keep value commit and publication together:
first admit publication, then commit the infallible value assignment before any
read/flush. On an error, leave the value unchanged. A future fallible setter
must prepare its replacement before publication. Do not mutate the graph or
value storage concurrently.

Several publications can precede `flush(driver, budget)`. Invalidation marks
reachable observers for checking and queues each effect once. Refresh pulls
memos current before their outputs are consumed. An equal memo output stops
its consumer from executing, although checking the affected graph still costs
work. Reads outside a flush also refresh memos (read-your-writes).

Successful evaluation replaces the dependency set with the reads from that
run. Failed evaluation removes newly added edges, retains previous dependencies
and leaves the observer dirty. A later flush retries it. Old and new edges can
coexist during evaluation, so reserve capacity for their union, not just the
larger final set. An error never silently drops a subscription.

The first error stops a flush and leaves its effect queued. Earlier successfully
completed effects remain committed. `flush` returns the count of retired queue
entries, including effects suppressed by memo equality; use `Stats.evaluations`
for actual callback invocations. Budget exhaustion is retryable. Budgets count
callbacks, including nested memos, not elapsed time or total edge traversal.

## Ownership and failures

`dispose(id)` removes one node or an entire scope subtree, including queued work
and dependency edges. It returns the removed node count. Dependents outside the
subtree are invalidated: reading a disposed source reports `Stale`, rather than
quietly keeping its last value. The root is disposed only by `close()`.

Slot generations prevent an old handle from becoming valid when a slot is
reused **inside a live graph**. `Id` values are borrowed identities, not owners.
A `Graph` is one manually managed owner: do not copy it, forge handles or use
borrows after closing it. `close()` releases graph metadata and becomes
idempotent on that same owner. Retire all its IDs before creating/reusing another
graph; the storage address is not a globally unique graph identifier across
allocator reuse. These are explicit lifetime obligations until a stronger
owner/type contract exists. In particular, this kernel does not claim arbitrary
use-after-close safety.

The higher value/capture layer must coordinate typed destruction with graph
scope disposal; `dispose` and `close` do not run application destructors.
Public structure mutation, disposal, close and recursive flush are rejected
while evaluating. Reactive writes from a callback are rejected too. Reads and
nested memo evaluation are supported. Event handlers are the intended mutation
boundary; feedback effects need a separate scheduling contract.

| Error | Meaning |
| --- | --- |
| `Closed` | The same owner has already been closed. |
| `Stale`, `DifferentGraph` | Invalid/reused slot or an ID from another live graph. |
| `WrongKind` | Wrong operation for a scope/source/memo/effect, including reading an effect. |
| `Busy`, `WriteDuringEvaluation` | Structural/reentrant operation or publication during evaluation. |
| `Capacity` | Invalid constructor limits, no node slot or no dependency edge slot. |
| `AllocationFailed` | Graph storage allocation failed; partial storage is released. |
| `Cycle`, `Depth` | Recursive dependency or the explicit nesting bound. |
| `Budget` | Callback evaluation allowance exhausted, or a nonpositive flush budget. |
| `Exhausted` | An observer epoch or value version cannot be incremented without wrapping. |
| `Evaluation(code)` | Driver-supplied computation failure. |

Node capacity is 2..65,536 including the root; edge capacity is 1..1,048,576.
Scope creation admits at most 255 ancestors including the root. At most 256
memo/effect refresh frames may be active. A slot at its maximum generation is
permanently retired. Graph storage and the invalidation work stack are reserved
at creation; the kernel performs no allocation while settling. Drivers may
have their own allocation/failure behavior. These bounds are a first kernel
profile, not proposed permanent limits for the entire UI framework.

`Stats` separates callback evaluations, nodes newly invalidated, dependency
version checks, tracked read calls, propagation edge visits and tracking edge
search visits. Counters are diagnostic `u64`s and can wrap. Invalidation walks
affected edges; the queue does not scan all nodes. Tracking deduplicates reads
by searching the observer's dependency list, so high fan-in has a measurable
linear search cost per read. No constant-time claim applies to arbitrary graph
shapes. Creation, disposal, layout and rendering costs are separate.

## Executable evidence

`tests/extended_reactive_execution.rs` compiles and executes
`tests/fixtures/extended/reactive/graph.lani`. It checks:

- Batched diamonds, repeated reads, lazy reads and independent effects.
- Memo equality, conditional dependency replacement and untracked reads.
- Failed callbacks, tentative-edge rollback, capacity errors and retry.
- Scope removal, queued-effect removal, external consumers of disposed sources,
  stale generations, wrong graph/kind and rejected reentrant mutations.
- Cycles, callback budgets and depth errors, followed by successful recovery.
- A separate full topological evaluator versus incremental outputs for 1,000
  deterministic batches on a graph with 16 sources, 32 memos and 8 effects.
- 100, 1,000 and 10,000 independent source/effect pairs: a sparse write executes
  one effect, invalidates one node, checks one dependency, visits one propagation
  edge and searches one tracking edge. An equal write executes none. Each size
  also exercises 1,000 rounds of slot/queue reuse.

Run the narrow gate (each command stays below two minutes):

```sh
LANIUS_GPU_REQUIRE_HARDWARE=1 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=85000 \
  timeout --kill-after=2s 100s flock -w 90 target/stdlib-work/library-gpu.lock \
  cargo test --release --test extended extended_reactive_execution:: -- --test-threads=1
```

The sparse counts are scheduling assertions, not UI frame times or a comparison
with GPUI/zgui. There is no native widget application yet. Allocation failure
injection, typed capture destruction, signal/value ownership and formal
verification remain separate acceptance gates.
