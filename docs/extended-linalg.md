# Native f64 linear algebra

`ext::linalg` provides counted strided matrix views, owned matrices, partial
pivot LU, and tall Householder QR least squares. The algorithms are Lanius code
using `core::f64` and `alloc::vec`; they do not call a host matrix library.
Runtime coverage targets native x86_64 Linux. This document makes no GPU
execution claim.

## Views and owners

`row_major(values, count, rows, cols)` borrows the first `rows*cols` logical f64
entries. `strided(values, count, offset, rows, cols, row_stride, col_stride)`
selects logical entry `values[offset + row*row_stride + col*col_stride]`.
`transpose(view)` exchanges shape and strides without allocating. Strides must
be nonnegative; a dimension with more than one selected entry requires a
positive stride. Overlapping logical entries are permitted for these read-only
views. Negative strides are rejected. Empty views select no entries and allow
`offset == count`.

The caller must provide a slice physically backed for `count` logical entries
and keep its storage alive. The current compiler cannot verify that physical
backing from a separate count. Constructors validate shape, arithmetic, and
selected bounds before reading entries. Slice indexing uses Lanius logical
order; raw native f64 storage need not use forward C array order.

`zeros`, `identity`, and `from_view` allocate a `Matrix`. Its `view()` borrows
storage, `get` checks bounds, and `set` checks bounds and finite values.
`try_clone(limits)` and the owned `transpose(limits)` method allocate independent
matrices. Free `add`, `sub`, `scale`, and `matmul` return new matrices.

A copied `Matrix`, `Lu`, or `Qr` aliases its allocations. Keep one active owner,
transfer it once, and call `destroy()` once. A factor owns its packed matrix and
pivot or reflector vector. Successful calls transfer returned owners to the
caller; failed calls release their temporary owners and preserve all inputs.
Borrowed views become invalid when their owner is destroyed. Views and record
fields are read-only by convention: mutating factor storage or ownership fields
violates the factor's invariant. These rules are manual, not compiler-enforced.

## LU and QR

`lu(a, tolerance, limits)` accepts rectangular matrices and returns packed L/U
storage, zero-based row swaps through `pivot(step)`, and permutation parity.
Starting with A and applying those swaps in order gives `L*U`; L has an implicit
unit diagonal. A zero or rejected pivot returns `Singular` and releases the
partial factor. Rectangular factorization can fail when a pivot column is zero,
even if a later column would supply rank under column pivoting.

For square factors, `solve(b, limits)` accepts any number of RHS columns;
`determinant()` includes the row permutation sign, and `inverse(limits)` solves
against the identity. Free `solve`, `determinant`, and `inverse` also accept a
matrix view and tolerance. A singular determinant is an error under this
factorization policy. The empty determinant is one and the empty inverse is a
0-by-0 matrix.

`qr(a, tolerance, limits)` requires `rows >= cols`. The upper triangle of
`packed()` stores R; lower entries and the owned tau vector encode Householder
reflectors. `apply_q` and `apply_q_transpose` preserve their input and return a
matrix. `Qr.least_squares(b, limits)` applies Q transpose, solves the leading
triangular system, and returns a `cols`-by-`b.cols` matrix. Free
`least_squares(a, b, tolerance, limits)` also constructs the factor. It never
forms normal equations. Empty parameter sets return zero coefficient rows.
Underdetermined systems are explicitly unsupported.

Tolerances are finite, nonnegative, and relative to the maximum absolute input
entry. A computed pivot or R diagonal is rejected when its magnitude divided by
that scale is at most the tolerance. `default_tolerance()` is `1e-12`. Zero
means reject exactly zero computed pivots, including when a nonzero relative
ratio would underflow. This unpivoted QR test is a numerical acceptance policy,
not a rank-revealing decomposition, exact rank decision, or condition estimate.
Near rank deficiency can still reduce accuracy; callers select the tolerance.

`norm(view, limits)` computes the Frobenius norm by scaling before squaring.
Householder generation also normalizes before forming reflector ratios, and
applications scale only the reflector's nonzero support. Rows with zero
reflector coefficients are preserved directly. This avoids discarding an
untouched tiny component beside a huge one. A destructive normalization or
rescaling underflow returns `NumericalFailure`. Some extreme mixed ranges are
conservatively rejected even when a more elaborate scaling algorithm could
produce a result. Ordinary f64 rounding and small-term underflow in summation
still apply; this API does not claim exact arithmetic. Uniformly tiny or large
matrices are covered separately from mixed-range cases.

