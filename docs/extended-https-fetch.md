# Fetching a verified HTTPS body

[`sample_programs/library/https_fetch.lani`](../sample_programs/library/https_fetch.lani)
performs one HTTPS GET and writes the decoded response body to binary stdout.
It uses the system OpenSSL 3 library for TLS and the existing
[`ext::http`](extended-http.md) encoder, incremental framing cursor, canonical
response parser and body decoder for HTTP/1.1.

The verified executable profile is Linux x86_64, linked through the native C
profile to `libssl.so.3` and `libcrypto.so.3` with libc startup. TLS and
certificate operations run in OpenSSL; application and stream ownership,
bounds, polling and HTTP processing run in Lanius.

```text
https-fetch ADDRESS PEER CA_FILE TARGET [OPTIONS]
```

`ADDRESS` is a numeric socket endpoint such as `127.0.0.1:8443` or `[::1]:8443`.
`PEER` is the DNS name or IP address that the certificate must authenticate.
`CA_FILE` is a PEM trust file, and `TARGET` is an origin-form path/query such as
`/files/current?format=raw`. DNS names select hostname verification and SNI.
Numeric peer identities select IP SAN verification without SNI. The HTTP Host
field uses that same peer identity, with the endpoint's port when it is not
443 and brackets around IPv6 literals.

For example, connect to a known address while authenticating a virtual host:

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  --native-link --native-library ssl --native-library crypto \
  --stdlib-root stdlib --source-root extended \
  sample_programs/library/https_fetch.lani -o /tmp/https-fetch

timeout --kill-after=2s 20s /tmp/https-fetch \
  127.0.0.1:8443 fixture.test /tmp/local-ca.pem /document \
  --timeout 5000 > /tmp/document
