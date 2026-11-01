# URL HTTP(S) client

Status: all five modules are implemented. Direct URL contracts/models/owners,
selected-socket adoption, plain/DNS/TLS exchanges, connector admission/failure
groups and the real fetch program's functional groups pass on their documented
finite Linux x86_64 profiles. Registered Rust runtime tests, complete wrapper
allocation-failure campaigns and broader scheduling/clock cases have no pass
claim. The [URL client guide](extended-url-client.md) records exact accepted
receipts and remaining gaps. The full standard and extended library goal
remains open.

## Purpose and existing boundaries

Make one URL produce one bounded HTTP or verified HTTPS exchange. Reuse
[`uri`](../extended/ext/uri.lani), [`resolve`](../stdlib/std/resolve.lani),
[`socket`](../stdlib/std/socket.lani), the canonical
[`HTTP client`](../extended/ext/http_client.lani) and
[`HTTPS client`](../extended/ext/https_client.lani). Native OpenSSL continues to
own certificate verification and cryptography.

Socket adoption is the required transport boundary: the existing numeric
`Prepared.begin` and `https_client::begin_with_context_until` consume preparation
and open their own socket. Selecting a connected socket and then reconnecting
through those functions would discard the selection. The new adoption paths
transfer the selected owner into those same drivers. Existing numeric-endpoint
APIs retain their distinct explicit transport use. There is no second HTTP
parser or request engine.

There are five source boundaries:

| Module | Responsibility and native dependencies |
| --- | --- |
| [`ext::host_name`](../extended/ext/host_name.lani) | Pure shared DNS byte policy; no allocation or host calls |
| [`ext::http_url`](../extended/ext/http_url.lani) | Owned URL planning; allocation-backed, with no DNS, sockets or TLS |
| [`ext::url_connect`](../extended/ext/url_connect.lani) | One canonical resolver/TCP selector and owned Connection; no HTTP/TLS imports or OpenSSL link dependency |
| [`ext::url_client`](../extended/ext/url_client.lani) | Plain HTTP preparation, selected-socket adoption and exchange; no OpenSSL source/link dependency |
| [`ext::url_tls`](../extended/ext/url_tls.lani) | Verified HTTPS facade over the same connector and canonical HTTPS driver; explicit OpenSSL/native libraries |

The split follows an actual dependency observation. The import-only native-link
control in `target/stdlib-work/url-https-import-only-compile-first.log` failed
before producing an executable: LNC0059 wrapped native linker errors for
unresolved OpenSSL symbols such as `ERR_get_error` and `SSL_CTX_new`. Importing
TLS sources therefore cannot be treated as an optional runtime branch of a
plain facade. HTTPS lives in `url_tls`, so an HTTP-only program can import
`url_client` without SSL/crypto libraries. This is a source dependency decision,
not a compiler repair. The direct plain URL executable compiles and runs
without SSL/crypto libraries; its only NEEDED library is libc.so.6.
No combined-facade alias is retained. No compiler, IR, ABI, proof, native glue
or custom cryptographic implementation change is planned.

## Specifications and chosen profile

