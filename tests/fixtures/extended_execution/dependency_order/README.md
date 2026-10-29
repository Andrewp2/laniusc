# Dependency ordering application fixture

CLI is `dependency_order --nodes N [--source S]`, with `-n`/`-s` aliases and
`--help`/`-h`. N is 0..4096; a supplied source must be in 0..N. Numeric tokens
are unsigned ASCII decimal, at most 64 bytes, with leading zeros allowed.
Duplicates and operands are errors. Help validates supplied options, waives
the required node option and bypasses stdin. Captured argv is limited to
24 arguments/1024 total bytes.

Input is CSV with exact header `before,after`, followed by unsigned decimal
node endpoints. Leading zeros, quoted fields, LF/CRLF and an unterminated
final record are accepted. Empty input is invalid; a header-only graph retains
isolated nodes. Limits are 4 MiB input, 16384 actual Read calls, 65536 raw
edges, 128 decoded bytes per field and 256 per record. Duplicate edges collapse
idempotently, while self-loops remain cycles. The app uses the public owned
reader and canonical CSV decoder, without a second production input loop.

Output is fully quoted CRLF CSV with columns
`position,node,hops,predecessor`, in the lexicographically smallest dependency
order. Positions are zero-based. Without source, the last two fields are
empty. With source, unreachable vertices have two empty fields; the source
has hops 0 and no predecessor. Every cycle returns 2 with empty stdout.

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

| Group | Cases | Scope |
| --- | ---: | --- |
| model | 83 | All 64 loopless three-node graphs, empty/isolated/disconnected vertices, parent and ready-heap ties, duplicates/shuffles, quoting/unterminated CSV, exact field/record limits, four 4096-node shapes and valid 4 MiB/65536-edge input |
| rejection | 40 | CSV schema/quoting/encoding/controls, endpoint spelling/range, field overflow, self-loops/disconnected cycles, zero-node edge, raw edge cap before deduplication and actual raw byte cap probes |
| cli | 41 | Required options, short aliases, duplicates, modes/operands, numeric spelling/range/token bounds, snapshot argument/byte caps, validated help and input bypass |
| io | 19 | Baseline, seven selected reached owner ENOMEM sites, directory stdin, read/write EINTR, read/EOF EIO, closed data/help stdout, genuine output prefix, signal failure and interruption budgets |

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

## Acceptance

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
