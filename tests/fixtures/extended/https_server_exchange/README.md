# Direct HTTPS server Exchange tests

These fixtures execute the actual `ext::https_server::Exchange` over a real
connected nonblocking TCP socket. The Python client verifies the server's
native certificate and negotiated TLS version. The consumer destroys its
caller-owned `ServerContext` before stepping the retained session. TLS records,
verification and cryptography remain in native OpenSSL; the shared duplex
observer is reused without modification.

## Initial executable gates

The `steps` group has six cases:

- TLS 1.2 public server with a binary fixed-length request and echoed body.
- TLS 1.3 public server with a binary chunked request and trailers.
- TLS 1.2 and TLS 1.3 required-client servers, each with a verified client
  certificate, a real `100 Continue` exchange and the binary body.
- The same two required-client policies without a client certificate. No HTTP
  event, request byte or response byte may be published before verification;
  rejection retains the native handshake diagnostic.

The `closure` group has two early-final cases, one per TLS version. The client
sends a valid request head and withholds its 257-byte upload. The server stages
a 413 response with a 64 KiB body. Small checked socket buffers and a client
that withholds response reads until the observed native write `WANT_WRITE`
establish real backpressure. The observer checks stable write bytes, pointer,
length and count cell across retries. The client independently parses the
complete response, authenticates the server's alert, sends the remaining
upload and completes its own alert. The server must retain confirmed response
progress, discard the 257 bytes and reach authenticated peer EOF before its
terminal event. This finite native-peer case does not establish all peers'
behavior after receiving an early alert.

The consumer mutates and destroys handler-local response headers/body after
`respond` returns. Request/head borrowed views are hashed throughout progress,
terminal completion and abort, remaining valid until `Exchange.destroy`.
Repeated terminal steps publish no second event, invoke no further SSL I/O and
cannot close a descriptor twice.

## Step and ownership evidence

Markers surround `step`, `before_wait`, external polling and application
decisions. Every step checks a native observer I/O-call delta of zero or one,
equal to its public `tls_stats().calls` delta. Decision and wait preparation
calls must perform zero native SSL I/O. The trace permits `poll` only inside
the explicit external poll frame. Successful cases also exercise stable
terminal replay.

`ledger.py` classifies source mappings using exact generated allocation and
release instruction sites. It keeps the one actually inherited TCP descriptor
as a separate initial owner; native file opens and source-created sockets have
their own observed owners. Loader/libc/OpenSSL heap mappings are outside the
source mapping ledger. Before exit, source owners balance, native context and
SSL counters are zero, and `/proc` shows only descriptors 0, 1 and 2 while the
consumer is still waiting for an acknowledgement. Nine CPU mutation controls
check hidden polling, inherited-fd leaks/double-close, unverified source sites,
mapping sizes/releases and marker balance.

## Status

Runtime acceptance is pending. Python syntax, literal byte lengths, Rust
formatting, diff checks and the nine ledger controls pass. A root-serialized
compile/run must validate the linked x86_64 ELF and host OpenSSL dependencies
before any executable API claim. Each shell command stays under two minutes.

The first two test filters in
`tests/extended_https_server_exchange_execution.rs` are:

```text
verified_server_steps_gate_public_required_client_http_and_expect_binary_bodies
early_final_tls_responses_finish_stable_backpressure_then_notify_and_discard_uploads
```

Fatal preparation/cleanup, quota and allocation campaigns are separate focused
gates; these first two groups do not establish their acceptance.
