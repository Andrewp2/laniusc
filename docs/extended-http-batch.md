# Bounded concurrent HTTP exchanges

`ext::http_batch` schedules independent HTTP exchanges using one thread and one
reusable `std::poll::PollSet`. Canonical request preparation always uses
`ext::http_client::Prepared`; a typed factory supplies the transport driver.
The plain entry uses the existing HTTP `Exchange`. Both entries use one
preparation, admission, refill, polling, accounting and cleanup engine. The
scheduler contains no TLS implementation or worker-thread pool.

The source is [`extended/ext/http_batch.lani`](../extended/ext/http_batch.lani).
The plain profile is native Linux x86_64 through the existing socket/poll
boundary. All eight focused plain library groups pass on the current generic
driver/error revision through the two receipts below. The eighth group covers
a slot freed by `before_wait` failure. The [verified HTTPS adapter](extended-https-batch.md)
and [fetch-many application](extended-fetch-many.md) have separate current
acceptance records. Other targets,
user GPU execution, name resolution, redirects, pooling and request replay
remain outside this profile. The [single-exchange guide](extended-http-client.md)
defines HTTP policy, including successful responses with non-2xx status.

## API and limits

```lanius
pub struct Job { endpoint: SocketAddr, request: http_client::Request }
pub struct Limits {
    max_jobs: i32, concurrency: i32,
    max_pending_bytes: u64, max_wire_bytes: u64, max_body_bytes: u64,
    operations: u64, work: u64
}
pub fn default_limits() -> Limits;
pub fn run_until(jobs: View<Job>, options: http_client::Options,
    limits: Limits, deadline: Deadline)
    -> Result<Report<http_client::Failure>,Failure<http_client::Failure>>;
pub fn run_with_until<J,D,E,F>(jobs: View<J>, factory: &F,
    options: http_client::Options, limits: Limits, deadline: Deadline)
    -> Result<Report<E>,Failure<E>>
    where D: Driver<E>, F: Factory<J,D,E>;
```

The abbreviations above refer to `core::net::SocketAddr`, `core::slice::View`,
`core::time::Deadline`, `core::result::Result`, and `ext::http_client`.
One shared client `Options` value supplies each exchange's wire, request,
response, informational-response, I/O and protocol-work limits.

| Batch limit | Default | Meaning |
| --- | ---: | --- |
| `max_jobs` | 64 | Bounds submitted, queued and input-indexed result records; valid range 1..4,096. |
| `concurrency` | 4 | Bounds active driver owners; valid range 1..64 and at most `max_jobs`. |
| `max_pending_bytes` | 64 MiB | Logical encoded request plus copied method bytes held by pending Prepared owners. |
| `max_wire_bytes` | 64 MiB | Logical wire bytes retained in completed Response owners. |
| `max_body_bytes` | 64 MiB | Decoded body bytes retained in completed Response owners. |
| `operations` | 1,048,576 | Abstract scheduler-operation allowance. |
| `work` | 4,294,967,296 | Aggregate charged client protocol-work allowance, protected by conservative reservations. |

The five unsigned limits may be zero. A nonempty batch with exhausted
operations fails before the next charged action. Logical byte caps and work
can reject a batch without opening a socket. An empty valid job view returns
an empty successful Report without allocation, clock or poll calls, including
under zero unsigned limits. Invalid limits or malformed/overflowing job view
metadata still fail locally. Physical view backing is a caller precondition.

## Typed factory and driver contract

```lanius
pub trait Driver<E> {
    pub fn stats(&self) -> http_client::Stats;
    pub fn interest(&self) -> http_client::Interest;
    pub fn raw_handle(&self) -> Option<i32>;
    pub fn before_wait(&self) -> Result<bool,E>;
    pub fn step(&self, ready: http_client::Readiness)
        -> Result<Option<http_client::Response>,E>;
    pub fn abort(&self) -> Result<bool,E>;
}
pub trait Factory<J,D,E> {
    pub fn request(&self, job: J) -> http_client::Request;
    pub fn begin(&self, prepared: &http_client::Prepared, job: J) -> Result<D,E>;
    pub fn from_http_failure(&self, failure: http_client::Failure) -> E;
    pub fn failure_stats(&self, error: E) -> http_client::Stats;
    pub fn shared_failure(&self, error: E) -> Option<Cause>;
}
```

