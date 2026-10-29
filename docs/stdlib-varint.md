# Checked native varints

`core::varint` provides sixteen free functions for native u32/u64/i32/i64
values over borrowed byte Views. The [consolidation](library-native-varint-plan.md)
replaces the status/fallback and two-word codecs directly. Native admission
and direct/model/physical gates pass, as do both migrated frames and the
150-case CLI. This finite native increment is accepted; the full library goal
stays open.

## API and byte representation

```text
Error = Bounds | BufferTooSmall(i32) | Truncated | Overflow | NonCanonical
Decoded<T> { value:T, next:i32 }
len_u32/u64/i32/i64(value) -> i32
write_u32/u64/i32/i64(bytes:View<u8>, offset:i32, value)
    -> Result<i32,Error>
read_u32/u64/i32/i64(bytes:View<u8>, offset:i32)
    -> Result<Decoded<integer>,Error>
zigzag_encode_i32(i32) -> u32; zigzag_decode_i32(u32) -> i32
zigzag_encode_i64(i64) -> u64; zigzag_decode_i64(u64) -> i64
```

Slash notation denotes separate concrete names. Length is 1..5 bytes for
32-bit values and 1..10 for 64-bit values, including zero's one-byte encoding.
Unsigned bytes carry seven payload bits per byte, least-significant group
first; bit 7 indicates continuation. The final byte clears that bit.
This follows the [official base-128 description](https://protobuf.dev/programming-guides/encoding/#base-128-varints).

Signed functions apply ZigZag: `0 -> 0`, `-1 -> 1`, `1 -> 2`, and signed MIN
to the same-width unsigned MAX. They implement Protobuf's
[sintN mapping](https://protobuf.dev/programming-guides/encoding/#signed-integers),
not signed LEB128 or the negative intN two's-complement encoding. Unsigned bit
operations/sign masks avoid negating signed MIN.

| Value | Unsigned or ZigZag wire bytes, hex |
| --- | --- |
| u32/u64 zero | `00` |
| u32/u64 300 | `AC 02` |
| i32/i64 -65 | `81 01` |
| u32 MAX / i32 MIN | `FF FF FF FF 0F` |
| u64 MAX / i64 MIN | `FF FF FF FF FF FF FF FF FF 01` |

The reader additionally requires the shortest representation. That is this
library's strict scalar profile; it is not a complete Protobuf implementation
or a claim that every Protobuf parser requires canonical varints.

## View-relative positions and admission

Revalidate nonnegative View start/length, nonoverflowing `start + length`,
then `0 <= offset <= length` before accessing a byte. Bounds takes precedence
over capacity or truncation. Offset equal to length is admitted: reads return
Truncated, and writes return BufferTooSmall for their required encoding.

All offsets and successful next positions are relative to the supplied View.
For a View starting at backing index 3, writing value 300 at offset 2 changes
backing indices 5 and 6 and returns next=4. Reading at offset 2 returns
`Decoded { value:300, next:4 }`. Neither operation mutates a caller cursor.

## Writes and reads

Writers compute the complete encoded length before the first store. If it
does not fit the remaining View, return BufferTooSmall(required encoded byte
count), not a shortfall or total backing size. The entire backing is unchanged.
Success writes exactly the encoding and returns `offset + encoded_count`;
all other bytes remain unchanged. There is no terminator or implicit allocation.

Readers stop at the first terminator and permit following data. Success
publishes the typed value and next position. Error publishes neither a partial
value nor a resume offset; retain the original offset when retrying after more
input arrives. Input bytes are never mutated.

| Error | Precedence and meaning |
| --- | --- |
| Bounds | Malformed View/offset; checked before any access or other error. |
| BufferTooSmall(required) | Writer's complete encoding will not fit; no store occurred. |
| Truncated | A required byte is unavailable before the width limit. |
| Overflow | Fifth/tenth byte has payload above 15/1, or still requests continuation. Checked before shifting/canonicality and without reading another byte. |
| NonCanonical | A permitted terminating byte has zero payload after the first byte. |

Thus `80` is truncated, `80 00` is noncanonical, and five `80` bytes overflow
for 32 bits even if input ends there. For 64 bits the same rule uses ten bytes.
`FF FF FF FF 10` overflows at 32 bits. Bytes after a completed value are not
validated as part of that read.

One private unsigned engine serves all widths; narrowing follows successful
width admission. Work is bounded by five/ten bytes, with constant local storage
and no host calls, recursion, allocation, clone, destruction or cleanup transfer.
Logical checks do not establish physical backing: keep selected bytes live,
initialized and actually present, preserving their native stride. Overclaimed
backing can trap on access; a physical trap has no rollback guarantee.

## Migration and real consumers

The retired modules are `core::varint_i32`, `core::varint_wide_u64` and
`core::varint_wide_i64`. There are no compatibility aliases. This does not
retire the unrelated `core::wide_u64`/`wide_i64` arithmetic APIs.

| Earlier call shape | Current policy |
| --- | --- |
| Raw bytes, logical len and offset | Build a physically backed View and pass its relative offset. |
| Status constants and value/next fallback accessors | Inspect Result; only Ok contains typed Decoded.value/next. |
| Signed codec module and unsuffixed ZigZag names | Use the concrete i32/i64 functions in core::varint. |
| Two-word codec values | Use native u64/i64 for these codecs; any represented-value conversion is an explicit caller choice. |

Both migrated frame-sum examples pass native checked reads/writes, printing
`4294967606` and `-4294967321`. The [varint-number program](stdlib-varint-number.md)
accepts `MODE VALUE`, encoding raw u64/i64 bytes or decoding one complete hex
value to decimal, with explicit
argument/output errors and manual argument cleanup. Its four registered groups
pass in 6.62s: model 76, wire 30, CLI 34 and I/O ten, totaling 150 native cases.

## Evidence and targets

| Receipt in `target/stdlib-work/` | Accepted scope |
| --- | --- |
| `native-varint-admission-first.log` | One test/4.72s: all four widths/extrema, nonzero View start and generic Result/Decoded transport; full syscall trace contains only entry/exit. |
| `native-varint-frames-first.log` | Two tests/5.72s: both migrated frame examples print their exact sums through native checked codecs and decimal output, with nonzero View starts. |
| `native-varint-direct-first.log` | One test/5.14s: all sixteen functions and 37 literal wires, native/packed layouts and four scenarios; admission filtered. |
| `native-varint-number-first.log` | Four application tests/6.62s: all 150 native cases on app `6dea3d57`. |
| `native-varint-model-first.log` | One test/6.12s: 61,144 cases, 52,662 reads/8,482 writes, four widths/two layouts, seed `0xa71a0261102`. |
| `native-varint-boundaries-first.log` | Two tests/9.94s: guarded mapping/exact release, seven no-host-call phases, four widths/three layouts and four migrated physical-overclaim traps exiting 101. |

All five library tests pass on source `a0ef8c9f`; frame/application gates are
separate. The [wire model](../tests/fixtures/stdlib_foundation/native_varint_model/README.md)
checks independent bytes, signed mapping, lengths, next/error payloads and whole
backing atomicity. Its exhaustive continuation-first two-byte domain is assigned
across profiles, not repeated over every type/layout combination. The
[boundary fixtures](../tests/fixtures/stdlib_foundation/native_varint_boundaries/README.md)
record native/packed/unaligned access limits and the retained physical traps.
Historical status/two-word receipts in the [codec overview](stdlib-byte-codecs.md)
and [foundation audit](stdlib-foundation.md) retain their old source/API scope.

The accepted profile is native Linux x86_64 CPU output from the GPU compiler.
Direct user-GPU execution, other targets, automatic lifetimes and formal
verification are unclaimed. No compiler, extractor, proof or native ABI change
is part of this increment.

## Focused targets

Run targets separately; the fixture guides retain exact accepted test filters.

```sh
cargo test --test stdlib_varint_execution
cargo test --test stdlib_varint_model_execution
cargo test --test stdlib_varint_boundary_execution
cargo test --test stdlib_varint_frames_execution
cargo test --test stdlib_varint_number_execution
```
