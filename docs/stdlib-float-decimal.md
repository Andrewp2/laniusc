# Binary floating-point decimal conversion

`core::float_decimal` parses decimal text directly to binary32 or binary64 and
formats either type as a shortest significant decimal that round-trips to the
same finite value. The implementation is entirely Lanius, uses caller-owned
scratch, and does not allocate or call a host numeric parser/formatter.

Executable coverage is **x86_64 Linux, using the GPU compiler to produce native
programs**. GPU-kernel execution and other targets have not been verified.
The native `core::f32`/`core::f64` bit transfers supply the exact representations;
conversion itself uses integer arithmetic. This module does not depend on
floating-point multiplication, division or the current hardware rounding mode.

## API

The abbreviated types below are `core::slice::View` and
`core::result::Result`:

```lanius
pub const SCRATCH_LEN: i32 = 864;
pub fn scratch_len() -> i32;
pub fn default_format_work() -> u64;
pub fn default_limits() -> Limits;

pub struct Limits { max_input: i32, max_digits: i32, max_work: u64 }
pub enum Error {
    Bounds, ScratchTooSmall(i32), InputLimit, DigitLimit, WorkLimit,
    Invalid(i32), Capacity(i32)
}

pub fn parse_f32(input: View<u8>, scratch: View<u32>, limits: Limits)
    -> Result<f32, Error>;
pub fn parse_f64(input: View<u8>, scratch: View<u32>, limits: Limits)
    -> Result<f64, Error>;
pub fn format_f32_len(value: f32, scratch: View<u32>, max_work: u64)
    -> Result<i32, Error>;
pub fn format_f64_len(value: f64, scratch: View<u32>, max_work: u64)
    -> Result<i32, Error>;
pub fn format_f32_into(value: f32, output: View<u8>,
                       scratch: View<u32>, max_work: u64)
    -> Result<i32, Error>;
pub fn format_f64_into(value: f64, output: View<u8>,
                       scratch: View<u32>, max_work: u64)
    -> Result<i32, Error>;
```

Provide at least **864 u32 elements**, not 864 bytes. Contents need not be
initialized to any particular value. Only that prefix is scratch; extra elements
are preserved. Six 128-limb integers occupy the first 768 elements and 96
base-10^9 groups occupy the remainder. The implementation has no recursion and
uses no heap storage. Current compiler array declarations require literal counts
such as `[u32; 864]`; callers can still compare the resulting view length with
`SCRATCH_LEN` or `scratch_len()`.

Inputs, output and scratch must have live physical backing for every claimed
element. Input/output/scratch must be physically disjoint. Nonzero view offsets,
native strided arrays and packed byte storage work through ordinary view
indexing. The library checks nonnegative `start`/`length` and their signed-i32
sum; those metadata checks cannot establish physical backing, overlap or
lifetimes. Scratch is exclusive to one active conversion and can change on
success or failure. Lanius does not enforce these storage conventions yet.

Formatting returns the exact byte count, writes at `output.start`, and preserves
all surplus output bytes. It writes no terminating NUL. A capacity error carries
the required byte count. **Every returned error preserves the entire output.**
The sizing calls perform the same conversion and return that exact count;
calling `*_into` afterwards performs conversion again with its own work budget.
A 24-byte output view is sufficient for either width under the spelling policy
below, including negative numbers and special values.

## Parse grammar and rounding

The ASCII decimal grammar is:

```text
[+-]?(digits[.digits?]? | .digits)([eE][+-]?digits)?
```

At least one mantissa digit is required. Leading plus, leading zeros, `.5`,
`1.`, `1.e2` and leading exponent zeros are accepted. Whitespace, separators,
hexadecimal syntax, Unicode digits and trailing bytes are rejected. Special
values are signed, case-insensitive `inf`, `infinity` or `nan`; NaN payload
syntax is not accepted.

Finite inputs round to the nearest representable binary value, with exact
halfway values choosing the even significand. This includes the normal/subnormal
transition, zero/minimum-subnormal midpoint, and maximum-finite/infinity
threshold. Negative zero is preserved, including negative values that underflow.
Overflow produces the correctly signed infinity. Parsing `nan` produces the
canonical quiet NaN (`0x7fc00000` or `0x7ff8000000000000`), preserving an explicit
negative sign. It does not infer a payload from text.

