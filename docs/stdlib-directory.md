# Directory iteration and walking

`std::directory` owns Linux directory descriptors and reads `getdents64` records
through `std::linux`. Its entry parser, iteration state, path construction,
metadata lookup, walk limits and cleanup are Lanius. Names are arbitrary Unix
bytes, not implicitly UTF-8.

## Iterator

`open(path, buffer_bytes)` and `open_at(directory_fd, path, buffer_bytes)` open
read-only directories with close-on-exec and final-component no-follow.
The buffer must be 24–1,048,576 bytes. The default walk buffer is 32 KiB. An
unusually long filesystem entry that cannot fit still produces the real host
EINVAL; a small caller buffer is not silently enlarged.

The returned `Reader` is one owner of its File and packed byte buffer.
`empty_directory()` plus `open_into`/`open_at_into` can instead populate a
caller-owned closed Reader. An already open or buffered output is rejected;
errors leave that output unchanged.
`next()` returns `Result<Option<Entry>, Error>`, skipping `.` and `..`.
`Entry` exposes a borrowed `name`, inode number, opaque signed `cookie`,
type hint and consumed record bytes. Order is the filesystem enumeration order.
The cookie is not a byte offset. Type hints can be Unknown and are not a
substitute for metadata or an atomic open. No assumption is made that names
are 255 bytes or valid Unicode.

`decode_entry(input, offset)` validates one externally supplied getdents64
record. It checks logical ranges, the minimum record size, 8-byte record
alignment, containment, a nonempty NUL-terminated name, and absence of slash.
Bytes after the first NUL are padding and are not interpreted. Unknown type
hints remain Unknown. A malformed batch marks its live Reader Failed.
Native record fields are decoded explicitly from the x86_64 Linux layout.

Entry name views expire at the next `next()` or `close()` call. Treat them as
read-only and copy them to retain them. Input to a helper must not alias a
directory's buffer while an operation can refill it. A public view's backing
must physically cover its logical range. `raw_handle()` is borrowed; do not
close or seek it, duplicate it for independent enumeration, or call another
getdents consumer on its shared open-file description while the iterator lives.

`next()` makes at most three refill syscalls per call while skipping dot entries;
a stream that still offers only skipped records hits Limit and becomes Failed.
Interrupted/WouldBlock errors preserve the buffered state for an explicit retry.
Other I/O errors are
reported without pretending to restore the kernel cursor. EOF is stable.
`close()` releases the byte buffer and makes one File close attempt, including
after a failed iteration. Repeated close is harmless. Copying Reader aliases
its resources; keep one active owner and close it once.

## Bounded walk

`walk(root, depth, limits)` returns an owned `Snapshot`. Depth 0 yields no
entries; depth 1 lists direct children. Deeper values descend only into actual
directories and successfully prune at the requested depth. `default_limits()`
bounds depth, observed entries, each relative path, aggregate path bytes,
work and the iterator buffer. Invalid or exceeded limits return an error.

Walking uses a bounded explicit stack. Each active directory is opened relative
to its parent with directory-only/no-follow flags. Child names contain no slash
and are never `.` or `..`. Metadata uses no-follow lookup; a type hint is never
trusted to decide whether a child is a directory. If a child changes between
metadata and open, its open result is used and the opened identity is checked.
Symlinks are listed without traversal. Mount crossings are allowed and still
subject to depth/entry/work limits; bind mounts can produce repeated identities.

The walk records entries observed during separate syscalls. Concurrent mutation
can add/remove names, change metadata, or make a lookup fail. A parent descriptor
anchors its object even if renamed, but relative report paths are observations
and need not name the same objects later. Earlier components of the supplied
root may resolve through symlinks. This is not a consistent filesystem snapshot,
a containment/security boundary, a locking protocol or a transaction.

The result stores packed relative-path bytes and scalar rows with metadata and
depth. `len()`, `entry_into(index, output)`, `byte_len()` and `work_done()` expose
the result. Create output with `empty_entry()` and pass `output.borrow()`;
it must be separate from snapshot storage. Entries remain valid until Snapshot
destruction; no live directory descriptor remains
in a successful result. Snapshot copies alias their allocations. `destroy()`
must run exactly once on the active owner.

