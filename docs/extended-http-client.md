# Connected HTTP/1 client

`ext::http_client` performs one bounded cleartext HTTP/1.1 exchange with an
explicit numeric IPv4/IPv6 endpoint. The Host authority is a separate byte
value, which supports virtual hosting without an implicit resolver. It uses
`ext::http` and the existing `std::socket`/clock bindings. Production parsing,
writing, framing, transport control, and body decoding are Lanius. Existing
native host bindings currently execute on Linux x86-64.

This optional extended library does not add a `std` dependency on `ext`.
It does not implement TLS, automatic redirects, proxying, connection pooling,
pipelining, upgrades, CONNECT tunnels, authentication/challenge or cookie
management, content decompression, or request replay. A valid 3xx/4xx/5xx
response is a successful transport result. Callers inspect its status.

## Request and exchange

```lanius
pub struct Request {
    method: core::slice::View<u8>,
    target: core::slice::View<u8>,
    authority: core::slice::View<u8>,
    headers: core::slice::View<ext::http::Field>,
    body: core::slice::View<u8>,
}
pub fn default_options() -> Options;
pub fn exchange_until(
    endpoint: core::net::SocketAddr,
    request: Request,
    options: Options,
    deadline: core::time::Deadline,
) -> core::result::Result<Response,Failure>;
```

All request views borrow caller storage during `prepare_until` or `begin_until`.
On successful preparation, every required byte has been copied: callers may
release method, target, authority, header names/values, body, and their view
containers before starting or driving the exchange. `exchange_until` performs
that same preparation internally.
Their backing may use valid nonzero starts and physical strides; logical
bounds are checked, while actual storage extent/layout/lifetime remain the
caller’s contract. Bodies preserve all byte values. Header names/values are
checked by the existing writer, including CR/LF injection rejection.

The client stages one checked HTTP/1.1 request with the existing
`ext::http::encode_request` writer. It supplies exactly one Host from
`authority`, `Connection: close`, and the writer’s Content-Length. Request
framing is fixed length, including zero for an empty body. Caller header
records use only `name` and `value`; their raw/offset fields are ignored.
Caller fields must exclude Host, Connection, Content-Length, Transfer-Encoding,
Expect, Upgrade, TE, Trailer, and names beginning with `Proxy-` (ASCII case
insensitive). An explicit Authorization header is ordinary caller-supplied
data; this does not implement authentication policy.

Targets are origin-form path/query bytes or `*` with OPTIONS. The existing
wire parser checks percent syntax and Host authority syntax. Absolute-form
proxy targets and CONNECT are unsupported. TRACE with nonempty content is
rejected. Other method/content semantics remain the caller’s responsibility;
the client does not silently change GET to POST when a body is supplied.
Endpoint routing is independent of the Host authority and its optional port.
No authority equality, URI normalization, DNS, NSS, `getaddrinfo`, search path,
or `/etc/resolv.conf` policy is applied.

## Resumable preparation and exchange

```lanius
pub struct Readiness {
    readable: bool, writable: bool, hangup: bool, error: bool,
}
pub struct Interest { readable: bool, writable: bool, immediate: bool }
pub enum Status { Active, Complete, Failed, Aborted }

pub fn prepare_until(request: Request, options: Options, deadline: Deadline)
    -> Result<Prepared,Failure>;
pub fn begin_until(endpoint: SocketAddr, request: Request,
    options: Options, deadline: Deadline) -> Result<Exchange,Failure>;

pub impl Prepared {
    pub fn borrow(&self) -> &Prepared;
    pub fn stats(&self) -> Stats;
    pub fn is_active(&self) -> bool;
    pub fn destroy(&self) -> bool;
    pub fn into_protocol(&self) -> Result<Protocol,Failure>;
    pub fn begin(&self, endpoint: SocketAddr) -> Result<Exchange,Failure>;
}
pub impl Exchange {
    pub fn borrow(&self) -> &Exchange;
    pub fn interest(&self) -> Interest;
    pub fn raw_handle(&self) -> Option<i32>;
    pub fn stats(&self) -> Stats;
    pub fn status(&self) -> Status;
    pub fn last_failure(&self) -> Option<Failure>;
    pub fn before_wait(&self) -> Result<bool,Failure>;
    pub fn step(&self, ready: Readiness) -> Result<Option<Response>,Failure>;
    pub fn abort(&self) -> Result<bool,Failure>;
}
```

