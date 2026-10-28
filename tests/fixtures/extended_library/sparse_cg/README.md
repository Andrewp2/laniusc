# Sparse conjugate-gradient runtime fixtures

These fixtures exercise the public solver from the
[fixed CG contract](../../../../docs/library-sparse-cg-plan.md) and
[API guide](../../../../docs/extended-sparse-cg.md). The GPU compiler emits
native Linux x86_64 code; the tests then execute that code. Compilation alone
does not establish runtime behavior, and these receipts do not claim
user-program execution on the GPU.

## Accepted library gates

| Receipt under `target/stdlib-work/` | Actual execution scope |
| --- | --- |
| `sparse-cg-contracts-first.log` | Three accepted tests and one stale test assertion failure in 10.96s: semantic contracts and both allocation-denial groups pass; the admission test fails |
| `sparse-cg-admission-index.log` | The corrected admission test passes in 6.27s, with the other three tests filtered |
| `sparse-cg-model-first.log` | One test passes in 6.78s: 1,918 cases, two backing forms, seed `0xc6a20261028` |
| `sparse-cg-scale-first.log` | One test passes in 14.08s: a 65,536-row manufactured sparse SPD system |

The first admission assertion expected no element position for a RHS norm
overflow on `[MAX,MAX]`. The agreed contract reports the failing logical index:
the second `ScaledNorm.push` fails at index 1. Only this fixture expectation
changed; the production source did not. The admission-only retry confirms the
corrected expectation and the remaining admission checks. Do not describe the
first four-test command as a four-test pass or add the overlapping retry as an
extra accepted gate. Six distinct library tests are accepted across these
separately scoped receipts.

`contracts.lani` covers None/Jacobi, exact and near initial guesses, zero RHS,
zero iterations, convergence on the last update, honest iteration limits,
independent returned storage, input bits, exact symmetry (including unmatched
signed zeros), diagonal requirements, wrapped CSR errors, encountered negative
or zero curvature, dot underflow/overflow, direct tiny-diagonal division and
initial/product arithmetic failure positions. Requested-work boundaries include
216 units and 292,057,776,072 units; the latter uses an already exact guess and
does not execute billions of iterations.

`owners.lani` opcode 0 checks descriptor/shape/vector/work and representability
errors before allocation, including inaccessible backing behind rejected
metadata/budgets, a u64-overflowing requested allowance, the hard owned-vector
capacity and the empty-system work boundary. It must publish `P` with no memory
allocation syscalls. Opcodes 1 through 5 enter Jacobi convergence, None
exhaustion, an exact initial guess, a product numerical failure and tiny-diagonal
Jacobi convergence. Inputs are stack backed. `R` marks entry into the production
call, `C` convergence, `L` iteration limit, `N` the expected numerical failure
and `F` a reached workspace allocation failure.

The driver denies each observed baseline mmap ordinal once for those selected
calls: 16 reached denials in the first group and 11 in the second. Every observed
successful mapping is paired with an explicit successful munmap of the same
address and size before exit; unexpected allocation services fail the test.
The campaign is finite and uses one denial per process. It is neither a
production resource checker nor a lifetime/alias checker or universal leak proof.

## Independent model

`model.lani` is a thin test-only binary adapter with nonzero-start counted
subviews, native/typed backing forms, input-bit comparisons and guard cells.
It serializes typed outcomes and destroys every returned solution owner.

`oracle.py` does not predict arbitrary iterates by reproducing CG. It solves
small dense systems with exact Fraction Gaussian elimination, recomputes
ascending-column binary64 `b-Ax`, checks its robust norm against published
metadata, verifies the stopping predicate and bounds solution error using the
manufactured family's strict diagonal-dominance margin. The corpus includes
40 seeded SPD families, both preconditioners, zero/exact/near guesses, several
iteration caps and separate ordered numerical/error controls. Norm comparisons
permit the documented finite rounding of independent norm algorithms; zeros
and scalar/subnormal controls remain strict.

A deterministic scalar control uses `A=[1e308]`, `b=[1]`, initial `[1]` and
Jacobi. After one update, recursive residual rounds to zero but fresh residual
is one: a one-step cap must return IterationLimit. A two-step cap must restart
once and converge near `1e-308`. This checks false-convergence refusal without
using a copied CG recurrence as the result oracle. Separate CPU controls check
Gaussian solutions and reject a forged reported norm; CPU-only controls are
not counted as native cases.

## Analytic scale

`scale.lani` constructs the 65,536-square tridiagonal with diagonal 4 and
off-diagonal -1. The known solution is all ones: RHS is 3 at the edges and 2
inside. There are 196,606 stored entries and 4,294,967,296 implicit dense cells.
The fixed setup/step formulas give 6,946,790 and 4,194,328 units, admitting
90,833,350 units for a 20-update cap under the default 100,000,000 budget.

The fixture requires convergence, preserved inputs, independent solution
ownership after destroying matrix/RHS/initial backing, maximum error below
`1e-8`, and a separately evaluated band residual satisfying the relative
`1e-10` predicate. The observed 6,757.127 ms native lifecycle includes
construction, solving, assertions and destruction; compilation is excluded.
This is not isolated solver throughput, a compiler benchmark or a cross-library
speed ratio.

## Reproduction and identities

Run each command independently. Every outer command is bounded below two
minutes; `ulimit -c 0` prevents assertion traps from leaving large core files.

```sh
ulimit -c 0
timeout --kill-after=2s 100s flock -w 95 target/stdlib-work/library-gpu.lock \
  env CARGO_TARGET_DIR=target/stdlib-build LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=70000 \
  cargo test --test extended_sparse_cg_contract_execution -- --nocapture --test-threads=1
timeout --kill-after=2s 100s flock -w 95 target/stdlib-work/library-gpu.lock \
  env CARGO_TARGET_DIR=target/stdlib-build LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=70000 \
  cargo test --test extended_sparse_cg_model_execution -- --nocapture --test-threads=1
timeout --kill-after=2s 100s flock -w 95 target/stdlib-work/library-gpu.lock \
  env CARGO_TARGET_DIR=target/stdlib-build LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=70000 \
  cargo test --test extended_sparse_cg_scale_execution -- --nocapture --test-threads=1
```

Accepted production SHA-256:
`778d9d4f2b3ed8e0187bf4bf9f993289fa28e33f10e45759d2b9433b3120b7ea`.

| Fixture | SHA-256 |
| --- | --- |
| `contracts.lani` | `65352f70cc97e39c8a0e286b1216c4dc90c047614fadf3644e0489d1d3ef4219` |
| `owners.lani` before the diagnostic assertion correction | `622f387c8aaa22c918333644aa06f6222bf851767e68ad2b37580c1057daa60b` |
| Current `owners.lani` | `f917d188f053f51c6b63e14000af088f7d0bbe39848871ecdf2c52752c0d3a55` |
| `model.lani` | `fe0a3a050d2347180aa597de84a88c342f698a9e9b251295245840c7b6cda63c` |
| `oracle.py` | `d9b8abdc26402cda3722d6907e04c517dedc38610c264c75e51ffcc0cef9c0cf` |
| `scale.lani` | `a2a6b5667a5a0f291b7b6490c115161e6ba56e1643ff0db4eb301570d07609e1` |

The [graph-diffusion program](../../../../docs/extended-graph-diffuse.md)
exercises assembly, solving and native CSV publication separately. Positive
definiteness remains a caller requirement; other solvers, preconditioners,
formal proofs, automatic ownership and broader targets remain roadmap work.
