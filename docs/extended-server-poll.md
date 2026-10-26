# Shared bounded server scheduling

`ext::server_poll` defines the common typed boundary for plain HTTP and HTTPS
server scheduling. The HTTP protocol belongs to
[`ext::http_server`](library-server-contract.md); transport drivers own socket
and TLS progression. The scheduler owns admission, fair turns, shared readiness,
budgets and acceptance-order outcomes. It contains no TLS or cryptography.

**Implementation status:** the public Driver, Factory, Handler, Reply and
Report boundary passed its separate compile/ELF/native admission control,
including nested owned E/A, handler-local staging and take/destruction.
The actual source is
[`extended/ext/server_poll.lani`](../extended/ext/server_poll.lani).
The persistent Server passes seventeen scripted profiles across separate
owner/publication, owned-error and active-cap/cancellation receipts. Two
additional native poll-fault profiles pass with the real plain driver and a
separate baseline calibration. The actual plain
and TLS applications pass four causal concurrency cases, separate HTTPS/mutual-TLS
application groups and a 64-connection scale observation per transport.
The empty-run concrete helpers also execute with an application error type
without a Destroy implementation. These finite receipts are detailed below;
reached allocation-failure and wider host-fault coverage remain open. Supported
execution is native Linux x86_64; HTTPS adds the
glibc/OpenSSL 3 profile. Other targets and user GPU execution are unverified.

## Frozen driver and factory boundary

```lani
pub trait Driver<E> {
    pub fn protocol(&self) -> &http_server::Protocol;
    pub fn stats(&self) -> http_server::Stats;
    pub fn transport_calls(&self) -> Option<u64>;
    pub fn rejection(&self) -> Option<http_server::Rejection>;
    pub fn interest(&self) -> http_client::Interest;
    pub fn raw_handle(&self) -> Option<i32>;
    pub fn before_wait(&self) -> Result<bool,E>;
    pub fn step(&self, ready: http_client::Readiness)
        -> Result<Option<http_server::Event>,E>;
    pub fn read_body(&self, decision: http_server::BodyDecision) -> Result<bool,E>;
    pub fn abort(&self) -> Result<bool,E>;
    pub fn destroy(&self);
}
pub struct Reservation { work: u64, bytes: u64 }
pub trait Factory<D,E> {
    pub fn reservation(&self) -> Result<Reservation,Cause>;
    pub fn begin(&self, accepted: socket::Accepted, deadline: Deadline)
        -> Result<D,E>;
    pub fn failure_stats(&self, error: E) -> http_server::Stats;
    pub fn failure_transport_calls(&self, error: E) -> Option<u64>;
    pub fn shared_failure(&self, error: E) -> Option<Cause>;
}
```

The shortened names above refer to their `core`, `ext` and `std` modules.
Factory `begin` consumes the accepted socket on every result. Constructor
failure releases every partial native and byte owner. The borrowed listener
remains caller-owned and open. Factory/error queries borrow shallow values;
they cannot destroy, mutate or retain error cleanup authority.

Driver step/before-wait errors and Empty/Complete events have already retired
the native transport. Their Protocol backing remains valid. The scheduler
snapshots numeric Stats, the optional value-only Rejection and the returned
error before calling terminal-only `destroy`. That operation frees backing
without native I/O, allocation or reportable failure. Explicit `abort` first
retires an active transport, retaining its diagnostic backing for this same
destruction step. A primary E/A and a distinct abort/close E remain separate.

`transport_calls` is an optional adapter diagnostic. Plain drivers return
None; HTTPS returns Some with its native handshake/read/write/shutdown attempt
count, excluding setup/free calls. None does not mean zero. Availability and
any present counter must remain stable/monotone through the driver lifetime;
factory construction failures supply the corresponding optional snapshot.

A step performs one bounded local protocol action or at most one active
transport leaf. No driver step or before-wait method polls or retries
EINTR/WouldBlock. Readiness is advisory and consumed once. For `Ok(true)`,
before-wait preserves the preceding Interest and current descriptor identity
through registration; `Ok(false)` leaves immediate work available. One driver's
connection timeout is local. Shared clock failure/reversal is classified
explicitly; the scheduler independently enforces the service deadline.

## Handler decisions and synchronous staging

