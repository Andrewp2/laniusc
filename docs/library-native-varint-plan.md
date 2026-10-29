# Native checked varints

## Scope and source

Consolidate the current u32/status and two-word codecs into one executable
`core::varint` module for u32, u64, i32 and i64. The in-repo users are two frame
examples and focused fixtures; the audit found no separate human dependency on
the old codec modules. Migrate those users and retire varint_i32,
varint_wide_u64 and varint_wide_i64 without compatibility aliases. This does
not retire the unrelated wide arithmetic modules.

The unsigned bytes follow the [official base-128 description](https://protobuf.dev/programming-guides/encoding/#base-128-varints):
seven low payload bits per byte, least-significant groups first, high bit for
continuation. Signed values use the [sintN ZigZag mapping](https://protobuf.dev/programming-guides/encoding/#signed-integers).
This library additionally requires shortest encodings; it is a strict scalar
profile, not a complete Protobuf implementation or a claim that all Protobuf
parsers impose this admission policy. Signed functions implement ZigZag, not
signed LEB128 or Protobuf intN two's-complement negative encoding.

## Public contract

```text
enum Error { Bounds, BufferTooSmall(i32), Truncated, Overflow, NonCanonical }
struct Decoded<T> { value:T, next:i32 }
len_u32/u64/i32/i64(value) -> i32
write_u32/u64/i32/i64(bytes:View<u8>, offset:i32, value)
    -> Result<i32,Error>
read_u32/u64/i32/i64(bytes:View<u8>, offset:i32)
    -> Result<Decoded<integer>,Error>
zigzag_encode_i32(i32) -> u32; zigzag_decode_i32(u32) -> i32
zigzag_encode_i64(i64) -> u64; zigzag_decode_i64(u64) -> i64
```

All offsets and successful next positions are relative to the supplied View,
not its underlying start. Revalidate nonnegative start/length, nonoverflowing
start+length and 0 <= offset <= length before any byte access. Bounds takes
precedence over capacity/truncation. Length functions return 1..5 or 1..10.

Writers compute the entire required encoded length before the first store.
Insufficient remaining capacity returns BufferTooSmall(required encoded byte
count), leaving the entire backing unchanged. Success writes exactly those
bytes and returns offset+count; outside bytes/guards are unchanged. Readers
never mutate input or a caller cursor. Errors expose no partial value or next
position; success stops at the first terminator and permits subsequent bytes.

Read at most five bytes for 32 bits or ten for 64 bits. An unavailable byte
before that limit is Truncated. At the last allowed byte, payload above 15/1
or a continuation bit is Overflow, without looking at another byte. Otherwise
a terminating zero payload after the first byte is NonCanonical. Thus maximum
width with continuation is Overflow even if input ends there; an overlong
zero terminator is NonCanonical only if the width/last-byte checks pass.

ZigZag uses unsigned bit operations and sign masks so i32::MIN/i64::MIN never
require signed negation or overflow. One private unsigned engine may serve all
four types; bounded casts follow successful width admission. No allocation,
host service, recursion, cleanup transfer or source-level implicit fallback.
View backing, initialization, actual native bounds/stride and lifetime remain
caller obligations. Logical checks do not establish physical backing.

## Real consumer and migration

Migrate both frame-sum examples to the checked native API and preserve their
observable sums. Add `varint_number MODE VALUE`, with encode-u64/encode-i64
producing raw wire bytes and decode-u64/decode-i64 accepting 2..20 hexadecimal
digits and printing canonical decimal plus LF. Decode must consume the entire
single value. Numeric inputs use the existing decimal contracts; hex accepts
ASCII upper/lowercase pairs only. Sole --help/-h, no stdin, two captured args,
64 total argument bytes, numeric tokens at most 20 bytes. All admission and
formatting complete in caller scratch and argument owners retire before stdout.
Output/help permits64 actual write attempts total, diagnostics8; SIGPIPE ignore
and borrowed descriptors. Status0 success/help,2 CLI/wire/range,3 argument-host,
4 allocation,5 output/signal,6 internal. Preserve primary failures during cleanup.

## Acceptance

1. Small native admission for all widths, full extrema, generic Result/Decoded
   and nonzero View starts before broad fixtures are prepared.
2. Direct contracts cover all public operations, error precedence, fifth/tenth
   byte cases, no-write rejection, null-backed invalid metadata and strides.
3. Independent wire oracle checks known examples, exhaustive short prefixes,
   every final-byte possibility at maximum width, generated full-width values,
   all truncations, offsets, canonical minimality and untouched backing. Include
   signed extrema and independent encode/decode expectations, not roundtrip only.
4. A focused pure/physical-boundary gate checks native/packed/unaligned byte
   layouts, exact access limits and no host calls inside codecs. Migrate the old
   physical-overclaim trap fixtures rather than losing this evidence.
5. Execute both migrated frame examples and the real CLI with normal, edge,
   malformed, reached allocation and actual I/O failure cases. Record finite
   fault coverage rather than implying universal failure safety.
6. Retire obsolete codecs/fixtures and stale generated reference entries; update
   semantic guides and module inventories. Root README and human policy files
   remain human-maintained. No compiler, ABI, extractor or proof changes.

Root serializes compiler/native/Cargo commands under the existing library lock.
Every command stays below two minutes. Initial target evidence is native Linux
x86_64 CPU output from the GPU compiler, not user-program GPU execution. The
full standard and extended library goal remains open after this increment.
