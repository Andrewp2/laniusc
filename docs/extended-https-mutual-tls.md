# HTTPS with required client certificates

The existing [`https-fetch`](extended-https-fetch.md) and
[`https-serve`](extended-https-server.md) applications can exchange HTTPS with
mutual TLS. The client still verifies the service's chain and DNS/IP identity;
the service additionally requires a client certificate admitted by its
configured client trust file. System OpenSSL 3 performs every certificate,
private-key and TLS operation. Lanius composes the existing HTTP codec, owned
sockets, buffered TLS stream, deadlines and resource bounds.

All four focused application groups pass GPU compilation followed by native
Linux x86_64 execution with libc startup, `libssl.so.3` and `libcrypto.so.3`:
109 application/consumer process cases across two separate receipts. The
ordinary HTTPS client and service receipts remain documented in their guides;
those earlier results cover their stated source and regression scope.

## Command lines and trust roles

```text
https-fetch ADDRESS PEER CA_FILE TARGET [OPTIONS]
    --client-cert CLIENT_CHAIN --client-key CLIENT_KEY

https-serve ADDRESS SERVER_CHAIN SERVER_KEY [OPTIONS]
    --require-client-ca CLIENT_CA_FILE
```

The fetch credential options must both be present with nonempty values, or
both absent. The service option requires a nonempty value. Separate and `=`
option values are supported, and the last occurrence wins. Existing argument
capture remains 32 client arguments or 48 service arguments, with 16,384 bytes
in either application.

| Input | Purpose |
| --- | --- |
| Fetch `ADDRESS` | Numeric destination, such as `127.0.0.1:8443` or `[::1]:8443` |
| Fetch `PEER` | Required service DNS name or IP SAN reference; also the HTTP Host identity |
| Fetch `CA_FILE` | Trust for the service's certificate chain |
| Fetch client chain/key | Credentials the service can request and verify |
| Serve server chain/key | Credentials clients verify for the service |
| Serve `--require-client-ca` | Trust for admitted client certificate chains |

The two trust files serve independent roles and can name different authorities.
DNS peer references retain SAN-based hostname checks and SNI. Numeric peer
references retain IP SAN checks without SNI. Client credentials never disable
service chain or identity verification. There is no fallback after credential
loading, chain verification or identity verification fails.

Build both applications with the native OpenSSL dependencies:

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  --native-link --native-library ssl --native-library crypto \
  --stdlib-root stdlib --source-root extended \
  sample_programs/library/https_serve.lani -o /tmp/https-serve

timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  --native-link --native-library ssl --native-library crypto \
  --stdlib-root stdlib --source-root extended \
  sample_programs/library/https_fetch.lani -o /tmp/https-fetch
```

For example, run the service in one terminal with a certificate covering
`fixture.test`:

```sh
/tmp/https-serve 127.0.0.1:8443 /tmp/service-chain.pem /tmp/service.key \
  --require-client-ca /tmp/client-ca.pem --requests 1 --report
```

Then fetch its health body using a client certificate admitted by that CA:

```sh
/tmp/https-fetch 127.0.0.1:8443 fixture.test /tmp/service-ca.pem /health \
  --client-cert /tmp/client-chain.pem --client-key /tmp/client.key
