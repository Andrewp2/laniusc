# format-report

[`sample_programs/library/format_report.lani`](../sample_programs/library/format_report.lani)
turns a bounded CSV item list into a formatted report. It parses and validates
every row before publication, then streams runtime formatting through seven
bytes of caller scratch into a 17-byte buffered writer. It does not allocate
a complete formatted report. All application behavior is Lanius.

Accepted on **2026-10-24** for x86_64 Linux native execution of an ELF built
through the GPU compiler. One strict ELF passed 81 native cases, including all
23 observed representative allocation denials. The application executes on the
CPU. This is functional acceptance; no throughput result is claimed.

## Input and invocation

There are no options or arguments. Extra arguments return status 2 before
allocation or stdin reads. With the compiler binary built, from the repository
root:

```sh
mkdir -p target/stdlib-work/format-report
target/stdlib-build/debug/laniusc --stdlib-root stdlib --source-root extended \
  --emit x86_64 sample_programs/library/format_report.lani \
  -o target/stdlib-work/format-report/format-report
printf 'name,quantity,unit_price\napple,2,1.25\n' \
  | target/stdlib-work/format-report/format-report
```

The first CSV record must have exactly the case-sensitive decoded fields
`name,quantity,unit_price`, with no surrounding spaces. Ordinary CSV quoting
is accepted. Empty input is invalid; header-only input is a valid empty report.
Data rows retain input order and have exactly three fields.

- Names contain 1–256 UTF-8 bytes. Empty names, ASCII controls (bytes 0–31),
  and DEL are rejected. Commas, quotes, spaces, and Unicode remain ordinary
  decoded name text. A quoted line break or TAB is therefore valid CSV but an
  invalid report name.
- Quantity spellings contain at most 128 bytes and use the existing strict
  signed decimal parser. The complete i64 range is accepted, including
  `-9223372036854775808` and `9223372036854775807`. Leading plus/minus and
  leading zeros are accepted. There is no trimming, decimal point, or exponent.
- Unit-price spellings contain at most 128 bytes and use the existing
  `core::float_decimal::parse_f64` grammar and correctly rounded binary64
  conversion. Decimal exponents and signed zero are accepted. NaN, infinity,
  and values that parse as infinity are rejected. There is no trimming.

The amount is `(quantity as f64) * unit_price` and must be finite. A quantity
outside binary64's exact integer range can round during this conversion; its
quantity column still prints the exact i64 value. Prices and amounts use
binary64 arithmetic and fixed-two decimal rounding, rather than decimal
accounting arithmetic. The program does not sum rows.

## Fixed output syntax

The header bytes are exactly:

```text
name\tquantity\tunit_price\tamount\n
```

Each data row uses this fixed runtime format pattern:

```text
{0:<16s}\t{1:>20d}\t{2:>12.2f}\t{3:>12.2f}\n
```

Here `\t` and `\n` describe TAB and LF bytes. Names are left aligned to a minimum
width of 16 Unicode scalars, with spaces added on the right. Quantity, unit
price, and amount are right aligned to minimum widths 20, 12, and 12. Longer
fields expand without truncation. Width counts Unicode
scalars rather than terminal display cells or UTF-8 bytes. Prices and amounts
have exactly two fractional decimal digits, including signed zero where its
binary64 sign is retained. Each row ends in LF.

The footer is exactly `rows=N\n`, where N is the data-row count without padding.
Header-only input therefore produces the 32-byte header and `rows=0\n`.
The output is a padded TAB-separated report; it is not a CSV re-encoding.
Names cannot contain TAB or LF, so field and row boundaries remain explicit.

## Bounds and preflight

| Resource | Bound |
| --- | ---: |
| Input bytes, including header and CSV punctuation | 1,048,576 |
| Data rows | 256 |
| CSV fields per record | 3 |
| Decoded CSV bytes per field / record | 256 / 768 |
| Numeric spelling bytes | 128 |
| Float significant-digit budget / work budget per parse | 128 / 1,000,000 |
| Formatted row bytes | 1,024 |
| Format work per measure or streaming call | 16,777,216 |
| Complete report bytes, including header and footer | 65,536 |
| Direct buffered-writer calls per formatting call | 4,096 |
| Explicit finish attempts | 64 |

