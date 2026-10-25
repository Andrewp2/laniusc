# Portable TLS server-flight authentication

`ext::tls_authentication` verifies a TLS 1.3 server authentication flight in strict order: EncryptedExtensions, Certificate, CertificateVerify, Finished. Certificate processing calls the actual [bounded X.509 path validator](extended-x509-path.md) with explicit anchors, expected service identity, and time. CV proves possession of that validated leaf key; Finished binds it to the supplied handshake secret and transcript. The implementation is [tls_authentication.lani](../extended/ext/tls_authentication.lani).

The authentication checkpoints and signature context follow [RFC 8446 sections 4.4.1–4.4.4](https://www.rfc-editor.org/rfc/rfc8446.html#section-4.4). This module implements selected SHA-256/SHA-384 with the Ed25519, X.509 server-authentication profile. It has no allocation, IO, foreign TLS backend, or caller-supplied trust flag/key shortcut.

**The selected-hash migration passed runtime admission on 2026-10-25 for GPU-compiled native x86_64 Linux output.** Three separate exact gates passed 232 protocol layout cases / 716 observations plus four ordinary flows. Earlier SHA-256-only receipts remain separate below. User GPU execution, other targets and isolated throughput remain unverified.

**Authenticated means server Certificate, CV, and server Finished have been verified. It does not mean the connection is Established.** A full client engine must still commit its own Finished to the transport before releasing application data, as specified by the [connection contract](tls-connection-contract.md). This component exposes a validated peer key and transcript, and has no application-data API.

## Inputs and construction

Here `View`, `Result`, and `Option` abbreviate the corresponding `core::slice`, `core::result`, and `core::option` types.

```lanius
pub struct Config {
    anchors: View<View<u8>>,
    reference: ext::service_identity::Reference,
    unix_time: i64,
    max_frame: i32
}
pub fn server(
    transcript: ext::tls_transcript::State,
    server_handshake_secret: ext::tls_schedule::Secret,
    offered_signature_schemes: View<u16>,
    config: Config
) -> Result<State, Error>;

pub enum Phase {
    EncryptedExtensions, Certificate, CertificateVerify, Finished,
    Authenticated, Failed
}
```

The caller supplies a transcript through **already checked CH/SH negotiation**, and the corresponding owned, tagged server handshake traffic secret. Its algorithm must match `transcript.algorithm()`: SHA-256 uses 32 active bytes and SHA-384 uses 48. Construction copies both values, plus the reference identity and time. It retains only the immutable anchor descriptors/backing. Changing the original secret, reference object, offer list, or transcript afterward does not change this State.

Import raw secret bytes with `tls_schedule::secret_from_view(algorithm, bytes)` before calling this constructor. Raw metadata and exact 32/48-byte length validation belong to that factory. Authentication no longer has an `InvalidSecretLength` constructor branch; a mismatched typed secret returns `HashMismatch`.

The transcript shape must be two messages without HRR, or four messages with HRR rewrite applied. This catches an incorrect checkpoint shape; it does not establish transcript provenance or negotiate CH/SH. The caller must have checked versions, cipher/hash/group, shares, session echo, HRR restrictions, extensions, and the selected X.509 profile. Use the checked transcript and service-identity constructors rather than fabricated state/fields.

The offered signature list has 1 through 32767 `u16` entries and must contain Ed25519 (`0x0807`). It covers the **CV offer**. The caller must separately ensure certificate Ed25519 signatures are permitted by the CH `signature_algorithms_cert` policy, or its `signature_algorithms` fallback. Path algorithm support alone does not check those offers.

Anchors must contain 1 through 8 logically valid DER views. `max_frame` is a complete handshake-frame limit, including its four-byte header, from 4 through 16777219. Construction checks offer/anchor-list metadata, bounds the anchor count before nested indexing, and checks every permitted anchor descriptor's metadata. Only then does it check transcript/secret hash agreement, followed by the frame limit, bounded offers, and transcript shape. `HashMismatch` precedes State construction or work/cryptographic progress; malformed supplied metadata takes precedence. No constructor parses an anchor or accepts a peer key. Explicit anchor/path/reference/time validation occurs during Certificate.

## Feeding complete frames

```lanius
State.feed(frame: View<u8>, certificate_scratch: View<ext::x509_path::Slot>,
           budget: &ext::x509_path::Budget) -> Result<Phase, Error>;
State.phase() -> Phase;
State.is_poisoned() -> bool;
State.authenticated() -> bool;
State.failure() -> Option<Error>;
State.peer_key() -> Option<ext::ed25519::Key32>;
State.transcript() -> Option<ext::tls_transcript::State>;
State.borrow() -> &State;
```

Each feed requires exactly one complete handshake frame. It accepts no fragments, coalesced suffix, record header, alert, or application bytes. Reassembly and authenticated record content belong to the [framing](extended-tls-framing.md) and [record](extended-tls-record.md) layers. EE extension meaning, placement, offered-versus-selected values, ALPN/SNI, and other negotiation checks remain the caller's responsibility before feeding EE. The codec checks its framing and duplicate extensions here.

| Expected frame | Checks before transcript advance |
| --- | --- |
| EncryptedExtensions | Exact expected kind and complete EE schema; caller has checked extension meaning |
| Certificate | Empty server request context, nonempty list, at most eight entries, no CertificateEntry extensions, then actual path/identity/time validation |
| CertificateVerify | Scheme `0x0807`, exactly 64 signature bytes, one available shared signature attempt, and valid Ed25519 proof using the validated leaf key |
| Finished | Exactly 32 SHA-256 or 48 SHA-384 verify bytes and correct selected-hash MAC using the copied server handshake secret and current transcript hash |

Certificate entries are DER X.509 certificates. Raw public keys and every nonempty CertificateEntry extension are explicitly unsupported. This includes OCSP and SCT extensions; the bridge does not silently ignore their meaning or claim revocation/CT verification. A server Certificate context must be empty and its list nonempty. Path order, supported certificate algorithms, constraints, anchor handling, DNS/IP identity, and inclusive explicit UTC time checks follow the validator's documented bounded offline profile. The bridge inherits that profile's limitations; it does not add general path building or revocation policy.

The bridge collects at most eight small DER-view descriptors locally. Parsed certificate records use caller-provided Slot workspace; no inline array of parsed certificates is created inside State. On Certificate, scratch must have at least `presented_entry_count + configured_anchor_count` slots. No scratch is required for EE, CV, or Finished: the argument is ignored in those phases. Scratch is never retained by State.

The CV signed input uses the selected transcript through Certificate: 130 bytes for SHA-256 or 146 for SHA-384. Ed25519 remains the signature scheme in either case, with a 64-byte signature. CV is appended only after successful verification. Finished is checked against the selected transcript through CV and appended only after successful verification. The leaf key is committed internally only after complete path success and Certificate transcript append; it remains unavailable through both getters until Finished succeeds.

## Owned CertificateVerify input

```text
CVInput { bytes: [u8;146], length: i32 }
certificate_verify_input(side: ext::tls_schedule::Side,
                         hash: ext::tls_hash::Digest) -> CVInput
CVInput.view(&self) -> View<u8>
```

The shared helper builds either RFC context: 64 spaces, `TLS 1.3, server CertificateVerify` or `TLS 1.3, client CertificateVerify` (33 bytes each), an explicit zero separator at offset 97, then the active transcript digest at offset 98. Its active length is `98 + HashLen`. It initializes all 146 owned bytes; the 16 inactive SHA-256 bytes are zero. The server verifier uses the server context. Callers of the client helper must still enforce their own permitted authentication flow.

The result copies the digest and retains no transcript/digest borrow. Bind it to a stable owned local before calling `.view()`. That borrowed `&self` view is valid only while the same CVInput remains live and unchanged at the same location; a copied receiver or chained temporary must not let inline-array backing escape. Durable outputs remain owned CVInput values. Mutating a returned input or source digest cannot alter another owned input or transcript.

`peer_key()` and `transcript()` return `None` before authentication or after any terminal failure. Successful returns own independent inline bytes. They do not borrow Certificate frames, scratch, anchors, or State. The returned transcript is the through-server-Finished checkpoint for later application/exporter derivation and client Finished processing. No resumption or client-Finished state is implemented here.

## Retry and terminal errors

Malformed frame metadata returns `Bounds` before every state check, without changing State, scratch, or budget. In Certificate, malformed scratch metadata also returns `Bounds` before work or parsing. Scratch metadata is ignored outside Certificate. Metadata validity means nonnegative start/length and a representable `i32` end; backing remains a caller precondition.

An undersized Certificate scratch view returns retryable `ScratchTooSmall`. Hash, leaf, phase, and scratch remain unchanged. It is detected after bounded TLS list parsing, so that feed's shared work debit is **not refunded**. A retry with sufficient scratch charges the frame again and appends it once on success.

Every wire/schema, order, size/work/signature budget, path, CV, Finished, or transcript failure is terminal. The first error is latched and `phase()` becomes Failed. Later valid feeds return that same error without further progress or budget use. A later malformed frame still returns transient Bounds first, while the latched failure is preserved. There is no reset or resume method after terminal failure. Unexpected optional CertificateRequest, missing/skipped stages, replay, or any feed after Authenticated is terminal `UnexpectedMessage`.

The error categories are `Bounds`, constructor limits/hash/transcript/anchor/offer errors (including `HashMismatch`), `FrameLimit`, `WorkLimit`, `SignatureLimit`, `ScratchTooSmall`, `UnexpectedMessage`, `Handshake(codec_error)`, Certificate context/list/count/extension errors, `Path(path_error)`, `CertificateVerify`, `Finished`, and `Transcript`. Path diagnostics retain the validator's kind and certificate/anchor/offset coordinates. A caller maps failures to connection abort/alerts under its own bounded transport policy.

A failure can withhold future getters but cannot revoke a key/transcript copy returned earlier. The owner of a full connection must treat later fatal protocol errors as terminal and stop using that connection. Public implementation fields are not a supported way to manufacture an authentication decision.

## Shared work and signature limits

Create `x509_path::Budget` with its checked factory and pass the same live budget throughout the flight. Do not reset/replenish it between Certificate and CV. Path certificate signatures and CV consume the **same** `signatures_left`; CV debits one before expensive verification, including a failed proof. Shared parsing/work use the validator's existing counters as well.

Before any eager TLS parser scans a frame, feed checks both `Config.max_frame` and `Budget.limits.max_input`. Let `n` be complete-frame bytes and `b = ceil(n/128)`. The exact bridge precharges from `work_left` are:

| Selected hash / expected phase | Feed debit |
| --- | --- |
| SHA-256, every phase | `4096 + 256*n` |
| SHA-384, EE or Certificate | `4096 + 256*n + 8192 + 16384*b` |
| SHA-384, CertificateVerify | `4096 + 256*n + 8192 + 32768 + 16384*(b+2)` |
| SHA-384, Finished | `4096 + 256*n + 8192 + 131072 + 16384*(b+10)` |

The original SHA-256 tariff covers frame/hash copying and both eager Certificate-list passes, including possible 1024-word duplicate-extension bitmap clears. SHA-384 adds the update-block bound for any prior residue plus fixed copy/setup allowances. CV reserves two snapshot compressions and 32,768 copy units for the owned 146-byte input. Finished reserves two snapshot, four ExpandLabel, and four HMAC compressions, plus 131,072 copy units. These conservative allowances use 16,384 per SHA-384 compression, 4,096 per setup/state node, and 32 per traversed logical byte as the source-accounting basis; they do not reinterpret the legacy SHA-256 tariff as an instruction count. See the [schedule cost composition](extended-tls-schedule.md#sha-384-cost-composition-for-budget-owners).

Path parsing/policy work is additional. A rejected work debit leaves the remaining counter unchanged and makes State terminal. The expected phase determines its reserve even when the incoming kind will later be rejected. Already admitted parser/retry work is not refunded. These are abstract resource limits, with no generated-instruction, physical-layout, elapsed-time or throughput guarantee.

The path defaults include a 1 MiB input ceiling and 16 MiB shared work. Those limits are independent: even the legacy tariff admits **less than roughly 64 KiB of total frame bytes**, with additional path and selected SHA-384 costs. Raising `max_frame` alone does not admit a larger flight. The historical accepted SHA-256 test used a real eight-certificate flight of roughly 80 KiB: default work rejected before Certificate parsing, while an explicitly raised shared allowance admitted it. The accepted both-hash peer also checked that distinction for the new branch. Applications must choose coherent frame, parser, path, work, signature, and storage limits.

## Backing and state copies

All input descriptors require actual physical backing. Anchors and their descriptor list must stay immutable and live until Certificate processing completes for every State copy that may use them. Each frame must stay immutable through its feed; accepted frame bytes are hashed/copied, so State retains no frame borrow afterward. The expected reference is copied; it is not learned from the presented certificate, SNI, DNS, or connected address.

Frame, scratch, anchors, State, and Budget must be mutually disjoint where any is writable. Scratch can be partially overwritten on a path error and can contain borrowed parsed records afterward. Do not inspect those records after their DER backing is reused/released. State returns only a copied key on complete validation and keeps no scratch reference. Reuse one workspace for serial calls after ending prior uses; do not share it concurrently.

State value copies fork their inline transcript, pending key, secret, phase, and error. They share only immutable anchor backing. They can progress independently with appropriate caller workspace, but shared Budget charges remain cumulative. Copies do not clone owners or acquire cleanup authority. There is no secure-erasure or constant-time compiler claim.

## Accepted selected-hash verification

The [driver](../tests/extended_tls_authentication_execution.rs) keeps three exact groups: `server_flight_authentication_matches_real_chain_signature_and_finished_peer`, `server_authentication_retries_budgets_and_terminal_failures_withhold_peer`, and `ordinary_server_authentication_consumer_executes_without_error_projection`. All three passed separately on the frozen selected-hash source and fixtures, without a failed gate or an authentication-specific compiler change.

The independent peer emits both SHA-256 and SHA-384 cases for positive and negative protocol groups, selecting hashlib/HMAC and Finished lengths from the explicit algorithm. It retains real certificate-path/identity/time checks and independent Ed25519 CV verification; suite hash does not change the certificate signature algorithm. Final publication compares all active digest bytes and canonical 48-byte observation storage, including zero tails.

The ordinary consumer passed four flows: both algorithms in both packed/native-strided layouts. It checks both owned RFC contexts against complete independent 146-byte backing, including inactive zero tails; mutates a CVInput copy and source digest; and verifies that another owned input and transcript snapshot remain unchanged. The positive/negative fixtures retain source-frame clearing and guard checks.

New first-frame work cases provide the exact expected bridge allowance minus one, exactly that allowance, and plus one for each algorithm/layout. These seams avoid depending on X.509 parser costs. They check rejection without a debit when insufficient, exact spending on admission, later metadata precedence and terminal behavior. The driver continues to distinguish exact bridge debits from nonnegative additional path charges. The accepted gates exercised these assertions under the exact tariffs above.

The exact accepted evidence is:

| Gate | Accepted cases/observations | Elapsed | Ignored local log |
| --- | --- | ---: | --- |
| `ordinary_server_authentication_consumer_executes_without_error_projection` | Four flows: both algorithms/layouts and both owned CV contexts | 10.29 s | `target/stdlib-work/tls-sha384-auth-ordinary-first.log` |
| `server_flight_authentication_matches_real_chain_signature_and_finished_peer` | 20 layout cases / 108 observations | 17.31 s | `target/stdlib-work/tls-sha384-auth-positive-first.log` |
| `server_authentication_retries_budgets_and_terminal_failures_withhold_peer` | 212 layout cases / 608 observations | 21.90 s | `target/stdlib-work/tls-sha384-auth-negative-first.log` |

The protocol total is **232 layout cases / 716 observations**, in addition to
four ordinary flows. These were **three separate exact invocations, three
independently compiled strict ELFs and three native processes**, rather than
one whole-target run. All native mmap/munmap/mremap/brk traces were empty.
The shared Rust resume build, also including the schedule driver, took
**1.24 s**; this is not an isolated authentication compilation measurement.
Its ignored local log is
`target/stdlib-work/tls-sha384-schedule-auth-build-first.log`; the
[bounded joint rebuild command](extended-tls-schedule.md#accepted-selected-hash-verification)
is recorded with the schedule receipts.

Current frozen source SHA-256 hashes, checked after execution, are:

| Source | SHA-256 |
| --- | --- |
| `extended/ext/tls_authentication.lani` | `6db96e4c7c3caf89e83f2a37c4b573ebada7fce23a4f920a63f4ab874b5573ed` |
| `tests/extended_tls_authentication_execution.rs` | `2a83ca5be78948c34d976a2dac07f449f9dca1cd5d9d638498d8584fb5ef3b8f` |
| `tests/fixtures/extended/tls_authentication/plain.lani` | `e0391188072b9b8f70e2c2baa6170502c13b98e1675df9cc0d1a1145e9a99f54` |
| `tests/fixtures/extended/tls_authentication/protocol.lani` | `f5fbbd51821514c90e39f7b535273769c1fd1780870619a4e9ebf10521a82541` |
| `tests/fixtures/extended/tls_authentication/peer.py` | `c9e8e95c1020dadbabc8984e37e39a084492a8520e25398e86628eb0da621a36` |

The source base was `e32b2fbfb77fa25ec0e5b0a83905d5c9c34faff3` with the
frozen integration additions. Each runtime selection used this exact wrapper
with its name and log from the table; the example selects the ordinary flow.
Repeat separately for positive and negative selections:

```sh
test_name=ordinary_server_authentication_consumer_executes_without_error_projection
RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
  LANIUS_DEBUG_STAGE_ERRORS=1 timeout --kill-after=2s 100s \
  flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s \
  target/stdlib-build/debug/deps/extended_tls_authentication_execution-4d6cb46e73acfb4f \
  --exact "$test_name" --nocapture --test-threads=1 \
  > target/stdlib-work/tls-sha384-auth-ordinary-first.log 2>&1
```

These results admit the exercised authentication boundary on native x86_64
Linux. They do not establish connected TLS interoperability, other targets,
user GPU execution, constant-time generated code or throughput. Authenticated
still does not mean Established.

## Historical SHA-256-only verification

The following receipts predate the typed-secret/SHA-384/CVInput migration. They establish the earlier SHA-256-only source; the current implementation has the separate accepted receipts above.

All three focused gates passed on **Linux x86-64** with GPU-compiled native output. The driver is [extended_tls_authentication_execution.rs](../tests/extended_tls_authentication_execution.rs), with [protocol, ordinary consumer, and independent peer](../tests/fixtures/extended/tls_authentication/).

| Gate | Accepted evidence | Elapsed |
| --- | --- | --- |
| `server_flight_authentication_matches_real_chain_signature_and_finished_peer` | 10 layout cases / 54 observations: real paths, independent CV/Finished/key/hash, HRR checkpoint, source/State copy independence, eight-certificate large-flight work limits | 13.87 s |
| `server_authentication_retries_budgets_and_terminal_failures_withhold_peer` | 100 layout cases / 286 observations: constructor and metadata boundaries, scratch retry/nonrefunded work, order/replay/poison, path/identity/time/CV/Finished failures, shared signatures, getters withheld | 17.43 s |
| `ordinary_server_authentication_consumer_executes_without_error_projection` | Ordinary imports and complete real-chain flow without Error projections, both layouts | 10.07 s |

The Python peer creates actual v3 certificates with fixed public test seeds and explicit OpenSSL config. It independently checks exact certificate TBS signatures with libsodium and validates path/hostname/time with OpenSSL using an explicit anchor and `-attime`. It constructs real CH/SH bytes, derives the supplied server traffic secret from X25519/HKDF, and computes CV and Finished independently. The bridge verifies every stage in native Lanius. No OpenSSL/libsodium code is imported by production.

Both packed and native-strided inputs have nonzero starts. Every observation checks phase, sticky failure, authentication/getter availability, signature allowance, and final independent key/transcript bytes. Before authentication, key/hash publication fields must be all zero. The peer does not mirror X.509 parser work accounting: the driver checks exact bridge tariff where applicable, unchanged counters for metadata/replay/observation, and an additional nonnegative path debit. Whole source frame and anchor bytes are compared, with byte/Slot guards. After serializing each frame and checking its guards, the protocol fixture clears the entire just-used frame region. The next shorter CV/Finished frame therefore cannot leave prior Certificate/SPKI backing available to hide an input alias. Anchor backing remains separate and immutable. Getter copies are mutated/advanced to check State remains independent.

The accepted gates used **three independent exact invocations**, compiling **three strict ELFs** and running **three native processes**. The two protocol runs cover **110 layout cases / 340 observations**, in addition to the ordinary consumer. All three native `mmap`/`munmap`/`mremap`/`brk` traces were empty. `OnceLock` can share the protocol ELF if both model tests run in one invocation; it did not share compilation across these accepted separate runs.

Independent review found no remaining source/oracle issue. Before positive/negative admission, it strengthened the protocol's source-lifetime witness by adding the clear described above. This was a test improvement, not a failed gate or production fix. Those two gates used protocol SHA-256 `4f20bc0914b75b511a76322516988f50e0921c0fddca8207f8717cffdd60fc09`; production remained `2ce953ea32eefa264204c66971b7df8f3945c348ef3b2aba3d40b24cb3ee337e`. The earlier accepted ordinary consumer was unchanged and required no rerun. No authentication gate failed.

The driver build completed in **1.75 s**, recorded in `target/stdlib-work/tls-peer-auth-admission/build-tls-authentication.log`. The accepted executable was `target/stdlib-build/debug/deps/extended_tls_authentication_execution-4d6cb46e73acfb4f`. Runtime logs in that admission directory are `tls-authentication-ordinary.log`, `tls-authentication-positive.log`, and `tls-authentication-negative.log`. These ignored local artifacts are evidence paths, not checked-in captures.

To rebuild only this driver:

```sh
timeout --kill-after=2s 100s flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  cargo test --test extended_tls_authentication_execution --no-run
```

Each accepted runtime command used the following wrapper separately with one exact gate from the table. The example selects the ordinary consumer; use the fresh build's executable path if its basename differs.

```sh
test_name=ordinary_server_authentication_consumer_executes_without_error_projection
timeout --kill-after=2s 100s flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s env \
  RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
  LANIUS_DEBUG_STAGE_ERRORS=1 \
  target/stdlib-build/debug/deps/extended_tls_authentication_execution-4d6cb46e73acfb4f \
  --exact "$test_name" --nocapture --test-threads=1
```

Each command has a 100-second outer guard, 35-second lock wait, and 60-second inner guard. GPU codegen has a 45-second guard, peer setup 40 seconds, and native execution 30 seconds. This is test-only diagnostic publication of keys/hashes, not a deployable secret-handling or connected TLS application.

These results establish the exercised authentication boundary on Linux x86-64. Record authentication, extension negotiation, certificate-signature offer enforcement, client Finished transport commitment, application release, alerts, entropy, deadlines, sockets, post-handshake messages, and full TLS interoperability remain outside this bridge. Authenticated still does not mean Established. No throughput or other-target result is claimed.
