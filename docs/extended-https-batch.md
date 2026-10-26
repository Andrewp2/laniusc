# Bounded verified HTTPS batches

`ext::https_batch` supplies verified TLS exchanges to the
[generic HTTP batch scheduler](extended-http-batch.md). One scheduler owns
request preparation, admission, refill, shared polling, accounting and result
cleanup. Each active [HTTPS Exchange](extended-https-client.md) drives the
same transport-free HTTP Protocol used by the plain client. There is no
second scheduler, HTTP codec or cryptographic implementation.

The source is [`extended/ext/https_batch.lani`](../extended/ext/https_batch.lani).
The native profile is Linux x86_64/glibc with OpenSSL 3 `libssl` and
`libcrypto`. **All six focused connected groups pass 108 cases across three
separate invocations.**
Earlier concrete HTTP batch, TLS and HTTPS application receipts do not
establish this generic scheduler or HTTPS adapter. The
[connected testing guide](extended-https-batch-testing.md) defines the finite
executable scope. User GPU execution and other platforms are unverified.

The production-shaped public generic trait/Report control compiles and exits
zero with two error types, including nested owned errors. It does not execute
the scheduler. All nine raw OpenSSL duplex groups pass 36 cases through
separate receipts, including the source-allocation gate. Selected native
client/server/mutual-TLS retry guards separately pass ten cases; these are
not complete reruns of all earlier TLS suites. Those lower-layer
controls are separate from the connected HTTPS results below. The migrated
[HTTPS fetch program](extended-https-fetch.md) has two receipts accepting all
four application groups and 63 cases, including empty-body zero allowances and
an exact 1 MiB binary response. Affected
[mutual-TLS application modes](extended-https-mutual-tls.md) pass three groups
and 101 cases, excluding prepared-context streams. Revised plain client and
batch regressions also pass, with their own scopes and receipts.
The current [fetch-many CSV-to-ZIP program](extended-fetch-many.md) passes all
five integration groups in 24.18 seconds, including 59 reached allocation
failures and a four-socket cap during its 64-job control. Historical full
native TLS matrices and excluded buffered/prepared-context groups retain their
older receipt scope; these selected current tests do not rerun them.

The separate generic-driver wait-retirement regression compiled but first
failed before its report with premature protocol EOF. Review classified its
fixture's work allowance as insufficient for default HTTP validation caps.
The corrected fixture passes unchanged behavioral assertions in its
10.07-second retry (`http-batch-wait-retirement-coherent-limits-retry.log`).
The complete current plain batch has eight accepted groups and 103 cases
across that receipt and a separate 13.00-second seven-group regression. The
[fixture record](../tests/fixtures/extended/http_batch_wait_retirement/README.md)
preserves the failed attempt, diagnostic evidence and budget correction.

## Public API

The abbreviated names refer to the corresponding `core` and `ext` modules.

```lanius
pub struct Job {
    endpoint: SocketAddr,
    identity: openssl_tls::Identity,
    request: http_client::Request,
}
pub fn run_until(
    jobs: View<Job>,
    context: &openssl_tls::Context,
    options: http_client::Options,
    tls: https_client::Options,
    limits: http_batch::Limits,
    deadline: Deadline,
) -> Result<http_batch::Report<https_client::Failure>,
            http_batch::Failure<https_client::Failure>>;
```

Create the shared verified client Context before the call, using explicit
trust and optional client credentials. Every job selects its numeric socket
endpoint, expected certificate DNS/IP identity and HTTP Host authority
independently. The adapter does not resolve names or enforce equality between
these three values. It provides no verification-disable option, redirects,
pooling, request replay, worker threads or application authorization.

`options`, `tls` and `limits` are shared configurations, not counters reset by
retries. The scheduler passes one absolute monotonic deadline to every
preparation and exchange. Use `http_client::Trailing::Reject` to reject
surplus plaintext already received after a framed response; this policy does
not wait for future traffic or peer EOF after a self-delimited response.

