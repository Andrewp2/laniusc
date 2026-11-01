# Sparse conjugate-gradient contract

This increment adds a usable sparse linear solver to the
[library roadmap](library-roadmap.md). It keeps the
[CSR representation](extended-sparse.md) and explicit manual owners. Six library
gates and four graph-diffusion application gates pass on native Linux x86_64,
with separately scoped test receipts. Other iterative/direct solvers and sparse
factorization remain separate roadmap work.

## Public surface in `ext::sparse_cg`

```lani
pub enum Preconditioner { None, Jacobi }
pub enum Stop { Converged, IterationLimit }
pub struct Options {
    max_iterations:i32, rtol:f64, atol:f64, preconditioner:Preconditioner
}
pub enum ErrorKind {
    Sparse(ext::sparse::ErrorKind), InvalidOptions, Shape, Bounds, EntryLimit,
    WorkLimit, NonFinite, NonSymmetric, NonPositiveDiagonal,
    NonPositiveCurvature, Breakdown, NumericalFailure, AllocationFailed
}
pub struct Error { kind:ErrorKind, row:i32, entry:i32, iteration:i32 }
pub struct Solution {
    x:alloc::vec::Vec<f64>, iterations:i32, restarts:i32,
    residual_norm:f64, rhs_norm:f64, stop:Stop
}
```

`default_options()` returns 1000 iterations, rtol `1e-10`, atol zero and Jacobi.
`solve(a:CsrView,b:View<f64>,initial:View<f64>,options:Options,limits:Limits)`
returns `Result<Solution,Error>`; limits are the existing `ext::sparse::Limits`.
`Solution.borrow()` returns `&Solution`; `destroy()` explicitly releases x.
Returned x owns independent backing. Copies alias cleanup authority, and
backing/lifetime/immutable-input obligations remain manual. No caller-visible
partial result escapes on Err. IterationLimit is an explicit successful
outcome containing the last iterate and freshly checked residual; callers must
inspect stop before treating it as converged.

## Admission and supported systems

Require square canonical finite CSR and vectors of exact length n. Every input
is finite-checked, including unused coefficients. Both counted-vector metadata
and all CSR descriptors must be valid. Negative option iterations, nonfinite
or negative tolerances are InvalidOptions. The owned vector length n must fit
`min(max_entries,268435455)` and the normal dimension cap. Inputs are preserved
on success and failure, including initial guesses and explicit signed zeros.

Verify exact numerical symmetry: for each nonzero stored a[i,j], the opposite
entry exists and equals it using f64 equality. Unmatched stored zeros are legal.
No approximate-symmetry tolerance or silent averaging is applied. Jacobi also
requires every diagonal value to be strictly positive, including for an
initially converged solve. Apply Jacobi as r[i]/a[i,i]; do not form an inverse
whose reciprocal could overflow. None uses z=r.

Positive definiteness is a caller requirement, not established by symmetry or
positive diagonals. Negative encountered p·Ap is NonPositiveCurvature; zero is
Breakdown (which can also arise from rounding/underflow). Nonpositive r·z is
Breakdown. These checks do not diagnose all indefinite matrices. A small
residual certifies only the documented numerical stopping test.

## Algorithm and truthful stopping

