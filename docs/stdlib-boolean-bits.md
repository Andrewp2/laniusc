# Boolean values and fixed-width bit operations

[`core::bool`](../stdlib/core/bool.lani) has 10 Boolean/conversion/selection
functions. [`core::bits`](../stdlib/core/bits.lani) has 42 scalar bit functions
for `u8`, `u16`, `u32` and `i32`. Both are allocation-free Lanius modules with
no host calls, pointers, views or caller-backed buffers. Inputs are passed by
value and are not mutated.

These functions are defined for every value in their declared input types.
They return ordinary values, with caller fallbacks for invalid extraction
indices; there is no `Result`, allocation failure or partial progress. Argument
expressions still execute normally and can have their own effects or failures.
The [integer guides](stdlib-narrow-integers.md) describe the distinct arithmetic
and shift APIs in each numeric module; native 64-bit operations are covered
[separately](stdlib-native-integers.md).

## Boolean operations and conversions

| Function | Result |
| --- | --- |
| `not(value)` | Invert the Boolean |
| `and(left, right)` | True exactly when both are true |
| `or(left, right)` | True when at least one is true |
| `xor(left, right)` | True exactly when the inputs differ |
| `eq(left, right)` | True exactly when the inputs agree |
| `ne(left, right)` | Same truth function as `xor` |
| `to_i32(value)` | 1 for true, 0 for false |
| `from_i32(value)` | False only for 0; every nonzero i32, including negative values, gives true |
| `select_i32(condition, when_true, when_false)` | The first i32 when true, the second when false |
| `choose_i32(condition, when_true, when_false)` | Same selection contract as `select_i32` |

The binary truth functions are:

| Left | Right | `and` | `or` | `xor` / `ne` | `eq` |
| --- | --- | --- | --- | --- | --- |
| false | false | false | false | false | true |
| false | true | false | true | true | false |
| true | false | false | true | true | false |
| true | true | true | true | false | true |

These are ordinary eager function calls. `and(false, expression)` still
evaluates its argument expression, as does `or(true, expression)`. Both i32
arguments of either selector are evaluated before selection. These helpers do
not provide the conditional evaluation of source `&&`, `||` or `if`. Selectors
accept the entire i32 domain and perform no numeric conversion or clamping.

## Widths, counts and indices

The suffix selects the entire representation being inspected:

| Suffix | Value domain | Bit width `W` | Valid bit indices |
| --- | --- | ---: | --- |
| `_u8` | 0..255 | 8 | 0..7 |
| `_u16` | 0..65535 | 16 | 0..15 |
| `_u32` | 0..4294967295 | 32 | 0..31 |
| `_i32` | -2147483648..2147483647, inspected as 32 two's-complement bits | 32 | 0..31 |

Bit index 0 is the least significant bit; `W - 1` is the most significant bit.
All rotation amounts and extraction indices are `u32`, including its maximum.
There is no negative-index input domain. An explicit signed-to-unsigned cast
produces an unsigned argument and follows these same rules.

All four suffix families expose the following nine operations. The names in
each row are separate public functions, not overloads:

| Public functions | Contract and result type |
| --- | --- |
| `count_ones_u8`, `count_ones_u16`, `count_ones_u32`, `count_ones_i32` | Number of set bits, as `u32` in 0..=W |
| `count_zeros_u8`, `count_zeros_u16`, `count_zeros_u32`, `count_zeros_i32` | `W - count_ones`, as `u32` |
| `leading_zeros_u8`, `leading_zeros_u16`, `leading_zeros_u32`, `leading_zeros_i32` | Zero bits before the highest set bit, or W for zero, as `u32` |
| `trailing_zeros_u8`, `trailing_zeros_u16`, `trailing_zeros_u32`, `trailing_zeros_i32` | Zero bits below the lowest set bit, or W for zero, as `u32` |
| `has_single_bit_u8`, `has_single_bit_u16`, `has_single_bit_u32`, `has_single_bit_i32` | True exactly when the representation has one set bit; false for zero |
| `rotate_left_u8`, `rotate_left_u16`, `rotate_left_u32`, `rotate_left_i32` | Rotate W bits left by the supplied amount; return the input value's type |
| `rotate_right_u8`, `rotate_right_u16`, `rotate_right_u32`, `rotate_right_i32` | Rotate W bits right by the supplied amount; return the input value's type |
| `reverse_bits_u8`, `reverse_bits_u16`, `reverse_bits_u32`, `reverse_bits_i32` | Move bit i to `W - 1 - i`; return the input value's type |
| `bit_at_or_u8`, `bit_at_or_u16`, `bit_at_or_u32`, `bit_at_or_i32` | Selected bit as `bool`, or the supplied Boolean fallback when `index >= W` |

Rotations reduce the amount modulo W. Zero or a multiple of W returns the
original value; W+1 acts like 1. The zero case avoids evaluating a shift by W.
For a nonzero reduced amount `s`, left rotation retains the W low bits of
`(bits << s) | (bits >> (W - s))`, and right rotation reverses the directions.
The u8/u16 implementations widen to u32 before shifts and mask back to their
own width. Overflowing bits wrap around; there is no saturating or checked
rotation variant here. Extraction indices are checked, not reduced modulo W.

