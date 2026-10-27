# Owned temporary directories

`std::temp_dir` implements a named temporary-directory owner in Lanius, using
the existing checked file operations and bounded OS entropy. The complete
source has passed four focused native groups reporting 46 accepted group
cases. Those finite ownership, entropy and failure receipts are recorded
below; they include overlapping baselines rather than 46 distinct behaviors.

The accepted profile is native x86_64 Linux, kernel `7.0.0-38-generic`, with
test-owned directories on ext4 under `/tmp`. The GPU compiler emits the host
CPU executable; directory operations do not run in a user-program GPU kernel.
Other hosts, targets and filesystems have no execution claim. See the
[filesystem increment plan](library-filesystem-completion-plan.md).

## Public API

| API | Contract |
| --- | --- |
| `empty() -> TempDir` | An inactive manual owner, with no allocation or I/O |
| `default_limits() -> Limits` | 32 candidate names and 128 entropy calls |
| `TempDir.borrow() -> &TempDir` | Borrow the same active owner |
| `create_in(&self, parent: &File, limits: Limits) -> Result<bool, Failure>` | Validate and duplicate the parent, create one directory, then open it; success is `true` |
| `parent() -> &File` | Borrow the retained parent duplicate |
| `directory() -> &File` | Borrow the created child directory; closed before successful child open or after explicit close |
| `name() -> View<u8>` | Borrow the created/kept 37-byte component, or an empty view before successful mkdir |
| `owns_temporary_name() -> bool` | Whether this owner still has temporary-directory removal duty |
| `state() -> State`, `stats() -> Stats` | Copy metadata without I/O |
| `last_cleanup() -> Cleanup` | Latest cleanup/actual child-close snapshot |
| `last_failure() -> Option<Failure>` | First saved Stage/cause, with current state/stats and latest cleanup facts |
| `close_directory() -> Result<bool, Failure>` | Retire only the child descriptor once; `false` means it was already closed |
| `keep() -> Result<bool, Error>` | Disarm removal without allocation or I/O; repeated keep before cleanup returns `false` |
| `cleanup() -> Result<Cleanup, Failure>` | Remove only the owned empty directory, then close child and parent and release backing when removal is resolved |
| `destroy() -> Result<Cleanup, Failure>` | The same fallible cleanup operation |

Keep one active owner. Copies of TempDir, its Files or its Vec are inactive
aliases. Do not close, take or replace either borrowed File, mutate public
storage fields, or independently clean copied records. There is no automatic
destructor. `parent()` and `directory()` have distinct roles: the former anchors
the generated component; the latter supports operations on the child's entries.
Caller-owned child resources must follow their own cleanup contracts.

The caller's parent is borrowed only during `create_in`. TempDir owns its own
close-on-exec duplicate, so later caller-parent closure or ancestor rename
does not invalidate that anchor. The caller retains its original File owner.

## Construction and namespace authority

`Limits { name_attempts: u32, entropy_calls: u64 }` accepts `1..=1024` names
and `1..=1048576` entropy calls. Constants expose those maxima as
`MAX_NAME_ATTEMPTS` and `MAX_ENTROPY_CALLS`; `NAME_BYTES` is 37. Invalid limits
fail before allocation, duplication, entropy or namespace effects.

Creation reserves all 37 name bytes, duplicates the parent with CLOEXEC,
requires file-type metadata identifying a directory, and rejects `O_PATH`.
Closed descriptors, metadata/flags failures and allocation failures retain
their typed cause. Any acquired storage or descriptor remains in this same
owner for explicit cleanup, even if no name was created.

Each candidate uses `.tmp-` followed by 32 lowercase hex digits from 16 fresh
OS entropy bytes. A candidate is charged before filling its entropy. Partial
entropy progress and EINTR consume the shared call allowance; only bounded
EINTR retries occur inside `std::entropy::fill_bounded`. There is no clock,
PID, PRNG or fixed-name fallback. See [bounded entropy](stdlib-entropy-bounded.md).

Each fully generated name gets one anchored `create_dir_at` request with mode
0700. Umask, default ACLs and parent inheritance remain host policy; requested
0700 is not a universal claim about every resulting mode bit. Only EEXIST
retries with fresh entropy. A collision never authorizes opening or removing
the existing name. Candidate exhaustion returns `NameLimit`; entropy
exhaustion preserves its separate failure and confirmed byte prefix.

Immediately after confirmed mkdir success, TempDir records removal authority
before any child open. It then makes one read-only `O_DIRECTORY | O_NOFOLLOW |
O_CLOEXEC` open through the retained parent. A failed open returns
`Stage::OpenDirectory` while preserving the created name, parent and removal
duty. It does not silently abandon the directory or try another candidate.

