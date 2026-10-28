# WebSocket wire protocol

`ext::websocket` implements HTTP/1 upgrade request/response syntax and the
extension-free frame and message protocol from
[RFC 6455](https://www.rfc-editor.org/rfc/rfc6455). It validates borrowed input,
preserves post-upgrade frame bytes, assembles fragmented messages, exposes
controls and encodes checked outgoing heads/frames. Production wire processing
is Lanius. It opens
no sockets and supplies no TLS, authentication, origin policy or random source.

The implementation composes `ext::http` and `core::base64`. Response validation
and encoding take a caller-supplied canonical expected Accept value computed
for the original request key. They perform no digest operation. The separate
[`ext::openssl_websocket`](extended-openssl-websocket.md) helper computes that
value through OpenSSL 3; the portable wire module has no crypto library
dependency. Current upgrade receipts and historical frame/request receipts
retain the separate scopes described below.
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

## HTTP upgrade response syntax

```text
Response {
    head: http::Head,
    protocol: Option<View<u8>>,
    remaining: View<u8>
}
validate_response(input: View<u8>, request: Request,
    expected_accept: View<u8>, limits: Limits) -> Result<Response, Error>
encode_response(request: Request, fields: View<http::Field>,
    accept: View<u8>, protocol: Option<View<u8>>, limits: Limits)
    -> Result<alloc::vec::Vec<u8>, Error>
```

Request must come from `validate_request` and remain unchanged with live
backing. Both response operations require a 28-byte canonical padded Base64
value representing 20 digest bytes. The caller must compute it from that
request's original encoded key using an established digest provider; use
[`openssl_websocket::accept_into`](extended-openssl-websocket.md) on the native
profile. These pure operations cannot establish that a supplied value actually
corresponds to the request key. They compare/encode the supplied bytes.

Validation requires HTTP/1.1 status 101 and exactly one Upgrade field equal to
`websocket`, compared without ASCII case. Exactly one Sec-WebSocket-Accept
field must match `expected_accept` byte for byte after HTTP field-whitespace
trimming. Every Connection field must be a valid token list, and their combined
tokens must include Upgrade without ASCII case. Duplicate Upgrade/Accept
fields, an Upgrade list/version suffix, missing or mismatching Accept and
malformed Connection tokens fail. The HTTP parser rejects Content-Length,
including zero, and Transfer-Encoding on this 101 response.

The response may omit protocol selection, even when protocols were offered.
A present Sec-WebSocket-Protocol must occur once, contain one token and match
an offered request protocol exactly, including case. Any response
Sec-WebSocket-Extensions field returns Unsupported; no extension is negotiated,
even when the request contains syntactically valid offers. Other handshake
violations return Handshake; HTTP syntax, incomplete input and cap errors keep
the existing mapped error/offset behavior.

Response borrows its HTTP head, optional protocol and `remaining` from input.
Only the head is consumed. `remaining` starts at `head.raw.len()` and preserves
all following bytes, including an entire or partial first frame. Keep input
and request backing alive through their respective borrows. Preserving these
borrowed bytes does not transfer a connected socket/TLS owner.

`encode_response` emits one HTTP/1.1 101 head with Upgrade, Connection and Accept,
plus at most one selected offered protocol and checked caller fields. Reserved
handshake/framing fields cannot be supplied through caller fields. It emits no
body, Content-Length, Transfer-Encoding or extension selection. HTTP head/line/
field caps and the offered-protocol cap apply. The encoder validates its staged
result through the same response validator. Success returns one independent
Vec owner requiring explicit `destroy()`; every error releases staging and
publishes no partial owner. New focused gates check wire and cap boundaries;
they do not establish every response-encoder allocation-failure path.

The [offline server-upgrade tool](extended-websocket-upgrade-program.md) composes
request validation, OpenSSL acceptance and response encoding. It requires EOF
on stdin and rejects trailing request bytes. A real connected client/server
still needs request/response accumulation, deadlines, nonce/mask entropy,
application policy and explicit transport/unread-byte ownership transfer.

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
slice length. Parsers allocate nothing. Request/response generation bounds field count
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
frame/decode options. This existing wire CLI provides no upgrade-response mode
or subprotocol selection option; the separate
[websocket-upgrade tool](extended-websocket-upgrade-program.md) handles that
offline request-to-response workflow.

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
WebSocket implementation is used in production. Those retained suites do not
cover the newly added provider-backed upgrade response operations.

On 2026-10-25, the reduced surface passed both
`extended_websocket_execution` groups in 12.37 seconds and all four
`extended_websocket_wire_execution` groups in 20.17 seconds. These compile
Lanius through the GPU compiler, validate emitted ELF jumps and execute on
x86_64 Linux. They cover the retained request/frame APIs, actual program
output, malformed input, limits, allocation failures and I/O cleanup.
The historical local logs are `target/stdlib-work/remove-crypto-websocket.log` and
`target/stdlib-work/remove-crypto-websocket-wire.log`.

Each runtime invocation used `timeout --kill-after=2s 100s`,
`flock target/stdlib-work/library-gpu.lock`, and `--test-threads=1` on the
freshly built driver binary. The three affected Rust drivers built together
in 86 seconds. No compiler, IR, ABI or proof source changed.

### Current upgrade execution

The new response and OpenSSL-accept surfaces have separate direct executable
receipts on Linux x86_64 CPU output from the GPU compiler. The pure contract
program uses no native crypto dependency. The helper and offline tool require
the native C ABI/CRT profile and OpenSSL 3 `libcrypto`; `libssl` is unnecessary.

| Receipt under `target/stdlib-work/` | Accepted finite scope |
| --- | --- |
| `websocket-upgrade-contracts-{compile,native}-first.log` and native trace | Compile/native exit 0: valid/OWS/single-selection responses, 34 malformed wire cases, negative-stride and packed layouts, trailing first-frame preservation, encoder round trips/reserved fields and bounds/cap errors |
| `websocket-upgrade-accept-native-first.log` | 310 cases across two layouts and overlapping input/output, comparing real OpenSSL output with an independent test-only digest oracle; 24 injected cases check provider failure, wrong/full-width returned size and error-output atomicity |
| `websocket-upgrade-app-functional-first.log` | 22 offline-tool functional cases |
| `websocket-upgrade-app-rejection-first.log` | 30 request/protocol/trailing-byte rejection cases |
| `websocket-upgrade-app-cli-first.log` | 15 argument/help cases |
| `websocket-upgrade-app-io-first.log` | Four real I/O failure cases, including closed stdout reader |

These direct groups retain separate counts without a distinct-coverage sum.
New `extended_websocket_upgrade_execution` and
`extended_websocket_upgrade_app_execution` drivers build with `--no-run` in
2.09s (`websocket-upgrade-driver-build-first.log`); that only admits the runner.
Historical request/frame tests were not rerun for this increment.

Current source hashes are `websocket e5d2253c…`, native helper `2c0baac5…` and
tool `176e8b97…`; contract producer is `9aa3dcb0…`, accept probe `3781b81a…`
and accept oracle `8f6b7b6e…`. Executable hashes are pure `939ed1f2…`, helper
`d321f898…` and tool `83a760bf…`. The
[upgrade fixtures](../tests/fixtures/extended/websocket_upgrade/README.md),
[OpenSSL helper guide](extended-openssl-websocket.md) and
[tool guide](extended-websocket-upgrade-program.md) own exact finite checks,
error/provider policy and remaining gaps.

The unchanged declaration generator and `--check` both pass with **265 pages
from 264 modules, 8,510 public declaration markers and 12,863 declaration/member
entries**. Logs are `websocket-upgrade-reference-{writer,check}-first.log`.
Only the index, existing WebSocket page and new OpenSSL-WebSocket page change.
These counts describe source discovery. The generator changes no runtime code
and the three human-maintained root files retain their original hashes.

No connected WebSocket runtime, formal proof, compiler-enforced borrow checking,
automatic owner cleanup, general digest API or GPU-device service follows from
this increment. Sensitive digest computation remains in OpenSSL.
