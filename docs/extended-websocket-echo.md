# One-client WebSocket echo server

`sample_programs/library/websocket_echo.lani` serves one WebSocket connection
over a real nonblocking TCP socket or OpenSSL TLS stream. It echoes the first
completed text or binary message, then finishes the client's Close exchange.

```text
websocket-echo ENDPOINT [--tls-cert FILE --tls-key FILE] [--origin ORIGIN]
websocket-echo --help
```

For example:

```sh
websocket-echo 127.0.0.1:0
websocket-echo '[::1]:8443' --tls-cert server-chain.pem --tls-key server.key \
  --origin https://example.test
```

## Startup and ownership

`ENDPOINT` must be a numeric IPv4 or bracketed IPv6 socket address. Port zero
asks the OS for an available port. Once configured and listening, the program
writes the actual bound numeric endpoint followed by one newline to stdout.
It writes no request or message payload to stdout. A caller can read that line
and connect immediately. The listener accepts one client and closes after that
connection finishes or fails; it is not a concurrent or persistent service.

Supplying `--tls-cert` and `--tls-key` enables TLS; they must occur together and
both be nonempty. The OpenSSL server context and credentials are configured
before creating or binding the listener. The private-key passphrase is empty;
encrypted-key prompting is not provided. Clients are explicitly unauthenticated
at the TLS layer (`ClientAuthentication::Unauthenticated`): the server presents
its configured certificate but does not require a client certificate.

The branch-local socket or TLS stream is the sole mutable transport owner.
The I/O adapter stores references to that owner; matching the adapter's channel
does not copy ownership state. The upgrade and frame adapters borrow the same
transport and are destroyed before TLS shutdown or socket close. Failure paths
also destroy the adapters and close every acquired owner.

## Handshake policy

The generic server adapter reads and validates the HTTP upgrade request before
any response is sent. The application applies these policies:

| Request | HTTP response |
| --- | --- |
| Valid upgrade with target exactly `/echo`, satisfying configured Origin | 101 |
| Valid upgrade with any other target, including `/echo?query` | 404 |
| Target `/echo` with missing or different single well-formed configured Origin | 403 |
| Malformed, unsupported or incomplete handshake, while a reply can still be written | 400 |

With `--origin`, exactly one Origin field must have the configured value.
Comparison is byte exact after the HTTP parser trims surrounding optional
whitespace from the incoming field value. The configured value must be nonempty,
at most 4096 bytes and contain no control bytes. Without this option, this
example applies no Origin restriction. Origin checking does not authenticate
clients or grant resource access; no application authentication is implemented.
Duplicate Origin fields are rejected by the wire validator before application
policy and receive HTTP 400 with version 13, rather than HTTP 403.

HTTP rejection responses use the canonical HTTP encoder, an empty body,
`Connection: close` and `Content-Length: 0`. HTTP 400 also advertises
`Sec-WebSocket-Version: 13`. The upgrade owner is destroyed before writing the
rejection through the still-owned transport. Clock, transport or allocation
failures can prevent a rejection response from being written; every policy or
handshake rejection still exits with an error status.

The successful response uses OpenSSL to compute the protocol-defined Accept
digest and selects no subprotocol or extension. No cryptographic primitive is
implemented in Lanius. Clients must await HTTP 101 before sending frames;
captured bytes after the request head are rejected as an early-frame handshake
violation. This is not a WebSocket URL router or an HTTP fallback server.

## Message and Close behavior

The first completed text or binary message is echoed as one final frame with
the same opcode and exact payload. Empty messages are valid. Fragmented text
is checked for UTF-8 validity by the wire module. The application answers Ping
with Pong carrying the exact payload, and ignores Pong events. All server
frames are unmasked, as required by RFC 6455.

Further completed data messages are discarded within the same limits while
waiting for Close; they do not cause a second echo. The received Close payload
is mirrored and fully flushed. Success requires a previous echoed message,
peer Close code 1000, both Close directions complete and a successful final
transport check. Early Close is mirrored but fails the operation. Empty Close
payloads and codes other than 1000 also fail this example's success policy,
even where the wire protocol permits them.

On success, TLS mode flushes its local close_notify before closing the transport.
The TLS shutdown operation stops at local alert sent or a completed shutdown;
it does not wait for the peer's close_notify. This establishes a local
authenticated TLS close, not a mutual-alert exchange. A sticky
TLS failure after a positive read is checked before completing the operation.
Premature EOF, malformed frames, invalid UTF-8, exhausted limits, clock failure
and timeout are errors. There is no reconnect or message replay.

## Limits

| Resource | Limit |
| --- | ---: |
| Frame payload / message | 65536 bytes each |
| Fragments per message / received frames | 64 / 256 |
| Request head / response / HTTP line | 16384 / 16384 / 8192 bytes |
| HTTP fields / offered subprotocols | 32 / 8 |
| Upgrade buffer / frame buffer | 16384 / 65550 bytes |
| Upgrade / frame I/O calls | 8192 each |
| Upgrade read bytes / scan work | 1 MiB / 16 MiB |
| Frame read / accepted write bytes | 1 MiB each |
| TLS I/O / TLS operation calls | 16384 / 8192 |
| TLS read / accepted write bytes | 1064960 each |
| Accept attempts / listener polls | 512 each |
| App transport readiness waits | 512 |
| HTTP rejection write/flush attempts | 8192 combined |
| stdout / diagnostic write attempts | 64 / 8 per write operation |

