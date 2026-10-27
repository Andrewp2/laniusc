# Checked descriptor-relative directory operations

`std::file_ops` provides two allocation-free Linux x86-64 operations:

```lanius
pub fn create_dir_at(directory_fd:i32, path:core::path::Path, mode:u32)
    -> core::result::Result<i32,core::io::Error>;
pub fn remove_dir_at(directory_fd:i32, path:core::path::Path)
    -> core::result::Result<i32,core::io::Error>;
```

All three focused executable groups pass on the tested Linux x86-64 host:
55 process invocations, including two repeated fault baselines. These are host
operations. GPU compilation produces their native executable; the operations
do not run inside GPU kernels.

## Path and mode contract

Both operations stage the complete raw byte path in bounded stack storage before
one native attempt. The existing `MAX_PATH_BYTES` limit is 4,095 bytes. Malformed
logical View bounds or embedded NUL return `io::Error::InvalidInput`; more than
4,095 bytes returns `Host(36)` (ENAMETOOLONG). An empty path reaches the kernel
and normally returns ENOENT. The caller must supply physically valid backing
for its declared View; logical checks cannot prove that obligation.

`create_dir_at` first rejects `mode > 4095` with InvalidInput, before path staging
or any syscall. The valid mode range is `0..=4095` (`0..=07777`). Requested
permissions remain subject to umask, default ACLs, parent set-group-ID and host
rules. The wrapper does not apply archive metadata or promise exact resulting
permissions for every parent/filesystem.

Relative paths resolve through the supplied descriptor. `AT_FDCWD` uses the
current directory; absolute paths ignore the descriptor. A retained descriptor
continues to identify its directory after that directory is renamed. These are
general byte-path primitives: nested components, `..` and intermediate symlinks
retain normal host resolution. The wrapper does not impose a leaf-only policy,
secure traversal, locking or hostile-directory protection. Callers such as an
archive extractor must validate their own components and namespace authority.

## Native effects and errors

| Operation | One Linux x86-64 syscall | Accepted success |
| --- | --- | --- |
| `create_dir_at` | `mkdirat`, number 258: `(dirfd, path, mode)` | Zero |
| `remove_dir_at` | `unlinkat`, number 263: `(dirfd, path, AT_REMOVEDIR=512)` | Zero |

The wrappers preserve errno through the existing I/O mapping, including
Interrupted for EINTR and WouldBlock for EAGAIN. A nonzero native success result
returns InvalidCount. There is no retry, fallback, path reconstruction,
existence check or heap allocation. The caller retains its directory descriptor;
the wrappers neither adopt nor close it.

EEXIST from creation does **not** establish directory type. Linux also returns
it for an existing regular file or symlink, including a dangling symlink. A
materializer that accepts an existing directory must separately open/check the
actual object using its required no-follow and directory rules. See the primary
[Linux mkdir/mkdirat documentation](https://man7.org/linux/man-pages/man2/mkdir.2.html).

Removal applies rmdir semantics to one empty directory name. It is not recursive,
does not remove a regular file or symlink leaf, and rejects a nonempty directory.
See [Linux unlink/unlinkat](https://man7.org/linux/man-pages/man2/unlink.2.html)
and [rmdir](https://man7.org/linux/man-pages/man2/rmdir.2.html).
The local headers used to cross-check the numbers and flag are
`/usr/include/x86_64-linux-gnu/asm/unistd_64.h` and
`/usr/include/linux/fcntl.h`.

Zero return values describe the syscall result; they do not imply storage
synchronization. These wrappers do not establish power-loss durability,
transactional rollback, archive extraction or network-filesystem guarantees.

## Focused execution gate

[`tests/stdlib_directory_at_execution.rs`](../tests/stdlib_directory_at_execution.rs)
compiles one actual Lanius consumer and supplies three narrow native groups:

- `namespace`: 24 processes covering actual directories/errno, raw and nested
  names, existing regular/directory/symlink leaves, absolute paths with an invalid
  dirfd, and held anchors after rename plus cwd change.
- `bounds`: 19 processes covering logical/NUL/path/mode preflight, exact
  4,095/4,096 path boundaries, mode-first error precedence and valid modes 0/4095.
- `faults`: 12 processes, including two real baselines and reached EIO, EINTR,
  EAGAIN, ENOSYS and unexpected-positive-result injection for each primitive.

Each case checks exact native arguments and at most one mutation attempt,
filesystem contents/identity, no source allocation, one caller-fd close and
actual `/proc` descriptor cleanup before process exit. The independent oracle
keeps failure evidence. The actual Rust driver ran all three tests successfully
in 6.51 seconds; receipt:
`target/stdlib-work/archive-directory-primitives-alias-retry.log`.
The shared prerequisite driver build passed separately in 2.63 seconds:
`target/stdlib-work/archive-prerequisite-drivers-build.log`.

Fourteen focused CPU controls pass for argument/attempt selectors and report
identity. Python syntax/local links, scoped whitespace and the owned Rust
driver's formatting also pass. The first gate stopped before native execution
with LNC0027 because the probe treated a module import as a short alias. Item
imports corrected that fixture error; production remained unchanged. Its log is
`target/stdlib-work/archive-directory-primitives-first.log`.

Accepted source SHA-256 snapshots:

- `stdlib/std/file_ops.lani`:
  `fa5c5b0b496bf56ce844f2d724506b2a4085aae34252ae7514329dcdd357ba37`
- `tests/fixtures/stdlib_execution/directory_at/probe.lani`:
  `8d1fe4ced934d9154efe850854f5a5013a389b6a887578e9549a4861a58a96d2`

The [fixture guide](../tests/fixtures/stdlib_execution/directory_at/README.md)
records the finite groups and exact commands. This acceptance covers the two
primitives; it does not accept the archive extractor that will consume them.
