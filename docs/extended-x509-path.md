# Ordered Ed25519 server certificate paths

[`ext::x509_path`](../extended/ext/x509_path.lani) makes a bounded server
certificate decision using explicit application anchors, a supplied UTC time,
and a DNS or IP reference. It verifies the exact signed TBSCertificate bytes
with the real Lanius Ed25519 verifier. Only success returns an independent
copy of the leaf public key.

This is an initial ordered Ed25519, offline TLS-server profile. It does not
implement general PKIX path construction or all RFC 5280 policy processing.
The scope below is part of the API contract. Certificate parsing alone, a
self-signature, a peer-supplied root, or a matching service name grants no
trust.

The path rules derive from [RFC 5280 sections 4.2 and
6](https://www.rfc-editor.org/rfc/rfc5280.html#section-6), Ed25519 encodings
from [RFC 8410](https://www.rfc-editor.org/rfc/rfc8410.html), and service
identity from [`ext::service_identity`](../extended/ext/service_identity.lani).
The implementation is allocation-free Lanius above the existing borrowed
[X.509 parser](extended-x509.md), calendar and Ed25519 modules. OpenSSL and
libsodium are test oracles only.

## Public API

```lanius
struct Limits {
    max_chain: i32, max_anchors: i32, max_input: u64,
    max_signatures: u64, max_work: u64, parsing: x509::Limits
}
struct Budget {
    parsing: x509::Budget, signatures_left: u64,
    work_left: u64, limits: Limits
}
struct Slot { certificate: Option<x509::Certificate> }
struct ValidatedServer {
    public_key: ed25519::Key32, anchor_index: i32, chain_length: i32
}
default_limits() -> Limits
budget(limits: Limits) -> Result<Budget, Error>
Budget.borrow() -> &Budget
empty_slot() -> Slot
validate_server(
    chain: View<View<u8>>, anchors: View<View<u8>>,
    reference: service_identity::Reference, unix_time: i64,
    scratch: View<Slot>, budget: &Budget
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
16,777,216 path work units. The embedded X.509 limits separately default to
1 MiB per certificate, 100,000 item visits and 16,777,216 parsing work units.
Configured counts are nonnegative and their sum must fit `i32`.

`scratch.length` must be at least `chain.length + anchors.length`. Slots are
caller storage for parsed borrowed records; they are not trust tokens. The
function never consumes preexisting Slot contents. Scratch may be partially
overwritten on failure. Outer logical bounds, counts, scratch capacity, time,
inner bounds and aggregate size checks precede parsing and Slot mutation.
These argument errors consume no budget. No physical backing extent can be
inferred from logical metadata: every view must have live backing for its
declared extent, including strided views. Scratch must not overlap input
DER, descriptor arrays, reference or budget storage.

Use `budget()` and preserve its limits and counters; its public fields allow
an enclosing protocol engine to debit the same allowances before frame
parsing and CertificateVerify. Do not replenish them during one decision.
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

Peer signature algorithms and every path public key must use Ed25519 with
absent parameters and the RFC 8410 sizes. The executable signature dispatch
has a real Ed25519 branch and rejects other algorithms; later RSA/ECDSA
verifiers can extend that boundary without replacing ordered path policy.
Anchor signature algorithms do not constrain the trusted public key because
anchor self-signatures are not verified. Leaf proof of private-key
possession still requires TLS CertificateVerify, followed by Finished.

Every attempted signature consumes one signature allowance before expensive
verification. A separate path-work debit of `tbs.length + 97` precedes it;
the fixed Ed25519 work is bounded by the signature count. Failed signature
attempts consume the same allowance. Other explicit path costs are:

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
Slot records. Returned `ValidatedServer.public_key` is an independent inline
32-byte value, usable after scratch and DER storage are reused.

Remaining general PKIX work includes normalized DN matching, path building,
name constraints and policy processing, revocation decisions, other critical
extension semantics, and RSA/ECDSA algorithms. This profile is one dependency
of the [TLS connection contract](tls-connection-contract.md); it does not
establish a complete TLS engine, transport, peer proof, certificate lifetime
management or general interoperability by itself.

## Accepted native verification

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
