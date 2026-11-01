# Checked Base64 profiles

`core::base64` replaces its four sentinel/fallback APIs with checked operations
over borrowed byte Views. The [increment](library-checked-base64-plan.md)
defines strict standard/URL-safe and padded/unpadded profiles. All five new
library tests, three selected migrated-consumer tests and the 194-case real
program pass on native Linux x86_64. This increment is accepted; the full
library goal stays open.

## API and profiles

```text
Profile = Standard | StandardUnpadded | UrlSafe | UrlSafeUnpadded
Error = Bounds | LengthOverflow | InvalidLength | InvalidByte(i32)
      | InvalidPadding(i32) | NonCanonical(i32) | BufferTooSmall(i32)
encoded_len(input_len:i32, profile:Profile) -> Result<i32,Error>
decoded_len(input:View<u8>, profile:Profile) -> Result<i32,Error>
encode_into(input:View<u8>, output:View<u8>, profile:Profile) -> Result<i32,Error>
decode_into(input:View<u8>, output:View<u8>, profile:Profile) -> Result<i32,Error>
```

All alphabets share A–Z, a–z and 0–9. Profiles fix the remaining symbols and
tail spelling; decoding does not auto-detect them.

| Profile | Symbols 62/63 | Tail policy |
| --- | --- | --- |
| Standard | `+` / `/` | Required `=` padding for a partial group |
| StandardUnpadded | `+` / `/` | No `=` anywhere |
| UrlSafe | `-` / `_` | Required `=` padding for a partial group |
| UrlSafeUnpadded | `-` / `_` | No `=` anywhere |

