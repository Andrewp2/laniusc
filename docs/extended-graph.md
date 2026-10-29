# Directed graphs and dependency ordering

The [directed-graph increment](library-directed-graph-plan.md) defines
integer adjacency owners, shortest-hop BFS and deterministic topological order.
The [storage](../extended/ext/graph.lani) and
[algorithm](../extended/ext/graph_algorithms.lani) sources pass all eight library
tests and all four application groups/183 cases on native Linux x86_64. This
increment is accepted; the full library goal stays open.

## Adjacency is not a numeric matrix

ext::graph represents a directed simple graph with dense node IDs 0..nodes-1.
Isolated nodes remain present, duplicate edges collapse idempotently and
self-loops remain edges. There are no weights or numeric coefficients. This
is separate from [numeric sparse CSR](extended-sparse.md), whose duplicate
summation and computed-zero removal must not define graph connectivity.

Canonical View stores nodes plus borrowed i32 offset/target Views. Offsets have
exactly nodes+1 elements, start at zero, never decrease and end at targets.length.
Every row's targets are in range and strictly increasing. Empty adjacency is
nodes=0, offsets=[0], targets=[]; even an owned empty Graph needs its offset
allocation. from_edges copies before sorting and never mutates its input;
from_view validates before making independent owned copies.

## Public surface

The following names belong to ext::graph:

```text
Edge { source:i32, target:i32 }
View { nodes:i32, offsets:core::slice::View<i32>, targets:core::slice::View<i32> }
Limits { max_nodes:i32, max_edges:i32, max_work:u64 }
ErrorKind = InvalidLimits | Bounds | NodeLimit | EdgeLimit | WorkLimit
          | Offset | Source | Target | Order | AllocationFailed | Cycle | Closed
Error { kind:ErrorKind, node:i32, edge:i32 }
default_limits() -> Limits
validate(View, Limits) -> Result<i32,Error>
view(nodes:i32, offsets:View<i32>, targets:View<i32>, Limits) -> Result<View,Error>
from_edges(nodes:i32, edges:View<Edge>, Limits) -> Result<Graph,Error>
from_view(View, Limits) -> Result<Graph,Error>
neighbors(View, node:i32, Limits) -> Result<View<i32>,Error>
```

Generic Views in parameter/result positions denote core::slice::View; the plain
View denotes graph adjacency. Graph exposes borrow, is_open, node_count,
edge_count, `view()->Option<View>` and `destroy()->bool`. Public owner fields describe
state, not permission to construct or alter it manually. Successful validate
returns the stored edge count. Edge implements `Ord<Edge>` lexicographically by
(source,target), using the existing slice sort.

ext::graph_algorithms adds `bfs(View,source,Limits)->Result<BfsPaths,Error>` and
`topological_order(View,Limits)->Result<Vec<i32>,Error>`. BfsPaths exposes borrow,
is_open, node_count, `source()->Option<i32>`, distance(node) and predecessor(node)
returning `Result<Option<i32>,Error>`, and `destroy()->bool`. The topological Vec
is an independent owner that the caller must destroy once.

## Validation and error precedence

Defaults are 1,048,576 nodes, 1,048,576 raw/stored edges and 100,000,000 work
units. Hard ceilings are 536,870,910 nodes and 268,435,455 edges; native Vec
capacity admission still applies. from_edges additionally checks its native
Edge staging capacity, `floor(i32::MAX/size_of<Edge>())`, **before work admission
and endpoint reads**. Raw edge count is limited before deduplication. Negative configured node/edge limits are InvalidLimits.
Bounds covers negative node counts and negative/overflowing View metadata.

Validation first checks limits, all descriptor metadata, configured/hard node
and edge ceilings and exact offset length (a mismatch is Bounds), then admits
validation work. It scans **all offsets before any target**. Invalid next offset
reports Offset at its preceding row; a bad first offset uses node 0, or -1 for
an empty graph. Offset errors have edge=-1. Then rows/edges are scanned in order:
out-of-range target -> Target, non-increasing target -> Order. Both carry the
row and zero-based edge index relative to the selected target View.

from_edges instead checks endpoints in original input order, each source before
its target, before allocation/sorting. Source/Target carries the offending node
ID and original relative edge index. Bounds/limit/work/allocation errors use
node=edge=-1. neighbors validates the complete graph before requested-node Bounds,
whose payload is node=requested, edge=-1. BFS uses that same source Bounds payload.

Algorithms call validate once, then check the BFS source, admit the full body
estimate and allocate. Invalid graph errors therefore precede source/body errors.
Recoverable errors preserve input and release private partial owners. Allocation
failure maps to AllocationFailed; preflight capacity failures use NodeLimit or
EdgeLimit. Cycle and Closed use node=edge=-1; Cycle returns no partial order
or cycle witness.

## Work admission and storage

Let n be nodes, m be raw edges for from_edges and stored edges otherwise,
h(x)=ceil(log2(max(x,1))) and V=n+1+m.

| Operation | Required max_work |
| --- | --- |
| validate / view / neighbors | V |
| from_view | 2V |
| from_edges | n+1+6m+4m(1+h(m)) |
| bfs | V+4n+2m+1 |
| topological_order | V+4n+2m+4n(1+h(n)) |

These exact admission estimates use widened u64 arithmetic within the hard
profile. They are weighted sizes, not instruction counts, elapsed time or a
shared allowance across calls. Validation admits V before backing reads;
from_view admits 2V before offset/target reads; from_edges admits its complete
estimate before endpoint reads. Full algorithm admission precedes allocation/
traversal after validation and the BFS source check.
No repeated whole-graph validation occurs in traversal. BFS/topology reserve
all result/workspace capacities before their inner loops, without loop growth.
Construction is O(n+m log m), validation/BFS O(n+m), topology O(m+n log n).

