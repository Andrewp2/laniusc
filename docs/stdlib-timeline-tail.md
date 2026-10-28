# Latest matching CSV timeline records

`sample_programs/library/timeline_tail.lani` reads a bounded timeline from stdin
and prints its newest matching records as CSV:

```sh
timeline-tail [--count N] [--level LEVEL] [--help]
printf 'level,message\nINFO,started\nWARN,retrying\nINFO,ready\n' | timeline-tail -n 1 -l INFO
```

The example prints:

```csv
"rank","level","message"
"1","INFO","ready"
```

## Schema and ordering

The first input record must contain exactly `level,message`, in that order and
case. CSV quoting around those field values is allowed. Every subsequent
record has exactly two fields. Level tokens match
`[A-Za-z][A-Za-z0-9_-]{0,31}`; messages are UTF-8 CSV fields and may be empty.
The CSV module handles escaped quotes, embedded line breaks and CRLF or LF
record endings. It rejects malformed quoting, invalid UTF-8 and unsupported
control bytes across all input, including records excluded by the filter.
ASCII control bytes other than quoted CR/LF, and DEL, are unsupported; this
includes TAB even inside a quoted field.

Input order determines chronology. The tool does not parse timestamps or sort:
it retains records in input order, reverses iteration, filters by optional
case-sensitive exact level, takes at most `N` matches, then enumerates them.
Default `N` is 10; valid counts are 0 through 4096. `--count 0` still validates
the entire input and prints only the output header. Missing matches also print
only that header. Duplicate options and positional operands are errors.

Output has `rank,level,message` fields. Ranks start at one for the newest match.
The CSV writer always quotes every field and uses CRLF. No matching record is
split on embedded commas or line breaks. The whole output is staged before
the first stdout write, so invalid later input cannot publish an earlier row.
An stdout error may still leave a confirmed output prefix.

## Iterator and ownership composition

The CSV table owns all decoded records. A separate vector retains `Entry`
values containing borrowed Text views into that table, in input order. The
selection is the actual generic composition:

```text
slice iterator -> rev -> filter -> take -> enumerate -> CSV writer
```

The source iterator, predicate and adapters have explicit lexical lifetimes;
they neither own nor destroy table rows. The table stays alive while output is
encoded. The reusable output record copies its fields before CSV emission.
The output buffer is independent and survives destruction of the table and
entry vector until stdout publication completes. There is no reversed copy of
the record collection and no handwritten backward index loop.

## Bounds and failures

| Resource | Bound |
| --- | ---: |
| Raw stdin bytes | 1048576 (1 MiB) |
| Data records / CSV records including header | 4096 / 4097 |
| Fields per input record | 2 |
| Level / message bytes | 32 / 8192 |
| Decoded bytes per input record | 8224 |
| Independent staged output bound | 2097152 (2 MiB) |
| stdin attempts / CSV staging write attempts / stdout attempts | 4096 / 8192 / 8192 |
| Captured arguments / total argument bytes | 16 / 1024 |

The decoded-record cap counts field content, excluding CSV separators, quoting
and line endings, so a full 32-byte level plus an 8192-byte message is allowed.
The raw input cap and staged output cap are separate explicit limits. An
excess-byte stdin probe distinguishes exact-cap EOF from oversized input.
Every I/O attempt, including EINTR, spends its corresponding call budget.
Blocking stdin/stdout have no wall-clock deadline.

| Exit | Meaning |
| ---: | --- |
| 0 | Canonical output or help written |
| 2 | Invalid CLI, schema, CSV, UTF-8, or a configured resource cap |
| 3 | stdin I/O failure or invalid transfer count |
| 4 | Reported allocation failure |
| 5 | stdout I/O failure or call cap |

SIGPIPE is ignored before I/O; failure to configure it exits with status 5.
Subsequent errors attempt the diagnostic `timeline-tail: operation failed`;
diagnostic failure preserves the primary status. Allocated input, output,
table, vector and record storage is explicitly released on returned paths.
This is an implementation contract, not a leak proof.

## Targets and verification

The intended executable target is Linux x86_64 through the GPU compiler's
native code emitter. No native C library, OpenSSL, JSON transport or Wasm
dependency is added. This does not claim GPU execution of stdin/stdout.

The GPU compiler emitted the native application successfully, and all focused
direct native groups passed on 2026-10-28: model 25 cases, rejection 24, CLI 20
and I/O 2. They include exact 1 MiB input, 4096 events, full 32-byte level plus
8192-byte message, ten seeded independent models, Unicode/CSV escaping, count
zero with full validation, no output on invalid later input, an actual stdin
directory read failure and a closed stdout reader. These are 71 finite cases.
The registered Rust driver separately compiled its own executable, passed the
shared strict ELF checker and passed all four tests using those same cases in
9.15 seconds. Cargo compilation took 1.72 seconds; receipt:
`target/stdlib-work/timeline-tail-rust-final.log`. The two runs cover the same
case set and are not added together as unique cases.

Executed source SHA-256:
`6579274d6f177f9fce0c6a1435d7f1a6ceaaa43f6e57716e55789a715aef6daf`.
Retained direct-run ELF (`target/stdlib-work/timeline-tail`) SHA-256:
`aca6fc83e962e950808a5c9abd8a08d3424cdde993c0cd07bdbd5df4556fb264`.
Final oracle SHA-256:
`233d98e206fc4231717d4ba24ba72e13d5af1243f845a9f8ba2341990889281c`.
Receipts under `target/stdlib-work/` are
`timeline-tail-compile-final.log` and
`timeline-tail-{model,rejection,cli,io}-native-final.log`.
The registered executable is produced separately; its binary hash is not
assumed to equal the retained direct-run executable above.

The initial model attempt stopped at its first seeded input because the
positive generator included TAB. The existing CSV dialect correctly rejected
it. The fixture now uses a space-containing positive message and adds an
explicit quoted-TAB rejection; all four groups pass with unchanged application
source. The Python model is test code only. It is not a formal proof,
allocation-failure campaign or resource checker. See
`tests/fixtures/stdlib_execution/timeline_tail/README.md` for group boundaries.

Independent review found one CLI mismatch: repeated help
was accepted despite the documented duplicate-option rule. The current source
rejects both `--help --help` and `-hh`, with two added CLI cases. The final
source's rebuild and complete four-group rerun passed all 71 cases above.
