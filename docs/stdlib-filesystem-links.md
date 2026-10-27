# Filesystem links and permissions

The new `std::file_ops` link, symlink-read and permission operations are
implemented in Lanius through the existing checked Linux syscall boundary.
All nine functions have focused executable evidence from five native Linux
x86_64 groups. GPU compilation produced the CPU executables; these filesystem
services are not GPU-kernel operations. The finite acceptance scope and separate
receipts are recorded below.

## Public surface

All paths are borrowed `core::path::Path`; destination buffers are borrowed
`core::slice::View<u8>`. `Error` below is `core::io::Error`.

```lani
pub struct LinkRead { copied:i32, complete:bool }

hard_link_at(old_directory_fd:i32, old_path:Path,
             new_directory_fd:i32, new_path:Path, follow:bool)
    -> Result<i32,Error>
hard_link(old_path:Path, new_path:Path, follow:bool) -> Result<i32,Error>

symlink_at(target:Path, new_directory_fd:i32, new_path:Path)
    -> Result<i32,Error>
symlink(target:Path, new_path:Path) -> Result<i32,Error>

read_link_at_into(directory_fd:i32, path:Path, destination:View<u8>)
    -> Result<LinkRead,Error>
read_link_into(path:Path, destination:View<u8>) -> Result<LinkRead,Error>

set_permissions(file:&File, mode:u32) -> Result<i32,Error>
set_permissions_at(directory_fd:i32, path:Path, mode:u32)
    -> Result<i32,Error>
set_permissions_path(path:Path, mode:u32) -> Result<i32,Error>
```

Current-directory wrappers delegate to the same `*at` operation using
`AT_FDCWD` (-100). They add no allocation, retries, fallback or extra syscall.
The four mutating operation families return `Ok(0)` only for a zero native
result; an unexpected successful count becomes `InvalidCount`.

## Link creation and path authority

