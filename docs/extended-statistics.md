# Numerical statistics

`ext::statistics` provides portable binary64 descriptive statistics, compensated
sums, Euclidean norms and all nine Hyndman–Fan sample quantiles. Production code
is Lanius and uses `core::f64`, `core::result` and borrowed `core::slice::View`
values. It allocates no memory and calls no host mathematics service.

Import it with `--source-root extended` and `import ext::statistics;`. A complete
executable example is
[`statistics_smoke.lani`](../tests/fixtures/extended_library/statistics_smoke.lani).

## Streaming values

```lani
let summary: ext::statistics::Moments = ext::statistics::moments();
summary.push(1000000000000.0).unwrap();
summary.push(1000000000000.25).unwrap();
assert(summary.mean().unwrap() == 1000000000000.125);
assert(summary.sample_variance().unwrap() == 0.03125);
```

`Moments` exposes `count`, `mean`, `minimum`, `maximum`, `m2`,
`population_variance`, `sample_variance`, `population_stddev` and
`sample_stddev`. Queries other than `count` return `Result<f64, Error>`.
`m2` is the sum of squared deviations from the mean. Population variance divides
it by `count`; sample variance divides it by `count - 1`. Standard deviation is
the square root of the corresponding variance. These definitions agree with
[NIST's measures of scale](https://www.itl.nist.gov/div898/handbook/eda/section3/eda356.htm).

`push(value)` and `merge(other)` return `Result<bool, Error>`, with `true` on
success. `merge` treats its argument as additional observations; merging a copy
of a summary doubles its observations. Empty summaries act as merge identities.
`push_view(view)` adds the entire view in one transaction, and
`summarize(view)` constructs a summary. An empty view produces an empty summary.

The implementation applies centered Welford updates and Chan/Pébay merges. It
retains the first observation as an origin, stores the mean's displacement from
that origin and compensates both displacement and `m2` additions. This preserves
small spreads around a large center without subtracting two raw sums of squares.
The formulas come from equations 1.1–1.4 of
[Pébay, SAND2008-6212](https://digital.library.unt.edu/ark:/67531/metadc837537/m2/1/high_res_d/1028931.pdf).
This origin shift and compensation are implementation refinements; updates and
merges still use floating arithmetic, so different partitions need not be bit
identical.

Each push or merge takes constant space and work. A view update takes linear
work and constant space. `MAX_COUNT` is `2^53`, the largest allowed count; every
count up to that limit converts exactly to binary64. The operation that would
exceed the limit fails before changing state.

## Paired observations and linear fit

`paired_moments()` constructs `PairedMoments`. It has `push(x, y)`, `merge(other)`,
`count`, `mean_x`, `mean_y`, `population_covariance`, `sample_covariance`,
`correlation` and `linear_fit`. Paired updates publish both marginal summaries
and the covariance together. A failure in either coordinate leaves all prior
state intact.

The covariance numerator follows Pébay's equation 3.1 and its incremental
specialization. Population and sample covariance divide by `n` and `n - 1`.
Correlation divides the centered cross product by each marginal norm in turn,
avoiding an unnecessary overflowing product of marginal variances. It clamps
floating rounding outside `[-1, 1]` to that interval. A constant coordinate has
undefined correlation and returns `Degenerate`.

`linear_fit()` returns `LinearFit { slope, intercept, r_squared }` for
`y = intercept + slope * x`. It requires at least two pairs and a positive
centered sum of squares in `x`. Constant `y` has slope zero, intercept equal to
its value and `r_squared = 1`. The intercept uses binary64 multiplication and
subtraction; a large coordinate center can reduce its accuracy. No inference,
confidence intervals, missing-value filtering or weighted-estimator convention
is implicit.

## Sum and norm

`sum()` constructs `CompensatedSum`, which exposes `push`, `merge`, `count` and
`value`. `value` returns zero for an empty sum. Neumaier compensation retains
small terms through cancellation, using the same recurrence documented in
[CPython's compensated sum](https://github.com/python/cpython/blob/main/Python/bltinmodule.c): `1e16, 1, -1e16` sums to `1`. A nonrepresentable
intermediate sum returns `Overflow`, even if later observations could cancel it.

`scaled_norm()` constructs `ScaledNorm`, which exposes the same methods. Its
value is the Euclidean norm; an empty stream has norm zero. The scaled sum of
squares avoids squaring huge or tiny observations directly. It uses the classical
scale/relative-square recurrence in
[LAPACK 3.1 DLASSQ](https://www.netlib.org/lapack/lapack-3.1.1/SRC/dlassq.f),
with atomic failure and merge handling added. For example,
`hypot(3e200, -4e200)` and `hypot(3e-200, -4e-200)` remain finite. `hypot(x, y)`
returns `Result<f64, Error>`. If the resulting norm is nonrepresentable, the
update returns `Overflow` and retains the previous norm.

## Quantiles and scratch storage

`QuantileType::Type1` through `Type9` choose the algorithm explicitly.
`quantile_type(number)` converts an integer in `1..=9`, rejecting other values.
`quantile_sorted(view, probability, kind)` validates finite values and sorted
order before querying. `median_sorted(view)` uses type 7 at probability `0.5`,
the ordinary middle value or average of the two middle values.

For unsorted input, use
`sorted_copy(input, scratch, max_work) -> Result<SortedSample, Error>`.
The scratch view must have at least the input's logical length. The operation
validates bounds, scratch size, budget and every input value before writing.
It then copies and heapsorts the selected prefix. The budget must be at least
`sorted_work_bound(count).unwrap()`, a conservative work charge of
`8 * count * (ceil(log2(count)) + 1)`; zero elements cost zero. A successful
`SortedSample` exposes `len`, `view`, `quantile(probability, kind)` and `median`.
The last two queries take constant work because construction already validated
and sorted the sample. A successful empty sample is valid, but its queries
return `Empty`.

The input and scratch backing must be disjoint or the same logical view. Exact
self aliasing sorts in place. Partial overlap is a caller precondition, because
the generic borrowed slice API does not expose a backing-address comparison.
The returned sample borrows scratch: keep that storage alive and unmodified
until the last query. `view()` returns the same borrowed storage. Ordinary
copies alias it; this convention is not enforced by the compiler. Disjoint input
remains unchanged, and scratch elements outside the selected prefix remain
unchanged. There is no owned allocation or `destroy` method.

Sorting takes `O(n log n)` work and constant extra space. Direct sorted queries
take `O(n)` validation plus constant query work. Both native arrays and typed
storage views retain their logical order and stride. Ordering follows
`core::f64::total_cmp`, including `-0` before `+0`; NaNs and infinities are errors.

The definitions follow the
[official R quantile manual](https://stat.ethz.ch/R-manual/R-devel/library/stats/html/quantile.html).
For one-based order statistics, let `h = n*p + m`, `j = floor(h)` and
`g = h-j`. The result interpolates between `x[j]` and `x[j+1]`, clamping
out-of-range ranks to the first or last observation.

| Type | `m` | Interpolation fraction |
| --- | --- | --- |
| 1 | `0` | `0` if `g == 0`, otherwise `1` |
| 2 | `0` | `1/2` if `g == 0`, otherwise `1` |
| 3 | `-1/2` | `0` if `g == 0` and `j` is even, otherwise `1` |
| 4 | `0` | `g` |
| 5 | `1/2` | `g` |
| 6 | `p` | `g` |
| 7 | `1-p` | `g` |
| 8 | `(p+1)/3` | `g` |
| 9 | `p/4 + 3/8` | `g` |

Endpoints return the observed minimum or maximum for every type, including
singletons and ties. Probabilities must be finite and exactly within `[0, 1]`.
This implementation uses binary64 `h` without R's optional fuzz or tolerance
outside the probability interval. It therefore specifies the type formulas,
without promising identical results to every version of R at rounding
boundaries. Interpolation avoids overflowing `b-a` for opposite extreme signs
and recenters near their midpoint to retain values close to cancellation.

## Errors and numerical limits

`Error { kind, index }` identifies the failure. `index` is relative to the input
view when a view update or sort finds bad data, or `-1` when no observation index
applies. Each fallible mutation preserves its old state on error. Scratch output
is also unchanged on recoverable errors. Construct streaming values with their
factories; fields represent implementation state and must not be changed by
callers.

| Error kind | Meaning |
| --- | --- |
| `Empty` | A location, population statistic or quantile needs an observation. |
| `InsufficientData` | A sample statistic, correlation or fit needs two observations. |
| `NonFiniteInput` | An observation is NaN or infinite. |
| `Overflow` | An intermediate or resulting statistic is nonfinite. |
| `CountLimit` | An update would exceed `MAX_COUNT`. |
| `Bounds` | A logical view or requested count has invalid bounds. |
| `InvalidProbability` | A probability is nonfinite or outside `[0, 1]`. |
| `InvalidQuantileType` | A type number is outside `1..=9`. |
| `NotSorted` | A direct sorted query sees an ordering inversion. |
| `ScratchTooSmall` | Scratch cannot hold all observations. |
| `WorkLimit` | The sorting budget is below the preflight charge. |
| `Degenerate` | Correlation or fit lacks the required nonzero spread. |

IEEE binary64 rounding and gradual underflow apply. In particular, an `m2`
smaller than the smallest subnormal may round to zero; a standard deviation
computed from that stored variance will then also be zero. Scaled norms avoid
this unnecessary squaring underflow. Moments reject overflowing `m2` even when
its division by a very large count could produce a representable variance.
These are explicit representation limits, not missing-value policies.

Until the language exposes physical slice lengths, callers must back every
claimed view element, as required by `core::slice`. Logical checks cannot detect
an overstated physical allocation. Views do not enforce lifetime or uniqueness.

## Executable evidence

`tests/extended_statistics_execution.rs` compiles native executables and compares
streaming and partitioned results against independent Python `Fraction` and
110-digit `Decimal` calculations. Deterministic cases include large means with
small spreads, positive and negative values, extreme and subnormal inputs,
compensated cancellation, covariance, regression, all nine quantile types,
endpoints, small samples and ties. When NumPy is installed, the suite also
compares its nine quantile methods on well-conditioned cases. Contract tests
cover atomic validation and
overflow failures, the exact count limit, view offsets, typed storage, signed
zero order, exact self aliasing, scratch/work limits and allocation denial.

Run the focused suite with `cargo test --test extended_statistics_execution`.
