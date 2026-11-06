# Weighted directed graphs and shortest paths

`ext::weighted_graph` stores directed multigraphs with exact `i64` edge costs
and computes owned single-source shortest-path results. It retains parallel
edges, exact duplicates, self-loops and zero-cost edges. The module is separate
from the [unweighted simple graph](extended-graph.md) and
[numeric sparse matrix](extended-sparse.md) APIs.

The [Lanius implementation](../extended/ext/weighted_graph.lani) passes four
focused execution gates on native Linux x86_64 with allocation support, using
code emitted by the GPU compiler. These cover direct contracts, independent
small-graph results and allocation-failure recovery; the receipts and limits
appear below. GPU-device execution, other targets and formal verification
remain unverified. The [route-cost application](extended-route-cost.md) has
separate acceptance covering 148 native cases.

## Public surface

All names below belong to `ext::weighted_graph`. Generic `View<T>` denotes
`core::slice::View<T>`; plain `View` is weighted adjacency. `Vec<T>` denotes
`alloc::vec::Vec<T>`, and `Option`/`Result` are the core generic types.

```text
Edge { source:i32, target:i32, cost:i64 }
Arc { target:i32, cost:i64 }
View { nodes:i32, offsets:View<i32>, arcs:View<Arc> }
Limits { max_nodes:i32, max_edges:i32, max_work:u64 }
ErrorKind = InvalidLimits | Bounds | NodeLimit | EdgeLimit | WorkLimit
          | Offset | Source | Target | Order | NegativeEdge | Overflow
          | NegativeCycle | AllocationFailed | Closed
Error { kind:ErrorKind, node:i32, edge:i32 }

default_limits() -> Limits
validate(View, Limits) -> Result<i32,Error>
view(nodes:i32, offsets:View<i32>, arcs:View<Arc>, Limits) -> Result<View,Error>
from_edges(nodes:i32, edges:View<Edge>, Limits) -> Result<Graph,Error>
from_view(View, Limits) -> Result<Graph,Error>
neighbors(View, node:i32, Limits) -> Result<View<Arc>,Error>
dijkstra(View, source:i32, Limits) -> Result<Paths,Error>
bellman_ford(View, source:i32, Limits) -> Result<Paths,Error>

Graph.borrow() -> &Graph
Graph.is_open() -> bool
Graph.node_count() -> i32
Graph.edge_count() -> i32
Graph.view() -> Option<View>
Graph.destroy() -> bool

Paths.borrow() -> &Paths
Paths.is_open() -> bool
Paths.node_count() -> i32
Paths.source() -> Option<i32>
Paths.distance(node:i32) -> Result<Option<i64>,Error>
Paths.predecessor(node:i32) -> Result<Option<Edge>,Error>
Paths.path_to(node:i32, Limits) -> Result<Option<Vec<Edge>>,Error>
Paths.destroy() -> bool
```

`validate` returns the stored arc count. `Edge` implements `Ord<Edge>` by
`(source,target,cost)`. `from_edges` validates endpoints, copies the input and
sorts the copy in that order. It never changes caller storage or removes
edges. `from_view` makes an independent copy after validation.

Node IDs are dense integers from zero through `nodes-1`. Offsets have exactly
`nodes+1` entries, begin at zero, never decrease and end at `arcs.length`.
Each row's arcs have in-range targets in nondecreasing `(target,cost)` order.
Equal pairs are valid. Empty adjacency is `nodes=0`, `offsets=[0]`, `arcs=[]`;
an empty owned graph still allocates the offset entry. No source is valid for
an empty graph.

## Exact costs and path choices

Dijkstra rejects the first negative arc in canonical order anywhere in the
graph, including a disconnected component. For nonnegative graphs it orders
queue entries by `(distance,node)`, keeps lazy duplicate entries and skips
stale distances. A current entry examines every outgoing arc, including arcs
to already settled nodes.

Bellman–Ford visits rows and arcs in canonical order and updates distances
in place. It runs at most `nodes-1` complete relaxation passes, stops after a
pass without changes, then makes a final scan. The first reachable arc that
can still improve a distance reports `NegativeCycle`. Every source-reachable
negative cycle is an error; disconnected negative cycles are ignored. There
is no destination-specific exception for a cycle that cannot reach a
particular queried node.

Both algorithms replace predecessors only for a strictly smaller distance.
Equal candidates keep the first predecessor. Raw-edge permutations therefore
produce the same canonical graph and the same results for a given algorithm.
Dijkstra and Bellman–Ford may choose different equal-cost paths; neither
promises a lexicographically minimal path.

Reachability is stored separately from distance. Every `i64` value, including
`i64::MIN` and `i64::MAX`, can be a successful distance. Every examined arc
whose source is reached uses checked signed addition **before** testing
whether the candidate improves its target. An unrepresentable sum reports
`Overflow`, even when that candidate could not improve the target. Values
never wrap or saturate. Bellman–Ford can encounter `Overflow` before it can
diagnose a negative cycle. During the final scan, the first encountered
overflow or still-improving arc wins; an unexamined later overflow does not
replace an earlier `NegativeCycle`.

