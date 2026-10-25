# Owned signature verification

Accepted for **x86_64 Linux output from GPU compilation**. Four focused
protocol gates passed 719 commands, and the ordinary consumer passed four
published cases. Source and independent oracles are reviewed. Performance
and user GPU-kernel behavior remain unverified. The existing path,
authentication, negotiation and connection integrations are being extended
separately; their guides distinguish accepted evidence from pending work.

This Lanius module imports owned public keys, classifies strict certificate
AlgorithmIdentifiers and TLS signature IDs, and dispatches real Ed25519,
P-256/SHA256 and RSA/SHA256 verification. It provides no signing, certificate
trust decision, identity/time validation or complete TLS authentication.
The [integration plan](tls-signature-integration-plan.md) tracks that work.

## API and supported matrix

`Bytes` means `core::slice::View<u8>`. Fallible calls return
`core::result::Result<T, Error>`.

| Call | Success value |
| --- | --- |
| `default_limits()` | `Limits { max_message: 1048576, max_signatures: 64, max_work: 1073741824 }` |
| `budget(Limits)` | `Budget` |
| `parse_spki(complete_der: Bytes, budget: &Budget)` | `PublicKey` |
| `certificate_scheme(complete_algorithm_der: Bytes, budget: &Budget)` | `Scheme` |
| `tls_scheme(id: u16, use: Use)` / `tls_id(Scheme)` | `Scheme` / `u16` |
| `default_proofs()` / `default_certificates()` | Owned ordered `Policy` |
| `validate_policy(Policy, Use)` | `i32` zero |
| `allows(Policy, Scheme, Use)` | `bool` |
| `verify(key: &PublicKey, use: Use, scheme: Scheme, message: Bytes, wire_signature: Bytes, budget: &Budget)` | `bool` |
| `key.borrow()` / `key.kind()` / `budget.borrow()` | `&PublicKey` / `Kind` / `&Budget` |
| `key.ed25519_key()` | Copied `Option<ext::ed25519::Key32>` |

`Use` is `Certificate` or `CertificateVerify`. `Kind` is `Ed25519`, `P256`
or `Rsae`. `PublicKey` is an owned struct containing a private material enum.

| Scheme | Required key | Certificate use | CertificateVerify use | Wire signature |
| --- | --- | --- | --- | --- |
| `Ed25519` | Ed25519 | `0807` | `0807` | Exactly 64 bytes |
| `EcdsaP256Sha256` | P-256 | `0403` | `0403` | Strict DER `SEQUENCE(INTEGER r, INTEGER s)` |
| `RsaPkcs1Sha256` | RSAE | `0401` | Rejected | Exactly the modulus byte length |
| `RsaPssRsaeSha256` | RSAE | `0804` | `0804` | Exactly the modulus byte length |

