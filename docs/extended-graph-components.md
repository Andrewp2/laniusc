# Strong components and condensation

The [component increment](library-graph-components-plan.md) adds two operations
to [ext::graph_algorithms](../extended/ext/graph_algorithms.lani):
`strong_components` groups mutually reachable nodes; `condensation` also builds
the directed acyclic graph between those groups. All six new library tests and
four application groups/312 cases pass on native Linux x86_64.
The earlier [directed-graph receipts](extended-graph.md) retain their original
BFS, topological-order and adjacency scope. The full library goal remains open.

## Public surface and identity

```text
strong_components(graph::View, graph::Limits) -> Result<StrongComponents, graph::Error>
condensation(graph::View, graph::Limits) -> Result<Condensation, graph::Error>

StrongComponents and Condensation:
  borrow() -> &Self
  is_open() -> bool
  node_count() -> i32
  component_count() -> i32
  component(node:i32) -> Result<i32, graph::Error>
  same_component(left:i32, right:i32) -> Result<bool, graph::Error>
  destroy() -> bool

Condensation:
  view() -> Option<graph::View>
```

Here `graph` denotes `ext::graph`; `Self` denotes the concrete owner. Two nodes
share a component exactly when each can reach the other, including a path of
length zero. Component IDs are dense and ordered by the smallest original node
in each component. They carry no topological-order promise. For example, the
graph with only edge 1->0 has components 0 and 1, and its condensation edge is
1->0. Use the existing `topological_order` when dependency order is required.

An empty graph has zero components. Every isolated node is a singleton. A
self-loop leaves its node in the same component. Condensation contains exactly
the distinct original edges whose endpoints have different component IDs;
it omits intra-component edges and has no self-loops. Its adjacency uses the
existing canonical `Graph` representation, with increasing unique neighbors.

Both results own an independent original-node mapping. Condensation also owns
its independent graph; constructors do not retain input backing. Either result
remains valid after the source graph is destroyed. Condensation computes its own
mapping, so callers cannot accidentally combine a graph with another graph's
component map.

## Queries and manual ownership

Queries check `Closed` before node `Bounds`. Bounds reports `node=requested`
and `edge=-1`; `same_component` checks its left argument before its right.
Closed owners report zero counts, and closed `Condensation.view()` returns
`None`. The first active `destroy()` returns true and releases the owner;
subsequent calls return false. `Closed` uses `node=edge=-1`.

Keep one active cleanup authority for each returned owner. Shallow copies and
borrowed views do not receive independent cleanup authority. A condensation
view expires when its owner is destroyed; keep the owner alive and unchanged
through calls using that view. Public fields describe state and do not permit
arbitrary owner construction or mutation. The language does not provide
automatic moves, destruction or lifetime enforcement here.

Input views must select live, initialized, correctly typed physical backing.
Successful logical validation does not prove that backing exists. Keep aliases
inactive through an operation. Returned errors preserve input and release all
private partial owners. Physical traps and concurrent mutation have no rollback
or automatic-cleanup guarantee.

## Admission and errors