The source has distance `Some(0)`, no predecessor and `Some(empty Vec)` as its
path. An unreachable node returns `None` for all three queries. Reachable
non-source paths contain full `Edge` values in source-to-destination order;
parallel-edge costs remain visible. `predecessor` returns the last such edge.
Errors return no partial `Paths` or partial materialized path.

## Ownership and lifetime

A `Graph` owns its offsets and arcs. Its views and neighbor rows borrow that
storage and expire before destruction. A `Paths` result owns its labels and
predecessor costs independently of the input graph. A materialized path owns
its `Vec<Edge>` independently of both owners. Destroying the graph does not
invalidate `Paths`; destroying `Paths` does not invalidate an already
materialized path. Callers destroy each successful path vector once.

Each active `Graph` or `Paths` has one cleanup authority. Copies alias that
authority: copying an owner is not a clone or move, and aliases must not be
used or destroyed after cleanup. The first `destroy` on the authority returns
true, repeats return false, and counts become zero. A closed graph's `view`
and a closed result's `source` return `None`. Path queries return `Closed`
before checking the requested node.

Public owner fields describe implementation state, not permission to forge,
mutate or independently destroy internal vectors. Borrowed input must have
live, aligned, initialized backing of the declared physical extent. The
library checks logical view metadata; it cannot validate arbitrary pointers
or backing lengths. Do not mutate input through an alias during any operation.
There is no implicit drop, borrow checker or allocation arena in this module.

## Limits and diagnostic precedence

Defaults are 1,048,576 nodes, 1,048,576 edges and 100,000,000 work units.
Negative node or edge limits report `InvalidLimits`; zero work is valid but
cannot admit even empty-graph validation.

Capacity checks use the target's actual `core::mem::size_of<T>()`. Let
`cap(T)=floor(i32::MAX/size_of<T>())` for these nonempty types:

| Operation | Additional hard capacity |
| --- | --- |
| Every graph operation | `nodes+1 <= cap(i32)`, `arcs.length <= cap(Arc)` |
| `from_edges` | Raw edge count `<= cap(Edge)` |
| Either shortest-path algorithm | `nodes <= cap(Label)` |
| Dijkstra | `arcs.length+1 <= cap(QueueItem)` |
| `path_to` | Actual output edge count `<= cap(Edge)` |

Private `Label` has fields `reached:bool`, `distance:i64`, `parent:i32`,
`parent_cost:i64`; `QueueItem` has `cost:i64`, `node:i32`. These capacities
must not be inferred from C layouts. On the current native storage model,
`i32`, `Arc`, `Edge`, `Label` and `QueueItem` occupy 4, 16, 24, 32 and 16 bytes.
Node-capacity failures report `NodeLimit`; arc, staging, queue and output-path
capacity failures report `EdgeLimit`.

`validate` checks limits, node/view metadata, configured and hard capacities,
exact offset length, then work admission, before reading backing storage.
A negative node count or invalid logical view metadata reports `Bounds`.
Offset-length mismatch also reports `Bounds`. It scans every offset before
any arc, then visits rows and arcs in order. A bad target reports `Target`
before any ordering error at the same arc. `view` uses this validation;
`neighbors` validates the whole graph before requested-node bounds.

`from_view` admits its full copy budget before reading offsets or arcs.
`from_edges` checks limits and metadata, configured and graph capacities,
raw `Edge` staging capacity, then its full budget. It checks each raw source
before its target, in original input order, before allocation or sorting.
All raw edges count toward limits, including exact duplicates.

Algorithms complete validation first, then check source bounds, workspace
capacities and the full algorithm budget. Dijkstra's global negative-edge
scan follows admission and precedes allocation. Each traversal error releases
its private result and workspace. All recoverable errors preserve caller
input. Allocation failure reports `AllocationFailed`.

`path_to` uses this order:

1. Closed result, then requested-node bounds.
2. Valid limits, then `Paths.node_count() <= max_nodes`.
3. Full path work admission, before reading any label or parent.
4. Reachability; unreachable nodes return `None` without allocation.
5. Follow the parent chain, enforcing the actual edge count against
   `max_edges` and `cap(Edge)` before allocating output.
6. Allocate and fill the forward path.

Thus `max_nodes` bounds the result's whole node population; `max_edges` bounds
only the requested output path, not the graph's original edge count. A source
path succeeds with `max_edges=0` when node/work admission succeeds. A reachable
non-source path with that limit reports `EdgeLimit`. Allocation failure leaves
the result usable for later queries. Internal parent-chain assertions guard
against forged or externally corrupted owners; valid algorithm results do
not trigger them.

Error locations are relative to the selected input view:

| Error | `node`, `edge` payload |
| --- | --- |
| Raw-edge `Source` / `Target` | Offending endpoint ID, original raw edge index |
| Arc `Target` / `Order` | Source row, canonical arc index |
| `NegativeEdge` / `Overflow` / `NegativeCycle` | Source row, canonical arc index |
| Bad first offset | `0` for a nonempty graph, otherwise `-1`; edge `-1` |
| Bad subsequent offset | Preceding row, edge `-1` |
| Final offset mismatch | Last row or `-1` for an empty graph; edge `-1` |
| Requested-node `Bounds` | Requested node, edge `-1` |
| Other metadata, limit, work, allocation or closed errors | `-1`, `-1` |

