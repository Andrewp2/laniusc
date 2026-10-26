# Resumable verified HTTPS client

`ext::https_client` connects one numeric endpoint, verifies its TLS peer and
drives the concrete [HTTP Protocol owner](extended-http-client.md). The same
request encoder, framing cursor, response validation, decoding and Response
type serve plaintext HTTP and HTTPS. This module supplies TCP and TLS
progress; it adds no HTTP parser or cryptographic implementation. Plain
`ext::http_client` imports no OpenSSL code.

The native profile is Linux x86_64/glibc with OpenSSL 3 `libssl` and
`libcrypto`. All six focused connected HTTPS groups pass 108 cases through
three separate native invocations. They exercise this Exchange directly and
through the [HTTPS batch adapter](extended-https-batch.md), using the shared
HTTP Protocol and generic scheduler. The synchronous facade also passes the
migrated `https_fetch` program's four groups, 63 cases, plus the
separate mutual HTTPS application gate of 101 cases. These application
invocations exclude their stream-only consumers.

## Public entry points

The shortened names below refer to `ext::http_client`, `ext::openssl_tls` and
the corresponding `core` types.

```lanius
pub struct Options { tls_calls: u64 }
pub fn default_options() -> Options;
pub fn begin_with_context_until(
    prepared: &http_client::Prepared,
    endpoint: SocketAddr,
    context: &openssl_tls::Context,
    identity: openssl_tls::Identity,
    options: Options,
) -> Result<Exchange,Failure>;
pub fn exchange_until(
    endpoint: SocketAddr,
    context: &openssl_tls::Context,
    identity: openssl_tls::Identity,
    request: http_client::Request,
    http_options: http_client::Options,
    tls_options: Options,
    deadline: Deadline,
) -> Result<http_client::Response,Failure>;

pub impl Exchange {
    pub fn borrow(&self) -> &Exchange;
    pub fn stats(&self) -> http_client::Stats;
    pub fn tls_stats(&self) -> TlsStats;
    pub fn status(&self) -> http_client::Status;
    pub fn last_failure(&self) -> Option<Failure>;
    pub fn negotiated_version(&self) -> i32;
    pub fn raw_handle(&self) -> Option<i32>;
    pub fn interest(&self) -> http_client::Interest;
    pub fn before_wait(&self) -> Result<bool,Failure>;
    pub fn step(&self, ready: http_client::Readiness)
        -> Result<Option<http_client::Response>,Failure>;
    pub fn abort(&self) -> Result<bool,Failure>;
}
```

`begin_with_context_until` consumes and disarms the actual Prepared before
validating driver options or acquiring transport resources, including on
failure. It retains the Prepared's absolute deadline and charged HTTP
work/I/O counters. A successful begin opens one nonblocking TCP socket;
connection attempts start in `step`.

The context remains the caller's owner. Begin acquires a distinct native
reference with `Context.retain` and copies the identity bytes. After a
successful begin, the original context and identity backing may be released.
After connection, Session attachment acquires its own native context
reference; the Exchange then destroys its retained Context wrapper and
identity copy. No later operation uses the caller's Context storage.

`exchange_until` performs canonical HTTP preparation once, calls begin, then
drives this same Exchange. It explicitly polls one socket when needed; the
resumable `step` and `before_wait` methods never poll or sleep. The
[HTTPS batch adapter](../extended/ext/https_batch.lani) supplies this driver to the
shared scheduler instead of using the synchronous facade.

## Peer policy and request policy

