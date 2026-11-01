# Strong components and condensation

This graph increment adds complete cycle decomposition over the existing
immutable `ext::graph::View`. It belongs in `ext::graph_algorithms` alongside
BFS and topological ordering. It preserves the full standard/extended-library
goal; unrelated graph families and compiler/runtime work remain separate.
The [implementation guide](extended-graph-components.md) records acceptance:
six library tests, four application groups with 312 cases, and both documented
standalone examples pass on native Linux x86_64.

## Contract

```text
strong_components(View, Limits) -> Result<StrongComponents, ext::graph::Error>
condensation(View, Limits) -> Result<Condensation, ext::graph::Error>

StrongComponents:
  borrow() -> &StrongComponents
  is_open() -> bool
  node_count() -> i32
  component_count() -> i32
  component(node:i32) -> Result<i32, Error>
  same_component(left:i32, right:i32) -> Result<bool, Error>
  destroy() -> bool

Condensation:
  borrow() -> &Condensation
  is_open() -> bool
  node_count() -> i32
  component_count() -> i32
  component(node:i32) -> Result<i32, Error>
  same_component(left:i32, right:i32) -> Result<bool, Error>
  view() -> Option<ext::graph::View>
  destroy() -> bool
```

Two vertices share a component exactly when each can reach the other, including
zero-length paths. Components have dense IDs in ascending order of their
smallest original node. Those IDs carry no topological-order promise. An empty
graph has zero components; every isolated node is a singleton; a self-loop
does not create another component.

Condensation owns the mapping and an independent canonical Graph. Its vertices
are component IDs, and its edges are exactly the distinct original edges
between different components. It has no self-loops and is acyclic. Reuse
`graph::from_edges` for canonical edge sorting/deduplication and owner creation.
Do not accept a graph and a separately computed mapping: their correspondence
would otherwise be unchecked. Both constructors leave input unchanged and
retain no input backing; results remain valid after input destruction.

Queries reject Closed first, then Bounds with node=requested, edge=-1. The
two-node query checks left before right. Closed counts are zero; closed view
is None. First destroy returns true, later calls false. Each returned owner
has one cleanup authority; copies stay inactive and views expire on destroy.
No automatic ownership, safe arbitrary public-field mutation or trap rollback
is promised.

## Algorithm and sources

[Tarjan's original algorithm, section 4](https://www.cs.cmu.edu/~cdm/resources/Tarjan1972-sccs.pdf)
and the [CMU DFS explanation](https://www.cs.cmu.edu/~15451-f18/lectures/lec19-DFS-strong-components.pdf)
define the lowlink rules and component-root test. The implementation uses
explicit frames instead of recursive calls. A tree-child return contributes
its lowlink; an already discovered, still-active target contributes its
discovery index. Completed targets do not affect lowlinks. A root pops one
complete active suffix. Each edge cursor advances once.

Reserve six i32 buffers of capacity n before traversal: returned mapping,
discovery indices, lowlinks, active vertices, DFS nodes and DFS edge cursors.
Unvisited has discovery=-1; active means discovered with mapping=-1. Scan
roots and canonical neighbors ascending. After traversal, reuse lowlink
storage for a raw-ID remap obtained by scanning original nodes ascending.
Release all five workspaces before returning the mapping or constructing
condensation. Native recursion depth must not depend on graph depth.

Kosaraju's two traversals would require reversed adjacency. Tarjan fits the
existing representation with O(n) workspace. SCC computation is O(n+m).
Condensation reuses existing canonical construction, so its complete cost is
O(n+m log(max(m,2))) with O(n+m) storage. No throughput ratio is claimed.

## Admission and failures

Call existing `graph::validate` once before operation-specific admission.
Its exact metadata, node/edge ceilings, full offset-before-target scan, errors
and error payloads remain authoritative. No repeated graph validation occurs
inside DFS. Invalid graph errors precede operation capacity/work errors.

Let n=nodes, m=stored edges, V=n+1+m, h(x)=ceil(log2(max(x,1))) and
F(n,m)=n+1+6m+4m(1+h(m)), the existing edge-constructor estimate.

| Operation | Required max_work after validation |
| --- | --- |
| strong_components | V+16n+4m+1 |
| condensation | V+16n+6m+1+F(n,m) |

These are fixed conservative weighted admission sizes, not instruction counts
or shared runtime budgets. Widen arithmetic to u64 before every product. The
canonical graph hard ceilings keep these values representable. Admit the full
operation before allocating or traversing its workspaces. Condensation first
requires m <= floor(i32::MAX/size_of<graph::Edge>()) and returns EdgeLimit if
not; this bounds its conservative m-entry pair reservation even when the
eventual cross-component edge count is smaller. Capacity precedes body work.

All SCC capacities are admitted by the existing graph i32 profile. Later
reserved pushes/resizes are invariants, not recoverable allocation sites.
Condensation reserves m Edge entries, maps all original edges through the
completed component IDs, skips intra-component edges, then passes the filled
view to `graph::from_edges` with the original Limits. That constructor's actual
work requirement is bounded by the pre-admitted F(n,m). Every error releases
all acquired private resources; source metadata/payloads remain unchanged.
Preserve existing graph errors. A native allocator failure is AllocationFailed.

Empty SCC needs no allocation. Empty condensation still owns the canonical
Graph offset [0], requiring its normal one allocation. No fake empty success
replaces that ownership contract.

## Application

Extend the existing `dependency_order` example with `-C` / `--components`.
Default mode keeps its existing output and cycle rejection. Components mode
accepts cyclic input, builds condensation, uses existing topological_order on
the resulting DAG, and emits quoted CRLF CSV `node,component,position` in
ascending original node order. Position is that component's zero-based place
in the lexicographically smallest component topological order. No BFS columns
exist in this mode. Combining components mode with --source is a usage error
before stdin; duplicate mode flags also reject. Reuse existing node/input/edge,
work, output and I/O limits, source parsing, staging and cleanup boundaries.
Keep the current argv lifetime policy. A component-position Vec enables linear
output lookup rather than scanning all nodes once per component.

## Evidence and ownership

Root owns this contract, all compiler/Cargo/native commands, final reference
generation and commit/push. Commands remain below two minutes and compiler/
native gates run serially under target/stdlib-work/library-gpu.lock. Agents
own separate production, direct contracts, independent model, resources/scale,
application, application oracle, documentation and independent-review paths.
They may run bounded static/host-only controls; no compiler/native execution.

Start with one tiny both-form runtime admission. Then check graph/error
precedence, deterministic IDs, closed owners, input independence, condensation
edge exactness and reuse by existing topology. An independent model must use
mutual reachability, not repeat Tarjan. Include exhaustive small directed
graphs, self-loops, disconnected/nested cycles, active cross-links and edges
into already finished components. Reach every selected actual allocation
site and match release addresses/extents. Use analytic 65,536-node chains,
cycles and component chains to test deep traversal and complete output.
Existing application groups plus new mode cases and standalone examples are
separate acceptance scopes. Do not use library tests as evidence for the CLI.

Accepted target initially means native Linux x86_64 CPU output from the GPU
compiler. Other targets, user GPU execution and formal verification require
separate support. Missing compiler support gets a narrow reproduction and
dependency report instead of a compiler change in this increment. Human root
README, AI policy, CONTRIBUTING, tests/common and protected vector/compiler/
proof sources are outside this edit surface.
