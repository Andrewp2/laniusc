# Resumable compression encoding

`ext::deflate` and `ext::compression` add borrowed encoders for raw DEFLATE,
zlib and gzip under the [streaming contract](library-streaming-deflate-plan.md).
They retain fixed workspace across calls and report exact progress. All five
library groups and five application groups/99 cases pass on the finite native
Linux x86_64 profile. The whole-input APIs retain their complete-input size
choice and output-atomic errors; earlier receipts keep their API/source scope.

## Storage and raw API

```text
Status = NeedInput | NeedOutput | Done
Step { read:i32, written:i32, status:Status }
Failure { error:Error, read:i32, written:i32 }

input_buffer_len() -> i32       // 32768 bytes
output_buffer_len() -> i32      // 32773 bytes
scratch_len() -> i32            // 32768 i32 elements
encoder(block:View<u8>, pending:View<u8>, scratch:View<i32>)
    -> Result<Encoder,Error>
Encoder.borrow() -> &Encoder
Encoder.step(input:View<u8>, output:View<u8>, final_input:bool)
    -> Result<Step,Failure>
Encoder.is_done() -> bool
Encoder.reset()
```

Construction checks all three logical View descriptors before capacity checks,
then requires block, pending and hash storage in that order. Invalid metadata
returns `Bounds`; short block/hash storage returns `ScratchTooSmall(32768)`, and
short pending storage returns `Capacity(32773)`. Construction reads no initial bytes,
allocates nothing and calls no host service. Step/reset also allocate nothing.
Only the required workspace prefixes may be changed; larger-view tails remain
untouched. All access preserves the actual View strides.

The caller owns the buffers. Workspace descriptors and physical backing must
remain valid, writable, disjoint and exclusively assigned until the encoder
is retired. Each input/output span must be disjoint from the other span and
all workspace. The Encoder object's own storage, including the container
Encoder, must also be disjoint from workspace and every step's input/output.
Logical checks cannot establish backing size, pointer validity
or absence of aliases. Copies of an Encoder are inactive aliases, not another
active state or cleanup owner. Reset discards buffered input/output and logical
state without clearing workspace; it does not release caller storage.

## Progress and final input

Every step validates both complete input/output descriptors before handling
Done or a container's failed state. Invalid metadata returns `Bounds` at
`read=written=0` without state or backing changes. Counts refer only to this
call: `read` bytes were consumed, and `written` bytes form the initialized
output prefix. No offered input/output View is retained. Consumed bytes are
copied into block storage, so their caller buffer can be recycled.

Pending encoded bytes drain before new input is admitted. `NeedInput` means
the complete offered input was consumed and more input or finalization is
needed. `NeedOutput` means encoded bytes need output space. A zero-length
output can still admit input and prepare one block. Neither status is an
instruction to discard an unread input suffix.

`final_input=true` is a call-local caller promise that no bytes follow the
offered span; the encoder does not enforce that promise at runtime. If a call
suspends, resubmit its exact unread suffix and repeat true, including empty
drain calls. Do not withdraw that promise or supply later data. With valid
metadata, Done is fused and returns 0/0. To encode another stream, call reset
and establish a new final-input promise.

Output before Done is a prefix of an incomplete compressed stream. A consumer
that requires a complete file must defer publication until completion and any
required input-close checks; the [file compressor](extended-compress-file.md)
uses an AtomicFile temporary for this purpose.

## Deterministic block policy

Streaming accumulates exactly 32,768 input bytes per full block. Every full
block is nonfinal; a final partial block, possibly empty, closes the stream.
Thus an exact multiple of 32,768 still ends with a separate empty final block.
Match search restarts at each block, so references never cross block boundaries.

For each block, the shared greedy match engine compares fixed-Huffman and
stored wire sizes and chooses the smaller, preferring fixed on a tie. A
nonfinal fixed block is followed immediately after its end-of-block code by an
empty nonfinal stored-block header, then alignment padding. There is no padding
between the fixed end code and that next header. The marker's cost participates
in the size comparison. A stored block is
already byte aligned. Final partial blocks use ordinary final encoding.