[RFC 3986 sections 3.2 and 7.4](https://www.rfc-editor.org/rfc/rfc3986.html#section-3.2)
separate generic authority syntax from host interpretation and describe legacy
numeric-address ambiguities. This client adopts the narrower policy below.
[RFC 9110 section 4.2](https://www.rfc-editor.org/rfc/rfc9110.html#section-4.2)
defines the HTTP schemes and discourages userinfo;
[RFC 9112 section 3.2.1](https://www.rfc-editor.org/rfc/rfc9112.html#section-3.2.1)
defines origin-form targets. The URL host supplies the reference identity,
independently of resolved addresses or peer certificate contents, following
[RFC 9525 section 6.1](https://www.rfc-editor.org/rfc/rfc9525.html#section-6.1).
An IP identity uses IP SAN matching and no DNS SNI; DNS matching and SNI remain
separate operations in the existing OpenSSL wrapper. See
[RFC 9525 section 7.4](https://www.rfc-editor.org/rfc/rfc9525.html#section-7.4)
and [OpenSSL hostname configuration](https://docs.openssl.org/3.0/man3/SSL_set1_host/).

### URL policy

- Require an absolute `http` or `https` scheme, compared case-insensitively,
  and a nonempty authority/host. Reject userinfo, including an empty userinfo.
- Accept strict existing IPv4 and bracketed IPv6. Reject IPvFuture, IPv6 zone
  identifiers, percent-encoded hosts, raw non-ASCII and backslashes. Already
  encoded ASCII IDNA A-label spelling is ordinary DNS input; no IDNA conversion
  or validation beyond this byte profile is promised.
- For DNS, share the exact current OpenSSL DNS byte checks, with a URL-specific
  cap of 253 bytes (TLS retains its configured identity limit):
  nonempty 1..63 byte labels, ASCII letters/digits/hyphens, no leading/trailing
  label hyphen or trailing dot, and at least one letter. Single-label names
  remain allowed under explicit system NSS policy; no global-DNS-name promise.
- First classify strict IPs. Reject remaining classic numeric candidates:
  one through four dot-separated parts, each either decimal digits or `0x`/`0X`
  followed by hexadecimal digits. Thus `127.1`, `0177.0.0.1`, `2130706433`,
  `0x7f000001` and `127.0x0.0.1` cannot become DNS identities while libc routes
  them numerically. This lexical rejection is URL policy, not an extension of
  the shared DNS validator. It does not implement an address-access policy.
- Default port is 80/443. A present port must contain decimal digits, have
  checked numeric value 1..65535, and fit without overflow. An explicitly empty
  port is rejected. Preserve explicit leading zeros and explicit default port
  spelling in Host authority; use the checked value for the endpoint.
- Preserve authority case, bracket spelling, path escapes, literal dot segments
  and repeated slashes. The request target is path plus an optional `?` and
  query; an empty path becomes `/`. Preserve an explicitly empty query. Accept
  and discard a syntactically valid fragment; never transmit it or treat it as
  request-target bytes. No percent decoding or normalization occurs.
- DNS identity is the original host bytes, excluding port. IPv6 IP identity
  excludes brackets and port. Never derive identity or Host from a chosen IP,
  resolver canonical name, reverse lookup or certificate. No redirects,
  proxies, pooling, automatic retries after TCP selection or relative URLs in
  this increment. `uri_resolve` remains available for a later explicit policy.

## Pure public API

Signatures below abbreviate standard qualified types. Records shown as owners
have implementation fields, one active cleanup authority and explicit destroy.

```lani
// ext::host_name: extract the current checked_identity DNS checks once.
pub enum Error { Bounds, Empty, Limit, Nul(i32), Invalid(i32) }
check_dns(bytes:View<u8>, maximum_bytes:i32) -> Result<i32,Error>

// ext::http_url
pub enum Scheme { Http, Https }
pub enum HostKind { Dns, Ipv4, Ipv6 }
pub struct Limits { url_bytes:i32, target_bytes:i32 }
pub enum ErrorKind {
    Bounds, InvalidLimits, Uri, Scheme, Authority, Userinfo, Host, Port,
    TargetLimit, AllocationFailed
}
pub struct Error { kind:ErrorKind, offset:i32, syntax:Option<uri::Error> }
default_limits() -> Limits
parse(input:View<u8>, limits:Limits) -> Result<Url,Error>
Url.borrow() -> &Url
Url.is_open() -> bool
Url.scheme() -> Option<Scheme>
Url.host_kind() -> Option<HostKind>
Url.host() -> Option<View<u8>>
Url.ip() -> Option<net::IpAddr>
Url.port() -> Option<u16>
Url.authority() -> Option<View<u8>>
Url.target() -> Option<View<u8>>
Url.destroy() -> bool
```

`host_name::check_dns` is allocation-free and performs no host calls. Its offset
is relative to its input. Nonpositive `maximum_bytes` reports Limit; the caller
selects its policy cap. `openssl_tls::checked_identity` maps these results to
its existing Bounds/Identity/Limit/Nul errors, preserving existing TLS behavior,
limits and IP validation. There is one DNS validation implementation.

URL defaults are 16384 URL bytes and 8192 target bytes; both limits must be in
1..1048576. Parse validates the full logical input with `uri::parse_with_limit`,
then the profile, checked port and target length before allocating. It packs
its owned URL bytes and target into bounded storage; getters borrow only that
storage. Input may have a nonzero start or signed stride and may be released
after success. No NUL terminators are exposed. Error offsets are logical raw
URL byte offsets; -1 means no particular byte. Uri errors retain the original
typed diagnostic in `syntax`; other errors have None there. Local syntax and
policy errors take precedence over allocation failure.

Destroy is idempotent, returns whether it released an active owner, and makes
all getters return None. Borrowed views become invalid at destroy. Shallow
copies do not create another owner. Failed construction releases every partial
allocation. Storage is bounded by the URL/target caps and actual Vec capacities;
this is not a process-wide memory cap.

## Driver adoption and ownership

```lani
// ext::http_client
Prepared.adopt_connected(socket:&std::socket::Socket) -> Result<Exchange,Failure>
Exchange.run() -> Result<Response,Failure>

// ext::https_client
adopt_connected_with_context_until(prepared:&http_client::Prepared,
    socket:&std::socket::Socket, context:&openssl_tls::Context,
    identity:openssl_tls::Identity, options:Options) -> Result<Exchange,Failure>
Exchange.run() -> Result<http_client::Response,Failure>
```

Both adopters consume an active Prepared and invalidate the supplied Socket
owner on **every outcome**, including invalid options, expired deadline,
inactive Prepared, closed/unconnected socket, identity error or allocation
failure. Inactive Prepared stays inactive. Implement Socket transfer with the
actual `take_handle()` plus `from_owned_handle(handle,family,kind)` APIs;
`take_handle` sets the original handle to -1. Do not borrow a live descriptor
without transferring it or create a second owner by copying its record.

Socket metadata validity remains the existing Socket construction precondition.
Adoption rejects closed/non-TCP metadata, proves nonblocking mode and queries
the peer to reject unconnected sockets. Native queries use the Prepared HTTP
I/O quota and deadline; invalid input uses existing Io(InvalidInput) metadata.
The plain driver begins its existing Protocol phase. The TLS driver retains
Context/copies identity as today, then begins Attach. Neither opens, connects,
sends or handshakes during adoption. TLS Session construction stays in the
existing driver. The HTTP deadline, work and preparation counters are retained.

Failure closes the transferred socket at most once, aborts Protocol and frees
retained context/name/session owners. Preserve the primary failure and any
close error in existing `Failure.cleanup`; never overwrite one with the other.
Socket close retires the library token even when the host reports failure;
do not retry close on a possibly reused descriptor.

`run()` drives the same existing step/interest/before_wait engine and poll loop
to completion using its stored deadline. Factor current synchronous exchange
loops into it; keep one implementation per existing transport. It accepts an
active Exchange, including one previously stepped by its caller. On terminal
error it preserves current driver cleanup. A subsequent run on a Failed owner
returns its sticky failure; Complete/Aborted owners return Inactive and cannot
republish a Response. TLS counters remain
readable as metadata after completion. Existing numeric APIs keep their
ownership and runtime behavior; they are not deprecated-name aliases.

## Connector API and manual ownership

The connector's exact public types are separate from HTTP/TLS diagnostics.
Qualified standard names are abbreviated below, as in the pure API section.

```lani
// ext::url_connect: no HTTP, HTTPS or OpenSSL import.
pub struct Options {
    family:resolve::Family, addr_config:bool, max_results:i32,
    max_attempts:i32, socket_calls:u64, attempt_timeout:time::Duration
}
pub struct Stats {
    resolver_calls:u64, addresses:i32, attempts:i32,
    socket_calls:u64, polls:u64
}
pub enum Stage { Validate, Resolve, Open, Connect, Poll, Verify, Close }
pub enum Cause {
    InvalidState, InvalidOptions, NoAddresses, Exhausted, AttemptLimit,
    CallLimit, Timeout, Clock(clock::Error), Time(time::Error),
    Resolve(resolve::Error), Io(io::Error)
}
pub struct AttemptFailure { index:i32, endpoint:net::SocketAddr,
    stage:Stage, cause:io::Error, timed_out:bool }
pub struct Failure {
    stage:Stage, cause:Cause, stats:Stats, index:i32,
    endpoint:Option<net::SocketAddr>, last_attempt:Option<AttemptFailure>,
    cleanup:Option<io::Error>
}
pub struct ConnectionInfo { index:i32, endpoint:net::SocketAddr,
    stats:Stats, last_attempt:Option<AttemptFailure> }
default_options() -> Options
validate_options(options:Options) -> Result<bool,Cause>
connect_until(url:&http_url::Url, options:Options, deadline:time::Deadline)
    -> Result<Connection,Failure>
Connection.borrow() -> &Connection
Connection.socket() -> &socket::Socket
Connection.info() -> ConnectionInfo
Connection.close() -> Result<bool,io::Error>
```

Connection owns the selected Socket and immutable connection metadata. It has
one cleanup authority. Transfer that Socket through an adopter or explicitly
close it; a shallow record copy does not duplicate ownership. Close follows the
existing retire-once Socket rule. After adoption the original Socket token is
inactive, so a later Connection close cannot close the adopted generation.
The caller must not manufacture another owner from the inspection/borrowed
socket. Failure and ConnectionInfo carry metadata only, including nested
resolver/clock diagnostics; neither owns a descriptor or result-vector backing.

Connector defaults are family Any, addr_config false, 32 results, 16 attempts,
512 socket calls and 5 seconds per attempt. Results and attempts must each be
1..4096. Attempt duration must be normalized and nonzero. Invalid deadline
nanoseconds report InvalidOptions before native effects. `socket_calls` accepts
any u64, including zero; fewer than two credits fails CallLimit before lookup.

For DNS, call `resolve::lookup(Name(host),Port(port),...)` at most once, with
Tcp, mapping Disabled, caller family/addr_config, host cap 253, service cap 5
and max_results. Preserve result order, duplicates and scope values. Numeric
URLs construct one value from strict core parsing, bypass NSS, and obey an
explicit family restriction; mismatched numeric family gives NoAddresses.
`addresses` counts available candidates, not successful sockets. This module
can select TCP for either admitted URL scheme; it never implements TLS or HTTP.

## Plain and verified TLS facade APIs

```lani
// ext::url_client: plain HTTP only, no OpenSSL imports.
pub struct Request { method:View<u8>, headers:View<http::Field>, body:View<u8> }
pub struct Options { connection:url_connect::Options, http:http_client::Options }
pub enum Stage { Validate, Prepare, Connect, Adopt, Exchange }
pub enum Cause {
    InvalidState, SchemeMismatch, ConnectionOptions(url_connect::Cause),
    Connect(url_connect::Failure), Http(http_client::Failure)
}
pub struct Failure {
    stage:Stage, cause:Cause, connection:Option<url_connect::ConnectionInfo>,
    http:Option<http_client::Stats>, cleanup:Option<io::Error>
}
default_options() -> Options
exchange_until(url:&http_url::Url, request:Request, options:Options,
    deadline:time::Deadline) -> Result<Response,Failure>
Response.borrow() -> &Response
Response.is_open() -> bool
Response.http() -> &http_client::Response
Response.connection() -> url_connect::ConnectionInfo
Response.destroy() -> bool

// ext::url_tls: explicitly requires the native OpenSSL libraries.
pub struct Options { request:url_client::Options, tls:https_client::Options }
pub enum Stage { Validate, Identity, Prepare, Connect, Adopt, Exchange }
pub enum Cause {
    InvalidState, SchemeMismatch, InvalidOptions,
    ConnectionOptions(url_connect::Cause), Identity(openssl_tls::Error),
    Connect(url_connect::Failure), Http(http_client::Failure),
    Https(https_client::Failure)
}
pub struct Failure {
    stage:Stage, cause:Cause, connection:Option<url_connect::ConnectionInfo>,
    http:Option<http_client::Stats>, tls:Option<https_client::TlsStats>,
    cleanup:Option<io::Error>
}
default_options() -> Options
exchange_until(url:&http_url::Url, context:&openssl_tls::Context,
    request:url_client::Request, options:Options, deadline:time::Deadline)
    -> Result<Response,Failure>
Response.borrow() -> &Response
Response.is_open() -> bool
Response.http() -> &http_client::Response
Response.connection() -> url_connect::ConnectionInfo
Response.tls_stats() -> https_client::TlsStats
Response.destroy() -> bool
```

These are two distinct Response owners over the existing canonical HTTP
Response. Only the TLS facade adds actual TLS counters; plain responses have
no fabricated optional TLS field. `url_client` requires Http; `url_tls` requires
Https. A mismatch fails before DNS/socket effects. Request cannot override the
URL authority or target. Both construct the canonical Request and prepare it
exactly once before lookup. Connector options, live URL and canonical request
admission precede lookup; TLS also checks context/identity/options first.

Plain default options use `url_connect::default_options` and default HTTP options
with Trailing::Reject. TLS defaults compose those plain options with existing
HTTPS defaults. There is no hidden widening of HTTP/TLS or connector budgets.
Both facade Failures retain transport-specific typed errors and snapshots.
A failed connector is nested in Cause::Connect with its current endpoint and
last attempt; `Failure.connection` is None until TCP selection actually
succeeds. HTTP preparation stats can already be Some. TLS stats remain None
until the existing TLS driver supplies them; no zero activity is invented.

Each successful Response destroys its canonical HTTP owner once and returns
whether it was active. Its HTTP/body/header borrows are usable only before
destroy. Keep the Response alive through output/report publication. URL,
resolver result vectors, Prepared and Socket owners do not escape through it.
The caller owns the borrowed TLS Context throughout the synchronous call and
may release request/URL backing after return. Adoption and exchange use the
same stored deadline and the same canonical driver run loops described above.

## Connection, time and fallback rules

The canonical `url_connect` connector opens at most one socket at a time. A
zero-based attempt index is the original result ordinal; every attempted candidate counts once,
even when socket creation fails. Before each attempt derive
`min(global deadline, now + attempt_timeout)` with checked time arithmetic.
The global deadline is never extended or restarted. A fresh check after a
blocking operation can reject an otherwise successful result as expired.

Use existing socket create/connect/wait_ms/take_error/peer_addr leaves, with
clock checks before and after each attempt. Advisory readiness is not success:
pending connect needs SO_ERROR and actual peer proof. ENOTCONN after a zero
SO_ERROR returns to bounded polling. EINTR from poll consumes its call and
retries within the same deadlines. Do not call the uncounted convenience
`Socket.connect_until` under an advertised physical-call cap.

`socket_calls` counts actual socket creation, connect, poll, SO_ERROR, peer
query and failed-attempt close calls issued by this connector, including
failed/EINTR calls. It excludes clocks, NSS, allocation, adoption and subsequent
driver calls; those retain their own explicit accounting. Keep one unused close
credit while a connector-owned socket is live. Other calls cannot spend it.
Release this reservation when ownership transfers; charge it only if close is
actually issued. No retry or next candidate follows a close error.

Endpoint refusal/unreachable/timeout/address-unavailable failures may advance
after cleanup: Linux connect/SO_ERROR errno 111, 101, 113, 110, 99 or 100, and
an attempt deadline while the global deadline remains live. Unsupported socket
family/protocol (open errno 97/93) may also advance. Other open failures,
including descriptor exhaustion and memory pressure, are terminal. Poll/query
syscall failure, invalid native result, allocation, clock, time arithmetic,
global deadline, limits, invalid input and cleanup failures are terminal.
Unexpected connect errors, including EINTR, are terminal after cleanup; no
uncertain connect is retried on the same descriptor.

Native leaf results are recorded before the post-call clock/deadline check.
If that check reports a clock failure or an expired global deadline, return
Clock or Timeout as the terminal primary failure. Preserve any reached native
error in last_attempt, including its actual stage and endpoint, rather than
replacing it with a synthetic clock error. A close failure remains secondary in
cleanup; neither it nor a saved native error may overwrite the terminal clock/
global-time cause. When the post-call check succeeds, the original native
failure retains its ordinary classification and fallback policy, even if only
the per-attempt deadline expired. Eligible native errors may advance after
close while the global deadline is healthy. A successful native leaf followed
by local attempt expiry instead records a timed-out endpoint failure with
Host(110), then may advance. Attempt-only expiry does not erase a reached
native error.

An attempt close error remains secondary to the primary attempt/global failure.
After all available candidates fail, return Exhausted plus last_attempt. If
untried results remain when the attempt cap is reached, return AttemptLimit.
Limit/clock/global-time failures retain last_attempt without recasting it as
their primary cause. Only the latest completed endpoint failure is retained;
there is no unbounded error list. Fields index/endpoint identify the current
attempt, or -1/None before any attempt. HTTP/TLS snapshots are None until those
engines actually exist; do not fabricate zero-valued activity.

**The first proven TCP connection ends fallback.** Transfer that exact socket
generation to the canonical driver. Adoption, TLS verification/handshake, HTTP
send/receive/parser/decode/shutdown or output failure cannot restart resolution
or try another endpoint, even for GET or when no HTTP bytes have yet been sent.
Success and failure release every resolver address-vector owner. A failed
adoption consumes the selected socket as specified above.

System NSS lookup is synchronous and uninterruptible here. Deadline checks
before/after it cannot bound its wall time, retries, native allocations, files,
threads or network work. Caller-owned TLS trust/credential construction has
the same blocking qualification. The real program starts its deadline before
URL/context preparation so elapsed time is included at later checks; no hard
whole-command wall-time promise follows. Socket/HTTP/TLS quotas do not include
libc/OpenSSL internal work. Process SIGPIPE policy stays an explicit caller
responsibility, as in current fetch programs.

## Program migration and focused acceptance

The ordinary fetch front door is now `fetch URL [OPTIONS]`, preserving
method/body/header and bounded output behavior from `http_fetch` and verified
CA/client-credential handling from `https_fetch`. It uses `--ca-file`, or default
trust paths when omitted, and rejects TLS-only options on Http explicitly.
The separate numeric endpoint/identity programs retain their distinct transport
test policy. There is no old-CLI parser or compatibility alias. The
[program guide](extended-fetch-url.md) records its exact CLI statuses, help,
limits and accepted functional receipts.

The acceptance requirements below remain split by causal boundary. The current
finite gates are summarized afterward; an unexercised item here is not accepted
merely because an adjacent case passed.

1. Pure URL/helper gates: independent mapping goldens for authority, port,
   numeric ambiguity, quotes/invalid bytes, path/query/fragment, case, stride,
   caps and owned-input release. Shared DNS refactor must preserve old TLS
   diagnostics. Deny every reached URL construction allocation.
2. Adoption gates: active/inactive Prepared; closed, UDP, blocking and
   unconnected socket rejection; expired deadline and TLS setup OOM. Prove
   both original owners inactive on every result, exact selected FD generation
   reaches send/receive or TLS BIO attachment, and no open/connect after
   handoff. Preserve primary and close errors; no reused-descriptor close retry.
3. Resolver/connector gates: controlled native resolver order/duplicates,
   refusal then success, attempt timeout then success, cap/exhaustion,
   zero-call admission, native EAI/system diagnostics and noDNS numeric path.
   Invalid request/identity/options produce no lookup or socket activity.
   Exercise post-leaf Clock/global Timeout with the reached native diagnostic
   retained in last_attempt and close failures only in cleanup; check the
   reserved close credit even when ordinary call allowance is exhausted.
4. Connected HTTP/TLS gates: exact encoded request target and Host; DNS name
   resolving to loopback retains DNS verification/SNI; numeric IP SAN has no
   SNI. A certificate matching only the chosen address fails the DNS request
   and never connects to a spare candidate. Post-send failure also cannot
   contact a spare. Check original deadline under delayed native lookup and
   peer stalls without calling blocking NSS deadline-cancellable.
5. Resource/failure gates: binary/empty response, ownership through output,
   individually reached wrapper OOM and connector I/O/cleanup faults. Reuse
   verified full-width raw allocation sites supporting 0x22 and 0x62, native
   resolver G/F observations and existing OpenSSL resource observers. Separate
   wrapper source allocations from loader/NSS/OpenSSL owners; do not reuse old
   MAP_32BIT-only filters or claim native internals under source quotas.
6. Dependency gates: an HTTP-only native-link import/exchange has no unresolved
   OpenSSL symbols or SSL/crypto library requirement. The explicit TLS module
   uses the existing native-library profile. The first import-only linker
   failure is preserved separately and is not executable workflow evidence.
7. One actual migrated program gate against independent plain and OpenSSL
   peers, plus only affected existing numeric driver groups. Do not rerun the
   broad library suite by default.

### Current finite acceptance

| Boundary | Accepted evidence | Remaining scope |
| --- | --- | --- |
| URL/helper | Public contracts, 70 model records on two backing layouts and 16 owner/failure cases, including four reached allocation denials | Other targets and broader profiles remain separate |
| Driver adoption | Public smoke, one connected same-generation case and eight failure cases, including reached close EIO | These plain-adoption failures do not establish every TLS setup OOM path |
| Plain exchange | Two direct fixed/interim-chunked numeric cases with exact binary wire and pre-exit resource checkpoints | Full wrapper allocation campaign remains open |
| DNS selection | One controlled four-address ordered fallback case, selected ordinal one after two attempts, preserved duplicate list and retired failed socket | NSS cancellation, native internal quotas and asynchronous policy remain open |
| Verified TLS | Eight cases across TLS 1.2/1.3, original DNS/SNI and numeric IP SAN/no SNI, identity mismatch before HTTP, authenticated truncation and no spare-endpoint/request replay | Every TLS schedule and wrapper source-OOM path is not established |
| Connector boundaries | Twelve admission and eight failure/cleanup cases, separately: local deadlines/caps/family before attempt, refusal, reserved close credit, attempt cap/exhaustion, native EAI/system diagnostics, idempotent close and reached close EIO | Attempt-timeout fallback and arbitrary post-leaf clock faults remain unexercised by this selection |
| Link dependency | Plain executable links/runs without SSL/crypto; TLS explicitly links native ssl/crypto | No other host target implied |
| Real program | Separate direct groups of 24 HTTP, 33 CLI/preflight and four HTTPS functional cases | Full application source-owner/OOM/fault acceptance remains separate |

Exact source identities, logs and checkpoint qualifications belong to the
[URL](extended-http-url.md), [connected-client](extended-url-client.md),
[fetch](extended-fetch-url.md) and fixture guides. These are direct executable
receipts, not native Rust-libtest passes. A confirmed
[constructor-name-resolution reduction](../tests/fixtures/compiler_dependencies/url_none_inference/README.md)
has an executable module-qualified Option control; no general generic payload
limitation or compiler repair is claimed by this increment.

Root serializes all compiler/native commands, each under two minutes. The
native target is Linux x86_64/glibc/OpenSSL using GPU-compiler output executed
on CPU. Pure URL/helper receipts have their own allocator/host effect scope;
no GPU-device execution claim is implied. This plan records the agreed
implementation boundaries; its declarations and source presence are not
runtime acceptance.