## Preparation, admission and peer policy

Every HTTP request is canonically encoded and prepared before the first
socket opens. A request failure returns batch `Cause::Preparation`; the
failing input records a typed HTTPS `Failure` with `Stage::Prepare` and
`Cause::Http(original_failure)`. Other inputs remain `NotStarted`, and all
prepared owners are released.

This all-request preparation rule does not preflight every TLS context,
identity or peer certificate. On each later admission, HTTPS begin consumes
the actual Prepared owner, validates TLS options and local identity policy,
retains a native Context reference, copies identity bytes and opens one
nonblocking socket. Native IP syntax admission happens when the Session is
attached after connection. Certificate-chain and identity verification happen
during the native handshake. An earlier valid sibling can therefore start
before a later job's identity, native setup or handshake fails. A valid empty
batch performs no Context or TLS-option admission.

The canonical [OpenSSL policy](extended-openssl-tls.md) requires verified
server trust and DNS/IP identity, with a minimum TLS version of 1.2.
Optional client credentials do not weaken server verification. Certificate
acceptance does not assign an application principal or authorize an HTTP
route. Establish an explicit process SIGPIPE policy before running the batch:
OpenSSL's socket BIO can raise SIGPIPE, and this API does not change signal
dispositions.

## Borrowing and result ownership

Keep the job view, its Request and identity backing, and the caller Context
valid and unchanged through `run_until`'s return. The scheduler holds shallow
job descriptors while queued. A begun HTTPS Exchange owns its copied HTTP
state and identity, its own native Context reference and its socket/Session.
The shared Context remains the caller's owner on every result. No active
Exchange escapes the call.

Results use the scheduler's typed
`Report<https_client::Failure>`, `Outcome<https_client::Failure>` and
`Failure<https_client::Failure>` directly. Input indices remain stable despite
completion order. A valid non-2xx HTTP response is `Outcome::Complete`; status
acceptance is application policy. TLS, socket, HTTP and per-job limit errors
normally become `Outcome::Failed`, while siblings continue. A nested common
HTTP timeout or clock failure terminates the whole batch and retains the
failing job's detailed error. Shared scheduler/poll/limit failures likewise
retain completed responses, abort active owners and destroy queued Prepared
owners.

`Report.get` returns a borrowed shallow descriptor. `Report.take` transfers
one outcome and installs `Taken` before exposing it. A taken Complete response
can outlive the Report and must be explicitly destroyed. `Report.destroy`
and `Failure.destroy` release all outcomes still owned by the Report.
Failed and Aborted cleanup payloads retain complete typed HTTPS diagnostics,
including nested HTTP/TLS errors, confirmed progress and secondary socket
cleanup errors. HTTPS Failure owns diagnostic metadata only; its explicit
Destroy implementation therefore has no resources to release. Do not create
another cleanup authority by copying owners or destroying a value from `get`.

## Readiness, retries and closure

One thread cooperatively steps the active owners and waits through one shared
PollSet. No synchronous per-job HTTPS facade runs inside the scheduler. A step
performs at most one active TCP leaf or TLS I/O attempt, and may instead
perform a bounded local Protocol action. Polling stays in the shared scheduler.
One OpenSSL attempt can make several BIO syscalls and perform synchronous
native work; this is not CPU preemption or one syscall per step.

The HTTPS driver's retry and closure rules remain unchanged in a batch:

- WANT retains the exact staged write arguments until completion or failure.
  A write waiting for write readiness excludes other TLS I/O; a write waiting
  for read readiness permits the documented read interleaving.
- A final HTTP head stops new upload. An already pending native write must
  finish with its original arguments or fail under the existing deadline and
  quotas; it is never silently discarded.
- TLS 1.3 can send local `close_notify` before the rest of an early-final body,
  once pending write and read requirements permit it. TLS 1.2 defers local
  notification until the framed response completes. A peer requiring an
  unsupported TLS 1.2 early half-close can reach the deadline.
