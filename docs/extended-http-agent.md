# HTTP/1.1 client agent

`ext::http_agent` is a synchronous HTTP/1.1 client for cleartext `http://`
URLs. It adds three things to the client stack:

- a keep-alive connection pool keyed by host and port, with idle-count,
  idle-time and per-connection use limits;
- redirect following with a hop limit, method rules and an origin policy for
  credentials;
- request bodies that are either fixed (`Content-Length`) or streamed from any
  `core::io::Read` source as `Transfer-Encoding: chunked`.

Response framing comes from the incremental [`ext::http`](extended-http.md)
cursor, and the final message is checked once by the canonical parser. URLs
come from [`ext::http_url`](extended-http-url.md), reference resolution uses
[`ext::uri`](extended-uri.md) syntax, and connections come from
[`ext::url_connect`](extended-url-client.md) (resolution through libc, then
ordered connect attempts). Programs that use it therefore link natively.

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
pub fn resolve(base: View<u8>, location: View<u8>, out: &Vec<u8>) -> bool;

pub impl Agent {
    pub fn fetch(&self, request: Request) -> Result<Response,Error>;
    pub fn preconnect(&self, url: View<u8>, count: i32) -> Result<i32,Error>;
    pub fn stats(&self) -> Stats;
    pub fn idle(&self) -> i32;
    pub fn clear(&self) -> i32;
    pub fn close(&self) -> bool;
}
pub impl Response {
    pub fn status(&self) -> i32;
    pub fn head(&self) -> View<u8>;
    pub fn header(&self, name: View<u8>) -> Option<View<u8>>;
    pub fn body(&self) -> View<u8>;
    pub fn url(&self) -> View<u8>;
    pub fn destroy(&self) -> bool;
}
```

`View`, `Vec`, `Option` and `Result` abbreviate the `core::slice`,
`alloc::vec`, `core::option` and `core::result` types.

- **`fetch`** sends `request.body` with a fixed length.
- **`fetch_stream`** reads `source` until EOF and sends it as chunks of up to
  `chunk_bytes` (16 KiB by default), then the zero-size last chunk. The request
  body field is ignored.
- **`Response`** has one manual owner; call `destroy` once you are done with
  its views.
  - `head()` is the raw final response head.
  - `body()` is the decoded body. A fixed or close-delimited body is served in
    place from the receive buffer; a chunked body is decoded into its own
    buffer, and its trailers are discarded.
  - `url()` is the final URL after redirects.
  - The `redirects`, `reused` and `kept` fields record how many hops were
    followed, whether the final hop used a pooled connection, and whether that
    connection went back to the pool.
- **`close`** closes every pooled connection and releases the pool. After it
  the agent rejects new requests.

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

## Connection pool

The pool key is the URL host (ASCII case-insensitive) and port. So
`127.0.0.1` and `localhost` are separate keys even when they reach the same
server. A finished exchange goes back to the pool only when:

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
| `max_uses` | 100 | Requests per connection before it is retired. |

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
scheme drops `Authorization` and `Cookie`.

There are three ways a redirect ends the request with an error:

- `max_redirects` (default 10) bounds the hops: a further redirect fails with
  `TooManyRedirects(hops)`;
- a `Location` that does not resolve to a valid http URL fails with
  `BadLocation`;
- an `https://` target fails with `UnsupportedScheme`.

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
| `UnsupportedScheme` | `https://` request or redirect |
| `Connect(cause)` | resolution or every connect attempt failed |
| `Io(error)` | send or receive error, such as a reset mid-response |
| `Timeout` | the exchange deadline passed |
| `Truncated(n)` | EOF after `n` response bytes; `n` = 0 is an empty reply |
| `Parse(error)` | malformed status line, fields, chunking or framing |
| `TooLarge` | a head, line, body or informational limit was exceeded |
| `TooManyRedirects(n)`, `BadLocation`, `UnreplayableBody(status)` | redirect failures |
| `UnexpectedUpgrade` | a `101` response |
| `Source(error)` | the streamed body's source failed |
| `AllocationFailed`, `Clock` | resource failures |

A valid 4xx or 5xx response is a successful result; check `status()`.

## curl-like sample

```text
http-curl [-X METHOD] [-H 'Name: value']... [-d DATA | -T FILE|-] [-L]
          [--max-redirs N] [-i] [-I] [-f] [--max-time MS]
          [--max-idle-per-host N] [--max-idle N] [--idle-timeout MS]
          [--max-uses N] [--preconnect N] [--pause MS] [--no-retry] [--stats] URL...
```

The sample fetches each URL in turn through one agent and writes the bodies
to stdout.

- `-L` follows redirects (off by default, as in curl).
- `-d` sends a fixed POST body.
- `-T` streams a file, or stdin with `-`, as a chunked PUT.
- `-i` prints the head before the body, and `-I` sends HEAD.
- `-f` fails on statuses of 400 and above.
- `--pause` waits between URLs.
- `--stats` writes one `response ...` line per URL and one `pool ...` line to
  stderr.

The exit codes follow curl:

| Code | Meaning |
| --- | --- |
| 1 | unsupported scheme |
| 3 | bad URL or Location |
| 7 | connect failed |
| 8 | malformed response or upgrade |
| 18 | truncated response |
| 22 | `-f` and status ≥ 400 |
| 26 | upload read error |
| 28 | timeout |
| 47 | too many redirects |
| 52 | empty reply |
| 56 | receive error |
| 63 | too large |
| 65 | redirect needs the streamed body again |

## Executed evidence

`tests/extended_http_agent_execution.rs` compiles the sample with native
linking. It runs `tests/fixtures/extended/http_agent/oracle.py` against two
Python `http.server` origins and scripted raw-socket servers. Every case
checks:

- the exit code and output;
- the client's `response`/`pool` statistics;
- the server-observed connection and request counts.

| Group | Cases | Covers |
| --- | --- | --- |
| pool | 18 | reuse, per-host keys, total and per-host eviction, use limit, idle and `Keep-Alive` expiry, `Connection: close`, HTTP/1.0, trailing bytes, stale probe, GET retry vs. no POST retry, disabled pool, chunked and HEAD/204 reuse |
| redirect | 29 | chains on one connection, hop limits and loops, the 11-row method/body table, HEAD on 303, relative/dot/query/fragment/network-path references, credential stripping, missing/https/malformed `Location`, streamed body on 307 vs. 303 |
| upload | 10 | stdin and file chunked uploads with exact chunk counts, empty stream, fixed body, PATCH, no length on GET, early `413` during a 32 MiB upload, `-f`, reserved and injected headers |
| broken | 21 | empty reply, truncated head and body, garbage, bad chunk size, CL+TE, conflicting lengths, stalled head and body, slow drip within and past the deadline, 101, oversized head, too many 1xx, 100+103 then 200, close-delimited body, HEAD with a length, refused connect, bad and https URLs, reset mid-body |

```text
http-agent-pool cases=18 connections=33 requests=44
http-agent-redirect cases=29 connections=31 requests=67
http-agent-upload cases=10 connections=8 requests=9
http-agent-broken cases=21 connections=18 requests=1
```

The whole oracle runs in about 9 seconds.

## Limits of this version

- Cleartext only. HTTPS needs the TLS driver from
  [`ext::https_client`](extended-https-client.md) under the pool.
- The agent is synchronous: one exchange at a time, with no pipelining and no
  concurrent requests.
- It does not implement cookies, authentication challenges, proxies,
  decompression or `Expect: 100-continue`.
- Response trailers are discarded.
- Bodies are buffered whole, up to `limits.body_bytes`; there is no streaming
  response reader.
