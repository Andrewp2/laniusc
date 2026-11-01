# HTTP reverse proxy

`ext::http_proxy` is a reverse proxy in the
[HTTP service](extended-http-service.md) family. One `std::event` (epoll)
loop accepts HTTP/1.1 and prior-knowledge h2c clients and forwards each
request to an HTTP/1.1 upstream chosen by path prefix. It keeps idle
upstream connections in per-upstream pools, rewrites headers for the next
hop, and streams bodies both ways through fixed buffers. It never holds a
whole body. `ext::http_proxy_tls` puts the same proxy behind TLS, and ALPN
picks HTTP/2 or HTTP/1.1.

The proxy is split into separate modules, not added to `ext::http_service`,
which is already about 1,000 lines:

| Module | Contents |
| --- | --- |
| `ext::http_body` | Incremental body framing (`Framer`): Content-Length, chunked, close-delimited or none. |
| `ext::http_rewrite` | Hop-by-hop removal and forwarding fields, for HTTP/1.1 heads and for HTTP/2 requests and responses. |
| `ext::http_proxy` | The event loop, the upstream pools, timeouts and the h2c front end. |
| `ext::client_transport` | The interface that hands a server's client socket I/O to a transport layer. |
| `ext::tls_clients` | The TLS transport over that interface (OpenSSL through `ext::openssl_tls`). |
| `ext::http_proxy_tls` | `ext::http_proxy` plus `ext::tls_clients`. |
| `ext::http_service_tls` | `ext::http_service`'s event Server plus `ext::tls_clients`: HTTPS with ALPN h2. |

The first four link no native code. The last three link OpenSSL
(`--native-link --native-library ssl --native-library crypto`).

## API

```lanius
pub enum Error { Io(core::io::Error), Event(std::event::Error), Clock, AllocationFailed, InvalidState }
pub struct Options { limits: ext::http::Limits, buffer_bytes: i32, connect_timeout_ms: i32, response_timeout_ms: i32, io_timeout_ms: i32, head_timeout_ms: i32, idle_timeout_ms: i32, pool_idle_ms: i32, max_idle: i32, upstream_connections: i32, max_requests: i32, via: View<u8>, h2: bool, h2_streams: i32, h2_stream_window: i32 }
pub struct Stats { clients, h2_clients, requests, h2_requests, responses, upstream_connects, reused, retries, bad_gateway, gateway_timeout, rejected, aborted, peak_clients: i32 }
pub fn default_options() -> Options;
pub fn proxy(listener: &std::socket::Socket, options: Options, max_clients: i32) -> Result<Proxy,Error>;

pub impl Proxy {
    pub fn add_upstream(&self, address: core::net::SocketAddr) -> Result<i32,Error>;
    pub fn route(&self, prefix: View<u8>, upstream: i32) -> Result<i32,Error>;
    pub fn poll(&self, deadline: core::time::Deadline) -> Result<i32,Error>;
    pub fn stats(&self) -> Stats;
    pub fn active(&self) -> i32;
    pub fn upstream_connections(&self) -> i32;
    pub fn idle_connections(&self) -> i32;
    pub fn wrap_clients(&self, secure: bool) -> Result<i32,Error>;
    pub fn close(&self) -> Result<i32,Error>;
}
```

The listener is borrowed and must be a nonblocking listening TCP socket.
Upstream 0 serves every path that no route claims. When several route
prefixes match, the longest one wins. `poll` waits once for readiness, until
`deadline` or an earlier internal timeout. It then handles that readiness
and applies timeouts. Call it in a loop.

| Option | Default | Meaning |
| --- | --- | --- |
| `buffer_bytes` | 65536 | Each connection's input buffer. Also the output backlog at which the other side stops reading. |
| `connect_timeout_ms` | 2000 | Upstream connect. |
| `response_timeout_ms` | 10000 | From sending the request head to receiving the response head. |
| `io_timeout_ms` | 10000 | A body that makes no progress in either direction. |
| `head_timeout_ms` | 5000 | A client's request head. |
| `idle_timeout_ms` | 5000 | A client's keep-alive idle time. |
| `pool_idle_ms` | 4000 | Idle time of a pooled upstream connection. |
| `max_idle` | 64 | Idle connections kept per upstream. |
| `upstream_connections` | 128 | Open connections per upstream. Further requests queue for one. |
| `max_requests` | 1000 | Requests per client connection. |
| `via` | `lanius` | The pseudonym in Via. |
| `h2`, `h2_streams`, `h2_stream_window` | true, 100, 65535 | Accept h2c, with this many concurrent streams and this per-stream window. |

