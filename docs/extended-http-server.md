# Bounded HTTP/1 server connections

`ext::http_server` accepts one connection from a caller-owned nonblocking TCP
listener and handles one request and one checked final response. Parsing,
framing, transfer decoding, response writing, and transport control are Lanius.
The current socket/clock host bindings execute on Linux x86-64. This optional
extended library does not make `std` depend on `ext`.

The application chooses request policy and the response. There is no routing
framework, callback, worker thread, keepalive/pipelining processor, TLS, content
decompression, upgrade, or tunnel handoff. Each final response has
`Connection: close`. Bytes following the selected request are discarded, never
interpreted as another request or forwarded.

## Staged owner

```lanius
pub fn default_options() -> Options;
pub fn accept_until(
    listener: &std::socket::Socket,
    options: Options,
    deadline: core::time::Deadline,
) -> core::result::Result<Connection,Failure>;
```

The borrowed listener must be an open nonblocking TCP socket. Its descriptor,
flags, and lifetime remain the caller's responsibility. Acceptance checks its
nonblocking flag and uses `accept4` with nonblocking and close-on-exec flags.
No listener descriptor is closed or changed. An accept/decode failure reports
any accepted-descriptor cleanup attempt and secondary close error from
`std::socket::AcceptFailure`. A constructor failure retains no new owner.

A successful Connection has one active manual owner. Do not forge or modify
its public fields, socket, Vec owners, cursor, counters, or phase, copy it as
an independent owner, close its descriptor through an alias, or use it
concurrently. `peer()` returns the decoded numeric peer; `stats()` snapshots
progress without doing I/O. The listener may accept another connection after
this constructor returns; this library does not schedule those connections.

| Operation | Required state | Result/state |
| --- | --- | --- |
| `read_head()` | newly accepted | `Some(RequestHead)`, or `None` for actual EOF before any request byte |
| `send_continue()` | head with supported expectation | explicitly writes one `100 Continue`; partial failure can resume with this same method |
| `read_request()` | head, required 100 fully sent | canonical full Request with transfer-decoded body |
| `reply(Response)` | head, full request, or rejected request | stage a complete final response, then call `finish()` |
| `finish()` | final response staged | resume its exact write, half-close, drain, and close progress |
| `close()` | owner still maintained | retire owned descriptor once, including on close error |
| `destroy()` | owner still maintained | close if needed, release all four Vec owners, return a close error if any |

A read error makes the request rejectable; the request read is not retried.
Some bytes may already have been consumed without being retained. The caller
can choose an empty 4xx/5xx with `reply`, or abort with `close`/`destroy`.
Insufficient time/work/I/O budgets are not renewed by doing so. Once a 100 is
staged, it must be completed before a final response can be staged, even if its first send failed with zero confirmed bytes. This avoids
interleaved HTTP heads. Once a final response is staged, only that response
may resume;
a second `reply` is InvalidState. An invalid syscall byte count is abort-only
because transfer progress is unknown. Closed completed `finish()` returns its
cached successful stats; a latched terminal close/clock failure remains an
error. Calls in other states return InvalidState.

`close()` preserves byte storage. `destroy()` invalidates all published views;
use it once on the active owner even after errors. No method silently drops an
owned connection on an error. A caller choosing to abort after a read failure
keeps that original Failure and separately handles its explicit cleanup result.

## Views and request authority

`RequestHead` contains the canonical `ext::http::Head`, a classified Target,
and an Expectation. The head is copied into a separate immutable owned buffer
before publication. Its method/header/target views remain valid while the
main receive buffer grows and relocates. `Request` contains a fully validated
`ext::http::Message` borrowing immutable request-wire storage and a `body`
view borrowing a separate transfer-decoded Vec. All these views remain valid
through later operation errors and descriptor closure, until `destroy()`.
Content-Encoding is metadata; gzip or other representation coding is not
decoded. Caller response views may borrow these maintained request views.

Target exposes `form` (Origin, Absolute, Authority, Asterisk), optional scheme
and authority, path, and optional query. Origin-form is classified before URI
parsing, so `//a:b/path` is a path rather than a URI authority. Query splitting
and URI parsing preserve byte spelling; no percent decoding, path cleanup,
DNS, or authority equality policy is applied. For absolute-form the target's
authority is effective, even when Host differs. Origin/asterisk use Host when
present; CONNECT exposes its authority-form target. An empty absolute path is
exposed as `/`. HTTP grammar and Host requirements come from `ext::http`.
The application must choose virtual-host and scheme policy explicitly.

The incremental cursor retains offsets only. HeadReady is followed by strict
head validation; Boundary remains a candidate until the canonical full parser
validates the exact prefix, including forbidden/Connection-nominated trailers,
and its consumed/decoded lengths agree. The final message is parsed once,
then decoded once. Saved cursors avoid reparsing all prior bytes on every
fragment. Already-read tail stays in bounded wire storage but is excluded
from Request.message and body.

## Expect and final response policy

