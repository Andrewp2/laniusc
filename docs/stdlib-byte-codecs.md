# Byte codecs and integer representations

These allocation-free Lanius modules operate on caller storage or scalar
values. They make no host calls and create no owned buffers.

| Module | Representation | Main result convention |
| --- | --- | --- |
| `core::base64` | Strict padded standard Base64 | Byte count, or fallback / `-1` |
| `core::binary` | Shortest unsigned binary ASCII | ASCII byte or parsed value, with fallback |
| `core::hex` | Shortest unsigned hexadecimal ASCII | ASCII byte or parsed value, with fallback |
| `core::endian` | Fixed-width unsigned, signed and IEEE float encodings, either byte order | Value with fallback; boolean write success |
| `core::crc32` | Reflected CRC-32/ISO-HDLC | Unfinished state or finished checksum |
| `core::varint` | Shortest u32/u64 base-128 and i32/i64 ZigZag encodings | Result with typed Decoded/View-relative next, or explicit Error |

The scalar binary/hexadecimal helpers produce digits for one integer. Their
shortest representations have no leading zero padding or emitted radix
prefix. For example, hexadecimal byte value 10 has the one-digit spelling
`a`; these helpers do not provide a fixed two-character-per-byte buffer codec.

## Storage, errors and work

Array parameters are borrowed. Keep their storage live, correctly typed and
large enough for every accessed element. A supplied logical length or capacity
does not enlarge the physical array or prove its layout. Overclaimed backing
can trap during indexing; a trap has no rollback guarantee. Use the established
[array/view contracts](stdlib-foundation.md) when constructing raw views.

With valid physical backing, rejected logical bounds or insufficient declared
output capacity leave the destination unchanged in Base64, endian and varint
writes. Base64 decoding also validates the entire encoded input before writing.
Successful writes change only their documented output range. Pure read and
validation functions do not mutate input. Base64 explicitly supports using the
same array at the same base for input and output, as described below.

Fallback-returning APIs have no independent success bit. A valid result may
equal the fallback. Base64 length callers can use `-1`, since successful lengths
are nonnegative. For full-range numeric reads/parses, comparing the returned
value with a numeric sentinel cannot reliably identify failure. Validate the
logical bounds first, or use the digit predicates where applicable. Checked
varints instead return Result with explicit errors, without numeric sentinels.

There is no work-budget parameter. Base64 and CRC work is linear in the supplied
input length; binary/hex parsing is linear up to the first rejected code or
overflow. Callers must impose their own input-size limits. Endian operations
access at most eight bytes; varints access at most five/ten for 32/64 bits. Scalar digit
formatting is bounded by the integer width, with constant auxiliary storage.

## Strict Base64

