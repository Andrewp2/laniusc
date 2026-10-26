# Owned temporary files

`std::temp_file` implements named temporary-file ownership in Lanius using OS
entropy and the existing Linux syscall boundary. Source and executable fixtures
are present. The five independent native groups passed **78 process cases**,
covering the selected TempFile ownership, allocation/fault and checked-primitive
scope below. Atomic publication and the `kv_tool` migration remain pending.

The accepted profile is native x86_64 Linux, kernel `7.0.0-38-generic`, with the
oracle's temporary directories on ext4 (`/tmp`, host device `/dev/nvme0n1p4`).
The GPU compiler builds the native program; these host
operations do not execute inside GPU kernels. Other operating systems and
network filesystems have no acceptance claim.

## Construction and inspection

| API | Contract |
| --- | --- |
| `empty() -> TempFile` | Initialize an inactive manual owner without allocation or I/O |
| `default_limits() -> Limits` | 32 name attempts and 128 nonblocking entropy calls |
| `create_in(&self, parent: &File, limits: Limits) -> Result<bool, Failure>` | Duplicate and validate the parent, then exclusively create one temporary file; success is `true` |
| `create_in_excluding(&self, parent: &File, excluded: Path, limits: Limits) -> Result<bool, Failure>` | Additionally validate and exclude one destination component before any creation |
| `borrow() -> &TempFile` | Borrow the same active owner |
| `file() -> &File` | Borrow its read/write file; closed when no file descriptor is owned |
| `directory() -> &File` | Borrow its retained directory anchor for inspection |
| `name() -> View<u8>` | Borrow the created or kept component; empty when no such name is owned |
| `owns_temporary_name() -> bool` | Whether cleanup still has temporary-name deletion authority |
| `state()`, `stats()` | Copy metadata; no host operation |
| `last_cleanup() -> Cleanup` | Copy the latest cleanup receipt |
| `last_failure() -> Option<Failure>` | Copy the first saved failure with current owner state/recovery retention |

Keep one active owner. Copies of `TempFile`, its File fields or its Vec backing
are inactive aliases, not independent resources. There is no automatic
destructor. Do not close, take or replace either borrowed File, write public
owner fields, or use borrowed views after cleanup/reuse. Ordinary file I/O,
seek, metadata and synchronization use the borrowed File while it is live.

Creation borrows the caller's parent only during the call. It acquires its own
CLOEXEC duplicate and checks descriptor metadata and flags, rejecting a closed
descriptor, non-directory, missing file-type metadata or `O_PATH`. The caller
retains its original descriptor and can close it after creation. All subsequent
name operations use the duplicate, including after the parent is renamed.

## Namespace authority and entropy

The parent namespace must be **exclusive or cooperative** for the lifetime of
the temporary name. Other users must not replace, unlink or hard-link that
name. A directory descriptor anchors the parent inode; it cannot secure a
visible child name against hostile directory writers. An inode check before
rename/unlink would not remove this race.

Each candidate is `.tmp-` followed by 32 hexadecimal digits from 16 fresh OS
entropy bytes. Creation requests ReadWrite, create, exclusive, no-follow and
CLOEXEC, with mode `0600` subject to host permission rules. It never requests
truncation. Only a successful exclusive open grants deletion authority.
An `EEXIST` collision obtains fresh entropy and another candidate; it never
opens, truncates or removes the existing file or symlink.

`Limits` contains `name_attempts: u32` in `1..=1024` and `entropy_calls: u64` in
`1..=1048576`. One candidate attempt is charged before filling its entropy;
partial entropy progress and EINTR consume the shared entropy-call allowance.
`std::entropy::fill_bounded` uses `getrandom(GRND_NONBLOCK)`, retries only EINTR
under that allowance and propagates unavailable entropy and other errors.
There is no PRNG, clock, PID or fixed-name fallback. See
[bounded OS entropy](stdlib-entropy-bounded.md).

An excluded destination must be one nonempty raw byte component, no longer
than `MAX_COMPONENT_BYTES` (255), containing neither NUL nor `/`, and neither
`.` nor `..`. Non-UTF-8 bytes are allowed. Logical View bounds are checked;
the caller must still provide valid physical backing. The component is copied
before effects. Equality with a generated name consumes a name/entropy attempt,
increments `Stats.excluded`, and makes **no open attempt**. This prevents an
atomic writer from exposing its destination as an empty temporary file.

`Stats` reports candidate attempts, exclusive-open attempts, actual EEXIST
collisions, excluded equalities and entropy calls separately. Exhausting
candidates returns `Error::NameLimit`; entropy exhaustion retains the nested
entropy failure and its confirmed prefix length. Disk opens and file I/O can
block in the kernel: attempt limits do not establish an elapsed-time deadline.

## Keep, close and cleanup

