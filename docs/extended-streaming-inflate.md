# Resumable DEFLATE, zlib and gzip decoding

The [resumable decompression increment](library-streaming-inflate-plan.md)
keeps decoder state across input and output chunks. Raw decoding belongs to
`ext::inflate`; zlib/gzip framing and owned decoding belong to
`ext::compression`. Their implementation uses one raw parser and preserves
partial bits, code tables, pending copies and history instead of replaying
compressed prefixes after output growth. All seven new library tests pass:
four direct tests, one independent model and two resource tests. All seven
application groups also pass, covering 98 native cases. This finite native
Linux x86_64 increment is accepted.
The full standard/extended-library goal remains open.

The format authorities are [RFC 1951](https://www.rfc-editor.org/rfc/rfc1951)
for DEFLATE, [RFC 1950](https://www.rfc-editor.org/rfc/rfc1950) for zlib and
[RFC 1952](https://www.rfc-editor.org/rfc/rfc1952) for gzip. The
[zlib manual](https://zlib.net/manual.html) provides a streaming reference.
Production decoding is Lanius. System zlib is only an independent test
generator/oracle; the library adds no native codec dependency.

## Raw interface and persistent storage

```text
ext::inflate::Status = NeedInput | NeedOutput | Done
ext::inflate::Step { read:i32, written:i32, status:Status }
ext::inflate::Failure { error:Error, read:i32, written:i32 }

workspace_len() -> i32                 // 707 i32 elements
fast_workspace_len() -> i32            // 8,643: adds the fast-path tables
decoder(history:View<u8>, workspace:View<i32>, max_distance:i32)
    -> Result<Decoder,Error>

Decoder.borrow() -> &Decoder
Decoder.step(input:View<u8>, output:View<u8>, final_input:bool)
    -> Result<Step,Failure>
Decoder.reset(max_distance:i32) -> Result<bool,Error>
Decoder.is_done() -> bool
Decoder.is_failed() -> bool
```

Views denote `core::slice::View`. The window must be a power of two from 256
through 32,768. History must contain at least that many bytes; workspace must
contain at least 707 i32 elements. Construction checks complete logical metadata
and capacities before touching backing. It stores descriptors and scalar state
without clearing or reading unused storage, allocating, calling a host service
or taking cleanup authority. History/workspace tails beyond the admitted
prefixes remain untouched.

The workspace contains 320 code lengths, 16 literal counts, 288 literal
symbols, 16 distance counts, 32 distance symbols, 16 code-length counts and
19 code-length symbols. The decoder preserves actual descriptor strides.
A workspace of at least `fast_workspace_len()` elements also holds the
[table-driven fast path](#table-driven-fast-path)'s lookup tables at
offsets 707 and 6,339. A 707-element workspace keeps the bit-serial decoder
alone, with identical results and progress.
Persistent ring position and valid-history count stay within the selected
window. They do not depend on a cumulative signed output counter. History
spans blocks, and overlapping copies insert each emitted byte before looking
up the next byte.

Only history/workspace borrows persist. A step retains no input or output view,
so consumed input and delivered output storage can be recycled between calls.
Keep all persistent backing live, writable and disjoint from input/output and
from each other. End temporary views before mutation; keep shallow decoder
copies and other aliases inactive. Logical validation does not establish
physical capacity, lifetime or non-overlap. Destruction remains the caller's
responsibility, and physical traps have no rollback guarantee.

## Progress, final input and suspension

Both success and failure counts describe **this call**. `read` counts input
bytes consumed; a counted byte may still have buffered bits in the decoder.
`written` counts initialized output bytes at the beginning of the offered
output view. Input is unchanged, unconsumed input bytes are not read, and output
outside that prefix is unchanged. Raw Done stops at the final block and leaves
following whole bytes unread.

`final_input` is a promise for this call that no bytes follow the offered span.
It is not remembered or enforced across calls. After NeedOutput, offer its
exact unread suffix again and repeat true, including on empty calls draining
pending output. Supplying extra input later or withdrawing that promise cannot
support a valid completion/truncation claim. With missing required input,
false produces NeedInput and true produces UnexpectedEof. Pending output drains
before the decoder considers a later input need.

An empty output view can still admit headers, empty blocks, end codes and
validation. NeedOutput means a confirmed literal, stored byte or match byte
needs space. Streaming steps use NeedOutput and never report OutputTooSmall.
Stored blocks check missing input before missing output; match
distance validation precedes output capacity. Dynamic literal-count validity
is checked after all HLIT/HDIST/HCLEN fields arrive. These rules preserve the
existing whole-buffer failure precedence at chunk boundaries.

Each step validates both complete View descriptors first, even after Done or
failure. Invalid metadata returns Bounds with read=written=0 and leaves all
state/backing unchanged. With valid metadata, a completed decoder returns Done
at 0/0; a failed decoder repeats its original error at 0/0. Codec errors and
final-input truncation stay sticky until reset. Bounds is recoverable.

A valid reset returns true, adopts the admitted window and clears logical
history, parser, failure and completion state without clearing backing. Invalid
reset changes nothing. Reset starts a new decode and discards the meaning of
prior provisional output. Consumers independently bound offered chunk sizes,
total input/output and call counts. The engine has no hidden input replay,
recursive tree walk or wall-time guarantee; work is linear in consumed input
and produced output with bounded alphabet work per block.

## Container interface

```text
ext::compression::DecodeFailure { error:Error, read:i32, written:i32 }
decoder(history:View<u8>, workspace:View<i32>, format:Format, limits:Limits)
    -> Result<Decoder,Error>

Decoder.borrow() -> &Decoder
Decoder.step(input:View<u8>, output:View<u8>, final_input:bool)
    -> Result<ext::inflate::Step,DecodeFailure>
Decoder.reset(format:Format, limits:Limits) -> Result<bool,Error>
Decoder.total_read() -> u64
Decoder.total_written() -> u64
Decoder.members() -> i32
Decoder.is_done() -> bool
Decoder.is_failed() -> bool
```

The existing Format, Limits and Error definitions remain canonical. Defaults
are 16 MiB input, 64 MiB output and 1,024 members. The borrowed container decoder
requires 32,768 history bytes and the 707-element raw workspace, including when
the selected format is RawDeflate. Construction/reset validate nonnegative
limits, complete backing metadata and capacities before changing state. No
allocation or cleanup authority is added. Framing embeds the raw decoder and
scalar header, checksum and counter state.

Container steps share the raw metadata-first, call-local final-input and
sticky-error rules. Before an active step reads anything, its **entire offered
input span** must fit the remaining cumulative input allowance. An oversized
offer returns sticky InputLimit at 0/0, even if only its prefix might have been
needed. Callers must limit their offers. Actual consumed bytes alone advance
`total_read`, so a resubmitted unread suffix is not charged twice. Framing may
inspect invalid trailing magic without consuming it; container `read` does not
count that rejected lookahead. The raw no-prefetch guarantee above has its own
raw-stream scope. Cumulative
counters use u64 within the existing i32 Limits domain.

Output offered to the raw engine is bounded by caller space and remaining
output allowance. NeedOutput turns into OutputLimit only when allowance is
exhausted and a real output byte is pending. Exact-cap streams can still finish
end markers and trailers. A step updates checksum, decoded size and counters
once for every confirmed output byte, including a prefix returned with an error.
**Streaming output is provisional until container Done.** A later checksum,
trailer, member-limit or end-of-input error cannot undo bytes already delivered.

Raw and zlib wait for explicit final input after their body/trailer. Before
that final confirmation, any further byte is TrailingData. Gzip accepts a
sequence of members and completes only when explicit final input confirms its
end. Each member starts with fresh logical history and checksum state. Empty
gzip input is Truncated. Raw/zlib do not infer concatenation. `members()` counts
completed raw bodies or checksum/size-validated framed members, including while
waiting for final input.

The framing profile preserves complete fixed-header/trailer reads before their
semantic checks. Zlib validates method, header check, advertised window and
Adler-32; a complete dictionary ID precedes UnsupportedDictionary. Gzip extra,
name and comment fields and optional header CRC can span calls; their bytes
are metadata, never output paths. Each member validates CRC-32 and wrapping-u32
ISIZE. After a gzip member, trailing magic classification precedes admission
of another member, including when that prefix spans calls. Reserved symbols
fail when used; an empty distance alphabet remains valid until a match needs
one. The existing [container guide](extended-compression.md) records format and
error details.

## Whole-buffer entry points and allocation order

`inflate::decode_into` and `decode_into_window` remain allocation-free. They
use the same raw engine with complete caller output as history and 8,643 local
i32 table entries, so they take the fast path. They need no separate 32 KiB ring allocation or second
parser. NeedOutput maps to their existing OutputTooSmall; final input exhaustion
maps to UnexpectedEof. Their failure counts remain diagnostic, because those
facades do not return retained decoder state. Use Decoder to resume.

Owned `compression::decode` allocates one history ring and one workspace,
then grows only its result geometrically around the same framing state. Every
growth rebuilds transient output views, so no view into moved storage survives.
It no longer restarts a member after growth. Complete input/limit metadata
admission still precedes allocation, but fixed workspace allocation can now
fail before later format validation. A malformed header therefore need not
win over AllocationFailed; this is an explicit allocation-order change.

On success, only the independent returned Vec remains live. On error, every
private owner is released and no output owner escapes. Owned decoding still
publishes no result before all container and end checks pass. Encoding keeps
its existing deterministic fixed/stored strategy. Historical compression
timings describe the old member-replay decoder. The focused native comparison
below has its own receipt and does not establish compiler or cross-library
performance.

## Focused native comparison

The unchanged `compress_bytes` application was compiled against retained
before/after codec sources. Each executable decoded the same six independent
zlib-generated workloads, pinned to CPU 0, with one warmup and three timed
processes per workload. Every output byte was checked. Each workload expands
to 1,048,576 bytes. Times include native process startup, pipes, owned input and
output, decoding and checksums; GPU compilation is outside the measurements.

| Corpus | Format | Before median (range), ms | After median (range), ms |
| --- | --- | --- | --- |
| Repeated | Raw | 70.872 (70.126–91.895) | 59.922 (59.535–61.585) |
| Repeated | zlib | 73.851 (73.209–84.133) | 62.207 (61.783–63.243) |
| Repeated | gzip | 136.526 (135.409–137.561) | 136.966 (130.578–143.756) |
| Random | Raw | 205.834 (198.761–230.915) | 211.182 (190.719–230.906) |
| Random | zlib | 200.089 (198.110–200.566) | 188.186 (185.863–189.569) |
| Random | gzip | 249.939 (248.344–271.903) | 241.001 (236.895–243.470) |

Random raw ranges overlap substantially; repeated gzip is comparable in these
samples. The other four medians decreased. This limited comparison supports no
universal speedup or regression claim. The committed
[native comparison harness](../tests/fixtures/extended/inflate_stream_resources/native_compare.py)
records full output checks, executable hashes and all samples. Local receipts
are `target/stdlib-work/inflate-stream-native-compare/before.json` and
`after.json`, with `target/stdlib-work/inflate-stream-native-after.log`.
The before executable SHA-256 is
`44301cf192e224e4f1c4b2db8cf0d1d0e13becf6041fe3b0ec052004ab8c8f8d`;
after is `9c73938e313cb6a7354ecce9f694979f0757aadc800c0c17bab985fadf49f8a0`.
These native workloads add no GPU-compiler performance claim.

## Table-driven fast path

With a `fast_workspace_len()` workspace and packed (stride +1) input, output
and history bytes, each Huffman block builds two lookup tables when its trees
are read. The literal/length table has a 10-bit primary level and the distance
table an 8-bit one, each with second-level subtables for longer codes. An entry
packs the symbol's payload (literal byte or length/distance base), extra-bit
count, kind and code length into one i32, in the manner of zlib's
`inflate_fast` and libdeflate.

The loop runs while at least 8 input bytes and 258 output bytes remain. It keeps
a 64-bit bit buffer refilled by one unaligned word load, decodes up to three
literals per refill, and copies matches a word at a time when the distance is
8 or more (a repeated-byte word at distance 1, bytes otherwise). Matches older
than the current call read from the ring as it stood when the call began; the
ring is updated in bulk on exit. Stored blocks copy whole runs by word.

On an unused code or a distance beyond the history it rewinds to the start of
the symbol and returns to the bit-serial decoder, which reports the same error
with the same progress. On exit it hands back unconsumed whole input bytes, so
read counts and retained bit state match the bit-serial decoder. A
[gzip workspace](extended-compression.md) of `ext::compression::fast_workspace_len()`
(10,691) also holds slicing-by-8 CRC-32 tables.

### Measurements

Measured on the Linux x86_64 laptop (load average 14–21), compiled with the shared
`lcc` of 2026-10-31. Each figure is the median of five processes of a
streaming stdin-to-stdout program with 64 KiB input and 256 KiB output
buffers and direct `std::fs` reads and writes. Every output was compared with
the original bytes.

| Input | Decoded bytes | 707 words (before) | Fast path (after) | `gzip -d` |
| --- | --- | --- | --- | --- |
| docs/stdlib tar, gzip -6 | 18,145,280 | 3.00 s (6.0 MB/s) | 0.20 s (91 MB/s) | 0.07 s (259 MB/s) |
| text tar, gzip -6 | 13,281,280 | 1.98 s (6.7 MB/s) | 0.16 s (83 MB/s) | 0.05 s (266 MB/s) |
| 50 MB zeros, raw | 50,000,000 | | 0.03 s | |
| 20 MB random (stored), raw | 20,000,000 | | 0.02 s | |
| 10 MB literal-heavy, raw | 10,000,000 | | 0.24 s (42 MB/s) | |

Literal-heavy data is the slowest case: each literal still costs a table load,
a byte store and the loop's bounds checks. Through `std::stream` descriptors,
which stage 1 KiB at a time with a byte loop, the same corpus took 2.97 s
before; the [`tgz` tool](extended-pax.md) therefore reads and writes packed
buffers through `std::fs` directly.

The fast path was checked against Python zlib and gzip by the
[tgz oracle](../tests/fixtures/extended/tgz_oracle.py) (4,160 cases, 0
failures, including 680 corrupted, truncated or trailer-flipped streams and the 98 MiB
`czf | xzf` pipeline) and by the resumable-decoder model above rebuilt with a
10,691-element workspace (1,925 cases, 2,236 passes, every byte split, eight
stride layouts, 0 failures).

## Atomic file application and evidence

The [decompress_file application](extended-decompress-file.md), invoked as
`decompress_file --format raw|zlib|gzip INPUT OUTPUT`, uses fixed
input/output/history/workspace storage and writes decoded chunks only into a
temporary file. It validates complete format, trailer and EOF, then closes
input successfully before committing through [AtomicFile](stdlib-atomic-files.md).
NoReplace protects an existing destination. There is no whole-input or
whole-output staging.

The application profile bounds compressed input to 16 MiB, output to 64 MiB,
members to 1,024, read attempts to 32,768, decoder calls to 262,144 and atomic
write attempts to 131,072. A one-byte EOF probe at the exact input cap separates
an exact fit from excess input. Input/output buffers have 4,096 bytes each.
The namespace must remain cooperative during creation, publication and cleanup.

Before-publication errors preserve the destination. A successful rename can
still be followed by a directory-sync or cleanup failure; visibility and
durability must be reported separately. Unconfirmed rename outcomes must not
be treated as rollback. The application may retry directory sync once without
replaying commit, and retains a nonzero original primary result. Any retained
temporary is kept explicitly and its parent/name reported in hex for recovery.
It never unlinks the destination as cleanup. The separate application guide
owns exact CLI, statuses and diagnostics.

Raw source `e7acd1346f409c38d4520466f47fe3232b8a233c59556ee3d0c023ac69c8bcf3`
and framing source
`c305c1cb9e9fd332e97c0158cb3a3c0a634c4a4930b13ce50f14861ee8336452`
pass all four direct native tests in the final receipt below. The first
direct-contract scheduler could withdraw its final-input promise; its 4.79s
receipt is superseded by the corrected scheduler. Production did not change.
The earlier tiny admission overlaps the final four-test run and adds no test
count. Both resource tests and the independent model also pass. The model's
first compile attempt rejected test-fixture `View<u8>=` spacing; spacing and a
stale driver assertion were corrected without production changes. All seven
application groups also pass. Together these are 14 distinct new registered
tests. Twelve selected existing regressions also pass: five raw, five container
and two `compress_bytes` application tests. The older application's fault
campaign was not rerun. Standalone compilation and both documented examples
also pass; they add no registered test or application-case count. Older codec
receipts keep their original API/source scope. Evidence covers
chunk boundaries, exact progress/guards and sticky/reset state, independent
zlib streams, fixed workspace at multiple large sizes, reached allocation
failures and actual atomic publication outcomes.

| Receipt under `target/stdlib-work` | Accepted scope |
| --- | --- |
| `inflate-stream-admission-first.log` | 1 native test / 4.67s: exact stored-block chunk progress, inert construction, guards, unread sentinel, terminal/reset behavior and a full trace with no intervening host effects; separate Rust build 1.61s |
| `inflate-stream-direct-final.log` | 4 direct native tests / 12.02s: stored/chunk admission, raw contracts, metadata/terminal/reset preflight and container framing; full traces verify no intervening host effects |
| `inflate-stream-existing-gzip.log` | 1 selected existing container test / 6.75s: optional gzip headers, concatenated members and exact cumulative limits on current framing source |
| `inflate-stream-existing-malformed.log` | 1 selected existing container test / 6.91s: malformed/truncated framing, checksums, sizes, dictionaries and trailing input |
| `inflate-stream-existing-owned-contracts.log` | 3 selected existing container tests / 13.87s: strided views, ownership, invalid metadata, independent stored/fixed/dynamic zlib streams and advertised window validation |
| `inflate-stream-existing-app.log` | 2 selected existing `compress_bytes` tests / 10.76s: functional interoperability plus arguments, limits, members and checksums; the old fault campaign is excluded |
| `inflate-stream-existing-distances.log` | 1 selected existing raw test / 4.41s: every legal length/distance through 32,768, overlapping copies and history across blocks |
| `inflate-stream-existing-trees.log` | 1 existing raw tree test / 4.90s |
| `inflate-stream-existing-raw-malformed.log` | 1 existing raw malformed-input test / 4.53s |
| `inflate-stream-existing-raw-contracts.log` | 1 existing raw contract test / 5.00s |
| `inflate-stream-existing-differential.log` | 1 existing raw differential test / 4.68s; these four receipts plus the distance receipt cover all five existing raw groups on current source |
| `inflate-stream-resources-fixed.log` | 1 native test / 7.51s: 16 streams in two processes, 2 MiB and 4 MiB decoded outputs, fixed backing across formats/errors, complete bytes/counters and cleanup |
| `inflate-stream-resources-owned.log` | 1 native test / 6.39s: 31 processes, three baselines and 28 reached allocation failures, including malformed-header/checksum precedence and exact live allocation extent accounting |
| `inflate-stream-model-final.log` | 1 independent model test / 12.90s: 1,925 cases plus 311 reset passes, 2,236 total passes, 29,914 decoder calls and 2,626,630 output bytes across four forms/eight layouts; seed `0x1f1a7e0261107` |
| `decompress-file-model.log` | 1 application test / 10.27s: 15 native functional cases, all three formats, exact decoded output and NoReplace behavior |
| `decompress-file-boundaries-and-failures.log` | 6 application tests / 23.48s: 83 native cases across rejection 15, CLI 37, output limit 1, input limits 2, member limits 2 and faults 26, including eight reached allocation failures |
| `decompress-file-standalone-build.log` | Exact documented standalone compile exits 0 with no output |
| `decompress-file-guide-examples.log` | Both documented shell examples exit 0 with empty stdout/stderr and exact destination bytes: raw `ABC` and two-member gzip `AB` |

The fixed-workspace receipt observes the same 35,601 requested allocation bytes
at both decoded sizes: 32,769 history bytes and 708 i32 elements, including
guards. This measures the two caller-owned backing allocations, not process
RSS or stack buffers. Constructor, step and reset make no intervening
allocations; reuse preserves guards and releases backing at the end. The
owned-decoder receipt verifies that no private owner escapes its success/error
cleanup contract at the reached failures.

Initial acceptance targets native Linux x86_64 CPU output from the GPU compiler.
Other hosts, user-program GPU execution, language-enforced lifetimes, formal
verification, preset dictionaries and streaming encoding remain separate work.
The full standard/extended-library goal remains open.
