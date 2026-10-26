# Mutual TLS with OpenSSL

`ext::openssl_tls` can load client credentials and require a verified client
certificate on a server. OpenSSL 3 performs every TLS, PEM, key, signature and
certificate-chain operation. The Lanius layer supplies policy, bounded byte
staging, nonblocking progress and explicit cleanup; it implements no
cryptographic primitive or TLS record parser.

The earlier credential profile passed all six focused mutual TLS groups:
107 cases compiled on the GPU and executed as native C-linked Linux
x86_64/glibc binaries with system OpenSSL 3.0.13. Those historical receipts
combine separate invocations, not one wholly passing suite run. Its affected
behavior also passed nine mandatory client-verification cases in 7.03 s
(`target/stdlib-work/mutual-tls-client-verification-regression.log`) and all six
ordinary server groups, 53 cases, in 6.95 s
(`target/stdlib-work/mutual-tls-server-regression.log`). Those regression
receipts establish their stated historical regression scope.

After the shared duplex changes, the selected mutual-TLS retry group passed
all six cases in 7.01 seconds on 2026-10-26, covering both roles and real
backpressure. This current-source gate did not rerun the five other historical
mutual-TLS groups. The [shared TLS guide](extended-openssl-tls.md#current-duplex-and-ownership-receipts)
records the separate current duplex, shutdown and ownership gates.

## Explicit policies

```text
new_with_credentials(
    trust: Trust,
    certificate_chain: View<u8>,
    private_key: View<u8>,
    passphrase: View<u8>,
    limits: Limits
) -> Result<Context, Error>

ClientAuthentication = Unauthenticated | Required(Trust)
new_server(chain, key, passphrase, client_authentication, limits)
    -> Result<ServerContext, Error>

Context.io_bytes() -> i32
Context.session(fd, Identity::Dns(...) | Identity::Ip(...)) -> Result<Session, Error>
ServerContext.session(fd) -> Result<Session, Error>
```

The existing `new(trust, limits)` remains a client without configured own
credentials. Both client constructors require server trust and the existing
SAN-based DNS/IP reference verification. Loading a client key never disables
those checks. SNI is sent for DNS references only. The protocol floor remains
TLS 1.2; compression and renegotiation are disabled, and abrupt EOF is not
normalized to a clean TLS close.

`Unauthenticated` remains the explicit server policy that does not request a
client certificate. `Required(trust)` sets exactly `SSL_VERIFY_PEER |
SSL_VERIFY_FAIL_IF_NO_PEER_CERT` (native value 3), with a null verification
callback. It loads the selected trust store and verification-depth limit and
sets the native `ssl_client` certificate purpose. It offers neither optional
client certificates nor a callback that can accept verification failure.
These native modes are defined by
[OpenSSL's verification contract](https://docs.openssl.org/3.0/man3/SSL_CTX_set_verify/).

Before a required server session becomes `Open`, a successful native handshake
must also have verification result zero and a non-null peer certificate.
The same postchecks remain mandatory for every client session. This explicit
presence check matters because a zero verification result alone also occurs
when no certificate was presented.
[OpenSSL documents that distinction](https://docs.openssl.org/3.0/man3/SSL_get_verify_result/).
The required-peer policy is copied into each Session, so destroying the caller's
context owner before the handshake cannot remove it. `SSL_new` retains its
native context reference; sessions do not borrow the Lanius Context storage.

## Certificate acceptance and application authorization

Required-server acceptance establishes OpenSSL's chain, validity, purpose and
private-key-possession checks for a certificate admitted by the configured
trust policy. It does not select an application account, compare a client DNS
name, authorize an HTTP path or grant a role. Two different certificates from
the same trusted authority can both pass. A certificate without an EKU
restriction can pass the native client-purpose check; an explicitly incompatible
EKU is rejected. There is no custom subject/SAN principal mapping in this API.
Application authentication policy and authorization remain separate work.

`Trust::CaFile` selects the supplied PEM CA file. `Trust::DefaultPaths` uses
OpenSSL's configured default locations, including its documented environment
overrides. A broad trust store defines a broad set of acceptable issuers.
The wrapper does not advertise a CA distinguished-name hint list or install
certificate-selection callbacks. Those hints are separate from the trust store;
the peer selects its configured credential under OpenSSL's native rules.
[Trust loading and CA hints are distinct OpenSSL settings.](https://docs.openssl.org/3.0/man3/SSL_CTX_load_verify_locations/)
Revocation fetching, custom CRL/OCSP policy, optional certificates and
post-handshake authentication are outside this profile.

## TLS 1.3 completion and later alerts

`Handshake::Complete` reports completion of the local native handshake with
the wrapper's required peer checks. It is not a receipt that the remote
application accepted this endpoint's certificate. In TLS 1.3 a client can
complete locally before the server processes the client's certificate and
returns a rejection alert. A subsequent `read_into`, `write` or shutdown can
therefore fail after client-local completion.
[An OpenSSL maintainer explains this TLS 1.3 ordering.](https://mta.openssl.org/pipermail/openssl-users/2022-October/015568.html)

Required servers expose no `Open` state or application I/O when client
verification fails. Clients still need an appropriate application response or
acknowledgment to establish remote acceptance. There is no hidden read,
blocking confirmation exchange or discarded application data in the handshake
API. Callers must handle errors at every later operation and account for any
application bytes already accepted before an alert.

## Fresh required-client authentication

Required server contexts disable native session caching, read back that it is
off, set `SSL_OP_NO_TICKET`, and set the TLS 1.3 ticket count to zero. The
last setting matters because disabling stateless tickets alone still permits
stateful TLS 1.3 tickets. This first profile performs fresh client-certificate
authentication; it does not preserve or scope an earlier authentication across
resumed sessions. Ordinary unauthenticated server policy is unchanged.

Client constructors expose no session import or `SSL_set_session` operation,
so a new client Session does not automatically select a previous session.
No TLS early-data or post-handshake client-authentication API is provided.
See OpenSSL's [cache modes](https://docs.openssl.org/3.0/man3/SSL_CTX_set_session_cache_mode/),
[ticket options](https://docs.openssl.org/3.0/man3/SSL_CTX_set_options/) and
[TLS 1.3 ticket count](https://docs.openssl.org/3.0/man3/SSL_CTX_set_num_tickets/).

## Shared credentials and cleanup

Supply a PEM chain path beginning with the endpoint's leaf, followed by its
intermediate issuers, and a PEM private-key path. Both roles use the same
staging and native loader: chain-file load, private-key load, then explicit
key consistency check. Loading a matching credential does not validate its
own expiry, issuer trust, reference identity or application role. Those are
the verifying peer's decisions.
[OpenSSL defines the chain order and key-match contract.](https://docs.openssl.org/3.0/man3/SSL_CTX_use_certificate/)

Limits, both credential paths, passphrase and applicable CA-file metadata are
validated before staging or native context acquisition. Paths must be nonempty
UTF-8, NUL free and within `limits.path_bytes`. Passphrases are counted bytes,
need not be UTF-8, and must be NUL free with length at most
`MAX_PASSPHRASE_BYTES` (1,023). An empty view supplies an explicit empty
passphrase; it does not request an interactive fallback.

Staging includes a terminator and a non-null allocation even for an empty
passphrase. Before loading either PEM file the wrapper supplies a null password
callback and that explicit string as userdata. It detaches the userdata before
wiping the full staged password, including its terminator, with
`OPENSSL_cleanse` and releasing staging. This applies on success, credential,
trust and policy failure, and every partial allocation failure. The caller
continues to own its original passphrase and any erasure policy for that input.
There is no stdin, environment-password, terminal or callback fallback.
[The native PEM password convention](https://raw.githubusercontent.com/openssl/openssl/openssl-3.0.13/doc/man3/PEM_read_bio_PrivateKey.pod)
and [OpenSSL's implementation](https://raw.githubusercontent.com/openssl/openssl/openssl-3.0.13/crypto/pem/pem_lib.c)
define the noninteractive userdata behavior.

Factory failure returns no usable partially configured context. Errors retain
the first captured native queue code and phase before cleanup; handshake
verification failures also retain the native verification code. A missing
client certificate normally produces OpenSSL's native handshake error rather
than a fabricated verification code. A failed post-success presence check
returns `PeerCertificate`. Fatal session errors free native/staging owners and
leave `State::Failed`; ordinary later destruction remains safe.

Context, ServerContext and Session are manual owners. Keep one active owner,
do not modify public policy/storage fields or call the raw declarations to
override a live wrapper's policy. End concurrent or inactive aliases before
cleanup. Native references retain a context for its sessions; each wrapper
reference is released once. Session destruction frees its BIOs with
`BIO_NOCLOSE`; the connected nonblocking descriptor remains caller owned.

## Progress and bounds

Handshake, read, write and shutdown retain the existing shared Session API.
Each step performs at most one native TLS operation and returns completion,
`WantRead`, `WantWrite` or an error. Both readiness directions are possible
from reads and writes. A pending write owns a stable byte copy and must use
`retry_write`; a pending read retains its original native address and request
size while allowing a different sufficiently large destination. A new write
cannot replace a pending write. Write-WANT_WRITE excludes other
TLS I/O; write-WANT_READ permits reads, and either read WANT permits writes.
Handshake and native shutdown require no pending application operation.
`read_need` and `write_need` retain independent requirements. The shared
[Session contract](extended-openssl-tls.md#explicit-progress-operations)
defines read quiescence and reads after confirmed local notification.

The caller supplies polling, absolute deadlines, total call/byte quotas and
an explicit SIGPIPE policy. After abandonment, destroy the TLS owner before
closing the caller-owned socket. The wrapper has no hidden wait or retry loop.
Existing `Limits` bound staged paths, reference identity, I/O buffers and
verification depth. They do not bound PEM file size, native certificate parsing,
native allocations, chain-verification CPU work or elapsed time in a native
call. Credential loading can perform filesystem I/O.

## Focused tests and execution scope

`tests/extended_openssl_mutual_tls_execution.rs` defines six focused groups:

- Both roles with TLS 1.2/1.3, custom/default trust, root-only intermediate
  chains, DNS/IP server references, native stack/packed/Vec layouts and a context
  destroyed before its retained Session handshakes.
- Missing, untrusted, expired, wrong-purpose and incomplete client chains;
  mandatory server trust/reference checks; local completion versus later alerts.
- Shared credential and input validation, encrypted keys, wrong passwords,
  missing/malformed PEM, mismatch and noninteractive loading with stdin held open.
- Native acquisition, policy, trust and credential failures, forced verification
  result and absent-peer postchecks, first diagnostics and exact native/fd cleanup.
- Stable copied write retries and read staging in both roles, changed caller
  views, operation guards and real nonblocking backpressure.
- Every observed credential/trust/identity/session staging allocation failed
  in turn, with exact mapping release and no escaped native owners.

All test certificates and keys are generated at runtime by OpenSSL commands.
The generator independently checks valid chains and expected expiry, purpose
and trust failures with `openssl verify`. Python's native OpenSSL MemoryBIO
provides the independent peer; it supplies no custom TLS engine. Rust, Python,
the native observer and syscall injector are test machinery.

### Accepted runtime receipts

These receipts cover the credential profile before the shared duplex changes.

| Receipt | Accepted scope |
| --- | --- |
| `target/stdlib-work/mutual-tls-matrix-first.log` | Matrix: 19 cases in 6.21 s, covering both roles, TLS 1.2/1.3, DNS/IP server references, chains, layouts, default/custom trust and native policy receipts |
| `target/stdlib-work/mutual-tls-other-groups.log` | Four groups passed in a 7.54 s mixed run: allocation 17 cases, retries 6, native faults 30 and credentials 18; its verification group failed a stale expected-code assertion |
| `target/stdlib-work/mutual-tls-verification-native-control.log` | Corrected verification group: 17 cases passed in 5.77 s with an independent native control |

Together these receipts accept all six groups and 107 reported cases. The
allocation group includes every observed staging failure position in its
baseline: seven for the required server and eight for the credentialed client,
plus the two successful baselines. It checks exact `MAP_32BIT` releases and
native/context/session/fd ownership. The mixed receipt remains a recorded
partially failing run; the later focused receipt resolves its verification
assertion without changing production behavior.

### Current focused retry regression

`mutual_tls_stable_retries_cover_both_roles_and_real_backpressure` passed six
cases in 7.01 seconds on 2026-10-26, recorded in
`target/stdlib-work/openssl-mutual-tls-duplex-guards-regression.log`. The current
consumer checks copied retry bytes and pointers, changed read destinations,
real backpressure and the directional guards for both roles. An empty write
must complete locally without clearing a pending read's size or WANT and
without another native TLS call. This selected group does not establish a
fresh pass of every historical matrix, credential, verification, allocation
or native-fault case.

### Wrong-trust native control

The stale expectation concerned a credentialed Lanius client using
`untrusted.pem` against the native Python/OpenSSL server. That server also loads
`root.pem` to verify clients. OpenSSL uses the loaded root when building its
outgoing server chain, so it sends the leaf **and** that self-signed root.
The exact peer/trust setup returns verification code 19, self-signed certificate
in the chain. The earlier code-20 expectation described a leaf-only chain.

`tests/fixtures/extended/openssl_mutual_tls/verification_control.py` preserves
two independent native checks: Python/OpenSSL observes the two-certificate
peer chain and code 19; `openssl verify` gives code 20 for the leaf alone and
code 19 when supplied the root as untrusted chain material. The corrected test
expects exactly 19 for that case, rather than accepting either error code.
Failed state, absence of Open/publication, zero application bytes and all
other verification assertions remain unchanged.

These are finite cases using runtime-generated test certificates and the
selected Linux x86_64/glibc/OpenSSL 3 profile. They do not prove every
certificate, signature algorithm, provider configuration, trust store, peer,
network schedule, resumption attempt or resource failure. The timings are
host observations, not latency or memory guarantees. No other host or
GPU-kernel execution claim is made.
