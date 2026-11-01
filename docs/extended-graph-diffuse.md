# Sparse graph diffusion

`sample_programs/library/graph_diffuse.lani` solves
`(I + lambda*L)x = b` for an undirected weighted graph using the sparse
Jacobi-preconditioned conjugate-gradient library:

```sh
graph-diffuse --nodes N [--lambda V] [--iterations K] [--rtol V] [--atol V] [--help]
printf 'kind,source,target,value\nedge,0,1,1\nsource,0,,1\n' | graph-diffuse --nodes 2
```

With default parameters, the example's exact mathematical solution is
x=(2/3,1/3). The emitted values are finite binary64 approximations satisfying
the library's fresh-residual stopping test. Output contains every node in
increasing order, including zeros.

## CLI and CSV schema

`--nodes` is required and ranges from 1 through 4096. `--iterations` ranges
from 0 through 1000 and defaults to 100. `--lambda` defaults to 1, `--rtol` to
1e-10 and `--atol` to zero. These three values must parse to finite nonnegative
binary64 numbers; signed zero is allowed. Numeric CLI fields are bounded to
128 bytes. Integer options accept ASCII decimal digits without signs or
whitespace; leading zeros are allowed.

Short aliases are `-n N`, `-k K` and `-h`. Lambda and tolerance options have
only long spellings. All duplicates are rejected, including different aliases
and repeated help in short clusters. Positional operands are rejected. Help
validates every supplied option, then bypasses stdin and the required nodes
option.

The exact case-sensitive header is `kind,source,target,value`. Every subsequent
record has exactly four fields:

| Kind | Source | Target | Value |
| --- | --- | --- | --- |
| `edge` | Node u | Node v | Finite nonnegative weight |
| `source` | Node u | Empty field | Finite signed source value |

Node numbers are zero-based ASCII decimal integers below N. CSV quoting around
fields is allowed, including a quoted empty source target. Missing node sources
are zero. Repeated source records add their parsed values in original input
order. Every edge record is undirected; a second record with reversed endpoints
contributes another edge weight rather than replacing the first.

The existing UTF-8 CSV dialect permits LF or CRLF endings. Empty input, a BOM
or altered header, blank records, invalid UTF-8, unsupported controls, unknown
kinds and malformed numbers are errors. Header-only input is valid and supplies
a zero source vector. All rows are parsed and schema-validated into plain
records before graph or source arithmetic begins. Invalid disconnected rows
and invalid self-loops therefore still reject. Decimal underflow to binary64
zero follows the existing parser's documented behavior.

## Assembly and sparse solve

The program initializes one identity diagonal triplet per node and a zero
source vector. It then processes validated records in original input order:

- A non-self edge computes t=`lambda*weight`, requiring a finite result. A
  nonzero t appends +t to diagonals (u,u) and (v,v), then -t to off-diagonals
  (u,v) and (v,u), in that order. A zero t contributes no triplets.
- A self-loop contributes zero after its raw weight has been validated. It
  performs no scaling product, so an irrelevant `lambda*weight` overflow on a
  valid self-loop is not a numerical failure.
- A source record adds to its node's current value, requiring each intermediate
  sum to be finite. Later cancellation cannot rescue a prior overflow.

The identity entries precede all edge contributions when coordinate duplicates
coalesce. Every edge is scaled before assembly; the program does not first
sum raw edge weights and then scale. Canonical CSR construction aggregates
these triplets in their original order. Corresponding symmetric off-diagonal
entries receive the same sequence of values.

The actual production composition is:

```text
CSV -> validated plain records -> symmetric triplets + source vector
    -> canonical CSR -> sparse_cg::solve(Jacobi, initial zero)
    -> converged solution -> staged CSV
```

There is no application CG implementation or dense matrix conversion. The
solver receives the configured full iteration allowance, relative/absolute
tolerances and fixed sparse limits. It computes a fresh residual `b-Ax`
initially and after every update. The application accepts only `Stop::Converged`
with finite reported residual and RHS norms. `Stop::IterationLimit` is an
explicit numerical failure for this CLI, even though the library returns its
last iterate as a valid owned result.

Convergence means the fresh residual norm is at most atol, or, for positive
rtol and RHS norm, its ratio to the RHS norm is at most rtol. A zero iteration
limit can succeed when the initial zero vector already meets this test; it
otherwise fails without output. Large tolerances may intentionally accept a
coarse or initial approximation. Full work admission and input/diagonal checks
still occur before an initially converged result is accepted.