| API | Contract |
| --- | --- |
| `close_file() -> Result<bool, Failure>` | Retire only the file descriptor once; retain the name and anchor. `false` means it was already closed |
| `keep() -> Result<bool, Error>` | Disarm deletion on this same owner with no I/O/allocation; first call is `true`, repeated keep is `false` |
| `cleanup() -> Result<Cleanup, Failure>` | Close the file once, remove only an owned temporary name, then close its anchor and release backing when removal is resolved |
| `destroy() -> Result<Cleanup, Failure>` | Same fallible cleanup operation |

Keep does not transfer ownership into a second record. It leaves the name
borrow and any remaining file/directory descriptors in this owner. Later
cleanup releases those resources while preserving the kept name. Copy the name
into application-owned storage first if it must outlive cleanup. Keep is also
available after failed removal, when the file descriptor is already closed.
It explicitly accepts responsibility for the remaining named file; it does not
claim that a write, sync or earlier close succeeded.

The states are Inactive, Open, ClosedNamed, Kept, CleanupPending and Released.
Creation may begin only in Inactive or Released with no remaining resources.
An active create attempt returns InvalidState without disturbing that owner or
recording a new primary failure. Other creation errors retain any acquired
backing/anchor in the original owner. The caller must inspect the Failure and
call cleanup even after failed creation. A failing open, excluded candidate or
collision never gives cleanup permission to unlink that candidate.

Cleanup makes at most one file close, one anchored unlink and one directory
close. A close retires its descriptor before the host attempt, including on
EINTR or delayed error; the descriptor number is never retried. Cleanup continues
after a file-close error. Removal distinguishes Removed, AlreadyAbsent,
Unconfirmed and NotOwned. An absent name is explicitly recorded rather than
turned into a fictitious successful unlink.

If removal fails, cleanup retains the name backing, directory descriptor and
deletion authority in CleanupPending. A later explicit cleanup may retry one
unlink, or keep can disarm deletion. Destruction must not free recovery
information while removal remains unresolved. Once removal is resolved or
deletion was disarmed, cleanup retires the anchor and frees backing even if a
close reports an error. Repeated terminal cleanup makes no host call and
refreshes `last_cleanup` with a no-attempt receipt.

`Cleanup` records separate attempted/error fields for file close, removal and
directory close, plus its removal outcome and retained-resource flag. It is
metadata only. `Failure` preserves the first operation's Stage/cause and current
State/Stats. Its cleanup attempt/error fields describe the most recent cleanup
operation, while **Failure.cleanup.retained is recomputed from current owners**.
This makes a failed constructor's retained backing/anchor visible before any
cleanup attempt. `last_cleanup` remains the latest-call snapshot; actual
`close_file` attempts also record their one-close receipt.

Cleanup returns Err only for a new cleanup failure. After an earlier create
failure, successful cleanup returns its Ok receipt, and the original diagnostic
remains available through last_failure. Returned receipts/failures are independent
metadata snapshots. Callers should retain a returned failure if they need its
particular secondary errors after later cleanup refreshes the latest receipt.

