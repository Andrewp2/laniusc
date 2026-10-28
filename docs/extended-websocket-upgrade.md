# Borrowed WebSocket client upgrade

`ext::websocket_upgrade` sends one validated opening request, flushes the
borrowed transport, and receives one valid WebSocket response head. It retains
any frame bytes delivered with that head and can transfer them into
[`ext::websocket_stream`](extended-websocket-stream.md).

This module supplies the client handshake state machine. The existing
[`ext::http::Cursor`](extended-http-cursor.md) finds the HTTP head, and
[`ext::websocket`](extended-websocket.md) validates the request, response,
extensions and selected subprotocol. There is no separate HTTP parser here.
The module performs no socket, TLS, clock, random or cryptographic operation.
The caller provides a transport that implements `core::io::Read` and
`core::io::Write` when advancing the handshake.

## API

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

## Scope and verification

This is a generic borrowed client upgrade layer. Server framing can be
initialized separately with `websocket_stream::new(..., Role::Server, ...)`
after a caller completes and validates the server's wire handshake. There is
no server-upgrade API in this module.

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

The accepted module SHA-256 is
`c8f4a42d44cab9fae66bbdcec92e6f6924984dc36890e06b6592147179ea5262`;
fixture SHA-256 is
`da71889b32722418e4eaeab834a5faebb882f4284d75a33bafc8febbbd4bfefe`.
The executed ELF SHA-256 is
`6d7a17ee3fd32438343cbc058df5ae6f598d0c5f5390923bdbf93d4465dc5591`.
Compile and direct-execution receipts under `target/stdlib-work/` are
`websocket-transport-contracts-compile-quota-correction.log` and
`websocket-transport-contracts-native-quota-correction.log`. This direct run
does not claim that the separate Rust registration has run.

The [`websocket_once` program](extended-websocket-once.md) also composes this
module over a real connected transport. Its application-specific functional,
TLS and error receipts belong to that program's guide and do not enlarge the
pure contract fixture's scope. No allocation-failure injection, GPU runtime
support, automatic ownership enforcement or formal proof is established here.

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
