# Caller-backed formatting

`core::fmt` composes UTF-8 text, booleans, Unicode scalars, integers and
user-defined values into a caller's buffer. It can also measure the same output
without storing bytes. It makes no allocations and performs no I/O.

Execution is verified on **x86_64 Linux using the GPU compiler**. The algorithms
use portable Lanius operations; other targets, including GPU execution of user
programs, have not been established by these tests.

## Formatter and errors

`buffer(bytes, offset, capacity)` returns `Result<Formatter, Error>`. Negative
offset/capacity and overflowing `offset + capacity` return Bounds. The caller
must physically back the claimed range. Indexed writes respect the byte slice's
stride, including native arrays and packed storage.

`measure()` returns a Formatter with no destination storage. Both constructors
start with length zero. Keep buffer storage alive and use `borrow()` when passing
a formatter to other functions. A copied Formatter copies its cursor and error
state while borrowing the same backing bytes; it does not acquire storage.
Do not change its internal fields directly.

| Method | Behavior |
| --- | --- |
| `write_text(Text)` | Append valid UTF-8 unchanged, including NUL |
| `write_quoted(Text)` | Append a complete JSON string, including quotes |
| `write_scalar(u32)` | Append one valid Unicode scalar encoded as UTF-8 |
| `write_bool(bool)` | Append lowercase `true` or `false` |
| `write_signed(i64, Integer)` | Append sign and magnitude using selected radix/padding |
| `write_unsigned(u64, Integer)` | Append magnitude using selected radix/padding |
| `len()` | Bytes successfully appended/measured before the first error |
| `finish()` | Return the current total length or the first error |

Every append returns `Result<i32, Error>` with the **total successful length**,
not the size of that individual append. It validates/reserves its complete output
before changing any destination bytes. Failure leaves this append unwritten;
earlier successful appends remain. The first error is latched, and every later
append and finish returns it without writing. Inspect each result or check finish
after a sequence; ignoring both discards error information.

The errors are Bounds, BufferTooSmall(required_total), SizeOverflow, InvalidRadix,
InvalidWidth and InvalidScalar. BufferTooSmall identifies the total required at
the first failed append; it does not predict later appends. SizeOverflow means
the length cannot fit i32. A measured result can therefore be at most i32::MAX.
Invalid arguments to a buffer constructor do not construct a failed formatter.

Text sources must remain valid and unchanged during formatting, and their bytes
must not overlap the destination. The language does not enforce those borrow
or immutability rules. A formatter does not append a terminating NUL or LF unless
the caller requests it. There is no implicit truncation.

## Integer and quoted-text rules

`Integer { radix, uppercase, min_digits }` accepts bases 2 through 36. Digits
above 9 are ASCII a–z or A–Z. `min_digits` is nonnegative and counts magnitude
digits only; zero still emits one digit. Padding consists of leading zeroes after
an optional minus sign. No plus sign, base prefix, grouping or locale behavior is
implicit. `decimal()` selects radix 10, lowercase and a minimum of one digit.

Signed integers use sign and magnitude in every base, including i64::MIN. They
do not format negative values as two's-complement unsigned bit patterns. All
primitive integer widths fit the signed/unsigned entry points. Huge padding is
measurable in constant time; actual output necessarily takes time proportional
to its length. A tiny destination rejects it before writing or padding loops.

Quoted strings follow [RFC 8259 section 7](https://www.rfc-editor.org/rfc/rfc8259.html#section-7):
quote and backslash receive a backslash escape, U+0000–U+001F use lowercase
`\u00xx`, and other valid UTF-8 remains unchanged. There is no normalization,
HTML escaping or optional slash escaping. Unicode scalar writes reject surrogate
code points and values above U+10FFFF.

## Custom formatting

`Display<T>` defines `format(value: T, output: &Formatter) -> Result<i32, Error>`.
Implementations append their representation and return the formatter's finish
result. `display(value, output)` dispatches through that trait. Implementations
are supplied for all ten integer widths, bool, char and borrowed Text.

```lanius
pub impl core::fmt::Display<Point> for Point {
    pub fn format(value: Point, output: &core::fmt::Formatter)
        -> core::result::Result<i32, core::fmt::Error> {
        output.write_scalar(40);
        core::fmt::display(value.x, output);
        output.write_scalar(44);
        core::fmt::display(value.y, output);
        output.write_scalar(41);
        return output.finish();
    }
}
```

This implementation is exercised as `(-42,7)` in the executable contract fixture.
Display implementations control their own side effects. Measuring a custom value
and formatting it again only promises the same size if that implementation and
its inputs are deterministic and unchanged. The trait does not make an arbitrary
sequence of appends transactional. Logging controls its renderer and performs a
complete preflight before modifying the record buffer.

The checksum application uses this module for eight-digit lowercase hexadecimal
and decimal output. It combines formatting with configuration, CLI parsing,
CRC-32, files, borrowed streams and structured logging.

## Evidence and remaining work

`tests/format_log_execution.rs` compiles and executes real imports. Formatting
coverage includes:

- All primitive Display implementations and a custom record; packed/native
  destinations, offsets, guards, exact capacity, sticky errors and zero allocation
  attempts even when allocation is denied.
- 746 signed/unsigned reference cases: bases 2–36, integer limits, digit
  boundaries, mixed case and padding, plus invalid radix/width/capacity cases.
  Generated cases use seed `0xf04a202612345678`.
- 67 quoted-string round trips, including all ASCII/control bytes, non-BMP
  scalars and generated Unicode (seed `0xcafe2026`); invalid UTF-8 inputs are
  rejected by the checked Text construction boundary.
- Invalid scalars, representable measured lengths up to i32::MAX and overflow.

On 2026-10-23 all seven formatting/logging groups passed in 13.93 seconds.
The four existing checksum application groups in the CLI and configuration
targets also passed. To run the focused suite from the repository root:

```sh
timeout --kill-after=2s 100s env CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 cargo test --locked --test format_log_execution -- --nocapture
```

Floating-point formatting, format-string syntax, alignment/precision policies,
owned String conveniences and general user-type streaming adapters remain future
work. No declarations or silent implementations of these operations are included.
The generic combined logging facade has a separate [compiler reproduction](library-dependencies.md).
