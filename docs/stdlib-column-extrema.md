# Numeric column extrema report

[`sample_programs/library/column_extrema.lani`](../sample_programs/library/column_extrema.lani)
is a small stdin report built from bounded I/O, UTF-8 Text, iterator lookahead
and minimum/maximum reductions. Its focused group passes through GPU
compilation and native Linux x86_64 CPU execution in **6.51 seconds**:
`target/stdlib-work/column-extrema-injection-parser-corrected.log`.

```text
column-extrema COLUMN
```

`COLUMN` is exactly one unsigned decimal argument, from **1 through 4096**.
It is one-based. Argument capture is bounded to one argument and 32 bytes.
The sample reads stdin, writes one CSV report to stdout, and does not write
diagnostic text to stderr.

## Input and report

The complete input must be valid UTF-8, including comments and unselected
columns. Input is split on LF. ASCII-blank lines are skipped, as are lines
whose first byte after ASCII trimming is `#`. CRLF works through that trimming.
Fields are separated by ASCII whitespace. This is a whitespace table reader,
not a quoted CSV parser.

Each data line must contain the selected column as a complete decimal `i64`
token under `core::decimal`'s checked parser: ASCII digits with an optional
leading `+` or `-`, without separators or trailing bytes. Other columns remain
uninterpreted UTF-8 text. Missing columns, malformed tokens and overflow reject the report.
Every selected value and its original physical one-based line number is staged
before publication. Comments and blank lines still count toward physical row
numbers.

The header and one result row are:

```csv
count,min,max,min_row,max_row
4,-5,8,4,5
```

Minimum chooses the first tied input row; maximum chooses the last. The
example could come from two `8` rows on physical lines 2 and 5, and two `-5`
rows on lines 4 and 6. An empty dataset reports:

```csv
count,min,max,min_row,max_row
0,,,,
```

## Bounds and cleanup

| Resource | Explicit bound |
| --- | --- |
| Input | 65,536 bytes |
| Data rows | 4,096 |
| Selected column | 1..4096 |
| Output staging | 128 packed stack bytes |

The input buffer reserves its full bound once. The existing bounded copy
helper accepts exact-cap input only after observing EOF; any extra input
rejects it. After UTF-8 validation, one numeric vector reserves all 4,096 rows.
Lookahead over lines and fields performs no allocation. Borrowed min/max
reductions select original staged records without cloning or destroying them.

Every parse, cap, allocation and I/O return path releases its actual numeric
vector, input buffer and argument owners as applicable. The entire report is
validated and formatted before the first output byte. An output failure can
leave a written prefix; there is no atomic stdout guarantee. Existing
`write_all` retries Interrupted and short writes. SIGPIPE is explicitly ignored
so a closed output pipe is an I/O error. Byte and row limits do not impose an
I/O deadline on a blocking stdin or stdout.

| Exit | Meaning |
| --- | --- |
| 0 | Report written |
| 2 | Argument count, decimal form, length or column range |
| 3 | Input/output failure or signal-policy setup failure |
| 4 | Allocation failure |
| 6 | Invalid UTF-8, missing column or invalid/overflowing selected integer |
| 7 | Input byte or data-row cap |

## Focused execution evidence

The accepted sample group executes 24 process cases: 16 input/argument/limit
cases, `/dev/full`, a traced baseline, all four reached allocation-failure
positions, Interrupted output and a synthetic short write.

The native driver covers Unicode unselected fields, comments/blank lines and
physical tie rows; both signed `i64` extremes; empty/comment-only input;
argument errors; invalid UTF-8 in a comment; missing/invalid/overflowing fields;
exact and exceeded byte/row caps; `/dev/full`; every reached allocation failure;
Interrupted output and synthetic short-write offset handling. The latter
strace injection returns a count without emitting those bytes, so its oracle
checks the remaining suffix rather than claiming those synthetic bytes were
written. Both write fault cases require exactly one actual `(INJECTED)` stdout
write with the requested error/result and a correctly sized successful retry.
Mapping ledgers confirmed all successful allocations were released, including
the exact allocation prefix at each of the four reached OOM positions.

The first complete iterator run passed its four library groups but failed the
sample's short-write harness assertion in 15.67 seconds
(`target/stdlib-work/iterator-lookahead-first.log`): the strace selection omitted
`write`, so its injection was not reached. An app-only rerun then failed the
new trace-count parser on `(INJECTED)` in 5.72 seconds
(`target/stdlib-work/column-extrema-write-faults-corrected.log`). Correcting that
parser produced the passing 6.51-second app receipt above. The production
iterator and sample source remained unchanged; the accepted library and app
evidence comes from separate runs.

These are bounded sample acceptance cases. They do not establish other targets,
unbounded streams or user-program GPU execution. See the
[lookahead and reduction contract](stdlib-iterator-lookahead.md).
