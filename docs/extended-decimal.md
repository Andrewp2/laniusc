# Finite arbitrary precision decimals

`ext::decimal` provides owned finite decimal arithmetic over `ext::big_int`.
A value is an arbitrary signed integer coefficient multiplied by ten raised
to a checked decimal exponent. The implementation is entirely Lanius; it
uses the existing big integer provider for integer arithmetic and division.
It never calls a host decimal package or converts through binary floating
point. `core::decimal_number` and `core::float_decimal` remain the separate
bounded conversion facilities.

The behavioral reference is the finite model, string grammar, rounding,
division, quantize and reduce operations in the
[General Decimal Arithmetic specification 1.70](https://speleotrove.com/decimal/decarith.html).
This is a finite arithmetic library, rather than an IEEE 754 decimal
interchange type or a complete implementation of that specification.

## Values, equality and quantum

The exponent records a value's quantum. For example, `1.20` has coefficient
`120`, exponent `-2` and scale `2`; `1.2` has coefficient `12` and exponent
`-1`. Both compare equal and have the same hash. Leading coefficient zeros
are removed. Trailing coefficient zeros are retained, and zero is always
nonnegative while retaining its exponent. Thus `-0.00` becomes unsigned zero
with exponent `-2`. `zero()` has exponent zero. Zero has precision one.

Each nonzero value caches its coefficient's unsigned decimal digits alongside
its owned `BigInt`. The cache costs an additional allocation and conversion
work when constructing arithmetic results. It makes comparison, equality,
ordering and hashing allocation free: comparisons first inspect sign and
adjusted exponent, then compare digit sequences with implicit trailing zeros.
No allocation or resource error can be interpreted as equal values.
`value_hash()` hashes the sign, coefficient without trailing zeros, and its
corresponding exponent using FNV-1a. All zeros have the same hash.

`Decimal` implements `core::cmp::Eq`, `Ord`, `PartialEq`, `PartialOrd`, and
`core::hash::Hash`. Its partial order never returns `Unordered`. Ordering and
hashing concern numeric value, while `exponent()` and formatting expose the
retained quantum. `reduce(limits)` removes trailing coefficient zeros; it
sets zero's exponent to zero.

## Ownership and failure

Ordinary record copies are shallow. Keep one active owner of every `Decimal`
and call `destroy()` exactly once when finished. `try_clone(limits)` creates
an independent owner. Destroying that owner clears both its coefficient and
cache and resets it to zero. Borrow operands with `value.borrow()`; every
arithmetic operation returns independent storage and preserves all input
owners on success and on failure, including self aliases.

All fallible operations return `core::result::Result<T, ext::decimal::Error>`.
The error variants are `Bounds`, `InvalidSyntax`, `NonFinite`, `DigitLimit`,
`ScaleLimit`, `LimbLimit`, `WorkLimit`, `OutputLimit`, `AllocationFailed`,
`DivisionByZero`, `Inexact`, and `Overflow`. Partial results are destroyed
before errors are returned. Callers must also destroy returned owned byte
vectors and big integers. `from_coefficient` borrows and clones its integer;
`to_big_int` returns an independent owned integer.

The coefficient, cache, and exponent fields are implementation storage.
Borrowed views and shallow copies must not mutate or destroy them. These
ownership and immutability rules are manual conventions, not compiler enforced
lifetimes or uniqueness.

## Construction and conversion

| API | Contract |
| --- | --- |
| `zero()` | Allocation free zero with exponent zero |
| `from_i64(value, limits)`, `from_u64(value, limits)` | Exact machine integer construction |
| `from_coefficient(coefficient: &BigInt, exponent: i32, limits)` | Independent coefficient clone at the requested exponent |
| `parse(input: View<u8>, limits)` | Exact ASCII decimal parser |
| `parse_text(input: Text, limits)` | Same parser over the entire borrowed UTF-8 text |
| `to_big_int(rounding, limits)` | Independent integer after rounding to exponent zero |
| `to_i64(limits)`, `to_u64(limits)` | Exact integer conversion; fractional values are `Inexact`, out of range is `Overflow` |

The complete finite grammar is `[+-]?(digits[.digits?]?|.digits)([eE][+-]?digits)?`,
where `digits` contains at least one ASCII decimal digit. Examples include
`+12.00`, `.5`, `17.`, `0.73e-7`, and `-123E+20`. There is no whitespace,
separator, radix prefix, NUL terminator, or implicit precision rounding.
Malformed strings return `InvalidSyntax`. Valid case insensitive `Inf`,
`Infinity`, `NaN`, and `sNaN` spellings, including signed forms and diagnostic
NaN digits, return `NonFinite`. No infinities, NaNs, or negative zeros are
stored. Exponent text is checked without integer wraparound; an exponent
outside the configured range returns `ScaleLimit` even for zero.

The parser retains fractional trailing zeros and applies an explicit exponent
exactly. Leading zeros do not consume the significant digit limit, although
all input bytes consume work. The input view uses ordinary logical indexing,
including selected subviews and the language's native array strides. The
caller must provide valid live backing for the selected range.

## Exact arithmetic and rounding

| Methods | Contract |
| --- | --- |
| `borrow()`, `destroy()`, `try_clone(limits)` | Ownership operations |
| `is_zero()`, `sign()`, `precision()`, `exponent()`, `scale()` | Allocation free queries; sign is `-1`, `0`, or `1`; scale is negative exponent |
| `compare(other)`, `value_hash()` | Allocation free numeric comparison and hash |
| `neg(limits)`, `abs(limits)` | Independent exact results |
| `add(other, limits)`, `sub(other, limits)` | Exact coefficients aligned at the smaller input exponent |
| `mul(other, limits)` | Exact product with the sum of input exponents |
| `pow(exponent: u32, limits)` | Exact nonnegative integer power by squaring, retaining the repeated multiplication quantum |
| `rescale(target_exponent: i32, rounding, limits)` | Set an explicit result exponent; append zeros or round as needed |
| `round(context, limits)` | Round to at most the requested number of significant digits |
| `quantize(quantum, context, limits)` | Rescale to the other value's exponent and require the result to fit context precision |
| `div(other, context, limits)` | Correctly rounded division at context precision |
| `reduce(limits)` | Exact removal of trailing coefficient zeros |

`Context { precision: i32, rounding: Rounding }` has strictly positive
precision. `default_context()` selects 34 digits and `HalfEven`. Exact
addition, subtraction, multiplication and powers do not apply a context or
silently round. The exponent of a zero power result is the original exponent
multiplied by the power. The integer power contract uses `x^0 = 1`, including
`0^0`, as the integer provider does. Negative and nonintegral powers and
transcendental functions are outside this API.

The eight rounding modes apply symmetrically to a signed coefficient:

| Mode | Behavior when discarded digits are nonzero |
| --- | --- |
| `Down` | Toward zero |
| `Up` | Away from zero |
| `Floor` | Toward negative infinity |
| `Ceiling` | Toward positive infinity |
| `HalfUp` | Nearest; exact ties away from zero |
| `HalfDown` | Nearest; exact ties toward zero |
| `HalfEven` | Nearest; exact ties choose an even retained digit |
| `Unnecessary` | Return `Inexact` |

Removing only zero digits succeeds under every rounding mode. Rounding a
negative magnitude to zero produces unsigned zero. `round` repairs a carry
such as `9.995` at precision three to `10.0` with precision three. `rescale`
retains its requested exponent, so the same carry to exponent `-2` is `10.00`.
`quantize` returns `DigitLimit` when the result cannot fit its precision and
never changes its requested exponent to fit a carry. `rescale` has no separate
context precision requirement beyond the resource digit limit.

Division computes the decimal order of the exact ratio, scales an integer
numerator or denominator to the requested final precision, and uses the
big integer quotient and remainder. Remainder comparison with half the
divisor determines rounding exactly; no guard digit approximation or binary
float is involved. An exact result removes trailing zeros only toward the
preferred exponent (dividend exponent minus divisor exponent). An inexact
result has the context precision, except that carry normalization may change
its exponent. The divisor's sign determines the quotient sign, independently
of the positive remainder calculation. Division by zero is always an explicit
`DivisionByZero`, including zero divided by zero.

## Resource bounds

Every fallible call takes a `Limits` value:

```lanius
pub struct Limits {
    max_limbs: i32,
    max_digits: i32,
    max_scale: i32,
    max_work: u64,
    max_output: i32
}
```

Defaults are 1,048,576 limbs, 100,000 coefficient digits, absolute exponent
100,000, 100,000,000 work units, and 1,048,576 output bytes. Invalid bounds
return `Bounds`: limbs must be in `0..536870911`, digits in
`1..1000000000`, scale in `0..1000000000`, and output nonnegative.
`max_scale` bounds the absolute stored exponent, rather than adjusted exponent.

`max_digits` bounds each input/result coefficient and each decimal scaling
scratch coefficient. It is independent of context precision. Consequently,
precision five with a five digit resource bound can reject `1/3`: the scaled
integer numerator requires six digits. Supply scratch headroom as well as
output precision. `max_limbs` bounds each integer allocation following
`ext::big_uint`'s rules, including its single division guard limb. Neither is
a total live memory quota; the allocator may deny every allocation. Cache
and output vector capacity/allocation failures return `AllocationFailed`.
An operation with smaller per-call limits validates existing input sizes too.

A single remaining work budget is shared across a call's composed operations,
including powers. Decimal syntax/cache construction precharges three units
per input byte; scaling charges its copied/added digits; discarded suffix and
tie scans precharge twice the coefficient length. Integer primitive calls
are charged conservative bounds derived from the actual limb counts or
maximum decimal-to-limb count before dispatch. Coefficient-to-cache conversion
also covers signed insertion/removal copies. These bounds deliberately may
reject work which would finish with a smaller number of instructions.
Queries, comparisons, hashing, bounded setup and allocator internals are not
an instruction meter. Applications requiring a budget across calls must
account for that separately.

Plain and scientific formatting charge one unit per emitted byte.
`format_into` charges both the staged output and the subsequent atomic copy,
so it needs twice the byte count. `measure` uses the same plain byte-count,
output-limit and work preflight as `format`, without allocating.

Exponent overflow and underflow relative to the configured range return
`ScaleLimit`. The library does not silently clamp to zero, create a subnormal,
produce infinity, set sticky flags, or implement traps. Explicit rescaling to
a permitted exponent can round a tiny value to zero. Exact division removes
scratch trailing zeros before applying the final exponent range, so a large
context precision does not itself force a scale error for an exact integer
quotient. These are deliberate finite-library boundaries rather than the
full GDA/IEEE exception model.

## Formatting and atomic output

`format(limits)` returns owned plain decimal bytes with no exponent. Fractional
quantum is retained (`1.20` formats as `1.20`); positive exponent is expanded
with zeros (`1E+3` formats as `1000`). Positive exponent zero formats as `0`.
Thus plain formatting roundtrips numeric value but can lose a positive quantum.

`format_scientific(limits)` always uses scientific notation: one leading
coefficient digit, an optional decimal point and remaining digits, then `E`
and a signed adjusted exponent. It preserves coefficient and quantum,
including zero's exponent: `1.20` gives `1.20E+0`; zero at exponent `-3` gives
`0E-3`. Parsing that representation reproduces the original quantum.

`format_into(output: View<u8>, limits)` stages the entire plain representation
before changing caller storage. All output bytes stay intact on any error,
including invalid view metadata, insufficient capacity, limits or allocation
failure. Success changes only the returned prefix of the selected view.
There is no implicit terminator. Input owners survive formatting errors.

## Executable evidence

`tests/extended_decimal_execution.rs` compiles and executes native x86_64 Linux
Lanius fixtures. Python `decimal` supplies the independent rounding/quantum
reference and `Fraction` additionally checks exact arithmetic identities.
Deterministic cases include ties and adjacent values in all rounding modes,
negative exponents, cancellation over 1,500 digits, 1,024 significant digit
repeating division, carry repair, exact and inexact rescaling, comparisons
across quantum, signed extrema, malformed input, limits and repeated owned
updates. No Rust or Python implementation is linked into the production
library.

The allocation suite traces every `mmap` in each of 23 construction,
arithmetic, conversion and formatting scenarios, injects `ENOMEM` at every
observed allocation, verifies surviving operands, and requires every successful
allocation to have a matching `munmap`. Atomic output is checked under both
capacity and allocation failures. This evidence concerns the native target;
it makes no GPU execution claim.

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR=/home/andrew-peterson/code/laniusc/target/stdlib-build \
  CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --test extended_decimal_execution -- --test-threads=1
```