The abbreviated types above are `core::net::SocketAddr`,
`core::time::Deadline`, `core::option::Option`, and `core::result::Result`.
Preparation runs the same checked request writer and copies the method without
opening a socket. This lets a caller validate and stage several jobs before
starting network activity. Preparation failures release their temporary owners.
An active `Prepared` must be consumed with `begin` or `into_protocol`, or
released with `destroy`.
`destroy` returns true once, then false. `begin` disarms the actual Prepared
before opening a nonblocking socket, and preserves its absolute deadline and
cumulative work/I/O accounting. It opens only; connection attempts start in
`step`. Repeated `begin` on a consumed/destroyed Prepared reports `Inactive`.
`begin_until` is preparation followed by `begin`.

`step` never polls, sleeps, or retries a failed network operation internally.
It returns `Ok(None)` while active, one owned `Response` on completion, or a
`Failure`. A step performs at most one active network leaf: connect, socket
error query, peer query, receive, send, or write shutdown. Send and receive
attempts use at most 1024 bytes. Other turns advance at most one cursor event
(including canonical validation when that event selects a boundary),
decode/materialize the final response and all bounded informational heads,
close, or publish.
Mandatory error cleanup may also close the socket in a failing turn. Cursor
and whole-message parsing use the existing byte/header/trailer/work caps;
canonical validation and decoding are bounded actions, not preemptible CPU
slices or a hard wall-clock fairness guarantee.

Drive `interest().immediate` work immediately with all-false Readiness. When it
is false, call `before_wait` before participating in a single or shared poll.
It checks the deadline and charges one I/O allowance, returning `Ok(true)`.
If immediate work remains, it returns `Ok(false)` without a poll charge; step
that work first. This charge is an abstract per-exchange poll participation:
one shared poll may charge several participating exchanges, and interrupted
or timed-out attempts still count. No poll occurs inside `before_wait`.
Pass the resulting readiness flags to the next step, then discard that hint.
A timeout or interruption uses all-false readiness; the next step checks the
original deadline again. Readiness belongs to that current socket/slot only:
never reuse an old result for a new Exchange that happens to reuse its fd.