The result is staged: a directory/read/metadata/open/close/allocation/limit
failure closes every active descriptor, frees every buffer and partial result,
and returns no partial Snapshot. Cleanup still attempts all closes; the first
operation error wins over cleanup errors. On the successful path, a close error
is returned. The walk does not retry EINTR indefinitely.

Work is an abstract deterministic budget, not elapsed time or exact machine
instructions. The initial charge is buffer size + root byte length + 1. Each
iterator call charges its recorded work plus 1: each refill costs 1 + returned
bytes, and each decoded record costs record length + 1. An observed entry costs
twice its complete relative-path length + 1, plus basename length + 1 for its
metadata lookup. Descent costs buffer size + basename length + 2. A single
bounded iterator call is completed before its charge is checked; failure can
therefore do up to three refills before returning Limit. `work_done()` reports
accepted charges on success. Capacity growth is geometric; path-byte and row
capacities cannot exceed configured limits. Peak directory buffers scale with
active depth; retained rows and paths scale with the complete result.

## Directory report

```sh
laniusc --stdlib-root stdlib sample_programs/library/directory_report.lani \
  -o directory-report
./directory-report --depth 3 -- .
./directory-report --kind file --suffix-hex 2e6c616e69 -- .
./directory-report --prefix-hex ff -- .
```

The CLI reports deterministic byte-path order as TSV with a header:
`path_hex`, `kind`, `depth`, `size`, `mode`, `inode`, `mtime_sec`, `mtime_nsec`.
Path hex is lowercase and reversibly represents tabs, newlines, NUL-free
non-UTF-8 names and other raw bytes. Paths are relative to the selected root;
the root itself is not a row. Kind is file, directory, symlink, fifo, socket,
character, block or unknown. Size and inode are unsigned decimal; mode is
octal including type bits; timestamps use signed epoch seconds and nanoseconds.

`--prefix-hex` and `--suffix-hex` match basename bytes. `--kind` filters output;
filtering never suppresses traversal of a directory needed to reach matching
descendants. `--depth` controls traversal. Argument, depth, entry, path-byte,
work and output caps are explicit. The CLI shares one work budget across walk,
filtering, sorting and formatting: scanning a basename/filter byte costs one;
sorting charges one per comparison, compared byte pair and swap; visiting or
formatting a result row costs one, and each output byte costs one. Arguments
are limited to 32 and 65,536 bytes. Depth defaults to 64 and is at most 128;
entries default to 65,536 and are at most 1,048,576; aggregate path bytes default
to 16 MiB and are at most 64 MiB; one relative path defaults to 4095 and is at
most 1 MiB. Work defaults to 128 Mi units and is at most 1 Gi units. Output
defaults to 32 MiB and is at most 64 MiB. Configure them with `--depth`,
`--max-entries`, `--max-bytes`, `--max-path-bytes`, `--max-work` and `--max-output`.
The report requires type/mode, inode, size and modification time presence bits;
missing fields produce an error rather than invented data. Walking, filtering,
sorting and output generation finish before stdout is written. A host write
failure can expose a prefix already accepted by the OS.
The CLI explicitly ignores SIGPIPE before allocating so a closed output pipe
returns an I/O error through the same cleanup path. Failure to install that
process-wide disposition exits with status 3 before arguments are copied.

Exit status is 0 for success/help, 2 for arguments/limits/malformed records,
3 for host I/O/close errors, and 4 for allocation failure. Every exit releases
argument, iterator, snapshot, sorting and output owners. The report performs
no file mutation or network I/O.

## Evidence and sources

The focused native tests compare raw names, kinds, sizes, modes, inode numbers
and timestamps with Python `os`/`stat`, including symlinks, non-UTF-8 names,
deep/wide trees and sparse files. Synthetic record tests check every prefix,
misaligned/overflowing record boundaries and name terminators. Syscall and
allocation denial tests account for descriptor lifetimes and mmap/munmap pairs,
and verify that late errors expose no stdout.
Injected close errors skip the kernel close; those cases verify owner
invalidation and one attempt, rather than emulating Linux's descriptor release.

The kernel contract is [getdents64](https://man7.org/linux/man-pages/man2/getdents.2.html),
including opaque cookies and DT_UNKNOWN. The mature reference is
[musl readdir](https://git.musl-libc.org/cgit/musl/tree/src/dirent/readdir.c).
Metadata and descriptor contracts are described in
[Descriptor operations](stdlib-file-operations.md).
