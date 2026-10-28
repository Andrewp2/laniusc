# Canonical sparse matrices

This increment adds finite binary64 compressed sparse rows (CSR), independent
owners and sparse/dense composition. The shared implementation contract is
the [sparse plan](library-sparse-plan.md). All three modules are present;
the contracts below describe their source behavior. All six registered
library gates and four graph-application gates pass on native Linux x86_64.
This finite increment is accepted. No compiler production change, native
mathematics service or Wasm dependency is part of this increment.

## Layers and representation

| Module | Responsibility |
| --- | --- |
| `ext::sparse` | Borrowed CSR admission, validation, row/element access and caller-output matvec; no allocation or host service |
| `ext::sparse_matrix` | Independent canonical CSR owners, coordinate construction, clone and transpose |
| `ext::sparse_ops` | New owned sparse arithmetic, vector results and dense composition |

Import with `--source-root extended`. CSR keeps shape explicitly, including
empty shapes. `CsrView { rows, cols, offsets, columns, values }` borrows three
counted views. Its canonical invariants are:

- `rows` and `cols` are nonnegative, and `rows+1` fits `i32`;
- offsets have exactly `rows+1` entries, start at zero, never decrease and end
  at `nnz`;
- column and value lengths both equal `nnz`;
- each column is in `[0,cols)` and columns increase strictly within each row;
- every stored value is finite; explicit `+0` and `-0` are legal.

General matrices accept negative values too. A graph application's
nonnegative edge-weight rule is separate from CSR admission.

