# Owned temporary files and atomic publication

This workflow is implemented and accepted on the finite native x86_64 Linux
profile recorded in the module guides. The prerequisite TempFile owner and
checked descriptor-relative primitives passed 78 native process invocations
across five groups, including repeated baselines; the
[TempFile guide](stdlib-temp-files.md)
records exact scope and receipts. `std::atomic_file` passed four focused groups
with 66 process invocations; its [guide](stdlib-atomic-files.md) records the
owner, bounds, publication and fault receipts. The migrated `kv_tool` passed its
separate [application gates](extended-kv.md#current-application-receipts).
These receipts do not complete the overall standard-library goal or establish
crash durability.

Build one complete workflow: create an owned temporary regular file in an
anchored directory, write bounded data, then either keep it, remove it, or
publish it under one destination name. Start with native **x86_64 Linux** on
explicitly tested local filesystems. GPU kernels, other operating systems,
network filesystems and universal power-loss durability are outside this scope.

## Existing foundation and consumer

- [`std::file_ops`](../stdlib/std/file_ops.lani) already supplies `open_at`,
  exclusive creation, no-follow/CLOEXEC options, CLOEXEC descriptor duplication,
  descriptor metadata and `sync_all`/`sync_data`. It now also supplies checked
  `remove_file_at` and `rename_at` with Replace/NoReplace policy.
- [`std::entropy`](../stdlib/std/entropy.lani) supplies bounded nonblocking OS
  entropy. Its `fill_bounded` uses `getrandom(GRND_NONBLOCK)` with an explicit
  call budget. It does not implement cryptographic primitives.
- [`std::file`](../stdlib/std/file.lani) is a manual descriptor owner. `close`
  retires its descriptor before one host attempt, including on error. `flush`
  does not synchronize storage.
- [`std::filesystem`](../stdlib/std/filesystem.lani) supplies checked pathname
  rename/unlink; the descriptor-relative mutations live in `std::file_ops`.
- [`kv_tool::save`](../sample_programs/library/kv_tool.lani) now uses the bounded
  AtomicFile owner. It replaced a caller-selected SCRATCH flow that followed a
  final symlink, ignored removal failures and omitted synchronization. `init`
  now uses NoReplace instead of checking absence before a replacing rename.

The new workflow belongs in host-backed std modules, separate from portable
core utilities. `std::temp_file` supplies ownership and `std::atomic_file`
supplies publication policy over that owner. Consumers share the implementation
instead of building independent scratch-file mechanisms.

## Directory authority and names

The constructor borrows a live directory `File`, duplicates it with
`F_DUPFD_CLOEXEC`, and verifies directory metadata. The new owner retains that
duplicate through cleanup or publication. The caller's descriptor remains its
own owner. Creation, removal, rename and directory sync all use this same anchor.
No operation reconstructs a full path or depends on the current directory.
Reject missing file-type metadata, a non-directory, and `O_PATH` descriptors;
the anchor must support ordinary directory I/O, including the attempted sync.

Require **exclusive or cooperative mutation authority over the parent namespace**
through the operation. Other participants must not replace, unlink or hard-link
the temporary name. This is an application precondition; metadata cannot prove
it. A directory descriptor fixes parent identity, including after a parent
rename. It does not protect a visible child name against hostile directory
writers. Checking inode identity before rename/unlink does not close that race.

Accept destination names as one raw byte component: nonempty, at most 255 bytes
as an API limit, no NUL, no `/`, and neither `.` nor `..`. Preserve non-UTF-8
bytes. A host can impose a smaller component limit. Validate public View bounds
and copy names into owned backing before effects; do not retain caller storage.
The caller must supply valid physical backing for borrowed input views.

Generate each candidate as `.tmp-` plus 32 hexadecimal digits from **16 fresh OS
entropy bytes**. Reject a candidate equal to the destination. Open with
ReadWrite, create, exclusive, no-follow and CLOEXEC, requesting mode `0600`;
never truncate an existing name. The requested mode remains subject to host
permission rules. Only `EEXIST` advances to a fresh candidate. Stop at the
finite collision or shared entropy-call limit. Entropy errors, including
unavailability, propagate; there is no PID, clock, deterministic PRNG or fixed
name fallback. Exclusive creation remains the authoritative collision check.
See Linux [open](https://man7.org/linux/man-pages/man2/open.2.html) and
[getrandom](https://man7.org/linux/man-pages/man2/getrandom.2.html).

## Owners and cleanup

Use an initialized, inactive owner and fallible in-place operations. An error
returns metadata; any acquired descriptor, owned name or cleanup authority stays
in the same inspectable owner. This avoids losing resources inside a failed
constructor or an ignored `Result`. Allocate name backing before creation;
commit, keep and failure cleanup must need no new allocation.

| State | Authority and permitted next actions |
| --- | --- |
| Inactive | No native or name owner; creation may begin |
| Open | Own file, directory anchor and temporary-name deletion; write, keep, cleanup or commit |
| ClosedNamed | File descriptor retired; name/anchor remain; internal commit continuation, keep or cleanup |
| Kept | Same owner retains file/name/anchor, but deletion is disarmed; cleanup releases resources and preserves the name |
| FailedBeforePublication | Preserve primary error and any remaining owners; keep or explicit cleanup |
| PublicationUnconfirmed | A rename returned an error whose effect is unconfirmed; inspect/keep recovery information or explicitly clean only the temporary name; never repeat rename automatically |
| Published | Temporary deletion authority permanently disarmed; retain anchor if directory sync needs retry |
| Released | All descriptors and backing released or transferred; repeated cleanup has no effects |

`keep` transitions the same owner into Kept, disarming temporary deletion
without I/O or allocation. It retains the name and any live file/directory
descriptors until explicit cleanup; no second manual owner is introduced.
The file borrow reports whether its descriptor is still open. Keeping does
not promise persistence. A borrowed
temporary File permits ordinary I/O only while its owner is live; callers must
not close it, duplicate active owner copies or mutate owner fields. Atomic
publication exposes its own bounded sequential writer instead of a raw File
borrow that could bypass its byte and call limits.

One `cleanup` call closes a live temporary descriptor once and attempts at most
one anchored unlink of its temporary leaf. Record close and unlink outcomes
separately, preserving an earlier primary error. `ENOENT` is reported as already
absent. On unresolved removal, retain the anchor, name and cleanup authority so
the caller can retry cleanup explicitly or keep the remaining named file. Once the
name is absent, close the anchor once and release backing. Never unlink a
published destination, scan a directory or remove names matching a prefix.

`destroy` is fallible cleanup: it must retain an owner with unresolved name
removal rather than free its recovery information. Returned cleanup metadata
distinguishes attempted removal, removed/already-absent/unconfirmed name,
descriptor retirement and close errors. Repeating successful cleanup is inert.
Linux close errors never trigger retry of the retired descriptor number.
Cleanup of Published state only retires its retained anchor; it cannot change
the destination or turn unconfirmed directory durability into success.
Process termination can leave a named temporary file; no crash scavenger or
automatic language destructor is promised. See
[unlink](https://man7.org/linux/man-pages/man2/unlink.2.html) and
[close](https://man7.org/linux/man-pages/man2/close.2.html).

## Publication contract

Choose an explicit policy: `Replace` or `NoReplace`. The latter is necessary
for `kv_tool init`; an existence check followed by replacement is insufficient.
Commit freezes writes, requires all writer borrows to be quiescent, and performs:

1. `sync_all` on the completed temporary file.
2. One file close. A sync or close error prevents the rename attempt.
3. One anchored rename from temporary leaf to destination leaf in the same
   directory, with the selected replacement policy.
4. **Immediately upon rename success, record Published and disarm temporary
   deletion**, before any further fallible call.
5. `sync_all` on the directory anchor, then retire the anchor and free backing.

Return a receipt with visibility (`NotPublished`, `Published`, or `Unconfirmed`),
confirmed written bytes, file-sync and directory-sync outcomes, current phase,
remaining recovery authority and distinct cleanup errors. A normal fully
released success requires both syncs and all closes to succeed. Errors also
carry the receipt; a bare I/O error must never hide publication.
Receipts and failures own metadata only. Name views borrow the live owner and
expire when its backing is transferred or released.

If rename succeeds but directory sync fails, return **Published with directory
durability unconfirmed** and keep the anchor for explicit `retry_directory_sync`.
That retry performs at most one sync attempt; it never writes, renames or rolls
back, and retires the anchor on success. A later anchor-close error likewise
leaves Published/file-synced/dir-synced facts intact. The target must never be
deleted as error cleanup. Repeated commit returns its cached receipt without
another syscall; retries use only the explicit sync/cleanup operations.

Before successful rename, cleanup touches only the temporary leaf. Preserve
unconfirmed visibility when a rename error does not establish its effect;
do not retry the rename or claim that the old target survived. This matters
especially for storage errors and NFS replay ambiguity, which is one reason
network filesystems are outside initial guarantees. `NoReplace` conflicts and
unsupported filesystem flags remain explicit errors; no weaker fallback.
Replacement acts on a destination symlink itself, not its target. See
[rename](https://man7.org/linux/man-pages/man2/rename.2.html).

Atomic namespace visibility concerns one destination name. Existing readers
may retain an old open file, and other hard links are unchanged. Publication
does not supply locking, compare-and-swap, multi-file transactions or protection
against lost updates. Replacing a file uses the new file's permissions and
metadata; it does not preserve the old file's ACL, owner or timestamps.
Default publication requests private `0600`; broader metadata policies can be
added explicitly later. File sync alone does not persist the directory entry;
both successful syncs still rely on filesystem/device guarantees, rather than
proving survival of every hardware failure. See
[fsync](https://man7.org/linux/man-pages/man2/fsync.2.html).

## Host primitives and bounds

Two checked wrappers over the existing `std::linux::call` are now implemented
in `std::file_ops` and covered by the accepted prerequisite gates. They stage
and validate all paths before effects, validate a zero success result, preserve
errno and make one attempt without allocation or retries:

| Primitive | Linux x86_64 call and arguments |
| --- | --- |
| Anchored file removal | `unlinkat`: syscall `263`, arguments `(dirfd, leaf, 0)` |
| Anchored publication | `renameat2`: syscall `316`, arguments `(dirfd, old_leaf, dirfd, new_leaf, flags)`; flags `0` for Replace, `1` for `RENAME_NOREPLACE` |

Zero rename flags have renameat semantics. `NoReplace` needs filesystem support;
unsupported kernel/filesystem errors propagate. These are Lanius wrappers,
not new externs, compiler operations, native glue or ABI requirements. Syscall
numbers are also present in the host's `asm/unistd_64.h`. A separate renameat
wrapper, temporary directories, `O_TMPFILE`/linkat publication, hostile shared
directories and metadata preservation are deferred.

Creation accepts finite positive name-attempt and entropy-call budgets.
Publication additionally requires a maximum confirmed byte count and finite
write-attempt allowance. Charge partial writes and EINTR attempts; zero progress
is a typed failure and no remaining operation can replenish a budget. Checked
counter arithmetic prevents overflow. Reject a write request exceeding the
remaining byte allowance before effects; empty writes make no host call. Check
returned counts and retain the exact confirmed prefix on failure.
Each commit phase has one host attempt;
explicit sync/cleanup retries are separate bounded calls. Mandatory descriptor
retirement is never suppressed by an exhausted work budget.

These limits bound library work and attempts, **not syscall duration**. Regular
file writes, opens and fsync can block in the kernel. Do not claim a cooperative
deadline or async disk I/O; native tests need an external process timeout.

## Implementation and executable acceptance

The anchored primitives, shared TempFile owner, bounded AtomicFile wrapper and
`kv_tool` migration are implemented. AtomicFile's accepted source SHA-256 starts
`9e0a9709`; its four groups passed 66 native process invocations against one
frozen probe ELF on Linux 7.0.0-38-generic/x86_64 with local ext4 process
directories. Counts include repeated baselines. The two baseline-reached source
allocations were denied individually, and publication retry was independently
observed while Published still retained its anchor. Exact receipts and limits
are in the [AtomicFile guide](stdlib-atomic-files.md#executable-acceptance).

The first bounds gate exposed an oracle fd-selector error: stderr phase markers
were counted as file payload writes. The inspected trace had no owned-file
write. The selector correction and two CPU controls brought the harness total
to 36 controls; the full bounds retry reused unchanged production/probe code
and the same ELF. The preliminary smoke overlaps current groups. Both Rust test
drivers passed build admission separately from native runtime acceptance.

The migrated application removes the SCRATCH argument, uses NoReplace for init
and Replace for updates, preserves snapshot limits, and reports publication
uncertainty and cleanup failures. Its 64 process invocations are documented
separately in the [KV guide](extended-kv.md#current-application-receipts), rather
than counted as AtomicFile cases. Concurrent read/modify/write updates still
require application coordination.

The original focused test strategy is retained below. The module and fixture
guides state which finite cases were executed; this checklist is not a claim
that every possible fault, target or crash scenario was tested.

Focused x86 execution tests cover or should continue to cover:

- Real exclusive creation, final-symlink collisions, private requested mode,
  CLOEXEC on both descriptors, exact binary/empty/large contents, keep/cleanup,
  transferred-owner disarming and repeat terminal calls.
- Raw names and malformed View/component/limit rejection before effects;
  changed cwd and renamed/replaced parent paths still operate in the anchored
  original directory. Do not present these as hostile child-name race tests.
- Controlled entropy/collision cases: fresh candidates, exhaustion, short
  reads/EINTR/EAGAIN, no predictable fallback and no preexisting-file truncation.
  Inject entropy only in the host-side test harness, not through a public
  insecure random-source alternative.
- Reached partial-write, no-progress, ENOSPC, file-sync, file-close, rename,
  unlink and directory-close failures. Bind injection to the owned fd/inode and
  distinguish injected results from real filesystem observations.
- The critical post-rename directory-sync failure: independently observe the
  full new target, Published receipt, retained anchor, no destination unlink and
  no second rename during explicit sync retry. Also retain uncertainty after an
  injected ambiguous rename result instead of declaring rollback.
- Real NoReplace contention: exactly one initial creator succeeds and the
  other never overwrites it. Existing-target readers observe complete old or
  new snapshots. Test killed-process phases only for observed namespace state;
  they are not power-cut durability tests.
- Every reached source allocation and native-owner acquisition/unwind, including
  cleanup failure followed by keep or retry. Count exact closes and require no
  live source owners after complete release.

Production logic remains in Lanius; host-side tests arrange and inspect the
filesystem. Every acceptance command stays under two minutes. No new compiler,
native-glue or cryptographic implementation was required. GPU kernels, other
operating systems, network filesystems, hostile parent namespaces, metadata
preservation and power-cut durability remain outside this accepted profile.
