# DNS and IP service identity

`ext::service_identity` implements DNS-ID and IP-ID validation and matching
above the borrowed `ext::x509` SAN cursor. It follows the matching rules in
[RFC 9525 sections 6.2–6.4](https://www.rfc-editor.org/rfc/rfc9525.html#section-6.2)
and the SAN representations in
[RFC 5280 section 4.2.1.6](https://www.rfc-editor.org/rfc/rfc5280.html#section-4.2.1.6).
The production implementation is pure Lanius, allocates nothing and performs
no host I/O or DNS lookup.

```lanius
pub enum Error {
    Bounds, InvalidDns, InvalidIp, InvalidReference, X509(ext::x509::Error)
}
pub enum Kind { Dns, Ip }
pub struct Reference { kind: Kind, bytes: [u8; 253], length: i32 }

dns_reference(value: View<u8>) -> Result<Reference, Error>
ip_reference(value: View<u8>) -> Result<Reference, Error>
validate_dns_reference(value: View<u8>) -> Result<i32, Error>
validate_dns_presented(value: View<u8>) -> Result<i32, Error>
match_dns(reference: View<u8>, presented: View<u8>) -> Result<bool, Error>
match_ip(reference: View<u8>, presented: View<u8>) -> Result<bool, Error>
match_certificate(cert: ext::x509::Certificate, reference: Reference,
                  budget: &ext::x509::Budget) -> Result<bool, Error>
```

The application constructs its reference from independently chosen service
input, rather than copying a presented SAN. A successful identity comparison
is one part of certificate authentication. It does not verify a signature,
trust anchor, certification path, validity interval, revocation, key usage,
extended key usage, name constraints or TLS handshake transcript. Those
checks belong to the consuming validation layer.

## DNS representation and validation

The DNS constructors and validators accept ASCII letter/digit/hyphen labels,
each containing 1–63 bytes. A label starts and ends with a letter or digit.
Empty labels, spaces, underscores, NUL, non-ASCII bytes, URI syntax, ports,
brackets and backslash escapes reject. The normalized textual name is at most
253 bytes, corresponding to the DNS 255-byte wire limit including label
lengths and the root label. Metadata is checked before indexed access:
starts and lengths must be nonnegative and their sum must fit `i32`.

One optional final dot is accepted and removed for comparison and copied
references. This is the explicit root-label notation described by
[RFC 1034 section 3.1](https://www.rfc-editor.org/rfc/rfc1034.html#section-3.1),
not search-list expansion. Root-only `.`, multiple final dots and empty
interior labels remain invalid. The maximum accepted dotted input is 254
bytes when its final byte is that root dot. No public-suffix list, assigned
TLD table, registration check or minimum number of labels is imposed. The
caller determines that a syntactically accepted name is the intended FQDN.

Numeric labels are allowed, including a wholly numeric name or dotted IPv4
text. [RFC 9525 section 3](https://www.rfc-editor.org/rfc/rfc9525.html#section-3)
explicitly notes the syntactic overlap with IPv4 text. The application chooses
the reference type: `dns_reference` creates a DNS-ID and `ip_reference` creates
an IP-ID. When the independently chosen service reference is an actual IP
address, the application uses IP-ID. The library never changes a numeric
DNS reference into an IP reference or resolves a DNS name to compare its IP.

ASCII A-label spellings such as `xn--bcher-kva.example` pass the same LDH
syntax and ASCII comparison. This is not a full IDNA implementation: it
does not map Unicode, decode Punycode, validate an A-label's decoded IDNA
properties, or derive an A-label from a U-label. Callers needing IDNA apply
their independently selected IDNA policy before this API.

`dns_reference` stores a lowercase, root-dot-free copy in its inline byte
array; unused bytes are zero. It retains no input view. The standalone DNS
validators return the normalized length without copying or changing input.
Raw comparisons validate both logical views first, then reference syntax,
then presented syntax. ASCII case has no significance.

## Presented wildcards

Only one `*` is accepted, and it must be the complete leftmost label of a
presented DNS-ID. It matches exactly one nonempty reference label; the
remaining labels must match in order. Thus `*.example.test` matches
`a.example.test`, while `example.test` and `a.b.example.test` do not match it.
Partial or repeated wildcards such as `f*.example.test`, `*.*.example.test`
and `api.*.test` are invalid. Reference wildcards always reject.

The single-label presented pattern `*` is permitted by this syntax and can
match one single-label reference. The module does not add registry or
public-suffix issuance policy. A consuming application can impose stricter
certificate policy separately.

Raw `match_dns` returns `InvalidDns` for an invalid presented identifier.
Certificate matching ignores invalid DNS-ID entries as nonmatches and keeps
scanning, including invalid wildcard forms, following RFC 9525's instruction
to ignore malformed wildcard identifiers. A later valid DNS-ID can match;
an earlier match remains a match when a later DNS-ID has invalid DNS syntax.
Malformed SAN framing or X.509 structural errors still return errors.

## IP representation and matching

`ip_reference` takes exactly four or sixteen binary octets in network byte
order and stores an independent copy. `match_ip` validates both logical
views and requires each length to be four or sixteen. It compares the entire
address exactly; differing address lengths do not match. IPv4 and an
IPv4-mapped IPv6 encoding therefore remain distinct identifiers.

No textual IP parser, brackets, scope identifier, prefix mask or network
matching is built into this layer. Applications can use
`core::net::parse_ip` and `IpAddr.write_octets` to obtain binary input.
A DNS SAN containing IP-looking text cannot satisfy a binary IP reference,
and an IP SAN cannot satisfy a DNS reference.

## Certificate traversal, limits and errors

The certificate must come from `ext::x509::parse` or a copy of that checked
value. Keep its physical backing alive and unchanged during matching.
Arbitrarily forged or edited nested certificate records are outside the
X.509 manual-record contract. Certificate values and cursors borrow storage;
reference values own independent inline bytes and have ordinary value-copy
semantics. Mutating a reference copy does not change another copy.

Only SAN `dNSName` and `iPAddress` participate. The subject Common Name is
never consulted. Mailbox, URI, SRV/otherName and other SAN forms do not satisfy
these reference types. Ignoring an unrelated name form here does not mark
its semantics or a critical extension handled for path validation.

`match_certificate` walks the complete extension and SAN cursors under the
same live X.509 budget, including entries after a match. This deliberately
keeps later structural failures and exhausted limits observable. It returns
`Ok(true)` only after finishing the scan, `Ok(false)` for a mismatch, or an
explicit error. There is no hidden cursor, retained state or global budget.
Repeated calls construct fresh cursors and consume the same borrowed budget.

Additional work beyond X.509's documented cursor charges is conservative:

- Check the manual reference length before constructing or indexing an
  inline view. An impossible length returns `InvalidReference` immediately.
- Debit `reference.length + 1` work units before its content validation.
- Before validating/comparing each DNS or IP SAN, debit
  `4 * (san_content.length + reference.length) + 1` work units, independent
  of identifier family, match outcome or early byte inequality.

This covers bounded DNS validation and comparisons without charging by CPU
instruction count. Insufficient work returns a wrapped X.509 `WorkLimit`
with the certificate-relative content offset, or offset zero for reference
preflight. Consumption is not rolled back. Item/input limits and X.509/DER
errors retain their original kinds and root-relative offsets. Copying a
budget forks its allowance; use one borrowed instance for aggregate limits.
No concurrent mutation of the budget, references or backing is supported.

| Error | Meaning |
| --- | --- |
| `Bounds` | Malformed raw view metadata |
| `InvalidDns` | Invalid raw DNS syntax, including prohibited wildcard forms |
| `InvalidIp` | Raw IP input is not four or sixteen octets |
| `InvalidReference` | Edited manual reference length or DNS contents fail revalidation |
| `X509(error)` | Original structural or shared-resource failure, including budget exhaustion |

## Focused verification

All four focused gates passed on **x86_64 Linux native executables generated
by the GPU compiler**, with strict ELF checks and empty allocation traces.
The production source, driver, CPU model and Lanius fixtures were unchanged
throughout admission. Independent source/contracts review also passed; that
review is separate from execution evidence.

`tests/extended_service_identity_execution.rs` supplied these exact gates:

| Exact test | Accepted evidence | Elapsed | Log |
| --- | --- | ---: | --- |
| `ordinary_service_identity_consumer_without_error_projection` | Real certificate, copied DNS/IP references and shared budget without caller error projection | 7.04 s | `identity-ordinary.log` |
| `service_identity_dns_ip_models_and_value_copies` | 1,314 commands: independent regex/label model, ASCII mutations, boundaries, wildcards, numeric typing, IP families and copied references | 7.06 s | `identity-raw.log` |
| `service_identity_certificate_san_family_policy_and_shared_budgets` | 226 certificate commands plus 10 bounded continuation controls: CN-only mismatch, invalid DNS entries, SAN family separation, copies and shared/late limits | 7.05 s | `identity-certificates.log` |
| `service_identity_real_openssl_dns_and_ip_certificates` | 42 commands over actual OpenSSL DNS/wildcard/IPv4/IPv6, CN-only and malformed-wildcard certificates | 7.07 s | `identity-openssl.log` |

These were **four independent exact invocations**, each compiling its own
ELF, rather than a single full-suite invocation. Together they admitted
1,592 protocol commands plus the ordinary consumer. Each of the two budget
baselines ran once at full allowance and then with exact work, one fewer
work unit, a shared allowance and one fewer item: ten commands in total.
Each shared control calls the matcher twice within its one protocol command.
The fresh Rust driver build took 1.25 s. These timings include orchestration
and compilation and are not isolated matching-throughput measurements.

Fixtures exercise native-strided arrays and packed bytes at nonzero offsets
and check all input and guard cells. The protocol is compiled once per driver
invocation, with at most 128 commands per bounded native process. Traces must
contain no `mmap`, `mremap`, `munmap` or `brk` calls. A separate Python model
constructs expected names and comparison results without calling production.
Its synthetic certificate signatures intentionally do not authenticate;
real OpenSSL certificates supply a separate structural corpus. OpenSSL and
Python are test setup/oracles only, not production dependencies.

The limit controls measure a successful scan's framing cost, then test that
exact allowance, one fewer work unit at the final SAN content, repeated scans
sharing an allowance, and one fewer item. This checks that an early identity
match cannot bypass a later budget error without freezing parser-internal
framing costs into the identity tests.

The local logs are under `target/stdlib-work/tls-peer-auth-admission/`.
Each accepted exact gate used the standard bounded wrapper below, replacing
`TEST_NAME` and `TEST_LOG` with its table entries:

```bash
RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
timeout --kill-after=2s 100s \
  flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s \
  target/stdlib-build/debug/deps/extended_service_identity_execution-06afa9d30b495495 \
  --exact TEST_NAME --nocapture --test-threads=1 \
  > target/stdlib-work/tls-peer-auth-admission/TEST_LOG 2>&1
```

The executable basename identifies this local build; a fresh build may use
another basename. Admission covers the enumerated cases on x86_64 Linux.
GPU execution here refers to compilation; user GPU kernels and other target
architectures remain unverified. Certificate trust/path validity,
unimplemented identity types and full IDNA processing require their own
implementation and evidence. The manual lifetime/backing and aggregate
budget contracts remain applicable.
