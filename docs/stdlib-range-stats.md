# range-stats

The application is admitted as **x86_64 Linux ELF through the GPU compiler** at
compiler checkpoint `59612b3431d7b0cdff16a6faecf881f62a675503`. One compilation
passed the strict ELF/jump checker and supplied all 41 successful native test
cases. Execution is native; this evidence does not cover user GPU kernels,
other targets, or throughput benchmarks.

[`sample_programs/library/range_stats.lani`](../sample_programs/library/range_stats.lani)
computes statistics over a quota-limited inclusive ascending i32 range. It uses
the actual `core::iter::RangeI32` and borrowed `Take<RangeI32,i32>` adapter,
checked decimal parsing/formatting, owned argument snapshots, and checked
stdout writes. All application behavior is implemented in Lanius with no ext
dependency or new host service.

## Build and use

From the repository root, with the compiler binary built:

```sh
mkdir -p target/stdlib-work/range-stats
target/stdlib-build/debug/laniusc --stdlib-root stdlib --emit x86_64 \
  sample_programs/library/range_stats.lani \
  -o target/stdlib-work/range-stats/range-stats
target/stdlib-work/range-stats/range-stats -2 2 5
```

The command form is exactly three positionals:

```text
range-stats START END LIMIT
```

The example's stdout is a CSV header and one numeric row:

```csv
count,sum
5,0
```

The range includes both endpoints. Only its first LIMIT values are selected.
Reversed bounds or LIMIT zero produce `count,sum\n0,0\n`. A range whose
endpoints are equal contains one value if its quota is positive; i32::MAX is a
valid endpoint. The program consumes the real iterator rather than substituting
an arithmetic formula.

## Arguments and work bounds

START and END are complete ASCII i32 decimals. The existing core decimal
grammar permits one optional leading `+` or `-` and leading zeroes. Whitespace,
separators, suffixes, missing digits, non-ASCII digits, and overflow are errors.
LIMIT is a complete unsigned u64 decimal without either sign, restricted to
`0..=1_000_000`. For example, `-0002 +0002 0005` is accepted; a signed LIMIT is
rejected.

The snapshot accepts at most three arguments and 96 total argument bytes,
excluding terminating NULs; processing then requires exactly three. There are
no options, stdin input, or implicit default endpoints/quota.

Count uses u64 and sum uses i64. At every selected prefix, the sum's magnitude
is at most `2^31 * 1_000_000 = 2_147_483_648_000_000`, which fits i64. Inclusive
i32::MAX is handled by RangeI32's widened sentinel. Iteration makes at most
LIMIT successful adapter steps plus a final None check; zero quota does not
advance its borrowed source. Parsing is bounded by the argument-byte cap.
Host calls can block, and write_all retains its existing Interrupted retry
policy; there is no elapsed-time bound.

## CSV publication and errors

The entire header, formatted numbers, comma, and final newline are staged in
64 logical packed stack bytes before the first stdout write. Every decimal
formatting result is checked. Even the entire u64/i64 decimal domains need at
most 52 bytes with this framing; the application's tighter bounds need at most
36. Fixed-array backing may occupy more native stack storage than the logical
byte count.

Publication uses `core::io::write_all`. A short write is continued, but a later
I/O error can leave a CSV prefix in stdout. Output is not atomic. No diagnostic
text or error rows are mixed into stdout, and stderr is unused. Argument,
allocation, or signal-setup errors occur before CSV publication.

| Status | Meaning |
| --- | --- |
| 0 | Complete header and data row written |
| 2 | Argument count, byte cap, decimal grammar/range, or quota error |
| 3 | Signal-policy setup, checked output, or defensive formatting error |
| 4 | Argument-snapshot allocation failure |

The formatting-error branch is defensive; fixed capacity covers every valid
input. Main explicitly installs process-wide SIGPIPE Ignore before allocating.
An actual closed stdout pipe can therefore return a checked error so argument
cleanup runs. The iterator library does not change signal policy.

