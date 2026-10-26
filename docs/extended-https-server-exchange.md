# Resumable verified HTTPS server connections

`ext::https_server` has a source implementation against the
[frozen server Protocol contract](library-server-contract.md). Compilation and
native acceptance are pending. Its close ordering follows the selected
paired native TLS experiment below. The earlier sequential HTTPS service and
client driver receipts do not establish this server driver.

The intended profile is Linux x86_64/glibc with OpenSSL 3 `libssl` and
`libcrypto`. The caller supplies an accepted, connected, nonblocking TCP
socket and a configured `openssl_tls::ServerContext`. Lanius drives the
shared `http_server::Protocol`; OpenSSL continues to perform certificate
verification, TLS records, encryption and shutdown. There is no TLS record
parser, cryptographic implementation or exported application callback.

## Public API

The shortened names below belong to `ext::http_server`, `ext::openssl_tls`
and the corresponding core/std modules.

```lanius
pub struct Options { tls_calls: u64 }
pub struct TlsStats {
    calls: u64, handshakes: u64, reads: u64, writes: u64, shutdowns: u64
}
pub fn default_options() -> Options;
pub fn begin_connected(
    socket: Socket, peer: SocketAddr, context: &ServerContext,
    http_options: http_server::Options, tls_options: Options, deadline: Deadline
) -> Result<Exchange,Failure>;
pub impl Exchange {
    pub fn borrow(&self) -> &Exchange;
    pub fn protocol(&self) -> &http_server::Protocol;
    pub fn peer(&self) -> SocketAddr;
    pub fn stats(&self) -> http_server::Stats;
    pub fn logical_bytes(&self) -> u64;
    pub fn tls_stats(&self) -> TlsStats;
    pub fn status(&self) -> http_server::Status;
    pub fn rejection(&self) -> Option<http_server::Rejection>;
    pub fn last_terminal_failure(&self) -> Option<Failure>;
    pub fn negotiated_version(&self) -> i32;
    pub fn remaining(&self) -> Duration;
    pub fn raw_handle(&self) -> Option<i32>;
    pub fn interest(&self) -> http_client::Interest;
    pub fn before_wait(&self) -> Result<bool,Failure>;
    pub fn step(&self, ready: http_client::Readiness)
        -> Result<Option<http_server::Event>,Failure>;
    pub fn read_body(&self, decision: http_server::BodyDecision)
        -> Result<bool,Failure>;
    pub fn respond(&self, response: http_server::Response) -> Result<bool,Failure>;
    pub fn abort(&self) -> Result<bool,Failure>;
    pub fn destroy(&self) -> Result<bool,Failure>;
}
```

## Responsibility and ownership

The constructor consumes its socket on entry, including on failure. It
creates the native Session while the caller's ServerContext borrow is live;
successful `SSL_new` retains its own native reference. The driver does not
retain a pointer into the caller's Context storage and needs no additional
ServerContext reference-count API. The Context's configured public-service
or required-client-certificate policy governs handshake admission.
The constructor checks the socket's nonblocking flag with one charged
attempt. It does not accept, poll, perform a handshake or transfer HTTP bytes.
On constructor failure it destroys all newly acquired transport and Protocol
owners. The caller's original socket descriptor copy becomes an inactive
alias at entry; it must not close that alias later.

No HTTP event or application decision is published before the Session's
handshake and configured peer checks succeed. Certificate-chain acceptance
does not grant a route, role or application principal. Establish a process
SIGPIPE policy before constructing or driving a Session with a socket BIO.

The shared Protocol owns frozen request-head bytes, request wire, decoded
body and encoded response. The driver owns the Session and socket. Request
views borrow Protocol storage and remain valid only until that Protocol is
destroyed. A response is staged synchronously while its borrowed application
storage is live; later transport steps use the Protocol's owned wire.
Terminal failure, abort and completion release the transport but retain
Protocol backing until `Exchange.destroy`. Destroy frees that backing even
when an active abort reports a close error. Repeated terminal destroy cannot
free a second owner or close a reused descriptor. Keep one active manual
Exchange; do not operate independent shallow copies or native aliases.

The Protocol borrow supports the scheduler's synchronous reply sink; it is
not permission to advance, destroy or alter the Protocol independently of
the driver. Decision errors from `read_body` or atomic response preflight
remain recoverable if Protocol stays active. Fatal clock/work/allowance
errors retire the transport. Request rejections remain explicit decisions,
with their original diagnostic snapshots available after a chosen response.

## Bounded progress

The driver exposes caller-driven readiness and progress. Each step makes
zero or one active TLS handshake/read/write/shutdown attempt. It never polls,
sleeps or retries a WANT inside that step. Socket readiness is advisory and
must be consumed once; hangup is not authenticated TLS EOF. Native setup,
protocol work, Session destruction and mandatory close have their own stated
accounting. One OpenSSL call may issue several BIO syscalls and perform
synchronous cryptographic work; one attempt is not a CPU or time slice.

Plaintext operations use at most 1,024 bytes or the smaller Session I/O limit.
TLS counters record attempts separately from the shared HTTP I/O and work
allowances. One absolute deadline covers handshake, application pauses,
request/response progress and teardown. Exhaustion cannot renew a budget or
prevent mandatory owner cleanup.

`Options.tls_calls` is positive, defaulting to 1,048,576 attempts. It includes
handshake, read, write and shutdown WANT retries. TLS setup, Context creation,
Session frees and native helper calls are not additional TLS attempts. A
zero option is InvalidOptions. Native certificate/credential allocations and
cryptographic work are not bounded by the Protocol's logical byte/work caps.

