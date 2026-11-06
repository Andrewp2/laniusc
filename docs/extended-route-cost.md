# Exact integer route costs

[`route_cost.lani`](../sample_programs/library/route_cost.lani) composes bounded
CSV input, exact integer parsing, [weighted graphs](extended-weighted-graph.md),
shortest paths and staged CSV output. It contains no graph algorithm of its own.

**Native Linux x86_64 execution passes all four focused gates: 148 cases.**
The sample uses allocation and host stdin/stdout. GPU execution, other targets
and formal verification remain unverified. Compiling through the GPU compiler
is distinct from executing this host program as a GPU kernel.

```sh
route-cost --nodes N --source S [--algorithm dijkstra|bellman-ford] [--target T]
printf 'source,target,cost\n0,1,8\n0,2,2\n2,1,1\n1,3,3\n' |
  route-cost --nodes 5 --source 0 --target 3
```

The example emits fully quoted CSV with CRLF record endings:

```csv
"source","target","reachable","cost","path"
"0","3","true","6","0;2;1;3"
```

## Arguments and input

`--nodes` and `--source` are required. Node IDs range from zero through N−1;
N ranges from 1 through 4096. `--target` requests one route. The algorithm
defaults to `dijkstra`; choosing `bellman-ford` is explicit. There is no
automatic fallback. Short options are `-n N`, `-s S`, `-a ALGORITHM`, `-t T`
and `-h`. Attached short values and long `--name=value` values are accepted.
Duplicate options, unknown options and positional arguments are errors.

Node arguments contain ASCII decimal digits only, with leading zeros allowed.
Signs and whitespace are rejected. Help validates supplied option syntax and
values, then bypasses stdin and required-option and cross-field checks.
For example, `--help --nodes 2` succeeds; an unknown option still fails.

Input begins with exactly `source,target,cost`, in that order and case.
Quoted header fields are accepted. Each subsequent row has three fields:
source node, target node and exact signed `i64` cost. Endpoints use unsigned
decimal digits. Costs accept an optional `+` or `-`, followed by at least one
ASCII digit. Leading zeros and signed zero are allowed. Whitespace, exponents,
fractions and values outside the `i64` range are errors. No rounding occurs.

The existing CSV dialect accepts UTF-8, quoting and CRLF or LF endings.
Malformed quoting, altered headers, invalid UTF-8, unsupported control bytes
and invalid endpoints fail before computation. A header without edges is
valid. Parallel edges, exact duplicates and self-loops are retained.

## Costs, reachability and paths

Dijkstra rejects every negative edge, even in a disconnected component.
Bellman–Ford permits negative edges and rejects every source-reachable
negative cycle, even if that cycle cannot reach the requested target.
Disconnected negative cycles do not invalidate a Bellman–Ford result.

Every examined edge from a reached node uses checked `i64` addition before
testing whether it improves the target distance. An unrepresentable sum is
an error even when that candidate could not improve the current route.
Arithmetic never wraps or saturates. Both `i64::MIN` and `i64::MAX` remain
valid distances. Bellman–Ford may report arithmetic overflow before detecting
a negative cycle; the first encountered error wins.

Each algorithm keeps the first predecessor for equal-cost alternatives in
the library's canonical traversal order. Neither promises a lexicographically
smallest path, and the two algorithms can choose different equal-cost paths.
The node-only route does not identify which duplicate parallel edge was used.

Without `--target`, output has columns `node,reachable,cost,predecessor`, one
row per node in ascending order. Unreachable rows have `false` and empty
cost/predecessor fields. The source has cost zero and no predecessor. Other
reachable rows name the predecessor node of a shortest-path edge.

With `--target`, output has columns `source,target,reachable,cost,path` and
one data row. A route lists node IDs separated by semicolons. Source equal
to target yields `true`, cost `0`, and the source ID alone. An unreachable
target yields `false` with empty cost and path fields. Empty reachable paths
and unreachable nodes therefore remain distinct.

## Bounds and failure behavior

| Resource | Bound |
| --- | ---: |
| Arguments after executable / total argument bytes | 24 / 1024 |
| Nodes | 4096 |
| Edges / CSV records including header | 65536 / 65537 |
| Raw input bytes | 4194304 (4 MiB) |
| Fields per record / bytes per field / bytes per record | 3 / 128 / 384 |
| Weighted-graph work budget per operation | 100000000 |
| Staged output bytes / path bytes | 1048576 / 65536 |
| Input read calls / stdout publication calls | 16384 / 16384 |
| CSV staging write calls / diagnostic write calls | 131072 / 8 |