## Forwarding semantics

Rewriting follows RFC 9110 7.6 (`ext::http_rewrite`):

- Hop-by-hop fields are dropped both ways: Connection, Proxy-Connection,
  Keep-Alive, TE, Transfer-Encoding and Upgrade, and every field a
  Connection header names.
- X-Forwarded-For gets the client address appended.
- Via gets `1.1 lanius` appended, or `2 lanius` for an HTTP/2 client. Via is
  also added to responses.
- X-Forwarded-Proto is added when it is absent: `http`, or `https` behind
  `ext::http_proxy_tls`.
- An HTTP/2 request becomes an HTTP/1.1 head. `:authority` becomes Host and
  split `cookie` fields are joined with `"; "`. A body with no
  content-length is sent chunked.
- A response is relayed with its own framing: Content-Length, chunked
  (re-chunked for HTTP/1.1 clients), or close-delimited (chunked to an
  HTTP/1.1 client, DATA frames to an HTTP/2 client).
- No body is relayed for HEAD, 204 or 304. Interim 1xx responses are
  skipped. `Expect: 100-continue` is answered by the proxy. A 101 or a
  tunnel gives 502. h2 CONNECT gives 501.

**Pooling.** A response that ends cleanly on a keep-alive upstream
connection returns that connection to its upstream's idle pool. The pool
holds at most `max_idle` connections for at most `pool_idle_ms` each. An
idle pooled connection that turns readable has been closed upstream and is
dropped.

**Retry.** If a request without a body fails on a reused connection before
any response byte arrives, the request is retried once on a new
connection. That failure is the usual race with an upstream's keep-alive
timeout.

**Connection cap.** At `upstream_connections` busy connections per
upstream, further requests queue, oldest first, until a connection frees up.

**Streaming.** Bodies stream both ways through the per-connection buffers.
`ext::http_body` reports at most one content span per step, so a body of
any size passes through `buffer_bytes`. Backpressure is symmetric: a side
stops reading while the other side's output backlog exceeds
`buffer_bytes`. HTTP/2 request bodies stream too: `ext::http2_server`'s
`stream_bodies` option queues a request at its HEADERS, and window credit
is returned only as the proxy forwards the bytes.

**Failures.** Before the response starts, a failed connect or upstream
answers 502, and an expired connect or response timeout answers 504.
After the response starts, the client connection is closed (HTTP/1.1) or
the stream is reset (HTTP/2), and `aborted` is counted. Malformed client
heads get 400, 431 or 501, and a slow head gets 408.

## TLS and ALPN

```lanius
// ext::http_proxy_tls
pub fn proxy(listener: &std::socket::Socket, options: ext::http_proxy::Options, max_clients: i32, context: ext::openssl_tls::ServerContext) -> Result<TlsProxy,Error>;
pub impl TlsProxy { add_upstream, route, poll, stats, tls_stats, active, close }
// ext::tls_clients
pub fn alpn_protocols(out: &alloc::vec::Vec<u8>, h2: bool) -> bool;
pub struct Stats { handshakes: i32, h2: i32, failures: i32, truncated: i32 }
```

Offer protocols on the context first:

```lanius
let list: alloc::vec::Vec<u8> = alloc::vec::new<u8>();
ext::tls_clients::alpn_protocols(list.borrow(), true);
context.set_alpn(list.as_view());
```

`ext::openssl_tls::ServerContext.set_alpn` installs a Lanius function as
OpenSSL's `SSL_CTX_set_alpn_select_cb` callback, which uses the C-callback
support. The callback picks the server's most preferred protocol that the
client offers. With no overlap it leaves ALPN unanswered and the handshake
proceeds without it. A client that selects `h2` runs HTTP/2. Any other
outcome runs HTTP/1.1, including the prior-knowledge h2c preface over TLS.

The transport sends close_notify before half-closing the connection, so
close-delimited responses end cleanly. A client that closes without
close_notify is counted as `truncated`, not as a failure.

**Transport interface.** The proxy does no TLS itself. After
`wrap_clients`, `poll` reports four notices for each wrapped client:

- `ACCEPTED`
- `READY` (with the readiness bits)
- `SHUTDOWN`
- `DROPPED`

A transport implements its side through `ext::client_transport::Clients`.
It moves bytes with `client_input`/`client_received` and
`client_output`/`client_sent`, runs the proxy with `client_ready`, and adds
readiness of its own with `client_hold`. The proxy still owns each epoll
registration and computes the readiness that its buffers need.

`ext::tls_clients` does the TLS work on that interface. It is generic over
any `Clients` implementation, so the same code serves the proxy and
`ext::http_service`'s event Server.

