# Decimal conversion attribution

`shaders/float_decimal.slang` and `shaders/float_decimal_tables.slang` adapt the Simple Decimal Conversion implementation from the Rust standard library (`core::num::imp::dec2flt::decimal_seq` and `slow`).

Copyright (c) The Rust Project Contributors. The adapted code is provided under the MIT or Apache License, Version 2.0, at your option. The complete licenses are included in this directory. The surrounding repository uses the same dual license.

Algorithm references:

- Nigel Tao and Ken Thompson's Simple Decimal Conversion, described in [ParseNumberF64 by Simple Decimal Conversion](https://nigeltao.github.io/blog/2020/parse-number-f64-simple.html).
- [Rust decimal sequence implementation](https://github.com/rust-lang/rust/blob/master/library/core/src/num/imp/dec2flt/decimal_seq.rs).
- [Rust exact fallback](https://github.com/rust-lang/rust/blob/master/library/core/src/num/imp/dec2flt/slow.rs).
- [Wuffs implementation](https://github.com/google/wuffs/blob/main/internal/cgen/base/floatconv-submodule-code.c).

The source audit used the local Rust 1.97.1 toolchain source. The review package retains exact source snapshots and SHA-256 hashes; the URLs above identify the upstream projects and may evolve.

## Adaptations

1. Digits occupy a caller-owned storage buffer region, rather than a private array. A constant-size state record keeps count, decimal position, and discarded-nonzero-tail information.
2. Decimal shifts are at most 28 bits, instead of 60. For left shifts, `(digit << shift) + carry < 10 * 2^shift`; for right shifts, `10 * remainder + digit < 10 * 2^shift`. Both fit a u32 at shift 28. Larger shifts are composed from these exact steps. Only the published table entries for shifts through 28 are retained.
3. Significand assembly uses two u32 limbs. No native 64-bit integer or floating-point GPU capability is required.
4. The scanner accepts the existing language's decimal separators only between digits and consumes the complete bounded token. It accepts a mantissa without a decimal point as a helper-level convenience; the parser still owns token kinds. Leading signs are separate unary syntax and supplied to the helper as a Boolean.
5. The scanner preserves signed decimal-position/exponent cancellation before saturation. Its exponent accumulator saturates above every possible u32 source digit count plus 4096; the resulting bounded position retains every case that could round to a finite nonzero binary32/binary64 result.
6. Finite literal overflow returns an explicit status with no value. Underflow rounds to nearest, ties to even, including subnormals and signed zero. No NaN or infinity spelling is accepted by this literal helper.
7. Invalid bounds, scalar IDs, workspace capacity, syntax, and internal invariants have separate statuses. Internal normalization has an explicit 1024-shift guard; token scanning is never truncated by that guard.

The helper is compiler implementation code. It does not add a Rust runtime library, JSON transport, or a Wasm dependency.
