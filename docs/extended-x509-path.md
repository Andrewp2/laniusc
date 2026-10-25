# Ordered server certificate paths

[`ext::x509_path`](../extended/ext/x509_path.lani) makes a bounded server
certificate decision using explicit application anchors, a supplied UTC time,
and a DNS or IP reference. It verifies the exact signed TBSCertificate bytes
through the owned [signature dispatcher](extended-signature.md). Certificate
edges support Ed25519, ECDSA/P-256/SHA-256 and RSAE PKCS#1/SHA-256 or
PSS/SHA-256/MGF1-SHA-256/salt32. Only success returns an independent owned
`signature::PublicKey` for the leaf.

**Multi-algorithm path admission passed on 2026-10-25** for native x86_64
Linux output from GPU compilation. All five focused gates have accepted
receipts, with source versions and repaired fixture failures recorded below.
The historical Ed25519-only receipt remains separate. This is an ordered,
offline TLS-server profile; it does not implement general PKIX path
construction or all RFC 5280 policy processing.
The scope below is part of the API contract. Certificate parsing alone, a
self-signature, a peer-supplied root, or a matching service name grants no
trust.

The path rules derive from [RFC 5280 sections 4.2 and
6](https://www.rfc-editor.org/rfc/rfc5280.html#section-6), Ed25519 encodings
from [RFC 8410](https://www.rfc-editor.org/rfc/rfc8410.html), and service
identity from [`ext::service_identity`](../extended/ext/service_identity.lani).
The implementation is allocation-free Lanius above the existing borrowed
[X.509 parser](extended-x509.md), calendar and owned signature modules.
OpenSSL and libsodium are test oracles only.

## Public API

```lanius
struct Limits {
    max_chain: i32, max_anchors: i32, max_input: u64,
    max_signatures: u64, max_work: u64, parsing: x509::Limits
}
struct Budget {
    parsing: x509::Budget, verification: signature::Budget, limits: Limits
}
struct Slot {
    certificate: Option<x509::Certificate>,
    public_key: Option<signature::PublicKey>
}
struct ValidatedServer {
    public_key: signature::PublicKey, anchor_index: i32, chain_length: i32
}
default_limits() -> Limits
budget(limits: Limits) -> Result<Budget, Error>
Budget.borrow() -> &Budget
empty_slot() -> Slot
validate_server(
    chain: View<View<u8>>, anchors: View<View<u8>>,
    reference: service_identity::Reference, unix_time: i64,
    certificates: signature::Policy, scratch: View<Slot>, budget: &Budget
) -> Result<ValidatedServer, Error>
```

`chain` is nonempty and ordered leaf first, followed by intermediates.
`anchors` is a separate, nonempty set of certificate DER views supplied by
the application. Each configured certificate supplies its subject, public
key, validity and constraints as the anchor authority. Its self-signature is
not a source of trust and is not verified. All configured anchors are parsed
before path decisions; malformed unused configuration also fails closed.

The default limits are eight peer certificates, eight configured anchors,
1 MiB of cumulative peer **plus anchor** DER, 64 signature attempts, and
1,073,741,824 shared verification/path work units. The increase from the
historical 16,777,216 allowance explicitly accommodates the shared primitive
and owned-cache tariffs. `verification.message_limit` comes from the
nonnegative `parsing.max_input`; signature and work counters live only in
`verification`. The embedded X.509 limits separately default to
1 MiB per certificate, 100,000 item visits and 16,777,216 parsing work units.
Configured counts are nonnegative and their sum must fit `i32`.

`scratch.length` must be at least `chain.length + anchors.length`. Slots are
caller storage for parsed borrowed records; they are not trust tokens. The
function never trusts preexisting Slot contents. Outer logical bounds,
counts, scratch capacity, time, inner metadata, aggregate size and local
certificate-policy validity precede the first work debit and Slot mutation.
Bad preflight/configuration, or an unaffordable first debit, leaves scratch
untouched. After that debit succeeds, every active Slot is cleared before
parsing starts. Later errors may leave parsed records and successful imports
in scratch, and retain their admitted costs. Every subsequent validation
rebuilds its active caches; supplying a key or parsed certificate in scratch
never grants authority. Argument/configuration errors consume no budget. No physical backing extent can be
inferred from logical metadata: every view must have live backing for its
declared extent, including strided views. Scratch must not overlap input
DER, descriptor arrays, reference or budget storage.

Use `budget()` and preserve its limits and counters; its public fields allow
an enclosing protocol engine to debit `verification.work_left` and
`verification.signatures_left` before frame handling and CertificateVerify. Do not replenish them during one decision.
Copying the record forks the allowance. Shared borrowed budgets enforce an
aggregate bound across parsing, candidate anchors, signatures and identity.

## Ordered chain and anchor rules

Names link by **exact DER encoding**, including string type and case. The
same comparison determines self-issued status: subject DER equals issuer
DER. This is a restricted profile, stricter than RFC 5280's normalized DN
comparison. Equal keys or a valid self-signature do not make a certificate
self-issued for path-length accounting.

Every peer signature is checked against the next certificate's key. The
last peer signature is checked against a configured anchor whose subject
matches its issuer. An exact DER copy of a configured anchor at the end of
a chain of length greater than one is removed from the effective peer
count. Its already checked child signature is reused, and the configured
anchor's policy applies. No approximate subject/key match strips a peer
certificate. Direct trust in a non-CA leaf is outside this profile: a
configured anchor must satisfy the CA rules below.

Duplicate authorities within either input list are rejected before path
work. Authority equality means exact subject and SubjectPublicKeyInfo DER;
this conservatively rejects repeated authorities even if certificate serials
or signatures differ. Cross-list duplicates fail for a selected candidate
unless they are the exact final root copy removed above. A self-issued
rollover certificate with a different key remains possible. There is no
search, intermediate reordering, issuer fetching or automatic anchor lookup.

Candidates are considered in supplied order. A matching issuer with an
invalid signature or disallowed anchor policy does not prevent trying a
later candidate. If no candidate succeeds, the first issuer-linked
candidate's error is returned; if none links, the result is `Untrusted`.
Resource exhaustion stops immediately, including on a later candidate.
Earlier failed attempts retain their budget costs. Parsing failures in
configured anchors are immediate configuration errors.

## Time, usage and constraints

The application supplies signed Unix UTC seconds in
`[-62135596800, 253402300799]`, covering years 1 through 9999. There is no
system-clock call or default time. Every peer and the selected configured
anchor must contain a nonreversed interval, and the supplied time must lie
in it **inclusively**. Certificate times use the parser's explicit
seconds-and-Z profile; leap-second encodings are unsupported there.

Every intermediate and selected anchor requires `basicConstraints.cA`.
KeyUsage, when present, must include `keyCertSign` on those certificates and
`digitalSignature` on the leaf. ExtendedKeyUsage, when present on **any**
path certificate or selected anchor, must contain `serverAuth` or
`anyExtendedKeyUsage`. Absent KU/EKU places no restriction in this profile.

Each `pathLenConstraint` counts only non-self-issued intermediate CAs below
that CA. It excludes the target leaf and the CA carrying the constraint.
Self-issued rollover still consumes chain, parsing, comparison and signature
budgets. Arbitrarily large positive minimal DER path lengths are compared
without narrowing to `u64` or inventing a numeric profile cap.

Critical basicConstraints, KeyUsage, ExtendedKeyUsage and SAN are processed.
A critical SAN may contain only DNS-ID and IP-ID choices in this profile;
other choices fail `UnsupportedCritical`. Other critical extension OIDs
fail `UnknownCritical`. DNS/IP matching scans every SAN/extension even
after a match; a later parse or budget failure prevents success.

The following controls fail `UnsupportedConstraint` **even when
noncritical**: nameConstraints, certificatePolicies, policyMappings,
policyConstraints and inhibitAnyPolicy. This implementation does not ignore
their semantics and then advertise a fully validated PKIX path. Unknown
noncritical extensions also fail conservatively, except this explicit
metadata allowlist:

- SubjectKeyIdentifier and AuthorityKeyIdentifier, which do not replace
  subject linkage or signature verification.
- AuthorityInfoAccess, CRLDistributionPoints and FreshestCRL. Their contents
  remain opaque and no locations are fetched.

This is an **offline policy without revocation checking**. Certificate
revocation status is unchecked. The allowlist does not claim validation of
these metadata extensions or their remote objects.

## Algorithms, budgets and errors

The caller supplies a nonempty, duplicate-free ordered `signature::Policy`
for certificate edges. The shared `validate_policy(..., Certificate)` rejects
unknown IDs and invalid lengths before any work debit. The default certificate
policy permits `0807,0403,0804,0401`; this is distinct from the default TLS
proof policy, which omits certificate-only PKCS#1. Each checked child
AlgorithmIdentifier is classified by `signature::certificate_scheme`, checked
against this certificate policy, then verified with its **issuer's** imported
key. A child's subject key may belong to a different family from its issuer
or signature. There is no inference or padding/encoding fallback.

Shared import supports RFC8410 Ed25519, named-curve P-256 with supported
compressed/uncompressed points, and the bounded RSAE 2048–4096-bit profile.
It retains strict algorithm parameters and DER signature rules. See the
[signature contract](extended-signature.md) for exact encodings and tariffs;
the X.509 parser's exact inner/outer AlgorithmIdentifier comparison remains.
Unsupported imports or algorithm/policy classification map to indexed
`UnsupportedAlgorithm`; shape/key mismatch and false verification map to
indexed `InvalidSignature`. Shared resource failures retain `InputLimit`,
`WorkLimit` or `SignatureLimit`. Malformed local certificate policies use
`UnsupportedAlgorithm` with both indices -1.

Anchor self-signatures remain unverified, so their algorithms do not limit
trust in configured public keys. The exact stripped-root exception also
reuses only an already verified child edge. This exception does not waive
certificate-edge policy for any other peer, and subject==issuer alone never
manufactures trust. Leaf possession still requires the enclosing protocol's
CertificateVerify and Finished.

Every active peer key is imported at its existing policy/issuer boundary.
Configured anchor keys are imported **only for linked candidates**. Unlinked
anchors are still structurally parsed but do not fail merely because their
key algorithm is unsupported. Successful imports are cached for this call;
failed imports are not cached. A later linked candidate may recover from an
unsupported key or failed signature, while resource exhaustion stops search.
Issuer-import errors identify the issuer certificate and its certificate-relative
SPKI location; signature errors identify the signed child.

The shared signature budget admits algorithm-specific setup, hashing and
verification. Failed attempts retain their charges; a positive expensive
reservation consumes an attempt, while a denied reservation does not create
one. Existing child OID and `tbs.length + 97` path debits remain. Storage and
owned-key handoffs add these explicit abstract costs:

| Operation | Shared work debit |
| --- | ---: |
| Initial preparation, for N active Slots | `N*(SLOT_STORAGE_WORK+1)+1` |
| Cache inspection at a policy/import boundary | `KEY_COPY_WORK` |
| Successful import result and cache publication | `2*KEY_COPY_WORK`, plus OID/import work |
| Cached issuer into a stable verification local | `2*KEY_COPY_WORK` |
| Returned independent leaf key | `2*KEY_COPY_WORK` |

`SLOT_STORAGE_WORK=524288` covers reset plus parsed-Slot publication using two
8KiB logical storage envelopes at 32 credits/byte. `KEY_COPY_WORK=131072` uses
a 4KiB logical handoff envelope; RSA stores three 128-element u64 arrays plus
bounded metadata. These are conservative abstract credits, not asserted ABI
sizes, generated copy counts, machine instructions, RSS or wall time. Physical
Slot/key footprint and compiler copy behavior need separate measurement.

Other explicit path costs are:

- Descriptor preparation: peer count plus anchor count plus one.
- Each byte comparison: both input lengths plus one, before length/byte
  comparisons, including candidate and duplicate scans.
- OID classification/purpose scans: OID length plus one.
- Validity comparisons: 19 units; each returned SAN choice: one unit.
- Path-length comparison: INTEGER content length plus one.

The shared X.509 budget covers all repeated framing, item visits and content
scans, including malformed TLV attempts. Service identity charges its own
reference and SAN comparisons to that same parsing budget. Units are
conservative logical work, not measured instructions or wall time.
Consumption is never rolled back after any error. No hidden retry, reset,
allocation, owner release, file/network I/O or implicit clock access occurs.

`Error { kind, certificate, anchor, offset }` uses zero-based peer and
configured-anchor indices; `-1` means inapplicable. An anchor-policy error
has `certificate == -1`. Signature failures identify the signed peer and
candidate anchor when applicable. `offset` is a logical byte offset within
the identified certificate, never a physical address. Generic policy,
metadata and linkage errors may use zero. Parsing wrappers retain the
underlying X.509 error's certificate-relative offset, with resource kinds
preserved as `InputLimit`, `ItemLimit` or `WorkLimit`.

`Bounds`, empty/count/input/scratch limits and `InvalidTime` describe
preflight errors. Other kinds distinguish parsing, duplicate authorities,
unsupported algorithms, linkage/trust/signature failure, validity, CA/KU/EKU,
path length, critical/constraint handling and identity failure. No error
returns a leaf key or a partly trusted decision.

## Borrowing and remaining work

All DER and descriptor backing must stay live and unchanged throughout the
call, with no concurrent mutation. Slot certificates retain those borrowed
views after the call; callers must not use them after backing is recycled.
Only parser-produced records with preserved fields may be used as checked
X.509 values. The validator reparses input and never trusts caller-fabricated
Slot records or supplied key caches. Returned `ValidatedServer.public_key`
is an independent owned value, usable after every Slot, DER buffer and
descriptor is cleared or reused. `ed25519_key()` explicitly extracts an owned
Ed25519 witness when that is the actual key family; it is not a default route
for other families. Slots now include the largest owned RSA cache, so callers
must account for expanded inline storage rather than assuming the historical
Ed25519 slot size.

Remaining general PKIX work includes normalized DN matching, path building,
name constraints and policy processing, revocation decisions, other critical
extension semantics and additional algorithms/policies. This profile is one
dependency of the [TLS connection contract](tls-connection-contract.md); it does not
establish a complete TLS engine, transport, peer proof, certificate lifetime
management or general interoperability by itself.

## Accepted multi-algorithm verification: 2026-10-25

The focused target `extended_x509_path_execution` retains the ordinary
consumer and prior semantic/OpenSSL controls, with direct typed caller
migration and no compatibility aliases. All five gates have accepted
receipts across three driver invocations:

| Test | Accepted coverage | Receipt |
| --- | --- | --- |
| `ordinary_path_consumer_returns_only_the_validated_leaf_key` | Ordinary Ed25519 chain and explicit owned Ed25519 extraction | Ordinary, 9.86 s |
| `ordered_signed_paths_match_independent_policy_and_shared_budget_cases` | 146 semantic commands, including issuer-import indexed failure | Corrected pair, 30.21 s combined |
| `supported_ed25519_paths_agree_with_openssl_verify` | 16 explicit-anchor OpenSSL commands | Initial protocol batch, 36.80 s overall |
| `mixed_issuer_families_policies_cache_retirement_and_openssl_paths` | 64 layout commands: mixed issuer/subject families, policies, poisoned/rebuilt caches, lazy anchors and import-work indexing | Initial protocol batch, 36.80 s overall |
| `mixed_paths_share_exact_work_and_signature_admission_without_cache_reuse` | Eight baseline commands plus 24 one-less/exact/one-more combined work controls | Corrected pair, 30.21 s combined |

The accepted total is **258 protocol commands plus the ordinary consumer**.
Those successful groups used **five strict ELFs and six native processes**:
one ordinary ELF/process, two ELFs/processes for the two accepted initial
protocol groups, and two newly compiled ELFs with three native processes for
the corrected pair. The baseline and boundary portions of the last gate
share one ELF but launch separate native processes. Failed attempts are
excluded from those accepted counts. Every accepted native allocation trace
was empty for `mmap`, `munmap`, `mremap` and `brk`. Native execution has a
40-second per-process timeout. This verifies CPU execution of GPU compiler
output, not a user GPU kernel or another execution target.

The mixed corpus constructs real signed DER through OpenSSL and uses
`openssl verify` only for common supported complete-path expectations. Explicit
local-policy, cache, candidate-order and resource expectations are separate.
Its host cost composition reuses the independently exercised signature
foundation tariff oracle and independently parsed DER facts, plus the public
storage/handoff contract. This pins complete successful path work; native
baseline controls additionally check exact admission boundaries. No observed
native counter defines the independent expected tariff.

Each mixed success clears every active source descriptor, Slot and DER byte
before an independently supplied leaf proof is checked with each of two
retained key copies. Both packed and
strided layouts have nonzero input/scratch starts and guards. Dedicated
controls cover caller cache poisoning, fresh repeated validation, unimported
unlinked anchors, retained successful failed-candidate imports, all-cache
clearing before later parse failure and issuer-indexed import exhaustion.
`mixed.py` imports only test oracle helpers; production imports no Python,
OpenSSL or host crypto backend. These timings and abstract work assertions
make no isolated throughput, machine-instruction or physical-storage claim.
The real certificate application's 95-case migration remains separately
pending in [its guide](extended-verify-certificate.md).

### Version pins and failure history

The executed production source throughout every accepted group was
`extended/ext/x509_path.lani` SHA-256
`ae5d9c3347437424982a721e6fed868f34fde2c2911a8ddc654aaa3feb420037`.
The ordinary source was
`0b7d907af19afb51a842724def72186f9e86509cee9a2a1225cf8ae92ed4ee87`,
and the protocol source was
`6a86910e4a23d0afa5100555bc6fe861dd2df6310c53010d7a983456af118485`.

| Source | Accepted version / scope |
| --- | --- |
| Driver, ordinary and initial protocol invocation | `fb01defe7e8fca854d867471ebf0dec250c8a7cce613c7a1462ef823e3d00a9a` |
| Mixed fixture, initial accepted 64 commands | `74d5704aa6c6c3c0595cdac444136b3d932a5f6fd2c72fa4458bbd92d1e8892f` |
| Mixed corpus | `9b306991927a83c214d85dddcd52e5bdb730e554d3137a80c93f46ba5cf69f5b` |
| Driver, corrected pair; bounded diagnostics only | `1a6f7d061c568ad8be54719cd964577d278f64954e4bc7a16d724eaa9258097d` |
| Mixed fixture, corrected boundary gate | `a10f34e3f430dba2b3721804a9e2d62a59080af600e9d74fd556769398363ba0` |
| Semantic model, corrected 146 commands | `38782f262fad2da07ad14820e6cfbf8a96f2fe310a0b9ee3308666d8bad21ccf` |

The earlier semantic-model version
`e496f0cf7e23657871cd05848320146beb1a01aeed83bb323c5de83d309c7ffc`
also supplied unchanged host DER helpers to the initial mixed corpus and
OpenSSL controls. This is receipt accounting across source versions, **not**
a claim that the final whole target ran once without failures.

1. The first ordinary attempt failed before ELF emission in **3.32 s** on
   an inadmissible statement-valued match arm in the new error mapper
   (`LNC0016`). Enum-valued arms corrected that stdlib syntax without changing
   mappings or tariffs. The ordinary retry then passed in **9.86 s**.
2. The initial four-test protocol invocation completed in **36.80 s** with
   two passes and two failures. Its 64 mixed commands and 16 OpenSSL commands
   remain accepted. Semantic case 36 expected import rejection for a
   31-byte Ed25519 key, but the existing X.509 schema correctly rejected that
   RFC8410 width during parsing. The corrected witness is a well-framed
   named-P256 SPKI with an invalid 32-byte key, reaching the intended shared
   import boundary and issuer index.
3. The initial boundary process hit a test assertion after 18 reports: a
   one-less WorkLimit case reused a mode that unconditionally required a
   successful cache result. Success-specific cache/repeat checks now run on
   actual success; that mode permits only explicit WorkLimit on its failure
   branch, and the independent Rust expectation still requires WorkLimit.
   Positive model expectations remain success. No production or tariff
   change addressed either protocol failure.
4. The corrected two-test invocation passed in **30.21 s**, accepting all
   146 semantic commands and all eight baseline plus 24 boundary commands.
   Driver diagnostics were bounded to lengths and short prefixes, without
   changing contract assertions. No compiler dependency or compiler change
   was established or needed by these failures.

The initial path-driver build took **1.16 s**. The fresh corrected-driver
build, also selecting TLS TCP and exchange targets, took **1.45 s**; it was
not an isolated path build measurement. Ignored local receipts are:

- `target/stdlib-work/tls-signature-path-build.log`
- `target/stdlib-work/tls-signature-path-ordinary-first.log`
- `target/stdlib-work/tls-signature-path-ordinary-syntax-fixed.log`
- `target/stdlib-work/tls-signature-path-protocol-first.log`
- `target/stdlib-work/tls-signature-path-tcp-app-build.log`
- `target/stdlib-work/tls-signature-path-boundaries-fixtures-fixed.log`

### Recorded commands

The corrected joint Rust build used:

```sh
timeout --kill-after=2s 100s flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s env \
  CARGO_TARGET_DIR=/home/andrew-peterson/code/laniusc/target/stdlib-build \
  CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  cargo test --test extended_x509_path_execution \
  --test extended_tls_tcp_execution --test extended_tls_exchange_execution --no-run \
  > target/stdlib-work/tls-signature-path-tcp-app-build.log 2>&1
```

The three actual runtime selections below used this wrapper and the same
binary basename; the fresh build replaced its contents before the corrected
pair. They were serialized, with an outer 100-second limit, lock wait at most
35 seconds and the stated inner limit:

```sh
path_gate() {
  inner_limit="$1"; shift
  RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
    LANIUS_DEBUG_STAGE_ERRORS=1 timeout --kill-after=2s 100s \
    flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
    timeout --kill-after=2s "$inner_limit" \
    target/stdlib-build/debug/deps/extended_x509_path_execution-5795f25b8c495892 \
    "$@" --nocapture --test-threads=1
}
path_gate 60s --exact ordinary_path_consumer_returns_only_the_validated_leaf_key \
  > target/stdlib-work/tls-signature-path-ordinary-syntax-fixed.log 2>&1
path_gate 90s --skip ordinary_path_consumer_returns_only_the_validated_leaf_key \
  > target/stdlib-work/tls-signature-path-protocol-first.log 2>&1
path_gate 90s --skip ordinary_path_consumer_returns_only_the_validated_leaf_key \
  --skip mixed_issuer_families_policies_cache_retirement_and_openssl_paths \
  --skip supported_ed25519_paths_agree_with_openssl_verify \
  > target/stdlib-work/tls-signature-path-boundaries-fixtures-fixed.log 2>&1
```

The first protocol log intentionally records its mixed outcome. Replaying
that selection on corrected sources is a new run, not the historical receipt.

## Historical Ed25519-only native verification

[`extended_x509_path_execution.rs`](../tests/extended_x509_path_execution.rs)
passed all three focused gates on x86_64 Linux, using GPU-compiled native
ELFs:

- An isolated ordinary consumer, with no caller projection on path error
  enums, verifies a real signed chain and checks the returned key.
- 144 model commands: 72 independently signed semantic cases in native byte
  array and packed layouts, with nonzero starts, outer descriptor/scratch
  starts, guards, unchanged DER, and retained returned-key copies. Cases
  include self-issued rollover, included/excluded roots, trust/usage/time/
  constraints, huge path lengths, duplicate authorities, failed candidate
  continuation, exact signature quotas and preflight/resource errors. A
  matching SAN followed by item exhaustion must still fail the full identity
  scan. Selected candidate-policy failures pin exact peer/anchor indices.
- 16 commands compare eight supported signed-chain decisions with
  `openssl verify` using explicit anchors, time, sslserver purpose and DNS-ID.
  Cases outside the shared restricted policy are excluded from that
  differential.

The host fixture creates actual signed DER using libsodium's independent
Ed25519 signer/verifier and host semantic certificate facts; production never
calls it. The accepted whole-target invocation passed in **20.28 seconds**:
144 model commands, the ordinary consumer and 16 OpenSSL differential
commands. One strict protocol ELF was reused between the model and OpenSSL
groups, alongside one strict ordinary-consumer ELF. All three native
processes passed with empty `mmap/mremap/munmap/brk` traces. The driver bounds
each native run to 40 seconds. This is native execution of compiler output,
not execution of certificate validation as a GPU kernel.

The fresh Rust driver build took 1.30 seconds. Logs are
`target/stdlib-work/tls-peer-auth-admission/build-x509-path.log` and
`target/stdlib-work/tls-peer-auth-admission/x509-path-all.log`. The accepted
production source SHA-256 remained
`166b35eacf1daf6e1813bd30ef1a9873bf0e5c74f4ec69ebae4800929d43bf42`.
Independent source review also passed.

The accepted command ran the whole target once, rather than three separate
exact-test invocations:

```bash
RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
timeout --kill-after=2s 100s \
  flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s \
  target/stdlib-build/debug/deps/extended_x509_path_execution-5795f25b8c495892 \
  --nocapture --test-threads=1 \
  > target/stdlib-work/tls-peer-auth-admission/x509-path-all.log 2>&1
```

These gates admit the documented ordered Ed25519 profile. The general PKIX
and complete TLS requirements listed above remain open.
