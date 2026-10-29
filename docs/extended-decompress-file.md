# Decompress into a new file

`sample_programs/library/decompress_file.lani` decodes raw DEFLATE, zlib or gzip
from one regular file into a new output file. It uses the resumable decoder
with fixed input, output and codec storage. Decoded bytes stay in an owned
temporary file until complete validation and successful input close permit
publication. Existing output names are protected by atomic `NoReplace`.

The seven application groups passed 98 native process cases. The exact
standalone compiler command and both shell examples below also passed, with
separate receipts recorded under acceptance.

## Build and examples

From the repository root with the compiler binary built:

```sh
mkdir -p target/stdlib-work
timeout --kill-after=2s 100s flock -w 95 target/stdlib-work/library-gpu.lock \
  target/stdlib-build/debug/laniusc --stdlib-root stdlib --source-root extended \
  --emit x86_64 sample_programs/library/decompress_file.lani \
  -o target/stdlib-work/decompress_file
```

This raw stored block decodes to exactly `ABC` without a final newline:

```sh
example_dir=$(mktemp -d target/stdlib-work/decompress-example.XXXXXX)
printf '\001\003\000\374\377\101\102\103' > "$example_dir/input.raw"
target/stdlib-work/decompress_file --format raw -- \
  "$example_dir/input.raw" "$example_dir/output.bin"
```

The next input contains two complete gzip members. The output is exactly the
two bytes `AB`, with no newline:

```sh
example_dir=$(mktemp -d target/stdlib-work/decompress-example.XXXXXX)
printf '\037\213\010\000\000\000\000\000\000\377\001\001\000\376\377\101\213\236\331\323\001\000\000\000\037\213\010\000\000\000\000\000\000\377\001\001\000\376\377\102\061\317\320\112\001\000\000\000' > "$example_dir/input.gz"
target/stdlib-work/decompress_file -fgzip \
  "$example_dir/input.gz" "$example_dir/output.bin"
```

Both successful invocations leave stdout and stderr empty. Each example creates
a fresh directory because repeating a command with an existing output returns
an error and preserves that output.

## CLI and filesystem profile

The CLI is `decompress_file --format raw|zlib|gzip [--] INPUT OUTPUT`.
`-f FORMAT` and attached `-fFORMAT` select the format. `--help` and `-h` show
help, waiving missing required options and operands while validating everything
supplied. Canonical `ext::cli` Intermixed parsing accepts options among operands
and `--` terminates option parsing. Duplicate options, unknown formats and
extra operands reject before opening files. Format names are case-sensitive.

Arguments are bounded to 16 entries and 8192 raw bytes, excluding argv[0] and
terminating NULs. Each supplied path is 1..4095 bytes without NUL. UTF-8 is not
required, and `-` is a literal filename. The output path is split at its last
slash without normalization. Its final component must contain 1..255 bytes
and cannot be `.` or `..`; a trailing slash rejects. A bare output filename
uses `.` as its parent. Help also validates a supplied output component.

The input opens read-only with close-on-exec, no-follow, nonblocking and no
controlling terminal. Descriptor metadata must identify a regular file before
temporary creation. The existing output parent opens as a directory with the
same flags. No-follow checks the final component of those opens; it is not a
promise to reject symlinks in every ancestor. Parent path resolution follows
the host rules.

The output namespace must be cooperative and stable through creation,
publication and cleanup, on the supported local Linux filesystem profile.
The program is not a hostile-directory sandbox. It does not create missing
parent directories, copy metadata or replace an existing file, directory or
symlink. Input and output may name the same file, but `NoReplace` then rejects
publication without changing its bytes. The input path is never used as a
cleanup deletion target.

## Streaming and bounds

The application allocates four fixed vectors: 4096 input bytes, 4096 output
bytes, 32768 history bytes and 707 `i32` workspace entries. The container
decoder borrows history and workspace for its lifetime. Individual steps retain
no input or output view. The application reuses consumed input storage and
flushes each confirmed output chunk into the AtomicFile temporary before
reusing its output buffer. It never holds the complete compressed input or
decoded output in memory.

| Resource | Bound |
| --- | ---: |
| Compressed bytes | 16,777,216 |
| Decoded bytes | 67,108,864 |
| Gzip members | 1024 |
| File read attempts, including EOF and Interrupted | 32768 |
| Decoder step calls | 262144 |
| Temporary payload write attempts, including Interrupted | 131072 |
| Temporary candidate names / entropy calls | 32 / 128 |
| Directory sync attempts | 2 |
| Help stdout attempts / diagnostic stderr attempts | 64 / 64 |
| Diagnostic storage | 9000 bytes |

