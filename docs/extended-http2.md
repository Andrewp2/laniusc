# HTTP/2

HTTP/2 (RFC 9113) comes in three layers:

- [`ext::hpack`](extended-hpack.md): header compression;
- `ext::http2_frame`: the frame codec;
- `ext::http2`: a client connection engine without I/O, which multiplexes
  request streams over one connection.
- [`ext::http2_server`](extended-http2-server.md): the server engine, also
  without I/O, which `ext::http_service` runs for prior-knowledge h2c.

[`ext::http_agent`](extended-http-agent.md#http2) runs the engine over
verified TLS connections that select `h2` by ALPN, so `fetch` and
`fetch_all` use HTTP/2 wherever an https origin offers it. None of the
three modules does I/O or links native code; only the agent's TLS needs
OpenSSL.

## Frame codec

`ext::http2_frame` holds the frame types, flags, error codes, SETTINGS
identifiers and limits as constants (`DATA` … `CONTINUATION`, `END_STREAM`,
`ACK`, `END_HEADERS`, `PADDED`, `PRIORITY_FLAG`, `NO_ERROR` …
`HTTP_1_1_REQUIRED`, `HEADER_TABLE_SIZE` … `MAX_HEADER_LIST_SIZE`,
`HEADER_BYTES`, `DEFAULT_FRAME_SIZE`, `LARGEST_FRAME_SIZE`,
`DEFAULT_WINDOW`, `LARGEST_WINDOW`).

```lanius
pub struct Error { code: i32, stream: i32 }   // stream 0: a connection error
pub struct Frame { kind: i32, flags: i32, stream: i32, payload: View<u8> }
pub fn preface() -> View<u8>;
pub fn next(input: View<u8>, max_frame: i32) -> Result<Option<Frame>,Error>;
pub fn size(frame: Frame) -> i32;
pub fn declared_size(input: View<u8>) -> i32;
pub fn has(frame: Frame, flag: i32) -> bool;
pub fn data(frame: Frame) -> Data;
pub fn headers(frame: Frame) -> Headers;
pub fn continuation(frame: Frame) -> View<u8>;
pub fn push_promise(frame: Frame) -> PushPromise;
pub fn rst_stream(frame: Frame) -> i32;
pub fn ping(frame: Frame) -> View<u8>;
pub fn goaway(frame: Frame) -> Goaway;
pub fn window_update(frame: Frame) -> Result<i32,Error>;
pub fn setting_count(frame: Frame) -> i32;
pub fn setting(frame: Frame, index: i32) -> Setting;
pub fn check_setting(setting: Setting) -> Result<i32,Error>;
pub fn write_header(out: &Vec<u8>, length: i32, kind: i32, flags: i32, stream: i32) -> bool;
pub fn write_frame(out: &Vec<u8>, kind: i32, flags: i32, stream: i32, payload: View<u8>) -> bool;
pub fn write_settings(out: &Vec<u8>, settings: View<Setting>) -> bool;
pub fn write_settings_ack(out: &Vec<u8>) -> bool;
pub fn write_ping(out: &Vec<u8>, ack: bool, opaque: View<u8>) -> bool;
pub fn write_goaway(out: &Vec<u8>, last_stream: i32, code: i32, debug: View<u8>) -> bool;
pub fn write_window_update(out: &Vec<u8>, stream: i32, increment: i32) -> bool;
pub fn write_rst_stream(out: &Vec<u8>, stream: i32, code: i32) -> bool;
pub fn write_headers(out: &Vec<u8>, stream: i32, block: View<u8>, end_stream: bool, max_frame: i32) -> bool;
pub fn write_data(out: &Vec<u8>, stream: i32, data: View<u8>, end_stream: bool, max_frame: i32) -> bool;
```

`next` returns the next complete frame at the start of `input`, or `None`
when more bytes are needed. Its payload is a view of the input. It applies
the checks a receiver makes before it looks at stream state:

- the frame size against the `SETTINGS_MAX_FRAME_SIZE` we advertised
  (FRAME_SIZE_ERROR);
- stream 0 for SETTINGS, PING and GOAWAY, and a nonzero stream for DATA,
  HEADERS, PRIORITY, RST_STREAM, PUSH_PROMISE and CONTINUATION
  (PROTOCOL_ERROR);
- fixed payload lengths: PRIORITY 5, RST_STREAM 4, PING 8, WINDOW_UPDATE 4,
  SETTINGS a multiple of 6 and empty with ACK (FRAME_SIZE_ERROR);
- padding that fills the payload or more (PROTOCOL_ERROR).

A PRIORITY frame of the wrong length is a stream error, so the caller skips
`declared_size(input)` bytes and goes on. Unknown frame types are returned
for the caller to ignore. `headers` also reports a stream that depends on
itself, which is a stream error whose header block must still be decoded to
keep HPACK in step. `check_setting` applies the value rules of section
6.5.2 (ENABLE_PUSH 0 or 1, INITIAL_WINDOW_SIZE at most 2^31 − 1, MAX_FRAME_SIZE
from 16,384 to 16,777,215). `write_headers` splits a header block into
HEADERS and CONTINUATION frames of at most `max_frame` bytes, and
`write_data` splits data the same way.

## Connection engine

```lanius
pub enum Cause { Protocol, Peer, Refused, Malformed, Limit, Busy, Closed, Cancelled, InvalidRequest, AllocationFailed }
pub struct Error { cause: Cause, code: i32, stream: i32 }
pub enum State { Open, Done, Failed }
pub struct Options { hpack: ext::hpack::Limits, encoder_table_bytes: i32, stream_window: i32, connection_window: i32, max_frame: i32, max_streams: i32, body_bytes: i32, block_bytes: i32 }
pub fn default_options() -> Options;
pub fn client(options: Options) -> Result<Connection,Error>;
pub fn connection_specific(name: View<u8>) -> bool;
pub fn valid_name(name: View<u8>) -> bool;
pub fn valid_value(value: View<u8>) -> bool;

pub impl Connection {
    pub fn output(&self) -> View<u8>;
    pub fn sent(&self, count: i32);
    pub fn feed(&self, data: View<u8>) -> Result<i32,Error>;
    pub fn start(&self, fields: View<ext::hpack::Header>, end_stream: bool, head: bool) -> Result<i32,Error>;
    pub fn send_data(&self, id: i32, data: View<u8>, end: bool) -> Result<i32,Error>;
    pub fn unsent(&self, id: i32) -> i32;
    pub fn ping(&self, opaque: View<u8>) -> Result<i32,Error>;
    pub fn goaway(&self, code: i32) -> bool;
    pub fn cancel(&self, id: i32) -> bool;
    pub fn state(&self, id: i32) -> State;
    pub fn stream_error(&self, id: i32) -> Error;
    pub fn status(&self, id: i32) -> i32;
    pub fn field_count(&self, id: i32) -> i32;
    pub fn trailer_count(&self, id: i32) -> i32;
    pub fn field(&self, id: i32, i: i32) -> ext::hpack::Header;
    pub fn body(&self, id: i32) -> View<u8>;
    pub fn release(&self, id: i32) -> bool;
    pub fn is_open(&self) -> bool;
    pub fn can_start(&self) -> bool;
    pub fn wants_read(&self) -> bool;
    pub fn active_streams(&self) -> i32;
    pub fn failure(&self) -> Option<Error>;
    pub fn goaway_received(&self) -> bool;
    pub fn goaway_code(&self) -> i32;
    pub fn goaway_last_stream(&self) -> i32;
    pub fn peer_max_streams(&self) -> i64;
    pub fn peer_initial_window(&self) -> i64;
    pub fn peer_max_frame(&self) -> i32;
    pub fn peer_header_table(&self) -> i64;
    pub fn send_window(&self) -> i64;
    pub fn pings_acknowledged(&self) -> i32;
    pub fn frames_received(&self) -> i64;
    pub fn settings_acknowledged(&self) -> bool;
    pub fn destroy(&self) -> bool;
}
```

The caller owns the transport. It sends `output()` and reports what went
out with `sent(n)`, and passes every received byte to `feed`. `client`
queues the connection preface, a SETTINGS frame (ENABLE_PUSH 0,
MAX_HEADER_LIST_SIZE, and the table size, initial window and frame size
when they differ from the defaults) and a connection WINDOW_UPDATE up to
`connection_window`.

| Option | Default | Meaning |
| --- | --- | --- |
| `hpack` | `hpack::default_limits()` | Decoder limits; `table_bytes` is advertised as HEADER_TABLE_SIZE and `list_bytes` as MAX_HEADER_LIST_SIZE |
| `encoder_table_bytes` | 4096 | Cap on our encoder's dynamic table |
| `stream_window` | 1 MiB | Receive window per stream (INITIAL_WINDOW_SIZE) |
| `connection_window` | 16 MiB | Receive window for the connection |
| `max_frame` | 16384 | MAX_FRAME_SIZE we accept |
| `max_streams` | 100 | Our own cap on concurrent streams |
| `body_bytes` | 64 MiB | Per-response body limit |
| `block_bytes` | 256 KiB | One assembled header block (HEADERS + CONTINUATION) |

**Streams.** `start` opens a request stream with the given fields
(pseudo-fields first) and returns its odd identifier. Names must be in
HTTP/2 form (`valid_name`: lowercase, no separators), values free of NUL, CR
and LF and of surrounding whitespace, no connection-specific fields
(`connection`, `keep-alive`, `proxy-connection`, `transfer-encoding`,
`upgrade`) and `te` only as `trailers`; otherwise `InvalidRequest`. A field
list above the peer's MAX_HEADER_LIST_SIZE fails with `Limit`. `Busy` means
no stream slot now (the smaller of the peer's MAX_CONCURRENT_STREAMS and
`max_streams`); `Closed` means a GOAWAY was sent or received. `head` marks
a HEAD request, whose response has no content.

**Flow control.** `send_data` queues body bytes, and DATA goes out round
robin over the streams within the connection window, each stream's window
and the peer's frame size. Received DATA counts against our windows,
padding included, and is acknowledged with WINDOW_UPDATE once half a window
is consumed. Data past a window is a FLOW_CONTROL_ERROR, and a window
update that overflows 2^31 − 1 is one too (on the stream or the
connection). A change of the peer's INITIAL_WINDOW_SIZE moves every open
stream's send window by the difference.

**Control frames.** The first frame from the server must be SETTINGS.
Each SETTINGS is checked, applied and acknowledged; the peer's
HEADER_TABLE_SIZE resizes our encoder's table, and ENABLE_PUSH 1 from a
server is a PROTOCOL_ERROR. PING is answered, and our own `ping` counts the
acknowledgements. A GOAWAY stops new streams; open streams above its last
stream identifier fail with `Refused`, as does a stream the server resets
with REFUSED_STREAM, so either is safe to retry.

**Responses.** A response header block must start with exactly one
`:status` of three digits and carry no other pseudo-field; 1xx blocks other
than 101 are skipped, and 101 is malformed. Regular fields must have valid
names and values and no connection-specific names. `content-length`, if
present, must be one number that matches the body. Malformed responses are
stream errors (`Malformed`, RST_STREAM PROTOCOL_ERROR). A header block
after the final one must end the stream and becomes the trailers.
PUSH_PROMISE is a connection error, since push is disabled. CONTINUATION
must follow its HEADERS directly, on the same stream.

**Errors.** A connection error queues GOAWAY with its code and fails every
open stream with that error (`failure()`); a stream error queues RST_STREAM
and fails that stream only. Frames for a stream that is already finished or
released are ignored, but their header blocks are still decoded and their
DATA still counts against the connection window. `release(id)` frees a
finished stream; field and body views are valid until then.

## Executed evidence

The engine is checked over cleartext with prior knowledge by
[`engine_driver.lani`](../tests/fixtures/extended/http2/engine_driver.lani),
a scripted client that prints each response's status, length, FNV-1a hash,
fields and trailers. [`engine_oracle.py`](../tests/fixtures/extended/http2/engine_oracle.py)
runs it against two servers from
[`h2server.py`](../tests/fixtures/extended/http2/h2server.py):

- `Server`: libnghttp2's server session (the HTTP/2 library curl uses),
  driven through ctypes. nghttp2 validates everything the client sends:
  frames, HPACK, flow control and messaging. The server records the
  client's SETTINGS, concurrency, frame sizes, WINDOW_UPDATEs, resets and
  GOAWAY codes.
- `RawServer`: hand-built frames, for the violations nghttp2 will not
  produce. It decodes the client's header blocks with nghttp2's inflater.

Python's `h2` and `hpack` packages and `nghttpd` are not installed here, so
libnghttp2 (present as a system library) is the independent peer.

| Group | Cases | Covers |
| --- | --- | --- |
| nghttp2 | 17 | 20 concurrent streams finishing out of order; the peer's MAX_CONCURRENT_STREAMS of 2 (`Busy` past it); a 5,000,000-byte download under 64 KiB windows (over 100 WINDOW_UPDATEs); a 3,000,000-byte upload; a server that acknowledges data 20 ms late with a 1000-byte stream window; a body sent in parts; 65,536-byte peer frames; a zero peer header table; CONTINUATION from 40 fields of 1000 bytes; trailers and 103 before 200; HEAD and 204; RST_STREAM; GOAWAY; PING both ways; our GOAWAY and cancel; invalid requests refused locally; 200 sequential requests on one connection |
| raw | 46 | 19 connection errors with their GOAWAY codes (PUSH_PROMISE, SETTINGS values, an ACK with payload, SETTINGS on a stream, an oversized frame, a short PING, a zero or overflowing connection WINDOW_UPDATE, overlong padding, HPACK index 0, HEADERS on a server or idle stream, DATA on stream 0, interrupted or orphan CONTINUATION, RST_STREAM on an idle stream, a first frame other than SETTINGS); 20 stream errors with their RST_STREAM codes (DATA before HEADERS, uppercase, connection-specific and newline fields, missing, repeated-position or 4-digit `:status`, request pseudo-fields, `content-length` mismatches, trailers without END_STREAM, 1xx with END_STREAM, 101, zero or overflowing stream WINDOW_UPDATE, stream flow-control violations, self-dependency, a short PRIORITY, the body and header-list limits); and valid padding, priority, CONTINUATION, unknown frames and settings, frames on finished streams keeping HPACK in step, REFUSED_STREAM and GOAWAY last-stream refusal, server PING and SETTINGS, and an INITIAL_WINDOW_SIZE change on open streams |

```text
http2-engine-nghttp2 cases=17
http2-engine-raw cases=46
```

`tests/extended_http2_execution.rs` compiles the driver and runs both groups
(about 28 seconds together). The agent's HTTP/2 group, over TLS with ALPN,
is described in the [agent guide](extended-http-agent.md#http2).

## Limits

- Client only; no server engine.
- No server push (disabled in SETTINGS), no PRIORITY signals of our own,
  no extended CONNECT.
- Cleartext `h2c` upgrade is not offered; prior knowledge works with the
  engine directly.
- Response bodies are buffered whole per stream, up to `body_bytes`.
