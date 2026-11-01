# Streaming and deterministic CBOR

`ext::cbor_stream` is a streaming RFC 8949 codec built on the
[`ext::cbor`](extended-cbor.md) event type. It has three parts:

- A push **`Decoder`** that takes input in chunks of any size. It returns each
  event as soon as that item's head, and any string payload, is buffered.
- A buffered **`Writer`** that takes one call per item. Its output can be
  flushed to `core::io::Write` while the document is still being written.
- An **`EventReader`** that pulls input from `core::io::Read`.

Both the decoder and the writer have an optional **core deterministic** mode
(RFC 8949 §4.2.1). Errors are typed and carry `u64` byte offsets. The decoder
also enforces limits on depth, item count, string length and input size.

`ext::cbor` validates a complete buffer before it returns any event, and does
no allocation. This module allocates instead (`alloc::vec`), and can therefore
stream, join chunks and sort keys. Both modules use the same `Event` values,
so an `ext::cbor::Reader` can feed a `Writer`.

The [cbor-to-json sample](../sample_programs/cbor_to_json.lani) converts
standard input to JSON through `EventReader` and the `ext::json_stream`
writer.

Evidence covers native Linux x86_64 executables from the GPU compiler.

## Decoder

```lanius
pub struct Options { max_depth: i32, max_items: u64, max_string_bytes: i32,
                     max_input: u64, deterministic: bool, sequence: bool }
pub fn default_options() -> Options;   // 128, 1000000, 16 MiB, 64 MiB, false, false
pub fn decoder(options: Options) -> Result<Decoder, Error>;

Decoder.feed(source: [u8], start: i32, count: i32) -> Result<i32, Error>;
Decoder.finish();
Decoder.next() -> Result<bool, Error>;
Decoder.advance() -> i32;                // next() without the Result: 1, 0 or -1
Decoder.last_error() -> Error;           // the error after advance() returned -1
Decoder.event() -> ext::cbor::Event;     // valid after next() returned Ok(true)
Decoder.event_offset() -> u64;           // byte offset of the event's head
Decoder.is_complete() -> bool;
Decoder.depth(), byte_offset(), bytes_received(), items_read(), roots_read()
Decoder.reset(); Decoder.destroy();
```

Each `next()` call returns one of three results:

- `Ok(true)`: an event is ready.
- `Ok(false)`: either more input is needed, or `finish()` has been called and
  the input is complete.
- An error. Errors are sticky: every later call returns the same error.

`advance()` is the same step without the `Result`. It returns 1 for
`Ok(true)`, 0 for `Ok(false)` and -1 for an error, which `last_error()` then
returns. A `Result` return costs about 100 instructions in the current
native code, so per-event loops should use `advance()`.

The decoder never consumes part of a head. A truncated head, or a string
whose payload has not fully arrived, waits for more input. After `finish()`,
either case is `UnexpectedEnd` at the item's head.

The event sequence is the same as `ext::cbor::Reader`'s. `End` closes definite
containers and tags, and it is synthesized as soon as the last child
completes. Indefinite items are closed by their break byte.

`Bytes` and `Text` payloads borrow the decoder's buffer. They stay valid until
the next `feed` or `reset`. Consumed input is compacted during `feed`, so
memory is bounded by the largest pending item, not by the document size.

With `sequence` set, the decoder reads an RFC 8742 CBOR sequence: zero or more
complete items in a row. Without it, a byte after the root item is
`TrailingData`.

The checks run in a fixed order. Each one reports at the head offset of the
item it rejects:

1. Reserved additional information 28–30 is `InvalidHead`.
2. A truncated argument is `UnexpectedEnd`.
3. An indefinite length on major type 0, 1 or 6 is `InvalidHead`.
4. A break byte is checked next. At the root, or inside a definite container
   or a tag, it is `UnexpectedBreak`. After a key in an indefinite map, it is
   `OddMap`.
