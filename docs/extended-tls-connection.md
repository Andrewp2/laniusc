# Portable TLS connection engine

`ext::tls_connection` composes the Lanius negotiation, framing, transcript,
X25519/P-256, selected hash, key schedule, record and server-authentication
layers. It implements client and server roles in one allocation-free engine.
Socket ownership, nonblocking calls, entropy acquisition and deadlines belong
to `ext::tls_tcp`.

The source profile is TLS 1.3 with X25519 or secp256r1 ECDHE, explicit
certificate/proof signature policies, and an explicit suite policy:
AES-128-GCM/SHA256 (`1301`), AES-256-GCM/SHA384 (`1302`), or
ChaCha20-Poly1305/SHA256 (`1303`). The signature-policy/generic-key integration
is accepted on x86_64 Linux at engine `163f9b96`: all twelve engine gates passed
in four serialized invocations. Earlier pinned milestones are recorded
separately below. Connected TCP/application and performance admission for this
migration are separate, still-pending gates.
The server authenticates; its client is explicitly anonymous. There is no PSK
resumption, early data, client certificate authentication or post-handshake
authentication. Received NewSessionTicket messages are structurally validated
and discarded; the cache is disabled and this engine never issues a ticket.

This profile does not satisfy the complete mandatory algorithm set in
[RFC 8446 section 9](https://www.rfc-editor.org/rfc/rfc8446.html#section-9).
The ordered certificate verifier retains its documented offline,
explicit-anchor constraints; this engine does not add general PKIX path
building, normalized distinguished names, revocation or unsupported policies.
See [the connection contract](tls-connection-contract.md),
[path validation](extended-x509-path.md),
[service identity](extended-service-identity.md), and
[authentication](extended-tls-authentication.md).

## Construction and storage

`client(config, buffers, entropy)` and `server(config, buffers, entropy)` return
an `Engine`. `ClientConfig` supplies a typed `groups: GroupPolicy` and
`initial_share: Option<Group>`; `ServerConfig` supplies `groups`. Policies contain
one or two distinct groups. The server chooses its first mutual group and requests
HRR when that share is missing. The application default is X25519 then P-256,
with an initial X25519 share. `Negotiated` reports the selected typed `group`.

Call `entropy_layout(groups)` for the sole slot-layout authority. Its `EntropyLayout`
returns exact `length`, `x25519_offset: Option<i32>` and `p256_offset: Option<i32>`.
Random always occupies the first 32 bytes. X-only and P-only use 64 bytes. Dual
policy uses 96 bytes with X at offset32 and P at offset64, independently of
preference order. Every enabled slot requires independent fresh cryptographic OS
bytes. P-256 is derived first; zero or out-of-range scalar returns
`InvalidEphemeralScalar` before X derivation or caller-buffer writes. The engine
caches each enabled public key once and reuses the appropriate independent state
on HRR. P-256 TLS shares are exactly 65-byte uncompressed points; point validation
precedes scalar multiplication. The full 32-byte shared x coordinate, including
leading zeros, is input to the actually selected SHA256/SHA384 key schedule.
Production callers use `tls_tcp`, which acquires this input through bounded
nonblocking OS entropy calls. It allows eight total P-scalar candidates, refilling only
the P slot at most seven times on `InvalidEphemeralScalar`, under the original deadline
and HostBudget. There is no modular reduction or deterministic fallback. Fixed entropy
appears only in test fixtures. See the exact [group integration contract](tls-group-integration-plan.md).
The engine copies entropy and the server signing seed; their original inputs
may be overwritten after construction. This is not a secure-erasure guarantee.

Client configuration supplies immutable trust anchors, a copied DNS/IP
reference identity, explicit UTC certificate time, optional DNS SNI, and an
encoded ALPN offer list (concatenated nonempty `u8`-length-prefixed names).
Server configuration supplies an immutable ordered DER chain, a 32-byte seed,
and one preferred **plain**, unprefixed ALPN protocol. `require_alpn` requires a
negotiated protocol. SNI and certificate reference identity remain distinct.
The server derives the real Ed25519 seed's public key, imports the actual leaf
SPKI through `signature::parse_spki`, and compares all 32 bytes before it can
emit a handshake. The local signer remains Ed25519 only. Issuer certificate
signatures may independently use the supported Ed25519, P-256 ECDSA/SHA256,
RSA PKCS#1/SHA256, or RSA-PSS/SHA256 profile. This adds no RSA/ECDSA private
signer or external signing substitute.

`ClientConfig.proofs: signature::Policy` controls CertificateVerify offers;
`certificates: Option<signature::Policy>` controls extension 50. `None` omits
extension 50 and uses the actual extension-13 fallback. Both local policies
are validated before construction work. ServerHello selects suite/group only,
never a proof algorithm. The client constructs authentication's owned policies
from `signature_policy` over the actual retained ClientHello, including CH2,
rather than trusting mutable caller metadata or assuming Ed25519.

The server separately requires Ed25519 in the actual proof offer. Each sent
certificate's algorithm must appear in the effective certificate offer.
Algorithms are classified once during construction and cached as owned scheme
values; the leaf is not parsed twice. A transmitted root is included in this
stricter sender check, even though path validation can trust a configured
anchor without verifying its self-signature. Omitting a root is supported.
Unsent trust anchors are never eagerly imported by engine construction.

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
views never point into temporary inline engine arrays. The path workspace
includes owned imported-key cache entries, so sixteen logical slots occupy
more physical bytes than the earlier parser-only slots. Callers must use
`size_of<x509_path::Slot>()`, not an old byte constant. It is used synchronously
and may retain obsolete borrowed parser records after an
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
`peer_key()` returns `Option<signature::PublicKey>` with no certificate backing
borrow. Failure/abort drops the engine's retained key. A copied returned key
remains owned after frame/cache retirement; it conveys no trust outside the
decision that produced it.

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

Defaults allow a 1 MiB handshake body as a storage ceiling. The shared path
verification account starts with 1 Gi abstract work credits. Authentication
also reserves its conservative `4096 + 256 * frame_length` tariff before
nested parsing, plus actual path/signature work and owned-key copy credits.
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

## Suite policy, late binding and SHA384 work

Both configurations now own `suites: tls_suite::Policy`, containing one to three
unique ordered suites. Constructors revalidate its public fields before ephemeral
operations or caller-buffer writes. ClientHello emits exactly that active order;
the server selects its first permitted offered suite. There is no implicit suite
fallback outside the policy. The default order is ChaCha20, AES128, AES256.
`Negotiated.suite` uses the shared `tls_suite::Suite` authority.

Selection, transcript, phase secrets, master and exporter are absent before an
actual validated suite decision. CH1 stays in its caller-owned hello region; its
frame length and handshake-byte debit are recorded once. On the client's validated
SH/HRR, its actual suite hash binds and hashes those exact retained bytes once.
The server binds after checked CH1 selection. HRR never rebinds, including to a
different suite with the same hash. The synthetic HRR frame is 36 or 52 bytes.
CH1 remains immutable while CH2 comparison borrows it; the CH2 and cookie ranges
remain disjoint. SHA384 still consumes the raw 32-byte X/P ECDHE secret.

Typed secrets/digests own 48-byte maximum storage. Finished uses exactly 32/48
active bytes; the shared CertificateVerify helper uses 130/146. Snapshot and
secret results are bound to stable locals before borrowing views. The final
client-Finished ACK, server client-Finished verification, traffic epoch switches,
one pending wire cursor and fatal-alert-before-key-retirement ordering are
preserved. Exporters use the bound hash and permit at most 8160/12240 bytes.

Default `max_work` is **68,719,476,736 (64 Gi) abstract credits**. This finite
policy allows the existing normally chunked 1 MiB echo program to use AES256's
larger admitted charges; record/control/byte and host deadline limits remain
independent. It is neither 64 Gi instructions nor an elapsed-time guarantee.
Earlier SHA256 charges remain legacy weights, not a universal source-action
bound. Existing SHA256 operation and group tariffs retain their values.

For the new SHA384 branch, set `C=16384`, `B(n)=ceil((n+17)/128)` and
`N=ceil(o/48)`. Private checked-at-use helpers implement these source-counted
compression, wrapper and byte-traversal envelopes:

```text
Hash(n) = C*B(n) + 8192 + 32*(n+48)
HMAC(n) = C*(3+B(n)) + 12288 + 32*(1024+n)       # TLS key<=128
E(l,c,0) = 8192 + 32*(1024+l+c)   # encoded-info staging; no compression
E(l,c,o>0) = C*(2 + B(11+l+c)+1
                  + (N-1)*(B(59+l+c)+1))
              + 4096*(N+2)
              + 32*(1024+l+c + N*(10+l+c+97) + o)
Stream(n) = C*(ceil(n/128)+1) + 16384 + 32*(n+256)
Snapshot = 2*C + 12288 + 32*(128+48)
Rewrite(n) = Snapshot + 12288 + Stream(n+52) + 4096 + 32*52
```

`C` covers the fixed SHA512-family loading, schedule and 80 rounds with a
conservative source-action margin. Copies include state-wrapper allowances of
4096 per node and 32 credits per traversed byte. Stream reserves a compression
upper bound independent of current residue. Snapshot reserves two padding blocks.
These envelopes do not claim compiler constant-time behavior or exact machine
instruction counts.

| Actual operation | Additional SHA384 work, before the call |
| --- | --- |
| Bind selected transcript | 12,288 initialization/copy credits |
| Append retained CH1 or another transcript frame | `Stream(frame_length)`; no second byte quota debit |
| HRR rewrite | `Rewrite(hrr_length)` |
| No-PSK handshake schedule through two HS secrets and master | `2*HMAC(48)+HMAC(32)+2*Hash(0)+2*E(7,48,48)+2*E(12,48,48)` (30 compressions), plus separate snapshot |
| App client/server secrets and exporter master | `2*E(12,48,48)+E(10,48,48)` (12), plus separate snapshot |
| Finished generation/verification | `E(8,0,48)+HMAC(48)` (8), plus separate snapshot |
| Shared CV input | `4096+32*146`, plus separate snapshot and unchanged Ed25519/signature allowance |
| Each record owner | `E(3,0,32)+E(2,0,12)+196608` (8 plus AES setup increment) |
| Actual KeyUpdate installation | `E(11,0,48)+record_owner` (12 plus AES setup increment) |
| Export(label,context,output) | `Hash(0)+E(label_length,48,48)+Hash(context_length)+E(8,48,output_length)` |

AES256 adds four rounds to the existing AES128 path. Four rounds execute
`4*16*11*8=5632` fixed GF-multiplication iterations; at most 16 source actions
per iteration plus round bookkeeping fits **131,072 additional credits per AES
block**. Protected record charging adds
`131072*(1+floor((charged_length+16)/16))`, covering the encrypted inner/type and
tag AES block. Incoming wire length safely dominates inner length. Plain CH/SH
and ignored CCS do not pay this fee. A cached AES256 setup adds **196,608**:
131,072 for the extra four hash-subkey encryption rounds plus 65,536 for extra
key expansion. AES128 and ChaCha record fees are unchanged.

All debits check before subtraction and before the operation they own. Already
spent parsing or earlier stage work remains spent on failure. Label/context
lengths are <=249/255, output<=12240 and N<=255; raw context/frame lengths fit
validated i32 domains. Even their largest multiplication/addition stays far below
u64 maximum, and the accumulated allowance never increases at HRR or KeyUpdate.
Authentication has its own shared path/signature work account; this table does
not replace that module's debits.

## Group-specific work

X-only construction retains 1,048,576 work units, and its exchange/schedule retains
1,179,648. Each P-256 public derivation or exchange reserves 67,108,864 before the
expensive call; P-256 schedule work adds 131,072. Dual construction reserves both
public derivations. The [source-counted envelope](tls-group-integration-plan.md#work-accounting)
is conservative abstract admission work, not executed instructions or an elapsed-time
bound. Rejected scalar admissions run fixed decode/range checks and are separately
bounded by the adapter's eight-candidate cap. Default engine work is 64 Gi;
large certificate/record workloads still need explicit sufficient session/path limits.

## Signature-policy integration

The current source uses one `path_budget.verification` allowance for imported
keys, algorithm classification, certificate/CV verification and the shared
attempt count. Earlier parsing/classification charges remain spent on later
failure. Local Ed25519 signing reserves **67,108,864 shared verification
credits** and one attempt, as well as the separate **1,048,576 engine
protocol-work credits**. Both work allowances and the attempt are preflighted
before any of these debits. The protocol check also includes every known
pre-sign SHA384 debit: the 50,688-credit snapshot and 8,768-credit CV-input
staging fee. Their existing later debits each occur once. Stats reads the
shared attempt counter; there is no per-certificate, per-algorithm or proof
reset. Signature resource errors during local credential setup map to the
engine's existing `Limit`;
unsupported or mismatched local credentials map to `Credential`.

The signing envelope follows the actual Ed25519 source: 512 fixed point
double/add/select steps, each below 20 field products and 64 linear
operations. At 512 credits per product and 256 per linear operation, a step
fits 32,768 credits. Another 4,096 products and 16,384 linear operations
cover the two affine encodings and scalar reductions. The fixed 130/146-byte
CertificateVerify input needs at most five SHA512 blocks across seed,
nonce and challenge hashes; allowing 65,536 credits per block still gives
`512*32768 + 4096*512 + 16384*256 + 5*65536 < 67108864`. These are conservative
source-action admission credits, with no timing or compiled-instruction bound.
The engine protocol account separately pays framing, transcript and record
operations; neither account refills the other.

The new exact gates in `extended_tls_connection_execution` are:

- `mixed_certificate_issuers_keep_real_ed25519_signer_and_full_epochs`: six
  full paired connections, real Ed25519 leaf signer under RSA PKCS#1,
  ECDSA/P-256, and RSA-PSS issuer certificates, both layouts and all three
  existing suites. OpenSSL generates and independently verifies each path;
  the wire peer checks Ed25519 proofs, complete records and all epochs.
- `actual_signature_offers_fallback_rejections_and_owned_key_retirement_execute`:
  six accepted and eight rejected offer cases. These separate proof and
  certificate permission, exercise extension-50 omission/fallback, retain
  copied generic keys through certificate/cache retirement and abort, and
  reject non-Ed proof offers or unoffered sent-certificate algorithms before
  any successful ServerHello. A labeled private metadata challenge changes
  the retained ClientConfig after CH emission; actual CH bytes remain policy
  authority. This is not a supported Engine restoration API.
- `local_signing_shares_verification_work_and_attempt_boundary_after_credentials`:
  eight layout cases, exact and one-less remaining shared signing work under
  SHA256 and SHA384. A labeled private seam only decreases the existing account
  after real credential import and complete Certificate acknowledgement.
  Exact credit must produce a separately verified proof and complete all
  epochs. One less must leave the attempt and remaining shared work unchanged,
  emit only the independently decrypted fatal alert, and withhold the key.
  These counter probes do not describe a public allowance-reset API.
- `local_signing_preflights_all_presign_protocol_work_before_shared_reservation`:
  twelve cases, pre-sign protocol credit minus one/exact/plus one under both
  hashes and layouts, capped after the same real Certificate ACK. Minus one
  preserves the shared verification work, attempt and handshake backing.
  Exact/plus one signs and stages a full CertificateVerify that libsodium
  independently verifies byte for byte against the real transcript. The
  subsequent frame reservation correctly fails because those cases leave
  zero/one protocol credit; no wire CV or authentication success is claimed.
  The crypto reservation and attempt remain spent once signing was admitted.

The public constructor/admission fixture adds ten layout cases for empty,
duplicate or forbidden proof policies and empty/unknown certificate policies,
bringing its accepted total to 90. Existing Ed-only paired cases retain their
actual offered bytes, shared budgets, ACK barrier, all record epochs, partial
progress, close/KeyUpdate and full guard checks. The certificate work allowance
is explicitly sized for the new signature tariffs; it is never replenished.

### Signature integration admission

All twelve gates passed against unchanged frozen engine `163f9b96`, driver
`599b184c`, protocol `83cb790b` and independent peer `02020d0b`. The ordinary
fixture is `2d4aa639`, controls `c361dee4`/`2dacff2d`, and constructor admissions
`11d38ca9`/`ebd275ff`. Root ran four disjoint selections of
`extended_tls_connection_execution-45bdd3cf3691412b`:

| Invocation | Gates and scripted cases | Strict ELFs / native processes | Elapsed |
| --- | --- | --- | --- |
| Ordinary exact gate | Storage, CH construction, partial ACK and abort consumer | 1 / 1 | 21.66 s |
| Four new signature gates | Mixed issuers 6; offers/copy lifetime 14; shared signing work 8; pre-sign protocol work 12 | 1 / 4 | 36.34 s |
| Five paired regression gates | X pairs 4; long/HRR 4; P groups 8; SHA384-only 4; cross-hash/cookie HRR 4 | 1 / 5 | 42.15 s |
| Two `boundaries_execute` gates | Controls 50; constructor admissions 90 | 2 / 2 | 47.98 s |

This is **204 scripted cases plus the ordinary consumer, five compiled strict
ELFs and twelve native processes**, across four invocations. It is not a
single full-suite invocation. The two sets of paired gates each share their
own protocol compilation through `OnceLock`. Each of the nine paired native
processes owns exactly one 3,520,000-byte test-arena mmap and matching
address/size munmap; the peer rejects every additional allocation event.
Controls, constructor admissions and the ordinary consumer require empty
mmap/mremap/munmap/brk traces. The portable engine itself allocates nothing.

The final receipt includes the pre-sign guard correction found in source
review before engine admission: the initial SHA384 check now includes snapshot
and CV-input staging fees before reserving shared crypto work or an attempt.
The later fees remain unchanged and occur once. There was no failed engine
runtime gate in this admission. The exact/plus-one protocol probes prove a
valid **staged** proof followed by the expected post-sign frame limit, as
described above; they do not claim a completed wire proof or authenticated
connection. Full wire proof/Finished/ACK publication is separately checked by
the accepted shared-work-exact and ordinary paired success cases.

The fresh joint engine/authentication/verify-certificate Rust driver build
passed in 1.46 s. Its log is
`target/stdlib-work/tls-signature-engine-cert-control-build.log`; this build
receipt does not admit the other targets' runtime behavior. Engine runtime
logs in the same directory are:

- `tls-signature-engine-ordinary-first.log`;
- `tls-signature-engine-new-first.log`;
- `tls-signature-engine-paired-regression-first.log`;
- `tls-signature-engine-boundaries-first.log`.

All invocations used `RUST_MIN_STACK=16777216`,
`LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000`, `LANIUS_DEBUG_STAGE_ERRORS=1`, a
100 s outer timeout and 35 s lock wait. The ordinary inner timeout was 60 s;
the other three used 90 s. These commands reproduce the accepted selections
without repeating a gate:

```bash
engine=target/stdlib-build/debug/deps/extended_tls_connection_execution-45bdd3cf3691412b
run_engine() {
  local inner_seconds="$1"
  shift
  RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
    LANIUS_DEBUG_STAGE_ERRORS=1 timeout --kill-after=2s 100s \
    flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
    timeout --kill-after=2s "${inner_seconds}s" "$engine" "$@" \
    --nocapture --test-threads=1
}
run_engine 60 --exact ordinary_connection_storage_and_pending_wire_consumer_executes
run_engine 90 \
  --skip ordinary_connection_storage_and_pending_wire_consumer_executes \
  --skip connection_error_atomicity_and_record_epoch_boundaries_execute \
  --skip group_entropy_scalar_encoding_and_work_admission_boundaries_execute \
  --skip paired_connections_match_independent_wire_epochs_and_authentication \
  --skip fragmented_long_certificate_and_both_hello_retry_modes_execute \
  --skip p256_and_dual_group_connections_match_independent_openssl_ecdh \
  --skip sha384_only_suite_both_groups_and_publication_execute \
  --skip sha384_late_binding_cross_hash_retry_and_cookie_execute
run_engine 90 \
  --skip ordinary_connection_storage_and_pending_wire_consumer_executes \
  --skip connection_error_atomicity_and_record_epoch_boundaries_execute \
  --skip group_entropy_scalar_encoding_and_work_admission_boundaries_execute \
  --skip mixed_certificate_issuers_keep_real_ed25519_signer_and_full_epochs \
  --skip actual_signature_offers_fallback_rejections_and_owned_key_retirement_execute \
  --skip local_signing_shares_verification_work_and_attempt_boundary_after_credentials \
  --skip local_signing_preflights_all_presign_protocol_work_before_shared_reservation
run_engine 90 boundaries_execute
```

Root performed all compiler/native admission. Author checks were Python AST
parsing, Rust formatting, and source/whitespace review only. GPU execution here
is the compiler running on the GPU; user GPU kernels remain unverified.
Independent real OpenSSL RSA/ECDSA server-proof interoperability belongs to
the connected TCP/application gates, still pending for this migration. The
new paired sender remains a real Ed25519 signer. No general PKIX, timing,
compiled constant-time or secure-erasure guarantee is added.

## Earlier SHA384 verification scope

That milestone's eight exact filters retained the six earlier names and added:

- `sha384_only_suite_both_groups_and_publication_execute`: four singleton-AES256
  flights across X/P and native/packed storage;
- `sha384_late_binding_cross_hash_retry_and_cookie_execute`: four requested-group
  or cookie-only HRR flights whose actual AES256 selection differs from the
  client's preferred SHA256 suite.

The existing pair, long/HRR and P-group modes keep explicit prior two-suite
SHA256 policies. Their wire peer now requires an explicit hash and suite at
helper boundaries. The independent peer checks both published suite IDs against
its own first-policy-intersection selection and the actual wire, in addition to
both published group IDs. It verifies complete SHA384 CV/Finished, HRR synthetic
hash, schedule, records, exporters and directional KeyUpdate bytes through
OpenSSL/hashlib/hmac. Wire-feed fragmentation does not by itself mean that one
small handshake frame spans multiple protected records.

At that snapshot the public-constructor/admission mode had 80 layout cases:
the previous 52 plus suite-policy validation, unbound pre-SH state, actual SHA384 transcript
snapshots, exact/one-less selected-hash handshake charges and HRR suite/history
rejections. Constructor metadata/policy failures preserve the full caller arena.
Initial CH pumping and every partial ACK retain absent suite/transcript state;
a validated SH/HRR binds the actual hash, without a second CH1 byte debit.

After a real authenticated SHA384 handshake, the paired fixture checks the full
12,240-byte exporter against independent HKDF, rejects 12,241 before any output
or work change, and checks zero-output export's nonzero exact charge and all
sentinels. After both close alerts drain, a labeled private `work_left` seam
lowers each of two independent real endpoints once: exact zero-output allowance
succeeds and reaches zero; one less fails terminally without output/publication.
It does not manufacture authenticated/nonce state, replenish credit, or claim
that a public API can reset the account. Public KeyUpdate's observed work delta
is checked separately against the old SHA256 fee or the complete SHA384/KU/AES
fee; exporters remain unchanged after traffic updates.

These are test-only diagnostic protocols that expose test-derived secrets and
wire bytes. The paired processes explicitly own their sole caller arena; the
engine still allocates nothing. The control mode adds two isolated SHA384
Finished cases per layout (50 total controls): a valid 48-byte Finished and a mismatched tag each span two separately
EVP-authenticated records. The first fragment leaves the transcript/epoch
unchanged; only valid completion appends the frame and installs the application
opener. Mismatch retains the old receive generation, withholds publication and
produces the independently checked fatal alert. These labeled private phase/keys
seams test reassembly and Finished verification, not certificate authentication.

## Earlier SHA384 admission

All eight engine gates passed against production `635898ed`, with negotiation
`b3044892`, driver `44df5a19`, and frozen protocol/peer `4879ee72`/`83c63d68`.
Root ran two disjoint filter invocations of the same driver binary:

| Invocation | Gates and accepted cases | ELFs / native processes | Elapsed |
| --- | --- | --- | --- |
| Paired protocols | X pairs 4; long/HRR 4; P groups 8; SHA384-only 4; cross-hash/cookie HRR 4 | 1 / 5 | 32.65 s |
| Boundaries and ordinary | Controls 50; admissions 80; ordinary consumer | 3 / 3 | 50.63 s |

This is **154 scripted cases plus the ordinary consumer, four compiled strict
ELFs and eight native processes**. The five paired gates share one protocol
compilation through `OnceLock` within their invocation. Each paired process
has exactly one explicit 3,520,000-byte caller arena mmap and its matching
address/size munmap; the oracle rejects any other allocation event. Controls,
admissions and the ordinary consumer have empty mmap/mremap/munmap/brk traces.
Controls used `302afb1c`/`2dacff2d`, admissions `2375f1f7`/`81ec6c10`, and ordinary
fixture `0d3e703b`. The joint engine/negotiation Rust build passed in 1.24 s.

Evidence under `target/stdlib-work/`:

- `tls-sha384-engine-paired-first.log`;
- `tls-sha384-engine-boundaries-first.log`;
- `tls-sha384-engine-negotiation-build-first.log`.

Both runtime invocations used `RUST_MIN_STACK=16777216`,
`LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000`, `LANIUS_DEBUG_STAGE_ERRORS=1`, a 100 s
outer timeout, 35 s lock wait and 90 s inner timeout, with `--nocapture
--test-threads=1`. Binary:
`target/stdlib-build/debug/deps/extended_tls_connection_execution-45bdd3cf3691412b`.
The paired invocation skipped the ordinary, controls and admissions filters;
the second skipped the five paired filters. No test was repeated between them.

Before these engine gates, a separate AES256 application entry compilation
correctly rejected the all-literal snapshot-cost expression as i32 where u64 was
required (`LNC0006`, 4.08 s, `tls-sha384-app-interop-fresh.log`). Root added one
explicit `as u64` to that return expression. Its value remains 50,176 abstract
credits; no compiler, API, protocol, oracle or expectation changed. The admitted
engine hash above includes that cast. There was no failed engine gate.

Root performed all compiler/native admission. Author-side checks were Python
AST parsing, targeted Rust formatting and static/whitespace review; the author
ran no Cargo, GPU/compiler, native or cryptographic oracle process for this
migration. These receipts admit the portable scripted profile, not a general
certificate policy or the complete RFC mandatory algorithm set. Transport and
real-peer application evidence remains in their own guides. Earlier receipts
below apply only to their pinned source versions.

## Earlier SHA256 typed-group admission

The typed-group/P-256 portable engine migration is accepted on x86_64 Linux at
engine `eaf51c4c` and negotiation `3f089664`. Six separate exact invocations each
compiled one strict ELF and ran one native process. They checked **114 scripted
cases plus the ordinary consumer**.

| Exact gate | Accepted cases | Elapsed |
| --- | --- | --- |
| `ordinary_connection_storage_and_pending_wire_consumer_executes` | Ordinary constructor/pending-wire consumer | 17.37 s |
| `paired_connections_match_independent_wire_epochs_and_authentication` | 4 X25519 flights: both suites × both layouts | 21.40 s |
| `fragmented_long_certificate_and_both_hello_retry_modes_execute` | 4 X25519 flows: both HRR forms and long eight-certificate flights | 26.49 s |
| `p256_and_dual_group_connections_match_independent_openssl_ecdh` | 8 P-only/dual flights, both suites/layouts and both requested-group directions | 21.14 s |
| `connection_error_atomicity_and_record_epoch_boundaries_execute` | 46: 23 controls × both layouts | 20.18 s |
| `group_entropy_scalar_encoding_and_work_admission_boundaries_execute` | 52: 26 admissions × both layouts | 21.07 s |

The ordinary, control and admission processes had empty
`mmap/munmap/mremap/brk` traces. Each of the three pair/fragment/P-group processes
owned one explicit 3,520,000-byte caller arena, with exact allocator flags and a
matching address-and-size munmap. The engine did not allocate, resize or release
that storage. This is six ELFs/six native processes, not one whole-target run.

Final pair/fragment/P-group protocol `b21543b6` and peer `c9fe9ebf` serialize both
client and server `Negotiated.group` IDs. The independent peer checks each against
its first-mutual policy selection and the actual authenticated flight's wire
selection. Controls used fixture `f8ad669a` and peer `ece7e979`. Admission fixture
`4652bbf0` and peer `410ae4f5`, ordinary fixture `86a19948`, and driver `a2b1e879`
remained frozen for their receipts. The initial two-target Rust build took 1.70 s;
the final four-target build took 1.75 s. Binary:
`extended_tls_connection_execution-45bdd3cf3691412b`.

Every exact gate used the serialized 100 s outer / 35 s lock-wait / 60 s inner
wrapper, `RUST_MIN_STACK=16777216`, `LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000`,
`LANIUS_DEBUG_STAGE_ERRORS=1` and `--exact GATE --nocapture --test-threads=1`.

Logs are under `target/stdlib-work/tls-connection-admission/`:

- `group-engine-ordinary-first.log`;
- `group-engine-pairs-final.log`;
- `group-engine-fragments-final.log`;
- `group-engine-p256-publication.log`;
- `group-engine-controls-helper-fixed.log`;
- `group-admission-first.log`;
- `group-build-first.log` and `group-build-frozen.log`.

The initial P-group receipt passed eight cases in 22.66 s using protocol
`3a96ba67` and peer `3c39f52c` (`group-pairs-first.log`). Review strengthened the
published-group assertions from client/server equality to two independent wire
comparisons. The final 21.14 s receipt admits that stronger fixture. This was a
coverage improvement, not a production fix.

The first migrated controls attempt compiled its ELF, then failed in CPU oracle
input preparation before native launch: the helper still called `shared_key()`
without the new explicit group/policy arguments. That attempt took 20.81 s
(`group-engine-controls-first.log`). The one-line test-oracle migration now passes
X25519 and two X-only policies explicitly. CPU-only preparation then constructed
46 cases/3,170 bytes; the final 20.18 s native receipt above admits the repaired
oracle. Production and the Lanius controls fixture did not change for this repair.

The existing ordinary, pair, long/HRR and 46-control fixtures now select X-only
explicitly and preserve their original entropy and policy meaning. The added gate
`p256_and_dual_group_connections_match_independent_openssl_ecdh` checks eight paired
flights across both suites/layouts, both group HRRs and P cookie-only HRR.
`group_entropy_scalar_encoding_and_work_admission_boundaries_execute` checks 52
layout cases: exact entropy slots/length, zero/order/oversized scalars,
duplicate/unoffered policy, malformed/compressed/off-curve peer shares, exact and
one-less P exchange work, and no caller-buffer mutation on the tested early
admission rejections.
It uses public entry points and fixed test entropy; no private authenticated phase
is manufactured. Source fixtures preserve no-auth/publication, source/guard and
manual owner contracts. The P peer cross-checks affine bigint public/ECDH values
against raw OpenSSL in both directions before checking emitted record bytes.

Root performed all serialized compiler/native admission. Author-side checks were
Python syntax parsing, targeted Rust formatting, whitespace/static review, and
the explicitly authorized CPU-only controls-input preparation after its helper
migration omission. No author-side Cargo, compiler/GPU or native fixture run
occurred. These receipts cover the portable selected profile. TCP/OpenSSL and
application acceptance have separate evidence in their respective guides; this
module still supports the documented Ed25519/SHA256 credential profile and does
not claim the complete mandatory TLS algorithm set or general PKIX validation.

### Earlier X25519-only receipts

The earlier portable paired selected profile was accepted on x86_64 Linux. The four
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
The earlier X25519 portable selected profile was accepted. Real TCP/OpenSSL and
application admission remains separate; general TLS compliance is not claimed.
These tests do not establish constant-time generated code or general TLS/PKIX
compliance. TCP/OpenSSL peer evidence belongs to the adapter/application gates.
