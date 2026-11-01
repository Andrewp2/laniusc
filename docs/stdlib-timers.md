# Timers

`std::timer` wraps Linux [timerfd](https://man7.org/linux/man-pages/man2/timerfd_create.2.html)
timers: one-shot or periodic, relative or absolute, with blocking or
nonblocking expiration reads. Each `Timer` owns one close-on-exec descriptor.
It issues raw `timerfd_create`, `timerfd_settime`, `timerfd_gettime`, `read`
and `close` system calls through `std::linux::call`, uses stack storage and
allocates nothing. Execution is verified on **Linux x86_64 CPU output from the
GPU compiler**.

## Creating and closing

`create(clock, mode)` accepts the clocks timerfd supports, named with
[`std::host_clocks::Clock`](stdlib-host-clocks.md): `Monotonic`, `Boottime`,
`Realtime`, `RealtimeAlarm` and `BoottimeAlarm`. Any other clock returns
`Clock(Unsupported)` before the system call. `Mode::Blocking` timers are read
with `wait()`; `Mode::Nonblocking` timers with `try_wait()`.

Alarm timers can wake a suspended system. Creating one needs CAP_WAKE_ALARM;
without it the kernel returns EPERM, reported as `Host(1)`. Monotonic timers
stop counting during suspend; Boottime and the alarm clocks include it.
Realtime timers follow the wall clock.

`close()` closes the descriptor exactly once and marks the owner closed even
if the close fails; it is never retried, because the descriptor number may be
reused. Every later operation returns `Closed`. There is no automatic
destructor: close each timer once. Copies of a `Timer` value alias the same
descriptor and do not track each other's close. `raw_fd()` exposes the
descriptor for readiness polling (for example with `std::poll`); reading or
closing it directly breaks the owner's contract. `clock()` and `is_open()`
report the owner's state.

## Arming

| Method | Clock kind | First expiration |
| --- | --- | --- |
| `arm_after(initial, interval)` | Any | `initial` from now; must be nonzero |
| `arm_at_instant(target, interval)` | Steady (`Monotonic`, `Boottime`, `BoottimeAlarm`) | `target` on the timer's clock; must be nonzero |
| `arm_at_timestamp(target, interval, cancel_on_set)` | Wall (`Realtime`, `RealtimeAlarm`) | Positive Unix timestamp `target` |

After the first expiration the timer expires every `interval`; a zero interval
makes it one-shot. A zero `initial` or zero target (which the kernel treats as
"disarm"), a negative or epoch wall target, unnormalized nanoseconds or a span
beyond the signed timespec range return `InvalidSetting`. A target of the wrong
kind returns `Clock(WrongKind)`. All validation happens before the system call.

Each arm or `disarm()` replaces the previous setting, discards any unread
expiration count, and returns the previous setting. A `Setting` has
`remaining` (relative time to the next expiration, even for absolute timers)
and `interval`; `is_armed()` means nonzero remaining and `is_periodic()`
nonzero interval. `setting()` reads the current one without changing it. A
one-shot timer is disarmed once it has expired.

An absolute target that has already passed expires asynchronously soon after
arming, not necessarily before an immediate `try_wait()`, and counts every
missed period. With `cancel_on_set`, a discontinuous change to the wall clock
(for example `settimeofday`) makes the next read return `Cancelled` (ECANCELED)
while the timer stays armed. Without it, a changed clock simply moves the
absolute target.

## Reading expirations

`wait()` blocks until at least one expiration and returns the number since
the last read, which is greater than one when the reader fell behind
(overruns); the count is consumed. EINTR is retried. `try_wait()` returns
`None` when nothing has expired and `Some(count)` otherwise; EINTR is returned
as `Host(4)`. Calling the read that does not match the timer's mode returns
`WrongMode`. A blocking `wait()` on a disarmed timer blocks until the timer is
armed again, so arm before waiting. A count of zero or a short read is
`InvalidCount`.

## Errors

| `Error` | Meaning |
| --- | --- |
| `Clock(cause)` | `Unsupported` clock, `WrongKind` target or invalid PID clock from `std::host_clocks` |
| `Host(errno)` | Positive Linux errno, including EPERM for alarm timers without CAP_WAKE_ALARM |
| `Closed` | The owner was already closed |
| `InvalidSetting` | Zero, negative, epoch or unrepresentable setting |
| `WrongMode` | `wait()` on a nonblocking timer, or `try_wait()` on a blocking one |
| `Cancelled` | A cancel-on-set wall timer saw the clock change |
| `InvalidCount` | Unexpected syscall result, zero count or malformed kernel timespec |

## Application: timer-ticks

[`sample_programs/library/timer_ticks.lani`](../sample_programs/library/timer_ticks.lani)
arms one blocking timer and reports every read:

```sh
laniusc --stdlib-root stdlib sample_programs/library/timer_ticks.lani -o timer-ticks
./timer-ticks --interval-ms 20 --count 4
./timer-ticks --clock boottime --absolute --interval-ms 10 --count 3 --work-ms 35 --format tsv
./timer-ticks --clock realtime --absolute --initial-ms 15
```

Options, each at most once: `--clock monotonic|boottime|realtime|realtime-alarm|boottime-alarm`
(default monotonic), `--interval-ms N` (0..60000, default 0 for one-shot),
`--initial-ms N` (1..60000, default the interval, or 10 for one-shot),
`--count N` reads (1..10000, default 1; one-shot allows only 1),
`--work-ms N` (0..60000) sleeping between reads to simulate a slow consumer,
`--absolute` to arm at start plus initial on the timer's clock, and
`--format json|tsv`. The program reads its start time on the timer's own clock,
arms the timer, and writes one row per read to stdout: `read`, `expirations`,
`total` and `elapsed_ns` since the start. TSV adds a header line. After the
last read it disarms, checks the setting is disarmed, and closes.

Exit status 0 is success or `--help`, 2 invalid arguments, 3 a host failure,
reported as `timer-ticks: <stage> errno=N` on stderr (for example
`create failed errno=1` for alarm clocks without CAP_WAKE_ALARM). A wall clock
set backwards during a run is reported as a clock failure rather than a negative
elapsed time.

## Evidence

`tests/stdlib_timers_execution.rs` runs three groups. On the current source
they were executed directly as the same compiled programs and oracle commands:

- **contracts** (`tests/fixtures/stdlib_timers/contracts.lani`), a
  self-checking program: unsupported clocks rejected before the call; alarm
  creation is a timer or EPERM; relative one-shot (one expiration, at least
  5 ms elapsed, disarmed afterwards); periodic overruns (at least five after
  11 ms of 2 ms periods); disarm returning the previous periodic setting;
  kind, zero and unnormalized settings; mode mismatches; an absolute steady
  target; close once and every operation `Closed` afterwards; a nonblocking
  Boottime timer whose past target counts at least ten missed 1 ms periods;
  and an absolute cancel-on-set Realtime timer. Ten repeated runs exit 0.
- **cli** (19 cases): exact help, sixteen malformed argument lists, and both
  alarm clocks checked against this process's CAP_WAKE_ALARM from
  `/proc/self/status` (EPERM on the test machine).
- **ticks** (138 cases), ten configurations over Monotonic, Boottime and
  Realtime, relative and absolute, one-shot and periodic, JSON and TSV. For
  each read the reported total is the running sum, the total-th expiration
  time `initial + (total-1)*interval` is at most the elapsed time, and the
  total never exceeds `floor((elapsed - initial)/interval) + 1`. With
  `--work-ms`, every period that ended before the slow consumer's next read is
  counted (exactly for absolute timers, within 1 ms of arming delay for
  relative ones), so later reads report at least three overruns. Python's
  own monotonic duration of each run is at least the last expiration time.