A single case-insensitive `Expect: 100-continue` on an HTTP/1.1 request with a
nonempty fixed body or chunked framing yields Continue. `send_continue()` is
explicit; `read_request()` otherwise returns ExpectationRequired without
reading. Duplicate, combined-list, or unknown expectations yield Unsupported.
HTTP/1.0 ignores recognized 100-continue. A recognized expectation on a bodyless
request needs no 100. A fixed body known to exceed the body/raw cap fails before
any 100 is permitted. The library never automatically chooses 417 or another
rejection. The caller can send a final rejection as soon as the head is ready.

`Response` supplies status, reason bytes, header records, body, and an explicit
`core::time::SystemTime` date. Header raw/offset fields are ignored. All input
views must have valid logical bounds and live, disjoint backing from mutable
Connection internals; actual extent/layout remains the caller's contract.
Reason and header syntax are checked by the existing HTTP encoder.

Final statuses 200..599 are supported; the only interim operation is 100.
CONNECT 2xx and 101 are rejected before any response byte is sent. A 2xx requires
a full validated Request. An unknown/malformed head permits only empty 4xx/5xx;
a rejected request permits 4xx/5xx. HEAD, 204, 304, and 205 require an empty body.
HEAD/204/304 omit Content-Length; 205 emits Content-Length: 0. The application
chooses representation semantics and error mapping. An Upgrade proposal may
be handled as ordinary HTTP, but no upgrade is accepted.

The writer manages Date, Connection, Content-Length and framing. Caller fields
must exclude Date, Connection, Content-Length, Transfer-Encoding, Trailer,
Upgrade, Keep-Alive, and Proxy-Connection, case-insensitively. It stages the
whole response, canonically validates it, and only then starts transmission.
Preflight/allocation failure writes no response byte and permits another
valid `reply` if budgets remain. Preparation costs already charged are kept.
Once staged, caller response storage need not remain live after the operation
returns, even when `finish()` is needed later.

Date is a checked 29-byte IMF-fixdate produced in UTC from the supplied time,
with year 0000..9999 and checked calendar conversion. Invalid time/year returns
a Date error before staging. The library does not read or invent wall time;
the application can call `std::clock::system_now()`. The response version
matches a validated request head, or defaults to HTTP/1.1 for a malformed head.

## Deadline, quotas, and teardown

One absolute monotonic deadline covers accept, head/body processing,
application pauses, response preparation, writing, shutdown, and draining.
The library observes the clock before and after active leaf I/O, after framing,
canonical validation, decoding, and staging, and around final cleanup. A late
successful read, EOF, send, or shutdown is recorded and then returns Timeout;
late data is not published as a successful request/response result. Backward
observations return ClockReversed. EINTR/WouldBlock retry under the same
limits; neither renews the deadline. These are observations between syscalls,
not an OS real-time interruption guarantee. Cleanup close is attempted even
when the active deadline or I/O quota is exhausted.

Options has separate request/response HTTP Limits, `request_bytes`,
`response_bytes`, `drain_bytes`, `io_calls`, and `work`. All byte/count limits
are nonnegative; io_calls is positive. Default body cap is 1 MiB, each wire cap
2 MiB, new drain bytes 1 MiB, leaf I/O quota 1048576, work 268435456. Logical wire
and body caps are not exact mmap sizes: Vec geometric capacity and temporary
response line/field/encoded owners are bounded by their configured logical
limits and the existing Vec allocator policy. Allocation failure is explicit.

The active I/O quota counts every attempted fcntl flag check, accept4, socket
send/receive, poll, and shutdown leaf call. Clock observations and mandatory
close are separate. `cleanup_calls` counts actual owned-descriptor close
attempts; `cleanup_errors` counts their failures. A single close retires that
owner even on EIO/EINTR; it is never retried with a possibly reused FD number.
Caller-owned listener cleanup remains outside Connection stats. final_started
marks the first final-send attempt; response_sent counts confirmed bytes. It
does not claim that an attempted send transferred data.

Work is a charged/reserved budget, not a machine-instruction counter. Before
any flag check/accept/allocation/scan, constructor reserves 2*request_bytes
for the offset-only cursor; insufficient aggregate allowance fails immediately.
`scan_work` separately reports actual cursor work, bounded by that reservation.
There is no refund or reset. Additional charges precede operations: received
append/discard bytes; up to line_bytes+1 for a rejected-line status
classification; 4*head bytes for head copy/validation/target/expectation;
4*selected request bytes plus 4*configured head_bytes*(trailers+1) for canonical
validation; 2*encoded+2*decoded bytes for decode; 25 for a staged 100; and response
field count plus 4*encoded size+2*method length+29 for preparation. Multiplication
is performed in u64 with nonnegative i32 bounds. The head×trailer reserve covers
the existing canonical header scan per trailer; unconditional linear parsing
for arbitrary header/trailer limits is not claimed. Vec growth is amortized;
no front-shifting/reparse loop is introduced. Successful cursor scan work is
partition-invariant; syscall counts and other charges need not be.

