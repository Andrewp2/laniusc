# Resumable directory traversal

`std::walk` walks a Linux directory tree without retaining the whole result.
It owns the active directory readers and one relative-path buffer. Callers
receive entries one at a time, decide whether to descend into each directory,
and can stop between events. The existing `std::directory::walk` remains the
separate API for an owned snapshot.

The implementation is written in Lanius over the existing directory and file
operation bindings. The GPU compiler's Linux x86_64 CPU output passed 60 native
cases and 39 host observer controls. The [fixture guide](../tests/fixtures/stdlib_directory_cursor/README.md)
records the accepted gates, commands and evidence limits.

## API

```text
open(root: Path, limits: Limits) -> Result<Cursor, Error>
open_at(parent_fd: i32, root: Path, limits: Limits) -> Result<Cursor, Error>

Cursor.next() -> Result<Option<Event>, Error>
Cursor.descend() -> Result<i32, Error>
Cursor.prune() -> Result<i32, Error>
Cursor.close() -> Result<i32, Error>
Cursor.work_done() -> u64
Cursor.entries_seen() -> u64

Event {
    Entry(Item),
    Enter(Directory),
    Leave(Directory),
    Fault(Fault)
}
```

`Item` contains a borrowed relative `path`, borrowed basename `name`, `depth`,
no-follow `Metadata`, and borrowed `parent_fd`. The basename is one validated
component, never `.` or `..`. Applications can use the parent descriptor and
basename for their own `open_at` calls while the event remains valid.

`Directory` contains the relative `path`, `depth`, metadata from its opened
descriptor, and borrowed `fd`. `Fault` contains the relative `path`, `depth`,
`stage` and `cause: std::directory::Error`; it does not supply a usable file
descriptor or metadata. Stages are `Metadata`, `Open`, `Verify`, `Read` and
`Close`.

The root is opened during construction. Its first event is `Enter` at depth 0
with an empty relative path; there is no root `Entry`. Direct children have
depth 1. Construction does not retain the supplied root path's backing.
`open_at` borrows its supplied parent descriptor only during construction;
the returned cursor owns the independently opened root descriptor.

## Decisions and event order

Traversal is depth first in the filesystem's enumeration order. It does not
sort entries. Every `Entry` whose metadata identifies a directory pauses the
cursor for an explicit decision:

- `descend()` schedules an attempt to open and verify that child.
- `prune()` schedules continuation with the next sibling.
- `next()` before either decision returns `InvalidState` without advancing.

The decision methods do not open or read anything. The following `next()`
performs the selected transition. A successful descent yields `Enter` before
any child is read, allowing the application to load per-directory rules.
Calling either decision method outside a pending directory entry returns
`InvalidState` and preserves the cursor.

Files, symlinks and other nondirectory entries need no decision. The next call
continues with their sibling. A directory's exhaustion yields `Leave` while
its descriptor is still open. The next mutation consumes that reader and
returns to the parent. Normal exhaustion closes the root and returns `None`;
subsequent `next()` calls return `None` without further work.

Every successful `Enter` has one matching `Leave` during ordinary traversal
and recovery from a subtree fault. Explicit cancellation and terminal resource
errors do not synthesize remaining `Leave` events. Applications must retire
their own parallel state when abandoning a traversal.

## Errors and recovery

Recoverable filesystem failures appear as explicit `Fault` events:

| Fault stage | Context | Continuation on the next call |
| --- | --- | --- |
| `Metadata` | Child metadata lookup failed or omitted required fields | Skip that child and read the next sibling |
| `Open` | A selected child directory could not be opened | Skip that child and read the next sibling |
| `Verify` | Opened child metadata failed or its identity changed | Retire the attempted child and read the next sibling |
| `Read` | The current raw reader failed | Yield that directory's `Leave`, then retire its reader |
| `Close` | Closing after `Leave` failed | Continue with the parent, or finish after the root |

