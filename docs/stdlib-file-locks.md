# Advisory whole-file locks

`std::file_ops` adds borrowed File locking through the existing Linux syscall
service. The [fixed locking plan](library-file-locking-plan.md) defines this
increment. Native policy/fault, state-model, process and locked-application
gates pass on the finite Linux x86_64/local-filesystem profile below. This
selected increment is accepted.
Earlier descriptor, positional-I/O and file-patch receipts retain their own
source/API scope. The whole standard and extended library goal remains open.

## Interface and one-attempt behavior

```lani
pub enum LockMode { Shared, Exclusive }
pub enum LockWait { Blocking, Nonblocking }
pub fn lock(file:&File,mode:LockMode,wait:LockWait) -> Result<i32,Error>;
pub fn unlock(file:&File) -> Result<i32,Error>;
```

A closed logical File returns `Host(9)` without a host call. A live File
causes exactly one `flock` syscall (73), using these operation bits:

| Request | Operation |
| --- | ---: |
| Shared, Blocking | `LOCK_SH = 1` |
| Exclusive, Blocking | `LOCK_EX = 2` |
| Shared, Nonblocking | `LOCK_SH \| LOCK_NB = 5` |
| Exclusive, Nonblocking | `LOCK_EX \| LOCK_NB = 6` |
| Unlock | `LOCK_UN = 8` |

Only an exact zero host result returns `Ok(0)`. A malformed nonzero success
returns `InvalidCount`. Existing error mapping returns `Interrupted` for
EINTR, `WouldBlock` for EAGAIN/EWOULDBLOCK and `Host(errno)` for other native
errors. No acquisition or unlock retries, spins or falls back. Unlocking a
live File with no lock still makes the host call; there is no cached
success/no-op branch.

Blocking can wait indefinitely. One host attempt supplies no deadline,
cancellation or deadlock detection. Nonblocking asks once and reports
contention directly. `LockWait` selects the operation bits; it does not set
descriptor status flags. The functions allocate no heap storage and do not
seek, flush, synchronize, unlock implicitly or close the File.

## Lock lifetime and manual coordination

