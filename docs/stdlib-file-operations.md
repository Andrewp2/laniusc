# Descriptor operations

`std::file_ops` supplies checked x86_64 Linux descriptor operations alongside
the existing single-owner `std::file::File`. It uses `std::linux` for the actual
system calls. Path staging, option validation, metadata decoding and ownership
remain Lanius.

## Open and ownership

`options()` starts with read access, close-on-exec and no controlling-terminal
acquisition. `OpenOptions` selects Read/Write/ReadWrite access, creation,
exclusive creation, truncation, append, nonblocking, final-component no-follow,
directory-only lookup, synchronization policy and creation mode. Modes are
0–4095 (permission and special bits), filtered by the process umask/default
ACLs. Exclusive requires create; append/truncate require write access. Invalid
options fail before the host lookup. Unsupported Linux flags are not silently
enabled or simulated.

`open(path, options)` uses the working directory. `open_at(directory_fd, path,
options)` uses the supplied borrowed directory descriptor for relative paths;
absolute paths ignore it, as Linux specifies. `AT_FDCWD` names the current
working directory. Both return an owned `std::file::File`. They copy and
revalidate the entire logical byte path, reject NUL, and append a NUL in private
packed storage. The path limit is 4095 bytes. Empty paths reach the host and
normally report ENOENT. UTF-8 and normalization are not required.

Keep one active owner per descriptor. Copying a File aliases its descriptor;
it does not duplicate it. `close()` invalidates the owner before one close
attempt and never retries a failed close. Linux may report a delayed I/O error
after releasing the descriptor. A descriptor borrowed by another operation
must remain live and must not be concurrently closed or reassigned.

No-follow checks the final component. Earlier path components can resolve
through symlinks. A trailing slash has Linux directory-resolution semantics.
These calls do not implement a filesystem sandbox or an atomic path snapshot.

## Position, synchronization and duplication

`seek(file, offset, origin)` returns the resulting signed 64-bit byte position.
Origins are Start, Current, End, Data and Hole. `position(file)` is a zero
Current seek. Negative resulting positions, unseekable descriptors and
filesystem-specific Data/Hole support are host errors. Seeking beyond EOF does
not extend a file. Append writes still target EOF regardless of seek position.

`sync_all(file)` invokes fsync; `sync_data(file)` invokes fdatasync. Their errors
are returned. File/stream `flush` has a different buffering contract. Syncing a
file alone does not sync a containing directory entry; callers implementing a
replacement protocol must also handle namespace synchronization and every
intermediate error. Storage/filesystem guarantees remain those of Linux and
the device.

`duplicate(file, minimum_fd, close_on_exec)` allocates a new descriptor at least
minimum_fd and returns a new File owner. `duplicate_to(source, target,
close_on_exec)` atomically replaces a live target descriptor with dup3 and
leaves ownership with the target File. Equal descriptor numbers are rejected
with InvalidInput. On failure neither owner changes. Linux discards any error
from the implicit close of the former target. Copies of the old target must
not remain active.

Duplicates share open-file position and status flags. Their descriptor flags
are independent. `close_on_exec`/`set_close_on_exec` inspect or change the
descriptor flag. `status_flags` returns the Linux access/status bits;
`set_status` changes only append/nonblocking and preserves other current bits.
That read/modify/write is not a concurrent update primitive. No descriptor
operation provides locking or a transaction.

## Metadata

`empty_metadata()` creates caller-owned output. `metadata_into(path, follow,
output)`, `metadata_at_into(directory_fd, path, follow, output)` and
`metadata_file_into(file, output)` stage a 256-byte statx result and publish it
only after decoding succeeds. The descriptor form uses AT_EMPTY_PATH. The
path forms explicitly choose whether to follow the final symlink.

The layout comes from [Linux's statx UAPI](https://github.com/torvalds/linux/blob/master/include/uapi/linux/stat.h),
not a native `struct stat` cast. `decode_statx_into(view, output)` exposes the
same checked decoder for an externally supplied 256-byte result. Logical range
and timestamp nanoseconds are validated before output changes. Unknown future
mask/attribute bits are preserved; absent known fields are zeroed. Use
`metadata.has(mask)` before interpreting optional fields. Basic fields can be
absent, and birth time is optional. A successful query is not a promise that
every field was returned or observed at the same instant.

Metadata includes file type/mode, identity (inode, device, links, uid/gid),
length (unsigned bytes, allocated 512-byte blocks, preferred block size),
access/modification/status-change/birth timestamps, and attributes with their
support mask. Timestamp seconds are signed seconds from the Unix epoch;
nanoseconds are 0–999,999,999. `kind(mode)` distinguishes regular, directory,
symlink, FIFO, socket, character and block devices; unknown kinds remain Unknown.

## Errors and verification

Calls make one host attempt. EINTR and EAGAIN become `core::io::Interrupted`
and WouldBlock; other errno values become Host(errno). Invalid paths/options
use InvalidInput, overlong paths Host(36), and malformed host counts/layouts
InvalidCount. Retrying is explicit; close must never be retried. There is no
discard-to-seek, proc-fd duplication, no-op sync or older-kernel metadata
fallback. A kernel without statx reports its actual error.

Physical backing and lifetime remain caller preconditions for public views;
logical metadata cannot discover an invented physical slice length. Metadata
outputs, Files and options must be library-maintained rather than forged or
mutated during an operation. The wrappers allocate no heap storage.

The native contract tests compare metadata and descriptor behavior with the
independent OS interfaces, including raw names, symlinks, exclusive creation,
sparse 64-bit positions, shared duplicated positions and descriptor flags.
Syscall fault tests check error propagation and exact close attempts. See also
[openat](https://man7.org/linux/man-pages/man2/open.2.html),
[lseek](https://man7.org/linux/man-pages/man2/lseek.2.html),
[dup3](https://man7.org/linux/man-pages/man2/dup.2.html),
[statx](https://man7.org/linux/man-pages/man2/statx.2.html) and
[fsync](https://man7.org/linux/man-pages/man2/fsync.2.html).
