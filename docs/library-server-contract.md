# Shared server contract

This is the frozen interface for the current server implementation increment.
It defines the API that the plain driver, TLS driver, scheduler and focused
fixtures compile against. The implementation is saved; its finite acceptance
scope is recorded below. Interface admission does not establish all transport
or scheduler behavior.

The sole HTTP owner and shared HTTP types live in `ext::http_server`. The TLS
driver imports that module; it does not implement another request parser,
Expect policy, target classifier, decoder, Date formatter or response writer.
Production code remains Lanius plus the existing native host/OpenSSL bindings.

## Existing data and new decisions

Existing `Options`, `Stage`, `Cause`, `Stats`, `TargetForm`, `Target`,
`Expectation`, `RequestHead`, `Request` and `Response` retain their fields and
variants. Failure gains the separately latched rejection:

```lani
pub enum Status { Active, Complete, Failed, Aborted }
pub enum BodyDecision { Read, ContinueThenRead }
pub enum SendKind { Continue, Final }
pub struct Rejection { cause: Cause, stage: Stage, stats: Stats }
pub struct Failure {
    cause: Cause, stage: Stage, stats: Stats,
    cleanup_attempted: bool, cleanup: core::option::Option<core::io::Error>,
    rejection: core::option::Option<Rejection>
}
pub enum Event {
    Head(RequestHead), Request(Request), Rejected(Rejection),
    Empty, Complete(Stats)
}
pub enum Need {
    Local, Input(i32), Output(SendKind), Decision,
    Shutdown, Drain(i32), FinishTransport
}
```

`Failure` and `Rejection` contain diagnostic values, not native handles or
allocated owners. `Failure` implements `core::clone::Destroy<Failure>` with no
resource work. An adapter may cache/return their borrowed value descriptors.
A generic adapter's other error type must independently state its ownership;
it must not duplicate ownership between its cache and a returned error.

## Concrete Protocol interface

The signatures below use fully named library types except the types defined
in `ext::http_server` above.

```lani
pub fn reservation_bytes(options: Options)
    -> core::result::Result<u64,Cause>;
pub fn protocol(options: Options, deadline: core::time::Deadline)
    -> core::result::Result<Protocol,Failure>;
pub impl Protocol {
    pub fn borrow(&self) -> &Protocol;
    pub fn status(&self) -> Status;
    pub fn stage(&self) -> Stage;
    pub fn stats(&self) -> Stats;
    pub fn logical_bytes(&self) -> u64;
    pub fn remaining(&self) -> core::time::Duration;
    pub fn rejection(&self) -> core::option::Option<Rejection>;
    pub fn last_terminal_failure(&self) -> core::option::Option<Failure>;
    pub fn head(&self) -> core::option::Option<RequestHead>;
    pub fn request(&self) -> core::option::Option<Request>;
    pub fn final_staged(&self) -> bool;
    pub fn event(&self) -> core::option::Option<Event>;
    pub fn event_revision(&self) -> u64;
    pub fn need(&self) -> Need;
    pub fn check(&self) -> core::result::Result<bool,Failure>;
    pub fn before_io(&self, stage: Stage) -> core::result::Result<bool,Failure>;
    pub fn before_wait(&self) -> core::result::Result<bool,Failure>;
    pub fn failure(&self, cause: Cause) -> Failure;
    pub fn advance(&self) -> core::result::Result<Need,Failure>;
    pub fn read_body(&self, decision: BodyDecision)
        -> core::result::Result<bool,Failure>;
    pub fn respond(&self, response: Response)
        -> core::result::Result<bool,Failure>;
    pub fn receive_limit(&self) -> core::result::Result<i32,Failure>;
    pub fn feed(&self, bytes: core::slice::View<u8>)
        -> core::result::Result<bool,Failure>;
    pub fn feed_eof(&self) -> core::result::Result<bool,Failure>;
    pub fn start_send(&self)
        -> core::result::Result<core::option::Option<core::slice::View<u8>>,Failure>;
    pub fn pending_send_bytes(&self) -> i32;
    pub fn commit_send(&self, count: i32) -> core::result::Result<bool,Failure>;
    pub fn cancel_send(&self) -> core::result::Result<bool,Failure>;
    pub fn drain_limit(&self) -> core::result::Result<i32,Failure>;
    pub fn discard(&self, count: i32) -> core::result::Result<bool,Failure>;
    pub fn record_write_shutdown(&self, peer_eof: bool)
        -> core::result::Result<bool,Failure>;
    pub fn record_close(&self, attempted: bool,
        cleanup: core::option::Option<core::io::Error>)
        -> core::result::Result<bool,Failure>;
    pub fn transport_finished(&self) -> core::result::Result<bool,Failure>;
    pub fn abort(&self) -> bool;
    pub fn destroy(&self) -> bool;
}
```

