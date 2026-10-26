# OpenSSL client TLS with peer verification

`ext::openssl_tls` provides client TLS through OpenSSL 3 `libssl` and
`libcrypto`. OpenSSL performs the handshake, certificate verification,
encryption, record handling and shutdown. Lanius supplies explicit trust and
identity policy, stable retry buffers, state checks and resource ownership.
There is no custom cryptography, TLS record parser, C adapter, JSON bridge or
Rust/Python production TLS implementation.

The source targets the [Linux x86_64/glibc native C profile](library-native-c.md),
with OpenSSL 3.0.13 audited locally. All nine current raw duplex groups pass
36 executed cases, including independent read/write retries, read quiescence,
write-side shutdown, context retention and all five source allocations reached
by one staging lifecycle. The [connected HTTPS tests](extended-https-batch-testing.md)
also pass six groups and 108 cases using this wrapper, the shared HTTP Protocol
and the generic scheduler.

The migrated [HTTPS fetch](extended-https-fetch.md) application also passes its
four groups, 63 cases; the [mutual HTTPS applications](extended-https-mutual-tls.md)
pass three groups and 101 cases. Focused retry/ownership regressions pass for
the older raw client, [server](extended-openssl-tls-server.md) and
[mutual TLS](extended-openssl-mutual-tls.md) consumers. These results do not rerun
their complete historical matrices or accept the separate stream-only
consumers. These finite Linux tests do not complete the security family or
establish another target.

## Trust and identity

`new(trust,limits)` returns `Result<Context,Error>`. Choose
`Trust::DefaultPaths` to load OpenSSL's configured default trust locations, or
`Trust::CaFile(path)` to load a supplied CA file. The file path is a nonempty
UTF-8 byte view without NUL, bounded by `limits.path_bytes`. The wrapper copies
and terminates it before passing it to OpenSSL. Default trust follows the
linked OpenSSL configuration and environment; selecting defaults does not
guarantee the machine has a populated trust store.

`new_with_credentials(trust,chain,key,passphrase,limits)` creates the same
verified client context with one native PEM credential pair. Its shared
credential loader, passphrase policy, exact cleanup and mutual-TLS evidence
are documented in the guide above. The client still requires service trust
and DNS/IP identity checks.

Every context requires `SSL_VERIFY_PEER`, with no application verification
callback, and a minimum protocol version of TLS 1.2. OpenSSL's configured
cipher/security policy otherwise applies. Compression and renegotiation are
disabled. `SSL_OP_IGNORE_UNEXPECTED_EOF` is explicitly cleared so a global
configuration cannot turn missing `close_notify` into successful EOF. The
checked API offers no verification-disable option.

`context.session(fd,identity)` returns `Result<Session,Error>`. Identity is
mandatory and separate from the numeric endpoint used to establish the socket.

`context.validate_identity(identity)` returns `Result<i32,Error>` and reuses
the same local checker without allocating or calling OpenSSL. It returns
`Ok(0)` for admitted metadata/policy, or a local error; a closed context returns
`Cause::Closed` in `Phase::Identity`. An asynchronous caller can use it before
opening a socket. It does not prove physical view backing or complete IP
syntax: OpenSSL still checks IP syntax when the Session is attached.

The identity policies are:

| Identity | Verification and SNI |
| --- | --- |
| `Identity::Dns(name)` | Set OpenSSL's expected DNS name and send that name as SNI. Require a matching subjectAltName; no common-name fallback or partial-label wildcard matching. |
| `Identity::Ip(address)` | Set OpenSSL's expected IP address through `X509_VERIFY_PARAM_set1_ip_asc`. Match an IP subjectAltName and send no SNI. |

DNS names are ASCII hostnames, including caller-prepared IDNA A-labels. Labels
have 1..63 characters, contain letters/digits/hyphens, and start/end without a
hyphen. The complete name has at least one letter, no trailing dot, wildcard,
NUL or empty label, and at most 253 bytes. Digit/dot-only references must use
the IP variant. The wrapper does not resolve names or perform IDNA conversion.

