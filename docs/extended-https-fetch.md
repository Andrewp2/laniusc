# Fetching a verified HTTPS body

[`sample_programs/library/https_fetch.lani`](../sample_programs/library/https_fetch.lani)
performs one HTTPS GET and writes the decoded response body to binary stdout.
It uses the system OpenSSL 3 library for TLS through
[`ext::https_client`](extended-https-client.md), which drives the same
[`ext::http_client::Protocol`](extended-http-client.md) as cleartext HTTP.
The application supplies a canonical Request and limits; the library owns
request encoding, incremental framing, informational responses, canonical
validation and body decoding. The application has no separate HTTP parser.

The native profile is Linux x86_64, linked through the native C profile to
`libssl.so.3` and `libcrypto.so.3` with libc startup. This migration to the
resumable HTTPS driver is **pending compilation and runtime acceptance**.
Earlier receipts below describe the preceding stream-based application and
do not establish this revision. TLS and certificate operations run in
OpenSSL; application ownership, bounds, polling and HTTP processing run in
Lanius.

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

For a service that requires a client certificate, add both
`--client-cert CLIENT_CHAIN` and `--client-key CLIENT_KEY`. Both values must be
nonempty, or both options must be absent. The chain is PEM with the client leaf
first, followed by its intermediate issuers; the key must match. The app supplies
an explicit empty passphrase and never prompts. A key requiring a nonempty
password fails; the reusable TLS factory accepts explicit secret input.
Credential failure never falls back to a client without credentials. See the
[mutual TLS guide](extended-https-mutual-tls.md) for both applications and their
independent service/client trust roles.

## Verification and framing

The TLS wrapper requires certificate-chain verification, an authenticated peer
certificate and DNS/IP identity verification. DNS matching uses SAN names and
rejects Common Name fallback and partial wildcards. TLS 1.2 is the minimum
version. No HTTP request bytes are submitted until the verified TLS handshake
has completed.

Client credentials preserve every service trust and identity check. In TLS 1.3,
local client handshake completion does not prove that the service accepted the
client certificate; a later read can receive a rejection alert. The app still
requires a complete validated HTTP response before publishing its body. A
certificate's acceptance by the service also does not establish application
account or route authorization.

The application emits a bounded GET with `Connection: close`. It supports
fixed-length, chunked and close-delimited response bodies, and at most eight
informational responses totaling at most 65,536 bytes. Switching protocols is
rejected. The framing cursor only finds a candidate boundary; the complete
selected response is then checked by the canonical parser before decoding.
Decoding removes HTTP transfer framing; content encodings such as gzip remain
part of the returned body.
The application explicitly selects `http_client::Trailing::Reject`. Extra
plaintext already read beyond the final response boundary is rejected. A
self-delimited response does not wait for peer EOF merely to discover later
bytes. Output starts after the complete response has been validated and
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

All numeric values are unsigned decimal integers; signs, missing values and
overflow are errors. Zero is accepted and exercises the corresponding bound.
Options can appear before or after operands, with separate or `=` values. Repeated
options use the last value. Argument capture permits 32 arguments and 16,384
bytes. The request is capped at 16,384 bytes. HTTP limits are 16,384 head
bytes, 8,192 line bytes, 64 headers, 16,384 trailer bytes, 16 trailers and
65,536 chunks. Informational responses share the total response byte bound.
At an exact close-delimited body or response byte limit, one extra plaintext
byte may be consumed to distinguish authenticated EOF from excess input;
excess bytes are never output. Fixed and chunked responses finish at their
validated boundary without that EOF probe.

The TLS profile bounds trust and credential paths to 4,096 UTF-8 bytes each,
peer identities to 253 ASCII bytes, native plaintext I/O buffers to at most
16,384 bytes and certificate verification depth to 16. The HTTPS driver stages
at most 1024 request bytes per active write and reads at most 1024 plaintext
bytes per active read. Native retry storage keeps each pending operation
stable; the application does not create a separate buffered stream queue.

The application creates one absolute monotonic deadline before loading its
OpenSSL context, with or without client credentials. The same deadline then
covers canonical request preparation, connection establishment, TLS handshake,
request transmission, response reads, HTTP validation/decoding and local TLS
shutdown. The socket is nonblocking. WANT_READ or WANT_WRITE polls the direction
requested by OpenSSL using the remaining time. Interrupted polls retry with the
original deadline and spend call budget. A terminal error aborts pending TLS
operations and releases their owners.

