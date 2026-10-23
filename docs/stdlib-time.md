# Durations, clocks and deadlines

`core::time` provides allocation-free Duration, Instant, SystemTime and Deadline
values. `std::clock` supplies native clock reads and generic deadline waits.
Execution is verified on **x86_64 Linux using the GPU compiler**. Core arithmetic
uses portable Lanius operations; other targets and GPU execution of user programs
have not been established by these tests.

## Duration

A Duration stores nonnegative u64 whole seconds and a u32 nanosecond fraction
in `[0, 1_000_000_000)`. Its maximum is u64::MAX seconds plus 999,999,999 ns.
Values copy independently and need no destruction. Use constructors and preserve
normalized fields: the language does not enforce field privacy.

| Constructor | Behavior |
| --- | --- |
| `zero()` | Zero seconds and nanoseconds |
| `max_duration()` | Largest representable duration |
| `duration(seconds, nanos)` | Normalize excess u32 nanoseconds; return Overflow if the carry exceeds u64 seconds |
| `from_secs(u64)` | Exact whole seconds |
| `from_millis(u64)` | Exact whole milliseconds |
| `from_micros(u64)` | Exact whole microseconds |
| `from_nanos(u64)` | Exact whole nanoseconds |

The unit constructors are infallible. Normalizing `duration(3, 4_294_967_295)`
gives 7 seconds and 294,967,295 ns; the constructor returns `Result<Duration, Error>`.

| Method | Behavior |
| --- | --- |
| `is_zero()` | Test both components |
| `as_secs()` | Whole seconds, discarding the fraction |
| `subsec_nanos/micros/millis()` | Fractional part in the named unit, rounded down |
| `as_nanos/micros/millis()` | Whole duration in that unit, rounded down; `Result<u64, Error>` |
| `as_secs_f64()` | Approximate seconds; large values can lose precision or round up |
| `compare(other)` | -1, 0 or 1 |
| `checked_add/sub(other)` | Exact addition/subtraction or an explicit error |
| `checked_mul(u32)` | Exact product or Overflow; zero factor yields zero |
| `checked_div(u32)` | Divide and round down to a nanosecond; zero divisor is an error |
| `saturating_add/sub(other)` | Clamp overflow to the maximum or subtraction below zero to zero |
| `saturating_mul(u32)` | Clamp an overflowing product to the maximum |

Checked arithmetic returns `Result<Duration, core::time::Error>`. Errors are
Overflow, Negative and DivisionByZero. Integer-unit conversion returns Overflow
when the total cannot fit u64, even if the Duration itself fits. No operation
silently wraps a duration. Division discards subnanosecond fractions.

For example, converting a large duration to milliseconds can fail while reading
its whole seconds and fractional milliseconds remains valid. The API does not
pretend that its full seconds range fits in a single u64 nanosecond count.
Float-to-duration construction and signed durations remain future work.

## Instants and deadlines

`instant(duration)` constructs an Instant relative to an explicit clock origin.
This supports injected clocks and deterministic tests. Native monotonic instants
come from `std::clock::monotonic_now()`. Compare or subtract instants only from
the same origin; the type does not encode or check a clock identity.

Instant exposes `compare`, `checked_add(Duration)`, `checked_sub(Duration)`,
`duration_since(earlier)` and `saturating_duration_since(earlier)`. Checked addition
can return Overflow; checked subtraction or a reversed duration_since returns
Negative. The saturating difference returns zero when the other instant is later.
These arithmetic methods do not read a clock.

`deadline_at(Instant)` constructs a Deadline. `deadline_after(start, duration)`
returns a checked Result. `is_expired(now)` includes equality, and
`remaining(now)` saturates at zero. A deadline stores its target once; querying
it never resets its origin or adds another interval. These pure operations take
the current instant explicitly and perform no sleep or polling.

## SystemTime

`system_time(seconds: i64, nanos: u32)` returns a SystemTime or InvalidNanoseconds
when the fraction is at least one billion. Seconds are signed Unix seconds;
the fraction is always nonnegative. Thus `(-1, 999_999_999)` is one nanosecond
before the epoch. This constructor requires an already normalized fraction.
`unix_epoch()` constructs `(0, 0)`.

SystemTime exposes `unix_seconds`, `subsec_nanos`, `compare`, `duration_since`,
`checked_add(Duration)` and `checked_sub(Duration)`. Subtracting a later timestamp
returns Negative. Adding/subtracting beyond the signed-second range returns
Overflow. Arithmetic and differences cover the full i64 seconds domain, including
i64::MIN; they do not flatten the timestamp into overflowing i64 nanoseconds.