IDs are hexadecimal. The mapper and verifier both enforce PKCS#1's
certificate-only restriction; an eligible ID alone never authorizes a proof.
Unknown IDs, restricted-PSS-key IDs and other hash/curve schemes return
`UnsupportedAlgorithm`. These choices follow
[RFC 8446 section 4.2.3](https://www.rfc-editor.org/rfc/rfc8446.html#section-4.2.3).

All verification entry points take the **complete message**. Ed25519 uses
pure Ed25519 without external prehashing. P-256 and RSA hash the supplied
message once with SHA256. No digest shortcut, signature-format guessing,
algorithm fallback or automatic TLS context construction is supplied.
Callers construct the correct signed certificate/proof bytes and enforce
offers, roles, transcript checkpoints and Finished separately.

### Explicit ordered policies

`Policy { order: [u16;4], length: i32 }` owns one to four active, unique TLS
IDs in preference order. The unused tail is ignored. Default proof policy
is `0807,0403,0804`; default certificate policy adds `0401`. Callers validate
each public configuration value for its intended `Use`. Invalid active lengths
and duplicate IDs return `InvalidParameters`; unknown or use-forbidden active
IDs return `UnsupportedAlgorithm`. No validation or permission helper changes
the policy or a budget.

`allows` validates the whole policy before returning membership. A malformed
policy returns an error even when the requested scheme is absent. A valid
proof policy returns false for the certificate-only PKCS#1 scheme. Copying a
policy preserves its active list independently of later changes to the original.
The copied Ed25519 key projection returns `None` for P-256/RSAE keys; it adds
no private-key capability or trust decision.

The four-family ordinary consumer also passed after adding explicit projection
checks: mutating the projected Ed25519 copy leaves the retained key unchanged
and executable, and P-256 plus both RSA cases return `None`. That gate took
8.66 seconds including GPU compilation, with an empty allocation trace;
receipt: `target/stdlib-work/tls-signature-projection-copy.log`.

The focused native policy consumer passed on 2026-10-25 in 7.84 seconds,
including GPU compilation. It checks all 65,536 TLS IDs for each use, 10,368
policy cases drawn from supported/unknown IDs and duplicate combinations,
permission queries, copied ownership, invalid lengths and unused tails.
The emitted executable exits zero with empty stdout/stderr and an empty
allocation trace. Receipt: `target/stdlib-work/tls-signature-policy-first.log`.
Connected signature integration remains under implementation and requires its
own path, proof and peer evidence.

The admitted policy/projection source pins are production
`887ca81497e6ced65afbdc0a87d093ec1c28d338a09296987f9dedb4734a6ee0`,
policy consumer
`9c0bd64e777e8629d2081c0910c987dbae49674e0915c0794cf91917f23ce8f5`,
ordinary consumer
`e55ce7dba66c7d4737c3520c4f5b466bfe33438112200dfea285b6354935a2fc`,
and driver
`d1f64fe154bfd5c67d28a9325ebf199dea1e4a94a20ce07c2e2651fe9b2f6542`.
The fresh driver build took 1.14 seconds
(`target/stdlib-work/tls-signature-policy-build.log`). These receipts extend
the earlier standalone admission below; they do not rerun its 719-command
matrix or establish connected TLS behavior.

### Strict import and classification

Only complete, canonical DER SPKIs are accepted, with zero unused BIT STRING
bits. Key and AlgorithmIdentifier input caps are `MAX_SPKI_BYTES = 1024`
and `MAX_ALGORITHM_BYTES = 256`, independent of the message-size limit.

- **Ed25519:** SPKI OID `1.3.101.112`, absent parameters and exactly 32 key
  bytes. Its certificate signature identifier has the same OID and absent
  parameters. Import checks shape and copies bytes; it does not establish
  point/subgroup validity. The existing verifier applies those checks when
  the key is used. A shape-admitted key is not a trust token.
  See [RFC 8410](https://www.rfc-editor.org/rfc/rfc8410.html).
- **P-256:** `id-ecPublicKey` with required named-curve OID
  `1.2.840.10045.3.1.7`. Accepted 33-byte compressed and 65-byte uncompressed
  points are checked as finite/on-curve and stored as an owned canonical
  65-byte key. Missing, NULL, explicit or other curve parameters, restricted
  key-agreement OIDs, hybrid points and infinity are rejected. Certificate
  signatures require `ecdsa-with-SHA256` and absent parameters.
  See [RFC 5480](https://www.rfc-editor.org/rfc/rfc5480.html) and
  [RFC 5758 section 3.2](https://www.rfc-editor.org/rfc/rfc5758.html#section-3.2).
- **RSAE:** the existing [RSA importer](extended-rsa.md) requires
  `rsaEncryption` with NULL, an odd canonical 2048–4096-bit modulus and an
  odd-u32 exponent at least 3. Its cached arrays are owned. Signature
  classification reuses the same RSA parser: PKCS#1/SHA256 permits absent
  or NULL parameters; PSS requires SHA256, MGF1-SHA256, salt32 and omitted
  default trailer. Restricted PSS-key SPKIs and other profiles are rejected.
  See [RFC 4055](https://www.rfc-editor.org/rfc/rfc4055.html).

ECDSA wire signatures are DER-only, never raw `r||s`. Canonical positive
nonzero INTEGER syntax is checked before curve verification; values at
least the curve order produce cryptographic rejection. Valid high-S and
low-S signatures remain accepted. RSA retains exact DigestInfo/PSS checks,
including the non-byte-aligned 2049-bit `emLen` case. Mathematical rejection
returns `Ok(false)`; wrong sizes/encodings produce explicit errors.

## Ownership, errors and shared allowances

Use `parse_spki`; key material is immutable implementation state, not a
serialization format. Copies own independent inline arrays and retain no
source borrow. Imports/classification/verification preserve all input bytes.
All logical ranges need stable physical backing. Inputs may overlap each
other, but must be disjoint from the mutable budget and immutable key state.
Signed native strides and packed byte views use ordinary indexing. Logical
metadata does not prove physical capacity or enforce alias rules.

`Limits` contains `max_message: i32`, `max_signatures: u64`, `max_work: u64`.
`Budget` contains `message_limit: i32`, `signatures_left: u64`,
`work_left: u64`. Negative message limits are invalid; zero limits are valid.
The message limit applies to `verify`, not fixed-size DER imports. The
default work limit does not guarantee all 64 expensive attempts fit.
Keep the same budget across a decision. Copying/replenishing it explicitly
forks or resets the caller's allowance; this module never does so implicitly.

Errors are `Bounds`, `InvalidLimits`, `InputLimit`, `WorkLimit`,
`SignatureLimit`, `UnsupportedAlgorithm`, `InvalidParameters`, `InvalidKey`,
`SchemeKeyMismatch` and `InvalidSignatureEncoding`. Priorities are:

1. Validate every direct view's start, length and overflow before byte access
   or budget changes. Then check the budget's message limit.
2. Imports/classification check their fixed cap, reserve `length + 128`, and
   parse strict schema. P-256 import reserves its crypto tariff before point
   validation; Ed25519 reserves 32 copy credits before copying.
3. Verification checks message cap, use eligibility, key family and signature
   size, in that order. A wrong key family wins over malformed signature size.
4. P-256 reserves `signature_length + 128` and parses DER **before** checking
   the attempt quota. Invalid DER consumes its parse charge but no attempt;
   even quota zero does not bypass this syntax check.
5. Check the attempt quota, reserve crypto/hash work and consume one attempt.
   An unaffordable reservation consumes neither its work nor an attempt.
   Admitted cryptographic failures consume both, including early mathematical
   rejection inside a primitive. Earlier parse/import charges are retained.

RSA uses a transferred allowance: a temporary `rsa::Budget` receives exactly
the shared remaining work and message limit; remaining work is copied back
on **every** delegated return, including errors. No fresh default budget is
created. The wrapper checks the attempt quota before verification and debits
one attempt only when the RSA verifier's positive work reservation succeeds.
The delegated RSA setup, verification and failure charges remain authoritative.
RSA SPKI and certificate classification each include this module's common
classification charge plus the existing RSA parser's own charges; these are
explicit separate bounded stages. There is no rollback on a later error.

## Work units and security limits

The fixed tariffs are **bounded digit-loop/body/helper credits**. They are
source-derived admission envelopes, not CPU/GPU instructions, elapsed time,
equal-cost units across algorithms or compiled constant-time guarantees.
Their basis differs from broader weighted source-action accounting used by
other TLS planning documents. Delegated RSA retains its documented credit
schedule. Each stage still draws from one shared numeric allowance.

| Stage | Source envelope | Rounded tariff |
| --- | --- | ---: |
| P-256 import | At most 1040 products × 512 + 4096 linear helpers × 64 = 794624 | `P256_IMPORT_WORK = 1048576` |
| P-256 verification | 512 scalar steps × 32768 + 2048 products × 512 + 8192 linear helpers × 64 = 18350080 | `P256_VERIFY_WORK = 33554432` |
| Ed25519 verification | 1024 scalar steps × 32768 + 4096 products × 512 + 8192 linear helpers × 256 = 37748736 | `ED25519_VERIFY_WORK = 67108864` |

The counts follow the fixed digit sizes, point-add/double/select schedules,
inversions and public decoding in [P-256](../extended/ext/p256.lani) and
[Ed25519](../extended/ext/ed25519.lani). P-256's two scalar multiplications
give 512 steps; Ed25519's two subgroup checks and two proof multiplications
give 1024. Product envelopes cover schoolbook/reduction bodies and bounded
local overhead; linear helpers cover fixed digit scans and selections.
The fixed tariffs reserve worst-case work even when public data allows an
earlier failure.

P-256 additionally reserves
`n + 1024*floor((n+72)/64) + 4096` for SHA256 message work. Ed25519 reserves
`n + 1024*floor((n+144)/128) + 4096`, where `n = message_length + 64` includes
the encoded R/public-key prefix hashed internally with SHA512. Lengths and
credit arithmetic fit `u64` for valid current `i32` views. There is no hidden
deadline or retry; callers also bound operation counts and external I/O.
No allocation, private-key operation, secure-erasure or host backend is added.

## Executable admission

[extended_signature_execution.rs](../tests/extended_signature_execution.rs)
compiles a shared protocol fixture per driver invocation and a separate
ordinary consumer without Error-enum projection. All output response bytes
are compared, not merely success counts. Native runs require empty traces
for `mmap`, `munmap`, `mremap` and `brk` and unchanged source/guard storage.
All five API gates passed these checks.

| Exact filter | Accepted blocks / commands |
| --- | --- |
| `all_key_scheme_and_use_combinations_match_independent_openssl` | 18 / 189 |
| `malformed_and_inconsistent_signatures_match_independent_openssl` | 6 / 286 |
| `strict_spki_algorithm_identifiers_and_tls_ids_are_classified` | 117 / 117 |
| `metadata_and_shared_allowance_bridges_preserve_inputs_and_attempts` | 23 / 127 |
| `ordinary_consumer_imports_owns_classifies_and_verifies_all_families` | Four published cases in one separate consumer |

The four protocol groups passed in **one focused invocation, 25.70 s**:
164 blocks and **719 commands**, one shared protocol ELF and four native
processes. The earlier ordinary invocation passed in **9.28 s**, using a
separate ELF/native process. API evidence totals **two strict ELFs and five
native processes**, all with empty allocation traces. Diagnostics below are
separate and excluded from these counts. This is not a single whole-target
test invocation. Timings include compilation/orchestration, not signature
throughput. Peer/native protocol timeouts are 45 seconds each; the ordinary
timeout is 10 seconds. The fresh final diagnostic/protocol driver build took
1.16 s; the same frozen production and fixtures supplied both API invocations.

Expected cryptographic acceptance comes from OpenSSL EVP DigestVerify with
explicit scheme/hash/RSA padding, MGF and salt settings. Existing test-only
Python affine/pow helpers author signatures and check independent raw public
operations; they do not supply native expected acceptance. Published anchors
reuse attributed [RFC8032](extended-ed25519.md),
[RFC6979](extended-p256.md) and [NIST RSA](extended-rsa.md) fixtures. The
matrix includes six original positive NIST byte vectors, generated exact
2049/4096-bit RSA keys, compressed P-256 import, empty through 16 KiB messages,
all key/scheme/use combinations and both physical layouts.

Other groups exercise signature/message mutations, strict parameter and ID
rejection, wrong key/use priority, malformed views, copy/reassignment of the
large owned enum, source overwrite, complete guards, exact/one-less work,
quota zero, DER-before-quota ordering and post-import shared depletion.
Final source/test review is clean. This admission establishes the stated
standalone verification profile; X.509 path integration, certificate/proof
offer enforcement, TLS authentication integration, cross-peer TLS tests and
performance remain pending. No public trust/identity/time/Finished or signing
capability follows from this foundation.

### Earlier standalone commands and source receipts

Frozen SHA256 prefixes are production `8d1f17ee`, final Rust driver
`61e73950`, independent peer `3e8d5964`, protocol `8b101d45` and ordinary
fixture `7f6107f1`. The peer, protocol, ordinary source and all expectations
were unchanged through the source-form repairs described below. The current
binary is
`target/stdlib-build/debug/deps/extended_signature_execution-cb9d8345407ed7f3`.
The ordinary receipt predates the final diagnostic-selector additions in the
Rust driver; its test body was unchanged. Reproducing it with the current
driver uses:

```sh
RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
LANIUS_DEBUG_STAGE_ERRORS=1 timeout --kill-after=2s 100s \
  flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s \
  target/stdlib-build/debug/deps/extended_signature_execution-cb9d8345407ed7f3 \
  --exact ordinary_consumer_imports_owns_classifies_and_verifies_all_families \
  --nocapture --test-threads=1 \
  > target/stdlib-work/signature-ordinary-exhaustive-first.log 2>&1
```

The accepted four-group protocol invocation used the final driver, skipping
only the already accepted ordinary case and the separate diagnostic:

```sh
RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
LANIUS_DEBUG_STAGE_ERRORS=1 timeout --kill-after=2s 100s \
  flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 90s \
  target/stdlib-build/debug/deps/extended_signature_execution-cb9d8345407ed7f3 \
  --nocapture --test-threads=1 \
  --skip ordinary_consumer_imports_owns_classifies_and_verifies_all_families \
  --skip explicit_policies_cover_ids_subsets_copies_and_use_permissions \
  --skip signature_match_arm_control \
  > target/stdlib-work/signature-protocol-first.log 2>&1
```

The 90-second inner wrapper remains below two minutes; each peer/native
subprocess keeps its separate 45-second limit. Build receipt:
`target/stdlib-work/signature-material-control-build.log`. An earlier joint
hash/signature Rust build took 1.21 s; that host build alone was not runtime
evidence. All GPU compilation/native invocations were serialized by root;
the source author ran only source/AST/format checks. Other execution targets
and standalone user GPU kernels remain unverified.

### Admission dependency investigation

The initial ordinary and matrix gates stopped before ELF production with
`LNC0005 UnresolvedIdent` at a qualified call following a dense wildcard
match arm. Replacing the impossible-family direct panic with typed
`Option` extraction still stopped at `core::option::None()` in the same
arm. Conventional spacing also failed in the full composition. These
results do **not** isolate a panic/never-type or general whitespace/wildcard
issue. The accepted production uses exhaustive named Material
variants for those extractions; all validation and allowance ordering, the
matrix and independent oracles are preserved.

| Earlier production source | Invocation | Pre-ELF result / elapsed | Log under `target/stdlib-work/` |
| --- | --- | --- | --- |
| `fa97d108`, direct impossible-family panic | Ordinary | LNC0005 / 3.60 s | `signature-ordinary-first.log` |
| `fa97d108` | Matrix | LNC0005 / 5.45 s | `signature-matrix-first.log` |
| `ac001fbc`, typed Option with wildcard | Ordinary | LNC0005 / 3.73 s | `signature-ordinary-option-fixed.log` |
| `eb4b7b0b`, spaced typed Option | Ordinary | LNC0005 / 3.87 s | `signature-ordinary-spaced-first.log` |

Three minimal self-contained source candidates under the signature fixture
directory compare unspaced wildcard, conventionally spaced wildcard and
exhaustive named-variant arms. Each checks the same three runtime results.
Fresh unspaced and spaced i32-payload controls passed in 3.75 s and 4.04 s,
respectively. The default named-variant i32 control also passed in 4.00 s
(`target/stdlib-work/signature-match-explicit-first.log`). The full spaced
production ordinary consumer still failed
before ELF generation in 3.87 s. The unresolved identifier remains scoped
to that larger composition. Two closer controls use the actual mixed
RSA/Ed25519/P-256 record payloads, nested family branches and repeated
differently typed locals, comparing wildcard and exhaustive projections.
The actual-record wildcard fixture (`858be637`) now reproduces
`LNC0005 UnresolvedIdent` at `core::option::None()` on line 15, token 26404,
before ELF generation in **3.55 s**. The exhaustive production
(`8d1f17ee`) passed the unchanged four-case ordinary consumer in **9.28 s**.
The actual-record explicit control (`954a2baa`) passed in **6.71 s** with
the fresh `61e73950` driver. The same production then passed all four
protocol groups without oracle/expectation changes.

The fresh closer-control Rust build took 1.16 s and produced
`extended_signature_execution-cb9d8345407ed7f3`. The accepted ordinary run
used the earlier diagnostic driver revision with the test-only mutable
`Command` argument correction, before the actual-record selector entries
were added; its ordinary test body was unchanged. These driver revisions
must not be conflated merely because the local executable suffix is reused.
The separate positive diagnostic filter `signature_match_arm_control`
defaults to `match_explicit`; `LANIUS_SIGNATURE_MATCH_CONTROL` can select
`match_wildcard_spaced`, `match_wildcard_unspaced`,
`match_material_records_wildcard` or `match_material_records_explicit`.
No expected-error test is added. The first diagnostic Rust build separately
failed `E0308` because its test-only direct `Command` argument needed a
mutable borrow; root fixed that argument and the fresh build passed. This
was a host test-driver compilation error, not a production runtime failure.
Its receipt is `target/stdlib-work/signature-record-build-frozen.log`, with
the corrected build in `signature-record-build-control-fixed.log`.
A stale diagnostic invocation
matching zero tests is not evidence. Original failure logs are retained;
the closer build receipt is `target/stdlib-work/signature-material-control-build.log`,
the minimal failure is `signature-material-wildcard-first.log`, the paired
control is `signature-material-explicit-first.log`, and the ordinary pass
is `signature-ordinary-exhaustive-first.log` in the same directory.
These diagnostic controls are separate from API-matrix admission. No compiler,
extractor, IR, ABI or proof changes are part of this
investigation; the scoped dependency is also recorded in
[library-dependencies.md](library-dependencies.md).