- Shutdown WANT is exclusive until local alert output completes. `Sent`
  establishes local notification only; no bidirectional shutdown wait is
  required before destroying TLS and closing the socket. Raw `SHUT_WR` does
  not substitute for TLS closure.
- Only authenticated TLS EOF terminates a close-delimited HTTP body. Fixed
  and chunked bodies can finish at their validated HTTP boundary without
  awaiting peer EOF. A response publishes only after transport cleanup.

See the [single-exchange guide](extended-https-client.md) for exact readiness,
terminal replay and closure semantics. Focused execution covers cross-direction
WANT, both protocol versions, verified client chains, truncation, partial
outcomes, native failures and reached source-allocation cleanup. This does
not enumerate all TLS record partitions or network schedules.

## Limits and statistics

The scheduler's job/concurrency, pending request, completed wire/body,
operation and reserved aggregate protocol-work limits retain their
[shared meanings](extended-http-batch.md#work-operation-and-storage-accounting).
Logical byte caps exclude allocator capacities, temporary candidates, caller
backing and native OpenSSL memory. They do not bound process RSS. Conservative
work reservations can admit fewer jobs than `concurrency` when aggregate
credit is tight; no allowance is silently divided by the concurrency setting.

`https_client::Options.tls_calls` independently bounds each job's native
handshake/read/write/shutdown attempts, including WANT retries. It must be
positive and defaults to 1,048,576. HTTP I/O charges include TCP leaves, TLS
attempts and poll participation; several owners can participate in one physical
poll. `Report.stats.polls` counts physical shared polls. The Report has no
aggregate TLS-operation counter; detailed failed jobs retain their `TlsStats`.

Protocol-work and scheduler-operation counters do not measure native
cryptography, certificate verification, allocator work or every CPU
instruction. Context setup precedes this call, and synchronous native work
and mandatory cleanup cannot be preempted by the deadline. Exhausting a
budget still attempts all active owner cleanup and preserves prior completed
responses. No hard native memory ceiling, real-time return bound or
throughput guarantee is claimed.

## Execution receipts

All six groups pass on native Linux x86_64/glibc with OpenSSL 3 through the
production GPU compiler, across the following separate invocations. There is
no claim of one combined passing suite invocation.

| Receipt under `target/stdlib-work/` | Accepted scope | Elapsed |
| --- | --- | ---: |
| `https-batch-initial-two-groups-first.log` | Verified overlap/ownership: 5 cases; canonical framing/buffered input: 4 | 11.01 s |
| `https-batch-policy-transport-limits-first.log` | Peer policy: 11; transport/early-final/closure: 6; limits/cancellation: 16 | 14.04 s |
| `https-batch-resource-direct-typed-retry.log` | Resource/resumable/native-fault controls: 66, including every one of 42 reached source-allocation failures | 37.52 s |

Sixteen allocation positions occur after networking begins. The other 24
resource-group controls include six direct-step/abort invocations, native
faults and recovery. Source mapping/descriptor ledgers and the per-SSL native
observer check cleanup before process exit; native OpenSSL malloc paths and
process-global caches are outside the source-allocation sweep.

The first resource attempt stopped during direct-consumer compilation because
a nested error pattern produced `AssignMismatch` / `LNC0006`; no Python cases
ran. Rewriting that fixture as two explicit typed matches preserves its errno
and cleanup assertions. The passing retry required no production/compiler
patch; the [testing guide](extended-https-batch-testing.md#acceptance) retains
the failing form and distinguishes it from runtime evidence.

The confirmed 14-line `nested_io.lani` reduction imports no HTTP/TLS code and
still rejects the nested binding with `LNC0006` at 6:59. The explicit two-match
control compiles to a validated native x86_64 ELF and exits zero after all four
assertions. The [admission record](../tests/fixtures/extended/https_batch/compiler_admission/README.md)
keeps both commands and diagnostics. This is a compiler-expression limitation
with an executable source spelling, not a runtime TLS failure or a compiler fix.