The namespace must stay cooperative/stable throughout creation and cleanup.
Other actors must not replace, rename or remove the generated directory.
Parent descriptor anchoring and no-follow child open do not secure a name
against hostile replacement between mkdir, open and removal. No containment,
recursive deletion, metadata restoration or crash scavenging is promised.
Attempt limits bound calls, not elapsed kernel blocking time.

`Stats` separates:

```lanius
pub struct Stats {
    name_attempts: u32,
    mkdir_attempts: u32,
    open_attempts: u32,
    collisions: u32,
    entropy_calls: u64
}
```

An entropy failure can consume a candidate without a mkdir attempt; a collision
consumes a mkdir attempt without a child-open attempt. Successful mkdir leads
to exactly one child-open attempt. Cleanup does not reset these creation facts.

## Empty-only cleanup and keep

Normal cleanup first attempts removal while both child and parent descriptors
remain live. It calls only `remove_dir_at` on its generated component, never
scans the child, follows its entries or removes children recursively.

On confirmed removal or ENOENT, it disarms removal, closes the child once,
closes the parent once, then frees the name. ENOENT records `AlreadyAbsent`,
not a fictitious successful remove. Child-close failure does not suppress
parent close or backing release. Every close retires the descriptor before
the host attempt and is never retried, including after EINTR or delayed error.

On ENOTEMPTY or another removal error, cleanup retains the child, parent, name
backing and removal duty in `CleanupPending`. It attempts neither descriptor
close on that path. The caller may remove its own children through
`directory()` and retry cleanup, or call pure `keep()` and explicitly assume
the remaining directory's external lifetime. Each cleanup call makes at most
one removal attempt. A failed `destroy()` retains the same recovery resources.

`close_directory()` is an explicit separate choice. It closes only the child,
leaving the parent and name duty intact. Subsequent nonempty cleanup then
naturally retains only parent/name; the child is no longer available for
entry operations. A real close attempt refreshes `last_cleanup`; an already
closed child returns `Ok(false)` without another call or receipt refresh.

`keep()` only disarms removal on this same owner. It works after child-open
failure or failed removal whenever the name is still owned. It retains both
the name view and any descriptors until explicit cleanup. Kept cleanup skips
removal, closes child then parent and frees backing. Copy the name bytes into
caller-owned storage first if they must outlive cleanup: **all name views become
invalid when cleanup releases that storage**. Keep does not create another
descriptor owner or establish synchronization/durable publication.

An inactive keep returns `InvalidState` without recording a primary failure.
Cleaning an empty/released owner returns a no-attempt receipt and sets
`Released`; repeated terminal cleanup does no I/O. The states are `Inactive`,
`Open`, `ClosedNamed`, `Kept`, `CleanupPending` and `Released`. Creation is
allowed only in Inactive/Released with no remaining resources. Invalid active
recreation preserves resources, counters, receipts and the prior saved failure.
A new eligible creation begins a fresh diagnostic/counter lifecycle.

## Failures and cleanup receipts

`Error` distinguishes `InvalidState`, `InvalidLimits`, `AllocationFailed`,
`UnavailableMetadata`, `NotDirectory`, `UnsupportedDescriptor`, `NameLimit`,
`Io(core::io::Error)` and `Entropy(std::entropy::Failure)`.

`Stage` is `Validate`, `Allocate`, `Duplicate`, `Metadata`, `Flags`, `Entropy`,
`Create`, `OpenDirectory`, `CloseDirectory`, `Remove` or `CloseParent`.
`Failure { stage, cause, state, stats, cleanup }` saves the first Stage/cause
in the current creation lifecycle. Later successful cleanup does not erase it,
and a new cleanup error does not replace it. The cleanup fields expose that
attempt's separate errors:

```lanius
pub enum Removal { NotOwned, Removed, AlreadyAbsent, Unconfirmed }
pub struct Cleanup {
    directory_close_attempted: bool,
    directory_close_error: Option<core::io::Error>,
    remove_attempted: bool,
    removal: Removal,
    remove_error: Option<core::io::Error>,
    parent_close_attempted: bool,
    parent_close_error: Option<core::io::Error>,
    retained: bool
}
```

`last_cleanup` is the latest-call snapshot. `last_failure` retains that
snapshot's attempted/error fields but recomputes `cleanup.retained` from the
actual current resources. This exposes retained failed-construction backing
and anchors even before the first cleanup attempt. A failed removal records
`Unconfirmed` and its exact error. `cleanup` returns Err only for a new failure
in that call, not merely because an earlier create/close failed. Returned
receipts/failures are independent metadata snapshots; save one if its secondary
details must survive the next cleanup refresh.

## Focused executable acceptance

The accepted production sources remained unchanged throughout the native
gates and harness corrections:

| Source | SHA-256 |
| --- | --- |
| `stdlib/std/temp_dir.lani` | `56898b00479c5051db959b5f05069b7435c337be0b96cfe47c997adaf2c994b6` |
| `stdlib/std/file_ops.lani` | `21269e340801c09396a133a43ea5f5391307a59de861476605a140f953530ab6` |

