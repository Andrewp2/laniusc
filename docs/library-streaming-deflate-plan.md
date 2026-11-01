# Resumable compression encoding

At `29daf6a2`, decoding retains state across chunks, but `ext::deflate` and
`ext::compression` encode complete borrowed inputs into complete outputs. This
increment adds bounded-storage encoding and a real file compressor. The full
standard and extended library goal remains open.

## Authorities and design

The format authorities are [RFC 1951](https://www.rfc-editor.org/rfc/rfc1951.html),
[RFC 1950](https://www.rfc-editor.org/rfc/rfc1950.html) and
[RFC 1952](https://www.rfc-editor.org/rfc/rfc1952.html). The
[zlib manual](https://zlib.net/manual.html) describes incremental progress and
empty stored blocks for byte alignment. Production remains Lanius; system zlib
is an independent test oracle only.

Reuse the existing greedy match search, fixed Huffman codes, bit writer and
stored-block writer. Parameterize their final-block/alignment behavior rather
than introducing another compressor. Whole-input measurement/encoding retains
its complete-input optimization and output-atomic failure contract. Streaming
is a distinct bounded-storage policy over the same block engine, not a legacy
compatibility wrapper.

Streaming collects exactly 32,768 bytes per full block. Each full block is
nonfinal, and a final partial block (possibly empty) closes the stream. Match
search starts afresh for each block. Choose the smaller fixed or stored wire
representation, preferring fixed on a tie. A nonfinal fixed block ends with an
empty nonfinal stored block to align the next block to a byte; count those
alignment bytes when selecting. A stored block is already byte aligned.
Partial final blocks use ordinary final encoding. Caller chunk partitions do
not change output. Cross-block match opportunities and dynamic trees are not
part of this fast block policy; no compression-ratio promise follows.

## Borrowed raw interface

```text
ext::deflate::Status = NeedInput | NeedOutput | Done
ext::deflate::Step { read:i32, written:i32, status:Status }
ext::deflate::Failure { error:Error, read:i32, written:i32 }
input_buffer_len() -> i32             // 32768 bytes
output_buffer_len() -> i32            // 32773 bytes
scratch_len() -> i32                  // existing 32768 i32 elements
encoder(block:View<u8>, pending:View<u8>, scratch:View<i32>)
    -> Result<Encoder,Error>
Encoder.borrow() -> &Encoder
Encoder.step(input:View<u8>, output:View<u8>, final_input:bool)
    -> Result<Step,Failure>
Encoder.is_done() -> bool
Encoder.reset()
```

Construction validates complete logical metadata first, then block, pending and
hash capacities. Existing Bounds, ScratchTooSmall and Capacity errors identify
invalid metadata, insufficient block/hash storage and insufficient pending
storage respectively. No initialization reads, allocation or host calls occur.
Only admitted workspace prefixes may be written. Preserve actual View strides.

Every step validates both complete input/output descriptors before terminal
state handling. Bounds is recoverable at 0/0 without changing state or backing.
Counts describe this call: only consumed input and the initialized output prefix
are counted. Input/output views are not retained. Consumed bytes are copied into
block storage, allowing the caller to recycle input. Pending output drains before
new input is admitted. NeedInput means all offered input was consumed and more
input or finalization is needed. NeedOutput means confirmed encoded bytes need
space. Zero output may still admit input and prepare one block.

`final_input` is a call-local promise that no bytes follow the offered span; the
encoder does not enforce promises made by the caller. After suspension,
resubmit the exact unread suffix and repeat true, including empty drain calls.
Done is fused at 0/0 with valid metadata. Reset discards pending state without
clearing workspace and starts a new stream. Workspace descriptors and backing
must remain valid, disjoint, writable and exclusively assigned; input/output
must be mutually disjoint and disjoint from workspace. The Encoder object's
own storage must also be disjoint from all workspace and input/output spans,
including for the framing Encoder below. Copies of an Encoder
are inactive aliases. Physical lifetime/capacity and cleanup remain manual.

Encoding work is linear with a bounded 258-byte candidate check per input
position and fixed table clearing per block. Scratch is fixed regardless of
total stream size. Caller chunk sizes bound per-call copying; one block may be
encoded even when no output is offered. This is not a wall-time guarantee.

## Container interface

```text
ext::compression::EncodeLimits { max_input:u64, max_output:u64 }
ext::compression::EncodeFailure { error:Error, read:i32, written:i32 }
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

Use existing Format/Error and embed the raw encoder. Defaults are 16 MiB input
and 64 MiB output. u64 limits avoid cumulative signed-buffer limits. Emit the
existing deterministic zlib header or gzip header (no time/name/comment; OS255).
Update canonical Adler-32/CRC only for actual consumed bytes; gzip size is the
consumed count modulo 2^32. Preserve partial header/trailer writes.

Validate metadata first even after failure/Done. With valid active state the
entire offered input span must fit remaining input allowance before any state
change; otherwise latch InputLimit at 0/0. Actual consumed bytes alone advance
totals. OutputLimit occurs only when another encoded byte is required beyond
the output allowance, with exact progress already made. Exact-fit completion
must succeed. Limits/codec errors are sticky until reset, repeated at 0/0;
Bounds is recoverable. Reset adopts the new format/limits and resets raw state,
checksums and counters. No allocation, I/O, automatic cleanup or dictionary is
introduced. Dynamic coding, public flush modes and preset dictionaries remain
separate capabilities.

## Real file consumer and acceptance

`compress_file --format raw|zlib|gzip INPUT OUTPUT` uses the existing CLI, File,
AtomicFile and NoReplace policy, following the decompressor's explicit
visibility/durability/recovery contract. Use fixed input/output/workspace
owners, a 64 MiB input cap with a real EOF probe, a 65 MiB compressed-output cap,
131,072 read attempts, 262,144 encoder steps and 131,072 atomic write attempts.
The File adapter reads at most 1,024 bytes per call, so the read budget leaves
room for the exact-cap EOF probe and interrupted calls.
Only regular no-follow inputs are admitted. Close input and finish encoding
before commit. Report cleanup/recovery outcomes honestly. The output cap is
defensive under the admitted input/encoding bound. Existing destinations must
remain untouched, including when INPUT and OUTPUT name the same inode.

Eight agents own raw implementation, framing, application, differential model,
direct/resource tests, application tests, docs and independent review. Root
owns integration, native execution and release. Root alone runs compiler/Cargo/
native commands serially under `target/stdlib-work/library-gpu.lock`; each outer
command is capped at 100 seconds. Start with a small raw/container admission.
Use independent zlib decompression, chunk invariance, progress/terminal/limit
tests, exact workspace guards and fixed-allocation scale evidence. Exercise
application allocation/I/O/publication failures and several real files.
Run selected old deflate/compression regressions because block helpers change.

Preserve README, AI_POLICY, CONTRIBUTING, tests/common, std/vec and core/mem.
No compiler/IR/ABI/extractor/proof change is planned; isolate any new limitation
instead. Initial acceptance is Linux x86_64 CPU output from the GPU compiler,
not device execution or formal proof. The receipts below record the completed
increment; the full library roadmap remains open.

## Accepted increment

All five new library groups and all five file-compressor groups pass on Linux
x86_64 CPU output from the GPU compiler. Production hashes are raw encoder
`f1dd114f`, framing `4d23bd47` and application `671688ab`. Independent source,
test and documentation reviews pass. No compiler or ABI repair was required.

| Gate | Accepted result | Local receipt in `target/stdlib-work/` |
| --- | --- | --- |
| Raw/zlib/gzip admission | 1/1 in 5.44 s; Rust build 0.19 s | `streaming-deflate-admission-final.log` |
| Exact limits, bytewise framing and recycled strided input | Passed in the mixed 14.49 s invocation; build 1.16 s | `streaming-deflate-direct-resources.log` |
| Fixed-owner scale | Passed in that same invocation | `streaming-deflate-direct-resources.log` |
| Metadata/recovery/reset | Corrected fixture passes 1/1 in 5.63 s; build 0.19 s | `streaming-deflate-metadata-final.log` |
| Independent wire/progress model | 1/1 in 13.74 s; build 1.06 s | `streaming-deflate-model.log` |
| File content and block boundaries | 17 cases in 11.07 s; build 1.14 s | `streaming-deflate-tool-model.log` |
| File CLI and input/destination policy | 39 + 9 cases in one 8.58 s invocation; build 0.21 s | `streaming-deflate-tool-admission.log` |
| Actual 64 MiB input boundary | 2 cases in 36.15 s; build 0.18 s | `streaming-deflate-tool-limits.log` |
| Reached file allocation/I/O/publication failures | 32 cases in 17.27 s; build 0.19 s | `streaming-deflate-tool-faults.log` |
| Selected existing raw encoder regressions | 3/3 in 10.92 s; build 1.19 s | `streaming-deflate-existing-raw.log` |
| Existing owned container encoding | 1/1 in 6.33 s; build 1.19 s | `streaming-deflate-existing-containers.log` |

The independent model covers 112 cases and 260 passes over 28 payload patterns,
5,934,732 input bytes and eight selected layouts, using seed
`0xdef1a7e0261115`. It tests the raw API and three container selections: these
are four API routes but three wire formats. All cases have whole and irregular
chunk schedules; 36 small-case passes use one-byte schedules. System zlib
checks complete decoded data, an independent RFC reader checks block policy,
and a validated wire-event model checks exact per-call progress and counters.
Consumed-source poisoning, full output/workspace guards, reset and fused Done
are observed. Twenty-two rejected host corruptions and nine independent
reference streams remain separate oracle controls, not native case counts.

The scale test reconstructs all 6,357,096 input bytes from eight streams whose
combined encoded size is 3,207,473 bytes. Five mappings totaling 208,933 bytes
are reused across all streams and released exactly once. Its traced native
process takes 3.914524 seconds, separate from 1.009526 seconds compiling that
fixture. Timing includes input generation, guards, publication and tracing;
it is not isolated throughput or a comparison against another compressor.

The file program passes 99 native process cases across five groups. Its
32-case fault group comprises 23 other cases and nine reached allocation
denials. The observer covers fifteen specified syscalls; synthetic close
failures prove logical retirement, not successful physical closure. Actual
64 MiB success and the extra-byte rejection confirm the EOF probe. The 65 MiB
output bound is defensive under the admitted input/encoding bound, so no
unreachable output-limit rejection is claimed. Library output-limit behavior
has separate direct execution evidence.

Two authoring failures are retained rather than counted as runtime evidence.
The initial 3.53-second admission invocation rejected block-valued match arms
in new framing source; ordinary conditional branches corrected that syntax.
The first mixed direct invocation passed framing and scale but rejected a
fixture's large integer cast before execution. A typed u64 binding retained
the intended limit of exactly 2^32, and only that failed metadata selector was
rerun. The earlier file read budget was also corrected before native runs:
the 1,024-byte provider cap requires an extra call after exactly 64 MiB to
observe EOF. These changes introduce no new compiler dependency.

Standalone CLI compilation passes with exit zero and an empty success log in
`streaming-deflate-cli-build.log`. Both documented examples pass independently:
raw ABC produces exactly five bytes, and the five-byte binary input produces
a 25-byte gzip file checked with system gzip and zlib. Inputs remain unchanged,
successful stdout/stderr are empty and temporary files are retired. The two
examples in `streaming-deflate-cli-examples.log` are separate from the 99 cases.

The [encoder guide](extended-streaming-deflate.md),
[file-tool guide](extended-compress-file.md) and fixture READMEs retain precise
source hashes and scopes. Whole-input and streaming fronts share the same
match/code/block helpers, with explicit distinct block policies. Borrowing and
cleanup remain manual. Other targets, device execution, formal verification,
preset dictionaries, dynamic-tree encoding, public flush modes and the rest of
the standard/extended library roadmap remain open.
