# CSV row ordering with a borrowed comparator

`sample_programs/library/sort_rows.lani` orders bounded CSV input by one column,
preserving every decoded field:

```sh
sort-rows [--column N] [--numeric] [--descending] [--header] [--help]
printf 'name,score\nold,2\nfirst,10\nsecond,10\n' | sort-rows -H -c 2 -n -r
```

The example keeps the header, then emits first/10, second/10 and old/2. Equal
keys retain their original input order even when the primary key is descending.
Output is fully quoted CRLF CSV, so the output spelling of quotes and record
endings can differ from input while field values remain unchanged.

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

`--descending` reverses the primary text/numeric order. An original source-row
index always breaks ties in ascending order. The underlying heapsort remains
unstable; the explicit unique secondary key provides stable visible ties.
The comparator never reverses the source index, destroys a row or changes its
policy during sorting.

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
    -> owned Row vector -> sort_unstable_by(counted view, borrowed comparator)
    -> complete staged CSV -> stdout
```

Each Row owns one CSV Record plus a borrowed selected-field view, a parsed i64
when requested and the original row index. `take_record` transfers the record
out of the decoder and leaves empty decoder buffers. The header has its own
owner outside the sorted vector.

`sort_unstable_by<Row,Compare>` receives the vector's checked counted view.
Its allocation-free heapsort moves whole shallow Row handles. Record buffers
remain stable, so selected-field views remain valid when their handles move.
The comparator receives temporary shallow values and never retires, mutates
or retains their cleanup authority. A final cleanup loop destroys each record
in its current slot exactly once, destroys the header separately and releases
the vector. Append failures destroy the rejected record. The decoder's current
partial record is destroyed on parsing failure.

Raw input, argument storage and independent output storage also have explicit
cleanup on returned paths. All records are released after output staging and
before publication; the staged bytes remain live through stdout. These are
manual ownership contracts, not a lifetime or leak-freedom proof.

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
Text cost covers bytes from both operands plus length and source-index
ordering; numeric cost covers numeric-key and source-index ordering. Byte
inspection includes its comparison; these are dominant logical units rather
than hardware instructions.

Each heapsort sift traverses at most L levels with at most two comparator
calls per level. Bounding heap construction and extraction by N sifts each
already gives at most 4*N*L comparisons; `4*N*(1+L)` conservatively includes
boundary cases. Exact callback schedules are not a public promise. The input
caps make the allowance arithmetic representable, and key cost is compared
with the remaining cap by division before multiplying. Rejection occurs
before any sort mutation or comparator call. There is no mid-sort budget that
changes comparison answers. CSV parsing and formatting have their own byte,
record and I/O bounds rather than this comparison estimate.

| Resource | Bound |
| --- | ---: |
| Raw stdin bytes | 4194304 (4 MiB) |
| Data rows / additional optional header | 16384 / 1 |
| Fields per record / decoded bytes per field | 64 / 8192 |
| Decoded bytes per record | 65536 |
| Pre-sort comparator-work allowance | 100000000 |
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
| 2 | Invalid CLI/CSV/key/range, input/record/field/work/staging limit |
| 3 | stdin or argument-capture I/O error, or invalid input transfer count |
| 4 | Reported allocation failure |
| 5 | stdout error/call limit or SIGPIPE setup failure |
| 6 | Internal decoder-progress or slice-sort failure |

SIGPIPE is ignored before I/O. Setup failure returns 5 before diagnostics;
other failures attempt `sort-rows: operation failed\n` on stderr. A failed
diagnostic preserves the primary status.

## Target and verification

The verified target is native Linux x86_64 CPU code emitted by the GPU
compiler, with native stdin/stdout. Device-side GPU execution is outside this
profile. Production is entirely Lanius using existing CSV, decimal, CLI,
stream and comparator/slice modules. No new parser, protocol, host service or
Rust/Python library implementation is added.

All four registered application groups are accepted on 2026-10-28, totaling
122 unique native cases across two focused runs:

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

The [slice ordering guide](stdlib-slice-ordering.md) records separate shared
API contracts and library evidence. This application's stable visible ties
come from its unique source-index secondary key; they do not add stability
to the underlying sort API. The source imports `core::slice` and qualifies
slice-view calls, following the
[existing import limitation reduction](../tests/fixtures/stdlib_compiler_state/item_import_priority/README.md).
Compiler repair remains separate; this increment changes no compiler, ABI or
proof source. Automatic ownership, formal verification and broader target
execution remain roadmap work.