IP strings use the usual unbracketed IPv4/IPv6 notation, at most 45 ASCII bytes,
without zone identifiers. OpenSSL validates their address syntax. Empty
identities are rejected rather than disabling identity checks. Names are copied
into packed NUL-terminated staging while OpenSSL records its own policy copies.

A successful handshake is exposed as `Open` only after both
`SSL_get_verify_result()==0` and a non-null borrowed peer certificate. The
wrapper never frees that borrowed certificate pointer. Checking both prevents
an anonymous or certificate-free handshake from being treated as authenticated.
Certificate pinning, OCSP/CRL policy, ALPN and application protocol negotiation
remain outside this profile. Client credentials use the constructor above.

## Socket and context ownership

The descriptor must already refer to a connected, nonblocking stream socket.
The caller keeps it alive for the session and must not change its flags, close
it or use raw socket I/O concurrently with TLS. The wrapper validates a
nonnegative descriptor but cannot prove these preconditions.

`SSL_set_fd` installs OpenSSL's socket BIO with borrowed descriptor ownership.
TLS cleanup frees the BIO and SSL resources without closing the descriptor.
The caller closes the socket after TLS cleanup. The wrapper neither connects
nor polls it, and never changes process signal dispositions.

OpenSSL's socket BIO can raise SIGPIPE. Establish an explicit process policy
before attaching or using it. The existing
`std::signal::set_disposition(Signal::BrokenPipe,Disposition::Ignore)` provides
the supported ignore policy and changes the whole process; an application must
handle its failure. A TLS error return cannot protect a process with default
SIGPIPE termination.

Both `Context` and `Session` are shallow manual owners. Keep one active owner,
use `borrow()` for operations, and leave copied aliases inactive. Do not edit
their fields or call them from concurrent/foreign threads. `SSL_new` retains
its native context references, so `context.destroy()` may release the wrapper's
reference while existing sessions remain live. A session does not retain a
pointer into the Lanius context owner's storage.

`context.retain()` returns `Result<Context,Error>` and uses `SSL_CTX_up_ref`
to create a distinct native reference with the same limits. The returned
context is another active owner that must eventually be destroyed. Either
owner may be destroyed first. A closed source returns `Cause::Closed` in
`Phase::Context`; native failure captures the error queue and transfers no
reference. This lets an asynchronous connection retain policy before creating
its Session. A descriptor copy alone does not retain anything. Retained
contexts share immutable trust, credentials and policy; callers must not edit
them through native declarations or owner fields.

`session.destroy()` abandons TLS without implicitly calling `SSL_shutdown`.
It invalidates its pointers, frees SSL, wipes its owned read/write staging with
OpenSSL's `OPENSSL_cleanse`, and releases the allocations. Repeated destruction
through that owner does nothing. This is also the cancellation path after a
deadline, attempt budget or application error; it makes no graceful-delivery
claim. The borrowed descriptor remains the caller's resource.

## Explicit progress operations

Every progress method returns `Result<Outcome,Error>` and performs at most one
TLS I/O call. It contains no poll, deadline loop, hidden retry or sleep. The
caller must bound its own attempts, bytes and elapsed time and use socket
readiness/deadline APIs when needed. One OpenSSL call can still perform native
protocol work; a step count is not a CPU-work or hard-time bound.

| Method | Outcomes |
| --- | --- |
| `handshake()` | `Handshake::{Complete,WantRead,WantWrite}` |
| `read_into(output)` | `Read::{Data(count),Closed,WantRead,WantWrite}` |
| `write(input)` | `Write::{Complete(count),WantRead,WantWrite}` |
| `retry_write()` | The same write outcomes for the pending staged request |
| `shutdown_write()` | `Shutdown::{Complete,Sent,WantRead,WantWrite}`; stop after local notification |
| `shutdown()` | The same outcomes, with explicit bidirectional progress |

