# HTTP and HTTPS from a URL

The URL client composes owned URL parsing, ordered TCP selection and the
existing HTTP drivers. The selected APIs execute on **Linux x86_64/glibc**, with
OpenSSL 3 required for HTTPS. Compiler execution on the GPU produces these CPU
programs; these receipts do not establish user-program GPU execution.

The direct plain, DNS, TLS and connector boundary/failure groups pass. The
registered Rust tests have no runtime-pass claim. The full
standard and extended library goal remains open. The
[implementation plan](library-url-client-plan.md) retains the agreed boundaries
and remaining acceptance work; the real [fetch program](extended-fetch-url.md)
has its own functional receipts.

## Layers and effects

| Module | Responsibility | Effects and dependencies |
| --- | --- | --- |
| [`ext::host_name`](../extended/ext/host_name.lani) | Shared ASCII DNS identity admission | No allocation, lookup or host call |
| [`ext::http_url`](extended-http-url.md) | Validate an absolute HTTP(S) URL and own its host, authority and target bytes | Allocator backing only; no DNS, socket, file or TLS operation |
| [`ext::url_connect`](../extended/ext/url_connect.lani) | Resolve once, try endpoints in order and return one owned TCP connection | Synchronous libc NSS for DNS names; native sockets and clocks; no HTTP or TLS import |
| [`ext::url_client`](../extended/ext/url_client.lani) | Prepare one plain HTTP request, adopt the selected socket and run the canonical driver | Native plain HTTP; no SSL/crypto link requirement |
| [`ext::url_tls`](../extended/ext/url_tls.lani) | Verify the original URL identity and run HTTPS over the same selected socket | Explicit OpenSSL Context and native `ssl`/`crypto` libraries |

The [URL guide](extended-http-url.md) owns syntax, limits and indexed parser
errors. The canonical [HTTP](extended-http-client.md) and
[HTTPS](extended-https-client.md) drivers own serialization, HTTP framing,
decoding and TLS state. There is one HTTP protocol engine. OpenSSL performs
certificate verification and all TLS cryptography.

## Exchange API

The plain facade exposes:

```text
url_client::Request { method: View<u8>, headers: View<http::Field>, body: View<u8> }
url_client::Options { connection: url_connect::Options, http: http_client::Options }
url_client::default_options() -> Options
url_client::exchange_until(url: &http_url::Url, request: Request,
    options: Options, deadline: time::Deadline) -> Result<Response, Failure>
```

It accepts only `Scheme::Http`. Its default HTTP trailing-byte policy is
`Trailing::Reject`. The request cannot override the URL-derived authority or
target. The facade checks a live URL and connector options, then canonically
validates and copies the request **before** lookup or socket creation.

HTTPS exposes:

```text
url_tls::Options { request: url_client::Options, tls: https_client::Options }
url_tls::default_options() -> Options
url_tls::exchange_until(url: &http_url::Url, context: &openssl_tls::Context,
    request: url_client::Request, options: Options, deadline: time::Deadline)
    -> Result<Response, Failure>
```

It accepts only `Scheme::Https`. The caller supplies a live configured Context
and retains its ownership through the synchronous call. A zero TLS-call budget,
invalid Context or inadmissible identity fails before lookup or socket creation.
Context trust/credential construction is a separate explicit operation.

Both Response types expose `borrow`, `is_open`, `http`, `connection` and
`destroy`. `http()` requires an active owner and borrows the canonical HTTP
Response. `connection()` returns value metadata about the selected endpoint.
The TLS Response also exposes `tls_stats()`. Neither response owns the URL or
request input; both own the returned HTTP storage until explicit destruction.

### Ownership through the call

1. The caller owns a parsed Url and live request backing. Its views must remain
   valid through the synchronous call.
2. Canonical preparation owns independent request storage. A connector failure
   destroys that Prepared owner.
3. The connector owns at most one socket at a time and releases its resolver
   result vector on success or failure.
4. Adoption consumes Prepared and invalidates the selected Socket token on
   **every** result. The existing driver becomes its sole cleanup authority.
5. The driver returns an owned HTTP Response or cleans up on failure. Keep a
   successful facade Response alive through body/header use and output.