Drive immediate turns with all-false Readiness. Otherwise call `before_wait`
before registering the advertised descriptor/interest. `Ok(true)` reserves
one HTTP I/O participation; successful registration metadata stays stable.
`Ok(false)` means local work or an application decision, with no poll charge.
Each Head, Request or Rejected revision is published once, then the caller
chooses the next command. Neither before_wait nor inspection acknowledges an
application decision or replenishes its deadline.

Stable write requests follow the [shared TLS contract](extended-openssl-tls.md#explicit-progress-operations):
write-WANT_WRITE is exclusive; write-WANT_READ may interleave reads. Either
read WANT may interleave writes. A pending native write retains its original
pointer, bytes, length and count cell until completion or abandonment. Only
a confirmed positive count commits the Protocol send reservation. Read
quiescence is allowed only for WantRead; read-WantWrite protocol output must
progress or the Session must be abandoned at a bound.

While a final response is still being sent, the driver must permit bounded
discard reads without parsing those bytes as another request. Interim 100
progress must preserve the request body instead. The Protocol remains the
sole authority for Expect, request rejection, response staging and drain
allowances. TLS code must not reproduce those policies.

Completion/empty events are published only after TLS/session cleanup, socket
close and the Protocol's final completion check. Failed progress repeats the
same cached Failure without another native operation; completed or aborted
progress returns no second event. Terminal before_wait returns false, except
for a Failed owner, which returns its saved error. Abort retires an active
transport once and preserves Protocol storage. Stats and the diagnostic
version snapshot remain readable after terminal cleanup.

`Failure` retains a typed HTTP, TLS or socket cause, the driver Stage, current
HTTP Stats and TLS Stats, an optional earlier Rejection, and close-attempt /
cleanup diagnostics. Native TLS errors preserve their original phase, SSL
error, queue code, verification code and errno. A cleanup failure does not
replace an earlier operation failure. `Failure` owns metadata only; its
Destroy implementation performs no resource work.
If the reply sink already latched a fatal Protocol failure, abort still
retires its live transport. A successful actual close returns `Ok(true)`;
replaying the earlier diagnostic during bookkeeping is not a new cleanup
error. A new close failure is returned separately, while the saved primary
retains that real secondary error and the final cleanup counters.
Cleanup of an already fatal Protocol preserves Failed status: later step and
before_wait replay the refreshed original Failure, even when abort itself
successfully retired the transport. Explicit cancellation without an earlier
fatal instead records Aborted.
The saved earlier primary retains its operation stage. When no earlier fatal
exists, close failure is the sole Close primary, with no duplicate secondary
cleanup field.

## Local notification, bounded drain and peer closure

The source supports the same explicit close sequence for TLS 1.2 and TLS 1.3:

1. Confirm every byte of the staged final response. Finish any pending native
   write without replacing its request or claiming WANT means zero progress.
2. Finish a pending read-WantWrite through bounded discard. Quiesce only a
   read-WantRead reservation, preserving native buffered input.
3. Call `shutdown_write` once per eligible step until local `Sent` or native
   `Complete`. Shutdown WANT is exclusive. Never substitute raw TCP SHUT_WR.
4. After `Sent`, use positive-capacity TLS reads to discard remaining peer
   application bytes within the Protocol's drain bound and observe its
   authenticated close_notify. Do not repeat full shutdown to consume that
   input. At the exact drain cap, one byte of EOF lookahead is allowed.
5. Destroy Session, close the socket once, record cleanup and acknowledge
   transport completion to Protocol before publishing Complete/Empty.

Native `Complete` proves local notification and peer EOF together. The
Protocol records both facts before one post-call clock check. Merely attempting
shutdown or observing socket hangup proves neither. A pending write still
unresolved when the peer closes fails as PeerClosed; it is not committed or
treated as graceful cancellation.

The selected raw experiment passed four cases in 6.91 seconds:
`target/stdlib-work/openssl-tls-server-alert-before-drain-explicit-return-retry.log`.
For each of TLS 1.2 and TLS 1.3, the native server confirmed a 65,612-byte HTTP
413 response under real write backpressure, sent its alert, then discarded
257 peer bytes and reached authenticated EOF. One peer queued its tail before
the alert; the other wrote it after authenticating the alert. Both retained
stable write retries and ended with no native owners. The
[experiment fixture](../tests/fixtures/extended/openssl_tls_server_shutdown/README.md)
records the peer controls. Its remaining eight cases passed in 7.74 seconds,
recorded in
`target/stdlib-work/openssl-tls-server-shutdown-remaining-groups-first.log`.
Across both versions these establish a clean drain-before-alert control,
honest missing-alert deadlines for both orderings and typed truncation after
abrupt transport EOF. All retain the confirmed response prefix and release
their native owners. These are twelve finite cases across separate receipts,
not one suite invocation or an integrated HTTP driver receipt.

This evidence selects the ordering for the audited native OpenSSL peers. It
does not promise every TLS 1.2 peer will send application data after receiving
an alert or establish this new HTTP driver by itself. A peer that denies late
writes may still finish with its own alert. Native protocol errors, missing
alert, truncation, deadline and drain-limit failures retain their exact
diagnostics and confirmed response progress; they do not become clean
completion. The driver does not disable TLS 1.2 or infer TLS 1.3 behavior from
a negotiated version alone.

## Acceptance scope

Compilation, direct native state cases, verified client-certificate policy,
early-response closure for both versions, retry schedules, exact limits and
owner/allocation failure gates are pending for this driver. No supported
target is claimed from source alone. The full library roadmap remains open.