Job arguments are borrowed shallow descriptors. `request` projects a request
from unchanged caller backing; it does not consume the job, create a second
request owner, perform network effects or retain an owner outside the call.
The factory and all backing it borrows must remain valid through return.
Its hooks are bounded synchronous operations; the scheduler cannot preempt
arbitrary custom factory code.

`begin` consumes and disarms the actual Prepared on every result. It preserves
the prepared HTTP state, deadline and already charged work instead of running
another encoder. A successful driver owns exactly one transport/protocol
session. No active driver escapes the scheduler. The plain adapter is a
private wrapper around the existing `http_client::Exchange`, so forwarding
trait methods cannot recurse into themselves.

Driver statistics begin with the Prepared statistics, are monotone and retain
confirmed progress on errors. They remain readable after terminal calls.
Interest and readiness must agree: `before_wait` returning `Ok(false)` leaves
immediate work available to `step`. For `Ok(true)`, the driver must preserve
the preceding non-immediate `Interest` and its current descriptor identity
through poll registration. The scheduler reads `interest()` before the gate,
then uses those read/write flags with `raw_handle()` after it; the gate must
not silently change which event or session that request describes.
Protocol work cannot exceed the shared client `Options.work` allowance.
Drivers must preserve the common absolute deadline,
bounded nonblocking step/readiness contract and one-time Response transfer.
`step` and `before_wait` errors must release and disarm the driver's transport
and protocol owners before returning. `abort` does the same on every result,
including an error that reports failed cleanup. A driver must not retain a
successful Response after transferring it.

Every returned `E` transfers its own error cleanup authority. Error statistics
and shared-failure classification receive borrowed copies: they must not
destroy, mutate or retain that authority. Errors must remain valid after the
failed driver's partial owners have been released. Borrowed error payloads
must keep their backing valid and unchanged through the error's final use
and destruction, whether it remains in a Report or Failure or transfers in a
taken Outcome. That lifetime can extend past `run_with_until` returning;
keeping factory/job backing alive only during the call is insufficient for
an error that still borrows it. `from_http_failure` keeps
canonical preparation failures typed; `shared_failure` identifies common
deadline/clock failures that terminate the whole batch. The scheduler never
reduces a driver error to an integer or parses transport-specific policy.

## Preparation and ownership

All canonical request preparation happens before the first socket is opened.
The scheduler prepares jobs in input order using the shared client's encoder,
method copy and framing cursor. No application or batch-specific request
encoder or parser runs in parallel with that source of truth.

Any preparation failure returns global `Cause::Preparation`, records the
failing input's `Outcome::Failed(factory.from_http_failure(client_failure))`, and leaves every other
outcome `NotStarted`. All previously prepared owners are destroyed and no
socket has been started. The nested failure retains the original allocation,
validation, protocol-work, clock or deadline reason. A global pending-cap,
work-reservation or scheduler failure during preparation likewise opens no
sockets, but is reported under its own batch cause.

All job and Request views borrow caller backing through the selected run
function's return.
Do not free, grow, mutate or destructively alias that backing during the call.
Each Prepared owner stages its request independently, but queued endpoints
and the input records remain borrowed. Custom factory/driver hooks run only
inside the synchronous call; no public persistent runner retains queued views.

Before preparation the batch allocates an input-indexed outcome vector and
pending vector, at most `min(concurrency, job_count)` active slots and poll
requests, and the PollSet's two buffers. These scheduler owners do not grow
after preparation starts. Engine request/response storage still allocates
under each exchange's existing contract.

After every preparation succeeds, admissions follow increasing input index.
The factory's `begin` transfers the prepared owner into its driver. The plain
factory opens one nonblocking socket and preserves preparation's charged work.
Begin, socket, HTTP and per-exchange
limit failures become `Outcome::Failed` and valid siblings continue. A common
clock/deadline failure from an active exchange also terminates the batch;
that exchange keeps its detailed Failed outcome and other active jobs abort.

## Input-order outcomes and transfer

```lanius
pub struct Abort<E> { stats: http_client::Stats, cleanup: Option<E> }
pub enum Outcome<E> {
    NotStarted, Complete(http_client::Response), Failed(E),
    Aborted(Abort<E>), Discarded(http_client::Stats), Taken
}
pub struct Report<E> { outcomes: alloc::vec::Vec<Outcome<E>>, stats: Stats }
pub struct Failure<E> { cause: Cause, report: Report<E> }
```