```lani
pub enum Decision { Read(http_server::BodyDecision), Responded, Abort }
pub trait Handler<A> {
    pub fn head(&self, id: u64, peer: SocketAddr,
        head: http_server::RequestHead, reply: &Reply) -> Result<Decision,A>;
    pub fn request(&self, id: u64, request: http_server::Request,
        reply: &Reply) -> Result<Decision,A>;
    pub fn rejected(&self, id: u64, rejection: http_server::Rejection,
        reply: &Reply) -> Result<Decision,A>;
}
```

Connection IDs are dense zero-based acceptance ordinals, never reused. Every
kernel-accepted socket consumes one ID, including peer-decode, constructor,
handshake, empty-input and request failures. Such an ID may produce no handler
call. Slot generations identify reused scheduling storage separately.

`reply(protocol)` creates a borrowed Reply sink. `Reply.head()` returns the
already validated optional head, without reparsing, allocation or I/O.
`stage(response)` calls Protocol.respond synchronously: response reason,
headers, Date and body are validated and copied while handler-local backing
is alive. Returning a Response with views into expired locals is unsupported;
handlers return Decision instead. `is_staged()` records successful final
staging, and `last_failure()` retains the latest staging diagnostic.
Successful final staging clears an earlier staging rejection, so a recovered
preflight attempt is not presented as the failure of a later handler action.

Responded requires a successfully staged final response. Read is legal only
for Head with no final staged; Protocol enforces the explicit Continue policy.
Request/Rejected require Responded or Abort. A handler may recover an atomic
staging rejection by staging a valid alternative while allowance remains.
An atomic staging rejection followed by Abort is cancellation. If staging
instead fails the Protocol, even a returned Abort produces
InvalidDecision(ResponseFailure) with the exact preparation Failure retained;
a preparation clock error also stops the service.
Unaccepted decisions cannot silently leave an application event pending.
Handlers are ordinary synchronous calls and must bound their own work;
the scheduler cannot preempt blocking application or native code.

## Service limits and reservations

`ServerLimits` has these frozen fields:

| Field | Default | Meaning |
| --- | ---: | --- |
| `max_accepted: i32` | 64 | Total accepted descriptors, including failed setup; hard maximum 4,096. Zero selects an empty run. |
| `concurrency: i32` | 4 | Active owners across setup, handshake, HTTP and drain; range 1..64. |
| `accept_calls: u64` | 1,048,576 | Attempted nonblocking accepts, including EINTR/WouldBlock. |
| `polls: u64` | 1,048,576 | Issued one-shot wait permits, including unused publications. |
| `operations: u64` | 16,777,216 | Charged scheduler visits, hooks, metadata initialization and clock checks. |
| `handler_calls: u64` | 192 | Application decision calls. |
| `work: u64` | 4,294,967,296 | Cumulative charged HTTP work plus active unused work reservations. |
| `live_bytes: u64` | 256 MiB | Conservative active HTTP byte reservations, including staging candidates. |
| `connection_timeout: Duration` | 5 s | Accepted-at duration, capped by the service's fixed absolute deadline. |

Factory.reservation uses `http_server::reservation_bytes(options)` and the
configured per-connection protocol-work allowance. Reserve both before
accepting a descriptor. This includes persistent head/request/body/response
bytes and response staging candidates; it excludes native/OpenSSL heaps,
allocator spare capacity, application/caller storage and stack memory.
Current logical byte lengths are diagnostic values, not permission to admit
another unreserved connection. Reservations can reduce effective concurrency.

`Stats.waits` counts issued wait permits. `Stats.polls` counts actual poll
syscalls performed by the owner's poll-once convenience; external readiness
submission does not fabricate an observed syscall. A caller may perform at
most one external poll for a publication. Driver I/O counters separately
include conservative poll participation. Mandatory cleanup bypasses exhausted
active budgets and attempts every owner.

Scheduler operations precharge each complete bounded pass: the admission slot
search, poll-request clearing and active-owner visits, and both readiness
identity validation and hint copying. An early exit keeps the reserved pass
charge. Clock observations and active hook calls have separate charges.
Cheap invalid epoch/length checks return before these passes. These are
abstract work units, not CPU instructions or a wall-time preemption guarantee.

## Manual typed outcomes

Report indexes are acceptance ordinals. Complete/Empty/Pending carry a
`ConnectionInfo` containing ID, optional peer, final/current HTTP Stats and
optional transport-call/Rejection snapshots. They contain no request or
response views.

