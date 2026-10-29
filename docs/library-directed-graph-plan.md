# Directed graphs and dependency ordering

## Scope and sources

Provide integer-only directed simple graphs, shortest-hop BFS results and
deterministic topological ordering. Existing numeric CSR matrices add duplicate
coefficients and omit zero sums; those policies must not define graph edges.
Reuse Vec, slice ordering, Deque and BinaryHeap rather than duplicate collection
engines. No compiler, ABI, extractor, proof or protected std::vec changes.

[Boost BFS documentation](https://www.boost.org/latest/libs/graph/doc/html/graph/algorithms/traversal/breadth_first_search.html)
defines edge-count distances and FIFO discovery. Use first discovery to retain
parents, scanning ascending neighbors. The source has distance zero and no
parent; unreachable vertices have neither distance nor parent. Self-loops do
not rediscover vertices. This is unweighted shortest-hop search.

[Jeff Erickson's section 6.5](https://courses.physics.illinois.edu/cs374/fa2017/notes/06-dfs.pdf)
describes Kahn ordering by maintaining incoming counts and a bag of ready nodes.
Use the existing Min heap for that bag: choosing the smallest available ID at
each step gives the lexicographically smallest valid order. This policy changes
queue-based linear traversal to O(m+n log n). Exhausting ready nodes before all
nodes are emitted means Cycle, including self-loops. Do not modify the graph.

## Modules and APIs

`ext::graph` owns storage, checked construction and validation:

```text
Edge { source:i32, target:i32 }
View { nodes:i32, offsets:core::slice::View<i32>, targets:core::slice::View<i32> }
Limits { max_nodes:i32, max_edges:i32, max_work:u64 }
ErrorKind = InvalidLimits | Bounds | NodeLimit | EdgeLimit | WorkLimit
          | Offset | Source | Target | Order | AllocationFailed | Cycle | Closed
Error { kind:ErrorKind, node:i32, edge:i32 }
Graph { offsets:Vec<i32>, targets:Vec<i32>, count:i32, active:bool }
default_limits() -> Limits
validate(View, Limits) -> Result<i32,Error>
view(nodes:i32, offsets:core::slice::View<i32>, targets:core::slice::View<i32>, Limits) -> Result<View,Error>
from_edges(nodes:i32, edges:core::slice::View<Edge>, Limits) -> Result<Graph,Error>
from_view(View, Limits) -> Result<Graph,Error>
neighbors(View, node:i32, Limits) -> Result<core::slice::View<i32>,Error>
Graph::borrow(&self) -> &Graph
Graph::is_open(&self) -> bool
Graph::node_count(&self) -> i32
Graph::edge_count(&self) -> i32
Graph::view(&self) -> Option<View>
Graph::destroy(&self) -> bool
```

`ext::graph_algorithms` uses that one validation boundary:

```text
BfsPaths { distances:Vec<i32>, parents:Vec<i32>, selected_source:i32, active:bool }
bfs(View, source:i32, Limits) -> Result<BfsPaths,Error>
topological_order(View, Limits) -> Result<Vec<i32>,Error>
BfsPaths::borrow(&self) -> &BfsPaths
BfsPaths::is_open(&self) -> bool
BfsPaths::node_count(&self) -> i32
BfsPaths::source(&self) -> Option<i32>
BfsPaths::distance(&self, node:i32) -> Result<Option<i32>,Error>
BfsPaths::predecessor(&self, node:i32) -> Result<Option<i32>,Error>
BfsPaths::destroy(&self) -> bool
```

Names above are fixed for independent authors. Fields describe owner state,
not permission to construct or mutate it manually. End borrowed views before
destruction; copies alias one cleanup authority. destroy returns true for the
first active release and false afterward, leaving empty reusable owner state.
Closed Graph.view/source return None and node/edge counts are zero; BfsPaths
queries report Closed before node Bounds. No implicit move/drop/lifetime claim.

## Graph shape, construction and errors

Node IDs are dense 0..nodes. Keep isolated nodes. Canonical adjacency has
offsets length nodes+1, first offset zero, nondecreasing offsets, final offset
equal to targets.length, and each row's targets strictly increasing in range.
Empty graph is nodes=0, offsets=[0], targets=[]; an owned empty graph still
needs the one offset allocation. Duplicate input edges collapse idempotently;
self-loops remain. from_edges copies before sorting and never mutates input.
Successful validate returns the stored target/edge count.
from_view validates then copies into independent backing. Graphs are immutable
through public operations; neighbors returns a read-only logical borrow.

Defaults: 1,048,576 nodes, 1,048,576 raw/stored edges, 100,000,000 work units.
This profile has hard node ceiling 536,870,910 and edge ceiling 268,435,455;
native Vec element-size capacity checks still precede allocations. Raw edge
count is limited before deduplication, and the resulting stored count cannot
exceed it. Bounds rejects negative nodes and invalid View starts/lengths/sums.
Negative configured node/edge limits give InvalidLimits. Size/work admission
precedes backing access in construction and validation. Source/target IDs are
checked in original input order before allocation or sorting.

validate first checks limits, all descriptor metadata, hard/configured node
and edge bounds and exact offset length (mismatch is Bounds), then validation work. Next scan all
offsets before any target. Offset failure identifies the preceding row for a
bad next offset, or node 0/-1 for a bad first offset, with edge=-1. Then scan
rows and edges in order: bad target -> Target; non-increasing target -> Order.
These errors carry source row and relative edge index. from_edges instead
reports Source/Target with the offending endpoint ID and original edge index,
checking each source before its target. Bounds/limits/work/allocation errors
otherwise use node=edge=-1. neighbors validates completely before node Bounds,
which carries node=requested and edge=-1. An invalid BFS source uses that same
requested-node payload after graph validation. Closed carries node=edge=-1.

Algorithms call validate once, check BFS source Bounds, admit their full work
estimate, then allocate. Invalid graph errors therefore precede source/body
admission. No repeated whole-graph validation inside traversal. Distance and
predecessor queries reject Closed, then out-of-range Bounds with node=requested
and edge=-1; valid unreachable/source-parent absence is Option::None. Distances
are at most nodes-1 and fit i32. First FIFO discovery with sorted neighbors
fixes ties; it does not mean choosing the numerically smallest predecessor.

All recoverable errors preserve input and release private partial owners. Cycle
returns no partial result or purported cycle witness (node=edge=-1). Out-of-memory
maps to AllocationFailed; preflight capacity failures use NodeLimit/EdgeLimit.
Logical checks cannot establish backing, lifetime or arbitrary alias safety;
native physical traps have no rollback guarantee.

## Work and space

Work units are deterministic weighted size estimates for admission, not exact
instruction counts or wall-clock deadlines. Let n=nodes, m=selected raw edges
for from_edges and stored edges otherwise, and h(x)=ceil(log2(max(x,1))).

| Operation | Required max_work |
| --- | --- |
| validate/view/neighbors | V=n+1+m |
| from_view | 2V |
| from_edges | n+1+6m+4m(1+h(m)) |
| bfs | V+4n+2m+1 |
| topological_order | V+4n+2m+4n(1+h(n)) |

Calculate in u64 after widening. Profile ceilings keep these sums/products
within u64. Validation always admits V before reads; algorithms then admit the
full estimate before allocation/traversal. from_view admits 2V before copying.
No partial result survives failure. Construction is O(n+m log m), BFS O(n+m),
ordering O(m+n log n), validation O(n+m). Reserve final/workspace capacities
before traversal; no growth or allocation in the BFS/topological inner loops.
Use a reserved Deque for BFS and a reserved Min BinaryHeap for ready IDs.

## Real program and acceptance

`dependency_order --nodes N [--source S]` reads CSV `before,after` through the
new bounded owned reader. Bounds: 4096 nodes, 65536 raw edges, 4 MiB input,
16384 Read calls and 1 MiB staged output. Output is CSV with header
`position,node,hops,predecessor`; optional source adds BFS fields, otherwise
both fields are empty. Source node distance is 0 with empty parent; unreachable
fields are empty. Empty graph without source prints only the header. Validate
CLI before input, reject cycles with empty stdout, preserve primary errors,
release all input/graph/path/output owners explicitly and ignore SIGPIPE.
Use canonical CSV parsing/writing and bounded output/diagnostic attempts.
Status 0 success/help, 2 CLI/data/cycle/limits, 3 input, 4 allocation, 5 output
or signal setup, 6 internal. Exact CLI/help/diagnostic details go to its guide.

Accept small native admission, direct metadata/error/graph/parent/order cases,
independent all-pairs hop and exhaustive small-permutation ordering models,
guarded physical boundaries, reached OOM and input/owner preservation, reserved
65,536-node chain/star/layered workloads, and real program normal/edge/CLI/
EOF/cap/I/O/cleanup cases. Reuse focused collection regressions only if needed.
Root runs compiler/native/Cargo serially under the existing library lock; every
command stays below two minutes. Agents run static/bounded CPU oracle controls.
Initial evidence is native Linux x86_64 CPU output from the GPU compiler;
user GPU execution, other targets and formal proofs need separate evidence.
The complete standard and extended library goal stays open.
