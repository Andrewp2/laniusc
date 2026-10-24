# copy-file

[`sample_programs/library/copy_file.lani`](../sample_programs/library/copy_file.lani)
copies bytes between two distinct regular files using
[`std::file_copy::copy_regular`](stdlib-file-copy.md). The program uses raw
argument snapshots, byte paths, checked descriptor opens, a fixed stack buffer,
and explicit ownership cleanup. Application logic and the copy loop are Lanius.

The application is admitted as **x86_64 Linux ELF through the GPU compiler**.
One strict-checked executable supplied 59 passing native cases. The verification
record below gives the compiler checkpoint, exact commands, logs, and scope.

## Build and use

From the repository root, with the compiler binary built:

```sh
mkdir -p target/stdlib-work/copy-file
target/stdlib-build/debug/laniusc --stdlib-root stdlib --emit x86_64 \
  sample_programs/library/copy_file.lani \
  -o target/stdlib-work/copy-file/copy-file
target/stdlib-work/copy-file/copy-file source.bin destination.bin 1048576
```

The command form is exactly three positional arguments:

```text
copy-file SOURCE DESTINATION MAX_BYTES
```

On success, DESTINATION contains the complete bytes read from SOURCE, up to
MAX_BYTES. The program emits no stdout or stderr text. The destination bytes
and the exit status are its result. There are no options, default arguments,
or special stdin/stdout path names.

## Arguments and bounds

Main snapshots at most three arguments and 8,210 total raw argument bytes,
excluding argv[0] and terminating NULs. This budget covers two 4,095-byte paths
and a 20-byte u64 decimal. Processing requires exactly three arguments. Each
path must contain 1–4,095 bytes without NUL. Filenames may contain spaces,
newlines, or invalid UTF-8; paths retain their original bytes and spelling.

MAX_BYTES is a complete unsigned ASCII u64 decimal restricted to
`0..=9223372036854775807` (`i64::MAX`). Leading zeroes are accepted. Signs,
whitespace, separators, suffixes, non-ASCII digits, missing digits, and overflow
are errors. Longer leading-zero spellings are accepted within the total
argument-byte budget. Arity, path lengths and values, decimal grammar, and the
quota range are checked before either file is opened.

Copy scratch is 1,024 packed logical bytes backed by `[i32;256]` stack storage
through `core::mem::typed_slice_from_raw_parts` and a checked `View<u8>`.
The copy operation allocates no heap storage. The argument entry vector and
packed argument bytes are the program's only heap owners.

The copy reads until an actual EOF. At exactly MAX_BYTES it makes a one-byte
EOF probe, which is never written. An extra byte yields LimitExceeded and
leaves the first MAX_BYTES bytes in DESTINATION. For quota zero, an empty source
succeeds and a nonempty source yields LimitExceeded with an empty destination.
Metadata length does not substitute for EOF, so a concurrently changed source
may yield a different stream of bytes. There is no elapsed-time bound.

## Opens and destination effects

SOURCE opens read-only with final-component no-follow, nonblocking, and
close-on-exec. DESTINATION opens write-only with create, final-component
no-follow, nonblocking, and close-on-exec. Its open omits truncation and append.
New files request mode `0666`, subject to the process umask and default ACLs.
Existing file permissions are not replaced.

Nonblocking opens avoid waiting for a FIFO peer. The library then checks access
and status flags, regular-file type, and device/inode identity before rewinding
both descriptors and truncating the destination. The same path, hard links,
and other names of the same opened file are rejected before truncation. Special
files are rejected by the library if opening them succeeds. A destination FIFO
with no reader can instead fail during its nonblocking open.

Opening may create DESTINATION before a later descriptor-policy or copy error.
After successful truncation, an error can leave an empty destination or a
copied prefix. Preexisting destination contents are discarded at that point.
The program performs no temporary-file replacement, rename, rollback, metadata
copy, locking, or synchronization. Close success does not promise durability.

Final-component symlinks are rejected for both paths. Earlier components follow
the operating system's symlink resolution; these opens do not form a filesystem
sandbox. Concurrent path changes and file mutation remain subject to Linux
semantics. The operation copies the opened descriptors, without taking an
atomic snapshot of either pathname or source contents.

## Errors and ownership

| Status | Meaning |
| --- | --- |
| 0 | Copy reached EOF within the quota, and both closes succeeded |
| 2 | Argument count, byte budget, path value/length, decimal, or quota-range error |
| 3 | Argument host-read failure, open, descriptor-policy, copy, or close error |
| 4 | Argument-snapshot allocation failure |
| 5 | Source exceeded MAX_BYTES, and both closes succeeded |

Any close failure selects status 3, including after LimitExceeded. Read and
write errors, Interrupted, WouldBlock, and close errors are returned without
retry. A short successful write is continued; zero progress is an error. The
library preserves separate consumed and written byte counts in CopyFailure;
the program reports its cause through the status without diagnostic output.

Main owns the argument snapshot and destroys it after every processing result.
Snapshot failures clean up their own partial construction. Processing borrows
a shallow argument handle, and path views remain backed until all file work
finishes. A shallow copy creates no independent owner.

Each successful open creates one active File owner. A failed destination open
still closes the source. After a copy attempt, the program closes destination
and source even if the first close fails. Each owned descriptor receives one
close attempt; close retires ownership before its host call and is never
retried. The library borrows these owners and does not close them. Only regular
files reach writes, so the program does not change process signal policy.

