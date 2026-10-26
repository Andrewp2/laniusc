# A bounded HTTPS health and echo service

[`sample_programs/library/https_serve.lani`](../sample_programs/library/https_serve.lani)
serves one request per TLS connection, sequentially, using system OpenSSL for
TLS and the existing [`ext::http`](extended-http.md) request parser, framing
cursor, body decoder and response encoder. It is a concrete native HTTPS
service with explicit resource owners and finite processing bounds.

The verified executable profile is Linux x86_64, linked through the native C
profile to `libssl.so.3` and `libcrypto.so.3` with libc startup. OpenSSL performs
TLS and certificate operations; Lanius owns the sockets, stream buffers,
deadlines, polling, bounds and HTTP processing.

```text
https-serve ADDRESS CERT_CHAIN KEY [OPTIONS]
```

`ADDRESS` is a numeric socket endpoint such as `127.0.0.1:8443` or `[::1]:8443`.
Port zero asks the OS to select an available port. After loading the credentials
and binding the listener, the program writes its actual numeric endpoint and a
newline to stdout. HTTP responses travel over TLS, separately from that line.

`CERT_CHAIN` names a PEM certificate chain, with the leaf certificate first.
`KEY` names its matching PEM private key. The application supplies
an explicit empty passphrase to the server factory and never prompts for one.
A key requiring a nonempty password fails before the listener is created. The
reusable OpenSSL factory supports explicit secret input; this application has
no passphrase argument. Credential paths must be nonempty, NUL-free UTF-8, at
most 4,096 bytes.
Native file permissions and OpenSSL's credential loaders govern file access.

The server uses TLS 1.2 or newer. By default it explicitly selects
`ClientAuthentication::Unauthenticated`: clients verify the service's chain and
DNS/IP identity, while the service does not request client certificates.
`--require-client-ca FILE` instead requires a verified client certificate.
OpenSSL supplies all certificate, record and cryptographic operations in both
profiles.

Build through the native C profile with `ssl` and `crypto`:

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  --native-link --native-library ssl --native-library crypto \
  --stdlib-root stdlib --source-root extended \
  sample_programs/library/https_serve.lani -o /tmp/https-serve

/tmp/https-serve 127.0.0.1:8443 /tmp/service-chain.pem /tmp/service.key \
  --requests 2 --timeout 5000 --report

curl --cacert /tmp/local-ca.pem \
  --resolve fixture.test:8443:127.0.0.1 https://fixture.test:8443/health
printf 'binary\000body' | curl --cacert /tmp/local-ca.pem \
  --resolve fixture.test:8443:127.0.0.1 \
  --data-binary @- https://fixture.test:8443/echo > /tmp/echoed
```

Use a certificate covering the chosen DNS name or IP address. DNS resolution
belongs to the client; the server itself binds only numeric endpoints.

## Required client certificates

`--require-client-ca CLIENT_CA_FILE` selects
`ClientAuthentication::Required(Trust::CaFile(...))`. The option requires a
nonempty, NUL-free UTF-8 path of at most 4,096 bytes; separate and `=` values
work, and the last occurrence wins. Client trust is independent of the service
chain and key that clients verify. Build the
[fetch client](extended-https-fetch.md) separately for this example.

```sh
/tmp/https-serve 127.0.0.1:8443 /tmp/service-chain.pem /tmp/service.key \
  --require-client-ca /tmp/client-ca.pem --requests 1 --report

/tmp/https-fetch 127.0.0.1:8443 fixture.test /tmp/service-ca.pem /health \
  --client-cert /tmp/client-chain.pem --client-key /tmp/client.key
