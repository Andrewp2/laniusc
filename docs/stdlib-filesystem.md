# Checked filesystem mutations

`std::filesystem` implements four checked byte-path operations in Lanius over
the existing `std::fs` host bindings. The executable target is **x86_64 Linux**.
The GPU compiler builds the native programs; these filesystem operations execute
on the CPU. GPU kernels and other operating systems are unverified.

| Function | Effect |
| --- | --- |
| `create_dir(path)` | Create one directory, requesting mode `0777` subject to umask and default ACLs |
| `remove_dir(path)` | Remove one empty directory |
| `remove_file(path)` | Unlink one non-directory name, including a final symbolic link |
| `rename(from, to)` | Rename a file, symbolic link or directory, replacing a compatible destination under Linux rules |

All four return `Result<i32, core::io::Error>`. Successful calls return `Ok(0)`.
Each call makes at most one host mutation attempt. `EINTR` becomes `Interrupted`,
`EAGAIN` becomes `WouldBlock`, and other errors become `Host(positive_errno)`.
There are no automatic retries. Caller policy determines whether a retry is
appropriate after an error.

These are single-operation primitives. Creating an existing directory returns
`Host(17)` (`EEXIST`); missing parents are errors. Directory removal fails for a
nonempty directory. Removing an absent file reports the host error. No operation
creates parents, recursively traverses children, or suppresses failures.

See the Linux contracts for [mkdir](https://man7.org/linux/man-pages/man2/mkdir.2.html),
[rmdir](https://man7.org/linux/man-pages/man2/rmdir.2.html),
[unlink](https://man7.org/linux/man-pages/man2/unlink.2.html), and
[rename](https://man7.org/linux/man-pages/man2/rename.2.html).

## Byte paths and validation

Arguments are borrowed `core::path::Path` values. Bytes may contain invalid
UTF-8, newlines, tabs or backslashes; only `/` separates components. Relative
paths use the process's current working directory, and absolute paths use the
host filesystem root. No implicit lexical normalization occurs. Empty paths are
valid Path values and are sent to the host, which returns `Host(2)` (`ENOENT`).

`MAX_PATH_BYTES` is **4095**, excluding the terminating NUL added by the existing
runtime binding. Paths longer than this return `Host(36)` (`ENAMETOOLONG`) before
any host mutation. Per-component limits remain host decisions and can return the
same error for shorter paths.

Each operation copies path bytes into private packed stack storage. It handles
both native strided byte arrays and packed buffers, including selected subviews
with nonzero offsets. It does not allocate. One-path operations use 4 KiB of
library stack staging; rename uses 8 KiB. Existing runtime bindings also stage
their own NUL-terminated paths.

At the host boundary, negative or overflowing logical View ranges and NUL bytes
return `InvalidInput`. This includes public Path/View fields constructed by hand
and later NUL mutation of a previously valid Path. Rename checks and stages its
source, then its destination, before attempting the syscall. An invalid second
argument cannot cause a partial rename or a truncated name operation.

Backing storage must cover the declared range and stay alive and unchanged for
the call. The language does not enforce these borrowing rules. A falsely claimed
physical length can trap during indexing; it is not a recoverable input error.
Concurrent mutation of borrowed bytes violates the contract. See
[byte paths](stdlib-paths.md) for the shared Path invariants.

## Resolution, replacement and ownership

Intermediate symbolic links use normal Linux path resolution. `remove_file`
unlinks a final symbolic link itself. `remove_dir` rejects a final symbolic link
to a directory. Rename moves a final source symbolic link itself and can replace
a final destination symbolic link.

Rename can replace an existing compatible destination. A directory destination
must be empty. An unchanged source/destination or two names already referring
to the same object can succeed without a namespace change, as specified by the
host. Cross-filesystem moves report `Host(18)` (`EXDEV`); there is no copy/delete
fallback. Success preserves the host's namespace atomicity rules and does not
promise persistence after a crash.

Path-based operations can race with other filesystem users and follow symlinks
in parent components. They do not confine access beneath a trusted directory.
Descriptor-relative operations and configurable no-follow policies require new
host bindings.

Removing a filename does not close an already open `std::file::File`; its owner
can continue I/O until it explicitly closes the handle. Rename likewise does not
transfer or duplicate descriptor ownership. See [owned files](stdlib-files.md).

## Executable evidence

`tests/filesystem_operations_execution.rs` compiles and runs Lanius programs,
then checks the actual Linux filesystem. Its four groups cover:

- Creating, removing and replacing files/directories; duplicate and absent
  names; nonempty-directory and wrong-object errors; absolute and relative
  names; trailing separators; a controlled umask; non-UTF-8 names; final and
  intermediate symlinks; and preservation of file contents on failed renames.
- Strided and packed subviews, excluded NUL padding, aliased rename arguments,
  and an open file that remains writable after unlink. Malformed logical views,
  later NUL mutation and oversized paths cause no host mutation or allocation.
- Twenty-four injected host failures across all four operations, checking
  errno propagation, one attempt, preserved names/contents, no allocation and
  no cross-filesystem rename fallback.
- Actual mutations at the exact 4095-byte path limit, followed by rejection of
  4096-byte paths before a syscall, for both rename arguments as well as each
  one-path operation.

The test harness uses Rust only to compile programs, set up and inspect temporary
files, and inject syscall failures with `strace`. Production behavior lives in
Lanius. Error injection replaces a syscall; the tests distinguish it from the
ordinary filesystem checks. All commands use bounded execution.

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test filesystem_operations_execution -- --nocapture
```

## Dependencies for metadata and directory enumeration

The currently bound filesystem services are open/read/write/close and these four
mutations. `stdlib/std/fs.lani`, the `HostService` list in
`crates/laniusc-compiler/src/codegen/lowering_ir.rs`, and the x86 runtime mapping
in `shaders/codegen/lir/x86/runtime_abi.slang` expose no metadata, directory-entry
read or descriptor-relative operations.

A minimal directory enumeration binding needs a directory descriptor open and
a bounded entry-read operation with explicit record sizes, raw name bytes, EOF,
short-buffer and errno behavior. Linux `getdents64` is one possible primitive;
the library would validate records and own iteration state. A useful metadata
binding needs a fixed result layout for file kind, sizes and timestamps, plus
explicit follow/no-follow behavior. Linux `statx` or a documented `fstat`/
`newfstatat` adapter could supply it. These are proposed dependencies, not APIs
implemented or advertised by `std::filesystem`.

`tests/fixtures/stdlib_foundation/filesystem_operations_directory_dependency.lani`
is an intentionally unsupported minimal example. Merely declaring a new
`extern "lanius_std"` directory operation fails native compilation with
`LNC0017: unsupported x86 call ABI` (target LIR opcode 20), before producing an
artifact. It is excluded from the passing runtime fixtures. Adding such a host
operation requires compiler/runtime coordination; no compiler, runtime ABI or
code generation source was changed for this library milestone.

Seek/position, synchronization for durability, hard links, symlink creation and
reading, descriptor duplication, configurable permissions/open flags, and
descriptor-relative access likewise remain unavailable through these wrappers.
No placeholder methods for them are exported.
