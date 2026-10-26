# Process-group runtime verification

`tests/stdlib_command_group_execution.rs` checks the new-group policy in
`std::command` and the unreaped-leader anchor used by `std::command_capture`.
Production process control remains Lanius and existing raw Linux syscalls.
Python is an independent test peer and resource oracle only.

## Contract and state space

The focused test family distinguishes requested `Group::New`, confirmed group
authority, startup `Unconfirmed` or `Unknown`, observed terminal status, and an
actually reaped leader. A process group is not a session or a permanent process
tree. A descendant or leader can leave it.

The Linux contracts behind the checks are:

- [setpgid](https://man7.org/linux/man-pages/man2/setpgid.2.html): fork inherits a
  group, exec preserves it, and a new group remains in the same session.
- [kill](https://man7.org/linux/man-pages/man2/kill.2.html): a negative group
  target reaches group members; success alone establishes delivery to at least
  one member, not every member.
- [wait](https://man7.org/linux/man-pages/man2/waitpid.2.html): `WNOWAIT` can
  observe terminal status without reaping. Actual reap and ECHILD retire the
  library's leader anchor.

Three positive entry fixtures compile through the production stdlib root and
the unchanged shared strict ELF/jump checker. One Rust invocation reuses each
compiled artifact through `OnceLock`; selecting a behavior group compiles only
`probe.lani`, while the fault group compiles only `failure.lani` and
`confirm.lani`.

| Group | Finite cases and durable assertions |
| --- | --- |
| Membership | Inherited policy and a new group. Kernel PID/PGID/SID reports check the new leader's PGID equals its PID, the grandchild shares it, and the session stays unchanged. PID-only and group signals use distinct acknowledgments. |
| Signal reach | Group cancellation reaches leader and grandchild. Another case moves the leader into the private parent's group while the grandchild retains the original group, requiring cancellation of both the original group and owned positive leader. A sibling sentinel remains alive in the parent's group. Injected group-signal/cancel EPERM retains ownership before retry or graceful cleanup. |
| Authority | A terminal leader remains unreaped while a grandchild keeps stdout open. Observation and observed status preserve group authority. Separate actual-reap and SIGCHLD-ignore/ECHILD cases revoke it while the grandchild is still alive. A waitid EINTR control preserves the owner and retries explicitly. |
| Capture anchor | A leader exits 23 while its grandchild retains stdout. Capture reaches its absolute deadline, retains observed status and the unreaped anchor, then explicit group cancellation kills the grandchild and reaps the leader. A successful drain instead reaps once and leaves no group authority. |
| Setup and resources | Valid child setup packets, startup read/protocol uncertainty, early child death, explicit confirmation after a parent setup error, reached pre-fork allocation failures, pipe/fork errors and wait errors. Every case ends with an actual reap or known ECHILD and full parent resource cleanup. |

## Independent peer and cleanup authority

`peer.py` forks one grandchild and waits for its pipe READY marker before
publishing identities. Signal handlers are installed before this barrier.
Each SIGUSR1 acknowledgment contains the sender PID. The fixture requires
both the leader and grandchild acknowledgments for a group signal; merely
checking the kill syscall's return value would miss incomplete reach.

Every fixture runs in a private session. Its parent and sibling remain
responsive after group operations. The oracle rejects kill targets zero,
minus one, any unrelated negative PGID, and a negative group kill after the
leader's actual reap. It does not try to force numeric PID reuse.

The Python oracle is a test-only Linux
[child subreaper](https://man7.org/linux/man-pages/man2/PR_SET_CHILD_SUBREAPER.2const.html).
It adopts and waits for orphan grandchildren. For post-reap tests the fixture
first reports that its leader anchor is revoked and further group calls are
locally rejected. The oracle then uses `waitid(P_PID, ..., WNOWAIT)` to establish
that the reported grandchild is its own unreaped child before opening a pidfd.
It verifies the grandchild is still live and signals that exact process. The
oracle retains default SIGCHLD handling and has no competing reaper, so the
child relationship pins the identity through acquisition. Recorded parent or
leader PIDs never supply cleanup signal authority. Exceptional cleanup kills
only the owned unreaped tracer; `--kill-on-exit` kills its followed tracees,
then the oracle reaps adopted children with a bounded wait. The peer also has
a finite alarm.

The parent-only trace ledger tracks every successful mmap address and requested
length, each internal descriptor and every directly forked child. It rejects
unknown/double/wrong-length releases, unreaped children and unretired owned
descriptors. `waitid(WNOWAIT)` does not remove a child from that ledger. The
explicit SIGCHLD-ignore case models known automatic reap separately. Followed
child traces also reject allocation/deallocation before exec.

## Fault targeting and startup uncertainty

[Strace injection accounting](https://man7.org/linux/man-pages/man1/strace.1.html)
is per syscall and per tracee. Consequently a followed first-setpgid failure
affects both the parent and child's first call. The tests label this as a dual
fault and require the child's real stage-6 failure packet, including its magic,
errno and checksum. They do not claim isolated child-only injection.

Parent-only traces isolate parent setpgid/getpgid failures. The successful-exec
control forces EACCES plus either a getpgid error or mismatched result, then
checks that `Spawn::Unknown` retains its child. Explicit later confirmation
uses the real kernel identity and restores group authority without changing
startup uncertainty. This avoids using a sleep as proof that the exec race
resolved in a particular order. Valid child failure packets take precedence
over parent setup uncertainty; both facts have separate controls.

Each injected errno is checked against its exact syscall, tracee and ordinal.
Synthetic packet truncation and early SIGKILL are classified separately from
errno returns. Signal-only injection has no errno/retval `INJECTED` marker;
the selected child's syscall entry must abort, no child exec may occur, and
the parent must actually reap that exact child with the requested signal.
The oracle does not require death/signal display lines suppressed by its
`-qq` and `signal=none` trace options. One tiny, argument-free spawn fixture
supplies the observed
baseline allocation positions; every reached ordinal is independently denied
once. The gate preserves the exact request prefix through the denial and
requires all successful owner generations to be released. This does not cover
simultaneous faults, arbitrary permission changes or PID namespaces.

## Reproduction and evidence

All five groups passed root's serialized native gates across the separate
receipts below. The Rust driver does not print the oracle's case-count summary,
so these receipts support the five accepted groups without an asserted total
native case count.

The membership and parent-isolation group passed root's serialized native gate
in 7.31 seconds: `target/stdlib-work/command-group-membership-first.log`.
It exercised both inherited and new groups. Fixtures and source were unchanged
during that run.

The signal-reach, authority and capture-anchor groups passed in the subsequent
mixed four-group invocation, 12.08 seconds total:
`target/stdlib-work/command-group-other-groups-first.log`. The startup/fault
group in that invocation reached the early-SIGKILL case but rejected an absent
strace display line. Its oracle now checks the exact child entry/no-exec/reap
evidence described above. This harness correction changed no production source
or native fixture. The startup/fault group then passed its focused retry in
6.85 seconds: `target/stdlib-work/command-group-startup-fault-retry.log`.

CPU checks passed Python syntax, malformed ledger/fault controls and four
isolated Python-peer scenarios
(two-recipient signals, leader movement, retained pipe and orphan reap, and
successful peer-owned grandchild reap). Those checks do not execute Lanius.

Run one focused group at a time, with the shared GPU gate used by this project:

```sh
cargo test --locked --test stdlib_command_group_execution \
  inherited_and_new_groups_preserve_session_and_parent_isolation \
  -- --exact --nocapture --test-threads=1
```

The other exact test names are in the driver. Each oracle process has a bounded
timeout, and every subprocess has a separate bound. These finite Linux x86-64
cases are functional and resource-lifetime evidence. They do not establish
another target, containment of escaping descendants, cleanup after an arbitrary
trap, or whole-program timing guarantees.