### Events and application authority

`advance` performs one bounded local action, never socket/TLS I/O or a wait.
`need` and all metadata accessors perform no parsing, allocation, clock read or
I/O. Local means another local turn is available; Input/Drain counts are
positive and at most 1024. Output carries the kind of bytes being sent.

Head, Request and Rejected are latched application decisions. `event()` returns
the current borrowed descriptor repeatedly until an accepted command clears
it. `event_revision()` starts at zero and increases once for each new event;
drivers publish a given nonzero revision once. Need::Decision permits no
request read, discard or send. Application pauses retain the original absolute
deadline. A sink may call `respond` while the driver is between steps; drivers
must observe the Protocol's current need, rather than cache a stale decision.

Head permits `read_body` or a final response. Request permits a final response.
Rejected permits an allowed error final or abort; it never permits another
request read. A 2xx requires a full validated Request. An unknown/malformed
head permits only empty 4xx/5xx; a rejected request permits 4xx/5xx. All existing
HEAD/204/304/205, CONNECT, managed-field and explicit-Date rules remain.

`Read` accepts a head without a required interim. `ContinueThenRead` is valid
only for a supported, required 100-continue expectation, stages the exact 25
bytes, and automatically resumes body collection after they are confirmed.
Unsupported expectations or Read while Continue is required return
ExpectationRequired without changing the decision or doing I/O. Bodyless and
recognized HTTP/1.0 expectations need no interim. Known excessive fixed
content becomes Rejected before any Continue can be staged. Once Continue is
staged, its exact bytes must finish; no final can replace or interleave it.
Options.response_bytes and Stats.response_bytes describe the final encoded
response. Continue is the separate fixed 25-byte operation, charged to work,
active I/O and Stats.continue_sent; it is not added to that final byte cap.

`respond` validates and copies the complete final response synchronously, while
caller-local fields/body are alive. It sends no bytes. Invalid ordering,
response syntax/Date/capacity/allocation errors preserve the applicable
decision and leave no final staged; another valid response is permitted while
allowance remains. A work/deadline/clock failure is terminal. A successful
stage clears the decision and cannot be replaced. Request-borrowed response
body views are supported without releasing or mutating their backing.

### Input, reservations and teardown

`receive_limit`, `feed` and `feed_eof` are only for Input. Feed takes a positive
confirmed prefix no larger than the allowance and copies it into owned wire
storage. EOF requires an actual positive-capacity read returning EOF. Both
record successful transport progress before post-operation clock checks. A
request append allocation failure becomes a Rejected decision; fatal allowance
or uncertain-progress failures return Err. Parsing/validation/decode happen
in later local turns, preserving confirmed counts.

`start_send` is only for Output and reserves at most 1024 immutable bytes.
There is at most one reservation. `commit_send` accepts a positive prefix no
larger than that reservation, records Continue/final progress once, clears the
reservation and then checks the clock. `cancel_send` clears a reservation only
after the driver proves no native write is in flight. Plain EAGAIN/EINTR
supplies that proof; TLS WANT does not. Reservations survive unrelated drain
progress and must be retried with the same native bytes/count cell. No final
response can be staged while an interim reservation exists.

