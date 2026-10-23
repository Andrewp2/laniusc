# Binary64 elementary mathematics

`core::math` implements elementary functions in Lanius, without allocation,
external math calls, or a host service. Inputs and outputs are `f64` values.
The algorithms support the entire finite binary64 range, including subnormals
and the largest finite arguments to sine and cosine. Execution evidence is
native x86_64 Linux; other backends have not been validated by this work.

The value algorithms assume binary64 arithmetic with round-to-nearest,
ties-to-even, gradual underflow, and no algebraic reassociation or fused
replacement of their compensated steps. The module does not set a rounding
mode, expose floating point exception flags, set `errno`, or promise results
for other rounding modes. It does not change `core::f64` or `core::f32`.

## API

| Function | Meaning |
| --- | --- |
| `sin(x)`, `cos(x)` | Sine and cosine, with `x` in radians. |
| `sin_cos(x)` | `SinCos { sin: f64, cos: f64 }`; one shared argument reduction. Scalar wrappers return these same component values. |
| `exp(x)` | Exponential with base `e`. |
| `expm1(x)` | `exp(x)-1`, evaluated without cancellation near zero. |
| `log(x)` | Natural logarithm. |
| `log1p(x)` | `log(1+x)`, retaining information lost by directly rounding `1+x`. |
| `atan(x)` | Principal arctangent, in `[-π/2, π/2]`. |
| `atan2(y,x)` | Principal angle of `(x,y)`, with signed axis behavior, in `[-π, π]`. |
| `pow(x,y)` | `x` raised to real exponent `y`, with signed integer powers and IEEE special cases. |
| `scalbn(x,n: i32)` | `x * 2^n`; exponent scaling with one final rounding for subnormal results. All `i32` exponents are accepted. |

`PI`, `TAU`, `FRAC_PI_2` and `LN_2` are public binary64 constants. Their values
are rounded representations of π, 2π, π/2 and ln(2), not exact real constants.
No argument is restricted to a small angle or an application-specific domain.

## Special values and numerical limits

Unary NaNs become quiet NaNs. The selected input's sign and payload bits are
retained. Binary functions return a quiet selected input NaN except for the
explicit power identities below. No floating point status flag behavior is
part of this contract.

| Function | Special values |
| --- | --- |
| `sin`, `cos`, `sin_cos` | Infinite argument produces NaN. Sine preserves `±0`; cosine of either zero is `1`. |
| `exp` | `+∞ → +∞`, `-∞ → +0`, either zero → `1`. Large finite values overflow to `+∞` or underflow through subnormals to `+0`. |
| `expm1` | `+∞ → +∞`, `-∞ → -1`; preserves `±0`. Large negative finite input rounds to `-1`; large positive input overflows. |
| `log` | Either zero → `-∞`; negative input including `-∞` → NaN; `+∞ → +∞`; `log(1) → +0`. |
| `log1p` | `-1 → -∞`; inputs below `-1` including `-∞` → NaN; `+∞ → +∞`; preserves `±0`. |
| `atan` | Preserves `±0`; `±∞ → ±π/2`. |
| `scalbn` | Preserves infinities and signed zeros for every exponent. Overflow has the input sign; underflow preserves the sign of the rounded zero. |

`atan2(±0, positive x)` is `±0`, while `atan2(±0, negative x)` is `±π`.
Here the sign of a zero `x` participates: `(±0,+0)` follows the positive case
and `(±0,-0)` follows the negative case. A nonzero `y` on the vertical axis
returns signed π/2. Finite `y` with positive infinite `x` returns signed zero;
negative infinite `x` returns signed π. Two infinite coordinates produce
signed π/4 or 3π/4 according to the quadrant. Signs follow `y`.

Power has these explicit rules:

- `pow(x,±0)` and `pow(1,y)` return `1`, including NaN arguments in the other position.
- `pow(-1,±∞)` returns `1`.
- For infinite `y`, the magnitude of `x` relative to one selects positive infinity or positive zero.
- A negative finite nonzero base with a finite noninteger exponent produces NaN.
- Negative zero or negative infinity has a negative result only for odd integer exponents. Positive and negative exponents select zero or infinity reciprocally. Thus `pow(-0,-3)=-∞`, `pow(-0,0.5)=+0` and `pow(-∞,0.5)=+∞`.
- Finite overflow/underflow retains the result's integer-power sign. Parity is determined exactly from the exponent's binary64 representation; representable integers of magnitude at least `2^53` are even.

