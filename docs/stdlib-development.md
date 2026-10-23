# Testing Lanius libraries

Tests, generated checks, and measured workloads are Lanius source programs.
`tools/lanius-test` compiles one entry to a native x86_64 Linux executable and
runs it. The shell driver supplies phase timeouts and preserves the program's
exit status. The checks, selection, generation, reports, and timing live in
`stdlib/test`.

Build the compiler, then run the library example:

```sh
cargo build --bin laniusc
tools/lanius-test sample_programs/library/library_tests.lani
tools/lanius-test sample_programs/library/library_tests.lani --filter property --seed 42 --cases 1000
tools/lanius-test sample_programs/library/library_tests.lani --list
```

If the compiler is in another build directory, set `LANIUSC` to its executable
path. For example:

```sh
LANIUSC="$PWD/target/stdlib-build/debug/laniusc" tools/lanius-test sample_programs/library/library_tests.lani
```

The example exercises `Option`/`Result` fallbacks, signed formatting and parsing,
an allocated `Vec` against a stack model, generated decimal round trips, and a
measured native workload. It releases each vector owner after its final use.

## Write a suite

The primitive runner lets `main` dispatch tests explicitly:

```lanius
module app::main;
import test::check;
import test::suite;

fn main() -> i32 {
    let runner: test::suite::Runner = test::suite::begin_args();
    if (runner.select(test::check::literal("integer.sum",11))) {
        runner.record(test::check::equal_i64(2 + 2,4,
            test::check::literal("sum differs",11)));
    }
    if (runner.select(test::check::literal("optional.feature",16))) {
        runner.record(test::check::skip(test::check::literal("not configured",14)));
    }
    return runner.finish();
}
```

Evaluate the test only inside a successful `select`. Selection returns false for
filtered tests and in list mode. Every true selection requires exactly one
`record`, followed by one final `finish` for the suite. Missing, repeated, and
out-of-order operations produce runner error status 2. Reports stop after an
output failure; an incomplete report never succeeds.

`begin(filter, seed, cases, list)` supplies the same runner without reading
arguments. `run_args(tests.borrow())` and `run(tests.borrow(), filter, seed,
cases, list)` offer trait dispatch through `suite::Cases`. Implement `count`,
`name`, and `run(index, seed, cases)`; see
`tests/fixtures/stdlib_foundation/development_suite.lani`. Both forms use the
same selection, accounting, and reporting implementation. Cases execute in
source/index order. Names need not be unique; a filter selects every match.

`check::truth`, `equal_i64`, `fail`, and `skip` return ordinary `Outcome` values.
They never catch a trap. An `assert`, `test::assert` failure, panic, invalid
memory access, or explicit exit can terminate the process before its summary.
Use nontrapping checks and handle `Result`/`Option` errors explicitly when a
case should fail and allow later cases to run. Put tests that deliberately trap
in separate source programs; the driver preserves their termination status.

## Names, messages, and ownership

`check::Label` borrows a byte view and a logical length. `literal("text", 4)`
requires the exact UTF-8 byte count of a static string literal. This count is a
caller precondition: the source language currently has no general `str` length
operation. Never overstate the backing length. A label built from other storage
must keep that storage alive and unchanged through `record` or `finish` as
applicable. Case names must contain 1..4096 bytes; detail messages allow
0..4096 bytes; filters allow 0..256 bytes.

The runner and argument parser allocate no heap memory. They use bounded stack
storage for arguments and borrow test labels. Libraries used by a case can own
resources: destroy each manual owner exactly once after the final borrowed view
or alias is no longer used. The runner does not destroy a callback's resources.

## Selection and reports

The compiled source accepts:

| Option | Meaning |
| --- | --- |
| `--filter BYTES` | Case-sensitive byte substring; an empty filter selects all names. |
| `--seed U32` | Decimal seed in 0..4294967295; default 1. |
| `--cases N` | Generated case budget in 1..10000; default 100. |
| `--list` | Print selected names without evaluating any case. |

Unknown and repeated options, missing operands, invalid numbers, overlong
arguments, and more than 16 arguments fail with status 2. A filter with no
matches fails with status 3. An all-skipped suite succeeds. List mode succeeds
when it lists at least one case.

The complete text format starts with `lanius-test 1`, then the seed and case
budget. Each selected case emits `PASS`, `FAIL`, `SKIP`, or `LIST` and its name.
Failed and skipped cases include a detail line; numeric equality failures show
expected and actual values. C0 control bytes, DEL, and backslash in names or
details print as `\xhh`, preserving one physical line per record. Other bytes
are emitted unchanged. A final summary counts selected, passed, failed, skipped,
and filtered cases. List mode records selected/filtered counts with zero result
counts. Benchmark records may appear while a selected case executes.

