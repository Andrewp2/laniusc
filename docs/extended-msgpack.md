# MessagePack

`ext::msgpack` is a streaming [MessagePack](https://github.com/msgpack/msgpack/blob/master/spec.md)
codec. It has three parts:

- A push **`Decoder`**. It takes input in chunks of any size and returns one
  event per value as soon as that value's header and payload are buffered.
- An **`EventReader`** that reads input from `core::io::Read`.
- A buffered **`Writer`**. It always emits the shortest format and flushes to
  `core::io::Write`.

The decoder reports typed errors with `u64` byte offsets. It enforces limits
on depth, item count, payload size and input size.

The decoder also has two optional checks:

- `canonical` rejects any header longer than the value or length needs.
- `timestamps` (on by default) validates timestamp extensions.

The [msgpack-json sample](../sample_programs/msgpack_json.lani) converts in
both directions.

Evidence covers native Linux x86_64 executables built with the GPU compiler.

## Events

| Event | Formats |
| --- | --- |
| `Nil`, `Boolean(bool)` | `c0`, `c2`/`c3` |
| `Unsigned(u64)` | positive fixint, uint 8/16/32/64 |
| `Integer(i64)` | negative fixint, int 8/16/32/64. A positive value stored in a signed format is reported here too. |
| `Float32(u32)`, `Float64(u64)` | exact bits |
| `Str(View<u8>)` | fixstr, str 8/16/32. The bytes are strict UTF-8. |
| `Bin(View<u8>)` | bin 8/16/32 |
| `Ext(i8, View<u8>)` | fixext 1/2/4/8/16, ext 8/16/32. All 256 type codes are accepted, including the reserved negative ones. |
| `Array(u32)`, `Map(u32 pairs)` | fixarray/fixmap, 16, 32 |
| `End` | Synthesized once the last element of a container completes |

`ext::msgpack::timestamp(payload)` decodes a type −1 payload into
`Timestamp { seconds: i64, nanoseconds: u32 }`. It accepts the 32-bit, 64-bit
and 96-bit forms. Nanoseconds above 999,999,999 are rejected.

## Decoder

```lanius
pub struct Options { max_depth: i32, max_items: u64, max_string_bytes: i32, max_input: u64,
                     sequence: bool, canonical: bool, timestamps: bool }
pub fn default_options() -> Options;  // 128, 1000000, 16 MiB, 64 MiB, false, false, true
pub fn decoder(options: Options) -> Result<Decoder, Error>;
Decoder.feed(source, start, count); Decoder.finish(); Decoder.next() -> Result<bool, Error>;
Decoder.event(), event_offset(), is_complete(), depth(), byte_offset(), roots_read(), reset(), destroy()
pub fn event_reader<R>(reader: &R, decoder: &Decoder, scratch: View<u8>) -> Result<EventReader<R>, Error>;
```

`next()` behaves like the `ext::cbor_stream` decoder:

- `Ok(true)` means an event is ready.
- `Ok(false)` means the decoder needs more input. After `finish()`, it means
  the input is complete.
- Errors are sticky.
- Payload views borrow the decoder's buffer until the next `feed`.

With `sequence` set, the decoder reads a stream of concatenated values.

Checks run in a fixed order. Each one reports at the offset of the value's
first byte:

1. `0xc1` → `InvalidByte`.
2. Truncated header bytes → `UnexpectedEnd`.
3. With `canonical` set, a non-shortest header → `NotCanonical`. This covers
   ints in a wider or signed format, str 8 below 32, bin/str/array/map 16
   below their 8-bit or fixed forms, and ext 8 with a fixext length.
4. A str, bin or ext payload over `max_string_bytes` → `StringLimit`. This is
   checked before waiting for the payload.
5. A truncated payload → `UnexpectedEnd`.
6. Exceeding `max_items` → `ItemLimit`.
7. Invalid str UTF-8 → `InvalidUtf8`.
8. An invalid timestamp extension → `InvalidTimestamp`.
9. A container beyond `max_depth` → `DepthLimit`.

Two more errors come from the input as a whole. A byte after the root, when
`sequence` is not set, is `TrailingData`. Input beyond `max_input` is
`InputLimit`.

## Writer

```lanius
pub fn writer(options: WriterOptions) -> Result<Writer, Error>;  // max_depth, max_output_bytes
nil(), boolean(bool), unsigned(u64), integer(i64), float32(u32), float64(u64),
text(Text), str_bytes(View<u8>), bin(View<u8>), ext(i8, View<u8>), timestamp(i64, u32),
begin_array_len(u64), begin_map_len(u64 pairs), begin_array(), begin_map(), end(),
event(Event), output(), stable_len(), flush_to<W>(&W)
```

Every header the writer emits is the shortest one, matching
`msgpack.packb(..., use_bin_type=True)`:

- Integers use the unsigned formats when non-negative and the signed formats
  when negative.
- `ext` uses fixext when the length allows it.
- `timestamp` picks the shortest of the 32-bit, 64-bit and 96-bit forms.

`begin_array()` and `begin_map()` open a container whose length is not yet
known. When it ends, `end()` inserts the shortest header. `flush_to` writes
only the stable prefix, which stops at the outermost such container.

The writer rejects the following, leaving its output unchanged:

| Error | Cause |
| --- | --- |
| `CountMismatch` | More or fewer elements than a declared length |
| `OddMap` | `end()` after a key with no value |
| `InvalidPlacement` | `end()` at the root |
| `InvalidUtf8` | A str that is not valid UTF-8 |
| `InvalidValue` | Nanoseconds above 999,999,999, or a length over u32 |
| `DepthLimit` | Nesting beyond `max_depth` |
| `OutputLimit` | Buffered output beyond `max_output_bytes` |

Several roots in a row produce a stream of concatenated values.

## msgpack-json

`msgpack_json < in.msgpack` reads a stream of concatenated values and prints
one compact JSON line per value:

- nil → `null`.
- Integers are exact.
- Floats use the shortest round-trip spelling of the f64 value. Non-finite
  floats become `null`.
- bin → unpadded base64url string.
- Map keys must be str or integers (integers become decimal strings). Any
  other key stops with `UnsupportedKey`.
- Ext values stop with `UnsupportedExt`.

`msgpack_json --from-json < in.json` writes MessagePack:

- Integer spellings in [−2^63, 2^64) stay integers.
- Every other number becomes float64, correctly rounded. Numbers longer than
  768 bytes are rejected.
- Objects keep duplicate keys.

Errors print `msgpack-json: KIND at OFFSET`. JSON errors are prefixed with
`json`. Exit codes: 0 success, 1 usage, 2 invalid or unsupported input, 3 I/O,
4 out of memory.

## Oracle

`tests/fixtures/stdlib_execution/msgpack_oracle/oracle.py` uses two
independent references:

- **The installed `msgpack` 1.0.3 package**: acceptance, decoded values,
  `packb` bytes, and `Unpacker` fed one byte at a time.
- **A Python model in the file**: a shortest encoder, encodings with longer
  headers than needed, a decoder that follows the error order above, and the
  canonical rules.

`msgpack_batch.lani` reads one hex value per line. It runs `copy` (decode,
then re-encode) and `check` (canonical decode), each fed 1, 3, 7 and 4096
bytes at a time.

| Group | Cases | Agreement |
| --- | ---: | --- |
| spec | 76 | Format table typed in by hand: 61 values and 15 errors, all 76 matching both references. copy and check each 304/304; msgpack-python agrees on 76/76. |
| generated | 1,500 | All formats, including float32, reserved ext codes, timestamps and duplicate keys; non-canonical headers on every third value. copy and check each 6000/6000. msgpack-python reads all 1,500 Lanius outputs back to the input's value. The shortest encoder equals `packb` on all 888 values `packb` can express. 1,288 values are canonical. |
| mutations | 3,000 | copy and check each 12000/12000 with exact error kind and offset. msgpack-python agrees on acceptance and value for 3000/3000. 2,192 are rejected. |
| limits | 2,398 | Nine depth, item and payload settings at chunk sizes 1 and 4096, plus nesting through 1,000 levels. 2398/2398 agree; 398 are rejected. |
| sequences | 1,200 | Streams of 0 to 4 values, a quarter of them mutated. 1200/1200 agree on root count or error, and msgpack's `Unpacker` agrees on 600/600. |
| json | 900 | 500 MessagePack streams converted to JSON (261 converted, 39 empty, 200 rejected, including unsupported keys and ext values), plus 400 `--from-json` runs checked against Python `json`, the shortest encoder and msgpack-python. 900/900 agree. |

`tests/fixtures/extended/msgpack_contracts.lani` covers the following:

- The writer cases listed above, plus timestamp encoding and decoding.
- A 3,000-map stream flushed after every map through a `SliceWriter`. It is
  byte-identical to the same stream written without flushing.
- `EventReader` with a 3-byte scratch buffer.
- The `Finished` and `InputLimit` feed errors.

Its expected output is checked into `tests/extended_msgpack_execution.rs`.
All six oracle groups run in about 25 seconds in total. The cargo
registrations were not run in this session.
