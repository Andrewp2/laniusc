# Signed weighted paths with sparse matrix products

`sample_programs/library/sparse_paths.lani` reads a weighted directed adjacency
matrix and writes the canonical nonzero entries of its positive integer power:

```sh
sparse-paths --nodes N [--length K] [--help]
printf 'source,target,weight\n0,1,2\n1,2,-3\n' | sparse-paths --nodes 3
```

With the default length 2, the example has one nonzero result: source 0,
target 2, weight -6. Entries sum products of edge weights along walks of
exactly K edges; vertices and edges may repeat. Signed weights can cancel.
The calculation supplies a finite binary64 matrix power, with no shortest-path,
normalization, convergence or exact-integer-count guarantee.

## CLI and input

`--nodes` is required and ranges from 1 through 4096. `--length` ranges from
1 through 16 and defaults to 2. Short aliases are `-n N`, `-k K` and `-h`.
Integer arguments contain ASCII decimal digits only; leading zeros are
allowed, signs and whitespace are rejected. Every duplicate option is an
error, including different aliases and repeated help in a short cluster.
Positional operands are rejected. Help validates supplied options and bypasses
both stdin and the required nodes option.

Input begins with exactly `source,target,weight`, in that order and case.
CSV quoting around those names is allowed. Every data record contains exactly
three fields: zero-based source and target integers less than N, followed by
a finite signed binary64 weight. Positive, negative and signed-zero weights
are accepted. Nonfinite input is rejected. The existing decimal parser may
round a sufficiently small magnitude to zero; that becomes a zero edge.

CSV uses the existing UTF-8 dialect, including CRLF/LF record endings and
quoted fields. Empty input, BOM-prefixed or altered headers, blank records,
invalid UTF-8, unsupported controls and malformed numbers are errors. All
input is validated, including disconnected edges. A header with no edges is
valid and produces only the output header for every accepted length.

## Sparse arithmetic and ownership

The real production composition is:

```text
CSV -> triplets in input order -> canonical CSR A
    -> A*A -> (A*A)*A -> ... -> canonical CSV
```

Coordinate duplicates coalesce in original input order. The resulting CSR has
strictly increasing columns within each row; exact-zero entries are omitted.
Length 1 renders this assembled matrix directly. For K greater than one,
products associate left: each next matrix is `matmul(result,A)`. The program
performs exactly K-1 products, at most 15, without exponentiation by squaring.
This order is part of the floating-point contract.

Each product scans a left row in increasing inner column, then the matching
right row in increasing output column. It performs ordinary binary64 multiply
and add, starting accumulators at positive zero. Touched-column sorting does
not reorder those sums. Every intermediate result is canonical and drops
rounded exact zeros. Nonfinite products or partial sums fail immediately;
later cancellation cannot rescue overflow. Gradual underflow and rounding
remain IEEE behavior and may remove an entry that rounds to zero.

The base CSR owner stays live through every product and final render. The
first product borrows that same immutable base twice and returns independent
backing. Later products borrow the current result and base, release the old
result after success, and install the new owner. Failure releases the current
result and then the base. No owning matrix is duplicated to create independent
cleanup authority, and no dense N-by-N buffer is constructed.

CSV input is copied into plain triplet values before the decoded table and raw
input are destroyed. The edge vector, all matrix owners, output record,
argument owner and output buffer have explicit cleanup on returned paths.
The output buffer remains independent through stdout publication. These are
source ownership contracts; finite tests do not establish a lifetime or leak
proof.

## Output and limits

Output is fully quoted CRLF CSV with header `source,target,weight`. It contains
only nonzero entries, sorted first by source and then target. Every weight is
finite and formatted with the existing binary64 formatter. All assembly,
products and formatting finish before the first stdout write. Input, resource,
allocation or numerical failure therefore publishes no prefix. An stdout
failure can leave a confirmed written prefix.

| Resource | Bound |
| --- | ---: |
| Raw stdin bytes | 4194304 (4 MiB) |
| Raw edges / records including header | 65536 / 65537 |
| Fields per record / decoded bytes per field | 3 / 128 |
| Decoded bytes per record | 384 |
| Nodes / positive length | 4096 / 16 |
| Stored entries in the base and every product | 65536 |
| Per-operation logical work estimate | 100000000 |
| Matrix product calls | K-1, at most 15 |
| Independent staged output | 16777216 bytes (16 MiB) |
| stdin / CSV staging / stdout attempts | 16384 / 262144 / 32768 |
| Diagnostic attempts | 8 |
| Captured arguments / total argument bytes | 24 / 1024 |

The decoded-record cap counts field content, excluding commas, quoting and
line endings. Three 128-byte fields are therefore permitted together. An
excess-byte probe distinguishes exact-cap EOF from oversized input. EINTR
retries spend their call budget; other I/O errors, including WouldBlock,
terminate. Blocking descriptors have no whole-program wall-clock deadline.

The entry cap applies to every actual rounded intermediate result. A product
that exceeds it fails even if a later power could cancel entries. Structural
candidates that cancel within a product do not count as stored entries.
Product work uses the shared sparse contract's conservative estimate
`3*(R+1+NA) + 2*C + 2*P*(3+ceil_log2(max(C,1)))`, admitted with overflow-safe
arithmetic. Each input validation also has its own work limit. These are
per-operation logical estimates, not an aggregate instruction or time limit.
See [the product contract](library-sparse-product-plan.md) for definitions and
scratch bounds.

