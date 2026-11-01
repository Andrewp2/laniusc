# Named host clocks, CPU clocks and absolute waits

`std::host_clocks` exposes the Linux clocks beyond `std::clock`'s CLOCK_MONOTONIC
and CLOCK_REALTIME pair: coarse and raw variants, the suspend-aware boot clock,
TAI, process/thread CPU clocks, another process's CPU clock, clock resolutions
and absolute kernel waits. It issues raw `clock_gettime`, `clock_getres` and
`clock_nanosleep` system calls through `std::linux::call`, uses stack timespec
storage and allocates nothing. Execution is verified on **Linux x86_64 CPU
output from the GPU compiler**; other targets have no binding.

## Clocks and kinds

| `Clock` | Linux clock | Kind | Reading |
| --- | --- | --- | --- |
| `Realtime` | CLOCK_REALTIME (0) | Wall | Settable Unix time |
| `RealtimeCoarse` | CLOCK_REALTIME_COARSE (5) | Wall | Last tick's realtime value; cheaper, tick resolution |
| `Tai` | CLOCK_TAI (11) | Wall | Realtime plus the kernel's TAI offset (zero unless set by time synchronization) |
| `Monotonic` | CLOCK_MONOTONIC (1) | Steady | Same clock as `std::clock::monotonic_now`; excludes suspend; frequency-adjusted |
| `MonotonicRaw` | CLOCK_MONOTONIC_RAW (4) | Steady | Hardware rate, no NTP frequency adjustment |
| `MonotonicCoarse` | CLOCK_MONOTONIC_COARSE (6) | Steady | Last tick's monotonic value |
| `Boottime` | CLOCK_BOOTTIME (7) | Steady | Monotonic plus time spent suspended |
| `ProcessCpu` | CLOCK_PROCESS_CPUTIME_ID (2) | Cpu | CPU time of all threads of this process |
| `ThreadCpu` | CLOCK_THREAD_CPUTIME_ID (3) | Cpu | CPU time of the calling thread |
| `ProcessCpuOf(pid)` | `((~pid) << 3) \| 2` | Cpu | CPU time of process `pid` |
| `RealtimeAlarm` | CLOCK_REALTIME_ALARM (8) | Wall | Reads like Realtime; waits and timers can wake a suspended system |
| `BoottimeAlarm` | CLOCK_BOOTTIME_ALARM (9) | Steady | Reads like Boottime; waits and timers can wake a suspended system |

