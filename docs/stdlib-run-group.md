# Bounded command-group supervision

`sample_programs/library/run_group.lani` runs a noninteractive command in an
explicit new process group. It waits for the direct child or an observed
deadline, then uses TERM, a grace period, KILL and bounded direct-child reaping.
Production parsing, launch, clocks, polling, signaling and cleanup run in Lanius.

Build from the repository root:

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  --stdlib-root stdlib sample_programs/library/run_group.lani -o /tmp/run-group
/tmp/run-group --status -- /bin/sh -c 'printf ready; exit 7'
/tmp/run-group --timeout-ms 100 --grace-ms 50 --reap-ms 500 -- /bin/sleep 2
```

The first command returns the child's exit code 7. The sleep example returns
124 when its deadline expires, with a cleanup/status diagnostic on stderr.
These examples describe the contract; focused native evidence is recorded below.

## CLI and limits

```text
run-group [--timeout-ms N] [--grace-ms N] [--reap-ms N]
          [--max-operations N] [--status] -- PROGRAM [ARG...]
```

Options end at `--` or the first program. Every later byte belongs to the
child's arguments, including values that resemble supervisor options. Numeric
options accept separate values only; digits are required, without a sign or
whitespace. Repeated and unknown options fail. `--help` must appear alone.

| Option | Default | Maximum | Meaning |
| --- | ---: | ---: | --- |
| `--timeout-ms` | 10,000 | 86,400,000 | Run deadline after spawn returns. |
| `--grace-ms` | 1,000 | 60,000 | Time to retain the leader after TERM before attempting KILL. |
| `--reap-ms` | 1,000 | 60,000 | Separate deadline for direct-child reaping after KILL. |
| `--max-operations` | 1,000,000 | 10,000,000 | Normal monitoring clock, wait and poll attempts. |
| `--status` | Off | — | Also report ordinary child completion. |

All numeric options allow zero. A zero timeout starts cancellation without an
ordinary wait. A zero operation budget still launches the command, then enters
explicit cleanup. A zero reap interval permits one nonblocking wait attempt.

The argument snapshot admits 4,120 arguments and 1 MiB of bytes. The underlying
[`std::command`](stdlib-command.md) request limits also apply: 4,096 child
arguments including argv[0], 4,096 environment entries, 65,536 bytes per string,
1 MiB of packed launch storage and 256 PATH candidates. The runner inherits a
bounded environment snapshot and searches its supplied PATH for bare programs.
Arguments and environment values remain raw bytes; no shell interprets them
unless the selected program is a shell.

Child stdin is `/dev/null`. Stdout and stderr are inherited and stream directly;
the runner neither captures nor caps their bytes. It stages its own argument,
environment and poll owners before spawning and allocates no monitor storage
after fork. This is a noninteractive supervisor: it does not transfer terminal
foreground ownership or implement shell job control. The parent ignores SIGPIPE
for checked diagnostics; the command request restores the child's default
SIGPIPE disposition as described by the command module.

## Group authority and lifecycle

The runner sets `Request.group = Group::New`. It never accepts a user-supplied
PGID or joins an arbitrary group. Requested policy, confirmed group setup and
startup certainty are separate facts. A missing `group_id()` receives one
`confirm_group()` attempt. Startup-channel EOF remains Unconfirmed; it is not
proof of exec or proof that a group was created.

During ordinary monitoring the runner checks CLOCK_MONOTONIC, calls
`try_wait()` for its positive direct-child PID, and polls an empty PollSet for
at most 10 ms. A terminal wait ends supervision immediately. Background members
may survive an ordinary early leader exit; no later group signal follows reap.

On timeout or a monitoring failure:

1. Close any still-owned pipe endpoints.
2. With confirmed group authority, attempt group TERM and direct-leader TERM.
   Without that authority, attempt direct-leader TERM only and report the group
   uncertainty. Both targets are attempted even if the first signal fails.
3. Retain the unreaped leader throughout the grace period. No wait occurs here,
   including when TERM has already caused the leader to exit.
4. Attempt KILL on the original confirmed group and the still-owned positive
   leader. The direct target covers a leader that moved to another group.
5. Use bounded `try_wait()` calls to reap only the direct child. Once terminal
   wait or ECHILD invalidates its owner, perform no further signaling.

The full grace period is deliberate: reaping a cooperative leader early would
release the authority needed to escalate against a stubborn remaining group
member. Signals always go through the Child methods, using their current
owner state. Saved diagnostic PID values never become signal targets. A leader
still in the original group can receive TERM through both requested targets.
Signal handlers must account for that repeated request.

Unknown startup is a supervisor failure even if later group confirmation
succeeds. Cleanup can target the group only when that separate confirmation
exists; otherwise it attempts the direct child and leaves descendant cleanup
uncertain. Reported setup/exec failure already carries the reaped status and
does not enter a second cancellation sequence.

## Time, work and incomplete cleanup

The run deadline starts after `spawn` returns. Argument/environment preparation,
the blocking startup handshake and final diagnostic publication are outside
that interval. Each charged clock, nonblocking wait and poll attempt consumes
one monitoring operation, including EINTR. Interruptions preserve the original
absolute deadline. The counter is an abstract operation budget, not a literal
syscall or CPU-instruction count.

Cleanup has independent bounds so monitoring-budget exhaustion cannot skip
it: at most 10,000 grace poll rounds, 10,000 reap attempts, their clock/poll
checks, four signal attempts and fixed endpoint closes. The first cleanup
error is retained. ESRCH from signaling still proceeds to reaping. An error
in grace clock/poll handling or its round cap ends grace early and proceeds to
KILL. A reap clock failure still permits an initial nonblocking wait. No
blocking `wait()` or `cancel_group_and_wait()` is used by the runner.

Clock checks and at-most-10-ms polls give observation-based deadlines. Scheduler
delays, blocking host calls and uninterruptible kernel operations can overrun
them. A failed or incomplete cleanup cannot promise that the child died or was
reaped. `cleanup-incomplete pid=N` records an owner still retained at CLI exit;
the OS then reparents it, and the exited CLI cannot later reap it.
`ownership-lost=true` records ECHILD invalidation without claiming a reap.

## Status and output

| Exit | Meaning |
| --- | --- |
| Child code | Ordinary completion, including nonzero codes. |
| 128 + signal | Ordinary signal death. |
| 124 | Observed run deadline expired; cleanup diagnostics may still report failure or incompleteness. |
| 125 | Invalid arguments, supervisor/unknown-startup failure, or diagnostic I/O failure. |
| 126 | Reported child setup/exec failure other than ENOENT/ENOTDIR. |
| 127 | Reported executable ENOENT/ENOTDIR. |

An ordinary child may itself return 124..127; `--status` distinguishes recorded
ordinary completion from supervisor errors. Normal nonzero child status alone
does not produce a diagnostic when `--status` is absent.

Status/error lines begin `run-group:` and contain stage, reason, errno, the
informational original PID, startup, group confirmation, signal-attempt flags,
reaped/lost state, and exit/signal fields. Startup is 0 before a retained child
record, 1 for Unconfirmed, and 2 for Unknown. `group-confirmed` means confirmation
was established before supervision; a printed true value is not current
authority after reap. `term-scope` is 0 for no attempt, 1 for group plus leader,
or 2 for leader only. Attempt flags do not assert signal delivery.

Stages are arguments 1, preparation 2, startup 3, monitor 4 and publication 6.
Reasons are arguments 1, clock 2, work cap 3, wait 4, poll 5, deadline 6,
unknown startup 7, reported startup failure 8, preparation/spawn failure 9,
unconfirmed group 10 and publication 11. Library-native errno is retained when
available. Cleanup errors appear separately; library failures without a native
errno use 5 as a diagnostic fallback, not a claim of kernel EIO.

Diagnostics use fixed stack storage and at most 1,024 checked write attempts.
A partial diagnostic is not replayed; failed publication returns 125 after
lifecycle handling. Child output can already have streamed before a later
supervisor error. There is no staged or atomic stdout/stderr transaction.

## What a group does not establish

Group signaling targets members present and permitted by the kernel at that
call. Success establishes at least one delivery, not delivery to every member
or proof that the group is empty. Descendants may use `setpgid` or `setsid` to
escape; the runner does not discover, adopt or reap arbitrary descendants.
It installs no forwarding handler for external termination of the supervisor.
This is not full process-tree containment or automatic detached cleanup.

The command module's single-threaded caller, no asynchronous user handlers,
no outside reaper, and no SIGCHLD Ignore/SA_NOCLDWAIT restrictions apply. Keeping
the direct child unreaped anchors its numeric identity only under those
ownership preconditions. There is no pidfd or namespace isolation in production.

Primary Linux contracts are [setpgid](https://man7.org/linux/man-pages/man2/setpgid.2.html),
[kill](https://man7.org/linux/man-pages/man2/kill.2.html),
[wait](https://man7.org/linux/man-pages/man2/waitid.2.html) and
[setsid](https://man7.org/linux/man-pages/man2/setsid.2.html).

## Focused acceptance

[`tests/stdlib_run_group_execution.rs`](../tests/stdlib_run_group_execution.rs)
defines five groups and shares one compilation of the real app:

- Ordinary status, inherited raw arguments/environment, null stdin, PATH and
  strict CLI admission.
- Cooperative/stubborn groups, leader exit during TERM grace, a leader moving
  groups, a descendant escaping through setsid, and normal early leader exit.
- Exact activated syscall faults, EINTR, monitor-budget exhaustion and broken
  diagnostic output.
- Hidden reaping, persistent signal/wait failures and ECHILD revocation, with
  explicit incomplete/lost-owner diagnostics and independent cleanup.
- Every reached pre-spawn allocation failure, exact request-prefix/FD/mapping
  ledgers, and rejection of any post-fork supervisor allocation.

Test-only Python peers provide the independent observations. Each supervision
process runs in a private test session. Trace output goes to regular files so
a live descendant cannot hold pipe EOF and prevent the oracle's own cleanup.
The moved-leader peer waits for the supervisor's first normal wait before
leaving its group, separating launch confirmation from later group movement.
The oracle is a Linux child subreaper;
it inspects and reaps its own adopted children, including deliberate escapes.
It never treats a saved numeric PGID as cleanup authority. Signal order and
the absence of reaping during grace are trace assertions, not tight timing
thresholds. Tests intentionally do not force PID reuse or claim exhaustive
concurrent process behavior.

All five groups passed GPU compilation and native Linux x86_64 execution in
**two separate invocations**, totaling **53 cases**:

| Invocation | Accepted groups and cases | Elapsed | Receipt under `target/stdlib-work/` |
| --- | --- | ---: | --- |
| Normal behavior | Ordinary command/status/admission group: 21 cases. | 6.36 s | `run-group-normal-first.log` |
| Remaining groups | Allocations: 10 cases; host faults: 12; group lifecycle/escape: 6; retained/lost ownership: 4. | 10.17 s | `run-group-other-groups-first.log` |

The allocation group includes its successful baseline and **all nine reached
pre-spawn allocation failures**, with no monitor allocation after fork. Traced
cases check exact mapping/FD/direct-child ownership ledgers; the oracle performs
bounded independent cleanup of adopted descendants. Fault cases verify actual
injection activation, target/errno/ordinal and signal/reap ordering. No
production change or extra rerun was needed between these two acceptances.
These are separate receipts, not a claim of one combined suite invocation.

CPU checks cover 25 literal byte lengths, Python syntax, resource-ledger and
fault-evidence controls and support the runtime evidence above. These finite
cases do not prove arbitrary process-tree containment, PID-reuse safety outside
the ownership preconditions, or a hard completion deadline. The bounded
reproduction command is:

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test stdlib_run_group_execution -- --nocapture --test-threads=1
```

The profile is native Linux x86_64 with the command module's Linux 5.11+
requirements. Tests also need Python, `strace` syscall injection and `/proc`.
No other target or hard real-time guarantee is claimed.
