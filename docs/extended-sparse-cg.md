# Sparse conjugate-gradient solver

`ext::sparse_cg` implements conjugate gradients for real symmetric
positive-definite systems over the existing
[canonical CSR representation](extended-sparse.md).
The fixed [solver contract](library-sparse-cg-plan.md) defines this increment.
All six new library and four real application gates pass on native Linux
x86_64. This finite increment is accepted. Earlier CSR foundation and
sparse-product receipts retain their own source/API scope.

## API and ownership

```lani
pub enum Preconditioner { None, Jacobi }
pub enum Stop { Converged, IterationLimit }
pub struct Options {
    max_iterations:i32, rtol:f64, atol:f64, preconditioner:Preconditioner
}
pub struct Solution {
    x:alloc::vec::Vec<f64>, iterations:i32, restarts:i32,
    residual_norm:f64, rhs_norm:f64, stop:Stop
}
```

`default_options()` returns `max_iterations=1000`, `rtol=1e-10`, `atol=0`
and `Preconditioner::Jacobi`.

```lani
pub fn solve(a:ext::sparse::CsrView,
             b:core::slice::View<f64>, initial:core::slice::View<f64>,
             options:Options, limits:ext::sparse::Limits)
    -> core::result::Result<Solution,Error>
```

Import with `--source-root extended`. `Solution.borrow()` returns `&Solution`;
`destroy()` explicitly releases its independent `x` buffer. A plain copy
aliases cleanup authority. Keep one active owner and destroy it once.
Inputs and their bits remain unchanged on success or failure. They may be
read-only aliases under their ordinary backing rules; physical bounds,
lifetimes and immutability throughout the call remain manual obligations.

`Ok` can contain either `Stop::Converged` or `Stop::IterationLimit`. Inspect
`stop` before accepting a solution as converged. An iteration-limited result
owns the last iterate and reports its freshly checked residual. An error
publishes no partial solution owner; all allocated workspace is released.

## Admitted systems and preconditioners

Require square, canonical, finite CSR and vectors `b` and `initial` of exactly
dimension `n`. Both vector descriptors need nonnegative start/length with a
representable sum; all physical backing must exist. Every coefficient and
vector entry is checked, including stored coefficients unused by a particular
iterate. Dimension and stored-entry caps are the shared sparse limits.

The solver verifies exact numerical symmetry. Each nonzero stored `a[i,j]`
must have an opposite stored entry equal by binary64 equality. Unmatched
explicit zeros are allowed. There is no approximate-symmetry tolerance or
silent averaging of the matrix.

| Preconditioner | Operation and admission |
| --- | --- |
| `None` | `z=r`; no diagonal preconditioner is required |
| `Jacobi` | Every diagonal must be present and strictly positive; compute `z[i]=r[i]/a[i,i]` directly |

Jacobi checks diagonals even for an initially converged solve. It never stores
reciprocals that could overflow for tiny valid positive diagonals.

**Positive definiteness remains a caller requirement.** Symmetry and positive
diagonals do not establish it. Encountered negative `p·Ap` returns
`NonPositiveCurvature`; zero returns `Breakdown`. Nonpositive `r·z` also
returns `Breakdown`. These checks detect some invalid or numerically
degenerate traversals; they do not classify every indefinite matrix.

## Recurrence and finite arithmetic

