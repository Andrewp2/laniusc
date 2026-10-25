# column-sum

[`sample_programs/library/column_sum.lani`](../sample_programs/library/column_sum.lani)
selects one whitespace-delimited column from bounded UTF-8 stdin and prints a
checked count/sum CSV summary. Its real iterator chain is
`Text.split → Filter → Map<Result<i64,Error>> → try_fold`. The predicate and
selection implement `Mapper`; the accumulator callback implements `TryFolder`.
Application parsing, selection, and reduction are Lanius.

The application is admitted as **x86_64 Linux ELF through the GPU compiler**.
One strict-checked executable supplied 58 passing native cases. The acceptance
record below gives the compiler checkpoint, commands, logs, and tested scope.

## Build and use

With the compiler binary built, from the repository root:

```sh
mkdir -p target/stdlib-work/column-sum
target/stdlib-build/debug/laniusc --stdlib-root stdlib --emit x86_64 \
  sample_programs/library/column_sum.lani \
  -o target/stdlib-work/column-sum/column-sum
printf 'apples 7\nbananas -2\n' | target/stdlib-work/column-sum/column-sum 2
```

The output is exactly:

```csv
count,sum
2,5
```

The CLI is `column-sum COLUMN`, with exactly one positive, one-based unsigned
ASCII u64 decimal. Leading zeroes are allowed; signs, whitespace, suffixes,
missing digits, zero, and overflow are rejected. The raw argument snapshot
permits one argument and 32 total bytes, excluding argv[0] and terminating NULs.
No independent column-value cap is imposed. A column larger than the number
of words fails on the first retained row; empty/comment-only input still
produces `count,sum\n0,0\n` for every valid column.

## Input and selection

The input limit is **1,048,576 bytes**, including separators and line endings.
The program reserves the entire bound once in an owned `alloc::io::Buffer`,
then reads stdin through the existing 1,024-byte stack copy adapter. At the
bound it still checks actual EOF. Detecting excess input can consume up to
1,024 additional bytes; excess bytes are not appended to the buffer. Exceeding
the limit returns status 7 without output. Read Interrupted is retried, while
other input errors return status 3.

After reading succeeds, the entire buffer is validated as UTF-8 before any
filtering or selected-field parsing. Invalid UTF-8 anywhere, including a
comment or unselected field, returns status 6 without output.

Lines split only at LF. The predicate drops lines that become empty after
ASCII trimming and lines whose first non-ASCII-whitespace byte is `#`.
Whitespace means exactly HT, LF, VT, FF, CR, and space. CRLF input is accepted;
CR, VT, and FF inside a line separate words. Non-ASCII whitespace and NUL are
ordinary field bytes. There is no inline-comment syntax or quoting.

Each retained line splits at those ASCII whitespace bytes. The chosen column
must be a complete i64 decimal, with an optional leading sign and leading
zeroes permitted by `core::decimal`. Missing columns, malformed tokens, and
integer overflow return status 6. Unselected fields may contain arbitrary
valid UTF-8 text. The whole retained row contributes one count and one value.

## Reduction and publication

Map yields an ordinary `Result<i64,Error>` item. The `TryFolder` propagates a
selection error and checks count with `core::u64::checked_add` and the running
sum with `core::i64::checked_add`. `try_fold` stops at the first error without
another source request. Structured application errors distinguish missing
column, decimal parse failure, and arithmetic failure.

Every selected prefix must fit i64. An overflowing or underflowing prefix
returns status 5, even if later values could cancel it back into range. Full
UTF-8 validation precedes this reduction; afterward the first selected-token
or arithmetic error determines the result. A late malformed token cannot
override an earlier arithmetic error that already stopped the fold.

Only a successful full reduction formats output. The header, decimal count,
comma, decimal sum, and newline are staged in 64 packed logical stack bytes;
all formatter results are checked. The whole u64/i64 domains need at most
52 bytes with this framing. Publication uses checked `write_all`, which
continues short writes and retries Interrupted. A later write failure may
leave a CSV prefix. Stderr is unused.

