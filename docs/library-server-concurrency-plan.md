# Resumable HTTP and HTTPS servers

The shared Protocol, plain and TLS drivers, generic server scheduler and both
local service applications are implemented. Finite native gates have passed
for protocol and generic dispatch, direct drivers, retained synchronous
behavior, causal application concurrency and bounded scale. The full server
increment is still under acceptance. Remaining gates cover plain fault and
resource handling, targeted TLS teardown, and actual Server owned-error and
global-cap behavior. Worker threads and the rest of the library roadmap remain
open.

This document preserves the original design rationale and the numbered
acceptance scope below. Its sketches explain that design; the current guides
define exact APIs, supported profiles and separate acceptance receipts:

| Surface | Current guide |
| --- | --- |
| Shared Protocol and plain Exchange | [Shared server contract](library-server-contract.md) |
| TLS Exchange and closure policy | [HTTPS server Exchange](extended-https-server-exchange.md) |
| Generic scheduler and persistent Server | [Server poll](extended-server-poll.md) |
| Plain service application | [HTTP service](extended-http-serve.md) |
| TLS service application | [HTTPS service](extended-https-server.md) |

Those finite receipts do not establish every acceptance item below. In
particular, separate raw OpenSSL experiments, direct-driver controls and
application runs retain their own evidence limits. No GPU program execution
or support for another operating system is claimed.

The first supported profile is Linux x86_64/glibc, with OpenSSL 3 for HTTPS.
Production protocol and scheduling code stays in Lanius. Existing native
socket, clock, poll and OpenSSL bindings supply host services. This design
needs no C callbacks, worker entry, new compiler IR or cryptographic primitive.

## Starting point before implementation

The following boundaries describe the sequential implementation that this
increment replaced. They explain why the shared engine was needed.

- [http_server.lani](../extended/ext/http_server.lani) already owned a staged
  head, request wire, decoded body and encoded response. It used the canonical
  HTTP cursor/parser/decoder/writer, but accept, receive, send and drain methods
  contained waits and loops.
- [https_serve.lani](../sample_programs/library/https_serve.lani) duplicated
  request collection, Expect handling, decoding and response preparation in
  the application. It served connections sequentially through
  [tls_stream.lani](../extended/ext/tls_stream.lani), whose byte-stream
  operations also waited internally.
- [openssl_tls.lani](../extended/ext/openssl_tls.lani) supplied caller-driven
  handshake/read/write/shutdown attempts, stable native retry storage and
  separate read/write count cells. It borrowed its nonblocking descriptor.
- [std::poll](../stdlib/std/poll.lani) supplied reusable bounded storage.
  `poll_ms` performed one syscall and returned EINTR; `poll_until` contained a
  retry loop. The new scheduler uses `poll_ms` and retains its own deadlines.

The resulting transport-independent server protocol is the sole authority for
head validation, target classification, Expect policy, request boundaries,
body decoding and response encoding. Both direct drivers and the concurrent
service use it. Existing canonical codecs remain the source of wire rules.

## Protocol owner and application decisions

The implementation keeps Protocol and the public request, response, options,
stats and HTTP error types together in `ext::http_server`. Its synchronous
Connection now uses Protocol plus the plain driver. The HTTPS driver imports
that same module. This gives both transports one preparation/parser/writer
implementation without a protocol/type import cycle. The Protocol interface
was frozen before the scheduler and TLS adapter integrated against it.

The original partial sketch below describes the ownership and decision model.
It is not the complete public interface. The exact signatures are in the
[shared contract](library-server-contract.md); the actual public generic
admission control has compiled and executed, as recorded there.

