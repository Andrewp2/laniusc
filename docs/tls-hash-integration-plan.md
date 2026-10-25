# TLS hash and cipher-suite integration proposal

**Proposal only; implementation and runtime admission are pending.** This
read-only audit used source checkpoint
`31afe5ab15e21c0b3521e153c837b3f66908e73c` plus the in-progress P-256 group
migration inspected on 2026-10-25. Group negotiation and connection ownership
remain with that milestone's author. Reconcile this plan against its admitted
snapshot before changing code. No source, fixture, compiler, proof, or ABI
work was performed for this proposal.

## Decision

Add `TLS_AES_256_GCM_SHA384` through one explicit hash contract spanning the
schedule, transcript, authentication, records, and connection. Put cipher
suite identity and policy in a light `ext::tls_suite` module. Migrate callers
directly from `tls_record::Suite`; retain no alias or SHA-256 default overload.
No external human compatibility dependency was identified in this audit.

Keep these independent selections separate:

- The negotiated suite chooses AEAD and handshake hash.
- X25519 or P-256 chooses ECDHE encoding and validation. Both current shared
  secrets remain 32 bytes, including with a 48-byte handshake hash.
- The selected signature scheme chooses CertificateVerify signing behavior.
  Retain the current Ed25519 certificate/CV profile for this milestone. RSA
  foundation admission does not automatically add RSA certificates or CV.

