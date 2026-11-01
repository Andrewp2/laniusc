# Sparse matrix multiplication

`ext::sparse_ops::matmul` extends the [canonical CSR family](extended-sparse.md)
with a sparse result from two sparse operands. The fixed
[product contract](library-sparse-product-plan.md) defines this increment.
The API is implemented in Lanius. All six new library gates and four real
application gates pass on native Linux x86_64; this finite increment is
accepted. Earlier CSR foundation receipts retain their source and API scope.

## API and result

```lani
pub fn matmul(a:ext::sparse::CsrView,
              b:ext::sparse::CsrView,
              limits:ext::sparse::Limits)
    -> core::result::Result<ext::sparse_matrix::Matrix,ext::sparse::Error>
```

Both operands must be complete canonical finite CSR views, and
`a.cols == b.rows`. The result has shape `a.rows` by `b.cols`, independent
offset/column/value buffers and strictly increasing columns within each row.
Computed values equal to either signed zero are omitted. Empty axes retain
their shape, including zero inner dimension. No operand or result is converted
to a dense matrix.

Every offset, column and stored value in both operands is validated, including
right-hand rows that no left entry visits. Stored input zeros remain legal
and unchanged. Valid read-only operands may alias, including multiplying a
square view by itself. Keep all backing live and immutable throughout both
passes; physical bounds and lifetimes remain manual preconditions.

On success, the caller receives one independent `Matrix` owner and must
eventually call `destroy()`. Plain copies alias its cleanup authority. On
error, no result owner escapes; partial output and scratch are released and
inputs remain unchanged. This API has no caller-visible partial-result
prefix.

## Arithmetic order and canonical output

For each output row `i`, traverse stored left entries in increasing inner
column `k`. For each entry `a[i,k]`, traverse the corresponding right row
`b[k,*]` in increasing output column `j`. Accumulate each output column from
positive zero using an ordinary binary64 product followed by addition:

```text
for k in stored columns of a.row(i), increasing:
    for j in stored columns of b.row(k), increasing:
        sums[j] = sums[j] + a[i,k] * b[k,j]
```

Missing structural terms are skipped. Explicit stored zeros are visited.
Each required product and partial sum must be finite. A nonfinite intermediate
returns `NumericalFailure { row:i, entry:left_entry }`; `entry` identifies the
logical slot in the left CSR column/value views. Later cancellation does not
recover an earlier overflow.

Only after accumulation are touched output columns sorted. Sorting changes
publication order without changing arithmetic order. A rounded `+0` or `-0`
sum is omitted; other finite values, including subnormals, are stored. There
is no epsilon threshold, compensated sum, fused multiply-add, arbitrary-range
scaling, exact-integer guarantee or uniform numerical error bound. Gradual
underflow and rounding follow the ordinary binary64 profile.

