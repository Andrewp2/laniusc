# Constructing and writing CSV records

`ext::csv::new` creates a reusable owned record. `ext::csv_write` writes its
canonical bytes directly to a `core::io::Write` implementation using one fixed
1,024-element byte buffer on the stack. It creates no encoded String, allocates no outer
storage, and does not flush or close the borrowed writer.

All five focused construction/writer groups pass with the GPU compiler and
native **Linux x86_64** execution. The three existing CSV table/normalizer
regression groups also pass with the shared encoder. Other platforms and
GPU-kernel execution have not been established.

## Dialect and canonical bytes

This API retains the [existing CSV dialect](extended-csv.md). Its quoting and
record grammar follow [RFC 4180 section 2](https://www.rfc-editor.org/rfc/rfc4180.html#section-2),
which permits optional quoting. This library's canonical profile quotes every
field, doubles each embedded quote, places commas only between fields,
and terminates each nonempty record with CRLF. Spaces, commas, quotes and CR/LF
inside fields remain data. UTF-8 scalars, including BOM and noncharacters, are
preserved without normalization. NUL, TAB, other ASCII controls except CR/LF,
and DEL are rejected. This is the established strict dialect; NUL is valid
UTF-8 text but is not a valid field here.

Zero fields represent no record and encode to zero bytes. One empty field is
a record and encodes to the four bytes `""\r\n`. Two empty fields encode to
`"",""\r\n`. Empty input and a blank CSV record therefore remain distinct.

The materializing `csv::encode_record` and `csv::encode` APIs use the same
canonical byte cursor as the stream writer. They continue returning owned
Strings. The stream writer can split a UTF-8 scalar, doubled quote or CRLF
across write calls; the concatenated byte sequence is valid canonical UTF-8 CSV.

## Record construction

```text
csv::new() -> Record
Record.borrow() -> &Record
Record.try_push_field(text: core::text::Text) -> Result<i32, csv::Error>
Record.field_count() -> i32
Record.byte_len() -> i32
Record.byte_capacity() -> i32
Record.field_capacity() -> i32
Record.field(index: i32) -> Result<Text, csv::Error>
Record.clear()
Record.destroy()
Record.encoded_len() -> Result<u64, csv::Error>
```

Construction is allocation free. Each successful append returns the new field
count and copies the supplied field into the record's packed UTF-8 bytes. The
input Text remains borrowed only for the call. Its logical metadata and UTF-8
are validated again, including Text assembled through public fields or an
unchecked constructor. Then the CSV control-byte policy is checked.
`InvalidUtf8(offset)` and `InvalidCharacter(offset)` from append identify bytes
relative to the supplied Text, starting at zero. Invalid logical ranges return
`Bounds`. Physical backing must cover the claimed range; the compiler does not
prove that precondition.

An append error preserves the complete record, byte/field lengths, both
capacities and all existing views. The implementation reserves any required
byte and span growth in separate staged vectors before changing either owner.
If the second reservation fails, it releases the first stage. After all
reservations succeed, appending cannot allocate; it commits both descriptors
only after copying the incoming field. A Text borrowed from one of this
record's own fields is supported, including when both vectors must grow.

Growth is geometric. Appending scans only the new Text for UTF-8 and controls,
copies that Text, and copies existing bytes/spans when their respective buffer
grows. This gives amortized linear construction for a growing record, with
temporary old-plus-new storage during a growth. Preserving both capacities on
failure requires this staging. A successful append can invalidate old views;
do not use the alias passed into a self-append afterward.

`clear` removes all fields and bytes while retaining both capacities. Rebuilding
records within those capacities allocates nothing. `destroy` frees both buffers
and resets the actual owner; repeated destruction is harmless. Keep one active
manual owner: copying a Record descriptor aliases storage and does not clone
it. End every field, encoding cursor and inactive copy before mutation or
destruction. The language does not enforce these ownership rules.

The constructor has storage/capacity bounds rather than decoder `Options`.
Callers impose their own field-count and decoded-byte limits before appending.
An allocation or capacity failure returns the existing `csv::Error` variant.
The decoder, table API and ordinary shallow Record behavior remain unchanged.

## Preflight and borrowed encoding cursor

```text
Record.encoding() -> Result<csv::Encoding, csv::Error>
Encoding.borrow() -> &Encoding
Encoding.remaining() -> u64
Encoding.next() -> Option<u8>
```

`encoded_len` allocates nothing. It checks nonnegative vector lengths and
capacities, lengths within capacity, contiguous nonoverlapping field spans,
span bounds and complete coverage of the packed byte buffer. It validates
every field's UTF-8 and control-byte policy, counts quoting and CRLF, and checks
encoded-length arithmetic. Errors from this whole-record preflight use packed
record byte offsets rather than per-input-Text offsets. A zero-field record
must also have zero packed bytes.

`encoding` performs that same preflight and returns a borrowed byte cursor.
`remaining` includes all syntax bytes. `next` returns canonical bytes and stays
exhausted after its last byte; cursor copies advance independently. Keep the
source record alive and unchanged for their complete use. A cursor is not an
owner and must never destroy its stored Record descriptor.

The vector storage pointers and physical allocations must still obey the
ordinary Vec/Record ownership invariants. Logical checks do not validate
arbitrary forged pointers or prove physical backing. Do not modify public
storage descriptors, spans, cursor state or packed bytes. The malformed metadata
tests restore deliberate corruption before owner cleanup.

## Stream writer and progress

```text
csv_write::Limits { max_output: u64, max_write_calls: u64 }
csv_write::default_limits() -> Limits
csv_write::Progress { written: u64, write_calls: u64 }
csv_write::Cause = Csv(csv::Error) | OutputLimit | CallLimit | Io(core::io::Error)
csv_write::Failure { cause, written: u64, write_calls: u64 }

csv_write::write_record<W>(writer: &W, record: &csv::Record, limits: Limits)
    -> Result<Progress, Failure> where W: core::io::Write
```

Defaults are 16 MiB encoded output and 65,536 write attempts per call. Unsigned
zero limits are valid. Preflight validates the **complete** record, computes
its canonical length and applies `max_output` before the first writer call.
CSV validation and output-limit failures report `written = 0`, `write_calls = 0`.
An empty Record succeeds with those same zero counts even when both limits are
zero.

The call budget is enforced as writes occur. Every attempted `write`, including
Interrupted and failed calls, consumes one attempt. Short successes continue
with the first unaccepted scratch byte. Interrupted retries within the budget;
WouldBlock and other errors return immediately. No busy retry loop is hidden.
Budget exhaustion can leave a confirmed prefix of the current record. The
function never calls `flush`; the caller decides when to drain buffering,
synchronize storage or close the writer.

`written` counts the exact prefix accepted by successful, valid write counts.
For an `Err`, `core::io::Write` requires that attempt to accept zero bytes. A
zero successful count becomes `Io(WriteZero)`; a negative or excessive count
becomes `Io(InvalidCount)`. An invalid count violates the writer contract, so
the failure reports only the prefix confirmed before that bad attempt; further
actual sink effects cannot be inferred. Successful return means all canonical
bytes were accepted by the writer, not necessarily delivered or made durable.

The writer and record remain borrowed for the call. Normal writes may update
the sink's own state. No alias may destroy either object or mutate the record
reentrantly through a writer callback. The sink must consume or copy the
borrowed scratch bytes before return and must not retain that view. Preflight
cannot protect against mutation after validation in this manual-borrow model.

The fixed scratch bounds outer stream-encoding storage. Native fixed arrays
can use word slots and strided slices, so 1,024 logical bytes do not promise
exactly 1,024 physical stack bytes. Allocations and
buffering inside the supplied writer remain its own contract. Record and
encoded-byte bounds, write-attempt counters and the linear passes are resource
controls, not elapsed-time or CPU-instruction limits. A blocking write requires
an external deadline policy if wall-clock time matters.

## Example

```text
let row: ext::csv::Record = ext::csv::new();
row.try_push_field(first_text).unwrap();
row.try_push_field(second_text).unwrap();
let progress = ext::csv_write::write_record(writer, row.borrow(), limits);
// Inspect progress or Failure.written before retrying or abandoning output.
row.clear();
// Rebuild the next row using the retained capacities.
row.destroy();
```

Retrying `write_record` starts a new complete record; it does not resume at a
previous failure's byte count. A caller must account for any already accepted
prefix before deciding to retry. Streaming applications can have earlier
complete records committed before a later input or output failure.

## Focused verification

`tests/extended_csv_write_execution.rs` defines five focused groups:

- An independent Python `csv` canonical writer/reader oracle: empty shapes,
  Unicode, noncharacters, quotes, commas, CR/LF, UTF-8 and 1,024-byte boundaries,
  generated fields from a fixed seed, plus rejected controls and malformed UTF-8.
- Every accepted byte boundary of a small record for host, WouldBlock, zero,
  negative/excessive count and repeated Interrupted failures. Exact/exceeded
  output and call caps, short writes, and larger scratch-boundary cases assert
  progress and no implicit flush.
- Malformed Text, spans, packed coverage and vector logical descriptors. A bad
  later field prevents every writer call, including String encoding preflight.
- Every observed constructor growth allocation failed in turn. The checks
  retain old contents, lengths, both capacities and borrowed fields, including
  self-alias append with simultaneous byte/span growth and partial-stage cleanup.
- 4,096 clear/rebuild/write cycles after warm-up, with syscall markers proving
  no intervening mappings/unmappings and a sink confirming no flush calls.

The Rust driver, Python oracle and syscall injector are test machinery.
Production construction, validation, canonical quoting and streaming are Lanius
code. All five groups are accepted through these separate receipts:

| Receipt | Observed result |
| --- | --- |
| `target/stdlib-work/csv-write-canonical-typed.log` | Canonical group passed in 6.49 s: 143 valid and 11 invalid Python-oracle cases |
| `target/stdlib-work/csv-write-other-groups.log` | Three groups passed in a 12.34 s mixed run: all six observed construction allocation positions, malformed metadata, and 4,096 allocation-free reuse/write cycles; the original prefix fixture failed lowering in this run |
| `target/stdlib-work/csv-write-prefix-flat.log` | The equivalent prefix fixture with a flat classifier and explicit local types passed GPU compilation and native execution in 6.74 s |
| `target/stdlib-work/csv-existing-shared-encoder.log` | All three existing CSV table/normalizer regression groups passed in 11.23 s |

The mixed run is not a wholly passing run. Its three accepted groups combine
with the canonical and later prefix receipts to establish the five focused
groups. Prefix coverage retains all 18 byte boundaries of the small record,
six failure behaviors at each boundary, 13 larger scratch-boundary positions,
short-write widths, exact output/call caps and no implicit flush. Independent
review confirmed that the classifier change preserves every error
classification, loop, budget and accepted-prefix assertion.

These are finite cases and the allocation positions reached by the fixed
fixture. They do not prove every writer implementation, source shape, possible
record, allocation schedule or physical backing lifetime. In particular,
contract-violating writer counts cannot establish unreported sink effects, and
logical preflight does not prove memory ownership or prevent reentrant alias
mutation. Timings are observations from this host, not performance guarantees.
No other platform or GPU-kernel execution claim is made.

### Generic write-result context

The stream writer gives its generic `writer.write` result the declared
`Result<i32, core::io::Error>` type explicitly, matching `core::io::write_all`.
The separate minimal controls `generic_inference_untyped.lani` and
`generic_inference_typed.lani` preserve the compiler context dependency:

- The untyped local fails with `LNC0027 CallMismatch` at `attempt.is_err()`;
  receipt: `target/stdlib-work/io-context-untyped.log`.
- The otherwise equivalent typed local compiles and executes with status zero;
  receipts: `target/stdlib-work/io-context-typed.log` and
  `target/stdlib-work/io-context-typed-native.log`.

This is a compiler inference limitation demonstrated by that source shape.
The annotation supplies the existing trait contract; it changes no writer
behavior, budget, error semantics or algorithm.

The original prefix fixture is preserved as `contracts_lowering_original.lani`
with its `flags=0x400` optimization-structure failure in the mixed receipt.
The standalone comparison also confirms the source-shape distinction:

- `nested_literal_lowering.lani` fails compilation with `LNC0057` and lowering
  `flags=0x400`; receipt: `target/stdlib-work/csv-nested-literal.log`.
- `bound_payload_control.lani` compiles and executes with status zero; receipts:
  `target/stdlib-work/csv-bound-payload.log` and
  `target/stdlib-work/csv-bound-payload-native.log`.

The control changes both nested-match structure and literal-versus-bound enum
payload spelling. These receipts establish a distinction between those two
complete source shapes; they do not isolate either feature as the exact cause.

```sh
timeout --kill-after=2s 110s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test extended_csv_write_execution -- --nocapture --test-threads=1
```