`Report.borrow`, `len`, `get(index)`, `take(index)` and `destroy` operate on the
one active report owner. `get` returns `Option<Outcome<E>>` as a shallow borrowed
descriptor. `take` returns an owning `Option<Outcome<E>>` and installs `Taken`
before exposing it; an out-of-range or already-taken index returns `None`.
`Report.destroy` and `Failure.destroy` require `E: core::clone::Destroy<E>`.
They destroy each remaining Complete response, each Failed error, and each
Aborted cleanup error before releasing the outcome storage. Length resets to
zero; historical numeric Stats remain. Constructors, execution, borrow, get
and take do not require this bound. The plain HTTP failure's Destroy is an
explicit no-op because its diagnostic fields own no allocation or handle.

Do not destroy an owner copied from `get`, mutate its vectors, or create a
second cleanup authority from a by-value Report/Failure copy. Transfer an
outcome with `take` when it must survive report destruction. Taking Failed or
Aborted transfers the contained `E` cleanup authority as well. A transferred
Complete response owns its wire, method, decoded body and informational heads;
its views remain valid until that response is destroyed. No request, pending,
active-socket or poll owner escapes on either result.

After outcome initialization, `Report.len()` equals the input count and
indices remain stable regardless of completion order. An early validation,
operation or outcome-allocation failure can return an empty report instead;
its `stats.jobs` still records the logically valid requested count. A
successful nonempty run contains only Complete or Failed outcomes until the
caller transfers any. A valid HTTP 404/500 is a Complete response; application
status policy is separate.

On a global failure, completed responses remain owned by the returned report.
Every active driver is aborted once and recorded with its confirmed client
Stats and the actual optional typed abort error; pending owners are destroyed and leave
NotStarted outcomes. Every active cleanup is attempted even after a prior
close fails or the work/deadline/operation allowance expires. Close is one
attempt under the socket owner contract; a faulty native close return does
not prove the kernel released that descriptor.

### Plain caller types

Plain callers use `Report<http_client::Failure>`,
`Outcome<http_client::Failure>` and `Failure<http_client::Failure>` in explicit
annotations. `Abort.cleanup` now carries the complete HTTP failure rather
than an extracted `io::Error`; callers can inspect its primary cause, stage,
statistics and secondary cleanup field. This preserves the same typed error
path used by other drivers. It does not create a second plain scheduler or a
compatibility alias.

## Fair scheduling and readiness

Each sweep starts at a rotating slot and performs at most one bounded
driver `step` per active owner. The plain HTTP engine step performs one bounded phase
action with at most one network leaf. A cursor-boundary action also includes
canonical validation; decoding can rebuild all configured-cap informational
heads. Sends/receives offer at most 1,024 bytes. This is cooperative fairness,
not time preemption of parsing, allocation, host calls or kernel scheduling.

After a sweep frees a slot, admission runs again before a potentially blocking
poll. Failed begins consume their input and permit the next queued job to be
considered. This refill repeats only while it makes input progress; a credit
shortage with active owners stops refill and waits for those owners to release
allowance. No queue-only busy-poll rule bypasses the work reservation.

A local error from `before_wait` can also free a slot after that refill.
The wait pass then returns immediately to the outer admission loop before
polling remaining siblings. It retains the failed input's typed error and
releases its unused work credit. A shared error still terminates the batch.
Previously charged participation allowances remain in the historical I/O
count even when that pass returns without a physical poll.

Immediate engine work is stepped without waiting for readiness. Pending peers
register their current descriptor and read/write interest. If another owner
still has immediate work, one zero-time shared poll probes those pending
peers, so an always-progressing upload cannot prevent other peers' readiness
from being observed. With no immediate work, the shared poll uses the common
deadline's remaining interval, rounded up and capped at `i32::MAX` milliseconds.

Each `poll_ms` makes one physical poll attempt. EINTR spends the attempt and
returns to the same deadline/budget loop. Failed polls never consume the
PollSet's previous publication. Request records and ready hints are rebuilt
for each round; replacing a slot clears its old descriptor/readiness identity.
Error, hangup and read-closed notifications drive the same canonical exchange
state machine. Readiness is advisory and does not grant permission to use
blocking socket calls.

