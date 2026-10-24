# Owned files and borrowed paths

`std::file::File` owns one native file descriptor. `core::path::Path` borrows
length-bearing path bytes. Both implementations are Lanius. File operations use
the existing filesystem bindings and `std::stream` byte adapters.

The executable target is **x86_64 Linux**. The GPU compiler builds these native
programs; the file operations execute on the CPU. There is no claim of file I/O
inside GPU kernels or on another operating system.

## Path bytes

`from_bytes(bytes, count)`, `from_bytes_range(bytes, start, count)` and
`from_view(View<u8>)` return `Result<Path, core::path::Error>`. Constructors accept
arbitrary non-NUL bytes, including invalid UTF-8. `Bounds` rejects negative or
overflowing ranges; `Nul(index)` identifies the first NUL relative to the selected
range. Empty paths are valid values; an open attempt reports the Linux error.
Paths are not normalized, canonicalized or checked for existence. Linux treats
`/` as a separator and accepts non-UTF-8 names; see
[pathname(7)](https://man7.org/linux/man-pages/man7/pathname.7.html).

Basic queries are `byte_len`, `is_empty`, `byte_at`, `as_bytes`, `is_absolute` and
`is_relative`. [Byte paths and owned buffers](stdlib-paths.md) also documents
components, names, prefixes, parent traversal, comparison, joins and edits.
`byte_at` returns `None` outside the logical range. Absolute means
the first byte is `/`; empty paths are relative. Backslashes have no special
meaning. `as_bytes` returns the same borrowed `View<u8>`, including its offset
and native byte stride.

The initial physical range must be backed by storage, as with `core::slice::View`.
A false backing claim traps when validation indexes beyond the actual slice.
Keep backing storage alive and unchanged. These lifetime and read-only rules are
manual contracts, not compiler-enforced safety. File opening rechecks NUL bytes
while staging the path so a later NUL mutation cannot silently shorten a name.

There is no path-value length limit beyond the view's `i32` bound. The current
file binding accepts at most **4,095 bytes**, excluding its terminating NUL.
Longer paths return `Host(36)` (`ENAMETOOLONG`) before any host open attempt.
Filesystem component limits and other host errors are preserved. Open copies
the path through 4 KiB of packed stack storage, so strided arrays and packed
buffers both work without heap allocation.

## Opening and ownership

`std::file::open(path, mode)` returns `Result<File, core::io::Error>`.

| `OpenMode` | Existing path | Missing path | Access |
| --- | --- | --- | --- |
| `Read` | Open at offset zero | Error | Read only |
| `Create` | Truncate to zero bytes | Create | Write only |
| `Append` | Preserve contents, append writes | Create | Write only |

The current runtime uses `O_RDONLY`, `O_WRONLY | O_CREAT | O_TRUNC`, and
`O_WRONLY | O_CREAT | O_APPEND`, respectively. Creation requests mode `0666`,
subject to the host's umask and ACL rules. Symlinks are followed. These bindings
do not set close-on-exec. Open makes one host attempt and reports interruption
to the caller. Append uses the host's append semantics per individual write;
several writes are not one atomic record. See
[open(2)](https://man7.org/linux/man-pages/man2/open.2.html).

Keep **one active owner** of a File. A record copy does not duplicate the host
descriptor. There is no automatic destructor. Call `close` on all exit paths,
including failed reads and writes. Pass `file.borrow()` to generic stream
helpers to retain the same owner.

| Operation | Contract |
| --- | --- |
| `is_open()` | Whether this owner still holds a descriptor; does not query the host |
| `raw_handle()` | Borrowed `Option<i32>` identifier; invalid after close or ownership transfer |
| `take_handle()` | Return the descriptor and reset this File without closing it; caller now owns it |
| `from_owned_handle(handle)` | Adopt exclusive ownership of a live descriptor; only negative values are checked |
| `close()` | Retire ownership, make at most one close attempt, return `Result<i32, Error>` |

Descriptor zero is valid. Once reset, `raw_handle` and `take_handle` return
`None`; `close` returns `Ok(0)` without another syscall. Do not independently
close a borrowed raw handle or keep using a descriptor after transferring it.
Otherwise descriptor-number reuse can redirect operations to an unrelated file.

Close resets ownership **before** the host call, including when that call
reports an error. Linux releases descriptors on interrupted closes and delayed
I/O errors, so retrying can close a different file that reused the number.
The error remains available to the caller; close success does not guarantee
durability. This is specifically the Linux contract, not a universal POSIX
contract. See [close(2)](https://man7.org/linux/man-pages/man2/close.2.html).

## Streams and failures

File implements `core::io::Read` and `Write`. Use the shared `read_exact`,
`write_all` and `copy` helpers for complete transfers. Individual read/write
calls transfer at most 1,024 bytes through packed stack staging. Reads and
writes preserve offsets and byte strides and can succeed with short counts.

Negative or overflowing logical buffer ranges return `InvalidInput` before
accessing storage. Zero-length requests return `Ok(0)`, including on a reset
File. Nonempty requests on a reset File report `Host(9)` (`EBADF`). Actual
buffer capacity remains a caller precondition.

`EINTR` maps to `Interrupted`, `EAGAIN` to `WouldBlock`, and other failures to
`Host(positive_errno)`. Shared exact/all/copy helpers retry interrupted
transfers and retain partial-progress counts. They do not close File owners.
Writes and creates can leave partial output after failure.

`flush` returns `Ok(0)` for an open owner because this type retains no library
output buffer. A reset owner returns `Host(9)`. Flush does not inspect raw
descriptor validity, issue `fsync`, close the file or establish durability.
An externally closed descriptor violates the ownership contract.

## Example and execution evidence

`sample_programs/file_concat.lani` concatenates one or more file arguments to
stdout with bounded stack storage. It preserves arbitrary bytes in filenames
and contents, closes each input even after copying fails, and stops at the first
error. Exit codes: `0` success, `2` absent/invalid arguments or a path exceeding
the binding limit, `3` open/read/write/close failure. Output may contain a prefix
on failure. This is a simple concatenator without option parsing or a special
stdin filename.

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  sample_programs/file_concat.lani --stdlib-root stdlib \
  -o target/stdlib-work/file_concat
timeout --kill-after=2s 10s target/stdlib-work/file_concat first.bin second.bin
```

`tests/stdlib_owned_file_execution.rs` has three executable test groups:

- Open modes, truncation, append creation, binary data, strided subviews, packed
  paths, bounds, empty and non-UTF-8 names, descriptor zero, adoption, transfer,
  closed-handle behavior, EOF, a real invalid-descriptor close, and descriptor
  reuse after repeated close. Invalid mutated paths do not create a shorter name.
- Copy through two owned files with injected open/read/write/close failures:
  permission and descriptor exhaustion, interrupted calls, would-block, disk
  full, I/O errors and zero write progress. Tests check errno, output prefixes,
  one close attempt per acquired descriptor and absence of heap allocations.
- The concatenation application with empty files, 133,164 binary bytes, newline
  and non-UTF-8 filenames, missing files, directory reads, the exact 4,095-byte
  path boundary, and cleanup on input/output/close failure.

`strace` error injection replaces a close syscall rather than producing a real
post-release kernel error. Those cases prove error propagation, owner retirement
and absence of retries; process exit releases the injected descriptor. The
separate normal reuse and real `EBADF` cases exercise actual kernel closes.

The focused suite passed on 2026-10-22 in 8.88 seconds, excluding its 1.43-second
test-harness build. Compiler warnings were pre-existing. Use the absolute build
directory and environment described in [stdlib-string.md](stdlib-string.md).
Four existing path execution groups and the legacy file-write execution test
also pass. Five path loader/type-check checks pass separately; they are not
runtime evidence. Stale exact dependency counts and a source-substring coverage
test were removed; executable path fixtures remain the behavior gate.

## Additional filesystem APIs

[File options and operations](stdlib-file-operations.md) now supply configurable
and descriptor-relative opens, seek/position, metadata, synchronization,
duplication and descriptor flags over the explicit Linux boundary. Configurable
opens default to close-on-exec; the three original modes above retain their
documented flags. [Directory iteration and walking](stdlib-directory.md) provide
raw names, bounded traversal and a real directory-report program.
[Borrowed paths and owned buffers](stdlib-paths.md) now provide lexical operations,
and [checked filesystem mutations](stdlib-filesystem.md) execute over existing
bindings. Lifetime enforcement, other targets and further filesystem operations
remain work. See
[library-dependencies.md](library-dependencies.md).
