# Native server TLS closure experiment

This is a test-only experiment for the proposed HTTPS server drain policy in
`docs/library-server-concurrency-plan.md`. It executes the existing
`ext::openssl_tls::ServerContext` and `Session`, linked to real OpenSSL 3.
Python's native `ssl.MemoryBIO` client verifies the server certificate and
negotiated version. No fixture implements TLS records, HTTP production code or
cryptography. The shared duplex observer is reused without modification.

## Causal setup

Every case negotiates TLS 1.2 or TLS 1.3 explicitly, then sends one request
prefix byte while withholding the remaining 257 application bytes. The server
reserves a real pending read, starts a complete 413 response with a 64 KiB body
and must reach a real write `WANT_WRITE`. Small checked socket buffers and a
peer that withholds all response reads until that marker establish actual
backpressure. A response-size guess is not accepted as proof of it.

The native observer checks the stable write pointer, bytes, length and count
cell across retry. The server changes its original input after WANT. Reads and
shutdown must fail locally while write `WANT_WRITE` remains pending. Only after
every response byte is confirmed may the server enter a closure policy. The
peer independently parses the captured response with `http.client`, validates
its status, framing and complete binary body, then releases the closure phase.

The report preserves the negotiated version, exact confirmed response count,
discarded upload count, local notification, authenticated EOF, operation stage,
typed native cause/phase/SSL code/error-queue code/system errno, timeout, retry
evidence and final native owner/socket checks.

## Paired cases

Each sequence runs under both TLS versions, for twelve total cases:

| Mode | Sequence | Required evidence |
| --- | --- | --- |
| 0 | Local alert, then peer queues its remaining upload before reading the alert | Exact native success or the specifically classified application-data-after-close-notify restriction; complete response retained |
| 1 | Local alert, peer authenticates it, then attempts the remaining upload | Distinguish native client write permission/rejection from server drain behavior; no arbitrary error or timeout is accepted |
| 2 | Bounded drain to authenticated peer EOF, then local alert | All 257 bytes discarded, authenticated EOF and completed native closure |
| 3 | Local alert, peer keeps transport open and withholds its own alert | Deadline failure with all response bytes confirmed, local alert retained and no false EOF |
| 4 | Peer sends upload, server drains before local alert, peer withholds its alert | Deadline failure after 257 discarded bytes; no local alert or false EOF claimed |
| 5 | Local alert, peer abruptly ends its transport write direction | Typed truncation during read; no authenticated EOF or rollback of confirmed response bytes |

Modes 0 and 1 are policy experiments. They do not assume equal native behavior
across TLS versions. The oracle admits only a complete authenticated exchange
or a precisely bound native restriction; unexpected states fail with the full
report. Native client rejection is identified by its SSL library and reason,
not inferred from a timeout. Mode 3 deliberately invokes no native client read
that could generate an automatic closure reply.

The discard allowance is 257 bytes plus a positive-capacity EOF probe; a byte
beyond the cap would report a drain limit. Each consumer has a four-second
initial absolute deadline and 20,000-operation bound. Missing-alert cases use a
250 ms closure deadline after the peer releases the already-confirmed response.
The oracle and Rust driver have finite outer process deadlines.

## Status and gates

All four groups passed on Linux x86_64 with native OpenSSL 3 on 2026-10-26,
covering twelve cases. The native consumer was validated as a linked x86_64 ELF
with OpenSSL dependencies before execution. This does not establish GPU kernel
execution of TLS APIs.

| Receipt under `target/stdlib-work/` | Result | Scope |
| --- | --- | --- |
| `openssl-tls-server-alert-before-drain-first.log` | Compiler admission failed; 5.02 s; no native cases | `LNC0006` for the missing explicit `bool` tail return in `notify`; `drain` had the same source spelling. Explicit unreachable `return false` tails fixed admission without compiler changes. |
| `openssl-tls-server-alert-before-drain-explicit-return-retry.log` | exit 0; 1 group; 6.91 s | Four alert-before-drain cases: both upload timings under TLS 1.2 and TLS 1.3 |
| `openssl-tls-server-shutdown-remaining-groups-first.log` | exit 0; 3 groups; 7.74 s | Drain-before-alert 2, missing-alert deadlines 4, abrupt transport EOF 2 |

CPU checks also passed for Python syntax, literal byte lengths, strict shared
observer C syntax, Rust formatting and five independent captured-HTTP parser
controls. The accepted native source and driver are frozen.

### Observed closure behavior

In this tested OpenSSL server/client setup, **both TLS versions** completed
modes 0 and 1 cleanly. The server confirmed all 65,612 response bytes, discarded
all 257 later upload bytes, observed authenticated peer EOF and completed
native closure. The native client permitted the late write even after its
read had authenticated the server's alert. Neither the client restriction nor
the server application-data-after-close-notify error branch was reached.
This is an observation about these native peers; it does not establish that
other TLS implementations will continue an upload after receiving an alert,
or change either protocol's requirements.

Drain-before-alert also completed cleanly under both versions after discarding
257 bytes and receiving the peer's authenticated alert. With that alert
withheld, both orderings timed out during drain while retaining the complete
confirmed response count. Alert-before-drain retained `local_notify = 1`;
drain-before-alert retained `local_notify = 0`. Neither claimed peer EOF.

Abrupt transport EOF after local notification produced `Cause::Truncated` in
`Phase::Read` under both versions, with `ssl_error = 1`, native code
`167772454` (OpenSSL unexpected EOF), and no authenticated peer EOF. The
confirmed response count remained 65,612. Every case reached a real native
write `WANT_WRITE`, checked a stable retry and ended with zero context/session
owners and invalid frees; the borrowed descriptor remained live until the
caller explicitly closed it.

Build the Rust driver with
`cargo test --locked --test extended_openssl_tls_server_shutdown_execution --no-run`.
The root runs these filters under its serialized GPU/native lock, keeping every
shell command under two minutes:

```text
server_alert_before_drain_classifies_native_upload_policy_for_both_tls_versions
server_drain_before_alert_requires_authenticated_peer_eof_for_both_tls_versions
server_missing_peer_alert_preserves_confirmed_response_at_the_deadline
server_abrupt_transport_eof_after_response_is_truncation_for_both_tls_versions
```

No production closure change is part of this fixture. These observations
support testing the proposed local-alert-then-bounded-read-discard policy for
both negotiated versions in the HTTPS server driver. That driver must still
retain response progress on deadline or truncation, require authenticated peer
EOF for clean completion, and tolerate peers that end their uploads promptly
on receipt of the alert. Its integrated acceptance remains separate.
