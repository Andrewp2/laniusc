# Portable TLS server-flight authentication

`ext::tls_authentication` verifies a TLS 1.3 server authentication flight in strict order: EncryptedExtensions, Certificate, CertificateVerify, Finished. Certificate processing calls the actual [bounded X.509 path validator](extended-x509-path.md) with explicit anchors, expected service identity, and time. CV proves possession of that validated leaf key; Finished binds it to the supplied handshake secret and transcript. The implementation is [tls_authentication.lani](../extended/ext/tls_authentication.lani).

The authentication checkpoints and signature context follow [RFC 8446 sections 4.4.1–4.4.4](https://www.rfc-editor.org/rfc/rfc8446.html#section-4.4). This module implements selected SHA-256/SHA-384 transcripts with the strict Ed25519, ECDSA/P-256/SHA-256 and RSA-PSS/RSAE/SHA-256 proof profiles from the [shared signature module](extended-signature.md). Certificate-edge algorithms are separately restricted by an explicit policy, including supported RSA PKCS#1/SHA-256 when permitted. It has no allocation, IO, foreign TLS backend, or caller-supplied trust flag/key shortcut.

**All six multi-signature API gates passed on 2026-10-25 for GPU-compiled native x86_64 Linux output:** 436 protocol layout cases / 1,436 feed observations and 12 ordinary flows. Four accepted strict ELFs ran in six native processes; allocation traces were empty. The prior selected-hash Ed25519 version has separate historical receipts below. User GPU execution, other targets and throughput remain unverified.

**Authenticated means server Certificate, CV, and server Finished have been verified. It does not mean the connection is Established.** A full client engine must still commit its own Finished to the transport before releasing application data, as specified by the [connection contract](tls-connection-contract.md). This component exposes a validated peer key and transcript, and has no application-data API.

## Inputs and construction

Here `View`, `Result`, and `Option` abbreviate the corresponding `core::slice`, `core::result`, and `core::option` types.

```lanius
pub struct Config {
    anchors: View<View<u8>>,
    reference: ext::service_identity::Reference,
    unix_time: i64,
    max_frame: i32,
    proofs: ext::signature::Policy,
    certificates: ext::signature::Policy
}
pub fn server(
    transcript: ext::tls_transcript::State,
    server_handshake_secret: ext::tls_schedule::Secret,
    config: Config
) -> Result<State, Error>;

pub enum Phase {
    EncryptedExtensions, Certificate, CertificateVerify, Finished,
    Authenticated, Failed
}
```

The caller supplies a transcript through **already checked CH/SH negotiation**, and the corresponding owned, tagged server handshake traffic secret. Its algorithm must match `transcript.algorithm()`: SHA-256 uses 32 active bytes and SHA-384 uses 48. Construction copies both values, plus the reference identity, time and both policies. It retains only the immutable anchor descriptors/backing. Changing the original secret, reference object, policy, or transcript afterward does not change this State.

Import raw secret bytes with `tls_schedule::secret_from_view(algorithm, bytes)` before calling this constructor. Raw metadata and exact 32/48-byte length validation belong to that factory. Authentication no longer has an `InvalidSecretLength` constructor branch; a mismatched typed secret returns `HashMismatch`.

The transcript shape must be two messages without HRR, or four messages with HRR rewrite applied. This catches an incorrect checkpoint shape; it does not establish transcript provenance or negotiate CH/SH. The caller must have checked versions, cipher/hash/group, shares, session echo, HRR restrictions, extensions, and the selected X.509 profile. Use the checked transcript and service-identity constructors rather than fabricated state/fields.

Each `signature::Policy` owns an active ordered list of one through four TLS IDs with no duplicates. Both are validated at construction for their purpose. `proofs` accepts `0807`, `0403`, `0804`; certificate-only `0401` is forbidden there. `certificates` also accepts `0401`. Unknown IDs, invalid active lengths and duplicates return `SignatureScheme`. The default constructors are `signature::default_proofs()` and `signature::default_certificates()`, but the caller supplies the policies actually emitted in CH: use the effective extension-50 policy or extension-13 fallback for certificates. Authentication neither invents offers nor infers proof permission from a certificate grant. No legacy offer-view/default-wrapper constructor remains.

Anchors must contain 1 through 8 logically valid DER views. `max_frame` is a complete handshake-frame limit, including its four-byte header, from 4 through 16777219. Construction checks anchor-list metadata, bounds the anchor count before nested indexing, and checks every permitted anchor descriptor's metadata. Only then does it check transcript/secret hash agreement, followed by the frame limit, both purpose-specific policies, and transcript shape. `HashMismatch` precedes State construction or work/cryptographic progress; malformed supplied metadata takes precedence. No constructor parses an anchor or accepts a peer key. Explicit anchor/path/reference/time validation occurs during Certificate.

## Feeding complete frames

```lanius
State.feed(frame: View<u8>, certificate_scratch: View<ext::x509_path::Slot>,
           budget: &ext::x509_path::Budget) -> Result<Phase, Error>;
State.phase() -> Phase;
State.is_poisoned() -> bool;
State.authenticated() -> bool;
State.failure() -> Option<Error>;
State.peer_key() -> Option<ext::signature::PublicKey>;
State.transcript() -> Option<ext::tls_transcript::State>;
State.borrow() -> &State;
```

Each feed requires exactly one complete handshake frame. It accepts no fragments, coalesced suffix, record header, alert, or application bytes. Reassembly and authenticated record content belong to the [framing](extended-tls-framing.md) and [record](extended-tls-record.md) layers. EE extension meaning, placement, offered-versus-selected values, ALPN/SNI, and other negotiation checks remain the caller's responsibility before feeding EE. The codec checks its framing and duplicate extensions here.

| Expected frame | Checks before transcript advance |
| --- | --- |
| EncryptedExtensions | Exact expected kind and complete EE schema; caller has checked extension meaning |
| Certificate | Empty server request context, nonempty list, at most eight entries, no CertificateEntry extensions, then actual path/identity/time validation |
| CertificateVerify | Actual scheme is allowed by the retained proof policy, compatible with the validated leaf key, strictly encoded, and accepted by the shared verifier under the remaining allowance |
| Finished | Exactly 32 SHA-256 or 48 SHA-384 verify bytes and correct selected-hash MAC using the copied server handshake secret and current transcript hash |

Certificate entries are DER X.509 certificates. Raw public keys and every nonempty CertificateEntry extension are explicitly unsupported. This includes OCSP and SCT extensions; the bridge does not silently ignore their meaning or claim revocation/CT verification. A server Certificate context must be empty and its list nonempty. Path order, supported certificate algorithms, constraints, anchor handling, DNS/IP identity, and inclusive explicit UTC time checks follow the validator's documented bounded offline profile. The bridge inherits that profile's limitations; it does not add general path building or revocation policy.

The bridge collects at most eight small DER-view descriptors locally. Parsed certificate records use caller-provided Slot workspace; no inline array of parsed certificates is created inside State. On Certificate, scratch must have at least `presented_entry_count + configured_anchor_count` slots. No scratch is required for EE, CV, or Finished: the argument is ignored in those phases. Scratch is never retained by State.

The CV signed input uses the selected transcript through Certificate: 130 bytes for SHA-256 or 146 for SHA-384. The proof hash is independent of that transcript hash: Ed25519 processes the complete input directly; `0403` and `0804` hash that complete 130/146-byte input once with SHA-256. They never receive only the transcript digest or a prehashed substitute. ECDSA requires strict DER `(r,s)`; RSA-PSS requires SHA-256, MGF1-SHA-256 and salt32. PKCS#1 is certificate-only and cannot be enabled for CV by any policy. CV is appended only after successful verification. Finished is checked against the selected transcript through CV and appended only after successful verification. The leaf key is committed internally only after complete path success and Certificate transcript append; it remains unavailable through both getters until Finished succeeds.

## Owned CertificateVerify input

```text
CVInput { bytes: [u8;146], length: i32 }
certificate_verify_input(side: ext::tls_schedule::Side,
                         hash: ext::tls_hash::Digest) -> CVInput
CVInput.view(&self) -> View<u8>
```

The shared helper builds either RFC context: 64 spaces, `TLS 1.3, server CertificateVerify` or `TLS 1.3, client CertificateVerify` (33 bytes each), an explicit zero separator at offset 97, then the active transcript digest at offset 98. Its active length is `98 + HashLen`. It initializes all 146 owned bytes; the 16 inactive SHA-256 bytes are zero. The server verifier uses the server context. Callers of the client helper must still enforce their own permitted authentication flow.

The result copies the digest and retains no transcript/digest borrow. Bind it to a stable owned local before calling `.view()`. That borrowed `&self` view is valid only while the same CVInput remains live and unchanged at the same location; a copied receiver or chained temporary must not let inline-array backing escape. Durable outputs remain owned CVInput values. Mutating a returned input or source digest cannot alter another owned input or transcript.

`peer_key()` and `transcript()` return `None` before authentication or after any terminal failure. Successful returns own independent inline bytes and cached public state. Use `.kind()` for family inspection and `.ed25519_key()` only for a copied Ed25519 projection; there is no general raw-key escape or trust-token constructor. They do not borrow Certificate frames, scratch, anchors, or State. The returned transcript is the through-server-Finished checkpoint for later application/exporter derivation and client Finished processing. No resumption or client-Finished state is implemented here.

## Retry and terminal errors

Malformed frame metadata returns `Bounds` before every state check, without changing State, scratch, or budget. In Certificate, malformed scratch metadata also returns `Bounds` before work or parsing. Scratch metadata is ignored outside Certificate. Metadata validity means nonnegative start/length and a representable `i32` end; backing remains a caller precondition.

An undersized Certificate scratch view returns retryable `ScratchTooSmall`. Hash, leaf, phase, and scratch remain unchanged. It is detected after bounded TLS list parsing, so that feed's shared work debit is **not refunded**. A retry with sufficient scratch charges the frame again and appends it once on success.

Every wire/schema, order, size/work/signature budget, path, CV, Finished, or transcript failure is terminal. The first error is latched and `phase()` becomes Failed. Later valid feeds return that same error without further progress or budget use. A later malformed frame still returns transient Bounds first, while the latched failure is preserved. There is no reset or resume method after terminal failure. Unexpected optional CertificateRequest, missing/skipped stages, replay, or any feed after Authenticated is terminal `UnexpectedMessage`.

The error categories are `Bounds`, constructor limits/hash/transcript/anchor/offer errors (including `HashMismatch`), `FrameLimit`, `WorkLimit`, `SignatureLimit`, `ScratchTooSmall`, `UnexpectedMessage`, `Handshake(codec_error)`, Certificate context/list/count/extension errors, `Path(path_error)`, `CertificateVerify`, `Finished`, and `Transcript`. Path diagnostics retain the validator's kind and certificate/anchor/offset coordinates. A caller maps failures to connection abort/alerts under its own bounded transport policy.

A failure can withhold future getters but cannot revoke a key/transcript copy returned earlier. The owner of a full connection must treat later fatal protocol errors as terminal and stop using that connection. Public implementation fields are not a supported way to manufacture an authentication decision.

## Shared work and signature limits

Create `x509_path::Budget` with its checked factory and pass the same live budget throughout the flight. Do not reset/replenish it between Certificate and CV. Path certificate signatures and CV consume `budget.verification.signatures_left` and `budget.verification.work_left`. CV does not create a default allowance. A positive crypto reservation consumes one signature attempt even on `false`; an unaffordable reservation consumes none. ECDSA DER parsing is charged before signature-quota admission, so malformed DER can consume parsing work without an attempt. RSA transfers and commits the same remaining work on every delegated return. X.509 structural parsing keeps its separate `budget.parsing` allowance; it does not replenish verification work.

Before any eager TLS parser scans a frame, feed checks both `Config.max_frame` and `Budget.limits.max_input`. Let `n` be complete-frame bytes and `b = ceil(n/128)`. Let `K = OWNED_KEY_WORK = 1048576`. The exact bridge precharges from `budget.verification.work_left` are:

| Selected hash / expected phase | Feed debit |
| --- | --- |
| SHA-256, every phase | `K + 4096 + 256*n` |
| SHA-384, EE or Certificate | `K + 4096 + 256*n + 8192 + 16384*b` |
| SHA-384, CertificateVerify | `K + 4096 + 256*n + 8192 + 32768 + 16384*(b+2)` |
| SHA-384, Finished | `K + 4096 + 256*n + 8192 + 131072 + 16384*(b+10)` |

`K` covers up to eight named key/result/Option handoffs, using a 4 KiB logical key envelope at 32 abstract credits per byte. It bounds the source-level handoffs when retaining and projecting the larger owned RSA context; it is not a claim about compiler-introduced copies, physical structure size, machine instructions or timing. Constructor and getter value copies are bounded, unmetered caller operations outside `feed`'s budget. The remaining SHA-256 tariff covers frame/hash copying and both eager Certificate-list passes, including possible 1024-word duplicate-extension bitmap clears. SHA-384 adds the update-block bound for any prior residue plus fixed copy/setup allowances. CV reserves two snapshot compressions and 32,768 copy units for the owned 146-byte input. Finished reserves two snapshot, four ExpandLabel, and four HMAC compressions, plus 131,072 copy units. These conservative allowances use 16,384 per SHA-384 compression, 4,096 per setup/state node, and 32 per traversed logical byte as the source-accounting basis; they do not reinterpret the legacy SHA-256 tariff as an instruction count. See the [schedule cost composition](extended-tls-schedule.md#sha-384-cost-composition-for-budget-owners).

Shared signature classification/import/verification and path parsing/policy/cache-storage work are additional. See the [signature tariffs](extended-signature.md) and [path accounting](extended-x509-path.md): P-256 and Ed25519 use fixed bounded-loop/helper credits plus hashing, while RSA retains its digit/body charges. These units do not turn differing primitive tariffs into a common per-instruction bound. A proof shape/key/use error maps to `SignatureScheme`; cryptographic `false` maps to `CertificateVerify`; shared work/signature exhaustion maps to terminal `WorkLimit`/`SignatureLimit`, and signature message-cap exhaustion maps to `FrameLimit`. Earlier admitted frame, DER and import costs remain charged. A rejected work debit leaves the remaining counter unchanged and makes State terminal. The expected phase determines its reserve even when the incoming kind will later be rejected. Already admitted parser/retry work is not refunded. These are abstract resource limits, with no generated-instruction, physical-layout, elapsed-time or throughput guarantee.

The current path defaults include a 1 MiB input ceiling and 1 Gi-unit shared verification allowance. Input, parser, frame, crypto, signature and storage limits remain independent. The retained roughly 80 KiB/eight-certificate regression explicitly compares a 16 Mi-unit low allowance with the new 1 Gi-unit allowance; it no longer labels the historical low setting as today's default. Raising `max_frame` alone cannot admit an otherwise unaffordable flight.

## Backing and state copies

All input descriptors require actual physical backing. Anchors and their descriptor list must stay immutable and live until Certificate processing completes for every State copy that may use them. Each frame must stay immutable through its feed; accepted frame bytes are hashed/copied, so State retains no frame borrow afterward. The expected reference is copied; it is not learned from the presented certificate, SNI, DNS, or connected address.

Frame, scratch, anchors, State, and Budget must be mutually disjoint where any is writable. Scratch can be partially overwritten on a path error and can contain borrowed parsed records afterward. Do not inspect those records after their DER backing is reused/released. State returns only a copied key on complete validation and keeps no scratch reference. Reuse one workspace for serial calls after ending prior uses; do not share it concurrently.

State value copies fork their inline transcript, pending key, secret, phase, and error. They share only immutable anchor backing. They can progress independently with appropriate caller workspace, but shared Budget charges remain cumulative. Copies do not clone owners or acquire cleanup authority. There is no secure-erasure or constant-time compiler claim.

## Accepted multi-signature verification

The existing three exact groups remain, with explicit one-entry Ed25519 proof/certificate policies and generic-key projection. Their complete key/hash bytes, framing, source guards, HRR, retries, copies, path/identity/time failures and getter-withholding checks remain. The oracle now includes the fixed owned-key handoff reserve and actual shared Ed25519 verifier tariff; constructor cases use policy errors in place of removed offer-view metadata. The migrated four-flow ordinary consumer passed in 13.96 s. Its two protocol groups passed in a separate 33.06 s invocation: 20 positive layout cases / 108 observations and 212 negative cases / 608 observations. Those 716 observations use the original three-group coverage with updated policy/cost contracts.

Three added exact groups are:

- `rsa_pss_and_ecdsa_certificate_verify_publish_owned_keys_for_both_transcript_hashes`
- `proof_policies_signature_hashes_and_shared_allowance_fail_closed`
- `ordinary_rsa_and_ecdsa_authentication_consumer_uses_owned_peer_key`

The [new independent peer](../tests/fixtures/extended/tls_authentication/signature_peer.py) creates RSA and P-256 leaf certificates under a real OpenSSL-validated Ed25519 CA/intermediate chain. It signs CertificateVerify over the independently assembled complete 130/146-byte input and uses OpenSSL EVP DigestVerify for the expected cryptographic decision. Test-only Python affine/integer helpers author signatures; production remains Lanius. It also calculates Finished with hashlib/HMAC over the actual preceding wire frames. The new CH contains the exact active proof-policy list in extension 13 and explicit certificate-policy list in extension 50, and traffic secrets are rederived from those actual CH/SH bytes. The ordinary consumer uses the same explicit Ed25519 certificate policy. A pre-admission static check caught and corrected an initial reuse of the old Ed-only CH; no generic native gate used that mismatched capture. A separate CPU byte walk checked the framing and both exact offer lists in all 212 protocol/ordinary captures.

The accepted added corpus contains **eight positive layout cases / 32 feed observations**, **196 negative layout cases / 688 feed observations** (24 constructor rejections), and an eight-flow ordinary consumer, covering both transcript hashes and both physical byte layouts. Negative cases cover wrong offers, certificate grants without proof grants, invalid/duplicate/PKCS#1 proof policies, forbidden PKCS#1 CV, wrong key, client context, transcript hash, digest-only/double-hash inputs, signature encoding/mutations, bad Finished, exact proof/Finished work seams and depleted attempts. Finite budgets only tighten the shared allowance after actual path validation; they never reset it upward. The driver checks exact CV/frame debits and monotonic additional path charges.

The generic consumer overwrites each Certificate frame before CV, then checks the published key's family and uses it on a separate independently signed retirement-witness message. It clears all parsed scratch, reassigns a returned full key value and verifies both saved-key and copied-State keys. These post-authentication witnesses have a distinct test allowance; actual CV always uses the original path allowance. No synthetic trusted key bypass is used. Before or after any failed checkpoint, getters remain unavailable. Each native driver requires an empty mmap/munmap/mremap/brk trace. The accepted current receipts are:

| Invocation | Accepted gates and counts | Elapsed | Ignored local log |
| --- | --- | ---: | --- |
| Retained ordinary consumer | `ordinary_server_authentication_consumer_executes_without_error_projection`: four Ed25519 flows, both hashes/layouts and both CV contexts | 13.96 s | `target/stdlib-work/tls-signature-auth-ordinary-syntax-fixed.log` |
| Retained protocol groups | `server_authentication_retries_budgets_and_terminal_failures_withhold_peer`: 212 cases / 608 observations; `server_flight_authentication_matches_real_chain_signature_and_finished_peer`: 20 / 108 | 33.06 s together | `target/stdlib-work/tls-signature-auth-regression-first.log` |
| First generic invocation | `ordinary_rsa_and_ecdsa_authentication_consumer_uses_owned_peer_key`: eight flows passed; both protocol attempts stopped before ELF generation | 20.09 s entire mixed invocation, not an ordinary-only timing | `target/stdlib-work/tls-signature-auth-generic-first.log` |
| Corrected generic protocol groups | `proof_policies_signature_hashes_and_shared_allowance_fail_closed`: 196 cases / 688 observations; `rsa_pss_and_ecdsa_certificate_verify_publish_owned_keys_for_both_transcript_hashes`: 8 / 32 | 43.57 s together | `target/stdlib-work/tls-signature-auth-generic-exhaustive-fixed.log` |

The six accepted API gates total **436 protocol cases / 1,436 observations plus 12 ordinary flows**. They produced **four accepted strict ELFs and six native processes**: old plain once, old shared protocol once/two processes, new plain once, and new shared protocol once/two processes. All mmap/munmap/mremap/brk traces were empty. The two failed generic compilation attempts produced no ELF or native process. These were four separately selected invocations, not a successful whole-target invocation. The fresh API-driver build took **1.19 s**, logged in `target/stdlib-work/tls-signature-auth-build.log`.

All accepted API invocations used the `e5ad90c646b69d6158f5ee17dae745db4a2b959230cab0510d88232944479b95` driver, binary `extended_tls_authentication_execution-4d6cb46e73acfb4f`. The current driver differs only by the separately selected positive diagnostics described below; no authentication API gate body changed. Current accepted source/fixture pins are:

| File | SHA-256 |
| --- | --- |
| `extended/ext/tls_authentication.lani` | `06a5e07867269ce42fa28efb150ec5e70fc9c819618dcf437429da9607609530` |
| `extended/ext/x509_path.lani` | `ae5d9c3347437424982a721e6fed868f34fde2c2911a8ddc654aaa3feb420037` |
| Retained `plain.lani` | `92976368cfb9b2b333a5f541fee108177a7c590101790751f7126bc9cc002874` |
| Retained `protocol.lani` | `566c1f61e1f586f34ec9791609d2ea556f4738d50ae84e2b04bdf04bfd0e9e4a` |
| Retained `peer.py` | `1b7c1c31d516027f9cc25a989d87e705c6b3ae7801ee22908f0cf410ab35ffd9` |
| `signature_plain.lani` | `653db88cc0586dcd67007c974d8091f832b4775c8736cf42db16fce0d18b301b` |
| Corrected `signature_protocol.lani` | `e96501c8bae04f4abb4688299e676113b292d5b39a91a5cf0b615ca519f5bef7` |
| `signature_peer.py` | `5ced26a208849abcfa8ed1343a24ab7a3403deef3d09534f054e5bfd10167ccb` |

### Exact current API gate commands

The fresh API-driver build used the standard separate target directory:

```sh
CARGO_TARGET_DIR=/home/andrew-peterson/code/laniusc/target/stdlib-build \
  CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  timeout --kill-after=2s 100s \
  flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s \
  cargo test --test extended_tls_authentication_execution --no-run \
  > target/stdlib-work/tls-signature-auth-build.log 2>&1
```

The following are the actual runtime selections on the six-API-test binary. The selector-only diagnostic was added afterward. When rerunning an API-only selection on a fresh current binary, also skip `authentication_error_match_positive_control`; the recorded corrected-generic command already does so. Each invocation has its own outer 100-second limit; the ordinary inner limit is 60 seconds and each multi-test inner limit is 90 seconds.

```sh
auth_bin=target/stdlib-build/debug/deps/extended_tls_authentication_execution-4d6cb46e73acfb4f
auth_old_plain=ordinary_server_authentication_consumer_executes_without_error_projection
auth_old_positive=server_flight_authentication_matches_real_chain_signature_and_finished_peer
auth_old_negative=server_authentication_retries_budgets_and_terminal_failures_withhold_peer
auth_new_plain=ordinary_rsa_and_ecdsa_authentication_consumer_uses_owned_peer_key
auth_new_positive=rsa_pss_and_ecdsa_certificate_verify_publish_owned_keys_for_both_transcript_hashes
auth_new_negative=proof_policies_signature_hashes_and_shared_allowance_fail_closed

RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
  LANIUS_DEBUG_STAGE_ERRORS=1 timeout --kill-after=2s 100s \
  flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s "$auth_bin" \
  --exact "$auth_old_plain" --nocapture --test-threads=1 \
  > target/stdlib-work/tls-signature-auth-ordinary-syntax-fixed.log 2>&1

RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
  LANIUS_DEBUG_STAGE_ERRORS=1 timeout --kill-after=2s 100s \
  flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 90s "$auth_bin" \
  --skip "$auth_old_plain" --skip "$auth_new_positive" \
  --skip "$auth_new_negative" --skip "$auth_new_plain" \
  --nocapture --test-threads=1 \
  > target/stdlib-work/tls-signature-auth-regression-first.log 2>&1

RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
  LANIUS_DEBUG_STAGE_ERRORS=1 timeout --kill-after=2s 100s \
  flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 90s "$auth_bin" \
  --skip "$auth_old_plain" --skip "$auth_old_positive" \
  --skip "$auth_old_negative" --nocapture --test-threads=1 \
  > target/stdlib-work/tls-signature-auth-generic-first.log 2>&1

RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
  LANIUS_DEBUG_STAGE_ERRORS=1 timeout --kill-after=2s 100s \
  flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 90s "$auth_bin" \
  --skip "$auth_old_plain" --skip "$auth_old_positive" \
  --skip "$auth_old_negative" --skip "$auth_new_plain" \
  --skip authentication_error_match_positive_control \
  --nocapture --test-threads=1 \
  > target/stdlib-work/tls-signature-auth-generic-exhaustive-fixed.log 2>&1
```

The first-generic command is a historical partial-run receipt, not an instruction to restore its failing classifier. On the corrected fixture it selects the three generic API gates; the accepted record above deliberately keeps its original one-pass/two-compilation-failures outcome.

## Compilation history and separate diagnostics

The first current-source ordinary admission attempt stopped **before ELF generation**, after 4.13 s; its fresh Rust-driver build took 1.19 s. The surfaced LNC0021 diagnostic pointed at an unchanged `tls_handshake` Iterator header. A narrower path-only compilation then identified unsupported bare-assignment match arms in the path error mapper; the owner rewrote them as an enum-valued match without changing error policy or tariffs. The corrected path ordinary gate passed in 9.86 s, followed by the unchanged authentication ordinary consumer in 13.96 s. The unchanged handshake header is not the cause or a compiler dependency, and no compiler change was made. The ignored initial log is `target/stdlib-work/tls-signature-auth-ordinary-first.log`; the accepted retry is recorded above. The initial failure never executed authentication code.

The first generic protocol compilation reported LNC0005 at its test-only Error classifier's final bare wildcard arm (`_->999`, token 80769). Neither generic protocol test reached ELF/runtime. Before changing it, the exact classifier was preserved in [a positive actual-Error diagnostic](../tests/fixtures/extended/tls_authentication/match_auth_error_wildcard.lani), alongside [an exhaustive named-variant control](../tests/fixtures/extended/tls_authentication/match_auth_error_explicit.lani). Both assert matched scalar and payload cases plus formerly default outcomes; neither encodes an expected compiler failure. The executing fixture now names all Error variants with exactly the same result codes; production, peer decisions and coverage are unchanged. This is scoped full-fixture evidence, not a blanket claim that every wildcard fails. The controls have a separate positive driver test, `authentication_error_match_positive_control`. `LANIUS_AUTH_ERROR_MATCH_CONTROL` allowlists only `match_auth_error_explicit` and `match_auth_error_wildcard`; the default is explicit. Each selection must compile, execute with empty input/output, and satisfy the same allocation-trace checks. No expected-error assertion was added. This selector-only driver update is `dcd98e54`; the six API gate bodies are unchanged from their executed `e5ad90c6` driver. The corrected generic protocol gates passed with that exhaustive classifier. The small controls remain separate pending diagnostics; they do not block the admitted API or establish a general wildcard failure. No compiler change was made.

## Historical selected-hash verification

These receipts describe the Ed25519-only version before the owned generic-key/policy/shared-tariff integration; they do not admit the current source.


At that historical milestone the [driver](../tests/extended_tls_authentication_execution.rs) kept three exact groups: `server_flight_authentication_matches_real_chain_signature_and_finished_peer`, `server_authentication_retries_budgets_and_terminal_failures_withhold_peer`, and `ordinary_server_authentication_consumer_executes_without_error_projection`. All three passed separately on the frozen selected-hash source and fixtures, without a failed gate or an authentication-specific compiler change.

The independent peer emits both SHA-256 and SHA-384 cases for positive and negative protocol groups, selecting hashlib/HMAC and Finished lengths from the explicit algorithm. It retains real certificate-path/identity/time checks and independent Ed25519 CV verification; suite hash does not change the certificate signature algorithm. Final publication compares all active digest bytes and canonical 48-byte observation storage, including zero tails.

The ordinary consumer passed four flows: both algorithms in both packed/native-strided layouts. It checks both owned RFC contexts against complete independent 146-byte backing, including inactive zero tails; mutates a CVInput copy and source digest; and verifies that another owned input and transcript snapshot remain unchanged. The positive/negative fixtures retain source-frame clearing and guard checks.

New first-frame work cases provide the exact expected bridge allowance minus one, exactly that allowance, and plus one for each algorithm/layout. These seams avoid depending on X.509 parser costs. They check rejection without a debit when insufficient, exact spending on admission, later metadata precedence and terminal behavior. The driver continues to distinguish exact bridge debits from nonnegative additional path charges. Those historical gates exercised the then-current tariffs, before the generic-key reserve and shared primitive-verification charges were introduced.

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

Historical selected-hash source SHA-256 hashes, checked after that execution, are:

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

The following receipts predate the typed-secret/SHA-384/CVInput migration. They establish the earlier SHA-256-only source; the selected-hash predecessor has separate historical receipts above. Current multi-signature admission is recorded separately above.

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