Duration, Instant and SystemTime implement `core::cmp::Eq`, `Ord` and
`core::hash::Hash`. Equal normalized values hash equally. Hash-map replacement,
ordered-map traversal and vector sorting execute with these types. They are
ordinary copied values, so using them as keys adds no nested ownership duty.

Calendar dates, time zones, leap-second representation and textual timestamp
formats are outside this module. SystemTime arithmetic treats each second as
one billion nanoseconds and makes no implicit calendar interpretation.

## Native clock reads

`std::clock::monotonic_now()` returns `Result<Instant, std::clock::Error>`.
`system_now()` returns `Result<SystemTime, Error>`. Each performs one native
16-byte clock read into stack storage and validates the result. The adapter
preserves full signed seconds and nanoseconds; it allocates nothing.

On Linux these use CLOCK_MONOTONIC and CLOCK_REALTIME respectively. Monotonic
reads may repeat, are affected by frequency adjustment and do not include system
suspend time. Realtime reads can jump as the wall clock changes. They represent
Unix time without separately counting leap seconds. See the Linux
[clock_gettime contract](https://man7.org/linux/man-pages/man2/clock_gettime.2.html).
These clocks serve different purposes; there is no automatic conversion between
Instant and SystemTime.

| Host error | Meaning |
| --- | --- |
| `Host(errno)` | Positive Linux error number from the underlying call |
| `InvalidTimestamp` | Malformed nanoseconds, or negative native monotonic seconds |
| `InvalidStatus` | A host operation returned an unexpected positive status, or a custom pause returned the wrong count |
| `InvalidDuration` | Negative argument to NativeClock.pause_ms |
| `Overflow` | The requested relative deadline cannot fit Instant |
| `ClockReversed` | A clock read during a wait precedes the previously observed instant |

Clock-read errors return immediately, including EINTR. A legitimate system time
before the epoch is a successful value. Read metadata and capability flags in
the legacy module are not probes for a successful current host call.

## Waiting and injected clocks

`native()` returns a NativeClock handle; `borrow()` borrows it. The `Monotonic`
trait defines:

```lanius
pub fn now(&self) -> core::result::Result<core::time::Instant, Error>;
pub fn pause_ms(&self, milliseconds: i32) -> core::result::Result<i32, Error>;
```

A successful pause returns the requested milliseconds. NativeClock rejects
negative inputs and returns zero for a zero pause without a syscall. A positive
pause uses the existing i32-millisecond binding. A clock implementation must use
one origin, supply valid instants and perform its documented wait; returning a
successful count does not excuse silently skipping the operation.

`sleep_for(clock, duration)` reads a starting instant, checks its target and
waits. `sleep_until(clock, deadline)` reads the current instant and waits for the
given target. Both return `Result<Instant, Error>`: the observed instant at or
after the deadline. They share one loop and accept native or injected clocks.
A zero duration or expired deadline needs a clock read but no pause.

The loop computes the remaining duration, rounds it **up** to milliseconds and
caps each request at i32::MAX milliseconds. This supports long durations without
truncating them to the host argument width. It rereads the clock after every
successful or interrupted pause. Host(4), Linux EINTR, from pause_ms is retried
against the original deadline; other pause errors return immediately. Relative
sleep failure can occur after time has already elapsed, and no progress duration
is returned with the error.

The Linux [nanosleep contract](https://man7.org/linux/man-pages/man2/nanosleep.2.html)
allows interruption and scheduling delay. This library uses relative millisecond
requests because those are the bound runtime operations. It checks the original
deadline between requests, but does not claim an atomic kernel absolute wait or
nanosecond sleep precision. Rounding and scheduling can make return late; repeated
interruptions can postpone it further. Successful return is never reported merely
because a pause call returned success while the observed clock is still early.

Custom clocks must eventually progress or fail. Repeated equal reads are allowed;
there is no arbitrary retry cap that turns a slow clock into false success.
Clock identity, concurrent use and cancellation remain caller responsibilities.
No thread, cancellation, suspend-aware clock or timer-queue service is implied.

## Application: scheduled ticks

[`sample_programs/clock_ticks.lani`](../sample_programs/clock_ticks.lani) combines
integer argument parsing, deadlines, native clocks, formatting and complete
stream writes. With the compiler already built:

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc sample_programs/clock_ticks.lani --stdlib-root stdlib --source-root extended -o target/stdlib-work/clock-ticks
timeout 5s target/stdlib-work/clock-ticks 3 10
```

Arguments are COUNT and INTERVAL_MS, defaulting to 3 and 10. Limits are 1,000
records and 60,000 milliseconds per interval. The first record has the starting
deadline; later deadlines are `start + index * interval`, so record-writing time
does not move the planned schedule. Missed deadlines are emitted as soon as the
program can proceed. Each JSON record contains tick, unix_seconds, nanoseconds,
elapsed_ns and late_ns. Wall-clock timestamps are informational; scheduling and
lateness use the monotonic clock.

Count zero validates arguments and exits without clock reads or output. Exit
status 2 means invalid arguments; 3 means clock, arithmetic or output failure.
Output errors can leave a prefix. The application performs no heap allocation.

## Evidence

`tests/time_execution.rs` compiles real modules and executes five focused groups:

- Normalization, full-width limits, arithmetic errors, negative Unix timestamps,
  comparison/hash contracts, deadlines and float conversion of an exact value.
- 400 arithmetic cases against a u128/i128 nanosecond model: 144 boundary pairs
  and 256 generated cases, seed `0x71ae202612345678`. Each checks constructors,
  arithmetic, saturation, conversions, instant operations and signed timestamps.
- Scripted clock progress, repeated readings, interruption, rounding, expired
  deadlines, failures before/after a pause, reversal, overflow and multi-chunk
  waits, without host operations or real delays.
- Native clock values compared with traced timespec bytes; injected signed
  boundaries, malformed fractions/statuses, errno preservation, interruptions,
  no-op zero pauses and requests capped at the exact i32-millisecond limit.
  Tests of very long sleeps suppress the real syscall and force a later error.
- Scheduled records, CLI bounds, every observed clock/output failure, retry and
  allocation denial; time types in collections; 1,048,576 exact additions and
  repeated native clock reads with no allocation attempts.

All five groups passed on 2026-10-23 in 13.24 seconds. Run from the repository root:

```sh
timeout --kill-after=2s 100s env CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 cargo test --locked --test time_execution -- --nocapture
```

Native measurements on 2026-10-23, Ryzen 9 5950X pinned to CPU 8:

| Workload | Small batch: median CPU time | Large batch: median CPU time |
| --- | --- | --- |
| Checked duration additions | 65,536: 3.872 ms | 1,048,576: 59.274 ms |
| Monotonic clock reads | 4,096: 3.467 ms | 65,536: 51.616 ms |

`time_batch.lani` accepts mode (0 arithmetic, 1 clocks) and count. Arithmetic
accumulates 123,456,789 ns per step and outputs the exact total; the clock workload
also checks nondecreasing reads and outputs elapsed nanoseconds. Each size had
one warm-up and nine alternating measured runs. Whole-process CPU times include
argument parsing and final output; compilation and strace are excluded. The large
arithmetic batch ranged from 57.435 to 88.864 ms, and clock reads from 46.497 to
61.011 ms. These are observations on this machine, not timing test thresholds
or compiler-performance comparisons.

## Existing surfaces and remaining dependencies

| Existing surface | Classification |
| --- | --- |
| `std::time::monotonic_read`, `system_read`, `sleep_ms_i32` | Executable native bindings, with raw status/pointer contracts |
| `std::time::unix_seconds` | Executable legacy i32-second binding; new SystemTime uses the full-width read |
| `monotonic_now_ns`, `system_now_unix_ms`, `sleep_ms(i64)` in std::time | Explicitly unbound ABI declarations; not supported operations |
| `std::time_checked` | Executable helpers with boolean failure and raw timespec storage |
| `std::time_wide` | Executable two-word decoding/read helpers with boolean/fallback failure |
| New `core::time`, `std::clock` | Executable typed arithmetic, clocks and generic waits; no silent stub operations |

The raw declarations retain their compiler-bound identities. Migrating old
checked/two-word consumers, float construction, calendar/zone libraries,
additional clocks, cancellation and native absolute/submillisecond sleep remain
work. No forwarding compatibility modules were added.

A [compiler reproduction](../tests/fixtures/stdlib_foundation/clock_wait_dependency/README.md)
records a layout failure when a generic clock read is followed by the fallible
Deadline factory. Separately typed Instant addition and Deadline construction
execute correctly. Production retains the generic APIs and shared wait loop
with that construction; the compiler limitation remains listed in
[library-dependencies.md](library-dependencies.md).
