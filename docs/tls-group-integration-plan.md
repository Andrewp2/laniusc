# TLS group integration contract

This is the implemented shared contract for the admitted TLS group migration.
The portable engine and negotiation module support X25519 and secp256r1 ECDHE;
server credentials and CertificateVerify remain Ed25519.
The two SHA256 record suites remain AES128GCM (`0x1301`) and ChaCha20Poly1305
(`0x1303`). Group preference is independent of suite preference.

The wire rules follow [RFC 8446 sections 4.1.4, 4.2.7–4.2.8 and
7.4.2](https://www.rfc-editor.org/rfc/rfc8446.html). There are no compatibility
aliases for the previous X25519-specific records or boolean share setting.

## Negotiation schema

These declarations belong to `ext::tls_negotiation`:

```lani
pub enum Group { X25519, Secp256r1 }
pub struct GroupPolicy { preferred:Group, fallback:core::option::Option<Group> }
pub struct KeyShare { group:Group, data:core::slice::View<u8> }
pub struct Selection {
    suite:u16, group:Group, signature:u16, peer_key:core::slice::View<u8>
}
pub struct Retry {
    suite:u16, requested:core::option::Option<Group>, cookie:core::slice::View<u8>
}
pub enum Decision { Selected(Selection), Retry(Retry) }
```

`group_id(Group)->u16` returns 29 or 23. `group_from_id(u16)` returns
`Result<Group,Error>`; unsupported IDs return `NoGroup`.
`validate_policy(GroupPolicy)->Result<i32,Error>` rejects duplicate entries
with `InvalidExtension`. `default_groups()->GroupPolicy` is X25519 followed by
secp256r1. `Offer` retains its existing descriptive raw vectors and hello;
its `x25519` field is removed. `key_share(Offer,Group,&Budget)` returns
`Result<Option<KeyShare>,Error>` after canonical validation of the hello.
Public `Offer` fields do not become trusted validation tokens.

The migrated functions are:

```lani
choose(Offer, preferred_suite:u16, GroupPolicy, &Budget)->Result<Decision,Error>
check_server_hello(Offer, ServerHello, Option<Retry>, &Budget)->Result<Decision,Error>
check_second_client_hello(Offer, Retry, ClientHello, &Budget)->Result<Offer,Error>
write_client_extensions(GroupPolicy, Option<KeyShare>, server_name:View<u8>,
                        alpn:View<u8>, cookie:View<u8>, output:View<u8>, &Budget)
    ->Result<i32,Error>
write_server_extensions(KeyShare, output:View<u8>, &Budget)->Result<i32,Error>
write_retry_extensions(Option<Group>, cookie:View<u8>, output:View<u8>, &Budget)
    ->Result<i32,Error>
```

The other EE, ALPN and suite helpers retain their signatures. A policy contains
one or two distinct groups. The client writer emits that order and zero or one
share belonging to that policy. Recognized X25519 shares are exactly 32 bytes;
recognized TLS P-256 shares are exactly 65 bytes beginning with `04`.
Compressed SEC1 encodings are rejected at this TLS boundary. Unknown peer
groups remain opaque and cannot be selected. All shares must follow the
supported-groups order, have unique group IDs, and have nonempty data.

The server selects its first policy group present in the client's groups. If
that group's share is absent, it returns `Decision::Retry`, even when a less
preferred mutual group's share is present. It does not silently fall back to
an already supplied share. `Selected` always contains a real peer share;
`Retry` has no fabricated peer key or boolean success discriminator.

An HRR requested group must have been advertised but not shared in CH1. CH2
then contains exactly that one share. Cookie-only HRR has `requested=None`,
requires an existing usable share, and preserves the original share bytes.
CH2 preserves the other RFC-required hello fields and extension history.
There is at most one HRR; final SH pins the retry suite and requested group.
The engine also retains the server's selected group across cookie-only HRR.

## Engine schema and entropy

`ClientConfig` replaces `send_key_share:bool` with
`groups:GroupPolicy, initial_share:Option<Group>`. `ServerConfig` adds
`groups:GroupPolicy`. An initial share must belong to the client policy.
`Negotiated` adds `group:Group`. Constructors and all existing progress,
record, application, close and exporter methods keep their signatures.
The application default uses `default_groups()` and
`initial_share=Some(Group::X25519)`.

`ext::tls_connection` exposes:

```lani
pub struct EntropyLayout {
    length:i32,
    x25519_offset:core::option::Option<i32>,
    p256_offset:core::option::Option<i32>
}
pub fn entropy_layout(policy:GroupPolicy)->Result<EntropyLayout,Error>
```

Invalid policy returns `InvalidConfig`. Random bytes always occupy `[0,32)`.
Slots have canonical order independent of policy preference:

| Enabled groups | Exact length | X25519 slot | P-256 slot |
| --- | ---: | --- | --- |
| X25519 only | 64 | `[32,64)` | absent |
| P-256 only | 64 | absent | `[32,64)` |
| both | 96 | `[32,64)` | `[64,96)` |

`client` and `server` require exactly this many fresh cryptographic OS bytes.
The pure engine accepts raw bytes only with that explicit precondition; the
scripted fixture is the deterministic test seam. Each scalar slot is
independent. X25519 input is never reused as a P-256 scalar after HRR.

When P-256 is enabled, construction first calls its scalar-checked public-key
operation. Scalar zero or scalar greater than or equal to the P-256 order
returns the new `Error::InvalidEphemeralScalar`, before X25519 derivation or
caller-buffer writes. No modular reduction, clamping, deterministic fallback
or group fallback repairs an invalid P-256 scalar. A successful constructor
derives each enabled public key exactly once and copies scalar/public state
inline. HRR uses those cached independent keys. No views into inline fields
escape: retained hellos and shares live in caller-owned hello backing.

The TCP adapter uses `entropy_layout` as the sole slot-layout authority. It
admits at most **eight P-256 candidates total**, including the initial slot,
and at most seven fresh refills of only that slot. Every entropy attempt and
constructor admission remains bounded by the original deadline and shared
HostBudget. Only `InvalidEphemeralScalar` triggers a refill. Other constructor
errors return immediately. Random and X25519 slots stay unchanged on a P-slot
retry. Entropy temporary storage is cleared on every outcome; this is not a
secure-erasure claim. Socket ownership transfers only after successful
construction and the adapter's required post-operation clock check.

## Work accounting

X25519-only construction keeps its existing 1,048,576 work debit. Its shared
secret plus schedule keeps 1,179,648. P-256 public derivation and P-256 shared
secret each reserve **67,108,864 (64 Mi) abstract work units** before the
primitive operation. P-256 shared-secret schedule work adds 131,072. A dual
constructor reserves both public-key tariffs. Policy/layout checks and scalar
rejections have bounded fixed work and perform no point multiplication.

The P-256 tariff comes from the current admitted primitive source, rather
than a measured elapsed-time promise:

- Each scalar multiplication has 256 fixed steps. A step uses 8 field
  multiplications in doubling and 24 in addition (including its exceptional
  doubling), totaling 8,192.
- Encoding costs at most 518 more field multiplications. Uncompressed point
  decoding plus shared-secret affine extraction gives a larger bound of
  8,712 for the complete shared-secret operation.
- A field multiplication has 64 product iterations, 64 reduction iterations,
  44 carry iterations, eight result-copy iterations and bounded normalization.
  Charging 6,144 source operations per multiplication conservatively covers
  these loops, indexing, arithmetic and fixed setup.
- An additional 32,768 per scalar step covers the bounded nonmultiplicative
  field operations, masks, selects and scalar-bit work. Another 65,536 covers
  scalar/point decoding, inversion-loop bookkeeping and result serialization.
  The envelope is `8712*6144 + 256*32768 + 65536 = 61,980,672`, below 64 Mi.

These are conservative admission units, not CPU instructions, a timing bound,
or a compiler constant-time claim. Invalid scalar admission performs only the
32-byte decode and fixed eight-limb range/zero checks; the eight-candidate
adapter cap bounds those rejected admissions separately. No engine is created
for them, and no valid expensive operation is repeated on a rejected candidate.
The default engine work allowance must cover dual construction and the
selected group exchange plus the existing certificate/record work.

## Preserved boundaries and focused admission

P-256 shared secret uses its exact 32-byte big-endian x coordinate, including
leading zero bytes. TLS validates exact uncompressed shape before invoking
the primitive, which checks coordinates/on-curve membership before scalar
multiplication. X25519 retains its existing all-zero shared-secret rejection.
P-256 ECDHE does not enable ECDSA certificates or signatures.

Client Finished must still fully drain under the handshake key before client
Established/publication. Server Established still requires verified client
Finished. One pending sealed record retains its exact acknowledgment cursor;
no resealing, nonce rollback or concurrent copied-engine use is introduced.
Record-end epoch changes, KeyUpdate final-slot reservation, half-close,
sticky fatal failure, hard session budgets, shared path signature budgets and
borrowed configuration lifetimes retain their accepted contracts.

Focused source migrations cover negotiation's independent wire model and
ordinary consumer; both groups and both suites in the engine pair oracle;
requested-group and cookie-only HRR; malformed/compressed/off-curve shares;
policy/entropy/scalar/work boundaries; source lifetime and pending-ACK guards.
Existing X25519 cases explicitly select the X-only policy and retain their
64-byte entropy/tariff meaning. TCP/application callers migrate directly in
their owner's change. No primitive, compiler, ABI, proof or runtime changes
belong to this milestone.

## Accepted portable admission

Root admitted negotiation production `3f089664` and engine `eaf51c4c` on x86_64
Linux through separately serialized exact gates. Negotiation checked 1,540 wire
commands plus 72 quota probes (1,612 total), ordinary six flows, four strict
ELFs/30 native processes and empty allocation traces. The engine checked 114
scripted cases plus its ordinary consumer across six ELFs/six native processes.
Three engine processes had empty allocation traces; three intentionally owned
one exact 3,520,000-byte caller arena each with matching address/size release.
Final pair oracles independently compare both published group IDs with policy
and actual wire selection. Source/fixture review was clean.

See [negotiation evidence](extended-tls-negotiation.md#focused-verification) and
[engine evidence](extended-tls-connection.md#admission-status) for exact gates,
versions, runtimes and logs. Those guides separate the earlier offers model,
equality-only publication witness and CPU helper-caller omission from final
accepted receipts. No production fix was required during these gates.

The TCP adapter and application have their own OS entropy/deadline, ownership
and interoperability receipts; this plan does not replace those guides. The
selected profile retains Ed25519 credentials and SHA256 suites. P-256 ECDHE
alone does not add ECDSA/RSA authentication, SHA384 suites, resumption, early
data, mutual authentication or general TLS/PKIX conformance. Work tariffs are
conservative source-operation admission units; these tests establish no
constant-time generated-code or elapsed-time guarantee.
