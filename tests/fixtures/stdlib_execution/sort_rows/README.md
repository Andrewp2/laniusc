# CSV row ordering application fixture

The oracle uses Python's independent CSV reader/writer and stable builtin
`sorted`. Text keys compare encoded UTF-8 bytes; numeric keys use separately
validated optional-sign ASCII decimal i64 values. Descending reverses primary
key order while preserving input order for ties. The library heapsort is not
reimplemented and its unstable tie layout is not asserted.

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
| io | 13 | Directory stdin, closed data/help stdout, traced baseline, four reached mmap denials, read/write EINTR, later read/first write EIO and SIGPIPE setup failure |

Allocation faults select early argument storage, the first input allocation,
a middle construction allocation and the last output allocation. Each ENOMEM
must be reached at its selected baseline ordinal with matching mmap arguments,
return status 4 and publish no output. Allocation order is not a public API.
Every observed successful mmap must match a successful munmap of the same
address and size; unexpected allocation services fail the fixture. This finite
trace check is not a resource checker, exhaustive denial campaign, lifetime
or alias check, or proof of leak freedom. Later read EIO requires a positive
earlier read and no publication; no positive transfer count is fabricated.

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

## Acceptance

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
