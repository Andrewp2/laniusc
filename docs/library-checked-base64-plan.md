# Checked Base64 profiles

## Scope and source

Replace the four fallback/sentinel functions in core::base64 with four checked
functions over byte Views. Support standard and URL-safe alphabets, each with
strict padded and unpadded profiles. Migrate all three WebSocket consumers;
the audit found only those consumers and focused fixtures, without a separate
human dependency requiring compatibility forwarding.

[RFC 4648 sections 3–5 and 10](https://www.rfc-editor.org/rfc/rfc4648.html)
define the alphabets, bit grouping, padding and vectors. Each profile here
rejects whitespace, the other alphabet, unexpected/missing padding and nonzero
unused bits. The unpadded variants are explicit application policies. No MIME
line wrapping, permissive decoding, cryptographic primitive or security claim.

## API and errors

```text
enum Profile { Standard, StandardUnpadded, UrlSafe, UrlSafeUnpadded }
enum Error {
    Bounds, LengthOverflow, InvalidLength, InvalidByte(i32),
    InvalidPadding(i32), NonCanonical(i32), BufferTooSmall(i32)
}
encoded_len(input_len:i32, profile:Profile) -> Result<i32,Error>
decoded_len(input:View<u8>, profile:Profile) -> Result<i32,Error>
encode_into(input:View<u8>, output:View<u8>, profile:Profile) -> Result<i32,Error>
decode_into(input:View<u8>, output:View<u8>, profile:Profile) -> Result<i32,Error>
```

Return written counts, relative to output.start; indexed error payloads are
relative to input.start. BufferTooSmall carries the complete required output
count. Bounds rejects negative View start/length or overflowing start+length;
encoded_len rejects negative length with Bounds. All integer arithmetic stays
within i32. LengthOverflow means the positive encoding result exceeds i32::MAX.
Padded maximum input is 1610612733; unpadded maximum is 1610612735. Their exact
outputs are 2147483644 and 2147483647. Empty data succeeds with count 0.

Both complete View metadata checks precede byte access and all other failures.
Encoding then calculates required length and checks capacity before reading or
storing. Decoding validates all input before checking output capacity or storing;
malformed input therefore precedes BufferTooSmall. Every recoverable rejection
leaves the entire backing unchanged, including same-base input/output aliases.
Read/validation functions never mutate storage. Successful writes touch only
their count bytes; no NUL/newline or implicit owner is added.

## Strict validation order

After metadata, padded input length must be a multiple of 4; unpadded length
must have remainder 0/2/3. Otherwise InvalidLength occurs before byte access.
Visit groups from left to right and positions within a group from left to right.
An unexpected '=' is InvalidPadding(index); an unrecognized alphabet byte is
InvalidByte(index). For padded profiles only the final group permits third or
fourth-position padding. If its third is '=', require fourth '=' or return
InvalidPadding(third index); do not reinterpret that mismatch as another error.
After validating that group's alphabet/padding shape, require zero unused bits:
second sextet low 4 bits for a one-byte tail, third low 2 for a two-byte tail.
NonCanonical points to that sextet's index. Unpadded profiles forbid every '='
and apply the same unused-bit rule after validating all tail symbols. No optional
padding, cross-alphabet acceptance or skipped characters.

## Storage and algorithm

Use one profile-aware alphabet mapper and shared length/validation engines.
Encoding walks groups backward, snapshots up to 3 input bytes before its stores;
decoding walks forward after full validation, snapshots each 4-symbol group
before stores. Both are O(n), constant auxiliary storage, allocation/host-free.
Preserve same-base in-place behavior when source/destination selected first
byte address and byte stride are identical, with enough physical output backing.
Disjoint storage works with arbitrary supported strides and View starts. Other
partial overlap is outside the contract; it is a caller precondition, not a
detected recoverable error. Borrowing alone does not enforce that discipline.
Caller supplies live, correctly typed physical backing and actual native bounds;
logical metadata checks do not establish them. Physical traps have no rollback.

WebSocket consumers select Profile::Standard explicitly and handle Result before
using lengths or copying staged output. Preserve their existing protocol errors
and commit boundaries. Fixed private encodings assert success and their exact
24/28-byte counts before commit; a contradiction is an internal contract failure.
OpenSSL continues to compute the handshake digest.

## Real program

`base64_bytes encode|decode PROFILE` accepts profile names standard,
standard-unpadded, url, url-unpadded. Sole --help/-h; no extra args. Capture at
most 2 arguments/64 bytes and retire argv before data allocation. Read binary
stdin with a 1MiB cap and 8192 actual read attempts, including Interrupted. Reserve
and initialize one Vec<u8> input backing of 1MiB before reading, track used count
separately, never grow. At the cap require an actual 1-byte EOF probe; an extra
byte is an error. Use the public checked length/codec API and a separately
reserved/initialized exact-size output Vec. No direct owner-field mutation.
Complete all input validation/conversion before stdout; retire input before
publication and output afterward. Output at most 1398104 bytes with 2048 actual
write attempts total; diagnostics 8. Ignore SIGPIPE, borrow standard descriptors.
Status 0 success/help, 2 CLI/invalid data/limits, 3 input or argument host errors,
4 allocation, 5 output/signal, 6 internal. Preserve primary failures during cleanup.

## Acceptance

1. Small native admission for all profiles, Result errors and same-base aliases.
2. Direct RFC vectors, exact errors/precedence, checked extreme lengths,
   null-backed metadata/structural rejection, whole-backing atomicity and strides.
3. Independent canonical-wire model across all four profiles, tail-bit and
   alphabet/padding mutations, boundary lengths, offsets and insufficient output.
   Do not rely on roundtrip-only expectations or permissive host decoding.
4. Guarded memory, native/packed/unaligned and same-base aliases, plus migrated
   physical-overclaim traps. Preserve every old codec guarantee actually useful.
5. Real CLI normal/binary/cap/malformed/owner/OOM/I/O acceptance; selected current
   WebSocket portable/upgrade/OpenSSL regressions for the migrated call sites.
6. Retire old APIs/fixtures and update semantic guides/reference metadata. Keep
   historical receipts scoped and all root human text unchanged.

Root serializes compiler/native/Cargo under the existing library lock; commands
stay below two minutes. Agents may perform bounded CPU-only controls. Initial
execution profile is native Linux x86_64 CPU output from the GPU compiler;
other targets and user-program GPU execution need separate evidence. Compiler,
extractor, proofs and ABI remain outside this increment. Full library goal open.
