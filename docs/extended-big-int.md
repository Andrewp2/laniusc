# Signed arbitrary precision integers

`ext::big_int` provides owned signed integers over `ext::big_uint`. All
magnitude storage, arithmetic and digit conversion come from the unsigned
provider. `BigInt` adds a sign and keeps zero nonnegative. It has no fixed
numeric width; `ext::big_uint::Limits` bounds memory, work and text output.

## Ownership and errors

Lanius copies records shallowly. Keep one active owner of each `BigInt`; use
`try_clone(limits)` for a separate allocation and call `destroy()` on each
owned result. Pass operands through `value.borrow()`. A borrowed value must
outlive the call. Every operation preserves its input owners and their values,
including self aliases, on success and on error. Destroying a value resets
that owner to zero; a shallow copy must not be destroyed again.

`DivRem` owns its `quotient` and `remainder` separately. Either call the pair's
`destroy()` method, or transfer both fields to their new owners and destroy
those owners later. Do not destroy the pair after transferring either field.
Every failing division destroys all partial results before returning.

Fallible functions return `core::result::Result<T, ext::big_uint::Error>` and
take `ext::big_uint::Limits`. They propagate the provider's errors:
`Bounds`, `LimbLimit`, `WorkLimit`, `OutputLimit`, `AllocationFailed`,
`InvalidRadix`, `InvalidDigit`, `Empty`, `Underflow`, `DivisionByZero`, and
`Overflow`. Valid signed subtraction never returns `Underflow`. Negative
integers and oversized magnitudes return `Overflow` when converted to `u64`.

## Public API

Module functions:

| Function | Result |
| --- | --- |
| `zero()` | Allocation free `BigInt` |
| `from_i64(value, limits)` | Checked owned `BigInt`, including `i64::MIN` |
| `from_u64(value, limits)` | Checked owned nonnegative `BigInt` |
| `parse(input: View<u8>, radix: i32, limits)` | Checked owned `BigInt` |

Methods:

| Methods | Contract |
| --- | --- |
| `borrow()`, `destroy()` | Borrow the owner; explicitly release it |
| `is_zero()`, `sign()` | Zero predicate; sign is `-1`, `0`, or `1` |
| `bit_length()` | Number of magnitude bits, zero for zero |
| `compare(other)` | `-1`, `0`, or `1` in ordinary integer order |
| `to_i64()`, `to_u64()` | Exact checked conversion |
| `try_clone(limits)`, `abs(limits)`, `neg(limits)` | Separate owned results |
| `add(other, limits)`, `sub(other, limits)`, `mul(other, limits)` | Exact arithmetic |
| `div_rem(other, limits)` | Truncating quotient and remainder |
| `div_rem_euclid(other, limits)` | Euclidean quotient and remainder |
| `pow(exponent: u32, limits)` | Exact power; `0^0` is `1` |
| `gcd(other, limits)` | Nonnegative greatest common divisor; `gcd(0,0)` is zero |
| `shl(bits: u64, limits)`, `shr(bits: u64, limits)` | Exact left shift; arithmetic right shift |
| `bit_and`, `bit_or`, `bit_xor` | Binary infinite two's complement operations, with `other, limits` |
| `bit_not(limits)` | Infinite two's complement complement |
| `format_radix(radix, limits)` | Owned `alloc::vec::Vec<u8>` text |
| `format_into(output: View<u8>, radix, limits)` | Byte count, with atomic errors |

The integer implements lawful `core::cmp::Eq`, `Ord`, `PartialEq`, and
`PartialOrd`. Equality and order methods inspect the values without taking
ownership, despite shallow record arguments. Its partial order never returns
`Unordered`.

## Text grammar

The entire input must match `[+-]?[0-9a-zA-Z]+`. The radix must be in `2..36`
and each digit must be below the radix. ASCII letters ignore case. Whitespace,
underscores, interior signs, and trailing invalid bytes fail. There is no
prefix syntax: `0x10` fails in radix 16, while `x` is an ordinary digit in
radix 36.
The empty input and a lone sign return `Empty`; an invalid digit returns
`InvalidDigit`. Leading zeroes are accepted; `-000` normalizes to zero.

Formatting uses lowercase letters, no prefix, no leading zeroes, and a minus
sign only for negative values. Zero formats as `0`. `max_output` includes the
minus sign. `format_into` first prepares the complete text, checks capacity,
then writes only the selected output prefix. All output bytes stay intact
on any error; insufficient capacity returns `OutputLimit`. The source and
output views use logical array indexing, preserving native strides.

## Division, shifts, and bitwise semantics

Truncating division satisfies `a = q*b + r`, `abs(r) < abs(b)`, and a nonzero
remainder has the dividend's sign. This follows GMP's
[truncating division contract](https://gmplib.org/manual/Integer-Division).
For example, `-7 / 3` gives `q=-2, r=-1`; `7 / -3` gives `q=-2, r=1`.
Division by zero returns `DivisionByZero` and preserves both operands.

Euclidean division satisfies the same identity with `0 <= r < abs(b)` for
either divisor sign. It starts with unsigned quotient and remainder, then
adjusts a negative remainder by `abs(b)`. For example, `-7 / 3` gives
`q=-3, r=2`; `-7 / -3` gives `q=3, r=2`.

`shr(k)` rounds division by `2^k` toward negative infinity, so `-7 >> 1` is
`-4` and an arbitrarily large right shift of a negative value is `-1`.
The implementation uses `-m = ~(m-1)` and unsigned shifts, then restores the
sign. Bitwise operations use the same identity and De Morgan's laws, matching
[GMP's two's complement semantics](https://gmplib.org/manual/Integer-Logic-and-Bit-Fiddling).
There is no fixed sign bit or limb width in these signed operations.

## Resource bounds

`max_limbs` bounds each magnitude under the unsigned provider's documented
scratch rules. `max_work` applies to each invoked unsigned primitive; signed
composition performs at most ten such primitives. Arithmetic, power, gcd,
parsing and formatting otherwise follow the provider's work accounting.
`pow` and `gcd` share a remaining work budget across their internal loops.
Signed formatting also inserts at most one sign byte and shifts the output
text once; this adds linear work in the bounded output length. Comparisons
and scalar conversions do not allocate.

Basic arithmetic uses one magnitude operation. Euclidean adjustment uses at
most one division, one subtraction, one construction of `1`, and one addition.
Negative right shifts and complements use at most two constructions of `1`,
one subtraction, one shift or clone, and one addition. Bitwise operations
use at most two input conversions, two Boolean operations and one output
conversion. Each intermediate has one owner and is destroyed on every error.

## Native verification

`tests/extended_big_int_execution.rs` compiles the Lanius fixtures through the
compiler and executes x86_64 Linux binaries. Python integers serve only as a
test reference. The suite covers signed extrema, values through thousands of
bits, all supported radices, randomized arithmetic chains, self aliases,
truncating and Euclidean division identities, infinite bitwise semantics,
canonical zero, malformed text, conversion overflow, resource errors and
atomic output. A separate fixture carries an owned value through repeated
arithmetic updates.

The allocation suite records every `mmap` in each tested operation, injects
`ENOMEM` at each observed allocation, checks surviving operands, and requires
every successful allocation to have a matching `munmap`. The execution
evidence concerns native x86_64 Linux, not user GPU execution. Reproduce with:

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR=/home/andrew-peterson/code/laniusc/target/stdlib-build CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --test extended_big_int_execution -- --test-threads=1
```
