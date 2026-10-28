# Sparse matrix implementation contract

This increment supplies canonical binary64 compressed sparse rows (CSR),
independent owners, sparse arithmetic and sparse/dense composition. It advances
the full mathematics roadmap; sparse factorization/solvers and additional
formats remain separate deliverables. The implemented profile passes six
library runtime gates and four graph-program gates on Linux x86_64; the
[module guide](extended-sparse.md) records the accepted contracts and receipts.

## Shared types in `ext::sparse`

```lani
pub enum ErrorKind {
    InvalidLimits, Shape, Bounds, DimensionLimit, EntryLimit, WorkLimit,
    Offset, Column, Order, NonFinite, NumericalFailure, AllocationFailed
}
pub struct Error { kind:ErrorKind, row:i32, entry:i32 }
pub struct Limits { max_dimension:i32, max_entries:i32, max_work:u64 }
pub struct Triplet { row:i32, column:i32, value:f64 }
pub struct CsrView {
    rows:i32, cols:i32, offsets:core::slice::View<i32>,
    columns:core::slice::View<i32>, values:core::slice::View<f64>
}
pub struct Row { columns:core::slice::View<i32>, values:core::slice::View<f64> }
pub struct ProductFailure { error:Error, completed:i32 }
```

Defaults are dimension and entry caps of 1,048,576 and 100,000,000 work units.
Negative caps are invalid. Rows/columns are nonnegative and rows must leave
room for an i32 `rows+1` offset count. Every counted view has nonnegative
start/length with a representable sum. Backing validity and lifetimes are
manual caller preconditions; no structural mutation is allowed during use.

Offsets have exactly `rows+1` entries, start at zero, are nondecreasing and
end at `nnz`. Column/value lengths equal `nnz`. Every column is in `[0,cols)`;
columns increase strictly within each row. Stored values are finite. Explicit
signed zeros are legal stored entries; absent entries read as positive zero.
`nnz` counts stored entries. Empty shapes retain their dimensions.

The representation follows the [SciPy CSR contract](https://docs.scipy.org/doc/scipy/reference/generated/scipy.sparse.csr_matrix.html).
Lanius additionally requires finite values and explicit caller limits. Input
coordinate duplicates are coalesced in original input order after sorting by
row/column/original ordinal. A nonfinite intermediate sum fails; exact-zero
coalesced results are omitted. Other newly computed exact-zero entries are
omitted; `from_csr`, clone and transpose preserve explicitly stored zeros.

## Modules and public operations

`ext::sparse` imports no allocator or host service. It provides `default_limits`,
`view(rows,cols,offsets,columns,values,limits)`, `validate(view,limits) ->
Result<i32,Error>` (nnz), `row(view,index,limits) -> Result<Row,Error>`,
`get(view,row,col,limits) -> Result<f64,Error>` and
`matvec_into(view,x:View<f64>,out:View<f64>,limits) ->
Result<i32,ProductFailure>`. A failed metadata/input/work preflight writes no
output. Numerical failure preserves complete previously written output rows;
`completed` names that prefix. Output backing must be disjoint from all inputs.
Dot products use increasing column order and ordinary binary64 product/add;
nonfinite products/sums fail and gradual underflow remains IEEE behavior.

`ext::sparse_matrix` owns three `alloc::vec` buffers in `Matrix`, with row/column
shape. It supplies `zeros`, `from_csr`, `from_triplets`, `transpose` and the
methods `borrow`, `view`, `nnz`, `destroy`, `try_clone(limits)`. Constructors
return `Result<Matrix,ext::sparse::Error>`. Results own independent backing;
errors release partial owners and preserve inputs. Copies alias cleanup
authority and are never independent owners. Destroy resets to a zero shape;
an empty destroyed owner is not promised to supply a valid CSR view.

`ext::sparse_ops` supplies `add`, `sub`, `scale`, `scale_rows`, `scale_columns`
returning new sparse owners; `matvec` returning `alloc::vec::Vec<f64>`;
`from_dense`, `to_dense` and `matmul_dense` using existing `ext::linalg`
matrix types. Sparse operands are CsrViews. Scalar factors are finite; vector
factor lengths match the relevant axis. All finite factor values are checked,
including unused columns. Shapes, limits and numerical errors are explicit.
These operations publish no owner on failure. Sparse/sparse multiplication
is a separate remaining operation; no dense fallback will pretend to supply it.

## Validation, failure and work

Structural validation checks limits/shape/view metadata and caps before array
reads, then offset structure, then column order/range and finite values.
Errors identify a row and entry where available, otherwise `-1`. Operations
must not allocate before validating complete inputs and phase admission.
Allocation failure is typed. Floating-point operation order and finite range
are part of the numerical profile, not exact arithmetic or a uniform accuracy
guarantee. Inputs and owners remain immutable until returned owners/views end.

Work units are documented dominant phase estimates, following the existing
dense-library policy: validation and linear passes charge their logical span;
coordinate sorting uses `nnz*(1+ceil(log2(max(nnz,1))))`; products charge their
actual sparse/dense shape estimate. They are not CPU instructions, cumulative
across independent calls, or wall-clock deadlines. Each implementation must
record its exact admission formula in the final guide and avoid overflowing
estimate arithmetic before comparing with the budget.

## Acceptance

Executable contracts cover malformed metadata/offsets/columns/order, empty
shapes, explicit zeros, duplicate aggregation/cancellation, bounds/limits,
finite arithmetic failures and prefix publication. Independent binary fixture
models compare with dense dictionary/Fraction references over seeded sparse
inputs, strided backing and sparse/dense compositions. Focused native owner
and allocation-denial cases cover partial-construction cleanup.

A bounded CSV graph-walk program assembles weighted directed edges, normalizes
each nonempty outgoing row, gives dangling vertices a self-loop, transposes
the transition matrix and advances a source mass with repeated sparse matvec.
It validates before output and exercises actual storage/transpose/product APIs.
Its reference uses an independently materialized transition matrix. Every
compiler/native command stays under two minutes. No compiler, IR, ABI, extractor
or proof production change is included; missing support gets a minimal reducer.

The accepted numerical model covers 3,886 cases across 17 modes. The analytic
scale gate uses 65,536 rows and 196,606 stored entries, with a full native
lifecycle observation of 1,365.553 ms. The graph program passes 113 process
cases. These are finite execution profiles, not formal proofs or user-program
GPU execution. A retained [item-import priority reduction](../tests/fixtures/stdlib_compiler_state/item_import_priority/README.md)
and executed qualified control record the compiler dependency encountered by
the application; qualified module calls leave the selected library APIs usable.
