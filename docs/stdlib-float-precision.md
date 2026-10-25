# Decimal precision formatting

`core::float_decimal` formats binary32 and binary64 values with an explicit
decimal precision. Fixed, scientific, and general notation round the exact IEEE
value to nearest, choosing an even final decimal digit at a halfway value.
Conversion uses Lanius integer arithmetic and caller scratch. It performs no
allocation and does not use a host formatter or the hardware rounding mode.

The original shortest formatting and parsing APIs retain their contracts. In
particular, shortest text is never an intermediate for precision formatting:
binary64 `2.675` formats with two fixed fractional digits as `2.67`, because its
exact binary value is below decimal `2.675`.

## API

Abbreviated `View` and `Result` below refer to `core::slice` and `core::result`.

```lanius
pub const MAX_PRECISION: i32 = 768;
pub enum PrecisionStyle { Fixed, Scientific, General }
pub struct PrecisionOptions {
    style: PrecisionStyle,
    precision: i32,
    alternate: bool,
    uppercase: bool
}
pub fn format_f32_precision_len(value: f32, options: PrecisionOptions,
    scratch: View<u32>, max_work: u64) -> Result<i32, Error>;
pub fn format_f64_precision_len(value: f64, options: PrecisionOptions,
    scratch: View<u32>, max_work: u64) -> Result<i32, Error>;
pub fn format_f32_precision_into(value: f32, output: View<u8>,
    options: PrecisionOptions, scratch: View<u32>, max_work: u64)
    -> Result<i32, Error>;
pub fn format_f64_precision_into(value: f64, output: View<u8>,
    options: PrecisionOptions, scratch: View<u32>, max_work: u64)
    -> Result<i32, Error>;
```

Every call requires the existing `SCRATCH_LEN` of **864 u32 elements**. Use
`default_format_work()` (1,000,000 units) as a starting work budget. Precision
must be in `0..=768`, including for nonfinite values. Every finite encoding,
including subnormals, is supported throughout this precision range.

Sizing returns the exact output byte count. Writing returns that count, writes
no NUL, and preserves surplus output bytes. A `Capacity(required)` error carries
the required count. Bounds, scratch, work, conversion, and capacity checks all
precede the first output write; **every returned error preserves the complete
output view**. Scratch can change on success or failure. Each sizing or writing
call has its own work budget.

The same backing requirements as [shortest conversion](stdlib-float-decimal.md)
apply: live backing for every claimed element, physically disjoint output and
scratch, and exclusive scratch during a call. Offsets, native strided arrays,
and packed storage all work. The metadata checks cannot prove backing,
lifetimes, or non-overlap. Only the first 864 scratch elements can change.

## Notation and rounding contract

| Style | Meaning of precision | Example with precision 3 |
| --- | --- | --- |
| `Fixed` | Digits after the decimal point | `1234.568` |
| `Scientific` | Digits after the decimal point, following one leading digit | `1.235e+03` |
| `General` | Significant digits; zero precision means one | `1.23e+03` |

General notation first rounds to the requested significant digits. If the
rounded scientific exponent is at least -4 and less than the effective
precision, it uses fixed notation; otherwise it uses scientific notation.
Without `alternate`, it removes fractional trailing zeros and removes an empty
decimal point. Integral zeros needed to express the value remain. For example,
`99.95` at general precision 3 becomes `100`; alternate form produces `100.`.
Rounding can change the notation: `9.999` at general precision 3 becomes `10`,
or `10.0` with alternate form.

Fixed and scientific notation retain the requested fractional zeros. A decimal
point appears when fractional digits are present, or whenever `alternate` is
true. Thus fixed precision zero formats `1.5` as `2`, or `2.` with alternate
form. General alternate form preserves all requested significant digits.

Scientific exponents always have a sign and at least two digits: `e+00`,
`e-09`, `e+38`, `e-324`. `uppercase` changes `e` to `E` and nonfinite spellings
to `INF` and `NAN`. Lowercase nonfinite spellings are `inf`, `-inf`, and `nan`.
NaN sign, payload, and signaling state are intentionally discarded, matching
the shortest API's treatment of NaN bits. Alternate form and precision add no
point or digits to nonfinite values.

Signed zero is preserved in every style, including a negative finite value
rounded to zero. Zero has scientific exponent zero. There is no locale,
grouping, width, alignment, sign-padding, hexadecimal, or percentage policy in
this API; surrounding formatters can compose those concerns.

