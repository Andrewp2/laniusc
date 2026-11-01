# WebSocket frames over a borrowed stream

`ext::websocket_stream` adds bounded read accumulation and partial-write
handling to [`ext::websocket`](extended-websocket.md). It borrows a transport
through `core::io::Read` and `core::io::Write`. The existing wire connection
owns frame validation, message fragmentation, UTF-8 and close-code rules.
This adapter imports no sockets, TLS, clocks, entropy or native libraries.

The focused scripted-transport fixture passes direct raw Linux x86_64
execution through the GPU compiler. The program runs on the CPU and needs no
native linking. This receipt covers the representative transport and scenarios
listed below. User-program GPU execution, allocation-failure injection and
formal verification remain unclaimed.

## Construction and ownership

```text
new<T>(inner: &T, role: websocket::Role, prefetched: View<u8>, limits: Limits)
    -> Result<Stream<T>, Failure>
```

Construction needs no trait bound and calls no transport method. It checks
logical view bounds, adapter limits and `websocket::connection` limits, then
copies `prefetched` into independent owned storage. The source stays unchanged
on every outcome and may be released after success. An excessive prefetch
returns `BufferLimit`; a failed copy allocation returns `AllocationFailed`.
No stream owner is published on failure.

The caller retains ownership of `inner`. Keep the same transport alive and
exclusively assigned to this stream until `destroy()`. A socket or TLS stream
must be closed separately afterward. Shallow copies of `Stream` alias its
allocations and borrow; they cannot supply independent cleanup authority.
Do not mutate its fields or forge its wire state.

`borrow()` returns the active owner reference. `destroy()` releases only this
adapter's read, frame and wire-message storage, returning true once and false
afterward. It never flushes, writes, closes the transport or sends a Close
frame. Unsent output is discarded. All views into the owner expire on
destruction. `is_active()` reports whether memory ownership remains active;
a failed stream stays active until explicitly destroyed.

## Limits and progress

```text
Limits {
    wire: websocket::Limits,
    buffer_bytes: i32,
    io_calls: u64,
    read_bytes: u64,
    written_bytes: u64
}
Stats {
    io_calls: u64,
    read_bytes: u64,
    accepted_bytes: u64,
    frames_received: u64,
    frames_sent: u64
}
```

`default_limits()` uses the wire defaults, a 16,777,230-byte unread-input cap,
65,536 I/O calls and 67,108,864 bytes each for reads and writes. The input cap
must be between 14 and 67,108,864 inclusive. The wire engine checks its own
nonnegative field limits. Zero I/O/read/write budgets are valid and prevent
the corresponding work when needed.

The input cap bounds unread encoded frame bytes, including read-ahead for
following frames. Consumed prefixes are compacted before another read. Buffer
capacity grows geometrically within the cap. An exhausted I/O call quota
fails before reserving more input storage. Every destination byte is reserved
before the transport can consume input; the read scratch buffer is
at most 1,024 logical bytes. Wire message/control storage has its separate wire
limits. One outgoing encoded frame is bounded separately by the wire payload
limit plus at most 14 header bytes and the remaining write budget.

`stats()` reports value snapshots. `io_calls` counts each actual inner read,
write and flush attempt, including Interrupted and WouldBlock. `read_bytes`
counts successful positive inner reads; prefetched bytes are excluded.
`accepted_bytes` counts positive writes accepted by the inner adapter. It does
not establish that a peer received those bytes or that a nested TLS/socket
layer finished sending them. `frames_received` counts each complete frame,
including nonfinal data frames and controls. `frames_sent` advances only after
all encoded frame bytes and the subsequent inner flush complete.

The quotas bound this layer's calls and byte counts. They do not bound CPU
work inside a transport method, wire validation, allocator work or a blocking
host call. The adapter provides no deadline or poll loop; those belong to its
transport/caller.

## Receiving

```text
Stream<T>.receive() -> Result<Option<websocket::Step>, Failure>
    where T: core::io::Read
```

One call returns at most one complete frame. `Some(Step)` includes a `Pending`
event for each nonfinal data frame. Controls remain separate events even in a
fragmented message. Completed message/control payloads borrow the wire owner
until the next receive call or destruction. Keep them read-only and finish
using them before either action. Read-ahead may already contain more frames;
the next receive processes those before reading again.

`None` means an actual inner read returned WouldBlock. It does not mean EOF,
an incomplete frame, an empty message or an ignored control. Interrupted reads
retry under the same I/O quota. Incomplete frames retain all unread bytes;
positive short reads append and retry the wire engine. A complete frame is
validated by that engine once, without a second independent payload parser.

Input-buffer allocation failure leaves the logical unread bytes unchanged,
returns `Cause::AllocationFailed` and permits retry. A wire allocation failure
returns `Cause::Wire(websocket::Error::AllocationFailed)` and preserves both
input and the wire state for retry. Neither consumes a partial frame.

EOF while partial frame bytes remain returns sticky `UnexpectedEof`. EOF with
an empty input buffer delegates to `wire.finish_receive()`, retaining
`Wire(UncleanEof)` or `Wire(FragmentedEof)` for missing peer Close or unfinished
fragmentation. After a delivered peer Close, another receive returns
`Wire(Closed)` without an inner read. No EOF path fabricates a Close event.

Malformed frames retain the canonical wire error and poison the wire engine.
`is_failed()` then reports true. As allowed by that engine, the caller can
still queue one valid error Close when no earlier frame is pending. The
adapter does not automatically respond to Ping or Close.