Read faults include Interrupted and WouldBlock. This cursor does not retry a
failed subtree; callers that need direct retry control can use
`std::directory::Reader`. A caller requiring the entire traversal to succeed
can stop and close on the first `Fault`. Faults never mean a consistent
snapshot was produced.

Root open and metadata failures are constructor errors. Cursor errors use:

```text
Error {
    Bounds, InvalidState, Limit, AllocationFailed,
    Closed, Failed, Directory(std::directory::Error)
}
```

Invalid limits or invalid logical root views return `Bounds`. Exhausting a
global entry, path, work or active-directory bound returns `Limit`.
Allocation failures return `AllocationFailed`. These operational errors are
terminal: subsequent traversal calls return `Failed`. They may occur after
the kernel directory position advanced, and they do not roll the traversal
back. The cursor retains its remaining owners until the caller invokes
`close()`.

`close()` is cancellation and final destruction. It attempts every remaining
descriptor close once, frees every reader buffer and the cursor's path/stack
allocations, and reports the first close failure as `Directory(cause)`.
Cleanup is never denied by the work budget. Repeated close succeeds, and
`next()` after explicit close returns `Closed`. Counters remain readable and
unchanged by close. Construction failures release partial resources before
returning; a primary open/metadata/verification error takes precedence over
an error while retiring its temporary reader.

