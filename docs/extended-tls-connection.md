# Portable TLS connection engine

`ext::tls_connection` composes the Lanius negotiation, framing, transcript,
X25519, key schedule, record and server-authentication layers. It implements
client and server roles in one allocation-free engine. Socket ownership,
nonblocking calls, entropy acquisition and deadlines belong to `ext::tls_tcp`.

The supported profile is TLS 1.3 with X25519, SHA-256, Ed25519 certificates and
CertificateVerify, and either AES-128-GCM (`1301`) or ChaCha20-Poly1305 (`1303`).
The server authenticates; its client is explicitly anonymous. There is no PSK
resumption, early data, client certificate authentication or post-handshake
authentication. Received NewSessionTicket messages are structurally validated
and discarded; the cache is disabled and this engine never issues a ticket.

This profile does not satisfy the complete mandatory algorithm set in
[RFC 8446 section 9](https://www.rfc-editor.org/rfc/rfc8446.html#section-9).
The ordered Ed25519 certificate verifier retains its documented offline,
explicit-anchor constraints; this engine does not add general PKIX path
building, normalized distinguished names, revocation or unsupported policies.
See [the connection contract](tls-connection-contract.md),
[path validation](extended-x509-path.md),
[service identity](extended-service-identity.md), and
[authentication](extended-tls-authentication.md).

## Construction and storage

`client(config, buffers, entropy)` and `server(config, buffers, entropy)` return
an `Engine`. The pure-engine entropy argument must contain 64 fresh OS
cryptographic bytes: 32 for the hello random and 32 for X25519 private input.
Production callers use `tls_tcp`, which acquires this input through bounded
nonblocking OS entropy calls. Fixed entropy appears only in test fixtures.
The engine copies entropy and the server signing seed; their original inputs
may be overwritten after construction. This is not a secure-erasure guarantee.

Client configuration supplies immutable trust anchors, a copied DNS/IP
reference identity, explicit UTC certificate time, optional DNS SNI, and an
encoded ALPN offer list (concatenated nonempty `u8`-length-prefixed names).
Server configuration supplies an immutable ordered DER chain, a 32-byte seed,
and one preferred **plain**, unprefixed ALPN protocol. `require_alpn` requires a
negotiated protocol. SNI and certificate reference identity remain distinct.
The server derives the seed's public key and compares all 32 bytes to the
actual leaf SPKI before it can emit a handshake. Every sent certificate uses
the implemented Ed25519 certificate-signature profile.

Call `required_buffers(limits)` before allocating caller backing. It checks
wire maxima, arithmetic and the packed-owner allocation-size domain. The
returned counts are logical elements:

| Buffer | Required count |
| --- | --- |
| `record` | 16,645 bytes |
| `decrypt` | 16,624 bytes |
| `handshake` | `4 + max_handshake_body` bytes |
| `hello` | `2 * max_hello_frame + min(max_hello_frame, 65533)` bytes |
| `pending_wire` | 16,645 bytes |
| `application` | `max_application_hold` bytes |
| `path` | 16 `x509_path::Slot` values |

The hello region retains separate CH1, CH2 and HRR-cookie ranges. Negotiation
views never point into temporary inline engine arrays. The path workspace is
used synchronously and may retain obsolete borrowed parser records after an
input frame is retired; neither the engine nor callers may use those old
records after their backing changes.

Every view needs physical backing for its logical range. All seven buffers
must be mutually disjoint and disjoint from the engine, configuration and
each mutating call's source/destination. Configuration descriptor arrays,
anchors, chain, SNI and ALPN backing stay live and immutable for the engine
lifetime. Do not resize or free borrowed owners. Bounds checks validate view
metadata, not arbitrary pointers or manual aliases.

An engine has **one active owner** of storage and nonce spaces. A value copy
supports passive inspection or a sole-owner handoff; driving both copies is
invalid. Fields are implementation state, not an authenticated resume format.
Caller-written phase/key fields cannot establish a valid TLS connection.
`abort()` disarms protocol use before caller backing is released; it frees
nothing and never rolls a nonce or pending cursor back.

## Progress and publication

`pump()` advances retained decoded content and prepares at most one outgoing
record. `outgoing()` borrows the exact unsent suffix. Only
`acknowledge_written(n)` commits actual positive transport progress; invalid
counts leave the cursor unchanged. A short write retains identical bytes.
Sealing happens once, before the transport accepts bytes, so retries never
reuse a nonce to reconstruct a record.

`feed_wire(input)` reports the exact consumed prefix, including on failure.
It completes at most one new record per call. The caller retains coalesced
tails and must not feed a consumed prefix twice. Decrypted content can remain
private while the handshake or application holding buffer applies backpressure;
a successful consumed count does not imply application publication.

The client checks CH/SH selections and EE semantics, then calls the actual
`tls_authentication` bridge for path/identity/time, CV and server Finished.
It derives application receiver keys through server Finished, but remains
unestablished while its own Finished is pending under the old handshake key.
Only the final transport acknowledgement of that record releases application
reads, writes, exporter output and the copied peer key. The server enters
Established only after verifying and appending client Finished. No caller trust
flag or externally supplied leaf key can perform these transitions.

`queue_plaintext` accepts at most one 16,384-byte prefix in Established and
reports accepted plaintext independently of wire transmission. `WantOutput`
accepts none. `read_plaintext` copies only released authenticated bytes into
caller output. It reports `WantInput` when a nonempty destination has no data;
clean EOF requires authenticated peer close_notify and drained prior data.
Small holding buffers retain the rest of an already-opened record and resume
after reads plus `pump()`. Application data is hidden after terminal failure,
including bytes held before the client-Finished acknowledgement.

## Handshake and key epochs

The engine retains exact hello bytes, handles one HRR, checks CH2 changes and
rewrites the transcript with message_hash. The optional server cookie policy
is stateful and bounded; it is not a stateless denial-of-service defense.
CH, SH, Finished and KeyUpdate must end their supplying record. A fragmented
handshake retains its receiving epoch and cannot be interleaved with other
record types. Compatibility CCS `01` is ignored only after the first CH and
before peer Finished, without transcript or sequence changes. Plaintext legacy
record versions are ignored; protected record headers follow `tls_record`.

KeyUpdate is sealed under the old sender and installs its successor only after
the exact old-key record fully drains. A received aligned update is verified
under the old receiver before installing the successor. Requests generate a
nonrequesting response before further application output; responses do not
produce request loops. Tiny private staging avoids overwriting a fragmented
incoming ticket when a local update is queued. The sender reserves its final
old-key slot for an update. The receiver accepts its final valid record and
rejects a subsequent old-key attempt through the record layer's exhaustion
check; receiving a valid final close_notify remains possible.

Directional generations and sequence counters remain independent. `Stats`
exposes pending wire/plaintext, reassembly/retained counts, sent/received record
counts and remaining hard allowances. Combined debit counters bound record,
control and handshake-byte statistics; generation increments check overflow.

## Limits, errors and closure

The engine owns hard session record, control, handshake-byte, work and key-update
allowances plus the shared path/signature and negotiation budgets. These
allowances never reset on retry, HRR or key update. Variable scans and cryptographic
operations debit before work. They bound abstract work and operations, not
elapsed time. A transport deadline or host-call budget is independently owned
by the adapter and can stop an Established operation without replenishing the
engine's hard allowances.

Defaults allow a 1 MiB handshake body as a storage ceiling. The default path
work allowance remains the authentication bridge's conservative tariff:
`4096 + 256 * frame_length` before nested parsing, plus actual path work.
Consequently raising the frame/storage ceiling alone does not admit large
certificate flights. The long-chain test explicitly raises path work; callers
must choose all resource limits coherently.

Invalid caller view metadata has priority and consumes no input or state.
Ordinary backpressure and invalid local acknowledgement/count requests are
retryable. A protocol, authentication, truncation or hard-session-limit failure
latches its first cause permanently and suppresses publication.
`is_resource_limit(error)` classifies the original nested error without replacing
it. Protocol failures cannot be reset into another handshake.

A fatal error may prepare one bounded alert only if the pending wire slot was
empty. If a previous record already spent a nonce, its bytes and cursor remain
accounted in stats but `outgoing()` suppresses them. The engine does not replace
that record with an alert or send its application suffix after failure.
`fatal_alert_pending()` distinguishes the one safe prepared alert; its prefix
may be acknowledged while the original failure remains latched. Alert creation
or transport failure cannot replace that cause. Key-state retirement does not
promise compiler-enforced secure erasure.

`begin_close()` drains prior pending output before sealing local close_notify.
`local_closed()` becomes true only after that alert is fully acknowledged.
Local write closure does not close reads; authenticated peer close_notify
preserves earlier unread application data and permits remaining local output.
Subsequent peer input is ignored as required by
[RFC 8446 section 6.1](https://www.rfc-editor.org/rfc/rfc8446.html#section-6.1).
Raw transport EOF before peer close_notify, including incomplete framing, is
sticky `Truncated`; it is never clean TLS EOF.

## Admission status

The portable paired selected profile is accepted on x86_64 Linux. The four
independent exact invocations below each compiled one strict ELF and ran one
native process. Production remains allocation-free: the ordinary and controls
fixtures have empty memory traces; each paired fixture process intentionally
owns exactly one 3,520,000-byte arena with a matching address/size release.

| Exact gate | Accepted cases | Elapsed |
| --- | --- | --- |
| `ordinary_connection_storage_and_pending_wire_consumer_executes` | Ordinary constructor/pending-wire consumer, earlier production snapshot | 16.32 s |
| `paired_connections_match_independent_wire_epochs_and_authentication` | 4: both suites × both layouts | 18.15 s |
| `fragmented_long_certificate_and_both_hello_retry_modes_execute` | 4: both HRR forms and long eight-certificate flights | 25.30 s |
| `connection_error_atomicity_and_record_epoch_boundaries_execute` | 46: 23 controls × both layouts | 17.82 s |

Each gate used the serialized 100 s outer / 35 s lock-wait / 60 s inner
wrapper, `RUST_MIN_STACK=16777216`,
`LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000`, `LANIUS_DEBUG_STAGE_ERRORS=1`,
and `--exact GATE --nocapture --test-threads=1`. This acceptance
covers the documented paired profile; the real TCP/OpenSSL matrix remains a
separate adapter/application admission.

The ordinary x86_64 Linux consumer passed the serialized parent gate at
production SHA256 `5b1ad994d88b41d5b006119b6a746d0b6b279a20ad6c941ea81751cc1d563704`:
one strict ELF, one native process, empty `mmap/munmap/mremap/brk` trace, 16.32 s.
It exercised checked sizing, ClientHello construction, a one-byte pending-wire
acknowledgement and abort. Rust target build took 1.58 s. Logs:
`target/stdlib-work/tls-connection-admission/build-connection-ordinary.log` and
`connection-ordinary.log`.

The first paired native process
terminated with SIGSEGV before stdout. The preserved ELF reserved 12,649,328
bytes in its entry frame and failed on its first call before reading input.
The two large fixture arrays and lowering temporaries exceeded the ordinary
stack. The same ELF passed all four pair cases with a 32 MiB stack as a
diagnostic control; that is not the normal-stack acceptance gate.
The first arena revision failed before ELF creation with LNC0017, "invalid
checked fixed-array layout": `typed_slice_from_storage<[u8;440000]>` crossed
the generic specialization's existing 65,535-native-word fixed-array limit in
`crates/laniusc-compiler/src/type_checker/generic_body.rs`. That failed gate took
5.32 s; its log is `connection-pairs-arena.log`. The former source is preserved
as `protocol-generic-array-arena.lani` beside that log. The unregistered tiny
`generic_array_limit.lani` fixture records the checked-layout dependency. Its
negative compilation probe reproduced LNC0017 before ELF emission; the receipt
is `generic-array-limit.log` in the same admission directory. It is not an
executable TLS regression gate.

The revised fixture explicitly owns one arena allocation and constructs a
three-word native byte-slice descriptor through small caller-storage records.
This is a test-only unsafe seam tied to the documented native data/count/stride
ABI, not a new production constructor. It checks actual `-8` and `+1` strides
and both physical endpoints, then preserves every previous layout, flight and
guard case. Its temporary descriptor is copied before those backing bytes are
reused. The peer requires exactly one 3,520,000-byte mmap with the allocator's
exact `MAP_PRIVATE|MAP_ANONYMOUS|MAP_32BIT` flags and a matching address-and-size
munmap, with no engine allocation, resize or extra release.
The revised normal-stack paired gate passed in 18.15 s: four cases (both suites
in both layouts), one strict ELF and one native process. Exact gate:
`paired_connections_match_independent_wire_epochs_and_authentication`. Its
independent wire oracles and sole-arena address/size ledger passed at production
`b26122db`, protocol `9c2bf1ca`, peer `ee5ce301`, and driver `f10e1ea6`. Log:
`target/stdlib-work/tls-connection-admission/connection-pairs-descriptor.log`.
The separate `fragmented_long_certificate_and_both_hello_retry_modes_execute`
gate passed in 25.30 s on those unchanged sources: four cases covering
requested-group HRR, cookie-only HRR, and eight-certificate flights with
ChaCha/native and AES/packed backing. It used one strict ELF/one native process
and the same exact sole-arena allocation/release ledger. Log:
`target/stdlib-work/tls-connection-admission/connection-fragments-descriptor.log`.
Production also received a source-reviewed outer-record overflow classification
correction: record framing above 16,640 bytes reports `RecordOverflow` and alert
22; the separate handshake reassembly cap retains its own error.

The independent test peer uses real OpenSSL Ed25519 chains, libsodium X25519 and
signature checks, Python hashlib/hmac and OpenSSL EVP AEAD. It verifies emitted
frames, transcript checkpoints, directional records, exporter, KeyUpdate,
application bytes and close order. Test stdout intentionally contains wire and
secret-derived diagnostics; this is not a deployable secret-handling program.
The fixture also checks source/entropy/seed lifetimes, pending suffix stability,
final client-Finished acknowledgement, buffer guards and both layouts.
The separate `connection_error_atomicity_and_record_epoch_boundaries_execute`
gate prepares 23 controls in both layouts (46 cases): caller metadata and ACK
atomicity, consumed header prefixes, record/handshake limits, CCS/order/EOF,
terminal error persistence, final permitted receiver app/close records and
next-old-key exhaustion, aligned last-slot KeyUpdate, sender update drain,
fragmented tickets with local controls, an authenticated KeyUpdate with a
trailing handshake frame rejected before receive-key installation, suppressed
fatal pending output and application withholding/half-close. Cases near sequence
or generation limits, or holding application data, use explicitly labeled
private state seams; they are not evidence of peer authentication. Public
paired flights exercise real trust.
The initial 44 controls passed their independent exact x86_64 Linux gate in
19.25 s, one strict ELF/one native process with an empty memory trace. This
supplemental receipt is superseded by the accepted 46-case fixture below. Log:
`target/stdlib-work/tls-connection-admission/connection-controls-first.log`.
Production was `b26122db`, controls `159cd2e5`, driver `f7aca22e`, and peer
`c895cf04`. The legal CCS half of operation20 uses actual CH transmission; its
late-CCS half deliberately injects the peer-Finished phase. Operation21's
partial-prefix EOF control uses only public progress.
The earlier source is preserved as
`target/stdlib-work/tls-connection-admission/controls-first-44.lani`.
The added operation22, in both layouts, brings the current fixture to 46 cases.
That enlarged gate independently passed in 17.82 s: one strict ELF/one native
process with an empty `mmap/munmap/mremap/brk` trace. It checks the full consumed
ciphertext prefix, sticky UnexpectedMessage, unchanged receive generation,
the already consumed AEAD sequence and a fatal alert under the unchanged
sending key.
Its frozen sources were production `b26122db`, controls `2f3fd0e2`, peer
`8545fc00`, and driver `f10e1ea6`. Rust driver build took 1.18 s and produced
`extended_tls_connection_execution-45bdd3cf3691412b`. Logs:
`target/stdlib-work/tls-connection-admission/connection-controls46.log` and
`build-connection-controls46.log` in the same directory.
The current portable selected profile is accepted. Real TCP/OpenSSL and
application admission remains separate; general TLS compliance is not claimed.
These tests do not establish constant-time generated code or general TLS/PKIX
compliance. TCP/OpenSSL peer evidence belongs to the adapter/application gates.
