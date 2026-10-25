# Portable TLS server-flight authentication

`ext::tls_authentication` verifies a TLS 1.3 server authentication flight in strict order: EncryptedExtensions, Certificate, CertificateVerify, Finished. Certificate processing calls the actual [bounded X.509 path validator](extended-x509-path.md) with explicit anchors, expected service identity, and time. CV proves possession of that validated leaf key; Finished binds it to the supplied handshake secret and transcript. The implementation is [tls_authentication.lani](../extended/ext/tls_authentication.lani).

The authentication checkpoints and signature context follow [RFC 8446 sections 4.4.1–4.4.4](https://www.rfc-editor.org/rfc/rfc8446.html#section-4.4). This module supports the SHA-256/Ed25519, X.509 server-authentication profile. It has no allocation, IO, foreign TLS backend, or caller-supplied trust flag/key shortcut.

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
    server_handshake_secret: View<u8>,
    offered_signature_schemes: View<u16>,
    config: Config
) -> Result<State, Error>;

pub enum Phase {
    EncryptedExtensions, Certificate, CertificateVerify, Finished,
    Authenticated, Failed
}
```

The caller supplies a transcript through **already checked CH/SH negotiation**, and the corresponding 32-byte server handshake traffic secret. Construction copies both, plus the reference identity and time. It retains only the immutable anchor descriptors/backing. Changing the original secret bytes, reference object, offer list, or transcript afterward does not change this State.

The transcript shape must be two messages without HRR, or four messages with HRR rewrite applied. This catches an incorrect checkpoint shape; it does not establish transcript provenance or negotiate CH/SH. The caller must have checked versions, cipher/hash/group, shares, session echo, HRR restrictions, extensions, and the selected X.509 profile. Use the checked transcript and service-identity constructors rather than fabricated state/fields.

The offered signature list has 1 through 32767 `u16` entries and must contain Ed25519 (`0x0807`). It covers the **CV offer**. The caller must separately ensure certificate Ed25519 signatures are permitted by the CH `signature_algorithms_cert` policy, or its `signature_algorithms` fallback. Path algorithm support alone does not check those offers.

Anchors must contain 1 through 8 logically valid DER views. `max_frame` is a complete handshake-frame limit, including its four-byte header, from 4 through 16777219. Construction checks descriptor metadata before indexing, with the anchor-count bound checked before nested descriptors. It then checks the limit, secret length, bounded offers, and transcript shape. No constructor parses an anchor or accepts a peer key. Explicit anchor/path/reference/time validation occurs during Certificate.

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
| Finished | Exactly 32 verify bytes and correct MAC using the copied server handshake secret and current transcript hash |

Certificate entries are DER X.509 certificates. Raw public keys and every nonempty CertificateEntry extension are explicitly unsupported. This includes OCSP and SCT extensions; the bridge does not silently ignore their meaning or claim revocation/CT verification. A server Certificate context must be empty and its list nonempty. Path order, supported certificate algorithms, constraints, anchor handling, DNS/IP identity, and inclusive explicit UTC time checks follow the validator's documented bounded offline profile. The bridge inherits that profile's limitations; it does not add general path building or revocation policy.

The bridge collects at most eight small DER-view descriptors locally. Parsed certificate records use caller-provided Slot workspace; no inline array of parsed certificates is created inside State. On Certificate, scratch must have at least `presented_entry_count + configured_anchor_count` slots. No scratch is required for EE, CV, or Finished: the argument is ignored in those phases. Scratch is never retained by State.

The CV signed input is exactly 130 bytes: 64 spaces, `TLS 1.3, server CertificateVerify`, one zero byte, and the SHA-256 transcript through Certificate. CV is appended only after successful verification. Finished is checked against the transcript through CV and appended only after successful verification. The leaf key is committed internally only after complete path success and Certificate transcript append; it remains unavailable through both getters until Finished succeeds.

`peer_key()` and `transcript()` return `None` before authentication or after any terminal failure. Successful returns own independent inline bytes. They do not borrow Certificate frames, scratch, anchors, or State. The returned transcript is the through-server-Finished checkpoint for later application/exporter derivation and client Finished processing. No resumption or client-Finished state is implemented here.

## Retry and terminal errors

Malformed frame metadata returns `Bounds` before every state check, without changing State, scratch, or budget. In Certificate, malformed scratch metadata also returns `Bounds` before work or parsing. Scratch metadata is ignored outside Certificate. Metadata validity means nonnegative start/length and a representable `i32` end; backing remains a caller precondition.

An undersized Certificate scratch view returns retryable `ScratchTooSmall`. Hash, leaf, phase, and scratch remain unchanged. It is detected after bounded TLS list parsing, so that feed's shared work debit is **not refunded**. A retry with sufficient scratch charges the frame again and appends it once on success.

Every wire/schema, order, size/work/signature budget, path, CV, Finished, or transcript failure is terminal. The first error is latched and `phase()` becomes Failed. Later valid feeds return that same error without further progress or budget use. A later malformed frame still returns transient Bounds first, while the latched failure is preserved. There is no reset or resume method after terminal failure. Unexpected optional CertificateRequest, missing/skipped stages, replay, or any feed after Authenticated is terminal `UnexpectedMessage`.

The error categories are `Bounds`, constructor limits/secret/transcript/anchor/offer errors, `FrameLimit`, `WorkLimit`, `SignatureLimit`, `ScratchTooSmall`, `UnexpectedMessage`, `Handshake(codec_error)`, Certificate context/list/count/extension errors, `Path(path_error)`, `CertificateVerify`, `Finished`, and `Transcript`. Path diagnostics retain the validator's kind and certificate/anchor/offset coordinates. A caller maps failures to connection abort/alerts under its own bounded transport policy.

A failure can withhold future getters but cannot revoke a key/transcript copy returned earlier. The owner of a full connection must treat later fatal protocol errors as terminal and stop using that connection. Public implementation fields are not a supported way to manufacture an authentication decision.

## Shared work and signature limits

Create `x509_path::Budget` with its checked factory and pass the same live budget throughout the flight. Do not reset/replenish it between Certificate and CV. Path certificate signatures and CV consume the **same** `signatures_left`; CV debits one before expensive verification, including a failed proof. Shared parsing/work use the validator's existing counters as well.

Before any eager TLS parser scans a frame, feed checks both `Config.max_frame` and `Budget.limits.max_input`. It then charges **4096 + 256 × complete_frame_bytes** from `work_left`. This conservative logical tariff covers frame/hash copying and both eager Certificate-list passes, including possible 1024-word duplicate-extension bitmap clears. Path parsing/policy work is additional. A rejected work debit does not modify the remaining counter; it makes State terminal. These are logical resource limits, not instruction counts or an elapsed-time bound.

The path defaults include a 1 MiB input ceiling and 16 MiB shared work. Those limits are independent: the bridge tariff means the default work allowance admits **less than roughly 64 KiB of total frame bytes**, with further path costs. Raising `max_frame` alone does not admit a larger flight. The accepted test includes a real eight-certificate flight of roughly 80 KiB (the peer asserts it exceeds 64 KiB): default work rejects before Certificate parsing, while an explicitly raised shared work allowance admits it. Applications must choose coherent frame, parser, path, work, signature, and storage limits.

## Backing and state copies

All input descriptors require actual physical backing. Anchors and their descriptor list must stay immutable and live until Certificate processing completes for every State copy that may use them. Each frame must stay immutable through its feed; accepted frame bytes are hashed/copied, so State retains no frame borrow afterward. The expected reference is copied; it is not learned from the presented certificate, SNI, DNS, or connected address.

Frame, scratch, anchors, State, and Budget must be mutually disjoint where any is writable. Scratch can be partially overwritten on a path error and can contain borrowed parsed records afterward. Do not inspect those records after their DER backing is reused/released. State returns only a copied key on complete validation and keeps no scratch reference. Reuse one workspace for serial calls after ending prior uses; do not share it concurrently.

State value copies fork their inline transcript, pending key, secret, phase, and error. They share only immutable anchor backing. They can progress independently with appropriate caller workspace, but shared Budget charges remain cumulative. Copies do not clone owners or acquire cleanup authority. There is no secure-erasure or constant-time compiler claim.

## Accepted verification

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
