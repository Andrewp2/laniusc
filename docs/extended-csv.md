# CSV tables

`ext::csv` parses an owned UTF-8 String into independently owned fields and
encodes a parsed table as canonical CSV. Import it through the `extended`
source root; see [extended/README.md](../extended/README.md).

## Dialect

The quoting and record grammar follow [RFC 4180](https://www.rfc-editor.org/rfc/rfc4180).
This module accepts UTF-8 and, by default, LF record separators as well as CRLF.

- Commas separate fields. Spaces remain part of a field.
- A quoted field may contain commas and CR/LF. Two quotes represent one quote.
- Quotes may only open at the start of a field. After a closing quote, only
  another quote, a separator, or the end of input is valid.
- Bare CR outside a quoted field is invalid. Set `allow_lf = false` to require
  CRLF record separators. CR and LF inside quoted fields remain unchanged.
- Other ASCII controls, including TAB and NUL, and DEL are rejected. Non-ASCII
  Unicode scalars are accepted. There is no BOM removal or normalization.
- Empty input gives zero rows. A blank record gives one empty field. A trailing
  comma adds an empty field; a trailing record separator adds no extra row.
- Headers have no special meaning. The default requires every row to have the
  same number of fields; `require_same_width = false` permits varying widths.

The encoder quotes every field, doubles embedded quotes, and ends every record
with CRLF. The empty table encodes as an empty String. Re-encoding canonical
output is idempotent. The original choice of quoting and line endings is not
preserved.

## API and ownership

| Operation | Result |
| --- | --- |
| `default_options()` | LF allowed, uniform row width required, limits set to `i32::MAX` |
| `parse(input, options)` | `Result<Table, Error>`; borrows input and copies its fields |
| `Table.row_count()` | Number of records |
| `Table.field_count(row)` | `Option<i32>`; None for a negative or missing row |
| `Table.field(row, column)` | `Result<Text, Error>`; borrowed field without copying |
| `Table.try_field(row, column)` | `Result<String, Error>`; independent owned copy |
| `Table.destroy()` | Deeply frees fields and rows, resetting this owner to an empty table |
| `encode(table)` | `Result<String, Error>`; independent owned output, preserving table |

Borrowed fields remain valid while the table is alive and unchanged. They use
[core::text::Text](stdlib-text.md); no field allocation or revalidation occurs.
Destroy returned Strings separately. `parse` never destroys or mutates its
input. A plain Table copy aliases the same allocation tree; maintain one active
owner. Destruction invalidates copies of the old handle. Destroying the same
reset owner again is harmless. These are manual ownership conventions, not
compiler-enforced guarantees.

Parsing, encoding and field copying return explicit allocation failures. Failed
operations release their partial results and preserve the source owner.

## Limits and errors

Options bound records (`max_records`), fields per record (`max_fields`), and
decoded bytes per field (`max_field_bytes`). Records and bytes may be zero;
fields must be at least one. Negative limits and zero fields produce
`InvalidOptions`. Quotes used for syntax do not count toward a field's byte
limit. Limits are checked while parsing; they do not bound the caller's input
allocation or total process memory.

| Error | Meaning |
| --- | --- |
| `InvalidOptions` | Invalid configured limits |
| `UnexpectedQuote(offset)` | Quote inside an unquoted field |
| `UnclosedQuote(offset)` | Opening quote of an unfinished field |
| `TrailingText(offset)` | Unexpected byte after a closing quote |
| `InvalidLineEnding(offset)` | Bare CR or disallowed LF separator |
| `InvalidCharacter(offset)` | Disallowed control byte |
| `UnequalFields(row)` | Zero-based row with a different width |
| `LimitExceeded(offset)` | Byte position where a configured limit was exceeded |
| `AllocationFailed` | Storage could not be obtained |
| `Bounds` | Field-copy request outside the table |

Offsets are zero-based input byte positions. An EOF limit check may report the
input byte length. Input must satisfy String's valid UTF-8 invariant; a caller
must not mutate its borrowed bytes to break that invariant.

## Execution evidence

On 2026-10-22, all three tests in `tests/extended_csv_execution.rs` passed in
8.48 seconds on x86_64 Linux, using the GPU compiler built from `441e66f9` plus
the library changes on `codex/stdlib`.

- The contract fixture checks table queries, independent field ownership,
  destruction, limits, CRLF-only parsing, and optional varying row widths.
- The stdin/stdout program checks 14 valid and eight malformed inputs, including
  quoting, empty fields, multiline fields, Unicode and invalid controls.
- Forty-eight deterministic generated tables vary field spelling, separators
  and final terminators. Both the varied input and canonical output are executed
  and compared with output derived from the logical fields.
- Allocation tests fail each allocation after input construction in a
  parse/encode/copy workflow. They check explicit errors, preserved input,
  independent field lifetime, and syscall traces for leaked or duplicate frees.

Run from the repository root with `strace` installed:

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" \
  CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test extended_csv_execution -- --nocapture
```

`sample_programs/csv_normalize.lani` reads UTF-8 CSV from stdin and writes
canonical CSV to stdout. Exit status is zero on success, two for invalid input,
three for I/O failure, and four for allocation failure. Output may be partial
when a write fails.

The program now uses the shared [byte stream APIs](stdlib-streams.md) for bulk
input and complete output writes. Its normalizer suite also injects allocation
failures in input buffering, UTF-8 construction and parsing, checking status,
diagnostics and cleanup. This integration suite passed on 2026-10-22 in 6.14
seconds.

The implementation currently materializes the entire input, table and encoded
output. Streaming parsing/writing, constructing or editing rows, header-based
access, and table transformations remain future work. Wasm and user-program
GPU execution have not been established. The GPU is used to compile the tested
native programs.

The borrowed-field integration passed all three CSV test groups in 11.64
seconds on 2026-10-22, including negative/missing rows and columns and independent
owned copies. Streaming CSV remains unfinished.
