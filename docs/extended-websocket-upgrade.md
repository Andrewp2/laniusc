# Borrowed WebSocket upgrade

`ext::websocket_upgrade` sends one validated opening request, flushes the
borrowed transport, and receives one valid WebSocket response head. It retains
any frame bytes delivered with that head and can transfer them into
[`ext::websocket_stream`](extended-websocket-stream.md).

Its server owner receives and validates one opening request, pauses for caller
policy, stages an accepted response and flushes it before becoming ready for
server framing. Both owners borrow a caller-owned transport.

The existing
[`ext::http::Cursor`](extended-http-cursor.md) finds the HTTP head, and
[`ext::websocket`](extended-websocket.md) validates the request, response,
extensions and selected subprotocol. There is no separate HTTP parser here.
The module performs no socket, TLS, clock, random or cryptographic operation.
The caller provides a transport that implements `core::io::Read` and
`core::io::Write` when advancing the handshake.

## Client API

```text
client<T>(&T, request:View<u8>, expected_accept:View<u8>, Limits)
    -> Result<Client<T>,Failure>

Client<T>.borrow() -> &Client<T>
Client<T>.stats() -> Stats
Client<T>.is_active() -> bool
Client<T>.is_ready() -> bool
Client<T>.step() -> Result<Progress,Failure>
    where T: core::io::Read, T: core::io::Write
Client<T>.response() -> Result<websocket::Response,Failure>
Client<T>.into_stream(websocket_stream::Limits)
    -> Result<websocket_stream::Stream<T>,Failure>
Client<T>.destroy() -> bool

Progress::{Again,NeedRead,NeedWrite,Ready}
Stats { io_calls:u64, read_bytes:u64, accepted_bytes:u64, work:u64 }
Failure { cause:Cause, stats:Stats, completed:i32 }
```

Construction, inspection, destruction and conversion require no I/O trait
bounds. The caller retains the same live transport for the entire operation.
`destroy()` frees handshake storage, returns `true` once and `false` thereafter,
and never flushes or closes that transport. Statistics remain inspectable after
destruction.

## Admission and request identity

Both input views require nonnegative, nonoverflowing logical metadata and
physically backed storage. The factory checks metadata and limits, applies the
request cap, validates the complete request, and requires its parsed head to
occupy the entire input. Following bytes, including an already encoded frame,
are rejected. It then requires exactly 28 canonical padded Base64 bytes that
decode to 20 bytes for the expected Accept value. All these checks precede
source copying and transport I/O.

The expected Accept must have been computed for this request's original key
through an established digest provider, such as
[`ext::openssl_websocket`](extended-openssl-websocket.md). The factory checks
the value's shape; it cannot establish that the caller used the correct key.
Fresh nonce generation and peer authentication remain the caller's policies.

After successful admission, the module owns an immutable copy of the request
and a by-value copy of the expected Accept. The caller may then change or
release both original input buffers. The owned request is validated again at
response completion so response validation uses the retained request identity
and offered subprotocols. It is never resent by this module.

## Advancing a handshake

The phases are sending the request prefix, flushing the transport, receiving
the response head, and ready. One `step()` calls at most one inner `write`,
`flush` or `read` operation.

| Outcome | Behavior |
| --- | --- |
| Positive write | Preserve the accepted prefix, then return `Again` |
| Successful `flush()` returning zero | Enter response reception, then return `Again` |
| Positive read | Preserve every byte, advance the canonical cursor and validate a complete head, then return `Again` |
| `Interrupted` | Charge the attempt and return `Again` without inventing progress |
| `WouldBlock` during write/flush | Return `NeedWrite` |
| `WouldBlock` during read | Return `NeedRead` |
| Ready | Return `Ready` without another transport call |
| Fatal error | Save and return the same failure on subsequent operations |

A successful read may set `is_ready()` while returning `Again`. Calling
`step()` again yields `Ready`; `response()` and `into_stream()` may also be
used as soon as `is_ready()` is true. Repeated ready steps perform no I/O and
do not change statistics.

Positive counts must fit the requested range. A zero write fails with
`Io(WriteZero)`. A negative or oversized read/write result, or nonzero flush
result, fails with `Io(InvalidCount)`. A nonempty read returning zero is actual
EOF: the cursor receives `eof=true`, preserving its canonical incomplete or
malformed-head error. A limit, timeout imposed by an outer layer, or
`WouldBlock` is never interpreted as EOF.

