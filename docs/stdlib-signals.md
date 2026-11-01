# Signals

`std::signal` covers Linux x86_64 signals without asynchronous code:

- Default and Ignore dispositions, and queries of the installed action
- signal sets, the calling thread's block mask and the pending set
- synchronous delivery through a [signalfd](https://man7.org/linux/man-pages/man2/signalfd.2.html), which `std::event` can watch
- `handle()`, which combines the three into "handle these signals"

It allocates no memory and installs no callback, custom handler or
signal-return trampoline: a handled signal is blocked and read as data.
Resource limits are in [`std::rlimit`](stdlib-rlimit.md).

```lanius
import std::signal;
let configured = std::signal::set_disposition(
    std::signal::Signal::BrokenPipe,
    std::signal::Disposition::Ignore);
// Check configured before starting work that depends on this policy.
```

`set_disposition(signal, disposition)` returns
`Result<i32,core::io::Error>`. Success is `Ok(0)`. Kernel errno 4 maps to
Interrupted, errno 11 to WouldBlock and other kernel errors to Host with the
positive errno. An impossible nonzero success status is InvalidCount.

| Signal | Linux x86_64 number |
| --- | --- |
| Hangup | 1 |
| Interrupt | 2 |
| Quit | 3 |
| User1 | 10 |
| User2 | 12 |
| BrokenPipe | 13 |
| Alarm | 14 |
| Terminate | 15 |
| Child | 17 |
| Abort | 6 |
| Kill | 9 |
| Segfault | 11 |
| Continue | 18 |
| Stop | 19 |
| TerminalStop | 20 |
| CpuLimit | 24 |
| FileSizeLimit | 25 |
| WindowChange | 28 |
| Other(n) | n, for any 1..64 (realtime signals are 34..64) |

`number(signal)` returns the number, or 0 for an `Other(n)` outside 1..64.
`from_number(n)` returns the named variant, `Other(n)` for unnamed numbers in
range, or None. `set_disposition` returns InvalidInput for an invalid signal.

## Process and thread contract

Dispositions affect every thread in the calling process. Applications must
coordinate changes with other code that manages signals: setting Default or
Ignore replaces the previous disposition. The function does not change the
calling thread's blocked-signal mask or send a signal. Ignored dispositions are
inherited across exec; custom handler dispositions are reset by exec. These are
Linux process semantics described in [signal(7)](https://man7.org/linux/man-pages/man7/signal.7.html).

Default selects the kernel's normal action for the signal. Ignore suppresses
delivery of that signal. In particular, Ignore for BrokenPipe lets a failed
write to a closed pipe or socket return EPIPE instead of terminating the
process. This lets a command report an I/O error and destroy its owners. The
library changes no process policy until the application calls it.

Explicit Ignore for Child has the kernel's child-reaping semantics; it differs
from leaving Child at its default disposition. Applications that collect child
exit statuses must choose that policy deliberately. See
[sigaction(2)](https://man7.org/linux/man-pages/man2/sigaction.2.html).

`replace_disposition(signal, disposition)` does the same and returns the
previous `Action`: `Default`, `Ignore` or `Handler` (some other code installed
a handler address). `action(signal)` reads it without changing it. Kill and
Stop cannot be changed: the kernel returns `Host(22)` (EINVAL). These and the
calls below return `std::signal::Error`:

| `Error` | Meaning |
| --- | --- |
| `Host(errno)` | Positive Linux errno |
| `Bounds` | Invalid signal, empty set, or Kill/Stop given to `handle()` |
| `Closed` | The receiver was already closed |
| `Pending(n)` | `restore()` found handled signal `n` still pending |
| `InvalidResult` | Unexpected system call result or malformed signalfd record |

Alternate stacks, custom callbacks and handler trampolines remain outside this
interface. It does not change the runtime's global signal policy or the
compiler's older signal primitive.

## Sets, masks and pending signals

A `Set` holds signals 1..64 with the kernel's sigset bit layout (bit n-1 for
signal n). Build one with `empty()`, `full()`, `of(signal)` or
`from_bits(bits)`, then `with`, `without`, `union`, `intersection` and
`difference`. Query it with `contains`, `contains_number`, `count`, `first`
(the lowest member, 0 when empty), `is_empty` and `bits`. Adding an invalid
signal leaves a set unchanged.

The block mask belongs to the **calling thread**. `block(set)`,
`unblock(set)` and `set_mask(set)` return the previous mask; `mask()` reads
it, and `pending()` returns the blocked signals waiting for delivery. The
kernel never blocks Kill or Stop and drops them from any mask silently. A
blocked signal stays pending (standard signals are queued once) until it is
received or unblocked. When it is unblocked it is delivered according to its
disposition.

## Receiving signals

`receiver(set, mode)` opens a close-on-exec signalfd for a nonempty set. It
receives only signals that are **blocked**, because unblocked signals are
delivered by their disposition first, and **not ignored**, because ignored
signals are discarded. Each read consumes one pending signal and returns a
`Delivery`:

| Field | Meaning |
| --- | --- |
| `signal` | Signal number; `named()` and `is(signal)` compare it |
| `code` | `si_code`: 0 (SI_USER) for `kill`, -6 for `tgkill`, positive for kernel signals, for example 1 (CLD_EXITED) for Child; `from_user()` is `code <= 0` |
| `pid`, `uid` | Sender, or the child for Child |
| `status` | Exit code or terminating signal for Child |
| `errno` | `si_errno` |

`Mode::Blocking` receivers wait in `read()` (EINTR retried). On a
`Mode::Nonblocking` receiver `read()` returns `Host(11)` when nothing is
pending and `try_read()` returns None. The descriptor (`raw_fd()`) is readable
in [`std::event`](stdlib-event-loop.md) while a signal is pending; drain with
`try_read()` until None, since several signals may be queued behind one
readiness event. `close()` closes once and never retries. Pending signals stay
pending and blocked.

## Handling a set

`handle(set)` makes `set` handled in three steps. It sets ignored members to
Default, blocks the set, and opens a nonblocking receiver. If any step fails,
it undoes the earlier steps. A set containing Kill or Stop, or an empty one,
is `Bounds`. The returned `Handled` offers `raw_fd()` for `std::event`,
`try_read()`, `set()` and `previous_mask()`.

`restore()` undoes `handle()`: it closes the receiver, unblocks the members
that were not blocked before, and re-ignores the members it reset. It first
refuses with `Pending(n)`, changing nothing, while a member that it would
unblock is pending: that signal would otherwise be delivered by its
disposition, for example terminating the process for Terminate. Drain with
`try_read()` and call it again. A signal that arrives between that check and
the unblock is still delivered normally.

### Children and exec

The block mask and ignored dispositions survive fork and exec. Blocking a set
for a receiver therefore would also block it in every child. To prevent that,
`std::command` requests default to `ChildMask::Clear`, which empties the
child's mask before exec. `ChildMask::Inherit` passes the parent's mask on.
`handle()` never leaves a handled signal ignored, so children see Default for
it. Use these APIs from a single-threaded process. Another thread with the
signal unblocked would receive it instead.

## Native boundary and evidence

The implementation uses `std::linux::call` with x86_64 syscalls 13
`rt_sigaction`, 14 `rt_sigprocmask`, 127 `rt_sigpending`, 289 `signalfd4`, 0
`read` and 3 `close`. `rt_sigaction` Its stack buffer uses the kernel layout: four 64-bit words for
handler, flags, restorer and signal set; the syscall's signal-set size is 8.
Default and Ignore use handler values 0 and 1, with flags, restorer and mask
zero. A query passes a null new action. The layout is the Linux kernel ABI,
rather than libc's public structure. Delivery records are the kernel's 128-byte
`signalfd_siginfo`.

`tests/stdlib_signal_execution.rs` queries kernel state independently for every
named mapping in both directions. It writes to an actual closed stdout pipe
with BrokenPipe ignored and checks EPIPE, then restores Default in a separate
child and checks SIGPIPE termination. Only test children receive these signals.
Fault injection checks positive errno mapping, interruption, temporary
unavailability and invalid success statuses. Traces check that all cases are
allocation-free.

The real `tcp_exchange` consumer selects BrokenPipe Ignore before allocation
or output. Its closed-stdout integration regression checks status 3 and owner
cleanup after a complete network response.

All three focused signal tests passed. The final literal-pipe checks passed
for both ignored and restored-default dispositions. Logs are in
`target/stdlib-work/signals/`.

### Masks, receivers and handling

`tests/stdlib_signal_delivery_execution.rs` runs the self-checking
`tests/fixtures/stdlib_signals/contracts.lani` program. It checks:

- set algebra, numbering, `from_number` and invalid `Other` values
- block and mask round trips, and the kernel refusing to block Kill
- a self-sent User1 pending, then received with code 0 and this process's PID
- nonblocking `Host(11)` and None, blocking reads, and `Closed` after close
- `replace_disposition` and `action` round trips, and EINVAL for Kill
- `handle()` resetting an ignored User2, `restore()` refusing with
  `Pending(12)` until it is drained, and then restoring Ignore and the mask
- through `std::event`, a child's `kill -TERM $PPID` and its exit received as
  Terminate (SI_USER, the child's PID) and Child (CLD_EXITED, status 3)
- a child shell killing itself with TERM while the parent blocks TERM: it
  dies by signal 15 with `ChildMask::Clear` and exits 3 with `Inherit`

The same program checks [`std::rlimit`](stdlib-rlimit.md#evidence). Repeated
direct runs exit 0.

## Application: supervise

[`sample_programs/library/supervise.lani`](../sample_programs/library/supervise.lani)
runs one command and restarts it when it crashes:

```sh
laniusc --stdlib-root stdlib sample_programs/library/supervise.lani -o supervise
./supervise --backoff-ms 200 --max-restarts 10 -- ./server --port 8080
./supervise --grace-ms 2000 --max-open-files 256 -- python3 worker.py
```

The command is found through PATH and runs in a new process group with the
supervisor's stdio. The supervisor handles Terminate and Interrupt with
`std::signal::handle` and watches three descriptors in one `std::event` loop:
the signalfd, the child's pidfd and a Monotonic timerfd.

- **Crash and restart.** A nonzero exit or death by a signal is a crash. A
  zero exit ends the supervisor with status 0. After the k-th consecutive
  crash it waits `backoff * 2^(k-1)` ms, capped at `--max-backoff-ms`, then
  starts the command again. A run that lasted at least `--stable-ms` resets
  the count. After more than `--max-restarts` consecutive crashes it gives up
  with the last run's status.
- **Forwarding.** Terminate or Interrupt is forwarded to the child through its
  pidfd, and the timer is armed for `--grace-ms`. The child's own exit then
  ends the supervisor with the child's status, without a restart. If the
  grace period ends, or a second signal arrives first, the child gets SIGKILL.
  A signal while waiting out a backoff ends the supervisor with 128 + signal.
  Because the child has its own process group, a terminal's Ctrl-C reaches it
  once, through forwarding.
- **Limits.** `--max-open-files N` sets the supervisor's soft open-file limit
  with `std::rlimit`, so every child inherits it.

Options, each at most once:

| Option | Range | Default |
| --- | --- | --- |
| `--max-restarts N` | 0..1000 | 5 |
| `--backoff-ms N` | 1..3600000 | 100 |
| `--max-backoff-ms N` | the backoff..3600000 | 10000 |
| `--grace-ms N` | 1..3600000 | 5000 |
| `--stable-ms N` | 0..86400000 | 10000 |
| `--max-open-files N` | 16..1048576 | unchanged |

`--help` must be the only argument. Events are written to stderr, after the
child's own output, as `supervise TAB elapsed_ns TAB event TAB fields`:

- `start ATTEMPT PID`
- `exit ATTEMPT exited CODE` or `exit ATTEMPT signaled SIG`
- `backoff ATTEMPT DELAY_MS`
- `giveup MAX_RESTARTS`
- `forward SIG`, `kill 9` and `stop SIG`

The exit status is the final child status: its code, or 128 + its signal.
After `stop` it is 128 + the received signal. 125 means the supervisor failed
(`supervise: <reason> errno=N`, including invalid arguments), and 126 or 127
mean the command could not be started.

`tests/fixtures/stdlib_signals/oracle.py` checks the program in two groups,
each of which passes on repeated direct runs:

- **cli** (50 cases):
  - exact help and sixteen malformed argument lists
  - a soft open-file limit above the hard limit refused with 125, checked
    when the host's hard limit is below 1048576
  - exec failures 127 and 126
  - a shell probe of the child's environment, run three times: empty SigBlk
    and SigIgn, its own process group, the supervisor as parent, and the
    open-file soft and hard limits with and without `--max-open-files`
  - `--max-restarts 0` with success and with a crash
- **supervise** (97 cases):
  - three crashes and a success, with delays of exactly 40, 80 and 100 ms in
    the rows, measured gaps within 500 ms of them, and distinct PIDs that match
    the ones the children report
  - stable runs that keep the delay at the base past `--max-restarts`
  - giving up after two restarts with status 137
  - TERM and INT forwarded to a Python handler, which chooses status 0 or 7
  - a child ignoring TERM killed after a 200 ms grace period (measured 200 to
    1000 ms), and a second signal killing it at once
  - a stop during a 5 s backoff within 3 s
  - an INT sent to the supervisor's whole process group reaching the child
    exactly once
