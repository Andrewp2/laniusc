# Percent encoding of component data

`ext::percent` provides allocation-free byte encoding and decoding into caller
storage. It executes on x86_64 Linux through the GPU compiler's native output.
GPU kernel execution has not been verified.

The codec follows [RFC 3986 sections 2.1–2.4](https://www.rfc-editor.org/rfc/rfc3986#section-2.1).
The encoder preserves ASCII letters, digits, `-`, `.`, `_` and `~`. Every other
byte becomes `%HH` using uppercase hexadecimal. The decoder accepts both hex
cases and leaves a literal `+` unchanged. This is a codec for component data;
choose component boundaries before decoding. It does not validate a URI, apply
form encoding, normalize paths or interpret UTF-8.

For example, encoding `a b+c/d` produces `a%20b%2Bc%2Fd`. Decoding `%2f%00%FF+`
produces the bytes `[47, 0, 255, 43]`. NUL and non-UTF-8 bytes are data. Encoding
an already encoded value treats its percent signs as data; decoding performs
one pass, so `%252F` becomes `%2F`.

## Public API

Import `ext::percent`, `core::slice` and `core::result`. Sizes and positions use
`i32`; each fallible function returns `core::result::Result<i32, Error>`.

| Function | Behavior |
| --- | --- |
| `is_unreserved(byte: u8) -> bool` | Whether this encoder preserves the byte |
| `encoded_capacity(input_length: i32)` | Checked worst-case size, three times the byte count; does not read input storage |
| `encoded_len(input: View<u8>)` | Exact output byte count |
| `decoded_len(input: View<u8>)` | Validates all escapes and returns the exact decoded count |
| `encode_into(input: View<u8>, output: View<u8>)` | Encodes into the output prefix and returns bytes written |
| `decode_into(input: View<u8>, output: View<u8>)` | Decodes into the output prefix and returns bytes written |

Empty inputs succeed with zero bytes written, including into an empty output.
No function appends a NUL terminator. Output after the written prefix remains
unchanged. Sizing and conversion take linear time and constant auxiliary space.
Conversion validates in one pass and writes in another.

## Errors and atomic failure

`Error` has four variants:

- `Bounds`: a negative view start/length, start plus length exceeding `i32::MAX`,
  or a negative length passed to `encoded_capacity`.
- `SizeOverflow`: the encoded count exceeds `i32::MAX`. Worst-case sizing rejects
  lengths above 715827882; exact sizing can still accept a large input containing
  enough unreserved bytes.
- `Capacity(required)`: output is too short; the payload is the exact byte count.
- `InvalidEscape(index)`: the first `%` without two following ASCII hexadecimal
  bytes. The position is relative to the selected input view.

Conversion checks both views' metadata first, then reads and validates the entire
input, then checks capacity, and finally writes. A malformed escape therefore
precedes a capacity error. Every returned error leaves the whole output unchanged.

## Storage and aliasing

Views retain their own storage stride. Packed byte buffers, native byte arrays
and nonzero start offsets use the same API. Callers must supply live backing for
every declared element, writable output and stable input for the call. The
compiler does not enforce these lifetime and mutability requirements; logical
metadata checks cannot validate a pointer or the backing's physical length.

Input and output may be disjoint. In-place operation is also supported when the
two views start at the same physical element and have the same stride: input is
the existing prefix and output supplies the available capacity. Encoding writes
backward; decoding writes forward. Arbitrary partial overlap is outside the
contract. Copies of views alias their backing and carry no ownership.

## Executable evidence

`tests/extended_percent_execution.rs` compiles and executes two Lanius fixtures.
The contract fixture covers native array strides, offset windows, in-place
expansion/shrinking, malformed metadata, relative error positions, capacity
failures, untouched output and arithmetic sizing boundaries. The batch fixture
checks packed storage against an independent Rust test reference: every byte
value, every byte in both escape positions, generated payloads, lowercase
escapes, roundtrips, both alias modes and insufficient capacities. Rust supplies
test inputs and expected outputs only; the production codec is Lanius.

Both programs run with every `mmap` attempt forced to fail and assert that no
allocation or deallocation syscall occurs. The batch fixture checks its output
guards and unchanged storage after each failure. Input sizes near `i32::MAX`
are covered by arithmetic sizing tests; the suite does not create multi-gigabyte
buffers to exercise exact-size overflow.

Run the focused native tests with the repository's absolute build directory:

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR=/home/andrew-peterson/code/laniusc/target/stdlib-build \
  CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test extended_percent_execution
```