5. In deterministic mode, any indefinite length is `Indefinite`.
6. In deterministic mode, a head longer than needed is `NotPreferred`.
7. A two-byte simple value below 32 is `InvalidSimple`.
8. In deterministic mode, a float that fits exactly in a narrower width is
   `FloatNotShortest`.
9. A wrong chunk inside an indefinite string is `ChunkType`.
10. A string over `max_string_bytes` is `StringLimit`. This is checked before
    waiting for the payload. For an indefinite string, the limit applies to
    the total of its chunks.
11. Exceeding `max_items` is `ItemLimit`. Every head counts except breaks.
12. Invalid UTF-8 in text is `InvalidUtf8`.
13. Opening a container or tag beyond `max_depth` is `DepthLimit`.

In deterministic mode, two more checks run when a map key finishes. A key
that equals the previous key's encoding is `DuplicateKey`. A key that sorts
below the previous one in bytewise lexicographic order (a proper prefix sorts
first) is `UnsortedKeys`. Both report the key's head offset.

Input beyond `max_input` is `InputLimit`. Feeding after `finish()` is
`Finished`.

## EventReader

```lanius
pub fn event_reader<R>(reader: &R, decoder: &Decoder, scratch: View<u8>)
    -> Result<EventReader<R>, Error> where R: core::io::Read;
EventReader.next() -> Result<bool, StreamError>;  // Cbor(Error) or Io(core::io::Error)
EventReader.advance() -> i32;                     // 1 event, 0 EOF and complete, -1 failed
EventReader.last_error() -> StreamError;          // the error after advance() returned -1
EventReader.read_calls() -> u64;
```

`EventReader` borrows the reader, the decoder and the scratch buffer. It reads
into the scratch buffer only when the decoder needs more input. Interrupted
reads are retried. A read of zero bytes calls `finish()`.

## Writer

```lanius
pub struct WriterOptions { max_depth: i32, max_output_bytes: i32, deterministic: bool, sequence: bool }
pub fn default_writer_options() -> WriterOptions;   // 128, 64 MiB, false, false
pub fn writer(options: WriterOptions) -> Result<Writer, Error>;

unsigned(u64), negative(u64) /* -1-n */, integer(i64), simple(u8), boolean(bool),
null(), undefined(), float16(u32), float32(u32), float64(u64),
bytes(View<u8>), text(Text), text_bytes(View<u8>),
begin_array(), begin_array_len(u64), begin_map(), begin_map_len(u64 pairs),
begin_bytes(), begin_text(), tag(u64), end(),
event(ext::cbor::Event)                           // copies a decoder event
output() -> View<u8>, len(), depth(), stable_len(), roots_written(), is_complete()
flush_to<W>(&W) -> Result<i32, core::io::Failure> where W: core::io::Write
clear(), destroy()
```

Integer, length and tag heads always use the shortest form. A tag applies to
the next item and closes after it, so tags need no `end()`. When `event()`
copies a decoder stream, it absorbs the decoder's `End` events for tags.

The writer rejects the following, leaving its output unchanged:

| Error | Cause |
| --- | --- |
| `InvalidPlacement` | A second root without `sequence`, an `end()` at the root, or an `end()` that would close a tag |
| `CountMismatch` | More or fewer children than a declared length |
| `ChunkType` | Anything other than matching chunks inside `begin_bytes()`/`begin_text()` |
| `OddMap` | `end()` after a key with no value |
| `InvalidUtf8` | Text that is not valid UTF-8 |
| `InvalidSimple` | Simple values 24–31 |
| `InvalidValue` | float16 bits above 0xffff |
| `DepthLimit` | Nesting beyond `max_depth` |
| `OutputLimit` | Buffered output beyond `max_output_bytes` |

Error offsets are absolute output byte positions.

In **preserving** mode, the writer keeps what it is given:

- Float widths and bits are kept.
- Unknown-length containers become indefinite (`0x9f`/`0xbf`/`0x5f`/`0x7f`
  … `0xff`), and chunks are kept.
