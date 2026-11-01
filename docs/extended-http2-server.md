# HTTP/2 server

`ext::http2_server` is the server counterpart of the
[`ext::http2`](extended-http2.md) client engine. Like the client, it does
no I/O and links no native code. It reuses [`ext::hpack`](extended-hpack.md),
`ext::http2_frame`, and `ext::http2`'s `Error`, `Cause`, `State` and field
checks. [`ext::http_service`](extended-http-service.md#http2-h2c) runs it
over plain TCP for prior-knowledge `h2c`.

## Engine

```lanius
pub struct Options { hpack: ext::hpack::Limits, encoder_table_bytes: i32, stream_window: i32, connection_window: i32, max_frame: i32, max_streams: i32, body_bytes: i32, block_bytes: i32, max_requests: i32 }
pub fn default_options() -> Options;
pub fn server(options: Options) -> Result<Connection,ext::http2::Error>;

pub impl Connection {
    pub fn output(&self) -> View<u8>;
    pub fn sent(&self, count: i32);
    pub fn feed(&self, data: View<u8>) -> Result<i32,ext::http2::Error>;
    pub fn next_request(&self) -> Option<i32>;
    pub fn method(&self, id: i32) -> View<u8>;
    pub fn scheme(&self, id: i32) -> View<u8>;
    pub fn authority(&self, id: i32) -> View<u8>;
    pub fn path(&self, id: i32) -> View<u8>;
    pub fn field_count(&self, id: i32) -> i32;
    pub fn trailer_count(&self, id: i32) -> i32;
    pub fn field(&self, id: i32, i: i32) -> ext::hpack::Header;
    pub fn header(&self, id: i32, name: View<u8>) -> Option<View<u8>>;
    pub fn body(&self, id: i32) -> View<u8>;
    pub fn respond(&self, id: i32, status: i32, fields: View<ext::hpack::Header>, end_stream: bool) -> Result<i32,ext::http2::Error>;
    pub fn send_data(&self, id: i32, data: View<u8>, end: bool) -> Result<i32,ext::http2::Error>;
    pub fn unsent(&self, id: i32) -> i32;
    pub fn state(&self, id: i32) -> ext::http2::State;
    pub fn stream_error(&self, id: i32) -> ext::http2::Error;
    pub fn cancel(&self, id: i32) -> bool;
    pub fn release(&self, id: i32) -> bool;
    pub fn ping(&self, opaque: View<u8>) -> Result<i32,ext::http2::Error>;
    pub fn goaway(&self, code: i32) -> bool;
    pub fn finished(&self) -> bool;
    pub fn is_open(&self) -> bool;
    pub fn active_streams(&self) -> i32;
    pub fn last_stream(&self) -> i32;
    pub fn requests_accepted(&self) -> i32;
    pub fn streams_refused(&self) -> i32;
    // also failure, goaway_received, goaway_code, goaway_sent,
    // peer_initial_window, peer_max_frame, peer_header_table, send_window,
    // pings_acknowledged, frames_received, settings_acknowledged
    pub fn destroy(&self) -> bool;
}
```

The caller owns the transport. It sends `output()`, reports what went out
with `sent(n)`, and passes every received byte to `feed`. `server` queues a
SETTINGS frame and a connection WINDOW_UPDATE up to `connection_window`. The
SETTINGS frame carries MAX_CONCURRENT_STREAMS and MAX_HEADER_LIST_SIZE, plus
the table size, initial window and frame size when they differ from the
defaults. `feed` first checks the 24-byte client preface as it arrives,
then requires a SETTINGS frame.

| Option | Default | Meaning |
| --- | --- | --- |
| `hpack` | `hpack::default_limits()` | Decoder limits; `table_bytes` is advertised as HEADER_TABLE_SIZE and `list_bytes` as MAX_HEADER_LIST_SIZE |
| `encoder_table_bytes` | 4096 | Cap on our encoder's dynamic table |
| `stream_window` | 1 MiB | Receive window per stream (INITIAL_WINDOW_SIZE) |
| `connection_window` | 4 MiB | Receive window for the connection |
| `max_frame` | 16384 | MAX_FRAME_SIZE we accept |
| `max_streams` | 100 | MAX_CONCURRENT_STREAMS |
| `body_bytes` | 1 MiB | Per-request body limit |
| `block_bytes` | 64 KiB | One assembled header block (HEADERS + CONTINUATION) |
| `max_requests` | 1000 | Streams accepted before a graceful GOAWAY |

**Requests.** A HEADERS frame on a new odd stream opens it. While
`max_streams` streams are open, a new one gets RST_STREAM(REFUSED_STREAM)
and counts in `streams_refused`. The header block is still decoded, which
keeps HPACK in step. The request section must follow RFC 9113 section 8.3.1:

- pseudo-fields come first, each once, and only `:method`, `:scheme`,
  `:authority` and `:path` are allowed;
- `:method` is required; `CONNECT` takes `:authority` alone, and every other
  method needs `:scheme` and a nonempty `:path`;
- regular fields must pass `ext::http2::valid_name` and `valid_value` and
  must not be connection-specific; `te` may only be `trailers`;
- any `content-length` must equal the bytes received.

A malformed request gets RST_STREAM(PROTOCOL_ERROR). Trailers (a second
HEADERS with END_STREAM and no pseudo-fields) are kept after the regular
fields. `next_request` returns the lowest complete stream not yet taken.

The engine answers two cases itself; the application never sees these
streams:

- a body over `body_bytes` gets 413;
- a header list over the decoder limit gets 431.

The engine sends a complete `content-length: 0` response and stops the rest
of the upload with RST_STREAM(NO_ERROR).

**Responses.** `respond` sends `:status` (200–599) followed by the given
fields in HTTP/2 form; END_STREAM is set when `end_stream` is true.
`send_data` queues content. DATA goes out round robin within the
connection window, each stream's window and the peer's MAX_FRAME_SIZE, as
WINDOW_UPDATEs arrive. A response that finishes before its request does
sends RST_STREAM(NO_ERROR) (RFC 9113 section 8.1). `release` frees a stream
the application took; streams it never took are freed when they end.

**Flow control in.** Received DATA, padding included, counts against both
windows. Each window is replenished with WINDOW_UPDATE once half of it has
been received and buffered. Until our SETTINGS is acknowledged, a stream
window below 65,535 counts as 65,535, because the client may still use the
default.

**Connection control.** SETTINGS are applied and acknowledged:

- a change to INITIAL_WINDOW_SIZE moves every stream's send window;
- HEADER_TABLE_SIZE bounds our encoder.

PING is answered. A client GOAWAY lets open streams finish, after which
`finished()` is true. `goaway(code)` sends GOAWAY with the last stream
opened; later streams are ignored, so the client may retry them elsewhere.

**Errors.** As in the client engine, violations that RFC 9113 makes
connection errors send GOAWAY with the code and fail every stream:

- a bad preface, or a first frame other than SETTINGS;
- frames on stream 0 that need a stream, and HEADERS on even streams;
- frames that are not CONTINUATION inside a header block;
- frames over MAX_FRAME_SIZE;
- HPACK errors (COMPRESSION_ERROR);
- windows over 2^31 − 1 (FLOW_CONTROL_ERROR);
- PUSH_PROMISE from a client.

Stream errors send RST_STREAM. Unknown frame types and PRIORITY are
ignored.

## HTTP/2 over TLS

There is no TLS server path yet. A TLS server selects `h2` with
`SSL_CTX_set_alpn_select_cb`, and OpenSSL has no server-side ALPN without
that callback. Lanius cannot yet define a C callback: the grammar has no
function types or function addresses (see
[library-concurrency-dependencies.md](library-concurrency-dependencies.md)).
The engine needs no changes for TLS. A TLS driver can feed it from
`ext::tls_stream` the way `ext::http_agent` drives the client engine, once
ALPN selection is possible.

## Executed evidence

`tests/fixtures/extended/http2_server/oracle.py` drives libnghttp2 1.59's
client session through ctypes (`nghttp2_client.py`). Python's `h2` package
and `nghttpd` are not installed. It runs against two programs:

- `pipe`: `engine_pipe.lani`, which runs the engine over stdin/stdout with
  `max_streams` 8 and 64 KiB windows;
- `tcp`: `h2c_service.lani`, the `ext::http_service` sequential h2c
  driver on a loopback listener with the default engine options. The same
  mode also runs against `h2c_events.lani`, the event server with
  `enable_h2`.

Each mode runs:

- **nghttp2 group (6 cases):**
  - 12 or 150 multiplexed requests, past MAX_CONCURRENT_STREAMS, with
    per-request fields and the advertised limit checked;
  - an upload larger than both receive windows;
  - a 100,000-byte download under a 1,000-byte client window acknowledged
    by hand, with every DATA frame at most 1,000 bytes;
  - PING;
  - 413 for an oversized body;
  - client GOAWAY with a stream still open.
- **raw group (18 cases):**
  - connection errors, each checked by its GOAWAY code: bad preface, DATA
    on stream 0, HEADERS on an even stream, an oversized frame, an invalid
    HPACK index, a zero WINDOW_UPDATE, a frame inside a header block,
    INITIAL_WINDOW_SIZE over the limit, PUSH_PROMISE, and an overflowing
    connection window;
  - stream errors, each checked by its RST_STREAM code, with a following
    request on the same connection still answered: stream window overflow,
    missing `:path`, an uppercase field name, a connection-specific field, a
    duplicate pseudo-field, and a content-length mismatch;
  - one stream over the limit refused while the rest stay open;
  - an unknown frame type ignored.

The `tcp` mode also sends a plain HTTP/1.1 request on the same listener,
and expects 400 for a corrupted preface.

```text
http2-server-engine nghttp2=6 raw=18
http2-server-h2c nghttp2=6 raw=18 http1=1
```

`tests/extended_http2_server_execution.rs` compiles the programs and checks
these lines.

### Load test

`load.py` runs two phases against `h2c_events.lani` on one event loop and
checks every body:

1. 100 concurrent h2c clients, each a libnghttp2 session with 20
   multiplexed requests;
2. 100 concurrent HTTP/1.1 keep-alive clients with 20 sequential requests
   each.

It then checks the server's counters (`connections=200 h2=100
requests=4000 errors=0`, with a peak of at least 100 connections). On the
3070 laptop, under load from other jobs, four rounds against one server
process (`/proc` CPU times of the server per phase) gave:

| Phase | Wall time | Rate | Server CPU | Page faults |
| --- | --- | --- | --- | --- |
| h2c | 0.22–0.35 s | 5,700–9,100 req/s | 0.23–0.29 s | 15,700 |
| HTTP/1.1 | 0.22–0.28 s | 7,100–9,300 req/s | 0.22–0.24 s | 4,500 |

A request now costs the server about as much over HTTP/2 as over
HTTP/1.1, 115–145 µs against 110–120 µs. Before this round h2c took
0.91 s of server CPU per phase (0.62 s of it system time) against 0.30 s.
The CPU went to memory, not to scanning: every allocation in the current
runtime is its own `mmap` and page fault and every release a `munmap`, and
h2c made about 31 allocations per request. Its system time followed the
63,000 page faults per phase. The fixes, in order of effect:

- `Vec::try_reserve` reserves exactly, so `ext::http2_frame`, `ext::hpack`
  and the engine's stream arrays reallocated (and copied) on each frame,
  each integer and each stream. They now reserve with doubling.
- The engine keeps the response header list and encoded block between
  responses, reserves a request section in one step, recycles the buffers
  of freed streams (up to 32 sets of at most 16 KiB each), and frames a
  response body that fits the flow-control windows straight into the
  output instead of copying it into the stream first.
- The event server sends a connection's responses together once its
  queued requests are answered (one `send` for 20 responses instead of 20)
  and pops its ready queue by index instead of shifting it.
- Streams are found through an open-addressed table, with their states
  in parallel arrays, and buffer shifts use `core::slice::copy_within`.
  These changed little on their own.

The remaining h2c page faults are mostly the two buffers each new stream
reserves for its fields and the per-connection engine setup. The Python
client side still costs more for h2c (about 0.21 s against 0.14 s).
