# Resumable HTTP client execution tests

`tests/extended_http_exchange_execution.rs` exercises the public
`ext::http_client::Exchange` state machine through a native Lanius fixture.
Python supplies an independent caller, loopback peer, HTTP oracle and syscall
resource ledger. It is test infrastructure only.

## Behavior boundary

`prepare_until` stages request storage before opening a socket. A successful
`Prepared.begin` consumes the actual prepared owner. `begin_until` combines
these operations, opens one nonblocking socket and returns before connecting
or polling. Caller method, target, authority, header and body allocations are
released immediately after construction in the native fixture. The peer then
checks the staged request using h11, including its binary body.

The fixture calls `step(Readiness)` explicitly. Every call is bracketed in the
syscall trace. The oracle permits at most one active network leaf per step,
at most 1024 bytes per send/receive, and no internal poll in construction,
stepping, abort or `before_wait`. Mandatory cleanup close is counted separately
from active network attempts. Cursor, canonical parse and decode actions may
process configured bounded data in one turn; this test does not establish a
hard CPU time slice or operating-system scheduling guarantee.

The caller drives pending readiness with a separate raw poll. It calls
`before_wait` first and counts that abstract participation once. Immediate
work must return false without charging a poll. The global I/O count must
equal socket creation attempts, active network leaf attempts and charged
external poll participations. Confirmed sent/received totals must equal the
positive results in the actual syscall trace.

## Focused groups

| Group | Assertions |
| --- | --- |
| Steps and readiness | Real repeated caller-driven steps, staged request lifetimes, immediate-work poll refusal, and all-false readiness preserving a pending connection. A synthetic EINPROGRESS leaves the socket unconnected: SO_ERROR=0 must still be followed by peer proof, ENOTCONN stays pending, and no request bytes are sent. |
| Framing | Fixed, chunked and HTTP/1.0 close-delimited responses; whole, byte and seven-byte permissions; ordered 100/103 heads, binary bodies, chunk extensions/trailers, empty/error final statuses, exact limits and discarded extra bytes. Close-cap completion requires an actual positive-capacity receive returning zero; one-byte overflow is recorded but never published. |
| Early final | The peer sends a final rejection head during a large staged upload, then withholds its response body until it observes real request-side EOF. Upload progress freezes after the final head; successful half-close and injected shutdown failure preserve their distinct progress flags. |
| Lifecycle | Prepared destruction/consumption, abort before and during connection, idempotent terminal operations, failed-close abort, sticky failure, and response lifetime after Exchange disarm. Fresh hints drive the upload; only after it completes do deliberately false hangup/error hints test that a close-delimited response still needs actual receive EOF. |
| Faults and budgets | Every engine allocation position reached in two fixed workloads, selected socket/connect/peer/send/receive/close failures, interruptions, persistent interruption under a cumulative quota, zero/low caps, primary protocol plus secondary close failure, and a successful send whose delayed return crosses the original deadline. |

The HTTP expectations follow
[RFC 9112 message framing](https://www.rfc-editor.org/rfc/rfc9112.html#section-6.3)
and [informational response semantics](https://www.rfc-editor.org/rfc/rfc9110.html#section-15.2).
Python `http.client` independently decodes supported final bodies. Explicit
vectors cover policy that those libraries do not enforce identically, such as
the existing strict duplicate Content-Length policy and unsupported upgrades.

## Determinism, ownership and faults

The peer releases the next response fragment only after native progress has
consumed the previous prefix and the engine reaches pending readiness. The
oracle does not assume that TCP writes preserve receive boundaries. The full
receive backing stays owned by Exchange until one Response is transferred.
The fixture retains final/informational method descriptors and body/wire views
after all caller request owners have been destroyed, then checks terminal
Exchange operations before using and releasing the Response.

The trace ledger tracks mmap addresses with their requested lengths and
descriptor owner generations. Unknown, duplicate or wrong-length frees fail.
Every socket owner must receive one direct close attempt; injected close
errors still retire library cleanup authority and must never trigger retry.
These checks describe owner invalidation and attempted cleanup, including the
case where an injected close error leaves the kernel descriptor until process
exit.

Allocation campaigns reuse the same listener address and argv. They derive
engine allocation ordinals from public-call markers, excluding the fixture's
caller-storage setup. Each denial requires the exact mmap ordinal, ENOMEM and
one INJECTED marker, the original request-length prefix through that point,
the allocation-specific typed cause, and a completely balanced successful
mapping ledger. A changed port-string length cannot silently shift the
baseline argument allocation requests.

Other errno injections likewise require their exact syscall, ordinal, errno
and marker. The false-connect controls distinguish synthetic readiness from
a kernel-confirmed connection. The deadline control requires a successful
positive send, retained confirmed progress, and Timeout after its delayed
return; it does not claim that a userspace operation can be preempted at an
absolute instant.

## Evidence and reproduction

All five direct Exchange groups are accepted on the native Linux x86-64
profile across the separate receipts below: 83 cases in total, counting the
strengthened steps group once. These are distinct from the 188 synchronous
client regression cases.

The first direct steps group passed in 7.37 seconds, printing three cases:
`target/stdlib-work/http-exchange-steps-first.log`. After that terminal run,
the oracle gained an explicit equality check between released fragments and
confirmed receive progress before releasing each next fragment. The probe
also strengthened sticky failure stage/offset/secondary-error equality checks.
The earlier receipt does not validate those added assertions. The subsequent
shared-compilation invocation passed the strengthened steps group (three
cases), early-final group (two), and framing group (20), in a mixed 9.35-second
run: `target/stdlib-work/http-exchange-all-groups-current.log`.

The two remaining groups in that invocation exposed harness errors. The
lifecycle control replayed false readable/hangup hints before finishing its
upload, repeatedly prioritizing receive work. It now drives fresh readiness
through upload before testing that advisory hangup is not EOF. The zero raw
cap control expected the transport's ResponseLimit, but the canonical cursor
first returns `Http(Limit(0))` at Receive, as before the refactor. It now checks
that exact subtype/offset with zero sent/received progress and no receive
syscall. Both corrections preserve production behavior. Their focused retry
passed lifecycle (10 cases) and faults (48) in 8.58 seconds:
`target/stdlib-work/http-exchange-two-groups-retry.log`. The two allocation
workloads printed 12 and 14 reached engine allocation positions, each denied
individually with the required marker, typed error and cleanup checks.

The existing six `extended_http_client_execution` groups passed the shared
engine regression in 26.85 seconds before this new test target was admitted.
Its separate receipt is
`target/stdlib-work/http-exchange-client-regressions-current.log`; it does not
stand in for the direct resumability groups.

CPU checks passed Python syntax, native literal byte lengths, independent h11
request parsing and `http.client` binary fixed/chunk decoding. Synthetic trace
controls accept balanced ownership and reject incorrect frees, double close,
internal poll, multiple active leaves, missing cleanup and invalid fault
markers. These checks execute no native Lanius fixture.

Run the first focused group with the project's serialized GPU gate:

```sh
cargo test --locked --test extended_http_exchange_execution \
  staged_request_lifetimes_pending_readiness_and_one_leaf_steps_execute \
  -- --exact --nocapture --test-threads=1
```

The driver prints each accepted oracle summary, including the reached engine
allocation positions. The remaining exact names are in the driver. Every
public-call read and subprocess has a finite bound. Coverage is finite Linux
x86-64 loopback behavior; it does not establish TLS, arbitrary server traffic,
general HTTP conformance, another operating system, or hard realtime bounds.