```lani
pub enum BodyDecision { Read, ContinueThenRead }
pub enum SendKind { Continue, Final }
pub struct Rejection { cause: Cause, stage: Stage, stats: Stats }
pub enum Event {
    Head(RequestHead), Request(Request), Rejected(Rejection), Empty, Complete(Stats)
}
pub enum Need {
    Local, Input(i32), Output(SendKind), Decision,
    Shutdown, Drain(i32), FinishTransport
}

pub fn protocol(options: Options, deadline: core::time::Deadline)
    -> core::result::Result<Protocol,Failure>;
pub impl Protocol {
    pub fn advance(&self) -> core::result::Result<Need,Failure>;
    pub fn event(&self) -> core::option::Option<Event>;
    pub fn event_revision(&self) -> u64;
    pub fn read_body(&self, decision: BodyDecision)
        -> core::result::Result<bool,Failure>;
    pub fn respond(&self, response: Response)
        -> core::result::Result<bool,Failure>;
    pub fn feed(&self, bytes: core::slice::View<u8>)
        -> core::result::Result<bool,Failure>;
    pub fn feed_eof(&self) -> core::result::Result<bool,Failure>;
    pub fn start_send(&self)
        -> core::result::Result<core::option::Option<core::slice::View<u8>>,Failure>;
    pub fn commit_send(&self, count: i32)
        -> core::result::Result<bool,Failure>;
    pub fn transport_finished(&self)
        -> core::result::Result<bool,Failure>;
    pub fn destroy(&self);
}
```

`advance` converts eligible parse/limit errors into a latched Rejection and
Need::Decision; it does not return those as terminal Err. `Event` is a borrowed
descriptor of the owner's current application decision.
It remains visible without generating another callback until the application
chooses the next operation. A driver publishes each decision once. Repeated
inspection has no I/O or allocation. `Need::Decision` forbids input collection
or response transmission until the application acts. Application pauses still
consume the connection's existing absolute deadline.

Empty and Complete become terminal events only after the driver has retired
the native transport, recorded close progress and called transport_finished.
Protocol abort retains its buffers; explicit Exchange.destroy releases them.
The scheduler snapshots terminal values and then destroys backing once.

| State/event | Application may do | Required next behavior |
| --- | --- | --- |
| New connection | Drive steps | Read and validate a head, or report actual empty EOF |
| Head | Read, explicitly continue then read, respond, abort | Preserve the head while body wire may grow |
| Request | Respond or abort | Body and complete message have passed canonical validation |
| Rejected | Empty 4xx/5xx or abort, if budgets and transport allow | Retain the original rejection diagnostic; never resume request parsing |
| Response staged | Drive steps or abort | Finish that exact response; no replacement final response |
| Empty | Retire connection | No invented HTTP request or automatic response |
| Complete/failed/aborted | Inspect cached result, destroy | No further active I/O or second publication |

Preserve the existing explicit Expect profile: one supported HTTP/1.1
expectation with content requires `ContinueThenRead` or an immediate final
response. Unsupported expectations cannot enter body collection. HTTP/1.0
ignores recognized 100-continue; bodyless requests need no interim response.
Known excessive fixed content fails before 100. Once any 100 response is
staged, finish its exact bytes before permitting a final response. Invalid
ordering returns `InvalidState`/`ExpectationRequired` without starting I/O.

