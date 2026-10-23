# CSV grouping report

`sample_programs/csv_report.lani` is a complete native application using the
standard and extended libraries. It reads CSV from stdin, validates its schema
and numbers, groups records, computes checked totals, and writes JSON to stdout.

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  sample_programs/csv_report.lani --stdlib-root stdlib \
  --source-root extended -o /tmp/csv-report

timeout --kill-after=1s 5s /tmp/csv-report <<'CSV'
group,value
fruit,12
veg,-3
fruit,+005
CSV
```

Output:

```json
[{"group":"fruit","total":17,"count":2},{"group":"veg","total":-3,"count":1}]
```

## Behavior

- The first record must contain exactly `group,value`, with matching case and
  no surrounding spaces. Ordinary CSV quoting is accepted in the header.
- Each following record has two fields. Group names retain their exact decoded
  text, including empty names, spaces, Unicode, commas and quoted line breaks.
- Values are signed 32-bit decimal integers. A leading plus/minus and leading
  zeroes are accepted. There is no trimming, decimal point or exponent syntax.
- Totals are checked after each record. An intermediate overflow fails even
  when a later value could bring the mathematical final sum back into range.
- Groups appear in first-occurrence order. Each output object has `group`,
  `total` and `count`. Header-only input produces `[]`; empty input is invalid.
- All parsing, validation and encoding finish before the first stdout write.
  A later output failure can leave a prefix; exit status remains nonzero.

Limits are 16 MiB input, 100,000 data records, two fields per record and 1 MiB
decoded bytes per field. The JSON encoder also enforces its default limits.
These are logical limits rather than a total-memory bound.

| Exit status | Meaning |
| --- | --- |
| 0 | Complete JSON output |
| 2 | Invalid UTF-8, CSV, schema, integer, arithmetic overflow or configured limit |
| 3 | Input/output failure, including a write that makes no progress |
| 4 | Allocation failure |

Errors produce best-effort stderr diagnostics. Invalid values and overflowing
totals identify a one-based CSV record number, counting the header as record 1.
This is a record number, not a physical line number when quoted text spans lines.

## Modules exercised

| Module | Role |
| --- | --- |
| `alloc::io`, `core::io`, `std::stream` | Bounded input buffering, partial reads/writes and native descriptors |
| `alloc::string` | Valid UTF-8 ownership; one independent name per group |
| `core::text` | Borrowed fields, decimal parsing and text-key lookup |
| `ext::csv` | Table parsing, limits and field access |
| `core::decimal`, `core::i32` | Explicit numeric parsing errors and checked addition |
| `std::vec`, `alloc::hash_map` | Owned group records and hashed Text-to-index lookup |
| `ext::json` | Document building, borrowed mutation and encoding |
| `core::option`, `core::result` | Absence and failure propagation |

The group vector owns each name. The lookup map borrows those names and is
destroyed before them. CSV fields are borrowed while reading rows; numeric
fields and repeated group names are not copied. A failed insertion rolls back
the new group. JSON copies
its keys and values; helper functions borrow the actual document owner while
growing its storage. Every application error path releases owned resources.

## Execution evidence

Both groups in `tests/library_csv_report_execution.rs` passed on 2026-10-22,
using the GPU compiler and executing the emitted binaries on x86_64 Linux:

- Empty reports, signed extrema, repeated groups, exact ordering, malformed
  schemas/CSV/numbers/UTF-8 and intermediate arithmetic overflow.
- 4,096 deterministic generated records, including quoted/multiline/Unicode
  names, compared with an independent Rust grouping model and JSON decoder.
- Every allocation failed in turn across input, parsing, grouping and encoding.
  Syscall traces check that all successful allocations are released.
- Cleanup after malformed data; interrupted reads/writes retry successfully;
  I/O errors and would-block return failure. An injected second-write error
  leaves exactly the first 1,024 output bytes and returns status 3.

The traced failure group passed in 13.61 seconds. Each traced native process
has a five-second bound; syscall tracing the generated workload exceeds the
ordinary 500 ms process limit.

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test library_csv_report_execution -- --nocapture
```

## Runtime measurements

On an AMD Ryzen 9 5950X, the emitted native program gave these elapsed times.
Each measurement includes process startup and pipe I/O, excludes compilation,
uses three measured runs after one warm-up, and verifies the complete output.
No syscall tracing was enabled. These are initial local measurements.

| Records | Distinct groups | Input bytes | Output bytes | Median |
| ---: | ---: | ---: | ---: | ---: |
| 4,096 | 64 | 45,703 | 2,714 | 240.92 ms |
| 32,768 | 64 | 365,425 | 2,773 | 1,624.05 ms |
| 4,096 | 1,024 | 50,095 | 43,452 | 675.91 ms |

The workload has header `group,value\n`, followed by records
`group{i % groups},{i % 101 - 50}\n` for zero-based `i`.
The individual samples are recorded in
`target/stdlib-work/csv-report-runtime.tsv` in the development checkout.

Those initial measurements used the linear map. After migration to
`alloc::hash_map`, a paired comparison on the same machine gave:

| Records | Distinct groups | Linear-map median | Hash-map median |
| ---: | ---: | ---: | ---: |
| 4,096 | 64 | 235.60 ms | 217.46 ms |
| 32,768 | 64 | 1,353.39 ms | 1,231.30 ms |
| 4,096 | 1,024 | 694.17 ms | 306.82 ms |

Each case used one warm-up pair, then four measured pairs with alternating
execution order. Both binaries' complete outputs were verified against the
same expected groups. Samples are in
`target/stdlib-work/csv-report-hash-runtime.tsv`. Compiler sources did not
change between these two binaries. The reporter's two integration test groups
passed again after migration, including the complete allocation-failure sweep.

After replacing field copies with borrowed Text, another paired comparison
against commit `bab810ce` gave:

| Records | Distinct groups | Owned-field median | Borrowed-field median |
| ---: | ---: | ---: | ---: |
| 4,096 | 64 | 232.36 ms | 175.24 ms |
| 32,768 | 64 | 1,755.69 ms | 1,233.25 ms |
| 4,096 | 1,024 | 302.83 ms | 268.91 ms |

The baseline was rebuilt from that commit's archived library/application
sources using the same compiler as the new program. Each case used one warm-up
pair and four measured pairs with alternating order, process startup and pipe
I/O included, compilation excluded. Every output byte matched the expected
JSON. Samples are in `target/stdlib-work/csv-report-text-runtime.tsv`. These
local measurements describe the combined String/Text/application change; they
are not measurements of compiler throughput or GPU user-program execution.
Both report test groups passed again in 13.32 seconds, including the allocation
and I/O fault sweep.

The new lookup is expected constant time with distributed hashes, with linear
worst-case probes. CSV still owns the complete table and separately allocates
fields. Streaming CSV and lower allocation overhead remain work. This application
establishes module composition and failure behavior; it does not complete the
text/data foundation or the broader library roadmap. GPU user-program execution
and other host targets are unverified.
