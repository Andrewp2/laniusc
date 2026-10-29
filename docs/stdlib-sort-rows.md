# Stable CSV row ordering with a borrowed comparator

`sample_programs/library/sort_rows.lani` orders bounded CSV input by one column,
preserving every decoded field. The current implementation uses the public
allocation-backed stable sort and has passed 123 native cases. Earlier
unstable-sort receipts are recorded separately below. The standalone build
and both exact examples have also passed.

## Build and use

With the compiler binary built, run from the repository root:

```sh
mkdir -p target/stdlib-work
timeout --kill-after=2s 100s flock -w 95 target/stdlib-work/library-gpu.lock \
  target/stdlib-build/debug/laniusc --stdlib-root stdlib --source-root extended \
  --emit x86_64 sample_programs/library/sort_rows.lani \
  -o target/stdlib-work/sort-rows
printf 'name,score\nold,2\nfirst,10\nsecond,10\n' | \
  target/stdlib-work/sort-rows -H -c 2 -n -r
```

Expected output, with CRLF after every row:

```csv
"name","score"
"first","10"
"second","10"
"old","2"
```

Text ordering also retains interleaved equal keys:

```sh
printf 'b,first\na,second\nb,third\na,fourth\n' | \
  target/stdlib-work/sort-rows
```

Expected output:

```csv
"a","second"
"a","fourth"
"b","first"
"b","third"
```

The standalone build and both exact example commands passed on the migrated
producer. Output is fully quoted CRLF CSV, so quote spelling and record endings
can differ from input while field values remain unchanged.

## CLI and ordering

`--column` is one-based, defaults to 1 and ranges from 1 through 64. Its value
contains ASCII decimal digits without signs or whitespace; leading zeros are
allowed. Short aliases are `-c N`, `-n`, `-r`, `-H` and `-h`. Every duplicate
option is rejected, including aliases and repeated flags in short clusters.
Positional operands are rejected. Help validates all supplied options before
bypassing stdin. Attached short values, long equals values and a final bare
`--` use the existing CLI parser.

Default text ordering compares unsigned UTF-8 bytes lexicographically, then
key length. It is case-sensitive, without normalization, locale collation or
BOM removal. Empty text keys are valid. Valid BOM and Unicode noncharacters
are retained as ordinary text. Invalid UTF-8 and unsupported ASCII controls,
including TAB, NUL and DEL, are rejected by the existing CSV dialect, including
inside quoted fields. Quoted CR and LF remain field content.

`--numeric` parses each selected data cell as a strict signed i64: an optional
leading + or -, followed by at least one ASCII digit, with exact i64 bounds.
Leading zeros are allowed; whitespace, empty fields, separators, decimal points
and overflow are rejected. Only the selected cell is numeric. Original field
spellings are preserved, so +02 and 2 compare equal while retaining their
separate input text and relative order.

`--descending` reverses the primary text/numeric order. Equivalent keys remain
Equal in both directions; the stable library preserves their original input
order. There is no source-index secondary key. The comparator never destroys
a row, mutates its backing or changes its policy during sorting.

## Header and input policy

Rows are ordinary data by default. With `--header`, the first record is retained
at the front and excluded from sorting and numeric-key parsing. It must still
contain the selected column and pass complete CSV validation. All records,
including the header, must have the same field count.

Empty input succeeds with empty output, including with `--header`. Header-only
input emits that header after validation. A blank record is a one-field empty
record: it is valid for a one-column text sort and fails a numeric-key parse.
A missing selected column in any record is an error. No new header is invented.

CSV uses the existing quoted-field, UTF-8 and LF/CRLF rules. Every record and
selected key is validated before sorting or output. Invalid later input cannot
publish an earlier row. Output quotes every field and uses CRLF while retaining
all decoded content, field order and numeric spellings.

## Ownership and algorithm composition

The actual application path is:

```text
native stdin -> owned bytes -> CSV Decoder.take_record
    -> owned Row vector -> alloc::slice::sort_by(counted view, borrowed comparator)
    -> complete staged CSV -> stdout
```

Each Row owns one CSV Record plus a borrowed selected-field view and a parsed
i64 when requested. A separate parsing ordinal recognizes the first/header
record; it is not stored in Row or used for ordering. `take_record` transfers
the record out of the decoder and leaves empty decoder buffers. The header
has its own owner outside the sorted vector.

`alloc::slice::sort_by<Row,Compare>` receives the vector's checked counted view.
For two or more rows it reserves exactly N typed workspace entries before
reading rows or invoking the comparator. Iterative stable merging copies whole
shallow Row handles and chooses the left run on Equal. Record buffers remain
stable, so selected-field views remain valid when their handles move. Workspace
aliases grant no nested cleanup authority; the library releases only temporary
Vec backing before returning. Zero or one row needs no workspace allocation.

The comparator never retires, mutates or retains row cleanup authority. A
returned reservation failure leaves the input unchanged; AllocationFailed maps
to status 4, CapacityOverflow to 2, and impossible Bounds/internal storage
errors to 6. The application also checks the returned sorted count. A final
cleanup loop destroys each record in its current slot exactly once, destroys
the header separately and releases the vector. Append failures destroy the
rejected record. The decoder's partial record is destroyed on parsing failure.

Raw input, argument storage and independent output storage also have explicit
cleanup on returned paths. Scratch is released before CSV staging. All records
are released after output staging and before publication; the staged bytes
remain live through stdout. Existing argv storage stays live through the
run/help/diagnostic call and is released afterward. No new empty-heap-at-write
invariant is claimed. These are manual ownership contracts, not a lifetime or
leak-freedom proof.

## Work admission and bounds

The program admits comparator work before sorting. For N data rows, let
L=`ceil_log2(N)` and M be the longest selected data key in decoded bytes:

```text
N <= 1: admitted sorting work = 0
N > 1:  comparison allowance = 4*N*(1+L)
text:   key_cost = 2*M + 2
numeric:key_cost = 2
require comparison allowance * key_cost <= 100000000
```

A work unit counts an inspected key byte, or one scalar ordering operation.
Text cost covers bytes from both operands plus length/constant ordering
headroom; numeric cost bounds its scalar ordering checks. Byte inspection
includes its comparison. These are dominant logical units, not hardware
instructions, and no deleted ordinal comparison is implied.

Bottom-up merge sorting needs at most N*L comparator calls. The existing
`4*N*(1+L)` admission is deliberately retained as a conservative policy with
spare headroom, preserving the application's previous accepted/rejected work
boundaries. Exact callback schedules are not a public promise. Input caps make
the arithmetic representable, and key cost is compared with the remaining cap
by division before multiplying. Rejection occurs before workspace allocation,
sort mutation or comparator calls. There is no mid-sort budget that changes
comparison answers. Typed copy work is separately bounded by O(N log N) merge
passes; CSV parsing and formatting have their own byte, record and I/O bounds.

| Resource | Bound |
| --- | ---: |
| Raw stdin bytes | 4194304 (4 MiB) |
| Data rows / additional optional header | 16384 / 1 |
| Fields per record / decoded bytes per field | 64 / 8192 |
| Decoded bytes per record | 65536 |
| Pre-sort comparator-work allowance | 100000000 |
| Stable workspace for N >= 2 | Exactly N typed Row entries; checked Vec capacity |
| Independent staged output | 8388608 bytes (8 MiB) |
| stdin / CSV staging / stdout attempts | 16384 / 65536 / 16384 |
| Help / diagnostic attempts | 64 / 8 |
| Captured arguments / total argument bytes | 24 / 1024 |

Decoded-record limits exclude commas, quotes and line endings. An excess-byte
probe distinguishes exact-cap EOF from oversized input. EINTR retries spend
their I/O budget; other errors, including WouldBlock, terminate. Blocking
stdin/stdout have no whole-program wall-clock deadline.

