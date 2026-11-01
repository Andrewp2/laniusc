# Compare ordered integer series

`sample_programs/library/compare_series.lani` compares two signed-integer
series supplied in one CSV stream. It reports equality, lexicographic order
and whether each series is already sorted, preserving each side's input order.
The implementation has passed 119 native cases. The standalone build and
both exact examples below have also passed separately from the registered
runtime tests.

## Build and use

With the compiler binary built, run from the repository root:

```sh
mkdir -p target/stdlib-work
timeout --kill-after=2s 100s flock -w 95 target/stdlib-work/library-gpu.lock \
  target/stdlib-build/debug/laniusc --stdlib-root stdlib --source-root extended \
  --emit x86_64 sample_programs/library/compare_series.lani \
  -o target/stdlib-work/compare_series
printf 'side,value\nleft,1\nright,1\nleft,2\nright,3\nleft,2\n' | \
  target/stdlib-work/compare_series
```

Expected output, with CRLF after both rows:

```csv
"left_count","right_count","equal","order","left_sorted","right_sorted"
"3","2","false","less","true","true"
```

Descending order changes element comparisons. A shorter equal prefix still
compares less:

```sh
printf 'side,value\nleft,9\nright,9\nright,1\n' | \
  target/stdlib-work/compare_series --descending
```

Expected output:

```csv
"left_count","right_count","equal","order","left_sorted","right_sorted"
"1","2","false","less","true","true"
```

Both example pipelines exited 0 and matched their literal 111-byte CRLF
reports. Their separate build and output receipts are recorded below.

## CLI and input

`compare_series [--descending] [--help]` accepts `-r` and `-h` aliases.
There are no operands. Duplicate flags, including repeated aliases or short
group members, fail. The existing `ext::cli` parser accepts short groups,
exact long names and a `--` terminator; an operand after that terminator still
fails. Help accepts otherwise valid flags and bypasses stdin. It does not
waive invalid CLI. Argument capture permits eight entries and 1024 total
bytes. Only scalar options survive argument-owner cleanup.

The first CSV record must be exactly `side,value`, in that order and case.
Every data record contains exactly two fields:

- `side` is exactly `left` or `right`.
- `value` is a signed i64 in 1..64 decoded ASCII decimal bytes. The existing
  decimal parser permits an optional `+` or `-` and leading zeros, with exact
  i64 range checks. Whitespace, prefixes and non-ASCII digits fail.

No field is trimmed; no BOM removal or case conversion occurs. Numeric
spellings compare by value, so `+000`, `-0` and `0` are equal. Interleaved
rows append to the selected side without changing either side's order.
Empty stdin is invalid. A header-only stream describes two empty series.

The canonical strict CSV decoder accepts ordinary quoting, LF/CRLF and a
final unterminated record. Quoted CR/LF remains data and fails the side or
decimal grammar. Invalid UTF-8, NUL, TAB, prohibited ASCII controls and DEL
fail CSV validation. Blank records and missing/extra fields fail. Field and
record limits count decoded field bytes, excluding commas, quotes and record
terminators.

## Comparison and output

All input must reach actual EOF and pass CSV validation before comparison.
Both sides are ordinary `Vec<i64>` owners. Each public consumer receives fresh
independent slice cursors over those live values:

| Mode | Equality | Lexicographic order | Per-side sortedness |
| --- | --- | --- | --- |
| Natural | `core::iter::eq` | `core::iter::cmp` | `core::iter::is_sorted` |
| Descending | `core::iter::eq` | `core::iter::cmp_by` | `core::iter::is_sorted_by` |

The descending comparator reverses only unequal numeric elements. It uses
comparisons rather than negation, so i64::MIN is ordinary input. Its separate
bool pair mappers accept `previous >= current`. Equal adjacent values are
sorted in both modes. Empty and singleton series are sorted. Equality is
independent of the selected ordering.

Lexicographic order uses the first unequal corresponding pair. If all common
elements agree, the shorter series is less in both modes. The application
does not invert the final natural result, sort either side, or implement a
private sequence comparison loop. New iterator cursors prevent one consumer's
short circuit or exhaustion from changing another result.

