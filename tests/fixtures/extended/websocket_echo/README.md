# One-message WebSocket echo execution fixtures

`oracle.py` runs independent Python clients against the actual compiled
`sample_programs/library/websocket_echo.lani` application. h11 parses the HTTP
responses, a separate parser validates unmasked server frames, fresh client
masking keys/nonces come from the host random source, and Python ssl/OpenSSL
provides TLS and certificate verification. No production cryptography is
implemented in these fixtures.

The application accepts one connection, echoes its first completed Text/Binary
message, services Ping/Pong, discards later bounded messages and mirrors Close.
Success requires code 1000 after the echo and, for TLS, sending the local
authenticated close_notify. TLS shutdown does not wait for the peer alert.
Readiness is exactly the actual bound numeric endpoint plus one newline. No
message payload is printed by the server.

## Focused groups

| Group | Cases | Behavior |
| --- | ---: | --- |
| `plain` | 11 | Binary, empty Text/Binary, fragmented UTF-8/binary with Ping, 126-byte and 65536-byte payloads, 64 fragments, exact Origin, IPv6, first-message-only echo |
| `handshake` | 12 | Malformed key/version/method/duplicate fields, missing Upgrade, exact route, missing/different/duplicate required Origin, captured early frame, incomplete head; HTTP 400/403/404 and rejection headers |
| `rejection` | 10 | Unmasked client, RSV, invalid UTF-8, truncated data, unclean EOF, early/abnormal Close, oversized frame, 65 fragments |
| `cli` | 14 | Invalid arguments/options/endpoint/credentials/Origin plus both help forms; network-only strace confirms no socket activity |
| `tls` | 4 | Independently verified TLS 1.2 and 1.3, bad client trust, strict observation of server close_notify |
| `credentials` | 3 | Missing certificate/key and mismatched key fail before listening |
| `deadline` | 1 | The five-second absolute service deadline bounds waiting for a client |
| `io` | 1 | Closed readiness stdout reports exit 5 after listener creation; no resource-cleanup claim |
| `integration` | 1, optional | Existing Lanius `websocket-once` client against the server |

Missing or different well-formed required Origin values receive HTTP 403; a
duplicate Origin is wire-invalid and receives HTTP 400 plus version 13.

Valid clients wait for HTTP 101 before transmitting frames. A captured request
plus early frame is deliberately rejected. Server responses never negotiate
extensions or subprotocols. Rejected application/frame data must not be echoed;
a protocol Close/control response before shutdown is allowed.

Every child has a bounded readiness/communication watchdog; each group has a
77-second watchdog. TLS test credentials are generated in a temporary directory
by the existing OpenSSL certificate fixture. No keys are checked in.

## Commands and evidence

After the root agent compiles the echo application with native SSL/crypto link:

```sh
python3 -B tests/fixtures/extended/websocket_echo/oracle.py plain target/stdlib-work/websocket-echo.elf
python3 -B tests/fixtures/extended/websocket_echo/oracle.py handshake target/stdlib-work/websocket-echo.elf
python3 -B tests/fixtures/extended/websocket_echo/oracle.py rejection target/stdlib-work/websocket-echo.elf
python3 -B tests/fixtures/extended/websocket_echo/oracle.py cli target/stdlib-work/websocket-echo.elf
python3 -B tests/fixtures/extended/websocket_echo/oracle.py tls target/stdlib-work/websocket-echo.elf
python3 -B tests/fixtures/extended/websocket_echo/oracle.py credentials target/stdlib-work/websocket-echo.elf
python3 -B tests/fixtures/extended/websocket_echo/oracle.py deadline target/stdlib-work/websocket-echo.elf
python3 -B tests/fixtures/extended/websocket_echo/oracle.py io target/stdlib-work/websocket-echo.elf
```

The optional integration command takes the existing client executable as its
third argument. The Rust driver is `tests/extended_websocket_echo_execution.rs`;
it uses one cached native application producer for the independent groups.

The `io` group uses an actual pipe with its read end closed and a nine-second
child watchdog. No elapsed-time assertion or leak/resource-cleanup claim is
attached to that case.

## Accepted runtime receipts

The actual native application source `dcdef14c`, executable
`44d1b314144f7f59722394ca6a14514fc69145dc5d85a5e24ca4465e4a7eb37f`,
passed 56 cases across eight separately run independent-peer groups:

| Group | Cases | Receipt under `target/stdlib-work/` | Detailed evidence |
| --- | ---: | --- | --- |
| `plain` | 11 | `websocket-echo-plain-native-first.log` | `/tmp/websocket-echo-plain-wmazif5s` |
| `handshake` | 12 | `websocket-echo-handshake-native-corrected-oracle.log` | `/tmp/websocket-echo-handshake-8ssils8c` |
| `rejection` | 10 | `websocket-echo-rejection-native-corrected-oracle.log` | `/tmp/websocket-echo-rejection-kkczu71y` |
| `cli` | 14 | `websocket-echo-cli-native-corrected-oracle.log` | `/tmp/websocket-echo-cli-sfpeua2g` |
| `tls` | 4 | `websocket-echo-tls-native-corrected-oracle.log` | `/tmp/websocket-echo-tls-e_msk65e` |
| `credentials` | 3 | `websocket-echo-credentials-native-corrected-oracle.log` | `/tmp/websocket-echo-credentials-j4inuans` |
| `deadline` | 1 | `websocket-echo-deadline-native-corrected-oracle.log` | `/tmp/websocket-echo-deadline-h4n7quqs` |
| `io` | 1 | `websocket-echo-io-native-first.log` | `/tmp/websocket-echo-io-ei6jaber` |

Plain cases used oracle `292068b1`. Their inputs and expectations are unchanged
in oracle `684d5894`, which ran the next six groups. Final oracle `f7805501`
added the passing `io` case and preserved all seven earlier groups' inputs and
ordinary behavior. The first handshake run correctly received HTTP 400 for
duplicate Origin; its stale 403
expectation was corrected to the existing wire contract. This was a fixture
expectation error. No implementation change was needed for that observation.
The fourth TLS case observes the local authenticated close_notify with strict
Python TLS EOF handling; it does not require a peer-alert wait that the current
TLS shutdown API does not promise.

The optional Lanius-to-Lanius integration also passed one case using the current
client executable `798f00e9` (application source `0ae21ee1`, current upgrade
module `cae29596` and HTTP module `5d495716`). Its receipt is
`target/stdlib-work/websocket-echo-integration-native-first.log`, with detailed
evidence in `/tmp/websocket-echo-integration-z7lv4xk1`. The server echoed the
binary upload and both programs completed their normal Close exchange.

Both new Rust integration drivers built successfully with `--no-run` in 2.18
seconds. The build-only receipt is
`target/stdlib-work/websocket-server-driver-build-first.log`. No Rust libtest
runtime execution is claimed; the native acceptance above came from direct
oracle runs. After adding the I/O test, the echo driver rebuilt with `--no-run`
in 1.43 seconds; its build-only receipt is
`target/stdlib-work/websocket-server-driver-build-io.log`. The nine passing CPU
controls check only the independent frame/response oracle and are separate from
the native execution receipts.

This is Linux x86_64 host-service coverage. IPv6 requires a working loopback
IPv6 stack; the IPv6 case is required and is not silently counted as passing on
a disabled stack. These tests make no GPU, formal verification, allocation
failure, leak-checking, multi-client, streaming-message or service-hardening
claim.
