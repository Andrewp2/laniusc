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
allowed match window. Both policies use the same match, code and block-writing
helpers. The streaming policy adds no dynamic trees, cross-block matches,
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

## Raw, zlib and gzip containers

```text
EncodeLimits { max_input:u64, max_output:u64 }
EncodeFailure { error:Error, read:i32, written:i32 }
default_encode_limits() -> EncodeLimits
encoder(block:View<u8>, pending:View<u8>, scratch:View<i32>,
        format:Format, limits:EncodeLimits) -> Result<Encoder,Error>
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