[RFC 4648 sections 3–5 and 10](https://www.rfc-editor.org/rfc/rfc4648.html)
describe the alphabets, bit grouping, padding and vectors. These explicit
profiles reject whitespace, the other alphabet and nonzero unused bits.
Unpadded modes are application policies; there is no optional padding, MIME
line wrapping or permissive character skipping. This is a byte codec, without
a cryptographic primitive or security claim.

## Counts, bounds and capacity

Successful codec results are written byte counts, not next positions. Output
starts at output.start; indexed errors identify a zero-based position relative
to input.start. BufferTooSmall carries the complete required output count.
Empty input succeeds with zero when metadata is valid.

For encode_into/decode_into, both complete View descriptors are checked
before byte access and all other failures: start/length must be nonnegative and their sum must not overflow i32.
`encoded_len` rejects negative input length as Bounds. Its positive result
must fit i32; otherwise it returns LengthOverflow without accessing storage.

| Encoding policy | Maximum input length | Exact output length |
| --- | ---: | ---: |
| Padded | 1,610,612,733 | 2,147,483,644 |
| Unpadded | 1,610,612,735 | 2,147,483,647 |

These are arithmetic limits, not allocation guarantees. Encoding calculates
required length and checks output capacity before reading or storing bytes.
Decoding validates **all input** before checking output capacity or storing;
malformed input therefore precedes BufferTooSmall. Bounds on either View still
precedes malformed input. Every recoverable error leaves the whole backing
unchanged, including supported input/output aliases.

## Strict decoding order

1. After metadata, padded length must be divisible by four; unpadded length
   must have remainder zero, two or three. Otherwise InvalidLength occurs
   before any byte access.
2. Visit groups and positions from left to right for error selection.
   Unexpected `=` is InvalidPadding(index); an unrecognized alphabet byte is
   InvalidByte(index). Only a padded final group permits positions three/four
   to contain padding.
3. If that group's third symbol is `=`, its fourth must also be `=`. A mismatch
   is InvalidPadding at the third index, without reclassifying the fourth.
4. After validating tail symbols/padding shape, require zero unused bits:
   second sextet's low four bits for one decoded byte, third's low two for two.
   NonCanonical identifies that sextet. Unpadded tails use the same bit rule.

For example, Standard rejects `Zg` as InvalidLength, `Zh==` as
NonCanonical(1), and `Zg=?` as InvalidPadding(2). StandardUnpadded accepts
`Zg` as one byte and rejects its padded form. Error payloads remain relative
to the selected input View, including with a nonzero underlying start.

## Storage, aliases and effects

Shared profile/length/validation engines use O(n) work and constant local
storage, with no allocation, host calls, recursion or cleanup transfer. Success
writes only the returned count of output bytes; no NUL/newline or implicit owner
is added.
Read/validation operations never mutate input.

Encoding walks groups backward and snapshots up to three input bytes before
stores. Decoding walks forward after full validation and snapshots each group
before stores. Same-base operation is supported when the selected first byte
address **and byte stride** match, with sufficient physical output backing.
Disjoint Views can use supported strides and nonzero starts independently.

Other partial overlap is outside the contract, not a detected recoverable
error. Keep claimed backing live, initialized, correctly typed and physically
present. Logical checks do not prove physical length or enforce borrowing.
Native indexing/protection can trap on a physical overclaim; traps have no
rollback guarantee. Caller size limits bound linear work; there is no work quota.

## Migration and consumers

Replace encoded_len_or/decoded_len_or with checked Results, and replace raw
array/length/capacity calls with Views plus an explicit Profile. encode_into
and decode_into retain their names with new signatures/Result types. There
are no fallback aliases or automatic profile selection.

The consumers ext::websocket, ext::websocket_upgrade and
ext::openssl_websocket select Standard explicitly. Ordinary invalid keys
retain their false/Handshake/Key policy. Encoding fixed local nonce or
digest storage checks Result and exact 24/28-byte success before destination
copy; a contradiction is an internal assertion, not a misleading Capacity
error. OpenSSL continues to compute the handshake digest.

The [base64_bytes program](stdlib-base64-bytes.md) reads bounded binary stdin,
validates/converts privately and publishes bounded output with explicit owners
and I/O errors. All four application groups pass 194 cases.

## Evidence and targets

Accepted current codec source is c5eb1fc4; receipts below are separate registered
commands under target/stdlib-work. All are native Linux x86_64 CPU output from
the GPU compiler.

| Receipt | Accepted scope |
| --- | --- |
| checked-base64-admission-first.log | 1 test / 4.46s: four profiles/functions, RFC and URL/unpadded wire, same-base aliases and indexed error |
| checked-base64-direct-first.log | 1 test / 4.25s: four scenarios, 96 literal profile/stride vectors, exact error/length/atomicity checks; admission filtered |
| checked-base64-model-first.log | 1 test / 5.93s: 48,995 independent cases, all profiles/functions and four stride combinations, including 1,600 same-base cases; seed 0xba5e640261102 |
| checked-base64-boundaries-first.log | 2 tests / 8.50s: four profiles, eleven lengths, three layouts, seven pure phases, one exact mapping/protection/release and two physical-overclaim traps101 |
| checked-base64-websocket-contracts.log | 1 selected migrated wire-consumer test / 8.59s; older allocation test filtered |
| checked-base64-websocket-transport.log | 1 scripted transport regression / 12.50s, including the migrated upgrade consumer |
| checked-base64-openssl-accept.log | 1 selected OpenSSL test / 7.03s: 310 cases across two layouts with overlap plus 24 injected atomic failures; one other test filtered |
| checked-base64-bytes-first.log | 4 CLI tests / 8.85s: model100, rejection56, I/O18 and CLI20 = 194 distinct cases |

Both direct processes permit only entry/exit in full syscall traces. The
[direct](../tests/fixtures/stdlib_foundation/checked_base64/README.md),
[independent model](../tests/fixtures/stdlib_foundation/checked_base64_model/README.md)
and [application](stdlib-base64-bytes.md) guides retain exact frozen sources,
commands and limits. The [boundary guide](../tests/fixtures/stdlib_foundation/checked_base64_boundaries/README.md)
records physical storage and trap scope. The selected wire, scripted transport
and real OpenSSL helper tests establish the three migrated consumer call sites;
they do not rerun the broader historical protocol suites.

Current consumer sources are `websocket.lani 9e59e09e`, `websocket_upgrade.lani 3ed64a08`, `openssl_websocket.lani 0e2f9803`.

Earlier standard-padded sentinel receipts in the
[codec overview](stdlib-byte-codecs.md) and [foundation audit](stdlib-foundation.md)
keep their historical source/API scope, as do older broad WebSocket receipts.
User-GPU execution, other targets, automatic ownership/lifetimes and formal
verification need separate evidence. No compiler, extractor, proof or native
ABI change belongs to this increment.

## Focused targets

Run targets separately; fixture guides retain the accepted filters.

```sh
cargo test --test stdlib_base64_execution
cargo test --test stdlib_base64_model_execution
cargo test --test stdlib_base64_boundary_execution
cargo test --test stdlib_base64_bytes_execution
```