Caller chunk boundaries and output capacities do not change the complete
encoded bytes. Streaming and whole-input encoding may differ: whole-input
measurement chooses over the complete borrowed span and can use its full
allowed match window. Both policies make the same match and code choices; a
[packed fast pass](#packed-fast-pass) writes streaming blocks when the block
and pending buffers are packed bytes. The streaming policy adds no dynamic trees, cross-block matches,
preset dictionaries or public flush modes, and promises no compression ratio.

Storage stays fixed as total input grows. Work is linear in input size with
fixed table clearing per block. Candidate checks examine at most 258 bytes per
position in each bounded measurement/emission pass. Calls copy only admitted
spans but may encode a full block even
with no output space. These are work/storage bounds, not wall-time guarantees
or throughput measurements.

For input length n, let q=floor(n/32768) and r=n%32768. Full blocks use at most
32,773 bytes each; a final partial uses at most r+5 bytes, or exactly two bytes
when r=0. Raw output is therefore at most n+5q+5, tightened to n+5q+2 when r=0.
Container framing adds six bytes for zlib or eighteen for gzip.

## Packed fast pass

When the block and pending buffers have stride +1 (any `alloc::vec::Vec<u8>`
view), each block is encoded in one pass that writes the pending buffer
directly. It stops as soon as the fixed encoding exceeds the stored size,
which is exactly when stored is selected, so the earlier separate measuring
pass is gone. Its output is byte-for-byte the output of the general pass,
which still serves other strides and whole-input `encode_into`:

- Each hash slot holds `position | (x << 8 | y) << 15` for the bytes x, y, z
  at that position. For fixed x and y, the 15-bit hash determines z, so a slot
  whose tag matches already has the same three bytes and needs no byte checks.
- Fixed literal, length and distance codes come from small per-block tables
  with bit-reversed codes and extra bits packed together.
- Lookahead bytes, match comparison and the insertion of positions inside a
  match read the block a 64-bit word at a time; match comparison finds the
  first differing byte from the XOR of two words.
- Output bits accumulate in a 64-bit buffer and leave a word at a time.
- Only a three-byte match can lose to its literals (a match costs at most 31
  bits, four literals at least 32), so the literal-cost test is one comparison.

Block intake, pending publication and stored blocks copy by word, and gzip
CRC-32 uses slicing-by-8 tables built on the stack for spans of 2 KiB or more.

### Measurements

These were measured on the Linux x86_64 laptop (load average 7–9) with the shared `lcc` of 2026-10-31.
The program streams stdin to stdout through `ext::compression::encoder` (gzip) with 64 KiB
buffers and direct `std::fs` I/O. Each time is the fastest of nine interleaved runs (two for
the old encoder). Every output was decoded by Python `gzip` and was byte-identical to the previous
encoder's output.

| Input | Bytes | Before | After | Output bytes | `gzip -1` | `gzip -6` |
| --- | --- | --- | --- | --- | --- | --- |
| docs/stdlib tar | 18,145,280 | 4.78 s (3.8 MB/s) | 0.34 s (54 MB/s) | 10,112,519 | 0.19 s, 8,651,104 | 0.43 s, 7,894,861 |
| text tar | 13,281,280 | 3.78 s (3.5 MB/s) | 0.26 s (50 MB/s) | 5,401,026 | 0.11 s, 3,973,737 | 0.34 s, 3,240,787 |

Bit-serial CRC-32 accounted for about 2.5 s of the corpus's old time. The remaining cost is
per-byte bookkeeping in the generated code; the fixed-Huffman profile (no dynamic trees)
keeps output larger than gzip's. The opt-in [dynamic Huffman levels](#dynamic-huffman-levels)
close most of that gap.

## Dynamic Huffman levels

```text
level_window_len() -> i32       // 65552 bytes
level_pending_len() -> i32      // 32784 bytes
level_scratch_len() -> i32      // 102400 i32 elements
level_encoder(window:View<u8>, pending:View<u8>, scratch:View<i32>,
              level:i32) -> Result<Encoder,Error>
```

Level 0 is `encoder(window, pending, scratch)`, so its output is unchanged.
Levels 1-3 are opt-in. They return the same `Encoder` with the same
`step`/`is_done`/`reset` contract. The window and pending views must be packed
(stride +1, any `Vec<u8>` view) and at least the lengths above, or the call
returns `Bounds`, `ScratchTooSmall(65552)`, `Capacity(32784)` or
`ScratchTooSmall(102400)` (scratch); any other level is `Bounds`.

- **Matching.** A 32 KiB sliding window over a 64 KiB buffer. Every position
  is inserted into a 32,768-entry hash table with a 32,768-entry chain, keyed
  on a multiplicative hash of the next four bytes. Matches are 3-258 bytes and
  are compared a word at a time.
  Absolute positions start at 32768, so an empty slot is always out of range,
  and they are rebased before reaching 2^30.
- **Parameters.** As in zlib: `chain` bounds the candidates per search (a
  quarter once the previous match reaches `good`), and a match of `nice`
  bytes ends the search and skips hashing the positions inside it. Lazy
  matching retries a match shorter than `lazy` one byte later. A three-byte
  match farther than 4,096 bytes is dropped.

  | Level | Chain | Lazy | Nice | Good |
  | --- | --- | --- | --- | --- |
  | 1 | 4 | greedy | 16 | 4 |
  | 2 | 4 | 8 | 32 | 4 |
  | 3 | 16 | 32 | 258 | 16 |

- **Blocks.** Each 32 KiB of input becomes one block. Its symbols are kept in
  scratch, and the block is written as dynamic, fixed or stored, whichever is
  smallest in exact bits. Bit packing continues across blocks, so only the
  final block pads to a byte. As with level 0, input that ends on a 32 KiB
  boundary adds an empty final block.
- **Codes.** Code lengths come from in-place minimum-redundancy lengths
  (Moffat and Katajainen) over frequency-sorted symbols. They are limited to
  15 bits (7 for the code-length code) by removing the Kraft excess as zlib
  does. Code lengths use the RFC 1951 run codes 16, 17 and 18. Symbols leave
  a 64-bit word at a time.

### Level measurements

These were measured on the Linux x86_64 laptop (load average 9–10) with the shared `lcc` of 2026-11-01.
The program is the same gzip streaming program as above, with the level as its argument. Each time is the
fastest of seven interleaved runs. Every level's output was decoded by Python `gzip` and by
`zlib` as a raw stream.

| Input | Level 0 | Level 1 | Level 2 | Level 3 | `gzip -1` | `gzip -6` |
| --- | --- | --- | --- | --- | --- | --- |
| docs/stdlib tar, 18,145,280 B | 10,112,519 B, 0.37 s | 8,205,489 B (+3.9%), 0.57 s | 8,120,999 B (+2.9%), 0.63 s | 7,920,440 B (+0.3%), 0.78 s | 8,651,104 B, 0.21 s | 7,894,861 B, 0.46 s |
| text tar, 13,281,280 B | 5,401,026 B, 0.28 s | 3,546,334 B (+9.4%), 0.35 s | 3,464,239 B (+6.9%), 0.39 s | 3,269,766 B (+0.9%), 0.56 s | 3,973,737 B, 0.12 s | 3,240,787 B, 0.35 s |

Percentages are relative to `gzip -6`. Level 2 runs at 28.7 MB/s on the docs/stdlib tar and
33.8 MB/s on the text tar. On this run level 0 and `gzip -6` were each about 9% slower than in
the quieter run above.

## Raw, zlib and gzip containers

```text
EncodeLimits { max_input:u64, max_output:u64 }
EncodeFailure { error:Error, read:i32, written:i32 }
default_encode_limits() -> EncodeLimits
encoder(block:View<u8>, pending:View<u8>, scratch:View<i32>,
        format:Format, limits:EncodeLimits) -> Result<Encoder,Error>
level_encoder(block:View<u8>, pending:View<u8>, scratch:View<i32>,
              format:Format, limits:EncodeLimits, level:i32)
    -> Result<Encoder,Error>   // level 0 is encoder()
Encoder.borrow() -> &Encoder
Encoder.step(input:View<u8>, output:View<u8>, final_input:bool)
    -> Result<ext::deflate::Step,EncodeFailure>
Encoder.total_read() -> u64
Encoder.total_written() -> u64
Encoder.is_done() -> bool
Encoder.is_failed() -> bool
Encoder.reset(format:Format, limits:EncodeLimits)
```

These are `ext::compression` APIs using its existing `Format` and `Error`.
The factory maps raw Bounds to Bounds and other raw admission errors to
`Encode(raw_error)`.
Defaults allow 16 MiB input and 64 MiB encoded output. The u64 allowances and
totals are independent of the i32 per-call View/count limits. The wrapper
borrows the same workspace and retains partial header/trailer state.

RawDeflate emits only the raw stream. Zlib emits header `78 01` and the
Adler-32 trailer. Gzip emits `1f 8b 08 00 00 00 00 00 00 ff`: no optional
fields or timestamp, and OS 255. It emits one member with CRC-32 and consumed
input length modulo 2^32. Checksums advance only for bytes actually consumed;
they are format checksums, not authentication.

After metadata validation and terminal-state handling, an active encoder
admits the **entire offered input span** against remaining input allowance
before changing state. Oversized offers latch `InputLimit` at 0/0, even if
the encoder would otherwise consume only part of that offer. Only consumed
bytes advance `total_read`. `total_written` includes confirmed header, body
and trailer bytes.

`OutputLimit` occurs only when another encoded byte is required beyond the
allowance, retaining this call's exact progress. Completion at the exact
allowance succeeds. Limits and codec errors are sticky until reset and repeat
at 0/0; `Bounds` remains recoverable, including after Done or failure. Reset
adopts a new format/limits and clears counters, checksums and raw logical
state. It adds no I/O, dictionary or automatic cleanup.

## Evidence and remaining work

Raw source is frozen at
`f1dd114fa6a98ab07ffe25d769276ea52915a164fe11e63ce67ed43e9a9a10ad`.
Container source is frozen at
`4d23bd4740d77f4d157e88498f69ba47bbd385f41294d9fe4ab3a9954a85af9a`.
The first native admission passes in all three formats: one test in 5.44
seconds after a separate 0.19-second Rust build, with three exact allocations
and releases (`target/stdlib-work/streaming-deflate-admission-final.log`). The
initial attempt failed compilation from authored block-match syntax in the
framing source, in 3.53 seconds after a 1.70-second build. Ordinary branch
dispatch corrected that syntax before native execution; no compiler repair
was needed.

The next three-group command passed framing/limits/stride and scale, but its
metadata fixture failed to compile: 14.49 seconds, separate Rust build 1.16
seconds (`streaming-deflate-direct-resources.log`). The literal in
`4294967296 as u64` was checked as i32 before the cast (LNC0069); an explicitly
typed u64 binding preserves the same boundary. Only that fixture changed.
Its narrow retry passed one test in 5.63 seconds after a 0.19-second build
(`streaming-deflate-metadata-final.log`), preserving the complete 196,637-byte
workspace snapshot and matching all six allocation/release lifetimes.

Accepted framing tests include exact limits, one-byte headers/trailers,
negative-stride workspace and 32,769 consumed source bytes overwritten after
admission, with four exact allocations/releases. Scale runs eight streams at
two sizes through five fixed owners totaling 208,933 bytes. All 6,357,096 input
bytes decode independently from 3,207,473 encoded bytes; 1,961 pure phases and
exact cleanup pass. The traced scale process took 3.914524 seconds, separate
from 1.009526 seconds compiling it, and includes input generation, checks and
publication. It is not isolated codec throughput. See the
[direct/resource fixture guide](../tests/fixtures/extended_streaming_deflate/README.md).

The [independent model](../tests/fixtures/extended_streaming_deflate_model/README.md)
passes one test in 13.74 seconds after a separate 1.06-second Rust build
(`streaming-deflate-model.log`). Seed `0xdef1a7e0261115` covers 112 cases,
260 complete passes, 28 patterns and 5,934,732 consumed input bytes across eight
selected layouts. The four entry routes are the raw API and container
RawDeflate/zlib/gzip: there are three wire formats, not four. Whole, irregular
and small bytewise schedules produce identical complete bytes after reset.
Independent zlib decoding and an RFC block reader validate content/framing;
a separate intake/publication event model checks exact per-call progress.
Twenty-two host corruption controls and nine reference streams add no native
cases. Accepted producer/oracle/driver prefixes are `b0c7b363`/`975b8933`/`8a22069a`.

The [file compressor](extended-compress-file.md#evidence-and-remaining-scope) passes
five groups/99 native cases, including nine reached allocation denials and
real publication/recovery outcomes. Standalone build/examples are separate.
Selected existing whole-input regressions below check the shared block-helper
change. Historical
[raw](extended-deflate.md#executable-evidence),
[container](extended-compression.md#executable-evidence) and
[performance](extended-compression-performance.md) receipts do not establish
the new streaming APIs.

Four selected existing groups pass on the current sources, separately from
new-API acceptance: three raw groups for contracts, match-code boundaries and
stored 65,535-byte boundaries in 10.92 seconds (Rust build 1.19 seconds,
`streaming-deflate-existing-raw.log`), plus one owned-container encoding
interoperability group in 6.33 seconds (build 1.19 seconds,
`streaming-deflate-existing-containers.log`). Logs are under
`target/stdlib-work/`. Neither complete historical suite was rerun.

The accepted target is Linux x86_64 CPU code emitted by the GPU compiler.
Other hosts, GPU device programs, enforced borrowing/destruction and formal
proof require separate evidence. No compiler, ABI, host codec or protected
library change is part of this increment. The broader library goal remains
open; see the [dependency ledger](library-dependencies.md).

## Format sources

[RFC 1951](https://www.rfc-editor.org/rfc/rfc1951.html) defines block framing,
fixed codes and stored alignment. [RFC 1950](https://www.rfc-editor.org/rfc/rfc1950.html)
defines zlib framing and Adler-32; [RFC 1952](https://www.rfc-editor.org/rfc/rfc1952.html)
defines gzip headers, CRC and size fields. The
[zlib manual](https://zlib.net/manual.html) describes incremental progress and
empty stored blocks for byte alignment. These are format/design references;
system zlib is only an independent test oracle. Production encoding is Lanius.
