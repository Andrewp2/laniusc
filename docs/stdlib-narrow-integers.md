# Native 8, 16 and 32 bit integers

`core::{i8,u8,i16,u16,i32,u32}` are the canonical native integer modules for these widths. Their production implementations use Lanius primitive integers. Signed arithmetic widens to `i64`; unsigned arithmetic widens to `u64`. Every product of two 32 bit operands fits its widened type. Checks happen before narrowing, so overflow cannot be confused with a valid zero result.

Execution evidence targets x86_64 Linux. Conversions involving `isize` and `usize` use the verified 64 bit pointer widths on that target. This guide does not establish behavior for other machine targets or GPU execution.

## Arithmetic and errors

| Family | Contract |
| --- | --- |
| `checked_add/sub/mul/neg/pow` | `Some(result)` when representable, otherwise `None` |
| `wrapping_add/sub/mul/neg/pow` | Keep the low bits at the module's width |
| `saturating_add/sub/mul/pow` | Clamp to `MIN` or `MAX` on overflow |
| `checked_div/rem/div_euclid/rem_euclid` | `None` for zero divisors and signed `MIN / -1` or `MIN % -1` |
| `div/rem/div_euclid/rem_euclid` | Trap for the same invalid inputs |
| `wrapping_div/rem` | Trap on zero; signed `MIN,-1` returns `MIN` or zero |
| `saturating_div` | Trap on zero; signed `MIN,-1` returns `MAX` |
| `abs` | Signed only; trap on `MIN` |
| `checked_abs`, `wrapping_abs`, `saturating_abs` | Signed `MIN` gives `None`, `MIN`, or `MAX` respectively |
| `unsigned_abs`, `abs_diff` | Return the full magnitude in the corresponding unsigned type |
| `saturating_abs_diff` | Signed magnitude clamped at signed `MAX` |

Exponent zero returns one, including `0^0`. Euclidean remainders are nonnegative, including when the divisor is signed `MIN`. `is_multiple_of` returns false for zero divisors. Signed `MIN` is a multiple of `-1` even though their strict quotient is unrepresentable.

## Bounds, bits and alignment

`clamp(value,low,high)` traps when `low > high`. `checked_clamp` returns `None`; `clamp_or` returns the caller's explicit fallback. Inclusive and exclusive range predicates return false for reversed ranges.

`checked_shl/shr` check the count, rather than whether significant bits are discarded. Counts at least `BITS` return `None`. Plain `shl/shr` trap for those counts. Wrapping shifts reduce the count modulo `BITS`. Signed right shifts extend the sign. Rotations, bit reversal, byte swapping and counts operate on exactly the module's width; zero has `BITS` leading and trailing zeros.

`checked_next_power_of_two` returns one for values at most one, including negative signed inputs. It returns `None` if the positive result exceeds `MAX`; `next_power_of_two` traps in that case.

Unsigned `is_aligned`, `checked_align_up/down` and strict `align_up/down` accept every nonzero alignment, including values that are not powers of two. Checked alignment returns `None` for zero alignment or rounded overflow. Strict alignment traps for invalid inputs. `Some(0)` remains a valid rounded result.

`gcd` returns a nonnegative magnitude, using the corresponding unsigned result for signed modules. `gcd(0,0)` is zero, and a signed `MIN` magnitude remains representable. `checked_lcm` returns zero if either argument is zero, otherwise the nonnegative least common multiple when it fits the module type. Overflow returns `None`.

## Conversions

Every module provides checked, saturating and wrapping `from_*` and `to_*` functions for all ten native integer types: `i8/u8/i16/u16/i32/u32/i64/u64/isize/usize`.

- Checked conversions use numeric range and return `Option`.
- Saturating conversions clamp to the destination's numeric bounds.
- Wrapping conversions retain the low destination bits, interpreting signed results with two's complement.
- Plain `from_*` exists only when every source value fits the destination.

`core::u8` also owns nibble and ASCII helpers. Bytes above 127 are preserved by case conversion. Hex/nibble functions with `_or` use the explicit fallback for invalid input. The whitespace helper preserves the existing byte contract: space and byte codes 9 through 13, including vertical tab.

## Runtime verification

`tests/stdlib_narrow_integers_execution.rs` compiles production Lanius fixtures and executes the resulting native programs. It checks all 65,536 byte pairs for signed and unsigned checked addition, subtraction and multiplication, plus extreme and seeded cases for every width. Independent Rust primitives and `i128` conversion/range arithmetic provide one oracle; Python arbitrary precision arithmetic provides another. The focused target passes 787,067 Rust primitive/`i128` comparisons, 393,851 Python comparisons, and all 90 isolated traps. Inputs retain all 64 bits through the binary transport. Failures report the seed, case index, type, operation and operands.

The contract fixture checks strict successful operations, range predicates, infallible conversions, alignment including valid zero, all byte values for ASCII/nibble behavior, and all byte pairs for case-insensitive equality. A separate fixture isolates 90 invalid strict calls and checks their trap signal. The previous canonical module fixtures remain executable with their failure assertions migrated to explicit checked/fallback APIs.

The six changed `core_*_complete.lani` consumers also passed direct compilation
and native execution against these final modules. Each exited zero with empty
stdout/stderr. This verifies the existing callers without rerunning the unrelated
cases in the historical foundation loop. Independent source review found no
arithmetic, conversion, shift, GCD/LCM or alignment defect.

## Remaining internal migration

The older `core::number_i8`, `number_i16`, `number_i32`, `number_u16`, `number_u32`, `byte` and `narrow` modules still have real consumers and remain separate pending migration. The canonical modules do not delegate to them, and no compatibility aliases were added.

Current consumers include signed byte/halfword vector samples; `core::array_i32_4` and integer samples; `core::hash` and represented `core::wide_u64`; and `core::text`, `core::hex`, `core::hex_wide_u64`, `alloc::string` and byte samples. `core::narrow` has explicit conversion samples and execution coverage. Migrate those callers to the canonical checked, wrapping, saturating or fallback contracts before removing the redundant implementations. Represented wide integer modules are outside this change.