| Status | Meaning |
| --- | --- |
| 0 | Complete CSV header and summary written |
| 2 | Invalid CLI arity, byte budget, or column decimal/value |
| 3 | Signal setup, input/output, argument host-read, or defensive formatting error |
| 4 | Argument or input-buffer allocation failure |
| 5 | Checked count or selected-prefix sum overflow |
| 6 | Invalid UTF-8, missing selected column, or invalid selected i64 |
| 7 | Input exceeds 1,048,576 bytes |

## Ownership and bounds

Main sets process-wide SIGPIPE Ignore before allocation so a closed stdout
pipe can return EPIPE and run cleanup. It keeps the single argument-snapshot
owner and destroys it after every processing result. Snapshot construction
cleans up its own failures. CLI validation precedes input allocation and reads.

The input buffer owner stays outside all callbacks and the fold result and is
destroyed after every reserve, copy, validation, reduction, or output outcome.
Its bytes remain alive and unchanged while Text, Split, Filter, Map, and word
cursors borrow them. Predicate, mapper, folder, accumulator, and staging storage
are stack locals. Stdin/stdout remain borrowed descriptors and are not closed.

A valid invocation makes three heap allocation attempts: argument entries,
packed argument bytes, and the input reservation. Copy and processing add no
allocations. Input storage has a fixed logical bound; physical native layout
is checked through actual allocation/release lengths in tests. The input cap
also bounds row/word scanning and prevents the selection index from reaching
u64 overflow even for a huge requested column. There is no elapsed-time bound
on stdin/stdout host calls.

## Focused test and accepted evidence

[`tests/stdlib_column_sum_execution.rs`](../tests/stdlib_column_sum_execution.rs)
defines `column_sum_selection_checked_reduction_and_exact_cleanup`. It compiled
the real application once through the production stdlib root, passed the
unchanged shared strict ELF/jump checker through `common::TempArtifact`, and
reused that executable for all 58 native cases. Native runs have a five-second
timeout and one-second forced-termination grace.

The initial group, before both compiler repairs, passed in **6.21 s**, including
GPU compilation, native execution, and tracing. The combined Rust build of the iterator-selection and
application test drivers completed in **1.22 s**. Compiler checkpoint:
`28eee3362eb6cb7136618757da3bf2be7d8ecf84`, with the new uncommitted
`core::iter` selection/reduction sources. Compiler sources were unchanged.
The application body, test driver, and stdlib inputs were frozen during the
gate. After acceptance, only the application's header comment and this guide
were updated; executable code and the driver remained unchanged.

| Native cases | Count | Checked behavior |
| --- | --- | --- |
| Data selection and validation | 26 | Empty/comment rows, selected versus unselected text, ASCII separators, Unicode, i64 MIN/MAX, missing columns, malformed tokens, full-input UTF-8 validation, prefix overflow/underflow, and first-error ordering |
| Input boundaries | 3 | A UTF-8 sequence across a 1,024-byte read boundary, exactly 1,048,576 bytes, and excess input |
| CLI budget acceptance | 1 | Exactly 32 argument bytes with leading zeroes |
| Invalid CLI | 13 | Missing/extra arguments, zero, empty/signed/malformed/non-ASCII/overflowing column values, invalid raw bytes, and the byte cap |
| Allocation faults | 3 | Reached ENOMEM on argument entries, argument bytes, and input reservation, before any read |
| Read faults | 5 | Reached EIO at attempts 1/2, EAGAIN, invalid count 1025 for a 1024-byte request, and Interrupted retry |
| Write faults | 5 | Reached EIO, EAGAIN, zero progress, Interrupted retry, and a synthetic short write with resumed suffix |
| Real closed stdout | 1 | Actual EPIPE under SIGPIPE Ignore and complete allocation cleanup |
| Signal setup fault | 1 | Reached rt_sigaction EINTR before any allocation, input, or output |

