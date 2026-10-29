# Iterator series comparison application fixture

CLI is `compare_series [--descending/-r] [--help/-h]`, with no operands or
duplicate flags. Help validates all supplied flags and bypasses stdin.
Captured argv is bounded to eight arguments and 1024 bytes.

Input is canonical CSV headed exactly `side,value`. Each data record has side
`left` or `right` and a strict signed i64 decimal value: optional sign, leading
zeros, 1..64 decoded bytes and no trimming. Relative input order within each
side is preserved, including interleaved rows. Quoting, LF/CRLF and final
unterminated CSV follow the existing dialect. Empty input is invalid; a
header alone describes two empty series. Bounds are 1 MiB input, 8192 actual
Read attempts, 65536 combined data records, 64 decoded bytes per field and
128 per record. The public owned reader requires actual EOF/cap probing.

Output is exactly two fully quoted CRLF CSV rows with columns
`left_count,right_count,equal,order,left_sorted,right_sorted`. Counts are
decimal, booleans `true`/`false`, and ordering `less`/`equal`/`greater`.
Valid unequal or unsorted inputs still return 0. Invalid data/CLI/limits
return 2, input/argv host failure 3, allocation failure 4, output/signal failure
5 and unexpected internal contracts 6. All prepublication failures have empty
stdout. Data/help output has 64 attempts, diagnostics eight.

## Independent model

Expected equality is Python list equality; lexicographic comparison is tuple
ordering. Descending transforms each element using arbitrary-precision integer
negation before tuple comparison, so i64::MIN remains representable and the
structural shorter-prefix rule remains unchanged. This is not negation of the
entire ascending comparison. Sortedness uses the independent adjacency
predicate `all(a <= b)` or `all(a >= b)`, including duplicate plateaus.

The oracle neither runs nor sorts a copy of the production iterator. Model
cases use fresh mathematical lists; equality, comparison and sortedness are
checked together so a reused/exhausted production cursor cannot hide an
unsorted equal input. CPU controls cross-check 3200 tiny-alphabet/direction
combinations against a separate first-difference/length specification, with
literal empty/prefix/full-width anchors. The native corpus is deliberately
finite rather than that whole Cartesian process set.

| Group | Cases | Scope |
| --- | ---: | --- |
| model | 44 | Both directions, empty/equal/prefix/early/late differences, full signed width, duplicate/inversion/plateau sortedness, interleaving, quoting and final records, 64-byte signed cells, maximum combined count and exact input bytes |
| rejection | 35 | Header/side/width/quoting/encoding/controls, integer syntax/range/token bytes, invalid late data after a decisive prefix, combined row limit and consumed excess cap probe |
| cli | 19 | Aliases/clusters, operands/unknown flags/duplicate flags, snapshot entry/byte caps and validated help without stdin |
| io | 21 | Baseline, seven selected reached ENOMEM sites, real input/output failures, EINTR, EOF/error precedence, genuine short publication prefix, signal failure and attempt limits |

The valid exact-cap input has an 11-byte header, 65534 sixteen-byte left-zero
rows and one seven-byte/one fourteen-byte row: exactly 1048576 bytes and
65536 values. Its complete expected report is small. The exact-cap trace must
observe a one-byte EOF request; the oversized trace consumes one confirmed
extra byte and rejects. This keeps row and byte bounds independently visible.

## Ownership and selected faults

The production app uses fresh public slice cursors over two Vec<i64> owners.
Raw input and the CSV decoder retire after parsing, then values retire after
the consumers. Canonical CSV writing stages the report in a caller-backed
512-byte SliceWriter. Its reusable CSV Record still owns byte/field working
storage; those owners retire before stdout. No heap owner remains at any
data/help/diagnostic write. The test ledger requires this empty live set,
matches every successful mmap to exact address/requested-length munmap and
allows address reuse only after release. It rejects borrowed descriptor closes
and other allocation services. This is finite observed cleanup, not an
automatic lifetime or exhaustive leak-freedom guarantee.

Seven selected mmap failures cover both argv mappings, initial input, initial
left/right storage, a later right-side growth and late CSV report storage.
They must be reached at baseline ordinals/arguments, return 4, release all
obtained mappings and publish nothing. They do not cover every allocation.
Real directory stdin and closed data/help stdout exercise EISDIR/EPIPE.
Read/write EINTR retries to the exact report. EIO on a later read or required
EOF publishes nothing; an incomplete input host failure precedes malformed
schema. SIGPIPE policy failure is silent before argv capture.

The ordinary report is at most 124 bytes. A selected regular-stdout file
uses `RLIMIT_FSIZE=10` **and an explicitly inherited ignored SIGXFSZ**. That
test environment permits a genuine ten-byte prefix followed by status 5;
the app itself sets only SIGPIPE policy. Without that inherited SIGXFSZ policy,
termination by the default file-size signal would not establish status-5
cleanup. A separate host Python probe confirms a real ten-byte write then
EFBIG. The native prefix case is untraced; selected full output-error traces
provide the cleanup ledger separately. No successful transfer count is
fabricated and no extra app segmentation is introduced for testing.

Compact summaries separately require 8192 interrupted input calls returning 2
or 64 interrupted writes plus one diagnostic returning 5. They establish
attempt counts, not a full allocation ledger. Both injection ranges fit the
local strace finite schedule limit. Argument-host status 3 and internal
contract injection are not covered by this corpus.