Read requests are at most 4096 bytes and the remaining compressed allowance.
At the exact allowance the application makes a one-byte probe: EOF accepts the
byte bound, while a real extra byte rejects. The current native File provider
transfers at most 1024 bytes per host call. Read interruptions spend attempts
and retry. Other read errors abort; opens and closes are never retried.

After `NeedOutput`, the exact unread input suffix is offered again with fresh
output capacity. Draining pending output does not force an input read. Only
`NeedInput` permits refilling an exhausted input chunk. A real host EOF makes
`final_input` true, including later empty drain calls. Success requires decoder
Done, all offered input consumed and matching cumulative input/output counts.
Raw and zlib reject trailing bytes; gzip validates all consecutive members,
including every trailer checksum and size. Empty or truncated encodings reject
according to the container contract. Raw DEFLATE supplies no checksum.

The final step's provisional output is discarded when that step fails.
Earlier decoded chunks may already be present in the temporary, but they are
never published after a codec, limit, input or input-close failure. Interrupted
temporary writes retry under AtomicFile's cumulative allowance. Bounds limit
bytes and attempts, not elapsed time or blocking host calls.

## Publication and recovery

After argument validation, the four vectors are allocated and the decoder is
initialized. The program opens and validates input, opens the output parent
and creates an AtomicFile. Creation copies the destination component and
duplicates the parent descriptor. The caller's parent descriptor is then
closed; a failure prevents decoding and publication. Input is closed exactly
once after decoding, including failures. Successful complete decoding and
successful input close are required before the one commit attempt.

Commit syncs the temporary file, closes it, performs one `NoReplace` rename,
records publication and syncs its directory. An existing destination yields
EEXIST without replacement. Other failures have the visibility reported by
[AtomicFile](stdlib-atomic-files.md): `not-published`, `published` or
`unconfirmed`. A newly published file can accompany a later sync or cleanup
failure. A nonzero status therefore does not establish that a vacant output
name remains vacant, or that publication was rolled back.

For a Published but unsynced result with a retained directory descriptor, the
application makes at most one explicit directory-sync retry. It never repeats
commit or rename and keeps the original nonzero primary status even if the
retry succeeds. Diagnostics report the current sync and visibility facts.

The application calls cleanup and observes its accumulated close/removal
results. If an owned temporary name remains after unsuccessful removal, it
copies the 37-byte name, calls `keep` to accept that recovery duty and calls
cleanup once more to retire the remaining descriptor and backing storage.
The recovery parent and component are reported as hexadecimal bytes. This
names an accepted residue for manual inspection; it does not prove that an
ambiguous rename left a file at that name. Cleanup never unlinks OUTPUT.

The four vectors are released after execute/recovery returns. Arguments remain
live long enough to render any parent path into the fixed diagnostic buffer,
then are released before stderr publication. Every normal execution has one
active owner per allocation or descriptor. These are manual lifetime rules;
trap recovery and language-enforced ownership are not established here.

## Status and diagnostic grammar

| Exit | Meaning |
| ---: | --- |
| 0 | Successful complete publication or help |
| 2 | Usage, codec, limits or existing output |
| 3 | Input, metadata, parent open or input-close failure |
| 4 | Allocation failure |
| 5 | Output failure before publication, help output or SIGPIPE setup failure |
| 6 | Published but directory sync failed; retained after a successful retry |
| 7 | Unconfirmed publication visibility |
| 8 | Cleanup/recovery failure without an earlier primary failure |

The first operational failure is retained through cleanup. Caller-parent close
failure is cleanup status 8. A temporary-file close failure during commit is
output status 5; later cleanup facts remain visible. A Published cleanup failure
after a successful directory sync is status 8. Diagnostic failure never replaces
an existing nonzero status. SIGPIPE is ignored before argument capture; policy
setup failure returns 5 silently. Help output failure returns 5.

Every other failed invocation attempts one LF-terminated line with fields in
this exact order:

```text
decompress_file: code=N phase=WORD visibility=VISIBILITY file_synced=B directory_synced=B cleanup_failed=B retained=B recovery_parent_hex=HEX|- recovery_name_hex=HEX|-
```

N is the exit code. B is `0` or `1`. VISIBILITY is `not-published`, `published`
or `unconfirmed`. WORD is one of `arguments`, `input-open`, `input-metadata`,
`parent-open`, `workspace`, `decoder`, `temporary-create`, `parent-close`,
`input-read`, `decode`, `write`, `input-close`, `commit`, `cleanup` or `help`.
The phase identifies the primary failure. Hex fields use lowercase byte pairs
only when a temporary recovery name was kept; otherwise both are `-`.
`retained` reports AtomicFile's current resource flag after cleanup, not whether
a kept filesystem name may still exist. `cleanup_failed` preserves an observed
cleanup error even if subsequent retirement succeeds. A broken stderr can
truncate or obscure recovery diagnostics. Help contains exactly 1182 bytes.

