# One-message WebSocket client

`sample_programs/library/websocket_once.lani` is a small client that sends stdin
as one binary WebSocket message and writes the first completed peer text or
binary message to stdout. Output is staged until the WebSocket Close exchange
and transport cleanup succeed.

```text
websocket-once ENDPOINT AUTHORITY TARGET [--tls-name DNS] [--ca-file FILE]
websocket-once --help
```

For example:

```sh
printf 'hello' | websocket-once 127.0.0.1:8080 localhost:8080 /echo
printf 'hello' | websocket-once 127.0.0.1:8443 localhost:8443 /echo \
  --tls-name localhost --ca-file development-ca.pem
```

## Address and trust choices

`ENDPOINT` is an explicit numeric socket address, such as `127.0.0.1:8080` or
`[::1]:8080`, with a nonzero port. `AUTHORITY` supplies the exact HTTP Host
field. `TARGET` is an origin-form path beginning with `/`, optionally followed
by a query. HTTP syntax validation runs before connecting.

`--tls-name` enables verified TLS and supplies a DNS reference identity and SNI
name. A numeric TLS name is rejected by this example. `--ca-file` selects a CA
file and requires `--tls-name`; otherwise TLS uses OpenSSL's default trust
paths. The TCP endpoint, HTTP Host and TLS reference identity are deliberate
separate inputs. The program does no DNS lookup and does not parse `ws:` or
`wss:` URLs. It does not provide Origin, authentication, subprotocol selection,
extensions, redirects, reconnects or request replay.

OpenSSL verifies the certificate chain and DNS identity before HTTP data is
sent. OpenSSL also computes the protocol-defined Accept digest. Lanius contains
no custom cryptographic primitive. A shared bounded OS-entropy budget supplies
the 16-byte handshake nonce and a fresh four-byte masking key for every client
data, Pong and Close frame; entropy failure aborts the operation.

## Message and close behavior

1. Read stdin through EOF into a bounded buffer. Empty input is valid.
2. Connect and complete the WebSocket upgrade, preserving frame bytes that
   arrive in the same read as the HTTP 101 response.
3. Send one binary message. Receive fragments and answer Ping with matching
   Pong payloads; ignore Pong events.
4. Copy the first completed text or binary message into independent storage,
   then send Close code 1000. Subsequent messages are discarded while the
   bounded exchange waits for the peer's Close.
5. Require peer Close code 1000 and a completely flushed local Close. A Close
   before any completed message is echoed and fails the operation. Empty Close
   payloads, code 1001 and all other codes fail this example's success policy,
   even where the wire protocol permits them.
6. Destroy the upgrade/frame owners, send TLS close_notify on success, close
   the transport, and publish the staged message. No trailing newline is added.

Malformed frames, invalid text UTF-8, premature EOF, exceeded limits, trust
failure or timeout leave stdout empty. The TLS transport's sticky error check
runs before completion so a late clock error after a positive read cannot be
published as success. Cleanup always runs; a cleanup failure preserves an
existing primary status and adds a secondary diagnostic.

## Bounds

| Resource | Limit |
| --- | ---: |
| Input message, received message, frame payload | 65536 bytes each |
| Fragments per message | 64 |
| Received frames, including control/fragment frames | 256 |
| HTTP request/head | 16384 bytes |
| HTTP line / headers | 8192 bytes / 32 |
| HTTP authority / target | 1024 / 4096 bytes |
| Upgrade / frame buffered bytes | 65550 each |
| Upgrade read bytes / wire work | 1 MiB / 16 MiB |
| Upgrade / frame I/O calls | 4096 / 8192 |
| Frame read / accepted write bytes | 1 MiB each |
| TLS I/O / TLS operation calls | 16384 / 8192 |
| TLS read / accepted write bytes | 1064960 each |
| App readiness waits | 512 |
| Shared entropy calls | 1024 |
| stdin attempts / stdout attempts | 1024 each |

The five-second absolute network deadline starts after stdin EOF and includes
TLS context setup, connect, upgrade, frames and successful cleanup. It is
checked around I/O and state transitions. Blocking stdin and stdout have no
wall-clock deadline. A synchronous OpenSSL or OS call cannot be interrupted by
these cooperative checks, so this is not a hard whole-process timeout. Every
stdin attempt, including EINTR and the excess-byte probe, spends its call
budget. Network limits are separate per layer, not one aggregate syscall cap.

## Exit status

| Status | Meaning |
| ---: | --- |
| 0 | Message published after successful close and cleanup, or help printed |
| 2 | Invalid arguments, request/configuration or stdin failure/limit |
| 3 | Transport, entropy, trust, clock, protocol, deadline or cleanup failure |
| 4 | Reported Lanius allocation failure |
| 5 | stdout write failure or call limit |

SIGPIPE is ignored before I/O. A failed diagnostic write does not replace the
primary status. Stdout failure can happen after a valid network exchange; the
program may already have published a prefix when that write fails.

## Targets and evidence

The intended executable target is Linux x86_64 with native linking, libc and
OpenSSL 3 (`ssl` and `crypto`). Both plain and TLS modes use the same executable
and therefore require those libraries. The GPU compiler produces this native
program; this does not claim GPU execution of host services.

The Linux x86_64 application compiled and directly passed these finite groups
on 2026-10-28: plain 9 cases, rejection 12, CLI 17, I/O 3 and TLS 5. Those
results cover actual TCP/TLS peers, binary messages, empty stdin upload and
empty response, coalesced and
fragmented input, Ping/Pong, no-publication error paths, closed stdout, the
absolute deadline, verified TLS 1.2/1.3, isolated default trust paths, and
certificate identity/trust failures. The executable's native dependencies are
`libssl.so.3`, `libcrypto.so.3` and `libc.so.6`.

Executed source SHA-256 is
`0ae21ee1b16b6199e1c8fc2bb721a90da926ed0f22c245b6f7518104cee268bf`;
ELF SHA-256 is
`1e946119df3d277e9f28817c860e53d9b8b6ae1c23ee5459bf65e5bbe42f3ab5`.
The compile receipt is `websocket-once-compile-borrowed-owner.log`; the plain
receipt is `websocket-once-plain-native-empty-upload.log`. The other group
receipts are `websocket-once-{rejection,cli,io,tls}-native-borrowed-owner.log`,
all under `target/stdlib-work/`. The final plain group used oracle SHA-256
`54598776b41694c278e27b0772199e4273e06f34f19126fddb1dd5612e539c73`;
its only change from the other groups' oracle (`1283881d…`) makes the existing
empty-response case also send empty stdin. Other group inputs and assertions
are unchanged. Eight CPU-only oracle controls pass separately.
The application and transport Rust drivers both build with `--no-run` in 2.00
seconds (`websocket-transport-driver-build-first.log`); Rust-driver execution
remains pending. These results do not prove
allocation cleanup under OOM or formal correctness. See
`tests/fixtures/extended/websocket_once/README.md` for exact group boundaries.

An earlier application version passed its plain groups but aborted in its
first TLS case: the wrapper matched mutable owning stream state by value.
The repaired wrapper stores borrowed references and retains the sole
socket/TLS owner in branch scope throughout exchange and cleanup. All five
groups above ran again against that repaired source. The earlier failure is
retained in `websocket-once-tls-native-first.log`; no compiler or oracle change
was used to make it pass.