The CLI maps its limits directly to the shared engine:

| Application bound | Library setting or check |
| --- | --- |
| Request, 16,384 bytes | `http_client::Options.request_bytes` |
| `--max-response` | `http_client::Options.response_bytes`, including informational prefixes |
| `--max-body` | `http_client::Options.wire.body_bytes` |
| Eight informational responses / 65,536 bytes | `interim_count` / `interim_bytes` |
| `--max-io` | `http_client::Options.io_calls` |
| `--max-work` | `http_client::Options.work` |
| `--max-tls` | `https_client::Options.tls_calls` |
| `--max-output` | Decoded body-length check before the first stdout write |
| `--max-stdout-calls` | Attempt allowance in the application's stdout loop |

`--max-io` now counts TCP leaves, TLS attempts and poll participation in the
shared engine. It includes the charged normal socket close. Each handshake,
read, write or shutdown attempt also spends `--max-tls`, including WANT
retries. It does not count buffered input acceptance, because this application
no longer uses the `tls_stream` adapter. `--max-work` uses the shared HTTP
encoder/cursor/canonical-validation/decoder accounting, including retained
informational-head construction. These are intentional accounting changes;
exact old stream call/work thresholds are not preserved. No budget resets
between preparation, connection and completion.

Context loading, native setup, clock observations and OpenSSL's internal helper
calls are not separate charged I/O attempts. Native TLS setup and cryptographic
calls are synchronous: deadline checks surround progress and cannot preempt a
call. Context loading precedes the exchange's first deadline check; its elapsed
time still spends the original deadline. Path caps do not bound PEM file size,
native parsing, allocations or cryptographic work. Cleanup runs even after a
budget is exhausted. Parser work and plaintext byte limits are independent
bounds, not a process-memory quota.

`--max-output` remains separate from `--max-body`. A complete decoded body may
be allocated within the body limit before the smaller output limit rejects
it. Such rejection destroys the Response and publishes no body prefix.

The deadline applies to network processing. Stdout has its own byte and call
limits; a blocking stdout descriptor can still block inside a write. Short
writes resume at the first unwritten byte. EINTR spends a call and retries;
EAGAIN, host errors, zero progress and invalid counts fail output. Once stdout
starts, an output failure can leave a body prefix.

## Shared exchange and ownership

The app creates an `openssl_tls::Context` with either `new` or
`new_with_credentials`, then calls:

```text
https_client::exchange_until(endpoint, &Context, identity, Request,
                             http_options, tls_options, deadline)
    -> Result<http_client::Response, https_client::Failure>
```

The Request contains `GET`, the supplied origin target, the constructed Host
authority, no additional fields and an empty body. The canonical writer adds
`Host`, `Connection: close` and the empty body's framing. Request backing stays
live through the call. The HTTPS engine prepares once, copies the owned request
and method, then drives the same Protocol used by cleartext HTTP. There is no
second request encoder, framing cursor, response parser or body decoder in this
application.

The context remains the caller's owner on success and failure. The resumable
driver acquires its own native context reference and identity backing before
opening a socket; Session attachment retains the native context it needs. The
app destroys its Context after the exchange returns. On success, TLS and socket
owners have already been released, and exactly one Response owns its wire,
decoded body, method and informational metadata. The app borrows `body()` for
publication, then destroys that sole owner on either stdout result. It never
destroys a borrowed Response descriptor copy.

The synchronous facade drives the same readiness-based Exchange used by the
[HTTPS batch adapter](extended-https-batch-testing.md). Its step operation does
not poll internally; the facade waits explicitly when needed. Native failures
retain their typed TLS diagnostic in the library's Failure, including confirmed
progress and cleanup metadata; the CLI maps them to the exit classes below.

The application establishes an explicit process SIGPIPE-ignore policy before
OpenSSL uses socket BIOs.

## The TLS stream adapter

The separate [`ext::tls_stream`](../extended/ext/tls_stream.lani) adapter remains
available to consumers of `core::io::Read`/`Write` and to the existing HTTPS
server profile. Its buffered acceptance and queue accounting are separate from
this application's shared Protocol. The contracts below describe those stream
consumers, including the historical application and focused consumer tests.

