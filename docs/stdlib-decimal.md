# Decimal integers

`core::decimal` provides allocation-free integer formatting and parsing.
The packed-byte parsers are `parse_u8`, `parse_u16`, `parse_u32`, `parse_i8`,
`parse_i16` and `parse_i32`. Each takes `(bytes: [u8], count: i32)` and returns
`Result<integer, ParseError>`. Each also has a `parse_TYPE_range(bytes, offset,
count)` form that avoids copying or shifting a substring. Error offsets are
relative to the selected range. Borrowed `core::text::Text` exposes matching
`parse_TYPE()` methods.

## Input contract

- Parse exactly the first `count` bytes. There must be at least one digit.
- Signed types accept one optional ASCII plus or minus. Unsigned types accept
  digits only, including rejecting a plus or `-0`.
- Leading zeroes are valid. Signed `-0` produces zero.
- Whitespace, decimal points, exponents, separators, NUL and non-ASCII digits
  are invalid. The function does not trim input.
- Arithmetic is checked before multiplication/addition. Overflow never wraps;
  signed minima are handled without negating an unrepresentable value.
- The slice must physically back `count` bytes. Negative offsets/counts or an overflowing offset + count are errors.
  An overstated positive count can trap on indexing because the compiler still
  lacks a slice-length projection. No data is written and no storage is allocated.

`ParseError { kind, offset }` uses the following kinds:

| Kind | Offset |
| --- | --- |
| Bounds | -1 for a negative or overflowing integer range |
| Empty | 0 for zero count |
| MissingDigits | End of input after a sign |
| InvalidDigit | First non-digit byte |
| Overflow | First digit that exceeds the selected type's range |

Errors are reported in scan order. For example, an overflowing numeric prefix
followed by a letter reports Overflow before reaching that letter.

Use an owned String directly:

```lanius
let parsed: core::result::Result<i32, core::decimal::ParseError> =
    core::decimal::parse_i32(text.as_bytes(), text.byte_len());
```

Formatting uses `len_TYPE(value)` and `byte_at_or_TYPE(value, index, fallback)`
for the same six types. Index zero is the first ASCII byte; signed negative
values include a minus. The formatter writes no pointers. The existing
`parse_ascii_TYPE_or` functions accept `[i32]` character-code views and return
a caller-selected fallback; new packed-text callers should use the explicit
Result APIs above.

## Evidence and remaining work

Both groups in `tests/stdlib_decimal_execution.rs` passed on 2026-10-22 in
9.21 seconds after adding range parsers using the GPU compiler and native x86_64 Linux execution.

- The existing formatting and cell-input fixture also executes all six packed
  parsers, signed/unsigned 32-bit extremes and negative/zero counts.
- A native stdin fixture parses after a selector byte without shifting storage
  and tests every target width against independently
  generated values, leading zeroes, signs, exact range boundaries, malformed
  bytes and the expected error kind/offset.

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test stdlib_decimal_execution -- --nocapture
```

The implementation has no allocation or host dependencies. GPU user-program
execution is not established by these tests. Native 64-bit parsing/formatting,
floating-point conversion and count-free views remain separate work.