The driver compiles once per libtest process, admits only actual little-endian
ELF64 x86-64 output and uses the shared strict jump gate. The standalone oracle
also rejects non-ELF files. Child processes have 15-second deadlines and each
registered group 85 seconds. Exact command/input/output/status and selected
traces are retained. Root alone runs compiler/Cargo/native commands.

```sh
python3 -B tests/fixtures/stdlib_foundation/compare_series/oracle.py controls
python3 -B tests/fixtures/stdlib_foundation/compare_series/oracle.py model PATH_TO_ELF
python3 -B tests/fixtures/stdlib_foundation/compare_series/oracle.py rejection PATH_TO_ELF
python3 -B tests/fixtures/stdlib_foundation/compare_series/oracle.py cli PATH_TO_ELF
python3 -B tests/fixtures/stdlib_foundation/compare_series/oracle.py io PATH_TO_ELF
```

## Acceptance

Bounded CPU controls pass for literal outputs, descending prefix/full-width
ordering, 3200 model cross-checks, cap input parsing, malformed reference inputs,
corpus counts, exact literal lengths and deliberately premature publication.
All **119 distinct native Linux x86_64 cases are accepted** across two
registered commands on the qualified source. The model passed one test in
10.63 seconds with three filtered; the remaining groups passed three tests
in 9.63 seconds with the functional selector filtered. Neither accepted
receipt has a failure. These are separate commands, not a combined four-test
all-pass run. The GPU compiler produced strict-admitted ELF64 programs and
execution was on the CPU.

| Group | Cases | Receipt in `target/stdlib-work/` | Evidence |
| --- | ---: | --- | --- |
| model | 44 | `iterator-comparison-compare-series-functional-retry.log` | `/tmp/compare-series-model-wvhscz01` |
| rejection | 35 | `iterator-comparison-compare-series-remaining-retry.log` | `/tmp/compare-series-rejection-7w1tq5ms` |
| cli | 19 | `iterator-comparison-compare-series-remaining-retry.log` | `/tmp/compare-series-cli-9lun6vt6` |
| io | 21 | `iterator-comparison-compare-series-remaining-retry.log` | `/tmp/compare-series-io-w047__5c` |

Accepted identities (SHA-256):

- Application: `c143a686830b29af516717440a0e162e7542c1d7655562e2fa7d8d43252fc52c`.
- Oracle, unchanged throughout admission: `78518fe0f3b7d1c45a0a69dfdb7fd802d809cf91cd34df234f854c7f395b9f44`.
- `core::iter`: `0efff466fc31a96918d9cd55ad69d4073586803608b35bc1d5a7d743a4ba6211`.

Two earlier full-target attempts failed before ELF/native launch. The first
reported `LNC0021` at the callback trait's imported Ordering signature:
zero passed/four failed in 5.18 seconds,
`iterator-comparison-compare-series-first.log`, source
`e3ae644e0918d090b57d0154f64f21183c72edf4e43b5a14299edddc2f63b59f`.
Qualifying callback boundaries produced source
`7f6fcd92657a3bb5ae7f08300244ce6010af06a036a2573bd6b51cdfc4b783f5`,
which then reported `LNC0005` for an ambiguous imported Ordering variant:
zero passed/four failed in 5.48 seconds,
`iterator-comparison-compare-series-qualified-retry.log`. Qualifying every
core Ordering type/variant resolved those app admission blockers. The CLI,
limits, help, output contract, oracle and driver expectations did not change.
These failures supply no native behavior evidence and do not establish a
compiler repair or general alias-resolution guarantee.

The inspected baseline retires 40-byte/12-byte argv mappings before collection,
reads 1253 bytes and EOF, then parses 64 values per side. Both final 512-byte
value mappings retire before CSV report allocations. Its 84-byte/128-byte CSV
working owners retire before the one actual 117-byte stdout write. All traced
publication and diagnostic events have an empty live mapping set.

Seven selected ENOMEM sites reached ordinals 1/2/3/10/11/19/25: argv, initial
input, first left/right mappings, later right-side 512-byte growth and final
84-byte report storage. Each returns 4 with empty stdout and matching explicit
releases. The later right-side failure retires the existing left mapping and
right prefix; report-storage failure retires its partial Record owners after
the sequences were already released. This is selected fault coverage, not all
allocations.

The real file-size case inherits ignored SIGXFSZ explicitly, retains the exact
ten-byte prefix `"left_coun` and returns 5. It is untraced and provides neither
an errno nor a release ledger; the separate host probe established EFBIG, and
selected full output-error traces establish cleanup. Actual directory stdin
and closed data/help stdout exercise EISDIR/EPIPE. Read/write EINTR preserve
the report. Later-read/required-EOF EIO returns 3 with empty output; even bad
schema waits for the owned reader's EOF before validation. Silent signal
failure and the compact 8192-read/64-write attempt bounds also passed.

The exact-cap model trace observes a real one-byte EOF; its valid 1 MiB input
contains all 65536 data records. The oversized trace consumes one extra byte
and rejects. Descending prefix cases, full signed extrema, independent
sortedness and the 723-byte help are included in these accepted groups.
Standalone build/example commands are separate from this integration driver.
Driver hashes are omitted because root may format Rust drivers after runtime
acceptance; no broad rerun is claimed.

User GPU execution, other targets, argument-host failure, arbitrary broken
providers, internal-error injection, formal verification, automatic ownership/
lifetimes and exhaustive faults remain unclaimed.
