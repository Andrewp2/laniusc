# Third and fourth descriptive moments

`ext::higher_statistics` provides a portable, unweighted
binary64 summary for centered third/fourth moments and named skewness/kurtosis
estimators. Its `Moments` type composes the existing
[`ext::statistics::Moments`](extended-statistics.md) state with `M3` and `M4`;
the original moment operations and their representation limits remain unchanged.
The shared error enum adds `Underflow` for this module's profile. Production
computation is Lanius, with no allocation or host math service. Both registered
runtime tests pass on the finite Linux x86_64 profile below.

[Weighted second-order statistics](extended-weighted-statistics.md) are a
separate API. This module does not supply weighted skewness, weighted kurtosis,
arbitrary-order moments or multivariate higher co-moments.

## State and observations

Every observation must be finite. The count is at most `2^53`. Summary fields
are implementation state: use the factory and operations, rather than editing
the fields. A copy is an independent scalar summary, without owned storage,
implicit allocation or cleanup.

Define `M_r = sum((x_i - mean)^r)`, and `m_r = M_r/n`. `M2` is the existing
second-moment numerator. `M3` is signed; `M4` is nonnegative in exact arithmetic.
Both are stored in binary64. A push or merge publishes all orders together;
overflow in `M4` preserves the old count, mean, `M2` and `M3` too. A dataset
accepted by ordinary `ext::statistics::Moments` may exceed this type's range.

## API

Import with `--source-root extended` and `import ext::higher_statistics;`.

```lani
let summary = ext::higher_statistics::moments();
summary.push(-1.0).unwrap();
summary.push(0.0).unwrap();
summary.push(1.0).unwrap();
assert(summary.count() == 3);
assert(summary.m3().unwrap() == 0.0);
assert(summary.population_skewness().unwrap() == 0.0);
```

| Surface | Operations and results |
| --- | --- |
| `moments() -> Moments` | Empty summary |
| Observation updates | `push(value)`, `merge(other)` return `Result<bool,ext::statistics::Error>` |
| Borrowed batches | `push_view(values) -> Result<bool,ext::statistics::Error>`; `summarize(values) -> Result<Moments,ext::statistics::Error>` |
| Base queries | `count`, `mean`, `minimum`, `maximum`, `m2`, `population_variance`, `sample_variance`, `population_stddev`, `sample_stddev` |
| Higher central sums | `m3`, `m4` |
| Population normalized queries | `population_skewness`, `population_kurtosis`, `population_excess_kurtosis` |
| Adjusted queries | `adjusted_skewness`, `adjusted_excess_kurtosis` |

`count()` returns `u64`; every other query returns
`Result<f64,ext::statistics::Error>`. Successful updates return `true`, including
empty merges and empty batches. An empty source is a merge identity; a
nonempty source adds observations, so merging a copy doubles the sample.
The base queries retain the original module's definitions and error behavior.

## Formula mapping