While a final response has unsent bytes, the server alternates successful
bounded writes and discard attempts, polling both directions when needed.
This avoids waiting for a complete upload before reading an early rejection.
It then checks Shutdown::Write and drains positive-capacity receives to actual
EOF. Already-buffered tail is `buffered_discarded`; new discarded socket bytes
consume drain_bytes. At exactly the drain cap, a positive 1-byte EOF probe is
allowed: zero completes; a byte returns DrainLimit and counts that one-byte
lookahead. There is no zero-length receive substituted for EOF. Total observed
network bytes are bounded by request_bytes+drain_bytes+1. Tail/drain bytes are
not interpreted as messages. Closing without EOF, including a drain limit,
may prevent the peer from receiving the entire response; even full sends and
shutdown do not prove peer application delivery.

Failure reports cause, active stage, progress Stats, and any automatic cleanup
attempt/secondary error. cleanup_attempted describes that operation, while the
Stats cleanup counters are cumulative. retained is the current logical wire
length while receiving, then the selected request-prefix length after validation;
the physical owner can also hold the separately counted buffered tail.
Confirmed byte and successful shutdown/EOF progress
are recorded before subsequent clock failures. Primary operation failure is
preserved over cleanup failure. A clean transfer followed by close failure is
an error. After successful transfer/drain, finish always attempts close, even
if its pre-close clock check fails. No success-shaped empty request or response
stands in for an error.

The framing, authority, Expect, Date and close policy follows
[RFC 9112](https://www.rfc-editor.org/rfc/rfc9112.html) and
[RFC 9110](https://www.rfc-editor.org/rfc/rfc9110.html).

## Real local service

```text
http-serve ADDRESS [--requests N] [--timeout MS] [--report]
```

`sample_programs/library/http_serve.lani` binds a numeric IPv4/IPv6 address
(port 0 allowed), prints its actual endpoint as one checked stdout line, then
serves 1..64 sequential connections (default 1). Each connection gets a new
absolute deadline including acceptance; default 5000 ms, range 0..60000. IPv6
sets IPV6_V6ONLY explicitly. It sets BrokenPipe Ignore before allocating so
checked stdio failures return a status. Startup/report I/O is outside the
network deadline. It creates no worker or daemon.

| Request | Response |
| --- | --- |
| GET/HEAD `/health` | 200 `ok\n` / empty HEAD |
| POST `/echo` | 200 transfer-decoded binary body, application/octet-stream |
| OPTIONS any valid target | 204 with Allow |
| missing path | 404 |
| known method disallowed on a known path | 405 with Allow |
| other method, including CONNECT | 501 |
| absolute-form scheme other than http | 421 |
| unsupported expectation | 417 before body read |

Absolute http authorities are accepted without virtual-host filtering; this
small service does not proxy or forward them. It explicitly sends 100 only for
supported requests that will read a body. Grammar/head/body failures map to
400/431/413. A line limit crossed inside the request-target span (after the
first SP, before the second SP) yields RequestTargetLimit and 414. Other
overlong first lines yield RequestLineLimit and 400. Classification examines
only the prefix through the failed scan, so an eventual SP/CRLF already in a
whole input does not change the result; a smaller head cap still maps to 431.
This only chooses a rejection status, never accepts an unvalidated request. Allocation failure
attempts an empty 500 and retains process status 4.
Host I/O, deadline, and work/I/O exhaustion return 3 without disguising them as
a handled protocol rejection. Unsupported Upgrade is ignored.

Additional paired flags are --max-request, --max-response, --max-body,
--drain, --max-head, --max-line, --max-headers, --max-trailers,
--max-trailer-bytes, --max-chunks, --max-io, --max-work. Byte/count caps range
0..64 MiB; io/work range 0..2147483647, with io positive. Scalar repeats use the
last value. --max-body sets both request and response body caps; remaining
HTTP head/line/count flags set request limits only. Limits are explicit local
service policy. --report emits one checked stderr progress line per accepted
connection after closure, including failures. Exit 0 includes handled HTTP error
responses and clean empty connections; 2 arguments, 3 transport/protocol/budget
failure, 4 allocation, 5 signal setup or stdout/stderr I/O. All reached owners
are destroyed and owned descriptors are retired on these paths.

## Focused evidence

`tests/extended_http_server_execution.rs` compiles real native fixtures and
this service through the strict common machine-code checker. The native owner
fixture retains head/body views through receive-buffer growth and close,
checks absolute authority, response preflight/Date, and resumes an exact staged
response after injected send EIO. A baseline-derived clock fault immediately
after automatic close verifies primary clock failure, truthful cleanup metadata,
retained views, and the complete response already transferred. Independent h11
clients exercise IPv4/IPv6,
binary fixed/chunked messages, fragmentation, Expect/early finals, malformed
framing, pipeline discard, 1 MiB echo, exact drain EOF/overflow, late successful
syscalls, sequential accepts, and malformed arguments.

The fault oracle fails every allocation reached by its baseline exchange,
injects leaf errors/retries/quota exhaustion and close failures, and checks
real closed stdout and /dev/full. Its ledger matches each reached mmap address
and exact requested munmap length, and exactly one close attempt per owned FD.
An injected close EIO skips the kernel close; that case proves logical owner
retirement, while physical release occurs at process exit. It is not evidence
that the skipped kernel call physically closed a descriptor.
