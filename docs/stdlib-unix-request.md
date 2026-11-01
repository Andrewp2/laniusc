# Bounded Unix-stream request client

`sample_programs/library/unix_request.lani` sends one binary stdin payload to
a local Unix-stream peer and prints one fully admitted binary response:

```sh
unix_request path /run/example.sock < request.bin > response.bin
unix_request abstract example-service < request.bin > response.bin
```

The namespace is explicit. `path` uses a pathname, while `abstract` uses
Linux's abstract Unix namespace. This is Unix-stream IPC, not TCP. A sole
`--help` or `-h` prints help and bypasses stdin/network activity.

## Address and argument preflight

The CLI is exactly `unix_request path|abstract NAME`, or sole help. Capture
admits at most two values and 128 total bytes, excluding terminating NULs.
Namespace spelling is lowercase and exact; there are no extra options.

Pathnames contain 1..107 raw non-NUL bytes. Abstract names contain 0..107 raw
argv bytes. Neither requires UTF-8, normalization or a special prefix.
`@` is literal in both namespaces. Since argv cannot contain NUL, this CLI
cannot express embedded abstract NUL bytes even though the public library
supports them. An empty abstract name is a valid explicit name, not an
autobind request.

Name bounds and pathname validity are checked before stdin or socket effects.
The public socket operation also revalidates its borrowed pathname at the
host boundary. Names borrow the argument owner, which stays live through
the exchange. The program neither binds nor unlinks a server pathname.

## Request and response framing

Stdin is one binary request payload, at most 1048576 bytes, with actual EOF
required before socket creation. It is sent as:

```text
four-byte big-endian u32 payload length | exactly that many payload bytes
```

The application calls the public `core::endian` u32 big-endian functions.
After sending the entire request, it calls `shutdown(Write)` once. That
half-close lets a peer verify request EOF while retaining the response side.

The response has the same framing, with at most 1048576 payload bytes.
The client reads the complete four-byte header, guards the full u32 length
before narrowing, receives exactly that many bytes, then requires actual
response EOF with a one-byte probe. Short headers, truncated payloads,
oversized declarations, trailing bytes and a peer that withholds EOF are
errors. Empty request and response payloads are valid; both still have a
four-byte frame header, and an empty response still requires EOF.

Stdout contains only the response payload, without its frame header.
It starts only after complete response admission and successful explicit
socket close. No network/framing/deadline/allocation/close error publishes
a response prefix. A valid empty response succeeds with empty stdout and
needs no stdout write.

## One connection, one deadline

After bounded stdin reaches EOF, the application starts one five-second
monotonic deadline before creating its nonblocking Unix stream. It calls
`connect` once. Interrupted, WouldBlock/EAGAIN and other failures terminate
that connection attempt; it does not apply TCP's pending-connect/readiness
policy or open a replacement connection.

Request/response transfers use public `send_until` and `receive_until`
with that same absolute deadline. Confirmed partial transfers advance the
cursor once; no bytes are replayed. Both request-header/body and
response-header/body/EOF calls share one 8192-call transfer budget.

The until methods may perform an initial transfer before waiting. Therefore
the application also checks the monotonic deadline before and after every
successful public transfer, including header/body partials and the EOF probe.
It checks around connect and shutdown and after close before admitting output.
A peer making continual positive progress cannot renew the aggregate deadline.
Clock failure, reversal or expiry is an error.

The 8192-call limit counts public transfer invocations, not raw host syscalls.
A public until call can perform multiple host send/receive/poll attempts
following the same deadline. Connect, shutdown and close each have their own
single attempt and do not consume this transfer count. This is a cooperative
deadline policy, not an interruption mechanism for every host call.

Blocking stdin and stdout are outside the network deadline. Their attempt
limits do not impose a whole-command wall-clock timeout.

## Owners and cleanup

Input and staged response use separate `alloc::io::Buffer` owners, each with
a 1048576-byte logical limit. They begin without backing and grow only for
positive admitted bytes. Response allocation starts after a valid response
header and a positive body transfer; an empty response needs no backing.
Stack staging preserves actual native array stride through the public APIs.

A single lexical `UnixStream` owner remains live through the whole exchange.
It is borrowed by helpers and closed exactly once after any acquired-socket
outcome, including protocol, allocation and deadline failure. Close invalidates
the owner before its host attempt and is not retried. If the exchange already
failed, a later close failure preserves its primary status. Otherwise a close
failure prevents stdout and returns 6.

After the network workflow returns, the input owner is explicitly destroyed.
The response owner remains live through stdout and is then destroyed on every
path. The argument owner is released before main returns. No owner is copied
into a second cleanup authority; no automatic destruction is assumed.

## Budgets and failures

| Resource | Bound |
| --- | ---: |
| Captured arguments / bytes | 2 / 128 |
| Pathname bytes | 1..107 |
| Abstract argv name bytes | 0..107 |
| Input / response payload bytes | 1048576 each |
| Input stream attempts, including EOF and Interrupted | 8192 |
| Public network transfer calls, shared both directions | 8192 |
| Connected-workflow monotonic deadline | Five seconds |
| Socket creation / connect / shutdown Write | At most one each |
| Close after socket acquisition | Exactly one attempt |
| Native transfer staging | At most 1024 bytes per host send/receive |
| Stack input/response scratch | 4096 logical bytes each |
| Output stream attempts, including Interrupted | 8192 |
| Help stdout / diagnostic stderr attempts | 64 / 8 |

At the stdin byte cap, a one-byte probe distinguishes EOF from excess input
without extending the buffer. Ordinary input/output Interrupted retries consume
their attempt budgets. Other input errors terminate; socket until-method
retries retain the common deadline.

