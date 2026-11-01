# Sequential HTTP/1.1 service

`ext::http_service` serves HTTP/1.1 over one owned TCP connection at a time:
a bounded keep-alive request reader with absolute deadlines and typed errors,
a response writer, and a method/path router. The wire grammar, framing
checks, chunked decoding and limits come from [`ext::http`](extended-http.md);
sockets and clocks come from `std::socket` and `std::clock`. It is an optional
extended library, so `std` does not depend on it.

The sample [`http_static`](../sample_programs/library/http_static.lani) is a
static-file server with directory listings, single byte ranges, `HEAD`, a
`POST /echo` route that accepts chunked bodies, and `GET /healthz`.

Compared with the staged one-request [`ext::http_server`](extended-http-server.md),
this module processes keep-alive and pipelined requests, sends
`Connection: keep-alive`/`close` explicitly, and has no scheduler: one
connection is served to completion before the next is accepted.

## Connection loop

```lanius
pub fn default_options() -> Options;
pub fn accept_until(listener: &std::socket::Socket, options: Options,
    deadline: core::time::Deadline) -> Result<Option<Connection>,Error>;
pub impl Connection {
    pub fn next_request(&self) -> Result<Option<Request>,Error>;
    pub fn begin(&self, status: i32) -> Result<i32,Error>;
    pub fn header(&self, name: View<u8>, value: View<u8>) -> Result<i32,Error>;
    pub fn header_number(&self, name: View<u8>, value: u64) -> Result<i32,Error>;
    pub fn end_head(&self, length: u64) -> Result<i32,Error>;
    pub fn write_body(&self, data: View<u8>) -> Result<i32,Error>;
    pub fn respond(&self, status: i32, content_type: View<u8>, body: View<u8>) -> Result<i32,Error>;
    pub fn reject(&self, error: Error) -> Result<i32,Error>;
    pub fn set_close(&self);
    pub fn will_keep_alive(&self) -> bool;
    pub fn close(&self) -> Result<i32,Error>;
}
```

The listener is borrowed and must be a nonblocking TCP socket. `accept_until`
waits for readiness until the deadline and returns `Ok(None)` when it passes.
It retries `EAGAIN`, `EINTR`, `ECONNABORTED` and `ECONNRESET` from `accept4`.
Each connection allocates an input buffer (`buffer_bytes`) and a body buffer
(`limits.body_bytes`) once. `close` releases both and the descriptor once.

A typical loop:

```lanius
while (conn.will_keep_alive()) {
    let next = conn.next_request();
    if (next.is_err()) { conn.reject(next.unwrap_err()); return; }
    let item = next.unwrap(); if (item.is_none()) { break; }
    // route and respond exactly once
}
conn.close();
```

`next_request` returns `Ok(None)` when the peer closes or stays idle between
requests, or when `max_requests` have been read. Each `Request` borrows the
connection buffers: `method`, `target`, `path` (the target before `?`; for
absolute-form targets, the path after the authority), `query`, `version`, the
parsed `head`, the decoded `body`, `keep_alive` and `chunked`. These views are
invalid after the next `next_request` or `close`. Fixed-length bodies are
views into the input buffer. Chunked bodies are decoded into the body buffer,
and trailers are validated by `ext::http`. Bytes after the request stay
buffered and are processed as the next pipelined request.

Keep-alive follows RFC 9112: HTTP/1.1 persists unless `Connection: close`, and
HTTP/1.0 persists only with `Connection: keep-alive`. Any read error, the
request limit, or `set_close` makes the next response carry
`Connection: close`. `Expect: 100-continue` on HTTP/1.1 sends one interim
`100 Continue` before the server waits for an incomplete body.

## Deadlines and slow clients

| Option | Default | Starts |
| --- | --- | --- |
| `idle_timeout_ms` | 5000 | when the connection waits with no buffered request byte; expiry returns `Ok(None)` and sends nothing |
| `head_timeout_ms` | 2000 | when the first byte of a request is available; absolute, so trickled bytes or endless header lines never extend it |
| `body_timeout_ms` | 10000 | when the head is complete |
| `write_timeout_ms` | 10000 | for each `end_head`/`write_body` send |
| `drain_timeout_ms`, `drain_bytes` | 200, 65536 | after the write half-close in `close`, so the peer reads the final response instead of a reset |

Head and body expiry return `HeadTimeout`/`BodyTimeout`, which `reject`
answers with `408` and closes. The server is sequential, so one slow client
holds later clients for at most the head plus body deadlines. Clients that
arrive during that time wait in the listen backlog. Concurrent slow clients
add up. A poll-based server should use `ext::server_poll`.

## Limits and typed errors

`Options.limits` is an `ext::http::Limits` (defaults: 8 KiB head and line,
64 fields, 1 MiB body, 4 KiB and 16 trailer fields, 4096 chunks).
`buffer_bytes` (default 1,179,648) must hold the head plus the encoded body.

```lanius
pub enum Error { Parse(ext::http::Error), HeadTooLarge, BodyTooLarge, HeadTimeout,
    BodyTimeout, WriteTimeout, Truncated, Io(core::io::Error), Clock,
    AllocationFailed, InvalidState, InvalidHeader }
pub fn status_for(error: Error) -> i32;
```

| Error | `status_for` |
| --- | --- |
| `Parse(Malformed)`, `Parse(Bounds/Incomplete/Capacity)`, `Truncated` | 400 |
| `Parse(Limit)`, `HeadTooLarge` | 431 |
| `BodyTooLarge` (declared `Content-Length` above the limit, chunk total, chunk-size overflow, or a full buffer) | 413 |
| `HeadTimeout`, `BodyTimeout` | 408 |
| `Parse(Unsupported)` (unknown transfer coding, `HTTP/1.2`, `HTTP/2.0`) | 501 |
| `AllocationFailed`, `Parse(AllocationFailed)` | 500 |
| `Io`, `WriteTimeout`, `Clock`, `InvalidState`, `InvalidHeader` | 0: no response, close only |

