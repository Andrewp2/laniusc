# CSV row ordering application fixture

The oracle uses Python's independent CSV reader/writer and stable builtin
`sorted`. Text keys compare encoded UTF-8 bytes; numeric keys use separately
validated optional-sign ASCII decimal i64 values. Descending reverses primary
key order while preserving input order for ties. The library sorting engine is
not reimplemented. The stable-sort migration removes the application's source
ordinal tie-breaker: equal primary keys now depend on `alloc::slice::sort_by`
preserving whole-row order.

Every successful output is checked byte-for-byte against fully quoted CRLF
CSV, including all original field spellings, quoted commas/quotes/embedded
line endings, valid BOM/noncharacters and Unicode normalization distinctions.
Headers remain first and bypass numeric-key parsing, while selected-column
and width validation still apply. CSV's TAB/NUL/DEL rejection is tested.

| Group | Cases | Coverage |
| --- | ---: | --- |
| model | 37 | Empty/singleton/header-only, both directions, stable text/numeric ties, extrema/signed zeros, UTF-8 byte order, quoting/newlines/trailing empty fields, default/selected columns, exact 4 MiB input, field/record/row boundaries, text-work boundary and seeded models |
| rejection | 33 | Malformed CSV/UTF-8/controls/width, field/record/row/input caps, strict i64 grammar/bounds, missing selected columns, invalid later keys and text-work admission |
| cli | 39 | Column grammar/bounds, duplicate aliases/flags, operands, argument caps, help validation/input bypass and short clusters/attached/long equals forms |
| io | 14 | Directory stdin, closed data/help stdout, traced baseline, five reached mmap denials including the stable-sort workspace, read/write EINTR, later read/first write EIO and SIGPIPE setup failure |

Allocation faults select early argument storage, the first input allocation,
a middle construction allocation and the last output allocation. Each ENOMEM
must be reached at its selected baseline ordinal with matching mmap arguments,
return status 4 and publish no output. Allocation order is not a public API.
Every observed successful mmap must match a successful munmap of the same
address and size; unexpected allocation services fail the fixture. This finite
trace check is not a resource checker, exhaustive denial campaign, lifetime
or alias check, or proof of leak freedom. Later read EIO requires a positive
earlier read and no publication; no positive transfer count is fabricated.

The fifth denial targets the actual stable-sort workspace. The existing
baseline has five data rows plus a separate header. Source inspection binds
its Row vector to a capacity-four generation followed by capacity eight, and
the stable sort to one exact five-row reservation. The oracle requires a
unique immediately paired workspace mmap/munmap whose requested bytes imply
the same element size as both Row-vector generations. The capacity-four
generation must retire just after the capacity-eight allocation; capacity
eight must remain live across the workspace. Whole-input EOF precedes these
phases, the workspace retires before any output-staging allocation, and the
Row vector retires before stdout. Ambiguous evidence fails the oracle.

This identifies size and lifetime from the source and the actual trace; it
does not assume a private Row layout or select a generic middle mapping. The
new ENOMEM process must match the baseline allocation-argument prefix through
that exact request, return 4 with no stdout, make no later allocation, and
release every observed successful mapping. Comparator-call absence and input
rollback belong to direct library gates, not this application trace. No extra
native calibration process is used. Current argument owners remain live
through stdout; the fixture does not require an empty heap at publication.

The work-boundary pair uses 512 equal text keys with 2,440 and 2,441 bytes:
`4*512*(1+9)*(2*key_bytes+2)` is respectively below and above 100,000,000.
Long field/record cases use singleton sorting, for which no comparisons are
required. Larger staged-output/write-call caps are bounds rather than
independently reached cases in this fixture.

```sh
python3 -B tests/fixtures/stdlib_execution/sort_rows/oracle.py controls
python3 -B tests/fixtures/stdlib_execution/sort_rows/oracle.py model PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/sort_rows/oracle.py rejection PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/sort_rows/oracle.py cli PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/sort_rows/oracle.py io PATH_TO_ELF
```

Each native child has a 25-second deadline; each registered group has an
85-second deadline. Commands, inputs, stdout, stderr, status and optional
syscall evidence are retained. CPU controls check tie stability, strict i64
bounds, every generated CSV input/output reference round trip, work-boundary
arithmetic, group counts and a deliberately missing release.

Six additional CPU-only workspace controls check a valid source-bound trace
and reject wrong workspace size, wrong Row-vector size, missing release,
missing publication and ambiguous candidate identity. Together with the ten
existing controls, **16 CPU controls passed**; this is separate from native
acceptance.