The recurrence follows the preconditioned CG template in
[Netlib Templates, section 2.3.1 and Figure 2.5](https://www.netlib.org/templates/templates.pdf),
also used by the mature
[SciPy CG implementation](https://github.com/scipy/scipy/blob/main/scipy/sparse/linalg/_isolve/iterative.py).
Start with `r=b-Ax`, apply the selected preconditioner to get `z`, set
`rho=r·z` and `p=z`. A step computes:

```text
q = A*p
alpha = rho / (p·q)
x = x + alpha*p
r = r - alpha*q
z = M^-1*r
newrho = r·z
beta = newrho/rho
p = z + beta*p
```

Matrix products reuse `ext::sparse::matvec_into`. Dot products and vector
updates traverse ascending logical indices with ordinary binary64 products
and additions. Nonfinite products, partial sums or updates fail explicitly.
An `alpha` rounded to zero is `Breakdown`.

Euclidean norms reuse `ext::statistics::scaled_norm`; each reported norm must
be finite and representable. Dot products are unscaled and uncompensated.
A finite SPD system can therefore fail from overflow, underflow or breakdown.
The solver supplies no arbitrary-dynamic-range guarantee, uniform forward
error bound or finite-step convergence promise.

## Fresh residuals and truthful stopping

Compute a fresh `b-Ax` initially and after **every completed iterate update**,
reusing `q` after its search-direction product. Only its norm is published as
`Solution.residual_norm`. `rhs_norm` is the robust norm of the supplied `b`.

`Converged` requires this binary64 predicate:

```text
residual_norm <= atol
or (rtol > 0 and rhs_norm > 0 and residual_norm/rhs_norm <= rtol)
```

The relative comparison uses division to avoid overflowing `rtol*rhs_norm`.
Rounding in that division is part of the stopping contract. Overflow of this
comparison-only ratio to positive infinity simply fails the relative test.
Zero RHS uses only the absolute predicate. A small accepted residual
establishes this numerical test; it does not certify a forward solution-error bound or positive
definiteness.

Check the fresh residual before the iteration limit. Consequently an exact
initial solution can converge at zero iterations, and convergence on the last
allowed update is `Converged`. With no allowed updates and an unacceptable
initial residual, return `IterationLimit` with the initial iterate and its
fresh residual. An empty admitted system converges at zero steps without
allocating.

The ordinary recursive `r` remains the recurrence state. If its norm meets
the predicate but the fresh residual does not, and another step is allowed,
replace `r` with that fresh residual, recompute `z/rho`, set `p=z` and increment
`restarts`. Continue a new CG segment from the current `x`. This residual
replacement never substitutes a recursive norm for the reported one or grants
a convergence guarantee.

## Full requested work and workspace

Options require nonnegative `max_iterations` and finite nonnegative `rtol`
and `atol`. Invalid values return `InvalidOptions`. Owned vector length `n`
must fit the dimension cap and `min(limits.max_entries,268435455)`.

Before reading payload, admit CSR/vector metadata, shapes and the conservative
**full requested** iteration allowance. For `k=nnz` and
`L=ceil_log2(max(n,1))`:

```text
setup = 20*(n+1) + 6*k + (k+n)*(1+L)
step = 40*(n+1) + 8*k
setup + max_iterations*step <= limits.max_work
```

Widen extents before addition. Compare the iteration count with the remaining
budget divided by `step` before multiplication, preventing overflow even with
`max_work=u64::MAX`. Shared CSR validation also retains its separate phase
budget. The full requested allowance applies even to empty or immediately
converged systems; lower the requested iterations or raise a coherent budget
when needed. These dominant-work estimates are neither an instruction ledger
nor a wall-clock deadline.

After admission, validate CSR payload, both vectors, exact symmetry and Jacobi
diagonals, then compute the RHS norm, all before allocation. Nonempty solves
maintain five `n`-element buffers `x,r,z,p,q` and a sixth diagonal buffer for
Jacobi. There is no allocation inside the iteration loop and no dense matrix
conversion. Initially converged nonempty systems may still allocate this
bounded workspace. A returned solution retains only `x`; success releases
scratch and every error releases partial workspace.
These are logical vector lengths; allocator capacities and aggregate resident
memory have separate costs.

## Errors and positions

```lani
pub enum ErrorKind {
    Sparse(ext::sparse::ErrorKind), InvalidOptions, Shape, Bounds, EntryLimit,
    WorkLimit, NonFinite, NonSymmetric, NonPositiveDiagonal,
    NonPositiveCurvature, Breakdown, NumericalFailure, AllocationFailed
}
pub struct Error { kind:ErrorKind, row:i32, entry:i32, iteration:i32 }
```

| Kind | Meaning |
| --- | --- |
| `Sparse(kind)` | Shared CSR or matvec error, including matvec arithmetic failure, with its original kind, row and entry |
| `InvalidOptions` | Negative iterations, negative tolerances or nonfinite tolerances |
| `Shape` / `Bounds` | Non-square/wrong vector length, or malformed counted-vector metadata |
| `EntryLimit` / `WorkLimit` | Owned vector extent or full requested allowance exceeds admission |
| `NonFinite` | Nonfinite vector input |
| `NonSymmetric` | A required opposite entry is missing or unequal |
| `NonPositiveDiagonal` | Jacobi diagonal is absent or not strictly positive |
| `NonPositiveCurvature` | Encountered `p·Ap` is negative |
| `Breakdown` | Zero curvature, nonpositive `r·z` or a zero rounded step size |
| `NumericalFailure` | A solver arithmetic result or norm is not finite/representable; matvec failures retain their wrapped sparse kind |
| `AllocationFailed` | Workspace allocation fails |

Global and scalar dot/curvature/breakdown errors use `row=-1,entry=-1`.
Vector input/arithmetic errors use `row=-1,entry=logical_index`. Symmetry and
diagonal errors identify the matrix row/slot; a missing diagonal has
`entry=-1`. Wrapped sparse positions retain their original meanings.

`iteration` is the zero-based attempted step. Preflight, RHS-norm and initial
residual failures use `-1`. Once a step is attempted, even a fresh-residual
failure uses that step index. Returned `iterations` counts completed updates;
`restarts` counts residual-replacement restarts.

## Verification and remaining scope

Six new registered library tests are accepted across separate focused
receipts:

| Gate | Receipt under `target/stdlib-work/` |
| --- | --- |
| Semantic contracts and both allocation-denial groups | Three passes in the mixed 10.96s command `sparse-cg-contracts-first.log`; that command also records the initial admission-fixture failure |
| Corrected allocation-free admission contracts | One test, 6.27s; `sparse-cg-admission-index.log` |
| Independent solution/residual model | One test, 6.78s; `sparse-cg-model-first.log` |
| Large manufactured sparse system | One test, 14.08s; `sparse-cg-scale-first.log` |

The first admission assertion expected an unavailable norm-error index for
RHS `[MAX,MAX]`. The corrected fixture expects the failing push index `1`,
matching the source contract; no production change was needed. The first
semantic/OOM receipts use owner fixture `622f387c`; the isolated corrected
admission receipt uses `f917d188`. The mixed command is not an all-four pass.

Selected denial campaigns reach 16 converged/iteration-limited and 11
numerical/tiny-Jacobi workspace allocation errors: 27 reached operation
denials. Each observed baseline allocation is denied once on those inputs;
successful mappings match explicit pre-exit releases by full address and
size. These finite observations establish neither arbitrary allocation
schedules nor formal leak freedom. The corrected admission process allocates
nothing.

The independent model covers 1,918 cases over two backing forms with seed
`0xc6a20261028`. Its test-only oracle uses exact Fraction Gaussian elimination
for selected small SPD systems, independently recomputes fresh residuals in
ascending-column binary64 order and checks norms and stopping decisions. For
the diagonally dominant reference families it also bounds solution error
using the exact reference and residual/rounding allowance. It does not
reproduce CG to predict intermediate iterates. Norm comparisons use the
fixture's finite tolerances; they do not add an API-wide accuracy guarantee.

An executed scalar case uses `A=[1e308]`, `b=[1]` and initial `x=[1]`:
the first update produces recursive residual zero while fresh residual is
one. With one allowed step the result is honestly iteration-limited; with
two it restarts once and converges. This directly checks the residual-gap
policy.

The manufactured large gate solves a 65,536-by-65,536 tridiagonal system with
196,606 stored entries, diagonal 4, off-diagonals -1 and exact solution all
ones. Jacobi uses at most 20 iterations and `rtol=1e-10`; its admitted work
is 90,833,350. After destroying original matrix/vector owners, the fixture
checks the independent solution, maximum value error below `1e-8` and a
separate fixed-band residual evaluation meeting the relative threshold.
The 6757.127ms whole native lifecycle includes construction, all checks and
destruction; it does not isolate solver-kernel throughput.

The accepted library source is `extended/ext/sparse_cg.lani`, SHA-256
`778d9d4f2b3ed8e0187bf4bf9f993289fa28e33f10e45759d2b9433b3120b7ea`.
The [fixture guide](../tests/fixtures/extended_library/sparse_cg/README.md)
records reproduction commands, source identities and finite fault scope.
No existing production module changed and no older library regression groups
were rerun; the new model and large gate exercise the shared canonical matvec
and norm helpers. The executed
profile is native Linux x86_64 CPU output from the GPU compiler; device
execution is unclaimed.
The algorithm is Lanius over the shared CSR, statistics and vector modules.
It adds no native mathematics provider, C/Rust/Python solver, JSON transport
or Wasm dependency.

The [graph-diffusion application](extended-graph-diffuse.md) solves
`(I + lambda*L)x=b` from undirected nonnegative weighted edges and signed
sources. It requires a converged result before staged CSV publication; its
own bounds, numerical construction and failure policies are separate.
All four registered application tests pass in 17.42s, recorded in
`target/stdlib-work/graph-diffuse-runtime-first.log`: model 36, rejection 48,
CLI 55 and I/O 15, totaling 154 process cases. Library/model/allocation-denial
and application counts retain separate scopes. The application guide records
its numerical comparison tolerances, reached failures and staged-output
policy.

Other iterative/direct methods, sparse factorizations, broader storage formats,
automatic ownership, formal proofs and other executable targets remain
separate work. Existing CSR and sparse-product receipts do not cover this
solver.