```

The service publishes its bound numeric endpoint on stdout after configuration
and listener setup. The fetch publishes only the decoded response body. The
existing GET/HEAD health and binary POST echo routes, request framing, response
validation and one-request-per-connection policy are unchanged.

Omitting both fetch credential flags selects the ordinary verified HTTPS
client. Omitting the service client-CA option explicitly selects
`ClientAuthentication::Unauthenticated`, which does not request a client
certificate. These public-service modes remain useful independently of the
required-client profile.

## Credentials and admission policy

Supply a PEM chain with the endpoint's leaf first and its intermediate issuers
afterward, plus the matching, unencrypted PEM private key. Both applications
pass an explicit empty passphrase and never prompt. Encrypted, malformed,
missing or mismatched credentials fail; there is no passphrase argument or
password source in either application. The reusable
[`ext::openssl_tls` factory](extended-openssl-mutual-tls.md) separately supports
explicit secret input. Credential and trust paths must be nonempty, NUL-free
UTF-8 within the configured 4,096-byte path cap. Native file access policy and
OpenSSL govern the actual file reads.

`--require-client-ca` selects `ClientAuthentication::Required(CaFile(...))`.
The native policy requires a certificate, verifies its chain and client
purpose, and checks a non-null peer certificate and successful verification
before the server stream opens. No HTTP request is processed before that
handshake succeeds. The underlying modes are documented by
[OpenSSL's verification contract](https://docs.openssl.org/3.0/man3/SSL_CTX_set_verify/).

This admits every client certificate accepted by that trust and native purpose
policy. It does not map a subject or SAN to a user, compare a client DNS name,
grant a role or authorize a route. Different trusted client principals can
both access health and echo. A certificate with no EKU restriction can pass;
an incompatible explicit EKU is rejected. Choose the client trust set with
that scope in mind. Revocation fetching and custom CRL/OCSP policy are outside
this profile.

The required-client factory disables session caching and TLS tickets,
including the TLS 1.3 ticket count. Each required connection performs fresh
client-certificate authentication. There is no early-data or post-handshake
client-authentication API. The complete native policy and manual owner
contract are described in the [mutual TLS library guide](extended-openssl-mutual-tls.md).

## Completion, HTTP output and errors

TLS 1.3 permits a client to complete its local handshake before the service
processes and accepts the client's certificate. Even a successful client write
does not prove remote admission; a subsequent read can receive a fatal alert.
The certificate and Finished ordering is defined in
[RFC 8446 sections 4.4.1 and 4.4.4](https://www.rfc-editor.org/rfc/rfc8446.html#section-4.4.1).

The fetch continues through its bounded response read, canonical HTTP parser,
body decoder and final stream checks. It publishes no body if that exchange
fails. A required service emits no HTTP response for a rejected client. A
client may already have submitted request plaintext before learning of a late
rejection; this profile does not promise delivery rollback. After a later
response/output failure, a service response or fetch stdout can contain a
prefix under the existing application contracts.

Exit codes remain unchanged: 2 for arguments or processing bounds, 3 for
credentials/TLS/socket/clock/HTTP failure, 4 for allocation failure and 5 for
output or SIGPIPE-policy failure. Configuration errors in the service fail
before it publishes a listening endpoint. Diagnostic writes retain their
independent finite retry budgets and preserve the original status on failure.

## Prepared-context ownership

The client credential branch uses the additive prepared factory:

```text
tls_stream::connect_with_context_until(
    endpoint: SocketAddr,
    context: &openssl_tls::Context,
    identity: openssl_tls::Identity,
    limits: tls_stream::Limits,
    deadline: Deadline
) -> Result<Stream, Failure>
```

The factory borrows the context on success and every error. It never destroys
that caller owner. A successful native Session retains its own OpenSSL context
reference, so the caller may destroy its Context as soon as the factory
returns. The fetch does so on every result. The stream derives its write-queue
and native read caps from `Context.io_bytes()` rather than silently substituting
default limits.

Both client factories share one connection core and one uninterrupted State
from configuration through connection and handshake. The existing
`connect_until` owns its newly created Context in `Some`; prepared and accepted
server streams store `None`. Pre-session failures release only owned contexts.
Stream cleanup detaches an owned Context before destroying it and releases
SSL before the sole socket owner, then the context and queue. Keep one active
manual owner for each returned resource; by-value copies are inactive aliases.

Buffered `Write` acceptance, stable retry staging, confirmed versus accepted
plaintext counters, sticky post-call deadline errors, `check()`, terminal
shutdown and abortive `close()` are unchanged. In particular, failed flushes
can follow wire progress. They do not permit retrying new input on that failed
connection. See the [client stream contract](extended-https-fetch.md#the-tls-stream-adapter).

## Bounds and synchronous setup

The existing byte, work, I/O-call and TLS-call options apply to both profiles.
Defaults remain 5,000 ms, 65,536 I/O operations and 32,768 TLS operations. The
client defaults to a 2 MiB response and 1 MiB decoded body/output; the service
defaults to a 2 MiB request/response and 1 MiB decoded body. TLS plaintext staging
and the stream queue are capped at 16,384 bytes. Full bounds and HTTP limits
remain in the [fetch](extended-https-fetch.md#bounds-and-deadlines) and
[service](extended-https-server.md#bounds-and-deadline-scope) guides.

The fetch creates its absolute deadline before preparing credentials. Native
credential loading is synchronous and occurs before the prepared connector's
first deadline check; it is not preempted and does not spend connector I/O
counters. Its elapsed time still spends the same already-created deadline.
After entry, the prepared factory charges configuration once and carries the
same counters and deadline through the shared connection core.

The service loads its credentials and client trust before creating the
listener and before any per-slot deadline. Each sequential slot then uses the
same absolute deadline across accept, handshake, HTTP processing and shutdown.
WANT direction polling, interrupted-call accounting, unconditional cleanup
and the explicit process SIGPIPE-ignore policy remain unchanged. Native PEM
loading, certificate parsing, cryptographic work and native allocations are
not a process-memory quota or a preemptible CPU bound. Blocking stdout/stderr
writes are outside the network deadline.

## Focused execution gates

[`tests/extended_https_mutual_tls_execution.rs`](../tests/extended_https_mutual_tls_execution.rs)
builds the actual two applications and a prepared-context consumer. It checks
generated-function ELF boundaries and the OpenSSL 3 shared dependencies before
running them. Python's native OpenSSL peers enforce certificate verification;
standard HTTP parsers inspect the application messages. The shared raw TLS
fixture generates and independently verifies certificates using the OpenSSL
CLI in temporary storage; no private fixture keys are checked in.

All four groups passed on the selected profile:

| Group | Accepted process cases | Scope |
| --- | --- | --- |
| Matrix | 35 | TLS 1.2/1.3, different trusted clients, absent EKU, complete intermediate chains, DNS/IP and IPv4/IPv6, independent client trust, ordinary public HTTPS, native application pairs and three sequential slots |
| Failures | 34 | Missing, expired, incompatible-purpose, untrusted and incomplete client chains; mandatory service trust/identity; late alerts; rejected native application pairs with no HTTP response/body output |
| Limits | 32 | Paired flags, empty/missing credentials, malformed/mismatched/encrypted keys, client trust setup, exact body/output limits, call/work caps and accept/handshake/request deadlines |
| Prepared context | 8 | Borrowing on success/errors, caller destruction before stream use, configured three-byte I/O cap, copied queue, original Configure counter, closed/invalid/deadline/name/refused/stalled paths |

The prepared-context group passed its eight cases in 6.21 seconds, recorded in
`target/stdlib-work/https-mutual-prepared-first.log`. The matrix, failures and
limits groups passed their combined 101 cases in 15.23 seconds, recorded in
`target/stdlib-work/https-mutual-app-groups.log`. These are distinct selected
test invocations, not a whole-suite receipt. Each app pair counts two native
processes; Python peers are not counted as additional cases. The compiled ELFs
also passed generated-function boundary and OpenSSL dependency checks.

These elapsed times describe the focused test invocations, not an application
throughput benchmark. The finite fixtures do not establish every certificate,
trust store, provider, network schedule, allocation failure or host
configuration. The applications remain sequential with no keepalive or
principal/route authorization. No other host or GPU-kernel execution claim is
made. Focused regressions for the earlier owned-Context/default stream paths
are separate gates and are not included in these 109 cases.

```sh
timeout --kill-after=2s 110s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test extended_https_mutual_tls_execution -- --nocapture --test-threads=1
```
