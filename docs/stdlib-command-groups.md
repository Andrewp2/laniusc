# Child process groups and cancellation

`std::command` adds explicit Linux x86_64 process-group creation, anchored group
signaling and non-reaping exit observation. All five focused API groups,
existing command/capture regressions and the bounded run-group app have passing
receipts recorded below. The GPU compiler emits native CPU programs; other
targets and user-program GPU execution need separate evidence.

This uses the existing `std::linux::syscall6` boundary. There is no new compiler,
runtime service, ABI or libc callback. The existing
Linux 5.11+ command profile and its single-thread/manual-owner restrictions
apply.

## Creation policy and startup evidence

```lanius
pub enum Group { Inherit, New }
// Request has a group: Group field.
```

`command::request(...)` defaults to `Group::Inherit`. Set `request.group` to
`Group::New` to create a process group whose ID is the new child's PID. The
child remains in the parent's session. There is one spawn engine; there is no
arbitrary group-join policy, session creation or terminal foreground control.

The child calls `setpgid(0,0)` before other setup or exec. An exact nonzero
result is reported through the existing startup channel as child packet stage
6, exposed as `Stage::ProcessGroup`, then the child exits. The parent also
calls `setpgid(child_pid,child_pid)`. Exact zero confirms the expected group.
If the child won the exec race and the parent receives EACCES, only a matching
`getpgid(child_pid)==child_pid` confirms it. POSIX explains why both sides call
[`setpgid`](https://pubs.opengroup.org/onlinepubs/9799919799/functions/setpgid.html).

A parent group-setup failure does not discard the child. The parent still
processes the startup channel. A valid child failure record is reaped and
returned through `Spawn::Failed`; an otherwise empty channel with an unresolved
parent failure returns `Spawn::Unknown` with its child owner. Startup read or
protocol failure also preserves the owner. Group proof already obtained stays
available even when startup certainty is Unknown.

EOF on the CLOEXEC error channel remains only `Startup::Unconfirmed`; it does
not prove exec or group setup. Requested policy and confirmed group authority
are independent:

| Child method | Meaning |
| --- | --- |
| `group() -> Group` | Requested inherited/new policy, including after reap |
| `group_id() -> Option<i32>` | Confirmed original group ID while its leader is still owned and unreaped |
| `confirm_group() -> Result<i32,Failure>` | For an unconfirmed New request, make one exact expected-ID query; no arbitrary PGID is accepted |

Already-confirmed `confirm_group` returns its anchored ID without another
query. Failed queries or mismatches retain the child owner without granting
group authority. `Error::GroupUnconfirmed` identifies unavailable authority;
native setup/query errors retain their positive errno in `Failure`.

## One unreaped leader anchors the group ID

The owner permits negative-PGID signaling only when the group was confirmed,
the unreaped child PID is greater than one, and no reaped status is cached.
The group ID is the original leader PID. Negation widens to i64 first; this
never constructs target zero or minus one.

Actual terminal `wait`/`try_wait` reaping clears PID, observation and group
authority before returning the cached status. An observed ECHILD also revokes
ownership and returns `LostChild`. Later group signaling is rejected locally,
even if descendants still physically exist. A stored PGID is not a persistent
resource handle after its leader has been reaped.

Keep one active Child descriptor. Copied descriptors grant no second wait or
signal authority. Do not use outside waiters, concurrent threads, asynchronous
user handlers, SIGCHLD Ignore or SA_NOCLDWAIT. An outside reaper can invalidate
the identity before the library notices; these APIs do not repair that broken
precondition. Public fields are not an ownership-validation boundary.

## Observation and final reap

```lanius
Child::try_observe_exit() -> Result<Option<ExitStatus>,Failure>
```

This makes one nonblocking Linux
[`waitid(P_PID, ..., WEXITED|WNOHANG|WNOWAIT)`](https://man7.org/linux/man-pages/man2/waitpid.2.html)
call when no terminal status is already known. It validates the Linux x86_64
128-byte siginfo layout, expected child PID and terminal result code before
forming an `ExitStatus`. No event returns `None`. EINTR and recoverable errors
retain the anchor for a caller's next budgeted attempt. ECHILD invalidates it.

A terminal observation is cached separately from the reaped-status cache.
`id()` and confirmed `group_id()` remain available. Repeated observations can
return that cached status without another kernel query; they cannot detect an
outside reap. Ordinary `wait` or `try_wait` must still perform the final reap.

`command_capture::communicate` now observes exit while draining pipes, preserving
the leader anchor when descendants retain pipe ends. `Progress.status` can be
an observed terminal result while `Progress.reaped` is false. Once all acquired
pipes are closed and terminal status is known, capture checks its deadline and
charges its operation budget before one final nonblocking `try_wait`. EINTR
is retried through the charged outer loop. A valid final result returns success
immediately, with `reaped=true`, without a later fallible clock check.

Capture failures preserve the unreaped anchor except when ownership was lost
through ECHILD or an actual final reap already occurred. A contradictory
observed/final status is reported as failure with `reaped=true`; authority has
already been revoked. Capture never blocks in `wait` or implicitly cancels.
Existing endpoint/prefix ownership and failure cleanup remain explicit.

Successful capture proves terminal status of the direct child plus EOF of its
captured streams. A descendant can close its pipes and continue running. Final
reap ends group authority regardless of such descendants; capture does not
wait for the entire group or establish that it is empty.

## Signals and cancellation

```lanius
Child::signal_group(signal: i32) -> Result<i32,Failure>
Child::cancel_group_and_wait() -> Result<ExitStatus,Failure>
```

`signal_group` accepts signals 0..64, validates authority locally, then signals
the original negative group ID. It returns native errors, including ESRCH,
without reaping or discarding ownership. A successful
[`kill(-pgid,signal)`](https://man7.org/linux/man-pages/man2/kill.2.html)
means at least one permitted member received the signal. It does not prove all
members received it or exited. Signal zero checks existence/permission only.

`cancel_group_and_wait` first validates confirmed, unreaped authority. It then
attempts every still-owned pipe close, SIGKILL to the original group, and
SIGKILL to the still-owned positive leader PID. The positive fallback covers
an executed leader that left its original group. It never queries that
leader's new PGID and signals some unrelated group instead.

Both signal targets are attempted even after an earlier cleanup error. ESRCH
is tolerated for these cancellation sends. The first other close/signal error
is returned and final reaping is skipped, leaving the Child for retry. If all
attempts succeed, the convenience method uses ordinary blocking `wait` to reap
only the direct child. A wait error also retains ownership unless ECHILD was
observed. Callers needing finite cleanup use explicit group/direct signals,
clock/work limits and nonblocking waits. SIGKILL cannot guarantee a kernel-stuck
process becomes immediately reapable.

Group cancellation reaches current members of the original group. Descendants
can move to another group/session or change signal permissions. This is not a
process-tree containment mechanism, cgroup, subreaper or terminal job-control
system. Unknown startup without confirmed group authority must not be described
as successful descendant cleanup; the caller may retry confirmation or perform
explicit direct-child fallback with that limitation.

## Focused execution evidence

The dedicated `tests/stdlib_command_group_execution.rs` driver and independent
peers cover inherited versus new
group identity, delivery to leader and grandchild, parent/child setup races and
faults, startup Unknown certainty, an exited-but-unreaped leader with descendant
pipe retention, retained capture authority on failure, final-reap revocation,
ECHILD, an escaped leader and original-group cancellation with positive-leader
fallback. Traced syscall activation and exact FD/allocation/reaping ledgers
remain active. All five API groups passed across these separate native Linux
x86_64 runs:

| Receipt under `target/stdlib-work/` | Result | Time |
| --- | --- | --- |
| `command-group-membership-first.log` | Inherited/new membership, session and parent-isolation group passed | 7.31 s |
| `command-group-other-groups-first.log` | Signal reach, observation/reap/ECHILD and capture-anchor groups passed; startup/fault group failed an oracle death-display expectation | 12.08 s |
| `command-group-startup-fault-retry.log` | Corrected startup/fault group passed | 6.85 s |

The mixed run's startup failure came from requiring strace's optional
`killed by SIGKILL` display line even though the traced wait already recorded
SIGKILL termination. The corrected oracle checks termination evidence without
depending on that display. Production source remained unchanged.

Existing behavior also passed its focused regression gates:

| Receipt under `target/stdlib-work/` | Result | Time |
| --- | --- | --- |
| `command-group-inherit-regressions.log` | All four existing command groups passed | 22.09 s |
| `command-group-capture-contracts-first.log` | Three-pipe capture admission and owner/progress contract group passed | 8.62 s |
| `command-group-capture-oracle-first.log` | Capture CLI/concurrency and independent resource-fault oracle group passed | 10.84 s |

The separate [bounded run-group app](stdlib-run-group.md) exercises deadline,
TERM/grace/KILL policy and disclosed incomplete cleanup. Its five groups passed
in two invocations totaling 53 process cases: 21 normal/admission cases in
6.36 seconds (`run-group-normal-first.log`) and 32 allocation, host-fault,
group-lifecycle and ownership cases in 10.17 seconds
(`run-group-other-groups-first.log`), under the same receipt directory. This
includes all nine reached pre-spawn allocation failures and no post-fork
supervisor allocation.

These separate receipts establish the finite tested Linux profile. They do not
establish all process topologies, hard cleanup deadlines or cleanup after
process-wide ownership preconditions are violated.
