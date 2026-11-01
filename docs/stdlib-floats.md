# Binary floating-point value utilities

`core::f32` and `core::f64` provide matching, executable utilities for IEEE
binary32 and binary64 values. Operations include exact bit transfer,
classification, signs, neighboring values, total ordering, integral rounding,
checked clamping and correctly rounded square root. All implementations are
Lanius and allocate no heap storage.

Executable evidence covers **x86_64 Linux using the GPU compiler**. Other
hosts and GPU-kernel execution have not been established. These are value
contracts: the library does not expose floating-point status flags, change
hardware rounding modes or promise the exception side effects of hardware
arithmetic.

## Values and exact bits

| API in each module | Contract |
| --- | --- |
| `to_bits(value) -> u32` / `u64` | Exact encoding of every input bit, including signed zeros and NaN payloads |
| `from_bits(bits) -> f32` / `f64` | Construct the value with those exact bits; no numerical conversion |
| `ZERO`, `ONE`, `EPSILON`, `MIN_POSITIVE`, `MAX`, `MIN` | Finite constants; minimum positive means the smallest positive **normal** value, and `MIN` is the most negative finite value |
| `SIGN_MASK`, `EXPONENT_MASK`, `FRACTION_MASK`, `QUIET_MASK` | Integer encoding masks |
| `INFINITY_BITS`, `NAN_BITS` | Integer encodings of positive infinity and the canonical positive quiet NaN |
| `infinity()`, `neg_infinity()`, `nan()` | Runtime constructors for nonfinite values |

Nonfinite floating constants are not simulated with finite placeholders.
Constructors use their public integer encodings. The canonical NaNs are
`0x7fc00000` and `0x7ff8000000000000`.