These functions return IEEE-style values directly, not `Result` or a fallback.
Applications that require finite values should check `core::f64::is_finite` at
their own boundary.

## Algorithms and source provenance

The implementation translates the following files from
[OpenLibm revision 5fe399749f9276eaa0b8403e507470da05cbbb3f](https://github.com/JuliaMath/openlibm/tree/5fe399749f9276eaa0b8403e507470da05cbbb3f/src),
which derives these algorithms from fdlibm:

- `k_sin.c`, `k_cos.c`, `e_rem_pio2.c`, `k_rem_pio2.c`: reduced-interval polynomials, split π/2 reduction, and Payne–Hanek reduction with 66 base-`2^24` digits of `2/π`.
- `e_exp.c`, `s_expm1.c`: split-ln(2) reduction and compensated rational expressions.
- `e_log.c`, `s_log1p.c`: exponent normalization, polynomial evaluation, and corrections for rounded `1+x`.
- `s_atan.c`, `e_atan2.c`: interval transforms, quadrant reconstruction, and ratio overflow/underflow handling.
- `e_pow.c`: a compensated two-piece logarithm, two-piece exponent product, and exponential reconstruction. It does not use `exp(y*log(x))` as a substitute.
- `s_scalbn.c`: exponent manipulation and final subnormal scaling.

The Sun permission notices are retained in the source. Bruce D. Evans's
trigonometric reduction optimizations are attributed there. There is no
copied GPL/CRlibm or UCB test code in the production module.

Deliberate translation choices are limited to value-level special-case
handling, explicit integer casts, structured loops replacing C `goto`, and
using `core::f64::round_ties_even` for medium-size reduction instead of C's
large-constant `rint` idiom. Negative-base exponent parity uses the exact
binary64 significand rather than mixed C signed/unsigned word expressions.
`scalbn` checks extreme `i32` exponents before adding them to the biased
exponent. Floating point exception-triggering expressions in the original
source are replaced with explicit value returns where their flag side effect
has no representation in Lanius.

## Accuracy and executable evidence

The focused driver imports and executes the production Lanius module. Its
binary transport preserves every input/output bit. The independent Python
oracle reconstructs exact dyadic inputs from those bits and evaluates with
**450 decimal digits**, enough for reduction of arguments near the maximum
binary64 exponent. It also includes 90 published round-to-nearest sanity
vectors from the MIT-licensed
[libc-test/OpenLibm-test data](https://github.com/JuliaMath/openlibm-test/tree/18e28496adee3d84fefdda6efcb9c5b8996a2398/src/math/sanity).
Their notice is preserved in `math_reference_vectors.txt`; GPL `crlibm` and
UCB data from that repository are excluded.

The current 20,200-case differential run observed a maximum distance of **one
binary64 ULP** for each elementary function and **zero ULP** for `scalbn`.
The regression gate permits up to four ULP for finite elementary results and
requires the expected nonfinite classification. This is an observed sample
and a test budget, not a proof of a global error bound or correct rounding.

Cases include every normal exponent and both signs for trigonometry, selected
subnormals, maximum finite values, neighbors of π/2 multiples and the reduction
cutoff, exponential overflow/subnormal boundaries, logarithmic normalization
thresholds, tiny cancellation cases, extreme `atan2` ratios, near-one bases
with huge exponents, and signed integer powers. Separate exact-bit checks cover
signed zeros, NaNs, infinities, domains, and scaling at `i32` exponent limits.
Seeded failures report the operation and raw input/output bits.

Run the focused target in the repository's shared build environment. When
other agents use the GPU, hold `target/stdlib-work/library-gpu.lock` around
compilation/tests; standalone native execution and reference calculation use
the CPU. Tests require Python with `mpmath`; production has no such dependency.