The [Linux flock contract](https://man7.org/linux/man-pages/man2/flock.2.html)
defines an open-description lock. Duplicates share it: any duplicate can
change or release it, and one close need not release it while another
duplicate remains. Independent opens compete, even in one process. Shared
holders coexist; an exclusive holder excludes cooperating independent opens.
Repeated acquisition does not count nested ownership. Conversion may release
the previous mode before acquiring the next; failure does not promise the
old lock remains held.

The APIs borrow a File without creating a guard or a new cleanup owner.
`File` copies alias one descriptor; `duplicate` creates another descriptor
for the same open description. Keep each descriptor's manual owner valid and
coordinate every alias/duplicate's lock, unlock and close calls. One handle's
scope cannot describe the lock's lifetime. See
[descriptor ownership and duplication](stdlib-file-operations.md).

After a failed conversion, later compatibility must not be predicted from
the former mode alone. An explicit unlock can normalize the description's
state when the caller coordinates all aliases. An unlock error does not
acknowledge release. A malformed lock result does not acknowledge acquisition.
There is no library-maintained held flag, reference count or rollback.

## Filesystem and protection scope

This is advisory whole-file locking on the selected local Linux profile.
Cooperating clients lock the same file identity around their protected work.
The wrapper does not protect replacement of a pathname, prevent unrelated
writers from ignoring the protocol or undo completed writes. It supplies no
byte-range lock, transaction or durability guarantee.

NFS can emulate flock using other locking machinery; SMB may impose mandatory
I/O failures. Protocol, server and mount choices affect those semantics.
Those environments require separate evidence and are outside this increment's
local-filesystem claim. The host error is returned without a compatibility
fallback. These qualifications follow the Linux reference linked above.

## Cooperative file-patch mode

The existing [file-patch program](stdlib-file-patch.md) gains one explicit
mode through the same preflight, positional operation and cleanup path:

```sh
file_patch [--lock] PATH OFFSET EXPECTED_HEX REPLACEMENT_HEX
```

`--lock` is recognized only as a leading fifth operand; the four-operand
workflow still treats its path literally. Sole `--help` / `-h` retains help
behavior. All path, numeric/span and hex validation/decoding happens before
open. Payload limits and sixteen-attempt positional read/write budgets retain
the preceding contract.

After open, locked mode attempts one nonblocking Exclusive acquisition before
any positional read. Acquisition failure skips the patch and unlock, then
closes once and reports status 6 with `file_patch: lock failed`. Only
acknowledged acquisition enables the unlock phase; malformed success still
closes the sole owner.

After acquisition, the program runs the existing read/compare/write, attempts
unlock once, then close once regardless of unlock success. Diagnostics follow
cleanup in phase/unlock/close order. Status precedence is a primary patch
failure, then unlock failure (6), then close failure (3), then success (0).
There is no cleanup retry. Data can already be changed when cleanup fails.

The mode coordinates clients honoring the same lock protocol across the
comparison/write interval. It is not concurrent compare-and-swap, protection
from path replacement, transactional rollback or crash durability. The
unlocked mode retains its own meaningful workflow and prior evidence.
All four locked-application groups pass with 49 unique process cases. The
ordinary four-operand corpus has its own current regression receipt.

## Verification and target

| Accepted gate | Observation | Receipt under `target/stdlib-work/` |
| --- | --- | --- |
| Native lock policy/contracts, one test | Actual compatibility, description/duplicate lifetime and one-attempt policies | `file-lock-native-first.log`, 6.86s; the other fault test failed its tool-warning harness |
| Native faults, one final test | 16 schedules, 14 reached injections and two controls; exact-zero check includes 4,294,967,296 | `file-lock-native-fault-final.log`, 5.45s |
| Independent state model, one test | 1,287 programs / 24,244 steps / four owner slots; seed `0xf10c20261030` | `file-lock-model-first.log`, 5.76s |
| Separate-process blocking, one test | A `/proc` witness observes syscall 73 / LOCK_EX before explicit release and wakeup | `file-lock-process-blocking.log`, 5.97s |
| Separate-process lifetime, three tests | Six peer lifecycles across all four process tests; three observed waits, duplicate retention and last-close/process-exit release | `file-lock-process-lifetime.log`, 5.37s; blocking test filtered |
| Locked file-patch model, one test | Fifteen new locked-mode cases | `file-lock-app-model-first.log`, 7.73s |
| Locked file-patch boundaries, three tests | Bounds15 + faults15 + protection4; all four new application groups total 49 unique cases | `file-lock-app-boundaries.log`, 7.62s; model filtered |
| Existing positional native contract, one test | Amended full-span/staging/cursor contract executes against new FileOps source `9ca5ca58` | `file-lock-positional-regression.log`, 6.74s |
| Ordinary file-patch workflow, four tests | All 82 existing unlocked process cases execute against app source `b2a6984c` | `file-lock-file-patch-regression.log`, 7.73s |

The last two rows are selected current regressions. The 82 ordinary application
cases repeat the earlier corpus; they remain separate from the 49 new locked
cases. No full descriptor/positional suite rerun is claimed.

The first native command's policy test passed while its fault test rejected a
strace compatibility warning for a large positive injected result. The final
fault-only run permits only that exact warning in that case, while requiring
the actual 64-bit result and `InvalidCount`. Other unexpected tool output
still fails. Production remains unchanged.

The [native fixture guide](../tests/fixtures/stdlib_foundation/file_lock/README.md)
records 39 actual lock syscalls in the policy fixture, unchanged content,
cursor/status and no allocation/sync/hidden close. Its two test identities
are accepted across the mixed policy receipt and final fault-only receipt.

The [independent model](../tests/fixtures/stdlib_foundation/file_lock_model/README.md)
compares real opens, duplicates, lock/unlock, close/reopen and seek with four
manual owner slots. It observes 949 WouldBlock results, including 138 failed
conversions, then normalizes each with explicit unlock before predicting
later compatibility. It checks bytes, descriptor uniqueness/owner state,
shared cursor/status and per-handle close-on-exec. Each program ends with a
last-close/reacquire control; no atomic old-mode retention assumption is added.

The [process fixtures](../tests/fixtures/stdlib_foundation/file_lock_process/README.md)
use explicit readiness/release handshakes and kernel wait witnesses. Across
six native peer lifecycles, all three blocking waits are observed at syscall
73 with the advertised descriptor and LOCK_EX before controlling-host unlock,
last-duplicate close or process-exit release. The four tests check real
nonblocking contention, duplicate retention, wakeup, bytes/cursors and exact
lock/close counts, with no allocation or sync calls. Their scope is the tested
local filesystem.

The [locked application fixtures](../tests/fixtures/stdlib_execution/locked_file_patch/README.md)
include 15 fault processes with 18 reached injected errors. Protection cases
use independent host-lock probes during actual positional reads/writes and
observe release before close. Injected cleanup results establish attempt and
status policy; they do not turn skipped host calls into executed kernel
cleanup. Earlier positional/application cases retain their historical scope.

Accepted production identities:

| Source | SHA-256 |
| --- | --- |
| `stdlib/std/file_ops.lani` | `9ca5ca58e09b39342c6409bded385b18e08d7488de233d32a87fe82826cf9f8a` |
| `sample_programs/library/file_patch.lani` | `b2a6984c1bf73d0092327286bf858725ee729dcb4a51f1b13876160fa9ad7528` |

The selected target is native Linux x86_64 CPU output from the GPU compiler
on a tested local filesystem. Production is Lanius using the existing
`std::linux` service. Other filesystem/platform behavior, GPU device execution,
automatic or affine ownership and formal proof remain unclaimed.