6. Call `Response.destroy()` once when finished. It returns true for the active
   owner and false afterward. Its borrowed HTTP/body/header views expire then.
   Destroy the independent Url when its own borrows are no longer needed.

Lanius does not yet enforce these lifetimes or insert automatic destruction.
A shallow record copy creates no second cleanup authority. Source conventions
and executable checks establish this manual policy; they are not a borrow
checker or a formal memory-safety proof. A later ownership language can change
the mechanism while retaining these transfer, error and lifetime contracts.

### Selected-socket adoption

The shared drivers expose the handoff directly:

```text
http_client::Prepared.adopt_connected(socket: &socket::Socket)
    -> Result<http_client::Exchange, http_client::Failure>
https_client::adopt_connected_with_context_until(prepared: &http_client::Prepared,
    socket: &socket::Socket, context: &openssl_tls::Context,
    identity: openssl_tls::Identity, options: https_client::Options)
    -> Result<https_client::Exchange, https_client::Failure>
```

Both consume Prepared and transfer/disarm the Socket token before any return,
including errors. Closed, non-TCP, blocking or unconnected inputs fail. The
nonblocking and peer queries use the existing HTTP quota/deadline. Adoption
does not open, connect, send or handshake. Plain starts the existing Protocol
phase; TLS retains Context/identity and starts Attach with no Session yet.
Close errors retire the token once and remain secondary diagnostics.

Each Exchange's `run()` uses its existing step/readiness/poll engine and stored
deadline. It can resume an active Exchange already stepped by its caller.
Failed owners retain their sticky failure; Complete/Aborted owners report
Inactive and cannot republish a Response. The older numeric endpoint entry
points retain their separate transport policy and are not aliases.

## TCP selection and budgets

```text
url_connect::Options {
    family: resolve::Family, addr_config: bool, max_results: i32,
    max_attempts: i32, socket_calls: u64, attempt_timeout: time::Duration
}
url_connect::default_options() -> Options
url_connect::validate_options(options: Options) -> Result<bool, Cause>
url_connect::connect_until(url: &http_url::Url, options: Options,
    deadline: time::Deadline) -> Result<Connection, Failure>
```

Defaults are family Any, `addr_config=false`, 32 results, 16 attempts, 512
socket calls and five seconds per attempt. Results and attempts each admit
1..4096. Attempt duration must be normalized and nonzero. A deadline with
invalid nanoseconds fails admission. Socket-call budgets zero and one are
valid values that fail `CallLimit` before NSS or socket work.

Numeric URLs bypass resolution and obey the requested family restriction.
A mismatch returns `NoAddresses`. DNS URLs invoke the system resolver at most
once, with TCP, address mapping disabled, host cap 253 and service cap five.
Returned ordering, duplicates and scope values are preserved. `max_results`
bounds the returned vector; it cannot bound native NSS work.

Each attempt uses the smaller of the absolute caller deadline and
`now + attempt_timeout`, with checked arithmetic. The global deadline never
restarts. Advisory readiness is insufficient: a pending connection requires
SO_ERROR and an actual peer query. A zero SO_ERROR followed by ENOTCONN returns
to bounded polling. Poll EINTR consumes a call and may retry within the same
deadlines.

`Stats` contains `resolver_calls`, `addresses`, `attempts`, `socket_calls` and
`polls`:

- `resolver_calls` counts API invocations, including a local staging failure
  before native NSS. It is not necessarily a count of native `getaddrinfo` calls.
- `addresses` counts available candidates. `attempts` counts actual socket
  creation attempts, including failed creates. `ConnectionInfo.index` is the
  selected candidate's original zero-based ordinal.
- `socket_calls` counts actual connector create, connect, poll, SO_ERROR, peer
  query and failed-attempt close calls, including failed calls. It excludes
  clocks, lookup, allocation, adoption and subsequent HTTP/TLS operations.
- One close credit is reserved before opening a socket and while it remains
  connector-owned. Cleanup may use that credit after ordinary call admission
  fails. Successful transfer releases the reservation without charging it.

A standalone Connection exposes `borrow`, `socket`, `info` and `close`.
`socket()` borrows the actual transfer token; it does not create another owner.
`close()` returns `Ok(true)` after successful retirement or `Ok(false)` if the
token was already closed/adopted. A close error still retires the library token;
retrying close could hit a reused descriptor and is forbidden.

