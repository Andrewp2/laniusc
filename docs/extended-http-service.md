# HTTP/1.1 service

`ext::http_service` serves HTTP/1.1 with:

- a bounded keep-alive request reader with absolute deadlines and typed errors;
- a response writer that adds `Date`;
- a method/path router;
- two drivers that share all parsing and writing code:
  - an event-driven `Server` that multiplexes many connections on one
    [`std::event`](stdlib-event-loop.md) (epoll) loop;
  - a sequential `Connection` driver.

The wire grammar, framing checks, chunked decoding and limits come from
[`ext::http`](extended-http.md). Sockets and clocks come from `std::socket` and
`std::clock`. It is an optional extended library, so `std` does not depend on it.

The sample [`http_static`](../sample_programs/library/http_static.lani) is a
static-file server. It supports directory listings, single byte ranges,
`ETag`/`Last-Modified` validators with conditional requests, and `HEAD`. It
also has a `POST /echo` route that accepts chunked bodies, and `GET /healthz`.

Compared with the staged one-request [`ext::http_server`](extended-http-server.md),
this module handles keep-alive and pipelined requests and sends
`Connection: keep-alive` or `Connection: close` explicitly. The event server
is single-threaded and needs no worker threads.

## Event-driven server

```lanius
pub fn server(listener: &std::socket::Socket, options: Options, max_connections: i32) -> Result<Server,Error>;
pub impl Server {
    pub fn next(&self, deadline: core::time::Deadline) -> Result<Option<i32>,Error>;
    pub fn request(&self, slot: i32) -> Request;
    pub fn take(&self, slot: i32) -> Connection;
    pub fn put(&self, slot: i32, conn: Connection) -> Result<i32,Error>;
    pub fn active(&self) -> i32;
    pub fn stats(&self) -> ServerStats;   // connections, requests, rejected, timeouts, idle, errors, peak
    pub fn close(&self) -> Result<i32,Error>;
}
```

The listener is borrowed and must be a nonblocking listening TCP socket. It is
registered in a `std::event` loop with one slot per connection, from 1 to
4096 slots. `next(deadline)` drives all of the following until a request is
complete:

- accepts;
- nonblocking reads (direct `recvfrom` into the connection buffer);
- parsing;
- response flushing (direct `sendto` from the output buffer, refilled from the
  file with `pread64` in 256 KiB pieces);
- the write half-close and drain.

It then returns that request's slot, or `None` when the deadline passes. The
application takes the slot's `Connection`, stages exactly one response with
the writer below, and calls `put`. In this mode the writer only buffers, so a
handler never blocks. `put` flushes as far as the socket allows and leaves the
rest to the loop.

```lanius
while (true) {
    let next = server.next(deadline); if (next.is_err()) { break; }
    let slot = next.unwrap(); if (slot.is_none()) { break; }
    let request = server.request(slot.unwrap()); let conn = server.take(slot.unwrap());
    // route, then respond / stream_file exactly once
    server.put(slot.unwrap(),conn);
}
server.close();
```

The loop recomputes its wait from the earliest slot deadline. When a deadline
passes:

- an idle slot closes silently;
- a slot still in its head or body gets a buffered 408 and closes after it
  is sent;
- a stalled write or drain closes.

Slow peers hold only their own slot. When every slot is busy, the listener is
removed from the loop, so the level-triggered readiness cannot spin. It is
added back when a slot frees, and later clients wait in the listen backlog
until then. If a handler puts back a connection without a complete response,
the server answers 500 and closes, and counts it in `errors`. Accepted
sockets get `TCP_NODELAY` because responses are written whole. Without it,
small keep-alive responses measured 40 ms each (a delayed-ACK stall); with it
they take about 1.2 ms.

Each connection starts with an input buffer of `head_bytes + 16 KiB`. The
buffer doubles up to `buffer_bytes` only while a body needs the space. The
chunked-body buffer grows to the decoded length. Neither buffer is
zero-filled, because bytes are read back only after the host or a copy has
written them.

## Sequential driver

```lanius
pub fn accept_until(listener: &std::socket::Socket, options: Options,
    deadline: core::time::Deadline) -> Result<Option<Connection>,Error>;
pub impl Connection {
    pub fn next_request(&self) -> Result<Option<Request>,Error>;
    pub fn reject(&self, error: Error) -> Result<i32,Error>;
    pub fn close(&self) -> Result<i32,Error>;
    pub fn set_close(&self);
    pub fn will_keep_alive(&self) -> bool;
}
```

