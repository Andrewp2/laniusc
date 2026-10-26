# Bounded concurrent HTTP exchanges

`ext::http_batch` schedules independent cleartext HTTP/1 exchanges over numeric
socket endpoints using one thread and one reusable `std::poll::PollSet`. It
reuses `ext::http_client::Prepared` and `Exchange` for request encoding, socket
progress, framing, validation, decoding and close behavior. There is no second
HTTP engine, TLS implementation or worker-thread pool.

The source is [`extended/ext/http_batch.lani`](../extended/ext/http_batch.lani).
The first profile is native Linux x86_64 through the existing socket/poll
boundary. All seven focused library groups pass GPU compilation and
native execution through separate receipts, including the scheduler correction
and consecutive-failed-begin regression described below. The
[fetch-many application](extended-fetch-many.md) also passes all five groups
through separate receipts. Other targets, user GPU execution,
TLS, name resolution, redirects, pooling and request replay are outside this
profile. The [single-exchange guide](extended-http-client.md) defines the
underlying HTTP policy, including successful responses with non-2xx status.

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
    limits: Limits, deadline: Deadline) -> Result<Report,Failure>;
```

The abbreviations above refer to `core::net::SocketAddr`, `core::slice::View`,
`core::time::Deadline`, `core::result::Result`, and `ext::http_client`.
One shared client `Options` value supplies each exchange's wire, request,
response, informational-response, I/O and protocol-work limits.

| Batch limit | Default | Meaning |
| --- | ---: | --- |
| `max_jobs` | 64 | Bounds submitted, queued and input-indexed result records; valid range 1..4,096. |
| `concurrency` | 4 | Bounds active Exchange owners; valid range 1..64 and at most `max_jobs`. |
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

## Preparation and ownership

All canonical request preparation happens before the first socket is opened.
The scheduler prepares jobs in input order using the shared client's encoder,
method copy and framing cursor. No application or batch-specific request
encoder or parser runs in parallel with that source of truth.

Any preparation failure returns global `Cause::Preparation`, records the
failing input's `Outcome::Failed(client_failure)`, and leaves every other
outcome `NotStarted`. All previously prepared owners are destroyed and no
socket has been started. The nested failure retains the original allocation,
validation, protocol-work, clock or deadline reason. A global pending-cap,
work-reservation or scheduler failure during preparation likewise opens no
sockets, but is reported under its own batch cause.

All job and Request views borrow caller backing through `run_until`'s return.
Do not free, grow, mutate or destructively alias that backing during the call.
Each Prepared owner stages its request independently, but queued endpoints
and the input records remain borrowed. There are no user callbacks or public
persistent runner whose queued views can outlive this call.

Before preparation the batch allocates an input-indexed outcome vector and
pending vector, at most `min(concurrency, job_count)` active slots and poll
requests, and the PollSet's two buffers. These scheduler owners do not grow
after preparation starts. Engine request/response storage still allocates
under each exchange's existing contract.

After every preparation succeeds, admissions follow increasing input index.
`Prepared.begin` transfers its actual owner, opens one nonblocking socket and
preserves the preparation's charged work. Begin, socket, HTTP and per-exchange
limit failures become `Outcome::Failed` and valid siblings continue. A common
clock/deadline failure from an active exchange also terminates the batch;
that exchange keeps its detailed Failed outcome and other active jobs abort.

## Input-order outcomes and transfer

```lanius
pub struct Abort { stats: http_client::Stats, cleanup: Option<io::Error> }
pub enum Outcome {
    NotStarted, Complete(http_client::Response), Failed(http_client::Failure),
    Aborted(Abort), Discarded(http_client::Stats), Taken
}
pub struct Report { outcomes: alloc::vec::Vec<Outcome>, stats: Stats }
pub struct Failure { cause: Cause, report: Report }
```

`Report.borrow`, `len`, `get(index)`, `take(index)` and `destroy` operate on the
one active report owner. `get` returns `Option<Outcome>` as a shallow borrowed
descriptor. `take` returns an owning `Option<Outcome>` and installs `Taken`
before exposing it; an out-of-range or already-taken index returns `None`.
`destroy` destroys every remaining Complete response and the outcome storage;
it resets length to zero and preserves the historical numeric Stats.
`Failure.borrow` and `Failure.destroy` provide the corresponding owner helpers.

Do not destroy an owner copied from `get`, mutate its vectors, or create a
second cleanup authority from a by-value Report/Failure copy. Transfer an
outcome with `take` when it must survive report destruction. A transferred
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
Every active exchange is aborted once and recorded with its confirmed client
Stats and optional close error; pending owners are destroyed and leave
NotStarted outcomes. Every active cleanup is attempted even after a prior
close fails or the work/deadline/operation allowance expires. Close is one
attempt under the socket owner contract; a faulty native close return does
not prove the kernel released that descriptor.

## Fair scheduling and readiness

Each sweep starts at a rotating slot and performs at most one bounded
`Exchange.step` per active owner. Each engine step performs one bounded phase
action with at most one network leaf. A cursor-boundary action also includes
canonical validation; decoding can rebuild all configured-cap informational
heads. Sends/receives offer at most 1,024 bytes. This is cooperative fairness,
not time preemption of parsing, allocation, host calls or kernel scheduling.

After a sweep frees a slot, admission runs again before a potentially blocking
poll. Failed begins consume their input and permit the next queued job to be
considered. This refill repeats only while it makes input progress; a credit
shortage with active owners stops refill and waits for those owners to release
allowance. No queue-only busy-poll rule bypasses the work reservation.

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

The [focused testing guide](extended-http-batch-testing.md) records the seven
finite groups and their ownership/fault machinery. All seven groups are
accepted through four separate receipts:

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

The [fetch-many guide](extended-fetch-many.md) records all five accepted
application groups on the same native Linux x86_64 profile. It composes the
batch with CSV admission and staged ZIP output:

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
