# TLS 1.3 negotiation helpers

`ext::tls_negotiation` validates the meaning of borrowed TLS handshake fields and writes checked
extension lists. Its full DHE profile uses X25519 (`0x001d`) or secp256r1
(`0x0017`), explicit proof/certificate signature policies, and an explicit shared
suite policy: AES128GCM/SHA256 (`0x1301`), AES256GCM/SHA384 (`0x1302`), or
ChaCha20Poly1305/SHA256 (`0x1303`).

The source follows [RFC 8446 sections 4 and
9](https://www.rfc-editor.org/rfc/rfc8446.html#section-4), [RFC 6066 section
3](https://www.rfc-editor.org/rfc/rfc6066.html#section-3), and [RFC 7301 section
3](https://www.rfc-editor.org/rfc/rfc7301.html#section-3). This restricted algorithm profile
does not implement all mandatory algorithms of RFC 8446 section 9.1 and does not claim general
TLS algorithm conformance.

## Migration status

The signature-policy integration is accepted on x86_64 Linux at production
`bf0f259f`. All four gates passed in one invocation. It removes synthetic
signature selection from ServerHello and uses explicit `signature::Policy`
values for proof and certificate permission. The earlier
shared-suite/SHA384 migration was accepted on x86_64 Linux at production
`b3044892`. All four gates passed in one invocation with empty allocation traces.
Source and focused fixtures use `tls_suite` as the single suite authority and
migrate callers directly, with no old suite-mapping alias. Current and earlier
pinned receipts are recorded separately below.

The typed-group negotiation migration was accepted on x86_64 Linux at production
`3f089664`. Its four focused exact gates passed with empty allocation traces.
The exact shared schema, entropy and HRR contract is in
[the integration plan](tls-group-integration-plan.md). Internal callers migrated directly;
there are no X25519-specific compatibility aliases. This receipt covers negotiation
helpers; the engine and transport have their own admission evidence.

## API

| Operation | Result |
| --- | --- |
| `budget(Limits { max_message, max_work })` | `Result<Budget, Error>` |
| `inspect_client_hello(ClientHello, &Budget)` | Validated `Offer` |
| `choose(Offer, tls_suite::Policy, GroupPolicy, &Budget)` | `Decision::Selected(Selection)` or `Decision::Retry(Retry)` |
| `check_server_hello(Offer, ServerHello, Option<Retry>, &Budget)` | Checked normal selection or HRR |
| `check_second_client_hello(first, Retry, second, &Budget)` | Checked CH2 `Offer` |
| `select_alpn(Offer, preferred, required, &Budget)` | Offered protocol or empty optional selection |
| `check_encrypted_extensions(Offer, EncryptedExtensions, required_alpn, &Budget)` | `NegotiatedExtensions` |
| `key_share(Offer, Group, &Budget)` | Canonically validated `Option<KeyShare>` |
| `signature_policy(Offer, signature::Use, &Budget)` | Owned recognized proof/effective-certificate policy |
| `group_id(Group)` / `group_from_id(u16)` | Typed group / wire-ID conversion |
| `validate_policy(GroupPolicy)` / `default_groups()` | Distinct one/two-group policy / X25519 then P-256 default |
| `tls_suite::from_id(u16)` | Shared checked suite conversion (separate module) |

`Budget.borrow()` supplies the shared reference. Default limits are 262144 logical field bytes
and 16777216 abstract work units. `max_message` limits each prepared stage's aggregate logical
fields; it does not sum repeated stages or represent the encoded frame size. For example, SH
checking first inspects CH under that cap and then caps the SH fields separately. `max_work` is
shared across all stages of the operation. No host calls or allocations occur.

`Offer` retains `hello`, decoded groups/signature lists, raw key shares, SNI, ALPN
and cookie views. Its fields describe the parsed offer. Consuming functions derive the fields
again from `Offer.hello`; fabricated descriptive fields cannot authorize a selection. The caller
must keep all backing alive and immutable. Copying an Offer copies borrowed descriptors, with no
ownership transfer or independent backing. Physical array backing and disjoint mutable
budget/output storage are manual contracts.

`Group` is `X25519` or `Secp256r1`. `GroupPolicy` contains `preferred` and
`fallback: Option<Group>`; repeated groups are invalid. `KeyShare` contains a typed
`group` and borrowed `data`. `Selection` contains only `suite`, typed `group`
and `peer_key`; ServerHello selects no signature scheme. `Retry` contains `suite`, `requested: Option<Group>` and `cookie`.
`requested=None` denotes cookie-only HRR. `Decision` distinguishes the two results;
there is no placeholder peer key or retry boolean in a successful selection. Cookies
are unprefixed content, not the encoded u16 length. `NegotiatedExtensions` contains
one unprefixed ALPN view and `server_name_ack`.

Errors distinguish metadata bounds, input/work limits, nested codec failures,
malformed/missing/duplicate extension data, unsupported features, absent implemented
suite/group/signature, unoffered selections, session mismatch, retry/CH2 violations, ALPN/SNI
violations, and insufficient writer output capacity. A syntactically valid offer without an
implemented algorithm is accepted by inspection and rejected by selection. Budget already spent
by earlier stages remains spent after a later failure.

## ClientHello and server selection

ClientHello requires TLS 1.3 supported_versions, nonempty supported_groups and
signature_algorithms, and key_share. A missing-share attempt uses a present **empty key_share
vector**. Groups cannot repeat. Shares cannot repeat, must belong to supported_groups, and must
follow its relative order. Membership/order validation advances one group cursor, avoiding a
shares-times-groups search. X25519 shares must contain 32 bytes. P-256 shares must contain exactly 65 bytes with
prefix `04`; compressed SEC1 points are rejected. This module validates wire shape; the
engine calls the P-256 primitive to validate the actual point before scalar multiplication.
Other groups remain opaque and cannot be selected by this profile.

Suite/group selection is independent of credential permission. A valid hello
without Ed25519, or even without a locally supported signature ID, can select
a suite/group. A credential/authentication consumer separately decides whether
it can satisfy the actual proof and certificate policies.

Server preference is an owned `tls_suite::Policy` with one to three distinct
active entries. Selection revalidates the public policy and chooses its first
offered entry. A singleton does not permit fallback to another implemented suite.
The shared default orders ChaCha20, AES128, then AES256. Invalid empty, duplicate
or oversized policies reject; inactive slots grant no authority. The server
chooses the first group in its policy that the client advertised. If its
share is absent, selection returns a requested-group HRR even when a less preferred
mutual group already has a share. Group preference does not depend on suite preference.

Unknown ClientHello extension types are ignored after complete framing and duplicate-ID
validation. A well-framed psk_key_exchange_modes extension (45) alone is accepted and ignored;
it grants no PSK selection. Actual pre_shared_key (41), early_data (42), raw certificate-type
negotiation (19/20), and post-handshake authentication (49) are explicitly unsupported.
oid_filters (48) is misplaced in CH. Padding bytes must be zero. Unknown
signatures/groups/suites remain offers, never selected unsupported algorithms.

SNI validates ServerNameList framing, uniqueness of every name_type, and nonempty
length-prefixed names. Host type zero uses ASCII LDH labels, at most 253 bytes, no wildcard,
final root dot, NUL or IP literal. Opaque unknown name types do not authorize a host-name
acknowledgement. This is an SNI transport policy; service_identity separately accepts an
optional DNS root dot and explicitly typed numeric DNS references. No IDNA mapping or DNS lookup
is performed. ALPN protocols are opaque nonempty 1–255-byte strings; the concatenated
u8-prefixed list is bounded and fully scanned. Duplicate ALPN strings are permitted.

## HRR, CH2 and EncryptedExtensions

ServerHello checks session echo, offered implemented suite, selected TLS 1.3 version, one
offered implemented-group share, and extension placement. HRR admits only supported_versions, cookie and
requested key_share. A requested group must be offered and not already shared. A second HRR,
empty/no-change HRR, or unsupported request is rejected. Cookie-only HRR requires a nonempty
cookie and an existing implemented-group share, so this profile can finish without a second retry. Initial
CH cookies are rejected.

CH2 must retain random, session and cipher-suite bytes, and every unchanged extension's data and
relative order, including unknown extensions. A requested key_share changes only that
extension's payload, retaining its position among unchanged extensions; its replacement contains
exactly one requested share. The cookie echoes exactly. Padding may change, move, appear or
disappear. Cookie may be inserted. Cookie-only retry preserves the key-share payload too.

After HRR, call `check_second_client_hello` before accepting the final SH; supply the resulting
CH2 Offer and `Some(Retry)` to `check_server_hello`. The final SH must retain the retry
suite/group. Local checks also require current CH cookie equality with the supplied Retry,
reject cookies with `None`, and reject another HRR. These checks do not prove transcript
history: the connection engine must enforce message order, retain CH1 and the validated HRR, and
apply CH2 comparison. The module does not rewrite transcripts or control encryption epochs.

EE allows SNI acknowledgement, ALPN and informational supported_groups only. Responses require
the corresponding client offer; SNI acknowledgement is empty and requires a recognized offered
host. ALPN contains exactly one offered protocol. A nonempty `required_alpn` must match exactly
and cannot be absent. Server groups are fully framed/unique but need not be a subset of client
groups (RFC 8446 section 4.2.7). Unsolicited, misplaced and unsupported server extensions are
fatal; early-data/PSK acceptance is never ignored. All extension framing is checked before
publication of success.

## Atomic extension writers

All four writers return the length of a **raw extension list**, with no outer u16 list prefix.
The existing `tls_handshake` ClientHello/ServerHello/EE writers add their enclosing lengths.

- `write_client_extensions(GroupPolicy, proofs: signature::Policy, certificates: Option<signature::Policy>, Option<KeyShare>, server_name, alpn_list, cookie, output, &Budget)`
  emits versions, groups, explicit proof signatures, optional certificate signatures,
  key share and optional SNI/ALPN/cookie.
- `write_server_extensions(KeyShare, output, &Budget)` emits TLS 1.3 version and its typed share.
- `write_retry_extensions(Option<Group>, cookie, output, &Budget)` emits version and
  requested group and/or cookie.
- `write_encrypted_extensions(selected_alpn, server_name_ack, output, &Budget)` emits the
  requested acknowledgement and/or one selected protocol.

Client ALPN is a concatenated u8-prefixed list. Selected ALPN is one unprefixed protocol. Empty
optional views omit their extensions; `share=None` emits the required empty
key_share vector. Cookie content is 1–65533 bytes when present; session IDs are 0–32 bytes in
the codec. With singleton proof and certificate policies, a one-group client list is
37 bytes with no share, 73 with an X25519 share, or 106 with a P-256 share. More
generally its base length is `25 + group_bytes + 2*proof_count`, plus
`6 + 2*certificate_count` when extension 50 is present, and `4 + share_length`
when a share is present. A two-group policy adds two bytes. Optional extensions add their
framing and contents. A supplied share must belong to the policy.

Writers validate all metadata, shape, output capacity, resource allowance and semantic inputs
before their first output store. Failures preserve the entire output, including bytes inside its
advertised range. Success changes only the returned prefix; trailing bytes are untouched. Input
views, output and mutable budget must be disjoint. Budget debits can remain after a semantic
error. Capacity failures precede detailed content scanning; malformed metadata precedes
capacity/budget access.

## Independent proof and certificate policies

The shared `signature::Policy` owns four u16 slots and an active length of 1–4.
Proof defaults are `0807,0403,0804`; certificate defaults add `0401`. Local
policies are validated for their intended `signature::Use` before writer stores:
unknown IDs, duplicate active IDs, forbidden-use IDs and invalid lengths reject
with negotiation `NoSignature`. Inactive slots grant no permission. This module
classifies IDs through the shared signature boundary; it implements no verifier
or signer and makes no leaf-key compatibility or trust decision.

`certificates=None` omits extension 50. Its effective certificate list is then
extension 13's actual list, as required by [RFC 8446 section
4.2.3](https://www.rfc-editor.org/rfc/rfc8446.html#section-4.2.3). With extension 50
present, certificate permission comes exclusively from that list; proof
permission never fills a missing certificate algorithm. PKCS#1 SHA256 (`0401`)
can be certificate permission, including via fallback, but cannot authorize a
CertificateVerify proof.

`signature_policy(offer,use,budget)` re-parses `offer.hello` rather than trusting
its descriptive views. It scans the appropriate effective list, retains
recognized/use-appropriate IDs in peer order, ignores unknown or forbidden-use
IDs, and collapses recognized duplicates. Empty recognized output returns
`NoSignature`. A successful result owns its four slots, with a zero inactive
tail; later descriptive Offer changes cannot alter it. Both signature extension
bytes, including extension-50 presence, remain immutable across HRR/CH2.

The helper retains canonical inspection's charges and reserves another
`8 * effective_list_bytes + 32` abstract units before its bounded scan. At most
four recognized IDs exist in the implemented dispatch matrix; duplicate collapse
compares against at most those four owned slots. Failure can retain earlier
budget charges, but returns no partial policy. No cryptographic operation or
allocation occurs.

## Work and lifetime bounds

Operations precharge conservative linear work before content scans, including fixed duplicate
bitmaps. Initial inspection charges `8 * aggregate_field_bytes + 4096`; other operations add
their own bounded scan charges and may inspect the offer again. Every shared debit checks before
subtraction. A failed debit leaves that debit unspent, without restoring successful earlier
debits. This is an abstract work allowance, not a deadline or exact instruction count. Budget
copies fork an allowance; share the same borrowed instance to enforce one allowance across
stages. Concurrent mutation requires external synchronization.

The implementation uses stack bitmaps (8 KiB each) for bounded u16 domains and performs no
allocation. Valid returned views remain borrowed and require immutable backing through their
last use. Inputs with valid logical metadata but insufficient physical storage violate the
manual backing contract.

## Current verification scope

The ordinary six-flow fixture retains an explicit two-suite SHA256 policy and
now emits the shared proof/certificate defaults, then inspects their owned
policies through the new helper. The
independent offer model adds singleton SHA384, all three ordered suites, both
server preference orders, invalid policies and disjoint/no-fallback cases. It
retains valid ordered X/P share pairs and reversed-share rejection. The server
model adds SHA384 normal and HRR selections, cross-hash and same-hash suite
changes after HRR, and CH2 history checks. The writer model remains the same
extension-list contract; cipher-suite lists belong to the enclosing hello codec.

`protocol.lani` transports all three active policy entries and the active length;
the Python peer selects from its own policy/list intersection. All returned
views, source bytes, guards and existing exact/one-less work probes remain
checked. The four Rust filters retain their names listed below. New focused cases check
full owned policy arrays (including inactive zeros), use separation, peer-order
deduplication, unknown IDs, PKCS#1 certificate-only permission, extension-50
omission/fallback, forged descriptive Offer fields, and valid no-Ed selection.
Exact extension bytes and full output guards cover local invalid policies and
independent proof/certificate orders. HRR cases preserve or deliberately alter
each signature list and extension-50 presence. The helper cases lead the offer
model so exact/one-less replay covers canonical rescanning plus policy scanning.
## Signature-policy admission

All four filters passed in one unfiltered invocation in **18.81 s**, with the
shared signature Policy helpers present. The ordinary consumer retained six
SHA256/two-suite flows while exercising the new explicit signature defaults.
The independent protocol supplied the broader policies and negative cases.

| Gate | Wire commands | Exact/one-less probes | Native processes |
| --- | --- | --- | --- |
| Atomic writers | 382 | 24 | 7 |
| Client offers | 752 | 24 | 13 |
| Server / HRR / CH2 / EE | 634 | 24 | 11 |
| Ordinary consumer | Six flows | — | 1 |

This is **1,768 wire commands plus 72 budget probes (1,840 commands), and six
ordinary flows**. The driver batches model commands in groups of 64 and runs
each gate's 24 probes in one additional process: `ceil(382/64)+1`,
`ceil(752/64)+1` and `ceil(634/64)+1`. Including the ordinary consumer gives
**32 native processes**. Every process has an empty mmap/mremap/munmap/brk trace.
One protocol ELF is shared by `OnceLock` across the three model filters; the
ordinary consumer compiles the second strict ELF. No runtime test was repeated.

The executed source/test inputs retained their frozen full SHA256 hashes:

| File | SHA256 |
| --- | --- |
| `extended/ext/tls_negotiation.lani` | `bf0f259f2f00e1785ddf10c68131e2cbbcee38ddd8ee4dfc9a62e5abfcf32a94` |
| `tests/extended_tls_negotiation_execution.rs` | `81692627a1f780e816d3e62b85ff323e91253150c44fd38f370af2b14f592afb` |
| `tests/fixtures/extended/tls_negotiation/model.py` | `a0cf754fb992f2e699d940b58e5454f2dac7b98444ee8f1f4535b7cf28f2bbd4` |
| `tests/fixtures/extended/tls_negotiation/protocol.lani` | `df7eff1cbfe4fe23cb0ae069045901cddee155d67867d8528501327565ecaf93` |
| `tests/fixtures/extended/tls_negotiation/plain.lani` | `1fea52ce5e0e61fc0fdc3c0bd55d06ea4fdbe937ba8e0b0ed589d0c180f54e58` |

Root's fresh Rust build passed in **1.15 s**. Evidence under
`target/stdlib-work/` is `tls-signature-negotiation-build.log` and
`tls-signature-negotiation-first.log`. The binary was
`target/stdlib-build/debug/deps/extended_tls_negotiation_execution-b5ff2330e3937816`.
All four filters ran together with no filtered-out test. There was no failed
signature-policy negotiation gate or source change during admission.

Root performed compiler/native execution. Author-side checks were Python AST
parsing, targeted Rust formatting and static/whitespace review; the author ran
no Cargo, GPU/compiler, native or oracle process. These receipts cover the
negotiation helper boundary. Certificate validation, proof verification and
connection/transport acceptance have their own contracts and gates. Earlier
receipts below remain evidence only for their pinned historical inputs.

## Earlier SHA384 admission

All four gates passed in one unfiltered invocation, **13.14 s**, against production
`b3044892`, driver `da50c181`, model `2cdb56b6`, protocol `d922cf63` and ordinary
fixture `0cf50bed`. The ordinary filter's `two_suites` name accurately describes
its six retained SHA256 flows; the protocol model supplies the new three-suite
policy and SHA384 coverage.

| Gate | Commands / flows | Native processes |
| --- | --- | --- |
| Atomic writers | 338 wire commands + 24 exact/one-less probes | 7 |
| Client offers | 666 wire commands + 24 exact/one-less probes | 12 |
| Server / HRR / CH2 / EE | 616 wire commands + 24 exact/one-less probes | 11 |
| Ordinary consumer | Six flows | 1 |

The total is **1,620 wire commands plus 72 quota probes (1,692 commands), and the
six-flow ordinary consumer**. The protocol's `OnceLock` shares one strict ELF
across its three gates; the ordinary consumer compiles a second ELF. There are
31 native processes, all with empty mmap/mremap/munmap/brk traces. This is one
whole-target run, two compiled ELFs and 31 processes, not four compilations.

Root's joint engine/negotiation Rust build passed in 1.24 s. Evidence under
`target/stdlib-work/`:

- `tls-sha384-negotiation-first.log`;
- `tls-sha384-engine-negotiation-build-first.log`.

Runtime used `RUST_MIN_STACK=16777216`,
`LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000`, `LANIUS_DEBUG_STAGE_ERRORS=1`, a 100 s
outer timeout, 35 s lock wait and 90 s inner timeout. Binary
`target/stdlib-build/debug/deps/extended_tls_negotiation_execution-b5ff2330e3937816`
received `--nocapture --test-threads=1`, with no filter or skips. No migrated
negotiation gate failed. Root performed compiler/native admission; author-side
checks were Python AST parsing, targeted Rust formatting and static/whitespace
review. No author-side Cargo, GPU/compiler, native or oracle execution occurred
for this migration. These helpers validate negotiation fields; authentication,
connection and transport retain their separate contracts and evidence.

## Earlier SHA256 typed-group verification

The typed-group gates passed in four separate exact invocations, compiling four
strict x86_64 Linux ELFs and running 30 native processes, all with empty
`mmap/mremap/munmap/brk` traces. The model gates checked **1,540 wire commands
and 72 exact/one-less quota probes (1,612 total)**; the ordinary gate exercised
six flows. Production remained `3f089664` throughout.

| Gate | Commands / flows | Native processes | Runtime |
| --- | --- | --- | --- |
| Ordinary consumer | Six streams | 1 | 9.55 s |
| Final offers model | 616 commands + 24 quota probes | 11 | 12.10 s |
| Server / HRR / CH2 / EE | 586 commands + 24 quota probes | 11 | 12.01 s |
| Atomic writers | 338 commands + 24 quota probes | 7 | 11.74 s |

The final offers receipt uses model `37c50e14`. The server and writer receipts
used `9d6dabe3`; their case-generation and expectation functions did not change
in the later offers-only revision. The protocol is `af0f5233`, ordinary fixture
`5d7d299c`, and Rust driver `6d936699`. The earlier two-target Rust build took
1.70 s (`group-build-first.log`); the frozen joint four-target build took 1.75 s
(`group-build-frozen.log`). The binary is
`extended_tls_negotiation_execution-b5ff2330e3937816`.

Current coverage includes both group orders, strict preference with a missing
preferred share, P-only and dual policies, duplicate policies, exact P-256 wire
shape, requested-P HRR/CH2, final retry pins, canonical typed share lookup and
writer capacities. Actual valid two-share X/P offers in both supported-group
orders are paired with reversed, otherwise valid share lists. Both server
preference orders and lookup of each returned key are checked. The independent
protocol hashes the actual returned views and preserves all input/guard bytes.

Logs are under `target/stdlib-work/tls-connection-admission/`:

- `group-negotiation-ordinary-first.log`;
- `group-negotiation-offer-multishare.log`;
- `group-negotiation-retry-first.log`;
- `group-negotiation-writers-first.log`.

The original migrated offers model (`9d6dabe3`) also passed 576 commands plus
24 probes in 11.55 s (`group-negotiation-offer-first.log`). Review then added the
valid two-share/reversed-order cases, adding 40 layout commands. This was a
coverage improvement, not a failed gate or production fix; the 616-command
receipt above admits the final offers model. Root performed all serialized
compiler/native runs. Author-side checks were Python syntax parsing, targeted
Rust formatting and whitespace/static review; the author ran no test process.

### Earlier X25519-only receipts

The earlier X25519-only four focused gates passed on x86_64 Linux in **four separate exact invocations**, each
compiling a strict ELF. The accepted evidence comprises four ELFs and 25 native processes, all
with empty allocation traces. This is not a single full-suite invocation.

| Gate | Commands / flows | Native processes | Runtime |
| --- | --- | --- | --- |
| Ordinary consumer | Six streams | 1 | 8.98 s |
| Offers model | 414 commands + 24 budget probes | 8 | 10.91 s |
| Server / HRR / CH2 / EE model | 534 commands + 24 budget probes | 10 | 11.09 s |
| Atomic writers model | 274 commands + 24 budget probes | 6 | 11.04 s |

The revised model gates executed 1294 commands/probes in 24 native batches. The ordinary
consumer used the earlier driver build, with the same frozen production and plain fixture. Its
fresh Rust build took 1.23 s; the revised witness driver build took 1.35 s, and its rustfmt
check passed. The author ran only CPU oracle preparation; root serialized compiler/native
admission.

Evidence lives in `target/stdlib-work/tls-connection-admission/`:

- `build-negotiation.log` and `negotiation-ordinary.log`;
- `build-negotiation-witnesses.log`;
- `negotiation-offers-witnesses.log`;
- `negotiation-server-witnesses.log`;
- `negotiation-writers-witnesses.log`.

An earlier length-only offers protocol passed 414 model commands and 24 budget probes in 10.15
s. Review then identified missing returned-view byte witnesses and an unreachable actual-cookie
prior check. The revised protocol adds full SHA256/hashlib witnesses and manual-Offer history
cases; the earlier receipt is retained as history and does not admit the revised protocol.
Production and the ordinary fixture did not change.

`tests/extended_tls_negotiation_execution.rs` contains four separately selectable gates:

- `tls_negotiation_ordinary_two_suites_and_retry_consumer`: six ordinary flows, both suites with
  direct, requested-share HRR and cookie-only HRR, without Error projections.
- `tls_negotiation_client_offer_wire_model_and_limits`: deterministic independent Python
  wire/label/set model; implemented/unimplemented algorithms, signature fallback, ordered
  shares, duplicate/framing errors, SNI/opaque ALPN, layouts, copied descriptors and resource
  errors.
- `tls_negotiation_server_retry_second_hello_and_encrypted_extensions`: offered selections,
  misplaced/unsolicited extensions, HRR no-op/repeat rules, CH2 invariants including moved
  key_share, cookie echo, SNI/ALPN response semantics.
- `tls_negotiation_atomic_extension_writers_and_guards`: independent wire encoding, all-byte
  output/guard snapshots, invalid inputs/capacity/work, and no mutation on rejection.

The Python model constructs and interprets wire vectors with independent `struct`, set/order,
regex and IP-address operations. It is test orchestration, not a library backend. Both native
strided and packed byte layouts use nonzero offsets. The native protocol asserts every
input/guard byte remains unchanged. Every writer case compares all 1024 output/guard bytes.
Actual returned peer-key/cookie/SNI/ALPN views carry full SHA256 witnesses checked against
independent Python hashlib outputs, so equal-length wrong offsets/backing are observable. A
manual Offer with a real CH cookie and a forged descriptive cookie exercises
matching/mismatching prior checks and canonical hello authority. Successful samples are replayed
with exactly their observed total work allowance and one less; this checks shared-stage
exhaustion without freezing incidental costs. Every native process is traced for
mmap/mremap/munmap/brk and must show no allocation.

Root performed serialized admission with the following command shape, substituting each exact
gate name from the list above. The revised runtime binary is
`target/stdlib-build/debug/deps/extended_tls_negotiation_execution-b5ff2330e3937816`:

```sh
RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
  LANIUS_DEBUG_STAGE_ERRORS=1 \
  timeout --kill-after=2s 100s flock -E 75 -w 35 \
  target/stdlib-work/library-gpu.lock timeout --kill-after=2s 60s \
  target/stdlib-build/debug/deps/extended_tls_negotiation_execution-b5ff2330e3937816 \
  --exact tls_negotiation_ordinary_two_suites_and_retry_consumer \
  --nocapture --test-threads=1
```

Cargo uses `CARGO_TARGET_DIR=target/stdlib-build CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0
CARGO_PROFILE_TEST_DEBUG=0`. GPU compilation is compiler execution; behavior of user GPU kernels
is unverified. These helpers alone do not constitute a TLS connection or peer authentication.
