# TLS certificate and proof signature integration

**Integration proposal; the standalone dispatch foundation is executable.**
The [owned signature module](extended-signature.md) passes 719 protocol
commands and a four-vector consumer. RSA and P-256 primitives also execute.
The current path validator,
CertificateVerify receiver and local credential signer still use Ed25519.
This document proposes their integration; it adds no new trust decision.
The overall standard-library/TLS goal remains open.

## Current boundaries

| Source | Existing contract that integration must preserve/change |
| --- | --- |
| [`x509`](../extended/ext/x509.lani), `parse` / `spki` | Borrowed schema records; inner/outer signature AlgorithmIdentifiers currently must have identical DER. Unknown algorithms can be parsed without being executable. |
| [`x509_path`](../extended/ext/x509_path.lani), `public_algorithm` / `signature` / `validate_server` | Ordered paths, configured anchors, explicit identity/time, CA/usage/constraint policy and shared counters; dispatch and returned leaf key are Ed25519-only. |
| [`tls_authentication`](../extended/ext/tls_authentication.lani), `server` / `verify` / `peer_key` | Hardcoded `0807`; copied leaf retained internally after Certificate, public result withheld until Finished. |
| [`tls_negotiation`](../extended/ext/tls_negotiation.lani), `choose` / `check_server_hello` / `write_client_extensions` | Parses separate proof/certificate lists, including the required missing-certificate-list fallback, but requires/emits Ed25519 and puts a synthetic signature choice into ServerHello selection. |
| [`tls_connection`](../extended/ext/tls_connection.lani), configs / `derive_handshake` / `prepare_cv` | Client offers/authenticates Ed25519; server seed is a real Ed25519 signer and every configured certificate signature is currently required to be Ed25519. |
| [`rsa`](../extended/ext/rsa.lani) / [`p256`](../extended/ext/p256.lani) | RSA owns bounded cached public state and charges work; P-256 validates/copies points and verifies raw signatures, with a strict DER adapter but no budget. Both provide verification, not signing. |

## One executable verification boundary

`ext::signature` now supplies the shared verification boundary above the
existing primitives. The notation below describes its roles; the
[module guide](extended-signature.md) and [source](../extended/ext/signature.lani)
define the admitted signatures and ownership contract. `PublicKey` is an
owned wrapper with private tagged storage, rather than a public enum:

```text
PublicKey = owned Ed25519, P256 or Rsae key material
Scheme    = Ed25519 | EcdsaP256Sha256 | RsaPkcs1Sha256 | RsaPssRsaeSha256
Use       = Certificate | CertificateVerify
Limits    = { max_message: i32, max_signatures: u64, max_work: u64 }
Budget    = { message_limit: i32, signatures_left: u64, work_left: u64 }

budget(Limits) -> Result<Budget, Error>
parse_spki(complete_der: Bytes, budget: &Budget) -> Result<PublicKey, Error>
certificate_scheme(complete_algorithm_der: Bytes, budget: &Budget)
    -> Result<Scheme, Error>
tls_scheme(id: u16, use: Use) -> Result<Scheme, Error>
verify(key: &PublicKey, use: Use, scheme: Scheme,
       message: Bytes, wire_signature: Bytes, budget: &Budget)
    -> Result<bool, Error>
```

`Bytes` is `View<u8>`. `tls_scheme` maps certificate-only PKCS#1 IDs only
for `Certificate` use, including a missing-extension-50 fallback list;
`verify` also rejects `RsaPkcs1Sha256` with `CertificateVerify`, so a wrong
caller route cannot enable it. Certificate classification can return all
four schemes. No algorithm inference, padding fallback or raw/DER guessing
is allowed. Keep only this dispatch boundary; path/authentication code must
not maintain separate RSA/ECDSA interpretations.

Errors distinguish `Bounds`, `InputLimit`, `WorkLimit`, `SignatureLimit`,
`UnsupportedAlgorithm`, `InvalidParameters`, `InvalidKey`,
`SchemeKeyMismatch` and `InvalidSignatureEncoding`. A well-shaped incorrect
signature returns `Ok(false)`; enclosing path/authentication layers map it
to their existing indexed signature/fatal proof errors. Resource errors
retain their category so candidate search cannot conceal exhaustion.

All direct view metadata precedes byte access and counter changes. Then
apply fixed input/size caps, algorithm parameters, use/key compatibility,
signature shape and reservation before the expensive operation. DER
classification/import stages already admitted before a later error retain
their charges. Inputs require live physical backing and are disjoint from
mutable budget/state; all supported strides use ordinary indexing.

## Exact key and signature matrix