[Source](../stdlib/core/base64.lani): `core::base64` uses the standard alphabet
`A-Z a-z 0-9 + /`, with `=` padding. Its format follows
[RFC 4648 sections 3–4](https://www.rfc-editor.org/rfc/rfc4648.html#section-3).
The decoder rejects whitespace, URL-safe alphabet substitutions, misplaced
padding and nonzero unused pad bits. It accepts empty input. A partial final
group requires padding; every encoded input length must be divisible by four.

| Function | Contract |
| --- | --- |
| `encoded_len_or(input_len,fallback)` | Exact `4*ceil(input_len/3)`, without accessing storage; fallback for negative lengths or lengths above 1,610,612,733 |
| `decoded_len_or(input,input_len,fallback)` | Validate all selected encoded bytes and return the exact decoded count; fallback on malformed data or invalid logical length |
| `encode_into(input,input_len,output,capacity)` | Encode the input prefix into the output prefix; return bytes written, or `-1` for invalid input length / insufficient capacity |
| `decode_into(input,input_len,output,capacity)` | Validate, then decode into the output prefix; return bytes written, or `-1` for malformed data, invalid length / insufficient capacity |

The maximum accepted encoding input length produces 2,147,483,644 bytes, the
largest possible multiple-of-four result within i32. No such storage is
allocated by the length helper. Negative output capacity fails even for empty
input; empty input and zero capacity succeed with count zero.

For a final `xx==` group, the second sextet's low four bits must be zero.
For `xxx=`, the third sextet's low two bits must be zero. Thus `Zg==` decodes
to `f`, while `Zh==` fails despite sharing its significant bits. `Zg` fails
because padding is absent. No terminator or newline is appended on encoding.

Encoding works backward and reads each source group before storing its four
output bytes. Decoding works forward after validation. Both support exactly
the same input/output array and base, with enough physical space for the
declared output. This contract does not establish arbitrary overlap between
different base addresses. Bytes after the returned output count are unchanged.

## Binary and hexadecimal scalar ASCII

Sources: [binary](../stdlib/core/binary.lani) and
[hex](../stdlib/core/hex.lani). All three widths, `u8`, `u16` and `u32`, have
the following function families:

| Operation | Binary names | Hexadecimal names |
| --- | --- | --- |
| Shortest digit count | `len_u8`, `len_u16`, `len_u32` | Same names |
| Digit at an index | `byte_at_or_u8/u16/u32` | `byte_at_lower_or_u8/u16/u32`, `byte_at_upper_or_u8/u16/u32` |
| Complete parse | `parse_ascii_u8_or`, `parse_ascii_u16_or`, `parse_ascii_u32_or` | Same names |

Here `/` in a name cell denotes separate width-specific functions, not a
literal identifier. Digit counts return u32. Zero has length one and digit
`0`; maximum lengths are 8/16/32 binary digits or 2/4/8 hexadecimal digits.
Index zero selects the most significant digit. An index at or beyond the
shortest length returns the caller's fallback unchanged. Hex output selects
lowercase or uppercase letters explicitly; its parsers accept either case.

Complete parsers consume exactly the first `len` elements of an **`[i32]`
ASCII-code array**, not a `[u8]` or a NUL-terminated string. Binary accepts an
optional `0b`/`0B`; hexadecimal accepts `0x`/`0X`. A prefix must have at least
one following digit. Leading zeros are accepted. Empty/negative lengths,
signs, whitespace, separators, invalid codes and overflow return fallback.
Neither parser truncates a large value into the requested narrower type.

Both modules also expose these u32 accumulation helpers:

- `can_append_ascii_digit_u32(current,digit_byte,limit)` tests syntax and whether
  `current*radix+digit <= limit`, without overflowing first.
- `append_ascii_digit_or_u32(current,digit_byte,limit,fallback)` performs that
  append only when the predicate succeeds; otherwise it returns fallback.

The radix is two or sixteen according to the module. `limit` may be below
u32::MAX; appending zero to zero is valid even when the limit is zero. These
helpers accept one digit only. They do not process prefixes. Keep a separate
validity flag when using them to distinguish an accepted full-range value
from an equal-valued fallback.

## Fixed-width endian access

[Source](../stdlib/core/endian.lani). Reads/writes use `[u8]`, a logical `len`
and a zero-based `offset` measured in bytes. They do not advance a cursor.

| Value | Width | Read functions | Write functions |
| --- | ---: | --- | --- |
| `u16` | 2 | `read_u16_be_or`, `read_u16_le_or` | `write_u16_be`, `write_u16_le` |
| `u32` | 4 | `read_u32_be_or`, `read_u32_le_or` | `write_u32_be`, `write_u32_le` |
| Native `u64` | 8 | `read_u64_be_or`, `read_u64_le_or` | `write_u64_be`, `write_u64_le` |
| `i16` / `i32` / `i64` | 2 / 4 / 8 | `read_i16/i32/i64_be_or`, `read_i16/i32/i64_le_or` | `write_i16/i32/i64_be`, `write_i16/i32/i64_le` |
| `f32` / `f64` | 4 / 8 | `read_f32/f64_be_or`, `read_f32/f64_le_or` | `write_f32/f64_be`, `write_f32/f64_le` |
| `core::wide_u64::WideU64` | 8 | `read_wide_u64_be_or`, `read_wide_u64_le_or` | `write_wide_u64_be`, `write_wide_u64_le` |

Big endian puts the most significant byte first; little endian puts the least
significant byte first. The u32 value 305,419,896 uses bytes `12 34 56 78`
in big endian or `78 56 34 12` in little endian (byte literals shown in hex).
The explicit `wide_u64` names preserve both u32 words of `WideU64`; native
u64 has its own concrete functions. Signed encodings preserve same-width
two's-complement bits, and floats reuse existing exact to_bits/from_bits
transport without arithmetic. Slash notation above denotes separate concrete
function names. The [native numeric increment](stdlib-native-endian.md) adds
24 functions for a 36-function module. Two direct native tests pass with all
24 additions, 58 literal base vectors and four physical-overclaim traps.
The independent model passes 16,032 cases; two memory/scale tests pass
672 rejections and a 32,768-record workload. The record-repacking program
passes four groups/96 cases. This finite Linux x86_64 increment is accepted.
The separate static call inventory covers all 36 names and is not runtime
evidence.
Historical receipts cover the original twelve u16/u32/represented-WideU64
functions; current old-family and UTF-16 regressions have separate receipts.

For width `w`, valid logical bounds are `len >= w`, `offset >= 0` and
`offset <= len-w`. This subtraction-based check avoids an overflowing
`offset+w`. Invalid bounds return the read fallback or `false` before any
storage access. A successful write returns `true` after storing all `w`
bytes, leaving bytes outside `[offset,offset+w)` unchanged. Alignment of the
offset is unrestricted; the implementation assembles individual bytes.

## CRC-32 state and finalization

[Source](../stdlib/core/crc32.lani). The checksum is reflected CRC-32/ISO-HDLC:
width 32, reversed polynomial `0xEDB88320`, initial state `0xFFFFFFFF`, and
final XOR `0xFFFFFFFF`. The corresponding forward polynomial is `0x04C11DB7`.
The input bytes retain their order; each byte updates the state through eight
least-significant-bit steps. The CRC convention is also described by
[RFC 1952's sample CRC algorithm](https://www.rfc-editor.org/rfc/rfc1952.html#section-8).

| API | Meaning |
| --- | --- |
| `INITIAL` | Starting unfinished state, 4,294,967,295 |
| `REVERSED_POLYNOMIAL` | 3,988,292,384 |
| `XOR_OUT` | 4,294,967,295 |
| `update_byte(state,value)` | Return a new unfinished state after one u8 |
| `finish(state)` | Return the finalized checksum by applying `XOR_OUT` |
| `checksum_or(values,len,fallback)` | Finalized checksum of the first `len` bytes; negative length returns fallback without reading |

For streaming, retain the unfinished state across chunks and finalize the
state used for reporting. `finish` takes a scalar copy, so the original
unfinished state can continue receiving bytes. Do not feed a finalized
checksum back as an unfinished state. Empty input has checksum zero; ASCII
`123456789` has checksum `0xCBF43926` (3,421,780,262).

The result is a u32, not serialized bytes. A containing protocol chooses its
wire byte order, which can be written with the endian helpers above.

## Checked native varints

[Source](../stdlib/core/varint.lani) and [full contract](stdlib-varint.md).
One module covers u32/u64/i32/i64 through sixteen free functions. Reads/writes
accept View<u8> and relative offsets; Result separates every valid integer from
Bounds, BufferTooSmall(required), Truncated, Overflow and NonCanonical.
Successful reads return typed Decoded { value, next }; writers return the next
relative offset after preflighting complete capacity, with no writes on rejection.
The inclusive offset==length boundary is admitted, producing Truncated for reads
and BufferTooSmall for writes. Fifth/tenth-byte overflow precedes canonicality.

The unsigned representation uses seven low payload bits per byte; signed APIs
use ZigZag, not signed LEB128 or Protobuf intN. Shortest encodings are mandatory.
The retired `varint_i32`, `varint_wide_u64` and `varint_wide_i64` modules have no
forwarding aliases; unrelated two-word arithmetic remains supported separately.
All five native library tests, both migrated frame examples and the 150-case
CLI pass; the dedicated guide records their separate finite receipts.

## Existing executable evidence and its limits

This section records earlier fixture coverage. The varint rows describe the
retired status/two-word source/API freeze, not the current driver contents or
native checked API. Current admission and migrated-consumer receipts belong to
the [native varint guide](stdlib-varint.md). The other codec rows keep their
existing scopes. Their physical-bounds cases expect native trap exit 101;
none establishes user-GPU or other-target execution.

| Existing driver | Behaviors checked in its fixtures |
| --- | --- |
| [stdlib_base64_execution.rs](../tests/stdlib_base64_execution.rs) | Known padded vectors; empty input; size overflow; strict padding/pad-bit/whitespace rejection; unchanged logical-failure outputs; same-base aliasing; all 256 one-byte values and selected two-/three-byte families; source/output backing traps |
| [stdlib_endian_execution.rs](../tests/stdlib_endian_execution.rs) | Both byte orders at offsets; u16/u32 and two-word 64-bit values; rejected bounds and sentinel preservation; 256 varying high-byte patterns across several offsets; source/output backing traps; packet-header consumer |
| [stdlib_crc32_execution.rs](../tests/stdlib_crc32_execution.rs) | Constants, empty/negative lengths, `123456789`, binary bytes, an ascending 0..255 stream, byte-wise versus prefix checksum, and a physical-bounds trap |
| [stdlib_foundation_execution.rs](../tests/stdlib_foundation_execution.rs) | `core_binary` and `core_hex`: digit positions/case, prefixes, malformed input, width maxima/overflow and fallbacks; binary additionally round-trips every u8 |
| Historical `stdlib_varint_execution.rs` | u32 known wire bytes and maximum; 0..255 round trips; offset progress; logical failure/sentinels; truncated, overflow and noncanonical statuses; physical read/write traps; frame-sum consumer |
| Historical `stdlib_varint_signed_execution.rs` (retired driver) | ZigZag endpoints and known wire bytes; -128..127 round trips; shared status/progress and failed writes; signed frame-sum consumer |

Some drivers also include public-name presence checks. Those checks complement
the runtime fixtures; finding a function name in a fixture alone does not
prove its contract. The fixed matrices and known vectors above are finite
evidence, not exhaustive verification of all u32 values, byte strings, overlap
patterns or malformed encodings. Atomic logical failures and general format
rules are stated from the audited implementation; the table identifies the
specific branches exercised by existing tests.