Two independent read-only reviews of TempDir's production source found no
material issue.
Those reviews are separate from executable acceptance and do not establish
an independent review of the test harness.

The [Rust driver](../tests/stdlib_temp_dir_execution.rs) and
[fixture guide](../tests/fixtures/stdlib_execution/temp_dir/README.md) record
four accepted groups across these three commands. Logs are under
`target/stdlib-work/`:

| Log | Whole command result and time | Accepted groups |
| --- | --- | --- |
| `filesystem-temp-dir-native-first.log` | Mixed: 1 passed, 3 failed; 6.88 seconds | `owner`: 9 cases |
| `filesystem-temp-dir-callback-retry.log` | Mixed: 2 passed, 1 failed; 7.66 seconds | `cleanup_faults`: 10; `creation_faults`: 8 |
| `filesystem-temp-dir-single-entropy-rule-retry.log` | 1 passed; 6.07 seconds | `admission_entropy`: 19 |

The accepted group counts sum to 46, including calibrations and overlapping
controls. They are not the cumulative process-execution count across all
failed/retry commands. Each time measures its whole invocation, including
failed groups where present; it is not an isolated passing-group time or one
combined campaign timing.

The finite accepted scope is:

- `owner`: empty/kept lifecycle, real child creation and content, nonempty
  cleanup retaining both descriptors, child removal through `directory()` and
  successful retry, caller-parent closure and rename/replacement anchoring,
  already-absent removal, active recreation rejection and explicit child close.
- `admission_entropy`: invalid limits and regular/closed/O_PATH parents;
  bounded nonblocking entropy with partial/EINTR progress, exhaustion, zero/
  invalid counts and host failures; real collisions and finite candidate limits.
- `creation_faults`: every reached source allocation on the recorded baseline,
  plus reached duplicate, metadata, flags, mkdir and child-open failures.
  Successful mkdir followed by failed open retains name/parent/removal duty.
- `cleanup_faults`: retained removal errors with both descriptors or an
  explicitly closed child, keep/retry recovery, child/parent close retirement,
  explicit-close diagnostics and the original open failure preserved beside a
  later removal error.

The fixtures check real mode 0700 under their explicit umask 0077, namespace
objects and unchanged outside/replacement/collision targets. Collision-recovery
profiles use one test-only substituted first entropy draw of 16 zero bytes
to target an existing real file, directory or symlink. The attempted mkdir
must return real EEXIST. Later candidates bind to actual OS entropy in the
trace; the successful name must differ and counters must agree with every
draw, collision, mkdir and open. Separate bounded-exhaustion controls repeat
their forced draw. Synthetic entropy is labelled test infrastructure, not
production randomness or a library fallback.

ACK barriers hold the native child alive while the oracle checks exact source
mapping requests/releases, full-width addresses and descriptor generations
against `/proc`. Verified native instruction sites, operation phases and
anchored names bind each reached fault; final explicit release leaves no
owned mapping or descriptor beyond the standard streams before process exit.
Failed removal retains recovery ownership, pure keep does no I/O, and terminal
cleanup does not retry retired descriptors. A strace-injected close error skips
the physical close: a separately marked Q-phase repair closes that exact
generation only after logical retirement is checked. This establishes the
library's once-retire policy, not a natural physical-close-error outcome.

### Harness corrections and CPU controls

The first invocation's other three groups stopped at a Python callback bug:
injection-expectation assembly overwrote the callback with a dictionary, then
attempted to call it. After correcting that local variable, creation and
cleanup groups passed in the second invocation. Its admission group then
stopped at the first collision because duplicate strace `getrandom` options
overrode the intended first injection. The unchanged reached-injection guard
rejected that real, unmarked first draw. The final harness uses a single forced
first-draw option and rejects duplicate syscall injection options; the third
invocation passed admission/entropy. Neither correction changed production
code or weakened first-diagnostic, namespace or resource checks.

The final oracle SHA-256 is
`4a097176ff554ce1c6b793f3541207098ce79c219310978262e3071c191c36e0`.
Its 45 Python-only controls are separate evidence: they exercise source/fd/
phase/framing guards, callback assembly and rejection propagation, duplicate
option rejection and collision trace/name/counter mutations. They run no
compiler or native Lanius program. The fixture guide retains the full harness
history and bounded commands.

These native receipts establish the listed paths on the recorded local Linux
profile. They do not establish every allocation/failure schedule, filesystem,
hostile namespace, crash durability or user-program GPU-kernel support. The
[mktemp_dir program guide](stdlib-mktemp-dir.md) records the separate real
consumer and its application receipts; those are not added to the owner-group
count. The [filesystem plan](library-filesystem-completion-plan.md) tracks the
separate checked primitive increment.
