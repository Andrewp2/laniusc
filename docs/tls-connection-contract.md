# Authenticated TLS connection contract

This is the implementation and acceptance contract for reusable TLS connections.
The [portable engine](extended-tls-connection.md) now passes paired handshakes,
fragmentation, retry and boundary gates. The [TCP adapter](extended-tls-tcp.md)
passes real OpenSSL exchanges, 1 MiB pressure streams, ownership/fault gates and
deadline/budget resumption. The [real program](extended-tls-exchange.md) passes
74 interoperability, I/O, ownership and budget cases. The guides distinguish
accepted snapshots from pending work. Production protocol, cryptography and
certificate validation stay in Lanius; OpenSSL is an independent test peer.
The broader algorithm and PKIX
requirements below remain open.

## Existing boundaries and remaining work

| Existing source | Contract the connection must add |
| --- | --- |
| [tls_record](../extended/ext/tls_record.lani), [tls_schedule](../extended/ext/tls_schedule.lani), [tls_transcript](../extended/ext/tls_transcript.lani) | Negotiate algorithms, bind directional keys to epochs, and enforce authenticated transcript checkpoints. A successful AEAD open alone does not authenticate the peer. |
| [tls_handshake](../extended/ext/tls_handshake.lani), [tls_framing](../extended/ext/tls_framing.lani) | Validate message/extension meaning, ordering, fragmentation and key-change boundaries. Framing returns borrowed storage and partial consumed counts. |
| [tls_negotiation](../extended/ext/tls_negotiation.lani) | Reuse the admitted suite/share/signature, HRR/CH2, SNI/ALPN checks and extension writers. Retain CH1/CH2 backing and validated retry history; semantic success alone is not a transcript or authentication checkpoint. |
| [x509_path](../extended/ext/x509_path.lani), [service_identity](../extended/ext/service_identity.lani), [x509](../extended/ext/x509.lani), [Ed25519](../extended/ext/ed25519.lani) | Use the admitted explicit-anchor ordered Ed25519/offline profile, then enforce proof of possession. Extend normalized names, path building, name constraints, certificate policies and revocation before claiming general PKIX support. Parsing alone establishes no trust decision. |
| [tls_authentication](../extended/ext/tls_authentication.lani) | Reuse the admitted EE/Certificate/CV/Finished server-authentication checkpoint. The engine must validate CH/SH and EE negotiation, bind traffic secrets/epochs, and commit client Finished before releasing application data. |
| [AES](../stdlib/core/aes.lani), [AES-GCM](../extended/ext/aes_gcm.lani) | The record layer now admits explicit AES-128-GCM/SHA-256 and ChaCha20-Poly1305/SHA-256 suites. The connection must negotiate one, preserve it through key updates, and honor directional key-use limits. |
| [std::socket](../stdlib/std/socket.lani), [std::poll](../stdlib/std/poll.lani), [core::io](../stdlib/core/io.lani) | Own transport lifetime, retained partial records, bounded progress and deadlines. TCP lives in `std::socket`; `std::net` is legacy host-ABI surface. |
| [std::entropy](../stdlib/std/entropy.lani), [std::random](../stdlib/std/random.lani), [std::clock](../stdlib/std/clock.lani), [calendar](../stdlib/core/calendar.lani) | Bound entropy attempts, separate monotonic deadlines from certificate wall time, and propagate every host failure. |

## First executable profile and the full TLS requirement

The first connected profile is TLS 1.3, X25519, Ed25519 certificate signatures
and CertificateVerify, `TLS_AES_128_GCM_SHA256` and
`TLS_CHACHA20_POLY1305_SHA256`, server authentication,
and explicit application-supplied trust anchors. Its client and server must
exchange real application bytes with independently configured OpenSSL peers.
No PSK resumption, 0-RTT, mutual/client certificate authentication or
post-handshake authentication is offered initially. Session tickets may be
validated and discarded under an explicit disabled-cache policy. Unsupported
negotiation must fail explicitly rather than select an unimplemented path.