- Map order and duplicate keys are kept.

Re-encoding decoder events therefore reproduces any input whose heads were
already preferred.

In **deterministic** mode, the writer produces core deterministic encoding
whatever it is given:

- `float64` and `float32` narrow to the shortest width that holds the value
  exactly. NaN payloads and signs are kept: the payload is shifted and must
  fit. `1.0` becomes `f93c00`, `100000.0` becomes `fa47c35000`, and the
  default quiet NaN becomes `f97e00`.
- Unknown-length containers and chunked strings get a definite head. The head
  is inserted when they end, and chunks are joined.
- When a map ends, its pairs are sorted by the bytewise order of their encoded
  keys. The sort is a stable merge sort and is skipped when the keys are
  already in order. Keys whose encodings are equal fail with `DuplicateKey`,
  so 1.0 written as float16 and as float64 is a duplicate. This error is
  sticky.

`flush_to` writes the stable prefix of the output and drops it from the
buffer. In deterministic mode, the stable prefix stops at the start of the
outermost open map or unknown-length item, because a later sort or head
insertion can still change those bytes. A large definite array of small maps
therefore streams with bounded memory. On a write failure, the unwritten
bytes stay buffered.

## cbor-to-json

```sh
cbor_to_json [--seq] [--deterministic] < input.cbor > output.json
```

The sample follows RFC 8949 §6.1:

- Integers become JSON numbers, exact through ±2^64.
- Floats are widened exactly to f64 and spelled with the shortest round-trip
  digits from `core::float_decimal`. Infinities and NaN become `null`.
- `false` and `true` stay booleans. `null`, `undefined` and other simple
  values become `null`.
- Byte strings become unpadded base64url strings.
- Tags are dropped in favour of their content.
- Indefinite strings are joined.
- Map keys must be text or integers, looking through tags. Integer keys
  become decimal strings. Any other key stops with `UnsupportedKey` at the
  key's head offset.

`--seq` prints one JSON line per item of a CBOR sequence. `--deterministic`
rejects input that is not core deterministic.

Errors print `cbor-to-json: KIND at OFFSET`. Exit codes: 0 success, 1 usage,
2 invalid or unsupported CBOR, 3 I/O, 4 out of memory. Output streams in
64 KiB blocks, so input that fails late may leave partial output behind.

Limits are depth 512, 16 MiB per string and 64 MiB of input. There is no
limit on item count.

## Oracle

`tests/fixtures/stdlib_execution/cbor_oracle/oracle.py` contains an
independent Python CBOR implementation:

- A recursive decoder that follows the error order above.
- A preserving encoder, which can also write longer heads than needed.
- A core deterministic encoder that narrows floats with `struct` round trips.
- The §6.1 JSON mapping.