| Owned key / SPKI | Certificate signature | TLS proof ID / representation |
| --- | --- | --- |
| Ed25519 OID `1.3.101.112`, absent parameters, zero unused bits, 32 bytes | Ed25519 OID with absent parameters; 64 raw bytes | `0807`; 64 raw bytes; pure Ed25519 over the complete message |
| `id-ecPublicKey` `1.2.840.10045.2.1`, required named curve `1.2.840.10045.3.1.7`, zero unused bits | `ecdsa-with-SHA256` `1.2.840.10045.4.3.2`, absent parameters | `0403`; strict DER SEQUENCE(INTEGER r, INTEGER s), then existing P-256 verification |
| `rsaEncryption` `1.2.840.113549.1.1.1`, required NULL; existing strict RSAE importer | `sha256WithRSAEncryption`, absent or NULL; or exact supported PSS parameters | `0804`; RSA-PSS/SHA256, MGF1-SHA256, salt32, exactly `key.signature_length()` bytes |

Use [RFC 8410](https://www.rfc-editor.org/rfc/rfc8410.html) for Ed25519,
[RFC 5480 sections 2–3](https://www.rfc-editor.org/rfc/rfc5480.html#section-2)
for EC keys, [RFC 5758 section 3.2](https://www.rfc-editor.org/rfc/rfc5758.html#section-3.2)
for ECDSA identifiers and [RFC 4055](https://www.rfc-editor.org/rfc/rfc4055.html)
for RSA parameters. For P-256, accept existing supported uncompressed and
compressed encodings, validate finite/on-curve points, and store the
canonical 65-byte key. Reject hybrid/infinity points, missing/NULL/explicit
curve parameters, other curves and `id-ecDH`/`id-ecMQV` restrictions.
ECDSA wire signatures never accept raw `r||s`; range checks remain in the
verifier, and valid high-S and low-S signatures remain accepted.

RSA retains its 2048–4096-bit, odd-u32 exponent profile, including the
2049-bit PSS `emLen` rule. Reject restricted PSS-key SPKIs, different
hash/MGF/salt policies and unsupported hashes. Reuse `rsa::signature_scheme`
and `parse_rsae_spki`, rather than creating another PSS parser. The generic
X.509 parser's exact inner/outer AlgorithmIdentifier DER comparison remains
an explicit stricter profile: absent-vs-NULL is accepted for either complete
RSA identifier, but mixing their encodings inside one certificate remains
rejected unless a separately reviewed parser change is justified.

An issuer's key selects the verifier for a child's signature. The child's
subject key can be a different family: RSA CA → P-256 intermediate →
Ed25519 leaf is valid within the supported policy. SPKI import is not proof
of trust, private-key possession or RSA key-generation assurance. Ed25519
import initially checks algorithm/size and copies bytes; its existing
verifier enforces point/subgroup rules when used. Do not call every imported
value a fully validated cryptographic key.

## Ownership and one shared allowance

Change `ValidatedServer.public_key`, authentication's retained leaf and
`Engine.peer_key()` to the owned enum. Use `Option<PublicKey>` for absent
internal state. A successful path returns a copied key; authentication
keeps it private until CertificateVerify **and** Finished succeed, and the
engine keeps its existing established-state publication boundary. Reusing
certificate, frame or scratch bytes must not change a retained key.

Add an initially empty imported-key cache to each path Slot. Initialize it
on every validation call; never trust caller-supplied scratch/cache fields.
Import supported peer keys at their existing policy boundaries and import
configured anchor keys only for linked candidates. Cache a successful import
within that decision so repeated signatures do not repeatedly expand RSA
keys. Unused configured anchors still undergo existing structural parsing;
do not accidentally reject them solely because eager crypto import added a
new policy. A full cached RSA enum occupies several KiB: include the added
Slot/engine storage, inline-copy cost and required-buffer calculations in
the integration review and performance gate. No allocation fallback.

Embed one `signature::Budget` in the path budget. Existing path/frame work
debits use its `work_left`; all issuer attempts and CertificateVerify use
its `signatures_left`. Keep the existing separate X.509 parsing budget,
with its purpose documented. Migrate every direct counter access in path,
authentication, connection stats and local signing. Do not reset an allowance
per certificate, candidate, algorithm switch or proof.

Bridge existing RSA APIs using a temporary `rsa::Budget` seeded from the
shared remaining work and message limit, then commit its remaining work
back on **every** return path. This is one transferred allowance, not a new
default budget. RSA setup, strict parameter parsing and unsuccessful
cryptographic operations retain their existing costs. Check the signature
quota before verification; commit one attempt when the delegated positive
work reservation succeeds. An unaffordable reservation consumes no attempt,
while earlier parse/import charges remain. P-256 and Ed25519 reserve one
attempt plus fixed crypto tariffs and explicit length-dependent hashing
work before entering their unbudgeted primitives. P-256 import also needs
a fixed tariff, including compressed decoding. Publish source-derived
tariff constants and boundary tests before enabling the branches; do not
present them as timing or machine-instruction bounds. Revisit the current
16-Mi-unit default path allowance against the selected multi-algorithm
chain profile, rather than silently making ordinary chains exceed it.

## Offers, checkpoints and local credentials

Keep certificate acceptance and proof acceptance distinct, following
[RFC 8446 sections 4.2.3, 4.4.2–4.4.4 and 9.1](https://www.rfc-editor.org/rfc/rfc8446.html#section-4.2.3).
Proposed default proof preferences are `0807,0403,0804`; certificate
preferences add `0401`. Copy their supported masks/preferences into engine
state from the **actual emitted offer**. Make the extension writer accept
these explicit policies and preserve all-or-error output preflight.
When extension 50 is absent, its effective policy is extension 13's list.
Unknown peer IDs are ignored during selection; unknown/duplicate local
policy IDs are configuration errors. HRR must preserve both offers.

Remove the synthetic Ed25519 selection from `check_server_hello` and
`Selection.signature`: ServerHello selects no signature scheme. Server
credential selection chooses a realizable proof separately; the client
checks the actual CertificateVerify scheme against its retained proof
offer and copied leaf key. Certificate-edge algorithms are checked against
the effective certificate policy. Keep the existing configured-anchor
exception for its unverified self-signature/exact stripped root copy;
subject==issuer on an untrusted peer must never manufacture an anchor.
The initial sender can require offered algorithms on every transmitted
certificate and omit a root; document that stricter chain-selection policy.

CertificateVerify continues to cover the 64 spaces, server context string,
zero separator and transcript snapshot through Certificate. In the current
SHA256 transcript profile that message is 130 bytes. Pass it unchanged to
Ed25519; SHA256-based RSA/ECDSA schemes hash that **whole message once**.
Do not substitute the transcript digest for this message or double hash it.
Verify before appending CertificateVerify, and verify Finished before
appending Finished. Failure stays terminal with no public key/application
publication. Signature hash choice is independent of cipher suite and DHE
group; P-256 ECDSA can accompany X25519 key exchange.

The first integration retains the existing real **Ed25519 seed signer**.
It can serve an Ed25519 leaf signed by supported RSA/P-256 issuers and
must check that the seed matches that leaf. RSA/ECDSA leaf verification lets
the client authenticate independent servers; it does not let the Lanius
server sign with those keys. Do not add unsupported credential variants,
external signer stubs or host-backed substitutes. Implement/audit real
private-key signers in a later milestone before advertising those local
credential capabilities or claiming complete two-role interoperability.

## Implementation sequence and executable gates

1. Implement/import/classify/verify in the shared boundary; test every key
   versus scheme/use combination, strict parameters, wrong encodings,
   2049/4096-bit RSA, compressed P-256, copied values and both layouts.
   Independent OpenSSL verification supplies expected results. Test exact
   and one-less setup/import/verify allowances and unsuccessful charges.
2. Extend ordered paths without changing anchors, identity/time, exact-name,
   CA/KU/EKU/path-length or extension policy. Exercise mixed-family chains
   and failed candidate continuation against an explicitly configured
   OpenSSL path oracle, with matching restrictions. Assert indexed errors,
   budget conservation and leaf-key independence after all source retirement.
3. Extend offers and authentication together. Use independently signed
   RSA-PSS and ECDSA proof messages, wrong-offer/use/key/hash/context cases,
   valid PKCS#1 proof rejection, malformed DER, bad Finished and frame copies.
   Certificate-only permission must never authorize CertificateVerify.
4. Run real OpenSSL peers: Lanius client ↔ RSA/ECDSA/Ed25519 servers and
   Lanius Ed25519 server with mixed issuer chains ↔ OpenSSL client. Cover
   both existing suites, both DHE groups, HRR, fragmented frames, partial
   transport progress, application bytes, close and fatal alerts. Assert no
   established state on trust/proof/Finished failures. Each command stays
   under two minutes; root serializes GPU compilation/native admission.
5. Retain ordinary imported consumers, full input/guard checks and empty
   allocation traces; compare the existing representative performance
   closure after enum/cache expansion. No compiler/ABI/proof changes or
   new benchmark-ratio claim belong to this milestone.

Migrate in-repository callers directly; retain no Ed25519-default adapters
around the new explicit policy/key contract. Preserve existing semantic
regressions while adding mixed-algorithm expectations. Implement each stage
fully before exposing it in offers; no declaration-only dispatch branches.

This closes the missing SHA256 signature verification routes toward the
mandatory TLS algorithms. It does not expand the existing ordered/offline
PKIX profile into general path building, normalized DN processing,
revocation or policy/name-constraint support. SHA384/HKDF primitives alone
do not add a SHA384 TLS schedule/suite, P-384 or new credential signers.
All integration behavior and cross-peer interoperability in this proposal
remain unverified until the gates above pass.