All mantissa digits contribute to the exact integer coefficient. No decisive
tail is silently discarded. All mantissa digits, including leading and trailing
zeros, count towards `max_digits`; exponent digits do not. The complete syntax
is checked before a valid zero or clearly out-of-range value is returned.
Exponent magnitude saturates internally at 1,000,000. With at most 768 mantissa
digits, a larger positive or negative exponent cannot change the overflow or
underflow result; this avoids an unbounded arithmetic loop for long exponents.

The default limits are:

| Limit | Default | Meaning |
| --- | ---: | --- |
| `max_input` | 1024 | Selected input bytes |
| `max_digits` | 768 | Mantissa digits; hard supported range is 0 through 768 |
| `max_work` | 1000000 | Charged integer/character work for this call |

Negative signed limits, or `max_digits > 768`, return `Bounds`. Callers may
increase the input-byte limit to allow longer exponent spelling; the mantissa
digit ceiling remains fixed. Values beyond the byte/digit/work budgets return
explicit resource errors. These limits bound accepted representations, rather
than treating an unprocessed suffix as insignificant.

## Shortest formatting policy

For each finite value, the formatter finds the fewest significant decimal
digits inside that value's exact nearest-even rounding interval. At the first
working precision it chooses the decimal closest to the exact binary value.
If two candidates are equally close, it chooses the one with an **even decimal
coefficient**. Binary32 requires at most 9 significant digits; binary64 at most
17. Decimal coefficient trailing zeros are removed, adjusting the exponent.

The output uses whichever of these spellings is shorter; equal lengths choose
fixed notation:

- Fixed notation has a leading zero before the point for magnitudes below one.
- Scientific notation has one digit before the point, lowercase `e`, no positive
  exponent sign, and no exponent zero padding.
- Neither form adds a point or fractional zero when unnecessary.

Examples include `0.1`, `125`, `1e20`, `1e-45` and `5e-324`. Signed zeros are
`0` and `-0`. Infinities are `inf` and `-inf`. Every NaN formats as `NaN`;
decimal text intentionally does not preserve NaN sign, payload or signaling
state. Use `to_bits`/`from_bits` or a binary codec when those bits matter.

This is shortest significant decimal formatting under the stated notation
rules. It does not offer fixed precision, locale formatting, hexadecimal output
or a JSON-number policy; infinities and NaNs are part of this API's explicit
grammar.

## Algorithms and speed

