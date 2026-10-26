# WebSocket wire protocol

`ext::websocket` implements HTTP/1 upgrade-request syntax and the extension-free
frame and message protocol from [RFC 6455](https://www.rfc-editor.org/rfc/rfc6455).
It validates borrowed input, assembles fragmented messages, exposes controls,
and encodes checked outgoing frames. Production processing is Lanius. It opens
no sockets and supplies no TLS, authentication, origin policy or random source.

The implementation composes `ext::http` and `core::base64`. It does not generate
or validate a WebSocket upgrade response or a Sec-WebSocket-Accept value.
The retained APIs pass the focused native execution groups described below.
[The protocol registry](https://www.iana.org/assignments/websocket/) supplies the
registered close codes through 1014. RFC 7936 changes subprotocol registration
procedures, RFC 8307 permits `.well-known` WebSocket URI paths, and RFC 8441 adds
an HTTP/2 bootstrap. The first two require no different wire processing here;
HTTP/2 bootstrap and all negotiated extensions, including per-message deflate,
are outside this HTTP/1 profile. Extension offers in a request are checked for
syntax; the caller handles any negotiation outside this module.

## HTTP upgrade request syntax

All byte arguments use `core::slice::View<u8>` and preserve source bytes.

| API | Contract |
| --- | --- |
| `default_limits()` | Bounded HTTP heads, 16 MiB frame and message payloads, 65,536 data fragments per message, and 32 offered subprotocols |
| `validate_request(input, limits)` | Borrowed `Request` with checked GET/HTTP/1.1 head, key and offered protocol count; following frame bytes remain outside `request.head.raw` |
| `protocol_at(request, index)`, `offers(request, protocol)` | Borrow offered tokens in preference order; protocol agreement is case-sensitive |
| `key_into(nonce, destination)` | Encode exactly 16 caller-supplied nonce bytes as 24 canonical Base64 bytes |
| `encode_request(start_line, fields, nonce, protocols, limits)` | Owned checked request; caller supplies Host and optional Origin/authentication fields; `protocols` is empty or a unique comma-separated token list |

Header names are case-insensitive. Key/version singleton duplicates and
Sec-WebSocket-Accept in a request are rejected. Protocol offers can span several
fields, but every token must be unique. Request Connection/Upgrade lists are
checked, including repeated field lines. The key must decode to exactly 16
bytes with canonical padding and unused bits. Version is exactly `13`. Nonzero request content and
transfer coding are rejected; a zero Content-Length is permitted. Origin may
occur once; the caller decides whether its value is acceptable.

The request encoder reserves Upgrade, Connection, the listed Sec-WebSocket
handshake fields and message framing to itself. Extra fields cannot supply
those names. It emits Content-Length zero through `ext::http`. Returned
vectors have one owner and require `destroy()`.
Every validation/allocation failure releases temporary header and wire owners.

A nonce must be freshly generated from an unpredictable source for each actual
connection. `key_into` encodes supplied bytes and cannot establish how they were
chosen. The same applies to the per-frame masking keys described below. Fixed
keys in examples/tests are reproducible test data, not a random-source fallback.

Request and Frame values passed back to helpers must come from their validators
or parser and remain unchanged. Connection fields are maintained by its methods;
do not forge or mutate them. Request records borrow their heads. Keep their
sources alive and unchanged through protocol lookup.
The HTTP parser checks Host/target syntax but performs no routing or authority
policy; callers implementing a real endpoint must supply that context. These
helpers do not authorize an Origin or authenticate a peer.

## Frames and connection state

`Role::Client` means the local endpoint is a client. It receives unmasked frames
and sends masked frames. `Role::Server` receives masked frames and sends
unmasked frames. A mismatched mask direction fails even when the mask is zero.
Only opcodes 0, 1, 2, 8, 9 and 10 are accepted. Reserved bits must be zero.
Lengths must use their shortest encoding. The 64-bit length form must have its
high bit clear; valid protocol lengths exceeding the configured signed 32-bit
storage limit return `Limit`, without narrowing or allocating.

| API | Contract |
| --- | --- |
| `parse_frame(input, receiver_role, limits)` | One complete borrowed `Frame`; `consumed` ends exactly at its payload, leaving subsequent frames untouched |
| `decode_frame_into(frame, destination)` | Copy/unmask its payload; bounds/capacity errors leave destination unchanged |
| `connection(role, limits)` | Empty connection with two unallocated vector owners |
| `receive(input)` | Process one complete frame and return `Step { consumed, event, payload, close_code }` |
| `send(fin, opcode, payload, mask_key)` | Validate outgoing message state and return one owned frame; commit state only after successful encoding |
| `finish_receive()` | At explicit EOF, require a received Close; distinguish an unfinished fragmented message from an otherwise unclean EOF |
| `is_failed()`, `close_received()`, `close_sent()`, `is_closed()` | Inspect protocol state; local Close reflects a successfully encoded frame, not completed transport I/O |
| `destroy()` | Release both connection buffers; borrowed event data becomes invalid |

`receive` returns Pending for a non-final data fragment, Text/Binary with the
entire assembled message for its final fragment, and Ping/Pong/Close controls
immediately. Control payloads use a separate buffer and cannot overwrite an
unfinished data message. UTF-8 validation carries incomplete code points across
fragments, rejects impossible prefixes immediately, and requires a complete
scalar sequence at the final text fragment. Binary payloads permit every byte.
A continuation requires an active message; a new data opcode cannot interrupt
one. All data fragments, including empty ones, count toward the fragment limit.
Control frames must be final and have at most 125 payload bytes.

The application must answer Ping with a Pong containing the same payload,
unless it has received Close. An unsolicited Pong needs no response. Receiving
Close exposes its original payload so the caller can encode the corresponding
Close response with `send(true, 8, step.payload, key)`. A Ping arriving after a
local Close can still be answered by Pong until peer Close arrives. Sending
Close prevents further data sends; in-flight incoming data remains readable
until peer Close. After receiving Close, no new outgoing message can begin;
an already started outgoing message can finish before the local Close reply.
Further input after peer Close returns Closed. The caller handles transport
closure and delivery of all encoded replies.

Close may have no payload (`close_code == -1`), or a two-byte network-order code
followed by a UTF-8 reason. One-byte payloads, reserved/unassigned wire codes,
and malformed reasons fail. Codes 1000–1014 except 1004/1005/1006 are supported,
as are application/private codes 3000–4999. Codes 1015 and 1016–2999 are not
accepted. A Close control may abort an unfinished incoming message; it does not
emit that partial data as a completed message. A received Close alone does not
prove both directions completed the closing handshake or that a transport
closed cleanly.

## Limits, atomicity and ownership

All limits and logical ranges must be nonnegative and nonoverflowing. Physical
backing must cover each declared range; a view cannot discover a forged physical
slice length. Parsers allocate nothing. Request generation bounds field count
and line sizes before staging; HTTP head budgets also apply. Protocol uniqueness
checking scans the bounded offered token set rather than allocating a registry
(worst case O(P²H) for P protocols and H head bytes; the default P cap is 32).
Frame processing is linear in the complete frame bytes; message buffers grow
geometrically up to `message_bytes`. There is no unbounded scan for missing
payload or a closing frame inside `receive`: it handles one supplied frame.

`Incomplete` consumes no input and preserves connection state; append bytes and
retry the same frame. Allocation failure likewise preserves the previous
message/control contents, capacity and fragmentation/close state. Bounds errors
leave the connection usable. Invalid peer protocol, UTF-8, close payload or
resource limits mark it Failed. It cannot continue receiving or send data, but may encode one
checked Close error reply (for example 1002, 1007 or 1009) before destruction.
Local `send` errors preserve outgoing state and return no partial wire owner.

Event payloads borrow internal connection storage and must be treated as
read-only. They expire on the next `receive` or destruction. Incoming wire
bytes must be disjoint from both internal buffers, including earlier event
views. `decode_frame_into` requires a validated unchanged Frame and disjoint
source/destination. `key_into` snapshots its source before writing and permits
overlap; destination range/capacity errors are atomic.

Connection and vector copies alias their allocations; keep one active owner and
destroy it once. After destroying a connection, call no other methods except
repeated destruction. Outgoing wire vectors belong to the caller. Encoding can use
an event payload from the same connection because it stages independent wire
storage before changing sender state. No automatic destructor or borrow checker
is claimed.

Errors distinguish Bounds, Incomplete, Protocol, InvalidUtf8, InvalidClose,
Limit, Unsupported, Handshake, Capacity, AllocationFailed, Closed, Failed,
UncleanEof and FragmentedEof. Receiving frame offsets count bytes from that frame;
UTF-8/close offsets include its wire header. Sending validation offsets refer to
the supplied payload. HTTP handshake parse errors retain HTTP head offsets;
Handshake/Unsupported errors carry no byte offset.

## Offline consumer

Compile the complete Lanius program with the optional source root:

```sh
laniusc --stdlib-root stdlib --source-root extended \
  sample_programs/library/websocket_wire.lani -o websocket-wire
./websocket-wire --request request.http
./websocket-wire client-frames.bin
./websocket-wire --client --decode --message 0 server-frames.bin > body.bin
```

Input comes from stdin with no path or with `-`. Frame mode defaults to receiving
client traffic as a server; `--client` reads server traffic. Reports contain one
line per frame, with event codes 0 Pending, 1 Text, 2 Binary, 8 Close, 9 Ping and
10 Pong, plus payload byte count, cumulative consumed bytes and close code.
`--decode` stages exactly the selected complete data message; controls do not
count toward `--message N`. A missing selected message is an error.

Frame mode normally requires a received Close at EOF. `--allow-open` explicitly
permits an open or fragmented message capture made of complete frames; it never
accepts a truncated frame. Trailing bytes after a Close are rejected. `--request`
reports the parsed request head's protocol count and consumed/remaining boundary;
later captured frame bytes remain outside that head. It cannot be combined with
frame/decode options. The CLI provides no upgrade-response mode or subprotocol
selection option.

The CLI reads and stages its whole result before stdout. Malformed/incomplete
input, protocol errors and resource limits produce no stdout. A write failure
may expose a prefix already accepted by the OS. Exit codes are 0 success/help,
2 arguments/protocol/limits, 3 I/O/open/close, and 4 allocation failure. Interrupted
reads are retried; opened files and all argument/input/output/connection owners
are released on every exit. Paths may contain non-UTF-8 bytes but not NUL.

`--max-input N` and `--max-output N` default to 18,874,368 bytes and accept
0–67,108,864. Library message/frame limits remain 16 MiB. Frame mode additionally
caps total frames at 65,536, including controls and empty fragments. Arguments
are bounded to 32 and 65,536 total bytes. The program supplies no mask-key or
nonce generation and never opens a socket.

## Focused verification status

The retained `tests/extended_websocket_execution.rs` coverage concerns request
parsing/encoding, Base64 nonce encoding, nonzero ranges, frame/message state,
fragments/control interleaving, split UTF-8, close handling and malformed
lengths/flags. Allocation controls cover retryable sender/receiver state and
release of request/frame staging owners.

`tests/extended_websocket_wire_execution.rs` retains the framing and request
CLI workflows, input/output limits and ownership/I/O controls. Python's
`websockets` parser is a test oracle for captured/generated frames; no host
WebSocket implementation is used in production. Tests for removed upgrade
response behavior are removed with those APIs.

On 2026-10-25, the reduced surface passed both
`extended_websocket_execution` groups in 12.37 seconds and all four
`extended_websocket_wire_execution` groups in 20.17 seconds. These compile
Lanius through the GPU compiler, validate emitted ELF jumps and execute on
x86_64 Linux. They cover the retained request/frame APIs, actual program
output, malformed input, limits, allocation failures and I/O cleanup.
The local logs are `target/stdlib-work/remove-crypto-websocket.log` and
`target/stdlib-work/remove-crypto-websocket-wire.log`.

Each runtime invocation used `timeout --kill-after=2s 100s`,
`flock target/stdlib-work/library-gpu.lock`, and `--test-threads=1` on the
freshly built driver binary. The three affected Rust drivers built together
in 86 seconds. No compiler, IR, ABI or proof source changed.