The cursor stops at `HeadReady` and is never advanced into frame bytes. The
complete head must pass `websocket::validate_response`: HTTP/1.1 status 101,
the expected Accept, valid Connection/Upgrade fields, no negotiated extension,
and at most one selected subprotocol offered by the original request.
Informational or ordinary HTTP responses fail this handshake; the module does
not skip them, read their bodies, redirect, reconnect or replay the request.

## Receiving storage and limits

```text
Limits {
    wire:websocket::Limits,
    request_bytes:i32,
    buffer_bytes:i32,
    io_calls:u64,
    read_bytes:u64,
    work:u64
}
```

`default_limits()` uses the WebSocket wire defaults plus:

| Limit | Default | Meaning |
| --- | ---: | --- |
| `request_bytes` | 65,536 | Entire copied request |
| `buffer_bytes` | 66,560 | Retained response head and coalesced frame prefix |
| `io_calls` | 65,536 | Total inner read, write and flush attempts |
| `read_bytes` | 66,560 | Bytes successfully read by this handshake |
| `work` | 8,388,608 | Canonical HTTP cursor work units |

Request and buffer caps must be in `1..=67,108,864`. Every nested wire/HTTP
limit must be nonnegative, and `wire.http.head_bytes <= buffer_bytes`.
I/O, read-byte and work budgets may be zero. Zero I/O budget permits
construction and fails the first attempted operation with `IoLimit`.

Read requests use positive scratch capacity of at most 1,024 bytes and fit both
remaining buffer and read-byte budgets. Capacity is reserved before every read
that needs storage growth. Growth is geometric and capped by `buffer_bytes`;
appending bytes returned by a valid read cannot allocate. Thus an allocation
failure cannot discard bytes already consumed from the transport. Previously
received bytes stay unchanged when storage relocates, as required by the
cursor.

`accepted_bytes` counts request bytes accepted by successful inner writes.
Every attempted read, write and flush counts toward `io_calls`, including
interruptions, would-block outcomes and invalid counts. `read_bytes` counts
only valid positive read results, including any coalesced frame bytes.
`work` snapshots `Cursor.work()` and never exceeds its budget. It covers the
cursor's defined work; it does not count request copying, allocator work or
the final canonical WebSocket validation passes. Those operations remain
bounded by request, HTTP and wire limits.

Exhausted buffer, read-byte and call budgets fail before another transport
call. They do not issue zero-length reads or infer a clean connection end.
Callers implementing deadlines must check them outside this portable module.
An inner blocking operation is subject to that transport's own behavior.

## Response views and stream conversion

`response()` returns borrowed `websocket::Response` metadata only when ready.
Its head, optional selected protocol and `remaining` frame prefix borrow the
client's frozen response buffer. The response method uses the static original
`GET` value. Keep those views unchanged and stop using them before successful
conversion or destruction.

`into_stream(limits)` calls
`websocket_stream::new(inner, Role::Client, response.remaining, limits)`.
The stream factory copies the complete prefetched prefix before publishing
its owner. On success, the upgrade owner releases its request/response storage
and becomes inactive; the stream retains the same borrowed transport and all
coalesced frame bytes. Those prefetched bytes do not count as reads made by
the stream itself.

A stream construction failure is returned as `Cause::Stream`. It leaves the
upgrade ready, its metadata valid and its transport untouched. The caller can
retry conversion with different stream limits or after resolving an
allocation failure. Neither conversion path performs transport I/O.

## Failure and ownership rules

`Cause` distinguishes `Bounds`, `InvalidLimits`, `Inactive`, `NotReady`,
`AllocationFailed`, `RequestLimit`, `BufferLimit`, `ReadLimit`, `IoLimit`,
`Io(core::io::Error)`, `Wire(websocket::Error)`, `Http(http::Error)` and
`Stream(websocket_stream::Failure)`.

`Failure.stats` records the counters at failure. `completed` is the accepted
request prefix for write/flush failures, the retained read progress for
receive or response-validation failures, and zero for local admission,
allocation, byte-cap, state or conversion failures. An exhausted I/O-call
budget preserves that phase's completed prefix too: accepted request bytes
while sending/flushing, retained response bytes while receiving. The phase
determines what that count describes; it is not permission to restart the
request elsewhere.