`connect_until` owns a nonblocking socket, client Context, Session and fixed
write queue. `connect_with_context_until(endpoint, &Context, identity, limits,
deadline)` borrows the caller's Context on every result; the successful Session
retains its own native reference, and the stream owns no caller Context.
`accept_connected_until` consumes an accepted socket on every result and uses
the same stream engine with a retained native server-context reference. Client
factories return only after verifying the service certificate. Use one active
manual stream owner; by-value descriptor copies do not acquire ownership.

`write` first drains a previously accepted queue, then copies a bounded prefix
of new input and returns the accepted count. It does not send that new queue
yet. Input may be changed or released after acceptance. `flush` sends accepted
bytes using OpenSSL's stable retry buffers; `read` and `shutdown` first flush
the queue. Queue capacity and native read caps derive from `Context.io_bytes()`.
Prepared and ordinary client factories share one deadline and charged State
through connection and handshake, without resetting counters.

`Stats.accepted_bytes` counts copied input once; `written_bytes` counts only
plaintext prefixes confirmed by successful native writes. A failed write
accepts no new input, though draining an older queue may have made progress.
A failed flush does not promise delivery rollback. A terminal pending-operation
failure aborts the session, and the owner cannot resume new input on it.

Call `check()` before publishing a result obtained through the adapter. When a
native read succeeds before a following clock observation fails, it preserves
the delivered count and records a sticky failure. `check` or the next operation
exposes that failure. `last_failure` retains the TLS diagnostic, stage,
confirmed counters and any socket cleanup error.

`shutdown` sends the local alert and stops at Sent or Complete, then closes
reads and new write acceptance. `check` and `close` remain available. `close`
releases SSL, the sole socket owner, any owned client Context and the queue,
discarding queued data without a hidden flush. Stream consumers must establish
their own process SIGPIPE policy. These operations and receipts remain a
separate profile from the migrated `https_fetch` exchange.

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

### Historical execution receipts

These receipts predate the migration to `https_client::exchange_until`. New
application compilation, verified peers, exact limits, output failures and
mutual TLS regression acceptance are pending. The adapter-only cases remain a
separate profile and cannot establish the migrated application.

The original four groups passed on Linux x86_64 in 14.44 seconds: 18 verified HTTP
matrix cases, 14 certificate/HTTP failure cases, 26 deadline/limit/output cases
and four buffered-stream cases, totaling 62 cases. The linked ELF's generated
function boundaries and its OpenSSL 3 native dependencies also passed their
checks. The local execution receipt is
`target/stdlib-work/https-fetch-execution-current.log`.
After sharing the engine with server streams and making the client Context
optional, all four groups and 62 cases passed again in 13.90 seconds:
`target/stdlib-work/https-fetch-server-context-regression.log`.

The mutual TLS and prepared Context additions passed four separate focused
groups in
[`tests/extended_https_mutual_tls_execution.rs`](../tests/extended_https_mutual_tls_execution.rs):
35 matrix, 34 rejection and 32 limit cases passed together in 15.23 seconds
(`target/stdlib-work/https-mutual-app-groups.log`); eight prepared-Context cases
passed in 6.21 seconds (`target/stdlib-work/https-mutual-prepared-first.log`).
These 109 cases count both applications and the prepared consumer; each native
application pair counts two processes. They cover mandatory service identity,
required client certificates, TLS 1.3 alerts, configured queue limits, borrowed
context lifetime and shared deadline/counter continuity. They are separate
from the earlier 62-case receipts above. The
[mutual TLS guide](extended-https-mutual-tls.md#focused-execution-gates) records
the exact group scope; these are selected invocations, not a whole-suite run.

Before this migration, the existing client buffered ownership/error group passed all
four cases in 7.01 seconds
(`target/stdlib-work/https-prepared-client-stream-regression.log`). The existing
server socket/context/buffer group passed its nine cases in 6.73 seconds
(`target/stdlib-work/https-prepared-server-stream-regression.log`). These
focused stream regressions did not rerun the other earlier application groups.

These results cover native CPU execution through OpenSSL 3. Other operating
systems and GPU-kernel execution have not been verified.

```sh
timeout --kill-after=2s 110s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test extended_https_fetch_execution -- --nocapture --test-threads=1
```