The input owner reserves the full byte bound once and uses the existing
1,024-byte stream-copy adapter. Success requires actual EOF, including at the
exact input bound. This copy can read a full additional 1,024-byte chunk before
the bounded Buffer rejects it; it does **not** use a one-byte limit probe.
Those excess bytes are not appended. Interrupted reads retry; host I/O has no
elapsed-time bound.

The real `ext::csv::Table` owns decoded fields. CSV parsing validates UTF-8 and
record structure. A typed Vec retains borrowed name Text plus parsed quantity,
price, and amount. Every row is measured with the same fixed pattern and
format limits used for publication. The program checks the sum of the header,
footer, and all row lengths before output, rejecting a 65,537-byte report.
Input, CSV, numeric, name, arithmetic, and preflight-limit errors publish no
bytes. All heap owners, including the writer's fixed buffer, are allocated
before publication. Work is bounded per operation and row count; these logical
budgets do not impose an elapsed-time or exact total-memory limit.

## Streaming output, failures, and cleanup

`core::format::write<alloc::buffered::Writer<std::stream::Descriptor>>` formats
the header, each row, and footer using caller-owned packed scratch with length
seven. Even a short data row is larger than scratch. The buffered writer owns
17 initialized bytes and batches scratch emissions into host writes of at most
17 bytes. No allocation occurs after the first stdout attempt.

The formatting call budget counts direct calls to the borrowed **buffered
writer**. It does not count every nested host syscall. A buffered drain may
make multiple host calls; positive progress is bounded by the bytes remaining
in its fixed 17-byte pending range. Generic formatting cannot bound arbitrary
writer internals. Interrupted formatting writes retry within that direct-call
budget.

Formatter `WriteFailure.completed` counts bytes accepted by that buffered
layer. Some may still be pending, so it is not a count of stdout bytes. On a
formatting failure the application stops, discards pending output, and releases
the writer buffer. It does not retry a formatted row or replay an accepted
prefix. Validation normally prevents later format errors; host failures or an
I/O-call limit can still occur after publication begins.

After every formatting call succeeds, main explicitly finishes the writer.
Interrupted finish errors retry up to 64 attempts; other finish errors stop
immediately. Exhausting that attempt budget returns status 7. A failed finish
retains pending bytes, which the app explicitly discards. Successful finish
releases the writer buffer. Either path then destroys typed rows before the
CSV table and releases the input owner. A later output failure may leave any
confirmed host prefix, including a partial header, row, or footer.

Stdin and stdout remain borrowed descriptors. Main installs process-wide
SIGPIPE Ignore before allocation so a closed stdout pipe reports EPIPE and
reaches cleanup. Stderr is unused. Finishing drains library buffering; the
application does not close descriptors or promise durable storage.

See the [streaming format guide](stdlib-format-write.md),
[format-string guide](stdlib-format-strings.md),
[buffered I/O guide](stdlib-buffered.md),
[CSV guide](extended-csv.md), and
[floating-point formatting guide](stdlib-formatting.md) for the library
contracts.

| Status | Meaning |
| --- | --- |
| 0 | Complete report and successful writer finish |
| 2 | Arguments, CSV/schema, name, integer, or price invalid |
| 3 | Signal setup, input, output, or finish I/O failure |
| 4 | Input, CSV, typed row, or buffered-writer allocation failure |
| 5 | Derived binary64 amount is nonfinite |
| 7 | Input/CSV/numeric/format/output limit, formatter I/O budget, or finish-attempt budget |

A fourth CSV field exceeds the configured three-field parser cap and therefore
returns 7. Missing or inconsistent fields return 2. Resource or allocation
errors detected before publication leave stdout empty; a publication-time
status 3 or 7 may leave a prefix.

## Focused driver and accepted evidence