## Work, operation and storage accounting

Before each preparation, the batch reserves the client's whole configured
protocol-work allowance. It then adds the client's reported charged work and
releases the unused reservation. Before admitting a Prepared owner, it
reserves only that owner's remaining allowance. Stats cross Prepared.begin
continuously; only monotone work/I/O deltas are added. The invariant is:

```text
reported aggregate protocol work + active unused work reservations <= limits.work
```

Terminal completion/failure releases only unused credit; charged work never
decreases. Credit shortage can delay further admission while active jobs
release reservations. If no owner is active and the next job cannot reserve
its remaining allowance, the batch returns WorkLimit rather than spinning.
This conservative policy can refuse a job whose eventual real work would fit.
Choose a per-job client work allowance smaller than the batch allowance when
multiple active exchanges are desired; setting the two equal can serialize
admission. These are charged protocol allowances, not CPU instructions.

`operations` separately precharges scheduler work: each global clock read,
allocating metadata constructor/reservation and initialized entry, slot scan,
poll-request/readiness visit, preparation, begin, step, `before_wait` and shared
poll attempt. Full-width scan/initialization charges can be reserved before an
early failure. Engine-internal clocks and protocol work follow the client
contract rather than becoming literal scheduler operations. Mandatory owner
cleanup and result destruction are outside the active allowance and are not
skipped on exhaustion.

`Stats.polls` counts actual physical shared poll attempts, including EINTR.
`Stats.io_calls` sums the client's charged network allowances and precharged
`before_wait` participation. Several participants can share one physical poll.
A later owner/global failure can prevent a poll after earlier participants
were charged, so these reservations may be unused. Mandatory cleanup close
is excluded. Neither counter should be presented as an exact total OS syscall
count in all failure cases.

Pending bytes count accepted Prepared request lengths plus copied method
lengths; `pending_bytes` is current and is zero at return, while
`peak_pending_bytes` records the maximum admitted sum. The one bounded
preparation candidate, vector capacities, encoder temporaries, inline metadata
and caller backing are excluded from this logical cap.

Completed wire bytes use the whole `Response.wire.len()`, including retained
informational prefixes. Final-message `as_view()` would undercount this.
Body bytes use `Response.decoded.len()`. Observed receive counts can include
discarded tail/overflow-probe bytes and are not these retention metrics.
Before retaining a candidate response, both remaining caps are checked. An
over-cap candidate is destroyed, its input records `Discarded(stats)`, active
siblings abort and previously retained responses remain available in Failure.
WireLimit takes precedence when both caps are exceeded.

These caps do not claim a total received-byte, allocator-requested-storage,
peak-RSS or native memory quota. Pending/completed metadata and method copies
are separately finite under job count and per-exchange caps; active request,
wire, decoded, informational and temporary storage are bounded by concurrency
and the client's configured limits. Peak storage can include a candidate
before its retention check. Destroying or taking results does not rewrite the
report's historical completed byte totals.

A custom driver's native-library storage and transport work are outside these
HTTP logical byte and protocol-work counters. The adapter must document and
enforce its own transport allowances. Scheduler operations charge calls to
factory/driver hooks, not every operation performed inside them; the same
bounded-step and owner-cleanup contracts remain required.

## Errors and common deadline

```lanius
pub enum Cause {
    Bounds, InvalidLimits, AllocationFailed, Timeout, Clock(std::clock::Error),
    Poll(std::poll::Error), OperationLimit, WorkLimit, WireLimit, BodyLimit,
    PendingLimit, Preparation, InvalidEngine
}
```

Scheduler and PollSet-construction allocation failures use AllocationFailed.
Preparation and post-admission client failures retain their nested allocation
cause in the Failed outcome instead. InvalidEngine identifies an inconsistent
engine state, descriptor or monotone accounting result; physical owner
validity remains a manual precondition.

The common deadline is an absolute normalized CLOCK_MONOTONIC value. All
preparations and exchanges retain it; retries and new admissions never reset
it. Scheduler clock reads reject reversal and observed expiry. Poll results
are checked against a later clock observation before readiness is used.
Already retained outcomes survive global expiry. Scheduling, fixed cleanup,
bounded local actions and blocking host completion can overrun the timestamp;
there is no hard real-time return or asynchronous cancellation guarantee.

