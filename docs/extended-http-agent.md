# HTTP client agent

`ext::http_agent` is a synchronous HTTP/1.1 and HTTP/2 client for `http://`
and `https://` URLs. It adds four things to the client stack:

- a keep-alive connection pool keyed by scheme, host and port, with
  idle-count, idle-time and per-connection use limits, for cleartext and
  verified TLS connections alike;
- redirect following with a hop limit, method rules and an origin policy for
  credentials;
- request bodies that are either fixed (`Content-Length`) or streamed from any
  `core::io::Read` source as `Transfer-Encoding: chunked`;
- [HTTP/2](#http2) for https origins that select `h2` by ALPN: one
  multiplexed connection per origin, and `fetch_all` to run requests
  concurrently on it;
- [streamed response bodies](#streamed-response-bodies): `fetch_to` writes a
  body of any size to a `core::io::Write` sink as it arrives.

Response framing comes from the incremental [`ext::http`](extended-http.md)
cursor, and the final message is checked once by the canonical parser. URLs
come from [`ext::http_url`](extended-http-url.md), reference resolution uses
[`ext::uri`](extended-uri.md) syntax, and connections come from
[`ext::url_connect`](extended-url-client.md) (resolution through libc, then
ordered connect attempts). TLS comes from
[`ext::tls_stream`](../extended/ext/tls_stream.lani) over
[`ext::openssl_tls`](extended-openssl-tls.md). Programs that use the agent
therefore link natively, against `libssl` and `libcrypto` as well, and must
ignore SIGPIPE before their first https request (OpenSSL writes with
`write`).

The existing [`ext::http_client`](extended-http-client.md) remains the
resumable one-exchange engine shared with the TLS drivers. It always sends
`Connection: close`. This module is the layer for programs that make several
requests: it keeps connections open between requests and follows redirects.
The sample [`http_curl`](../sample_programs/library/http_curl.lani) is a small
curl-like command built on it.

## API

```lanius
pub struct Request { method: View<u8>, url: View<u8>, headers: View<ext::http::Field>, body: View<u8> }
pub fn default_options() -> Options;
pub fn agent(options: Options) -> Result<Agent,Error>;
pub fn fetch_stream<R>(agent: &Agent, request: Request, source: &R) -> Result<Response,Error> where R: core::io::Read;
pub fn fetch_to<W>(agent: &Agent, request: Request, sink: &W) -> Result<Response,Error> where W: core::io::Write;
pub fn fetch_stream_to<R,W>(agent: &Agent, request: Request, source: &R, sink: &W) -> Result<Response,Error> where R: core::io::Read, W: core::io::Write;
pub fn resolve(base: View<u8>, location: View<u8>, out: &Vec<u8>) -> bool;

pub impl Agent {
    pub fn fetch(&self, request: Request) -> Result<Response,Error>;
    pub fn fetch_all(&self, requests: View<Request>, results: &Vec<Result<Response,Error>>) -> i32;
    pub fn preconnect(&self, url: View<u8>, count: i32) -> Result<i32,Error>;
    pub fn dial(&self, url: &ext::http_url::Url, deadline: Deadline) -> Result<Connection,Error>;
    pub fn stats(&self) -> Stats;
    pub fn idle(&self) -> i32;
    pub fn sessions(&self) -> i32;
    pub fn clear(&self) -> i32;
    pub fn close(&self) -> bool;
}
pub impl Response {
    pub fn status(&self) -> i32;
    pub fn version(&self) -> i32;
    pub fn head(&self) -> View<u8>;
    pub fn header(&self, name: View<u8>) -> Option<View<u8>>;
    pub fn body(&self) -> View<u8>;
    pub fn url(&self) -> View<u8>;
    pub fn streamed(&self) -> i64;
    pub fn destroy(&self) -> bool;
}
pub impl Connection {
    pub fn send(&self, data: View<u8>, deadline: Deadline) -> Result<i32,Error>;
    pub fn receive(&self, space: View<u8>, deadline: Deadline) -> Result<i32,Error>;
    pub fn is_secure(&self) -> bool;
    pub fn is_open(&self) -> bool;
    pub fn close(&self, graceful: bool) -> bool;
}
```

`View`, `Vec`, `Option`, `Result` and `Deadline` abbreviate the
`core::slice`, `alloc::vec`, `core::option`, `core::result` and `core::time`
types.

- **`fetch`** sends `request.body` with a fixed length.
- **`fetch_stream`** reads `source` until EOF and sends it as chunks of up to
  `chunk_bytes` (16 KiB by default), then the zero-size last chunk. The request
  body field is ignored.
- **`Response`** has one manual owner; call `destroy` once you are done with
  its views.
  - `version()` is 10 or 11 for HTTP/1.x and 20 for HTTP/2.
  - `head()` is the raw final response head. For HTTP/2 it is the response
    fields as `name: value` CRLF lines with lowercase names and no status
    line; `header(name)` searches them case-insensitively either way.
  - `body()` is the decoded body. A fixed or close-delimited body is served in
    place from the receive buffer; a chunked body is decoded into its own
    buffer, and its trailers are discarded.
  - `url()` is the final URL after redirects.
  - The `redirects`, `reused` and `kept` fields record how many hops were
    followed, whether the final hop used a pooled connection, and whether that
    connection went back to the pool.
- **`fetch_all`** appends one result per request, in order, and returns
  how many succeeded (see [HTTP/2](#http2)).
- **`close`** closes every pooled and HTTP/2 connection and releases the
  pool. After it the agent rejects new requests.

### Streamed response bodies

`fetch_to` is `fetch` with the final response's body written to `sink` as
it arrives, and `fetch_stream_to` is `fetch_stream` with the same. The
returned `Response` keeps the head (`head()`, `header()`, `status()`,
`version()`, `url()`), `body()` is empty and `streamed()` is the number of
body bytes written; it is -1 for a buffered response.

- **HTTP/1.1.** Once the final head is parsed, the body goes through an
  [`ext::http_body`](extended-http-proxy.md) framer and a buffer of at most
  64 KiB past the head, for fixed, chunked and close-delimited bodies alike.
  Chunk extensions and trailers are checked and dropped.
- **HTTP/2.** The stream's DATA is passed to the sink after each read from
  the connection, and the engine forgets it
  (`ext::http2::Connection.take_body`). Flow-control credit is returned as
  DATA arrives, as for buffered responses.
- **Limits.** `limits.body_bytes` does not bound a streamed body. Over HTTP/2
  it bounds the DATA received between two sink writes. The exchange
  deadline (`timeout_ms`) still covers the whole transfer.
- **Redirects.** A redirect the agent follows (`follow_redirects`, a
  redirect status and a `Location`) is read and buffered as usual. The final
  response, whatever its status, goes to the sink.
- **Sink errors.** A failed write ends the request with `Sink(error)`. Over
  HTTP/1.1 the connection is closed; over HTTP/2 the stream is reset with
  CANCEL and the connection stays open.
- **Retries.** A stale-connection retry happens only before any response
  byte arrives, so the sink never sees a body twice. Once bytes have been
  written, a failure is returned as is, with the sink holding a partial
  body.

The [`agent-fetch` sample](#fetch-sample) uses `fetch_to` with stdout or a
file as the sink.

### Request head

The agent writes:

1. the request line, using the URL's origin-form target;
2. exactly one `Host`, from the URL authority;
3. the caller's fields, in order;
4. the framing.

POST, PUT and PATCH always carry `Content-Length`. Other methods carry it only
when the body is nonempty. A streamed body uses `Transfer-Encoding: chunked`.

Caller fields must be valid tokens with values free of CR, LF, NUL and other
control bytes except tab. The agent owns these names, and a request that
supplies one fails with `InvalidHeader` before any connection is made:

- `Host`, `Connection`, `Keep-Alive`;
- `Content-Length`, `Transfer-Encoding`, `TE`, `Trailer`;
- `Upgrade`, `Expect`;
- any name beginning with `Proxy-`.

`CONNECT` and invalid method tokens fail with `InvalidRequest`.

## HTTPS

An `https://` request, or a redirect to one, uses a verified TLS connection.
The agent creates one OpenSSL client context at its first https use, from
`Options.trust` (`Trust::DefaultPaths` by default, or `Trust::CaFile(path)`)
and `Options.tls` (`openssl_tls::default_limits()`), and keeps it until
`close`. The OpenSSL wrapper's peer policy applies unchanged: chain
verification, a mandatory DNS or IP identity taken from the URL host (DNS
names also send SNI), and TLS 1.2 as the minimum. A certificate failure,
including one on a redirect hop, fails with `Tls(error)` before any HTTP byte
is sent. Set `Options.https` to false to refuse https URLs and redirects
with `UnsupportedScheme`.

Each connection is a [`tls_stream`](../extended/ext/tls_stream.lani) over
the socket from `ext::url_connect`, adopted by
`adopt_connected_with_context_until` (resolution and connect attempts are
the same as for cleartext). Pooling, reuse limits, stale retries and
redirects work exactly as below. Three details differ from cleartext:

- **Idle probe.** TLS 1.3 servers send session tickets after the handshake,
  so a parked connection can be readable without being dead. At checkout a
  readable TLS connection gets one nonblocking TLS read
  (`Stream.idle_probe`): only post-handshake records keep it, and
  application data, close_notify or EOF make it stale.
- **Unauthenticated EOF.** A TCP close without close_notify ends the
  response like EOF, so a length-framed or chunked response still completes
  and an empty reply on a reused connection is still retried. A
  close-delimited body cannot be trusted that way and fails with
  `Truncated(n)`.
- **Early responses.** A readable socket can again mean session tickets, so
  an upload is not cut short by polling. A server that answers before
  reading the body and resets the connection ends the request with
  `Io(error)`, since a failed TLS stream is closed at once.

Pooled TLS connections are closed with a close_notify when it can be sent
within 200 ms.

## HTTP/2

With `Options.http2` set (the default), every new https connection offers
`h2` and `http/1.1` by ALPN (`tls_stream::adopt_connected_with_alpn_until`,
`openssl_tls::Session.set_alpn`). When the server selects `h2`, the
connection runs [`ext::http2`](extended-http2.md) and becomes the origin's
HTTP/2 connection: later requests to the same host and port are streams on
it, without the pool. An origin that selects `http/1.1`, or nothing, is
served by the HTTP/1.1 code above, and its connections are pooled as
before. `dial` never offers `h2`, since upgrades need HTTP/1.1.

A request becomes one stream: `:method`, `:scheme`, `:authority` (the URL
authority) and `:path` (the origin-form target), then the caller's fields
with lowercase names, and `content-length` on the HTTP/1.1 rules. A fixed
body goes out as DATA; a streamed body is read in `chunk_bytes` pieces, each
sent as flow control allows, with END_STREAM after EOF, and no chunked
coding. The engine's limits come from the agent's: `limits.body_bytes` per
response and `limits.head_bytes` as the advertised header list size.
Trailers are dropped, as for HTTP/1.1. Redirects, the deadline per exchange
and the `Response` interface are unchanged.

Reuse follows the pool's options. Before each request the agent reads, without
waiting, anything the server sent the idle connection (SETTINGS, PING,
GOAWAY). It closes the connection, with GOAWAY(NO_ERROR) when that can be
sent within 200 ms, once it is idle past `idle_timeout_ms` (counted as
`expired`), after `max_uses` streams, after a GOAWAY from the server, on a
transport or connection error, and when pooling is disabled.

Retries:

- a stream the server refused (RST_STREAM REFUSED_STREAM, or above a
  GOAWAY's last stream) is retried once, whatever the method, when no
  streamed body was read;
- a request on a reused HTTP/2 connection that fails before any response is
  retried once on the HTTP/1.1 stale rules (idempotent, `retry_stale`).

`fetch_all` runs the requests to each https origin that negotiates HTTP/2
as concurrent streams of its connection, starting more as streams finish
when the server's MAX_CONCURRENT_STREAMS is lower. Each origin's batch has
one `timeout_ms` deadline. All other requests, and any that a server
refused, are then fetched one at a time like `fetch`. `fetch_all` does not
follow redirects: a redirect is returned as the response.

## Connection pool

The pool key is the URL scheme, host (ASCII case-insensitive) and port. So
`127.0.0.1` and `localhost` are separate keys even when they reach the same
server, and `http://h:8443` never reuses a TLS connection to `https://h:8443`. A finished exchange goes back to the pool only when:

- the response is HTTP/1.1 without `Connection: close`, or HTTP/1.0 with
  `Connection: keep-alive`;
- its body is not close-delimited;
- no bytes followed the response;
- any upload finished normally;
- the connection has been used fewer than `max_uses` times.

Otherwise the connection is closed.

| Option | Default | Meaning |
| --- | --- | --- |
| `max_idle_per_host` | 4 | Parking beyond this closes that host's oldest idle connection. |
| `max_idle_total` | 16 | Parking beyond this closes the oldest idle connection overall. |
| `idle_timeout_ms` | 15000 | An idle connection older than this is closed at the next checkout. |
| `max_uses` | 100 | Requests per connection (streams per HTTP/2 connection) before it is retired. |

A server `Keep-Alive: timeout=N` header shortens the idle time to
`N` seconds minus 500 ms. Setting either idle limit to 0 disables pooling;
requests then send `Connection: close`.

At checkout the agent polls the most recently parked matching connection with
a zero timeout. An idle HTTP/1.1 connection should have nothing to read, so a
readable socket (EOF or unsolicited bytes) is counted as stale and closed, and
the next candidate is tried.

A server can still close a pooled connection after that probe, so a request
can fail on a reused connection before any response byte arrives. The agent
retries such a request once on a new connection when all of these hold:

- the failure was an EOF, `EPIPE` or `ECONNRESET`;
- the method is idempotent (GET, HEAD, PUT, DELETE, OPTIONS, TRACE);
- the body is replayable: a streamed body counts only if nothing was read
  from its source yet;
- `retry_stale` is set.

POST is never retried.

`preconnect(url, count)` opens `count` new connections to the URL's origin and
parks them under the same limits. Without it, a synchronous agent only ever
holds one connection per host, so the per-host limit matters mainly after
preconnecting.

`Stats` counts:

| Field | Counts |
| --- | --- |
| `connections` | connections opened |
| `reused` | pooled checkouts |
| `requests` | exchanges sent, including retries and redirect hops |
| `redirects` | redirects followed |
| `retries` | stale-connection retries |
| `stale` | pooled connections found closed or readable at checkout |
| `evicted` | idle connections closed by the count limits |
| `expired` | idle connections closed by idle time |
| `early` | uploads cut short by an early final response |
| `http2` | connections that negotiated HTTP/2 (also in `connections`) |

A request on an HTTP/2 connection that was already open counts as
`reused`. `idle()` counts parked HTTP/1.1 connections and `sessions()` open
HTTP/2 connections.

## Redirects

With `follow_redirects` set (the default), these statuses are followed when
they carry a `Location`: 301, 302, 303, 307 and 308. A redirect without
`Location`, and every other status, is returned as the final response. The
`Location` is resolved against the current URL as an RFC 3986 reference,
including dot-segment removal; any fragment is dropped.

| Status | Method rule |
| --- | --- |
| 303 | Every method except HEAD becomes GET without a body. |
| 301, 302 | POST becomes GET without a body; other methods are kept. |
| 307, 308 | Method and body are kept. |

When the body is dropped, `Content-Type`, `Content-Encoding`,
`Content-Language` and `Content-Location` go with it. A fixed body is sent
again. A streamed body cannot be read again, so a redirect that keeps it
fails with `UnreplayableBody(status)`. A hop to a different host, port or
scheme drops `Authorization` and `Cookie`, so an http→https upgrade on the
same host drops them too. Downgrades from https to http are followed.

There are three ways a redirect ends the request with an error:

- `max_redirects` (default 10) bounds the hops: a further redirect fails with
  `TooManyRedirects(hops)`;
- a `Location` that does not resolve to a valid http or https URL fails
  with `BadLocation`;
- an `https://` target fails with `UnsupportedScheme` when `Options.https`
  is false.

The response body of every followed redirect is read in full. The connection
therefore goes back to the pool and is used for the next hop when the host is
the same.

## Uploads and early responses

A streamed body is read with repeated `read` calls until each chunk is full or
the source reaches EOF. Before each chunk, the agent polls the socket.
Suppose a final response is already readable, for example a `413` sent before
the server reads the body, or the send fails with `EPIPE` or `ECONNRESET`.
Then the agent stops uploading, reads that response and returns it. That
connection is not pooled, because its request was never completed. A read
error from the source fails with `Source(error)`.

## Connections for upgrades

`dial` opens a fresh connection to a parsed `http://` or `https://` URL's
origin, the same way the agent opens its own: resolution, ordered connect
attempts, and verified TLS with the agent's `trust` and `tls` options. The
connection never enters the pool. It is for protocols that take over the
connection after an HTTP/1.1 upgrade;
[`ext::websocket_client`](extended-websocket-client.md) uses it. A
`Connection` has one owner and is closed once. Each call takes its own
absolute deadline.

- `send` writes all of `data`.
- `receive` waits for at least one byte. `Ok(0)` is a clean EOF (a TCP FIN or
  TLS close_notify) and `Truncated(0)` is a TLS EOF without close_notify.
  `Timeout` leaves the connection usable, over TLS too: TLS reads are tried
  without blocking, then the socket is polled, so a quiet peer does not abort
  the TLS stream.
- `close(true)` sends TLS close_notify first; `close(false)` drops the
  transport.

## Deadlines, limits and errors

Each exchange has one absolute deadline of `timeout_ms` (default 30 s),
covering connect, send and receive. A slow drip of bytes cannot extend it.
Each retry and each redirect hop gets a fresh deadline.

Response limits come from `Options.limits` (`ext::http::default_limits()`:
64 KiB heads, 8 KiB lines, 100 fields, 16 MiB bodies). The receive buffer
grows by doubling. A fixed-length body reserves its full size once its head
is known. Up to `max_informational` (8) 1xx responses are skipped. A `101`
fails with `UnexpectedUpgrade`.

| Error | When |
| --- | --- |
| `InvalidRequest`, `InvalidHeader` | bad options, method or caller field |
| `Url(kind)` | the request URL does not parse |
| `UnsupportedScheme` | `https://` request or redirect with `Options.https` false |
| `Tls(error)` | TLS context, identity, handshake or certificate verification failure |
| `Connect(cause)` | resolution or every connect attempt failed |
| `Io(error)` | send or receive error, such as a reset mid-response |
| `Timeout` | the exchange deadline passed |
| `Truncated(n)` | EOF after `n` response bytes; `n` = 0 is an empty reply |
| `Parse(error)` | malformed status line, fields, chunking or framing |
| `TooLarge` | a head, line, body or informational limit was exceeded |
| `TooManyRedirects(n)`, `BadLocation`, `UnreplayableBody(status)` | redirect failures |
| `UnexpectedUpgrade` | a `101` response |
| `Http2(error)` | an HTTP/2 stream or connection error: a reset or GOAWAY from the server, a protocol violation or a malformed response |
| `Source(error)` | the streamed body's source failed |
| `Sink(error)` | writing a streamed response body to the sink failed |
| `AllocationFailed`, `Clock` | resource failures |

A valid 4xx or 5xx response is a successful result; check `status()`.

## curl-like sample

```text
http-curl [-X METHOD] [-H 'Name: value']... [-d DATA | -T FILE|-] [-L]
          [--max-redirs N] [-i] [-I] [-f] [--max-time MS]
          [--max-idle-per-host N] [--max-idle N] [--idle-timeout MS]
          [--max-uses N] [--preconnect N] [--pause MS] [--no-retry] [--stats]
          [--cacert FILE] [--no-https] [--http1.1] [--parallel] URL...
```

The sample fetches each URL in turn through one agent and writes the bodies
to stdout.

- `-L` follows redirects (off by default, as in curl).
- `-d` sends a fixed POST body.
- `-T` streams a file, or stdin with `-`, as a chunked PUT.
- `-i` prints the head before the body, and `-I` sends HEAD.
- `-f` fails on statuses of 400 and above.
- `--pause` waits between URLs.
- `--cacert FILE` trusts the PEM certificates in FILE instead of the system
  default paths; `--no-https` refuses https URLs.
- `--http1.1` turns HTTP/2 off; `--parallel` fetches all URLs with
  `fetch_all` (no redirects, no `-T`).
- `--stats` writes one `response ...` line per URL and one `pool ...` line to
  stderr.

The exit codes follow curl:

| Code | Meaning |
| --- | --- |
| 1 | unsupported scheme |
| 16 | HTTP/2 error |
| 3 | bad URL or Location |
| 7 | connect failed |
| 8 | malformed response or upgrade |
| 18 | truncated response |
| 22 | `-f` and status ≥ 400 |
| 26 | upload read error |
| 28 | timeout |
| 35 | other TLS failure (handshake, unreadable CA file) |
| 47 | too many redirects |
| 52 | empty reply |
| 56 | receive error |
| 63 | too large |
| 60 | certificate verification failed |
| 65 | redirect needs the streamed body again |

## Fetch sample

```text
agent-fetch [-o FILE] [-X METHOD] [-H 'NAME: VALUE']... [-d DATA | -T FILE|-]
            [-L] [--max-redirs N] [-m|--max-time MS] [--connect-timeout MS]
            [-D FILE|-] [-I] [-f] [--cacert FILE] [--no-http2] [--stats] URL...
```

[`agent_fetch`](../sample_programs/library/agent_fetch.lani) fetches each
URL in turn through one agent with `fetch_to` (or `fetch_stream_to` with
`-T`), so every body streams to stdout or to `-o FILE` through a fixed
buffer, at any size. Options are parsed by [`std::cli`](stdlib-cli.md)
(GNU `getopt_long` rules: `-oFILE`, `--max-time=MS`, `--` and `--help`).
It differs from `http-curl` in three ways:

- `--connect-timeout` sets `Options.connect.attempt_timeout` for each
  connect attempt. `--max-time` is the exchange deadline, transfer included.
- `-D FILE` writes each final head to FILE after its body; `-` is stderr.
  For HTTP/2 that is the field lines.
- `-f` exits 22 after the body has been written (curl's
  `--fail-with-body`), since the body streams before the status is
  checked.

`--stats` writes `response status= version= streamed= redirects= reused=
kept= url=` per URL and one `pool ...` line to stderr. Exit codes are the
`http-curl` ones, plus 23 for an output write error (`Sink`) and 2 for
command-line errors. The sample was named `agent-fetch` because
`sample_programs/library/fetch.lani` (the one-request URL client) and the
module `ext::http_client` (the one-exchange engine) already exist.

## Executed evidence

`tests/extended_http_agent_execution.rs` compiles the sample with native
linking against `libssl` and `libcrypto`. It runs
`tests/fixtures/extended/http_agent/oracle.py` against two Python
`http.server` origins, scripted raw-socket servers and, for the https group,
two Python `ssl` origins. Their test root, server certificates and keys are
generated for each run with the installed `openssl` CLI by
[`certificates.py`](../tests/fixtures/extended/openssl_tls/certificates.py);
nothing is checked in or downloaded. Every case
checks:

- the exit code and output;
- the client's `response`/`pool` statistics (`version`, `http2`, `sessions`
  included);
- the server-observed connection and request counts.

| Group | Cases | Covers |
| --- | --- | --- |
| pool | 18 | reuse, per-host keys, total and per-host eviction, use limit, idle and `Keep-Alive` expiry, `Connection: close`, HTTP/1.0, trailing bytes, stale probe, GET retry vs. no POST retry, disabled pool, chunked and HEAD/204 reuse |
| redirect | 29 | chains on one connection, hop limits and loops, the 11-row method/body table, HEAD on 303, relative/dot/query/fragment/network-path references, credential stripping, missing/https/malformed `Location`, streamed body on 307 vs. 303 |
| upload | 10 | stdin and file chunked uploads with exact chunk counts, empty stream, fixed body, PATCH, no length on GET, early `413` during a 32 MiB upload, `-f`, reserved and injected headers |
| https | 17 | TLS reuse over 127.0.0.1 (IP identity) and localhost (DNS identity, SNI), http→https redirect with credential stripping and pooled reuse afterwards, https→http redirect, scheme-separated pool keys on one port, 1 MB fixed and 250 KB chunked bodies, 3 MiB chunked upload, fixed POST, stale TLS connection, retry after an EOF without close_notify, `--no-retry` empty reply, preconnected TLS connections kept through their session tickets, untrusted root, expired certificate (also on a redirect hop), `--no-https`, missing CA file |
| broken | 21 | empty reply, truncated head and body, garbage, bad chunk size, CL+TE, conflicting lengths, stalled head and body, slow drip within and past the deadline, 101, oversized head, too many 1xx, 100+103 then 200, close-delimited body, HEAD with a length, refused connect, bad and https URLs, reset mid-body |

The HTTP/2 group is
[`tests/fixtures/extended/http2/agent_oracle.py`](../tests/fixtures/extended/http2/agent_oracle.py),
run by the same test file against libnghttp2's server session over TLS with
ALPN `h2` ([`h2server.py`](../tests/fixtures/extended/http2/h2server.py),
through ctypes; Python's `h2` and `nghttpd` are not installed here). The
server reports every stream, the client's SETTINGS and GOAWAY, and its peak
number of concurrent streams.

| Group | Cases | Covers |
| --- | --- | --- |
| h2 | 21 | ALPN selection and pseudo-fields, three requests as streams 1/3/5 of one connection with a 300 KB body, 8 `--parallel` 400 ms requests in under 2.5 s with 8 streams open at once, a server limit of 2 concurrent streams, `--parallel` across an HTTP/2 and an HTTP/1.1 origin in order, fixed and 400 KB streamed uploads under flow control, an empty stream, methods and caller fields, 60 × 400-byte response fields (CONTINUATION), trailers, 103 then 200, HEAD, a redirect on the same connection, `-f`, RST_STREAM (exit 16) and a refused stream retried once, GOAWAY then a new connection, server PING, idle expiry, `max_uses`, HTTP/1.1 fallback and `--http1.1` (ALPN seen by the server), certificate verification |

```text
http-agent-pool cases=18 connections=33 requests=44
http-agent-redirect cases=29 connections=31 requests=67
http-agent-upload cases=10 connections=8 requests=9
http-agent-broken cases=21 connections=18 requests=1
http-agent-https cases=17 connections=22 requests=27
http2-agent-h2 cases=21 connections=23 requests=43
```

The https group runs in about 3 seconds, the whole oracle in about 12, and
the HTTP/2 group in about 4.

## Limits of this version

- TLS has no session resumption, client certificates or option to disable
  verification.
- The agent is synchronous. Over HTTP/1.1 it runs one exchange at a time,
  with no pipelining; concurrency needs HTTP/2 and `fetch_all`. Cleartext
  `h2c` is not offered.
- It does not implement cookies, authentication challenges, proxies,
  decompression or `Expect: 100-continue`.
- Response trailers are discarded.
- Bodies are buffered whole, up to `limits.body_bytes`; there is no streaming
  response reader.
