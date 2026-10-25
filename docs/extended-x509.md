# Borrowed X.509 certificate structures

[`ext::x509`](../extended/ext/x509.lani) parses certificate structures in
caller storage above [`ext::der`](extended-der.md). It retains the exact signed
TBSCertificate encoding and returns borrowed fields and bounded cursors. It
allocates no memory, performs no host I/O and owns none of the input backing.

Parsing is not authentication. A returned `Certificate` has passed the
documented framing, field-shape and selected value checks. A certificate
consumer must still verify signatures, process every relevant extension,
build and validate a trust path, compare names, apply hostname rules, check
the clock and validity interval, and handle revocation and application policy.
Those authentication operations require an established native library through
a checked binding; that integration remains a dependency.

The structure definitions follow
[RFC 5280 sections 4.1 and 4.2](https://www.rfc-editor.org/rfc/rfc5280.html#section-4)
and [RFC 8410](https://www.rfc-editor.org/rfc/rfc8410.html). The implementation
uses Lanius and the existing DER, calendar and UTF-8 facilities. It does not
call OpenSSL or a foreign certificate parser.

## Entry point and shared limits

```lanius
struct Limits { max_input: i32, max_items: u64, max_work: u64 }
default_limits() -> Limits
budget(limits: Limits) -> Result<Budget, Error>
Budget.borrow() -> &Budget
parse(input: View<u8>, budget: &Budget) -> Result<Certificate, Error>
```

The defaults permit 1 MiB of input, 100,000 successful TLV visits and
16,777,216 work units. They are configurable resource limits, not additional
ASN.1 profile constraints. Input metadata must be nonnegative and have a
nonoverflowing logical end. Physical backing for that extent is the caller's
responsibility.

The same live budget can cover parsing and later helpers/cursor operations.
Costs are explicit and conservative:

- Every attempted DER framing operation first consumes **11 work units**,
  the bounded maximum header size. A malformed header still consumes them.
  Zero work stops before DER reads input. A cursor already at EOF performs no
  framing attempt and consumes nothing.
- A successfully framed value consumes one item, then `encoded.length + 1`
  work units before its typed scans. Parent and child encodings are charged
  separately. These units cover logical bytes, not measured CPU instructions.
- Equal-length OID/algorithm equality checks charge their length plus one;
  RDN ordering comparisons charge the compared prefix length plus one.
  Duplicate-extension detection rescans earlier extensions and charges those
  visits and comparisons too. Its quadratic worst case remains budgeted.

Budget consumption is not rolled back on error. In particular, an item is
already debited if its subsequent content-work debit fails. Copying a
`Budget` forks its remaining allowance; use one borrowed budget to enforce an
aggregate bound. The budget has no hidden global state or retry. Nesting is
limited to the fixed schema paths described below; opaque values do not
trigger recursive tree validation.

## Returned structures

`Certificate` contains:

| Field | Meaning |
| --- | --- |
| `encoded`, `tbs` | Exact original certificate and signed TBSCertificate encodings |
| `version` | ASN.1 integer value: 0=v1, 1=v2, 2=v3 |
| `serial` | Borrowed positive minimal INTEGER content, including any required leading sign octet |
| `signature_algorithm` | Exact outer `AlgorithmIdentifier` |
| `issuer`, `subject` | Borrowed `Name` values |
| `validity` | Original encoding and decoded `not_before`/`not_after` calendar fields |
| `spki` | Original SubjectPublicKeyInfo, generic algorithm identifier and borrowed key BIT STRING |
| `issuer_unique_id`, `subject_unique_id` | Optional borrowed BIT STRING values |
| `extension_content` | Borrowed extension-sequence content, empty when absent |
| `signature` | Borrowed signature BIT STRING |
| `unknown_critical_count` | Number of critical extension OIDs outside the four typed extension families |

Serial numbers are not narrowed to a machine integer or capped at 20 octets.
The parser rejects zero and negative serials in its selected positive-serial
profile; that is distinct from accommodating nonconforming issuers. A caller
can format or apply its own policy to arbitrarily long positive serial bytes
within the resource limits.

The parser requires exactly one Certificate with exactly three fields and a
complete TBSCertificate in schema order. Explicit DEFAULT v1 is rejected;
unique identifiers require v2/v3, extensions require v3, optional tags may
not repeat or appear out of order, and trailing fields fail. Issuer Names
must be nonempty. An empty subject requires a critical, nonempty SAN.

`AlgorithmIdentifier` preserves `encoded`, generic `oid` and optional
`parameters: Option<der::Element>`. The inner and outer signature algorithm
identifiers must have exactly identical DER bytes. RFC 8410 algorithms require
absent parameters; their public-key lengths are checked for X25519, X448,
Ed25519 and Ed448. Ed25519/Ed448 signature lengths are checked, and X25519/X448
cannot serve as signature algorithms. Other OIDs, parameters and key/signature
bytes remain representable, including RSA and ECDSA. Parsing does not validate
their algorithm-specific parameter schemas or mathematical key material.

Validity uses DER's explicitly bounded X.509 helper: seconds/Z forms,
Gregorian dates, years 1..9999 and seconds 00..59. Leap seconds need a separate
policy. It does not enforce the issuer's choice of UTC versus GeneralizedTime
by year, order the two times, consult a clock or establish current validity.

## Names and attributes

```lanius
Name.rdns() -> Rdns
Rdn.attributes() -> Attributes
Rdns.next(budget: &Budget) -> Result<Option<Rdn>, Error>
Attributes.next(budget: &Budget) -> Result<Option<Attribute>, Error>
```

Both cursor types have `borrow()` and `position()`. A `Name`/`Rdn` retains its
original `element`; `Attribute` contains `oid`, `value: der::Element` and
`encoded`. Every RDN is a nonempty SET OF complete two-field attribute
sequences in canonical encoded order. OIDs are validated without a `u64` arc
restriction. Known string encodings receive UTF-8/Printable/IA5 or BMP/Universal
scalar checks. Legacy Teletex bytes and unknown attribute value semantics stay
borrowed. Attribute OID-to-value-type constraints, repertoire interpretation,
normalization and distinguished-name equality belong to a name-policy layer.

## Extensions and typed helpers

```lanius
Certificate.extensions() -> Extensions
Extensions.next(budget: &Budget) -> Result<Option<Extension>, Error>
Extension.borrow() -> &Extension
Extension.kind() -> ExtensionKind
Extension.basic_constraints(budget: &Budget) -> Result<BasicConstraints, Error>
Extension.key_usage(budget: &Budget) -> Result<KeyUsage, Error>
Extension.extended_key_usage(budget: &Budget) -> Result<Oids, Error>
Extension.subject_alt_names(budget: &Budget) -> Result<GeneralNames, Error>
```

`Extension` retains `root`, `encoded`, `oid`, `critical` and the OCTET STRING's
`value` bytes. Extension OIDs cannot repeat. Explicit DEFAULT false is
rejected, booleans must be canonical, and the value must frame exactly one
DER element. The four recognized families are checked during certificate
parsing; helpers allow callers to inspect them later under the shared budget.

| Family | Returned representation and checks |
| --- | --- |
| Basic constraints | `ca: bool`, `path_length: Option<der::Element>`; canonical omitted false and arbitrary nonnegative INTEGER path length; a path length requires `ca` |
| Key usage | `bits: u32`, bit positions 0..8 follow the named usage indices; nonempty and canonically trimmed named BIT STRING |
| Extended key usage | Nonempty borrowed OID sequence via `Oids.next(budget) -> Result<Option<der::Oid>, Error>`; duplicate sequence values are preserved |
| Subject alternative name | Nonempty `GeneralNames` cursor, with raw typed-choice elements and `opaque_count` |

All extension/OID/GeneralName cursors have `borrow()` and `position()`.
`GeneralNames.next(budget)` returns `Result<Option<GeneralName>, Error>`.
`GeneralName.element.tag.number` identifies the RFC 5280 choice and its content
is borrowed. RFC822/DNS/URI choices are nonempty IA5, IP addresses have four
or sixteen octets, registered IDs are validated OIDs, directory names use the
Name structure, and otherName/ediPartyName wrappers have their required
shape. `directory_name(budget)` and `registered_id(budget)` return the
corresponding typed values. Name grammar, DNS labels, URI syntax, mail-address
rules, wildcards and hostname matching require separate policy.

X400 ORAddress remains opaque constructed content and is counted by
`GeneralNames.opaque_count`. This counter does not cover every semantic
unknown: otherName's OID-defined value and unknown attribute/algorithm schemas
also require their own processing. Generic ANY values and unknown extension
outer values receive known universal primitive/constructed-form checks and
selected primitive validation. Opaque constructed contents are not walked or
advertised as recursively valid DER.

**`unknown_critical_count == 0` is not a critical-extension validation result.**
Unknown critical OIDs are preserved and counted, not silently marked handled.
A validation layer must recognize and process all critical information it
uses, including unsupported names or semantics inside a recognized extension,
and reject what it cannot process. Merely decoding a helper or counting known
OIDs does not meet that obligation.

## Lifetimes, copies and failures

Keep input backing alive and unchanged while checked objects or cursors are
used. Logical slice starts and stride are preserved, including packed and
strided backing. Values own no storage; copies share bytes. Cursor copies
retain independent positions and pending state. Public nested records and
cursors must come from `parse` or checked helpers and remain unedited. The
API validates external input-view metadata, not arbitrary forged combinations
of nested record fields and subviews.

Cursor errors preserve the cursor position even when shared budget is
consumed. Positions count logical bytes from that cursor's sequence/SET
content; they are separate from root-relative error offsets. EOF is fused.
Helpers never mutate input. `Error` contains `kind`
and a logical `offset` relative to the certificate's retained `encoded` root,
including errors raised in nested helpers. It is not a physical byte address.
Underlying DER errors use kind `Der` and map their local offset into that root.
Other kinds distinguish bounds/input/item/work limits, schema/version/serial,
algorithm/name/validity/SPKI/extension failures, duplicate extensions and
noncanonical fields. The first failure is retained; later placeholder work
does not replace it or read additional input.

## Verification

All three focused gates pass on x86_64 Linux native output from the GPU
compiler. They ran as separate exact driver invocations, producing three
independently compiled strict ELFs and three native processes. Every native
`mmap`, `mremap`, `munmap` and `brk` trace is empty. This establishes the tested
native contracts; user GPU-kernel execution and performance are not claimed.
No compiler, runtime, shader, ABI or proof change is part of this implementation.

[`extended_x509_execution.rs`](../tests/extended_x509_execution.rs) passes
three focused gates:

- An isolated ordinary consumer reads a real certificate and unwraps the
  public APIs without projecting either X.509 error type.
- A host-only structural/mathematical model builds conforming structures and
  independently specified schema failures. It compares all borrowed signed
  bytes, names, algorithms, times, unique IDs and typed extensions; exercises
  long serials/OID arcs, defaults, duplicate/order/shape errors, exact selected
  nested logical error offsets, known universal forms, packed/strided guards,
  copies and positive/negative limits. Synthetic
  signature bytes intentionally do not authenticate, demonstrating that a
  schema result is separate from signature validation.
- Real OpenSSL Ed25519, RSA-2048 and P-256 certificates carry SAN/basic
  constraints/key-usage/EKU values. Independent structure oracles derive
  expected fields from those actual signed encodings. OpenSSL is test setup,
  never a production parser or key backend.

| Exact test | Commands | Elapsed | Log |
| --- | ---: | ---: | --- |
| `ordinary_x509_consumer_does_not_project_errors` | One ordinary consumer | 7.19 s | `x509-ordinary.log` |
| `x509_independent_schema_and_budget_models` | 684 model commands | 7.16 s | `x509-model.log` |
| `x509_real_openssl_algorithms_match_borrowed_models` | Six certificate commands: three algorithms, two layouts | 7.63 s | `x509-openssl.log` |

Logs are under `target/stdlib-work/tls-auth-admission/`. The ordinary driver
build took 1.31 seconds (`build-x509.log`). The final offset-aware driver
refresh took 1.21 seconds (`build-x509-offsets.log`) before the model and
OpenSSL gates. Production source and both Lanius fixtures remained unchanged
across that refresh; only the negative-offset test signal was tightened.

Each exact test used the following bounded command, substituting its name
and corresponding log from the table:

```bash
RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
timeout --kill-after=2s 100s \
  flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s \
  target/stdlib-build/debug/deps/extended_x509_execution-cdd8682ffa29fbb4 \
  --exact TEST_NAME --nocapture --test-threads=1 \
  > target/stdlib-work/tls-auth-admission/TEST_LOG 2>&1
```

Every native run is bounded and traces allocation syscalls. Fixture contracts
also test shared malformed-call depletion, zero-work rejection before a
null-backed body can be read, cursor-budget error atomicity and borrowed alias
identity. The controlled alias probe restores bytes before checked helpers
resume. Independent source review also passed; it is separate from the native
execution evidence above and supplies no trust/path/signature/clock/hostname
validation claim.
