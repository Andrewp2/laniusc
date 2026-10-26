# Concurrent local HTTP service

[`http_serve.lani`](../sample_programs/library/http_serve.lani) now uses the
shared [`http_server::Protocol`](library-server-contract.md) through the thin
[`http_server_poll`](../extended/ext/http_server_poll.lani) adapter and the
single [`server_poll`](extended-server-poll.md) scheduler.

**Work in progress:** this application migration is saved against the frozen
interfaces. Compilation and native application acceptance are pending. Earlier
sequential receipts in the [connection guide](extended-http-server.md) do not
establish this concurrent revision. The intended first target is Linux x86_64;
other operating systems and GPU-kernel execution are unverified.

## Invocation and routes

```text
http-serve ADDRESS [OPTIONS]
  --requests N --concurrency N --timeout MS --service-timeout MS --report
  --max-request N --max-response N --max-body N --drain N
  --max-head N --max-line N --max-headers N --max-trailers N
  --max-trailer-bytes N --max-chunks N --max-io N --max-work N
```

ADDRESS is numeric IPv4/IPv6, with port zero permitted. The app prints the
bound endpoint and newline once on stdout. All HTTP bytes use accepted TCP
sockets. IPv6 explicitly selects V6ONLY. The listener and accepted sockets are
nonblocking; SIGPIPE is ignored before host I/O. There are no worker threads,
keepalive requests, proxy forwarding, TLS, tunnels or response replay.

| Request | Final response |
| --- | --- |
| GET/HEAD `/health` | 200 `ok\n` / empty HEAD |
| POST `/echo` | 200 transfer-decoded binary request body |
| OPTIONS any valid target | 204 with `Allow: GET, HEAD, POST, OPTIONS` |
| Missing path | Empty 404 |
| Disallowed known method on a known path | Empty 405 with Allow |
| Other method, including CONNECT | Empty 501 |
| Absolute scheme other than http | Empty 421 |
| Unsupported Expect | Empty 417 before body collection |

Absolute http authorities remain accepted without virtual-host filtering;
origin-form `//` paths retain canonical path classification. Routing preserves
encoded path spelling and ignores query for route selection. Successful health
responses are text/plain; echo uses application/octet-stream. Canonical Date,
Connection and framing fields belong to Protocol. A response is staged through
Reply.stage inside its handler while local header descriptors and the borrowed
request body are live; no Response with expired backing is returned.

The shared explicit Expect policy sends one 100 for supported HTTP/1.1 content
before body collection, including content already buffered. A known excessive
fixed body is rejected first. A normal 2xx final requires the complete validated
request. Early route errors and unsupported Expect do not wait for an upload.
Protocol rejections map to empty 400/431/413/414, or 500 for allocation failure.
Handled syntax/limit rejection can complete with exit zero; allocation retains
exit four. Transport, deadline and exhausted work/I/O failures are terminal,
not permission to send an invented HTTP rejection.

## Admission, limits and deadlines

`--requests` is 1..64, default 1, and counts **every accepted descriptor**,
including failed setup, empty input and malformed requests. `--concurrency` is
1..16, default 4; effective concurrency is min(requests, concurrency). Handshake,
request, response and drain all occupy a slot. At capacity, new sockets stay in
the kernel backlog. A failed connection does not stop healthy siblings or
remaining admission. Each connection handles only its first selected request;
retained tail and later upload bytes are bounded discard, never another request.

`--timeout` is 0..60,000 ms, default 5,000, measured from acceptance. The new
`--service-timeout` is 0..3,840,000 ms and defaults to requests*timeout. One fixed
service deadline covers listener waits and all active owners. A connection's
deadline is min(service deadline, accepted-at+timeout). Neither bytes, callbacks
nor another admission renews either deadline. This changes the former sequential
scope, where each slot's timeout began before waiting to accept it.

Per-connection HTTP defaults remain those in the [connection guide](extended-http-server.md):
1 MiB body/drain, 2 MiB request and final response, 1,048,576 attempted active
I/O/participation calls and 268,435,456 protocol-work units. Byte/count flags
accept 0..64 MiB; io/work accept 0..i32MAX with io positive. max-body sets both
request and response body caps. Other HTTP head/line/count flags configure the
request side. Paired flags use separate values; repeats select the last value.
Argument capture permits 64 arguments and 8,192 bytes.

Service reservations are explicit derived bounds: work=requests*per-owner-work;
live bytes=effective-concurrency*Protocol.reservation_bytes(options). The latter
includes response-staging candidates and is not RSS, native heap or allocator
capacity. With n=requests and i=per-owner-I/O, attempted accepts are bounded by
n*(i+1); issued wait permits by 1024+n*(i+1)+16*n*(i+1); scheduler operations by
1024+n*(i+1)+32*n*(i+work+1); handler calls by 3*n. CLI bounds keep this arithmetic
within u64. Child I/O counts exclude listener acceptance; one fixed 25-byte 100
is counted separately from the final response byte cap.

## Results and output

With --report, the app writes one bounded stderr record for every accepted ID,
in acceptance order after the run. IDs are dense from zero and never reused:

```text
received=... sent=... response=... interim=... drain=... tail=... io=... cleanup=... cleanup-errors=... work=... scan=... id=... rejected=... shutdown=... eof=... closed=... code=... failed=...
```

sent counts confirmed final-response bytes; response is the final encoded
length; interim counts confirmed Continue bytes separately. io includes
conservative per-owner wait participation, not physical shared polls. rejected
marks the retained original rejection. shutdown/eof/closed reflect actual
recorded side effects. code is that outcome's exit class; failed means code is
nonzero, independently of other outcomes. Plain transport has no TLS counter;
no missing counter is reported as zero.

Exit zero includes completed HTTP error responses and clean empty connections.
Exit 2 is argument failure, 3 transport/protocol/budget failure, 4 allocation,
and 5 signal or stdout/stderr failure. A global service failure determines the
primary run status; otherwise the first nonzero acceptance-order outcome does.
Report output failure overrides it with 5. Every reached owner is destroyed;
Report.get returns borrowed metadata and is never separately destroyed.

Startup and each report have independent eight-attempt write budgets. EINTR
spends an attempt, short writes resume, and zero progress/EAGAIN/errors fail.
These host descriptors may block inside a write, outside the network deadline.
Plain teardown uses checked write shutdown and bounded discard to actual EOF;
full sends alone do not prove peer delivery. See the shared contract for exact
drain lookahead and primary/secondary cleanup failure behavior.
