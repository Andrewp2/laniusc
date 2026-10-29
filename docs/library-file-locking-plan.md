# Advisory file locking

Complete the missing whole-file locking boundary in `std::file_ops`, using
the existing Linux syscall service and File owner. Integrate it into the real
file-patching application so cooperating processes can protect its read,
comparison and writes. The previous positional increment is committed at
`fe36d541`; the whole standard/extended-library goal remains open.

## Native interface and responsibility

```lani
pub enum LockMode { Shared, Exclusive }
pub enum LockWait { Blocking, Nonblocking }
pub fn lock(file:&File,mode:LockMode,wait:LockWait)->Result<i32,Error>;
pub fn unlock(file:&File)->Result<i32,Error>;
```

Both functions borrow a live File. A closed logical owner returns Host(9)
without a host call. Otherwise make one syscall 73, using LOCK_SH=1,
LOCK_EX=2, optional LOCK_NB=4 or LOCK_UN=8. Only an exact zero host result
succeeds; malformed nonzero successes are InvalidCount. Preserve existing
Interrupted/WouldBlock/Host errno mapping; no retry, fallback, allocation,
seek, flush, implicit unlock or close. Blocking mode can wait indefinitely
and supplies no deadline/cancellation/deadlock detection. Nonblocking is one
attempt, not a spin loop. Unlock without a held lock remains a host operation.

The [Linux flock contract](https://man7.org/linux/man-pages/man2/flock.2.html)
is the source of truth. On the tested local Linux filesystem, shared holders
coexist and an exclusive holder excludes cooperating independent opens.
The lock belongs to the open file description: duplicates share one lock,
any duplicate can change/release it, and closing only one duplicate does not
necessarily release it. Independent opens compete even within one process.
Repeated acquisitions are not reference counted. Conversion is not promised
atomic, and a failed conversion must not be assumed to retain the old lock.

These are advisory, whole-file, descriptor-based locks, with no byte-range,
pathname replacement protection, content rollback, crash durability or
cross-filesystem semantic guarantee. Other writers can ignore the protocol;
NFS/SMB and mount-dependent behavior require separate evidence. Callers keep
the borrowed owner live and coordinate every alias/duplicate's lock/close
operations. Do not add a single-handle RAII guard that pretends to own the
shared lock state. Language-level affine ownership remains future work.

## File-patch integration

Retain the meaningful unlocked four-operand workflow and add one explicit
cooperative mode using the same implementation:

```sh
file_patch [--lock] PATH OFFSET EXPECTED_HEX REPLACEMENT_HEX
```

Recognize `--lock` only as a leading fifth operand; four operands still treat
all paths literally. Sole --help/-h still works. Snapshot at most five
operands and retain the existing 24576-byte admission cap. Validate and decode
everything before opening, as before. Shared argument/preflight, positional
read/compare/write, cleanup and reporting must not be copied into a second
program or a parallel unlocked implementation.

With --lock, after the one ReadWrite open, make one nonblocking Exclusive lock
attempt. On acquisition error, skip reads, writes and unlock; close once, and
return 6 with `file_patch: lock failed\n` before any secondary close diagnostic.
On successful acquisition, run the existing bounded read/compare/write. Then
attempt unlock exactly once, and close exactly once regardless of unlock
success. All phase/cleanup diagnostics happen after those cleanup attempts.
Return the primary patch status on patch failure; otherwise unlock failure
returns 6 and close failure returns 3. An unlock failure reports
`file_patch: unlock failed\n` after any primary phase diagnostic, before a
secondary close diagnostic. No implicit retry. A malformed lock success is
not treated as acknowledged acquisition; close still retires the sole owner.

Acquisition/cleanup failure can occur after data changes; no rollback. The
locked workflow protects cooperating clients locking the same file identity,
not writers that ignore locks or replace its path. File contents, positional
cursor behavior, sixteen-call read/write budgets and payload limits retain
the positional contract. Help must explain both modes and status 6; migrate
the internal oracle's help expectation directly, with no compatibility alias.

## Acceptance

- Actual independent-open shared/exclusive compatibility, repeated locks,
  safe conversion, duplicate sharing/unlock and last-close lifetime; closed
  owners, unchanged content/offset/status, no heap or hidden sync/close.
- An independent bounded state-machine corpus over several open descriptions
  and duplicate handles, compared with real native operations. Failed mode
  conversion may lose the old lock: model uncertainty or normalize with
  explicit unlock before predicting later compatibility; do not promise
  stronger atomicity than the API.
- Native errno/result injection, including acquisition and unlock errors,
  exact-zero admission, no retries and logical owner state preserved.
- Real separate-process contention and blocking wakeup, using explicit pipe
  readiness/release handshakes and bounded child deadlines, not sleeps.
- File-patch --lock functional/preflight/failure/cleanup tests, held-lock
  contention with no reads/writes, explicit release before close, true
  separate-process protection across the comparison/write interval, and
  interoperability with the host flock implementation. Ordinary mode retains
  its behavior through focused existing app regressions.
- Focused existing FileOps/positional regressions, guides/reference matching
  executable receipts, stable manual ownership and explicit target scope.

Production is Lanius only. Test drivers/oracles can use host APIs as independent
controls, without a production JSON bridge. Root serializes all compiler,
native and Cargo commands under the existing lock, each command below two
minutes. Preserve root README, AI_POLICY, CONTRIBUTING, compiler, runtime ABI
and proof sources. Missing compiler support gets a minimal reproduction.