Output is exactly two fully quoted CRLF CSV rows. The header is
`left_count,right_count,equal,order,left_sorted,right_sorted`; counts use
canonical unsigned decimal, booleans are `true`/`false`, and order is
`less`/`equal`/`greater`. Every valid report exits 0, including unequal or
unsorted inputs. There is no difference-status exit code.

## Bounds and ownership

| Resource | Bound |
| --- | ---: |
| Collected stdin | 1048576 bytes |
| Actual Read calls, including Interrupted and EOF | 8192 total |
| Data records across both sides combined | 65536 |
| CSV records including header | 65537 |
| Fields per CSV record | Exactly 2 |
| Decoded bytes per field / record | 64 / 128 |
| Caller-backed report capacity | 512 bytes |
| Private CSV writer calls | 16 total |
| Data / help stdout attempts | 64 each |
| Diagnostic stderr attempts | At most 8 |

Public `alloc::io::read_to_end` collects the entire source before parsing.
Its exact-cap one-byte EOF probe counts as a Read call; confirmed excess
input rejects the stream. On failure, the retained prefix owner is destroyed.
Input I/O, storage or byte/call errors therefore precede malformed CSV in an
incomplete source. The call budget imposes no wall-clock timeout on blocking
I/O.

The decoder reuses its field/byte storage. Each ready record contributes only
one copied i64 to the selected Vec before the decoder invalidates its fields.
The combined record cap is checked before push. Vec capacity grows through
ordinary checked `try_push`; there is no allocation for an empty side. The
bounded row count bounds comparison and sortedness work linearly; the general
iterator consumers themselves impose no quota on arbitrary infinite sources.

The decoder and complete raw input retire after parsing. Both value owners
remain live through every shared consumer, then retire before rendering. Only
the scalar counts, booleans and Ordering escape that phase. Canonical CSV
writing reuses one Record and stages both rows through a public SliceWriter
over the caller's 512-byte array. The header is 73 bytes and a conservative
maximum data row is 51 bytes, so the complete admitted report is at most 124
bytes. Rendering destroys its CSV allocations before returning the byte count.
All owned allocations, including argv, are gone before the first stdout call.

Every failure explicitly releases acquired owners before its diagnostic.
Standard descriptors remain borrowed and are never closed. Publication retries
only Interrupted, spends one attempt before each delegation and advances only
on confirmed positive counts. Zero, invalid counts, other errors or quota
exhaustion stop without replay. A publication failure may leave a confirmed
prefix of the complete staged report; there is no atomic-output or rollback
claim.

## Status and acceptance

| Exit | Meaning |
| ---: | --- |
| 0 | Any complete report, or help written |
| 2 | Invalid CLI/CSV/numbers or input/record/storage/staging limit |
| 3 | Input I/O or argument-capture host failure |
| 4 | Argument, input, decoder, value Vec or CSV allocation failure |
| 5 | Data/help output or SIGPIPE-policy failure |
| 6 | Unexpected storage/provider/formatting contract failure |

SIGPIPE is ignored before argument capture; setup failure returns 5 silently.
Other failures preserve their primary status and attempt the exact 33-byte
line `compare_series: operation failed\n` after cleanup. Diagnostic failure
does not replace that status. Help is exactly 723 bytes; successful runs have
empty stderr.

All **119 distinct cases** passed on native Linux x86_64 CPU output from the
GPU compiler. Acceptance spans two commands:

| Receipt in `target/stdlib-work/` | Accepted scope | Runtime | Registered result |
| --- | --- | ---: | --- |
| `iterator-comparison-compare-series-functional-retry.log` | Model: 44 cases | 10.63 s | 1 passed, 3 filtered |
| `iterator-comparison-compare-series-remaining-retry.log` | Rejection 35, CLI 19, I/O 21: 75 cases | 9.63 s | 3 passed, 1 filtered |