This profile covers a subset of general TLS interoperability.
[RFC 8446 section 9.1](https://www.rfc-editor.org/rfc/rfc8446.html#section-9.1)
requires, absent a different application profile standard, AES-128-GCM/SHA-256,
P-256 key exchange, RSA-PSS/RSAE/SHA-256 and ECDSA/P-256/SHA-256 signatures,
and RSA-PKCS1/SHA-256 certificate verification. AES, AES-GCM and explicit
AES-128-GCM/SHA-256 record integration now have native admission; P-256,
RSA and ECDSA primitives and their certificate integrations are missing. The SHA-256 and
SHA-384 hashes themselves already exist. AES-256-GCM/SHA-384 and X25519
also have the RFC's recommended status; supporting X25519/ChaCha/Ed25519 does
not satisfy the mandatory set. The [section 9.2 extension requirements](https://www.rfc-editor.org/rfc/rfc8446.html#section-9.2)
also require semantic implementations, beyond the existing generic codecs.
These remain explicit work after the first profile, not exceptions to the
full-library objective.

## Types, storage and ownership

The engine and adapter keep separate storage and host ownership. Their exported
types implement the following responsibilities; the linked guides give exact
signatures, size formulas and current runtime evidence:

| Type | Responsibility |
| --- | --- |
| `ClientConfig` | Immutable anchors, expected `DnsName` or `IpAddress`, optional ALPN offers, certificate/time policy and hard limits. Empty anchors or absent expected identity reject before a connection starts. |
| `ServerConfig` | Immutable DER chain and owned Ed25519 seed; construction checks that the derived public key matches the leaf. Configure one credential initially; SNI selection can be added with an explicit bounded registry. |
| `Engine` | One active owner of role/phase, transcript, ephemeral secret, directional record owners, epoch numbers, decoders, pending wire output and authenticated plaintext cursors. It borrows immutable config and caller-owned buffers. |
| `Buffers` | Disjoint record input, decrypted record, handshake reassembly, pending output and application staging storage. Capacities are validated once; no implicit growth during a handshake. |
| `tls_connection::Limits` / `tls_tcp::HostBudget` | Separate hard session byte/work/signature/record/control allowances from charged entropy/I/O/clock/poll attempts and observed deadlines. Exhaustion is an observable result. |
| `tls_tcp::Connection` | Owns one nonblocking `std::socket::Socket`, ten fixed storage/poll allocations and retained raw input. Each resource receives one retirement attempt. Attachment failure preserves the caller's original socket. |

Reserve at least 16645 bytes for a generic maximum protected frame and 16624
for possible decrypted inner data, applying the stricter record-layer limits
before publication. Set a configurable handshake-body/certificate budget
(e.g. 1 MiB), not an unbounded 24-bit allocation. Reassembly/validation storage
must keep all borrowed certificate/name views alive until path processing
finishes; copy the validated leaf key and required peer information before
consuming that frame. Decoder `consume`/`reset` invalidates prior frame views.
Do not reallocate any backing vector while engine/decoder views borrow it.

Config/anchors stay immutable for the engine lifetime. No caller view survives
an input-copying call unless the API explicitly returns a borrow. Connection,
record and decoder copies do not create a second owner or new nonce authority.
Follow the repository's manual ownership conventions; field privacy currently
cannot prove these invariants. Do not accept a caller-fabricated `trusted=true`
flag or `VerifiedPeer` token to enter an authenticated state. Only the actual
validator and proof-of-possession checks advance private session state.

## State machine and authentication checkpoints

| Client state | Required transition |
| --- | --- |
| Prepare / send ClientHello | Obtain fresh entropy; retain exact encoded CH; offer only implemented versions, groups, suites and signature schemes. |
| Await ServerHello / HRR | Check every selection against offers, session-id echo, version, compression and allowed extensions. HRR occurs at most once; validate requested changes/cookie, preserve required CH2 fields and apply the transcript rewrite. Reject an HRR requesting an already-sent key share. |
| Await server flight | After SH, derive distinct client/server handshake keys. Process EncryptedExtensions, nonempty Certificate, CertificateVerify, Finished in order. Reject unsolicited extensions and unsupported CertificateRequest explicitly. |
| Verify server / send client Finished | Validate chain + identity + wall time; verify server CV against the transcript through Certificate; append CV only after success. Verify Finished against the transcript before its own frame; append it only after success. Derive application/exporter secrets through server Finished, then send client Finished using the client handshake key. |
| Established | Publish no application data until server authentication succeeded and the client's Finished was committed to the transport. Retain already-received authenticated server application data within a fixed bound until that point. |

The server performs the mirror: validate CH, choose only an offered supported
profile, optionally send one HRR for a missing X25519 share/cookie policy, send
SH, encrypted EE/Certificate/CV/Finished, then verify client Finished before
publishing client data or accepting application writes. Its default peer is
**anonymous client**, not an authenticated client identity. A future mutual-TLS
mode must require and validate the client's Certificate and CV before Finished.
Check version `0304`, group `001d` with a 32-byte X25519 share, suite `1301` or `1303`
and offered Ed25519 scheme `0807`, including certificate-signature offers when
present. ALPN must select one offered protocol; a required absent/mismatched
selection fails. DNS SNI and the expected certificate identity remain distinct
inputs; omit DNS SNI for a literal IP reference.

CV input is exactly 64 space bytes, the direction-specific RFC context string,
one zero byte, and the current transcript hash. Its signature algorithm must
be offered and compatible with the validated leaf SPKI. Server Finished uses
the server handshake secret; client Finished uses the client handshake secret.
Resumption master uses the transcript through client Finished. Never append
record headers, compatibility CCS, alerts or application bytes to the handshake
transcript. These rules follow [RFC 8446 sections 4.4–4.6](https://www.rfc-editor.org/rfc/rfc8446.html#section-4.4).
Reject premature Application Data when no early-data mode was negotiated;
only the client's permitted post-server-Finished holding case above applies.

## Certificate verification boundary

Use the [bounded ordered verifier](extended-x509-path.md) and
[service identity matcher](extended-service-identity.md) for the first profile
before exposing authenticated connections. The
[certificate-verifier program](extended-verify-certificate.md) independently
exercises this boundary in 84 native cases. General PKIX support remains work.
The admitted verifier takes the presented chain, explicit configured anchors,
expected reference identity, supplied UTC time, caller workspace and shared
work limits. It fixes usage to TLS server authentication; a broader verifier
must add explicit client/server purpose policy. Success supplies the leaf key tied to that
validated path and identity, for the engine's subsequent CV check. A parser
result, self-signature, issuer-name match or encryption success is insufficient.

For the first Ed25519 path profile, verify each certificate's exact `tbs`
signature; link the path to a configured anchor; enforce validity, CA/basic
constraints, path length, keyCertSign/digitalSignature key usage and applicable
serverAuth/clientAuth EKU. Detect loops, duplicate candidates and work/depth
limits. Apply anchor constraints explicitly; a peer-supplied self-signed root
cannot appoint itself an anchor. Reject unknown critical information and any
known constraint/policy form whose semantics are not implemented.
`unknown_critical_count == 0` is not a validation result. Name constraints,
certificate policies and distinguished-name matching/path building remain
missing general-profile contracts, not fields a verifier may silently ignore.
The admitted ordered-chain implementation rejects unsupported policies and
constraints and uses byte-exact DN matching; extend that explicit profile
toward RFC 5280 path validation.

Service identity follows [RFC 9525 section 6](https://www.rfc-editor.org/rfc/rfc9525.html#section-6):
match the application-supplied DNS reference against DNS SANs, or literal IP
bytes against IP SANs. No CN fallback or identity derived from the presented
certificate, DNS response or connected address. Define ASCII case folding and
whole-leftmost-label wildcard rules; reject raw Unicode references until an
IDNA contract exists. Use explicit ASCII A-label references in the first
profile. Clock failure, invalid date conversion, unsupported policy or failed
verification aborts; no zero-time or accept-any-certificate fallback exists.
Revocation policy must say whether required evidence is supplied and checked;
an offline profile without revocation checking cannot claim it checked
revocation. Server credentials, roots and validation decisions need no foreign
TLS backend. [RFC 5280 section 6](https://www.rfc-editor.org/rfc/rfc5280.html#section-6)
is the path-validation source of truth.

The [server-flight authentication state](extended-tls-authentication.md) now
calls that verifier, verifies exact CV/Finished transcript checkpoints, and
withholds the copied peer key/transcript until success. Its admitted
110 protocol cases and 340 observations include retired input buffers,
independent copies, shared budgets and terminal errors. The caller still
supplies checked negotiation, certificate-signature offers and the correct
handshake record secret. Its `Authenticated` state is not `Established`;
the engine must commit the client's Finished before releasing application data.

## Partial I/O, deadlines and entropy

Keep protocol progress independent of host waits:

- `feed_wire(input, budget)` copies only its reported consumed prefix into
  decoder storage. On error, report any consumed bytes; never reread that prefix.
  Retain unconsumed decrypted bytes until all coalesced handshake frames finish.
- `queue_plaintext(input)` accepts at most one bounded record prefix only in
  Established, copying/sealing it once into the pending output slot. Report
  accepted plaintext separately from transmitted ciphertext. A full slot accepts
  zero bytes and requests output progress. It performs no hidden transport call.
- `outgoing()` borrows the exact pending wire suffix; `acknowledge_written(n)`
  advances only by actual positive transport progress. A partial write, timeout
  or WouldBlock retains those bytes. Do not reseal or accept the same plaintext
  again. `flush` means pending library output drained, not peer acknowledgement.
- `read_plaintext(destination)` copies only authenticated, released application
  bytes; it never exposes record scratch or handshake data. Nonempty reads return
  clean EOF only after authenticated close_notify and draining prior data.

The TCP adapter drives single `Socket.send`/`receive` calls on a verified
nonblocking socket, using single-attempt `PollSet.poll_ms` or reactor readiness
between WouldBlock results. Compute each poll timeout from the original
deadline. `poll_until` is also bounded by its explicit maximum attempts, but
does not return the actual attempt count; charge its complete worst-case
poll/clock cost before calling it if used. Short counts are normal; zero send
progress is an error.
Every syscall, Interrupted retry and poll/clock attempt consumes its budget.
Use one absolute monotonic handshake/operation deadline and observe it before
and after host calls; readiness never renews it. A late successful send still
advances the retained wire cursor before reporting expiry; a late receive
cannot publish new plaintext. Failure includes phase, accepted/consumed/sent
counts, pending state and separate cleanup error. Fatal protocol/handshake
failure is terminal. An Established operation deadline/budget stop can be
resumed with the same state; explicit abort abandons it.

Existing socket `*_until`, `wait_until` and core exact/all helpers contain
unbounded retry loops; do not use them to promise a bounded-attempt TLS API.
Polling readiness is advisory. Reject clock reversal and preserve the original
failure if close/release also fails. Numeric endpoint connection can be outside
the TLS engine; DNS resolution is a separate bounded operation and never
changes the expected certificate identity.

Each new handshake needs OS cryptographic entropy for its 32-byte random and
32-byte X25519 private input; server signing credentials are separately
provisioned. Use `x25519::shared_secret`'s low-order/all-zero rejection. Never
use xoshiro, time, a fixed fallback, or caller-selected deterministic `Source64`
as production entropy. Discard partial entropy on failure. The existing
`std::entropy::fill` retries EINTR without a limit. The now-admitted
[bounded entropy API](stdlib-entropy-bounded.md) supplies `read_some` with one
charged `getrandom(GRND_NONBLOCK)` attempt, plus `fill_bounded` with explicit
shared attempt limits and completed-prefix failures. The connection uses
`read_some` so it can check its original monotonic deadline between attempts;
an attempt budget alone does not establish that deadline. The binding uses the
existing Linux syscall boundary and surfaces EAGAIN and other host failures.
A blocking getrandom call cannot
be made deadline-bounded merely by checking the clock afterward. Tests may
inject a scripted entropy source through an internal test seam only.

## Record boundaries, alerts and post-handshake policy

Reassemble handshake messages across records and handle multiple messages in
one record. Never switch keys with a partial handshake message buffered, nor
interleave application records into a fragmented handshake. SH, Finished and
KeyUpdate that precede key changes must end at record boundaries. Track the
record epoch supplying every reassembly prefix. Framing `reset()` is available
for storage reuse; it never authorizes recovery from a terminal TLS error.

Handle the permitted unencrypted one-byte CCS value `01` only in its RFC
compatibility window; ignore it without transcript/sequence changes, charging
a control-message budget. Protected CCS, wrong contents and out-of-window CCS
are fatal. Respect plaintext versus ciphertext size limits; ignore the obsolete
plaintext record version as required, and use the protected header contract
once keys exist.

On fatal authentication/protocol errors, suppress application publication,
attempt the appropriate alert under a bounded output policy, then close; alert
failure cannot clear the original cause or permit more data. Validate two-byte
alerts and implement close_notify as independent read/write closure. Drain
pending writes before sealing local close_notify; after its transport drain,
shutdown the write half. Peer close_notify ends future received data, while
local writes may continue until locally closed. Raw TCP EOF without it is
truncation, including an incomplete frame; do not return clean TLS EOF. Do not
undo application bytes already delivered before a later truncation error.
See [RFC 8446 section 6](https://www.rfc-editor.org/rfc/rfc8446.html#section-6).

Support KeyUpdate after handshake completion. Seal its message under the old
sending key and drain that pending record before installing the new sender;
authenticate and validate the peer's complete update under the old receiver
before resetting receive keys. Bound update frequency, answer requests with
`update_not_requested` before the next application record, and never answer a
response with another request. Reserve an old-key sequence slot for the update;
rekey before exhaustion, or terminate. Sequence reset always accompanies a new
traffic secret. Send and receive generations remain independent.

The initial disabled-cache policy parses/limits received NewSessionTicket and
explicitly discards it; the server issues none. This offers no resumption API.
A later bounded cache must bind tickets/PSKs to authenticated identity, trust
policy, ALPN, cipher hash, nonce, receipt time, lifetime and age_add. Derive its
PSK only from the verified client-Finished checkpoint, respect the seven-day
maximum, and define secret ownership/expiry. Add binder verification and replay
policy before enabling resumption or 0-RTT; unsupported early data is rejected.

## Implementation sequence and acceptance gates

1. Reuse the admitted Ed25519 path/identity/time verifier and server-flight
   authentication state, with real CA/intermediate/leaf fixtures and explicit
   anchors. No externally supplied trust token substitutes for those checks.
   Use the admitted bounded entropy attempts with connection deadline checks.
2. Implement one portable engine with framing, exact negotiation, HRR, server
   credential proof, CV/Finished checkpoints, alerts, pending-record progress,
   close and KeyUpdate. Script fragments, stalls and clock/entropy failures;
   allocate all bounded storage before secrets or application publication.
3. Add nonblocking TCP client/server adapters and small real programs using
   explicit roots, expected DNS/IP identity, numeric endpoint and provisioned
   server key/chain. Require bidirectional application transfer and clean close.
4. Gate both directions against a real OpenSSL process, constrained initially
   to TLS1.3/X25519/Ed25519/ChaCha20. Configure OpenSSL certificate verification
   and the same actual CA trust boundary; do not use verify-none or treat a
   self-signature as trust. Test Lanius client against OpenSSL server, and Lanius
   server against a verifying OpenSSL client. Compare delivered bytes, negotiated
   profile, exporter output and Finished/key-update interoperability.
5. Add wrong root/name/IP, expiry/not-yet-valid, missing/malformed constraints,
   bad chain/CV/Finished/tag, duplicate/unsolicited extensions, low-order X25519,
   HRR and key-boundary violations, truncated EOF and close-notify half closure.
   Cross fragmented/coalesced records with every short-read/write split, EINTR,
   WouldBlock, zero/invalid counts, original deadline expiry, OOM and entropy
   failures. Trace no plaintext release before authentication, no resealing,
   exactly-once descriptor/buffer cleanup, and terminal-error persistence.
6. Preserve the broad goal: implement the missing RFC mandatory primitives,
   signature/PKIX semantics and extension behavior; expand independent OpenSSL
   tests without constrained algorithm flags before claiming general TLS
   compliance. Add session resumption, mutual/post-handshake authentication and
   other advertised features with their own executable state/security gates.

OpenSSL, Python and fault tools remain tests; no subprocess/foreign crypto
backend implements the Lanius connection. Each build/test command stays under
two minutes. Performance measurements must use the existing Lanius harness with
functional output checks; primitive gates and this design document cannot
establish connection correctness, constant-time code or full interoperability.