```

The caller supplies a numeric destination and trust file explicitly. The app
does not perform DNS resolution, follow redirects, use proxies, upload a body
or expose an option to disable verification. Final HTTP statuses, including
4xx and 5xx, return their body normally. HTTP status handling belongs to the
caller; exit zero means the verified exchange and output completed.

## Verification and framing

The TLS wrapper requires certificate-chain verification, an authenticated peer
certificate and DNS/IP identity verification. DNS matching uses SAN names and
rejects Common Name fallback and partial wildcards. TLS 1.2 is the minimum
version. No HTTP request bytes are submitted until the verified TLS handshake
has completed.

The application emits a bounded GET with `Connection: close`. It supports
fixed-length, chunked and close-delimited response bodies, and at most eight
informational responses totaling at most 65,536 bytes. Switching protocols is
rejected. The framing cursor only finds a candidate boundary; the complete
selected response is then checked by the canonical parser before decoding.
Decoding removes HTTP transfer framing; content encodings such as gzip remain
part of the returned body.
Extra application bytes received beyond the final response boundary are
rejected. Output starts after the complete response has been validated and
decoded, and the TLS/session/socket owners have been released.

Close-delimited responses require OpenSSL's authenticated `close_notify` EOF.
An abrupt TCP close or a cut TLS record is an error. A complete Content-Length
or chunked response can finish without waiting for a peer closure alert; the
client sends its local alert before closing. This follows the distinction in
[RFC 9112 section 9.8](https://www.rfc-editor.org/rfc/rfc9112.html#section-9.8).
Unexpected EOF is never globally ignored.

## Bounds and deadlines

| Option | Default | Maximum |
| --- | --- | --- |
| `--timeout MS` | 5,000 ms | 60,000 ms |
| `--max-response N` | 2 MiB | 16 MiB |
| `--max-body N` | 1 MiB | 16 MiB |
| `--max-output N` | 1 MiB | 16 MiB |
| `--max-io N` | 65,536 | `i32::MAX` |
| `--max-tls N` | 32,768 | `i32::MAX` |
| `--max-work N` | 64 MiB work units | `i32::MAX` |
| `--max-stdout-calls N` | 65,536 | `i32::MAX` |

All values are unsigned decimal integers; signs, missing values and overflow
are errors. Zero is accepted and exercises the corresponding bound. Options
can appear before or after operands, with separate or `=` values. Repeated
options use the last value. Argument capture permits 32 arguments and 16,384
bytes. The request is capped at 16,384 bytes. HTTP limits are 16,384 head
bytes, 8,192 line bytes, 64 headers, 16,384 trailer bytes, 16 trailers and
65,536 chunks. Informational responses share the total response byte bound.
At an exact response byte limit, one extra plaintext byte may be consumed to
distinguish authenticated EOF from excess input; excess bytes are never output.

The TLS profile bounds trust-file paths to 4,096 UTF-8 bytes, peer identities
to 253 ASCII bytes, each native plaintext I/O buffer to 16,384 bytes and
certificate verification depth to 16. The stream's owned write queue has that
same 16,384-byte capacity.

One absolute monotonic deadline covers connection establishment, TLS handshake,
request transmission, response reads, parsing checks and local TLS shutdown.
The socket is nonblocking. Every WANT_READ or WANT_WRITE polls the direction
requested by OpenSSL, using the remaining time. Interrupted polls retry with
the original deadline and spend call budget. A deadline or budget failure
while a TLS operation is pending aborts that TLS session and closes the socket.

`--max-io` counts setup operations, socket calls, poll attempts, buffered write
acceptance and TLS I/O attempts. Each TLS I/O attempt also spends `--max-tls`.
Clock checks and OpenSSL's internal helper calls are not individual counted
operations. Native OpenSSL setup and cryptographic calls are synchronous;
deadline checks surround them rather than preempting a call. Cleanup is
unconditional even after a budget is exhausted. Parser work and plaintext
byte limits are independent bounds, not a process-memory quota.

The deadline applies to network processing. Stdout has its own byte and call
limits; a blocking stdout descriptor can still block inside a write. Short
writes resume at the first unwritten byte. EINTR spends a call and retries;
EAGAIN, host errors, zero progress and invalid counts fail output. Once stdout
starts, an output failure can leave a body prefix.

## The TLS stream adapter

[`ext::tls_stream`](../extended/ext/tls_stream.lani) is the reusable transport
boundary. `connect_until` owns the nonblocking socket, OpenSSL context/session
and one fixed write queue. It returns only after certificate verification.
Use one active manual owner; all by-value copies remain inactive.

The same Read/Write and deadline engine now supports
[`accept_connected_until`](extended-https-server.md#socket-and-tls-ownership).
It consumes an accepted socket on every result and retains the server's native
context through its Session. A Stream owns an optional client Context; server
streams do not own the caller's ServerContext.

The adapter implements `core::io::Read` and `Write` with buffered acceptance.
`write` first drains a previous accepted queue, then copies a bounded prefix of
new input into its queue and returns the accepted count. It does not send that
new queue yet. Modifying or freeing the original input after acceptance cannot
change queued bytes. `flush` sends accepted bytes through OpenSSL's stable
write/retry buffers. `read` and `shutdown` first flush any accepted queue.
The sample explicitly flushes the GET before receiving the response.

`Stats.accepted_bytes` counts copied input once. `Stats.written_bytes` counts
plaintext prefixes confirmed by successful native TLS writes. Retries do not
charge acceptance again. A failed `write` accepts no new input, though draining
an older accepted queue may have made progress. A failed `flush` can follow
confirmed or unconfirmed wire progress; it does not promise delivery rollback.
Every pending-operation failure is terminal, so the caller cannot retry new
input on that TLS connection.

`check()` must succeed immediately before publishing an application result.
If a native read succeeds and its following clock observation expires, the
adapter preserves the delivered count, records a sticky failure and aborts.
`check()` or the next operation exposes that failure; the sample checks after
HTTP validation and decoding. `last_failure()` retains the TLS diagnostic,
stage, confirmed counters and any socket cleanup error.

`shutdown()` sends the local closure alert and stops at Sent or Complete.
Afterward both reads and new write acceptance are closed; `check` and `close`
remain available. `close()` is an explicit abortive release: it discards queued
data, frees SSL, closes the sole socket owner, frees any owned client context and releases
the queue. It never performs a hidden flush. The application establishes an
explicit process SIGPIPE-ignore policy before using OpenSSL's socket BIO.

## Errors and executable checks

| Exit | Meaning |
| --- | --- |
| 0 | Complete verified exchange and body output, or help |
| 2 | Invalid arguments or application/TLS/parser budget limit |
| 3 | TLS, certificate, socket, clock or HTTP framing failure |
| 4 | Allocation failure |
| 5 | Output I/O/call failure or SIGPIPE-policy setup failure |

Diagnostics distinguish certificate verification, missing certificates,
truncated TLS, timeouts, call/byte/work limits and HTTP failures. Stderr has a
separate eight-attempt budget and preserves the original status if it fails.

[`tests/extended_https_fetch_execution.rs`](../tests/extended_https_fetch_execution.rs)
compiles and executes the actual Lanius application and a focused adapter
consumer. Python's native OpenSSL `ssl` implementation supplies loopback TLS
peers; Python's standard HTTP header parser checks the request. Test certificates
are generated by the OpenSSL CLI into temporary storage. The tests cover:

- Verified DNS and IP identities, SNI, chain trust, TLS versions, binary body
  boundaries and fixed/chunked/close-delimited/informational HTTP responses.
- Certificate and HTTP failures before output, authenticated closure versus
  abrupt EOF and cut encrypted records, deadlines and independent budgets.
- Buffered acceptance, copied input, implicit drain before read, confirmed
  counters, pending-operation timeout/backpressure, and terminal shutdown.

All four groups passed on Linux x86_64 in 14.44 seconds: 18 verified HTTP
matrix cases, 14 certificate/HTTP failure cases, 26 deadline/limit/output cases
and four buffered-stream cases, totaling 62 cases. The linked ELF's generated
function boundaries and its OpenSSL 3 native dependencies also passed their
checks. The local execution receipt is
`target/stdlib-work/https-fetch-execution-current.log`.
After sharing the engine with server streams and making the client Context
optional, all four groups and 62 cases pass again in 13.90 seconds:
`target/stdlib-work/https-fetch-server-context-regression.log`.

These results cover native CPU execution through OpenSSL 3. Other operating
systems and GPU-kernel execution have not been verified.

```sh
timeout --kill-after=2s 110s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test extended_https_fetch_execution -- --nocapture --test-threads=1
```