Row `r` occupies the column/value slots in
`[offsets[r],offsets[r+1])`. `nnz` counts stored entries, including zeros.
This layout, sorted uniqueness and stored-zero distinction follow the
[SciPy canonical CSR definition](https://docs.scipy.org/doc/scipy/reference/generated/scipy.sparse.csr_matrix.html).
Finite values and explicit limits are additional Lanius requirements. No
SciPy dependency or promise of identical floating arithmetic is implied.

`CsrView` and `Row { columns,values }` own no storage. Their arrays retain
logical view order, nonzero starts and the backing slice's typed physical
stride. Keep all backing live and unchanged throughout calls and borrowed
uses. Public metadata is not a way to forge physical bounds or bypass owner
rules; the current language enforces neither those lifetimes nor uniqueness.

## Borrowed API

| Operation | Result |
| --- | --- |
| `default_limits()` | `Limits { max_dimension:1048576, max_entries:1048576, max_work:100000000 }` |
| `view(rows,cols,offsets,columns,values,limits)` | `Result<CsrView,Error>` after complete canonical validation |
| `validate(csr,limits)` | `Result<i32,Error>` containing `nnz` |
| `row(csr,index,limits)` | `Result<Row,Error>` borrowing the selected column/value spans |
| `get(csr,row,column,limits)` | `Result<f64,Error>`; exact stored value or positive zero for an absent entry |
| `matvec_into(csr,x,out,limits)` | `Result<i32,ProductFailure>`; success returns the number of completed output rows |

`row` and `get` admit metadata/limits, check query bounds, then revalidate the
complete CSR. `get` searches the selected sorted row by binary search after
that validation; it is not an unchecked constant-time element accessor.
Stored signed-zero bits survive lookup. These queries do not cache a trusted
validation result, copy backing or normalize the structure.

Validation checks limits, shapes, counted-view arithmetic and caps before
reading any array. It validates every offset before reading any column/value
pair. It then scans rows in order, checking column range, strict order and
value finiteness. Column/order errors at a slot precede that slot's finite
value check. Full input backing still remains a caller precondition: logical
metadata cannot establish its physical allocation length.

### Matvec arithmetic and output prefix

`x` has exactly `cols` entries; `out` has exactly `rows`. Output backing must
be disjoint from **every** input backing, including offsets and columns.
This is a manual precondition, not a runtime overlap detector. Read-only inputs
may alias under their ordinary backing rules.

Descriptor/shape/work checks precede complete CSR validation. Every `x`
element must then be finite, including columns unused by the sparse matrix.
All these preflight failures leave output unchanged and report
`ProductFailure { error, completed:0 }`.

Each dot product starts at positive zero, visits stored entries in increasing
column order and uses ordinary binary64 multiplication followed by addition.
A nonfinite product or partial sum returns `NumericalFailure` at its CSR
`row,entry`. The failing row is not written. `completed=r` means exactly the
first `r` output rows were published; the failed row and suffix retain their
previous contents. Complete earlier rows are not rolled back. Empty rows
publish zero. Subnormal rounding and gradual underflow remain ordinary
binary64 behavior; later cancellation cannot rescue an earlier overflow.

## Independent CSR owners

`ext::sparse_matrix::Matrix` owns three `alloc::vec` buffers: offsets, columns
and values, plus its shape. The free constructors below take sparse `Limits`
and return `Result<Matrix,ext::sparse::Error>`:

| Constructor | Behavior |
| --- | --- |
| `zeros(rows,cols,limits)` | No stored entries, with the required `rows+1` zero offsets; even a 0-by-0 matrix owns one offset |
| `from_csr(csr,limits)` | Validates and copies all three logical spans into independent backing, preserving stored signed zeros |
| `from_triplets(rows,cols,input,limits)` | Sorts and coalesces a borrowed `View<Triplet>` into canonical rows; input is unchanged |
| `transpose(csr,limits)` | Returns an independent `cols`-by-`rows` owner; stored values, including signed zeros, are copied without recomputation |

Methods are `borrow()`, `view()`, `nnz()`, `try_clone(limits)` and `destroy()`.
`try_clone` has the same validation/copy behavior as `from_csr`. Returned
views borrow the owner; owner destruction or transfer ends their validity.
Constructors preflight complete input and their admitted phase work before
allocating output. Errors publish no owner, release partial storage and
preserve input. Coordinate coalescing can fail after allocating its private
sorting stage; that stage is released too.

A plain Matrix copy aliases cleanup authority. Keep one active owner, transfer
it once and destroy it explicitly. No deep copy or automatic destruction is
implicit. Destroy resets all buffers and shape to zero; that cleanup state is
not a canonical empty CSR view, because its required single offset is absent.
Use `zeros(0,0,limits)` when a valid empty matrix is needed.

### Coordinate order and stored zeros

Triplet input is validated before the sorting allocation. The sort key is
`(row,column,original ordinal)`. Equal coordinates are summed with ordinary
binary64 additions in their **original input order**. A nonfinite intermediate
sum returns `NumericalFailure` at that original ordinal, even if later terms
could cancel it. No compensated or mathematically exact duplicate sum is
promised. A coalesced result equal to either signed zero is omitted.

`from_csr`, clone and transpose preserve explicit zeros rather than silently
calling an eliminate-zeros pass. Transpose uses count/prefix/scatter in linear
spans; traversing input rows in order produces sorted output columns. It does
not share or reinterpret the input's three buffers.

## Owned arithmetic and dense composition

Every `ext::sparse_ops` function takes sparse `Limits` and returns
`Result<Output,ext::sparse::Error>`. Sparse inputs are borrowed `CsrView`s.

| Operation | Output and shape |
| --- | --- |
| `add(a,b,limits)` / `sub(a,b,limits)` | New CSR Matrix; input shapes must match |
| `scale(a,factor,limits)` | New CSR Matrix of the same shape; finite scalar factor |
| `scale_rows(a,factors,limits)` | New CSR Matrix; factor view has exactly `a.rows` finite entries |
| `scale_columns(a,factors,limits)` | New CSR Matrix; factor view has exactly `a.cols` finite entries |
| `matvec(a,x,limits)` | New `alloc::vec::Vec<f64>` of length `a.rows`; `x.len()==a.cols` |
| `from_dense(a,limits)` | New CSR Matrix from `ext::linalg::MatrixView` |
| `to_dense(a,limits)` | New `ext::linalg::Matrix` with the CSR shape |
| `matmul_dense(a,b,limits)` | New dense Matrix: `a.rows` by `b.cols`, requiring `a.cols==b.rows` |

Inputs, factor vectors and phase work are completely admitted before output
allocation. Every factor is finite-checked, including unused columns and
factors on empty rows. Dense inputs follow the existing dense view's checked
shape/stride rules and every logical element is finite-checked, even if the
sparse coefficient is absent or the product has no output cells. Negative
logical dense strides are rejected; the underlying slice's physical native
stride is a separate representation detail.

Addition/subtraction merge sorted rows. Scaling visits the stored entries.
Both use a numerical/count pass before exact output reservation, then a fill
pass; inputs must remain unchanged through both. Result entries equal to
either signed binary64 zero are omitted, including unmatched stored zeros in
add/sub and underflow-to-zero products. No approximate-zero threshold is used.
`from_dense` similarly omits both zero signs. `to_dense` starts absent cells at
positive zero and directly copies stored values, preserving an explicit `-0`.

Matvec and sparse/dense product use increasing CSR inner-column order and
ordinary binary64 products/additions. Nonfinite intermediates fail even when
later cancellation would make a finite mathematical result. The owned matvec
wrapper discards any private prefix produced by the borrowed kernel and
releases its vector before returning the error. Sparse/dense product likewise
releases its partial dense result. **No owned result escapes on failure**;
inputs are preserved. This differs from caller-output `matvec_into`, whose
completed row prefix remains published.

These algorithms do not supply compensation, scaling for arbitrary dynamic
range, correctly rounded results or a uniform error bound. Gradual underflow
can lose nonzero mathematical terms; sparse zero omission follows the rounded
binary64 value. No host BLAS or other native mathematics library is called.

## Limits, work and errors

`Limits { max_dimension,max_entries,max_work }` applies to each call. Negative
dimension/entry caps are `InvalidLimits`. Dimensions above their cap return
`DimensionLimit`; stored count above its cap returns `EntryLimit`. A negative
shape or a row count that cannot admit `rows+1` is `Shape`. Counted views need
nonnegative start/length whose sum fits `i32`.

Work admission uses dominant phase estimates, following the existing
[dense-library policy](extended-linalg.md#resource-limits-and-failures). It is
neither a cumulative instruction counter nor a wall-clock deadline. Separate
phases are compared independently with the same `max_work`:

| Phase | Estimate |
| --- | --- |
| Full CSR validation | `rows+1+nnz` |
| Caller-output matvec, separately from validation | `cols+rows+nnz` |
| `zeros` | `rows+1` |
| `from_csr` / `try_clone` | `2*(rows+1)+3*nnz` |
| `from_triplets`, with raw input count `k` | `rows+1+5*k+k*(1+ceil(log2(max(k,1))))` |
| Owned transpose | `2*(rows+1)+3*(cols+1)+5*nnz` |
| Add/sub | `2*(rows+1+nnzA+nnzB)` |
| Scalar/row/column scaling | `2*(rows+1+nnz)+factor_count`, where factor count is `0`, `rows` or `cols` |
| Owned matvec | `cols+rows+nnz` |
| Dense input validation | `dense_input_count` |
| From dense | `2*dense_count+rows+1` |
| To dense | `dense_count+rows+1+nnz` |
| CSR times dense B | `dense_input_count+dense_output_count+nnz*B.cols+rows+1` |

The implementation widens extents before arithmetic; these owner formulas
are bounded by admitted signed-32 spans. The `from_csr` estimate includes its
validation and copy passes. Each CSR validation and dense-input validation
remains a separate admission inside operations. Product work uses division
before multiplication so a rejected estimate cannot wrap. A multi-operation
pipeline must impose its own cumulative policy if required.

Owned values cannot exceed 268,435,455 `f64` entries. Row-offset storage holds
at most 536,870,911 `i32` entries, so an owner's row count is at most
536,870,910, even if a caller raises `max_dimension`. Triplet input also has
the generic vector capacity bound
`floor(2147483647 / size_of<Indexed>())`, where the private staging entry holds
row, column, original ordinal and value. The raw triplet count must fit these
entry caps **before** coalescing, even when duplicates would cancel. These
are individual-buffer limits, not a cumulative live-memory or RSS budget.
Every dense input/output logical element count and the owned matvec result
length must also fit `max_entries` and the `f64` ceiling. A sparse matrix can
therefore be valid while its dense conversion returns `EntryLimit`. Dense
input caps apply before conversion even if most input cells are zero.

`Error { kind,row,entry }` uses zero-based logical positions. CSR entry errors
identify a slot in the selected column/value views, independent of their
physical starts. An unavailable coordinate is `-1`; a bad vector input uses
`row=-1, entry=column`. Offset failures identify the affected row when one
exists. For triplets, `entry` is the original input ordinal and `row` retains
the supplied row, including an invalid one. Dense finite-input checks use
the dense row and flattened row-major logical entry index. Numerical sparse
products identify the CSR row/entry; the dense output column is not encoded
in that error. Metadata/shape failures generally use `-1,-1`; an output entry
cap reached during sparse arithmetic identifies the producing row/entry.

| `ErrorKind` | Meaning |
| --- | --- |
| `InvalidLimits` | Negative dimension or entry cap |
| `Shape` | Invalid/incompatible shape or CSR buffer lengths |
| `Bounds` | Malformed counted view or queried row/column |
| `DimensionLimit` / `EntryLimit` / `WorkLimit` | The corresponding admission cap is exceeded |
| `Offset` | First, monotonic, range or final offset invariant fails |
| `Column` | A stored column lies outside the shape |
| `Order` | Columns within a row are unsorted or duplicated |
| `NonFinite` | A stored, scalar, vector-factor or dense input is NaN or infinite |
| `NumericalFailure` | A required product, partial sum or result is nonfinite |
| `AllocationFailed` | The owner/operation layer cannot allocate storage |

## Executed evidence and remaining scope

Six registered library tests pass across four focused commands, using the
GPU compiler's native Linux x86_64 CPU output:

| Gate | Accepted evidence | Runtime log under `target/stdlib-work/` |
| --- | --- | --- |
| Borrowed and owner semantic contracts | Two tests, 11.01s; malformed descriptors, canonical order/zeros, exact caps, output prefixes, owner independence and cleanup | `sparse-contracts-owners-first.log` |
| Reached allocation denials | Two tests, 9.92s; 18 constructor/clone/merge and 15 scale/product/conversion operation failures | `sparse-allocation-denials-first.log` |
| Independent numerical model | One test, 8.15s; 3,886 cases, 17 modes, two backing forms, seed `0xc5a20261028` | `sparse-model-qualified.log` |
| Analytic sparse scale | One test, 9.10s; 65,536-by-65,536 tridiagonal with 196,606 stored entries | `sparse-scale-first.log` |

The pure contracts issue no memory-allocation syscalls. Owner traces match
successful mappings with explicit pre-exit releases by full address and size.
The 33 reached operation-allocation failures exclude separately marked clone
input-owner setup denials. Each observed operation allocation site is denied
once on the selected inputs; these finite campaigns establish neither every
possible failure schedule nor formal leak freedom. A preflight regression
uses inaccessible vector/factor backing with a rejected work estimate to
check admission before input scanning.

The test-only numerical oracle independently materializes dense dictionaries,
checks bounded dyadic cases with exact Fraction arithmetic and models ordered
binary64 arithmetic for non-dyadic, extreme and subnormal cases. It compares
finite result bits exactly. Both backing forms exercise their logical view
order; tested `i32` storage strides are `+4` and both tested `f64` strides are
`-8`. An initial fixture assumption about those strides was corrected without
a production compiler or borrowed-kernel change. Positive physical `f64`
stride is not claimed by these receipts.

The analytic scale gate assembles reversed COO input, transposes, adds,
multiplies by ones and a ramp, and forms a two-column dense product. Dense
conversion rejects the 4,294,967,296 implicit cells with `EntryLimit`.
Its whole native process lifecycle was 1365.553ms, including construction,
all operations, assertions, destruction and harness work. This observation
does not isolate a kernel or establish a compiler-speed ratio.

Accepted production SHA-256 identities are:

| Source | SHA-256 |
| --- | --- |
| `extended/ext/sparse.lani` | `e7adc62eee158635d202b090c25d5ed8c6faa144db373aa97e35863d33f2cc9d` |
| `extended/ext/sparse_matrix.lani` | `9fdae36cfe679cc5fb175ad268978bbfd2921b31c1ca3e30fd490dc729b9e207` |
| `extended/ext/sparse_ops.lani` | `fa34680de882eb094559f52b43251cd96bb456a0108067c04712df896d400d6d` |

The [fixture guide](../tests/fixtures/extended_library/sparse/README.md) records
commands, test-source identities and finite evidence scope. Borrowed prefix
failures and atomic owned results remain distinct contracts. These tests
supply no uniform numerical error bound or formal proof.

The [graph-walk program](extended-graph-walk.md) assembles ordered input
triplets, obtains outgoing sums with real matvec, normalizes finite
nonnegative rows, inserts dangling self-loops, transposes and repeatedly calls
owned matvec. It uses no production dense graph matrix. Its finite walk,
numerical drift, cleanup and application bounds are documented separately;
it does not promise exact mass conservation or PageRank behavior.
All four registered application tests pass in 16.31s, covering model 32,
rejection 33, CLI 38 and I/O 10: 113 process cases. The accepted receipt is
`target/stdlib-work/graph-walk-runtime-module-import.log`. Its test-only
reference builds dense transitions independently and performs exact Fraction
walks; the application guide retains its comparison tolerances and finite
I/O/fault scope. The library model, allocation-denial, analytic scale and
application groups are separate evidence, not one combined case count.

An [item-import priority limitation](../tests/fixtures/stdlib_compiler_state/item_import_priority/README.md)
remains in the compiler: an explicitly selected `core::slice::view` can lose
to the sparse module's different `view` name. The typed reduction rejects
with `LNC0006`; the same-import qualified-call control compiles and executes.
The application imports `core::slice` and uses `core::slice::view` explicitly.
This name-resolution dependency has an executed workaround. No compiler
production source was changed.

Sparse/sparse multiplication, sparse factorizations/solvers and additional
storage formats remain future work. No dense fallback supplies those APIs.
The intended graph application is a finite weighted walk, not PageRank or
a stationary-distribution/convergence algorithm. Other host/device targets,
automatic ownership and formal proofs remain unclaimed.