`State` is `Handshake`, `Open`, `PeerClosed`, `Closing`, `Closed` or `Failed`.
Application writes require `Open`. Reads also remain available after confirmed
local notification, as described below. Repeating a completed handshake succeeds
locally only before shutdown and when no application operation is pending.
A fatal TLS error releases the native session and staging, reports `Failed`,
and leaves `is_open()` false.
Calling `destroy()` afterward records `Closed` and performs no repeated free.

Either read or write can need either socket readiness. Poll according to the
returned WANT, not the operation name. `read_need()` and `write_need()` return
`Need::{None,Read,Write}`. They remember each direction's most recent WANT
separately, until that request completes, is quiesced where allowed, or is
destroyed. They do not consult OpenSSL's thread error state later. A call in
the other direction does not replace this receipt; it may make an optimistic
retry useful. `pending_read_bytes()` and `pending_write_bytes()` expose the
retained request sizes, not delivered-byte counts.

Calls remain serialized in one thread. Permitted interleaving is:

| Last incomplete application operation | Next application operation |
| --- | --- |
| Read wanting read or write readiness | Retry the read, or start/resume a write |
| Write wanting read readiness | Retry the same staged write, or read |
| Write wanting write readiness | Retry that staged write only; no other TLS I/O |

A second new `write()` never replaces a pending write. Initial handshake and
an incomplete shutdown retry remain exclusive. These rules follow OpenSSL's
[retry documentation](https://docs.openssl.org/3.0/man3/SSL_get_error/) and
the maintainers' [read/write interleaving clarification](https://github.com/openssl/openssl/discussions/23112).

The wrapper retains OpenSSL's default `SSL_MODE_AUTO_RETRY` policy. A successful
read can leave plaintext buffered inside SSL after the socket is no longer
readable. A resumable driver must permit another bounded read attempt after
`Data` before waiting for new socket input. It must not busy-loop solely on
`SSL_has_pending`: incomplete records can keep that flag true without yielding
application data. Native record/control-message processing is not preempted by
a Lanius step or byte limit.

## Read and write retry buffers

Each session owns fixed-address read and write buffers plus stable native
`size_t` result cells. These allocations remain alive through WANT retries.
No caller slice pointer is retained. Logical view metadata is checked before
effects, but callers must physically back their views, keep them live during
the call, and avoid overlap with active owner storage.

`read_into(output)` requests at most `limits.io_bytes` logical bytes. On WANT,
the output remains untouched and the original native request size is retained.
Retry with `read_into` after the requested readiness. The retry may use a
different destination, but it must have at least the original requested
capacity; otherwise `Cause::Bounds` is returned without another TLS call. On
success, only the returned prefix is copied and the read staging is wiped.
An empty initial output returns `Data(0)` locally and does not mean EOF.

OpenSSL itself does not require stable read arguments across WANT. The wrapper
keeps this size reservation until completion or `quiesce_read()`. That method
returns `Result<bool,Error>`: `true` clears a read waiting for read readiness,
and `false` means no read was reserved. It clears the wrapper's size/need and
wipes its staging without consuming or discarding native buffered TLS input.
A read waiting for write readiness returns `InvalidState`; progress that
protocol output through the permitted operations, or destroy the session at a
bound. A closed owner returns `Closed`. Quiescence is a conservative wrapper
policy, not a claim that OpenSSL globally forbids interleaving read retries.

`write(input)` accepts one complete request no larger than `limits.io_bytes`,
copies it to owned staging and tries one `SSL_write_ex`. On WANT, release or
reuse the original input freely and resume it through `retry_write()`.
Retry uses the same bytes, length, buffer address and result cell. A second
`write`, handshake or shutdown while it is pending returns `InvalidState`.
A read is permitted only when the pending write wants read readiness. The
wrapper does not enable moving-buffer or partial-write modes. It validates
every successful native count and returns its confirmed
prefix; the caller handles any unconsumed suffix as a new request. Empty input
returns `Complete(0)` locally when no write is pending and writes are admitted.

WANT or failure is not a promise that no encrypted data reached the peer. A
native write may have sent part of a multi-record request before reporting
incomplete progress. Only successful completion counts are confirmed; a
cancelled/fatal write has no reliable delivered-prefix count. A higher-level
stream adapter must preserve that uncertainty when reporting acceptance or
flush failure. The copied pending request remains immutable until completion
or destruction.

For HTTP upload/early-final scheduling, a driver can stage at most 1,024 bytes
at a time and stop admitting new chunks when it recognizes the final response
head. A native write already pending must retain its arguments and may need
to finish before shutdown. If it wants write readiness and the peer refuses
to drain the upload, reading the early response is not permitted until that
write completes. A deadline or quota must terminate the connection honestly;
small chunks do not guarantee full-duplex success against that peer.

## EOF and shutdown

`Read::Closed` means OpenSSL received the peer's authenticated `close_notify`.
The state becomes `PeerClosed`; repeated reads report the same EOF locally.
Application writes are no longer admitted. The session stays live so the caller
can send its own notification through `shutdown()` or explicitly destroy it.

Transport EOF without `close_notify` returns `Cause::Truncated`, including
OpenSSL 3's `SSL_R_UNEXPECTED_EOF_WHILE_READING`. It is never normalized to
`Read::Closed`. Other protocol and system failures retain their native details.
Fatal SSL/SYSCALL errors destroy the session without a later shutdown attempt.

Entering native shutdown requires no pending application read/write. A read
waiting for read readiness can first be quiesced. Starting shutdown enters
`Closing` and permanently stops application writes:

- Native return 1 completes both directions, frees TLS resources and returns
  `Shutdown::Complete` with state `Closed`.
- Native return 0 returns `Shutdown::Sent`: local notification succeeded, but
  peer notification remains pending. The wrapper does not call `SSL_get_error`
  for this successful incomplete result.
- A negative return is classified immediately as WANT or an error. Retry only
  a shutdown method after readiness; application I/O stays disabled until that
  attempt reaches `Sent` or `Complete`.

`shutdown_write()` is the operation for sending local notification while
preserving remaining response reads. After confirmed `Sent`, repeated
`shutdown_write()` calls return `Sent` locally without a second native shutdown
call. `read_into()` is then admitted in `Closing`; it can produce data, WANT
or authenticated EOF under the usual retry rules. EOF records `PeerClosed`,
and the caller can explicitly complete cleanup or destroy the session. Writes
remain forbidden even if no write request was pending when shutdown started.
The local `Sent` replay does not interfere with a subsequently reserved read.

`shutdown()` explicitly requests native bidirectional progress. After `Sent`,
use reads to preserve any remaining application data; do not call `shutdown()`
again until that data has been consumed. A second native shutdown call can
reject peer application data rather than return it. If the caller starts a
new explicit bidirectional wait and it returns WANT, that wait is exclusive;
`shutdown_write()` then resumes the active shutdown rather than cancelling it.

OpenSSL supports reads after local notification. The protocol difference still
matters: TLS 1.3 leaves the initiator's read side open, whereas TLS 1.2 requires
the receiver to answer immediately and discard its pending writes. A TLS 1.2
peer therefore need not generate a delayed response body after receiving the
notification. An incomplete HTTP message remains an error. See
[TLS 1.3 closure](https://www.rfc-editor.org/rfc/rfc8446.txt) and
[TLS 1.2 closure](https://www.rfc-editor.org/rfc/rfc5246.txt).

`negotiated_version()` returns OpenSSL's numeric `SSL_version` result after
handshake completion and the required role policy checks: `771` (`0x0303`)
for TLS 1.2 or `772` (`0x0304`) for TLS 1.3
in the audited native library. It returns zero before handshake completion or
after destruction. This reports the retained session's version, not remote
application acceptance or authorization.

`Sent` alone is not a bidirectional clean shutdown. The caller decides whether
its application framing permits abandonment, or continues to the peer's alert
under its deadline. The socket remains borrowed throughout.

Receiving peer closure while the opposite application operation is still
reserved does not confirm that operation's completion. This wrapper stops
application writes at `PeerClosed`; if a pending request cannot be quiesced
or completed under those state rules, destroy the session. Graceful shutdown
is not guaranteed from every partially completed operation state.

## Error capture and limits

`Error` contains:

| Field | Meaning |
| --- | --- |
| `cause` | Local policy/state/bounds/allocation error, native failure, verification failure, missing peer certificate, peer close or truncation |
| `phase` | Context, trust, policy, session, identity, attach, handshake, read, write or shutdown |
| `ssl_error` | `SSL_get_error` result for a failed TLS I/O call; zero for other failures |
| `code` | First captured OpenSSL error code; zero is possible even on native failure |
| `verify_code` | Native verification result for handshake failures; zero outside that path |
| `system` | errno copied immediately after the native TLS I/O operation; zero for local failures |

Before I/O, the wrapper obtains this thread's glibc errno cell, clears the
OpenSSL error queue and resets errno. After I/O it copies errno, then calls
`SSL_get_error` before any other OpenSSL function. It captures the queue before
diagnostics or cleanup can replace it. The same thread must make the call and
its error lookup. The wrapper owns those queue operations; do not preserve raw
OpenSSL diagnostics across its calls.

| Limit | Default | Accepted range |
| --- | --- | --- |
| `path_bytes` | 4,096 | 1..1,048,576 |
| `identity_bytes` | 253 | 1..253, with the narrower DNS/IP policy above |
| `io_bytes` | 16,384 per staging buffer | 1..65,536 |
| `verify_depth` | 16 | 0..64, using OpenSSL's chain-depth definition |

These bound Lanius staging and local policy. They do not bound native trust
file parsing, total native handshake allocations, protocol work, transfer size
across many calls or the duration of one native operation. Invalid limits fail
before context construction.

## Native linking and verification status

Link applications with `--native-link --native-library ssl --native-library crypto`,
using the rebuilt compiler and ordinary stdlib/extended roots. Use an absolute
build target directory, for example `CARGO_TARGET_DIR="$PWD/target/stdlib-build"`.
OpenSSL's `long` arguments/results map to `i64`, `uint64_t` options to `u64`,
lengths to `usize`, and opaque handles to `ptr` on the selected profile. Control
commands and option masks match the installed OpenSSL 3 headers.

### Current duplex and ownership receipts

On 2026-10-26, the
[`extended_openssl_tls_duplex_execution`](../tests/extended_openssl_tls_duplex_execution.rs)
driver passed all nine current groups through three separate invocations.
The compiler generated linked native x86_64 ELFs; the consumers then executed
against host OpenSSL 3. This is not a GPU execution target. The driver checks
the linked ELF and both OpenSSL library dependencies before execution.

| Receipt under `target/stdlib-work/` | Executed scope | Invocation time |
| --- | --- | --- |
| `openssl-tls-duplex-initial-groups-first.log` | 3 groups, 10 cases: causal read/write interleaving and retained context lifetime (4), TLS 1.3 local notification followed by peer application data (2), labelled rare-WANT controls (4) | 6.43 s |
| `openssl-tls-duplex-five-edge-groups-first.log` | 5 groups, 20 cases: real write backpressure (2), buffered plaintext without socket readiness (2), two SSL owners with reverse retries (2), native fatal results and real truncated records (8), full-shutdown retries (6) | 6.20 s |
| `openssl-tls-duplex-source-allocations-first.log` | 1 group, 6 processes: one successful lifecycle and each of its five reached source-allocation failures | 7.36 s |

The peer withholds reads until the backpressure consumer observes a real native
write `WANT_WRITE`. The buffered-input consumer drains one native record after
a zero-time poll reports no socket event. Per-SSL observers check stable write
addresses, lengths, bytes and count cells even after caller backing changes.
Rare WANT and fatal injections are labelled negative controls; successful
transfers and encrypted records still come from OpenSSL.

The allocation campaign binds every injected ENOMEM to the baseline's exact
global mmap ordinal, emitted allocator instruction and requested size. All
source mappings created inside the campaign must be released before its
completion marker, and the complete trace must balance earlier source owners.
Native Context and Session owner counters must also reach zero before exit.
Nine CPU mutation controls check the source ledger and are not additional
product cases. Native OpenSSL heap allocations and process-global caches are
outside that source ledger. See the
[fixture evidence boundaries](../tests/fixtures/extended/openssl_tls_duplex/README.md).

The [connected HTTPS gate](extended-https-batch-testing.md#acceptance) provides
separate evidence for peer policy, transport scheduling and typed error
propagation through this wrapper. Its 108 cases do not replace the dedicated
legacy profile regressions. The migrated command-line programs have their own
accepted receipts below.

The three existing [HTTPS fetch application groups](extended-https-fetch.md#current-migrated-application-acceptance)
passed 58 cases in 11.12 seconds, recorded in
`target/stdlib-work/https-fetch-shared-exchange-app-first.log`. The separate
[mutual HTTPS application groups](extended-https-mutual-tls.md#focused-execution-gates)
passed 101 cases in 18.14 seconds, recorded in
`target/stdlib-work/https-mutual-tls-shared-fetch-app-first.log`. Both use the
migrated fetch's shared Exchange facade. These invocations exclude the
buffered-stream and prepared-context stream consumers. A new five-case empty
body/1 MiB application group also passed in 8.92 seconds, recorded in
`target/stdlib-work/https-fetch-empty-zero-limits-mebibyte-first.log`. Together
the two ordinary fetch receipts accept four groups and 63 cases. The
[fetch guide](extended-https-fetch.md#current-migrated-application-acceptance)
records the exact empty-body, zero-budget and binary-output checks.

The [shared HTTP Protocol and plain exchange gates](extended-http-client.md#current-extraction-acceptance),
[generic plain batch gates](extended-http-batch.md#current-generic-revision)
and [migrated CSV-to-ZIP downloader](extended-fetch-many.md#focused-acceptance)
also pass their current selected gates. Their guides retain the distinct
execution and ownership scopes.

### Focused legacy retry regressions

After their guard expectations were migrated to the directional retry
contract, all three selected legacy retry/ownership gates passed:

| Receipt under `target/stdlib-work/` | Executed scope | Invocation time |
| --- | --- | --- |
| `openssl-tls-client-duplex-guards-regression.log` | 3 client cases: stable pending writes, bounded polling, dirty error queue and native ownership | 6.48 s |
| `openssl-tls-server-duplex-guards-regression.log` | 1 server case: staged writes, changed read destinations and bounded polling | 6.26 s |
| `openssl-mutual-tls-duplex-guards-regression.log` | 6 mutual-TLS cases across both roles, with stable retries and real backpressure | 7.01 s |

Each is one selected group. The remaining historical groups were not rerun
in these invocations. The migrated checks reject a read only after a pending
write wants write readiness. An empty write during a pending read must return
local `Complete(0)` while preserving its reservation and remembered WANT,
without another native TLS call. Replacement writes, handshake and shutdown
still reject pending operations where required.

### Historical profile and application receipts

The following receipts cover the earlier serialized retry profile. Its old
consumers have been migrated to the directional retry contract and their
focused retry gates passed above. The complete historical matrices and
separate stream consumers have not been rerun for this revision.

[`extended_openssl_tls_execution`](../tests/extended_openssl_tls_execution.rs)
compiles the actual Lanius wrapper on the GPU and executes its native-linked
consumer against bounded loopback peers. `readelf` checks that the executable
depends on both `libssl.so.3` and `libcrypto.so.3`.

| Group | Executed cases | Receipt |
| --- | --- | --- |
| Peer verification matrix | 15 cases pass in 18.56 s: explicit CA trust, DNS and IPv4/IPv6 SAN identities, SNI/no-SNI, TLS 1.2/1.3, binary sizes through 65,536 bytes, packed/strided/owned views, state/metadata checks and context-reference ownership | `target/stdlib-work/openssl-tls-matrix-first.log` |
| Certificate and protocol rejection | 9 cases pass in 16.73 s: untrusted CA, wrong DNS/IP, expired certificate, missing intermediate, wrong purpose, CN-only name, TLS 1.1 and missing certificate | `target/stdlib-work/openssl-tls-verification-current.log` |
| Authenticated closure and truncation | 7 cases pass: clean notification, abrupt transport EOF, cut native encrypted records and incomplete-then-complete shutdown | `target/stdlib-work/openssl-tls-errors-retries.log` |
| Stable retries and cleanup | 3 cases pass: forced WANT_WRITE/read retry during a 524,288-byte exchange, copied pending bytes despite caller mutation and retained request sizes, changed read destinations, pending-operation guards, dirty error queues, bounded stalled polling and native-owner/borrowed-FD cleanup | `target/stdlib-work/openssl-tls-errors-retries.log` |

The last two groups passed in a shared 18.01 s run that also recorded a failure
in the old TLS 1.1 test-peer fixture. That log is not a clean whole-suite pass.
The peer now flushes OpenSSL's queued fatal alert after `SSLError`, before
closing its transport. A separate CPU self-check proves that the legacy peer
can negotiate TLS 1.1 with an explicitly permitted, security-level-0 native
client; the production client retains its TLS 1.2 floor. The nine rejection
cases then passed independently in the receipt above. The production TLS
module did not change across these gates. Together, the passing groups cover
34 cases; no single all-green four-group run is claimed here.

These cases use `Trust::CaFile`. `Trust::DefaultPaths` follows the installed
OpenSSL configuration; these receipts do not establish the contents or behavior
of every host trust store. They also do not establish server TLS, client
certificates, callbacks, ALPN, revocation/pinning policy, foreign-thread use,
other platforms or complete security-family coverage. The separate
[server TLS guide](extended-openssl-tls-server.md) records six passing groups
and the mandatory client-policy regression after introducing session roles.
The
[`ext::tls_stream`/HTTPS guide](extended-https-fetch.md) records a historical
adapter/application gate: 62 cases across four groups passed in 14.44 s,
covering stream progress, verification/HTTP failures, limits and binary framing
(`target/stdlib-work/https-fetch-execution-current.log`). That profile uses
numeric endpoints, explicit trust/identity, deadlines and manual cleanup.
It does not accept the current `https_fetch` migration to the resumable driver;
the separate current application receipts above do.
Test peers, certificates and native observers are test infrastructure;
production TLS and sensitive operations remain in OpenSSL.

Primary references: OpenSSL's [verification policy](https://docs.openssl.org/3.0/man3/SSL_CTX_set_verify/),
[trust loading](https://docs.openssl.org/3.0/man3/SSL_CTX_load_verify_locations/),
[DNS identity](https://docs.openssl.org/3.0/man3/SSL_set1_host/),
[IP verification parameters](https://docs.openssl.org/3.0/man3/X509_VERIFY_PARAM_set_flags/),
[error ordering](https://docs.openssl.org/3.0/man3/SSL_get_error/),
[read](https://docs.openssl.org/3.0/man3/SSL_read/),
[write retries](https://docs.openssl.org/3.0/man3/SSL_write/),
[shutdown](https://docs.openssl.org/3.0/man3/SSL_shutdown/) and
[peer-certificate ownership](https://docs.openssl.org/3.0/man3/SSL_get_peer_certificate/).
The additions also use the native [context reference count](https://docs.openssl.org/3.0/man3/SSL_CTX_new/),
[read-argument clarification](https://github.com/openssl/openssl/discussions/25310),
[interleaving table](https://github.com/openssl/openssl/discussions/30934) and
[buffered-plaintext contract](https://docs.openssl.org/3.0/man3/SSL_pending/).
The version getter follows [SSL_version](https://docs.openssl.org/3.0/man3/SSL_get_version/).
