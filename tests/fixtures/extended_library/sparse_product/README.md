# Sparse matrix product runtime fixtures

These fixtures exercise the public `ext::sparse_ops::matmul` contract from the
[product plan](../../../../docs/library-sparse-product-plan.md) and
[API guide](../../../../docs/extended-sparse-product.md). The compiler emits
native Linux x86_64 code, which is then executed. Compilation alone does not
establish any of these behavior claims; no user-program GPU execution is claimed.

## Scope and accepted receipts

| Driver | Actual evidence | Log under `target/stdlib-work/` |
| --- | --- | --- |
| `extended_sparse_product_contract_execution` | Four tests, 13.11s: semantic/admission cases and 16 reached allocation denials | `sparse-product-contracts-first.log` |
| `extended_sparse_product_model_execution` | One test, 7.45s: 2,194 cases, two backing forms, seed `0xc5a520261028` | `sparse-product-model-first.log` |
| `extended_sparse_product_scale_execution` | One test, 8.38s: 65,536-square tridiagonal product, 327,674 stored results | `sparse-product-scale-first.log` |
| Existing `extended_sparse_contract_execution` filtered by `execute` | Two semantic regression tests, 11.70s; two denial tests filtered | `sparse-product-foundation-regression.log` |

`contracts.lani` checks rectangular and empty shapes, read-only operand aliasing,
independent output, input preservation, canonical row order, actual nonzero
output limits after cancellation, finite input/arithmetic errors, explicit zero
terms, gradual underflow, and exact operation work boundaries. A populated
one-entry product with eight output columns checks that scratch is dimension
bounded independently of the entry cap. A structurally empty product retains
2,147,483,647 output columns and admits a widened work estimate of 4,294,967,297;
it does not allocate scratch.

`owners.lani` uses only stack-backed operands. Opcode 0 checks operation-work,
scratch-capacity and malformed-descriptor rejection without any memory
allocation. Full validation of valid operand payloads still precedes operation
work admission; only malformed descriptor checks precede their payload reads.
Opcodes 1 through 4 enter populated, structurally empty, cancellation and
numerical-failure operations. `R` marks entry into the production call, `S`
marks success, `N` the expected numerical failure and `F` an allocation failure.
Every allocation denied by the selected campaigns is reached within the call,
with no allocated input setup to confuse that count. The populated/empty group
reaches seven denials; cancellation/numerical failure reaches nine.

The Rust driver traces `mmap`, `mremap`, `munmap` and `brk`, denying each observed
baseline `mmap` ordinal separately. It pairs every observed successful mapping
with an explicit successful release of the same address and size before exit.
The selected allocation schedules are finite; this is neither a production
resource checker nor a proof of lifetime safety or leak freedom for all inputs.

## Independent numerical model

`model.lani` is a thin test-only binary adapter, preserving input bits and guard
cells. It supplies nonzero-start counted subviews over native and typed backing.
`oracle.py` uses dense coordinate dictionaries and exact `Fraction` arithmetic
for bounded dyadic cases, plus dense ordered binary64 calculations for rounding,
overflow-before-cancellation and subnormal boundaries. It does not reproduce
the production marker/touched-index accumulator or its two-pass strategy.

The corpus covers 125 rectangular shapes, 900 seeded dyadic matrices, 50
non-dyadic ordered models and 22 explicit boundary/cap cases, each over two
backing forms. Expected CSR offsets, columns, stored count and finite value
bits must match exactly; computed zeros must be absent. A CPU control corrupts
a nonzero subnormal to zero and requires the oracle to reject it. The CPU
controls are separate from native execution counts.

## Analytic scale

`scale.lani` constructs a tridiagonal matrix with diagonal 2 and adjacent
diagonals 1, then squares it through the public sparse API. The pentadiagonal
result has coefficients 1, 4, 6, 4, 1, with boundary diagonal 5. It checks every
coordinate and value, unchanged input, independent ownership, and products with
constant and ramp vectors after destroying the input.

The shape has 4,294,967,296 implicit dense cells, 196,606 input entries, 589,814
structural scalar products and an admitted work estimate of 23,330,433. The
observed 1,206.798 ms native lifecycle includes setup, all checks, both matvecs
and destruction; compilation is excluded. This is not isolated multiplication
throughput, a compiler benchmark or a speed ratio against another library.

## Reproduction

Run each command independently; every outer command is bounded below two
minutes. `ulimit -c 0` prevents failed assertions from leaving large core files.

```sh
ulimit -c 0
timeout --kill-after=2s 100s flock -w 95 target/stdlib-work/library-gpu.lock \
  env CARGO_TARGET_DIR=target/stdlib-build LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=70000 \
  cargo test --test extended_sparse_product_contract_execution -- --nocapture --test-threads=1
timeout --kill-after=2s 100s flock -w 95 target/stdlib-work/library-gpu.lock \
  env CARGO_TARGET_DIR=target/stdlib-build LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=70000 \
  cargo test --test extended_sparse_product_model_execution -- --nocapture --test-threads=1
timeout --kill-after=2s 100s flock -w 95 target/stdlib-work/library-gpu.lock \
  env CARGO_TARGET_DIR=target/stdlib-build LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=70000 \
  cargo test --test extended_sparse_product_scale_execution -- --nocapture --test-threads=1
```

Accepted production source SHA-256:
`bc4fb71475ffdf78934de8eefa3c67aeeeaa656e4a29abfa33b4c4d85f014e35`.
Fixture hashes are:

| File | SHA-256 |
| --- | --- |
| `contracts.lani` | `a5a102ce1127079b19e285c2a0d3d1cbbf45f9e300dcd8e092849517ea279800` |
| `owners.lani` | `c76a1a71b0ce2931ee1e1033082ef8faddbd943ce7a1ed79cdf05f2d619c4b9f` |
| `model.lani` | `3b7f3472e1dc5fe5673a6b4101de5469fc59ede22881f1f2aaff0d345ea48ac6` |
| `oracle.py` | `1fe6db9443fbcd5e22dd4cdba82e90e9c87e5b34d2dcc032ec203779b2e51e6f` |
| `scale.lani` | `171d13d6367ad27069a31de84f2c8aa8ea6879e564453fe3ce3d7c5bfe817afa` |

The [weighted-paths program](../../../../docs/extended-sparse-paths.md) exercises
CSV assembly, repeated sparse products and staged native output separately.
Broader targets, sparse factorizations/solvers and other formats remain outside
these finite receipts. The full library roadmap remains active.
