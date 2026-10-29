# Native numeric byte order

Complete the multibyte native primitive family in `core::endian`, alongside
the existing u16/u32 and represented WideU64 functions. At the start of this
increment, the module had twelve public functions; native u64, signed integers
and IEEE floats were missing. This closes a portable byte-utility gap after the file-family
increments. Unix-domain IPC remains a separate open capability. The whole
standard/extended-library objective remains open.

## Fixed public family

For each `T` in `u64`, `i16`, `i32`, `i64`, `f32`, `f64`, add four functions:

```lani
pub fn read_T_be_or(bytes:[u8],len:i32,offset:i32,fallback:T)->T;
pub fn read_T_le_or(bytes:[u8],len:i32,offset:i32,fallback:T)->T;
pub fn write_T_be(bytes:[u8],len:i32,offset:i32,value:T)->bool;
pub fn write_T_le(bytes:[u8],len:i32,offset:i32,value:T)->bool;
```

These are 24 functions, bringing the module to36. Keep the established raw
array/claimed logical length contract, names and existing twelve operations.
One-byte values have no byte-order distinction; pointer-sized fields do not
define a stable wire width. Neither needs duplicate big/little-endian names.
Do not introduce an unrelated codec trait, allocated byte array or parallel
checked-view facade in this increment.

For field width W, admission is exactly `len >= W && offset >= 0 &&
offset <= len-W`. Rejected reads return the exact fallback value without
backing access; rejected writes return false with no destination mutation.
Valid operations access exactly W elements at the selected offset, preserving
the actual native slice stride. Complete logical admission must precede any
write. Physical backing and lifetime remain caller preconditions; physical
overclaims may trap and do not promise rollback.

Big endian places the most significant byte first; little endian places it
last. Integer conversions preserve the specified-width two's-complement bit
pattern, not saturating or checked numeric conversion. Compose u64 from the
existing u32 operations and signed values from their unsigned widths. Reuse
existing packing engines, without rewriting the working represented-width
API or duplicating per-byte loops throughout the signed/float wrappers.

Float operations serialize IEEE binary32/binary64 bits through the existing
`core::f32` / `core::f64` to_bits/from_bits operations. No floating arithmetic
or numeric integer casts. Preserve every bit through reads/writes: both zero
signs, normal/subnormal values, infinities and quiet/signaling NaN payloads.
Invalid read fallback bits must also survive unchanged. Targets must support
these exact-bit value transfers; actual native acceptance is required before
claiming that property. Rust's [u64 byte conversions](https://doc.rust-lang.org/std/primitive.u64.html#method.from_be_bytes)
and [float bit conversions](https://doc.rust-lang.org/std/primitive.f64.html#method.from_bits)
are semantic references, not production implementations.

Production remains Lanius, allocation-free and independent of host byte
order/services. No new runtime ABI/compiler/proof changes. Missing target
support gets a minimal reproduction and precise dependency, not a narrowed
float contract or a compiler patch hidden in this library increment.

## Real program: repack_records

```sh
repack_records FROM TO
```

FROM and TO are exactly `le` or `be`. Sole --help/-h is supported. Read stdin
as one frame: ASCII magic `LNR1`, a u32 count in FROM order, then exactly that
many 32-byte records. Each record has these fields, all in FROM order:

| Byte offset | Field |
| ---: | --- |
| 0 | u64 identifier |
| 8 | i64 timestamp |
| 16 | i32 channel |
| 20 | f32 sample |
| 24 | f64 reading |

Write the identical magic, count in TO order, and records with each field in
TO order. Same-order conversion is byte identity; reversed byte order changes
only each field's byte ordering. Preserve all float bit patterns, with no
numeric validation/canonicalization or arithmetic. Decode/reencode through the
new public family, not private app byte-reversal loops.

Limit count to65536 records. Fully validate the count, magic, exact declared
length and EOF before any output, using existing owned byte-buffer facilities.
Thus malformed/oversized/truncated/trailing frames publish no stdout. Count0
is valid. Complete input work has an explicit attempt budget (at most8192
stream calls, Interrupted counted), including EOF observation; output is also
bounded to at most8192 calls with confirmed-prefix failure. Child call budgets
do not impose host timeouts. Bound argument capture, error/help output and
manual ownership; release all owners on success and failure. Output errors may
leave a published prefix. The test author and app author fix exact exit codes
and help bytes before root execution. No filesystem mutation or crypto needed.

## Acceptance

- Direct runtime calls to all24 additions, both orders/strides/offsets,
  surrounding sentinels, signed extrema, full-width high bits, IEEE corner
  patterns and exact fallback bits. Invalid logical metadata touches no backing.
- Independent byte/bit model across values and layouts; verify read and write
  directions separately as well as roundtrips so symmetric mistakes cannot pass.
- Distinct invalid logical bounds and physical overclaim traps, including
  admission before partial writes and full64-bit validation before narrowing.
- Real record program with independent byte-per-field oracle, both conversion
  directions and identities, mixed signed/float extremes, count/CLI/EOF/error
  boundaries, allocation failures and cleanup, plus a bounded scale frame.
- Existing endian runtime family and UTF16 or another real consumer regressions
  selected for actual import/behavior risk. Static public-call inventory updated
  to include the new executing producer; it is not runtime evidence by itself.
- Guides/reference distinguish exact tested targets, earlier receipts and
  remaining memory/compiler/target obligations. No silent no-op on a nonempty
  successful operation.

Root alone runs all compiler/native/Cargo commands serially under the existing
lock, with each command below two minutes. Other agents may run static/CPU
oracle checks. Preserve root README, AI_POLICY, CONTRIBUTING, tests/common,
compiler, runtime ABI and formal sources.