| Status | Meaning |
| --- | --- |
| 0 | All evaluated cases passed or skipped; or list mode found a match. |
| 1 | At least one case returned a failure. |
| 2 | Invalid configuration, runner transition, callback status, label bound, or report I/O. |
| 3 | No cases matched. |
| 4 | The driver could not compile the source. |
| 124 | A driver phase reached its timeout. |
| 137 | A timed-out phase required a forced kill. |

A signal or a source program's explicit exit can produce other statuses. A
completed summary distinguishes an orderly suite result from early termination.

## Generated properties

Implement `property::Property::check(input: u32, case_id: u32) -> check::Outcome`,
then call `property::run(property.borrow(), seed, cases)` from a selected case.
`case_id` starts at zero. The generator advances a wrapping 32-bit LCG before
each check: `state = state * 1664525 + 1013904223`. Seed zero is valid. The
sequence is deterministic and independent of suite filtering and case order.

The first failed or skipped generated check stops that property. Its report
includes seed, zero-based case ID, generated input, and executed count. Successful
runs return their executed count in the outcome. Invalid budgets return failure
before any callback executes. A property callback must bound its own work;
the case budget cannot interrupt a callback that loops forever.

For example, replay the decimal property with:

```sh
tools/lanius-test sample_programs/library/library_tests.lani --filter property.decimal_roundtrip --seed 42 --cases 1000
```

For a recorded counterexample at case ID K, use the same seed and at least K+1
cases. The generator does not shrink inputs or promise uniform domain coverage.
Reduce an input explicitly when that helps diagnose a failure. Model inputs can
derive operation counts, values, and choices from the generated word.

## Measured workloads

`bench::Work::iteration(index)` performs real work and returns its completed
work-unit count. `bench::measure(clock.borrow(), work.borrow(), iterations)`
uses the typed `std::clock::Monotonic` contract; `bench::native` supplies the
native monotonic clock through concrete `std::clock::monotonic_now` reads. The
injected path is tested with source clock implementations, including scripted
errors and backwards time. Both paths share work accounting and duration
validation. The measurement covers exactly the requested iteration
calls, excluding report output. Bounds are 1..1000000 iterations.

A successful `Measurement` holds iteration count, summed work units, and an
actual `core::time::Duration`. `bench::report` emits those fields and checks
stdout writes. `elapsed_nanos` is the fractional second in 0..999999999; combine
it with `elapsed_seconds` for the total duration. A zero duration is possible for
work below the clock's resolution and is never replaced with a fabricated time.

Clock errors, a reversed clock, invalid bounds, and work-count overflow return
typed errors. Work already completed before an error is not rolled back. Clock
faults and exact iteration/work accounting have deterministic source fixtures in
`development_bench.lani`; native measurements have no fixed duration assertion.
Choose work units that describe useful operations and keep a result/checksum
observable. This API performs one batch: it supplies no warmup, optimizer
barrier, automatic repetition, or statistical confidence claim.

An earlier implementation delegated `native` through `measure<NativeClock,W>`.
That source shape could fail native layout replay unless an otherwise unused
source clock implementation was also present. The precise earlier source and
failure/control pair are retained in
`tests/fixtures/stdlib_compiler_state/development/`; the production implementation
does not use such a declaration or warmup. The native-only execution fixture is
the positive gate for the default clock path.

## Driver configuration

`LANIUS_STDLIB_ROOT` and `LANIUS_SOURCE_ROOT` override the default repository
`stdlib` and `extended` roots. `LANIUS_TEST_COMPILE_SECONDS` defaults to 80;
`LANIUS_TEST_RUN_SECONDS` defaults to 30. Each must be an integer in 1..100.
Their combined budget must be at most 110 seconds; an invalid combination fails
with status 2 before compilation. GNU `timeout` adds at most a two-second
forced-kill grace period per phase, keeping the combined execution limits below
two minutes. Compiler paths,
source paths, roots, temporary directories, and program arguments are passed as
individual quoted arguments. `LANIUSC` names an executable, not a shell command
or an executable plus flags. Compiler diagnostics go to stderr. Temporary native
artifacts are removed when the driver exits.

## Runtime metadata boundary

`test::harness` describes future compiler registration, discovery, and runtime
service 13. It remains known and unbound. `core::target::HAS_TEST_HARNESS` and the
matching `core::runtime` capability remain false. This workflow calls ordinary
source APIs from an explicit `main`, using the already bound process, stdio,
clock, and optional allocation services. It does not add a harness runtime ABI
or make automatic discovery available.
