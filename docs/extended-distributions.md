# Continuous probability distributions

`ext::distributions` provides normal, exponential, gamma and beta distributions
with checked parameters, density/log-density, paired probability tails and
generic sampling. Production computation is Lanius, using `core::math`,
`core::f64` and `core::random::Source64`. It allocates no memory and calls no
host probability or math service. These four continuous laws do not complete
the probability family; discrete laws, quantiles and additional distributions
remain separate work.

## Parameters and API

| Factory | Parameters | Support |
| --- | --- | --- |
| `normal(mean, standard_deviation)` | finite mean; finite deviation > 0 | all real values |
| `exponential(rate)` | finite rate > 0 | x >= 0 |
| `gamma(shape, scale)` | finite shape > 0, finite scale > 0 | x >= 0 |
| `beta(alpha, beta_shape)` | finite shapes > 0 | 0 <= x <= 1 |

Factories return `Result<Distribution,Error>`. `Distribution` stores a
`Family` and two binary64 parameters. Construct it through a factory; every
public evaluation/sampling call validates it again, so invalid forged fields
fail before consuming randomness. The exponential's unused second parameter
is zero in factory-created values.

```lanius
import core::random;
import ext::distributions;
let law = ext::distributions::gamma(2.0,3.0).unwrap();
let source = core::random::from_seed(17);
let limit = ext::distributions::budget(10000,100000);
let x = ext::distributions::sample(source.borrow(),law,limit.borrow());
let density = ext::distributions::pdf(law,6.0);
let probabilities = ext::distributions::tails(law,6.0,limit.borrow());
```

| Operation | Result |
| --- | --- |
| `pdf(law,x)` | probability density, `Result<f64,Error>` |
| `log_pdf(law,x)` | natural logarithm of density |
| `tails(law,x,&Budget)` | `Tails { cdf, survival, log_cdf, log_survival }` |
| `sample<R>(source:&R,law,&Budget)` | one finite sample; R implements `Source64` |
| `budget(max_draws,max_work)` | cumulative mutable value budget |
| `Budget::charge(amount)` | reserve caller work units; false preserves budget |
| `remaining_draws()`, `remaining_work()`, `draws()`, `work()` | exact budget counters |

The CDF is P(X<=x); survival is P(X>x), identical to P(X>=x) for these continuous
laws. NaN x returns `NaN`; infinities use the distribution's limiting density
and tail values. Negative x is outside the exponential/gamma support; beta
values outside [0,1] have zero density and the corresponding endpoint CDF.

At a support endpoint, gamma shape<1 and beta endpoint shape<1 have infinite
density. Endpoint shape=1 has its finite limiting density. `pdf` may return
+infinity when density is mathematically infinite or exceeds binary64's range,
and zero on underflow. `log_pdf` preserves a finite logarithm where possible,
and can return -infinity. These evaluation infinities are distinct from a
successful sample: sampling never returns NaN or infinity.

## Numerical methods and boundaries

Normal density uses a standardized coordinate and checks the overflowing
subtraction case before dividing. Its CDF uses fdlibm/OpenLibm's piecewise
rational erfc approximation, evaluated in logarithmic form for the tail.
Consequently normal log-survival remains finite after ordinary survival
underflows. The coefficient/helper implementation retains the Sun permission
notice in `distributions_erfc.lani`; it is an implementation helper.

Exponential CDF uses `expm1`, survival uses `exp`, and log-survival is -rate*x.
When rate*x is subnormal or underflows, log-CDF is formed from log(rate)+log(x),
retaining information that a rounded product would lose.

Gamma normalization uses recurrence and a seven-term Stirling correction.
Near the shape parameter, a stable `x-log1p(x)` series evaluates the deviance
without subtracting large near-equal normalizing terms. The lower incomplete
gamma series and upper continued fraction are selected by argument. A
small-shape complement series uses `expm1` and a dedicated logGamma(1+a)
expansion. It factors out the shape before taking the logarithm, preserving
log tails even at the minimum positive subnormal shape. The smaller lower-tail
path is retained when appropriate.