## Ownership

Main owns one `std::args::Arguments` snapshot. The private processing function
borrows a shallow descriptor only; main destroys the active owner after every
parse, iteration/format, or publication result. Snapshot errors clean their own
partial construction. A descriptor copy does not create an extra owner.

The snapshot's entry Vec and packed argument bytes are the only heap owners.
RangeI32, Take, counters, and output staging allocate nothing. The leaf iterator
stays alive while Take borrows it. Argument views stay alive until parsing
finishes and are not retained by the output. Stdout remains a borrowed native
descriptor and is not closed by the program.

## Focused test target

`tests/stdlib_range_stats_execution.rs` contains one test that compiles the real
application once using the ordinary production stdlib root. Every executable
passes the existing strict shared ELF/jump checker. The test reuses that one
executable for 41 native cases:

- Twelve numeric cases cover full i32 endpoints, MIN/MAX singletons, ranges
  ending at MAX, negative sums, reversed bounds, zero quota, and quota-cap cases
  with large positive/negative i64 sums.
- One permitted-sign/leading-zero case and 23 malformed/count/byte-cap cases
  check complete argument grammar and stdout suppression on errors.
- Each of the two argument-snapshot allocation positions is separately failed
  with reached ENOMEM and exact cleanup.
- Injected stdout EIO, an actual closed stdout pipe with EPIPE, and a
  preallocation rt_sigaction EINTR check status 3 and ownership cleanup.

The independent output oracle uses an i128 closed-form arithmetic-series sum
and bounded cardinality; production walks the iterator. It compares complete
stdout bytes. The memory ledger pairs actual addresses with exact sizes and
allocation identities, accepts address reuse only after release, and rejects
wrong/double/unknown releases, extra allocations, mremap, missing injections,
or a nonempty final ownership set.

For the fault input `-2 2 5`, the x86 profile requests 120 bytes for three
View<u8> entries and four bytes for their packed argument text:

| Profile | Attempted sizes | Successful sizes | Release identities |
| --- | --- | --- | --- |
| Baseline / output errors | 120, 4 | 120, 4 | 0, 1 |
| ENOMEM position 1 | 120 | none | none |
| ENOMEM position 2 | 120, 4 | 120 | 0 |
| Signal setup failure | none | none | none |

Arguments.destroy releases entries before packed bytes. Each other argument
case has its exact snapshot profile, including empty or over-limit cases.
These sizes follow the current native View layout and allocator syscall
arguments; they do not assume page rounding. Signal Ignore must precede heap
allocation/output, and the real closed-pipe case must reach write(1) EPIPE.

The focused test command is:

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR=target/stdlib-build CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
  cargo test --test stdlib_range_stats_execution \
  range_stats_csv_arguments_and_exact_failure_cleanup -- --exact --nocapture
```

## Runtime evidence

`range_stats_csv_arguments_and_exact_failure_cleanup` passed in 5.42 s using
one GPU compilation and 41 native executions. The standalone Rust test build
completed in 1.17 s. Compiler checkpoint:
`59612b3431d7b0cdff16a6faecf881f62a675503`.

| Evidence | Terminal log |
| --- | --- |
| Rust test build | `target/stdlib-work/range-stats-admission/build.log` |
| Accepted native/fault group | `target/stdlib-work/range-stats-admission/runtime.log` |

The accepted group checked complete CSV bytes against the independent i128
oracle, all argument/error statuses, both reached allocation failures and
their exact cleanup, stdout EIO, actual pipe EPIPE under Ignore, and signal
setup failure before allocation/output. Every relevant address/size ownership
ledger ended empty. The test invokes the compiler API with the production
stdlib root; the build/use commands show the corresponding CLI entry point.

Elapsed gate times include compilation and instrumentation. They establish
this functional native profile, not execution throughput or support on another
target. No algorithm or test-behavior change was needed for admission.
