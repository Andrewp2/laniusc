# Sparse matrix product contract

This increment closes the sparse/sparse product gap in the
[library roadmap](library-roadmap.md). It builds on the
[canonical CSR foundation](extended-sparse.md). The six focused library gates
pass on native Linux x86_64, with two selected foundation semantic regressions.
The [weighted-paths application](extended-sparse-paths.md) passes its four
runtime groups through separately scoped first and amended-model receipts.

## Interface and invariants

`ext::sparse_ops::matmul(a:CsrView,b:CsrView,limits:Limits)` returns
`Result<ext::sparse_matrix::Matrix,ext::sparse::Error>`. Inputs are borrowed,
fully validated canonical finite CSR; `a.cols == b.rows`. The result has shape
`a.rows` by `b.cols`, independent backing, strictly increasing columns in each
row, and no stored exact zeros. Empty axes retain their shape. Inputs, including
explicit signed zeros and unused right-hand rows, remain unchanged.

Both operands use the existing dimension, entry and per-validation work caps.
Output offsets use the existing owned-row ceiling (`rows < 536870911`); output
entries use `min(max_entries,268435455)`. The output cap counts actual rounded
nonzero values, not symbolic candidates: cancellation can make a product fit.
The API never converts either operand or the result to a dense matrix.

## Algorithm and arithmetic

Use a row accumulator: scan each left row in increasing inner column `k`, then
the corresponding right row in increasing output column `j`. Accumulate each
`a[i,k]*b[k,j]` into its output column, starting from positive zero, with
ordinary binary64 multiplication and addition. Missing structural terms are
skipped. Explicit stored zeros are visited. A nonfinite product or partial sum
fails immediately with `NumericalFailure { row:i, entry:left_entry }`; later
cancellation cannot rescue overflow. Underflow and rounding remain ordinary
binary64 behavior. Sort touched column indices only after accumulation; sorting
does not reorder the sums. Drop computed `+0` and `-0` entries.

The sparse accumulator pattern is described by the mature
[SciPy CSR multiplication implementation](https://github.com/scipy/scipy/blob/main/scipy/sparse/sparsetools/csr.h).
Lanius additionally requires canonical input/output order, finite intermediate
results, explicit budgets and typed allocation errors. This is an independent
Lanius implementation, with no SciPy or native mathematics dependency.

Scratch consists of column-indexed markers and sums, plus a touched-index
buffer, each with `b.cols` capacity. Its storage is O(b.cols), not O(rows*cols).
Scratch columns are dimension-bounded, independently of `max_entries`, and the
f64 scratch buffer imposes a hard `b.cols <= 268435455` when structural products
exist; otherwise return `DimensionLimit`. A structurally empty product allocates
only its output offsets and does not require scratch. It retains wide empty
shapes that fit the ordinary dimension cap.

After full input validation and work admission, allocate scratch, perform a
numerical/count pass, reserve exact result storage, and repeat the same row
calculation to fill it. Reset markers only for touched columns. Reuse scratch
across rows and passes. This avoids a full output-column scan for every row.
Every partial owner is released on any failure; no result owner escapes on
error. Allocation failure may occur before arithmetic failure because scratch
is necessary for the numerical prepass. Copies still alias cleanup authority;
lifetimes and exclusive owner cleanup remain manual caller obligations.

## Work admission

Let `R=a.rows`, `C=b.cols`, `NA=nnz(a)` and
`P=sum(nnz(b.row(a.column[e])))` over all stored left entries. P counts structural
scalar products, including explicit zero coefficients. Derive P only after
canonical validation; this scan costs O(NA). Each input validation has its own
existing `rows+1+nnz` budget.

The separate conservative operation estimate is:

`3*(R+1+NA) + 2*C + 2*P*(3+ceil_log2(max(C,1)))`.

This admits the structural prepass, two row walks, marker/sum initialization,
two numerical passes, touched-index sorting and retirement. It is a logical
dominant-work estimate, not an instruction count or time guarantee. It applies
also to structurally empty products; these may do less actual work. Widen before
summing and compare P against the remaining budget divided by its coefficient
before multiplying. No u64 wrap is permitted, even with max_work=u64::MAX.
Work rejection precedes scratch/output allocation and scalar multiplication.
Global work/shape/cap errors use row/entry -1. A discovered output entry cap
error identifies the output row and column (entry is the output column here).

## Executable acceptance

- Contract cases: rectangular/empty/zero-inner products; canonical ordering;
  aliasing of read-only operands; input preservation; signed/explicit zeros;
  output independence; cancellation under entry caps; overflow before later
  cancellation; unused nonfinite input; malformed descriptors/offsets/order;
  exact work boundaries; overflow-safe estimates; scratch hard limits.
- Allocation denials: every observed scratch and exact-output mmap in selected
  populated, empty, cancellation and numerical-failure executions; explicit
  matching releases before exit and no leaked published owner on error.
- An independent dense/dictionary/Fraction model for seeded small dyadic
  matrices, plus ordered IEEE boundary cases, checks exact CSR structure and
  finite bits over native and typed backing/subviews. Test-only transport may
  be binary; no transport or Python implementation enters the production API.
- A large analytic sparse product verifies the absence of a dense fallback and
  exercises products with many rows, shared destinations and output fill-in.
- A small CSV weighted-path application composes coordinate construction,
  repeated sparse products, checked formatting and native byte I/O. It computes
  weighted paths of an exact positive length; it makes no shortest-path,
  normalization, convergence or exact-integer-count promise.

Root owns serialized compiler/native execution. Every command is bounded below
two minutes. Test the changed runtime boundary and meaningful regressions;
do not repeatedly run unrelated GPU/performance suites. Current target scope is
native Linux x86_64 code produced by the GPU compiler. Compiler failures get a
minimal reproduction rather than a production compiler/proof/ABI change here.

The accepted numerical model has 2,194 cases over two backing forms. Sixteen
reached allocation denials cover selected populated, empty, cancellation and
numerical-failure runs, with matching explicit releases. The analytic scale
gate checks all 327,674 entries of a 65,536-square product. The current
application groups cover 122 cases; the amended 34-case model includes a
rounded fourth power that distinguishes left association from repeated
squaring. See the [fixture receipts](../tests/fixtures/extended_library/sparse_product/README.md)
for exact execution scope. These finite checks advance the full library
roadmap; they do not establish formal correctness or broader target support.