A declared body that is too large is rejected before any of it is read.
`ext::http` rejects bare LF, obs-fold, control bytes, missing or repeated
`Host` on HTTP/1.1, `Content-Length` with `Transfer-Encoding`, repeated or
list `Content-Length`, chunked HTTP/1.0 requests, malformed chunk extensions
and forbidden trailer fields.

## Response writer

`begin(status)` stages `HTTP/1.1 NNN Reason`. `header` checks that the name is
a token and the value has no CR, LF or NUL. `end_head(length)` appends
`Content-Length` and `Connection`, then sends the head. The application must
then pass exactly `length` bytes through `write_body`; more is `InvalidState`.
For `HEAD` requests, `write_body` discards the bytes, so the same handler code
serves both methods. `respond` does all of this for an in-memory body, and
`reject(error)` sends `status_for(error)` (when nonzero) and closes. Status
codes outside 200..599 are refused; `100 Continue` is sent only by the reader.

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

Routes are checked in insertion order. An exact route matches the whole path,
and a prefix route matches the pattern followed by anything (`rest`). Method
`*` matches any method, and a `GET` route also answers `HEAD`. If a path
matches but no method does, `find` returns `MethodNotAllowed`, and the
application chooses the `Allow` header. Route views are borrowed and must
outlive the router. The router uses integer ids instead of callbacks, so the
application dispatches with `match`/`if`.

## Static-file sample

```text
http_static ROOT ADDRESS [--connections N] [--accept-timeout MS] [--head-timeout MS]
            [--idle-timeout MS] [--body-timeout MS] [--max-head N] [--max-body N] [--max-requests N]
```

It prints the bound address, serves until N connections or until no
connection arrives within the accept timeout, and then prints
`connections= requests= ok= partial= missing= rejected= timeouts= idle= errors=`.

- Paths are percent-decoded. NUL, backslash, `%2F` and any `.`/`..` segment
  return 400. Files open relative to the root directory descriptor
  (`openat`), and only regular files and directories are served (otherwise 403).
- A directory without a trailing slash gets a 301 to `path/`, which keeps the
  query. With the slash, it gets an HTML listing with HTML-escaped names,
  percent-encoded hrefs and `/` after subdirectories, in directory order. A
  regular file requested with a trailing slash returns 404.
- `Range: bytes=a-b`, `a-` and `-n` give 206 with `Content-Range`. A range
  that starts past the end, `-0`, or any range on an empty file gives 416
  with `bytes */size`. Multiple ranges and invalid syntax are ignored, and
  the full 200 is sent. File bodies stream through `read_at` in 64 KiB pieces.

## Executed evidence

These results come from `tests/fixtures/extended/http_service/oracle.py`
against the program compiled by `target/release/laniusc` on Linux x86_64. The
oracle uses Python `http.client`, `urllib` and raw sockets over 127.0.0.1 and
checks each server summary counter exactly against its own tally. Two
consecutive runs gave identical results:

| Group | Cases | Connections | Requests | Rejected | Timeouts |
| --- | --- | --- | --- | --- | --- |
| functional | 69 | 9 | 76 | 0 | 0 |
| malformed | 42 | 42 | 2 | 38 | 0 |
| slowloris | 12 | 13 | 7 | 5 | 5 |

- **Functional:** files, including 300,001 bytes and a UTF-8 name, through
  one reused `http.client` connection; `HEAD` content types; four listings
  compared with `os.listdir`; every listed href; redirects; 404/400/405;
  eight 206 ranges compared with Python slicing; three 416 and six ignored
  ranges; fixed, empty, 16 KiB and 1 MiB echoes and a chunked echo; a
  `urllib` redirect; pipelined and byte-at-a-time pipelined requests;
  absolute-form; HTTP/1.0 close and keep-alive; `Expect: 100-continue`.
- **Malformed:** 35 raw requests, each expecting an exact status and
  `Connection: close` (400 ×25, 431 ×4, 501 ×3, 413 ×3). Also: a valid
  request followed by garbage (200 then 400, nothing after), truncated head
  and body (400), three empty connections, and a 300 KB transfer afterwards.
- **Slowloris** (head 800 ms, idle 1200 ms, body 1000 ms):
  - a head trickled one byte per 50 ms gets 408 within 0.7–2.0 s;
  - endless header lines get 408 within 0.7–2.5 s;
  - a silent connection closes after the idle timeout;
  - a stalled body gets 408;
  - a partial head then silence gets 408;
  - a keep-alive connection idles out after one response;
  - a slow request that finishes inside the deadline is served;
  - a client queued behind a slowloris is served after the 408.

  Health checks between these cases confirm the server stays live.

The Rust harness `tests/extended_http_service_execution.rs` compiles the
sample and asserts these three summary lines. It was not built or run in this
change. Run it with
`cargo test --test extended_http_service_execution`.

## Limits of this version

- No concurrency. One slow client delays everyone else by up to its
  deadlines.
- No TLS, no `Date` header, no conditional requests (`If-Modified-Since`,
  `ETag`, `If-Range`), no multipart ranges, no content coding, no `Upgrade`.
- Leading empty lines before a request line are rejected, not skipped.
- `Request` views are borrowed with no lifetime check. Ownership and
  single-use are manual, as with the other `ext` server owners.
- Allocation failure and fault-injection coverage is not measured.
