# Event loop

`std::event` wraps a Linux [epoll](https://man7.org/linux/man-pages/man7/epoll.7.html)
instance and adds process descriptors ([pidfd](https://man7.org/linux/man-pages/man2/pidfd_open.2.html)).
One `Loop` multiplexes pipes, sockets, `std::timer` timerfds and child pidfds.
Readiness is level-triggered, each registration carries a 64-bit caller token,
waits take a millisecond timeout or a `core::time::Deadline`, and every
failure is an explicit `Error`. The module issues raw `epoll_create1`,
`epoll_ctl`, `epoll_wait`, `epoll_pwait2`, `pidfd_open`, `pidfd_send_signal`
and `close` system calls through `std::linux::call`. It allocates nothing;
events are staged in stack storage. Execution is verified on **Linux x86_64
CPU output from the GPU compiler**.

## Loops and registrations

`create()` opens a close-on-exec epoll descriptor. A `Loop` does not own the
descriptors it watches.

| Method | Effect | Errors |
| --- | --- | --- |
| `add(fd, interest, token)` | Register `fd`; its events report `token` | `Host(17)` (EEXIST) when already registered, `Host(1)` (EPERM) for regular files and directories, `Host(9)` (EBADF) for a closed fd, `Bounds` for a negative fd |
| `modify(fd, interest, token)` | Replace interest and token; rearms a oneshot registration | `Host(2)` (ENOENT) when not registered |
| `remove(fd)` | Deregister | `Host(2)` (ENOENT) when not registered |

`Interest` starts from `readable()`, `writable()` or `read_write()`.
`with_read_closed()` also reports a peer's write shutdown (EPOLLRDHUP),
`with_priority()` adds urgent data (EPOLLPRI), and `oneshot()` disables the
registration after one reported event until `modify` rearms it. Errors and
hangups are always reported, whatever the interest.

`registered()` counts successful adds minus successful removes through this
owner. Remove each descriptor before closing it: the kernel drops a
registration only when the last reference to the open file description closes,
so a duplicate held by a child or another fd keeps it reporting events.

## Waiting

Both waits fill the front of a caller's `View<Event>` (1 to `MAX_EVENTS` = 64
slots; anything else is `Bounds`) and return the number of events written.

- `wait(events, timeout_ms)` is one `epoll_wait`. `-1` blocks, `0` polls, and a
  timeout returns 0. EINTR is returned as `Host(4)`; values below -1 are `Bounds`.
- `wait_until(events, deadline)` waits until at least one event or until the
  `CLOCK_MONOTONIC` deadline (the `std::clock::monotonic_now` origin), with
  `epoll_pwait2`'s nanosecond timeout. EINTR and early wakes retry against the
  same deadline, so it returns 0 only once the clock has reached the deadline.
  An already expired deadline still polls once.

Each `Event` has `token` and readiness bits: `readable()`, `writable()`,
`priority()`, `error()`, `hangup()` and `read_closed()`. A pipe whose writer
closed is readable and hung up; read to end of file, then remove it. A timerfd
is readable while an expiration count is unread; read it with `try_wait()` on a
nonblocking timer. A pidfd is readable once the process has terminated.

## Closing

`close()` returns `StillRegistered(n)` while `n` registrations remain, so
cleanup is explicit. Otherwise it closes the descriptor exactly once and never
retries it. `force_close()` closes even with registrations, which the kernel
drops with the instance. After either, every operation returns `Closed`.
Copies of a `Loop` value alias one descriptor and do not share the count.

## Process descriptors

`pidfd_open(pid)` opens a descriptor for one process (`Bounds` unless
`1 <= pid <= std::host_clocks::PID_LIMIT`). Open it while the child is
unreaped, so the PID cannot have been reused. It becomes readable when the
process terminates, before the parent reaps it, and opening or closing it never
reaps or affects the process. `send_signal(signal)` (0 to 64; 0 checks
existence) signals exactly that process. After it has been reaped the call
returns `Host(3)` (ESRCH), even if the PID was reused. Reap with `std::command`
as usual; `close()` closes once and later calls return `Closed`.

## Errors

| `Error` | Meaning |
| --- | --- |
| `Host(errno)` | Positive Linux errno from the system call |
| `Closed` | The owner was already closed |
| `Bounds` | Negative fd, invalid event view, timeout below -1, PID or signal out of range |
| `StillRegistered(n)` | `close()` refused while `n` registrations remain |
| `InvalidResult` | Unexpected system call result |
| `Clock(cause)` | The monotonic clock read for a deadline failed |

## Application: tee-children

[`sample_programs/library/tee_children.lani`](../sample_programs/library/tee_children.lani)
runs two commands and tees both children's stdout and stderr through one loop:

```sh
laniusc --stdlib-root stdlib sample_programs/library/tee_children.lani -o tee-children
./tee-children -- make build ::: make test
./tee-children --timeout-ms 5000 --max-line 200 -- ./server ::: ./client --once
```

Both programs are found through PATH and get a null stdin. The loop registers
four pipes (tokens 0 to 3), two pidfds (4 and 5), and, with `--timeout-ms N`
(1 to 86400000; 0 or absent means none), a nonblocking Monotonic timerfd. Each
output row on stdout is

```
elapsed_ns <TAB> child <TAB> stream <TAB> kind <TAB> data
```

where `elapsed_ns` is the monotonic time since start when the bytes were read,
`child` is 1 or 2, `stream` is `out` or `err`, and `kind` is `line` (newline
removed), `split` (a line cut at `--max-line` bytes, 1 to 65536, default 4096)
or `partial` (bytes before end of file without a newline). Data bytes are
written unchanged. A child's exit is a `status` row with `exited CODE` or
`signaled SIG`. Rows are written in arrival order, so timestamps never
decrease.

On timeout the program writes `0 status timeout N`, sends SIGKILL to every
unreaped child through its pidfd, and arms a 100 ms grace period. Streams still
open when it ends (for example, held by a grandchild) are finished with their
partial lines, so the program does not wait for descendants. Every descriptor
is removed from the loop before it is closed, and the loop closes with no
registrations.

The exit status is 124 after a timeout. Otherwise it is child 1's nonzero code
(128 + signal for a signal), else child 2's. Exit 125 means the program itself
failed (`tee-children: <reason> errno=N` on stderr, including invalid
arguments). 126 and 127 mean a command could not be started; if the second
fails, the first is killed and reaped.

## Evidence

`tests/stdlib_event_loop_execution.rs` runs three groups. On the current
source they were executed directly as the same compiled programs and oracle
commands:

- **contracts** (`tests/fixtures/stdlib_event_loop/contracts.lani`), a
  self-checking program. It covers:
  - view, fd and timeout bounds
  - pipe readiness, level-triggered repeats and hangup after the writer closes
  - EEXIST, ENOENT and 64-bit tokens
  - oneshot disable and modify rearm
  - a Unix socket pair writable, then read-closed after a write shutdown
  - a timerfd woken through `wait_until` and an expired-deadline poll
  - a pidfd readable before the reap, ESRCH after it, and SIGKILL through a pidfd
  - `StillRegistered(2)`, `close`/`Closed` and `force_close`
  - `pidfd_open(0)` as `Bounds`

  Repeated runs exit 0.
- **cli** (56 cases): exact help and fourteen malformed argument lists, exec
  failures 127 and 126, prompt cleanup when the second spawn fails, exit-code
  precedence over four code pairs, and 143 for a child killed by SIGTERM.
- **tee** (12571 cases). It covers:
  - Two Python children write four streams on one shared 20 ms
    `CLOCK_MONOTONIC` schedule. The merged rows follow the schedule exactly,
    the median gap between stamps is at least 10 ms, and the span is at least
    300 ms.
  - With `--max-line 8`, splits, empty lines, tabs, CR and raw `0xff` bytes,
    and partial tails are exact.
  - 1 MiB of numbered lines on one stream arrives complete and in order next
    to 2000 stderr lines from the other child.
  - A 150 ms timeout gives exit 124, a timeout row at 150 ms or later, both
    children signaled 9, the output written before the timeout, and a run
    under 2 s.
  - A grandchild holding a pipe ends with exit 124 after timeout and grace,
    with the partial line emitted.
  - A run that finishes early writes no timeout row.

  Every run also checks that rows are well formed and timestamps nondecreasing.