## Sending and flushing

```text
Stream<T>.send(fin: bool, opcode: i32, payload: View<u8>, mask: [u8; 4])
    -> Result<i32, Failure>
Stream<T>.flush() -> Result<bool, Failure> where T: core::io::Write
Stream<T>.pending() -> View<u8>
```

`send` performs no transport call. It checks the exact encoded size against
the remaining write budget before `wire.send` can change outgoing fragment
or Close state. Success queues one independently owned encoded frame and
returns its encoded length. Input backing is no longer needed afterward.
Bounds, quota admission, validation and allocation errors leave the stream
usable. Wire send rules still apply after peer Close or a malformed frame.

Only one frame can be outstanding. `PendingWrite` rejects a new send while
any frame bytes or its required inner flush remain pending. `pending()` borrows
only the suffix not yet accepted by the inner transport. It can be empty while
inner flush is still pending; that still blocks another send. Keep this view
read-only and do not retain it across send, flush or destroy.

`flush()` drains partial writes, then calls `inner.flush()`. True means both
phases finished. False means WouldBlock, retaining the exact accepted-prefix
offset or inner-flush phase. Interrupted operations retry under the same
shared call quota. Retrying flush never copies or resends an accepted prefix.
An idle flush with no outstanding frame returns true without an inner call.

A successful write count must be within the offered range. Zero progress is
`Io(WriteZero)`; negative or excessive counts are `Io(InvalidCount)`. A
successful inner flush must return zero, otherwise it is `Io(InvalidCount)`.
These failures, terminal I/O errors and exhausted I/O/read/input-buffer quotas
are sticky: later send/receive/flush return the first saved failure without
more transport calls. Bytes accepted before failure remain represented in
the counters and pending suffix. Destruction is still required.

`close_sent()` becomes true only after the local Close frame's bytes and inner
flush complete. `close_received()` reports the wire engine's peer Close.
`is_closed()` requires both; encoding a Close or merely emptying the pending
suffix does not suffice. These flags establish protocol progress at this
layer, not peer acknowledgement, TLS close-notify or socket closure.

A client must supply a fresh unpredictable masking key for every frame.
The adapter uses the supplied key and cannot verify its source or freshness.
The server role sends unmasked frames; wire role rules also validate incoming
mask direction.

## Failures

`Failure { cause, stats, completed }` carries a progress snapshot. For a receive
failure, `completed` counts positive bytes read during that receive invocation.
For a flush failure it is the total prefix of the current encoded frame that
the inner accepted, including earlier flush invocations. Constructor and local
send failures report zero. Sticky replay preserves the original failure's
snapshot and count; `Inactive` after destruction reports current stats and zero.

`Cause` distinguishes `Bounds`, `InvalidLimits`, `Inactive`, `PendingWrite`,
`BufferLimit`, `ReadLimit`, `WriteLimit`, `IoLimit`, `Io(error)`, `Wire(error)`,
`AllocationFailed` and `UnexpectedEof`. `BufferLimit` during accumulation,
`ReadLimit` and `IoLimit` are terminal. `WriteLimit` is a nonterminal send
admission error: no outgoing state or queue changes, so a smaller valid frame
can still be queued. Local memory failures are likewise nonterminal.

## Acceptance status and remaining boundaries

The raw Linux x86_64 fixture
[`contracts.lani`](../tests/fixtures/extended/websocket_transport/contracts.lani)
passes with exit zero and empty output. It composes the public stream and
upgrade APIs with one deterministic Lanius transport. The accepted stream
source is `be16005d53ce0b808b0a5a807a434aac31e7399bcaf30518dbad23c64d28d55b`;
the complete fixture is
`da71889b32722418e4eaeab834a5faebb882f4284d75a33bafc8febbbd4bfefe`.
The compiler and direct execution receipts are
`target/stdlib-work/websocket-transport-contracts-compile-quota-correction.log`
and `target/stdlib-work/websocket-transport-contracts-native-quota-correction.log`.
Both logs are empty. This is direct executable acceptance, separate from any
Rust test registration or build-only check.

The stream portion exercises:

- Construction and idempotent memory-only destruction with an inner type that
  implements neither I/O trait; logical bounds, limits and inactive errors.
- Copied prefetch, coalesced read-ahead, split UTF-8 text, nonfinal Pending and
  interleaved Ping; caller input mutation does not change copied bytes.
- Both mask directions and roles, explicit peer Close, and local Close flags
  only after successful inner flush.
- Partial reads and writes, Interrupted, actual WouldBlock, queue admission,
  inner-flush WouldBlock, no accepted-prefix replay and idle flush.
- Invalid read/write/flush counts, WriteZero, Host(55), exact quota edges,
  completed counts and sticky replay without additional transport calls.
- Partial-frame, fragmented-message and missing-Close EOF distinctions;
  malformed frames and invalid UTF-8; a valid error Close after wire failure.
- Exact send-size admission before outgoing fragment/Close state changes,
  followed by a successful smaller frame.

These finite cases do not establish every possible generic transport,
allocation-failure path or ownership schedule. In particular, the retryable
read-buffer and wire allocation-failure contracts still need injected-failure
execution. Connected transport and upgrade application receipts belong to
their composition guides. No user-program GPU execution or formal ownership
proof follows from this CPU receipt.

Automatic destruction, borrow checking and formal ownership proofs remain
language/runtime work. The manual borrow and cleanup rules here are explicit
contracts that a later ownership mechanism can enforce.