```

OpenSSL requires the client certificate and verifies its chain, validity and
client purpose. The wrapper also checks a successful verification result and a
non-null certificate before the server stream opens. No HTTP request is
processed and no HTTP response is emitted for a rejected client. Required
contexts disable caching and TLS tickets, including the TLS 1.3 ticket count,
so each connection performs fresh client-certificate authentication.

Every certificate admitted by that trust and native purpose policy can access
the same health and echo routes. The service does not map a subject/SAN to a
user, compare a client DNS name, grant roles or authorize individual routes.
Different trusted clients and certificates without an EKU restriction can pass;
an explicitly incompatible EKU is rejected. There is no custom CRL/OCSP policy
or revocation fetching. Credential or trust failure never falls back to the
default unauthenticated-client mode.

In TLS 1.3 a client can finish its local handshake before the server rejects
its certificate. The client must handle a later fatal alert during I/O; local
handshake or write success alone does not prove server acceptance. See the
[mutual TLS application guide](extended-https-mutual-tls.md) and the
[native policy and ownership contract](extended-openssl-mutual-tls.md).

## Requests and responses

| Route | Method | Response |
| --- | --- | --- |
| `/health` | GET | 200 with the three bytes `ok\n` |
| `/health` | HEAD | 200 without a response body |
| `/echo` | POST | 200 with the decoded request body, byte for byte |
| Known route | Other method | 405 with an Allow field |
| Other path | Any method | 404 with an empty body |
| Non-origin request target | Any method | 421 with an empty body |

Routes use the encoded path from `ext::uri`; query strings do not change route
selection, and percent escapes are not decoded for routing. Responses use
`application/octet-stream` and `Connection: close`. The service does not keep a
connection alive, schedule concurrent clients, route virtual hosts, interpret
content encodings, or act as a forward proxy.

The incremental cursor finds a candidate request boundary. The canonical
request parser then checks the complete message, and `decode_into` removes
chunked transfer framing before the echo response is encoded. Fixed-length,
chunked and empty request bodies are supported. Binary NUL and arbitrary
non-UTF-8 body bytes remain unchanged. The parser enforces Host and framing
rules, including rejection of duplicate Host/Content-Length fields and
conflicting Transfer-Encoding/Content-Length. Already received bytes beyond
the selected request boundary are rejected rather than treated as another
request. The server closes after its one response even if a client later sends
more requests on that connection.

For HTTP/1.1, one case-insensitive `Expect: 100-continue` receives an encoded
100 response after canonical header, framing and declared-length checks. The
interim response is omitted if any body bytes are already buffered or no body
is forthcoming. Duplicate or unsupported expectations receive an encoded 417
without waiting for the body. HTTP/1.0 expectations are ignored. See
[RFC 9110 section 10.1.1](https://www.rfc-editor.org/rfc/rfc9110.html#section-10.1.1).

Malformed, incomplete or over-limit requests abort the connection without a
final HTTP response. A previously sent 100 response cannot be retracted. A
fixed-length or chunked request needs no transport EOF once its message is
complete. An authenticated TLS closure still cannot complete an unfinished
HTTP body. Abrupt TCP EOF and cut TLS records are errors; the TLS wrapper never
globally ignores unexpected EOF.

## Bounds and deadline scope

| Option | Default | Maximum |
| --- | --- | --- |
| `--requests N` | 1 | 64; minimum 1 |
| `--timeout MS` | 5,000 ms per connection slot | 60,000 ms |
| `--max-request N` | 2 MiB retained HTTP bytes | 16 MiB |
| `--max-body N` | 1 MiB decoded request/echo bytes | 16 MiB |
| `--max-response N` | 2 MiB encoded response bytes | 16 MiB |
| `--max-head N` | 16,384 request head bytes | 65,536 |
| `--max-headers N` | 64 request fields | 1,024 |
| `--max-chunks N` | 65,536 nonempty chunks | 65,536 |
| `--max-io N` | 65,536 operations per slot | `i32::MAX` |
| `--max-tls N` | 32,768 TLS operations per slot | `i32::MAX` |
| `--max-work N` | 64 MiB work units per slot | `i32::MAX` |

Numeric values are unsigned decimal integers. Missing values, signs and
overflow are errors. Zero is permitted for bounds other than the request count.
Options can appear before or after operands, using separate or `=` values; the last
occurrence wins. Argument capture permits 48 arguments and 16,384 bytes.
Request lines are capped at 8,192 bytes, trailers at 16 fields and 16,384 bytes.
Each native TLS staging buffer and the stream's fixed write queue hold at most
16,384 bytes. The static health body remains three bytes independently of the
decoded request-body limit.

Each slot starts one absolute monotonic deadline **before accept**. The same
deadline covers accept, handshake, request reads, parsing/decoding checks,
response transmission and local TLS shutdown. A new deadline begins only for
the next sequential slot. Any failed slot terminates the service, so at most
the configured number of connections is accepted. An idle listener, a silent
TLS client and a client that stalls partway through HTTP all have finite waits.

The listener and accepted sockets are nonblocking. Accept attempts and polls
spend the slot's I/O budget; their count is subtracted before handing the
remaining budget to `tls_stream`. Stream setup, socket calls, polls, buffered
write acceptance and TLS attempts spend that remaining budget. Each TLS
attempt also spends the TLS budget. WANT_READ/WANT_WRITE waits follow the
direction OpenSSL requests. Interrupted attempts retain the original deadline
and consume call budget. No cleanup depends on remaining budget.

Cursor work, conservative canonical-parser/encoder allowances and body-copy
work share the work cap. Request bytes, decoded bytes and total encoded
response bytes are separate caps. A 100 response counts toward the response
byte and write caps. At an unfinished exact input bound, at most one extra
plaintext byte can be consumed to identify excess input; it is never echoed.

Credential/client-trust loading and listener setup occur before the first slot
and its deadline. OpenSSL file loading and cryptographic operations are
synchronous. During a slot, deadline checks surround native calls but cannot
preempt one. Path and verification-depth caps do not bound PEM file size,
native allocations, certificate parsing or chain-verification CPU work.
Clock observations and internal OpenSSL helpers are not separate counted
operations. These are processing bounds, not a process-memory quota.

Stdout's startup line and each stderr record have independent eight-attempt
write budgets. Short writes resume at the unwritten byte; EINTR spends an
attempt and retries. Zero progress, invalid counts, EAGAIN and other errors
fail output. These descriptors can block inside a write, so the network
deadline does not promise a whole-process deadline. `--report` emits one
bounded stderr stats record for each constructed stream, after closing it.

## Socket and TLS ownership

[`ext::tls_stream::accept_connected_until`](../extended/ext/tls_stream.lani)
consumes an already connected socket on **every** result. All other copies of
that socket become inactive at entry. The constructor requires TCP,
nonblocking mode and a connected peer, closes the socket on every validation
or handshake failure, and returns only after the server handshake and any
required client-certificate checks complete.
Callers pass the same absolute deadline used during accept and account for
accept/poll calls before choosing the stream's remaining I/O budget.

The borrowed `ServerContext` creates a native session that retains its own
OpenSSL context reference. The caller may destroy `ServerContext` immediately
after construction without invalidating that stream, or retain it for later
sequential connections. Each Session also retains its required-peer policy
after that caller owner is destroyed. Server streams have no dummy client
context. Client streams from `connect_until` retain an owned Context in `Some`;
the [prepared client factory](extended-https-fetch.md#the-tls-stream-adapter)
borrows its Context and stores `None`, as server streams do. Cleanup releases
only an owned Context. All factories use the same handshake, buffered I/O,
deadline, failure and cleanup engine; client queue/read caps come from
`Context.io_bytes()`.

`Write.write` drains any earlier queue, copies a bounded prefix of new input,
and returns its accepted count without sending that new queue. The original
input can change after acceptance. `flush` sends the copied queue through the
stable OpenSSL write/retry staging; `read` and `shutdown` flush first. The app
explicitly flushes every encoded response. Accepted and confirmed transmitted
plaintext counters are separate; retries never charge acceptance twice.

A failed `write` accepts no new bytes, though an older queue may have made
progress. A failed flush can follow confirmed or unconfirmed wire progress
and provides no delivery rollback. Deadline/budget errors abort any pending
TLS operation before closing the descriptor. Successful native reads retain
their delivered count if the following clock check fails; the sticky failure
must be observed through `check()` before publishing an application result.
The service checks before sending its response and after successful shutdown.

Successful shutdown flushes accepted data and sends the local close_notify,
stopping at Sent or Complete. Reads and new write acceptance are then closed.
`close()` is abortive and never hides a flush. Cleanup always frees SSL first,
then closes the sole socket owner, releases an optional client context and
frees the queue. The listener closes before the application's server context
is destroyed. The process explicitly ignores SIGPIPE before using OpenSSL's
socket BIO; it never replaces TLS closure with raw TCP write shutdown.

## Errors and executable checks

| Exit | Meaning |
| --- | --- |
| 0 | Configured sequential requests completed, or help |
| 2 | Invalid arguments, configuration or byte/call/parser-work bound |
| 3 | Credential, TLS, socket, timeout, clock or HTTP framing failure |
| 4 | Allocation failure |
| 5 | Output failure or SIGPIPE-policy setup failure |

Invalid credentials or configured client trust fail before any listening
endpoint is published. A failed handshake produces no HTTP response. A later
transport/output failure can leave a response prefix; successful status means every response was flushed,
its local closure alert was sent, and owners were released. Diagnostic failure
preserves the original exit status. Stats include received, accepted and
confirmed sent plaintext, encoded response bytes, total slot I/O, TLS calls,
parser work and a failure flag.

[`tests/extended_https_server_execution.rs`](../tests/extended_https_server_execution.rs)
builds the actual application and a focused server-stream consumer through the
native `ssl`/`crypto` profile. Python's standard `ssl` client requires chain and
hostname verification; `http.client.HTTPResponse` independently checks the
responses. Runtime certificates come from OpenSSL CLI into temporary storage.
The fixtures cover binary fixed/chunked requests, Expect behavior, TLS versions,
DNS/IP identities, chain validation, HTTP failures, exact and zero bounds,
accept/handshake/read deadlines, socket consumption, server-context retention,
buffered copied input and pending-write backpressure. They also validate the
linked ELF and its OpenSSL 3 native dependencies.

The original four groups passed on Linux x86_64, totaling 106 application/consumer
process cases:

| Group | Cases | Coverage |
| --- | --- | --- |
| HTTP matrix | 28 | Verified DNS/IP, IPv4/IPv6, TLS 1.2/1.3, complete chains, health/echo, binary fixed/chunked bodies, Expect, routes and three sequential slots |
| Failures | 24 | Missing/malformed/encrypted/mismatched credentials, client trust/identity rejection, HTTP framing errors, authenticated incomplete EOF, abrupt EOF and cut records |
| Limits | 45 | Exact and zero byte/head/header/chunk/response/work bounds, accept/handshake/request deadlines, call caps, invalid arguments, help and startup output failure |
| Server stream | 9 | Socket consumption on validation/configuration errors, retained server context, copied buffered acceptance, read-triggered flush, terminal shutdown and backpressure timeout |

The matrix passed in 7.17 seconds; the remaining three groups passed in 10.87
seconds. Local receipts are `target/stdlib-work/https-server-matrix-vec-corrected.log`
and `target/stdlib-work/https-server-limits-failures-stream.log`. Both application
and stream-consumer linked ELFs passed generated-function boundary validation
and the OpenSSL 3 dependency checks.

The shared stream changes also passed the existing HTTPS client's four-group,
62-case regression in 13.90 seconds, recorded in
`target/stdlib-work/https-fetch-server-context-regression.log`. The mandatory
client trust, identity and protocol rejection group passed all nine cases in
5.98 seconds, recorded in
`target/stdlib-work/openssl-tls-client-policy-server-regression.log`. The server's
explicit unauthenticated-client policy did not remove the client's mandatory
chain and DNS/IP checks.

The required-client and prepared Context additions passed all four focused
groups in
[`tests/extended_https_mutual_tls_execution.rs`](../tests/extended_https_mutual_tls_execution.rs).
The 35 matrix, 34 rejection and 32 limit cases passed together in 15.23 seconds
(`target/stdlib-work/https-mutual-app-groups.log`). Eight prepared-Context cases
passed separately in 6.21 seconds
(`target/stdlib-work/https-mutual-prepared-first.log`). These 109 process cases
cover both applications and the prepared consumer, including native app pairs,
different trusted clients, mandatory service identity, late TLS 1.3 alerts,
rejected clients with no HTTP response, borrowed context lifetime and shared
limits. Each app pair counts two processes. They are separate from the earlier
106-case service and 62-case client receipts above; the
[mutual TLS guide](extended-https-mutual-tls.md#focused-execution-gates) gives
their exact finite scope.

On this source, the existing server socket/context/buffer group passed all nine
cases in 6.73 seconds
(`target/stdlib-work/https-prepared-server-stream-regression.log`). The existing
client buffered ownership/error group passed its four cases in 7.01 seconds
(`target/stdlib-work/https-prepared-client-stream-regression.log`). These
focused stream regressions did not rerun the other earlier application groups.

These finite loopback cases verify native CPU execution through OpenSSL 3.
They do not establish concurrent scheduling, keepalive, deployment capacity,
other operating-system support or GPU-kernel execution.

```sh
timeout --kill-after=2s 110s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test extended_https_server_execution -- --nocapture --test-threads=1
```