Both constructors call `graph::validate` once before operation admission. The
existing [graph validation order](extended-graph.md#validation-and-error-precedence)
is authoritative: configured limits and all descriptor metadata, node/edge
ceilings, exact offset length, validation work, all offsets, then targets in row
order. Thus invalid graph errors precede component capacity or body-work errors.
Traversal does not repeat validation.

Default limits are 1,048,576 nodes, 1,048,576 stored edges and 100,000,000 weighted
work units. Hard ceilings remain 536,870,910 nodes and 268,435,455 edges. Let
`n=nodes`, `m=stored edges`, `V=n+1+m`, `h(x)=ceil(log2(max(x,1)))`, and
`F(n,m)=n+1+6m+4m(1+h(m))`, the existing edge-constructor estimate.

| Operation | Required `max_work` |
| --- | --- |
| `strong_components` | `V+16n+4m+1` |
| `condensation` | `V+16n+6m+1+F(n,m)` |

These fixed conservative estimates use widened `u64` arithmetic. They admit
the complete operation before workspace allocation or traversal; they are
weighted sizes, not instruction counts, elapsed-time bounds or a shared budget
across calls. Validation still has its own earlier `V` admission.

After validation, condensation first requires
`m <= floor(i32::MAX/size_of<graph::Edge>())`; otherwise it returns `EdgeLimit`
before checking body work. This bounds its conservative reservation of `m`
edge pairs even if many input edges will collapse into one component. The graph
node ceiling already admits all six `i32` SCC buffers. Constructor-generated
capacity, work and allocation errors use `node=edge=-1`; existing
graph-validation payloads are preserved. Query Bounds carries the requested
node as described above. Native allocation failure returns `AllocationFailed`.

Empty strong components allocate no backing. Empty condensation still creates
the canonical graph with offsets `[0]`, which requires one allocation and can
return `AllocationFailed`.

## Algorithm and storage

[Tarjan's original algorithm, section 4](https://www.cs.cmu.edu/~cdm/resources/Tarjan1972-sccs.pdf)
and the [CMU DFS explanation](https://www.cs.cmu.edu/~15451-f18/lectures/lec19-DFS-strong-components.pdf)
describe the lowlink and component-root rules. A completed tree child contributes
its lowlink; an already discovered active target contributes its discovery
index. Completed components do not affect lowlinks. A component root removes
one complete suffix from the active stack.

The Lanius implementation represents DFS calls with explicit node and edge-cursor
stacks, so native recursion depth does not grow with graph depth. It reserves
six `i32` buffers of capacity `n`: result mapping, discovery indices, lowlinks,
active nodes, DFS nodes and DFS edge cursors. Every edge cursor advances once.
Unvisited nodes have discovery index -1; discovered nodes with mapping -1 are
active. Roots and canonical neighbors are scanned in ascending order.

After traversal, a scan of original nodes in ascending order builds the raw-ID
remap in reused lowlink storage. This gives the public minimum-node ordering
independently of Tarjan's component-completion order. The five workspaces are
released before returning the mapping or starting condensation construction.
Reserved pushes and resizes do not introduce later growth allocation sites.

Condensation reserves `m` edge pairs, maps every original edge, skips pairs
within a component and passes the filled view to `graph::from_edges`. That
existing constructor sorts, deduplicates and creates canonical owned adjacency.
Its actual work estimate is bounded by the pre-admitted `F(n,m)`. Strong
components use O(n+m) work and O(n) workspace; condensation uses
O(n+m log(max(m,2))) work and O(n+m) storage. No throughput ratio is claimed.

## Application and evidence

The [dependency_order program](extended-dependency-order.md) adds `-C` /
`--components`. This mode accepts cyclic input, computes condensation, uses the
existing topological order on that DAG and emits quoted CRLF CSV
`node,component,position` in ascending original-node order. Position is the
component's zero-based place in the lexicographically smallest component
topological order. The ordinary mode retains its cycle rejection and BFS
columns. Components mode rejects `--source` and duplicate mode flags before
stdin. The application guide owns the exact CLI, limits and publication policy.

Production source `1f1cf7cd4920f05567d53283628d1b119bf93f3d108255ad354522d61267d8a6`
passes all six new library tests across the separate receipts below. Application
source `3cae8b5ff6fe4d7cbd495d7b54155d33a1c941b8e97c4abdd6c3ab5d0a494a3c`
passes all four application groups/312 cases (166+52+58+36). This includes 183
retained cases and 129 new cases; historical cases are not added again. The
standalone build and both documented examples also pass.

| Receipt under `target/stdlib-work` | Accepted scope |
| --- | --- |
| `graph-components-admission-first.log` | 1 native test / 6.86s: both owners, literal mapping/DAG/topological order, unchanged input and repeated cleanup; strict ELF/shared jump checks and full allocation/release trace |
| `graph-components-contracts-first.log` | 2 native tests / 9.56s: complete owner/edge/guard/query/work contracts and validation/error precedence; owner traces match addresses/extents, preflight has no intervening host effects |
| `graph-components-model-first.log` | 1 native test / 7.28s: 3,218 operation/storage cases against mutual reachability, exact canonical component edges and independent topology; two constructors, two storage preparations, seed `0x5cc0261105` |
| `graph-components-resources-first.log` | 1 native test / 6.54s: four baselines, 17 reached allocation denials and 17 same-process recoveries; exact live-owner address/extent accounting and complete independent results after input destruction |
| `graph-components-scale-first.log` | 1 native test / 7.45s: three 65,536-node shapes, both constructors, every mapping/offset/target checked against independent formulas and exact reservation/release ledgers |
| `graph-components-app-model-accepted.log` | 1 application model test / 11.23s: 166 process cases on application source `3cae8b5f` |
| `graph-components-app-rejection-first.log` | 1 application rejection test / 9.66s: 52 process cases |
| `graph-components-app-cli-first.log` | 1 application CLI test / 8.26s: 58 process cases |
| `graph-components-app-io-first.log` | 1 application I/O test / 9.48s: 36 process cases, including component-mode allocation/read/write failures |
| `graph-components-app-build-command.log` | The documented standalone compiler command exits 0 without output |
| `graph-components-app-examples.log` | Both documented shell pipelines exit 0 with empty stderr and exact 120-byte default / 109-byte component CRLF CSV output |

The separate Rust driver builds took 3.10s for admission, 1.63s for the two
remaining direct tests, 1.59s for the model, 1.75s for resources and 0.20s for
scale; application model/rejection/CLI builds took 0.18s / 0.18s / 0.17s. The
[direct fixture guide](../tests/fixtures/extended_graph_components/README.md)
retains exact fixture and trace scopes. The
[independent model guide](../tests/fixtures/extended_graph_components_model/README.md)
records all 531 labeled directed graphs on zero through three nodes, seeded
graphs through 16 nodes and exact error/owner outputs. Both input preparations
use the actual i32 stride +4; they do not establish different stride values.
The ten host-only corrupted-output controls add no native coverage count. The
[resource guide](../tests/fixtures/extended_graph_components_resources/README.md)
records six nonempty SCC sites, ten nonempty condensation sites, no empty-SCC
site and one empty-condensation site. Full ledgers check cleanup before process
exit, including each reached failure and subsequent recovery. Scale executes a
deep chain, one giant cycle and a chain of 256-node cycles. Their component
counts are 65,536 / 1 / 256 and canonical DAG edge counts are 65,535 / 0 / 255.
Each shape checks all 131,072 mapping observations across the two constructors;
its complete live-owner ledger matches 19 / 17 / 19 allocations and releases.
These are finite workload checks, not a measured complexity or throughput claim.
The first application attempt stopped at an unsupported `else if` spelling
before native execution. Replacing it with nested blocks produced the accepted
model receipt; no compiler change was made. The
[application fixture guide](../tests/fixtures/extended_execution/dependency_order/README.md)
records its exact 312-case scope, including nine selected reached component-mode
allocation failures. Those sites do not exhaust every application allocation.
Standalone examples overlap existing application cases and add no distinct case
count.
The earlier eight library tests and four application
groups/183 cases do not establish these new APIs or this mode. Historical
graph, sparse and collection evidence retains its source and API scope.

This increment is accepted on native Linux x86_64 CPU output from the GPU
compiler. User-program GPU execution, other targets, automatic ownership and
formal verification require separate evidence. Additional graph algorithms and
the full standard/extended-library goal remain open.