Beta uses symmetry and the incomplete-beta continued fraction. Small shape
and small b*x use a normalized power series with a differenced log-gamma ratio;
it does not subtract two almost identical logGamma values. Shapes >=8 use
stable Stirling/deviance normalization. Alpha=1 or beta=1 uses the exact
power-law tail formula. For equal shapes, x = 0.5 returns exactly paired
probabilities (0.5,0.5) and log probabilities (-log(2),-log(2)), including
finite shapes whose sum overflows. Both incomplete-function fractions use modified Lentz
evaluation with a tiny denominator pivot; invalid numerical results are
errors. Probabilities are never clamped into [0,1].

`Tails` keeps log probabilities separately. The complementary ordinary/log
values use `expm1`/`log1p`, rather than subtracting a rounded ordinary CDF from
one. An ordinary probability may round to 0 or 1 while its informative log
tail remains finite. Successful tails lie in [0,1] and sum to one within
ordinary binary64 rounding.

Valid finite parameters are accepted by factories across binary64's range.
This is not a promise that every evaluation is representable or converges:

- Gamma evaluation returns `NumericalFailure` if its positive scaled x/scale
  coordinate underflows to zero or overflows. Support endpoints are handled
  first.
- Recurring incomplete-function iterations return `Precision` when adding one
  no longer changes a required shape parameter, or beta's shape sum overflows.
  Analytic beta shape=1 cases do not need those iterations.
- Every convergent series/fraction has the hard `MAX_ITERATIONS=1000000` cap.
  Failure to satisfy its convergence criterion returns `NoConvergence`;
  exhausting caller work first returns `WorkLimit`.
- Invalid/indeterminate computed intermediates return `NumericalFailure`.
  Severe tail conditioning can make a method fail instead of producing a
  probability. There is no normal approximation silently substituted for
  gamma/beta evaluations.

No correct-rounding or uniform relative-error guarantee is made. The measured
profile below is evidence over the tested inputs, not a proof for all finite
parameters. Logarithms near zero are judged by absolute error; relative error
there is not a useful accuracy measure.

## Sampling and randomness

Normal sampling uses the Box–Muller radius/angle transform. Each call discards
the second possible normal variate; there is no cache or hidden mutable RNG.
Exponential sampling uses -log1p(-U)/rate. Gamma uses Marsaglia–Tsang rejection
for shapes >=1, and G(shape+1)*U^(1/shape) below one. Beta combines independent
gamma draws using log bases and shape-scaled boost differences, then a stable
logistic ratio. Equal very small-shape boosts cancel before the unscaled base
residual is added; this also works at the minimum positive subnormal shape.

Uniform draws use `core::random::unit_f64`'s upper 53-bit grid [0,1). A radius
or logarithm requiring an open uniform rejects zero. Each rejection consumes a
draw/work unit, so a malicious or stuck zero source terminates at the explicit
budget. Uniformity claims assume independent uniform source words; these
methods do not repair a biased or correlated source and are not cryptographic.
The finite uniform grid bounds attainable normal/exponential tail variates;
this is finite-precision simulation, not exact continuous randomness.

Floating underflow may return gamma/exponential zero or beta endpoints; these
are the rounded representation of a draw, not gap shifts or rejection retries.
Overflow in the chosen sampling arithmetic returns `NumericalFailure`.
Generator advancement is not rolled back on a later error. Very large shapes
can have variation below representable binary64 spacing.

## Budgets and failure behavior

`Budget` is a value containing cumulative remaining/used draw and work counts.
Keep one active budget when calls must share a quota; copying it copies its
counters. Treat its fields as implementation state. Source and budget borrows
must remain valid for the call.

Work units are policy charges, not counts of CPU instructions or
transcendental iterations inside `core::math`:

- each attempted uniform draw costs one work unit;
- each gamma rejection proposal costs one additional unit;
- `tails` costs one unit plus one per iterative series/fraction step;
- density helpers have fixed bounded work and consume no budget;
- caller `charge(amount)` reserves that many units atomically.

A failed Source64 call consumes its attempted draw/work unit and returns
`Random(original_error)` unchanged. Draw-limit failure does not call the
source. Its attempted draw operation still costs one work unit. Work failure
occurs before the corresponding source attempt. Invalid parameters and NaN
evaluation input consume no draws/work. Failure never publishes a sample;
previous external RNG advancement and budget consumption remain observable.
There are no library allocations or partial owned buffers to clean up.

