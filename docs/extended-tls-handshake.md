# Borrowed TLS 1.3 handshake wire codecs

`ext::tls_handshake` parses and writes complete TLS 1.3 handshake messages in caller storage. It returns borrowed views, validates nested wire lengths, and allocates no owners. The implementation is [tls_handshake.lani](../extended/ext/tls_handshake.lani).

The wire definitions come from [RFC 8446 section 4 and appendix B.3](https://www.rfc-editor.org/rfc/rfc8446.html#section-4). The known message bytes come from [RFC 8448](https://www.rfc-editor.org/rfc/rfc8448.html). This module establishes wire structure; it does not authenticate a peer or establish a TLS connection.

## Frames and bodies

```lanius
pub enum Error {
    Bounds, Truncated, InvalidLength, UnsupportedType, InvalidValue,
    DuplicateExtension, MissingExtension, BufferTooSmall
}
pub struct Frame {
    kind: u8,
    wire: core::slice::View<u8>,
    body: core::slice::View<u8>
}
pub fn parse_frame(input: core::slice::View<u8>) -> Result<Frame, Error>;
pub fn frames(input: core::slice::View<u8>) -> Result<FrameCursor, Error>;
pub fn write_frame(kind: u8, body: core::slice::View<u8>, output: core::slice::View<u8>)
    -> Result<i32, Error>;
```

Here and below, `Result` and `Option` abbreviate `core::result::Result` and `core::option::Option`. Import `core::result`, `core::slice`, and `ext::tls_handshake`; cursor calls also need `core::iter` and `core::option`.

A handshake frame has a one-byte kind and a three-byte big endian body length. `MAX_BODY` is 16777215. `parse_frame` requires exactly one frame, while `frames` accepts a complete concatenation. `Frame.wire` includes the header; `Frame.body` excludes it. Both preserve the original backing, start, and physical stride.

Frame operations validate framing and known kinds. They do **not** validate body syntax. Call the matching typed parser before using a body as a message. Likewise, `write_frame` writes raw framing around a known kind; typed writers perform the body checks below. This distinction allows a transcript layer to consume the exact original `wire` bytes without rebuilding them.

Supported wire kinds are ClientHello (1), ServerHello/HelloRetryRequest (2), NewSessionTicket (4), EndOfEarlyData (5), EncryptedExtensions (8), Certificate (11), CertificateRequest (13), CertificateVerify (15), Finished (20), and KeyUpdate (24). Other kinds return `UnsupportedType`. The synthetic transcript kind `message_hash` (254) is also rejected; a transcript layer must construct that internal representation itself.

Record fragmentation and message reassembly belong to the caller. `Truncated` rejects an incomplete supplied frame or nested field; it does not retain a partial parser for the next record.

## Typed message API

Every `parse_NAME(body)` requires the complete body, excluding its four-byte header. Every `write_NAME(value, output)` emits the complete frame and returns its byte count. Finished takes an additional `hash_length` argument on both paths. EndOfEarlyData has no value parameter: its parser returns zero and its writer takes only output.

| Type / function suffix | Borrowed fields | Scalar fields |
| --- | --- | --- |
| `ClientHello` / `client_hello` | `random`, `session_id`, `cipher_suites`, `extensions` | — |
| `ServerHello` / `server_hello` | `random`, `session_id`, `extensions` | `cipher_suite: u16` |
| `EncryptedExtensions` / `encrypted_extensions` | `extensions` | — |
| `CertificateRequest` / `certificate_request` | `context`, `extensions` | — |
| `Certificate` / `certificate` | `context`, `entries` | — |
| `CertificateVerify` / `certificate_verify` | `signature` | `algorithm: u16` |
| `Finished` / `finished` | `verify_data` | — |
| `KeyUpdate` / `key_update` | — | `request_update: u8` |
| `NewSessionTicket` / `new_session_ticket` | `nonce`, `ticket`, `extensions` | `lifetime: u32`, `age_add: u32` |

All borrowed fields above have type `core::slice::View<u8>`. Vectors exclude their encoded length prefixes. `cipher_suites` contains consecutive two-byte suite identifiers. `entries` contains encoded certificate entries, and `extensions` contains encoded extension entries.

The codecs enforce their wire domains: hello legacy version `0x0303`, fixed 32-byte random, session ID at most 32, nonempty even cipher-suite bytes, and null legacy compression. Contexts and ticket nonces fit an 8-bit prefix; certificate entry data is nonempty. CertificateVerify allows an empty signature exactly as its grammar permits. KeyUpdate accepts only zero/one. Tickets are nonempty and their lifetime is at most 604800 seconds; zero remains valid.

`parse_finished(body, hash_length)` and `write_finished(value, hash_length, output)` support lengths **32 and 48**, corresponding to the TLS 1.3 SHA-256/SHA-384 suite hashes. They require exactly that many verify bytes and never accept an empty Finished. The connection chooses the expected hash length; parsing these bytes does not verify their MAC.

`ServerHello.is_hello_retry_request()` compares the complete random with the defined HRR value. `hello_retry_random()` returns an independent `[u8; 32]` value for a writer. No separate wire kind represents HRR.

## Extension boundary

All extension lists require complete four-byte entry headers, exact payload lengths, and unique 16-bit identifiers within that list. Duplicate identifiers in different certificate entries are allowed. Unknown identifiers and payload bytes retain their original order and contents.

The typed hello codecs additionally require `supported_versions` (43). Client data must be a complete, nonempty, even version vector containing `0x0304`; server/HRR data must be exactly the selected value `0x0304`. CertificateRequest additionally requires `signature_algorithms` (13), with a complete, nonempty, even two-byte algorithm vector.

**Other extension payload schemas are opaque here.** In particular, this module does not validate extension placement, offered-versus-selected values, key shares/groups, cookies, PSK identities/binders or their ordering, ALPN/SNI contents, early-data eligibility, or extension-specific booleans. A connection or extension processor must perform those checks before accepting the message's meaning.

It also leaves certificate DER/raw-public-key interpretation, chain/trust/hostname policy, signature verification, Finished verification, context uniqueness/echo, session ID echo, HRR sequencing, ticket freshness, and handshake order to later layers. TLS 1.2 and DTLS bodies are outside this API.

## Borrowed cursors and list writers

```lanius
pub struct Extension { kind: u16, data: core::slice::View<u8> }
pub struct CertificateEntry {
    data: core::slice::View<u8>, extensions: core::slice::View<u8>
}
pub fn vectors(input: View<u8>, prefix: u8, minimum: i32, maximum: i32)
    -> Result<VectorCursor, Error>;
pub fn extensions(input: View<u8>) -> Result<ExtensionCursor, Error>;
pub fn certificate_entries(input: View<u8>) -> Result<CertificateCursor, Error>;
pub fn find_extension(input: View<u8>, kind: u16) -> Result<Option<View<u8>>, Error>;
pub fn write_extension(kind: u16, data: View<u8>, output: View<u8>) -> Result<i32, Error>;
pub fn write_certificate_entry(value: CertificateEntry, output: View<u8>) -> Result<i32, Error>;
```

`View` abbreviates `core::slice::View` in this listing. `vectors` takes prefix widths 1, 2, or 3; its nonnegative minimum/maximum must fit that width. It iterates a raw concatenation of prefixed vectors. `extensions` and `certificate_entries` take raw entry lists without an outer vector prefix. `find_extension` validates the entire list before returning a payload; `Some(empty)` remains distinct from an absent extension.

Constructors eagerly validate the entire supplied list before returning a cursor. Every cursor has `borrow()` and `remaining_bytes()`, with one `core::iter::Iterator<T>` implementation:

| Cursor | Item |
| --- | --- |
| `FrameCursor` | `Frame` |
| `VectorCursor` | `View<u8>` |
| `ExtensionCursor` | `Extension` |
| `CertificateCursor` | `CertificateEntry` |

`next` therefore returns an ordinary `Option<T>`. A successful item advances past exactly its encoded bytes. Exhaustion is fused; later pulls return `None` without reading more backing. Cursor value copies fork their local position while sharing the borrowed input; shared references advance the same cursor. Public fields are implementation state, not a resumption format: use the checked constructors.

Certificate entry data is opaque, including for X.509 and raw-public-key encodings. Nested extension lists still receive framing and duplicate checks. The entry writer emits its three-byte data length and two-byte extension-list length; the extension writer emits its two-byte kind and two-byte data length.

## Storage, errors, and cost

All returned fields/cursor items borrow input. Keep that storage alive and immutable for as long as any returned view or cursor uses it. No operation clones data into an owner or assumes cleanup authority. Reusing a receive buffer invalidates all such outstanding borrows.

Logical metadata must have nonnegative start/length with no overflowing sum. The caller must supply physical backing for the claimed range. Writers require destination storage disjoint from every input and retain no destination borrow. They preflight all metadata, field domains, nested list structure/duplicates, body length, and capacity before their first destination write. Every returned error leaves all destination cells unchanged; extra destination cells remain unchanged on success. Parsers and failed cursor constructors leave input unchanged and expose no partial object.

`Bounds` describes malformed view metadata. `Truncated` describes missing encoded bytes. `InvalidLength` covers vector/body constraints and trailing bytes; `InvalidValue` covers fixed field/domain violations. Missing required extensions and duplicates have separate errors. `BufferTooSmall` lets callers retry with larger storage. Other errors are wire-policy failures whose alert/connection handling belongs to the caller.

The cursors hold only a borrowed descriptor and scalar position/terminal fields. Extension validation uses a fixed **1024-word `u64` bitmap (8 KiB)**, cleared once per nonempty list. This cost applies separately to each nonempty nested certificate-extension list as well as top-level lists. Empty lists avoid the clear. Lookup also validates first. No bitmap survives in a cursor.

Frame/vector construction scans entry headers; extension construction also checks duplicate identifiers. Certificate construction checks every entry and nested list. Validation work is bounded by the encoded entries plus 1024 bitmap-word clears per nonempty extension list. Iteration then takes constant work per item. Writers additionally copy their output bytes. The wire maxima bound encodings, while a connection should impose its own practical message/entry/reassembly limits. No path allocates or performs IO.

## Verification

Native admission is pending. The driver is [extended_tls_handshake_execution.rs](../tests/extended_tls_handshake_execution.rs), with [fixtures and the independent Python struct oracle](../tests/fixtures/extended/tls_handshake/). Its scope is Linux x86-64; each gate compiles one strict native ELF and runs one process with an empty `mmap`/`munmap` trace.

| Gate | Scope | Result |
| --- | --- | --- |
| `complete_borrowed_tls13_wire_codecs_execute_without_error_projection` | Typed client/server-HRR writers/parsers, borrowed offsets, generic Take and Frame/Extension cursor use without imported Error projection | Pending |
| `tls13_handshake_frames_bodies_cursors_and_atomic_writers_match_struct_model` | All message bodies, RFC bytes, four layouts, targeted malformed lengths/values, atomic writers and all cursor forms | Pending |

The model uses 34 valid frames, including ten published RFC 8448 trace frames. The capture lists its source URL and retrieved RFC text SHA-256; it does not depend on downloading during tests. The host constructs independent big endian struct encodings and error expectations, then compares actual re-encoded output. It includes zero-length CV signatures, empty certificate lists, session ID boundaries 0/32, 255-byte contexts/nonces, both Finished lengths, and raw unknown extension bytes.

Each valid message also gets a short-destination case. Truncations, trailing bytes, nested vector mistakes, invalid legacy/compression values, duplicate extension IDs, missing requirements, ticket lifetime overflow, invalid KeyUpdate, and unsupported/synthetic kinds receive separate expectations. Four layouts independently select packed/strided input and output, with nonzero starts. Native checks compare untouched source copies, full destination sentinels on failure, guards on success, copied cursor positions, and repeated EOF. The raw framing cases intentionally accept known-kind opaque bodies which typed parsers reject, preserving the documented boundary.

Root runs the serialized gates. Reproduction commands and accepted timings will be recorded after admission; no execution claim follows from source review alone.
