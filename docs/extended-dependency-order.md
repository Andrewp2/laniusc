# Order CSV dependencies and group cycles

`sample_programs/library/dependency_order.lani` reads directed dependency edges,
computes the lexicographically smallest valid node order and optionally adds
shortest-hop information from one source. With `--components`, it accepts
cycles and reports each node's strong component and that component's position
in the condensed dependency order. Its CLI is
`dependency_order --nodes N [--source S | --components] [--help]`.

## Build and use

With the compiler binary built, run from the repository root. The standalone
build and both exact shell examples below passed, along with the 312-case
integration corpus. Current and historical receipts are recorded separately
under acceptance.

```sh
mkdir -p target/stdlib-work
timeout --kill-after=2s 100s flock -w 95 target/stdlib-work/library-gpu.lock \
  target/stdlib-build/debug/laniusc --stdlib-root stdlib --source-root extended \
  --emit x86_64 sample_programs/library/dependency_order.lani \
  -o target/stdlib-work/dependency_order
printf 'before,after\n0,2\n1,2\n2,3\n' | \
  target/stdlib-work/dependency_order --nodes 5 --source 0
```

The first example expects these 120 bytes, with every record terminated by CRLF:

```csv
"position","node","hops","predecessor"
"0","0","0",""
"1","1","",""
"2","2","1","0"
"3","3","2","2"
"4","4","",""
```

Components mode permits cyclic groups and self-loops:

```sh
printf 'before,after\n0,2\n2,0\n1,3\n3,1\n3,0\n4,4\n5,1\n' | \
  target/stdlib-work/dependency_order --nodes 6 --components
```

It expects these 109 bytes, again with CRLF record terminators:

```csv
"node","component","position"
"0","0","3"
"1","1","2"
"2","0","3"
"3","1","2"
"4","2","0"
"5","3","1"
```

Component 2 is isolated and ready first. Component 3 must precede component 1,
which must precede component 0. The rows still follow original node IDs.

## CLI

| Option | Meaning |
| --- | --- |
| `--nodes N`, `-n N` | Required node count, 0..4096 |
| `--source S`, `-s S` | Optional source node, in `[0,N)`; incompatible with components mode |
| `--components`, `-C` | Report strong components and their dependency positions |
| `--help`, `-h` | Help, allowing otherwise valid options and requiring no stdin |

CLI numbers are 1..64 ASCII decimal bytes. Leading zeros are allowed; signs,
whitespace, prefixes, non-ASCII digits and overflow are errors. Capture admits
at most 24 arguments and 1024 total bytes. Duplicate options, including aliases
and repeated help in a short group, are errors. There are no operands. The
canonical `ext::cli` parser accepts attached values, exact long names and a
`--` terminator; operands following the terminator still fail.

Help permits omitted N. A supplied N still has to be in range, and a supplied S
is always bounded to 0..4095. When both are supplied, S must be less than N,
including in help mode. Components mode and source mode cannot be combined,
even with help. Repeated components flags, including mixed long/short aliases,
are errors. Ordinary execution requires N; N zero permits no source. All CLI
checks finish before input collection, and argument storage is
destroyed before reading or help publication.

## CSV and graph semantics

The first record must contain exactly `before,after`, in that order and case.
Every subsequent record has exactly two unsigned ASCII decimal endpoint IDs
in `[0,N)`. Leading zeros and ordinary CSV quoting are allowed. No whitespace,
sign, BOM removal or numeric normalization is added by the application.
Empty input is invalid; a header-only input describes a graph with no edges.

The existing strict CSV dialect accepts LF/CRLF and a final unterminated
record. UTF-8 is validated; quoted CR/LF remains field data and consequently
fails the endpoint decimal grammar. NUL, TAB, other prohibited ASCII controls
and DEL fail CSV validation. Each field has at most 128 decoded bytes, each
record at most 256 decoded field bytes, and the record cap is 65537 including
the header. Commas, quote syntax and terminators do not spend the decoded-byte
record budget. Blank records, missing/extra fields and malformed quotes fail.

An edge `u,v` requires u to precede v. Node IDs are dense and zero-based;
isolated nodes remain in the result. `ext::graph::from_edges` copies and
canonicalizes integer edges, removing duplicates idempotently. The raw edge
cap applies before deduplication. Self-loops remain and cause cycle rejection
in default mode.