## Work admission and memory

Let `n=nodes`, `m=arcs.length` (raw edge count for `from_edges`),
`V=n+1+m` and `h(x)=ceil(log2(max(x,1)))`. A call succeeds in admission when
its estimate is at most `max_work`:

| Operation | Required work |
| --- | --- |
| `validate`, `view`, `neighbors` | `V` |
| `from_view` | `2V` |
| `from_edges` | `n+1+6m+4m(1+h(m))` |
| Dijkstra | `V+4n+3m+4(m+1)(1+h(m+1))` |
| Bellman–Ford | `V+3n+n(n+m)` |
| `path_to` | `3n+1`, using the result's node count |

These are conservative weighted admission estimates, not instruction counts,
elapsed-time bounds or a shared consumable budget. Bellman–Ford admits the
worst case even when early convergence would use less work; `path_to` admits
the full population bound even for an empty or absent path. Arithmetic widens
nonnegative counts to `u64` before products. Even the full `i32` count bounds
keep these formulas within `u64`; capacity admission narrows them further.
This increment has no cancellation callback or resumable search API.

Graph storage uses `O(n+m)` memory. Construction from raw edges temporarily
adds an `Edge` vector. Both algorithms own `O(n)` labels; Dijkstra additionally
reserves `m+1` queue entries. A node settles once under nonnegative costs, so
each arc can cause at most one queue push; the initial source accounts for
the extra entry. Traversal never grows those reservations. Bellman–Ford uses
`O(n(n+m))` time; Dijkstra uses `O(n+m log(m+1))` time. Materializing a path
counts the chain, allocates exactly its edge count, then fills it backwards
into forward order, without retaining graph storage.

## Algorithm references

The strict-relaxation, nonnegative Dijkstra and bounded-pass Bellman–Ford
arguments follow Jeff Erickson's
[Shortest Paths chapter](https://jeffe.cs.illinois.edu/teaching/algorithms/book/08-sssp.pdf),
especially sections 8.1–8.3, 8.6 and 8.7. The duplicate-entry priority-queue
approach is also illustrated by the official Rust
[BinaryHeap Dijkstra example](https://doc.rust-lang.org/std/collections/binary_heap/index.html).
This module supplies its own explicit reachability, signed overflow,
canonical tie, capacity and work contracts.

## Executable acceptance and limits

All four registered tests passed on native Linux x86_64:

| Test target | Accepted evidence | Run time |
| --- | --- | --- |
| `extended_weighted_graph_execution` | Two tests: storage, paths, ties, checked `i64` endpoints/overflow, cycle diagnostics, owner independence, metadata and exact limit precedence | 8.84 s |
| `extended_weighted_graph_model_execution` | One test: 2,819 graphs, 5,638 algorithm outcomes and 12 oracle controls | 6.95 s |
| `extended_weighted_graph_resources_execution` | One test: five operation profiles, nine reached allocation failures, 16 observer controls; balanced cleanup and successful same-process recovery | 9.09 s |

The independent model enumerates simple paths and reachable cycles with exact
integers instead of reproducing either shortest-path algorithm. Its finite
corpus produced 4,910 successful results, 445 global-negative-edge rejections
and 283 reachable-negative-cycle rejections. It exhausts selected two- and
three-node graph families, then adds seeded four-to-six-node multigraphs,
signed DAGs and input permutations. The seed is `0x6a90261107`. Separate direct
fixtures exercise both signed 64-bit endpoints, overflow on non-improving
candidates, stale queue entries and both orders of final-scan overflow/cycle
precedence.

The resource gate covers construction from edges, copying a view, Dijkstra,
Bellman–Ford and path materialization. It classifies allocation sites against
the current native runtime, checks exact source allocation/release extents,
and fails every allocation reached by those profiles once. Each failed
operation releases its private storage before retry while preserving its
input owners. Natural overflow and negative-cycle errors also release their
private storage. The Dijkstra profile makes repeated tentative improvements
while using only its initial label and queue allocations.

See the [fixture guide](../tests/fixtures/extended/weighted_graph/README.md)
for selectors, corpus boundaries and observer controls. Local run logs are
`target/stdlib-work/weighted-graph-direct.log`,
`target/stdlib-work/weighted-graph-model.log` and
`target/stdlib-work/weighted-graph-resources.log`.

These are finite executable checks, not a proof or an exhaustive allocation
history. Generated cases use small costs; direct fixtures cover selected
`i64` boundaries. Resource injection covers the nine allocations reached by
the declared profiles, not every possible graph or failure schedule. Physical
borrow validity and one cleanup authority per owner remain caller obligations.
GPU-device execution, other targets, formal verification and the separate
route-cost application remain outside these receipts. No compiler changes
were needed for these four gates.
