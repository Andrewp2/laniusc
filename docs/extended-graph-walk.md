# Weighted directed graph walks

`sample_programs/library/graph_walk.lani` reads weighted directed edges, builds
a sparse transition matrix and advances a unit mass from a chosen source:

```sh
graph-walk --nodes N [--steps K] [--source S] [--help]
printf 'source,target,weight\n0,1,1\n0,2,3\n' | graph-walk --nodes 3
```

The example has masses 0, 0.25 and 0.75 after one step. Output contains every
node, including nodes with zero mass, ordered by node number.

## Input and CLI

`--nodes` is required and ranges from 1 through 4096. `--steps` ranges from 0
through 1000 and defaults to 1. `--source` defaults to 0 and must be less than
nodes. Short aliases are `-n`, `-k`, `-s` and `-h`. Integer arguments are
nonempty ASCII decimal digits without signs or whitespace; leading zeros are
allowed. All duplicate options are rejected, including different aliases and
short clusters. Positional operands are rejected.

Help validates supplied arguments and bypasses stdin and the required nodes
option. When nodes is supplied with help, source must still be in range for
that node count. Without nodes, a supplied help source must be at most 4095.

Input has the exact case-sensitive CSV header `source,target,weight`. Quoting
around header names is allowed. Every following record has exactly three
fields: zero-based source and target integers in range, and a finite binary64
weight greater than or equal to zero. Signed zero weights are allowed. CSV
quoting, CRLF/LF endings and numeric parsing use existing library modules.
Malformed CSV, invalid UTF-8, unsupported controls and invalid numbers anywhere
in input are rejected, including edges unreachable from the chosen source.
The decimal float parser may round a sufficiently small magnitude to zero;
that is a zero input weight for this binary64 application.

## Sparse composition and numerical profile

The application stores triplets in original input order, assembles canonical
CSR and coalesces duplicate coordinates in that order. Exact-zero coalesced
entries disappear. It computes outgoing row sums using a real sparse matvec
with a vector of ones. Every outgoing weight is divided directly by its row
sum; the implementation does not form a reciprocal, which could overflow for
a valid tiny positive row. A row with no logical outgoing entries receives a
self-loop of weight one.

The resulting sparse transition matrix is transposed. A source vector starts
with mass one at the selected node and zero elsewhere; each step computes a
new owned sparse matvec result and releases the previous vector. Thus each
step distributes a node's mass among its outgoing neighbors, while a dangling
node retains its mass. Repeated edges contribute their combined weight.
The actual production composition is:

```text
CSV -> triplets -> CSR -> matvec(ones) -> normalized triplets -> CSR
    -> transpose -> repeated matvec -> staged CSV
```

There is no production dense N-by-N matrix. CSR views borrow stable owners;
all intermediate owners remain live through their last use and are explicitly
destroyed. Returned matvec owners are installed only after the previous mass
owner is released. Triplets, input, argument storage and output storage also
have explicit cleanup on returned paths. This is an implementation contract,
not a leak-freedom proof.

Coalescing, increasing-column row sums, normalization and matvec use ordinary
binary64 arithmetic. Nonfinite intermediate sums/products are numerical
failures. Gradual underflow remains IEEE behavior: an extremely small
normalized probability or later mass can round to zero. Rounding may make a
row's stored probabilities or the final total differ slightly from one.
There is no exact conservation or uniform accuracy guarantee. Even zero
steps validates and normalizes the full graph before returning the source
unit vector; malformed or overflowing edges still fail.

## Output, bounds and failures

Output is fully quoted CRLF CSV with header `node,mass`, followed by exactly
N records. Node numbers are increasing and each mass is finite and
nonnegative. All input, graph construction, iterations and CSV formatting
finish in an independent buffer before the first stdout write. Input,
allocation or numerical failure cannot publish a CSV prefix; an stdout error
can leave a confirmed written prefix.