A close error still consumes that descriptor owner. The implementation does
not retry it, following the existing [File contract](stdlib-file-operations.md)
and Linux's descriptor-release behavior. Fault injection that skips a close
syscall can establish one attempt and owner invalidation; it does not emulate
the kernel releasing the descriptor. [Linux close documentation](https://man7.org/linux/man-pages/man2/close.2.html)

## Limits and bounded state

`default_limits()` supplies:

| Field | Default | Accepted values and meaning |
| --- | --- | --- |
| `max_open_dirs` | 64 | 1–4096 active readers, including the root |
| `max_entries` | 65,536 | Any u64; bounds admitted nondot entries |
| `max_path_bytes` | 4095 | 0–i32::MAX bytes in one relative path |
| `max_work` | 134,217,728 | Any u64; deterministic abstract work units |
| `buffer_bytes` | 32,768 | 24–1,048,576 bytes per raw directory reader |

The root path retains the existing binding's 4095-byte path limit. Relative
paths can be longer because child opens use one basename relative to a live
parent descriptor. There is no aggregate result-byte limit: this cursor does
not store previous entries. Path and frame capacities grow geometrically
without exceeding their respective configured bounds. Peak owned state is
the one path, the active frames and at most `max_open_dirs` reader buffers.

An application can impose a requested report depth by pruning directory
entries at that depth. The active-reader cap is a hard resource bound:
attempting `descend()` when that many readers are already open returns a
terminal `Limit` before another directory is opened.

`entries_seen()` counts nondot entries admitted by the entry cap, including
metadata faults and entries that later encounter a path/work/allocation
error. It excludes Enter, Leave and root events. Testing the cap requires
reading the next raw entry; an entry that exceeds it is consumed but neither
counted nor published.

## Work accounting

Work is not elapsed time or an exact instruction count. `work_done()` records
accepted charges. A rejected charge leaves that counter unchanged and marks
the cursor failed.

| Operation | Charge and boundary |
| --- | --- |
| Construction | `buffer_bytes + root.byte_len() + 2`, before allocation/open/metadata |
| An active `next()` | 1, before its transition |
| Raw reader call | Its actual `Reader.work_done()` increase, after the bounded call and before event publication |
| Admitted child | Complete relative-path length + basename length + 2, before path allocation/copy/metadata |
| Scheduled descent | `buffer_bytes + basename length + 2`, before frame reserve/child open/verification |

Decision scheduling, explicit close, fused EOF and rejected state calls make
no charge. The raw reader's decoded byte count is available only after its
call; that call can perform at most three refills before the cursor checks
the remaining work. No child metadata query, new event or descent follows a
failed work check. The raw reader's own record/refill accounting is documented
in [Directory iteration](stdlib-directory.md).

## Borrowing, mutation and filesystem changes

All event views are read-only observations of cursor backing. They expire at
the next cursor mutation, including a successful decision or close. Copy bytes
to retain them. Descriptor fields are borrowed under the same lifetime: do
not close, seek, or enumerate them independently. Descriptor-relative opens
and metadata queries are allowed while the event is live. Copying a Cursor,
frame or reader does not create another cleanup owner. Keep one active owner
and close it explicitly even after exhaustion or error.

Every child receives a no-follow metadata lookup. The cursor requires type and
inode presence, and it does not trust directory-entry type hints. On descent,
it opens a single component with directory-only/no-follow/close-on-exec flags,
then compares the opened device and inode to the caller-visible entry. A
replacement between `Entry` and descent is therefore reported rather than
silently traversed. A symlink replacement fails the no-follow directory open.
The raw kernel type hint may be unknown. [Linux directory-entry documentation](https://man7.org/linux/man-pages/man2/getdents.2.html)

Opened parent descriptors remain anchored to their objects when names change.
The reported path is still an observation and may no longer name that object.
Earlier components of the supplied root may follow symlinks; its final
component is not followed by default. A caller that deliberately supplies
`root/.` opts into resolution of the preceding component, as the recursive
grep consumer does for command-line directory symlinks. Mount crossings are
allowed; repeated directory identities are bounded by the configured resource
limits rather than a global visited set. [Linux descriptor-relative open documentation](https://man7.org/linux/man-pages/man2/open.2.html)

Separate metadata calls do not provide a filesystem transaction, containment
boundary, or immutable snapshot. No-follow child lookup and opened-descriptor
metadata use the existing statx bindings. [Linux statx documentation](https://man7.org/linux/man-pages/man2/statx.2.html)

## Verification scope

Accepted execution uses Linux x86_64 CPU output from the GPU compiler, with
native linking and `LANIUS_ALLOC=mmap`. GPU-device execution, other hosts and
compiler-enforced lifetimes are not claimed.

| Gate | Accepted cases | Coverage |
| --- | ---: | --- |
| Traversal model | 6 | Explicit decisions, pruning, event balance, live borrowed descriptors, raw names and special files, refills, depth, bounded retained state |
| Mutation and root policy | 9 | Root rename, borrowed parent lifetime, directory/symlink/missing-child replacement, root symlink policy and root failures |
| Bounds and cancellation | 20 | Invalid views/limits, exact entry/path/work bounds, reader cap, terminal states and cancellation between events |
| Resource and fault scenarios | 25 | Successful baselines, reached allocation and host-call failures, cleanup after Leave and cancellation close failure |

The model checks exact admitted-entry counts, including metadata faults and
entries rejected by the entry or path cap. Work checks derive the expected
charge from native directory-record extents and checked events. Close and
repeated close preserve both counters. A 16-sibling and a 160-sibling walk have
the same peak source-owned heap extent for equal-length names.

Resource checks account for source allocation extents and descriptor
generations at a paused checkpoint before process exit, then again after exit.
Reached fault checks cover source mmap calls from a small-tree baseline,
additional stack/path growth extents, baseline open/stat/read calls, and two
close paths. Injected close errors skip the kernel operation; the oracle
repairs that descriptor in a separate marked step. Those cases establish one
attempt, owner invalidation and continued cleanup, rather than kernel release
on a real close error. This is finite fault coverage, not every filesystem
schedule or errno.

The independent observer passed 39 positive and negative controls. The
[recursive grep consumer](extended-text-grep-walk.md) separately passed 35
behavior and resource cases using this cursor, including file filtering and
per-directory ignore rules. Those cases are not included in the cursor's 60.
