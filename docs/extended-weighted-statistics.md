# Weighted descriptive statistics

`ext::weighted_statistics` provides portable binary64
streaming summaries for nonnegative real weights. Its selected scope is
weighted second moments, paired covariance/correlation and a simple linear
fit. Production computation is Lanius, with no allocation or host math service.
The selected contracts and independent numerical models execute on Linux
x86_64 through the GPU compiler. All three registered gates pass on the
finite profile below.

Ordinary equal-weight summaries remain in
[`ext::statistics`](extended-statistics.md). Unweighted third/fourth moments
have a separate [higher-statistics guide](extended-higher-statistics.md).

## Observation and weight contract

Every value and weight must be finite; weights must be nonnegative. A
zero-weight observation is validated, then returns `Ok(false)` without changing
state. It does not contribute to the positive-weight count, extrema or spread.
NaN or infinity in a zero-weight row still fails. Negative zero is a zero
weight. Accepted positive-weight observations increment the count, through
`MAX_COUNT = 2^53`.

An empty summary has total weight zero. Location, extrema, population spread
and effective-count queries require positive total weight. Population and
reliability statistics have distinct names and denominators. No unnamed
weighted `sample_variance` convention is selected for a caller.

Construct summaries with their factories. Their fields encode implementation
state and are not caller-mutable configuration. Copying a summary copies its
scalar state. It owns no backing storage and needs no cleanup.

## API

Import with `--source-root extended` and
`import ext::weighted_statistics;`.

```lani
let summary = ext::weighted_statistics::moments();
summary.push(2.0,1.0).unwrap();
summary.push(8.0,2.0).unwrap();
assert(summary.count() == 2);
assert(summary.mean().unwrap() == 6.0);
assert(summary.population_variance().unwrap() == 8.0);
assert(!summary.push(100.0,0.0).unwrap());
```

All scalar queries below return `Result<f64,Error>`, except `count()` which
returns `u64`. The two summary types also expose `borrow()`.

| Surface | Operations and results |
| --- | --- |
| `moments() -> Moments` | Empty scalar summary |
| Scalar observations | `push(value,weight) -> Result<bool,Error>`; `merge(other) -> Result<bool,Error>` |
| Scalar queries | `count`, `total_weight`, `mean`, `minimum`, `maximum`, `m2`, `correction_denominator`, `effective_count` |
| Scalar spread | `population_variance`, `reliability_variance`, `population_stddev`, `reliability_stddev` |
| Scalar batches | `push_views(values,weights) -> Result<u64,Error>`; `summarize(values,weights) -> Result<Moments,Error>` |
| `paired_moments() -> PairedMoments` | Empty paired summary |
| Paired observations | `push(x,y,weight)`, `merge(other)` return `Result<bool,Error>`; `push_views(x,y,weights)` returns `Result<u64,Error>` |
| Paired queries | `count`, `total_weight`, `mean_x`, `mean_y`, `population_covariance`, `reliability_covariance`, `correlation` |
| `PairedMoments::linear_fit()` | `Result<ext::statistics::LinearFit,Error>` |

A successful positive-weight push returns `true`. Merging an empty source
returns `false`; a successful nonempty merge returns `true` and treats every
source observation as additional data. Merging a copy doubles those
observations. Batches return the number of added positive-weight observations,
including zero for an empty or all-zero-weight input.

`total_weight()` returns `Ok(0)` when empty. Other location, moment,
population-spread and effective-count queries return `Empty`. Reliability
variance/covariance/stddev need at least two positive-weight observations and
a positive stored correction denominator; otherwise they return
`InsufficientData`. `correction_denominator()` returns zero for a singleton.
The effective-count result is rounded binary64, clamped to `[1,count]`.

## Definitions and formula mapping

For positive-weight observations define

```text
W = sum(w_i)                    Q = sum(w_i * w_i)
mean = sum(w_i * x_i) / W       M2 = sum(w_i * (x_i - mean)^2)
D = W - Q/W                    effective_count = W*W/Q
population_variance = M2/W      reliability_variance = M2/D
```