[`tests/stdlib_format_report_execution.rs`](../tests/stdlib_format_report_execution.rs)
defines `format_report_csv_preflight_streaming_and_exact_failure_cleanup`. It
compiled the production application once with the real stdlib and extended
roots, passed the unchanged shared strict ELF/jump checker, and reused that
executable for every native case. Each process has a five-second
timeout and one-second forced-termination grace.

The independent host model creates CSV from known rows with ordinary doubled
quote escaping, parses numeric spellings with Rust's integer/float parsers,
computes binary64 amounts, and formats complete expected reports with Rust's
formatting implementation. It checks exact bytes, including Unicode scalar
padding, signed zero, decimal ties, large fixed float output, and the footer.
Invalid cases use explicit expected statuses and require no publication.

The fixed cases are:

| Cases | Count |
| --- | ---: |
| Empty report, full i64 extrema, signs/zeros, quoting/Unicode, float rounding/extrema, field bounds | 9 |
| Compact three-row representative baseline | 1 |
| Malformed CSV/UTF-8/schema/names/numbers and late invalid row | 20 |
| Field/numeric/row limits | 4 |
| Exact/exceeded input byte bound | 2 |
| Separate 256-row correctness case and exact/exceeded output byte bound | 3 |
| Read faults and retry | 5 |
| Drain/final-finish write faults, invalid/zero progress, retry, short write | 9 |
| Repeated Interrupted reaches formatter and finish budgets | 2 |
| Real EPIPE, signal failure, unexpected arguments | 3 |
| Total fixed native processes | 58 |

The representative recorded 23 allocation positions. The driver then denied
each position independently with reached ENOMEM, requiring status 4, empty
stdout, and exact cleanup. Those denials plus 58 fixed cases gave 81 native
processes; the 256-row workload was correctness-only. The driver printed both
counts after every case passed.

The allocation ledger matches each generation/address/requested-length tuple
with one exact release, tolerates address reuse after release, and rejects
leaks, double or wrong-length releases, and mremap. It assumes no physical Text
or row width. Publication must observe EOF first, use host requests no larger
than 17 bytes, and make no allocation after the first stdout attempt.

Fault cases distinguish draining a full buffer from flushing the final partial
buffer. They check confirmed host prefixes, retries, and explicit discard.
The synthetic one-byte short write suppresses the first host syscall while
reporting one byte, so the test expects the real remaining suffix once, with a
16-byte resumed drain. The closed-pipe case uses real EPIPE. Signal setup
failure must precede allocations and reads; extra arguments must not allocate
or read stdin.

The accepted source base was `0b03990bfd7b658f0c419cf4ec2c32477ccb186e` plus
the new `core::format` writer implementation. No compiler changes were needed.
The application body and driver stayed frozen after the gate; only this guide
and the application's admission comment were updated.

| Evidence | Accepted result |
| --- | --- |
| Fresh Rust application-driver build | 1.21 s |
| Application gate | One strict ELF, 81 native cases, one Rust test passed in 9.19 s |
| Representative allocation faults | All 23 observed positions independently denied and exactly cleaned up |
| Separate cases | 256-row correctness and exact 65,536-byte output boundary plus one-byte excess rejection |
| Build log | `target/stdlib-work/format-write-admission/build-report.log` |
| Runtime log | `target/stdlib-work/format-write-admission/report.log` |

The log paths are ignored local artifacts. From the repository root, the exact
accepted serialized runtime command was:

```sh
RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
  timeout --kill-after=2s 100s \
  flock -E75 -w35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s \
  target/stdlib-build/debug/deps/stdlib_format_report_execution-9b141589addc73ad \
  format_report_csv_preflight_streaming_and_exact_failure_cleanup \
  --exact --nocapture --test-threads=1 \
  > target/stdlib-work/format-write-admission/report.log 2>&1
```

This evidence covers the tested x86_64 Linux target and stated fault model.
Allocation denials verify reached attempts and explicit owner cleanup;
synthetic write results are checked against the bytes the host actually
received, as described above.
