# HTTPS service execution fixtures

The driver is [`tests/extended_https_server_execution.rs`](../../../extended_https_server_execution.rs).
It compiles the real `sample_programs/library/https_serve.lani` application and
`stream_contracts.lani` through the Linux x86_64 native `ssl`/`crypto` profile.
Each linked ELF passes the existing generated-function boundary validator and
checks for `libssl.so.3` and `libcrypto.so.3` before execution.

`oracle.py` uses Python's native OpenSSL client with `CERT_REQUIRED` and hostname
verification. Python's standard `http.client.HTTPResponse` checks response
framing and body bytes independently of the Lanius codec. The raw client helper
from `openssl_tls_server/client.py` controls authenticated closure and cuts of
native-produced encrypted records; it implements no TLS or cryptography.
The imported runtime certificate generator uses the OpenSSL CLI. All generated
keys, chains and trust files stay in temporary directories; none are checked in.

## Shared-scheduler oracle migration

The actual application now uses the shared HTTP Protocol, resumable HTTPS
transport and server scheduler. The migrated matrix passed all 30 cases against
the current application ELF, recorded in
`target/stdlib-work/https-serve-shared-scheduler-matrix-expect-policy-retry.log`.
The first attempt (`https-serve-shared-scheduler-matrix-first.log`) stopped at
the stale unsupported HTTP/1.0 Expect expectation; production code was unchanged
for the accepted retry. The negative and quota groups below are saved but have
not yet been executed against the migrated application.

Stage 1 updates matrix/application helpers: acceptance-order IDs and per-owner
code/failure/cleanup records replace the old copied-acceptance counter; native
TLS close_notify is exchanged with explicit unwrap and transport EOF; response
version follows HTTP/1.0 inputs; managed Date is checked; supported Expect sends
100 even for preloaded bodies. HTTP/1.0 recognized 100-continue is ignored with
no interim response, while unsupported expectations receive 417; this is an
intentional change from the earlier HTTPS application, per
[RFC 9110 section 10.1.1](https://www.rfc-editor.org/rfc/rfc9110.html#section-10.1.1). The old buffered-pipeline rejection moves to a
positive bounded-discard case that captures every plaintext byte and uses an
independent HTTP reader over frozen bytes, requiring exactly one response and
truthful tail/drain counts. Buffer prefetch cannot conceal an extra response.

Stage 2 migrates negative/limit consumers to every-accepted-owner reports,
accepted-at connection deadlines plus a fixed service deadline, and per-owner
I/O limits that exclude listener calls. Failed peer verification and TLS
handshakes require one actual owner record. Idle-listener expiry uses an explicit
service deadline and no owner record; accepted handshake/request expiry uses
the shorter connection deadline and one record. Tiny I/O/TLS controls connect a
real peer and check the exact consumed-call counter with no HTTP output. Zero
I/O/TLS configuration rejects before admission; zero HTTP work checks the
accepted socket is closed before TLS attachment, with zero HTTP/TLS counters.
New concurrency/service-timeout argument bounds are checked directly. Existing
malformed/trust/chunked/scale, exact/one-below bounds and output assertions remain
gates.

The `stream` function and its raw probe modes are unchanged: they collect their
own transport output and never use the application's report, managed-Date or
HTTP response/unwrap helper. The mTLS `prepared` group likewise uses its separate
native probe and peer, not the migrated application helpers. There is no schema
fallback between these profiles. Historical receipts below are not acceptance
for the migrated negative/quota groups or new stream/prepared acceptance.

## Historical verified cases

All four groups passed, totaling 106 application/consumer process cases:

| Mode | Cases | Main contracts |
| --- | --- | --- |
| `matrix` | 28 | Verified DNS/IP and complete chains; TLS 1.2/1.3; IPv4/IPv6; GET/HEAD health; empty, NUL-containing and multibuffer POST echo; chunk extensions/trailers; HTTP/1.0; 100/417 expectations; 404/405/421 routing; three sequential connections |
| `failures` | 24 | Credential loading fails before listen; clients reject wrong trust/name/IP, expiry, incomplete chains and wrong certificate purpose; malformed Host/framing/chunks/trailers/targets and buffered pipelines fail without a final response; clean TLS EOF cannot finish an incomplete HTTP body; abrupt/cut records fail |
| `limits` | 45 | Exact and one-below raw/head/header/body/chunk/response/work bounds; zero bounds; original accept/handshake/request deadline; zero/tiny IO/TLS call caps; option validation, help and `/dev/full` startup output failure |
| `stream` | 9 | Consuming constructor closes transferred UDP, unconnected, expired, closed, invalid-budget, closed-context and blocking sockets; live sessions retain a destroyed server context; write acceptance copies mutable input; read flushes it; shutdown rejects new IO; pending-write backpressure times out and becomes terminal |

`matrix` passed in 7.17 seconds, recorded in
`target/stdlib-work/https-server-matrix-vec-corrected.log`. The other three groups
passed in 10.87 seconds, recorded in
`target/stdlib-work/https-server-limits-failures-stream.log`.

The existing HTTPS client regression also passed all 62 cases in 13.90 seconds
against the shared optional-context stream implementation:
`target/stdlib-work/https-fetch-server-context-regression.log`. The mandatory
client trust/identity/protocol negative group passed nine cases in 5.98 seconds:
`target/stdlib-work/openssl-tls-client-policy-server-regression.log`.

This is finite native CPU/loopback coverage. It does not measure production
capacity or verify concurrency, keepalive, other operating systems or GPU
kernel execution. The application processes at most 64 sequential slots, one
request per connection, with explicit byte, work, call and absolute-time caps.
The stream consumer separately forces a pending-write timeout with constrained
peer buffering; no peer-delivery rollback is inferred from a flush error.

## Running

The Rust driver accepts the ordinary Cargo test filters. Coordinate GPU/codegen
execution with other repository work.

```sh
timeout --kill-after=2s 110s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test extended_https_server_execution -- --nocapture --test-threads=1
```

The Python oracle can also consume a previously built executable:

```sh
python3 tests/fixtures/extended/https_server/oracle.py matrix /tmp/https-serve
python3 tests/fixtures/extended/https_server/oracle.py stream /tmp/server-stream-contracts
```

See [`docs/extended-https-server.md`](../../../../docs/extended-https-server.md)
for the CLI, ownership rules, limits and deadline scope.