Failed stores `TransportFailure<E>` with primary error and optional cleanup E;
HandlerFailed stores `ApplicationFailure<E,A>` with A, an optional unrecovered
response-preparation Failure and optional cleanup E.
InvalidDecision and Aborted retain optional cleanup E. AcceptFailed preserves
the native AcceptFailure, including whether an acquired descriptor needed
cleanup. Taken has no cleanup authority.

`Report.get` borrows a shallow descriptor. `take` replaces its entry with Taken
before transferring it; repeated/out-of-range take returns None. Do not destroy
an error copied from get. `destroy_outcome`, Report.destroy and
ServiceFailure.destroy require both E and A to implement `core::clone::Destroy`.
Only disposal requires these bounds; construction and transfer do not.
They release secondary cleanup errors, primary errors and application errors,
then outcome storage. Repeated report destruction is empty. Historical numeric
Stats remain readable.

Returned errors must own their memory or borrow backing independently kept
valid through their final use/destruction, including after report transfer
or take. They cannot borrow a destroyed Protocol, a retired driver or expired
handler scratch. A copied descriptor does not create another owner. The
admission control exercises two E/A pairs, including nested owned payloads;
it does not establish arbitrary drivers or scheduler error-path ownership.

## Persistent owner API

The Server owner borrows listener, Factory and Handler until
destruction. A fair step gives each active slot at most one driver step or
handler decision and performs at most one nonblocking accept. Freed slots
permit admission before blocking, including before-wait retirement. At the
active cap, connections remain in the kernel backlog rather than hidden
accepted owners. Stop-accepting drains existing owners; abort-all retires them.

Prepare-wait publishes an epoch, borrowed requests and bounded timeout.
Resume consumes that publication once after checking epoch, length and frozen
ordinal/generation/fd identity. Every mutation invalidates older publications.
Poll-once performs exactly this prepare/poll_ms/resume path with one actual
attempt; serve-until drives the same owner. Neither is a second scheduling
algorithm. Finite execution receipts below cover these paths without claiming
all quota, failure or cancellation boundaries.

```lani
pub fn new<D,E,F,H,A>(listener: &socket::Socket, factory: &F, handler: &H,
    limits: ServerLimits, deadline: Deadline) -> Result<Server<D,E,F,H,A>,Cause>
    where D: Driver<E>, F: Factory<D,E>, H: Handler<A>;
pub fn serve_until<D,E,F,H,A>(listener: &socket::Socket, factory: &F, handler: &H,
    limits: ServerLimits, deadline: Deadline)
    -> Result<Report<E,A>,ServiceFailure<E,A>>
    where D: Driver<E>, F: Factory<D,E>, H: Handler<A>;
```

Server exposes `borrow`, `stats`, `last_failure`, `is_complete`, `is_accepting`,
`len`, `get` and `take`. Taking a Pending entry returns None. `step()` returns
whether the round performed work, rather than a completion flag; use
`is_complete()` for termination. `prepare_wait()` returns a PollInterest with
epoch, requests, timeout, immediate-work and completion fields. An empty
publication needs another step or is complete; it grants no external poll.
`resume(epoch, readiness)` validates all frozen bindings before applying any
hint. `poll_once()` returns whether it actually attempted a poll.

`stop_accepting()` drains current connections. `abort_all()` retires them
without active budgets, retaining each optional cleanup error in the report.
`take_report()` is available once quiescent; it transfers the report and also
releases scheduler metadata, so no Destroy bounds are needed for this path.
`destroy()` requires both error Destroy bounds, aborts active owners and
explicitly discards untaken diagnostics. Its boolean reports owner release,
not successful native close. Call abort-all and take-report first when those
diagnostics matter. No listener close occurs on any path.

