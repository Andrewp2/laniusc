# Dependency ordering application fixture

CLI is `dependency_order --nodes N [--source S | --components]`, with
`-n`/`-s`/`-C` aliases and `--help`/`-h`. N is 0..4096; a supplied source
must be in `[0,N)`. Components mode cannot be combined with source, including
on a help invocation. Duplicate mode flags reject before reading stdin. Numeric tokens
are unsigned ASCII decimal, at most 64 bytes, with leading zeros allowed.
Duplicates and operands are errors. Help validates supplied options, waives
the required node option and bypasses stdin. Captured argv is limited to
24 arguments/1024 total bytes.

Input is CSV with exact header `before,after`, followed by unsigned decimal
node endpoints. Leading zeros, quoted fields, LF/CRLF and an unterminated
final record are accepted. Empty input is invalid; a header-only graph retains
isolated nodes. Limits are 4 MiB input, 16384 actual Read calls, 65536 raw
edges, 128 decoded bytes per field and 256 per record. Duplicate edges collapse
idempotently, while self-loops remain part of the graph. The app uses the public owned
reader and canonical CSV decoder, without a second production input loop.

Output is fully quoted CRLF CSV with columns
`position,node,hops,predecessor`, in the lexicographically smallest dependency
order. Positions are zero-based. Without source, the last two fields are
empty. With source, unreachable vertices have two empty fields; the source
has hops 0 and no predecessor. Every cycle in the default mode returns 2
with empty stdout.

Components mode accepts cycles and emits `node,component,position`, also fully
quoted CRLF CSV, in ascending original node order. Component IDs are dense in
ascending smallest-member order; position is the component's index in the
lexicographically smallest topological order of the condensation DAG. Empty
graphs emit only this header. Self-loops and isolated vertices remain singleton
components unless another vertex is mutually reachable.

## Independent models

For small graphs, the oracle enumerates every vertex permutation and picks
the first one satisfying all edge constraints. It does not reproduce the
production indegree/ready-heap traversal. All 64 loopless directed three-node
graphs execute: 25 are DAGs and 39 must reject cycles. Explicit self-loop and
disconnected-cycle cases extend that coverage.

Shortest-hop distances use dense all-pairs relaxation. Distance layers then
choose the lexicographically first complete shortest vertex sequence, yielding
the sorted-neighbor FIFO discovery parent without implementing a queue. A
literal seven-node control requires predecessor 5 instead of smaller candidate
3, catching a mistaken smallest-predecessor policy. Duplicate/shuffled inputs
must preserve the exact result. Large chain/star/isolated/reverse-chain cases
use independently derived closed-form orders, distances and parents.

Components use an independent dense Boolean transitive closure. Mutual
reachability partitions vertices; scanning original nodes defines canonical
component IDs. The oracle enumerates component permutations to choose the
first valid topological order. It does not reproduce DFS, lowlinks, active
stacks, SCC pop order or the production ready heap. Literal controls include
component IDs whose topological positions differ, plus shuffled duplicates
and four intentionally corrupted serializations. Large components cases have
closed-form expected partitions and positions.

| Group | Cases | Scope |
| --- | ---: | --- |
| model | 166 | Original 83 cases plus 83 components cases: all 64 loopless three-node graphs; empty, isolated, self-loop, cyclic, nested/cross-link/completed-target and component-order ties; duplicate/shuffled and CSV spelling cases; four 4096-node shapes; exact 4 MiB/65536-edge input |
| rejection | 52 | Original 40 cases plus 12 components CSV/endpoint/field/node/edge/raw-byte admission cases |
| cli | 58 | Original 41 cases plus 17 components cases covering aliases and clusters, duplicates, source conflicts in either order and with help, nodes bounds, operands and help bypass |
| io | 36 | Original 19 cases plus one components baseline, nine selected reached allocation failures and seven components read/write/retry/prefix/attempt-limit cases |

All 183 earlier native process cases remain present. There are 129 added
components cases, for 312 accepted distinct native process cases. The two I/O
baselines are counted cases; site discovery does not run a separate uncounted
calibration process. CPU controls and any standalone examples are separate
from these native counts.

The valid maximum-input fixture has header length 13, then 65535 padded
64-byte rows and one 51-byte row: exactly 4194304 bytes and 65536 duplicate
0-to-1 edges. The expected result is a two-node graph. Separate raw-cap traces
use malformed CSV so their input semantics can be observed without tracing
65536 parsing operations: at the cap, a one-byte request must return EOF;
one byte beyond it must be consumed and rejected. No data is published.

## Ownership and fault scope

The baseline has fully collected input before parsing/graph processing and
only the staged output owner at the first stdout write. Full selected traces
match each successful mmap with explicit munmap at the same address/requested
length, allowing address reuse after release. They reject stdin/other borrowed
descriptor closes and other allocation services. Diagnostic writes require all
owners retired. This is a finite observed ledger, not automatic lifetime or
exhaustive leak-freedom evidence.