A fatal `step()` failure is sticky and leaves the memory owner active until
`destroy()`. Subsequent steps, response access and conversion return that same
failure without further transport calls. `response()` before readiness
returns `NotReady` without poisoning the client. After destruction or
successful conversion, these operations return `Inactive`.

Keep one active owner: by-value copies alias the same allocations and cannot
fork cleanup or state-machine authority. Do not mutate library-maintained
fields. The borrowed transport must not be accessed independently while the
handshake or resulting stream is using it. Current language types do not prove
these lifetime and exclusivity rules; no borrow-checking or formal-verification
claim is made here.

## Server API and policy boundary

```text
server<T>(&T, ServerLimits) -> Result<Server<T>,Failure>
default_server_limits() -> ServerLimits

Server<T>.borrow() -> &Server<T>
Server<T>.stats() -> Stats
Server<T>.is_active() -> bool
Server<T>.has_request() -> bool
Server<T>.is_ready() -> bool
Server<T>.request() -> Result<websocket::Request,Failure>
Server<T>.step() -> Result<ServerProgress,Failure>
    where T: core::io::Read, T: core::io::Write
Server<T>.accept(fields:View<http::Field>, accept:View<u8>,
    protocol:Option<View<u8>>) -> Result<i32,Failure>
Server<T>.into_stream(websocket_stream::Limits)
    -> Result<websocket_stream::Stream<T>,Failure>
Server<T>.destroy() -> bool

ServerProgress::{Again,NeedRead,NeedWrite,Request,Ready}
ServerLimits {
    wire:websocket::Limits, buffer_bytes:i32, response_bytes:i32,
    io_calls:u64, read_bytes:u64, work:u64
}
```

The factory validates limits, initializes the canonical HTTP request cursor
and creates empty owners. It performs no allocation or transport call and
requires no I/O traits. Default limits are the WebSocket wire defaults,
65,536 buffered bytes, 65,536 response bytes, 65,536 I/O attempts, 65,536 read
bytes and 8,388,608 cursor work units. Buffer and response caps must be in
`1..=67,108,864`; nested wire limits must be nonnegative and the HTTP head cap
must fit the buffer cap. I/O, read-byte and work budgets may be zero.

The phases are receiving, request policy, sending, flushing and ready.
Reception reserves bounded geometric storage before positive-capacity reads,
advances `http::Cursor` in Request mode and validates `HeadReady` through
`websocket::validate_request`. Bytes captured after the complete head fail
with sticky `Wire(Handshake)`, with `completed` equal to the entire retained
input. They cannot become an implicit second request or frame prefix.
This rule covers bytes returned by the transport with the request; it does
not prove that no further bytes were already queued outside the captured
prefix.

A positive read that completes validation returns `Again` while setting
`has_request()`. The next `step()` returns `Request`. Repeated request steps
perform no I/O until the caller accepts. `request()` exposes a borrowed,
immutable `websocket::Request`; its key, target, fields and protocol offers
remain valid through acceptance and readiness until conversion or destruction.
Before that policy boundary, `request()` returns `NotReady`.

The caller examines routing, Host, Origin, authorization and protocol offers,
then supplies an Accept value computed for the same key by an established
provider. `accept(fields, accept, protocol)` uses the existing canonical
`websocket::encode_response` and copies a complete response into an owned
snapshot before any transport write. Its effective HTTP head cap is
`min(wire.http.head_bytes,response_bytes)`. The canonical HTTP encoder checks
the complete serialized head size before allocating output, then reserves
exactly that size. Successful response size and its output vector capacity
fit that cap. Temporary field staging has its own bounded vector contract;
allocator metadata, alignment and OS page overhead are separate from these
logical byte counts.

Fields may add permitted response headers. The wire encoder rejects reserved
handshake/framing fields, invalid Accept shape, an unoffered or malformed
selected protocol and canonical syntax/limit errors. Local acceptance failures
use `Cause::Wire`, leave the server in Request, and perform no I/O. Corrected
input can be retried. Success returns the complete response length and enters
Sending. The response snapshot survives later changes to caller field,
Accept or protocol source buffers. Duplicate acceptance and acceptance in any
other phase return retryable `NotReady`.