The column-marker/sum accumulator pattern has a mature implementation in
[SciPy's CSR multiplication source](https://github.com/scipy/scipy/blob/main/scipy/sparse/sparsetools/csr.h).
Lanius separately requires sorted canonical operands/results, finite
intermediates, typed allocation failures and explicit budgets. Production
implementation is Lanius; SciPy and native mathematics libraries are not
runtime dependencies.

## Scratch and two-pass ownership

Populated products use column-indexed markers and sums plus a touched-column
list: three reusable scratch buffers, each with capacity `b.cols`.
Their storage is `O(b.cols)`. Only touched columns are sorted and retired
between rows; there is no full output-column scan for every output row.

After complete input validation and operation work admission:

1. Allocate and initialize scratch.
2. Calculate rows to check numerical results and count actual rounded
   nonzeros.
3. Reserve exact output offsets, columns and values.
4. Repeat the same row calculations to fill canonical output, reusing scratch.
5. Release scratch and return the result owner.

Scratch is required to discover numerical results. Consequently,
`AllocationFailed` may precede an arithmetic failure that would be found in
the numerical prepass. A failure during any scratch/output allocation releases
earlier allocations. A structurally empty product allocates only output
offsets and requires no scratch, while preserving its full output shape.
Actual rounded cancellation to zero does not make a structurally populated
product eligible for that shortcut.

## Limits and work admission

Existing sparse defaults and error types are shared; import with
`--source-root extended`. Both operands obey their own dimension/entry caps
and independent validation work budget `rows+1+nnz`.

| Resource | Admission |
| --- | --- |
| Result rows | `a.rows < 536870911`, leaving room for the owned offset buffer |
| Result stored entries | At most `min(limits.max_entries,268435455)` actual rounded nonzeros |
| Scratch columns when structural products exist | `b.cols <= 268435455`, plus the ordinary dimension cap |
| Structurally empty product | No scratch-column hard ceiling; ordinary dimension, owned-row and work caps still apply |

The output entry cap counts values remaining after rounded cancellation,
so symbolic candidate count alone cannot reject an otherwise fitting result.
Scratch is dimension-bounded independently of `max_entries`; a wide result
with few nonzeros can still require large scratch. These bounds constrain
individual buffers, not total resident memory or allocator CPU.

For the separate operation estimate, define:

- `R = a.rows`, `C = b.cols`, `NA = nnz(a)`;
- `P = sum(nnz(b.row(a.column[e])))` over **every stored left entry**;
- `L = ceil_log2(max(C,1))`.

`P` counts structural scalar products, including explicit zero coefficients.
It is derived only after both inputs validate. Its scan visits the left
entries and the selected right-row offsets, without multiplying values.
The operation is admitted when:

```text
3*(R+1+NA) + 2*C + 2*P*(3+L) <= limits.max_work
```

This conservatively covers the structural scan, two row walks, scratch
initialization, both numerical passes, touched-column sorting and retirement.
It also applies to structurally empty products, even when they do less actual
work. Arithmetic widens before addition and uses the remaining budget divided
by the product coefficient before multiplication; even `max_work=u64::MAX`
must not permit a wrapped estimate. Work rejection precedes scratch/output
allocation and scalar multiplication.

Validation and operation estimates are admitted independently against the
same cap. They follow the existing dominant-phase policy; they are neither
a cumulative instruction ledger nor a wall-clock deadline. A repeated-product
application must impose its own cumulative policy when needed.

## Errors and positions

Admission first checks limits, output dimensions and owned offset capacity,
then validates the complete left and right operands, then checks inner-shape
compatibility. It admits the product work estimate before choosing the
structural-empty shortcut or otherwise checking the scratch-column ceiling.
Scratch and output allocation follow those checks. This ordering is part of
the current failure contract.

Input errors retain the shared CSR validation contract. A malformed offset,
column, order or stored value identifies that operand's logical row/entry;
the error type does not add an operand tag. Global shape/work/cap admission
errors use `row=-1, entry=-1`.

| Failure | Meaning and position |
| --- | --- |
| `Shape` | Invalid or incompatible shapes |
| `DimensionLimit` | Configured dimension, owned-row or required scratch capacity is exceeded |
| `EntryLimit` | Input entry cap, or too many actual output nonzeros; a discovered output excess uses the output row and **output column** in `entry` |
| `WorkLimit` | Shared validation or separate product estimate exceeds its cap |
| `NumericalFailure` | Nonfinite product/partial sum; output row and **left CSR slot** |
| `AllocationFailed` | Scratch or exact output storage cannot be allocated |

`InvalidLimits`, `Bounds`, `Offset`, `Column`, `Order` and `NonFinite` retain
their meanings in the [shared guide](extended-sparse.md#limits-work-and-errors).
In particular, unused nonfinite right-hand values still reject during full
validation.

## Verification and remaining scope

All six new registered library tests pass on the source identity below:

| Gate | Accepted receipt under `target/stdlib-work/` |
| --- | --- |
| Contracts, allocation-free rejections and two reached-allocation-denial groups | Four tests, 13.11s; `sparse-product-contracts-first.log` |
| Independent dense/Fraction/ordered-binary64 model | One test, 7.45s; `sparse-product-model-first.log` |
| Large analytic sparse product | One test, 8.38s; `sparse-product-scale-first.log` |

Contracts exercise rectangular/empty products, canonical sorting, aliasing of
read-only operands, independent output, signed/explicit zeros, cancellation
under entry caps, finite-range failures, malformed inputs, exact work
boundaries and scratch limits. A populated eight-column result with output
entry cap one checks that scratch capacity follows columns independently
of `max_entries`. Descriptor/work rejection cases allocate nothing.

The denial groups reach seven populated/structurally-empty and nine
cancelled/numerical-failure allocation errors: 16 reached operation denials.
Every observed baseline allocation is denied once for these inputs; every
successful mapping is matched with an explicit pre-exit release by full
address and size. Baseline numerical failures and each allocation error
publish no result owner and preserve inputs. This finite single-denial scope
does not establish arbitrary failure schedules or formal leak freedom.

The independent model passes one registered runtime test in 7.45s, recorded
in `target/stdlib-work/sparse-product-model-first.log`: 2,194 cases, two backing
forms and seed `0xc5a520261028`. Its test-only oracle materializes dense
coordinate dictionaries, checks bounded dyadic products with exact Fractions
and models increasing-inner-column binary64 order for boundary cases. It
compares canonical storage, error positions and finite bits exactly, including
subnormals, rounded zeros, cancellation, fill-in and finite-range failures.

The large analytic product gate passes as one registered runtime test in
8.38s, recorded in `target/stdlib-work/sparse-product-scale-first.log`.
It computes a 65,536-row tridiagonal square with 196,606 input entries,
327,674 output entries and 589,814 structural products; its exact work
estimate is 23,330,433. The whole native process lifecycle was 1206.798ms,
including construction, computation, assertions and cleanup. This observation
does not isolate kernel throughput.

Two selected foundation semantic regression tests also pass on the current
module in 11.70s, recorded in
`target/stdlib-work/sparse-product-foundation-regression.log`. Other foundation
receipts retain their older source identities; no full old-suite rerun is
claimed.

The accepted library source is `extended/ext/sparse_ops.lani`, SHA-256
`bc4fb71475ffdf78934de8eefa3c67aeeeaa656e4a29abfa33b4c4d85f014e35`.
The [fixture guide](../tests/fixtures/extended_library/sparse_product/README.md)
records reproduction commands, test-source identities and finite fault scope.
The executed profile is native Linux x86_64 CPU output from the GPU compiler;
device-side GPU execution is unclaimed.

The [sparse-paths application](extended-sparse-paths.md) composes coordinate
construction, repeated left-associated sparse products, CSV formatting and
native byte I/O to compute signed weights of walks of an exact positive
length. Its guide records separate application bounds, errors and evidence;
all four registered application groups are accepted, covering model 34,
rejection 37, CLI 36 and I/O 15: 122 unique process cases. The first four-test
command passed in 20.45s with the earlier 33-case model, recorded in
`target/stdlib-work/sparse-paths-runtime-first.log`. The amended 34-case model
separately passed in 14.73s, recorded in
`target/stdlib-work/sparse-paths-model-association.log`; it replaces that
earlier model receipt. The added rounded scalar `1.1^4` case verifies the
specified left association. These overlapping model runs are not added as
distinct cases. The application supplies no shortest-path, normalization or
convergence algorithm.

Sparse factorizations/solvers, additional storage formats, automatic ownership,
formal proofs and broader target execution remain separate work. Earlier
foundation models, scale checks and allocation-denial receipts do not cover
this new API.