## Accepted stable-sort migration

All four registered groups passed on the first attempt: **123 distinct native
Linux x86_64 cases**, retaining the original 122 and adding one workspace
denial. Receipt: `target/stdlib-work/stable-sort-sort-rows-first.log`, four
tests passed in **12.95 seconds**, with a separate **1.71-second Rust build**.
The driver compiled the application through the GPU compiler, required an
actual x86_64 ELF and passed the existing shared direct-jump check before CPU
execution. No user-program GPU execution is claimed.

| Group | Cases | Evidence directory |
| --- | ---: | --- |
| Model | 37 | `/tmp/sort-rows-model-19qiycu3` |
| Rejection | 33 | `/tmp/sort-rows-rejection-ec8qh_9d` |
| CLI | 39 | `/tmp/sort-rows-cli-l_oukou0` |
| I/O | 14 | `/tmp/sort-rows-io-0e6dks_x` |

The actual successful baseline reads 82 input bytes and then EOF. Its Row
storage grows from a 384-byte capacity-four mapping to a 768-byte
capacity-eight mapping. The uniquely bound five-entry workspace requests
480 bytes and releases them immediately, before output staging. These
observations imply 96 bytes per Row in this executable; they are not an ABI
assumption or a portable Row-size promise. The final Row mapping and Record
owners retire before the 82-byte stdout write. A 100-byte staged-output
mapping and the two 200/38-byte argument mappings remain live through that
write, then retire.

The additional ENOMEM is reached at that same 480-byte request, matching the
baseline allocation-argument prefix. It returns 4, publishes no stdout and
makes no later allocation. The trace explicitly releases the five data
Records, separate header, final Row vector and raw input before its generic
diagnostic; argument mappings retire afterward. All observed successful
mappings match exact successful releases. This is one additional native
process, with no hidden calibration processes. The four existing selected
denials, read/write errors and interruption cases also pass in this receipt.
The finite application evidence does not prove comparator-call absence,
rollback, arbitrary failure schedules, lifetime safety or leak freedom.

Executed application SHA-256:
`9fd332e423755156c69b4cc77da2fc765a7690c4f99309cde14365fe602cb806`.
Oracle SHA-256:
`3d9e550373381d52367764b28c148d9a336dba6663d4b138290e8d1480ab304b`.
Stable-sort library SHA-256:
`e56129df41d435c226a11612d67b52cd9364e25d35d295e90f592376009aa667`.
Executed driver before subsequent whitespace-only root formatting:
`2f88b193f11e258098de289e4a9aebd9c230e485afe1bc34d1c0041c8e722e37`.
That formatting is not represented as a native rerun. Standalone application
examples have separate receipts in the
[application guide](../../../../docs/stdlib-sort-rows.md); they add no unique
cases to this fixture's 123.

## Historical application acceptance before the stable-sort migration

All four groups passed: **122 native Linux x86_64 cases** using the same
application and oracle across two receipts. The driver used the GPU compiler
and the shared strict ELF checker before CPU execution.

- Model 37 passed in 12.78 seconds; the other three tests were filtered.
  Receipt: `target/stdlib-work/slice-ordering-sort-rows-model-first.log`.
- CLI 39, rejection 33 and I/O 13 passed in 9.65 seconds; the model test was
  filtered. Receipt:
  `target/stdlib-work/slice-ordering-sort-rows-boundaries.log`.

Evidence directories:

- Model: `/tmp/sort-rows-model-rgnmuu8h`.
- CLI: `/tmp/sort-rows-cli-_oygmwul`.
- Rejection: `/tmp/sort-rows-rejection-6ccq315u`.
- I/O: `/tmp/sort-rows-io-w4j2yd79`.

Executed application SHA-256:
`16776894ee2749534f617399ed06f7257e9a889812d3bec202d9bb251a16122d`.
Oracle SHA-256:
`d45a3262e8c23a919dbacce290619701ed0b6f82dc645270ef0bbc9e831f6603`.
Preformat executed driver SHA-256:
`a53df9305e9b38f49ddd15e35dee32a5e6af684456d18e4bc76a4fca159efd90`.
That identity records the driver used for these receipts, before any final
whitespace formatting.

Ten CPU-only controls also passed. The native I/O receipt reaches all four
selected allocation denials and matches every observed successful mapping
with an explicit release in its traced processes. These finite observations
do not establish leak freedom or exhaustive allocation-failure coverage.
Device-side execution and formal verification remain outside this receipt.
