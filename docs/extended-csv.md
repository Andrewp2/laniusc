# CSV records and streams

`ext::csv` decodes UTF-8 CSV incrementally into reusable packed records. The
whole-table API collects records from the same decoder. Import it through the
`extended` source root; see [extended/README.md](../extended/README.md).

## Dialect

The quoting and record grammar follow [RFC 4180](https://www.rfc-editor.org/rfc/rfc4180.html#section-2),
with UTF-8 and optional LF record separators.

- Commas separate fields; spaces remain data. Headers have no special meaning.
- Quotes open only at a field's start. Inside quotes, commas and CR/LF are data;
  doubled quotes decode to one quote. After a closing quote, only another quote,
  a field/record separator or EOF is accepted.
- Bare CR outside quotes is invalid. `allow_lf = false` requires CRLF record
  separators; CR and LF inside quoted fields remain unchanged.
- Other ASCII controls, including TAB and NUL, and DEL are rejected. Non-ASCII
  Unicode scalars, including BOM and noncharacters, are retained. No normalization
  or BOM removal occurs. Malformed UTF-8 is rejected.
- Empty input has zero records. A blank record has one empty field. A trailing
  comma adds an empty field; a trailing record separator adds no extra record.
- By default every record must have the same number of fields. Set
  `require_same_width = false` to permit varying widths.

## Incremental decoding

`decoder(options)` returns `Result<Decoder, Error>` and allocates no storage.
Feed bytes from any source; the decoder has no host I/O dependency. Chunks may
end anywhere, including inside CRLF, a doubled quote or a UTF-8 scalar.

| Operation | Behavior |
| --- | --- |
| `feed(bytes, offset, count)` | `Result<Progress, Error>`; stops after at most one complete record |
| `Progress.consumed` | Number of bytes consumed from this call's range |
| `Progress.record` | True if a new record is ready |
| `finish()` | Explicit EOF; `Result<bool, Error>`, true only if EOF completes a new record |
| `byte_offset()` | Cumulative accepted input bytes as u64 |
| `records_read()` | Number of complete records |
| `has_record()`, `field_count()` | Readiness and optional number of fields |
| `field(index)` | `Result<Text, Error>` borrowing a complete decoded field |
| `take_record()` | `Option<Record>` transferring ownership of the ready record's buffers |
| `byte_capacity()`, `field_capacity()` | Current reusable buffer capacities |
| `reset()` | Clear parsing state, counters, error and EOF; retain buffers and options |
| `destroy()` | Free buffers and reset; the same owner may be reused or destroyed again |
| `borrow()` | Borrow the decoder for a helper that updates its state |

After a successful feed, advance the input position by `consumed`. Process a
ready record before feeding more bytes. If part of a chunk remains, feed that
remainder next. A successful nonempty feed always consumes at least one byte.
An empty feed consumes zero bytes, reports no new record and preserves the
current record; it is **not EOF**. Call `finish` after the source reaches EOF.
Repeated `finish` calls return false and preserve the last record. Nonempty
input after successful EOF returns `Finished` without changing state.

Negative or overflowing logical input ranges return `Bounds` without changing
state. Physical backing must cover the supplied range; overclaiming a native
slice can trap on indexing. Input storage is borrowed only during the call and
can be reused afterwards. It must not alias the decoder's own record buffers.

A valid nonempty feed attempt on an unfinished decoder invalidates the previous
record and its views, even if parsing later fails. `reset` and `destroy` also
invalidate them. Empty feeds, rejected logical ranges and repeated EOF preserve
the current record. After `take_record`, views are instead borrowed from the
returned Record and remain valid while that owner is alive and unchanged.

Parse, limit and allocation errors are sticky: later feed/finish calls return
the same error until reset. Partial records are never exposed. Storage remains
owned by the decoder so reset can reuse it or destroy can release it. On feed
failure, `byte_offset()` identifies the accepted prefix, excluding the failing
byte; a diagnostic offset may point earlier, such as the start of malformed
UTF-8, an opening quote or a pending CR. Errors are reported as encountered;
previous complete records may already have been delivered.

The [CSV report](csv-report.md) is a complete example: it reads 1 KiB chunks,
processes fields directly as Text, and retains group totals rather than a table.
It finishes validation before writing any stdout output.

## Owned records and tables

Each Record owns a packed decoded byte buffer and a vector of field spans.
Fields borrow subranges of those bytes and allocate nothing. Ordinary streaming
keeps both buffers and clears their lengths for the next record. Once capacity
is sufficient, subsequent records of the same or smaller shape allocate nothing.

`Record` provides `field_count`, `byte_len`, `byte_capacity`, `field_capacity`,
`field(index)`, `try_field(index)`, `clear` and `destroy`. `try_field` makes an
independent owned String. `clear` removes all fields while retaining capacity;
a cleared Record represents no record and encodes to empty output. A parsed
blank record instead contains one empty field and encodes as `""\r\n`.

| Whole-input operation | Result |
| --- | --- |
| `parse(input: String, options)` | `Result<Table, Error>`; borrows input, owns decoded records |
| `parse_bytes(bytes, offset, count, options)` | Same parser, including UTF-8 validation, without constructing a String |
| `Table.row_count()` | Number of records |
| `Table.field_count(row)` | `Option<i32>`; None for a negative or missing row |
| `Table.field(row, column)` | `Result<Text, Error>`; borrowed field |
| `Table.try_field(row, column)` | `Result<String, Error>`; independent owned copy |
| `Table.destroy()` | Free records and reset this owner to an empty table |
| `encode_record(record)` | `Result<String, Error>`; canonical encoding of one record |
| `encode(table)` | `Result<String, Error>`; canonical encoding of all records |

Encoding quotes every field, doubles embedded quotes and terminates each record
with CRLF. It does not preserve source spelling. Encoding and field copying
preserve their source on failure and release partial output. Output capacity
limits are reported explicitly. The encoder uses one record-encoding routine
for both APIs; it currently materializes the returned String.

Record, Table and Decoder are manually owned values. Copying their handles does
not clone storage. Maintain one active owner and destroy it once; copies of a
previous owner must not be reused. Borrowed fields require their owner to remain
alive and unchanged. The compiler does not enforce these lifetime rules.

## Limits and errors

`default_options` allows LF, requires uniform width and sets all limits to
i32::MAX. The limits are `max_records`, `max_fields` per record,
`max_field_bytes`, and `max_record_bytes` across all fields in one record.
Records and byte limits may be zero; fields must be at least one. Negative
limits or zero fields produce `InvalidOptions`.

Byte limits count decoded UTF-8 bytes. Separator/quoting syntax does not count;
quoted CR/LF and decoded quotes do. Limits are checked during parsing. Buffer
capacities grow geometrically and remain after reset, so these are logical data
limits rather than exact bounds on allocated bytes. Streaming storage is
O(largest record bytes + largest field count); the table API additionally
retains all collected records.

| Error | Meaning |
| --- | --- |
| `InvalidOptions` | Invalid configured limits |
| `UnexpectedQuote(offset)` | Quote inside an unquoted field |
| `UnclosedQuote(offset)` | Opening quote of an unfinished field |
| `TrailingText(offset)` | Unexpected byte after a closing quote |
| `InvalidLineEnding(offset)` | Bare CR or disallowed LF separator |
| `InvalidCharacter(offset)` | Disallowed control byte |
| `InvalidUtf8(offset)` | Malformed or incomplete UTF-8 sequence's starting byte |
| `UnequalFields(row)` | Zero-based record with a different width |
| `LimitExceeded(offset)` | Position where a configured limit is detected |
| `AllocationFailed` | Storage could not be obtained within allocator/vector limits |
| `CapacityOverflow` | Encoded output exceeds the String capacity range |
| `OffsetOverflow` | The cumulative input byte counter cannot advance |
| `Bounds` | Invalid logical feed/parse range or missing row/field |
| `NoRecord` | Decoder field access before a complete record is available |
| `Finished` | Nonempty feed after successful EOF |

Byte-position payloads are now u64; `UnequalFields` keeps an i32 record index.
Positions start at zero for the selected input, independent of the supplied
source-slice offset. EOF checks can report the input length. Consumers must be
rebuilt for the new Error payloads, Options field and packed Record layout.
The compiler and its ABI implementation were not changed for this library work.

## Execution evidence

On 2026-10-22, native x86_64 Linux binaries produced by the GPU compiler passed:

- All three groups in `tests/extended_csv_stream_execution.rs` (13.94 seconds):
  every split point and bytewise feeds for representative grammar/UTF-8 cases,
  48 generated logical tables with varied chunk schedules, exact errors and
  completed-record prefixes, EOF and empty-feed behavior, persistent errors,
  invalid logical ranges, reset, ownership transfer and independent field copies.
- A 4,096-record fixture retained capacities and made **no allocations after
  warm-up**, verified by syscall trace. All successful allocations were freed.
- Every allocation in a growing streaming decoder was failed in turn; fixtures
  checked error persistence, reset/capacity behavior and complete cleanup.
- The existing three CSV table/normalizer groups (11.12 seconds), including
  generated tables, malformed input, limits and allocation fault injection.
- Both report groups (8.49 seconds), including 4,096 generated records,
  allocation failures, interrupted/failed reads and writes, and partial output.

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test extended_csv_stream_execution -- --nocapture
```

The whole-table `csv_normalize.lani` sample remains useful for that API and
still buffers its input/output. The report uses incremental input. Generic
streaming writers, record construction/editing, header-based access and table
transformations remain work. GPU execution of user programs, Wasm and other
host targets have not been established; GPU compilation alone does not establish
them. Tests do not attempt to process 2^64 bytes to exercise counter exhaustion.
