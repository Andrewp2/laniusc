# Discrete probability distributions

`ext::discrete_distributions` provides Bernoulli, binomial, geometric and
Poisson laws: probability masses, natural log masses, paired tails and bounded
generic sampling. Production computation is Lanius. It uses `core::math`,
`core::random::Source64` and public continuous-distribution identities, with
no allocation, host probability service or cached random state.

## Parameter and count domains

| Factory | Accepted parameters | Mathematical support |
| --- | --- | --- |
| `bernoulli(p)` | finite p in [0,1] | 0 or 1 |
| `binomial(trials:u32,p)` | every u32 trial count; finite p in [0,1] | 0 through trials |
| `geometric(p)` | finite p in (0,1] | failures before first success: 0,1,2,... |
| `poisson(mean)` | finite mean in [0,1000000000] | 0,1,2,... |

Factories return `Result<Distribution,Error>`. Every public operation
validates the stored family, trial count and parameter again. Invalid forged
values fail before randomness or budget consumption.

Count arguments and samples are i64. Negative evaluation arguments are
outside support: mass zero, CDF zero and survival one. Bernoulli/binomial
arguments above support return their exact limiting values, throughout i64.
Geometric/Poisson evaluation supports nonnegative counts through
`MAX_COUNT=9007199254740991` (2^53-1), so both k and k+1 convert exactly to
binary64. Larger arguments return `CountRange`, including degenerate laws.
A sampled count outside that numerical domain also returns `CountRange`.
These unbounded laws are never capped, renormalized or resampled at the bound.

The Poisson mean cap is an explicit implementation domain. At mean 1e9,
central candidate spacing remains far below one count, the tested gamma-tail
iterations fit the fixed cap, and the independent numerical and sampling
profiles below cover that boundary. This does not establish accuracy for
arbitrary finite means; larger means need separate range/convergence work.

## API

```lanius
import core::random;
import ext::discrete_distributions;
let law = ext::discrete_distributions::binomial(100,0.03).unwrap();
let source = core::random::from_seed(17);
let limit = ext::discrete_distributions::budget(10000,100000);
let count = ext::discrete_distributions::sample(source.borrow(),law,limit.borrow());
let probability = ext::discrete_distributions::pmf(law,4);
let paired = ext::discrete_distributions::tails(law,4,limit.borrow());
```

| Operation | Result |
| --- | --- |
| `pmf(law,k)` | `Result<f64,Error>`, P(X=k) |
| `log_pmf(law,k)` | natural log P(X=k) |
| `tails(law,k,&Budget)` | `Tails { cdf, survival, log_cdf, log_survival }` |
| `sample<R>(&R,law,&Budget)` | `Result<i64,Error>`, R implements `Source64` |
| `budget(max_draws,max_work)` | one cumulative draw/work budget |
| `Budget::charge(amount)` | reserve caller policy work atomically |
| `remaining_draws()`, `remaining_work()`, `draws()`, `work()` | exact counters |

CDF means P(X<=k), and survival means P(X>k). In a discrete law, survival
differs from P(X>=k). Log zero is -infinity. Ordinary masses/tails may underflow
to zero while their informative log values remain finite. No probabilities
are clamped into [0,1].

## Evaluation methods and numerical limits

Bernoulli and geometric masses use their direct formulas and `log1p`.
Binomial endpoint masses retain n*log(p) or n*log1p(-p). A bounded sum of
logarithms evaluates the binomial coefficient within 128 counts of an
endpoint; other masses use the beta-density identity divided by n+1.
Binomial tails near either endpoint use positive lower/upper PMF recurrences
and retain a separate log normalization. Interior tails use the public
incomplete-beta identity, evaluated at p to avoid rounding 1-p to one.

Poisson masses use the public gamma-density identity, with explicit mean-zero
and count-zero branches. Its CDF/survival swap the public gamma tails at
shape k+1 and argument mean. Geometric tails use the analytic beta power-law
case. Endpoint branches precede any factory that would require a zero shape.
Complementary probabilities/logs use `expm1` and `log1p`.

Valid parameters do not promise success at every numerical argument.
Continuous `Precision`, `NoConvergence`, `WorkLimit` and numerical failures
propagate as corresponding discrete errors. For example, Poisson tails at
the maximum numerical count cannot resolve a required shape increment and
return `Precision`; the count itself is in domain. Series/fractions and
sampling rejection loops have a hard one-million-iteration cap. Work limits
can stop a computation sooner. Invalid/indeterminate intermediates return
`NumericalFailure`; there is no normal approximation substituted in production.

## Sampling and randomness

Bernoulli sampling compares independent uniform 64-bit words against the
successive binary prefixes of the exact binary64 probability. This is an
exact Bernoulli law for that dyadic p, assuming independent uniform source
words and sufficient budget. It handles the minimum positive subnormal p
without rounding its probability up to a 53-bit grid cell. It uses at most
17 words, can stop after one, and can consume an extra word on an equal
prefix with a zero suffix. It does not promise minimum-word consumption.