After acceptance, each step makes at most one response write or inner flush.
Short writes advance the exact accepted prefix. Interruptions, would-block
results, invalid counts, zero writes, fatal errors and quota admission follow
the client rules. A successful final flush returns `Again` while setting
`is_ready()`, and the next step returns idempotent `Ready` without I/O.
`has_request()` and `request()` remain available while sending, flushing and
ready, provided no fatal failure has occurred.

`Stats.read_bytes` counts retained request bytes; `accepted_bytes` counts
response bytes accepted by the inner writer. Every actual read, write or flush
attempt counts toward `io_calls`. `work` snapshots request cursor work only.
Receive failures and I/O quota exhaustion retain the request prefix count;
write/flush failures and I/O quota exhaustion retain the response prefix
count. Other local admission, allocation, byte-cap, state and conversion
failures use `completed=0`. A fatal step failure is sticky, owns its buffers
until destruction and prevents further transport calls.

`into_stream()` requires Ready and constructs
`websocket_stream::new(inner,Role::Server,empty,limits)`. The server has no
accepted prefetched frame bytes: any captured request tail was rejected.
Failed stream admission leaves Ready and existing request views intact;
successful conversion retires the handshake owner and transfers the same
borrowed transport to server framing. `destroy()` releases only handshake
memory and is idempotent in every phase. Request views expire on destruction
or successful conversion. The single-owner and borrowed-transport lifetime
rules above apply to the server too.

The upgrader generates accepted 101 responses. Application-specific rejection
responses, version advertising, routing, Origin policy and authentication are
caller responsibilities. A caller can destroy the memory owner, then use its
retained transport to send an appropriate ordinary HTTP error response and
close it. This module neither authenticates peers nor computes cryptographic
values.

## Scope and verification

The generic source has no host-service dependency. Its current executable
acceptance target is Linux x86_64, using a raw generated executable without
native linking, sockets, OpenSSL or a test C shim. The GPU compiler produces
that executable; this receipt establishes native runtime behavior, not GPU
execution of the user program.

The shared
[`websocket_transport/contracts.lani`](../tests/fixtures/extended/websocket_transport/contracts.lani)
fixture compiled and executed successfully with empty stdout/stderr on
2026-10-28. Its upgrade checks exercise:

- Construction/destruction with a transport that implements no I/O traits,
  preflight failures, and no transport calls during construction.
- Request and expected-Accept snapshots after the original buffers change.
- Short writes, successful flush before reception, one-byte head reads,
  interruptions, would-block results, and at most one inner call per step.
- A finite 512-unit cursor work budget under fragmented head reception.
- Idempotent ready steps, offered subprotocol selection, preservation of
  coalesced frame bytes, failed stream-limit admission and successful retry.
- I/O quotas at zero calls, after a partial request write, before request
  flush, before the first read and after a partial response read, including
  exact `completed` and counter snapshots.
- Invalid positive/negative I/O counts, WriteZero, injected Host errors,
  malformed HTTP, bad Accept, truncated head EOF, read-byte/work exhaustion,
  and sticky failures without further transport calls.

The accepted client-only checkpoint's module SHA-256 is
`c8f4a42d44cab9fae66bbdcec92e6f6924984dc36890e06b6592147179ea5262`;
fixture SHA-256 is
`da71889b32722418e4eaeab834a5faebb882f4284d75a33bafc8febbbd4bfefe`.
The executed ELF SHA-256 is
`6d7a17ee3fd32438343cbc058df5ae6f598d0c5f5390923bdbf93d4465dc5591`.
Compile and direct-execution receipts under `target/stdlib-work/` are
`websocket-transport-contracts-compile-quota-correction.log` and
`websocket-transport-contracts-native-quota-correction.log`. This direct run
does not claim that the separate Rust registration has run.

The unchanged client fixture was then rebuilt against the current module
`cae29596…` and shared canonical HTTP source `5d495716…`, and directly executed
with exit zero and empty stdout/stderr. Current ELF SHA-256 is
`cb81123922bf79a074357d68af2240e9818e1001c99931fe07bfdbec1187dca4`;
receipts are `websocket-transport-current-compile-first.log` and
`websocket-transport-current-native-first.log` under `target/stdlib-work/`.
This is the current client regression control; the earlier executable receipt
above remains historical evidence for its original shared-library context.