The independent host model validates UTF-8, finds byte word boundaries, and
uses i128 selected-prefix sums. It checks each prefix against i64 bounds,
including overflow and underflow followed by mathematical cancellation back
into range. Selection errors and arithmetic errors check full stdout
suppression. Invalid UTF-8 in a later comment takes precedence over earlier
arithmetic failure, establishing whole-input validation before processing.
Read EIO after one successful input read checks that data is not published
before a successful EOF.

All three allocation-failure ordinals were reached before a read. Every
successful mapping was released exactly once at its actual address and
requested length, including prior owners on allocation failure. The ledger
rejects extra allocations, unknown/double/wrong releases, mremap growth, and
live owners at exit without assuming `View<u8>` width. Normal valid invocations
own exactly the two argument allocations and one input reservation; processing
adds none.

Read and write faults require reached injections and exact attempt counts.
The invalid read result is rejected before inspecting nonexistent transferred
bytes. A synthetic one-byte short-write result suppresses the first host
write, so the test expects the remaining stdout suffix exactly once. The
Interrupted cases retry and produce the complete expected CSV. The actual
closed pipe reaches EPIPE without injection. Every case checks status,
complete stdout, empty stderr, and SIGPIPE setup before allocations/input.

The actual combined Rust-driver build command was:

```sh
timeout --kill-after=2s 100s \
  flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s env \
  CARGO_TARGET_DIR=/home/andrew-peterson/code/laniusc/target/stdlib-build \
  CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  cargo test --test stdlib_iterator_selection_execution \
  --test stdlib_column_sum_execution --no-run \
  > target/stdlib-work/iterator-selection-admission/build-diagnostics-and-app.log 2>&1
```

The actual bounded application acceptance command was:

```sh
timeout --kill-after=2s 100s \
  flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s env \
  RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
  target/stdlib-build/debug/deps/stdlib_column_sum_execution-274b5fa8d5b0dcc1 \
  --exact column_sum_selection_checked_reduction_and_exact_cleanup --nocapture \
  > target/stdlib-work/iterator-selection-admission/application.log 2>&1
```

Both commands returned zero. The outer timeout is 100 seconds, lock acquisition
is bounded to 35 seconds, and the inner command is bounded to 60 seconds.
Acceptance used a 16 MiB Rust thread stack and a 45-second GPU codegen guard.
The binary filename is specific to this build and may change on a later build.

| Evidence | Time | Terminal log |
| --- | --- | --- |
| Initial diagnostics/application driver build | 1.22 s | [`build-diagnostics-and-app.log`](../target/stdlib-work/iterator-selection-admission/build-diagnostics-and-app.log) |
| Initial application group, before both compiler repairs | 6.21 s | [`application.log`](../target/stdlib-work/iterator-selection-admission/application.log) |
| Final Rust build of six selected test targets | 1.11 s | [`build-final-regressions.log`](../target/stdlib-work/iterator-selection-admission/build-final-regressions.log) |
| Final application recheck, after both compiler repairs | 6.63 s | [`application-final.log`](../target/stdlib-work/iterator-selection-admission/application-final.log) |

The final recheck passed the same exact test with one strict-checked ELF and
all 58 native cases. Its source state was checkpoint
`28eee3362eb6cb7136618757da3bf2be7d8ecf84` plus both
[shared iterator-result context repairs](compiler-iterator-assignment-context.md)
and the stdlib selection/reduction additions. The application body and test
driver were unchanged. It used the acceptance command and binary above with
output redirected to `application-final.log`. The 1.11-second build covered
six selected test targets and is not an isolated application-build timing.

The GPU compiler produced the ELF; the program executed natively on x86_64
Linux. Gate times include compilation and instrumentation. This evidence
establishes functional behavior for that target, without a throughput
measurement or execution inside user GPU kernels.
