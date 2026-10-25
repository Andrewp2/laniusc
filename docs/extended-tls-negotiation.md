# TLS 1.3 negotiation helpers

`ext::tls_negotiation` validates the meaning of borrowed TLS handshake fields and writes checked
extension lists. It implements a full DHE profile using X25519 (`0x001d`) or secp256r1 (`0x0017`), Ed25519 (`0x0807`),
SHA256, and either AES128GCM (`0x1301`) or ChaCha20Poly1305 (`0x1303`).

The source follows [RFC 8446 sections 4 and
9](https://www.rfc-editor.org/rfc/rfc8446.html#section-4), [RFC 6066 section
3](https://www.rfc-editor.org/rfc/rfc6066.html#section-3), and [RFC 7301 section
3](https://www.rfc-editor.org/rfc/rfc7301.html#section-3). This restricted algorithm profile
does not implement all mandatory algorithms of RFC 8446 section 9.1 and does not claim general
TLS algorithm conformance.

## Migration status

The typed-group negotiation migration is accepted on x86_64 Linux at production
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
| `choose(Offer, preferred_suite, GroupPolicy, &Budget)` | `Decision::Selected(Selection)` or `Decision::Retry(Retry)` |
| `check_server_hello(Offer, ServerHello, Option<Retry>, &Budget)` | Checked normal selection or HRR |
| `check_second_client_hello(first, Retry, second, &Budget)` | Checked CH2 `Offer` |
| `select_alpn(Offer, preferred, required, &Budget)` | Offered protocol or empty optional selection |
| `check_encrypted_extensions(Offer, EncryptedExtensions, required_alpn, &Budget)` | `NegotiatedExtensions` |
| `key_share(Offer, Group, &Budget)` | Canonically validated `Option<KeyShare>` |
| `group_id(Group)` / `group_from_id(u16)` | Typed group / wire-ID conversion |
| `validate_policy(GroupPolicy)` / `default_groups()` | Distinct one/two-group policy / X25519 then P-256 default |
| `record_suite(u16)` | Explicit `tls_record::Suite` mapping |

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
`group` and borrowed `data`. `Selection` contains `suite`, typed `group`, `signature`
and `peer_key`. `Retry` contains `suite`, `requested: Option<Group>` and `cookie`.
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

Ed25519 must appear in signature_algorithms and the effective certificate-signature list. Absent
signature_algorithms_cert falls back to signature_algorithms. Server preference is one of the
two implemented suite IDs; the other is considered only when the preferred suite was not
offered. The server chooses the first group in its policy that the client advertised. If its
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

- `write_client_extensions(GroupPolicy, Option<KeyShare>, server_name, alpn_list, cookie, output, &Budget)`
  emits versions, groups, CV and certificate signature algorithms, key share, and optional
  SNI/ALPN/cookie.
- `write_server_extensions(KeyShare, output, &Budget)` emits TLS 1.3 version and its typed share.
- `write_retry_extensions(Option<Group>, cookie, output, &Budget)` emits version and
  requested group and/or cookie.
- `write_encrypted_extensions(selected_alpn, server_name_ack, output, &Budget)` emits the
  requested acknowledgement and/or one selected protocol.

Client ALPN is a concatenated u8-prefixed list. Selected ALPN is one unprefixed protocol. Empty
optional views omit their extensions; `share=None` emits the required empty
key_share vector. Cookie content is 1–65533 bytes when present; session IDs are 0–32 bytes in
the codec. A one-group client list is 37 bytes with no share, 73 with an X25519 share, or 106
with a P-256 share. A two-group policy adds two bytes. Optional extensions add their
framing and contents. A supplied share must belong to the policy.

Writers validate all metadata, shape, output capacity, resource allowance and semantic inputs
before their first output store. Failures preserve the entire output, including bytes inside its
advertised range. Success changes only the returned prefix; trailing bytes are untouched. Input
views, output and mutable budget must be disjoint. Budget debits can remain after a semantic
error. Capacity failures precede detailed content scanning; malformed metadata precedes
capacity/budget access.

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

## Focused verification

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
