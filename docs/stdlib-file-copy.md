# Bounded regular-file copy

`std::file_copy::copy_regular` replaces an open regular file's byte contents
from another open regular file, using caller-owned scratch storage:

```lanius
pub fn copy_regular(
    source: &std::file::File,
    destination: &std::file::File,
    scratch: core::slice::View<u8>,
    max_bytes: u64,
) -> core::result::Result<u64, core::io::CopyFailure>;
```

It copies from byte zero to actual EOF. Success returns the number of bytes
written. The destination contains that copied sequence with no old tail. The
function borrows both File owners and allocates no heap storage. It uses the
existing [File](stdlib-files.md), [descriptor operations](stdlib-file-operations.md)
and [stream adapters](stdlib-streams.md).

## Prepare the descriptors

Keep both descriptors live and exclusively controlled throughout the call.
The source must permit reading; the destination must permit writing. Open the
destination without truncation so the function can check its identity before
discarding its contents. For example, `file_ops::options()` with `access` set
to `Access::Write` and `create` set to true opens or creates it without an early
truncate. The caller must handle open errors and close every acquired owner.

The function checks these conditions before any seek, truncate or transfer:

1. Scratch has positive length, a nonnegative start, and a logical end no
   greater than `2147483647`. `max_bytes` is at most `9223372036854775807`.
   These argument checks happen before any system call, even with quota zero.