Service deadline and byte/work reservations are global. Each accepted socket
gets `min(service_deadline, accepted_at + connection_timeout)`, unchanged by
later phases or retries. Known Linux pending-connection errors and
ECONNABORTED spend one accept attempt and yield; no acquired descriptor means
no acceptance ordinal. Other listener failures stop admission. This follows
the [Linux accept error contract](https://man7.org/linux/man-pages/man2/accept.2.html).

## Executable evidence and remaining scope

The separate interface receipts are
`target/stdlib-work/server-poll-public-admission-first.log` and
`target/stdlib-work/server-poll-public-admission-native-first.log`. Both
returned zero with empty output and a validated x86_64 ELF. They establish
the imported public boundary, nested owned E/A, handler-local response copying
and manual report transfer/disposal. They predate the persistent engine.

Seven actual persistent-owner controls have also passed in two separate
compile/native groups on Linux x86_64:

| Receipt under `target/stdlib-work/` | Native cases | Whole group |
| --- | ---: | ---: |
| `server-poll-fatal-preparation-visibility-retry.log` | 3 | 15.58 s |
| `server-poll-publication-refill-reservations-first.log` | 4 | 14.62 s |

The first group retains fatal response-stage WorkLimit followed by handler
Ok(Abort) as InvalidDecision(ResponseFailure), including the original
preparation diagnostic. Ordinary Abort and recoverable unsupported-status
preflight followed by Abort remain Aborted. These cases execute actual
new/step/prepare_wait/resume/take/take_report/destruction, Pending-transfer
rejection, released reservations and inactive-owner behavior.

The second group executes nonempty one-shot readiness publication, cheap
invalid epoch/length rejection, superseding epochs, one-time advisory-readiness
consumption and mutation invalidation. A scripted local Timeout in before_wait
retires its owner and returns immediate work before the queued socket is
admitted. Separate capacity cases check that a single byte reservation reduces
configured concurrency two to one, and that consumed cumulative work is not
refunded after retirement: global WorkLimit leaves the queued fd unaccepted
while retaining the original local Timeout outcome.

Both groups use the real Server and Protocol with scripted test Drivers and
actual accepted loopback TCP sockets. Three and six accepted peers,
respectively, observe actual EOF. Before acknowledging process exit, the
independent harness checks `/proc` descriptors and source mmap/munmap plus
socket/close ownership; the completed trace must balance too. These unlinked
ELFs contain no CRT/OpenSSL heap mixed into the source allocation ledger.
The retained executables are `/tmp/server_poll_native_201688_0` and
`/tmp/server_poll_publication_native_206274_0`.

The preparation group's first invocation stopped before native execution in
4.35 seconds with LNC0021: fixture implementations of imported public traits
had private visibility. Correcting those declarations left the assertions and
production implementation unchanged. The failed receipt is
`target/stdlib-work/server-poll-fatal-preparation-first.log`; it is not a
scheduler runtime failure.

These seven finite controls establish no HTTP wire transfer or TLS behavior.
They script advisory readiness and local Timeout rather than establish genuine
deadline expiration. Their scope excludes all quota/error boundaries and an
allocation-failure campaign. Real wire behavior has the separate application
receipts below. Other targets and user GPU execution remain unverified.
See the [fixture guide](../tests/fixtures/extended/server_poll/README.md) for
the exact control scope.

### Concrete empty helpers without a destructor bound

`server-poll-nondestroy-runtime-first.log` passes the separate concrete-facade
control in 21.84 seconds. Both plain and TLS `serve_until` return typed empty
reports with a custom ManualError lacking Destroy. The control explicitly
releases real empty report capacity through its public outcomes Vec, preserves
the caller-owned listener/context, invokes no handler and performs no service
accept or poll. It releases its actual OpenSSL context and other owners before
return. This is empty-run API generality, not nonempty error-path ownership or
TLS transfer. See the [control guide](../tests/fixtures/stdlib_compiler_state/server_poll_nondestroy_admission/README.md).

### Actual applications and separate scale observations

The real programs execute the concrete adapters and the same generic
`serve_until`/`poll_once` path. Four separate causal cases pass: held plain
request head and held TLS handshake with queued refill, plus plain/TLS held
response readers. Both reader cases transfer complete 4 MiB binary bodies
and require real output EAGAIN before a healthy sibling finishes. Every case
enforces two active owners/three socket owners, acceptance-order reports and
explicit EOF; TLS 1.3 cases also require authenticated closure. The exact
receipts and finite schedules are in the [concurrency fixture guide](../tests/fixtures/extended/server_concurrency/README.md#status).

The [HTTPS application guide](extended-https-server.md#current-application-receipts)
separately records 102 current HTTPS service cases (30 matrix, 23 failure,
49 limits) and 101 affected mutual-TLS application cases (35/34/32). The latter
pair the previously accepted fetch executable with the current server. These
receipts cover their stated protocol/policy/budget behavior and do not replace
generic scheduler error-ownership or allocation-failure controls.

The separate [scale observations](../tests/fixtures/extended/server_concurrency/README.md#separate-scale-observation)
pass 64 echo connections per mode, eight-client demand, 65,536-byte bodies and
all acceptance-order reports. Actual active/socket peaks are four/five. Source
allocation observations are 1,224 allocations and 1,165,325 peak live requested
bytes for plain, and 1,419/1,352,377 for TLS; traced times are 3.346761/4.226492
seconds in `http-serve-concurrent-scale-first.log` and
`https-serve-concurrent-scale-first.log`. These timings include native startup,
peer/network/handshake/closure work and tracing; compilation, credential setup,
executable-site validation and final trace audit are excluded. Native/OpenSSL
heaps, RSS and the separate bootstrap mapping are outside the source ledger.
These observations establish no throughput target or compiler speed comparison.

### Owned scheduler errors

`server-poll-owned-errors-current.log` passes three finite actual-Server
profiles in 13.60 seconds: owned nested E from Factory.begin and Driver.step,
and owned A plus a separate abort E. Errors originate in the scheduler, survive
the specified live take/report transfer or destruction paths, and retain
their independent cleanup authority. Healthy siblings continue; all six
accepted peers observe actual EOF and source/native owners balance before
exit. Response acknowledgements and HTTP input are scripted driver actions,
and the abort error is scripted after a successful close. This is ownership
and sibling-progress evidence, not native wire or close-fault acceptance.
See the [ownership control guide](../tests/fixtures/extended/server_poll_ownership/README.md).

### Active-owner caps and cancellation

`server-poll-active-limits-api-retry.log` passes seven additional profiles in
13.42 seconds: operations, wait permits, handler calls and accept attempts
exhaust while owners are live; stop-accepting drains held owners without
admitting a queued peer; abort-all and active destroy retire owners
idempotently. Exact first causes, report order, released reservations and
mandatory cleanup remain visible. Thirteen accepted peers observe real EOF;
the stop case also consumes two genuine positive-capacity server EOF reads.
Independent source-map/native-fd ledgers balance before process exit and after
completion. See the [control guide](../tests/fixtures/extended/server_poll_limits/README.md).

Its first invocation stopped at fixture type checking (LNC0027, missing Stage
argument to Protocol.before_io) in 4.12 seconds. No native case ran in
`server-poll-active-limits-first.log`. Correcting that call preserved the
behavioral assertions; the accepted retry establishes their finite scope.

Together the earlier seven owner/publication profiles, three owned-error
profiles and seven cap/cancellation profiles are seventeen scripted scheduler
profiles across separate receipts.

### Reached native poll interruption and failure

Two additional native fault profiles pass in
`server-poll-marked-poll-faults-format-retry.log`, with exact summary
`server-poll-faults cases=2 calibration=1`. This group uses the actual plain
Factory/Exchange, not a scripted Driver. A successful warm readable poll and
partial-head read are consumed before real EAGAIN. The oracle then binds
binary markers, the live accepted fd, request set and baseline-derived native
poll ordinal to the injected call; drift or an unreached fault fails.

EINTR charges one physical call and wait permit without replaying old PollSet
readability. A step without hints performs no receive, a fresh publication
rejects the old epoch, and zero hints still do no receive. A fresh native poll
then observes EOF and allows the ordinary partial-request rejection to retire.
EIO preserves Poll(Io(Host(5))) as the shared first cause, retires the live
owner and backing, and leaves an ordered abort with its confirmed prefix.
Repeated failure observation performs no extra poll; listener ownership stays
with the caller. Each baseline/fault process separately balances source maps,
native fds and closes before exit and in the final trace.

The successful Python-only retry reused
`/tmp/server_poll_faults_native_249145_0` without GPU recompilation. The first
invocation, `server-poll-marked-poll-faults-first.log` (15.03 seconds), ran the
native assertions but failed an oracle assumption about spacing in strace's
successful close line. Parsing the exact fd/success/one-close marker frame
removed that formatting assumption without changing production or Lanius
source. The baseline is calibration, separate from the two fault profiles;
none is added to the seventeen scripted-profile count. See the
[poll-fault control guide](../tests/fixtures/extended/server_poll_limits/README.md#additive-reached-poll-faults).

Reached allocation failures, wider injected
host faults, broader plain application resource campaigns and the remaining
transport-specific teardown gates remain pending. Existing direct-driver and
historical sequential receipts keep their own stated scope.