Stdout advances only by confirmed positive counts. Zero, invalid counts,
other errors and exhausted attempts terminate. An output failure may leave
the already published payload prefix; it is not replayed or rolled back.
Success acknowledges completed descriptor writes, not downstream consumption
or crash durability.

| Exit | Meaning |
| ---: | --- |
| 0 | Complete admitted response payload written, or help written |
| 2 | Invalid CLI/name, input byte/attempt bound, or public network-call exhaustion |
| 3 | Stdin or argument-capture host error |
| 4 | Argument, input or response allocation failure |
| 5 | Stdout/help or SIGPIPE-policy failure |
| 6 | Socket/connect/network/framing/deadline/close failure |
| 7 | Unexpected internal codec/buffer failure |

Errors attempt exactly `unix_request: operation failed\n` with eight stderr
calls. Diagnostic failure preserves the primary status. SIGPIPE is ignored
before I/O; setup failure returns 5 without a diagnostic. Socket sends also
use the library's MSG_NOSIGNAL policy. Successful runs have no stderr output.

## Target and acceptance

All four registered application groups passed on 2026-10-28, totaling 84
native cases across two focused runs:

| Accepted group | Cases | Receipt under `target/stdlib-work/` |
| --- | ---: | --- |
| Model | 24 | One test, 8.49s; `unix-stream-app-model-first.log`, three other tests filtered |
| CLI, I/O and rejection | 19 + 24 + 17 | Three tests, 21.50s; `unix-stream-app-boundaries-first.log`, model filtered |

The model run's driver build took 1.86s. Both registered runs compiled the
application through the GPU compiler and passed the shared strict ELF checker
before native Linux x86_64 CPU execution, using the public Linux Unix-stream,
clock and allocator services. Abstract addressing is Linux-specific. GPU-device
execution, other backends and other operating-system address layouts remain
unverified.

Executed application source SHA-256:
`10e6ae4be570ff9a34844503a9fe81c651c6e83dfa952ff6c651f9ddc9fb119a`.
Socket module SHA-256:
`44f6739da9be0aa5d28c97dee2c905bca157e237df91c34a0ee6790909c06ccb`.
Accepted oracle SHA-256:
`27910405700a69f7cc8bfde285e4abef527f46cf0856faba9a0e78154fd04d58`.
Independent peer SHA-256:
`bd22278a5168c97c65abcdf7de10d161547cee76673b9b078298eb1289bc1879`.
Evidence directories:

- Model: `/tmp/unix-request-model-mok6db87`.
- CLI: `/tmp/unix-request-cli-e65nkgzw`.
- I/O: `/tmp/unix-request-io-9qel0g7v`.
- Rejection: `/tmp/unix-request-rejection-i4b8rt2m`.

The independent test-only peer uses the host AF_UNIX API in a separate
process. A readiness pipe acknowledges bind/listen before the client starts.
It retains the complete request through write-half EOF and compares its wire
bytes with an independently supplied BE32 length and original binary input.
Expected response bytes do not come from the production codec. Models cover
both namespaces, empty/binary frames, 1024-byte boundaries, exact 1 MiB
input/response, 107-byte names, raw non-UTF8 names, literal `@`, empty abstract
names and BE32 length boundaries.

Rejections cover input overflow before socket creation, missing endpoints,
short response headers/bodies, oversized/high-bit lengths, trailing bytes and
second frames. The two actual five-second deadline cases send no response or
withhold EOF after a complete response. In the accepted peer version, a
separate parent-controlled pipe keeps the peer alive until the client returns;
request write-half EOF cannot release it early. These finite deadline cases
do not force exhaustion of the 8192 public network-transfer budget or establish
a raw-host-attempt quota.

I/O cases execute read/send/receive Interrupted retries, stdin/stdout errors,
connect/send/receive/shutdown/close/clock/output/SIGPIPE failures, and six
reached allocation denials: first/last input growth, first/last response growth
and both help-argument owners. Allocation failures return 4 with empty stdout.
Detailed traces require matching explicit same-address/same-size releases for
observed successful mappings and one close attempt for each acquired socket.
Connect EINTR is not retried or replayed. Injected close errors suppress that
kernel call: evidence checks one attempt/invalidation, while process exit
performs final host cleanup; it does not show that the failed close itself
released the descriptor.

An untraced regular-file stdout case with `RLIMIT_FSIZE=10` and ignored
SIGXFSZ leaves exactly the first ten expected binary response bytes and returns
5 after an actual positive write. No successful count is fabricated. Separate
traced output-error cases observe owner/descriptor cleanup. Compact persistent
EINTR summaries check 8192 stdin errors, or 8192 output errors followed by the
successful stderr diagnostic; those summaries do not observe mapping releases.
These finite observations are not a resource checker or proof of general
lifetime, aliasing, leak freedom or arbitrary-failure safety. Defensive internal
status 7 is not claimed reachable from valid bounded inputs.

See `tests/fixtures/stdlib_execution/unix_request/README.md` for retained
commands and detailed scope, and `tests/stdlib_unix_request_execution.rs` for
the registered driver. Whitespace-only driver formatting after these receipts
does not represent a native rerun. With a warm build and configured GPU,
reproduce using:

```sh
timeout --kill-after=2s 100s flock -w 95 target/stdlib-work/library-gpu.lock \
  env CARGO_TARGET_DIR=target/stdlib-build LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=70000 \
  cargo test --test stdlib_unix_request_execution -- --nocapture --test-threads=1
```

Production is entirely Lanius. This application adds no compiler, runtime ABI,
proof, host service, Rust/Python library implementation, JSON transport or
Wasm dependency. See the [Unix-stream plan](library-unix-stream-plan.md) for
the separate public library contracts and acceptance requirements.
