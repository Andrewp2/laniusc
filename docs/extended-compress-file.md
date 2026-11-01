# Compress into a new file

`sample_programs/library/compress_file.lani` encodes a regular file as raw
DEFLATE, zlib or gzip using the [resumable encoder](extended-streaming-deflate.md).
Fixed buffers hold input, output and codec state. An AtomicFile temporary keeps
partial output private until encoding, actual EOF and input close succeed.
`NoReplace` preserves an existing destination. All five application groups/99
native cases pass, including nine reached allocation denials. Standalone
compilation and both examples pass separately.

## Build and examples

From the repository root with the compiler binary built:

```sh
mkdir -p target/stdlib-work
timeout --kill-after=2s 100s flock -w 95 target/stdlib-work/library-gpu.lock \
  target/stdlib-build/debug/laniusc --stdlib-root stdlib --source-root extended \
  --emit x86_64 sample_programs/library/compress_file.lani \
  -o target/stdlib-work/compress_file
```

Raw `ABC` encodes as the five bytes `73 74 72 06 00`:

```sh
example_dir=$(mktemp -d target/stdlib-work/compress-example.XXXXXX)
printf 'ABC' > "$example_dir/input.bin"
target/stdlib-work/compress_file --format raw -- \
  "$example_dir/input.bin" "$example_dir/output.raw"
```

A binary gzip example can be checked by the independent host decoder:

```sh
example_dir=$(mktemp -d target/stdlib-work/compress-example.XXXXXX)
printf '\000A\377B\n' > "$example_dir/input.bin"
target/stdlib-work/compress_file -fgzip \
  "$example_dir/input.bin" "$example_dir/output.gz"
gzip -dc "$example_dir/output.gz" | cmp - "$example_dir/input.bin"
```

Successful compression writes no stdout or stderr. Each example uses a fresh
directory; repeating it with an existing output must reject without replacing
that output. The exact standalone build and both examples passed. They are
separate smoke receipts, not additional application test cases.

## CLI and paths

The syntax is `compress_file --format raw|zlib|gzip [--] INPUT OUTPUT`.
`-f FORMAT` and attached `-fFORMAT` are accepted. Intermixed option parsing
allows options among operands; `--` ends option parsing. Duplicate options,
unknown case-sensitive formats and extra operands reject before file opens.
`-h`/`--help` waive missing required arguments but validate everything supplied,
including an output component. Help does not open files.
Its exact text contains 1,188 bytes.

The argument snapshot excludes argv[0] and allows 16 entries/8,192 raw bytes.
Paths use 1..4,095 bytes without NUL; UTF-8 is not required and `-` is a literal
filename. The output is split at its last slash without normalization. Its
final component must be 1..255 bytes, cannot be `.` or `..`, and cannot follow
a trailing slash. A bare filename uses `.` as its existing parent directory.

Input opens read-only, close-on-exec, no-follow, nonblocking and without a
controlling terminal. Metadata must identify a regular file before temporary
creation. The output parent opens as a directory with the same flags.
No-follow applies to the final opened component; ancestor resolution follows
host rules. The program requires a cooperative, stable local Linux namespace,
creates no parent directories, copies no metadata and is not a hostile-path
sandbox. Existing files, directories and symlinks are never replaced. If
INPUT and OUTPUT name the same inode, publication rejects and preserves it.

## Fixed storage and limits

Five vectors hold 4,096 input bytes, 4,096 output bytes, 32,768 block bytes,
32,773 pending bytes and 32,768 i32 scratch elements. They are initialized
before file opens and remain fixed during encoding. Encoder state borrows its
workspace; consumed input can be overwritten, and each encoded chunk is
written to the temporary before its output buffer is reused.

| Resource | Bound |
| --- | ---: |
| Input bytes | 67,108,864 (64 MiB) |
| Compressed bytes, including framing | 68,157,440 (65 MiB) |
| Input read attempts, including EOF/probes/Interrupted | 131,072 |
| Encoder steps | 262,144 |
| Atomic payload write attempts, including Interrupted | 131,072 |
| Temporary name attempts / entropy calls | 32 / 128 |
| Directory sync attempts | 2 |
| Help attempts / diagnostic attempts | 64 / 64 |
| Diagnostic storage / recovery-name storage | 9,000 / 37 bytes |

File read requests use at most 4,096 bytes and the remaining input allowance;
the current File provider transfers at most 1,024 bytes per call. At exactly
64 MiB, a real one-byte probe must return EOF; an extra byte rejects. The read
budget leaves room for that probe and retries. An interruption consumes a call
and retries; other read errors abort. Opens and closes are not retried.

The compressed-output cap is defensive. The stored alternative bounds the
64 MiB input to at most 67,119,124 bytes including the final empty block and
gzip framing, below 65 MiB. No independently reachable output-byte rejection
is claimed under this profile. Byte/call limits do not bound elapsed time or
a blocking host operation.

Only NeedInput allows a fresh input read. NeedOutput resubmits the exact unread
suffix; confirmed EOF sets `final_input=true` on every later drain call.
Success requires Done, complete input consumption and matching encoder/file
totals. A failed step's output is discarded; earlier temporary bytes remain
unpublished. Empty input produces a complete empty stream/member.

## Publication, cleanup and recovery

After workspace initialization, the program opens/validates input, opens the
output parent and creates the AtomicFile. Creation copies the output component
and duplicates its parent descriptor. The caller's parent is closed before
encoding; a close failure prevents publication. Input is closed exactly once,
including failure paths. Encoding completion and successful input close must
precede the single commit attempt.

Commit syncs and closes the temporary, performs one NoReplace rename, records
visibility and syncs the directory. An existing destination rejects without
replacement. [AtomicFile](stdlib-atomic-files.md) reports `not-published`,
`published` or `unconfirmed`; a nonzero result can accompany an already visible
new file. There is no rollback or universal crash-durability promise.