`raw_handle` is an optional borrowed descriptor for a poller. Do not close,
read/write, change flags, or otherwise operate on it independently. Readiness
is advisory: after EINPROGRESS, an exchange waits for writable/error/hangup
readiness before querying SO_ERROR, and then proves connection with a separate
peer query. SO_ERROR zero alone never authorizes sending. A still-unconnected
peer query returns to waiting. Calls with no readiness cannot bypass the
pending-connect gate. Hangup is never a substitute for an actual receive EOF.
These checks follow Linux [connect](https://man7.org/linux/man-pages/man2/connect.2.html)
and [getpeername](https://man7.org/linux/man-pages/man2/getpeername.2.html).

While active, `stats` is cumulative and `last_failure` is empty. Completion
transfers the response once, closes the socket and disarms all Exchange owners;
`status` becomes Complete and `raw_handle` is empty. Failure closes/releases
once and caches its original Failure; repeated step/before_wait calls return
that same failure without I/O, allocation, or renewed budgets. `abort` releases
an active Exchange regardless of exhausted quotas/deadline, returns true once,
and marks it Aborted. A close error is returned as primary `Cause::Io` at Close
and retained in `last_failure`; cleanup is still complete and not retried.
`abort` on any terminal state returns false. Step/before_wait on Complete or
Aborted report a local `Cause::Inactive` without touching transferred owners.
Terminal interest has all fields false. Copies of Prepared/Exchange are only
borrowed aliases: keep one actual manual owner, and do not mutate their fields.

`exchange_until` is the canonical synchronous driver over these same APIs.
It steps immediate work, charges poll participation, performs one socket poll,
and feeds that readiness back into the engine. It shares every request,
framing, response-validation, ownership and error path with direct callers;
there is no second HTTP parser or transport implementation.

## Shared transport-free Protocol

The concrete `Protocol` owns the staged request, copied method, growing receive
wire, framing cursor, informational spans/heads and decoded body. Plain
Exchange and TLS drivers drive this same owner. Request encoding, incremental
framing, canonical validation, decoding and Response construction each have
one implementation. This module imports no OpenSSL code; plaintext HTTP needs
no `libssl` or `libcrypto` dependency.

```lanius
pub enum Trailing { Discard, Reject }
pub enum Need { Local, Transfer, StopUpload, FinishTransport, Complete(Response) }
pub impl Protocol {
    pub fn borrow(&self) -> &Protocol;
    pub fn stats(&self) -> Stats;
    pub fn remaining(&self) -> core::time::Duration;
    pub fn status(&self) -> Status;
    pub fn last_failure(&self) -> Option<Failure>;
    pub fn check(&self) -> Result<bool,Failure>;
    pub fn before_io(&self, stage: Stage) -> Result<bool,Failure>;
    pub fn before_wait(&self) -> Result<bool,Failure>;
    pub fn failure(&self, cause: Cause) -> Failure;
    pub fn advance(&self) -> Result<Need,Failure>;
    pub fn receive_limit(&self) -> Result<i32,Failure>;
    pub fn feed(&self, bytes: View<u8>) -> Result<bool,Failure>;
    pub fn feed_eof(&self) -> Result<bool,Failure>;
    pub fn start_send(&self) -> Result<Option<View<u8>>,Failure>;
    pub fn pending_send_bytes(&self) -> i32;
    pub fn commit_send(&self, count: i32) -> Result<bool,Failure>;
    pub fn cancel_send(&self) -> Result<bool,Failure>;
    pub fn acknowledge_stop(&self) -> Result<bool,Failure>;
    pub fn record_write_shutdown(&self) -> Result<bool,Failure>;
    pub fn transport_finished(&self) -> Result<bool,Failure>;
    pub fn abort(&self) -> bool;
}
```

Here `View` abbreviates `core::slice::View`; the other abbreviations are above.
`Prepared.into_protocol` disarms the actual Prepared before driver work and
transfers its unchanged deadline, accounting and buffer owners. The method
opens no socket and reads no clock. The existing plain `Prepared.begin` uses
that transfer internally, then opens its socket. Copies of a Protocol remain
borrowed aliases with one cleanup authority.

`advance` performs a bounded local action and returns Local when more local
work remains. Transfer permits external I/O; `receive_limit` and `start_send`
require that state. A driver must drain new framing events before starting a
new upload chunk. `receive_limit` returns a positive count at most 1024,
including the separate one-byte Close EOF probe. `feed` accepts a positive
confirmed receive prefix and copies it into owned wire storage. It records
received bytes before its post-operation deadline/clock observation, including
a limit-overflow probe byte. `feed_eof` is for an actual transport EOF from a
positive-capacity read. Both resume local scanning. The driver validates native
counts and uses `check` after operations that return an error without bytes.

`start_send` reserves at most 1024 immutable staged request bytes. Only one
reservation may exist. `commit_send` confirms a positive prefix once and clears
that reservation, recording progress before its later clock observation.
A native retry retains the reservation; it must not call start_send again.
`cancel_send` clears a reservation only after the driver proves that no native
request remains in flight. An ordinary socket EAGAIN/EINTR supplies that proof;
a TLS WANT result does not. These are manual driver contracts, with no borrowed
buffer reallocation or mutation permitted while an operation refers to it.

StopUpload reports an observed final head immediately. New reservations are
then suppressed, while an operation reserved before that head may still commit
its confirmed bytes. `acknowledge_stop` resumes framing after the driver adopts
that policy; it does not set `write_shutdown` or perform I/O. Only an actual
successful socket write shutdown or confirmed local TLS alert justifies
`record_write_shutdown`. Transport-specific TLS retry, alert and version policy
belongs to the TLS driver; Protocol never maps a TLS WANT to a cancelled write
or performs a raw TCP shutdown for TLS.

FinishTransport follows shared canonical validation and decoding. The driver
finishes and closes its transport before calling `transport_finished`, with
no pending send reservation. A later advance constructs and transfers the
sole Complete(Response), disarming Protocol. Repeating advance then returns
Inactive; it never replays that Response. A final HTTP boundary or EOF alone
is insufficient to acknowledge transport cleanup.

`before_io` checks the deadline and charges one active attempt at its supplied
HTTP stage. Protocol's `before_wait` always charges one poll participation;
the driver must first establish that it will actually participate. `remaining`
returns the deadline remainder at the last checked monotonic instant, without
a new clock read or budget charge. Use it after a successful check/before_wait
for that poll's timeout; it does not refresh or extend the deadline. The plain
Exchange wrapper retains its immediate-work `Ok(false)` behavior. Native/TLS
attempt limits can add a separate transport budget, and native failures retain
their structured transport diagnostics rather than being cast to integers.
Mandatory cleanup stays outside exhausted active allowances.

Protocol failures are sticky and retain HTTP buffers for explicit cleanup.
`failure(cause)` records the first failure with shared progress/stage; later
operations return that original failure. `abort` releases HTTP buffers once,
performs no transport operation and preserves a saved failure. It returns false
after release or Complete transfer. Drivers close/disarm their actual socket,
TLS and Protocol owners before returning a terminal error to a batch scheduler.
Direct Protocol users have that same explicit cleanup obligation.

## Owned response and views

`Response` owns immutable response-wire storage, a separate exact copy of the
original request method, the decoded transfer body, and a bounded vector of
informational Head descriptors. `message()` returns the validated final
`ext::http::Message`; `as_view()` exposes only that final encoded message,
excluding informational heads and discarded trailing data. `body()` exposes
the transfer-decoded bytes. `informational()` exposes ordered validated 1xx
heads. Header spelling/order and separate trailers follow `ext::http`.
Content-Encoding is preserved metadata: gzip or other representation content
is not decompressed by `body()`.

The exact method copy is necessary: the wire parser’s `Head.method` borrows
its supplied request-method view. Final and informational heads therefore
borrow the response’s owned method allocation, and remain valid after caller
request/method storage is destroyed. Retained views are created only after
method and wire allocations are final. Later decoding/descriptor allocation
does not relocate either backing owner.

Keep one active manual owner. Copies of a Response are borrowed descriptors,
not independent owners. Do not mutate its public owner fields or bytes, and
do not independently destroy a copied descriptor. Use all response/message/
header/trailer/body views before `response.destroy()`. That method releases
the response’s owners; it never frees caller request storage.

An ordinary application handles `result.is_err()` and its typed Failure,
then inspects `response.message().head.status`, uses `response.body()`, and
finally calls `response.destroy()`. A successful final message is available
without retaining the request’s large staging buffer.

## Incremental framing and response association

The client uses the shared allocation-free `ext::http` cursor. The cursor
stores offsets and scalar state, not input views, so the cumulative receive
buffer can grow and relocate. A HeadReady event is drained before another
send. A Boundary is only a framing candidate; every selected response is
checked by the canonical whole-message parser before it is published.

Saved scan offsets inspect new bytes instead of reparsing every previous
head/chunk on each receive. Chunk size/extension grammar comes from the
existing HTTP helper. The final candidate prefix is parsed canonically once;
its exact consumed and decoded lengths must match the cursor. Trailer syntax
and the canonical forbidden/Connection-nominated trailer policy remain in
force. The incremental scan cost is linear in raw bytes and independent of
valid input partitioning. The existing canonical trailer check can scan the
bounded header section per trailer, so total parsing is not claimed to be
unconditionally linear for arbitrary configured header/trailer counts.

The exchange handles zero or more informational responses, preserving their
heads under cumulative count/byte/work caps. It accepts unsolicited 100 and
103, and other 1xx statuses except 101. A 101 is UnsupportedUpgrade, not an
informational response to skip. The client does not generate or accept an
Expect request header or implement a 100-continue handshake. Informational
responses do not renew deadlines or budgets.

Empty, fixed, and chunked final responses finish at their exact framing
boundary without waiting for connection EOF. Responses without framing finish
only after a positive-capacity receive actually returns zero. A timeout,
read error, hangup readiness flag, or zero-length buffer is never substituted
for EOF. HTTP/1.0 response compatibility and the strict Content-Length/TE
recipient policy are inherited from the wire parser.

`Options.trailing` selects the treatment of already-read bytes beyond the final
boundary. Its default Discard counts and removes them; Reject instead fails
with `Cause::Http(Error::Malformed(boundary.consumed))`, relative to the current
message. Neither policy interprets them as a second response, caches or
forwards them, or includes them in a published `as_view()`/`body()`. The client closes its dedicated connection
without waiting for proof that unseen trailing bytes do not exist. The
receive buffer keeps connection offsets through informational messages;
it does not repeatedly move a remaining tail to its front.

The framing/association policy follows [RFC 9112 sections 6–7](https://www.rfc-editor.org/rfc/rfc9112.html#section-6),
[connection failure and close handling](https://www.rfc-editor.org/rfc/rfc9112.html#section-9.5),
and [RFC 9110 informational responses](https://www.rfc-editor.org/rfc/rfc9110.html#section-15.2).
The mature h11 readers’ saved line-search positions and remaining-byte state
were consulted; h11 and Python `http.client` are independent test oracles.

## Upload progress and early final responses

The nonblocking engine processes cursor events before sending, alternates
bounded receive/send attempts while upload remains permitted, and enables a
fresh receive probe after each successful send. It requests both readable and
writable directions when neither operation can progress. Two WouldBlock
results settle on non-immediate interest rather than spinning between phases. This permits
an early final response to stop an upload instead of blocking in a send-all
operation while the server waits for the client to read its rejection.

If a final HeadReady arrives before all staged request bytes have been sent,
`upload_stopped` becomes true and no new chunk is reserved. The plain client
has no native write left in flight across calls, so it sends no later request
bytes. It
performs one checked `Shutdown::Write` in a separate subsequent step, then
continues receiving the final
response. This sends request-side EOF to a peer waiting on the abandoned
body. A successful shutdown is recorded before the next clock observation.
Shutdown failure is terminal. Normally completed uploads are not half-closed
automatically. No request is replayed.

This policy does not promise recovery of every early error response. A send
or receive failure before the final head is observed may terminate the
exchange. `request_sent` records confirmed send progress even when a later
clock or transport operation fails; it does not establish server processing,
TCP acknowledgment, or safe retry of a non-idempotent request.

## One deadline and explicit quotas

The caller supplies one absolute monotonic deadline. The client observes it
through preparation, network operations, cursor processing, canonical parse,
decode, close, and final publication. Positive final receives, successful EOF,
and successful shutdown/close have post-operation checks. Observed clock
reversal is an error. These checks occur between bounded operations; they
are not a realtime OS scheduling guarantee.

| Option | Default | Meaning |
| --- | ---: | --- |
| `trailing` | `Trailing::Discard` | Discard/count or reject already-received bytes after the final boundary |
| `wire` | `ext::http::default_limits()` | Head/line/header, decoded body, trailer, and chunk caps |
| `request_bytes` | 17825792 | Complete staged request bytes |
| `response_bytes` | 18874368 | Retained cumulative raw response bytes, including informational heads and chunk overhead |
| `interim_count` | 8 | Informational heads before the final response |
| `interim_bytes` | 65536 | Aggregate informational head bytes |
| `io_calls` | 1048576 | Active network leaf attempts across the whole exchange |
| `work` | 268435456 | Cumulative conservative scan/parse/copy allowance |

Size/count limits may be zero but not negative; `io_calls` must be positive.
Default wire limits include a 64 KiB head, 8 KiB line, 100 fields, 16 MiB
decoded body, 16 KiB trailers, 100 trailer fields, and 65536 nonzero chunks.
Raw and decoded limits are independent: chunk extensions/framing can consume
much more raw storage than decoded body bytes. Retained vectors grow
geometrically; quotas bound logical payloads and configured work, not exact
allocator capacity, peak temporary mappings, or process RSS.

The I/O quota counts each socket creation, connect, poll participation, SO_ERROR
check, peer check, send, receive, and write shutdown. Repeated EINTR/WouldBlock
attempts still count. The client uses single-attempt socket operations and
its own absolute-deadline poll loop; helper-internal retries cannot reset or
hide this budget. Mandatory cleanup close is attempted once even when the
quota or deadline is exhausted, and is outside the active I/O quota. Clock
reads and CLI file/stdio operations are separate from this networking quota.

Work is charged for header-record admission before traversal, reserved checked
request writing/method copying, monotone cursor work deltas, canonical parsing,
body decoding, and retained informational head materialization. Final parse
reservation includes the configured header/trailer product. Budgets never
reset on another receive or 1xx head. The reservation is deliberately
conservative and can reject a small message under a budget smaller than the
configured parser allowance. Work units are not CPU instructions or a promise
of partition-invariant cost for malformed streams observed at different
prefixes. Completed valid messages have partition-invariant scan accounting.

When an incomplete self-delimited message exhausts raw capacity, it fails
without a zero-capacity receive. A close-delimited message can be exactly at
its raw or decoded-body cap and still need EOF. The client then uses a
separate one-byte positive-capacity EOF probe. Zero completes that response;
a byte fails the raw/body limit and is included in confirmed receive progress.
Thus at most one overflow lookahead byte is consumed beyond an already-known
Close cap, and that byte is never retained or published. An initial head/body
read can also observe bytes before the head’s body policy is known, bounded
by the 1024-byte socket read. Tests cover EOF, overflow, I/O error, and late
EOF in the exact-cap probe path.

## Failure and cleanup contract

`Failure` reports typed `cause`, `stage`, current response `message_offset`,
`Stats`, and an optional secondary close error. Causes distinguish invalid
options, unsupported requests/managed headers/upgrades, allocation, timeout,
clock/socket/wire errors, request/response/body/interim/I/O/work limits, and
cursor/canonical boundary mismatch, and local use after completion/abort
(`Inactive`). HTTP parser offsets remain relative to
the selected message; add `message_offset` to locate them in the observed
connection byte stream. Stages distinguish preparation, opening, connecting,
sending, receiving, shutdown, validation, decoding, close, and publication.

`Stats` contains request length and confirmed sent bytes, received bytes
(including discarded data and overflow lookahead), informational count,
discarded trailing bytes, active I/O calls, work, and upload/shutdown flags.
Confirmed successful side effects stay recorded if a later deadline check
fails. Terminal errors are established before close: the original protocol,
limit, or timeout error stays primary if close also fails. Close failure after
an otherwise valid response discards the response. Every socket owner is
invalidated before its one direct close attempt; close is never retried.
A plain Exchange returns no response view on error and releases all of its
heap owners. Direct Protocol failures retain their explicit owner until abort,
as described above.
`Failure` itself contains only diagnostic metadata, with no allocation or
native handle; its explicit `core::clone::Destroy<Failure>` implementation
therefore has no resource work. Response owners still require their documented
explicit destruction.

## Fetch application

`sample_programs/library/http_fetch.lani` provides a real one-request CLI:

```text
http-fetch 127.0.0.1:8080 virtual.example:8080 '/path?q=x'
http-fetch '[::1]:8080' virtual.example /upload --method POST --body payload.bin
http-fetch 127.0.0.1:8080 virtual.example /upload --body - --report <payload.bin
```

The first three arguments are numeric ADDRESS with port, Host AUTHORITY, and
TARGET. Options are `--method`, `--body FILE|-`, repeated `--header NAME:VALUE`,
`--timeout`, `--raw`, `--report`, `--max-request`, `--max-response`,
`--max-body`, `--max-head`, `--max-line`, `--max-headers`, `--max-trailers`,
`--max-trailer-bytes`, `--max-chunks`, `--max-interims`, `--max-interim-bytes`,
`--max-io`, `--max-work`, and `--max-output`. Scalar options use their last
value. Raw/report are mutually exclusive. Header records preserve order.
Numeric values are checked unsigned decimal. The argument snapshot caps 64
tokens and 16384 bytes; paths and field values can contain non-UTF-8 bytes.

Timeout defaults to 5000 ms and caps at 60000. It covers `exchange_until` after
body-file/stdin staging, including request preparation, validation and decode.
Body-file/stdin staging and checked stdout publication are separately blocking
and do not have a clock timeout. Files are explicitly closed before exchange;
stdin/stdout remain borrowed. CLI size/count caps accept up to 67108864;
work/I/O caps accept up to 2147483647. Library limits are independent.

Default output is the transfer-decoded body, with no newline or content
conversion. `--raw` emits the final encoded response only. `--report` stages
one ASCII line with status, framing, lengths, informational count, upload
progress, shutdown flags, observed/discarded bytes, work, and I/O calls.
Default output cap is 18874368 bytes. The complete body/raw response/report is
prepared and checked before stdout. Syntax, framing, and limit failures emit
no stdout. A host output error can follow a prefix already accepted by the
OS; all owners are still cleaned up.

The CLI sets process-wide SIGPIPE Ignore before allocation or output, so real
closed stdout/stderr pipes use checked failures. Signal setup failure is
quiet. Exit statuses are 0 success (including HTTP error statuses), 2 argument
syntax, 3 transport/protocol/limit failure, 4 allocation failure, and 5 body
file/stdin/stdout/stderr or signal-policy failure. Diagnostics include cause,
stage, confirmed byte progress, upload/shutdown flags, and I/O count; a
secondary close failure is marked.

Explicit DNS composition belongs to caller code: invoke `dns_client.query_until`
with the same absolute deadline, copy a chosen A/AAAA address value, release
that DNS response, then call `exchange_until` with the numeric endpoint and
unchanged Host authority. There is no automatic address selection/fallback or
resolver activity inside the HTTP client.

## Focused execution evidence

The shared transport-free Protocol extraction and new trailing policy are
pending their current compiler/native gates. The receipts below establish the
preceding `480432e8` HTTP implementation; they do not establish acceptance of
these new Protocol entry points or the refactored plain driver. Existing
public plain Exchange/exchange_until signatures remain the same, and callers
using default_options select the existing Discard behavior. A direct Options
literal must now supply trailing explicitly.


The synchronous client regression and the five direct Prepared/Exchange groups
passed after the resumable refactor on the native Linux x86-64 profile through
the production GPU compiler. Their separate receipts and finite scopes are
recorded below.

`tests/extended_http_client_execution.rs` compiles native public contracts and
the CLI. The native fixture destroys caller method storage before inspecting
the response, exercises counted/strided binary input, two informational heads,
chunk extensions/trailers, and owned decoded body. The Python oracle uses
independent h11 request parsing and `http.client` body decoding against IPv4/
IPv6 loopback peers. It covers whole/bytewise/7-byte fragments, fixed/chunked/
close framing, HEAD/204/304, HTTP/1.0, binary headers/bodies, malformed and
smuggling inputs, exact EOF caps, large response scale, and an early-final
server that withholds its body until it observes the client’s half-close.

Fault gates fail every allocation reached on body and informational/chunked
report paths, check active leaf call accounting and persistent interruptions,
exercise late positive receives, exact-cap EOF, shutdown, close and publication
clock failures, and primary/secondary errors. Resource ledgers match mmap and
munmap addresses and requested lengths and check every owned FD close attempt.
CLI gates cover stdin/files, EIO/EINTR/short writes, `/dev/full`, actual anonymous
broken stdout/stderr pipes and failed signal setup. Oracles require test-only
Python h11; production uses no Python, Rust parser, JSON bridge, or external
network nameserver/service.

All six synchronous regression groups passed in 26.85 seconds, recorded in
`target/stdlib-work/http-exchange-client-regressions-current.log`. They report
188 cases: one native contract, 47 matrix, 21 limit/early-final, 34 rejection,
73 fault and 12 CLI/I/O cases. The two allocation paths reach 13 body and 22
report mappings; each reached allocation is failed individually and checked
for cleanup. The 1 MiB response case recorded 0.120329 seconds of client-process
wall time, including startup and transfer but excluding compilation. This is
one native peer/process observation, not a standalone throughput measurement.
The late-shutdown control verifies a successful shutdown syscall and its
recorded progress before the delayed return causes the original deadline to
expire.

`tests/extended_http_exchange_execution.rs` adds 83 direct cases: three
stepping/readiness, 20 framing, two early-final, 10 lifecycle and 48 fault
cases. The strengthened steps, framing and early-final groups passed in the
mixed 9.35-second invocation recorded in
`target/stdlib-work/http-exchange-all-groups-current.log`. Lifecycle and fault
groups passed their focused 8.58-second retry in
`target/stdlib-work/http-exchange-two-groups-retry.log`. The allocation
workloads reached 12 and 14 engine allocation positions, each failed once.
These counts are separate from the synchronous 188-case regression.

Direct-call trace epochs check no internal poll, one active network leaf per
step, 1024-byte send/receive bounds, cumulative accounting and confirmed
prefixes. They also check staged caller-storage release, owned Response
lifetimes, real EOF versus advisory readiness, early-final half-close and
single cleanup authority. Two harness corrections preserved the existing
fresh-readiness and canonical zero-cap contracts; the classification and
full coverage limits are in the
[Exchange testing guide](extended-http-exchange-testing.md). These finite
loopback cases do not establish hard CPU preemption or general HTTP
conformance.