In default mode, `ext::graph_algorithms::topological_order` chooses the smallest
currently ready ID using the canonical graph. A cycle anywhere returns 2 with empty stdout,
including a component unreachable from an optional source. No partial order
or cycle witness is published. Empty graphs without a source print the header
only. The program computes the complete order before optional BFS or staging.

With `--source`, public `bfs` supplies edge-count distances and predecessors.
FIFO discovery visits each node's ascending neighbors and keeps its first
predecessor. Parent IDs need not be the smallest among all shortest-path
parents. The source has hops zero and empty predecessor; unreachable nodes
have both fields empty. Without `--source`, both fields are empty for every
node. Rows stay in topological order, independently of BFS discovery order.

Default output has the four-column header `position,node,hops,predecessor`.
Positions start at zero.

With `--components`, public `condensation` groups two nodes together exactly
when each can reach the other, including zero-length paths. Component IDs are
dense and follow the smallest original member in ascending order. An isolated
node is a singleton; a self-loop creates no extra component. The condensed
graph has one edge per distinct dependency between different components and
has no self-loops. Public `topological_order` then gives the lexicographically
smallest order of component IDs. A component ID does not by itself imply a
dependency position.

Components output has the three-column header `node,component,position` and
one row per original node, in ascending original node order. All nodes in one
component share its zero-based position in the condensed order. No BFS columns
are present. Empty graphs print this header only. The complete component map
and order are computed before rendering.

The canonical CSV writer quotes every field, including empty fields, and
terminates records with CRLF. Numeric fields use canonical unsigned decimal.
No extra status text or diagnostic goes to stdout.

## Storage, work and publication

Public `alloc::io::read_to_end` collects binary stdin through actual EOF with
4 MiB and 16384-call limits. Interrupted, EOF and the one-byte cap probe spend
calls. An extra cap byte rejects the input; failure destroys the retained
ReadFailure prefix. Collection precedes CSV validation, so input I/O/storage/
limit failures occur before a malformed-CSV result.

One `ext::csv::Decoder` feeds the collected input and reuses its byte/field
capacities. Each ready record is validated and copied into plain Edge values
before the next feed invalidates its fields. No whole Table or per-row record
owner is retained. The decoder is destroyed after parsing, then the complete
input owner is destroyed before graph construction.

The graph owns its canonical integer adjacency; algorithms borrow that owner.
The topological result and optional BFS result each have one cleanup authority.
Rendering holds only `Option<&BfsPaths>` while the actual BFS owner remains live
in its branch. It calls public distance/predecessor queries for each output
node. No owner is fabricated, copied for mutation or returned through an expired
borrow. In components mode, a Condensation owner holds its independent graph
and node mapping. A `Vec<i32>` maps each component ID to its topological
position, giving linear output lookup. The temporary topological order is
destroyed once this position vector is filled; rendering borrows the
condensation and positions. Both owners are destroyed on success and ordinary
failure before the original graph is released.

One reusable CSV Record and `alloc::io::Buffer` stage the entire result. Graph,
order, paths, condensation, component positions, raw edges and Record are
explicitly destroyed before the first stdout write. Only staged output remains
live during publication and is
destroyed afterward on success or failure. Every earlier failure releases all
acquired owners before the diagnostic. A failed private CSV write abandons the
whole staged result and is never replayed.

| Resource | Bound |
| --- | ---: |
| Nodes / raw edges | 4096 / 65536 |
| Collected input / Read delegations | 4,194,304 bytes / 16384 |
| CSV records, including header | 65537 |
| Fields per input record | Exactly 2 |
| Decoded field / record bytes | 128 / 256 |
| Graph work admission | 100,000,000 per library call |
| Staged output / private writer calls | 1,048,576 bytes / 8192 |
| Data stdout attempts, including Interrupted | 2048 total |
| Help stdout attempts, including Interrupted | 64 total |
| Diagnostic stderr attempts | At most 8 |

Graph construction/validation and algorithms use the fixed limits from the
[directed-graph plan](library-directed-graph-plan.md) and
[strong-components plan](library-graph-components-plan.md). Work units are
weighted size estimates, not instruction counts or a shared elapsed-time budget. The
bounded node and raw-edge caps also bound parsing, scanning and rendering.
The staged byte/call bounds are independent admission policies; valid output
for 4096 nodes is smaller than 1 MiB. The current native Descriptor stages at
most 1024 host bytes per transfer, so admitted output fits the 2048-attempt
budget in failure-free execution.

