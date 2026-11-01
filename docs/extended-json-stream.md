# Streaming JSON tokens and writer

`ext::json_stream` reads JSON as a stream of tokens without building a
document, and writes JSON token by token. It complements the owned DOM in
[`ext::json`](extended-json.md): the DOM parses a whole `String`, while the
tokenizer accepts raw bytes in chunks of any size and validates UTF-8 itself.
Import it through the `extended` source root.

Two sample programs use it: [`jq_lite`](../sample_programs/jq_lite.lani), a
streaming path query, and [`csv_to_json`](../sample_programs/csv_to_json.lani),
which converts CSV to JSON. Both read stdin. Both are checked against Python's
`json` and `csv` modules (see [Execution evidence](#execution-evidence)).

## Format policy

The grammar is [RFC 8259](https://www.rfc-editor.org/rfc/rfc8259.html) with
the same strict choices as `ext::json`:

- The input is bytes and must be UTF-8. Malformed, overlong, surrogate-encoded
  (`ED A0 80`) or truncated sequences are `InvalidUtf8` at the sequence's first
  byte. Bytes at or above 0x80 outside a string are `UnexpectedByte`.
- Scalar roots are accepted. Exactly one root value is allowed. Whitespace is
  space, TAB, LF and CR only. A BOM, comments, trailing commas, `NaN`,
  `Infinity`, single quotes and trailing content are rejected.
- Escapes decode to UTF-8. A `\uD800`–`\uDBFF` escape must be followed
  immediately by a `\uDC00`–`\uDFFF` escape. A lone or reversed surrogate is
  `InvalidSurrogate` at the backslash of the first escape. Unescaped control
  bytes below 0x20 in a string are `ControlCharacter`. DEL and noncharacters
  are kept.
- Numbers must follow the RFC grammar. Leading zeros, `+1`, `.5`, `1.` and
  `1e` are `InvalidNumber` at the number's first byte. The token keeps the
  exact source spelling. Nothing is rounded, and a huge exponent such as
  `1e999999999` is accepted. For exact integer conversion, build a DOM with
  `ext::json` and use `integer_i64`/`integer_u64`.
- Duplicate object keys are delivered in order. The tokenizer checks only the
  grammar, so it does not detect duplicates.

## Tokenizer

```text
json_stream::tokenizer(options: Options) -> Result<Tokenizer, Error>
Tokenizer.feed(bytes: [u8], start: i32, count: i32) -> Result<Progress, Error>
Tokenizer.advance(bytes, start, count) -> i32   // feed() without the Result
Tokenizer.last_error() -> Error
Tokenizer.finish() -> Result<bool, Error>
Tokenizer.token() -> Option<Token>
Tokenizer.text() -> Result<Text, Error>
Tokenizer.boolean() -> Result<bool, Error>
Tokenizer.token_offset() -> u64      // first byte of the ready token
Tokenizer.depth() -> i32             // container depth after the token
Tokenizer.byte_offset() -> u64       // bytes consumed so far
Tokenizer.tokens_read() -> u64
Tokenizer.has_token(), is_complete(), reset(), destroy(), borrow()
```

`Token` is `BeginObject`, `EndObject`, `BeginArray`, `EndArray`, `Key`,
`Text`, `Number`, `Boolean` or `Null`. `text()` returns the decoded UTF-8 of a
key or string, or the exact spelling of a number. The view borrows the
tokenizer's buffer and stays valid until the next nonempty feed, `reset` or
`destroy`.

`feed` stops after at most one token. `Progress.consumed` counts the bytes
used from this call's range; feed the rest next. A number has no closing
character. It ends at the byte after it, and that byte is not consumed, so
`consumed` can be zero while `Progress.token` is true. A token's bytes can be
split across any number of feeds, including inside an escape, a surrogate pair
or a multibyte UTF-8 sequence. An empty feed is not EOF and changes nothing.
After the source ends, call `finish`. It returns true only when EOF completes
a root number, which is then the ready token. Repeated `finish` returns false.
Nonempty input after a successful `finish` is `Finished`.

`advance` is `feed` without the `Result`: it returns the bytes consumed and
`has_token()` tells whether a token is ready, or it returns -1 where `feed`
returns `Err`, and that error is `last_error()`.

The tokenizer keeps its token text and container stack in cached slices that
grow geometrically, and takes whitespace between tokens, string bodies
(no quote, backslash or control byte; complete valid UTF-8) and number digit
runs in one step each. Bytes that could change state, fail or reach a limit
still go one at a time, so tokens, offsets and errors are unchanged. On a
7.4 MB array of 100,000 four-key records, tokenizing alone went from 0.87 s
to 0.54 s (1.02 s to 0.67 s for the 12.3 MB indented form), and `jq_lite .`
from 1.24 s to 0.67 s (minimum of 3 interleaved runs, 2026-11-01).

Errors are sticky until `reset`, and partial tokens are never exposed.
Earlier tokens may already have been delivered, so a consumer that must not
act on invalid input should finish validation before publishing. Both sample
programs buffer their output for this reason. Storage is the token-text buffer
plus one byte per open container. Both grow geometrically and are kept by
`reset`. There is no recursion.

| Option | Default | Error |
| --- | ---: | --- |
| `max_depth` | 128 | `DepthLimit` at the opening bracket |
| `max_string_bytes` (decoded, per key or string) | 16,777,216 | `StringLimit` at the opening quote |
| `max_number_bytes` | 1,048,576 | `NumberLimit` at the number start |

Negative limits are `InvalidOptions`. `Error { kind, offset }` carries a u64
byte offset from the start of the stream. EOF errors (`UnexpectedEnd`) report
the stream length. `kind_name(kind)` returns the variant name as Text, for
diagnostics. The kinds are UnexpectedByte, UnexpectedEnd, InvalidUtf8,
ControlCharacter, InvalidEscape, InvalidSurrogate, InvalidNumber,
TrailingInput, the three limits, AllocationFailed, Bounds (an invalid feed
range or an accessor with no matching token), Finished and OffsetOverflow.
The writer adds OutputLimit and InvalidPlacement.

## Reading from `core::io::Read`

```text
json_stream::token_reader<R>(reader: &R, tokens: &Tokenizer, scratch: View<u8>)
    -> Result<TokenReader<R>, Error>          // R: core::io::Read
TokenReader.next() -> Result<bool, StreamError>
TokenReader.advance() -> i32        // 1 token, 0 end, -1 failed
TokenReader.last_error() -> StreamError
TokenReader.read_calls() -> u64
StreamError = Json(Error) | Io(core::io::Error)
```

`advance` is `next` without the `Result`: 1 for `Ok(true)`, 0 for
`Ok(false)`, and -1 for `Err`, whose error is `last_error()`. `jq_lite` uses it.

`next` feeds buffered bytes and reads more into the caller's scratch as
needed. `Ok(true)` means the borrowed tokenizer holds a ready token, which you
query with `token()`/`text()` as usual. `Ok(false)` means the source reached
EOF and `finish` validated the document. Later calls keep returning false.
Interrupted reads are retried. Any other read error is returned as `Io`, and
the buffered bytes stay in place. A reported count outside the scratch range
is `Io(InvalidCount)`. Scratch of any positive size works; the tests use 7
bytes and 1 KiB. Nothing is allocated beyond the tokenizer's own buffers. The
reader, tokenizer and scratch are borrowed, so keep them alive and
unshared while driving the reader.

## Writer

```text
json_stream::writer(max_depth: i32, max_output_bytes: i32) -> Result<Writer, Error>
Writer.begin_object(), end_object(), begin_array(), end_array()
Writer.key(text), string(text), number(text), boolean(value), null()
Writer.number_unchecked(text)     // number() without the grammar check
Writer.token(&Tokenizer)          // copy the ready token
Writer.fast_begin_object(), fast_end_object(), fast_begin_array(), fast_end_array() -> bool
Writer.fast_key(bytes, start, length), fast_string(...), fast_number_unchecked(...) -> bool
Writer.fast_null(), fast_boolean(value) -> bool, fast_f64(value: f64, scratch: View<u32>) -> bool
Writer.next_document()            // JSON Lines: LF, then accept another root
Writer.output() -> View<u8>, output_text() -> Text, len(), depth(), is_complete()
Writer.flush_to<W>(sink: &W) -> Result<i32, core::io::Failure>   // W: core::io::Write
Writer.clear(), destroy(), borrow()
```

Every method returns `Result<i32, Error>` with the new output length. The
writer adds commas and colons itself and tracks structure. A value where a key
is required, a second root, or a mismatched close is `InvalidPlacement`, and
the output is left unchanged. `key` and `string` check that their Text is
valid UTF-8. `number` requires one complete RFC 8259 number and keeps its
spelling. An `InvalidNumber` offset is relative to that Text. If
`max_output_bytes` or an allocation failure stops a write partway, the output
is truncated back to its previous length and the call returns `OutputLimit`
or `AllocationFailed`.

`number_unchecked` writes its Text as given. Use it only for text that is
already one RFC 8259 number, such as decimal digits or the shortest spelling
of a finite float.

The `fast_` methods are for hot loops. Each one takes the common path of the
method with the same name and returns a bool instead of a `Result`. `true`
means the token was written exactly as the `Result` method would have written
it. `false` means nothing was written: call the `Result` method from the same
state to get its outcome. That call may still succeed through the general
path, for example when the text needs escapes or UTF-8 checking, or it may
report the error. `fast_key`, `fast_string` and `fast_number_unchecked` take
the bytes directly, so the caller builds no Text. `fast_f64` formats a finite
value straight into the output with
`core::float_decimal::format_f64_into`, so the output is the same as
`number_unchecked` of that spelling. It declines NaN and the infinities,
which have no JSON number, and it needs `core::float_decimal::scratch_len()`
words of scratch. A `Result` return costs about 100 instructions in the
current native code, against about 8 for a bool, so a converter that tries
the fast form first and falls back to the `Result` form gets the same output
and errors at a fraction of the cost.

`key` and `string` whose text needs escapes or holds non-ASCII bytes check it
once, then write the escaped form in one pass into reserved room when the text
is at most 4,096 bytes and six bytes per input byte would still fit. Otherwise
they copy plain runs and escape byte by byte. The output and errors are the
same either way. The writer already appends into a cached output slice that
grows geometrically, and keeps open containers in a cached slice.

`flush_to` writes the buffered bytes with `core::io::write_all` and drops
them. Structure state is kept, so a document of any size can stream through a
bounded buffer. `max_output_bytes` then limits only the unflushed bytes. On a
write failure, the unwritten suffix stays buffered for a retry.
`Failure.completed` counts the bytes delivered by that call. The writer never
flushes or closes the sink.

The output bytes follow `ext::json` encoding exactly. JSON is compact. Quote
and backslash are escaped. Bytes below 0x20 are written as lowercase
`\u00xx`. Every other scalar keeps its UTF-8 bytes. No BOM or trailing newline
is added. Copying every token of a valid input therefore produces the same
bytes as `ext::json::encode` of the parsed document.

## Sample programs

`jq_lite PATH < input.json` takes a path of the form `.`, `.key`, `[N]` or
`.[N]`, in any sequence. A key is every byte up to the next `.` or `[`. The
program prints every value at that path in compact form, one per line.
Duplicate keys can produce several lines. If nothing matches, including when a
key is applied to an array, it prints `null`. Because the query runs on the
token stream, memory scales with the matched output and the nesting depth, not
the document size. Exit statuses: 0 success, 1 invalid path, 2 invalid JSON
(the message `jq-lite: KIND at OFFSET` goes to stderr), 3 I/O failure, 4 out
of memory.

```sh
printf '{"a":[1,{"b":"x"}]}' | jq_lite '.a[1].b'     # "x"
```

`csv_to_json < input.csv` reads RFC 4180 CSV with the
[`ext::csv` dialect](extended-csv.md): quoted fields, embedded commas,
quotes, CR/LF, and CRLF or LF record separators. The first record is the
header. The output is a JSON array with one object per data record, keys in
header order, values as JSON strings. Duplicate header names stay as
duplicate keys. Empty input and a header with no data records both produce
`[]`. `csv_to_json --csv` instead re-emits the records in the canonical form:
every field quoted, CRLF after each record. Invalid CSV exits 2 with
`csv-to-json: invalid CSV or limit`.

## Execution evidence

On 2026-10-31, the GPU compiler (`target/release/laniusc`) built native
x86_64 Linux binaries for the following runs. The oracles are
[`jq_lite/oracle.py`](../tests/fixtures/stdlib_execution/jq_lite/oracle.py) and
[`csv_to_json/oracle.py`](../tests/fixtures/stdlib_execution/csv_to_json/oracle.py),
registered in `tests/extended_json_stream_execution.rs`.

The JSON reference is Python's `json.loads` with stricter settings: strict
UTF-8 decoding, `parse_constant` rejecting `NaN` and `Infinity`, number
spelling kept through `parse_int`/`parse_float`, ordered key/value pairs, and
rejection of decoded lone surrogates. Python by itself accepts lone surrogates
and `NaN`; this library's policy rejects them. Accepted documents are compared
byte for byte with an independent rendering of the reference value.

| Group | Cases | Agreement |
| --- | ---: | --- |
| suite: hand-written JSONTestSuite-style y_/n_/i_ cases | 272 | 272 (98 accepted, 174 rejected) |
| generated: random documents with varied escapes, numbers, whitespace | 400 | 400 |
| mutations: 1–2 random byte edits of generated documents | 600 | 600 (164 accepted, 436 rejected) |
| paths: random jq-lite paths against Python selection | 300 | 300 |
| chunks: 30 multi-KiB documents, a 33 KB string, a 4 KB number | 32 | 32 |
| errors: exact `kind at offset` from this contract | 30 | 30 |
| bytewise: one byte per feed through tokenizer and writer | 602 | 602 |
| writer: scripted placement, number, UTF-8, depth and limit checks | 1 | 1 |
| stream: `TokenReader` over stdin with 7-byte scratch, `flush_to` every 32 bytes | 572 | 572 |

The bytewise fixture
([`json_stream_contracts.lani`](../tests/fixtures/extended/json_stream_contracts.lani))
also checks that an empty feed is not EOF and that EOF is sticky. Its 30
error cases report the same offsets as the chunked program.

The CSV reference is Python's `csv.reader(strict=True)`. Inputs are written by
`csv.writer` with random minimal or full quoting and CRLF or LF terminators,
and some omit the final terminator. Fields contain commas, quotes, CR, LF,
CRLF, BOM, non-BMP scalars and duplicate headers. The `--csv` output is
compared with `csv.writer(quoting=QUOTE_ALL, lineterminator="\r\n")`.

| Group | Cases | Agreement |
| --- | ---: | --- |
| rfc: hand-written RFC 4180 cases, JSON and `--csv` outputs | 48 | 48 |
| generated: 250 random tables plus one 600-record table, both outputs | 502 | 502 |
| invalid: inputs the dialect rejects | 15 | 15 rejected |

Of the 15 invalid inputs, Python's strict reader also rejects 7: an unclosed
quote, text after a closing quote, and invalid UTF-8. The other 8 are rejected
only by the documented `ext::csv` dialect: unequal widths, a bare quote in an
unquoted field, a bare CR, TAB, NUL, DEL, and a blank record in a two-column
table.

To reproduce, build each program with `laniusc FILE --stdlib-root stdlib
--source-root extended -o OUT`, then run `python3 -I ORACLE GROUP OUT`. The
`cargo test` registration was not run in this session because a cold debug
build of the test harness does not finish within the five-minute command
limit. The same oracle groups were run directly against the
compiler-produced binaries. GPU compilation alone does not show that the
programs run on the GPU, and other hosts are untested.

## Limits of this increment

Both samples now read through `TokenReader` and publish with `flush_to`;
every group above was rerun on those builds. For floating-point values, parse
`text()` with `core::float_decimal::parse_f64`, which is exact and now has a
fast path ([guide](stdlib-float-decimal.md)). Not done yet: duplicate-key
detection in the tokenizer, and jq filters beyond plain paths.