One cooperative five-second deadline begins before TLS credential loading and
covers listener setup, readiness publication, accept, TLS handshake, HTTP
upgrade, frames and successful cleanup. The deadline does not reset after
activity. Blocking stdout, credential loading and synchronous OpenSSL/OS calls
cannot be interrupted by these checks; this is not a hard process timeout.
Layer budgets are separate, not one aggregate syscall limit. IPv6 listeners
set `Ipv6Only`; backlog is one.

## Status and diagnostics

| Exit | Meaning |
| ---: | --- |
| 0 | One echo and normal Close exchange completed, or help printed |
| 2 | Invalid CLI arguments or configuration shape |
| 3 | Network, TLS credentials, clock, policy, protocol, limit or cleanup failure |
| 4 | Reported Lanius allocation failure |
| 5 | stdout or primary diagnostic write failure |

Every failure after argument capture attempts one generic primary diagnostic:
`websocket-echo: operation failed`. Cleanup errors also attempt
`websocket-echo: cleanup failed`; that secondary diagnostic is best effort.
SIGPIPE is ignored before I/O. The ready endpoint may already have been printed
when a later connection or protocol failure occurs.

## Targets and verification

The intended executable target is Linux x86_64 with native linking, libc and
OpenSSL 3 (`ssl` and `crypto`). Plain and TLS modes share one executable and
both require those libraries. The GPU compiler generates native code; this
does not establish GPU execution of host services.

The application compiled and directly passed these native groups on 2026-10-28:

| Group | Cases | Behavior |
| --- | ---: | --- |
| Plain | 11 | IPv4/IPv6, empty text/binary, binary payloads through 65536 bytes, 64 fragments, UTF-8, Ping/Pong, Origin and first-message selection |
| Handshake | 12 | Malformed/unsupported upgrade, route and Origin policy, early captured frame, incomplete head, canonical HTTP rejection headers |
| Rejection | 10 | Invalid client frames, UTF-8, oversized payloads, fragment cap, premature EOF and early/abnormal Close |
| CLI | 14 | Help and invalid arguments/configuration; network tracing checks rejection before socket activity |
| TLS | 4 | Independent certificate verification under TLS 1.2/1.3, bad trust and strict observation of the server's local close_notify |
| Credentials | 3 | Missing certificate/key and mismatched key fail before listening |
| Deadline | 1 | Absolute service deadline while waiting for a client |
| I/O | 1 | Actual closed stdout reader while the listener is owned; failed readiness publication exits 5 |

One additional integration case passed using the native Lanius
`websocket-once` client against this server. These are separate direct native
groups; they are not Rust-driver test passes.

Application source SHA-256:
`dcdef14cf63a40444ac936a60cb1b2c2841dca5542a2b1f9420742ede0bd727d`.
Echo ELF SHA-256:
`44d1b314144f7f59722394ca6a14514fc69145dc5d85a5e24ca4465e4a7eb37f`.
The integration client uses source
`0ae21ee1b16b6199e1c8fc2bb721a90da926ed0f22c245b6f7518104cee268bf`
and current ELF
`798f00e9f65c17d0fdeac77afaeba031a75b266124c82014745a8599b7476287`.

Receipts under `target/stdlib-work/` are
`websocket-echo-compile-deadline-response-fix.log`,
`websocket-echo-plain-native-first.log`,
`websocket-echo-{handshake,rejection,cli,tls,credentials,deadline}-native-corrected-oracle.log`,
`websocket-echo-io-native-first.log` and
`websocket-echo-integration-native-first.log`. Evidence directories are
`/tmp/websocket-echo-plain-wmazif5s`,
`/tmp/websocket-echo-handshake-8ssils8c`,
`/tmp/websocket-echo-rejection-kkczu71y`, `/tmp/websocket-echo-cli-sfpeua2g`,
`/tmp/websocket-echo-tls-e_msk65e`,
`/tmp/websocket-echo-credentials-j4inuans`,
`/tmp/websocket-echo-deadline-h4n7quqs`, `/tmp/websocket-echo-io-ei6jaber` and
`/tmp/websocket-echo-integration-z7lv4xk1`.

The plain group used an earlier oracle (`2920…`) whose plain inputs/assertions
are unchanged. The other six original groups and integration used oracle SHA-256
`684d5894251c6d72e7fe629de6e8af47f751d486caca01136834a54e3cfbf31c`.
The added I/O group used final oracle SHA-256
`f780550196e6665373983d34a64bffe128c2cd19deabab8df74d070b0a8d754a`;
all earlier group functions, inputs and assertions are unchanged. The eight
groups cover 56 cases, with the client integration counted separately.
The first handshake attempt failed a stale fixture expectation of HTTP 403 for
duplicate Origin. The validator correctly returned HTTP 400 with version 13;
the corrected fixture then passed. A TLS test expectation was also corrected
to the existing local-alert shutdown contract. Neither adjustment changed the
application or weakened the required WebSocket Close exchange.

The final server and echo Rust drivers, including the added I/O test, build
with `--no-run` in 1.43 seconds
(`target/stdlib-work/websocket-server-driver-build-io.log`); the prior driver
build passed in 2.18 seconds (`websocket-server-driver-build-first.log`). This is build
evidence only; no Rust-driver runtime test pass is claimed. No allocation-failure
cleanup, leak-freedom or formal-verification claim follows from these finite
functional tests. IPv6 coverage requires an operational loopback IPv6 stack;
it is not silently counted as passing on a disabled stack. See
`tests/fixtures/extended/websocket_echo/README.md` for independent-client details.