The centered merge specializes §3.1, equation 3.1 of
[Pébay et al. (2016)](https://people.xiph.org/~tterribe/pubs/P%C3%A9bayTerriberryKolla%2B16-_Numerically_Stable,_Scalable_Formulas_for_parallel_and_Online_Computation_of_Higher-Order_Multivariate_Central_Moments_with_Arbitrary_Weights.pdf)
at orders three and four. Let `n = n_A+n_B`, `a = n_A/n`, `b = n_B/n`,
`delta = mean_B-mean_A`, `s_A = -b*delta` and `s_B = a*delta`.
`Moments::combined` expands each old partition around the new mean:

```text
M3 = M3_A + M3_B
     + 3*s_A*M2_A + 3*s_B*M2_B
     + n_A*s_A^3 + n_B*s_B^3

M4 = M4_A + M4_B
     + 4*s_A*M3_A + 4*s_B*M3_B
     + 6*s_A^2*M2_A + 6*s_B^2*M2_B
     + n_A*s_A^4 + n_B*s_B^4
```

A singleton summary has zero centered moments. Adding it specializes the same
merge law, rather than treating raw powers of a large uncentered observation
as central moments. The existing origin-shifted first/second moment state
supplies the centered displacement.

The code adds each old compensation component separately. Linear shift terms
retain `delta` and the count ratio as separate product factors even if a
materialized shift would underflow. `Accumulator::add` uses Neumaier
compensation and rejects nonfinite intermediate additions. Finite final
cancellation does not rescue an earlier nonrepresentable intermediate.

The exact formulas below follow [WG21 P1708R10 §§2.4–2.5](https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2025/p1708r10.pdf).
Population skewness is `g1 = m3/(m2*sqrt(m2))`; population Pearson kurtosis is
`K = m4/(m2*m2)`, and population excess kurtosis is `g2 = K-3`. The adjusted
Fisher–Pearson skewness is `sqrt(n*(n-1))/(n-2) * g1`, requiring `n>=3`.
Adjusted excess kurtosis uses
`(n-1)/((n-2)*(n-3)) * ((n+1)*g2+6)`, requiring `n>=4`.
Its code rearranges the inner expression as `(n+1)*K - 3*(n-1)` and
compensates that subtraction. There is no ambiguously named `skewness` or
`kurtosis` method, nor an additional adjusted non-excess kurtosis method.

These are explicitly named finite-sample formulas. They do not promise an
unbiased estimate for every distribution, confidence intervals, normality
testing or an implicit policy for missing observations.

## Failures and numerical range

The module uses `ext::statistics::Error { kind,index }` rather than introducing
a second error type.

| Error or edge | Behavior |
| --- | --- |
| `Empty` | Raw central sums, base location/population queries and population normalized queries need an observation |
| `InsufficientData` | Sample variance/stddev need two; adjusted skewness needs three; adjusted excess kurtosis needs four |
| `Degenerate` | A population or adjusted normalized query has nonpositive `M2` |
| `NonFiniteInput` | An observation is NaN or infinite |
| `Overflow` | A base/higher intermediate, stored sum or query result becomes nonfinite |
| `Underflow` | A nonconstant summary would lose its positive fourth central sum to zero or a nonpositive value |
| `CountLimit` | An update would exceed `MAX_COUNT` |
| `Bounds` | A batch has a negative start/length or their sum exceeds `i32` |

A singleton has zero raw `m2`/`m3`/`m4` and population variance. Its population
skewness/kurtosis are `Degenerate`. Adjusted methods check their minimum count
before spread, so an empty or too-small constant sample is `InsufficientData`.
No undefined statistic is replaced by zero, and no observation is silently
discarded.

Scaled products in
[`ext::statistics_scaling`](../extended/ext/statistics_scaling.lani) avoid
unnecessary intermediate overflow/underflow. Finite raw `M4` is still a state
requirement, even when a normalized fourth-order statistic could be finite.
For a nonconstant sample, a nonpositive rounded `M4` rejects the update with
`Underflow` and preserves all old state. Constants retain zero `M4`.
Positive subnormal fourth moments remain supported with limited accuracy;
the check does not guarantee a relative error bound near the underflow edge.
Other intermediate rounding, cancellation and merge order can affect the
result. No uniform relative error bound, correct-rounding guarantee or formal
proof is claimed.

## Borrowed batches

A borrowed view update stages an entire summary and publishes only on success.
Input data is not retained. A failure reports its logical observation index,
while non-observation errors use `-1`. The caller must keep all claimed backing
live and readable through the call and prevent concurrent mutation. Logical
view validation cannot prove physical allocation length or enforce lifetimes.
Batch shape requires a nonnegative start and length whose sum fits `i32`;
reads follow the backing slice's logical stride and view order.

## Executable evidence and target

The independent native model passes 1,212 cases across 51 datasets, eight update
modes and two backing forms on Linux x86_64, with module `3f224ad3…` and model
producer `e3723d35…`. Fraction computes centered sums directly from exact
binary64 inputs; 110-digit Decimal computes square roots and normalization.
The reference does not repeat the production merge recurrence.

Modes cover scalar pushes, one batch, both split-merge directions, balanced
merges, singleton merges, self-merge duplication and `summarize`. Datasets
include symmetric and nearly symmetric shapes, repeated values, small-count
boundaries, large centers with small spreads, scales from `1e-75` to `1e75`,
a retained positive subnormal M4 and explicit raw-underflow rejection. Both
native-array and typed-storage backing forms use the current descending
`f64` descriptor; no positive packed-stride `f64` ABI is established.

Raw-sum comparisons use a `4e-12` budget against exact absolute centered
powers, handling nearly-zero M3 without a meaningless relative-to-zero test.
Normalized shape queries use `8e-11*max(1,abs(reference))` plus an explicit
absolute-rounding allowance for subnormal M4. The
[fixture guide and oracle](../tests/fixtures/extended_library/higher_statistics/README.md)
define all metric gates. This finite profile is no uniform accuracy bound.
Both registered runtime tests pass in 9.54s, including final scalar/batch/merge
Underflow cases, NaN and raw-fourth-moment overflow rollback, query count and
constant-data boundaries, recovery after rejection, exact count limits,
empty/self merges, aliased input and malformed views. The contract process
makes zero observed `mmap`/`munmap` calls under allocation denial. Input guard
bytes and exact input bits remain unchanged in the model. The source/profile
requires no hidden allocation.

An initial model-startup assertion expected positive `f64` storage stride.
The fixture was corrected to the documented descending descriptor, without a
compiler change. The passing direct model receipt is
`target/stdlib-work/higher-statistics-model-native-storage-fix.log`; the final
registered receipt is `target/stdlib-work/statistics-extension-runtime-final.log`.

The [sample-moments CSV program](extended-sample-moments.md) composes weighted
second moments with an unweighted positive-row higher-moment profile. Its four
registered runtime tests pass in 9.87s, covering 66 process cases:
model26/rejection30/CLI8/I/O2. Earlier direct runs overlap those cases and
supply no additional independent count. The original statistics module also
passes its two runtime regression tests in 12.06s, recorded in
`target/stdlib-work/statistics-original-regression.log`.

Supported execution evidence is Linux x86_64 CPU output from the GPU compiler.
Production source has no allocation, host mathematics, C-library, JSON
transport or Wasm dependency. Fraction/Decimal, Python, Rust and syscall
observation are test services. No other host target, user-program GPU
execution, automatic borrowed lifetime enforcement, uniform accuracy bound
or formal proof is established.