No operation scans a directory, removes a prefix, closes the caller's parent
or promises crash scavenging. A process killed before cleanup can leave its
named file. Keep/close/cleanup do not imply storage synchronization or durable
publication. Linux's unlink and descriptor-retirement rules are documented in
[unlink](https://man7.org/linux/man-pages/man2/unlink.2.html) and
[close](https://man7.org/linux/man-pages/man2/close.2.html).

## Checked descriptor-relative primitives

`std::file_ops` adds:

```lanius
pub enum RenamePolicy { Replace, NoReplace }
pub fn remove_file_at(directory_fd: i32, path: Path) -> Result<i32, io::Error>;
pub fn rename_at(old_directory_fd: i32, old_path: Path,
                  new_directory_fd: i32, new_path: Path,
                  policy: RenamePolicy) -> Result<i32, io::Error>;
```

These are general byte-path primitives, following `open_at` semantics. Relative
paths resolve through the corresponding descriptor; absolute paths ignore it.
Intermediate components retain normal host resolution, including symlinks and
`..`. The stricter component and cooperative-namespace policy belongs to the
TempFile owner. Each path has the existing 4095-byte cap and public View/NUL
validation. Rename stages both complete arguments before one host attempt;
an invalid second path cannot cause a partial operation.

Removal uses unlinkat flags zero and does not remove directories. Rename uses
renameat2 with flags zero for Replace or RENAME_NOREPLACE for NoReplace. Host
errno, including unsupported kernel/filesystem flags, propagates. There is no
copy/delete or existence-check fallback. Only a zero native result is accepted;
unexpected nonzero success counts return InvalidCount. Namespace visibility
does not imply durability, and storage/network error effects can be uncertain.
See [rename](https://man7.org/linux/man-pages/man2/rename.2.html).

## Focused executable gate

[`tests/stdlib_temp_file_execution.rs`](../tests/stdlib_temp_file_execution.rs)
contains five narrow groups: owner, collisions, validation, faults and
primitives. Lanius probes perform all library effects. An independent host
oracle checks filesystem bytes, source allocations and native descriptor
ownership. The owner probe holds the process alive after cleanup so `/proc`
inspection can confirm no residual descriptors or heap mappings before exit.
Deterministic entropy and close failures are labelled syscall injections;
synthetic skipped close calls receive a separate, test-only raw-fd repair.

All five groups passed on the frozen final ELFs:

| Group | Native process cases | Receipt under `target/stdlib-work/` |
| --- | ---: | --- |
| owner | 8 | `temp-file-owner-group-first.log` |
| collisions | 6 | `temp-file-collisions-first.log` |
| validation | 18 | `temp-file-validation-first.log` |
| faults | 19 | `temp-file-faults-first.log` |
| primitives | 27 | `file-at-primitives-group-first.log` |

These are process counts, including repeated fault baselines, rather than 78
distinct input behaviors. The fixture [acceptance notes](../tests/fixtures/stdlib_execution/temp_file/README.md)
record the independent oracle controls and resource-ledger scope.

The owner group verifies binary/empty/large contents, keep, explicit close,
repeated cleanup, parent rename/replacement anchoring, already-absent removal
and active-create rejection. Collision cases trace actual entropy bytes and
exclusive opens, including existing files/symlinks, bounded exhaustion and
excluded equality before any candidate open. Validation covers all selected
invalid names/limits and regular, closed and O_PATH parent descriptors.

The fault group reached the single 37-byte source allocation, injected its OOM,
and checked duplicate/metadata/flags/open, entropy and cleanup failures. Its 19
cases include the baselines and that one reached allocation failure. Failed
removal retains recovery authority for retry or keep. File/anchor close errors
retire each production owner once; the separately labelled raw repair only
releases the descriptor that strace's injected error deliberately left live.
Every accepted process passed the independent source-allocation/FD-generation
ledger, namespace checks and applicable held-process `/proc` observations.
These finite cases do not prove crash durability or hostile-directory safety.
Failed-construction cases also preserve the original Stage/cause through later
cleanup. Independent source review corrected a metadata-only issue before these
gates: failure receipts now derive retained ownership from actual resources,
while `last_cleanup` keeps its latest-call snapshot semantics.

The primitive group checks relative/absolute/nested/raw paths, replacement and
NoReplace conflicts, final symlinks, host errors, one-attempt injected failures,
unexpected return counts and the bounded-view consumer described below.

The initial checked-primitive bounds consumer compiled and passed one native
case with 11 rejected preflights, exactly two renameat2 calls and one unlinkat.
The real trace confirms that malformed/NUL/4096-byte paths caused no mutation
attempt, followed by successful same-name Replace, NoReplace `src` to `dst`
and removal. Receipts are `target/stdlib-work/file-at-bounds-first-compile.log`
and `target/stdlib-work/file-at-bounds-native.log`; the raw ELF is
`target/stdlib-work/file-at-bounds`. This establishes that finite primitive
scope. It overlaps the accepted primitive group's bounds case and adds no
additional distinct process case to the 78 above.

The final owner probe compiled, then its preliminary mode-0 native case passed
creation, binary write/readback and cleanup. It observed one real getrandom,
one unlink, an actual `.tmp-` plus 32-hex name and an empty anchored directory.
Before ACK/process exit, only descriptors 0/1/2 remained; the latest repeated
cleanup receipt reported no attempts or retained owners. Receipt:
`target/stdlib-work/temp-file-owner-basic-native.log` (`cases=1`). This overlaps
the accepted owner group's mode 0 and adds no additional distinct process case.
That preliminary receipt alone did not establish source-map or fault behavior;
the five independent group receipts supply the scope stated above.

Compiler admission history is separate:

- `temp-file-owner-first-compile.log` stopped before native execution with
  `LNC0016`: five typed-local generic closings written `>=` needed `> =` spacing.
- `temp-file-owner-spacing-retry-compile.log` records the successful admission
  retry, exit 0.
- `temp-file-owner-final-probe-compile.log` records successful final admission,
  exit 0, including the labelled skipped-close repair for the explicit
  close_file fault case.

These logs are under `target/stdlib-work/`. The native groups ran serially,
with each command bounded to two minutes. The Rust test driver also passed
Cargo build admission (`--no-run`), recorded in
`target/stdlib-work/temp-file-test-driver-build.log` with test binary
`stdlib_temp_file_execution-3366ea7d07c51ce1`. This is a build check, not an
additional native case: the five accepted runtime groups ran directly against
the frozen compiler-produced ELFs.

Atomic publication and the `kv_tool` migration remain the next phase described
in the [atomic-files plan](library-atomic-files-plan.md).
