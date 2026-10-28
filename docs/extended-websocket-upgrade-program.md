# Offline WebSocket server upgrade

`sample_programs/library/websocket_upgrade.lani` reads one HTTP WebSocket
upgrade request from stdin through EOF, validates it and writes its complete
HTTP 101 response to stdout. It combines `std::args`, `ext::cli`,
`std::stream`, `ext::websocket` and `ext::openssl_websocket`. OpenSSL performs
the RFC accept digest; Lanius performs request checks and response encoding.

**Status:** compiled and executed on Linux x86_64 with OpenSSL 3. Direct
functional groups passed: 22 successful handshake cases, 30 rejected-request
cases, 15 CLI cases and four real I/O failure cases. The Rust integration
driver built with `--no-run`; Rust libtest runtime execution was not run.
No GPU runtime or connected WebSocket support is claimed. The accepted ELF
SHA-256 is `83a760bf495d4d587c3255331ae910bb44655488903c8382f8019fb802c46a37`;
the exact build and direct-run receipts are in the fixture README.

## Use

Build for the Linux x86_64 native C profile with OpenSSL 3 `libcrypto`:

```sh
laniusc --emit x86_64 --native-link --native-library crypto \
  --stdlib-root stdlib --source-root extended \
  -o websocket-upgrade sample_programs/library/websocket_upgrade.lani
./websocket-upgrade < request.http > response.http
./websocket-upgrade --protocol chat < request.http > response.http
./websocket-upgrade --help
```

The supported options are `--protocol TOKEN` and `--help`/`-h`. The protocol
option can appear once, either with a separate value or as `--protocol=TOKEN`.
Its value must contain 1–256 bytes and match an offered protocol exactly,
including case. Omitting the option declines all offered protocols. The tool
declines all extensions. It accepts no operands or input filenames. Help
does not read stdin; malformed options still fail when combined with help.

The tool requires EOF before responding. Use it with a completed request
file or a producer that closes its pipe. Directly attaching it to a live
socket that remains open will wait for more input. Bounded syscall attempts
do not put a time limit on a blocking read or write.

## Processing and limits

The program copies bounded arguments, reads a bounded request, calls
`websocket::validate_request`, checks that the entire input is the request
head, computes the 28-byte accept value through OpenSSL and calls
`websocket::encode_response`. The request owner remains alive through
response encoding. The response owner remains alive through publication.
Both owners are explicitly destroyed after use, including returned errors.
The program borrows stdin/stdout/stderr and does not close them.

The limits are fixed:

| Input or operation | Maximum |
| --- | ---: |
| Arguments after the executable | 8 |
| Argument bytes, excluding terminators | 8192 |
| Selected protocol bytes | 256 |
| Input bytes / HTTP head bytes | 16384 |
| HTTP line content bytes, excluding CRLF | 4096 |
| Request/response fields | 64 |
| Offered protocols | 32 |
| Stdin read attempts | 128 |
| Stdout write attempts | 64 |
| Stderr diagnostic attempts | 8 |

Every I/O attempt consumes a call credit, including interrupted calls. Reads
and writes use the stream adapter's maximum 1024 bytes per call. At the input
byte cap, the program probes one further byte: EOF accepts the boundary;
another byte fails without appending it. A peer supplying tiny chunks can
exhaust the read-call limit before reaching the byte limit.

All validation and encoding finish before the first stdout write. Successful
output contains HTTP/1.1 status 101, Upgrade/Connection fields, the accept
field and optionally one selected protocol. It contains no body, content
length, transfer encoding or extension selection. Trailing request bytes,
including an initial WebSocket frame, are rejected because this offline tool
has no transport owner to receive them. Once output publication begins, a
later write failure may leave a prefix in stdout; operating-system writes
are not transactional.

| Exit | Meaning |
| --- | --- |
| 0 | Response or help written successfully |
| 2 | Invalid arguments, request, protocol selection or input/wire limit |
| 3 | Stdin error, exhausted read-call limit or failed OpenSSL accept operation |
| 4 | Lanius allocation failure |
| 5 | SIGPIPE policy setup or stdout failure/call limit |

The process ignores SIGPIPE before writing anything. A closed stdout reader
therefore returns exit 5 rather than terminating by signal. Diagnostic
delivery failures retain the primary exit class. OpenSSL can reject the
operation when the host's provider policy disables its required digest.

## Scope

This is an offline handshake processor. It does not listen, connect, upgrade
a transport owner, exchange frames, enforce origin/resource/authentication
policy or negotiate TLS. A connected server must establish those policies
and preserve unread bytes when it hands a socket to WebSocket framing.
The accept value does not authenticate a peer or provide confidentiality.

The response contract follows
[RFC 6455 server acceptance](https://www.rfc-editor.org/rfc/rfc6455.html#section-4.2.2).
See the [wire module](extended-websocket.md) and
[OpenSSL accept module](extended-openssl-websocket.md) for their individual
contracts. Focused cases, accepted source hash and exact direct-run receipts
live in `tests/fixtures/extended/websocket_upgrade_app/README.md`. These finite
functional checks do not certify every allocation-failure path or memory
safety property.
