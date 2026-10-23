# Arbitrary precision nonnegative integers

`ext::big_uint` stores normalized little endian `u32` limbs in an owned
`alloc::vec::Vec<u32>`. Zero has no limbs. The highest limb of a nonzero value
is nonzero. There is no fixed numerical width; allocation, explicit limits,
and the vector's addressable capacity bound a calculation.

Each successful constructor or arithmetic operation returns a new independent
owner. Inputs are borrowed and survive every failure. Use `value.borrow()`
for an operand, `value.try_clone(limits)` for a deep copy, and
`value.destroy()` exactly once when finished. Language record assignment is
a shallow handle transfer, not a clone. Do not keep two active owners of one
allocation. A destroyed owner becomes zero and repeated destruction of that
same owner is harmless; stale copies of an owner remain invalid.

```lanius
import ext::big_uint;
let limits: ext::big_uint::Limits = ext::big_uint::default_limits();
let a: ext::big_uint::BigUint = ext::big_uint::from_u64(18446744073709551615,limits).unwrap();
let square: ext::big_uint::BigUint = a.mul(a.borrow(),limits).unwrap();
let pair: ext::big_uint::DivRem = square.div_rem(a.borrow(),limits).unwrap();
assert(pair.quotient.compare(a.borrow()) == 0 && pair.remainder.is_zero());
pair.destroy(); square.destroy(); a.destroy();
```

`DivRem` owns its `quotient` and `remainder`. Destroy both with
`pair.destroy()`, or transfer each field to its next owner and destroy those
owners separately. Do not destroy the aggregate after transferring a field.

## Public operations

| API | Result or behavior |
| --- | --- |
| `zero()` | Allocation free normalized zero |
| `from_u64(value, limits)` | Exact machine value construction |
| `parse(bytes, radix, limits)` | Strict ASCII digits in radix 2 through 36 |
| `is_zero()`, `limb_len()`, `bit_length()` | Allocation free borrowed queries |
| `bit(index: u64)` | False beyond the significant bits |
| `compare(other)` | Negative, zero, or positive numerical order |
| `to_u64()` | Exact conversion, or `Overflow` |
| `try_clone(limits)` | Independent owned copy |
| `add`, `sub`, `mul` | Independent arithmetic results; subtraction rejects underflow |
| `div_rem` | Euclidean unsigned quotient and remainder, `a = q*b+r`, `r < b` |
| `shl(bits: u64, limits)`, `shr(bits: u64, limits)` | Exact logical shifts; arbitrary excessive right shifts return zero |
| `bit_and`, `bit_or`, `bit_xor` | Zero extended unsigned bit operations |
| `pow(exponent: u32, limits)` | Exponentiation by squaring; `0^0 = 1` |
| `gcd(other, limits)` | Euclidean GCD; `gcd(0,0) = 0` |
| `format_radix(radix, limits)` | Owned lowercase ASCII digits, without sign, prefix, separator, or terminator |
| `format_into(output, radix, limits)` | Stages owned formatting then copies into caller storage; returns bytes written |
| `value_hash()` | FNV-1a over the normalized little endian limb bytes |

`parse` accepts uppercase and lowercase letters and leading zeroes. Empty
input, a sign, whitespace, prefixes, separators, trailing bytes, NUL, and
digits outside the radix are errors. Caller slices follow the normal slice
precondition: metadata and backing storage must describe live accessible
elements. Metadata arithmetic is checked before accessing elements.

Formatting zero writes `0`. `format_into` preserves every caller output byte
on all errors, including insufficient capacity, allocation failure, invalid
radix, and resource limits. On success it changes only the returned prefix
of the selected view. The owned formatter's returned byte vector must be
destroyed by its caller.

## Limits and errors

`Limits { max_limbs: i32, max_work: u64, max_output: i32 }` is passed by value
to each public operation. Defaults are 1,048,576 limbs, 100,000,000 work units,
and 1,048,576 output bytes. Negative limb/output bounds and a limb bound above
536,870,911 are `Bounds`. These are resource limits, not a fixed numerical
precision. A caller can choose smaller limits to cap untrusted calculations.