While final Output remains, `drain_limit`/`discard` may alternate bounded
discard reads with sends. They are also valid during Shutdown, so an existing
native TLS read can finish before local notify, and during Drain after write
shutdown. Shutdown discards do not acknowledge or skip local write closure.
They are forbidden during interim Output. Discard takes the validated native
count, including zero for actual EOF from a positive-capacity attempt. It
never parses or appends those bytes. At an exact drain cap it allows one byte
of EOF lookahead: zero succeeds, positive one counts confirmed progress then
fails DrainLimit. Already-buffered tail and newly discarded bytes stay separate
in Stats. A send need not wait for an unread upload to drain first.

After the final send, Shutdown requires actual plain SHUT_WR or local TLS
notify. `record_write_shutdown(peer_eof)` records that successful side effect
and any simultaneously confirmed authenticated peer EOF before its one
post-operation clock check, then advances to Drain. Plain SHUT_WR supplies
false; TLS Shutdown::Complete supplies true, while a local-only alert supplies
false. The boolean never authorizes inventing peer EOF. After actual peer EOF,
the next local turn selects FinishTransport. An initially empty request EOF
selects FinishTransport without inventing HTTP output or requiring plain
shutdown; a TLS driver may still notify before closing and record that local
notify in FinishTransport. TLS EOF must be authenticated by its adapter.

The driver disarms/closes its actual descriptor once, then calls record_close
with whether it attempted that close and its optional error. This hook is
available even in failed/aborted states and under exhausted allowances. It
updates cleanup counters and `closed`. For an earlier fatal cause, cleanup
failure is secondary and the cached Failure gains truthful final Stats; a
close failure after otherwise successful progress is primary at Close.
It never performs I/O. Do not call it twice for the same retired transport.

`transport_finished` requires FinishTransport, no send reservation and a
recorded closed transport. It performs the final clock check, then publishes
exactly one terminal event: Empty for initial empty EOF, otherwise
Complete(Stats). Both are visible only after native cleanup. Repeated terminal
steps publish no second event or response. The separately latched rejection
remains inspectable with successful completion.

### Failure and storage lifetime

Known-progress request syntax/framing/head/line/target/body/raw limits and
request-staging allocation failures become one Rejection with immutable
cause/stage/Stats snapshot. Clock/reversal/timeout, exhausted work or I/O,
transport failure, invalid native counts and internal boundary inconsistency
are fatal. `failure(cause)` latches the first fatal cause; later active commands
return that cached Failure. Later error-response failure is primary while
`Failure.rejection` retains the earlier request rejection.

`abort` changes an active Protocol to Aborted and clears send reservations;
it performs no transport work and **retains all byte storage**. `destroy`
releases that storage once; an active owner becomes Aborted. Failed/Complete
status and diagnostic metadata survive destroy. Drivers retain Protocol after
terminal error, abort or completion, so published request/head/body views stay
valid until the actual Exchange.destroy. Repeated cleanup cannot free aliases.

Frozen head, request wire, decoded body and response wire have one owner.
Canonical full request/response parsing, response encoding and decoding remain
the only wire authorities. Request wire freezes before Request publication;
later discard cannot relocate it or expose a second request. There is no
Request ownership transfer to a service report.

`reservation_bytes` validates Options and returns a conservative logical byte
reservation for head + raw request + decoded body + response, plus response
line and header-descriptor staging candidates. It excludes native/OpenSSL
heaps, allocator spare capacity, caller/application storage and stack memory.
`logical_bytes` reports the current four persistent owner lengths. A scheduler
reserves the full byte candidate and `options.work` before admitting a socket;
current lengths are diagnostics, not permission to over-admit.

## Plain Exchange and synchronous convenience

