# Exact borrowed decimal numbers

`core::decimal_number` parses JSON number tokens and supplies exact ordering,
equality, integer classification and divisibility. The implementation is Lanius,
uses no allocation or floating point, and retains arbitrary coefficient and
exponent digits in borrowed input. It does not round, saturate exponents, or
materialize a number of zeroes proportional to an exponent's numeric value.

The verified executable target is **x86_64 Linux**. These pure algorithms have no
host-service dependency; GPU-kernel execution and other targets are unverified.

## Parsing and borrowing

`parse(core::slice::View<u8>) -> Result<Decimal, Error>` accepts one complete
number token using the grammar in [RFC 8259 section 6](https://www.rfc-editor.org/rfc/rfc8259#section-6):

```text
-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?
```

Whitespace, delimiters, leading integer zeroes, a leading plus sign, absent
fraction/exponent digits, NaN and infinity are errors. Exponent leading zeroes
and an exponent plus sign are valid. Coefficient precision and exponent length
are limited only by physically backed input and the View's `i32` range.

`Error` has public `kind: ErrorKind` and `offset: i32` fields. `Syntax` identifies
the first byte at which parsing cannot continue, relative to the selected view.
A required byte missing at end of input has offset `view.len()`. `Bounds` rejects
negative or overflowing logical view ranges and has offset `-1`. Parsing leaves
all input bytes unchanged.

A Decimal is a shallow borrow. Its source bytes must remain alive and unchanged
for every operation using it. Valid values come from `parse`; hand-constructed
or subsequently mutated metadata is outside the contract. There is no destructor.
Packed buffers, native strided arrays and selected subviews work. Physical
backing length remains a caller precondition: falsely claiming more input bytes
can trap during bounds-checked indexing. The compiler does not enforce the
borrowing and immutability rules.

## Queries and numerical comparison

| Method | Meaning |
| --- | --- |
| `is_zero()` | The mathematical value is zero, regardless of sign or exponent |
| `is_negative()` | The original token contains a leading minus, including `-0` |
| `is_integer()` | The mathematical value has no fractional part |
| `compare(other)` | Exact numerical ordering, returning `-1`, `0` or `1` |
| `equal(other)` | Exact numerical equality, equivalent to `compare(other) == 0` |
| `borrow()` | Borrow the same Decimal record |

Every representation of zero compares equal. For example, `-0e999999999999999999`
equals `0`. The lexical sign query deliberately retains a minus on zero; callers
checking mathematical negativity must also check `!is_zero()`.
`1.20` equals `12e-1`; `9007199254740993` is greater than `9007199254740992`;
`1200e-2` is an integer and `1200e-3` is not. These decisions do not use a binary
floating-point approximation. This supports the unbounded numerical semantics
required by [JSON Schema numeric validation](https://json-schema.org/draft/2020-12/json-schema-validation#section-4.2).

Internally, the coefficient is its nonzero-bounded mantissa digit window.
Leading and trailing zeroes are excluded without copying. If `e` is the exact
signed exponent, `i` is the integer digit count, and `first`/`last` are the first
and last nonzero mantissa digit ordinals, then:

```text
normalized scale = e + i - 1 - last
decimal order    = e + i - first
value magnitude = normalized coefficient * 10^(normalized scale)
```

Zero is handled separately. A nonzero value is an integer exactly when its
normalized scale is nonnegative. Comparison checks signs and decimal orders,
then compares coefficient digits padded with zeroes on the right.

Exponent adjustment never converts an arbitrary exponent to a native integer.
Up to 18 low digits form a bounded tail; the remaining prefix stays borrowed.
Adding a small offset changes the tail and at most one carry or borrow through
the prefix. A precomputed pivot describes any run of nines/zeroes and any added
or removed leading digit. The resulting virtual decimal digits can be compared
exactly, including across arbitrarily long shared prefixes. Native offsets stay
within approximately eleven decimal digits for all physically valid inputs.

## Divisibility and caller scratch

```text
scratch_len(divisor: Decimal) -> Result<i32, Error>
is_multiple_of(dividend, divisor, scratch: View<u8>, max_work: u64)
    -> Result<bool, Error>
is_multiple_of_counted(dividend, divisor, scratch: View<u8>, max_work: u64)
    -> Result<Multiple, Error>
Multiple { value: bool, work: u64 }
```

The result is true exactly when division produces an integer. Negative nonzero
divisors are supported. A JSON Schema validator must separately enforce its
strictly positive `multipleOf` keyword value. Zero dividends are multiples of
every nonzero divisor. Zero divisors return `ZeroDivisor`, including `0 / 0`.

Scratch requires the normalized divisor coefficient digit count plus one byte.
Its contents are temporary numeric digits, not ASCII. It may be larger than
required; bytes outside the required prefix remain unchanged. Scratch must be
writable, physically backed and disjoint from **both** immutable number inputs.
Logical View bounds are checked. Aliasing is a caller precondition.

Preflight order is zero-divisor/capacity check, scratch bounds, scratch size,
then work. `CapacityOverflow` reports an unrepresentable scratch length;
`ScratchTooSmall` reports insufficient logical length. These errors and `Bounds`
leave scratch unchanged. Work exhaustion returns `WorkLimit`; scratch may then
hold partial state. Operational errors have offset `-1`. No error is silently
converted into a false divisibility result.

After normalized scales are compared, the algorithm computes the coefficient
remainder by decimal long division, with at most nine subtractions per next
digit. A smaller dividend scale cannot produce an integer quotient because its
normalized coefficient has no factor of ten. With a nonnegative scale
difference, zero digits are appended to the remainder. Only the smaller of the
exact scale difference and `4 * divisor_coefficient_digits` steps are needed.
Any remaining denominator factor coprime to ten can never be repaired. All
factors of two or five in a divisor below `10^digits` are exhausted within that
cap. Thus even an exponent containing thousands of digits cannot cause a loop
proportional to its numeric value. Scale differences use exact comparisons and
a bounded binary search, without subtracting arbitrary exponent strings.

## Work limits and cost

`max_work` limits logical digit operations in divisibility. Charged operations
include initialization, exponent tail/pivot scans, virtual exponent comparisons,
scratch digit initialization, shifts, comparisons, subtraction and zero scans.
Each unit performs bounded scalar work; virtual tail digit access uses at most
18 native multiply/divide steps. Fixed metadata checks and bounded binary-search
control are included in the constant overhead. This is an algorithm budget, not
an instruction count or a wall-clock deadline.

Every successful counted call reports its consumed units. An enclosing parser
or validator can pass its remaining budget and subtract `Multiple.work` after
success. `WorkLimit` must terminate or propagate as a resource error. A call that
succeeds using `N` units also succeeds with budget `N`, fails with `N-1`, and
reports the same `N` with a larger budget. Zero budgets fail after preflight;
a zero dividend requires one unit after valid scratch preflight.

Parsing and the simple queries have no separate budget argument. Parsing,
integer classification and comparison have linear cost in their selected input
byte lengths, with fixed record storage. A conservative charging rule for a
shared application budget is **`256 * (sum_of_selected_input_lengths + 1)`**
units per parse, integer classification, comparison or equality call. Use one
length for parse/integer classification, two for comparison/equality, and perform
the arithmetic as checked `u64`. This intentionally overcharges short-circuit
cases. `is_zero`, `is_negative`, `scratch_len` and `borrow` are constant cost.

Divisibility uses `O(B)` scratch and
`O(B * (A + min(scale_difference, 4*B)))` decimal digit work, plus linear
exponent scans for a bounded binary search. `A` and `B` are normalized coefficient
digit counts. Long coefficients can be expensive; the explicit work budget is
part of the public contract. No heap allocation occurs, including on errors.

## Executable evidence

`tests/stdlib_decimal_number_execution.rs` has two focused executable groups:

- Grammar and error offsets, signed zero, values beyond `2^53`, integer
  boundaries, huge exponent carry/borrow, native strided/offset input and scratch
  views, input preservation, scratch suffix guards, zero divisors and exact
  counted-budget thresholds. `strace` observes no allocation or file/stream I/O.
- 2,525 numeric pairs compared with independent Python reference arithmetic:
  `Fraction(Decimal(...))` for moderate exponents and arbitrary integers/modular
  exponentiation for huge exponents. Coverage includes 8,192-digit coefficients
  and exponents, matching long prefixes, adjacent exponents, carry/borrow across
  the 18-digit split, leading exponent zeroes, equivalent encodings, positive
  and negative divisors, and `2^1000`/`3*2^1000` divisors that require more than
  three times their decimal digit count of factor repair.

Python and Rust are test/reference drivers only. Production numerical behavior
is implemented in `stdlib/core/decimal_number.lani`. The tests execute native
programs produced by the GPU compiler, rather than treating type checking as
runtime evidence.

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test stdlib_decimal_number_execution -- --nocapture
```