The relevant protocol requirements are [RFC 8446 sections 4.4 and
7](https://www.rfc-editor.org/rfc/rfc8446.html#section-4.4). Suite hash controls
transcripts, HKDF, Finished and traffic-secret updates. HRR substitutes a
framed hash of CH1. Application/exporter checkpoints include server Finished;
resumption includes client Finished. CertificateVerify signs its context
and the current transcript hash. This proposal changes their shared hash
plumbing while preserving the existing connection state machine.

## Current coupling found

| Source | Existing SHA-256 assumption | Required migration |
| --- | --- | --- |
| `extended/ext/tls_schedule.lani` | `Secret.bytes[32]`; SHA-256 extract/HMAC; 32-byte zero inputs, hashes and Finished; output cap 8160 | Tagged owned secrets/digests and selected primitive dispatch throughout every phase |
| `extended/ext/tls_transcript.lani` | One `core::sha256::State`; SHA-256 snapshot; 36-byte synthetic HRR frame | Explicit selected hash; owned digest snapshot; synthetic frame active length 36 or 52 |
| `extended/ext/tls_record.lani` | Two-suite enum; saved secret32; every AES key16; SHA-256 KeyUpdate | Shared suite authority; typed secret; AES key16/32 from suite; selected-hash updates |
| `extended/ext/tls_authentication.lani` | Copied secret32; CV input130; Finished32 | Hash agreement at construction; CV input130/146; Finished32/48 |
| `extended/ext/tls_negotiation.lani` | IDs 0x1301/0x1303; two-way implicit fallback | Checked owned suite policy and all three IDs; immutable HRR suite commitment |
| `extended/ext/tls_connection.lani` | Four-byte suite offer; preferred suite used as initial selection; SHA-256 snapshots and zero secrets; export cap8160 | Explicit unselected state, late hash binding, migrated checkpoint/secret types and hash-dependent exporter cap |

`aes_gcm::new` already accepts 16-, 24-, and 32-byte keys. HMAC/HKDF-SHA384
now exist as separate foundations. That does not establish the TLS integration.
The record layer must stop treating `is_aes` as equivalent to key length 16.

## Proposed public contract

Names below are proposed APIs for parent review, not APIs currently available.

### Hash authority: `ext::tls_hash`

```text
enum Algorithm { Sha256, Sha384 }
Algorithm.length() -> i32                       // 32 or 48
struct Digest { algorithm: Algorithm, bytes: [u8;48] }
digest(algorithm, input: View<u8>) -> Result<Digest, Error>
digest_from_view(algorithm, input: View<u8>) -> Result<Digest, Error>
Digest.view(&self) -> View<u8>                   // active prefix only
new(algorithm) -> State
State.algorithm() -> Algorithm
State.update(input: View<u8>) -> Result<i32, Error>
State.snapshot() -> Digest                      // finish a copy
State.borrow() -> &State
```

`Error` is `Bounds`, `InvalidLength`, or `LengthOverflow`. The module uses
the existing core SHA-256 and SHA-384 implementations, with owned inline
algorithm state. It introduces no provider trait, backend, allocation, or
public arbitrary-state restoration. Adopt the existing SHA-256 aggregate
ceiling, `2^61-1` input bytes, as the common wrapper ceiling; no expanded
128-bit public quota is needed for TLS. Updates reject before mutation.

Digest constructors initialize all 48 bytes. SHA-256 owns a canonical zero
tail at bytes 32..48; SHA-384 owns all 48. When converting the core SHA-384
64-byte digest, copy only its active 48 bytes. Never infer the algorithm from
an array width or a supplied byte count. `digest_from_view` validates logical
metadata, then exact selected length, and copies the input. Returned values
retain no source borrow. Snapshot/copy independence requires native tests.

`Digest.view` must borrow a stable `&self` receiver. It must not take a
value-copy receiver or return a view into a temporary receiver's inline
array. The view remains valid only while that same referent stays live,
unchanged, and at the same location. Bind a returned digest to an owned local
before borrowing its bytes; never let a chained temporary's view escape.
Durable results remain owned `Digest` values, not borrowed byte views.

### Suite authority: `ext::tls_suite`

| Variant | Wire ID | Hash | Traffic key | IV/tag |
| --- | --- | --- | ---: | --- |
| `Aes128GcmSha256` | 0x1301 | SHA-256 | 16 | 12/16 |
| `Aes256GcmSha384` | 0x1302 | SHA-384 | 32 | 12/16 |
| `ChaCha20Poly1305Sha256` | 0x1303 | SHA-256 | 32 | 12/16 |

```text
enum Suite { Aes128GcmSha256, Aes256GcmSha384, ChaCha20Poly1305Sha256 }
from_id(id: u16) -> Result<Suite, Error>
Suite.id() -> u16
Suite.hash() -> tls_hash::Algorithm
Suite.key_length() -> i32
Suite.is_aes() -> bool
struct Policy { order: [Suite;3], length: i32 }
policy(ordered: View<Suite>) -> Result<Policy, Error>
validate_policy(policy: Policy) -> Result<i32, Error>
default_policy() -> Policy
```

`Error` is `Bounds`, `Unsupported`, or `InvalidPolicy`. Construction checks
metadata, length 1..3, then duplicate active entries, and copies the order.
Every consumer also validates policy before indexing or writing, since public
implementation fields are not unforgeable credentials. Config constructors
validate policy before ephemeral public-key derivation or caller-buffer writes.
Inactive slots carry
no preference. No view into a temporary policy survives a call.

The proposed default order is ChaCha20, AES128, AES256, retaining existing
first and second preferences while advertising all three. Callers may supply
any unique order or a singleton AES256 policy. The server picks the first
locally permitted offered suite. No implicit fallback may escape the policy.
The client emits exactly its policy order. HRR and final SH must select an
offered suite, and final SH must keep the exact HRR suite, even when another
offered suite uses the same hash. Wire IDs remain descriptive in parsed TLS
messages; convert to `Suite` only through the shared checked factory.

`tls_suite` depends only on `tls_hash` for this mapping; it does not import
the record, schedule, or negotiation modules. This avoids a schedule/record
dependency cycle. Remove `tls_negotiation::record_suite`; migrate callers to
`tls_suite::from_id` instead of adding a forwarding compatibility surface.

### Schedule and record APIs

```text
tls_schedule::Secret { algorithm: tls_hash::Algorithm, bytes: [u8;48] }
secret_from_view(algorithm, bytes: View<u8>) -> Result<Secret, Error>
Secret.view(&self) -> View<u8>
max_output(algorithm) -> i32                     // 8160 or 12240
early(algorithm, psk: View<u8>) -> Result<Early, Error>
no_psk(algorithm) -> Early
expand_label(base: Secret, label, context, output) -> Result<i32, Error>
derive_secret(base: Secret, label, hash: Digest) -> Result<Secret, Error>
finished(base: Secret, hash: Digest) -> Result<Secret, Error>
verify_finished(base: Secret, hash: Digest, received) -> Result<bool, Error>
update_traffic(base: Secret) -> Result<Secret, Error>
tls_record::sealer(suite: tls_suite::Suite, secret: Secret) -> Result<Sealer, Error>
tls_record::opener(suite: tls_suite::Suite, secret: Secret) -> Result<Opener, Error>
```

Unannotated byte parameters above remain `View<u8>`. Add schedule
`HashMismatch`; retain errors for bounds, raw secret construction, labels,
contexts, output, received verify length, and derivation. Remove schedule
`InvalidHashLength`, since the raw digest factory now owns that check. Replace
record/authentication `InvalidSecretLength` with `HashMismatch`, since their
new constructor arguments cannot carry a raw length. Migrate exhaustive Error
matches and negative fixtures with these signatures. Check all caller-view
metadata first, then hash agreement and
semantic limits, before hashing, output writes, nonce use, or state changes.
Raw secret constructors require exact algorithm length and zero the unused
tail. A wrong-length input returns `InvalidSecretLength`; it is not truncated
or silently reinterpreted. `derive_secret`/Finished reject different digest
and secret algorithms. Record construction rejects a different suite hash.

`Secret.view` has the same stable borrowed `&self` contract as `Digest.view`.
An owned parameter/local can be borrowed for an immediate derivation while
it remains unchanged and live; its view must not be returned or retained
beyond that referent. In particular, bind `finished`, `update_traffic`, phase
or constructor results to owned locals before taking views. Typed-secret
APIs must not hide a dangling view into a copied receiver or returned
temporary. Phase/record state copies the owned secret it needs; durable
outputs stay owned.

Keep the phase wrapper names and receiver methods. `Early.traffic`,
`Early.exporter`, `Handshake.traffic`, `Master.traffic`, `Master.exporter`
and `Master.resumption` take `Digest` checkpoints instead of raw hash views.
`Early.binder`, `Early.handshake`, `Early.handshake_no_dhe`,
`Handshake.master`, both exporter `.export` methods and `Resumption.ticket`
derive with the receiver's algorithm. They gain no second hash parameter.
`Early.handshake(shared)` still consumes the actual raw ECDHE input. Its
32-byte X25519/P-256 input must not be padded or truncated to HashLen.

Explicit no-PSK, no-DHE and master zero inputs use 32 or 48 zeros according
to the phase's algorithm. An explicitly supplied empty PSK/shared input
retains its distinct current behavior. Label limits stay 1..249 raw bytes,
and encoded context stays at most 255. Requested output is at most 255 hash
blocks: 8160 or 12240 bytes. All returned secret tails are canonical.

### Transcript and authentication APIs

```text
tls_transcript::new(algorithm) -> State
State.algorithm() -> tls_hash::Algorithm
State.snapshot() -> tls_hash::Digest
tls_authentication::server(transcript: State, server_handshake_secret: Secret,
                           offered_signature_schemes, config) -> Result<State, Error>
```

Transcript `update`, `rewrite_for_hrr`, `messages`, `used_hrr` and `borrow`
keep their signatures and atomic-error semantics. Authentication construction
checks transcript/secret hash equality before making state, copying anchors,
or spending work. It stores the owned typed secret, not a borrowed view or
another independently configurable hash field. Keep existing phase, path,
scratch-retry, poison and getter contracts.

## Late binding and transcript lifetime

Do not hash ClientHello using a preferred-suite guess. The connection should
hold `Option<tls_transcript::State>` and `Option<tls_suite::Suite>` until a
validated selection exists. Phase secrets/master/exporter should likewise be
absent until derived, rather than fabricated SHA-256 zero placeholders.

Use the existing retained CH1 region in `Buffers.hello`. Store its exact
frame length in the Engine; retain both CH1 and CH2 regions under the current
group-migration ownership contract. No full-transcript allocation or parallel
SHA states are needed:

This deferral relies on the current full-DHE, no-PSK/no-0-RTT profile. A later
PSK binder milestone needs its own pre-selection hash handling.

1. Client builds and transmits CH1, retaining its complete immutable frame.
   Its byte/handshake debit occurs once, but transcript hashing is deferred.
2. After SH/HRR negotiation validates the actual suite, initialize that hash
   and feed the retained CH1 exactly once. Charge any selected SHA-384 work
   before this deferred operation; do not spend the handshake-byte quota twice.
3. For HRR, perform the selected-hash rewrite, then append CH2 and final SH.
   Reject a second rewrite or changed final suite. Never rebind after HRR.
4. Server chooses a permitted suite after inspecting CH1, binds that hash,
   and appends CH1 before preparing HRR or SH. It uses the same selected suite
   for all later derivations and record owners.

CH1 must remain immutable until binding/rewrite completes and as long as
`first_offer` still borrows it for CH2 validation. Partial transport ACKs or
RX reassembly reuse must not overwrite either retained hello region.

Failure cleanup must preserve the exact existing fatal-wire/key ordering.
First decide whether an existing pending record prevents a fresh fatal alert;
where permitted, seal the alert with the current sender and spend its nonce
before retiring keys at the existing `forget_keys` point. Do not clear
optional phase state, sender, or receiver early as incidental Option cleanup.
Keep a queued fatal record's backing, remaining offset, action, and
pending-fatal ownership live until acknowledgement or explicit abort, even
after phase secrets are retired. Never replace an existing pending record,
rederive keys to flush it, or replay an acknowledged prefix. Clearing fields
is not secure erasure.

HRR staging needs 52 logical bytes, using active length `4+HashLen`. For
SHA-384 the synthetic header is `fe 00 00 30`; for SHA-256 it stays
`fe 00 00 20`. Stage the selected digest prefix and then hash exactly the
active frame, without zero-tail padding. Preserve the existing count/first
message checks, magic validation, and all-or-nothing replacement.

## Flight, epoch and exporter changes

| Operation | SHA-384 requirement |
| --- | --- |
| Server CertificateVerify | 146-byte signed input: existing 98-byte context/separator prefix plus hash48; Ed25519 signature remains64 |
| Server/client Finished | Verify data48, handshake frame52; compute before appending the own Finished |
| Application/exporter derivation | Use through-server-Finished Digest48, preserving current client/server installation timing |
| Resumption/ticket helper | Through-client-Finished Digest48 and ticket PSK48; connection ticket cache remains disabled |
| Record derivation | Secret48, AES key32, IV12; save all 48 secret bytes for updates |
| KeyUpdate | Next secret48, freshly derived AES256 schedule/IV; sequence reset only after successful replacement |
| Exporter | SHA-384 empty/context hashes, output cap12240; raw context may exceed255 because it is hashed first |

Share one checked CertificateVerify-input helper between the authentication
verifier and server connection builder. Use 146-byte owned staging and active
length `98+HashLen`, with an explicit zero separator at offset97. Keeping the
helper at the authentication boundary avoids differing sender/receiver
constructions. It accepts a tagged Digest, not an arbitrary hash-length flag.
The signature scheme remains independently validated. Do not change Ed25519's
internal hashing or X.509 signature OIDs based on the suite.

Finished parse/write calls receive the selected HashLen. Compare every active
MAC byte; wrong received length rejects before computation. Keep authenticated
distinct from Established: client application release still requires final
client-Finished transport acknowledgement. The larger Finished may fragment;
record boundaries and pending ACKs must not cause early application keys or
plaintext release.

Keep record wire/content/inner limits and the existing AES-GCM 2^24-record
policy for both AES variants. Cache an AES256 `aes_gcm::Key` constructed from
exactly32 derived bytes. Update builds a full replacement secret/key/IV before
committing it. Preserve the last-old-key-record reservation for KeyUpdate,
sender switch after full ACK, receiver switch after authenticated complete
KeyUpdate, generation limits, poison semantics, and no nonce-space cloning.
Post-handshake tickets and KeyUpdate do not extend the handshake transcript.

`Engine.export` keeps its signature but validates the selected algorithm's
output ceiling before work or writes. The exporter secret carries its hash,
survives traffic updates unchanged, and remains unavailable before Established.
EarlyExporter remains a distinct helper type. This change does not enable
PSK/0-RTT, resumption caching or post-handshake authentication.

## Work and storage limits

Keep SHA-256 debits and group tariffs unchanged wherever the executed work is
unchanged. Preserve one cumulative `Limits.max_work`, handshake-byte/record/
control/update counts, negotiation budget, and shared path/signature budget.
Do not replenish budgets at hash binding, HRR, retry, or KeyUpdate. All quota
arithmetic must be checked before multiplication/addition.

For SHA-384, add an explicit source-counted surcharge rather than guessing
that its 48-byte output costs the same as SHA-256. Proposed admission unit:
**16,384 abstract units per SHA-384 compression**. The current
`core::sha512::State.compress` has fixed bounds: up to 2,048 units for 128-byte
loading, 4,096 for 64 schedule expansions, 8,192 for 80 rounds, and 1,024 for
constant/schedule clearing, setup and feed-forward, totaling 15,360 before
rounding. These count conservative source actions, not generated instructions
or elapsed time. Implementation review must check this decomposition against
the final source and include wrapper copying/padding separately in the debit.

Useful exact bounds for composing the selected branch are:

```text
C = 16384
B(n) = ceil((n + 17) / 128)              // fresh SHA384 finalization included
stream update at residue u: floor((u+n)/128) compressions
snapshot: 1 compression if u<112, else2
HMAC(message n, key<=128): 2 seeded pad blocks + B(n) + 1 outer block
HKDF-Expand, r=ceil(output/48):
  2 seeded pad blocks + sum(i=1..r)[B(info_length+1+(i>1 ?48:0)) + 1]
```

Zero-output HKDF does no HMAC. TLS PRKs are48 bytes, so seeded HMAC key setup
does not hash an oversized key. TLS label info is at most514 bytes; each
expand block therefore needs at most five inner plus one outer compression,
and an expansion needs at most `2+6*255` compressions. Add actual empty-hash,
extract, snapshot and context-hash operations from the schedule call tree;
do not charge only the outermost HKDF call. Charge raw context copying/hashing
and output stores linearly as today. New limits are logical resource policy,
without an instruction-count or wall-clock guarantee.

Derive a small checked cost function/table for each connection/authentication
operation before implementation admission. Examples: Finished derives its
key with one expansion block and authenticates hash48; traffic update derives
one new48-byte secret plus separate key32 and IV12 expansions. Late CH1
binding and HRR need their own debit before hashing retained bytes. An
undersized work allowance rejects before hash/output/key mutation; already
spent parser/retry work remains spent. Test exact and one-short allowances
for each new branch. Review AES256's14-round source against existing record
tariffs; preserve them only if their documented conservative allowance covers
the added rounds, otherwise increase only that suite's tariff explicitly.

Pure modules keep inline owned storage and allocate nothing. Hash/secret
records grow to maximum48-byte payloads; core SHA384 state and AES schedules
stay inline. Caller-backed views must remain live and disjoint during writes.
No borrowed view of a local digest/policy/secret may be retained in Engine.
Existing logical record/decrypt/handshake buffer sizes remain sufficient:
record framing is unchanged and the Ed25519 CV frame remains72 bytes; only
its local signed input grows. CH offers grow by at most two bytes. Re-evaluate
checked hello capacity through the normal writer preflight, never raw width
constants. TCP storage allocation uses existing checked element-size paths.

## Caller migration inventory

The direct migration must be one reviewable source change after the group
milestone freeze. Re-run `rg` then; this audit observed:

| Surface | Migration |
| --- | --- |
| `tls_record::{Suite,sealer,opener}` | Move enum references to `tls_suite`; pass owned tagged Secret, not `.view()` |
| `tls_schedule` callers | Supply algorithm to `early/no_psk`; construct Secret/Digest through checked factories; replace `[32]` serializers with active views |
| `tls_transcript` callers | Supply algorithm to `new`; bind `tls_hash::Digest` snapshot instead of `core::sha256::Digest` |
| `tls_authentication::server` | Pass Secret; constructor checks it against transcript; update fixture secret/hash framing |
| `tls_negotiation::choose` | Replace numeric preferred-suite argument with validated owned `tls_suite::Policy`; keep GroupPolicy separate |
| ClientConfig/ServerConfig | Replace `prefer_suite` with `suites: tls_suite::Policy`; migrate every initializer directly |
| `Negotiated.suite`, Sealer/Opener `.suite()` | Return `tls_suite::Suite`; connection group field and entropy API unchanged |
| `tls_tcp` attach/export/negotiated | Signatures stay; migrate transitive Config/Negotiated type imports and validate larger inline engine ownership |
| `sample_programs/library/tls_exchange.lani` | Use owned default suite policy; preserve existing CLI; rebase on the group author's Config migration |

Fixture callers include `tls_schedule/{plain,protocol}`,
`tls_record/{plain,protocol}`, `tls_record_aes/{plain,protocol}`,
`tls_authentication/{plain,protocol}`, `tls_connection/{plain,protocol,controls}`,
`tls_negotiation/plain`, `tls_tcp/peer`, `tls_auth_integration/flight`,
`tls_auth_perf/consumer` and `tls_crypto_perf.lani` under
`tests/fixtures/extended/`. Update their Rust/Python binary protocols, exact
Error matches, oracles and observations where hashes/secrets are serialized.
Keep existing SHA256 RFC8448 anchors byte-for-byte; update representation,
not expected cryptographic values. Update API references and owning guides
only alongside admitted implementation evidence. No shim or old default
constructor is proposed.

## Proposed executable gates

These are planned focused gates; no new test, case count, ELF, or runtime
result is claimed here. Reuse one freshly emitted strict ELF through OnceLock
inside each driver, use packed/strided backing with nonzero starts, and split
exact groups so every root-run gate fits its 60-second inner guard. Record
compiler/source/binary manifests; never reuse a cached Rust driver across
changed compiler/SPV state.

1. **Hash/schedule/transcript oracle.** Extend
   `extended_tls_schedule_execution` with both algorithms, using independent
   Python `hashlib`/`hmac`. Check every phase/label, zero versus empty inputs,
   all 32/48 Finished mismatch positions, exporter contexts above 255, maximum
   255-block output, hash/length mismatches and unchanged sentinels. Preserve
   the existing RFC8448 SHA256 anchors. Check snapshot forks, returned-copy
   mutation, canonical zero tails, HRR52/36, second-HRR rejection and atomic
   overflow. Pure execution must have empty allocation traces.
2. **AES256 record oracle.** Extend `extended_tls_record_aes_execution` with
   SHA384 label derivation and OpenSSL EVP AES256-GCM ciphertext/tag checks.
   Exercise types, padding, size boundaries, nonzero sequences/carry, the
   2^24 cap and reserved update slot. Reject wrong hash/length before output;
   verify owned secret copying, cached key updates, poison and scratch retry.
3. **Authentication flight oracle.** Extend
   `extended_tls_authentication_execution` with a real Ed25519 chain and
   independently generated146-byte CV input/Finished48. Test both HRR and
   ordinary checkpoints, wrong-hash constructor failure, all-byte MAC/tag
   tampering, source-buffer clearing after feeds, shared budget exhaustion,
   scratch retries and withheld getters. Keep signature-algorithm policy
   independent of the selected hash.
4. **Connection byte oracle.** Extend `extended_tls_connection_execution` and
   its external binary peer to select hashlib/HMAC/EVP from actual negotiated
   suite. Force AES256-only on each role, then mixed ordered policies and
   disjoint/duplicate/empty policies. Cover both admitted ECDHE groups,
   ordinary exchange, requested-group HRR and cookie-only HRR. Check changed
   suite after HRR, forged/unoffered0x1302, fragmented48-byte Finished, client
   Finished partial ACK withholding, all traffic epochs, exporter agreement
   before/after KeyUpdate, KeyUpdate partial ACK, alerts and close. Reuse the
   existing SHA256 controls as regressions without multiplying every old
   negative case by every suite/group combination.
5. **Independent TLS implementation.** In the existing TCP/connected-app
   tests, force TLS1.3 `TLS_AES_256_GCM_SHA384` against real OpenSSL in both
   client/server roles and each admitted group. Explicitly configure the TLS1.3
   suite with
   [`SSL_CTX_set_ciphersuites`](https://docs.openssl.org/3.0/man3/SSL_CTX_set_cipher_list/)
   or the corresponding CLI flag; legacy `set_cipher_list` does not select
   TLS1.3 suites. Assert the actually negotiated ID, trust/identity/time checks,
   binary exchange, exporter if exposed, KeyUpdate and orderly shutdown. A
   forced SHA384-only gate must fail rather than silently negotiate SHA256.
   Preserve host deadlines, partial I/O and reached allocation-failure cleanup
   checks in a compact representative adapter workload.

For each gate, publish actual commands/logs, strict ELF/native counts, observed
allocation positions where applicable and elapsed scope only after root
execution. Other targets, user GPU execution, constant-time machine-code
claims and throughput remain unverified. Root reviews this public contract
before implementation; group admission and the tariff review are entry
conditions, not completed work.