```lani
pub fn begin_connected(socket: std::socket::Socket,
    peer: core::net::SocketAddr, options: Options,
    deadline: core::time::Deadline)
    -> core::result::Result<Exchange,Failure>;
pub impl Exchange {
    pub fn borrow(&self) -> &Exchange;
    pub fn protocol(&self) -> &Protocol;
    pub fn peer(&self) -> core::net::SocketAddr;
    pub fn stats(&self) -> Stats;
    pub fn status(&self) -> Status;
    pub fn rejection(&self) -> core::option::Option<Rejection>;
    pub fn last_terminal_failure(&self) -> core::option::Option<Failure>;
    pub fn remaining(&self) -> core::time::Duration;
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

The constructor consumes a connected nonblocking TCP socket on entry, including
on failure, and checks its flag with one charged attempt. It never accepts,
polls or performs protocol transfer. Each step does either one local action or
at most one active send/receive/shutdown leaf; fatal cleanup may also close.
No step/before_wait polls or internally retries EINTR/WouldBlock. Fresh advisory
readiness is consumed once; hangup never stands in for a positive read's EOF.
Both read and write blocking settle into non-immediate poll interest.

Before_wait checks time/allowance; it returns false without a poll charge for
immediate work or an application decision. True charges one abstract poll
participation and preserves the advertised descriptor/interest until the
caller registers it. Driver fatal paths close/disarm transport and record
cleanup before Err; buffers remain until destroy. Abort also closes once and
preserves backing; destroy releases it even when close reports an error.

The existing `accept_until`/Connection surface remains a useful synchronous
convenience over this same Exchange and Protocol. It is the only layer here
with polling/driver loops. `read_head`, `send_continue`, `read_request`, `reply`,
`finish`, `close`, `destroy`, `peer` and `stats` keep their signatures. It does
not duplicate framing, body decoding, response preparation or teardown policy.
Fatal transport errors are now sticky; the old test permitting `finish` to
resume after send EIO must migrate. Atomic response-preparation errors still
permit another reply. This is a deliberate failure-policy correction, not a
compatibility shim or request to preserve uncertain native progress.

## Scheduler integration boundary

The scheduler owner defines its own exact generic Driver/Factory/Handler APIs
in `ext::server_poll`. Its Driver must expose `protocol() -> &Protocol`, the
progress/event/decision/cleanup methods above, and typed error diagnostics.
Reply.stage calls Protocol.respond synchronously inside the handler so borrowed
handler-local headers/body cannot escape. Head and Request callbacks receive
borrowed descriptors; reports contain values/Stats/rejection/errors only.

The generic Driver requires `abort() -> Result<bool,E>` to retire transport
while retaining Protocol storage, and `destroy()` with no return value to
release backing from an **already terminal** owner. The adapter calls its
concrete Exchange.destroy only after step/before_wait Err, Complete/Empty, or
an explicit abort. In that terminal state concrete destroy performs no native
I/O and cannot introduce another cleanup failure. The scheduler first snapshots
Stats/rejection/errors, then destroys backing exactly once. For a handler or
global failure it keeps the abort error separately from the original primary
error. Factory.begin failure releases all acquired transport and byte owners.

The agreed scheduler shape is a persistent
`Server<D,E,F,H,A>` borrowing listener/factory/handler until destroy. It offers
bounded step/decision/admission turns, separate prepare_wait and one-shot
resume(epoch, readiness) with ordinal/generation/fd validation, and poll_once
plus serve_until over that same owner. Every mutation invalidates old poll
publication. stop_accepting drains; abort_all immediately retires active
owners. The scheduler's public interface is frozen by its own module owner;
these Protocol signatures do not require a C callback, worker or new ABI.

## Current admission evidence

The root compiled the actual public control at
`tests/fixtures/stdlib_compiler_state/server_poll_admission/main.lani` and
validated its ELF64/x86-64 output. The native program exited successfully with
empty stdout/stderr. Its assertions exercised real Protocol head/body events,
synchronous reply staging with handler-local bytes, ordinary generic
Driver/Factory/Handler dispatch, and nested owned application/transport errors
through the actual Report take/destroy implementation. The compile and native
logs are `target/stdlib-work/server-poll-public-admission-first.log` and
`target/stdlib-work/server-poll-public-admission-native-first.log`.

That control uses a scripted test driver around the real Protocol. It is not
plain Exchange I/O, concurrent scheduling, TLS closure, or a GPU-executed
network service acceptance receipt. Those focused gates remain separate.