Output advances only by confirmed positive counts. Interrupted retries consume
attempts; zero, invalid counts, other errors or exhaustion stop without replay.
Output failure can leave a confirmed prefix of the complete staged CSV; there
is no rollback. Attempt limits impose no wall-clock timeout on blocking I/O.
Standard descriptors are borrowed and never closed.

## Statuses and acceptance

| Exit | Meaning |
| ---: | --- |
| 0 | Complete node/component report, or help written |
| 2 | Invalid CLI/CSV/endpoints, default-mode cycle, byte/call or graph/staging admission limit |
| 3 | Input I/O or argument-capture host failure |
| 4 | Argument, input, CSV, edge, graph, algorithm or staging allocation failure |
| 5 | Data/help output or SIGPIPE-policy failure |
| 6 | Unexpected storage, provider, graph or formatting contract failure |

SIGPIPE is ignored before argument capture. Setup failure returns 5 silently.
Other errors attempt the exact 35-byte line
`dependency_order: operation failed\n`, after cleanup, with at most eight
stderr attempts. Diagnostic failure preserves its primary status. Successful
runs have empty stderr. Current help is exactly 1023 bytes. The default header
is 40 bytes; the components header is 31.

### Current components acceptance

All **312 distinct application cases** passed on native Linux x86_64 CPU
output from the GPU compiler: 183 retained cases and 129 new components cases.
Each group ran in a separate command with one passing Rust test, zero failures
and three filtered tests.

| Group | Cases | Runtime | Receipt in `target/stdlib-work/` | Retained evidence |
| --- | ---: | ---: | --- | --- |
| Model | 166 | 11.23 s | `graph-components-app-model-accepted.log` | `/tmp/dependency-order-model-y67ubu8p` |
| Rejection | 52 | 9.66 s | `graph-components-app-rejection-first.log` | `/tmp/dependency-order-rejection-jteoe69x` |
| CLI | 58 | 8.26 s | `graph-components-app-cli-first.log` | `/tmp/dependency-order-cli-7era8xhv` |
| I/O | 36 | 9.48 s | `graph-components-app-io-first.log` | `/tmp/dependency-order-io-x54xqwat` |

The components oracle derives groups from mutual reachability and enumerates
component permutations for the smallest valid order. It checks all 64
loopless three-node graphs, disconnected and nested cycles, self-loops,
active cross-links, edges into completed components, duplicates/shuffles,
component-position ties, four 4096-node shapes and valid exact 4 MiB input.
Rejection and CLI additions cover input/admission failures, aliases, duplicate
mode flags, source conflicts in either order and help bypass. The exact
1023-byte help is checked. Existing default output, cycle failures and BFS
behavior remain in the accepted corpus.

The components I/O baseline has 96 nodes in 48 two-node cycles connected by a
reverse component chain. Its trace binds the SCC workspaces, condensed graph,
topological result and component positions by allocation size, phase and
lifetime. Nine reached allocation failures cover returned labels, final SCC
workspace, pair reservation and sorted copy, condensed offsets and targets,
topological result, component positions and late output growth. Each returns
4 with no data, releases every successful mapping at its observed address and
extent, and attempts no later allocation. Additional components I/O cases
exercise read/write interruptions, later read and EOF errors, real EPIPE,
a genuine 1024-byte output prefix followed by EIO, and the write-attempt cap.
These are finite fault and lifetime observations; compact attempt summaries
establish counts without a full release ledger. Details are in the
[fixture guide](../tests/fixtures/extended_execution/dependency_order/README.md).

The first model command stopped at parsing an unsupported application
`else if` before native execution. Rewriting that branch with nested `else`
and `if` preserved its contract; the accepted model receipt above uses the
corrected source. No compiler change was needed.

The exact standalone compile above exited 0 with no diagnostic output
(`graph-components-app-build-command.log`). Both documented shell pipelines
then exited 0 with empty stderr. All 120 default-mode bytes and all 109
components-mode bytes matched the literal expected CRLF output
(`graph-components-app-examples.log`). The outputs are retained as
`target/stdlib-work/graph-components-app-default-example.csv` and
`target/stdlib-work/graph-components-app-components-example.csv`. These
examples overlap the functional corpus and add no distinct case count.

Current accepted producer identities (SHA-256):