`kind(clock)` returns `Kind::Wall`, `Steady` or `Cpu`. `id(clock)` returns the
`clockid_t` value as i64. `ProcessCpuOf(pid)` requires `1 <= pid <= PID_LIMIT`
(4,194,304, Linux's PID_MAX_LIMIT); otherwise every operation returns
`InvalidProcess` before any host call. Steady clocks have boot-relative origins
and Monotonic/Boottime are subject to the process's time namespace offsets;
compare instants only from the same clock. There is no conversion between
clocks.

Reading an alarm clock needs no privilege (the kernel requires an RTC device
and returns EINVAL without one). Waiting on one, or creating a
[timer](stdlib-timers.md) on one, needs CAP_WAKE_ALARM; otherwise the kernel
returns EPERM, reported as `Host(1)`.

## Reading

| Function | Accepts | Returns |
| --- | --- | --- |
| `timestamp(clock)` | Wall | `Result<core::time::SystemTime, Error>` |
| `instant(clock)` | Steady | `Result<core::time::Instant, Error>` |
| `cpu_time(clock)` | Cpu | `Result<core::time::Duration, Error>` |
| `resolution(clock)` | Any | `Result<core::time::Duration, Error>` from clock_getres |

A clock of the wrong kind returns `WrongKind` without a host call, so a steady
instant can never be mistaken for a timestamp. Each read is one syscall. The
nanosecond field must be in `[0, 1e9)` and the padding word zero, otherwise
`InvalidTimestamp`; steady and CPU readings and resolutions must also have
nonnegative seconds. A pre-epoch wall reading is a valid SystemTime. Coarse
clocks may lag their fine counterparts by up to one tick, so a coarse reading
taken first never exceeds a later fine one. Resolution is the kernel's reported
granularity (1 ns for high-resolution clocks, one tick such as 1 ms or 4 ms for
coarse clocks), not an accuracy guarantee. The library does not use the vDSO.

`ProcessCpuOf(pid)` reads any process the kernel lets the caller name. It
includes every thread of that process but not the time of descendants it has
already reaped. For a child, the PID names that child while it is running and
after its exit has been observed without reaping (a zombie still carries its
final CPU time); once it is reaped, the read fails with `Host(22)` and the PID
can be reused. Use `std::command::Child::observe_exit()` before `wait()` to read
an exact final CPU time, as `time-command` does.

## Absolute waits

`sleep_until_instant(clock, target)` accepts Monotonic, Boottime and
BoottimeAlarm; `sleep_until_timestamp(clock, target)` accepts Realtime, Tai and
RealtimeAlarm. Other clocks of
the right kind return `Unsupported` (the kernel cannot sleep on raw or coarse
clocks, and sleeping on this process's own CPU clock could never finish in a
single-threaded program); a clock of the other kind returns `WrongKind`.

Each reads the clock first and returns that reading immediately if it is at or
after the target. Otherwise it makes one `clock_nanosleep(clock, TIMER_ABSTIME)`
call for the exact target with nanosecond precision, rereads the clock and
returns the observed value. EINTR repeats the same absolute request, so
interruption can never shift or shorten the wait; other errors return
immediately as `Host(errno)`. A steady target beyond the signed timespec range
is `InvalidTimestamp`. For steady clocks, a post-wake reading earlier than the
first reading is `ClockReversed` and one earlier than the target is
`InvalidStatus`. A realtime wait follows clock changes made while it sleeps:
setting the clock forward past the target wakes it, and the observed timestamp
(which may then be earlier than the target if the clock was set back after
waking) is returned unchanged. Scheduling can make every wake late.

## Boottime as a `std::clock::Monotonic` provider

`boottime()` returns a `Boottime` handle implementing `std::clock::Monotonic`,
so `std::clock::sleep_for` and `sleep_until` accept a suspend-aware clock:
deadlines include time the machine spends suspended. `now()` reads
CLOCK_BOOTTIME. `pause_ms(n)` rejects negative values as `InvalidDuration`,
returns 0 for 0 without a call, and otherwise makes one relative
`clock_nanosleep(CLOCK_BOOTTIME)`; EINTR surfaces as `Host(4)`, which
std::clock's waits retry against their original deadline. Errors map to
`std::clock::Error` as Host, InvalidTimestamp and ClockReversed, with other
local errors as InvalidStatus.

## Errors

| `Error` | Meaning |
| --- | --- |
| `Host(errno)` | Positive Linux errno; EINVAL for `ProcessCpuOf` usually means no such (or already reaped) process |
| `InvalidProcess` | `ProcessCpuOf` PID outside `1..=PID_LIMIT` |
| `WrongKind` | The operation does not accept this clock's kind |
| `Unsupported` | Absolute wait on a clock that cannot be waited on |
| `InvalidTimestamp` | Malformed kernel timespec, negative steady/CPU seconds, or unrepresentable target |
| `InvalidStatus` | Unexpected syscall result or early wake |
| `ClockReversed` | A steady clock read after waking precedes the first read |

## Application: time-command

[`sample_programs/library/time_command.lani`](../sample_programs/library/time_command.lani)
runs one program and reports its timing as one structured record on stderr,
like `time(1)`:

```sh
laniusc --stdlib-root stdlib sample_programs/library/time_command.lani -o time-command
./time-command -- make -j4
./time-command --format tsv -- sh -c 'exit 3'
./time-command --clocks
```

`time-command [--format json|tsv] -- PROGRAM [ARG...]` reads Realtime,
Monotonic and Boottime, spawns PROGRAM through PATH with inherited stdin,
stdout, stderr and environment (and SIGPIPE restored to default in the child),
then blocks in `observe_exit()`. It then reads both steady clocks and the
child's `ProcessCpuOf` clock while the child is an unreaped zombie, reaps it,
and reads its own process CPU time. Each option may appear once; `--` or the
first non-option (including a lone `-`) starts the program, whose arguments are
never parsed. The JSON record has fixed key order:

```json
{"pid":4242,"status":"exited","code":0,"signal":null,"real_ns":1358028,"boot_ns":1357540,"cpu_ns":570777,"self_cpu_ns":813851,"start_unix_sec":1793493043,"start_unix_nsec":340075500}
```

`status` is `exited` or `signaled`; exactly one of `code` and `signal` is
non-null. `real_ns` is the monotonic interval from just before spawning to just
after observation; `boot_ns` is the same on CLOCK_BOOTTIME and exceeds it by
time suspended. `cpu_ns` is the child process's exact user plus system CPU in
nanoseconds; it excludes descendants the child reaped itself (unlike
`RUSAGE_CHILDREN` totals). `self_cpu_ns` is time-command's own CPU.
`--format tsv` writes a header line and one row with the same fields, `-` for
null. `--clocks` instead writes to stdout one row for each of the nine
non-alarm named clocks: `clock`,
`kind`, `resolution_ns`, `sec`, `nsec` (CPU readings are this process's).

The exit status is the child's exit code, or 128 plus its terminating signal;
125 for time-command failures (arguments, clocks, environment snapshot, spawn,
observation or reap, report output), 126 when the program exists but cannot be
executed, and 127 when it is not found (ENOENT/ENOTDIR). Failures write one
`time-command: <reason> errno=N` line to stderr. A spawn with unknown startup
is killed and reaped before exiting 125. time-command ignores SIGPIPE itself,
does not change other signal dispositions (a terminal interrupt reaches both
processes), and must not be combined with outside waiters for its child.

## Evidence

`tests/stdlib_host_clocks_execution.rs` runs four groups; on the current source
they were executed directly as the same compiled programs and oracle commands:

- **contracts** (`tests/fixtures/stdlib_host_clocks/contracts.lani`), a
  self-checking program: every clock id, including the PID encoding at both
  limits; InvalidProcess at 0, -1, PID_LIMIT+1 and i32::MIN; WrongKind and
  Unsupported before host calls; ordered Monotonic/Boottime, coarse/fine and
  wall/TAI reads; thread <= process CPU, a PID-named reading of itself between
  two process readings, and EINVAL for an absent PID; positive sub-second
  resolutions for all nine clocks; absolute Monotonic, Boottime, Realtime and
  Tai waits that wake at or after their targets; past targets; and Boottime
  driving `std::clock::sleep_for`. Alarm clocks: ids 8 and 9, readings
  between their Realtime/Boottime neighbours, kind checks, a past target
  returning without a call, and a future BoottimeAlarm wait that must succeed
  or return EPERM; eleven
  resolutions are positive. It exits 0 with no output.
- **cli** (50 cases): exact help, ten malformed argument lists, ENOENT,
  a lone `-` program, PATH miss, EACCES file and directory, exit codes 0/1/3/255, signals
  15/9/6, binary stdout passthrough with child stderr ahead of the report,
  stdin inheritance, default SIGPIPE in the child (141), TSV statuses and
  option-like program arguments.
- **timing** (21 cases): start time between Python's surrounding reads;
  `real_ns` at least a 150 ms child sleep and within the observed interval,
  low CPU for a sleeping child, Boottime within 50 ms of Monotonic; a busy child's
  `cpu_ns` at least its own final `process_time_ns()` and within 100 ms of it,
  in JSON and TSV; and a shell whose reaped busy child is excluded.
- **clocks** (48 cases): JSON and TSV tables agree; every resolution equals
  Python `time.clock_getres` for the same clock id; every system-wide reading
  lies between Python reads of the same clock before and after the run.

The existing `authority` and `capture` command-group oracles (4 and 2 cases)
pass after `observe_exit()` was added beside `try_observe_exit()`.
Sources: [clock_gettime](https://man7.org/linux/man-pages/man2/clock_gettime.2.html),
[clock_nanosleep](https://man7.org/linux/man-pages/man2/clock_nanosleep.2.html),
[clock_getcpuclockid](https://man7.org/linux/man-pages/man3/clock_getcpuclockid.3.html),
[waitid](https://man7.org/linux/man-pages/man2/waitid.2.html).