In exact arithmetic, nonnegative lambda and weights give a positive definite
`I + lambda*L`. Binary64 construction can overflow or round away the identity
shift for huge coefficients, producing a singular represented matrix. Even a
finite SPD problem can encounter ordinary dot-product overflow or underflow
inside CG. The program therefore makes no universal SPD or convergence claim
for its assembled floating-point matrix. Nonfinite assembly, curvature errors,
breakdown and nonconvergence are explicit failures rather than approximate
successes. See [the sparse CG contract](library-sparse-cg-plan.md) for operation
order, fresh/recursive residual handling and restart behavior.

## Ownership, bounds and output

The decoded CSV table owns its fields only during validation; plain records
retain no field views. Raw input is then destroyed. Triplets and the source
vector remain live through CSR assembly. CSR, source and initial vectors remain
immutable through the solver call and are released afterward. A returned
solution owns its independent vector and is destroyed after formatting or
rejection. Records, output record, captured arguments and the independent
output buffer also have explicit cleanup on returned paths. These are manual
ownership contracts, not a lifetime or leak-freedom proof.

Output is fully quoted CRLF CSV with header `node,value` and exactly N data
records. Signed values and zero are valid. Every value must be finite. The
whole solve and formatting finish before the first stdout write; input,
resource, allocation, numerical and nonconvergence failures publish no prefix.
An stdout failure can leave a confirmed written prefix.

| Resource | Bound |
| --- | ---: |
| Raw stdin bytes | 4194304 (4 MiB) |
| Data records / CSV records including header | 65536 / 65537 |
| Fields per record / decoded bytes per field | 4 / 128 |
| Decoded bytes per record | 512 |
| Nodes / requested iterations | 4096 / 1000 |
| Assembled triplets / sparse stored-entry cap | 327680 / 327680 |
| Sparse operation and CG allowance work cap | 100000000 |
| Independent staged output | 1048576 bytes (1 MiB) |
| stdin / CSV staging / stdout attempts | 16384 / 65536 / 8192 |
| Diagnostic attempts | 8 |
| Captured arguments / total argument bytes | 24 / 1024 |

Decoded-record limits exclude commas, quotes and line endings. An excess-byte
probe distinguishes exact-cap EOF from oversized input. Every EINTR attempt
spends its I/O budget; other errors, including WouldBlock, terminate. Blocking
stdin/stdout have no whole-program wall-clock deadline.

The solver admits the complete requested allowance before solving. For n
nodes, k stored entries and L=`ceil_log2(max(n,1))`, its bound is
`20*(n+1) + 6*k + (k+n)*(1+L) + iterations*(40*(n+1)+8*k)`.
The library checks this with overflow-safe arithmetic against 100000000.
Dense graphs or large iteration allowances can therefore reject with a work
limit even when actual convergence would be immediate. Shared CSR validation
and construction retain their separate work checks. These are dominant logical
phase estimates, not instruction counts or wall-clock deadlines. Solver
workspace is six n-element vectors for Jacobi, including the returned x;
it allocates no storage inside the iteration loop.

| Exit | Meaning |
| ---: | --- |
| 0 | Converged finite output or help completed |
| 2 | Invalid CLI/schema/number/range or resource/work limit |
| 3 | stdin or argument-capture I/O error, or invalid input transfer count |
| 4 | Reported allocation failure |
| 5 | stdout error/call cap or SIGPIPE setup failure |
| 6 | Nonfinite assembly, solver numerical failure/breakdown, iteration limit or formatting failure |

SIGPIPE is ignored before I/O. Setup failure returns 5 before diagnostics;
other failures attempt `graph-diffuse: operation failed\n` on stderr. A failed
diagnostic preserves the primary status.

## Target and verification

The verified target is native Linux x86_64 CPU code emitted by the GPU
compiler, using native stdin/stdout. Device-side GPU execution is outside this
profile. Production is entirely Lanius and adds no C/Rust/Python solver,
JSON transport or Wasm dependency.

### Application acceptance