A session can hold decrypted bytes that epoll cannot see. For those
sessions, `wake` returns an immediate deadline while the server would take
more input.

## Executed evidence

Python asyncio upstreams (`tests/fixtures/extended/http_proxy/upstream.py`)
serve per-path behaviours: echo, uploads, fixed, chunked and close-delimited
bodies, HEAD, 304, 100, slow heads, stalls, drops, flaky keep-alive and
streaming echo.

| Group | Clients | Result |
| --- | --- | --- |
| `body_oracle.py` | Generated bodies at several piece sizes, against Python's reading of RFC 9112 framing | `http-body cases=151` |
| `rewrite_oracle.py` | Rewritten heads | `http-rewrite cases=11` |
| `proxy_oracle.py h1` | Raw HTTP/1.1 sockets | `cases=19 requests=23 connects=5 reused=20 retries=2` |
| `proxy_oracle.py errors` | Raw HTTP/1.1 sockets | `cases=12 bad_gateway=2 gateway_timeout=1 rejected=5` |
| `proxy_oracle.py h2` | libnghttp2 client sessions (ctypes) | `cases=13 requests=33 connects=6 reused=28` |
| `tls_oracle.py` (proxy) | Python `ssl` with ALPN, and nghttp2 over TLS | `cases=13 handshakes=5 h2=2 requests=33 failures=1` |
| `http2_server/tls_oracle.py` | `ext::http_service_tls` | `cases=8 handshakes=3 h2=1 requests=40` |

The h1 and h2 groups also check the following: hop-by-hop removal, forwarding fields,
routing, keep-alive and pipelining, bodies up to 5 MB both ways, chunked
trailers, HEAD and 304, the 100-continue rule, streaming echo, the pool
cap, and per-stream failures next to completing streams.

The TLS groups also check the following: TLS 1.2 or 1.3, `X-Forwarded-Proto: https`,
3 MB downloads, a 1 MB upload, chunked and pipelined responses, clean
close_notify on `Connection: close`, no-ALPN fallback, HTTP/2 streaming over
TLS, and a plain-HTTP client dropped at the handshake.

Tests: `tests/extended_http_proxy_execution.rs`.

### Load test

`load.py` runs 100 concurrent clients through the proxy (`load` profile) to
one upstream. First 100 h2c clients each send 20 multiplexed requests, then
100 HTTP/1.1 keep-alive clients each send 20 sequential requests. With
`--tls`, both phases run over TLS (ALPN h2, then http/1.1). Every body and
counter is checked.

Numbers from the 3070 Laptop machine:

| Run | h2 phase | HTTP/1.1 phase | Other |
| --- | --- | --- | --- |
| Plain, quiet machine | 0.42 s (4,763 req/s), proxy CPU 0.42 s | 0.27 s (7,339 req/s), proxy CPU 0.28 s | Direct to the upstream: 0.042 s. Peak RSS 60 MB. |
| Plain, load average 27 | 0.79 s, proxy CPU 0.67 s | 0.55 s, proxy CPU 0.45 s | |
| TLS, load average 27 | 1.04 s (1,915 req/s), proxy CPU 0.85 s | 0.82 s (2,454 req/s), proxy CPU 0.68 s | 200 handshakes. Peak RSS 73 MB. |

### Rewrite cost

`ext::http_rewrite` reads each message's Connection fields once into a
small token set (the first two field values; a third falls back to a full
scan), classifies each field name by length and first byte before one
name compare, and skips the X-Forwarded-For and Via merge scans when the
message has neither. `ext::http::equal_name` now compares lengths before
validating either name.

Same-load comparison (load average 24-26), old against new, two
interleaved runs each:

| Measure | Before | After |
| --- | --- | --- |
| Rewrite a 10-field browser request head | 315 µs | 72 µs |
| Rewrite a 9-field origin response head | 222 µs | 61 µs |
| Load test, h2 phase proxy CPU | 0.47-0.49 s | 0.38-0.40 s |
| Load test, HTTP/1.1 phase proxy CPU | 0.38-0.44 s | 0.33-0.35 s |

The load test's heads carry only two fields, so its gain is smaller than
the per-head gain. Parsing a 10-field head still costs about 57 µs, as
much as rewriting it.

## Limits

- Upstreams are plain HTTP/1.1. Not supported: TLS to upstreams, h2
  upstreams, CONNECT tunnels, WebSocket upgrades, response caching, and
  load balancing beyond prefix routes.
- Failures after the response starts are aborts, not retries.
- One thread.