The [RFC 8949 Appendix A](https://www.rfc-editor.org/rfc/rfc8949.html#appendix-A)
table is typed into the file by hand, with an expected Python value for each
of its 81 rows.

The batch driver `cbor_oracle/cbor_batch.lani` runs one hex item per line in
three modes, each fed 1, 3, 7 and 4096 bytes at a time:

- `copy`: decode, then preserving re-encode.
- `canon`: decode, then deterministic re-encode.
- `check`: decode in deterministic mode.

For every comparison, the outputs must match exactly, or the error kind and
offset must match.

| Group | Cases | Agreement |
| --- | ---: | --- |
| appendix | 81 | Python decodes every row to its typed value and re-encodes the same bytes. copy, canon and check each agree 324/324. 64 rows are deterministic. The sample converts all 81. |
| generated | 1,500 | Random trees: every major type, full-range arguments, chunked strings, indefinite containers, arbitrary and duplicate keys, all float widths, narrowable floats and NaN payloads, and non-preferred heads on every third item. copy, canon and check each agree 6000/6000. Python decodes all 1,500 Lanius outputs back to the same values (214 have duplicate canonical keys, 949 are already deterministic). |
| mutations | 3,000 | Byte replacements, bit flips, truncations, inserted break and indefinite bytes, and deletions. copy, canon and check each agree 12000/12000, with exact error kind and offset. 2,263 inputs are rejected. |
| limits | 2,400 | Nine depth, item and string limit settings at chunk sizes 1 and 4096, plus nesting through 300 levels. 2400/2400 agree; 327 are rejected. |
| sequences | 1,200 | RFC 8742 sequences of 0 to 4 items, a quarter of them mutated. 1200/1200 agree on root count or error. |
| json | 700 | 500 single items (406 converted, 25 `UnsupportedKey`, 69 invalid), 100 `--seq` runs and 100 `--deterministic` runs. 700/700 agree. Numbers are compared by spelling against Python `repr` digits. |

The canon and json groups model streaming error order. A duplicate key fails
when its map closes, and an unsupported key fails at its head. Either can come
before a decode error later in the input, and the Python reference raises at
the same point.

`tests/fixtures/extended/cbor_stream_contracts.lani` covers the following,
with expected output in `tests/extended_cbor_stream_execution.rs`:

- The Writer API cases in the error table.
- Float narrowing: 1.0, 100000.0, 1.1, quiet NaN, NaN payloads and half
  subnormals.
- Nested sorted maps and joined chunks.
- Sticky duplicate errors.
- A 3,000-map deterministic document flushed after every map through a
  `core::io::SliceWriter`. It makes 3,000 flushes, holds 0 bytes after each,
  and is byte-identical to the same document written without flushing.
- `EventReader` over a `SliceReader` with a 3-byte scratch buffer.
- The `Finished` and `InputLimit` feed errors.

All six oracle groups run in about 17 seconds in total. The cargo
registrations were not run in this session.

Measured on this development host on 2026-10-31, with the GPU compiler's
native x86_64 output. Each figure is the minimum user+sys time of interleaved
runs. The host was loaded, so the earlier and later binaries were timed side
by side:

| Workload | Before the S5 speed work | After |
| --- | --- | --- |
| `cbor_to_json`: a 4.66 MB document of 100,000 four-key records to 7.4 MB of JSON | 2.81 s (4.8 s in the first measurement) | 0.49 s (5.7x) |
| `cbor_batch check`: a definite array of 1,000,000 zero bytes, including hex parsing in the driver | 0.80 s | 0.34 s |
| `cbor_batch copy`: preserving re-encoding of the same array | 1.79 s | 1.27 s |

After the speed work, `cbor_to_json` costs about 200 ns per small item:
about 80 ns to decode, and the rest to dispatch and write JSON. A shortest
binary64 float costs about 0.7 µs more. Where the time went, and what
changed:

- `Decoder.next()` called `Vec` methods for its frame stack and key records
  on every event, each costing 40–80 ns. Frames now live in one `Vec<u64>`
  whose slice is cached, so the per-event path makes no `Vec` calls.
  `advance()` also skips the `Result` return.
- The JSON writer appended through `Vec.try_push` one byte at a time. It now
  writes into a cached slice that grows geometrically. Keys, strings and
  numbers that need no escapes are copied in one checked loop, and the
  `fast_` methods skip the `Result`.
- `core::float_decimal` shortest formatting dropped from about 2.5 µs to
  about 0.7 µs per value. A tuned Grisu3 came first, then Schubfach with
  binary-search tables and eight-digit spelling replaced it; see
  [the float guide](stdlib-float-decimal.md#algorithms-and-speed). With
  Schubfach, the 4.66 MB document converts in 0.485 s, against 0.532 s with
  the tuned Grisu3.
- Byte loops still cost about 60–140 instructions per byte, because every
  slice index copies the slice descriptor and multiplies by a run-time
  stride. This is a compiler defect, recorded in
  `tests/fixtures/compiler_defects/slice_byte_copy_cost.lani`.