Shortest formatting always uses Schubfach (R. Giulietti, "The Schubfach way
to render doubles", 2020, as in the JDK's `Double.toString`). Parsing tries
the Eisel-Lemire fast path first and falls back to the exact algorithm below
only when the fast path cannot prove its answer. Results are identical either
way; only speed changes.

- **Formatting.** Schubfach is exact for every finite nonzero binary64 and
  binary32 value, so there is no fallback path. For a value `c * 2^q` with
  `k = floor(q log10 2)`, it multiplies `c` and both interval ends by a
  126-bit upward-rounded `g ≈ 10^-k`. These are 64x128-bit products built
  from u64 pieces. Rounding to odd keeps the comparisons exact.
  - The algorithm first tries the at most one multiple of `10^(k+1)` inside
    the rounding interval.
  - Otherwise it takes `floor(v * 10^-k)` or that value plus one: whichever
    is inside, or, when both are, the closer one with ties to even.
  - Two changes from the JDK version give Python's shortest spelling instead
    of Java's two-digit minimum. The shorter candidate is tried from two
    digits up (the JDK starts at three), and tiny subnormals are not scaled
    by 10. So `5e-324` and `1e-323` keep one digit.
  - Integers below `2^53` (`2^24` for binary32) are their own spelling.
  - Digits are spelled eight at a time with multiply-shift division.
- **Parsing.** Parsing uses the Eisel-Lemire algorithm (Lemire, "Number
  Parsing at a Gigabyte per Second", 2021, as in fast_float and Rust's
  `dec2flt`). A first pass validates the whole syntax and keeps the leading
  19 significant digits.
  - With at most 19 significant digits, one 128-bit truncated product with a
    power of five decides the result.
  - A longer mantissa lies between the truncated digits `w` and `w + 1`. When
    both bounds round to the same value, that is the answer.
  - Otherwise, as for exact halfway cases, the exact numerator is built and
    the big-integer search runs. The big-integer workspace is set up only
    then.

The 651 128-bit powers of five and the 617 Schubfach `g(k)` values for `k`
in [-324, 292] live in `core::float_tables`, generated by
`tools/generate_float_tables.py`. They are binary-search trees of 64-bit
literals, so a lookup is about ten comparisons with no table decoding.

Each conversion charges 100 work units. A budget below 101 still returns
`WorkLimit`, and a short scratch view still returns `ScratchTooSmall`, so the
error contract is unchanged. Formatting uses no scratch beyond that check.

Measured on the laptop on 2026-10-31 as the minimum of 5 interleaved runs
under load, in µs per call:

| Workload | Grisu3 and hex-decoded tables | Schubfach and tree tables |
| --- | ---: | ---: |
| `format_f64_into`, uniformly random finite bits | 1.81 | 0.79 |
| `format_f64_into`, values in [2^-8, 2^8) | 1.09 | 0.66 |
| `format_f32_into`, uniformly random finite bits | 1.04 | 0.59 |
| `parse_f64`, 17-digit `repr` strings | 1.46 | 0.79 |
| `parse_f32`, 9-digit strings | 1.34 | 0.70 |

The parse figures exclude splitting the input into lines. At the start of the
S5 work, before Grisu3 was tuned, formatting took about 2.5 µs and parsing
about 1.5 µs per call. Every code path still costs about 15 instructions per
statement in the current native code, so the remaining time is mostly the
digit loops and the `Result` plumbing.

## Exact algorithm and bounds

Parsing builds the exact integer ratio `N / D` for the decimal. A binary search
over positive finite encodings finds the representable floor. Exact integer
comparison with its upper dyadic midpoint then chooses the nearest result and
resolves halfway parity. Bit-length comparisons precede shifts to avoid
constructing unnecessarily large intermediate integers. Both widths use the
same algorithm with their own binary format parameters.

Shortest formatting does no big-integer work (see Schubfach above). Fixed
precision formatting keeps its exact big-integer path.

The exact paths follow exact-boundary reasoning described by the
[Ryu author's implementation](https://github.com/ulfjack/ryu/blob/master/ryu/d2s.c)
and [Loitsch's paper, sections 2.1–2.2](https://www.cs.tufts.edu/~nr/cs257/archive/florian-loitsch/printf.pdf).
They are an independent bounded big-integer implementation, with no
production host conversion code. The
[Ryu parser source](https://github.com/ulfjack/ryu/blob/master/ryu/s2d.c)
also provides primary discussion of decimal parsing and exact rounding.

The hard mantissa bound and early decimal-order checks keep all parser
intermediates below 4096 bits. Every integer has at most
128 limbs; all decimal-group loops have at most 96 iterations. The budget charges
limb visits plus character/scalar costs, with a deliberately conservative charge
for several operations. A bounded primitive operation can finish before an
exhausted budget is observed at the next checkpoint; the budget is not a precise
instruction counter. `default_format_work()` returns 1,000,000, sufficient for
every finite representation under these bounds. A caller-selected lower budget
can return `WorkLimit` even for a small output. The default parsing budget also
covers the supported 768-digit mantissas within the default input-byte limit.

| Error | Meaning |
| --- | --- |
| `Bounds` | Invalid view metadata or unsupported signed limit configuration |
| `ScratchTooSmall(864)` | Fewer than the required scratch elements |
| `InputLimit` | Input exceeds the configured byte limit |
| `DigitLimit` | Mantissa exceeds the configured digit limit |
| `WorkLimit` | Conversion exhausts its work budget |
| `Invalid(offset)` | Invalid syntax at a zero-based offset relative to the selected input; input length means an expected digit is missing at the end |
| `Capacity(required)` | Actual output view is too short; required is exact |

No public API silently falls back to a rounded approximation, truncated output,
host service or no-op. Internal capacity assertions express the fixed integer
bounds; malformed input is handled through the public errors.

## Executable evidence

### Python oracle (2026-10-31)

[`float_oracle/oracle.py`](../tests/fixtures/stdlib_execution/float_oracle/oracle.py)
drives [`float_batch.lani`](../tests/fixtures/stdlib_execution/float_oracle/float_batch.lani),
a native batch program built by the GPU compiler. It is registered in
`tests/stdlib_float_oracle_execution.rs`. The cases include subnormals,
powers of two, all-ones significands, min/max finite, overflow and underflow
thresholds, exact binary midpoints and their neighbours one unit away in a
digit beyond the 700th, and long 20–120-digit mantissas.

| Group | Reference | Cases | Agreement | Time |
| --- | --- | ---: | ---: | ---: |
| parse64 | `float(text)` bits | 2,000,000 | 2,000,000 | 28.5 s |
| parse32 | `float(text)` to binary32, with exact rational resolution of binary32 midpoints | 500,000 | 500,000 | 12.8 s |
| format64 | `repr(x)` digits and exponent, and `float(output) == x` | 2,000,000 | 2,000,000 | 28.1 s |
| format32 | Exact rational shortest/closest/even model, plus round trip | 300,000 | 300,000 | 50.9 s |

Times include generating the cases in Python and checking them. The
contract fixtures `float_decimal_contracts.lani` and
`float_precision_contracts.lani` still pass. The older Rust-referenced
groups below were not rerun: this session did not run `cargo test`.

### Earlier receipts

`tests/stdlib_float_decimal_execution.rs` compiles Lanius fixtures to native
executables and executes seven focused groups:

- 6,144 binary32 and 20,480 binary64 patterns cover every exponent class, both
  signs, boundary significands and reproducible random raw bits. Every finite
  output independently parses to its original bits, and significant precision
  agrees with Rust's shortest formatter.
- Rust sometimes chooses the other decimal candidate at an exact equal-distance
  tie. Such disagreements must be adjacent, retain shortest precision, and
  select our even coefficient; Python standard-library exact rational arithmetic
  independently proves equal distance. Arbitrary last-digit differences fail.
- 4,096 generated decimal tokens, explicit grammar and extreme exponent cases
  parse at both widths against Rust's direct float parser.
- Exact dyadic midpoints, plus or minus the last decimal unit, test halfway
  parity at zero, subnormals, powers of two and overflow. Long cases exceed
  700 digits and retain the decisive final digit.
- Invalid syntax offsets, byte/digit/work limits, insufficient scratch,
  nonzero offsets, strided backing, exact/short output capacity and guards are
  checked at runtime. Syscall tracing plus injected allocation failure confirms
  that the conversion contract fixture makes no allocation or host-service
  calls.
- A separate 2,048-value native batch checks varied binary64 exponents with the
  default work and scratch budgets.

The final seven-group run passed in **14.00 seconds**. A separate one-process
batch of 2,048 varied finite binary64 values measured **490.475 ms formatting**
and **219.204 ms parsing** on the development machine. Format timing includes
argv loading, parsing raw u64 bit arguments and writing 47,069 output bytes;
parse timing includes argv loading and writing resulting u64 bit patterns for
45,021 input text bytes. Process startup and I/O are included. Compilation and
Python reference checks are excluded. All 4,096 conversion results were checked
against independent raw-bit transfer. These are whole-fixture measurements,
not a comparison with optimized Ryu or a claim about GPU throughput.

Run the focused suite with:

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR=/home/andrew-peterson/code/laniusc/target/stdlib-build \
  CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test stdlib_float_decimal_execution -- --nocapture
```

Rust and Python are independent test references only. No network bootstrap or
third-party test package is required. Runtime execution requires Linux x86_64,
the project's GPU compiler environment, Python 3 and `strace` for the allocation
contract check. Compiler warnings in the current build are unrelated to this
module. No compiler changes were required for conversion.
