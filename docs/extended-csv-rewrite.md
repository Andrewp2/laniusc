# Streaming CSV column rewriting

[`sample_programs/library/csv_rewrite.lani`](../sample_programs/library/csv_rewrite.lani)
reads CSV from stdin, selects columns in the requested order and writes
canonical CSV to stdout. It reuses one decoder and one constructed record;
it never collects the table or materializes an encoded output String.

The verified executable profile is Linux x86_64 native CPU execution. The GPU
compiler produces the executable; the application uses the Lanius CSV modules
and Linux stream/allocator services without an external CSV runtime.

```text
csv-rewrite COLUMNS [OPTIONS]
```

`COLUMNS` is one nonempty comma-separated list of zero-based decimal indices.
Reordering and repetition are deliberate: `2,0,2` emits the third, first and
third fields of every record. Every row is data, including the first. There is
no header mode, delimiter detection, field conversion or name-based selection.
Spaces, signs, empty list elements and trailing commas are invalid. Leading
zeroes are allowed. Both an index and the number of selected fields must fit
the configured field bound.

For example:

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  --stdlib-root stdlib --source-root extended \
  sample_programs/library/csv_rewrite.lani -o /tmp/csv-rewrite

printf 'id,name,city\n1,Alice,Paris\n' | /tmp/csv-rewrite 2,0,2 --report
```

Stdout is:

```csv
"city","id","city"
"Paris","1","Paris"
```

The actual record endings are CRLF. `--report` writes counters to stderr,
separately from CSV stdout.

## Dialect and transformation

The app uses the existing [`ext::csv`](extended-csv.md) dialect unchanged:

- UTF-8 is required. Malformed or incomplete UTF-8 fails.
- Commas separate fields. Quotes open only at field start, and doubled quotes
  represent one quote. Quoted CR and LF are preserved as field data.
- CRLF and LF record endings are accepted. Bare CR outside quotes fails.
- NUL, TAB, other ASCII controls except quoted CR/LF, and DEL fail. Unicode
  scalars outside ASCII, including BOM and noncharacters, remain unchanged.
- Every record must have the same number of fields. A selected index must
  exist in that width. The app does not fill missing fields or skip bad rows.
- Empty input has no records. A blank record has one empty field; selecting
  field zero produces the four bytes `""\r\n`. A final record need not have a
  record separator. A trailing separator adds no record.

The decoder processes a fixed input buffer of 4,096 logical byte elements, stopping at each
complete record and then resuming the unconsumed chunk remainder. Selected
fields borrow the decoder's current packed record. The app copies them in
selection order through `Record.try_push_field` into one reusable output
record. It finishes writing that record before feeding more input.

[`ext::csv_write::write_record`](../extended/ext/csv_write.lani) emits the
shared canonical encoding: every field is quoted, embedded quotes are doubled
and each record ends in CRLF. Its fixed stack scratch space holds 1,024 logical
byte elements and feeds the borrowed `core::io::Write`; no per-record encoded
allocation is needed. Native fixed arrays can use word-sized slots, so those
element counts are not exact physical stack-byte sizes. Both
constructed-record and decoder buffers retain capacity for later records.

## Bounds

| Option | Default | Maximum |
| --- | --- | --- |
| `--max-input N` | 16 MiB raw input bytes | 1 GiB |
| `--max-output N` | 32 MiB encoded output bytes | 1 GiB |
| `--max-records N` | 100,000 records | 1,000,000 |
| `--max-fields N` | 256 fields | 4,096; minimum 1 |
| `--max-field-bytes N` | 65,536 decoded bytes | 16 MiB |
| `--max-record-bytes N` | 1 MiB decoded bytes | 16 MiB |
| `--max-work N` | 268,435,456 work units | `i32::MAX` |
| `--max-read-calls N` | 65,536 attempts | `i32::MAX` |
| `--max-write-calls N` | 65,536 attempts | `i32::MAX` |

Values are unsigned decimal integers. Zero is accepted except for the field
bound. Signs, missing values and overflow fail. Options may precede or follow
the column list, with separate or `=` values; the last occurrence wins.
Argument capture permits 48 arguments and 16,384 bytes.

Field and decoded-record byte limits apply to both the source and transformed
record. Selecting a column repeatedly can therefore exceed the output-record
bound even when the source fits. These limits count decoded UTF-8 bytes,
including embedded quoted CR/LF and decoded quotes. Source punctuation and
record separators count toward the separate raw input cap. Canonical quotes,
commas and CRLF count toward the aggregate output cap.

At the exact input cap, a one-byte read probes for EOF. Empty input with a zero
cap succeeds if that probe reports EOF. An extra byte fails the cap; it is not
fed to the decoder or emitted. A pending final record is emitted only after
EOF has actually been established. Already completed records can precede a
failed probe.

Read and write budgets are cumulative for the entire transform, not reset for
each record. Every attempted call, including an Interrupted result, spends one
unit. Short successful reads and writes advance by their confirmed count.
Only Interrupted is retried; WouldBlock and other host errors fail. Zero
progress from a nonempty write and negative or excessive successful counts
fail explicitly. Nonempty successful output receives a final explicit flush;
each flush attempt also spends the same write-call budget. Empty output makes
no write or flush call.

The logical work model precharges before the corresponding operation:

| Operation | Charge |
| --- | --- |
| Decoder feed | 1 plus offered input bytes; refund unconsumed bytes after success |
| Explicit EOF | 1 |
| Each selected field append | 16 plus 6 times the field's decoded byte count |
| Whole-row writer preflight and emission | 8 times decoded row bytes, plus 16 times field count, plus 8 |

Feeds are shortened to fit remaining work. The selected-field allowance covers
UTF-8/control validation, copying and amortized geometric buffer growth. The
writer allowance covers complete-row preflight, quote handling, emission and
scratch copies without scanning the growing record after every append. This
is a conservative logical budget, not a count of CPU instructions, allocator
internals or elapsed time. Native blocking stdin/stdout calls have no deadline;
call caps limit repeated attempts rather than preempting a blocked syscall.

Storage is proportional to the largest source record, largest projected
record and their field counts, plus the selected-index vector and fixed
scratch buffers. Capacity grows geometrically and is retained. These are
logical bounds, not an exact allocator quota or a whole-process memory limit.

## Publication, errors and ownership

This is a streaming filter: stdout can already contain earlier records when a
later record fails parsing, width, selection or resource checks. There is no
output rollback. For each record, the shared writer validates the complete
record and checks the remaining aggregate output cap before its first write.
An output-byte preflight failure emits none of that record. A write or
write-call failure can leave a confirmed prefix inside a record, possibly
inside a UTF-8 sequence or escaped quote. Final flush happens after complete
records have been accepted; a flush failure can still leave buffered bytes
undelivered to an underlying sink.

`--report` emits these confirmed counters after processing and cleanup:

- `input`: bytes accepted from stdin, including an over-limit probe byte when
  one was read; `consumed`: bytes accepted by the decoder.
- `output`: bytes accepted by successful stdout writes; `rows`: records whose
  complete encoding was accepted. These counters do not imply durable storage.
- `read-calls`, `write-calls` and `work`: cumulative charged operations.
- `decoder-bytes`, `decoder-fields`, `record-bytes`, `record-fields`: retained
  capacities immediately before the owners were freed.

A final flush or later parse failure can occur after all displayed rows have
been accepted. Startup allocation/argument failures can occur before a report
exists. Stats and diagnostics each have an independent eight-attempt stderr
write budget; diagnostics preserve the original failure status if stderr
itself fails. A report failure after an otherwise successful transform is an
I/O failure. The app explicitly ignores SIGPIPE so broken pipes return through
its bounded I/O handling.

Decoder, constructed Record, selected-index vector and argument snapshot each
have one active manual owner and are destroyed on every applicable exit. Field
views never outlive a decoder feed/reset/destroy or constructed-record change.
Stdin and stdout descriptors are borrowed. The writer retains neither the
record nor its scratch view after returning.

| Exit | Meaning |
| --- | --- |
| 0 | Complete transform and final flush/report, or help |
| 2 | Invalid columns/arguments, CSV/UTF-8 error, missing column or resource cap |
| 3 | Read/write/flush/report/SIGPIPE setup failure or invalid I/O count |
| 4 | Allocation failure |

## Focused execution checks

[`tests/extended_csv_rewrite_execution.rs`](../tests/extended_csv_rewrite_execution.rs)
compiles the real application and appends a scripted entry to the same
production helpers. Python's standard CSV reader/writer independently computes
selected/reordered output for representative and generated inputs. The suite
also checks exact/zero caps, UTF-8/control and late-record failures, real short
file writes, broken pipes, `/dev/full`, interrupted/error syscalls and every
successful baseline allocation denied in turn.

All five groups passed on Linux x86_64. Their counters total 182
application/consumer process cases:

| Group | Cases | Accepted scope |
| --- | --- | --- |
| Python CSV matrix | 62 | Fourteen representative inputs and 48 generated transforms; selection/reordering/duplicates, empty and blank records, quoted commas/quotes/CR/LF, UTF-8 and input-chunk boundaries |
| Limits and errors | 88 | Exact/zero input/output/record/field/work/call caps, aggregate partial-output counts, malformed CSV/UTF-8/controls, late width errors, missing columns and argument validation |
| Real I/O | 11 | Kernel short file writes at 1/1,031/2,049-byte limits, `/dev/full`, a broken pipe, interrupted/error reads and writes, and persistent Interrupted budgets |
| Resources | 20 | Baseline allocation tracing, each baseline allocation denied in turn, complete cleanup/prefix checks, and one-row versus 4,096-row reuse measurements |
| Scripted production helpers | 1 process | 140 read/write chunk schedules, 13 I/O/flush failure modes and three EOF/input-boundary scenarios inside that process |

The scripted process invokes the actual appended production helpers 156 times;
these are internal scenarios, not 156 independent native runs. The native
executable validator checks generated function boundaries before the driver
executes either entry.

The gates have distinct local receipts:

- `target/stdlib-work/csv-rewrite-matrix-typed.log`: 62 matrix cases, 7.26 seconds.
- `target/stdlib-work/csv-rewrite-limits-io-scripted.log`: 88 limits, 11 real-I/O
  cases and the scripted consumer, 9.42 seconds for those three groups.
- `target/stdlib-work/csv-rewrite-resources.log`: 20 resource scenarios,
  8.11 seconds for that group.

The same-shape 4,096-row workload and its one-row control each made 16
allocations, with a peak of 1,558 requested allocation bytes and 32,768 bytes
of page-rounded mappings. Retained decoder/constructed-record capacities also
matched. Every successful allocation was freed. These are traced allocation
requests and mappings, not process RSS or total memory; executable and stack
space are outside the measurement.

The recorded 4,096-row check took 0.999 seconds, including process startup,
`strace`, captured output and Python's comparison. This is one moderate traced
workload, not a general throughput claim or a measurement of native compute
time alone. The results cover the selected finite cases; GPU-kernel execution
and other host targets have not been established.

```sh
timeout --kill-after=2s 110s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test extended_csv_rewrite_execution -- --nocapture --test-threads=1
```