- Application: `3cae8b5ff6fe4d7cbd495d7b54155d33a1c941b8e97c4abdd6c3ab5d0a494a3c`.
- Oracle: `03cc97f2a37ea7dc794ab31b04303d1539a368c2728f3a71fd82661b4ac53597`.
- `ext::graph`: `d8e5216346edfc3bcf554d17526d4e05ad71b0843a29a51185442085b36b074c`.
- `ext::graph_algorithms`: `1f1cf7cd4920f05567d53283628d1b119bf93f3d108255ad354522d61267d8a6`.

### Historical default-mode acceptance

The previous program, before components mode and the help change, passed
**183 distinct cases** on native Linux x86_64 CPU output from the
GPU compiler. The four registered groups ran in separate commands; each
receipt has one passing Rust test and three filtered tests.

| Group | Cases | Runtime | Receipt in `target/stdlib-work/` | Retained evidence |
| --- | ---: | ---: | --- | --- |
| Model | 83 | 9.12 s | `directed-graph-app-model-first.log` | `/tmp/dependency-order-model-djs5kd32` |
| Rejection | 40 | 9.65 s | `directed-graph-app-rejection-first.log` | `/tmp/dependency-order-rejection-9cfylhoz` |
| CLI | 41 | 8.96 s | `directed-graph-app-cli-first.log` | `/tmp/dependency-order-cli-1n49y4da` |
| I/O | 19 | 9.47 s | `directed-graph-app-io-first.log` | `/tmp/dependency-order-io-t70is69_` |

The independent oracle enumerates all vertex permutations for tiny graph
orders and uses dense all-pairs hop distances with lexicographic path layers
for predecessor expectations. Coverage includes all 64 loopless three-node
graphs, a first-discovery parent that differs from the smallest predecessor,
duplicates/shuffles, four 4096-node shapes and valid exact 4 MiB input with
65536 raw duplicate edges. Separate rejection traces verify the actual
one-byte EOF probe at the cap and consumption of one excess byte. The CLI
group checks exact help, option validation and input bypass.

The inspected I/O baseline retires both argv mappings before collecting all
6474 input bytes and EOF. It constructs a 96-node chain from 950 raw edges,
then publishes exactly 2014 CSV bytes. Only its 2560-byte output mapping is
live at the first stdout write; that owner is released afterward. Seven
selected, reached allocation failures cover both argv owners, initial input,
graph offsets, the topological result, partial BFS parents and late output
growth. Every case returns 4 with empty stdout and matching releases of
observed successful mappings. The BFS-parent failure also releases the
already allocated distances and the caller's order and graph. This is finite
fault evidence, not an exhaustive allocation or lifetime proof.

Actual directory stdin and closed data/help stdout exercise input errors and
EPIPE. Read/write interruptions preserve the exact result. Failure on the
required EOF call publishes nothing. A genuine first 1024-byte stdout transfer
followed by second-write EIO leaves exactly that confirmed prefix, returns 5
and releases staged output before the diagnostic. Compact interruption
summaries separately establish the 16384-read and 2048-data-write attempt
limits; they do not provide a complete release ledger. Argument-capture host
failure, internal-error injection and arbitrary broken providers are outside
this corpus. The [fixture guide](../tests/fixtures/extended_execution/dependency_order/README.md)
records the exact finite profiles and commands.

The compiler CLI build passed in 49.98 seconds
(`directed-graph-compiler-build.log`). The exact standalone compile above then
exited 0 (`directed-graph-app-build-command.log`), and the documented pipeline
exited 0 with all 120 literal CRLF bytes verified in
`target/stdlib-work/directed-graph-app-example.csv`. This example overlaps the
registered functional corpus and adds no distinct case count.

Historical accepted producer identities (SHA-256):

- Application: `03796591ff86a0edd9ba6108888c52e0954b5ea5e63ae7d971700b818eb64f79`.
- Oracle: `0a34e6c2b53cdb453197dc64ab507d49811e095dc1b8ea26d258b60b4c1f1146`.
- `ext::graph`: `d8e5216346edfc3bcf554d17526d4e05ad71b0843a29a51185442085b36b074c`.
- `ext::graph_algorithms`: `57ba3bcf02b04da8d6aa0fe0e1b387a7cb25cf1d0fc735770097e56df7bdadce`.

Rust driver formatting followed runtime acceptance; it changed no producer or
oracle behavior. Other targets, user-program GPU execution, exhaustive
failures, automatic lifetime enforcement, general alias safety, leak freedom
and formal proofs need separate evidence. Production is entirely Lanius and
adds no compiler, ABI, protected vector, host service, Rust/Python library
implementation, JSON transport, Wasm dependency or sensitive cryptography.
