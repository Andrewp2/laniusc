# Numerical CSV analysis and regression

[`sample_programs/library/data_analyze.lani`](../sample_programs/library/data_analyze.lani)
reads a finite binary64 CSV table from stdin, summarizes each column, and can
fit a least-squares regression. Parsing, decimal conversion, statistics,
sorting, matrix factorization and output are implemented in Lanius. The
program uses [`ext::csv`](extended-csv.md),
[`ext::statistics`](extended-statistics.md),
[`ext::linalg`](extended-linalg.md), `ext::cli`, `core::float_decimal`,
`core::fmt`, owned vectors and native descriptor I/O. Python and NumPy appear
only in the independent test oracle.

The verified executable target is **x86_64 Linux**. The GPU compiler produces
that executable; this evidence does not establish GPU-kernel execution, Wasm
or other host targets.

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  --stdlib-root stdlib --source-root extended \
  sample_programs/library/data_analyze.lani -o target/stdlib-work/data-analyze
printf 'x,y\n1,3\n2,5\n3,7\n' | \
  timeout --kill-after=2s 100s target/stdlib-work/data-analyze --header --fit
```

## Input and options

```text
data-analyze [--header] [--fit [--no-intercept]]
             [--max-input-bytes N] [--max-rows N] [--max-columns N]
             [--max-elements N] [--max-work N] [--max-output-bytes N]