| Resource | Bound |
| --- | ---: |
| Raw stdin bytes | 4194304 (4 MiB) |
| Raw data edges / CSV records including header | 65536 / 65537 |
| Fields per record / decoded bytes per field | 3 / 128 |
| Decoded bytes per record | 384 |
| Nodes / steps | 4096 / 1000 |
| Sparse operation entry cap including dangling self-loops | 69632 |
| Per-library-operation work estimate cap | 100000000 |
| Iteration admission | `K * (N + transition_nnz + 1) <= 100000000` |
| Independent staged output | 1048576 bytes |
| stdin / CSV staging / stdout attempts | 16384 / 65536 / 8192 |
| Diagnostic attempts | 8 |
| Captured arguments / total argument bytes | 24 / 1024 |

The iteration estimate is admitted using division before any multiplication,
so its arithmetic cannot wrap. These work estimates are logical phase bounds,
not CPU instruction counts or wall-clock deadlines. The other fixed caps make
the current iteration admission conservative. An excess-byte probe
separates exact-cap EOF from oversized input. EINTR retries spend the relevant
I/O budget; other errors, including WouldBlock, terminate. Blocking descriptors
have no whole-program wall-clock deadline.

| Exit | Meaning |
| ---: | --- |
| 0 | Completed node/mass output or help |
| 2 | Invalid CLI/schema/CSV/number/range or resource limit |
| 3 | stdin I/O error or invalid input transfer count |
| 4 | Reported allocation failure |
| 5 | stdout error/call cap or SIGPIPE setup failure |
| 6 | Numerical construction, row-sum, iteration or formatting failure |

SIGPIPE is ignored before I/O. A setup failure returns 5 before diagnostics;
later failures attempt `graph-walk: operation failed\n` on stderr. A failed
diagnostic preserves the primary status.

## Target and verification

The verified executable target is native Linux x86_64 emitted by the GPU
compiler. The application performs CPU graph computation and native I/O;
device-side GPU graph execution is outside this receipt. Production is entirely
Lanius using existing CSV, float, CLI and native stream facilities plus the
sparse modules. No C/Rust/Python library implementation, JSON transport or Wasm
dependency is added.

The registered driver `tests/extended_graph_walk_execution.rs` compiled the
final application through the GPU compiler, passed the shared strict ELF
checker and passed all four tests on 2026-10-28. Its test-only oracle
independently materializes small dense transitions and performs exact Fraction
walks. Large admission cases use independently known unit-mass results. The
accepted groups are model 32, rejection 33, CLI 38 and I/O 10: 113 finite
native cases. Runtime took 16.31 seconds; receipt:
`target/stdlib-work/graph-walk-runtime-module-import.log`.
Nine CPU-only controls passed separately. Accepted evidence directories are:

- Model: `/tmp/graph-walk-model-79k_i3xy`.
- Rejection: `/tmp/graph-walk-rejection-t_tbsk3p`.
- CLI: `/tmp/graph-walk-cli-mxbirxd3`.
- I/O: `/tmp/graph-walk-io-lqpbkfer`.

Executed source SHA-256:
`a5ef4646d9168ff460589bc7058425a1666485e26b142adb53be8c91ad2756b5`.
Oracle SHA-256:
`cb68606dccfda6bf8a988963728c46bf1108fb8d8f0b6be8ad215ea9baa4131d`.
The fixture guide gives tolerances, reached faults, commands and evidence scope:
`tests/fixtures/stdlib_execution/graph_walk/README.md`. No separate direct-run
ELF hash, exhaustive numerical guarantee or leak proof is claimed.

### Import limitation exposed during compilation

The initial selective `core::slice::view` import collided with the sparse
module's `view` and reported `LNC0027`. A narrow explicitly typed reduction
reports `LNC0006`; its qualified control compiles and executes successfully.
The accepted application imports `core::slice` and fully qualifies its slice
view calls. Module import is required for those qualified calls; simply
removing the item import leaves the function unavailable.

The [item-import priority reduction](../tests/fixtures/stdlib_compiler_state/item_import_priority/README.md)
records the failing form, executed qualified control and receipts. Compiler
repair remains separate; this application increment changes no compiler, ABI
or proof source.
