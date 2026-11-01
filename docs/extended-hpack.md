# HPACK

`ext::hpack` is HTTP/2 header compression (RFC 7541): prefix integers, raw
and Huffman string literals, the 61-entry static table, a bounded dynamic
table with eviction, and an encoder and a decoder that each own one table.
It does no I/O and has no native dependencies. One `Decoder` and one
`Encoder` serve one direction of one connection;
[`ext::http2`](extended-http2.md) uses one of each.

## API

```lanius
pub enum Error { Bounds, InvalidLimits, Integer, Index, Huffman, Truncated, TableSize, SizeUpdate, TooLong, Limit, Failed, AllocationFailed }
pub enum Indexing { Incremental, Without, Never }
pub enum Huffman { Shortest, Always, Never }
pub struct Header { name: View<u8>, value: View<u8>, never_indexed: bool }
pub struct Limits { table_bytes: i32, list_bytes: i32, fields: i32, string_bytes: i32 }
pub struct Integer { value: i32, used: i32 }
pub fn default_limits() -> Limits;            // 4096, 65536, 1024, 65536
pub fn static_name(index: i32) -> View<u8>;   // 1..61
pub fn static_value(index: i32) -> View<u8>;
pub fn huffman_length(value: View<u8>) -> i32;
pub fn huffman_encode(value: View<u8>, out: &Vec<u8>) -> Result<i32,Error>;
pub fn huffman_decode(input: View<u8>, out: &Vec<u8>, maximum: i32) -> Result<i32,Error>;
pub fn encode_integer(value: i32, prefix: i32, flags: i32, out: &Vec<u8>) -> Result<i32,Error>;
pub fn decode_integer(input: View<u8>, prefix: i32) -> Result<Integer,Error>;
pub fn encode_string(value: View<u8>, mode: Huffman, out: &Vec<u8>) -> Result<i32,Error>;
pub fn decoder(limits: Limits) -> Result<Decoder,Error>;
pub fn encoder(table_bytes: i32) -> Result<Encoder,Error>;

pub impl Decoder {
    pub fn decode(&self, block: View<u8>) -> Result<i32,Error>;
    pub fn count(&self) -> i32;
    pub fn header(&self, index: i32) -> Header;
    pub fn set_maximum(&self, bytes: i32) -> Result<i32,Error>;
    pub fn table_size(&self) -> i32;
    pub fn table_capacity(&self) -> i32;
    pub fn table_entries(&self) -> i32;
    pub fn table_name(&self, index: i32) -> View<u8>;
    pub fn table_value(&self, index: i32) -> View<u8>;
    pub fn destroy(&self) -> bool;
}
pub impl Encoder {
    pub fn set_huffman(&self, mode: Huffman);
    pub fn set_peer_maximum(&self, bytes: i32) -> Result<i32,Error>;
    pub fn start_block(&self, out: &Vec<u8>) -> Result<i32,Error>;
    pub fn encode_field(&self, name: View<u8>, value: View<u8>, indexing: Indexing, out: &Vec<u8>) -> Result<i32,Error>;
    pub fn encode(&self, fields: View<Header>, out: &Vec<u8>) -> Result<i32,Error>;
    pub fn table_size(&self) -> i32;
    pub fn table_capacity(&self) -> i32;
    pub fn table_entries(&self) -> i32;
    pub fn destroy(&self) -> bool;
}
```

`View`, `Vec` and `Result` abbreviate the `core::slice`, `alloc::vec` and
`core::result` types.

## Primitives

- **Integers** use an N-bit prefix (1 to 8). `decode_integer` accepts at most
  five continuation bytes and values up to 2^31 − 1 (`Integer` otherwise);
  a short input fails with `Truncated`.
- **Huffman.** The code of Appendix B is canonical: codes of one length are
  consecutive in symbol order. The tables hold each symbol's code and length,
  the symbols sorted by length, and per length the count, first code and
  offset, so decoding needs no tree. `huffman_decode` fails with `Huffman` on
  EOS inside the data, more than 7 bits of padding, or padding that is not
  all ones; `maximum` caps the decoded length (`TooLong`).
- **Strings.** `encode_string` with `Shortest` uses the Huffman code only
  when it is strictly shorter, so `307` is sent raw (3 bytes) where the
  RFC's C.6 example shows the 3-byte Huffman form; `Always` reproduces the
  RFC bytes.

## Decoder