`hard_link_at` stages the old path, then the new path, before one `linkat`
call. `follow=false` links the final source symlink inode itself;
`follow=true` uses `AT_SYMLINK_FOLLOW` (1024) to link its resolved target.
An existing destination name is never replaced. Linux controls ownership,
filesystem, cross-mount and link-count errors. See the
[Linux linkat contract](https://man7.org/linux/man-pages/man2/link.2.html).

`symlink_at` stages the target bytes, then the new path, before one
`symlinkat` call. It stores the target verbatim: relative, parent-component,
dangling and non-UTF-8 targets are permitted, subject to NUL/path bounds and
the host's limits. Only the new link path is resolved during creation. An
existing destination is retained. See
[Linux symlinkat](https://man7.org/linux/man-pages/man2/symlink.2.html).

The existing staging contract checks logical View metadata, rejects embedded
NUL, permits at most 4,095 path/target bytes, and appends the syscall's private
NUL terminator. Invalid logical metadata or NUL returns `InvalidInput`;
excess length returns `Host(36)` before a native call. Empty paths remain
ordinary host inputs and may return native errors.

A relative `*at` path is anchored by its supplied directory descriptor.
Absolute paths retain Linux descriptor-ignore behavior. Intermediate symlinks
and `..` retain normal host resolution; these are general byte-path APIs,
without a leaf-only containment or hostile-namespace guarantee. No input path
or target owner is consumed or changed.

## Bounded symlink reads

Linux `readlinkat` returns un-terminated bytes and may fill its entire native
buffer without revealing whether more bytes exist. See
[the Linux readlinkat contract](https://man7.org/linux/man-pages/man2/readlinkat.2.html).
This wrapper stages the complete input path and receives into a separate
4,096-byte packed stack probe before touching caller output.

Destination logical bounds are checked first. The native request is
`min(destination.length + 1,4096)`; the implementation only adds one when
the length is below 4096, so `i32::MAX` lengths cannot overflow that addition.
An empty destination still requests one byte.

After a successful native result within 0..request, the wrapper copies at most
`destination.length` bytes and reports:

- `copied`: the prefix actually copied into the selected destination View.
- `complete`: true only when the native result is shorter than the probe
  request, proving this one read did not fill the native buffer.

For a destination shorter than 4096, the extra byte distinguishes an exact fit
from truncation. At the 4096-byte probe cap, a full result remains explicitly
incomplete even if the caller supplied more space. No total target length is
invented, and no terminator is copied. The rest of the caller buffer remains
unchanged.

| Destination length | Target bytes returned by host/probe | Result |
| ---: | ---: | --- |
| 0 | 1 of a nonempty target | copied=0, incomplete |
| 3 | 2 | copied=2, complete |
| 3 | 3 | copied=3, complete: exact destination fit |
| 3 | 4 | copied=3, incomplete |
| 4095 | 4095 | copied=4095, complete |
| 4096 or larger | 4096 | copied=4096, incomplete |

Preflight, native errors and invalid returned counts leave the whole
destination unchanged. Negative successful values and values above the
requested count are `InvalidCount`, validated before copying. A zero returned
count is accepted as copied=0/complete. There is one attempt; EINTR is returned
without retry. Callers provide physical backing for every claimed element, as
with other Views.

Nonzero destination starts and native slice stride are preserved by typed
element copies. Path/destination overlap is supported because the path has
already been packed before any output mutation. The final symlink is read
rather than followed. Linux's empty-path descriptor behavior is passed through
when the caller supplies a suitable symlink descriptor.

## Permission changes

Both permission families accept only mode 0..4095 (octal 0000..07777), including
ordinary permissions and set-id/sticky bits. File type bits and larger values
return `InvalidInput` before descriptor inspection or path staging.

`set_permissions` borrows a live File and calls `fchmod` once. A closed
File returns `Host(9)` before a native call. It does not reopen, close, replace
or retarget the descriptor, so path rename/unlink does not redirect its object.

`set_permissions_at` stages one path after mode validation, then uses the
raw Linux `fchmodat` syscall with exactly three arguments. It always follows
the final symlink. `set_permissions_path` selects `AT_FDCWD`; it can operate
after a file has been closed or when opening it for reading is not appropriate.

These APIs have no no-follow permission flag or implicit fallback. The
[Linux chmod documentation](https://man7.org/linux/man-pages/man2/fchmod.2.html)
distinguishes the libc interface from the raw three-argument syscall. Host
ownership, capabilities, filesystem and special-bit rules remain authoritative;
inspect metadata when the resulting bits matter. The library does not modify
ambient umask or promise that every requested special bit will survive host
policy.

## Syscall and failure boundary

Local `asm/unistd_64.h` and `linux/fcntl.h` headers were checked against the
primary Linux documentation. The selected x86_64 calls are:

| Operation | Syscall | Native arguments |
| --- | ---: | --- |
| `hard_link_at` | linkat 265 | oldfd, oldpath, newfd, newpath, follow flags 0/1024 |
| `symlink_at` | symlinkat 266 | target, newfd, newpath |
| `read_link_at_into` | readlinkat 267 | fd, path, packed probe, requested count |
| `set_permissions` | fchmod 91 | fd, mode |
| `set_permissions_at` | fchmodat 268 | fd, path, mode |

No heap storage is allocated by these operations. Two-path and readlink
operations use two 4KiB stack buffers; path permissions use one 4KiB buffer.
Only the selected syscall is attempted after preflight. Existing errno mapping
preserves EINTR as `Interrupted`, EAGAIN as `WouldBlock` and other errno as
`Host(errno)`. There is no retry, second probe, libc emulation or silent no-op.
No automatic cleanup of a successfully created name or permission rollback is
performed; caller namespace ownership and recovery policy remain explicit.

## Executable acceptance

The [focused fixture guide](../tests/fixtures/stdlib_execution/filesystem_links/README.md)
records exact filters, evidence mechanics and source hashes. The five group
scopes total **139 cases**, accepted through two commands; this is not a count
of cumulative process executions because the first 34 fault cases were repeated.

| Accepted scope | Cases | Invocation time | Receipt under `target/stdlib-work/` |
| --- | ---: | ---: | --- |
| Links, readlink, permissions, preflight bounds | 28 + 19 + 12 + 45 | 6.67 s, complete mixed five-test invocation | `filesystem-links-native-first.log` |
| Complete fault-only retry | 35 | 6.36 s | `filesystem-links-faults-small-poke-retry.log` |

The first invocation passed all four listed groups and the first 34 fault
cases. Its final fault-case launch failed because installed strace rejected
a 4,096-byte `poke_exit` argument before starting the child. There was no native
product result or syscall trace for that launch. The oracle correction used
a 16-byte poke with the same synthetic 4,096 return count; the fault-only retry
then passed. Production, probe and Rust driver behavior did not change for the
retry. The 6.67 seconds includes the original tooling failure and is not an
isolated timing for the four passing groups.

The host oracle checks real device/inode identity and link counts, source
symlink follow policy, raw target bytes, nonreplacement and renamed descriptor
anchors. It checks all output backing bytes for real exact-fit, truncated,
4,095-byte, nonzero/strided and path-alias readlink cases. Permission cases
check descriptor and path modes, final-symlink following, and unchanged real
descriptor offsets/status/close-on-exec flags. Invalid paths, View metadata,
mode and destination precedence must issue zero effect calls.

The synthetic full-probe case requires `copied=4096`, `complete=false`, the
actually supplied 16-byte prefix and unchanged guards outside the copied range.
Unprovided copied interior bytes are deliberately unconstrained. It neither
proves a 4,096-byte kernel data write nor assumes zero-initialized scratch.
The complete byte comparisons for real reads remain separate evidence.

Reached EIO/EINTR/EAGAIN/ENOSYS and invalid returned counts are bound to the
baseline syscall instruction, ordinal and input arguments. Each operation
phase contains exactly one selected syscall, or none for preflight failure.
The target post-IP must match the exact Linux six-word syscall thunk with an
independently decoded instruction boundary. The unchanged raw source-map
verifier accepts its exact 0x22/full-width and historical 0x62 allocator profiles;
these primitive fixtures make no source allocations. Three stdout/ACK
checkpoints establish actual live descriptor identity, inspect the completed
operation, then verify all owners released before exit. The separate 40 CPU
controls are not counted as native cases.

The accepted FileOps SHA-256 is
`21269e340801c09396a133a43ea5f5391307a59de861476605a140f953530ab6`.
The [minimal parser cast/guard reproduction](../tests/fixtures/stdlib_compiler_state/filesystem_imports/README.md)
records an initial source-admission limitation. Widening the requested count
into an equivalent i64 local resolved the ambiguous comparison form before
these gates. A misleading larger-import fallback named `core::iter`; the
standalone reproduction fails without imports. No compiler repair is claimed.

Acceptance is limited to native Linux x86_64 on the tested filesystem profile.
Other operating systems, arbitrary filesystems, cross-mount behavior, ownership
or ACL policy, and hostile namespace/security guarantees were not established
by these finite groups. Kernel permission and special-bit rules remain
authoritative.
