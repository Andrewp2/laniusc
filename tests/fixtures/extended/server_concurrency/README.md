# Concurrent service acceptance

This is test infrastructure for the actual `http_serve.lani` and
`https_serve.lani` programs. No new Lanius test consumer replaces either
program. Production HTTP, scheduling and TLS remain in the library programs;
Python supplies bounded peers, independent h11/`http.client` readers and
syscall observations. TLS records and certificate operations use real OpenSSL.

## Initial causal cases

| Mode | Dependency before releasing the first peer |
| --- | --- |
| `plain-refill` | The first accepted peer sends a partial HTTP head. A healthy second peer must complete, then a queued third must be accepted and complete, while the first descriptor remains live. Only then finish the first head. |
| `tls-refill` | The first TCP peer wraps with `do_handshake_on_connect=False` and sends no TLS bytes. A verified second and queued third TLS peer must complete before the first performs its verified handshake/request. |
| `plain-reader` | A small receive-window peer sends a bounded 4 MiB echo, reads only its response head, then withholds body reads. Require actual server output followed by EAGAIN, then a healthy sibling's completion before resuming the held body. |
| `tls-reader` | The same held response-reader dependency uses verified TLS and stable native OpenSSL progress. |

The initial TLS cases pin TLS 1.3. Native closure policy covers both versions
in its own raw tests; this fixture does not inherit those cases as connected
TLS 1.2 program coverage. After exact response decoding, `SSLSocket.unwrap()`
sends and requires `close_notify`; raw TCP EOF and the product's successful
close syscall are required afterward. Missing notification is not tolerated.

`trace_events.py` binds each successful `accept4` to its client source port,
acceptance ordinal and fd generation. Reuse of a closed fd does not preserve
the old owner's authority. Both refill cases require completion order 1, 2, 0
and reports in acceptance order 0, 1, 2. A held first owner must still be live
after later peers finish. The third TCP connection is established in the
listener backlog while both initial accepted owners remain active; it must
not be accepted until the second retires. Plain peer 1 withholds write EOF,
and TLS peer 1 withholds its alert, to establish that queue state explicitly.
The reader cases require an actual write EAGAIN
after at least 256 KiB of positive output in that owner's generation. They
do not substitute elapsed ratios or `sleep` for proof of backpressure.

Active accepted connections peak at two; listener plus connection sockets
peak at three. Native certificate/loader file descriptors are tracked
separately and do not consume the socket cap. Socket and file close syscalls
must explicitly balance before successful process exit. The initial suite
does not yet claim source mapping/native SSL allocation ledgers or injected
fault/allocation coverage.

## Ownership and process bounds

Each invocation creates its own private temporary directory. The oracle
imports only guarded certificate/context helper modules, never CLI oracles
that execute their matrix at import. Existing helper and oracle files remain
unchanged. h11 checks HTTP framing, headers and exact binary body; a separate
`http.client.HTTPResponse` parses the complete response again.

Every service runs under `strace --kill-on-exit`; failure cleanup kills the
tracer and therefore its tracee. A GNU `timeout` bounds the Python process
group to 38 seconds with a two-second kill grace; Rust's outer bound is 45
seconds. Individual socket, startup, trace-wait and process-collection calls
have shorter deadlines. Success removes its directory unless
`LANIUS_KEEP_TEMP_ARTIFACTS` is set. Failure retains the trace, output and
diagnostic in the printed `lanius-server-concurrency-*` directory.

The Rust driver validates actual x86_64 executable output, generated jumps,
and the HTTPS native ELF profile/OpenSSL dependencies. Compilation remains
in the root's serialized GPU/native queue. Each command must remain below
two minutes; select a single group when admission or tracing approaches that
bound.

## Status

Source/static and CPU mutation controls are the only checks permitted during
initial fixture development. No new program compilation or native acceptance
is claimed until the root records its actual receipts. Report assertions
currently follow the agreed zero-based acceptance-order fields; additional
teardown/TLS-stat fields await the final application schema. Limits, host
faults and the 64-connection scale observation follow initial causal acceptance.

Run CPU-only oracle controls independently:

```sh
timeout --kill-after=2s 10s python3 \
  tests/fixtures/extended/server_concurrency/controls.py
```

These controls exercise trace identity/cap/error rejection and independent
HTTP reader rejection. They are not native service execution cases.