The maximum result is **1079 bytes**: negative maximum binary64, fixed notation,
precision 768 (one sign, 309 integral digits, one point, 768 fractional digits).
The same buffer bound covers both widths and every option combination.

## Errors and bounded work

These functions reuse `core::float_decimal::Error`:

| Error | Condition |
| --- | --- |
| `Bounds` | Precision outside `0..=768`, or invalid view start/length/sum |
| `ScratchTooSmall(864)` | Selected scratch contains fewer than 864 elements |
| `WorkLimit` | Charged arithmetic, digit, or reserved rendering work exceeds `max_work` |
| `Capacity(required)` | Selected output is shorter than the result |

`InputLimit`, `DigitLimit`, and `Invalid` belong to parsing and are not returned
by precision formatting. Work exhaustion is explicit, even for zero and
nonfinite values. Rendering work is reserved before capacity validation and
before any output write. No larger precision silently clamps or truncates.

## Exact algorithm and storage bound

Decode the magnitude into `m * 2^e`. For negative `e`, form the exact decimal
integer coefficient `m * 5^(-e)` and scale it by `10^e`; otherwise shift `m`
left by `e`. The existing 128-limb integer operations construct that coefficient
and divide it into base-10^9 groups in scratch elements 768 through 863.

After division finishes, the integer's storage is dead. Its first 768 elements
then hold the coefficient's decimal digits. Rounding inspects the first omitted
digit, whether any later digit is nonzero, and parity of the last retained
digit. A carry propagates through retained nines and can advance the decimal
order. Values below half a requested quantum become zero; an exact half with
retained coefficient zero also becomes zero. The renderer supplies leading,
integral, and fractional zero padding without extending the stored coefficient.

For binary64, `m < 2^53` and `-e <= 1074`, so the coefficient is less than
`2^53 * 5^1074 < 10^767`: at most 767 digits and fewer than 2548 bits. Positive
exponents produce at most 309 digits. Binary32 has tighter bounds. Thus the
128 limbs (4096 bits), 96 groups (864 decimal digits), and 768 individual-digit
slots suffice independently of the requested precision. Rounding a prefix
cannot grow the stored digit array: an all-nine carry becomes leading one plus
implicit zeros. Loops are bounded by IEEE exponent and coefficient limits,
requested precision, and the explicit work budget. There is no recursion.

## Sources and deliberate choices

The notation contract follows the official
[Python format specification](https://docs.python.org/3/library/string.html#format-specification-mini-language)
and [C11 draft N1570, §7.21.6.1](https://www.open-std.org/jtc1/sc22/wg14/www/docs/n1570.pdf):
fixed/scientific fractional precision, general significant precision and its
rounded-exponent selection, alternate form, and two-digit signed exponents.
The [Rust formatting precision specification](https://doc.rust-lang.org/std/fmt/index.html#precision)
also specifies fractional precision and ties-to-even rounding. Rust's exponent
spelling differs; this API deliberately uses Python/C spelling. Precision is
always explicit here, so no default precision is hidden in conversion.

The [IEEE arithmetic documentation](https://docs.oracle.com/cd/E19957-01/806-3568/ncg_math.html)
describes exact single/double encodings and nearest rounding with even ties.
This implementation applies that rounding rule to the exact value at the
requested decimal quantum. It guarantees correct rounding at every supported
precision, including precisions beyond C's recommended minimum guarantees.
Its exact integer derivation is independent of those languages' production
formatting implementations.

## Executable evidence

`tests/stdlib_float_precision_execution.rs` compiles Lanius through the GPU
compiler to x86_64 Linux executables. It compares results with Python's builtin
`format` and independently checks the rounded rational with `Fraction` and
`Decimal.from_float`. Cases cover both signs, every binary exponent field,
transition neighbors, subnormals, extrema, nonfinite payloads, reproducible
random raw bits, exact ties, carry-induced notation changes, and precision
endpoints 767 and 768. Sizing is checked against writing for every model case.

The contract fixture exercises packed and native storage with offsets, scratch
and output guards, exact and insufficient capacities, invalid metadata,
precision bounds, and early and final work exhaustion. It runs under `strace`
with `mmap` forced to fail and checks for no mapping, heap, file, or network
system calls. Native execution is verified on x86_64 Linux; GPU kernel execution
and other targets have not been verified.