Output is staged completely. Input, work, allocation and internal processing
failures publish no prefix; an stdout failure can leave a confirmed written
prefix. Empty output makes no stdout write and can succeed with a closed
stdout reader.

| Exit | Meaning |
| ---: | --- |
| 0 | Sorted CSV, empty output or help completed |
| 2 | Invalid CLI/CSV/key/range, input/record/field/work/staging or workspace-capacity limit |
| 3 | stdin or argument-capture I/O error, or invalid input transfer count |
| 4 | Reported allocation failure, including stable workspace reservation |
| 5 | stdout error/call limit or SIGPIPE setup failure |
| 6 | Internal decoder-progress or slice-sort failure |

SIGPIPE is ignored before I/O. Setup failure returns 5 before diagnostics;
other failures attempt `sort-rows: operation failed\n` on stderr. A failed
diagnostic preserves the primary status.

## Target and verification

The verified current target is native Linux x86_64 CPU code emitted by the GPU
compiler, with native stdin/stdout. All four migrated application groups passed
on their first attempt: **123 distinct cases**, four registered tests in
12.95 seconds after a separate 1.71-second Rust build. Receipt:
`target/stdlib-work/stable-sort-sort-rows-first.log`.

| Group | Cases | Retained evidence |
| --- | ---: | --- |
| Model | 37 | `/tmp/sort-rows-model-19qiycu3` |
| Rejection | 33 | `/tmp/sort-rows-rejection-ec8qh_9d` |
| CLI | 39 | `/tmp/sort-rows-cli-l_oukou0` |
| I/O | 14 | `/tmp/sort-rows-io-0e6dks_x` |

The corpus preserves the earlier 122 cases and adds one specifically reached
workspace ENOMEM process; no separate calibration process was needed. Existing
model cases check stable text/numeric ties in both directions, equivalent
numeric spellings, headers, full-width values, quoted fields, exact input/row
limits and the unchanged work-boundary pair.

The new failure binds the actual five-row workspace request to its source-Vec
generations and lifetime. The oracle requires a unique immediately paired
workspace mmap/munmap, whose five-entry requested size agrees with the earlier
four-entry and live eight-entry Row-vector generations. That scratch retires
before output-staging allocation. This does not assume a private Row byte
width or choose a generic middle allocation. The injected failure must match
the actual baseline request arguments, return 4, publish nothing, make no
later allocation and release every observed successful mapping. Comparator
call absence and input rollback require separate direct library evidence.

The four existing selected ENOMEM cases also remain accepted. Full selected
traces pair successful mappings and releases by address/requested length,
including record/header/value-vector cleanup. Existing argv lifetime is
preserved through publication; an empty heap at stdout is not asserted. These
are finite cleanup observations, not exhaustive lifetime or leak proofs.

Current accepted identities (SHA-256):

- Application: `9fd332e423755156c69b4cc77da2fc765a7690c4f99309cde14365fe602cb806`.
- Oracle: `3d9e550373381d52367764b28c148d9a336dba6663d4b138290e8d1480ab304b`.
- `alloc::slice`: `e56129df41d435c226a11612d67b52cd9364e25d35d295e90f592376009aa667`.

Static checks confirm unchanged help (442 bytes), diagnostic (28 bytes),
literal lengths and final newline. The exact documented standalone build
exited 0 with a silent compiler
(`target/stdlib-work/stable-sort-sort-rows-standalone.log`). Both example
commands exited 0 with empty stderr and literal quoted CRLF output: 56 bytes
for the header/numeric/descending case in
`target/stdlib-work/stable-sort-sort-rows-example-header.csv`, and 54 bytes
for text ties in `target/stdlib-work/stable-sort-sort-rows-example-ties.csv`.
Their corresponding `.stderr` files are empty. The examples overlap the
functional corpus and add no distinct cases. Production is entirely Lanius
using CSV, decimal, CLI, stream and the public stable sort. No new parser,
protocol, host service or Rust/Python library implementation is added.