Zero has zero ones, W zero bits, W leading zeros, W trailing zeros and no single
set bit. An all-ones value has W ones and zero leading/trailing zeros. For
the u8 value `0x81`, the count is 2 ones and 6 zeros; both leading and trailing
zero counts are 0; left/right rotation by 1 gives 3/192; reversal gives `0x81`
again.

### Signed representations

The i32 operations cast to u32, apply the full 32-bit operation and, for
transforms, reinterpret the resulting bits as i32. They do not inspect the
absolute magnitude, reject negative values or use sign-extending right shifts.
Every negative i32 therefore has zero leading zeros.

For `i32::MIN`, the one sign bit gives `count_ones_i32 == 1`,
`trailing_zeros_i32 == 31` and `has_single_bit_i32 == true`. Reversal or left
rotation by 1 gives 1. Right rotation of i32 value 1 by 1 gives `i32::MIN`.
For -1, all 32 bits are set: counts are 32 ones/0 zeros, and reversal or byte
swap remains -1. A transform may change the sign; that is an ordinary valid
bit-pattern result, not an arithmetic overflow error.

## Byte order, packing and extraction

Six more functions complete the 42-function `core::bits` surface:

| Function | Contract |
| --- | --- |
| `swap_bytes_u32(value)` | Reverse the four byte positions; return `u32` |
| `swap_bytes_i32(value)` | Same 32-bit permutation, returning the resulting `i32` pattern |
| `from_be_bytes_u32(first, second, third, fourth)` | Four u8 values packed most-significant first; return `u32` |
| `from_le_bytes_u32(first, second, third, fourth)` | Four u8 values packed least-significant first; return `u32` |
| `byte_at_be_or_u32(value, index, fallback)` | Byte 0 is most significant and byte 3 least significant; return `u8` |
| `byte_at_le_or_u32(value, index, fallback)` | Byte 0 is least significant and byte 3 most significant; return `u8` |

Byte extraction accepts indices 0..3; every larger u32 index returns fallback
unchanged before shifting. For `0x12345678`, BE extraction gives `12 34 56 78`
and LE gives `78 56 34 12` (hex). Packing those first four BE bytes produces
`0x12345678`; packing them in LE produces `0x78563412`, also its byte swap.
These are operations on scalar values, independent of the machine's memory
endianness. No array is read or written, and there is no implicit terminator,
string encoding, alignment or backing-storage requirement.

Every Boolean and u8 fallback can also be a valid extraction result. A returned
false bit or repeated fallback byte does not establish that the index was
valid; check the index separately when that distinction matters.

## Work and existing executable evidence

Boolean helpers, rotation, packing, extraction and byte swapping have bounded
constant scalar work. Counting/leading/trailing helpers have value-dependent
loops bounded by 32 steps, with the narrower domains reducing the possible
iterations. Reversal takes exactly W source loop iterations. No work grows
with the numeric rotation amount or rejected extraction index. These are work
bounds, not measured instruction counts or a constant-time execution claim.

The existing tests below compile production modules and execute x86_64 programs
on their supported native hosts. This guide audits their assertions and does
not claim a fresh compile or test run.

| Existing driver / fixture | Evidence represented |
| --- | --- |
| [`stdlib_foundation_execution.rs`](../tests/stdlib_foundation_execution.rs), [`core_bool.lani`](../tests/fixtures/stdlib_foundation/core_bool.lani) | Calls all 10 functions; both truth values, selected true/false pairs, zero/negative conversion and both selector branches; expected exit 0 and empty output |
| `stdlib_foundation_execution.rs`, [`core_bits.lani`](../tests/fixtures/stdlib_foundation/core_bits.lani) | Calls all 42 functions; zero/high-bit/all-ones boundaries, rotation amounts 0/1/W/W+1, invalid bit/byte indices and distinct-byte packing/swap examples |
| Loops in `core_bits.lani` | All 256 byte values for division/remainder count and bit expectations, reversal involution and inverse rotations for amounts 0..15; every repeated byte packed/extracted at each position; 256 halfwords at step 257 with analogous checks for amounts 0..31; all 32 i32 one-hot patterns for counts, bit positions and reversal |
| [`stdlib_runtime_contract.rs::core_bool_public_helpers_compile_and_run_through_stdlib_root`](../tests/stdlib_runtime_contract.rs) | Qualified/unqualified imports and all 10 Boolean helper calls through the real stdlib root; native result assertion |
| Foundation source-call inventory | Requires a fixture call for each current public function; supplements execution assertions, not a separate runtime proof |

The Boolean fixture does not enumerate every pair for every binary truth
function. The bit fixture's reversal/rotation inverse properties are
metamorphic checks; they do not independently determine every transform result.
Its u16 grid is sampled, and neither 32-bit value domain is exhausted. The
focused fixture does not include a dedicated `u32::MAX` rotation-amount vector;
its modulo behavior is source-audited here. No random/exhaustive full-u32 oracle,
Wasm execution or user-program GPU execution claim follows from this guide.
