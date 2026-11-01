# Atomic decompressor application tests

The driver compiles `sample_programs/library/decompress_file.lani` to a strict
ELF64 x86-64 executable and applies the shared native jump check. Python zlib
independently creates raw DEFLATE, zlib and gzip inputs and validates the expected
bytes. Each native process runs in its own directory against real input and
output files. The application uses the production borrowed decoder and
`AtomicFile` with `NoReplace`.

## Corpus

| Oracle group | Native process cases | Main evidence |
| --- | ---: | --- |
| `model` | 15 | Empty/binary/stored/fixed streams in all three formats; concatenated gzip; full 4 MiB output; existing destination preserved |
| `rejection` | 15 | Bad headers, bodies, checksum, size, truncation and trailing bytes; missing, directory and symlink inputs; symlink output parent |
| `cli` | 37 | Invalid/duplicate/missing options and bounds, help validation before opens, aliases/intermixed arguments, broken help output, failed diagnostic, signal setup failure |
| `input_limits` | 2 | Exactly 16 MiB compressed input and one excess byte, including the actual one-byte EOF/excess read |
| `member_limits` | 2 | 1,024 empty gzip members accepted; 1,025 rejected |
| `output_limit` | 1 | 64 MiB + 1 decoded bytes rejected without replacing the old destination |
| `faults` | 26 = 18 + 8 | One success baseline, all 8 baseline-reached allocations, open/read/write/close/sync/rename failures, directory-sync retry, retained recovery prefix |

The fixed groups contain **72 native process cases**. The fault group measures
A from its real baseline and reports it; the accepted run measured **A = 8**.
No guessed allocation ordinal is used.
Its 18 ordinary processes include the baseline and a separate failed-write
control used to locate cleanup unlink. They are each counted once. Python
generators, CPU controls, and compiler invocations are not native case counts.

## Resource, ordering and publication assertions

The trace parser tracks full-width addresses with exact allocation/release
extents and descriptor ownership through input, caller parent, duplicated anchor
and temporary file. It rejects unpaired owners and descriptor reuse while live.
Diagnostics and help must be emitted after owned mappings and descriptors are
retired. Input opens require read-only/no-follow/nonblocking behavior; parent
opens require directory/no-follow/nonblocking behavior. Temporary creation must
use exclusive creation and a valid generated name, never truncate a destination.

On full read traces, publication requires observed input EOF followed by input
close, then successful temporary-file sync and temporary close, followed by one
`renameat2(RENAME_NOREPLACE)` at most. Directory sync must follow confirmed
publication. The exact compressed-cap cases retain read tracing and require a
final request of one byte returning zero or one after exactly 16 MiB of prior
confirmed reads. Large output/member cases omit read/write payload traces to
bound trace volume; those cases do not claim observed EOF or transfer counts.
They retain file sync, close, rename, allocation and release observations.

Successful publication is checked against every expected destination byte.
Rejections and prepublication failures preserve an existing destination's inode
and contents. Published failures must retain the complete new output, and the
oracle distinguishes confirmed publication from an unconfirmed rename failure.
The retained-file case performs a real first write, injects failure at the next
baseline-selected write, and fails cleanup unlink. Its actual recovery file must
contain exactly the prefix confirmed by that first write. Its diagnostic must
name the captured temporary file and parent in hexadecimal, with no retained
backing owner after cleanup.

Each injected syscall must be reached and marked as injected. Allocation fault
runs must match the complete baseline allocation argument prefix, stop allocating
at the injected failure, and retire all earlier mappings. Close-error injection
skips the kernel close: these cases prove attempted cleanup, logical retirement,
status and publication behavior, **not** that the skipped call released the
kernel descriptor. Normal paths require actual successful descriptor release.
Failed directory sync remains status 6 even when the explicit retry succeeds;
failed diagnostic output preserves the earlier primary status. There is no
status 9.

## Accepted execution

The independent host-only controls pass, including deliberately broken mapping
ledgers and publication traces missing EOF or file sync. The root runner accepted
all **7 tests and 98 native process cases**. The format/model gate passed in
10.27 seconds (Rust build 2.31 seconds); the other six groups passed together in
23.48 seconds (Rust build 0.19 seconds). No failed or calibration attempt is
included in these counts.

| Group | Log | Evidence directory |
| --- | --- | --- |
| `model` | `target/stdlib-work/decompress-file-model.log` | `/tmp/decompress-file-model-yj2zk9t3` |
| `rejection` | `target/stdlib-work/decompress-file-boundaries-and-failures.log` | `/tmp/decompress-file-rejection-tsfm0ax3` |
| `cli` | same boundaries/failures log | `/tmp/decompress-file-cli-wv9k0vgi` |
| `input_limits` | same boundaries/failures log | `/tmp/decompress-file-input_limits-ro9cwzzq` |
| `member_limits` | same boundaries/failures log | `/tmp/decompress-file-member_limits-21pydl8a` |
| `output_limit` | same boundaries/failures log | `/tmp/decompress-file-output_limit-vus2pk5i` |
| `faults` | same boundaries/failures log | `/tmp/decompress-file-faults-zxrgpo1v` |

The accepted application source SHA-256 is
`3143c960baaa3993ded0a4b38c213b7f21e9d81ff92ae7105a8369160bbedac7`.
The accepted oracle SHA-256 is
`73def8efaff1e46cdd5f728c56e97e443ccc1a51b7afc2fc01421c7bb96ba119`.
Help is compared against the agreed 1,182-byte literal. Diagnostics are parsed
and their status, phase, visibility and ownership fields checked semantically.

The seven selectors in `tests/stdlib_decompress_file_execution.rs` invoke the
groups above separately, with an 85-second group timeout and 65-second native
process timeout. `python3 -B oracle.py controls` exercises only host controls.
Native evidence is scoped to Linux x86-64; this application requires host file
services and is not a GPU-kernel program.