Nonfinite inputs return `NonFinite`. Nonfinite arithmetic results, a nonzero
pivot division or reflector coefficient that collapses to zero, and detected
destructive scaling return `NumericalFailure`. Determinants reject intermediate
overflow or underflow, even if a later factor might bring the product back into
range. Errors never convert an unsuccessful pivot or solve into a zero result.

## Resource limits and failures

`Limits { max_elements: i32, max_work: u64 }` defaults to 1,048,576 elements and
100,000,000 work units. Negative element limits return `InvalidLimits`.
`max_elements` bounds each logical matrix input, output, and allocated work
buffer; it is not a bound on total live memory across the call. The hard element
ceiling is 268,435,455 f64 entries, matching the vector byte capacity. Products
above that ceiling return `Overflow` before allocation.

Work units are explicit shape estimates for the dominant loops. A call rejects
an estimate above `max_work` before that phase. It also checks the linear input
and output sizes. Validation scans, initialization, and copies add a fixed
number of linear passes; units are not CPU instructions or a counter shared
between calls. With A shape m-by-n and B having p RHS columns:

| Operation | Dominant estimate |
| --- | --- |
| allocation, clone, norm, elementwise | selected element count |
| matrix product m-by-n times n-by-p | `m*p*(n+1)` |
| LU factor | `m*n*(min(m,n)+2)` |
| existing square LU solve | `n*(n+3)*p` |
| QR factor | `8*m*(n+1)*(n+1)` |
| Q or Q transpose application / existing QR solve | `8*m*(n+1)*(p+1)` |
| free QR least squares | `8*m*(n+p+1)*(n+1)` |

Free LU operations run the factor estimate and the solve estimate separately;
applications needing a cumulative budget should charge both. All algorithms
are iterative, with no recursive depth to configure. Multiplicative work checks
use division before multiplication to prevent overflow. Zero dimensions have
explicit empty semantics. Incompatible shapes, malformed views, and resource
exhaustion return `Shape`, `NotSquare`, `UnderDetermined`, `Bounds`,
`InvalidStride`, `ElementLimit`, or `WorkLimit`. Invalid tolerance and allocation
failure remain distinct as `InvalidTolerance` and `AllocationFailed`.

## Sources and verification

The LU phases follow LAPACK's unblocked
[DGETF2](https://github.com/Reference-LAPACK/lapack/blob/master/SRC/dgetf2.f)
and the swap/forward/back substitution sequence in
[DGETRS](https://github.com/Reference-LAPACK/lapack/blob/master/SRC/dgetrs.f).
QR follows the reflector representation in
[DGEQRF](https://netlib.org/lapack/explore-html/d0/da1/group__geqrf_gade26961283814bb4e62183d9133d8bf5.html),
the unblocked update sequence in
[DGEQR2](https://github.com/Reference-LAPACK/lapack/blob/master/SRC/dgeqr2.f),
and the reflector equations in
[DLARFG](https://github.com/Reference-LAPACK/lapack/blob/master/SRC/dlarfg.f).
The tall least squares phases follow
[DGELS](https://github.com/Reference-LAPACK/lapack/blob/master/SRC/dgels.f).
Scaling before summing squares follows the representation described by
[DLASSQ](https://netlib.org/lapack/explore-html/d8/d76/group__lassq_gae8f40b0a34771b4f2d9c863de3af7be5.html).

This implementation uses simple loops, explicit errors, and normalized column
ratios instead of LAPACK's blocked BLAS kernels and safe-minimum scaling loop.
A one-element or zero-tail Householder column may use a sign reflector rather
than the identity; the resulting Q/R product is unchanged. Rank policy and
conservative numerical failure are deliberate API choices.

`tests/extended_linalg_execution.rs` executes the native library against tiny
exact Python Fraction references for products, solves, inverses, and
determinants, and, when installed, independent NumPy least squares references. It checks solve
residuals, least squares residual orthogonality, Q orthogonality, and QR
reconstruction. Contract fixtures exercise permutations, rectangular factors,
strided and transposed views, empty shapes, extrema, subnormals, mixed ranges,
nonfinite input, singularity, tolerance changes, and work/element limits. A
separate strace sweep denies every observed mmap in 18 operation paths and
checks preserved input/factor owners, successful cleanup, and zero live mappings.
Python and NumPy are test oracles only.