The previous sequential HTTPS application omitted 100 when some body bytes
had already arrived. RFC 9110 permits that. The common library and migrated
applications use the explicit-continue rule above for both transports. The
[HTTPS application guide](extended-https-server.md) records this behavior
change and its finite regression receipts. Head callbacks must promptly
choose a final response or continuation rather than wait for a body the client
has withheld.
[RFC 9110 Expect requirements](https://www.rfc-editor.org/rfc/rfc9110.html#section-10.1.1).

### Backing and transfer

The Protocol exclusively owns four storage classes: frozen head bytes, request
wire, decoded body and response wire. Published head views borrow the first;
body growth cannot invalidate them. Publish a complete Request only after
freezing its wire allocation, checking the cursor boundary against the whole
parser, and decoding into its separate owner. Retained tail bytes never
become a second request. Preserve exact bounds and target/expectation behavior
from the current server guide, including target-limit classification.

Request views remain valid through response staging, errors and descriptor
closure until Protocol destruction. They do not survive slot retirement.
The scheduler's report contains values, stats and owned/valid error payloads,
not dangling Request views. A handler cannot retain a borrowed request after
its invocation/connection lifetime. A response may borrow its request body or
handler-local line/field/body scratch. It must be staged synchronously through
the reply sink described below while that storage is still alive. Returning a
Response containing views into handler locals is invalid: those locals can
expire before the scheduler calls `respond`. Successful staging copies and
validates all response bytes; caller backing can then be released immediately.

Response preflight must be atomic: malformed fields, allocation or capacity
errors send no response bytes and leave direct callers able to choose another
response while allowance remains. The scheduler initially treats a handler's
unusable response as that connection's failure and aborts it, rather than
calling the handler repeatedly. Counts and original failure remain visible.

Keep the existing response profile: 200..599 finals, no upgrade or successful
CONNECT tunnel; Date, Connection and framing fields are library-owned. A
successful 2xx requires a fully validated request. Unknown/malformed heads
permit empty error finals only. HEAD/204/304/205 retain the documented empty
body and length policies. Wall time is an explicit response input. Routing,
authority, Origin, authorization and HTTP error-status selection belong to
the application.

### Rejection is an active decision, not terminal failure

Classify known-progress HTTP syntax/framing failures and request/head/line/
target/body limits as `Event::Rejected`. Request-staging allocation failure
may also offer an empty error response if its existing owners and confirmed
transport progress remain valid. Keep the frozen validated head when present
and all already-owned request storage until destruction. Stop further request
parsing and decoding; a rejection is not a retry permission. Unknown or
unvalidated bytes do not gain Request/Head authority through this event.

The Rejection contains the original cause, stage and immutable stats snapshot.
It is latched once. `stats()` continues to show current counters as a chosen
error response is staged, sent and drained; those later counts do not overwrite
the rejection snapshot. A handled rejection can complete with final Stats and
the retained optional Rejection in its outcome. It is not labelled a clean
accepted request, and the application chooses whether it affects process status.

Fatal transport/TLS errors, clock failure/reversal, observed timeout, exhausted
active allowances, invalid syscall counts and internal boundary inconsistency
produce terminal Failure and abort active transport instead. They do not
offer a Rejected decision that implies further response I/O is available.
This explicitly tightens the old Connection's broad read-error rejection
state; preserve old error-progress evidence and document the changed policy.
Local invalid application ordering returns InvalidState with no I/O; it does
not by itself imply a broken socket or replenish any allowance.

If staging/transmitting/draining/closing a chosen rejection response later
fails, that later operation is the terminal Failure's primary cause and stage,
with current Stats. Add `rejection: Option<Rejection>` to that failure/outcome
so the original HTTP rejection remains available alongside it. A cleanup close
failure is secondary to that terminal cause. A previously successful final
transfer followed only by close failure makes Close the primary error. A
terminal Failure is sticky after cleanup and never permits further active I/O;
the separately latched Rejection is the only diagnostic that can coexist with
an active response/drain state.

The existing Failure record can also describe a rejected command/preparation
attempt. Such an Err from `respond`/`read_body` is not automatically a terminal
driver transition: invalid order and atomic response syntax/capacity/allocation
failure preserve the applicable decision state. Expired time/work/I/O allowance
and uncertain native progress do terminate it. The API guide must state this
operation-specific distinction and expose status/last_terminal_failure; do not
cache an ordinary preparation rejection as the driver's terminal failure.

## Plain and TLS drivers

Boundaries: the existing `ext::http_server` for Protocol and the plain driver,
and `ext::https_server` for the TLS driver. Both expose the same progress
contract, with distinct typed transport errors:

```lani
pub fn begin_connected(socket: std::socket::Socket,
    peer: core::net::SocketAddr, options: Options,
    deadline: core::time::Deadline)
    -> core::result::Result<Exchange,Failure>;
// HTTPS additionally borrows a ServerContext and takes a tls-call limit.
pub impl Exchange {
    pub fn interest(&self) -> ext::http_client::Interest;
    pub fn raw_handle(&self) -> core::option::Option<i32>;
    pub fn before_wait(&self) -> core::result::Result<bool,Failure>;
    pub fn step(&self, ready: ext::http_client::Readiness)
        -> core::result::Result<core::option::Option<Event>,Failure>;
    pub fn read_body(&self, decision: BodyDecision)
        -> core::result::Result<bool,Failure>;
    pub fn respond(&self, response: Response)
        -> core::result::Result<bool,Failure>;
    pub fn abort(&self) -> core::result::Result<bool,Failure>;
    pub fn destroy(&self) -> core::result::Result<bool,Failure>;
}
```

These constructors consume the accepted socket on entry, including on error;
the caller retires its old shallow descriptor immediately. A failed constructor
closes acquired owners once and returns primary plus cleanup diagnostics.
The caller supplies a connected nonblocking TCP owner; constructor checks
and TLS setup phases must not perform a blocking handshake or hidden wait.
For TLS, create the Session while the borrowed ServerContext is live;
SSL_new retains the native context. A separate retained ServerContext API is
not required if attachment is eager. If attachment is deferred, implement and
test a real retain operation before allowing the caller context to expire.

Every `step` performs **zero or one active transport leaf**: plain send,
receive or shutdown; or TLS handshake, read, write or shutdown attempt. A
terminal step can close during mandatory cleanup. Allocations, clock checks,
native session construction and frees have separately documented accounting;
an OpenSSL operation can itself issue several BIO syscalls. There is no claim
of one OS syscall, equal CPU time or native preemption. One bounded local
protocol action per turn yields between scan/validate/decode/stage phases.

No step or before_wait calls poll or repeats interrupted/would-block I/O.
Readiness is advisory and consumed once. Hangup/error wakes the relevant
operation; only a positive-capacity read returning EOF establishes EOF.
`before_wait` checks time/budget and may retire an owner. Its successful true
result must preserve the advertised interest and descriptor until registration.
On retirement the scheduler reconsiders admission before blocking.

### TLS reservations and simultaneous directions

Use the existing Session owners and native storage; do not add TLS record or
cryptographic code. No HTTP event reaches the application before the native
handshake and configured client-certificate policy succeed. Required fresh
client-chain verification remains distinct from application authorization.

`start_send` establishes a bounded Protocol reservation. A successful plain
send commits its confirmed prefix. Plain EAGAIN/EINTR leaves no native write
request in flight, so the reservation may be released under an explicit
no-progress operation. A TLS WANT retains the exact native bytes, pointer,
length and count cell; retry through Session.retry_write and commit only the
returned positive count. Never replace it with a new response, interim head,
alert or shorter suffix while it is pending.

Respect Session's directional guards: write-WANT_WRITE is exclusive;
write-WANT_READ may require the permitted read progression, with independent
read storage/count cells. Pending read-WANT_WRITE must progress its protocol
output before being quiesced. Read-WANT_READ may be explicitly quiesced only
through the supported API. Buffered native plaintext is immediate work even
when the socket currently has no readable event. Reuse the client adapter's
tested arbitration rules, but audit them for server response/drain transitions.
If an interleaved read observes authenticated peer EOF while a write remains
pending, Session enters PeerClosed and cannot retry that write. Fail and
abandon the pending reservation with confirmed-send counters unchanged; do
not infer successful delivery from peer closure. A pending discard read that
requires write readiness must complete/progress its native operation before
shutdown can begin. Shutdown WANT is itself exclusive until local alert
completion, after which reads may resume.

## Rejection, drain and terminal behavior

While response bytes remain, alternate bounded sends and bounded discard
receives when both are possible. This applies to accepted responses with
already-buffered tail and early rejection of an unread upload. No unbounded
upload must be consumed before starting a rejection response. Discarding is
not parsing, accepting, forwarding or authorizing another request.

Plain TCP retains checked write half-close followed by bounded discard to
actual EOF. At the exact drain limit, a positive one-byte EOF probe may return
zero; a byte consumes the lookahead and reports DrainLimit. Keep received,
buffered-discarded and new-drain counts separate. Deadline/drain failure may
prevent full peer delivery even after all local sends succeeded.
[HTTP teardown considerations](https://www.rfc-editor.org/rfc/rfc9112.html#section-9.6).

HTTPS uses TLS closure, not raw TCP SHUT_WR in place of a native alert. Finish
any pending write first. Once the final HTTP bytes are confirmed, quiesce
only an eligible pending read, advance `shutdown_write` until local notify is
confirmed, then use reads to preserve/discard remaining peer application data
and observe authenticated peer closure. Do not use repeated full shutdown to
discard unseen application data. After peer alert, finish native cleanup and
close the socket once. An abrupt TCP EOF is truncation, not authenticated EOF.
[OpenSSL shutdown behavior](https://docs.openssl.org/3.0/man3/SSL_shutdown/).

The selected success policy requires authenticated peer EOF for TLS teardown,
as plain teardown requires EOF. It can time out after a delivered response
when the peer withholds its alert; retain that successful write progress in
the error. TLS 1.2 early rejection needed an explicit native peer experiment,
separate from TLS 1.3 half-close behavior. The
[TLS driver guide](extended-https-server-exchange.md) records the selected
ordering, raw closure experiments and later direct-driver acceptance as
separate evidence. Do not disguise a timeout,
truncation or missing peer alert as clean completion, or silently drop TLS 1.2
from the previously supported service profile.

Failure retains exact stage, confirmed progress, nested HTTP/TLS diagnostics,
any earlier Rejection, and secondary cleanup error. Recoverable HTTP rejection
is an application event, not yet a terminal transport error. Invalid byte counts, fatal TLS,
expired budget/deadline and close errors terminate the driver. Cleanup runs
without active-operation allowance and attempts every owned release. Abort
disarms before cleanup; repeated abort/destroy cannot close a reused fd.
Failed and completed terminal observations are stable and do no more I/O.

## One reusable server scheduler

The implemented `ext::server_poll` is parameterized by a plain/TLS Factory,
Driver and application Handler using ordinary Lanius traits. This is one
server admission/poll/cleanup engine shared by both transports. It reuses
std::poll; it need not force listener admission and application decisions into
the client's finite pre-staged-job scheduler. The following original sketch
shows the division of responsibility; consult the
[scheduler guide](extended-server-poll.md) for its full current interfaces.

```lani
pub trait Driver<E> {
    pub fn interest(&self) -> ext::http_client::Interest;
    pub fn raw_handle(&self) -> core::option::Option<i32>;
    pub fn before_wait(&self) -> core::result::Result<bool,E>;
    pub fn step(&self, ready: ext::http_client::Readiness)
        -> core::result::Result<core::option::Option<Event>,E>;
    // read_body, respond, stats and abort use the corresponding contracts above.
}
pub trait Factory<D,E> {
    pub fn begin(&self, accepted: std::socket::Accepted,
        deadline: core::time::Deadline) -> core::result::Result<D,E>;
}
pub enum Decision { Read(BodyDecision), Responded, Abort }
pub struct Reply { protocol: &Protocol }
pub impl Reply {
    pub fn stage(&self, response: Response)
        -> core::result::Result<bool,Failure>;
}
pub trait Handler<A> {
    pub fn head(&self, id: u64, peer: core::net::SocketAddr,
        head: RequestHead, reply: &Reply)
        -> core::result::Result<Decision,A>;
    pub fn request(&self, id: u64, request: Request, reply: &Reply)
        -> core::result::Result<Decision,A>;
    pub fn rejected(&self, id: u64, rejection: Rejection, reply: &Reply)
        -> core::result::Result<Decision,A>;
}
pub fn serve_until<D,E,F,H,A>(listener: &std::socket::Socket,
    factory: &F, handler: &H, limits: ServerLimits,
    deadline: core::time::Deadline)
    -> core::result::Result<Report<E,A>,ServiceFailure<E,A>>;
```

The handler stages a response inside its invocation through `Reply.stage`,
while its local headers, date buffer and body are alive. The sink borrows the
current Protocol and exposes synchronous response preparation only, with no
socket, poll, receive or TLS operation. It copies backing before returning.
Decision::Responded is valid only after exactly one successful final stage;
Decision::Read is valid only for a head and when no reply is staged. A failed
stage leaves no final staged, so the handler may choose an alternate valid
reply within its allowance, or return error/Abort. The scheduler checks the
decision against actual state, preventing success with an unstaged reply.

These are synchronous ordinary trait calls, not exported callbacks. Handlers
must bound their own work and avoid blocking I/O; the scheduler cannot preempt
application code or native calls. No heap-allocated closure or worker entry
is assumed. A handler error, invalid decision or returned response-preparation
error fails that connection while siblings continue. Returned A/E payloads
must own resources or borrow backing valid through Report destruction and
taken items; errors cannot borrow a handler's expired local scratch either.

Preallocate slots, outcome capacity, poll requests and PollSet before the
first accept. Configure explicit maximum accepted connections and concurrent
owners; handshake and drain phases count as active. Do not accept beyond the
active cap and hold hidden extra sockets. At capacity, leave connections in
the kernel listener backlog; do not promise bounded backlog memory or remote
connect latency. The initial service run is finite: count every kernel-accepted
connection, including empty, malformed, failed setup and failed handshake,
toward `max_accepted`. Peer-address decode failure with an acquired fd consumes
that admission too and retains its cleanup diagnostic.

One round gives each active slot at most one step or one application decision
in rotating order, plus at most one nonblocking accept when admission is
possible. Listener acceptance cannot monopolize a busy service. Retire freed
slots and reconsider listener work before blocking. Stop registering the
listener after the admission limit; finish active connections. Empty runs do
no accept/poll. Ordinary per-connection failures produce ordered outcomes and
permit further admission. Fatal listener, shared poll, clock or global budget
failures stop admission and abort active owners, retaining prior outcomes.

Build one poll request set from current identities after before_wait calls.
Discard stale results on fd/slot replacement; carry connection ordinal and
generation, not merely slot index. Include the listener only when it may
admit. Use poll timeout zero when local immediate work coexists with waiting
peers; otherwise wait until the earliest active or service deadline. Count
each actual poll, including EINTR. Do not interpret old PollSet publication
after an error as fresh readiness. EINTR consumes allowance and preserves
absolute deadlines. Ready fd bits do not prove successful I/O.

Reports retain acceptance-order outcomes and progress, with take/destroy
semantics and explicit nested-error cleanup. No request/response buffers
survive slot retirement unless a later API explicitly transfers ownership.
The listener stays caller-owned and open on return. The caller keeps Factory,
Handler, referenced configuration and TLS contexts live unchanged throughout
serve_until. No external descriptor closes/flag changes, concurrent use or
independent active shallow aliases are permitted.

### Limits, deadlines and cancellation

- **Connection:** retain separate HTTP head/line/header/trailer/chunk/body/raw
  request/response/drain caps, protocol work allowance, attempted active-I/O
  allowance, TLS-call allowance and one absolute connection deadline. Cap each
  active transfer at 1024 plaintext bytes or the smaller Session limit.
- **Service:** bound concurrency, total admissions, attempted accepts, physical
  polls, scheduler visits, handler calls, aggregate protocol work and logical
  live request/head/body/response bytes. Charge before work; use checked u64
  arithmetic. Name actual physical calls separately from conservative per-owner
  poll-participation reservations.
- **Reservation:** reject InvalidLimits if one connection cannot fit its
  configured byte/work reservation. Before each admission reserve available
  credit; if active owners hold it, wait for their retirement rather than
  accept an unbudgeted descriptor. Release unused reservation on retirement.
  Expose that conservative reservations can lower admitted
  concurrency; do not call a logical cap an RSS/native OpenSSL heap quota.
  Temporary response staging needs a pre-reserved candidate allowance, so the
  live cap is checked before constructing it rather than after publication.
- **Time:** service deadline covers listener waits and every active connection;
  a connection deadline is min(service deadline, accepted-at plus configured
  duration), never renewed by another stage, EINTR, callback or byte. This
  deliberately differs from the old sequential per-request accept deadline.
  Observe reversal and expiry around active work; record late successful I/O
  before reporting expiry, without publishing late success.
- **Cancellation:** expose `Server::stop_accepting()` to drain current owners
  and `Server::abort_all()` to retire them immediately; both are caller-driven
  between steps. The synchronous serve_until helper ends at its bounds/deadline.
  It must not imply another thread can cancel it. Signal integration belongs
  in the application and requires its own explicit contract.

Provide a caller-driven Server owner with `step`, `interest`/poll request
publication, outcome access, stop_accepting, abort_all and destroy; make
serve_until a convenience loop over that same owner. Do not implement a second
blocking scheduling path. Admission or report exhaustion never extends budgets.

The agreed wait interface separates a no-poll `step` from `prepare_wait`, which
publishes a one-shot epoch and borrowed poll requests. `resume(epoch, readiness)`
checks epoch, result length and the saved ordinal/generation/fd identities
before caching fresh hints. Any server mutation invalidates the old epoch.
`poll_once` performs prepare, one poll_ms and resume through this same owner;
it cannot silently reuse publication after interruption or another mutation.

## Implementation split and acceptance

| Owner | Source surface | Independent responsibility |
| --- | --- | --- |
| Protocol | Protocol and shared types in ext::http_server | Canonical parsing/writing, decisions, reservations, backing and work charges |
| Plain driver | ext::http_server, after Protocol interface freeze | One-leaf socket progression and synchronous wrappers over it; one file owner at a time |
| TLS driver | ext::https_server | Session ownership, verification, WANT arbitration, authenticated close |
| Scheduler | ext::server_poll | Generic admission, fair turns, shared polls, reservations, reports/cancellation |
| Application | http_serve and https_serve | Routing/status/trust policy, argument bounds, finite concurrency and reports |
| Tests/review | Focused direct, protocol, scheduler and application fixtures | Independent peers, causal schedules, owner ledgers and regressions |

The implementation sequence established type ownership, Event/Need, error
layers and consumption rules before parallel adapter work. A small actual
public trait control checked the generic boundary. Common response/target
logic stays with the Protocol owner. TLS tests share the existing native
observer. Independent review checks lifetimes, error scope and reservations.

Executable acceptance must include:

1. **Protocol decisions:** fragmented heads/body boundaries; stable head views
   across request growth; fixed/chunked binary bodies and trailers; independent
   h11/http.client parsing; invalid grammar and smuggling cases; Expect waiters,
   preloaded bodies, explicit 100, partial 100, early 4xx and malformed-head
   rejection. Verify original offsets and target-limit classification. A
   handled rejection retains its original stats snapshot while later reply
   counters evolve; injected send/drain/close failure retains both diagnostics.
   Handler-local response/header scratch must be copied before the handler
   returns, and later overwrites must leave the staged wire unchanged.
2. **Direct steps:** external markers around step/before_wait prove no internal
   poll and at most one active plain/TLS leaf. Real socket backpressure and
   native TLS WANT controls check stable send reservations, fresh readiness,
   buffered plaintext, exactly-once events and terminal replay.
3. **Causal concurrency:** hold one client's handshake or partial head until
   another completes; hold a response reader while another request finishes;
   require several accepted/request-ready peers before releasing a wave.
   Independent kernel fd accounting verifies caps. A freed slot must admit
   another client before an unrelated stalled peer's deadline, including
   begin failure and before_wait retirement.
4. **Teardown and policy:** large rejected uploads with bounded peer buffers;
   exact/below drain caps and positive EOF probe; peer half-close, abrupt reset,
   truncated native TLS record and missing notify; TLS 1.2/1.3 paired closure
   gates. Required/absent/untrusted/expired client chains must prevent HTTP
   callbacks while a valid sibling succeeds. All TLS bytes use real OpenSSL.
5. **Limits and cleanup:** zero/invalid/overflowing bounds, exact service and
   connection budgets, deadline expiry in each phase, EINTR/fatal accept/poll/
   clock/send/receive/close faults, handler error and response staging failure.
   Fail each reached source allocation in a causal representative baseline;
   bind exact site/ordinal/size and reject prefix drift. Check source mappings,
   native context/session owners and live fds before exit, plus recovery.
6. **Real program:** migrate both local services to the common engine, retaining
   their documented routing and explicit authority/trust distinctions. Exercise
   concurrent health/echo and rejection with binary bodies and fair refill.
   Compare response/status/header semantics independently, including all stated
   Expect/deadline changes, startup/report I/O errors and a bounded scale sample.

Choose narrow gates for each implemented boundary; reuse accepted independent
oracles instead of adding timing-ratio concurrency tests. Serialize GPU/native
acceptance through the existing root queue, keep each command under two minutes,
and record separate receipts. A compiler rejection gets a preserved minimal
control and dependency report, not a hidden compiler/ABI change in this batch.