`decode(block)` decodes one complete header block (after HTTP/2 has
assembled HEADERS and CONTINUATION) into fields readable with `count` and
`header(i)`; their views stay valid until the next `decode`. It handles the
indexed, literal-with-incremental-indexing, without-indexing and
never-indexed representations, and dynamic table size updates, which must
come first in the block and must not exceed the maximum (`SizeUpdate`,
`TableSize`).

The dynamic table's maximum is `limits.table_bytes` (the value HTTP/2
advertises as `SETTINGS_HEADER_TABLE_SIZE`), but no less than 4096 until
`set_maximum` lowers it after the peer has acknowledged the setting. Entries
are appended to one buffer and evicted from the oldest; evicted bytes stay as
a dead prefix until compaction. An entry larger than the table empties it.

Errors:

| Error | Meaning |
| --- | --- |
| `Index` | index 0, or past the static and dynamic tables |
| `Integer`, `Truncated`, `Huffman` | malformed integer, short block, bad Huffman data |
| `SizeUpdate`, `TableSize` | size update out of place or above the maximum |
| `TooLong` | one string literal over `string_bytes` |
| `Limit` | the header list over `list_bytes` (name + value + 32 per field) or more than `fields` fields |
| `Failed` | a decoder that already failed |

Every error except `Limit` leaves the decoder `Failed`: its table can no
longer be trusted, so HTTP/2 treats it as a connection error
(COMPRESSION_ERROR). On `Limit` the decoder finishes the block, keeping its
table in step with the peer's encoder, and drops the fields, so HTTP/2 can
reset just that stream.

## Encoder

The encoder's table capacity is the smaller of its own cap (`encoder(bytes)`)
and the peer's `SETTINGS_HEADER_TABLE_SIZE` (`set_peer_maximum`). A change is
signalled at the start of the next block as RFC 7541 section 4.2 requires:
the smallest capacity reached since the last block, then the final one.

`encode(fields, out)` emits `start_block` and then each field, choosing:

- an exact static or dynamic match as an indexed field;
- never-indexed for fields marked `never_indexed`, for `authorization` and
  `proxy-authorization`, and for `cookie` values under 20 bytes (as
  nghttp2 does);
- without indexing for a field larger than the table;
- otherwise a literal with incremental indexing, naming the static or
  dynamic entry when only the name matches.

`encode_field` emits one field with a chosen representation. Strings follow
`set_huffman` (`Shortest` by default).

## Executed evidence

[`driver.lani`](../tests/fixtures/extended/hpack/driver.lani) reads hex
commands on stdin (decode blocks with a decoder, encode field lists, set
table sizes, and the integer, string and Huffman primitives).
[`oracle.py`](../tests/fixtures/extended/hpack/oracle.py) checks it against:

- the RFC 7541 Appendix C examples, byte for byte;
- libnghttp2 (the HTTP/2 library curl uses, through ctypes), both ways: its
  deflater's output decoded by the driver, and the driver's output inflated
  by nghttp2, over random field lists with shared table state;
- malformed and mutated blocks, also given to nghttp2.

Python's `hpack` and `h2` packages and `nghttpd` are not installed on the
development machine, so nghttp2's own HPACK code is the independent oracle.

| Group | Cases | Blocks | Covers |
| --- | --- | --- | --- |
| rfc | 8 | 39 | C.1 integers; C.2 literals; C.3/C.4 request sequences raw and Huffman; C.5/C.6 response sequences with eviction under a 256-byte table, decoded and re-encoded exactly (C.6 in `Shortest` mode sends `307` raw); size updates |
| nghttp2 | 3 | 2512 | 40 connections × 25 blocks each way with table evictions, Huffman and never-indexed fields, and all 256 Huffman symbols |
| malformed | 17 | 624 | 12 bad blocks that nghttp2 also rejects (index 0, indexes past the table, a truncated or overflowing integer, strings past the block, Huffman EOS, long and zero padding, size updates above the maximum or after a field), `TooLong`, `Limit` with the table kept in step, the field-count limit, an oversized entry emptying the table, and 600 single-byte mutations of nghttp2 blocks: wherever both decoders accept one (over 100 times), their fields are equal |

```text
hpack-rfc cases=8 blocks=39
hpack-nghttp2 cases=3 blocks=2512
hpack-malformed cases=17 blocks=624
```

`tests/extended_hpack_execution.rs` compiles the driver and runs the three
groups (about 4.4 seconds together).