## Acceptance

The actual application entry compiled through the GPU compiler to a native
Linux x86_64 executable, admitted by the strict ELF64 and shared jump checks.
All **98 native process cases** passed across seven registered groups. The
first model selector passed in 10.27 seconds with six tests filtered
(`target/stdlib-work/decompress-file-model.log`); the remaining six selectors
passed together in 23.48 seconds with that model test filtered
(`target/stdlib-work/decompress-file-boundaries-and-failures.log`). These are
two test commands, not a single combined seven-test receipt.

| Group | Process cases | Retained evidence |
| --- | ---: | --- |
| Model | 15 | `/tmp/decompress-file-model-yj2zk9t3` |
| Rejection | 15 | `/tmp/decompress-file-rejection-tsfm0ax3` |
| CLI | 37 | `/tmp/decompress-file-cli-wv9k0vgi` |
| Compressed-input limits | 2 | `/tmp/decompress-file-input_limits-ro9cwzzq` |
| Member limits | 2 | `/tmp/decompress-file-member_limits-21pydl8a` |
| Decoded-output limit | 1 | `/tmp/decompress-file-output_limit-vus2pk5i` |
| Faults and recovery | 26 | `/tmp/decompress-file-faults-zxrgpo1v` |

Independent host zlib inputs cover all three formats, empty and binary data,
stored/fixed streams, concatenated gzip and complete 4 MiB output. Malformed
headers, bodies, checksums, sizes, truncation and trailing data reject without
replacing the existing destination. Rejection cases also check input/parent
path kinds. The CLI group checks the exact help, validation before opens,
aliases and diagnostic failure behavior. Existing destination inode and
contents are checked.

The compressed-cap traces require a final one-byte request returning zero or
one after exactly 16 MiB of confirmed prior input reads. Member cases accept
1024 and reject 1025 empty gzip members. Decoding 64 MiB plus one byte rejects
publication. Full traces require observed EOF and successful input close before
temporary-file sync, followed by temporary close and at most one NoReplace
rename. Directory sync follows confirmed rename. Large output/member cases
omit read/write payload tracing, so they establish output, limits, ownership
and publication outcomes without claiming observed EOF or transfer counts.

The 26 fault processes include one counted successful baseline and a counted
failed-write control. Eight ENOMEM injections reach every allocation in that
selected baseline, matching its complete allocation-argument prefix and
retiring each earlier mapping at its observed address and extent. Additional
faults cover opens, reads, writes, input/parent/temporary/anchor close, file and
directory sync, and rename. Published sync failures preserve the complete new
file and status 6 even after successful retry; an injected ambiguous rename
reports Unconfirmed. A real first temporary write followed by write and unlink
failures leaves exactly its confirmed prefix in the kept recovery file, whose
name and parent match the diagnostic hex fields.

Injected close errors skip the kernel close, so those cases establish attempted
cleanup, logical retirement and publication behavior rather than successful
kernel release by the skipped call. Normal paths require successful closes.
The full mapping/descriptor ledgers and negative host controls are finite
observations, not exhaustive lifetime or crash proofs. The
[application fixture guide](../tests/fixtures/stdlib_execution/decompress_file/README.md)
records exact scopes and commands.

Accepted producer identities (SHA-256):

- Application: `3143c960baaa3993ded0a4b38c213b7f21e9d81ff92ae7105a8369160bbedac7`.
- Oracle: `73def8efaff1e46cdd5f728c56e97e443ccc1a51b7afc2fc01421c7bb96ba119`.
- `ext::inflate`: `e7acd1346f409c38d4520466f47fe3232b8a233c59556ee3d0c023ac69c8bcf3`.
- `ext::compression`: `c305c1cb9e9fd332e97c0158cb3a3c0a634c4a4930b13ce50f14861ee8336452`.
- `std::atomic_file`: `9e0a970995d68f4c3ac1c1f2d307438d07796bee978affee694423b0d543af34`.

The exact standalone compiler command above exited 0 with no diagnostic output
(`target/stdlib-work/decompress-file-standalone-build.log`). Both literal guide
examples then ran against `target/stdlib-work/decompress_file`: the raw example
produced exactly the three bytes `ABC`, and concatenated gzip produced exactly
the two bytes `AB`. Byte comparisons passed, with empty stdout and stderr
(`target/stdlib-work/decompress-file-guide-examples.log`). These overlapping
examples add no cases to the 98-process corpus.

Library evidence belongs in the
[streaming decoder guide](extended-streaming-inflate.md). Other targets, user
GPU execution, hostile-directory guarantees, exhaustive faults, crash durability
and formal verification require separate evidence. Host zlib/gzip are test
references only; production uses Lanius codec and filesystem APIs.