Seven selected mmap failures cover both argv owners, initial input storage,
graph offsets, topological storage, partial BFS parents and late staged-output growth. Each
failure must be reached at the matching baseline ordinal/arguments, return 4,
release every obtained owner and publish nothing. They do not cover every
allocation site. Input EIO after a prefix or on the required EOF returns 3
without data. EINTR must retry to the exact result. Actual closed stdout
exercises EPIPE. A genuine first 1024-byte write followed by second-write EIO
must retain exactly that prefix and return 5; successful transfer counts are
never fabricated and the app needs no artificial output segmentation.

Compact summaries separately check 16384 read interruptions returning 2, and
2048 data-write interruptions plus one diagnostic returning 5. Those summaries
establish attempt counts without a complete owner ledger. Signal setup failure
returns 5 silently before argument capture. Argument-host failure, internal
error injection and arbitrary broken providers are outside this corpus.

The components I/O baseline uses 96 nodes grouped into 48 two-node cycles
with a reverse component chain and duplicated input edges. Expected labels
are `node / 2`; positions are `47 - component`. Its trace must identify all
six original-node SCC vectors, five workspace releases before the pair
reservation, the condensed pair staging and graph, topological buffers and
component-position vector. Original graph staging establishes the native
`Edge` byte width used for pair-buffer matches. Sizes, phase order and releases
must agree; an ambiguous graph-offset anchor is rejected. Every owner except
the final staged output must retire before its first stdout write.

Nine components ENOMEM cases select the returned label vector, final SCC
workspace, conservative edge-pair reservation, sorted pair copy, condensed
offsets and targets, topological result, component positions and late output
growth. Every fault must reach the baseline's complete mmap-argument prefix,
be marked as injected ENOMEM, return 4 with no data, release every successful
mapping and attempt no later allocation. These selected sites complement the
library resource fixture; they are not every application allocation site.
The new read/write cases check EINTR retry, later read EIO, required EOF EIO,
actual EPIPE, genuine 1024-byte output prefix then EIO, and the existing write
attempt ceiling. Full traces require address/extent cleanup before diagnostics;
compact attempt summaries do not establish a full owner ledger.

The driver compiles once per libtest process and requires an actual little-
endian ELF64 x86-64 executable plus the shared strict jump gate. The standalone
oracle also rejects non-ELF files. Every native child has a 15-second deadline;
each registered group has 85 seconds. Exact commands/input/output/status and
selected traces are retained.

```sh
python3 -B tests/fixtures/extended_execution/dependency_order/oracle.py controls
python3 -B tests/fixtures/extended_execution/dependency_order/oracle.py model PATH_TO_ELF
python3 -B tests/fixtures/extended_execution/dependency_order/oracle.py rejection PATH_TO_ELF
python3 -B tests/fixtures/extended_execution/dependency_order/oracle.py cli PATH_TO_ELF
python3 -B tests/fixtures/extended_execution/dependency_order/oracle.py io PATH_TO_ELF
```

## Components-mode acceptance

All four expanded groups passed separately on the frozen producer:
**312 distinct native Linux x86_64 cases**, comprising the retained 183 cases
and 129 components additions. Each receipt contains one passing Rust test,
zero failures and three filtered tests. The GPU compiler produced a strict
ELF64 x86-64 executable; the program ran on the CPU.

| Accepted group | Cases | Runtime | Receipt in `target/stdlib-work/` | Evidence |
| --- | ---: | ---: | --- | --- |
| model | 166 | 11.23 s | `graph-components-app-model-accepted.log` | `/tmp/dependency-order-model-y67ubu8p` |
| rejection | 52 | 9.66 s | `graph-components-app-rejection-first.log` | `/tmp/dependency-order-rejection-jteoe69x` |
| cli | 58 | 8.26 s | `graph-components-app-cli-first.log` | `/tmp/dependency-order-cli-7era8xhv` |
| io | 36 | 9.48 s | `graph-components-app-io-first.log` | `/tmp/dependency-order-io-x54xqwat` |

Accepted producer identities (SHA-256):

- Application: `3cae8b5ff6fe4d7cbd495d7b54155d33a1c941b8e97c4abdd6c3ab5d0a494a3c`.
- Oracle: `03cc97f2a37ea7dc794ab31b04303d1539a368c2728f3a71fd82661b4ac53597`.
- `ext::graph`: `d8e5216346edfc3bcf554d17526d4e05ad71b0843a29a51185442085b36b074c`.
- `ext::graph_algorithms`: `1f1cf7cd4920f05567d53283628d1b119bf93f3d108255ad354522d61267d8a6`.

The first model attempt failed during compilation because the new application
used unsupported `else if` syntax. It executed no native application cases.
Replacing that arm with nested `else { if ... }` preserved the intended CLI
behavior and the 1023-byte help text; the accepted model receipt above and all
subsequent groups use the repaired source. The diagnostic remains 35 bytes.

The components I/O baseline read 9734 bytes and EOF, then produced exactly
1517 output bytes. All 49 successful mmap allocations had matching explicit
munmap releases. The trace established a 16-byte native `Edge` width from the
original constructor's staging. It bound the six 384-byte SCC vectors, 2288-
and 752-byte pair buffers, 196-/188-byte condensed offsets/targets, and four
192-byte topological/position vectors. Only the final 1984-byte staged output
owner remained at the first stdout write; the two successful writes transferred
1024 and 493 bytes.