## Application verification

[`tests/stdlib_copy_file_execution.rs`](../tests/stdlib_copy_file_execution.rs)
contains the accepted test
`copy_file_bytes_arguments_policies_and_exact_failure_cleanup`. It compiled the
real sample once through the production stdlib root, passed the unchanged
strict shared ELF/jump checker through `common::TempArtifact`, and reused that
executable for all 59 native cases. Each native process has a five-second
timeout. A separate bounded `mkfifo` command prepared the FIFO cases.

The test passed in **5.63 s**, including GPU compilation and native tracing.
The Rust driver build completed in **1.20 s**. Compiler sources were unchanged
from checkpoint `59612b3431d7b0cdff16a6faecf881f62a675503`; application, stdlib
integration inputs, and the driver were frozen during the gate. Both commands
below returned exit status zero.

| Native cases | Count | Checked behavior |
| --- | --- | --- |
| Binary copies | 12 | Sizes 0, 1, 1023, 1024, 1025, and 4097, each with a new destination and an existing destination with a longer tail |
| Quotas | 4 | Zero quota with empty/nonempty source, exact quota, and an over-limit prefix; the final one-byte EOF probe is checked |
| Raw paths and numeric acceptance | 2 | Non-UTF-8/newline source and destination names with a long leading-zero quota; i64::MAX quota |
| Rejected arguments | 22 | Missing/extra arguments, empty paths, empty/signed/whitespace/non-ASCII/malformed decimals, u64 overflow, values above i64::MAX, paths over 4095 bytes, and total argument bytes over 8210; no file opens or truncation |
| Aliases | 2 | Same path and hard link reject before truncation and preserve source bytes |
| Final symlinks | 2 | Source and destination final-component symlinks fail before truncation and preserve both files |
| Earlier symlink | 1 | A symlink in a parent component follows normal Linux resolution |
| FIFOs | 2 | Source and destination FIFOs with no peer reject promptly under nonblocking opens, preserving existing destination bytes |
| I/O faults | 9 | Reached EACCES on openat attempts 1/2, EIO on ftruncate, EIO/EINTR on read and write attempt 2, EIO on close attempt 1, and EINTR on close attempt 2 |
| Quota plus close fault | 1 | Close EIO overrides LimitExceeded with status 3 and preserves the quota prefix |
| Allocation faults | 2 | Reached ENOMEM at each of the two argument-snapshot mmap attempts, status 4, no file opens, and complete cleanup of any prior allocation |

Every case checks the exit status and empty stdout/stderr. Host file reads
independently compare the entire destination or expected prefix and verify
source preservation. Open flags are checked in the trace, including absence of
O_TRUNC/O_APPEND. Fault cases assert the injected errno was reached exactly
once and check exact call counts, so an unexercised fault or retry fails the
test. Failed first/second opens produce zero/one close attempts; copy errors
still close both acquired owners.

The descriptor ledger pairs successful openat results with one close attempt
per owner and rejects unknown, repeated, or missing closes. Injected close
errors suppress the real host syscall. Those cases check error propagation,
logical ownership retirement, and attempt counts; actual kernel descriptor
release on delayed close errors is outside that injection model.

The memory ledger tracks every successful mmap by its actual address and
requested length and matches each munmap to that live owner. It rejects extra
allocations, unknown/double/mismatched releases, mremap, and unreleased owners.
Both ENOMEM positions are reached. File events are ignored by the memory
parser, and syscall result parsing tolerates strace's aligned columns. Expected
allocation counts follow argument bounds; no physical `View<u8>` width is
assumed. All successful mappings are released exactly once in every case.

The actual bounded driver-build command was:

```sh
timeout --kill-after=2s 100s \
  flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s env \
  CARGO_TARGET_DIR=/home/andrew-peterson/code/laniusc/target/stdlib-build \
  CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  cargo test --test stdlib_copy_file_execution --no-run \
  > target/stdlib-work/file-copy-admission/application-build.log 2>&1
```

The actual bounded acceptance command used the resulting driver binary:

```sh
timeout --kill-after=2s 100s \
  flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s env \
  RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
  target/stdlib-build/debug/deps/stdlib_copy_file_execution-41a64d10e2d53c40 \
  --exact copy_file_bytes_arguments_policies_and_exact_failure_cleanup \
  --nocapture --test-threads=1 \
  > target/stdlib-work/file-copy-admission/application.log 2>&1
```

The outer timeout is 100 seconds, lock acquisition is bounded to 35 seconds,
and the inner command is bounded to 60 seconds. The acceptance run sets a
16 MiB Rust thread stack and a 45-second GPU codegen guard. The driver filename
is the actual artifact from this build; a later build can have a different
hash.

| Evidence | Terminal log |
| --- | --- |
| Rust driver build | [`application-build.log`](../target/stdlib-work/file-copy-admission/application-build.log) |
| Accepted application group | [`application.log`](../target/stdlib-work/file-copy-admission/application.log) |

These elapsed gate times establish the application's functional native
profile, without a throughput measurement or evidence for another target or
user GPU kernels. Consult [the library guide](stdlib-file-copy.md) for the
status of the separate descriptor fixture gate.