Evidence directories are `/tmp/compare-series-model-wvhscz01`,
`/tmp/compare-series-rejection-7w1tq5ms`, `/tmp/compare-series-cli-9lun6vt6`
and `/tmp/compare-series-io-w047__5c`. The independent oracle uses list
equality, tuple ordering and adjacency predicates. Descending expectations
negate individual arbitrary-precision Python integers, preserving the prefix
rule and admitting i64::MIN. The native cases cover both directions, unequal
prefixes, equal-but-unsorted series, full-width integers, interleaving, CSV
boundaries, 65536 combined values and valid exact 1 MiB input. Separate traced
cap controls establish actual one-byte EOF and confirmed excess-byte reads.

Seven selected, reached allocation failures cover both argv mappings, initial
input, initial left/right storage, later right-side growth and late CSV report
storage. Each returns 4 with empty stdout and matching explicit releases of
observed successful mappings. Baseline and selected full traces require no
live heap owner at any data/help/diagnostic write. These are finite observed
cleanup cases, not every allocation site or an ownership proof.

Actual directory stdin and closed data/help stdout exercise input errors and
EPIPE. Read/write interruptions retry to the exact report. Later input and
required-EOF EIO publish nothing, and incomplete-source failure precedes CSV
validation. A regular-file output test with `RLIMIT_FSIZE=10` and an explicitly
inherited ignored SIGXFSZ produces a genuine ten-byte prefix, then returns 5.
The app sets only SIGPIPE policy; without that inherited SIGXFSZ policy,
default signal termination would not establish this status/cleanup behavior.
That prefix case is untraced; a separate host probe establishes EFBIG, while
the selected traced output-error cases establish cleanup. No positive transfer
count is fabricated. Compact summaries separately establish 8192 interrupted
input attempts and 64 interrupted output attempts plus a diagnostic; they do
not supply full release ledgers.

Accepted producer identities (SHA-256):

- Application: `c143a686830b29af516717440a0e162e7542c1d7655562e2fa7d8d43252fc52c`.
- Oracle: `78518fe0f3b7d1c45a0a69dfdb7fd802d809cf91cd34df234f854c7f395b9f44`.
- `core::iter`: `0efff466fc31a96918d9cd55ad69d4073586803608b35bc1d5a7d743a4ba6211`.

The initial producer
`e3ae644e0918d090b57d0154f64f21183c72edf4e43b5a14299edddc2f63b59f`
stopped all four tests before ELF execution in 5.18 seconds, with LNC0021 at
its Comparator signature. It is retained under
`target/stdlib-work/iterator-comparison-app-initial-failure`. The
callback-qualified revision
`7f6fcd92657a3bb5ae7f08300244ce6010af06a036a2573bd6b51cdfc4b783f5`
also stopped all four tests before native execution in 5.48 seconds, with
LNC0005 at `Ordering::Greater`
(`iterator-comparison-compare-series-qualified-retry.log`). Imported modules
declare multiple Ordering names. Fully qualifying every core Ordering
type/variant and Pair callback boundary resolved this import surface; the
accepted current producer above preserves the original semantics and limits.
These earlier receipts do not establish a general alias-support limitation.

Static literal byte-count and final-newline checks pass. The
[fixture guide](../tests/fixtures/stdlib_foundation/compare_series/README.md)
records independent controls and exact finite profiles. The exact standalone
compile above exited 0 with a silent compiler
(`target/stdlib-work/iterator-comparison-compare-series-build-command.log`).
Both documented pipelines exited 0 and matched their literal 111-byte CRLF
reports in `target/stdlib-work/iterator-comparison-compare-series-example-natural.csv`
and `target/stdlib-work/iterator-comparison-compare-series-example-descending.csv`.
These examples overlap the functional corpus and add no distinct case count.
Rust driver formatting followed runtime acceptance without changing production
or oracle behavior.

Argument-host failure, internal-error injection, arbitrary broken providers,
user-program GPU execution, other targets, automatic ownership/lifetime
enforcement, alias safety, exhaustive failures, leak freedom and formal
verification require separate evidence. Production is entirely Lanius and
adds no compiler, ABI or host service changes.