The recurrence follows the preconditioned CG template in
[Netlib Templates, section 2.3.1 and Figure 2.5](https://www.netlib.org/templates/templates.pdf),
also used by the mature [SciPy CG implementation](https://github.com/scipy/scipy/blob/main/scipy/sparse/linalg/_isolve/iterative.py).
Use r=b-Ax, z=M^-1*r, rho=r·z, p=z initially; each step computes q=Ap,
alpha=rho/(p·q), x=x+alpha*p, r=r-alpha*q, then z, new rho, beta=newrho/rho,
and p=z+beta*p. Products, sums and vector updates follow ascending logical
indices with ordinary binary64 multiplication/addition. Nonfinite arithmetic
fails explicitly. An alpha that rounds to zero is Breakdown.

Reuse `ext::sparse::matvec_into` for admitted CSR products and the existing
`ext::statistics::scaled_norm` for robust Euclidean norms. Dot products remain
ordinary finite binary64; scaling/compensation for arbitrary dynamic range is
not supplied. A finite SPD problem can therefore return a numerical error or
breakdown. Every norm must be representable and finite.

Freshly compute b-Ax initially and after EVERY completed update, reusing q
after its Ap use. Publish only that fresh residual norm. Converged requires
`residual_norm <= atol`, or, when rtol>0 and rhs_norm>0,
`residual_norm/rhs_norm <= rtol`. This division-based binary64 predicate avoids
overflow from rtol*rhs_norm; its rounding at the boundary is part of the profile.
If this comparison-only quotient overflows to positive infinity, the comparison
simply fails; it is not an iterative-arithmetic failure. A beta that rounds to
zero is permitted; only a zero alpha is classified as Breakdown.
The zero-RHS case uses the absolute predicate. Check the fresh residual before
the iteration limit, including at max_iterations zero or on the last update.

Keep the ordinary recursive r for the CG recurrence. If it satisfies the same
predicate but the fresh residual does not, and another step is allowed, restart
CG from the current x: copy fresh residual to r, recompute z/rho, set p=z and
increment restarts. This is a new ordinary CG segment with a checked initial
residual, not an assertion of finite-step or universal convergence. An empty
system is converged with zero steps and no allocations after full admission.

## Work, storage and failures

Let n be the dimension, k=nnz and L=ceil_log2(max(n,1)). Before payload reads,
admit descriptor/shape/vector metadata and the conservative full requested
allowance:

`setup = 20*(n+1) + 6*k + (k+n)*(1+L)`

`step = 40*(n+1) + 8*k`

`setup + max_iterations*step <= limits.max_work`.

Widen operands before sums and compare iteration count with the remaining
budget divided by step before multiplying. The shared CSR validator retains
its own phase budget. The requested allowance applies even when convergence
would be immediate; it is not a promise that the caller's cap will be spent.
These are conservative dominant-work units, not instructions or deadlines.

After admission, validate CSR, b and initial, exact symmetry and (for Jacobi)
diagonals before allocation. Compute rhs norm before allocation. Maintain five
n-element buffers x, r, z, p, q, plus n diagonal values for Jacobi. No allocation
occurs inside the iteration loop. Release all scratch and every partial owner
on error; retain only x in a returned Solution. Initially converged nonempty
systems may still allocate this bounded workspace. Never convert to dense.

Wrapped sparse errors preserve original kind/row/entry. Global errors use
row/entry -1. Vector arithmetic/finite errors use row=-1,entry=logical index;
symmetry and diagonal errors identify their matrix row/slot (missing diagonal
entry=-1). Scalar dot/curvature/breakdown errors use -1,-1. `iteration` is the
zero-based attempted step; preflight, RHS norm and initial residual errors use
-1. During an attempted step, even a fresh-residual error uses that step index.
Initial direction/preconditioned-dot failures use attempted step zero when a
step remains. A scaled-norm push failure reports the current vector index;
a final norm-value failure has no element coordinate.

## Executable acceptance

Exercise defaults, exact/near initial solutions, both preconditioners, zero
iterations, true last-step convergence, honest iteration limits, zero/empty
RHS, symmetry/diagonal/shape/finite errors, curvature, underflow/overflow,
descriptor and full-budget boundaries, independent ownership and input bits.
Reach a recursive/fresh-residual disagreement and verify restart or refusal to
claim convergence. An independent dense/Fraction model checks SPD families,
fresh residuals, stopping decisions and solution error over seeded systems;
ordered IEEE controls target numerical failures. Selected reached allocation
denials check explicit release address/size balance. A large sparse manufactured
system checks solution/residual without a dense fallback. A bounded CSV graph
diffusion application solves (I + lambda*L)x=b using symmetric nonnegative
weighted edges, with convergence/failure/output policy explicit. Valid
self-loops contribute nothing and skip coefficient-scaling arithmetic after
domain validation. Although the unrounded mathematical matrix is positive
definite, large finite edge weights can lose its identity term in binary64;
the assembled problem can therefore break down or fail to converge.

Root owns serialized compiler/native commands, each below two minutes. Current
target scope is Linux x86_64 CPU output from the GPU compiler. No compiler,
extractor, proof or ABI production change is part of this increment. Missing
compiler support gets a minimal reproduction and dependency report.

The accepted [fixture receipts](../tests/fixtures/extended_library/sparse_cg/README.md)
cover 1,918 independent-model cases over two backing forms, 27 reached workspace
allocation denials, and a 65,536-row manufactured SPD system with an independently
checked solution/residual. The scalar recursive-zero/fresh-one case refuses
convergence at a one-step cap and successfully restarts with a two-step cap.
The admission fixture's stale norm-error index was corrected in an isolated
retry without changing production code. The real
[graph-diffusion application](extended-graph-diffuse.md) passes 154 cases across
four native groups. These finite receipts advance the full roadmap; they do not
establish formal numerical correctness, arbitrary SPD convergence or broader
target support.