The weighted mean and centered-moment merge come from §3.3, equations
3.24–3.27, of [Pébay et al. (2016)](https://people.xiph.org/~tterribe/pubs/P%C3%A9bayTerriberryKolla%2B16-_Numerically_Stable,_Scalable_Formulas_for_parallel_and_Online_Computation_of_Higher-Order_Multivariate_Central_Moments_with_Arbitrary_Weights.pdf).
For two summaries, with `delta = mean_B - mean_A`:

```text
W = W_A + W_B
mean = mean_A + delta * W_B/W
M2 = M2_A + M2_B + delta*delta * W_A*W_B/W
```

The implementation keeps an origin-shifted, compensated mean and second
moment. It uses a scaled weight norm rather than materializing `Q` when that
would overflow. Effective count uses that norm's scale and relative square
sum directly, avoiding loss from first rounding its square root at subnormal
weights. `Moments::merge` chooses the heavier partition as its mean
base, and `Difference` can carry an opposite-extreme center difference as a
half difference plus factor two. Scaled products then apply the weight ratio
before the final range check. It preserves the reliability denominator with
positive terms:

```text
D = (W_A/W)*D_A + (W_B/W)*D_B + 2*W_A*W_B/W
```

Substituting `Q_A = W_A*(W_A-D_A)` and the corresponding `B` identity into
`D = W-(Q_A+Q_B)/W` gives this recurrence. The code scales and adds each
denominator compensation component separately. It avoids subtracting nearly
equal `W` and `Q/W`. The named
reliability convention matches equation 24 in
[WG21 P1708R10 §4.11](https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2025/p1708r10.pdf).
Frequency-weight and other corrections are different estimators. Multiplying
all weights by a common positive factor leaves the mathematical population and
reliability variances and effective count unchanged; finite arithmetic still
has representation limits.

[`ext::statistics_scaling`](../extended/ext/statistics_scaling.lani) supplies
implementation support for bounded-mantissa products and quotients, with one
final power-of-two scale. This avoids avoidable intermediate range failures.
It is rounded binary64 arithmetic, not an exactly rounded fused product,
arbitrary precision or a public estimator convention.

## Paired observations

Paired summaries share the same positive weights and publish both coordinates
and the centered cross product together. The merge correction is
`delta_x * delta_y * W_A*W_B/W`. Population covariance divides the cross product
by `W`; reliability covariance divides by `D`. Correlation normalizes by both
marginal spreads. The fit models `y = intercept + slope*x`. Correlation and
fitting require two positive-weight observations. Correlation returns
`Degenerate` for either nonpositive marginal spread, and clamps a finite
rounded result to `[-1,1]`. Fitting requires positive spread in `x`; constant
`y` produces slope zero, its value as intercept and `r_squared = 1`.
The intercept uses a half-scaled fallback if direct product/subtraction
overflows. Large centers can still lose accuracy through cancellation.
These APIs supply no sampling-design model, inference, confidence interval
or missing-value policy.

## Borrowed batches and failure behavior

View batches borrow their input only during the call and publish one complete
summary update. A bad value, weight, logical bound or numerical intermediate
leaves prior state intact. Error indices identify the logical batch position;
scalar, shape and query failures use an index of `-1`.

The views in a batch must all have equal logical lengths and nonnegative
start/length whose sum fits `i32`. Reads use the view's logical order,
including a typed storage stride. A batch validates and updates a local copy,
so an error after earlier valid rows still publishes no rows.

| `ErrorKind` | Meaning |
| --- | --- |
| `Empty` | No positive-weight observation is available for this query |
| `InsufficientData` | A reliability statistic, correlation or fit lacks the required count or positive denominator |
| `NonFiniteInput` | A coordinate is NaN or infinite, including a zero-weight row |
| `InvalidWeight` | A weight is negative, NaN or infinite |
| `Overflow` | A required intermediate, stored state or result is nonfinite or an accumulated squared quantity becomes negative |
| `CountLimit` | Positive-weight count would exceed `MAX_COUNT` |
| `Bounds` | View shape is invalid or paired logical lengths differ |
| `Degenerate` | Correlation or a fit lacks the required positive marginal spread |

Coordinate validation precedes weight validation, which precedes zero-weight
and count handling. Errors do not silently omit rows. Standard deviation is
computed as `sqrt(M2)/sqrt(divisor)`, allowing it to stay finite or nonzero
even when the corresponding variance query overflows or underflows.

The caller must provide valid live backing for every claimed view element.
Logical checks do not establish a physical allocation length or a compiler
checked lifetime. No input is stored in the summary. Read-only input views may
alias; callers must prevent mutation during the operation.

All finite inputs do not imply every result is representable. Nonfinite
intermediate or stored moments fail atomically; final subnormal rounding and
underflow remain binary64 behavior. A tiny positive `M2` can round to zero,
producing zero variance/stddev and `Degenerate` correlation or fit. A positive
correction denominator can round to zero, producing `InsufficientData` for a
reliability query. Weight imbalance can round effective count to one despite
more than one positive-weight observation. Order and partitioning may affect
low bits.
No formal error bound, correct-rounding guarantee or formal proof is claimed.

## Executable evidence and target

The independent numerical model passes 1,908 cases with module `d3cea094…` on
native Linux x86_64. Exact-input `Fraction` sums and 220-digit `Decimal`
derived statistics are independent of the production recurrence. Cases
include every ordered binary merge tree through six rows, larger
left/right/balanced merges, common weight scaling, small spreads around large
centers, opposite maximum centers, severe weight imbalance and equal
minimum-subnormal weights. Native-array and typed-storage backing forms both
use the current descending `f64` descriptor; this does not establish a
positive packed-stride `f64` ABI.

The model compares every scalar query and paired covariance/correlation/fit.
Its base gate is the larger of `2e-11` relative error, eight ULPs and a
metric-specific absolute allowance for center/cross-product/intercept
cancellation. A near-underflow correction denominator has an explicit
`InsufficientData` allowance while effective count still uses its exact
reference. See the [oracle and fixture guide](../tests/fixtures/extended_library/weighted_statistics/README.md)
for that finite profile. The log is
`target/stdlib-work/weighted-statistics-model-native-first.log`.

The support model independently passes 1,926 exact-rational cases over all
six helpers, including 1,122 exact-bit cases. Its maximum observed
ULP distances are `1,2,1,2,2,1` for product3/product5/quotient2/quotient4/
quotient5/quotient2_2. These observations do not promise correct rounding.
Both registered scaling tests pass in 7.31s, including its direct contract.

All three registered weighted tests pass. The initial registered command
passes numerical, contract and CPU-oracle-control gates in 13.07s. After
strengthening the paired contract, its exact registered test passes again in
6.03s with contract producer `add50150…`. This current fixture checks all
three paired view-length mismatches, the genuine paired count cap and late
`y`-coordinate overflow rollback, in addition to zero-weight validation,
error precedence, self-merging, scalar/paired batches and subnormal effective
count. Its observed `mmap`/`mremap`/`munmap`/`brk` trace is empty.
The model and CPU-control inputs are unchanged; the focused rerun is not
another independent numerical campaign. CPU oracle controls verify the
checker, separately from Lanius runtime behavior.

The [sample-moments CSV program](extended-sample-moments.md) exercises weighted
summaries together with unweighted higher moments. All four registered app
tests pass in 9.87s against the current dependency, covering 66 process cases:
model26/rejection30/CLI8/I/O2. Direct and registered runs overlap those same
cases. The ordinary statistics module also passes both original runtime
regression tests in 12.06s after the shared error-enum extension.

Final registered receipts under `target/stdlib-work/` are
`statistics-extension-runtime-final.log`,
`weighted-statistics-paired-contracts-final.log` and
`statistics-original-regression.log`. The earlier direct scaling model log is
`statistics-scaling-model-native-first.log`. Production support source is
`775960e8…`; ordinary statistics is `7f83f1e8…`. No compiler production change
is part of this increment.

Supported execution evidence is Linux x86_64 CPU output from the GPU compiler.
The portable computation has no host mathematics, C-library, allocation,
JSON-transport or Wasm dependency. Python Fraction/Decimal and Rust are test
services only. Other host targets, user-program GPU execution, uniform
accuracy, automatic borrowed lifetimes and formal proofs remain unclaimed.