A Published but unsynced result with a retained directory permits one explicit
directory-sync retry. Commit/rename never repeat, and the original error status
survives a successful retry. Cleanup retains close/removal facts. If removal
leaves an owned temporary name, the program copies its 37 bytes, calls `keep`
to accept recovery duty, then cleans up remaining descriptors/backing. It
reports the parent and name in hex. That name identifies accepted recovery
duty, not proof that an ambiguous rename left a file there. Cleanup never
unlinks OUTPUT or uses the input path as a deletion target.

The five vectors retire after execution/recovery. Arguments remain live while
rendering any recovery parent, then retire before diagnostics. Owners and
descriptors require explicit single cleanup authority; trap recovery and
compiler-enforced lifetimes are outside this contract.

## Status and diagnostics

| Exit | Meaning |
| ---: | --- |
| 0 | Complete publication or help |
| 2 | Usage, codec/limits or existing output |
| 3 | Input, metadata, parent-open or input-close failure |
| 4 | Allocation failure |
| 5 | Output failure before publication, help output or SIGPIPE setup failure |
| 6 | Published but directory sync failed, retained even after successful retry |
| 7 | Unconfirmed publication visibility |
| 8 | Cleanup/recovery failure without an earlier primary failure |

The first operational failure survives cleanup and diagnostic failure.
Caller-parent close failure is status 8; temporary close during commit is 5.
A cleanup failure after successful publication/sync is 8. SIGPIPE-ignore setup
failure returns 5 silently. Other failed invocations attempt one LF-terminated
line with these fields in order:

```text
compress_file: code=N phase=WORD visibility=VISIBILITY file_synced=B directory_synced=B cleanup_failed=B retained=B recovery_parent_hex=HEX|- recovery_name_hex=HEX|-
```

N is the status; B is `0` or `1`. Phase is `arguments`, `input-open`,
`input-metadata`, `parent-open`, `workspace`, `encoder`, `temporary-create`,
`parent-close`, `input-read`, `encode`, `write`, `input-close`, `commit`,
`cleanup` or `help`. Lowercase hex identifies a kept recovery name; otherwise
both hex fields are `-`. `retained` describes current AtomicFile resources
after cleanup, not whether a kept name exists. `cleanup_failed` preserves an
observed cleanup error even after later retirement. Broken stderr can obscure
these facts while preserving the primary status.

## Evidence and remaining scope

Source is frozen at
`671688abd9e4d5dce68ca0f7500414f158ad9f23358f9d39ea382d0a35381c7d`.
Standalone compilation passed with exit 0 and an empty log
(`target/stdlib-work/streaming-deflate-cli-build.log`). Both exact guide examples
passed in `streaming-deflate-cli-examples.log`: raw `ABC` produced the five
specified bytes; the five-byte binary input produced 25 gzip bytes, decoded
independently by GNU gzip and zlib. Both invocations were quiet, preserved input
and retired temporary names. The independent model passes 17 native cases in
one test, 11.07 seconds after a separate 1.14-second Rust build
(`target/stdlib-work/streaming-deflate-tool-model.log`). CLI/path admission
passes 39+9 cases together in two tests, 8.58 seconds after a 0.21-second build
(`streaming-deflate-tool-admission.log`). The two 64 MiB boundary cases pass
in one test, 36.15 seconds after a 0.18-second build
(`streaming-deflate-tool-limits.log`). Those traces observe 65,536 successful
1,024-byte reads followed by the actual one-byte EOF/excess probe. The final
fault group passes 32 cases in one test, 17.27 seconds after a 0.19-second build
(`streaming-deflate-tool-faults.log`). All logs are under `target/stdlib-work/`.

| Group | Native cases |
| --- | ---: |
| Independent model | 17 |
| Input/path kinds | 9 |
| CLI | 39 |
| Exact input cap/excess | 2 |
| Faults/recovery, including nine reached allocation denials | 32 |

The fault group counts one successful baseline, a failed-write control and
each reached denial once. Allocation/descriptor ledgers check exact cleanup,
fixed owners during streaming, EOF/input close before publication, complete
published output after late failures, directory-sync retry and the exact
compressed prefix in a retained recovery file. Injected close errors skip the
kernel close: those cases establish attempted cleanup and logical retirement,
not release by a skipped call. Normal paths require successful closes.

All cases retain read/write events. Large/cap cases abbreviate string payloads
to 64 bytes while full request/result counts remain visible. The finite trace
filter covers 15 syscalls, not every possible
host effect. Continuous read/write interruption reaches the respective
131,072-attempt ceilings. The write campaign also denies all 64 diagnostic
attempts: it observes full `code=2 phase=write` requests and final status 2,
without proving successful delivery of that specific limit diagnostic.
The defensive output cap, encoder-step bound, isolated help/diagnostic caps,
argument-capture host-read failure and same-process application retry are not
separately claimed as executed paths.
The [application fixture guide](../tests/fixtures/stdlib_compress_file/README.md)
defines the independent decoder, fixed-owner/publication ledger and accepted
failure observations. Host controls add no native cases.
Before execution, the read budget was raised from 65,536 to 131,072 after
checking the provider's 1,024-byte call cap: the original bound could not read
64 MiB and also observe EOF. This was a source/contract correction, with no
failed runtime receipt or compiler change.
The accepted target is Linux x86_64 CPU output from the GPU
compiler on the supported local filesystem profile. Earlier decompressor and
AtomicFile receipts do not establish this compressor. The
[library guide](extended-streaming-deflate.md) records codec evidence separately.
Other hosts, device execution, hostile namespaces, exhaustive failures,
automatic cleanup and formal proofs remain separate work.