## Verification status

### Current generic revision

The separate [production-shaped admission control](../tests/fixtures/stdlib_compiler_state/resumable_transport_admission/REPRODUCTION.md)
compiled to an x86_64 executable and exited zero. It dispatches the actual
public `Driver` and `Factory` traits with two error types, including nested
owned payloads, and executes the actual `Report<E>` take/destruction path.
Its receipts are `target/stdlib-work/resumable-transport-production-shape-first.log`
and `resumable-transport-production-shape-native.log`. Its fixture runner does
**not** call `run_with_until`; this is interface and owner admission evidence,
not scheduler, networking or TLS acceptance.

All eight focused plain batch groups pass against the shared HTTP Protocol,
generic driver/error engine and wait-retirement correction through two
separate invocations, covering 103 reported cases:

| Invocation | Accepted finite scope | Elapsed | Receipt under `target/stdlib-work/` |
| --- | --- | ---: | --- |
| Seven original groups on current sources | 102 cases: overlap/fairness 5; framing/mixed failures 10; native faults 14; preparation/ownership 16; limits/cancellation 18; consecutive failed begins 1; allocation baseline/recovery/faults 38, including all 36 reached failure positions and ten after networking began | 13.00 s | `http-batch-shared-protocol-generic-regressions-first.log` |
| New wait-retirement regression | One causal local `before_wait` failure with a held sibling, queued dependency and cleanup checked before process exit | 10.07 s | `http-batch-wait-retirement-coherent-limits-retry.log` |

These receipts accept the exercised plain adapter and scheduler paths; they
do not claim one combined eight-group invocation, every possible driver/error
type, native fault schedule or allocation history. Current application
integration acceptance remains separate from these library groups.