Nine reached ENOMEM cases selected mmap ordinals 25, 30, 31, 32, 33, 34, 35,
38 and 49. Every case returned 4 with empty stdout, matched the baseline mmap
argument prefix, made no later allocation and retired each successful owner.
The new output-prefix case transferred a real 1024 bytes before second-write
EIO, returned 5 and released staged output before its diagnostic. The compact
components write-attempt receipt recorded 2048 EINTR writes plus one successful
diagnostic; it is separate from the full owner-ledger evidence.

The oracle also passes host-only CPU controls for exact corpus counts,
mutual-reachability literals, component-position distinctions, duplicate
invariance and deliberately corrupted serializations. These controls and
standalone examples are not additional native cases in the 312-case count.
Standalone build/example acceptance belongs to the application guide.

## Historical default-mode acceptance

The following receipts refer to the previous frozen application and oracle,
before components mode. They retain the exact prior evidence and are not
current source identities.


CPU controls pass for literal output, cycle recognition, minimal ordering,
the tied-parent counterexample, duplicate invariance, graph/corpus counts,
exact help/diagnostic/header lengths and deliberately missing owner release.
All four registered groups passed separately on the frozen producer:
**183 distinct native Linux x86_64 cases**. Each receipt has one passing Rust
test, zero failures and three filtered tests. These are four separate commands,
not one combined four-test receipt.
The GPU compiler produced the strict-admitted ELF64 program; execution was on
the CPU.

| Accepted group | Cases | Runtime | Receipt in `target/stdlib-work/` | Evidence |
| --- | ---: | ---: | --- | --- |
| model | 83 | 9.12 s | `directed-graph-app-model-first.log` | `/tmp/dependency-order-model-djs5kd32` |
| rejection | 40 | 9.65 s | `directed-graph-app-rejection-first.log` | `/tmp/dependency-order-rejection-9cfylhoz` |
| cli | 41 | 8.96 s | `directed-graph-app-cli-first.log` | `/tmp/dependency-order-cli-1n49y4da` |
| io | 19 | 9.47 s | `directed-graph-app-io-first.log` | `/tmp/dependency-order-io-t70is69_` |

Producer identities (SHA-256):

- Application: `03796591ff86a0edd9ba6108888c52e0954b5ea5e63ae7d971700b818eb64f79`.
- Oracle: `0a34e6c2b53cdb453197dc64ab507d49811e095dc1b8ea26d258b60b4c1f1146`.
- `ext::graph`: `d8e5216346edfc3bcf554d17526d4e05ad71b0843a29a51185442085b36b074c`.
- `ext::graph_algorithms`: `57ba3bcf02b04da8d6aa0fe0e1b387a7cb25cf1d0fc735770097e56df7bdadce`.

The inspected I/O baseline releases its 160-byte and 18-byte argv mappings
before collection, reads all 6474 CSV bytes and EOF, then parses 950 repeated
edges into a 96-node chain. Its exact quoted output has 2014 bytes. Input,
raw edges, graph, ordering, BFS and CSV record owners retire before stdout;
only the 2560-byte staged-output mapping remains through the two writes and
is released afterward.

Seven selected allocation failures reach ordinals 1/2/3/21/23/27/39 at the
matching baseline arguments: argv owners, initial input, 388-byte graph
offsets, 384-byte topological result, 384-byte BFS parents and 2560-byte
output growth. Each returns 4 with empty stdout and matching explicit owner
releases. The BFS-parent fault releases its previously allocated distances
and the caller's complete ordering and graph. The late output fault likewise
retires graph/path/record/raw-edge state and the prior staged prefix without
publishing it. These seven reached sites are not every allocation.

Actual directory stdin and closed data/help stdout return the expected
input/output statuses. Interrupted reads and writes preserve the exact result.
A fault on the EOF call after all 6474 input bytes returns 3 with empty stdout.
The output-prefix receipt has a genuine first write of 1024 bytes, then EIO on
the second write; it returns 5, retains precisely the 1024-byte prefix and
releases staged output before the diagnostic. No positive count is forged.
The compact receipts show 16384 interrupted reads, or 2048 interrupted writes
and one successful diagnostic. Their scope is attempt counts, separately
from the complete selected owner ledgers.

The model receipt includes all 64 three-node graphs, the four 4096-node shapes
and the valid exact 4 MiB/65536-edge case. The separate rejection receipt
confirms byte-limit probes with real EOF and one consumed excess byte, plus
all listed malformed/cyclic cases. The CLI receipt checks the exact 776-byte
help and input bypass. This does not independently establish the standalone
build/example command, which is separate from this integration driver.

GPU device execution, other targets, formal verification, automatic lifetime
guarantees and exhaustive host/allocation faults remain unclaimed. Driver
hashes are omitted because root formats Rust drivers after runtime acceptance.