| Exit | Meaning |
| ---: | --- |
| 0 | Canonical output or help completed |
| 2 | Invalid CLI/schema/number/range, entry/work limit or staging limit |
| 3 | stdin I/O error or invalid input transfer count |
| 4 | Reported allocation failure |
| 5 | stdout error/call cap or SIGPIPE setup failure |
| 6 | Numerical coalescing/product or number-formatting failure |

SIGPIPE is ignored before I/O. Setup failure returns 5 before diagnostics;
subsequent failures attempt `sparse-paths: operation failed\n` on stderr.
A failed diagnostic preserves the primary exit.

## Target and verification

The verified target is native Linux x86_64 code emitted by the GPU compiler.
The program performs CPU matrix computation and native stdin/stdout I/O;
device-side GPU execution is outside this profile. Production is entirely
Lanius and adds no C/Rust/Python mathematics library, JSON transport or Wasm
dependency.

### Application acceptance

Current acceptance on 2026-10-28 is 122 unique finite native cases: model 34,
rejection 37, CLI 36 and I/O 15. It comprises two recorded runs:

- The initial registered run passed all four tests, with 121 cases (model 33,
  rejection 37, CLI 36 and I/O 15), in 20.45 seconds. Cargo build took 1.70
  seconds. Receipt: `target/stdlib-work/sparse-paths-runtime-first.log`.
- The oracle then added one rounded association case. The amended model passed
  as one registered test with 34 cases, three other tests filtered, in 14.73
  seconds. Receipt: `target/stdlib-work/sparse-paths-model-association.log`.
  The rejection, CLI and I/O group inputs are unchanged and retain their first
  acceptance. Repeated model cases are not added as distinct coverage.

Both registered runs compiled the unchanged application through the GPU
compiler and passed the shared strict ELF checker before executing the
independent oracle. Current evidence directories are:

- Amended model: `/tmp/sparse-paths-model-p5ce95ju`.
- Rejection: `/tmp/sparse-paths-rejection-0w7zwvox`.
- CLI: `/tmp/sparse-paths-cli-p_8z0m3y`.
- I/O: `/tmp/sparse-paths-io-tox_t_lf`.

The added scalar case A=[1.1], length 4 requires 1.4641000000000006. It
distinguishes repeated left-associated products from squaring's
1.4641000000000004 and passed without a production source change.

The fixture uses independent dense/Fraction models and ordered IEEE boundary
cases. It checks canonical output, signed cancellation, exact 65536-result
entry admission, work/entry/input bounds, later-power overflow and actual I/O
failures. Eight selected application allocation denials must be reached and
publish no stdout; small traced executions match observed successful mmap
and munmap address/size pairs. These finite observations supply no automatic
ownership, arbitrary failure-schedule or formal leak proof. The 16 MiB staging
cap is documented but is not independently reached by these bounded entries.

Executed application source SHA-256:
`1c01bd461535b5a87e1a783ad38c1b66281c350468f72760e79a83d53f7f1011`.
Current amended oracle SHA-256:
`1e42dd2f4003fe915345e1b8f7c953b0da08c65d221b3f0c44c499cb97f77f37`.
Initial accepted oracle SHA-256:
`6d8d4318d7aae26037a287c75d6fa29db2abee017d44d94442c3b61ba03149f3`.
Current driver SHA-256:
`6284516378b67271e65c6f5b5d2d778ba434d5edf66c071bbbcaa6945be3e41d`.
See `tests/fixtures/stdlib_execution/sparse_paths/README.md` for detailed
model/fault scope and `tests/extended_sparse_paths_execution.rs` for the
registered driver. With a warm build and configured GPU, reproduce using:

```sh
timeout --kill-after=2s 100s flock -w 95 target/stdlib-work/library-gpu.lock env CARGO_TARGET_DIR=target/stdlib-build cargo test --test extended_sparse_paths_execution -- --nocapture --test-threads=1
```

### Separate sparse product evidence

The underlying product has six separately accepted registered library tests:
four contract/allocation tests, one independent model and one large analytic
scale test. Their receipts under `target/stdlib-work/` are
`sparse-product-contracts-first.log`, `sparse-product-model-first.log` and
`sparse-product-scale-first.log`. The contract groups include 16 reached
operation allocation denials across populated, empty, cancelled and
numerical-failure inputs. Two selected earlier sparse semantic regressions
also passed, recorded in `sparse-product-foundation-regression.log`.
These are separate library gates and are not added to the application case
count. See [the product guide](extended-sparse-product.md#verification-and-remaining-scope)
for numerical models, scale figures, source identities and finite fault scope.

The accepted library `extended/ext/sparse_ops.lani` SHA-256 is
`bc4fb71475ffdf78934de8eefa3c67aeeeaa656e4a29abfa33b4c4d85f014e35`.
The application imports `core::slice` and fully qualifies slice-view calls,
following the [existing import limitation reduction](../tests/fixtures/stdlib_compiler_state/item_import_priority/README.md).
Compiler repair remains separate; this increment changes no compiler, ABI or
proof code.