Limb storage is reserved exactly or within its declared bound. Division alone
uses one additional temporary guard limb, so its dividend scratch may have
`max_limbs+1` limbs. Each temporary vector is bounded independently; the limit
is not a total live memory quota. The allocator can deny any request.
The vector's capacity derived from its target element layout is also checked;
a smaller physical capacity is reported as `LimbLimit`.

Work units count or conservatively bound limb iterations. Basic arithmetic
checks its loop bound before allocating. Parsing includes the syntax scan and
each multiply/add pass. Formatting includes its copy and repeated small
division passes. Division uses a conservative bound covering normalization,
quotient estimation, correction, subtraction, addback, and remainder recovery.
`pow` and `gcd` keep a remaining work budget across their arithmetic iterations.
Queries, comparison, normalization scans, and bounded setup/copy overhead are
not a hard CPU instruction meter. Limits are per call; applications that need
a budget across multiple calls must account for that separately.

Errors are `Bounds`, `LimbLimit`, `WorkLimit`, `OutputLimit`,
`AllocationFailed`, `InvalidRadix`, `InvalidDigit`, `Empty`, `Underflow`,
`DivisionByZero`, and `Overflow`. Failed construction destroys its partial
owner. Failed arithmetic destroys its temporary owners and preserves both
operands, including when they refer to the same owner.

## Arithmetic and division bounds

Addition uses a `u64` carry and subtraction a `u64` borrow. Basecase
multiplication performs one product plus one stored limb plus one carry:
`(B-1)^2 + (B-1) + (B-1) = B^2-1`, where `B=2^32`. This fits exactly in `u64`.

Single limb division uses a hardware `u64/u32` division. Multiple limb
division normalizes both values by shifting until the divisor's top bit is
set, then implements Knuth's basecase long division. For each quotient limb,
the preceding remainder is smaller than the divisor. Therefore the next
quotient limb is smaller than `B`. The two by one estimate is at most two too
high; the three by two check reduces it to at most one too high. A borrow from
the full multiply/subtract triggers one decrement and divisor addback.

The `qhat*v[i]+borrow` product is below `B^2`; the refinement comparison forms
`rhat*B+next` only while `rhat < B`. The saturated estimate case avoids dividing
a pair whose quotient would require another limb. The normalized remainder
is shifted back after all quotient positions are processed. Complexity is
`O((N-M+1)*M)` for division of `N` limbs by `M` limbs; multiplication is
`O(N*M)`. Parsing and general radix formatting use basecase methods and can
take quadratic work for long inputs.

The derivation follows the official Go `math/big` long division explanation:
[Guess and Check, Scaling Inputs, and Refining Guesses](https://go.dev/src/math/big/natdiv.go).
This module is an independent implementation using 32 bit limbs and explicit
Lanius allocation ownership, not a copied implementation.

## Equality, ordering, and hashing

`Eq`, `Ord`, `PartialEq`, `PartialOrd`, and `Hash` use numerical values.
Partial comparisons always return an ordered result. Equal normalized values
have the same hash, including zero parsed with any number of leading zeroes.
Trait arguments are temporary read handles; they do not transfer ownership.

A retained key or element must keep its unique owner alive and frozen until
every collection, sort, lookup, and retained handle has finished. A collection
does not deep clone or recursively destroy integer keys. Transfer ownership
explicitly and destroy each owned integer after releasing retained handles.

## Verification

`tests/extended_big_uint_execution.rs` compiles and executes the public API
on native x86_64 Linux. A deterministic independent Python integer oracle
covers all radices, exact values beyond 4,096 bits, carry/borrow boundaries,
Knuth estimate correction/addback patterns, powers, GCD, aliases, malformed
input, and evolving arithmetic sequences. Separate contracts cover checked
conversion, work/limb/output limits, invalid slice metadata, independent clone
destruction, and atomic output. Allocation tests deny each observed `mmap`
attempt and reconcile every successful allocation with its deallocation.
Compiler GPU execution is not evidence of GPU kernel arithmetic behavior.