Keep selected physical backing initialized, correctly typed and live; logical
metadata does not establish it. Neighbor Views are read-only logical borrows.
Do not mutate adjacency through aliased Views or public owner fields. End all
borrows before destruction and keep shallow owner copies inactive. Graph and
BfsPaths each have one cleanup authority: first active destroy returns true,
subsequent destroys false, with empty closed state. Closed Graph.view and
BfsPaths.source return None; counts become zero. Native physical traps have no
rollback guarantee. There is no implicit move/drop, lifetime enforcement or proof.

## BFS and topology policies

BFS uses a reserved FIFO Deque, scans ascending neighbors and retains each
node's first discovery parent. As described in [Boost's BFS documentation](https://www.boost.org/latest/libs/graph/doc/html/graph/algorithms/traversal/breadth_first_search.html),
distance is the minimum number of edges. The selected source has distance 0
and no parent; unreachable nodes have neither. Self-loops do not rediscover.
The tie policy is FIFO discovery with sorted neighbors, not minimum numeric
predecessor. Every distance fits 0..nodes-1.

A live BfsPaths returns Ok(None) for an unreachable distance and for the source
or unreachable predecessor. distance/predecessor reject Closed **before** node
Bounds. An absent path is not a bounds or closed-owner error.

Topological ordering uses incoming counts and the existing Min BinaryHeap for
ready node IDs. [Erickson section 6.5](https://courses.physics.illinois.edu/cs374/fa2017/notes/06-dfs.pdf)
describes Kahn's ready-node algorithm without graph destruction. Choosing the
smallest ready ID is this library's policy: it yields the lexicographically
smallest valid order, with O(m+n log n) work. If ready nodes exhaust before all
nodes are emitted, return Cycle, including for a self-loop. Input is unchanged.

## Application, evidence and targets

The [dependency_order program](extended-dependency-order.md) reads before,after
CSV through bounded owned input and emits position,node,hops,predecessor CSV.
Its profile admits 4096 nodes, 65536 raw edges, 4 MiB input / 16384 Read calls
and 1 MiB staged output. Optional BFS fields distinguish source and unreachable
nodes. Its separate guide owns exact CLI, wire and publication policy. The
four application groups pass 183 native cases. Its documented standalone build
and exact 120-byte CRLF example also pass (directed-graph-app-build-command.log);
these smoke checks overlap existing cases and add no count.

Current sources are graph d8e52163 and algorithms 57ba3bcf. Separate registered
receipts below are under target/stdlib-work. All eight library tests pass
through separate commands, not one combined run. Application groups total 183
distinct cases (83+40+41+19).

| Receipt | Accepted scope |
| --- | --- |
| directed-graph-admission-first.log | 1 test / 7.69s: copy/sort/dedup, neighbors, BFS distance/parent, literal topology, Cycle and repeated cleanup |
| directed-graph-preflight-first.log | 1 direct preflight test / 7.94s |
| directed-graph-owners-first.log | 1 direct owner-contract test / 7.04s |
| directed-graph-owner-faults-retry.log | 1 test / 7.77s: five normal/Cycle profiles and seven reached mmap failures, with matched addresses/lengths |
| directed-graph-boundaries-first.log | 1 test / 6.80s: three pure phases, one 8192-byte guarded mapping/protection/release |
| directed-graph-scale-first.log | 1 test / 7.12s: 65,536-node chain/star/layered shapes, every result triple, three BFS/three topology reservations and nine matched releases per shape |
| directed-graph-physical-first.log | 1 test / 7.51s: two deliberately overclaimed backing programs exit101; separate from positive guarded access |
| directed-graph-model-first.log | 1 test / 7.99s: 4,570 cases/seven operations/two layouts, traversal graphs at most six nodes; seed 0x6a4f0261103 |
| directed-graph-app-model-first.log | 1 application model test / 9.12s: 83 native cases, source 03796591 |
| directed-graph-app-rejection-first.log | 1 application rejection test / 9.65s: 40 cases |
| directed-graph-app-cli-first.log | 1 application CLI test / 8.96s: 41 cases |
| directed-graph-app-io-first.log | 1 application I/O test / 9.47s: 19 cases |

Admission uses strict ELF/shared jumps and full tracing with entry/exit plus
matched memory owners; direct preflight has only entry/exit. The owner retry
corrected a fixture view-range start/count assumption after its initial trap.
The model oracle corrected two pre-run precedence omissions. Production stayed
unchanged. [Direct](../tests/fixtures/extended_graph/README.md),
[model](../tests/fixtures/extended_graph_model/README.md) and
[resource](../tests/fixtures/extended_graph_resources/README.md) guides retain
exact source/retry/trace scopes. Eight model-output corruption controls are
CPU checks, not native coverage counts. Existing sparse/collection receipts
retain their scope and do not establish these graph APIs.

The accepted target is native Linux x86_64 CPU output from the GPU
compiler, using existing allocator/collection/provider contracts. User-GPU
execution, other backends and formal proofs need separate evidence. No compiler,
ABI, extractor or protected formal-vector contract changes belong here. Other
graph algorithms remain outside this increment.

## Focused targets

Run targets separately; fixture guides retain exact accepted filters.

```sh
cargo test --test extended_graph_execution
cargo test --test extended_graph_model_execution
cargo test --test extended_graph_resource_execution
cargo test --test extended_dependency_order_execution
```