The format model is described in
[Oracle's IEEE arithmetic guide](https://docs.oracle.com/cd/E19957-01/806-3568/ncg_math.html).
Bit transfer uses a local 8-aligned stack buffer and the existing
`core::mem::typed_slice_from_storage` contract. A single native float word and
its matching unsigned word view share that complete extent. This preserves
the payload rather than performing a cast or arithmetic conversion. Binary32
uses the native word's low 32 bits; binary64 uses all 64 bits. The implementation
does not assume C `float` object layout, reinterpret pointers as integers or
call an external bitcast function.

## Classification, signs and ordering

`classify` returns the module's `FpCategory`: `Nan`, `Infinite`, `Zero`,
`Subnormal` or `Normal`. Queries are `is_nan`, `is_infinite`, `is_finite`,
`is_normal` and `is_subnormal`.

`is_sign_negative` and `is_sign_positive` inspect the sign bit for **all** bit
patterns, including zeros and NaNs. `is_negative` and `is_positive` instead
mean numerically below or above zero: both are false for either zero and for
NaNs. `is_zero` accepts either zero; `is_nonzero` is true for every other
pattern, including NaNs.

`abs` clears only the sign bit, so `abs(-0)` is `+0`. It otherwise preserves
NaN payload and signaling/quiet encoding. `copy_sign(magnitude, sign)` combines
the first input's magnitude bits and second input's sign bit.

`signum` returns `+1` or `-1` according to the sign of every non-NaN input,
including `+0`, `-0` and infinities. A NaN is quieted while retaining its sign
and remaining payload bits. This replaces the earlier `f32` zero result for
zero input.

`min` and `max` ignore one NaN and return the other operand. When both are
NaNs, they quiet and return the left payload deterministically. For a tie
between `-0` and `+0`, `min` returns `-0` and `max` returns `+0`, regardless of
operand order. Two zeros with the same sign retain that sign. This is the
module's explicit number-selecting NaN policy; it does not promise signaling
NaN exception behavior.

`total_cmp(left, right)` returns `-1`, `0` or `1`. It distinguishes every
encoding and follows total ordering of the sign/magnitude representation:
negative NaNs precede negative infinity; negative values precede `-0`, then
`+0`, then positive values, infinity and positive NaNs. NaN quiet/signaling
bits and payloads participate, with the ordering reversed on the negative
side. It is suitable for deterministic sorting and agrees with the primitive
reference's total comparison.

## Neighbors and integral rounding

`next_up` and `next_down` return the adjacent representable value in the
specified numerical direction. Both zero encodings move upward to the smallest
positive subnormal and downward to the smallest negative subnormal. Positive
infinity remains fixed upward; negative infinity remains fixed downward. Moving
in the opposite direction reaches the largest finite magnitude. NaN inputs
retain every bit unchanged.

Integral rounding functions return floating-point values:

| Function | Direction / tie policy |
| --- | --- |
| `trunc` | Toward zero |
| `floor` | Toward negative infinity |
| `ceil` | Toward positive infinity |
| `round` | Nearest integer, half-way cases away from zero |
| `round_ties_even` | Nearest integer, half-way cases to an even integer |

All five use integer encoding operations. They preserve the appropriate zero
sign, retain infinities and NaNs unchanged, and return already integral large
values unchanged. They do not convert through a bounded integer type or depend
on the current floating-point rounding mode. Examples include
`round(-0.5) = -1`, `round_ties_even(-0.5) = -0`,
`round_ties_even(2.5) = 2` and `round_ties_even(3.5) = 4`.

## Square root

`sqrt` returns the correctly rounded nearest value, with ties to even. It
preserves `+0` and `-0`, accepts positive infinity and returns the canonical
positive quiet NaN for negative nonzero inputs, including negative infinity.
NaN input is quieted while preserving its sign and remaining payload. Negative
inputs no longer silently produce zero.

`sqrt_or(value, fallback)` returns the caller's fallback, unchanged, for NaNs
and negative nonzero inputs. Signed zeros and positive infinity are valid.

The implementation uses a restoring integer square root. Its normalization and
bit-generation approach is informed by
[fdlibm's integer square-root reference](https://netlib.org/fdlibm/e_sqrt.c).
The Lanius implementation has an explicit nearest-rounding value contract and
does not use floating-point additions to infer a hardware rounding mode.

For a positive finite input, normalization forms an exact integer significand
`M` and unbiased exponent `e`. Subnormals shift into the same normalized range.
When `e` is odd, doubling `M` and decrementing `e` makes it even without changing
the represented number. With precision `p` of 24 or 53, form the integer
radicand `N = M * 2^(p-1)`, held in two `u64` words. It needs at most 48 or 106
bits.

One restoring step per radicand bit pair maintains a root and remainder.
After 24 or 53 steps, `N = q² + r`, with `q = floor(sqrt(N))` and
`0 <= r < 2q + 1`. Nearest rounding increments `q` exactly when `r > q`:
the half-way square is `q² + q + 1/4`, and the integer `N` cannot equal it.
The result is then encoded with exponent `e/2`, handling a significand carry.
Intermediate root/remainder values fit `u64`. Every nonzero root of a finite
positive binary32/binary64 input is normal, so output subnormal rounding is
unnecessary. No approximate Newton iteration or host square-root call is used.

## Bounds and failure

`try_clamp(value, low, high)` returns `Result<float, ClampError>`. NaN bounds
or `low > high` return `ClampError::InvalidBounds`. Otherwise a NaN value is
returned unchanged; finite values and infinities are clamped by numerical
comparison. Numerically equal signed-zero bounds are valid, and an input
already within the bounds retains its encoding.

`clamp_or(value, low, high, fallback)` uses the explicit fallback for invalid
bounds. `clamp(value, low, high)` is strict and panics for invalid bounds.
This replaces the earlier implicit return of the input on invalid bounds.
The native panic is an immediate trap, tested for reversed and NaN bounds on
both widths. Use the checked or fallback API when invalid bounds are expected.

`between_exclusive` and `between_inclusive` are ordinary interval predicates.
They return false for NaN inputs/bounds and for reversed intervals.

## Executable evidence

`tests/stdlib_float_execution.rs` runs seven focused native groups, with about
684,000 bitwise comparisons against Rust primitive references. They cover:

- Exact bit transfer, both NaN signs, signaling/quiet payloads, signed zero,
  subnormal boundaries, finite extrema and infinity.
- Classification, sign queries, sign copying, neighbors, number-selecting
  min/max and total ordering, including random bit patterns and edge pairs.
- All integral rounding modes at half-way values, adjacent encodings,
  exponent boundaries and random patterns.
- Square roots over every binary32/binary64 exponent, selected significands,
  80,000 generated encodings and exceptional values. Results compare bitwise
  with native primitive square root.
- Checked clamping, fallbacks, intervals, finite constants and strict-clamp
  traps.
- Every helper with all heap-allocation calls denied, plus migrated existing
  `f32` runtime contracts.

The existing `f32` source-root loader test and floating-window application also
pass. The selected native raytracer gate passes after replacing its Rust reference's
unscaled Newton approximation with primitive `f32::sqrt`. The 19×10 native PPM
is byte-for-byte identical to the previous standard-library implementation.
Its separate static 16×9 `expected.ppm` disagreed with the corrected reference
until 2026-10-27, when it was regenerated: the native x86-64 output and the Rust
reference now produce the same bytes, and the fixture-oracle test passes.

Reference/test code controls native processes and supplies independent
expected values; all production behavior remains Lanius. No compiler, ABI,
runtime binding or formal proof change was required.