Errors are `InvalidParameter`, `NaN`, `NumericalFailure`, `Precision`,
`NoConvergence`, `WorkLimit`, `DrawLimit`, and `Random(core::random::Error)`.

## Sources and verification

Definitions and evaluation algorithms follow NIST DLMF
[gamma/Stirling](https://dlmf.nist.gov/5.11),
[logGamma series](https://dlmf.nist.gov/5.7),
[incomplete-gamma series](https://dlmf.nist.gov/8.7),
[lower series](https://dlmf.nist.gov/8.11),
[upper fraction](https://dlmf.nist.gov/8.9), and
[incomplete beta](https://dlmf.nist.gov/8.17), especially equations 8.17.22–23.
Sampling follows Box–Muller,
[“A Note on the Generation of Random Normal Deviates” (1958)](https://doi.org/10.1214/aoms/1177706645),
and Marsaglia–Tsang,
[“A Simple Method for Generating Gamma Variables” (2000)](https://doi.org/10.1145/358407.358414).
Mature comparisons included [NumPy 2.3.4 sampling](https://github.com/numpy/numpy/blob/v2.3.4/numpy/random/src/distributions/distributions.c)
and [SciPy XSF 0.1.0 incomplete functions](https://github.com/scipy/xsf/tree/v0.1.0/include/xsf/cephes).
The erfc rational helper derives from
[OpenLibm commit 5fe39974](https://github.com/JuliaMath/openlibm/blob/5fe399749f9276eaa0b8403e507470da05cbbb3f/src/s_erf.c).
The differenced normalization and scaled beta ratio are explicit binary64
arrangements of those identities; no host library performs production work.

Focused native tests compare 3434 parameter/operation cases against
100–450 decimal digit mpmath references using exact binary64 inputs. They
cover near-support values, central/tail cases, signed infinite arguments,
tiny shapes, extreme scales and explicit numerical/resource errors. The
ordinary gamma/beta accuracy grids reach shape 1000, with extra small-shape
vectors down to the minimum positive subnormal. The gate allows the larger
of 2e-11 relative density/tail error and 12 ULPs of the reference, including
subnormal ULPs; log error is divided by max(1,abs(reference)) and must not
exceed 2e-11. Printed density/tail error summaries use the denominator
max(1e-300,abs(reference)); this floor means they are not global relative
error measurements. Regressions cover exponential product underflow,
subnormal gamma/beta log tails, exact beta symmetry through the maximum
finite shape, and scripted beta boost cancellation.

A separate 35-case grid checks large shapes through defining-integral
quadrature in a centered, scaled coordinate at 90 decimal digits, with
selected 120-digit convergence controls. It uses gamma shapes 1e4, 1e8 and
1e12, beta shape pairs (1e4,2e4), (1e8,2e8), (1e12,2e12) and (1e15,1e15),
at mean plus {-8,-1,0,1,8} standard deviations. Successful large-shape tails
stay within a separate 2e-8 relative and normalized-log error gate; measured
maximum relative tail error was 7.89e-9. Gamma shape 1e12 at or below its
mean reaches the iteration cap and explicitly returns `NoConvergence`.
These finite parameter values remain valid. Large-shape asymptotic methods,
faster convergence and tighter accuracy remain further mathematics work.
Neither measured profile establishes a uniform accuracy bound.

The sampling model checks 392000 values over 25 fixed seeded streams, exact
draw/work consumption for the first 512 outputs per stream, finite support,
independent moment and CDF-count bounds, and a 200000-sample workload. Its
stream reference checks deterministic algorithm/consumption behavior;
distribution-shape checks use independent integrals/formulas. Scripted source
contracts cover propagated host errors, zero streams, cumulative budgets,
subnormal rounded samples and hard nonconvergence. `strace` confirms zero
allocations in the library contract executable. Python/Rust are test drivers
only. See [the sampling CLI](extended-sample-distribution.md) for actual CSV,
statistics, allocation-denial and I/O integration.