2. Both File owners are active. An inactive owner produces `Host(9)`.
3. `F_GETFL` reports readable source access and writable destination access.
   Both descriptors reject Linux access mode 3, `O_PATH` and `O_DIRECT`; the
   destination also rejects `O_APPEND`. Flags are inspected without changing
   them. See Linux's [access and status flag rules](https://man7.org/linux/man-pages/man2/open.2.html)
   and [F_GETFL](https://man7.org/linux/man-pages/man2/F_GETFL.2const.html).
4. Descriptor metadata includes `STATX_TYPE | STATX_INO` (`257`), and both
   kinds are regular files. The function compares device major, device minor
   and inode to reject aliases, including hard links and duplicated handles.
   The [statx mask](https://man7.org/linux/man-pages/man2/statx.2.html) determines
   which requested fields were returned; missing type or inode is rejected.

Policy rejection produces `InvalidInput`. Underlying operation errors retain
their existing `core::io::Error`. These checks leave the scratch bytes, file
offsets and destination contents unchanged through this API. The physical
backing and lifetime of the claimed scratch range remain caller preconditions;
logical range validation cannot discover an invented backing length.

After those checks, the function seeks the source to Start 0, seeks the
destination to Start 0, requires each successful result to equal zero, then
calls `file_ops::set_len(destination, 0)`. A different successful seek result
produces `InvalidCount` before truncation. Linux
[lseek](https://man7.org/linux/man-pages/man2/lseek.2.html) changes the position
shared by descriptors for the same open file description.
[ftruncate](https://man7.org/linux/man-pages/man2/ftruncate.2.html) discards the
old bytes; it can also update timestamps and clear set-ID mode bits.

## Copy and quota

Supply a positive scratch view even when `max_bytes` is zero. A view can start
inside an array or packed buffer:

```lanius
let storage: [u8; 1030] = [0; 1030];
let scratch: core::slice::View<u8> =
    core::result::unwrap(core::slice::view_range(storage, 3, 1024));
let copied: core::result::Result<u64, core::io::CopyFailure> =
    std::file_copy::copy_regular(source.borrow(), destination.borrow(), scratch, 1048576);
```

Scratch is mutable temporary storage. Its surrounding elements remain outside
the copy range. File reads and writes preserve its logical byte stride, so both
ordinary Lanius arrays and packed byte views work. The stream adapter transfers
at most 1024 bytes per host call, even for a larger scratch view.

The function ignores metadata length and reads until an actual zero-byte read.
This also permits regular pseudo-files whose reported size is zero but whose
reads produce bytes. Each request is limited by the remaining quota. Short
[reads](https://man7.org/linux/man-pages/man2/read.2.html) and
[writes](https://man7.org/linux/man-pages/man2/write.2.html) are normal; every
accepted input chunk is fully written before the next read.

At exactly `max_bytes` written, a one-byte source read checks EOF. Zero means
success. One byte produces `LimitExceeded` with `read = max_bytes + 1` and
`written = max_bytes`; that probe byte is never written. A zero quota therefore
still seeks and truncates the destination, then succeeds only if the source
probe reaches EOF. The quota bounds acknowledged output bytes, not elapsed
time: regular filesystem calls can block.

## Failure and ownership

`CopyFailure` contains the existing `cause`, `read` and `written` fields.
Counters start at zero for this call and record acknowledged successful
transfers. A read can consume a chunk before a later write fails, so `read`
can exceed `written`. A zero-progress write becomes `WriteZero`; a count
outside the requested range becomes `InvalidCount`. An invalid count cannot
establish what the host actually transferred; the counters retain the
previously acknowledged progress.

Each error is returned immediately, including `Interrupted` and `WouldBlock`.
Successful short transfers continue with their remaining bytes. The function
does not poll or impose a deadline. Calling it again starts preparation again,
including destination truncation; the counters do not provide a resume API.

Preparation and transfer are not transactional. A failure with both counters
zero may already have changed one or both offsets or emptied the destination.
A later failure can leave a copied prefix. An error return does not promise
restored offsets, original bytes or unchanged file metadata.

The caller must prevent concurrent reads, writes, seeks, flag changes,
descriptor close/reassignment, and backing-file mutation that would invalidate
the checks or copied sequence. Duplicates share offsets and status flags. The
operation takes no locks and creates no snapshot. It neither syncs nor closes
either owner. Keep handling explicit synchronization and close results as
required by the application; successful copying alone does not establish
durability.

## Verification

`tests/stdlib_file_copy_execution.rs` compiles the descriptor fixture once,
checks the emitted executable with the existing strict ELF/jump checker, and
reuses it for 84 native executions. The canonical gate passed on 2026-10-24 in
6.33 seconds; the separate test-driver build took 1.22 seconds. Logs are
`target/stdlib-work/file-copy-admission/descriptor-fixed-checker.log` and
`target/stdlib-work/file-copy-admission/build.log`.

The cases check actual binary output and shared descriptor offsets for lengths
0, 1, 7, 1024, 1025 and 4097, ordinary strided arrays and packed scratch,
capacities 1, 7 and 4096, removal of an old destination tail, exact quotas,
overflow probes and zero quotas. Rejected logical arguments, inactive owners,
access modes, status flags, nonregular files and inode aliases preserve the
checked contents and offsets before preparation. Fault cases cover metadata,
flags, both seeks, truncation, transfers and quota probes, including immediate
interruption/would-block propagation, invalid counts and confirmed prefixes
after a later error.

Of those executions, 83 syscall traces show no heap allocation/release or close
calls, and no status flag changes. The remaining execution uses Python only to
set `RLIMIT_FSIZE` and ignore `SIGXFSZ`, then execs the same fixture without
tracing Python startup. Its real short write consumes 7 source bytes, writes
the actual 3-byte prefix and returns `Host(27)` (`EFBIG`) with counters 7/3.
An independent `/proc/version` byte oracle also passes: its descriptor reports
regular-file kind and size zero, and the copy still reaches actual EOF.

The accepted fixture retains the original literal-count `[u8; 4100]` backing,
nonzero scratch start and full 4096-byte capacity. The earlier literal-count
checker failure and rejected typed-constant attempt are preserved in
`tests/fixtures/stdlib_compiler_state/byte_array_repeat_count/`; they are
historical compilation failures, not additional accepted native cases. The
unchanged original passed with the [count-checker fix](compiler-array-repeat-context.md)
in compiler commit `e59a9183`. These results
establish behavior on the existing native x86_64 Linux target; GPU kernel
behavior and performance are outside this evidence.