```

The [CSV dialect](extended-csv.md#dialect) accepts LF or CRLF separators, a
final unterminated record, and quoted fields. All records must have the same
width. With `--header`, the first record supplies column names and is excluded
from the data. Header names may be empty, repeated, Unicode, or contain quoted
commas, quotes and newlines; columns retain their zero-based indices. Without
`--header`, output names are empty. At least one numerical row is required.

Each data field is parsed directly to binary64 using the
[decimal conversion grammar](stdlib-float-decimal.md). A leading plus,
leading zeroes, `.5`, `1.`, and decimal exponents are accepted. Whitespace,
empty fields and malformed numbers are rejected. NaN, infinity and decimal
overflow to infinity are rejected. Signed zero and underflow to signed zero
are accepted. Fields, including header names, have a fixed 1,024 decoded-byte
limit; numerical mantissas additionally have the converter's 768-digit limit.
CSV syntax bytes count toward the input limit, while field limits count decoded
UTF-8 bytes. Input is read in 1 KiB chunks and CSV records are reused.

`--fit` treats the final column as the response and every preceding column as
a predictor. It requires at least two columns. An intercept is included first;
`--no-intercept` removes it and requires `--fit`. The number of rows must be at
least the number of fitted parameters; square systems are accepted. The
linear algebra library uses Householder QR, preserving the supplied data, with
its relative rank tolerance of `1e-12`. Dependent or sufficiently close to
dependent designs return `rank-deficient`; a minimum-norm solution is not
provided. The program uses compensated sums for predictions and the matrix
library's scaled norm for residuals.

Options accept `--name=N` or `--name N`. Limit values are unsigned decimal
integers. Duplicate options, operands and unknown options are errors. `--help`
(or `-h`) must be the only argument and succeeds without reading stdin.

## CSV output

Output begins with this exact header and uses CRLF records:

```csv
record,column,name,metric,value
```

Every result record has five fields. Names are always CSV quoted, and embedded
quotes are doubled. Values use deterministic shortest round-trip binary64
decimals from `core::fmt`; no locale or host formatting is involved.

| Record | Column/name | Metrics, in output order |
| --- | --- | --- |
| `column` | Input index and optional header name | `count`, `mean`, `sample_sd`, `min`, `max`, `median` |
| `coefficient` | `-1` / `intercept`, then predictor indices/names; with `--no-intercept`, predictor indices/names only | `estimate` |
| `fit` | Empty column and empty name | `observations`, `parameters`, `residual_dof`, `residual_norm`, `residual_sum_squares`, `rmse` |

Column records come first, ordered by input column. The `sample_sd` metric is
omitted for a one-row table because sample variance is undefined. Median is
Hyndman–Fan type 7 at probability 0.5, including the midpoint for even sample
sizes. `count`, `observations`, `parameters`, and `residual_dof` are exact
integer-valued binary64 values within the application limits.

With `--fit`, coefficient records follow in design-column order. Fit metrics
come last. For residuals `e = y - A * coefficients`, `residual_norm` is the
Euclidean norm, `residual_sum_squares` is its square, and `rmse` is the norm
divided by `sqrt(observations)`. `residual_dof` is observations minus fitted
parameters; `rmse` always uses observations, including when residual degrees
of freedom is zero.

For the example above, `x` has count 3, mean 2, sample SD 1, minimum 1, maximum
3 and median 2. `y` has mean 5 and sample SD 2. The coefficients are
approximately intercept 1 and slope 2. Floating-point factorization can leave
a small residual even for an exactly linear input.

Summaries follow the statistics library's finite arithmetic contract. Some
finite inputs cause a nonrepresentable intermediate, variance, residual or
squared residual norm; these produce an explicit `numerical-failure`. Binary64
underflow can round tiny variances or squared norms to zero. The program does
not promise exact real arithmetic or successful fits for every finite table.

## Resources, ownership and errors

| Limit | Default | Maximum accepted |
| --- | ---: | ---: |
| Input bytes | 16,777,216 | 67,108,864 |
| Numerical rows | 100,000 | 1,000,000 |
| Columns | 64 | 256; minimum 1 |
| Numerical elements | 1,000,000 | 8,000,000 |
| Output bytes | 1,048,576 | 16,777,216 |
| Logical work | 1,000,000,000,000 | 18,446,744,073,709,551,615 |

Zero is accepted for all limits except columns; a nonempty analysis then fails
at the relevant boundary. Rows exclude the optional header. Element limits
bound the retained numerical table and each matrix buffer. They do not express
a total process allocation ceiling. Storage includes the table, retained packed
header, reusable CSV record, two column buffers, the complete output buffer,
and, during fitting, the design matrix, QR factors, coefficients and residuals.
Vectors may retain geometric spare capacity. The output buffer reserves its
configured size, so lowering that limit also reduces its allocation.

Logical work is a conservative application budget, distinct from elapsed time
or instruction counts. Before each numerical parse and output value conversion,
the program reserves 1,000,000 units, matching the converter's per-call budget.
Each column reserves `sorted_work_bound(rows) + 8*rows` before accumulation
and sorting. Design construction reserves `2*rows*parameters`. For one response,
QR reserves `8*rows*(parameters+2)*(parameters+1) + 4*rows + parameters`.
Prediction, residual and norm work reserve `8*rows*parameters + 9*rows`.
Structural CSV and bounded text copying are additionally bounded by their byte,
row, column and output limits. Increasing a shape limit may also require raising
`--max-work`; there is no silent truncation.

| Exit | Meaning |
| --- | --- |
| 0 | Complete results or help written |
| 2 | Invalid arguments, CSV/UTF-8/number input, empty data, shape/rank/numerical failure, or resource limit |
| 3 | Argument access or descriptor I/O failure, including failed diagnostics or zero-progress writes |
| 4 | Allocation failure |

Diagnostics begin with `data-analyze:` and include a reason and `stage`.
CSV grammar and UTF-8 errors include the zero-based raw input `byte` offset;
unequal-width records include a zero-based CSV `row`. Number errors identify
both CSV `row` and `column`, counting the header as row zero when present.
Input I/O failures include the number of bytes already read. Summary failures
identify the input column; shape and rank failures during fitting concern the
whole design. Argument, allocation and output failures identify their stage.

The program validates the whole input and prepares the complete result in memory
before writing any stdout. Input, analysis, allocation and configured output
limit failures therefore leave stdout empty. Output I/O failures may leave a
prefix of the prepared CSV. Reads and writes retry EINTR, short writes advance
the remaining range, and zero-progress writes fail. If writing stderr fails,
exit status is 3. Every owned record, vector and matrix is explicitly destroyed
on success and failure.

## Executable evidence

On 2026-10-23, all three groups in
[`tests/extended_data_analyze_execution.rs`](../tests/extended_data_analyze_execution.rs)
passed in 11.63 seconds:

- Python `csv`, `statistics`, and NumPy compare the actual executable's
  statistics and QR coefficients over quoted Unicode/multiline headers, ties,
  signed zero, subnormals, one-row data, square and tall fits, and fitting with
  and without an intercept. An independently generated 4,096×4 design has two
  close predictor columns. Results are also checked for deterministic bytes.
- Malformed UTF-8 and CSV, invalid/nonfinite numbers after valid rows, inconsistent
  widths, rank deficiency, numerical overflow, invalid arguments, resource limits
  and exact input/output boundaries fail explicitly with no partial results.
- Every allocation observed in a successful fitted analysis is denied individually;
  syscall traces check complete cleanup. Tests cover each observed input/output
  syscall failing, EINTR retries, zero and short writes, `/dev/full`, failed
  diagnostics and failed help delivery. The successful short-write injection
  advances past the injected count, as required by the writer contract; strace
  itself suppresses those bytes rather than performing that write.

A native 4,096×4 run consumed 270,497 input bytes and produced 1,313 output bytes
in **942.805 ms**, including process startup and test-driver file I/O, with
compilation excluded. This is one observed sample, not a throughput guarantee.

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test extended_data_analyze_execution -- --nocapture
```