### Fallback ends at the first proven TCP connection

Endpoint refusal/unreachable/timeout/address-unavailable failures may advance
after successful cleanup: Linux errno 111, 101, 113, 110, 99 and 100. An attempt
timeout may advance while the global deadline remains live. Unsupported socket
family/protocol at open, errno 97/93, may also advance.

Other native failures, local resource exhaustion, malformed results, clock/time
errors, the global deadline, quota failures and cleanup errors are terminal.
An unexpected connect error, including EINTR, is terminal after cleanup.
Exhausting all candidates returns `Exhausted`; reaching the attempt cap with
untried candidates returns `AttemptLimit`.

**The first proven TCP connection ends selection.** The canonical driver adopts
that exact socket generation. Adoption, TLS verification/handshake, HTTP
send/receive/decode/shutdown or output failure cannot contact a spare endpoint,
repeat resolution or replay the request, regardless of the HTTP method.

## Errors and identity

Connector Failure carries `stage`, typed `cause`, statistics, current
`index`/`endpoint`, the latest endpoint `last_attempt` and secondary `cleanup`.
Before any actual create attempt, index is -1 and endpoint is None. Diagnostic
records own no socket or allocation backing.

A native failure is recorded before the following clock/deadline check. A
reached Clock or global Timeout becomes primary while `last_attempt` retains
the reached native diagnostic. A close error remains secondary in `cleanup`.
An already terminal control failure is preserved through cleanup. Local
attempt expiry does not erase a reached native error. The connector retains
only the latest endpoint failure, never an unbounded list.

Facade Failure adds a stage and transport-specific typed error. Connection
metadata is None until TCP selection succeeds; HTTP statistics can already
exist after preparation. TLS statistics are absent until the TLS driver
supplies them. No zero-valued activity is fabricated for an engine that did
not exist. The generated declaration pages retain every variant and field.

HTTPS verifies the original URL host. A DNS URL supplies that name for
certificate matching and SNI even when lookup selects an IP address. Numeric
URLs use IP SAN matching without DNS SNI; IPv6 identity omits URL brackets.
Resolver canonical names, reverse lookup, selected IPs and peer certificate
contents never replace the reference identity or Host authority.

Caller SIGPIPE policy remains explicit. Blocking NSS and Context construction
are not deadline-cancellable here. Checks before/after them can reject elapsed
results but cannot impose a hard wall-time limit. Source byte/call budgets
exclude libc/OpenSSL internal allocations, files, threads and network work.

## Native execution evidence

These are direct executable receipts from GPU-compiler output running on a
Linux x86_64 CPU. They are separate groups, not a combined distinct-case count
and not passing Rust libtests. Logs are under `target/stdlib-work/`.