### Historical unstable-sort producer

The earlier producer used allocation-free heapsort with a unique source-index
secondary key. Its four registered groups were accepted on 2026-10-28,
totaling 122 unique native cases across two focused runs. These receipts
retain that earlier producer's scope and do not verify the stable migration:

| Accepted group | Cases | Receipt under `target/stdlib-work/` |
| --- | ---: | --- |
| Model | 37 | One test, 12.78s; `slice-ordering-sort-rows-model-first.log`, three other tests filtered |
| CLI, rejection and I/O | 39 + 33 + 13 | Three tests, 9.65s; `slice-ordering-sort-rows-boundaries.log`, model filtered |

Both runs compiled the unchanged application through the GPU compiler and
passed the shared strict ELF checker before execution. Evidence directories:

- Model: `/tmp/sort-rows-model-rgnmuu8h`.
- CLI: `/tmp/sort-rows-cli-_oygmwul`.
- Rejection: `/tmp/sort-rows-rejection-6ccq315u`.
- I/O: `/tmp/sort-rows-io-w4j2yd79`.

The independent test-only oracle uses Python CSV and stable builtin sorting,
without reproducing heapsort. It checks exact quoted CRLF output, all field
spellings, text/numeric keys, both directions, tie order, header policy,
Unicode distinctions, quoting/newlines/trailing empty fields and exact 4 MiB
input. Cases cover i64 extrema, field/record/row boundaries and seeded models.
Ten CPU-only controls passed separately, including every generated reference
CSV round trip.

The text-work boundary is exercised with 512 keys: 2440-byte keys admit
99983360 units; 2441-byte keys reject 100024320 units. Singleton long-field
cases require no comparisons. Larger staging and write-call caps remain
explicit bounds rather than independently reached fixture cases.

I/O cases include real directory stdin and closed stdout failures, reached
read/write errors and interruption retries, plus four selected allocation
denials. Every ENOMEM must be reached with matching baseline mmap arguments,
return allocation status and publish no output. Selected full traces pair
observed successful mmap and munmap address/size pairs. These finite
observations do not establish arbitrary allocation schedules, automatic
ownership checking or lifetime/leak freedom. The later read error requires
an actual earlier positive read and no published prefix; positive transfer
counts are not fabricated.

Executed application source SHA-256:
`16776894ee2749534f617399ed06f7257e9a889812d3bec202d9bb251a16122d`.
Oracle SHA-256:
`d45a3262e8c23a919dbacce290619701ed0b6f82dc645270ef0bbc9e831f6603`.
See `tests/fixtures/stdlib_execution/sort_rows/README.md` for detailed
reference/fault scope and `tests/stdlib_sort_rows_execution.rs` for the
registered driver. Any later whitespace-only driver formatting changes no
application behavior and is not represented as a native rerun.
With a warm build and configured GPU, reproduce using:

```sh
timeout --kill-after=2s 100s flock -w 95 target/stdlib-work/library-gpu.lock \
  env CARGO_TARGET_DIR=target/stdlib-build LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=70000 \
  cargo test --test stdlib_sort_rows_execution -- --nocapture --test-threads=1
```

The [slice ordering guide](stdlib-slice-ordering.md) records the separate core
unstable APIs and their evidence. The current stable migration follows the
[allocation-backed stable-sort plan](library-stable-sort-plan.md); its equal
keys rely on the stable library rather than the historical secondary key.
The source imports `core::slice` and qualifies
slice-view calls, following the
[existing import limitation reduction](../tests/fixtures/stdlib_compiler_state/item_import_priority/README.md).
Compiler repair remains separate; this increment changes no compiler, ABI or
proof source. Automatic ownership, formal verification and broader target
execution remain roadmap work.
