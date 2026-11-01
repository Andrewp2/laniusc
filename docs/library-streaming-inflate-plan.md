# Resumable decompression contract

The complete standard/extended-library goal remains open. This increment
replaces member replay during output growth with reusable decoder state for
raw DEFLATE, zlib and gzip. It includes the raw engine, container framing,
owned decoding, fixed-workspace tests and an atomic file decompressor.

The current source audit found that `ext::inflate::decode_into_window` keeps
partial bits, trees and match progress inside one call. `ext::compression`
restarts that decoder after every output growth. The new engine must preserve
that work across arbitrary input and output boundaries. Ordinary borrowed text
traversal, slice segmentation and iterator partition/unzip remain separate
roadmap work; this increment does not redefine overall completion.

## Sources and architecture

Format authority is [RFC 1951](https://www.rfc-editor.org/rfc/rfc1951),
[RFC 1950](https://www.rfc-editor.org/rfc/rfc1950) and
[RFC 1952](https://www.rfc-editor.org/rfc/rfc1952). The
[zlib manual](https://zlib.net/manual.html) provides a mature streaming reference.
No native codec dependency or copied external codec implementation is added.
System zlib is an independent test generator/oracle only.

Use one raw state machine in existing `ext::inflate`. Persist block/bit state,
canonical-code traversal, dynamic alphabet construction, repeat extra bits,
stored-byte count and pending literal/match copies. History spans blocks and
overlapping copies append each byte before the next lookup. Ring head and valid
history count stay bounded by the admitted window; no cumulative signed output
counter may determine ring validity.

The engine has two private history representations. Streaming uses caller-owned
ring storage. The allocation-free `decode_into` and `decode_into_window`
operations use their complete caller output as history and 707 local i32 table
entries. These remain useful whole-buffer operations; they must call the same
engine, with no second parser or 32 KiB stack/heap allocation. Never retain an
owned Vec output view across growth.

The 707 workspace entries cover lengths (320), literal counts/symbols (16/288),
distance counts/symbols (16/32) and code-length counts/symbols (16/19).
Internal construction may use a small fixed local offset table. Preserve input,
output, history and table descriptors, including their actual element stride.

## Raw public interface

```text
ext::inflate::Status { NeedInput, NeedOutput, Done }
ext::inflate::Step { read:i32, written:i32, status:Status }
ext::inflate::Failure { error:Error, read:i32, written:i32 }  // existing type

workspace_len() -> i32  // 707
decoder(history:View<u8>, workspace:View<i32>, max_distance:i32)
    -> Result<Decoder,Error>

Decoder.borrow() -> &Decoder
Decoder.step(input:View<u8>, output:View<u8>, final_input:bool)
    -> Result<Step,Failure>
Decoder.reset(max_distance:i32) -> Result<bool,Error>
Decoder.is_done() -> bool
Decoder.is_failed() -> bool
```

Windows admit powers of two from 256 through 32768. History must have at least
that many elements; workspace must have at least 707. Check complete logical
metadata and capacities before touching backing. Construction is inert apart
from storing descriptors/scalars; unused backing is not read. Extra workspace
and history tails remain untouched. Actual backing, disjoint writable storage,
lifetimes and inactive aliases are caller obligations. No allocator, host call,
implicit owner transfer or cleanup belongs to this decoder.

Each step retains no input/output view. The caller can recycle consumed input
and published output between calls; only the history/workspace borrows persist.
All counts describe this call, including failure prefixes. Output outside the
reported written prefix and input beyond the reported read prefix are untouched.
Input bytes never change. A byte counted as read can still have retained bits.
Raw completion stops at the final block and leaves trailing whole bytes unread.

`final_input` is a call-local promise that no bytes follow the offered input.
After NeedOutput, reoffer its exact unread suffix and repeat true, including
empty drain calls. The decoder does not enforce that promise across calls or
retain the input. Supplying additional bytes later or withdrawing the promise
cannot support a valid completion/truncation claim. False plus missing input
returns NeedInput; true plus required missing input returns UnexpectedEof.
Pending output drains normally before later input needs are considered.

Zero output does not immediately return NeedOutput: headers, empty blocks,
end codes and validation may proceed. NeedOutput means a confirmed literal,
stored byte or match byte requires space. A stored block checks missing input
before missing output, preserving its whole-buffer progress contract. Match
distance validation precedes output capacity. Dynamic HLIT validity is checked
after all HLIT/HDIST/HCLEN bits arrive, preserving truncation precedence.

Every step first validates input/output metadata. Invalid metadata gives
Bounds with 0/0 and changes no state, history, workspace or output, including
after completion/failure. With valid metadata, completed state returns Done
0/0; failed state returns its original error 0/0. Codec errors and final-input
truncation are permanent until reset. Bounds is recoverable. A valid reset
returns true, clears all parser/failure/completion/logical-history state and
adopts the admitted window without clearing backing. Invalid reset leaves
everything unchanged. Reset makes prior provisional decoding irrelevant.

The streaming API never reports OutputTooSmall: output suspension is NeedOutput.
The whole-buffer facade maps it to its existing OutputTooSmall error and maps
final input exhaustion to UnexpectedEof. Existing error kinds and no-overread
semantics remain. There is no preset dictionary in this increment.

Work is linear in consumed input and emitted output with bounded alphabet work
per block; calls have no wall-time guarantee. Consumers bound offered chunks,
total input/output and call counts. No hidden replay of prior chunks is allowed.

## Container interface and limits

Add to existing `ext::compression`:

```text
DecodeFailure { error:Error, read:i32, written:i32 }
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

Require 32768 history bytes and the raw workspace size. Existing Format, Limits
and Error remain canonical. Construction/reset validate nonnegative limits and
backing metadata before mutation. No ownership or allocation occurs. Container
state embeds the raw decoder and scalar framing/checksum/counter state only.
Use the same call-local final-input, metadata-first and sticky-error contracts.

Before an active step reads anything, reject an offered input span larger than
the remaining cumulative input allowance with sticky InputLimit at 0/0. Charge
only actual consumed bytes, so resubmitted tails are not counted twice. This
whole-span admission is deliberate; callers must bound their offered chunks.
Use u64 cumulative counters while respecting the existing i32 Limits domain.

Limit raw output to min(caller space, remaining cumulative output budget).
NeedOutput becomes OutputLimit only when the budget is exhausted and a real
output byte is pending. Exact-cap streams can still parse EOB and trailers.
Partial confirmed output updates checksum, size and counters exactly once even
when that call also reports an error. Returned output remains provisional until
container Done; checksum failure cannot undo bytes already delivered.

Raw and zlib await explicit final input after their body/trailer. Any further
byte is TrailingData. Gzip accepts consecutive members, resets logical history
and checksums for each, and completes only when explicit final input confirms
the sequence ended. No concatenation is inferred for raw or zlib. Members()
counts completed bodies for raw and checksum/size-validated members for framed
formats, even while waiting for final EOF. Initial empty gzip input is truncated.

Retain existing framing profile: complete fixed headers/trailers before their
semantic checks; zlib dictionary IDs are fully read before UnsupportedDictionary;
gzip optional extra/name/comment fields and FHCRC span calls; each member checks
CRC32 and wrapping-u32 ISIZE. Subsequent gzip magic retains explicit trailing
data classification before member-limit admission; split prefixes must not
silently alter that classification. After a complete member, a lone nonfinal
0x1f waits for input. At final input it yields MemberLimit if that allowance is
exhausted, otherwise Truncated; a supplied second byte other than 0x8b is
TrailingData. Empty distance alphabets are valid until
a length/distance pair requires one; reserved symbols fail when used.

Replace owned decode's replay loop with one allocation of ring/workspace and
geometric output growth around this same framing state. Rebuild transient views
after growth. Complete input/limit metadata admission stays before allocation;
fixed workspace may now fail before later format validation. Document and test
that allocation-order change. On success only the returned Vec remains live;
on failure all private owners are released and no output owner escapes. Keep
encoding behavior and implementation unchanged. Remove superseded decode loops.

## Atomic file application

Add `decompress_file --format raw|zlib|gzip [--] INPUT OUTPUT`, with `-f`,
`-h`/`--help`, canonical Intermixed parsing, duplicate rejection and validated
help that waives missing required fields. Bound argv to 16/8192, paths to
1..4095 raw bytes and final output component to 1..255 bytes, excluding dot,
dot-dot and trailing slash. Use an explicit output parent/leaf split.

Open a regular input read-only/no-follow/nonblocking and verify metadata. Open
the output parent directory with no-follow/nonblocking under a cooperative
namespace contract. Use fixed 4096-byte input/output buffers, 32768 history
bytes and 707 i32 workspace entries. Bound compressed input to 16 MiB, decoded
output to 64 MiB, gzip members to 1024, read attempts to 32768, decoder calls to
262144 and atomic write attempts to 131072. Interrupted work spends attempts.
At the exact compressed cap, one real-byte EOF probe distinguishes exact EOF
from excess input. No whole input/output staging is allowed.

Create AtomicFile with NoReplace, 32 name attempts, 128 entropy attempts and
two directory-sync attempts. Existing destinations remain protected. Close the
caller's parent after the atomic owner has duplicated it. Write decoded chunks
only to the temporary. Validate complete format/trailers/EOF, then close input
successfully before a single commit. Data failure or input-close failure aborts
publication. A published vacant destination can still accompany later sync or
cleanup failure: report actual visibility and durability, not rollback.

Preserve existing AtomicFile recovery obligations. Retry directory sync at most
once after Published-but-unsynced; keep the original nonzero primary result.
If cleanup retains a temporary name, preserve its raw name, explicitly keep it
and retire the remaining owner; report parent/name in hex so the caller can
recover it. Never replay rename/commit/close or unlink the destination.
Diagnostics distinguish visibility, synchronization and recovery state, using
bounded stderr writes. Successful execution has empty stdout/stderr.

Exit status: 0 success/help; 2 usage/codec/limits/EEXIST; 3 input/open;
4 allocation; 5 output failure before publication; 6 published but unsynced;
7 unconfirmed visibility; 8 cleanup/recovery. Diagnostic failure does not
replace an earlier primary error. A failed help write returns output status 5.
Freeze literal help and diagnostic spelling with the app/test owners.

## Verification and ownership of work

Root alone runs compiler/Cargo/native commands, serially under the library lock,
each command under two minutes. Eight agents own raw engine, framing/owned
integration, direct contracts, independent chunk model, application, resource
and application tests, documentation, and independent review. No compiler,
IR, ABI, extractor, proof or protected vector/memory edits belong here.

Start with the tiny stored-stream admission. Then verify persistent fields and
matches, exact progress/guards, reset and sticky errors, both byte storage
layouts, malformed/truncated streams and framing boundaries. The independent
oracle generates/validates streams with zlib, explicitly loops gzip members
and rejects unused trailing bytes. Do not equate zlib prefetch with this API's
per-call consumed counts; use analytical witnesses and accounting properties.

Resource gates require fixed workspace, no allocation during step/reset, exact
partial-construction cleanup, reached allocation failures and live-owner reuse.
Compare full multi-megabyte outputs and fixed peak workspace at two sizes.
Application faults must separate pre-publication preservation, Published errors,
Unconfirmed visibility and skipped-close injection limitations. Run focused
existing raw/container/application regressions because their decoder changes.
Keep a retained pre-change executable for a focused native decode comparison;
do not run broad GPU/performance suites or claim cross-compiler performance.

Initial supported target is native Linux x86_64 CPU output from the GPU compiler.
Other targets, device execution, language-enforced lifetimes, formal verification,
preset dictionaries and streaming encoding remain separately tracked work.