The [connected HTTPS guide](extended-https-batch.md#execution-receipts) records
all six current groups and 108 cases through three accepted receipts. Those
consumers exercise the actual generic scheduler through `ext::https_batch`.
The [OpenSSL TLS guide](extended-openssl-tls.md#current-duplex-and-ownership-receipts)
separately records all nine raw duplex groups and 36 cases. The dedicated
guides define each gate's scope, corrections and native profile; raw transport
controls remain separate from scheduler acceptance.

Static review found a second real refill defect: a local `before_wait` error
retired an owner, but the same wait pass could block on another peer before
admitting queued work. A sibling waiting for a queued job could then stall
until the common deadline. The source now returns to admission immediately
after that local retirement. The focused causal regression below accepts this
path separately from the interface control and historical receipts.

### Wait-retirement regression

The [focused regression](../tests/fixtures/extended/http_batch_wait_retirement/README.md)
passes one case in 10.07 seconds in
`target/stdlib-work/http-batch-wait-retirement-coherent-limits-retry.log`.
It calls the actual generic scheduler with a test driver wrapping real HTTP
Exchanges. With concurrency two, job 0 has fully uploaded and is read-pending
without immediate work. Job 1 then releases its Exchange and returns one
terminal, nonshared typed `Io(Host(9001))` error from `before_wait`. Queued
job 2 must start and complete before job 0's peer releases its response.

The peer dependencies require job 1's full request and actual connection EOF
before job 2's response, then job 2's actual EOF before job 0's response.
Outcomes remain Complete, Failed, Complete in input order. The syscall trace
checks at most two sockets and rejects positive or infinite polling between
retirement and the third socket admission, even if a spurious event would
make that poll return immediately. The resource ledger and `/proc` descriptor
check run after explicit destruction and before the exit acknowledgement;
the final trace checks cleanup again. This is one finite driver-failure
schedule, not a native syscall fault or arbitrary interleaving claim.

The first gate failed before publishing a report because the fixture's
one-million-work allowance retained the HTTP defaults of 65,536 head bytes
and 100 trailers. Final validation alone reserves
`4 * 65536 * (100 + 1) = 26476544` work, before response-byte charges. Both
intended successes therefore returned local WorkLimit errors; the unchanged
aggregate outcome assertion trapped. The diagnostic receipt is
`target/stdlib-work/http-batch-wait-retirement-first-diagnostics.log`.
The fixture now supplies explicit head, line, header, trailer and trailer-byte
bounds that fit its allowance. Production accounting, causal dependencies,
success assertions and the resource oracle did not change for this retry.

### Historical concrete plain scheduler

The [focused testing guide](extended-http-batch-testing.md) records the seven
earlier finite groups and their ownership/fault machinery. The following
receipts cover the concrete plain scheduler before its generic driver/error
revision and the later wait-retirement correction. They do not establish the
current source's full acceptance. All seven earlier groups were accepted
through four separate receipts:

| Invocation | Accepted scope | Elapsed | Receipt under `target/stdlib-work/` |
| --- | --- | ---: | --- |
| Initial contracts | 16 contract cases | 9.84 s | `http-batch-contracts-first.log` |
| Mixed remaining-groups run | Framing/mixed: 10 cases; native faults: 14; all 36 observed allocation-failure points across 38 processes, including ten points after networking began | 13.79 s | `http-batch-remaining-groups-first.log` |
| Focused scheduler retry | Overlap/fairness: 5 cases; limits/cancellation: 18; unchanged tests on the corrected source | 9.62 s | `http-batch-refill-two-groups-retry.log` |
| Consecutive failed begins | One causal held-sibling regression with two exact socket EIO injections | 8.54 s | `http-batch-consecutive-begin-failures.log` |

The mixed invocation's overlap and limits groups failed for a real scheduler
defect: a completed slot was not refilled before blocking on a held sibling,
so queued work could stall until the deadline. The production source now
refills before blocking while preserving the work-credit guard. The original
causal tests and their expectations are unchanged, and both groups pass the
focused retry. This was a product correction, not a harness-only adjustment.
These receipts do not establish one combined passing suite run.

The additional regression proves that refill advances past consecutive failed
begins while a sibling is held. With concurrency two, input zero holds one
slot and input one completes in the other. Socket creation attempts three and
four fail with activated, exact EIO injections; input four must then finish
before the held input zero is released. The trace verifies exactly those two
injection ordinals, results, instruction address and arguments, a successful
sibling close before the failed begins, and no positive or indefinite poll
between the failed prefix and the fifth socket attempt. Outcomes remain in
input order with three Complete and two Failed entries, at most two live
sockets, and complete resource cleanup. This tests causal progress and exact
fault activation rather than a timing threshold.

The focused tests use independent local HTTP peers to require overlapping
requests before responses are released, vary response order and keep a slow
early job from blocking later progress. They check input-order outcomes, concurrency bounds,
mixed protocol failures, retained success after global cancellation, logical
byte/work/operation boundaries, stable partial I/O, every reached allocation
failure, and exact mapping/descriptor cleanup. Take/disarm tests inspect a
transferred response after report destruction. No production implementation
is supplied by the test peers or their reference codecs.

### Application acceptance

The [fetch-many guide](extended-fetch-many.md) records all five current
application groups passing against the shared HTTP Protocol and generic batch
engine in 24.18 seconds. The receipt is
`target/stdlib-work/fetch-many-generic-batch-current-regressions-first.log`:
matrix 16 cases, failures 31, limits 66, resources 61 including all 59 reached
allocation-failure positions, and real I/O 19. One scripted consumer checks
38 internal scenarios using the production input/publication helpers. The
resource group also executes the bounded 64-job program. These gates exercise
CSV admission, concurrent HTTP and staged ZIP output together.

The following earlier receipts predate the generic scheduler revision. They
retain the original application acceptance history and do not replace the
current-source receipt above:

| Receipt under `target/stdlib-work/` | Accepted final scope | Elapsed |
| --- | --- | ---: |
| `fetch-many-failures-limits-io-first.log` | Limits: 66 cases; real I/O: 19; production stream helpers: 38 internal scenarios | 18.81 s |
| `fetch-many-matrix-failures-resources-final.log` | Matrix: 16; expanded failures: 31; resources: 61, including all 59 reached allocation-failure positions | 15.63 s |

These are separate receipts, with finite input, schedule and single-fault
coverage. The application guide preserves its HTTP fixture correction and
defines status policy, output publication and resource measurements. Neither
these gates nor the library gates establish another platform, exhaustive
allocation/interleaving coverage, a hard completion deadline or a peak-RSS
quota.