The [`websocket_once` program](extended-websocket-once.md) also composes this
module over a real connected transport. Its application-specific functional,
TLS and error receipts belong to that program's guide and do not enlarge the
pure contract fixture's scope. No allocation-failure injection, GPU runtime
support, automatic ownership enforcement or formal proof is established here.

### Server execution

The separate
[`websocket_server/contracts.lani`](../tests/fixtures/extended/websocket_server/contracts.lani)
producer compiled and executed successfully as one raw Linux x86_64 process
with empty stdout/stderr on 2026-10-28. Its six top-level scenario functions
contain finite normal, fault and quota loops. They establish:

- No-trait construction/destruction and invalid-limit/state admission without
  transport calls.
- Copied request identity, an idempotent Request policy pause without writes,
  and a byte-exact 174-byte response with a caller policy header. Changing the
  original request, field, Accept and protocol buffers preserves owned data.
- One-call steps, short writes, Interrupted/WouldBlock, blocked flush, ready
  publication after flush and transactional conversion to the server framing
  role. The converted stream receives a masked client frame over the same
  borrowed transport.
- One-byte request reception within a 512-unit cursor budget, retryable
  reserved-field/Accept/protocol errors, and exact response-cap boundaries
  at 158/159 bytes, including retry with a smaller 129-byte response.
- Malformed/truncated requests, captured trailing bytes, read/work/call
  exhaustion, invalid I/O counts, WriteZero and Host failures. Terminal
  replays preserve counters and completed prefixes without additional calls.

The executed module SHA-256 is
`cae295960cc78dee04a097f2a67febc0c46ea4ca4fa1de5b4a8d191b5034b5d1`;
server fixture SHA-256 is
`44292f1171d1f68bf2925d5b907cfd75e6f6301e98da1badaf57a382994b1fc1`.
The shared canonical HTTP source SHA-256 is
`5d49571691ee7f01adc7a782842a59825276b5f012febba249b8f0702ef08591`.
The ELF SHA-256 is
`79996579684d80b3625fd2391e4ef642b759b91dd0d2e02eec059f9d5fe30902`.
Receipts under `target/stdlib-work/` are
`websocket-server-contracts-compile-first.log` and
`websocket-server-contracts-native-first.log`. The original client source
prefix is byte-for-byte unchanged. Its current shared-encoder regression run
is recorded above.

The server fixture uses deterministic borrowed Lanius transports and fixed
RFC example Accept data. It establishes no actual network server, allocation
failure injection, Rust registration execution, GPU execution or formal proof.

The separate [`websocket_echo` program](extended-websocket-echo.md) directly
passed eight finite native groups: plain 11 cases, handshake 12, frame/Close
rejection 10, CLI 14, TLS 4, credentials 3, deadline 1 and closed-readiness-stdout
I/O 1. These 56 cases
exercise an actual Linux x86_64 TCP/TLS server under the application's stated
policies. One additional integration case uses the current native
`websocket_once` client against that server. Exact application hashes,
receipts and group boundaries belong to the echo guide. The historical
46-case `websocket_once` application campaign used its earlier shared HTTP
context; only the single integration case and the pure client regression
above establish current-context acceptance here. They do not claim that the
entire earlier client application campaign was rerun.

The final server-contract and echo Rust drivers, including the added I/O
registration, built with `--no-run` in 1.43 seconds
(`target/stdlib-work/websocket-server-driver-build-io.log`). The earlier
2.18-second build predates that registration. These are build receipts only.
Actual Rust-driver runtime, allocation-failure cleanup,
GPU execution and formal-verification claims remain outside these receipts.

## Compiler inference dependency

The first connected-program compilation rejected the inferred generic
`inner.write(...)` result with `LNC0027` at its following `.is_err()` call.
The module explicitly declares its read, write and flush results as
`core::result::Result<i32,core::io::Error>`, matching the existing generic I/O
implementation style. The accepted executable uses those declarations; no
compiler code changed.

The existing
[generic byte-writer and reader reductions](library-context-inference-dependencies.md#generic-byte-writer-return)
record the analogous inference boundary and executable typed controls. This
annotation does not restrict the transport's concrete type. It is a compiler
dependency to remove, and does not prove that every similar diagnostic has
the same internal cause.