The library admits conservative work bounds before running the algorithm.
A graph can fit node and edge limits but exceed Bellman–Ford's work budget.
The [weighted graph guide](extended-weighted-graph.md) gives the formulas.

| Exit status | Meaning |
| --- | --- |
| 0 | Success or help |
| 2 | Invalid arguments, CSV, endpoint or integer |
| 3 | Input I/O failure |
| 4 | Allocation failure |
| 5 | Output I/O or SIGPIPE-disposition setup failure |
| 6 | Negative edge requires explicit Bellman–Ford |
| 7 | Source-reachable negative cycle |
| 8 | Checked path arithmetic overflow |
| 9 | Input, graph, work or output resource limit |

Each error writes a short diagnostic to stderr on a best-effort basis.
Interrupted reads/writes retry within their call budgets. SIGPIPE is ignored
so a closed output pipe becomes status 5. A record exceeding the field count
or byte limits reports status 9, even if it would also have invalid contents.

All parsing, graph computation, path materialization and output rendering
finish before the first stdout write. Admission, allocation and arithmetic
failures publish no output prefix. Actual stdout failure can leave a prefix;
publication is not transactional.

The raw input and CSV table are destroyed after copying plain edge values.
The edge vector is destroyed after graph construction; the graph is destroyed
after producing independent `Paths`. Materialized path vectors, `Paths` and
CSV record owners are destroyed after rendering. Argument and output storage
stay live through publication and are then destroyed. Every returned failure
path releases the owners it acquired. These are source contracts, not a proof
of lifetime safety.

## Focused evidence

`tests/extended_route_cost_execution.rs` compiles this real sample through the
GPU compiler to a native-linked x86_64 executable. All four selectors pass:

| Group | Executed cases | Receipt |
| --- | ---: | --- |
| Simple-path model and route witnesses | 62 | `target/stdlib-work/route-cost-functional-qualified.log` |
| Admission, arithmetic and algorithm failures | 41 | Same functional receipt |
| CLI, help and limits | 31 | Same functional receipt |
| I/O and allocation failures | 14 | `target/stdlib-work/route-cost-io-final.log` |

The three functional selectors passed together in 9.04 seconds. The I/O
selector passed in 10.40 seconds. Coverage includes:

- Distances and route witnesses against exhaustive simple-path enumeration
  on small graphs, exact endpoint values, disconnected components, zero
  cycles, duplicate/parallel edges and seeded graph families.
- Invalid inputs, reachable negative cycles, disconnected negative Dijkstra
  edges, nonimproving overflow candidates, overflow before cycle detection,
  and input/edge/work bounds with no stdout prefix.
- CLI parsing, help, accepted maximum nodes and edge counts.
- Real I/O failures, interrupted I/O, closed output, directory input, successful
  publication across bounded writes and three selected allocation denials that
  must reach verified source sites.

The I/O oracle uses the shared exact native source authority and whole-run
mapping ledger. It checks source allocation/release sites, byte lengths and
flags, while accounting separately for native and CRT bootstrap calls.
The three OOM cases are finite samples, not an exhaustive failure sweep.
Two publication cases use a small-buffer Unix socket with a send timeout.
`std::stream::Descriptor.write` caps each host syscall at 1024 bytes and returns
that progress to the application's loop. In the success case, the receiver
waits for the first completed chunk, then drains the socket to completion.
In the error case it stays paused until the socket fills and a later write
returns `EAGAIN`. The latter must leave exactly the confirmed prefix and exit
with status 5. Trace assertions bind each syscall request to
`min(1024, remaining bytes)` and the advanced payload offset. No positive write
count is injected, and actual received bytes must match the expected CSV or
confirmed prefix. This exercises application-level partial progress and retry;
it does not require a kernel write shorter than its own 1024-byte request.
Host-only controls also pass: five distance/witness mutations, six ownership
mutations and seven publication mutations are rejected. These checks validate
the oracle's signal; they are separate from the 148 native cases. They can run
independently:

```sh
python3 -B tests/fixtures/extended/route_cost/oracle.py controls
```

The accepted sample explicitly qualifies `core::slice::View<T>` and slice
`View` constructors. This avoids an observed imported-name collision with
`ext::weighted_graph::View`. That compiler import-resolution dependency and its
minimal reproducer are tracked separately in the
[library dependency notes](library-dependencies.md); these passing gates do not
claim the compiler issue is fixed.
