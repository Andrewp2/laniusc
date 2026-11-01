# Stable CSV row ordering with a borrowed comparator

`sample_programs/library/sort_rows.lani` orders bounded CSV input by one column,
with optional empty-key filtering, equal-key deduplication and a data-row limit.
It uses the public stable sort and [owned Vec editing](stdlib-vec-edit.md).
Selected rows retain every decoded field. All four editing-migration application
groups pass on native Linux x86_64, totaling 132 group cases. Earlier stable-sort
(123 cases) and unstable-sort receipts below retain their original producer
scope; counts are not added across those corpora.

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

These two commands passed on the preceding stable-sort producer; they are not
new execution receipts for the editing migration. Output is fully quoted CRLF
CSV, so quote spelling and record endings can differ from input while selected
field values remain unchanged.

Filtering, deduplication and limiting compose in that order around the sort:

```sh
printf 'key,value\nb,first\n,drop\na,early\na,later\nc,last\n' | \
  target/stdlib-work/sort-rows -H --drop-empty --unique --limit 2
printf '+02,early\n2,later\n1,last\n' | \
  target/stdlib-work/sort-rows -n -r --unique --limit 1
```

Expected quoted CRLF rows are `key,value`, `a,early`, `b,first` in the first
example (41 bytes), and `+02,early` in the second (15 bytes). These new examples
are illustrative expected outputs; no separate execution receipt is claimed.

## CLI and ordering

`--column` is one-based, defaults to 1 and ranges from 1 through 64. Its value
contains ASCII decimal digits without signs or whitespace; leading zeros are
allowed. Short aliases are `-c N`, `-n`, `-r`, `-H` and `-h`. Every duplicate
option is rejected, including aliases and repeated flags in short clusters.
Positional operands are rejected. Help validates all supplied options before
bypassing stdin. Attached short values, long equals values and a final bare
`--` use the existing CLI parser.

The new options are long-only:

| Option | Policy |
| --- | --- |
| `--drop-empty` | After complete validation, discard data rows whose selected text cell has zero bytes. |
| `--unique` | After stable sorting, retain the earliest input row for each equal selected key. |
| `--limit N` | After filtering, sorting and deduplication, retain at most N data rows; ASCII decimal 0..16384, leading zeros allowed. |

`--limit=N` uses the existing long-value parser. These options obey the same
duplicate rejection, including with help. There is no additional per-token
limit beyond argument capture. A zero limit still validates every record/key,
admits work, sorts and deduplicates when selected. It does not bypass errors or
work limits.

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
separate input text and relative order. With `--unique`, numeric equality uses
the parsed value, so the earliest spelling survives. Text equality uses exact
UTF-8 bytes. Numeric validation precedes `--drop-empty`: an empty numeric key
is still invalid and cannot be filtered away.

`--descending` reverses the primary text/numeric order. Equivalent keys remain
Equal in both directions; the stable library preserves their original input
order. There is no source-index secondary key. The comparator never destroys
a row, mutates its backing or changes its policy during sorting.

## Header and input policy

Rows are ordinary data by default. With `--header`, the first record is retained
at the front and excluded from filtering, sorting, deduplication, limiting and
numeric-key parsing. It must still contain the selected column and pass complete
CSV validation. All records,
including the header, must have the same field count. `--limit 0` can therefore
emit a validated header while retaining no data rows.

Empty input succeeds with empty output, including with `--header`. Header-only
input emits that header after validation. A blank record is a one-field empty
record: it is valid for a one-column text sort and fails a numeric-key parse.
A missing selected column in any record is an error. No new header is invented.

CSV uses the existing quoted-field, UTF-8 and LF/CRLF rules. Every record and
selected key is validated through EOF before filtering, sorting or output.
Invalid later input cannot publish an earlier row. Output quotes every field and uses CRLF while retaining
all decoded content, field order and numeric spellings.

## Ownership and algorithm composition

The actual application path is:

```text
native stdin -> owned bytes -> CSV Decoder.take_record
    -> owned Row vector -> optional retain_destroy
    -> alloc::slice::sort_by(counted view, borrowed comparator)
    -> optional dedup_by_destroy -> truncate_destroy
    -> complete staged CSV -> clear_destroy + release owners -> stdout
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
errors to 6. The application also checks the returned sorted count. Each Row's
explicit Destroy implementation releases its owned Record. Filtering and
deduplication release rejected rows immediately in forward order; limiting and
final `clear_destroy` cleanup release tails in reverse order. Final cleanup
then releases outer vector storage and destroys the separate header. Append failures
destroy the rejected record. The decoder's partial record is destroyed on
parsing failure. These paths do not clone Records or create new cleanup owners.
Selected-field views borrow their own Row's stable record backing; surviving
rows do not borrow storage released by removed rows.

Raw input, argument storage and independent output storage also have explicit
cleanup on returned paths. Scratch is released before CSV staging. All records
are released after output staging and before publication; the staged bytes
remain live through stdout. Existing argv storage stays live through the
run/help/diagnostic call and is released afterward. No new empty-heap-at-write
invariant is claimed. These are manual ownership contracts, not a lifetime or
leak-freedom proof.

## Work admission and bounds

The program admits comparator work after optional empty-key filtering and
before sorting. For N surviving data rows, let L=`ceil_log2(N)` and M be the
longest selected data key in decoded bytes. Removing only empty keys leaves
that maximum unchanged whenever nonempty keys survive:

```text
N <= 1: admitted sorting work = 0
N > 1:  comparison allowance = 4*N*(1+L) + (N-1 if --unique else 0)
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
spare headroom. Without new editing options, the previous accepted/rejected
work boundaries stay unchanged. `--unique` adds exactly N-1 adjacent callback
allowance; each compares the last retained row with current. `--limit` does not
reduce admitted sort/dedup work. The stable-sort callback schedule is not a
public promise. Input caps make the arithmetic representable, and key cost is compared with the remaining cap
by division before multiplying. Rejection occurs before workspace allocation,
sort mutation or comparator calls; optional filtering may already have released
empty-key rows. There is no mid-sort budget that changes comparison answers. Typed copy work is separately bounded by O(N log N) merge
passes; CSV parsing and formatting have their own byte, record and I/O bounds.

| Resource | Bound |
| --- | ---: |
| Raw stdin bytes | 4194304 (4 MiB) |
| Parsed data rows before filtering / additional optional header | 16384 / 1 |
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

The current editing migration passes on native Linux x86_64 CPU code emitted
by the GPU compiler, with native stdin/stdout. Its four focused application
groups total **132 group cases**, including 57 reached allocation denials:

| Group | Cases | Test time | Log under `target/stdlib-work/` |
| --- | ---: | ---: | --- |
| Independent CSV pipeline model | 22 | 7.42 s | `vec-edit-app-model.log` |
| Complete input/key admission and actual bounds | 17 | 14.49 s | `vec-edit-app-admission.log` |
| New CLI policies | 26 | 6.98 s | `vec-edit-app-cli.log` |
| Cleanup and output failures | 67 | 7.87 s | `vec-edit-app-io.log` |

The I/O group contains ten baseline/output-failure cases plus 57 allocation
denials tied to actual baseline requests. The
[focused fixture guide](../tests/fixtures/sort_rows_edit/README.md) records exact
owner and selected-syscall observations. These are finite native observations,
not an exhaustive allocation schedule or a lifetime proof. Three selected old
regression groups also pass on the current source in one 10.83-second command
(`vec-edit-app-regressions.log`): CLI 39, rejection 33 and model 37. These 109
cases remain separate from the new 132-case corpus; the old I/O group was
filtered out. Historical receipts below retain their earlier source scope.

Current source SHA-256 is
`7c0eec2c872ae505cb513fc40b13098b1c7922805701cd9b8d5a51e41c5796ab`;
driver `b4ec4f4d` and oracle `95c3bb0b` bind the new groups. The help literal is
827 bytes and the existing diagnostic remains 28 bytes. No new standalone
shell-example execution is included in the 132 cases.

### Historical stable-sort producer

The preceding stable-sort migration passed all four application groups
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

Historical stable-sort identities (SHA-256):

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
unstable APIs and their evidence. The preceding stable migration followed the
[allocation-backed stable-sort plan](library-stable-sort-plan.md); its equal
keys rely on the stable library rather than the historical secondary key.
The source imports `core::slice` and qualifies
slice-view calls, following the
[existing import limitation reduction](../tests/fixtures/stdlib_compiler_state/item_import_priority/README.md).
Compiler repair remains separate; this increment changes no compiler, ABI or
proof source. Automatic ownership, formal verification and broader target
execution remain roadmap work.