The registered driver `tests/extended_graph_diffuse_execution.rs` compiled the
application through the GPU compiler, passed the shared strict ELF checker
and passed all four tests on 2026-10-28. There are 154 finite native cases:
model 36, rejection 48, CLI 55 and I/O 15. The four registered tests took
17.42 seconds, including GPU compilation and native cases. Building the Rust
test driver took 1.68 seconds. Receipt:
`target/stdlib-work/graph-diffuse-runtime-first.log`.

- Model: `/tmp/graph-diffuse-model-545r1cw2`.
- Rejection: `/tmp/graph-diffuse-rejection-u_jgi3yt`.
- CLI: `/tmp/graph-diffuse-cli-j_dh0dvh`.
- I/O: `/tmp/graph-diffuse-io-t6xfmbau`.

The independent test-only oracle solves small dense systems with exact
Fraction elimination, recomputes fresh residuals and checks canonical output.
It does not reproduce CG to predict iterates. Cases include signed/repeated
sources, duplicate/reversed edges, huge ignored self-loops, zero lambda,
disconnected graphs, zero/last-step convergence, explicit nonconvergence,
subnormals, lost-identity breakdown, full schema validation before arithmetic,
maximum dimensions/records/input and seeded reference systems. Eleven CPU-only
controls passed separately, including all generated dense references.

Eight selected application allocation denials include all six CG workspace
reservations in a small graph, plus early construction and late staging.
The faults must be reached and publish no stdout. Observed successful mmap
and munmap address/size pairs balance in these traced executions. This finite
scope is not an automatic ownership checker, exhaustive failure campaign or
lifetime/leak proof. The larger triplet and output staging caps remain
explicit application bounds; tighter record/node limits keep these fixtures
from independently reaching them.

Executed application source SHA-256:
`f73d63e0b7f06555457ca7ecd3a257b12de39eec63b5b0affac88d6d9a5a5045`.
Oracle SHA-256:
`9e18d964008cbf4c0d3a0a1a65649eb94fbb5f6773092e61b76b6d08f79f2fe4`.
Registered driver SHA-256:
`4243d2f1eb2a37d9e1539ba51d9b1809ce3e091115515665093095f7a55ec452`.
See `tests/fixtures/stdlib_execution/graph_diffuse/README.md` for model
comparisons, fault scope and retained evidence. With a warm build and
configured GPU, reproduce the focused registered driver using:

```sh
timeout --kill-after=2s 100s flock -w 95 target/stdlib-work/library-gpu.lock \
  env CARGO_TARGET_DIR=target/stdlib-build LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=70000 \
  cargo test --test extended_graph_diffuse_execution -- --nocapture --test-threads=1
```

### Separate solver evidence

Six distinct sparse CG library tests are separately accepted. Three semantic
and allocation-denial tests passed in the mixed 10.96-second command
`sparse-cg-contracts-first.log`; its fourth, admission test initially failed a
stale expected diagnostic index. The corrected admission test passed alone
in 6.27 seconds in `sparse-cg-admission-index.log`. This expectation-only
correction changed owner fixture `622f387c` to `f917d188`, without a production
change; the first four-test command is not represented as an all-four pass.

The remaining gates are an independent 1,918-case model in 6.78 seconds
(`sparse-cg-model-first.log`) and a 65,536-node manufactured sparse system in
14.08 seconds (`sparse-cg-scale-first.log`). The scale fixture's whole native
lifecycle was 6757.127 ms, including construction, checks and cleanup; it does
not isolate solver throughput. The selected library workspace campaigns reach
27 operation allocation denials. These are separate library observations and
are not added to the application case count. No older library regression
suite rerun is claimed for this solver increment.

All named receipts are under `target/stdlib-work/`. The accepted solver
`extended/ext/sparse_cg.lani` SHA-256 is
`778d9d4f2b3ed8e0187bf4bf9f993289fa28e33f10e45759d2b9433b3120b7ea`.
See [the solver guide](extended-sparse-cg.md#verification-and-remaining-scope)
and its [fixture README](../tests/fixtures/extended_library/sparse_cg/README.md)
for fresh-residual/restart controls, source identities and finite fault scope.

The application imports `core::slice` and qualifies slice-view calls, following
the [existing import limitation reduction](../tests/fixtures/stdlib_compiler_state/item_import_priority/README.md).
Compiler repair remains separate. This increment changes no compiler, ABI or
proof source; other solvers, automatic ownership and formal verification
remain roadmap work.
