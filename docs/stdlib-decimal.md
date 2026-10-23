# Decimal integers

`core::decimal` provides allocation-free integer formatting and parsing.
The supported types are `u8`, `u16`, `u32`, `u64`, `usize`, `i8`, `i16`, `i32`,
`i64` and `isize`. For each type, `parse_TYPE(bytes, count)` returns
`Result<TYPE, ParseError>`. Each also has a `parse_TYPE_range(bytes, offset,
count)` form that avoids copying or shifting a substring. Error offsets are
relative to the selected range. Borrowed `core::text::Text` exposes matching
`parse_TYPE()` methods. The current compiler defines `usize` and `isize` as
64-bit integers; this implementation makes no claim about a future 32-bit target.

## Input contract

- Parse exactly `count` bytes from the selected offset. There must be at least one digit.
- Signed types accept one optional ASCII plus or minus. Unsigned types accept
  digits only, including rejecting a plus or `-0`.
- Leading zeroes are valid. Signed `-0` produces zero.
- Whitespace, decimal points, exponents, separators, NUL and non-ASCII digits
  are invalid. The function does not trim input.
- Arithmetic is checked before multiplication/addition. Overflow never wraps;
  signed minima are handled without negating an unrepresentable value.
- The slice must physically back the selected range. Negative offsets/counts or an overflowing offset + count are errors.
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

All ten parsers share one magnitude scanner. It computes the selected type's
quotient and remainder limit once, then checks each digit before arithmetic.
Parsing takes O(input bytes), uses constant storage, and handles full-width
unsigned values and signed minima without wraparound.

## Formatting

All ten types provide:

| API | Result |
| --- | --- |
| `len_TYPE(value)` | Exact number of ASCII bytes, including a minus sign |
| `byte_at_or_TYPE(value, index, fallback)` | Indexed ASCII byte, or fallback for any index past the end |
| `format_TYPE(destination, offset, capacity, value)` | `Result<i32, FormatError>` containing the number of bytes written |

Output is canonical base-ten text: zero is `0`, negatives start with `-`, and
there is no leading plus, leading zero padding, whitespace or NUL terminator.
Index zero is the first byte. The full signed/unsigned 64-bit domains need at
most 20 bytes. Use the buffer formatter to emit a whole number in O(digits)
time; repeatedly calling indexed byte access does O(digits²) work.

`FormatError::Bounds` rejects negative offsets/capacities and overflow in
`offset + capacity`. `FormatError::BufferTooSmall(required)` reports the exact
required size. Both errors leave every destination element unchanged. The
formatter writes only `[offset, offset + written)`, preserving the remaining
capacity and bytes outside the supplied range. It accepts packed and strided
byte slices and allocates nothing.

The caller must physically back the advertised destination range. The compiler
cannot yet expose slice lengths, so physical overclaims may trap on indexing;
they are not recoverable `FormatError`s. These preconditions also apply to the
initial counts used by [borrowed slice views](stdlib-slice-views.md).

The existing
`parse_ascii_TYPE_or` functions accept `[i32]` character-code views and return
a caller-selected fallback; new packed-text callers should use the explicit
Result APIs above.

## Owned text and host output

`alloc::string::from_i64` and `from_u64` create independent owned decimal
Strings. `String.try_append_i64` and `try_append_u64` append a complete number
and return the new byte length. Smaller integer types can widen explicitly to
these signed/unsigned entry points. Allocation or capacity failure preserves
the original owner, bytes and borrowed views. Formatting uses a fixed stack
buffer; the String is the only allocation-backed storage.

`std::io_decimal::write_TYPE(handle, value)` supports all ten native types. It
returns the full byte count, the first negative host error, or -1 for a short
single-byte write. Errors may leave a decimal prefix. These low-level writers
report `Interrupted` as an error; they do not retry it. The two-word integer
types retain their own distinct APIs; native values need no conversion to them.

The [window report](stdlib-slice-views.md#executable-example) now writes native
i64 sums directly. It retains its exact results for 4,096 full-range i32
samples, as well as its input, allocation and partial-output failure behavior.

### Native application timing

On the Ryzen 9 5950X, the window report was compared with library revision
`87f05936`, rebuilt with the same compiler. Each row uses one warm-up pair and
four measured pairs, alternating order; values are median elapsed milliseconds.
Every run's complete output was checked against independently computed results.

| Samples | Window width | Previous two-word sum output | Native integer output |
| --- | --- | --- | --- |
| 4,096 | 1 | 1,817.45 ms | 106.80 ms |
| 4,096 | 64 | 2,539.05 ms | 131.33 ms |
| 4,096 | 4,096 | 12.64 ms | 12.37 ms |

Input samples are the same reproducible full-range i32 sequence as the report
test: seed `0x71ad2026`, unsigned wrapping recurrence
`state = state * 1664525 + 1013904223`, interpreted as signed i32. The report's
algorithm is unchanged; this comparison includes the parser and writer changes.
These are native CPU program timings, not compiler-throughput or GPU timings.
The one-window case has little formatting work and shows little change.

## Evidence and remaining work

Verified on 2026-10-22 using the GPU compiler and native x86_64 Linux execution:

- Both groups in `tests/stdlib_decimal_execution.rs` pass. Existing formatting
  and cell-input behavior remains covered. The packed-input fixture tests all
  ten types against independently generated values, leading zeroes, signs,
  exact range boundaries, malformed bytes and error kind/offset, including
  overflow preceding a later malformed byte.
- All four groups in `tests/stdlib_integer_text_execution.rs` pass. Buffer
  formatters and indexed access are compared with Rust's native values across
  decimal and binary width boundaries and deterministic random bit patterns.
  Guard bytes verify exact writes and preservation on insufficient capacity or
  invalid bounds. Other fixtures cover packed storage, Text parsing, physical
  traps, String allocation-failure cleanup and host errors after partial writes.
- Both groups in `tests/library_window_report_execution.rs` pass after migration
  to native integer output, including generated statistics and fault injection.

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test stdlib_decimal_execution -- --nocapture
```

`core::decimal` has no allocation or host dependencies. Owned String operations
require the allocator, and native writers require host I/O. GPU user-program
execution is not established by these tests. Floating-point conversion,
format specifications and count-free slice construction remain separate work.