Create a verified client Context using `openssl_tls::new` or
`new_with_credentials`. Trust, mandatory DNS/IP identity, optional client
credentials, native certificate verification and minimum TLS version retain
the [OpenSSL wrapper's contract](extended-openssl-tls.md). The endpoint,
certificate identity and HTTP Host authority are distinct caller values.
There is no automatic resolver, authority/identity equality check, redirect,
connection reuse, proxy, retry/replay or verification-disable option.
Certificate acceptance does not implement application authorization.

Identity validation uses the canonical OpenSSL wrapper's byte policy; native
IP syntax admission still occurs during Session configuration. Logical view
bounds are checked. Actual physical extent, layout and lifetime remain caller
preconditions. Keep one active Exchange owner, borrow it for operations, and
do not mutate public fields, operate on copied owner aliases or call it from
concurrent/foreign threads.

HTTP options are those used to create Prepared. Select
`http_client::Trailing::Reject` when preparing a strict HTTPS exchange; this
rejects surplus plaintext already read beyond the framed response. The driver
preserves the caller's trailing policy and does not wait for peer EOF after a
self-delimited response just to discover later bytes. All canonical request
restrictions and bounded informational-response handling remain shared.
A valid non-2xx final response is a successful transport result; status
acceptance is application policy.

Establish an explicit process SIGPIPE policy before attaching or driving TLS.
OpenSSL's socket BIO can raise SIGPIPE, and this module does not change signal
dispositions. A TLS error return cannot prevent default signal termination.

## Readiness, duplex progress and stable requests

Drive `interest().immediate` turns with all-false Readiness. Otherwise call
`before_wait`, participate in a poll only after `Ok(true)`, and pass its flags
to the next step once. `Ok(false)` leaves immediate work available. Error and
hangup readiness permit an operation attempt; neither proves connection,
authenticated TLS EOF or a valid HTTP boundary. Never reuse readiness for a
new Exchange after descriptor reuse.

Each step performs at most one active TCP leaf or TLS I/O attempt. TCP
connection, SO_ERROR and peer-address checks occupy separate turns. Native
Session attachment, local Protocol work, read quiescence, cleanup and
publication are separate state transitions. Mandatory failure cleanup may
close the socket in the same failing turn. Native setup, canonical response
validation and decoding are bounded synchronous actions, not preemptible CPU
slices.

The driver retains independent TLS read/write needs:

- A pending write that wants write readiness is exclusive: only its exact
  staged write may cause TLS I/O until it completes or the Exchange aborts.
- A pending write that wants read readiness may interleave reads while its
  native pointer, data, length and output count cell remain fixed.
- Other pending read needs may interleave new or resumed writes. A new write
  never replaces a pending one.
- A successful read permits another optimistic read for buffered plaintext.
  WANT blocks that operation until matching readiness or permitted opposite
  direction progress. There is no `SSL_pending`/`has_pending` busy loop.

The shared Protocol locks an immutable request prefix of at most 1024 bytes.
When `Context.io_bytes()` is smaller, TLS stages only that smaller prefix and
the Protocol commits only the confirmed count. WANT retains both the native
write and Protocol reservation; it is never treated as cancellation or proof
that no bytes reached the peer. These stable retry arguments follow
[OpenSSL's write contract](https://docs.openssl.org/3.0/man3/SSL_write/).

## Early final response and closure

A final HTTP head stops new upload chunks. An already staged native write
must finish with its original arguments, or fail under the existing limits
and deadline. It is never silently dropped or replaced.

For TLS 1.3, after the pending writer has finished, a pending read that wants
read readiness may be quiesced without discarding native buffered input. The
driver then sends local `close_notify` and continues reading the remaining
response body. A read that wants write readiness must progress first. For
TLS 1.2, new upload also stops, but local notification waits until the framed
response completes. A TLS 1.2 peer that requires an unsupported early
half-close can therefore fail at the configured deadline. TLS never uses raw
socket `SHUT_WR`.

Shutdown WANT is exclusive until the alert output completes. `Sent` confirms
local notification only; `Complete` additionally observes peer notification.
Neither is an application receipt. After the framed response completes, the
driver reaches local `Sent` or `Complete`, destroys TLS, closes the socket,
acknowledges transport completion to Protocol, and only then publishes the
owned Response. It does not wait for a bidirectional close after `Sent`.
OpenSSL documents local notification and the use of reads for remaining peer
data in its [shutdown contract](https://docs.openssl.org/3.0/man3/SSL_shutdown/).

Only an authenticated TLS EOF is passed to Protocol. Missing peer
`close_notify` cannot terminate a close-delimited body successfully. A fixed
or chunked response can finish at its validated HTTP boundary without waiting
for peer EOF. Authenticated peer closure with an unresolved pending writer
fails as `PeerClosed` and abandons the session through normal owner cleanup;
it does not promise graceful shutdown.

`negotiated_version` is zero until a verified handshake completes. It then
retains the native version snapshot (771 for TLS 1.2, 772 for TLS 1.3), even
after completion, failure or abort. This diagnostic snapshot is not a live
Session, a peer-authorization result or proof of remote application acceptance.

## Limits and diagnostics

`Options.tls_calls` must be positive; its default is 1,048,576. It bounds all
handshake, read, write and local-shutdown attempts, including WANT retries.
Counters describe wrapper attempts, not ciphertext records or internal
OpenSSL operations:

```lanius
pub struct TlsStats {
    calls: u64, handshakes: u64, reads: u64,
    writes: u64, shutdowns: u64,
}
pub enum Stage {
    Prepare, Retain, Open, Connect, Attach, Handshake,
    Transfer, Shutdown, Close, Publish,
}
pub enum Cause {
    Http(http_client::Failure), Tls(openssl_tls::Error), Io(core::io::Error),
    InvalidOptions, TlsLimit, Inactive, InvalidEngine, PeerClosed,
}
pub struct Failure {
    cause: Cause, stage: Stage,
    stats: http_client::Stats, tls: TlsStats,
    cleanup: Option<core::io::Error>,
}
```

The shared HTTP I/O allowance charges TCP leaves, TLS attempts and each poll
participation. HTTP work remains the canonical encoder/parser/decoder work
allowance; it does not measure OpenSSL CPU. TLS setup, native allocator cost,
certificate verification and cryptographic work are not covered by a hard
CPU or memory ceiling. Deadline checks surround progress, but synchronous
native calls and cleanup cannot be preempted by this API. Use an external
process deadline when that stronger bound is required. Caller-created trust
or credential contexts precede begin and retain their own setup scope.

Confirmed HTTP byte progress is retained before a later clock/deadline
failure. Native OpenSSL errors retain their complete typed phase, SSL error,
queue code, verification code and saved errno; the driver does not erase
them into integers or replace them with a generic I/O code. `cleanup` records
a secondary socket-close failure without replacing the first cause.

Every terminal error from step/before_wait disarms Session, retained Context,
identity, socket and HTTP owners before returning. Repeated calls return the
same Failure without renewed budgets or native I/O. Stats remain readable.
Successful completion transfers one Response; release it with its existing
`destroy` method. `abort` releases an active owner even after quota/deadline
exhaustion, returns true once, and leaves no active transport owner, including
when close reports an error. Terminal interest is empty and `raw_handle` is
None. Step/before_wait on completed or aborted owners report local Inactive.
Failure contains metadata only; its `Destroy<Failure>` implementation needs
no resource release.

## Acceptance scope

On 2026-10-26, all six groups in
[`extended_https_batch_execution.rs`](../tests/extended_https_batch_execution.rs)
passed on the native profile above. These are separate invocations, not one
whole-suite run:

| Receipt under `target/stdlib-work/` | Executed scope | Invocation time |
| --- | --- | --- |
| `https-batch-initial-two-groups-first.log` | 2 groups, 9 cases: verified overlap/ownership (5), canonical framing and buffered input (4) | 11.01 s |
| `https-batch-policy-transport-limits-first.log` | 3 groups, 33 cases: typed peer policy (11), duplex transport and early-final closure (6), limits/cancellation (16) | 14.04 s |
| `https-batch-resource-direct-typed-retry.log` | 1 group, 66 cases: native faults, recovery, six direct resumable/abort invocations and every one of 42 reached source-allocation failures | 37.52 s |

The causal peers require concurrent connection/handshake and complete-request
barriers before releasing responses. Independent HTTP readers check emitted
requests and returned messages. TLS 1.3 early-final response bodies wait for
authenticated client notification; TLS 1.2 peers exercise the documented
deferred policy. Direct-consumer traces forbid hidden polls inside step/wait
and check the one-active-leaf limit. The kernel descriptor ledger, per-SSL
native owner counters and exact source-allocation ledger check cleanup before
process exit. Sixteen of the 42 allocation failures occurred after socket
creation. These runs use the scheduler's wait-retirement correction.

The first resource attempt stopped at compilation of a nested test-only error
pattern, before any Python campaign case ran. The accepted retry selects the
typed I/O payload before matching its Host code and preserves the exact error
assertions. No production TLS or compiler patch was needed for that correction.
The [testing guide](extended-https-batch-testing.md#acceptance) records the
reproduction and complete evidence boundaries.

The lower-level [raw TLS duplex gate](extended-openssl-tls.md#current-duplex-and-ownership-receipts)
passes all nine groups and 36 cases separately. The migrated
[HTTPS fetch application](extended-https-fetch.md#current-migrated-application-acceptance)
passes its 18 matrix, 14 failure and 26 limits cases in a separate
11.12-second invocation, recorded in
`target/stdlib-work/https-fetch-shared-exchange-app-first.log`. The
[mutual HTTPS application gate](extended-https-mutual-tls.md#focused-execution-gates)
passes 35 matrix, 34 failure and 32 limits cases in 18.14 seconds, recorded in
`target/stdlib-work/https-mutual-tls-shared-fetch-app-first.log`. These use
`exchange_until` through the actual CLI and exclude the separate
buffered-stream/prepared-context consumers. The additive empty-body,
zero-budget and 1 MiB group passed five cases in 8.92 seconds, recorded in
`target/stdlib-work/https-fetch-empty-zero-limits-mebibyte-first.log`. The two
ordinary application receipts therefore accept four groups and 63 cases;
the [fetch guide](extended-https-fetch.md#current-migrated-application-acceptance)
records their precise scope.

The selected legacy raw client/server/mutual-TLS retry gates also pass; their
scope is recorded in the [TLS guide](extended-openssl-tls.md#focused-legacy-retry-regressions).
The [shared HTTP Protocol and plain exchange gates](extended-http-client.md#current-extraction-acceptance),
[generic plain batch gates](extended-http-batch.md#current-generic-revision)
and [migrated CSV-to-ZIP application](extended-fetch-many.md#focused-acceptance)
also have current acceptance with their stated scopes. Full historical TLS
matrices and deliberately excluded stream-only consumers retain their earlier
receipts; this batch did not rerun them. These finite native schedules do not
cover every TLS partition, network interleaving or native OpenSSL allocation
failure, and they establish no other execution target.