`accept_until` waits for one connection. It retries `EAGAIN`, `EINTR`,
`ECONNABORTED` and `ECONNRESET` from `accept4`. `next_request` blocks with
the phase deadline and writes directly with `send_until`. `reject(error)`
sends `status_for(error)` (when nonzero) and closes. `close` half-closes,
drains briefly, and closes once. One slow client therefore holds every later
client for up to its deadlines; the `slowloris-seq` oracle group records this.

## Requests and keep-alive

`next_request` returns `Ok(None)` when the peer closes or stays idle between
requests, or when `max_requests` have been read. The event server's
`request(slot)` returns the same kind of `Request`. A `Request` borrows the
connection buffers, which stay valid until the response completes:

- `method`, `target`, `query`, `version` and the parsed `head`;
- `path`: the target before `?`, or for absolute-form targets the path after
  the authority;
- the decoded `body`, plus `keep_alive` and `chunked`.

Fixed-length bodies are views into the input buffer. Chunked bodies are
decoded into the body buffer, and `ext::http` validates trailers. Bytes after
the request stay buffered and are parsed as the next pipelined request.

Keep-alive follows RFC 9112: HTTP/1.1 persists unless `Connection: close`, and
HTTP/1.0 persists only with `Connection: keep-alive`. Any read error, the
request limit, or `set_close` makes the next response carry
`Connection: close`. On HTTP/1.1, `Expect: 100-continue` sends one interim
`100 Continue` before waiting for an incomplete body.

## Deadlines

| Option | Default | Starts |
| --- | --- | --- |
| `idle_timeout_ms` | 5000 | when the connection waits with no buffered request byte; expiry closes silently |
| `head_timeout_ms` | 2000 | when the first byte of a request is read; absolute, so trickled bytes or endless header lines never extend it |
| `body_timeout_ms` | 10000 | when the head is complete |
| `write_timeout_ms` | 10000 | sequential: for each send call; event server: for the whole buffered response |
| `drain_timeout_ms`, `drain_bytes` | 200, 65536 | after the write half-close, so the peer reads the final response instead of a reset |

## Limits and typed errors

`Options.limits` is an `ext::http::Limits` with these defaults: 8 KiB head and
line, 64 fields, 1 MiB body, 4 KiB and 16 trailer fields, 4096 chunks.
`buffer_bytes` (default 1,179,648) caps the head plus the encoded body.
`Options.date` (default true) adds the `Date` header.

```lanius
pub enum Error { Parse(ext::http::Error), HeadTooLarge, BodyTooLarge, HeadTimeout,
    BodyTimeout, WriteTimeout, Truncated, VersionNotSupported, Io(core::io::Error), Clock,
    AllocationFailed, InvalidState, InvalidHeader, Event(std::event::Error) }
pub fn status_for(error: Error) -> i32;
```

| Error | `status_for` |
| --- | --- |
| `Parse(Malformed)`, `Parse(Bounds/Incomplete/Capacity)`, `Truncated` | 400 |
| `Parse(Limit)`, `HeadTooLarge` | 431 |
| `BodyTooLarge` (a declared `Content-Length` above the limit, the chunk total, a chunk-size overflow, or a full buffer) | 413 |
| `HeadTimeout`, `BodyTimeout` | 408 |
| `VersionNotSupported` (a well-formed `HTTP/d.d` other than 1.0/1.1, such as `HTTP/1.2`, `HTTP/2.0`) | 505 |
| `Parse(Unsupported)` (an unknown transfer coding) | 501 |
| `AllocationFailed`, `Parse(AllocationFailed)` | 500 |
| `Io`, `WriteTimeout`, `Clock`, `InvalidState`, `InvalidHeader`, `Event` | 0: no response, close only |

A declared body that is too large is rejected before any of it is read.
`ext::http` rejects all of the following:

- bare LF, obs-fold and control bytes;
- a missing or repeated `Host` on HTTP/1.1;
- `Content-Length` together with `Transfer-Encoding`;
- repeated or list `Content-Length`;
- chunked HTTP/1.0 requests;
- malformed chunk extensions;
- forbidden trailer fields;
- malformed versions such as `http/1.1` or `HTTP/1.10` (400).

## Response writer

These `Connection` methods behave the same with both drivers:

```lanius
pub fn begin(&self, status: i32) -> Result<i32,Error>;
pub fn header(&self, name: View<u8>, value: View<u8>) -> Result<i32,Error>;
pub fn header_number(&self, name: View<u8>, value: u64) -> Result<i32,Error>;
pub fn end_head(&self, length: u64) -> Result<i32,Error>;
pub fn end_head_without_body(&self, length: u64) -> Result<i32,Error>;
pub fn write_body(&self, data: View<u8>) -> Result<i32,Error>;
pub fn stream_file(&self, file: std::file::File, position: u64, length: u64) -> Result<i32,Error>;
pub fn respond(&self, status: i32, content_type: View<u8>, body: View<u8>) -> Result<i32,Error>;
pub fn format_http_date(seconds: i64, out: [u8]) -> bool;  // 29-byte IMF-fixdate
pub fn parse_http_date(value: View<u8>) -> i64;             // -1 unless IMF-fixdate
```

- `begin(status)` stages `HTTP/1.1 NNN Reason` and the `Date` header. Status
  codes outside 200..599 are refused; only the reader sends `100 Continue`.
- `header` checks that the name is a token and that the value has no CR, LF
  or NUL.
- `end_head(length)` appends `Content-Length` and `Connection`. Exactly
  `length` body bytes must follow through `write_body` and/or `stream_file`.
- `end_head_without_body(length)` is for 304. It reports the selected
  representation's length (RFC 9110 8.6), and no body follows.
- `stream_file` takes ownership of the file and closes it exactly once, also
  on error or for `HEAD`.
- For `HEAD` requests, body bytes are dropped, so one handler serves both
  methods.
- `respond` does all of this for an in-memory body.

## Router

```lanius
pub fn router() -> Router;
pub impl Router {
    pub fn add(&self, method: View<u8>, pattern: View<u8>, prefix: bool, id: i32) -> Result<i32,Error>;
    pub fn find(&self, method: View<u8>, path: View<u8>) -> Match;
    pub fn destroy(&self);
}
pub enum Match { Found(Hit), NotFound, MethodNotAllowed }
pub struct Hit { id: i32, rest: View<u8> }
```

Routes are checked in insertion order:

- An exact route matches the whole path.
- A prefix route matches the pattern followed by anything (`rest`).
- Method `*` matches any method, and a `GET` route also answers `HEAD`.
- If a path matches but no method does, `find` returns `MethodNotAllowed`, and
  the application chooses the `Allow` header.

Route views are borrowed and must outlive the router. Routes carry integer
ids instead of callbacks, and the application dispatches on the id.

## Static-file sample

```text
http_static ROOT ADDRESS [--connections N] [--accept-timeout MS] [--head-timeout MS]
            [--idle-timeout MS] [--body-timeout MS] [--max-head N] [--max-body N]
            [--max-requests N] [--max-connections N] [--sequential]
```

By default it runs the event server with 64 slots. It exits once no
connection is active and none has arrived within the accept timeout.
`--sequential` uses the sequential driver instead, serving at most
`--connections N` connections. At exit it prints
`connections= requests= ok= partial= missing= rejected= timeouts= idle= errors=`.

- **Paths:** percent-decoded. NUL, backslash, `%2F` and any `.` or `..`
  segment return 400. Files open relative to the root directory descriptor
  (`openat`). Only regular files and directories are served; anything else
  returns 403.
- **Directories:** without a trailing slash, a 301 to `path/` that keeps the
  query. With the slash, an HTML listing in directory order, with HTML-escaped
  names, percent-encoded hrefs and `/` after subdirectories. A regular file
  requested with a trailing slash returns 404.
- **Validators:**
  - `ETag` is the strong `"size-mtime_seconds-mtime_nanos"` (hex), and
    `Last-Modified` is the modification time.
  - `If-None-Match` (weak comparison, `*`, lists) takes precedence over
    `If-Modified-Since` (IMF-fixdate only; other date forms are ignored). A
    match gives 304 with the validators and the full `Content-Length`.
  - `If-Range` honors `Range` only for an exact strong `ETag` or an exact
    `Last-Modified` date. Otherwise the full 200 is sent.
- **Ranges:**
  - `bytes=a-b`, `a-` and `-n` give 206 with `Content-Range`.
  - A start past the end, `-0`, or any range on an empty file gives 416 with
    `bytes */size`.
  - Multiple ranges and invalid syntax are ignored, and the full 200 is sent.

## Executed evidence

These results come from `tests/fixtures/extended/http_service/oracle.py all`
against the sample compiled with `target/claude-work/bin/lcc` (the resident
`laniusc`) on Linux x86_64. Each group starts its own server on 127.0.0.1:0
and uses Python `http.client`, `urllib`, threads and raw sockets. Every server
counter is checked exactly against the oracle's own tally. The whole set runs
in about 36 s. Consecutive runs gave identical lines:

| Group | Driver | Cases | Connections | Requests | Rejected | Timeouts |
| --- | --- | --- | --- | --- | --- | --- |
| functional | event | 70 | 9 | 77 | 0 | 0 |
| malformed | event | 45 | 45 | 2 | 41 | 0 |
| slowloris | event | 12 | 13 | 7 | 5 | 5 |
| conditional | event | 23 | 1 | 23 | 0 | 0 |
| concurrent | event | 39 | 78 | 254 | 8 | 8 |
| functional-seq | sequential | 70 | 9 | 77 | 0 | 0 |
| malformed-seq | sequential | 45 | 45 | 2 | 41 | 0 |
| slowloris-seq | sequential | 12 | 13 | 7 | 5 | 5 |
| conditional-seq | sequential | 23 | 1 | 23 | 0 | 0 |

- **Functional:**
  - files, including 300,001 bytes and a UTF-8 name, through one reused
    `http.client` connection;
  - a `Date` header within 10 s of the oracle's clock;
  - `HEAD` content types;
  - four listings compared with `os.listdir`, and every listed href;
  - redirects, and 404/400/405 responses;
  - eight 206 ranges compared with Python slicing, three 416 and six ignored
    ranges;
  - fixed, empty, 16 KiB and 1 MiB echoes, and a chunked echo;
  - a `urllib` redirect;
  - pipelined and byte-at-a-time pipelined requests;
  - absolute-form targets;
  - HTTP/1.0 close and keep-alive;
  - `Expect: 100-continue`.
- **Malformed:** 38 raw requests, each expecting an exact status, `Date` and
  `Connection: close`: 400 ×27, 505 ×3, 431 ×4, 413 ×3, 501 ×1. Also:
  - a valid request followed by garbage (200 then 400, nothing after);
  - a truncated head and a truncated body (400 each);
  - three empty connections;
  - a 300 KB transfer afterwards.
- **Slowloris** (head 800 ms, idle 1200 ms, body 1000 ms):
  - a head trickled one byte per 50 ms, endless header lines, and a partial
    head followed by silence each get 408 at the absolute head deadline;
  - a stalled body gets 408;
  - silent and idle keep-alive connections close silently;
  - a slow request that completes in time is served.

  A client that arrives while a slowloris is held is served in under 0.3 s
  by the event server. The sequential driver serves it only after the 408,
  0.5–2.0 s later.
- **Conditional:**
  - `ETag` and `Last-Modified` equal values computed from `os.stat`;
  - six `If-None-Match` forms (304/200);
  - `If-Modified-Since` equal, earlier, future, invalid and non-GMT dates;
  - `If-None-Match` precedence over `If-Modified-Since`;
  - Range under a matching `If-None-Match` (304);
  - five `If-Range` cases;
  - a `HEAD` 304;
  - a validator change after `os.utime`;
  - `Date` on a 404.
- **Concurrent** (event server only, 128 slots):
  - 16 threaded keep-alive clients × 12 mixed requests, including 64 KiB
    chunked echoes;
  - 20 requests completing in under 0.5 s beside eight held slowloris heads,
    which then each get 408;
  - 10 × 300 KB downloads in under 1 s beside a client that stops reading a
    32 MiB body; that client then reads it all, verified by SHA-256;
  - a request answered in under 0.3 s beside 40 idle connections, which then
    close silently;
  - ten raw sockets sending three pipelined requests interleaved byte by
    byte.

The Rust harness `tests/extended_http_service_execution.rs` compiles the
sample and asserts these nine summary lines. Under the no-cargo rule it was
not built or run. Its timing thresholds assume the groups are not contended
by other heavy jobs.

## Limits of this version

- **Threads and TLS:** one thread, no TLS.
- **Memory:** a connection uses up to `buffer_bytes` plus the decoded body,
  and the event server's `max_connections` is the only cap on the total.
- **Write deadline:** the event server's write deadline applies to the whole
  response, so a client must read the 32 MiB body within
  `write_timeout_ms` (10 s by default).
- **Not supported:**
  - multipart ranges;
  - content coding;
  - `Upgrade`;
  - RFC 850 and asctime dates in `If-Modified-Since`;
  - `If-Match` and `If-Unmodified-Since`.
- **Leading empty lines** before a request line are rejected, not skipped.
- **Manual ownership:**
  - `Request` views and `take`/`put` connections are borrowed with no
    lifetime check;
  - a taken slot must be put back before the next `next`.
- **Not measured:** allocation-failure and fault-injection coverage.
