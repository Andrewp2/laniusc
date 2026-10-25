# OpenSSL client TLS with peer verification

`ext::openssl_tls` provides client TLS through OpenSSL 3 `libssl` and
`libcrypto`. OpenSSL performs the handshake, certificate verification,
encryption, record handling and shutdown. Lanius supplies explicit trust and
identity policy, stable retry buffers, state checks and resource ownership.
There is no custom cryptography, TLS record parser, C adapter, JSON bridge or
Rust/Python production TLS implementation.

The source targets the [Linux x86_64/glibc native C profile](library-native-c.md),
with OpenSSL 3.0.13 audited locally. The dedicated native execution gates pass
34 cases across four groups: verified identity and binary transfers, rejection
policy, authenticated closure/truncation, and stable nonblocking retries.
The receipts and the corrected test-peer fixture are recorded below. These
results cover this client profile; server TLS and the full security family
remain separate work.

## Trust and identity

`new(trust,limits)` returns `Result<Context,Error>`. Choose
`Trust::DefaultPaths` to load OpenSSL's configured default trust locations, or
`Trust::CaFile(path)` to load a supplied CA file. The file path is a nonempty
UTF-8 byte view without NUL, bounded by `limits.path_bytes`. The wrapper copies
and terminates it before passing it to OpenSSL. Default trust follows the
linked OpenSSL configuration and environment; selecting defaults does not
guarantee the machine has a populated trust store.

Every context requires `SSL_VERIFY_PEER`, with no application verification
callback, and a minimum protocol version of TLS 1.2. OpenSSL's configured
cipher/security policy otherwise applies. Compression and renegotiation are
disabled. `SSL_OP_IGNORE_UNEXPECTED_EOF` is explicitly cleared so a global
configuration cannot turn missing `close_notify` into successful EOF. The
checked API offers no verification-disable option.

`context.session(fd,identity)` returns `Result<Session,Error>`. Identity is
mandatory and separate from the numeric endpoint used to establish the socket:

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
This profile does not add certificate pinning, OCSP/CRL policy, client
certificates, ALPN or application protocol negotiation.

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
| `shutdown()` | `Shutdown::{Complete,Sent,WantRead,WantWrite}` |

`State` is `Handshake`, `Open`, `PeerClosed`, `Closing`, `Closed` or `Failed`.
Application I/O requires `Open`. Repeating a completed handshake succeeds
locally only when no other operation is pending. A fatal TLS error releases
the native session and staging, reports `Failed`, and leaves `is_open()` false.
Calling `destroy()` afterward records `Closed` and performs no repeated free.

Either read or write can need either socket readiness. Poll according to the
returned WANT, not the operation name. Only one application operation may be
pending at once. `pending_read_bytes()` and `pending_write_bytes()` expose its
retained request size; they are not counts of bytes delivered to the peer.

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

`write(input)` accepts one complete request no larger than `limits.io_bytes`,
copies it to owned staging and tries one `SSL_write_ex`. On WANT, release or
reuse the original input freely and call only `retry_write()` or `destroy()`.
Retry uses the same bytes, length, buffer address and result cell. A second
`write`, a read, handshake or shutdown while it is pending returns
`InvalidState`. The wrapper does not enable moving-buffer or partial-write
modes. It validates every successful native count and returns its confirmed
prefix; the caller handles any unconsumed suffix as a new request. Empty input
returns `Complete(0)` locally when no operation is pending.

WANT or failure is not a promise that no encrypted data reached the peer. A
native write may have sent part of a multi-record request before reporting
incomplete progress. Only successful completion counts are confirmed; a
cancelled/fatal write has no reliable delivered-prefix count. A higher-level
stream adapter must preserve that uncertainty when reporting acceptance or
flush failure. The copied pending request remains immutable until completion
or destruction.

## EOF and shutdown

`Read::Closed` means OpenSSL received the peer's authenticated `close_notify`.
The state becomes `PeerClosed`; repeated reads report the same EOF locally.
Application writes are no longer admitted. The session stays live so the caller
can send its own notification through `shutdown()` or explicitly destroy it.

Transport EOF without `close_notify` returns `Cause::Truncated`, including
OpenSSL 3's `SSL_R_UNEXPECTED_EOF_WHILE_READING`. It is never normalized to
`Read::Closed`. Other protocol and system failures retain their native details.
Fatal SSL/SYSCALL errors destroy the session without a later shutdown attempt.

`shutdown()` requires no pending application read/write. It enters `Closing`:

- Native return 1 completes both directions, frees TLS resources and returns
  `Shutdown::Complete` with state `Closed`.
- Native return 0 returns `Shutdown::Sent`: local notification succeeded, but
  peer notification remains pending. The wrapper does not call `SSL_get_error`
  for this successful incomplete result.
- A negative return is classified immediately as WANT or an error. Retry only
  `shutdown()` after readiness; application I/O stays disabled.

`Sent` alone is not a bidirectional clean shutdown. The caller decides whether
its application framing permits abandonment, or continues to the peer's alert
under its deadline. The socket remains borrowed throughout.

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
other platforms or complete security-family coverage. The
[`ext::tls_stream`/HTTPS guide](extended-https-fetch.md) records a separate
accepted adapter/application gate: 62 cases across four groups pass in 14.44 s,
covering stream progress, verification/HTTP failures, limits and binary framing
(`target/stdlib-work/https-fetch-execution-current.log`). That profile uses
numeric endpoints, explicit trust/identity, deadlines and manual cleanup.
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