| Receipt | Accepted finite scope |
| --- | --- |
| [Pure URL contracts, model and owners](extended-http-url.md#executable-evidence) | Public contracts, 70 records on two backing layouts, and 16 owner/failure cases including four reached allocation denials |
| [Driver adoption](../tests/fixtures/extended/url_adoption/README.md) | Public smoke, one same-generation connected case and eight failure cases, including one reached close EIO and live pre-exit owner checks |
| `url-client-plain-native-first.log` | Two numeric HTTP cases: fixed and interim/chunked responses; exact Host, escaped/dot-segment target, omitted fragment and binary body; selected-socket handoff with no reconnect; live pre-exit source and descriptor cleanup |
| `url-client-dns-flags-retry.log` | One controlled four-address NSS case: refusal then selection at index one, two attempts, preserved ordering/duplicate list, failed socket retired before fallback, selected generation adopted without replay and pre-exit cleanup |
| `url-client-tls-native-first.log` | Eight cases across TLS 1.2/1.3: original DNS with SNI, numeric IP SAN without SNI, identity mismatch before HTTP, authenticated truncated HTTP and no endpoint/request replay; pre-exit source cleanup |
| `url-connect-admission-first.log` | Twelve cases: expired/invalid deadlines, checked-add overflow, invalid result/attempt/duration limits, zero/one socket-call budgets and numeric-family mismatch; no attempted endpoint or native resolver/socket work |
| `url-connect-failures-first.log` | Eight cases: numeric refusal, reserved cleanup credit at the call cap, ordered DNS attempt cap/exhaustion, EAI/system diagnostics, successful idempotent close and one reached close EIO; explicit raw repair after the fault is test work, not production cleanup success |
| [Real fetch](extended-fetch-url.md#functional-execution-and-remaining-acceptance) | Separate functional groups of 24 HTTP, 33 CLI/preflight and four HTTPS cases; these do not themselves establish application allocation/owner-fault acceptance |

Current sources are `host_name d7fae972…`, `http_url 24472542…`,
`url_connect bd3a3f65…`, `url_client 58f4989b…` and `url_tls 06a6ebfa…`.
The pure URL guide records the comment-only difference from its executed
parser source. The plain/DNS executable is `d4c3e0e1…`; TLS is `c94941e2…`.
Retained evidence directories are `/tmp/lanius-url-client-25f8u7wi`,
`/tmp/lanius-url-dns-9_1o2qp0` and `/tmp/lanius-url-tls-cdap36i7`.
Connector directories are `/tmp/url-connector-admission-82qawloo` and
`/tmp/url-connector-failures-qikporjw`; its
[fixture guide](../tests/fixtures/extended/url_connect/README.md) owns exact
producer/oracle identities and the fault/repair boundary.
The connector executable is `78e0979e…`.

The five new Rust integration drivers pass combined `--no-run` admission in
4.24s (`url-integration-driver-build-first.log`): `extended_http_url_execution`,
`extended_url_adoption_execution`, `extended_url_client_execution`,
`extended_url_connect_execution` and `extended_fetch_url_execution`. This
compiles the registrations; the actual Lanius/native behavior is established by
the separate direct receipts above. CPU oracle controls are separate again:
twelve URL-client and sixteen connector checks, with no native-case claim.

The first DNS harness attempt misread hexadecimal F_GETFL trace output. The
accepted retry parses that token with base zero and checks nonnegative flags
with O_NONBLOCK set. It changed no production source or ownership assertion.
The shared test verifier recognizes complete native runtime blocks and
full-width source allocation sites; it separates source owners from native
loader/libc/OpenSSL memory. Resource observations do not prove access safety.

The existing declaration generator and its `--check` both pass at this source
freeze: **264 pages from 263 modules, 8,502 lexical public markers and 12,847
declaration/member entries**. Receipts are `url-reference-writer-first.log`
and `url-reference-check-first.log`. The five new module pages and the existing
HTTP/HTTPS/OpenSSL pages are inventoried with reviewed guide links. Counts
describe discovery, not verified operations. Root README, AI policy and
contributing-file SHA256 values match their pre-generation values. No generator
implementation changed or compiler/native tests were rerun for documentation.

## Remaining dependencies and scope

- Finite connector boundary/fault acceptance does not establish every timeout,
  clock or cleanup-failure path. Attempt-timeout-then-success, arbitrary
  post-leaf clock faults and every reached wrapper allocation denial remain
  outside the selected connected gates.
- Registered new Rust drivers have not yet supplied runtime passes. Direct
  native receipts above remain valid independently of that runner.
- The [minimal constructor-name reduction](../tests/fixtures/compiler_dependencies/url_none_inference/README.md)
  records an unqualified `None()` collision with another enum's None item.
  Module-qualified `core::option::None()` compiles and executes. This is a
  name-resolution dependency with a working source spelling, not evidence that
  generic payloads generally fail. The TLS facade uses qualified constructors.
- Full wrapper/application source-OOM campaigns, native NSS/OpenSSL heap
  accounting, asynchronous lookup, pooling/keepalive, redirects, proxies,
  relative-URL policy and connected WebSocket handoff remain separate work.
- Automatic destruction, borrow checking, affine/effect tracking, formal
  proofs and other host/device targets are not supplied by these APIs or tests.

No API in this selected surface is a silent success/no-op stub. Idempotent
destroy/close results explicitly distinguish an already retired token. Broader
library declarations and unbound host services retain their own classifications
in the [roadmap](library-roadmap.md).
