# Native 64 bit and pointer width integers

`core::i64`, `core::u64`, `core::isize` and `core::usize` implement native integer
arithmetic in Lanius. Execution evidence is **x86_64 Linux**. On this target all
four types have 64 bits; pointer width constants describe this verified target.
Other pointer widths need a target-specific implementation and execution tests.
These modules allocate nothing and call no host service.

The signed and unsigned fixed width modules own the arithmetic algorithms.
The pointer width modules preserve their distinct input, output and Option
types while reusing those algorithms. Arithmetic on a `usize` value does not
establish that it is a valid allocation size or pointer offset.

## Arithmetic and failures

All four modules expose `MIN`, `MAX`, `BITS` and `BYTES`, comparison and range
queries, parity and multiple queries, and these arithmetic families:

| Family | Contract |
| --- | --- |
| `checked_add/sub/mul/neg/pow` | `Option<T>`; None means the mathematical result cannot fit |
| `wrapping_add/sub/mul/neg/pow` | Retain the low 64 result bits |
| `saturating_add/sub/mul/pow` | Clamp the mathematical result to the type's range |
| `checked_div/rem` | None for zero divisor; signed MIN/-1 also returns None |
| `div/rem` | Truncate the quotient toward zero; nonzero remainder has the dividend's sign; invalid operands trap |
| `wrapping_div/rem` | Signed MIN/-1 returns MIN for division and zero for remainder; zero divisor traps |
| `saturating_div` | Signed MIN/-1 returns MAX; zero divisor traps |
| `checked_div_euclid/rem_euclid` | Checked Euclidean quotient and nonnegative remainder, including MIN divisors |
| `div_euclid/rem_euclid` | Same Euclidean relation; invalid operands trap |

Exponent zero returns one, including `0^0`. The unsigned `checked_neg` succeeds
only for zero. Signed modules also expose `saturating_neg`, `signum`, and sign
queries. `is_multiple_of` returns false for a zero divisor and handles signed
MIN/-1 without executing an overflowing native division.

The signed `abs` always traps for MIN. `checked_abs` returns None there,
`wrapping_abs` returns MIN, and `saturating_abs` returns MAX. `unsigned_abs` and
`abs_diff` return the corresponding unsigned type, so the whole signed range
fits. The existing `saturating_abs_diff` retains a signed saturated result.

`clamp` always traps for reversed bounds. `checked_clamp` returns None, and
`clamp_or` returns the explicit fallback. Valid bounds clamp inclusively. This
makes both former `core::i64` ambiguities explicit: `abs(MIN)` cannot silently
produce a negative absolute value, and reversed clamp bounds cannot silently
select an endpoint. Other integer modules retain their existing contracts;
consolidating those APIs is separate work.

These arithmetic choices follow the documented checked, wrapping and saturating
families of the Rust [signed](https://doc.rust-lang.org/std/primitive.i64.html)
and [unsigned](https://doc.rust-lang.org/std/primitive.u64.html) integers.
Lanius `abs` uses one explicit trapping rule regardless of build profile.

## Shifts and bits

`checked_shl/shr` reject counts of 64 or more. They check the count, not whether
nonzero bits are discarded. `shl/shr` trap for those counts;
`wrapping_shl/shr` reduce the count modulo 64. Signed right shifts extend the
sign; unsigned right shifts insert zeroes.

`rotate_left/right` reduce counts modulo 64. `reverse_bits` and `swap_bytes`
operate on the complete representation. `count_ones/zeros`,
`leading_ones/zeros` and `trailing_ones/zeros` return `u32`; zero has 64 leading
and trailing zeroes. `is_power_of_two` requires a positive value.
`checked_next_power_of_two` returns None on overflow and one for inputs of one
or less. `next_power_of_two` traps on overflow.

## Conversions

Every module provides `checked_from_T`, `saturating_from_T` and
`wrapping_from_T`, plus the matching `*_to_T`, for each of `i8`, `u8`, `i16`,
`u16`, `i32`, `u32`, `i64`, `u64`, `isize` and `usize`.

- Checked conversion tests the numeric range and returns `Option`.
- Saturating conversion clamps to the destination range.
- Wrapping conversion retains the destination's low bits, interpreting its
  sign bit for signed destinations.

Infallible `from_T` constructors also exist for narrower source types whose
entire range fits the destination. For example, all four modules have
`from_u32`; only signed destinations have an infallible `from_i32`.
No float conversion, parser or byte serialization contract is implied.

## Executable evidence

Run the focused integration target from the repository root:

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" \
  cargo test --test stdlib_native_integers_execution -- --test-threads=1
```

The three tests import the production modules, compile native Lanius programs
and execute them. They cover constants, old `i64` entry points, exact widening,
arithmetic extrema, signed division rules, powers, bit boundaries and explicit
preconditions. A streaming driver compares **84,100 cases with Rust primitives
and i128 conversion range calculations**, then **84,100 with an independent
Python arbitrary-precision oracle**. Both combine boundary pairs with seeded
full-width values; shift and exponent counts include 0, 31, 32, 63, 64, 65,
127, 128, 129 and `u32::MAX`. The reference inputs preserve every 64 bit pattern
through a binary byte stream. Python implements only the test oracle.

All 54 strict failure cases terminate with the native assertion trap, SIGILL,
including reversed bounds, signed absolute overflow, zero division, signed
division overflow, excessive shift counts and power-of-two overflow.

The previously retained `repro_i64_compare.lani` and
`generic-completion-audit/wide-scalar-composition.lani` both compile and exit
zero with the current compiler. Their old failure reports do not justify
blocking these modules. No compiler, runtime, ABI, extractor or proof source
changes are part of this implementation. User-program GPU execution is not
established by running the compiler on a GPU.