Binomial sampling reflects p>0.5. When the reflected mean is below 10, it
first draws the nonzero-count event using `expm1`, then inverts the conditional
positive-count law. This retains tiny event probabilities. Lower uniforms
use a positive PMF recurrence; upper uniforms compare log-survival against
log(1-U)+log(P(X>0)) with a bracketed count search. The normalized first mass
uses a log-sinhc identity to preserve its negative first-order correction.
Larger means use Hörmann's BTRS envelope and squeeze, with final acceptance
from a stable log-PMF ratio to the modal mass.

Poisson sampling below mean 10 uses the same nonzero-event/conditional
inversion split. Its upper-tail count bracket doubles before binary search.
Larger means use Hörmann's PTRS envelope and the public stable log-PMF.
Geometric sampling uses a checked log/log1p inverse and rejects a zero uniform.

Only Bernoulli has the exact dyadic-law claim. The other samplers use rounded
arithmetic and a finite upper-53-bit uniform grid; their distribution and tail
accuracy is numerical. In particular the geometric inverse cannot reach every
outcome for every p. Very small p can produce `CountRange` rather than an
invented finite count. A biased/correlated source is not repaired by sampling.
These are simulation methods, not cryptographic generators.

## Budgets, ownership and failures

The budget contains one continuous-library work ledger and separate attempted
source-word counters. Delegated tails charge that same ledger. There are no
allocations or owned buffers. Borrowed sources/budgets must remain valid for
the call; budget fields are implementation state. Copying a budget copies
its counters, so keep one active value when calls must share a quota.

Policy work charges are:

- one per attempted source word, including a failed source call;
- one additional per BTRS/PTRS proposal;
- one per lower conditional-inversion recurrence step;
- tail base/iteration charges, including every bracket/search evaluation;
- fixed bounded mass helpers consume no budget;
- degenerate samples consume no draws or work.

Draw-limit failure does not call the source, but its attempted draw operation
costs one work unit. Work-limit failure precedes the corresponding source
attempt. Invalid distribution/count inputs consume no draws/work. A failed
source returns `Random(original_error)` without replacing its payload.
No later failure rolls back prior source advancement or work. Failure
publishes no count. The hard open-uniform/proposal caps also stop a stuck
source when a caller provides very large quotas.

Errors are `InvalidParameter`, `CountRange`, `NumericalFailure`, `Precision`,
`NoConvergence`, `WorkLimit`, `DrawLimit`, and `Random(core::random::Error)`.

## Sources and verification

The evaluation identities are [DLMF 8.17.5](https://dlmf.nist.gov/8.17.E5)
and [DLMF 8.4.10](https://dlmf.nist.gov/8.4.E10). Sampling envelopes follow
Wolfgang Hörmann's primary papers,
[The Generation of Binomial Random Variates](https://statmath.wu.ac.at/papers/92-04-07.wh.abs.html)
and [The Transformed Rejection Method for Generating Poisson Random Variables](https://statmath.wu.ac.at/papers/92-04-13.wh.abs.html).
The Lanius implementation replaces the papers' cancellation-prone direct
log-factorial differences with stable log masses. The conditional recurrence,
log-sinhc rearrangement and two-sided inversion are stated above rather than
being hidden approximations.

Mature comparisons included [NumPy 2.3.4](https://github.com/numpy/numpy/blob/v2.3.4/numpy/random/src/distributions/distributions.c)
and [Boost.Random 1.85](https://github.com/boostorg/random/blob/boost-1.85.0/include/boost/random/binomial_distribution.hpp).
Their source text is not included; the production formulas are a fresh
Lanius formulation of the published algorithms. Existing dependency notices
remain with their implementations.

Focused native models check 2572 ordinary/edge cases and a separate 195-case
large-count grid against exact-input 110–450 decimal digit references.
Finite PMF sums and centered defining-density integrals are independent of
the production incomplete-function code. The ordinary gate allows the larger
of 2e-11 relative mass/tail error and 12 ULPs; log error is normalized by
max(1,abs(reference)) and bounded by 2e-11. The separate large grid reaches
full-u32 trials and mean 1e9, with a 1e-8 gate; observed maximum relative
mass/tail error there was 5.21e-11. Printed ordinary probability summaries
divide by max(1e-300,abs(reference)), so they are not global relative maxima.
Neither profile establishes uniform accuracy or correct rounding.

Sampling checks cover 304000 values over 27 streams, support, independent
moments/CDF counts, and exact count/draw agreement for the first 128 values
of each tested stream. Large-regime empirical CDF checks use normal-limit
references with explicit error allowances, only in the test driver; the
separate numerical grid uses high precision integrals. Fourteen scripted
general-acceptance decisions compare independently computed high precision
PMFs on both sides of BTRS/PTRS thresholds, outside their squeezes.
Other scripts cover subnormal and 117-bit-prefix Bernoulli inputs, near-one
probabilities, upper-grid conditional quantile 45 at full-u32 trials,
source failures and hard resource caps. The native contract executable makes
no `mmap`/`munmap` calls. Rust/Python, mpmath and `strace` are test services only.
See [sample-counts](extended-sample-counts.md) for actual CSV and I/O integration.
