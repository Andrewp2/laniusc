# ChaCha20-Poly1305

`ext::chacha20_poly1305` provides the IETF AEAD construction from
[RFC 8439, sections 2.6 and 2.8](https://www.rfc-editor.org/rfc/rfc8439.html#section-2.8),
using `core::chacha20` and `core::poly1305`. It uses caller-owned byte views and
fixed local storage, with no allocation. Accepted on 2026-10-24 for x86_64
Linux output from GPU compilation. User GPU kernels and other execution
targets remain unverified.

## API

Import the module from the `extended` source root. Every argument is a
`core::slice::View<u8>`.

| Call | Result |
| --- | --- |
| `seal_into(key, nonce, aad, input, output, tag_output)` | `Result<i32, Error>` |
| `open_into(key, nonce, aad, ciphertext, tag, output)` | `Result<i32, Error>` |

Keys are exactly 32 bytes, nonces exactly 12 bytes, and tags exactly 16 bytes.
Successful calls return the payload length and write that many output bytes;
any larger output suffix is preserved. Empty payloads and AAD are valid.
Sealing an empty payload still writes a full authentication tag. The caller
must choose a different nonce for each sealing operation under the same key,
as required by [RFC 8439, section 4](https://www.rfc-editor.org/rfc/rfc8439.html#section-4).
The module does not generate or track nonces.

The error variants, in checking order, are:

1. `Bounds`: any logical view has a negative start or length, or its end exceeds
   `i32::MAX`.
2. `InvalidKeyLength`: the key length is not 32.
3. `InvalidNonceLength`: the nonce length is not 12.
4. `InvalidTagLength`: the supplied or destination tag length is not 16.
5. `BufferTooSmall`: output capacity is less than the payload length.
6. `AuthenticationFailed`: opening found a tag mismatch.

Every supplied logical view is checked before fixed lengths and capacity,
including for an empty payload. These errors preserve all destination bytes.
Opening authenticates ciphertext and AAD, reads and compares all 16 tag bytes,
and only then decrypts into the destination. It never exposes unauthenticated
plaintext through output. The comparison accumulates byte differences with
XOR and OR and has no early mismatch exit; this source structure is not a
constant-time compiler or machine-code guarantee. Tags are never truncated.

## Construction and storage

Block zero supplies the first 32 bytes of the one-time Poly1305 key; payload
ChaCha20 starts at counter one. Poly1305 receives AAD, zero padding to a
16-byte boundary, ciphertext, its zero padding, then the two byte lengths as
little-endian `u64` values. The `i32` view length domain fits within the IETF
counter space starting at one.

Every view needs physical backing for its complete logical range. Inputs must
remain immutable for the call, except for the payload bytes explicitly shared
with output. The written payload input/output cells may be exactly identical
or disjoint; partial overlap is unsupported. Output and tag views must be
disjoint from key, nonce, AAD and each other. Sealing tag output must also be
disjoint from plaintext input. On opening, output must also be
disjoint from the supplied tag. Disjoint ranges on one backing allocation are
valid. Logical checks do not establish ownership, physical capacity, alias
safety or nonce uniqueness; callers maintain those conditions manually.

Work is linear in AAD and payload length, using fixed local state. Opening
makes a MAC pass before its decryption pass. There is no elapsed-time bound,
secure-erasure guarantee, streaming AEAD state or implicit resource release.

## Admission

[extended_chacha20_poly1305_execution.rs](../tests/extended_chacha20_poly1305_execution.rs)
compiles a protocol fixture once per driver invocation, plus a separate
ordinary consumer that unwraps results without projecting error payloads.
The native process timeout is 30 seconds for each protocol group and five
seconds for the ordinary consumer. All native groups trace memory-management
syscalls and require an empty trace. All four accepted native processes had
empty allocation traces.

The independent host oracle calls `libsodium.so.23` through Python `ctypes`;
production has no dependency on it and the Rust target adds no Cargo crypto
dependencies. Published encryption and decryption examples from
[RFC 8439, section 2.8.2](https://www.rfc-editor.org/rfc/rfc8439.html#section-2.8.2)
and [appendix A.5](https://www.rfc-editor.org/rfc/rfc8439.html#appendix-A.5)
are also pinned directly. The appendix's literal slash and UTF-8 quotation
bytes are retained.

| Gate | Protocol commands |
| --- | ---: |
| `rfc8439_and_padding_block_boundaries_match_libsodium` | 1180 |
| `every_authenticated_component_mutation_rejects_before_destination_changes` | 744 |
| `invalid_views_lengths_and_capacities_preserve_all_destination_bytes` | 280 |
| `ordinary_consumer_seals_and_opens_without_error_projection` | Separate executable |

The first group crosses AAD padding boundaries 0/1/15/16/17/31/32/33 and payload
padding/block boundaries through 1024 bytes, in both directions. Decryption
inputs come from libsodium rather than relying on a native round trip.
All groups exercise nonzero offsets, native strided arrays, packed bytes,
exact in-place operation and disjoint buffers. Fixture assertions preserve
source bytes, full destination guards and unused capacity. The mutation group
changes every byte of each key, nonce, AAD, ciphertext and tag component and
requires authentication failure with the entire destination unchanged.
The invalid-input group covers all six views with negative starts, negative
lengths and overflowing ends, wrong fixed lengths, insufficient capacities,
and error priority with empty input. Partial overlaps and fabricated physical
backing are outside the contract and are not passed to the implementation.

### Accepted execution

The full four-test target passed in **6.45 s**, covering **2,204 protocol
commands**, the ordinary consumer, two strict ELF compilations and four native
processes. The three protocol groups shared one compiled ELF through
`OnceLock`; the ordinary consumer compiled separately. The fresh joint
four-target Rust build took 1.60 s and produced
`target/stdlib-build/debug/deps/extended_chacha20_poly1305_execution-ade2a5ec645719b0`.
These timings record admission work, not crypto throughput.

Local ignored evidence is in `target/stdlib-work/tls-crypto-admission/`:
`aead.log` records the complete four-test pass, and `build-crypto.log` records
the joint Rust build. These artifacts are not checked in.

The accepted command, run from the repository root, was:

```sh
timeout --kill-after=2s 100s flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s env \
  RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
  target/stdlib-build/debug/deps/extended_chacha20_poly1305_execution-ade2a5ec645719b0 \
  --nocapture --test-threads=1
```

The executable basename identifies the accepted local build; a fresh build
may produce another basename.
