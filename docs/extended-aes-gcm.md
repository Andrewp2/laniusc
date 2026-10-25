# AES-GCM

`ext::aes_gcm` implements authenticated encryption with associated data in
Lanius using [AES](core-aes.md) and GHASH from
[NIST SP 800-38D, sections 5–7](https://doi.org/10.6028/NIST.SP.800-38D).
It supports AES-128, AES-192 and AES-256, nonempty byte nonces and full
16-byte detached tags. Accepted on 2026-10-24 for x86_64 Linux output from
GPU compilation. This primitive alone does not provide a TLS
connection, certificate validation, replay protection or nonce management.

## API

Every argument below except the receiver is `core::slice::View<u8>`.

| Call | Result |
| --- | --- |
| `new(key)` | `Result<Key, Error>` |
| `key.seal_into(nonce, aad, input, output, tag_output)` | `Result<i32, Error>` |
| `key.open_into(nonce, aad, ciphertext, tag, output)` | `Result<i32, Error>` |
| `seal_into(key, nonce, aad, input, output, tag_output)` | `Result<i32, Error>` |
| `open_into(key, nonce, aad, ciphertext, tag, output)` | `Result<i32, Error>` |
| `key.borrow()` | `&Key` |

The constructor accepts exactly 16, 24 or 32 key bytes, returning `Bounds`
for invalid logical metadata before `InvalidKeyLength`. `Key` contains an
inline AES schedule and 16-byte hash subkey, retains no source borrow and
does not change during operations. Source-key overwrite and original-value
reassignment cannot change an existing copy. Use `new`; fabricated values
and arbitrary state-field mutations are outside the contract. Raw-key free
functions construct this same state after full preflight.

Nonce length is any positive byte length representable by a valid `i32`
view. Twelve-byte nonces use `J0 = nonce || 00000001`; other lengths use the
specified GHASH of padded nonce, 64 zero bits and the nonce bit length.
Empty plaintext and AAD are valid, including authentication-only GMAC use.
Tags must be exactly 16 bytes; shorter NIST tag variants are unsupported and
never silently truncated. Success returns the payload length, writes exactly
that many output bytes, preserves excess output capacity, and sealing writes
exactly 16 tag bytes.

## Preflight and publication

Raw-key free functions check errors in this order:

1. `Bounds`: any supplied view has negative start/length or an end greater
   than `i32::MAX`.
2. `InvalidKeyLength`: key length is not 16, 24 or 32.
3. `InvalidNonceLength`: nonce is empty.
4. `InvalidTagLength`: tag input/output length is not 16.
5. `BufferTooSmall`: output capacity is less than payload length.
6. `InputTooLong`: payload exceeds `MAX_PLAINTEXT_BYTES = 68719476704`.
7. `AuthenticationFailed`: opening found a tag mismatch.

Key methods omit the raw-key checks; all five supplied views are validated
before nonce/tag lengths and output capacity, even for an empty payload.
Preflight precedes encryption, output writes and raw-key expansion. Every
returned error preserves the entire destination and tag-output storage.
Opening first computes the expected tag over the supplied ciphertext and
AAD, compares all 16 tag bytes with accumulated XOR/OR differences, and only
then decrypts. Unauthenticated plaintext is never written to output.

The explicit NIST payload limit is `2^39−256` bits (`2^36−32` bytes), or at
most `2^32−2` counter blocks. Current valid `i32` views impose a tighter
`2^31−1`-byte bound, so `InputTooLong` is unreachable with valid current
metadata; it is not claimed as an executed large-input rejection test.
AAD/nonce bit lengths are at most eight times an `i32` byte length and fit
their 64-bit GHASH length fields. `inc32` increments the low counter word
**modulo** `2^32`: a general nonce can yield a `J0` near the wrap point, and
crossing that point is valid within the per-message block limit. The
implementation does not reject such a nonce or repeat a counter within an
accepted message.

## Backing, aliasing and security responsibilities

All logical ranges require physical backing. Inputs remain stable for the
call, except payload bytes explicitly shared with output. Written payload
cells may be exactly identical or disjoint; partial overlap is unsupported.
Output and tag must be disjoint from the key state/raw key, nonce, AAD and
each other. Sealing tag output is also disjoint from plaintext input;
opening output is disjoint from the supplied tag. Disjoint logical ranges
on one backing allocation are valid. Signed native-array strides and packed
byte slices are handled through ordinary byte indexing. Logical checks
cannot detect aliases, establish physical capacity or enforce ownership.

Callers must provide fresh nonces under a key and obey the construction and
per-key invocation limits in
[SP 800-38D, section 8](https://doi.org/10.6028/NIST.SP.800-38D), including
limits for general nonce lengths. `Key` copies do not create independent
nonce authority. The module does not generate nonces, remember prior uses,
track failed verifications, prevent replay or make repeated-nonce use safe.

AES uses algebraic S-boxes without secret-indexed tables. GHASH uses a fixed
128-iteration masked multiplication with public byte indices; the tag
comparison has no early mismatch exit. These are source properties, not
compiled constant-time guarantees. Work is linear in nonce, AAD and payload
length, with an authentication pass before opening's decryption pass. All
working storage is fixed inline; no allocation, host backend, streaming AEAD
state, secure-erasure or hardware-acceleration guarantee is supplied.

## Admission

[extended_aes_gcm_execution.rs](../tests/extended_aes_gcm_execution.rs)
compiles a protocol fixture once per driver invocation and a separate
ordinary consumer without error-enum projection. The test-only independent
OpenSSL EVP oracle is accessed through Python `ctypes`; production has no
OpenSSL/Python dependency and the Rust driver adds no Cargo crypto library.

| Gate | Accepted commands |
| --- | ---: |
| `nist_vectors_nonce_aad_and_payload_boundaries_match_openssl` | 194 |
| `every_authenticated_component_mutation_preserves_destination` | 460 |
| `invalid_views_lengths_capacities_and_priority_preserve_destinations` | 368 |
| `ordinary_consumer_uses_copied_key_and_both_aead_directions` | Separate executable |

Published examples 1 and 5 from
[NIST's AES-GCM examples](https://csrc.nist.gov/CSRC/media/Projects/Cryptographic-Standards-and-Guidelines/documents/examples/AES_GCM.pdf)
pin empty and nonempty outputs for all three key widths. Decryption inputs
come from OpenSSL, with direct NIST output checks, rather than a native
round trip serving as the only oracle. Cases cross block/padding boundaries,
nonce lengths 1/8/12/13/15/16/17/31/32/33/64/128, empty GMAC payloads,
copied states, exact in-place/disjoint output and both physical layouts.
Two 16 KiB payloads cover a maximum TLS content size in both directions.
A test-only field calculation chooses a general nonce whose `J0` low word
is `fffffffe`; OpenSSL supplies the expected GCM output across the counter
wrap. That calculation does not implement the GCM output oracle.

The mutation group changes every byte of key, general nonce, AAD,
ciphertext and tag and requires authentication failure with all output
unchanged. Error cases cover malformed metadata in every view, bad lengths,
capacities and priority, including empty messages and key methods. Full
source/guard/suffix assertions and empty allocation traces are required.
Partial overlaps and fabricated physical backing are outside the GCM
contract and are not passed to it.

The whole four-test target passed in **9.91 s**, covering **1,022 protocol
commands**, an ordinary consumer, two strict ELF compilations and four
native processes. Three protocol groups shared one ELF through `OnceLock`;
the ordinary consumer compiled separately. Every native group traced
`mmap`, `munmap`, `mremap` and `brk` and had an empty trace. Native timeouts
are 30 seconds per protocol group and five seconds for the ordinary consumer.
The fresh Rust driver build took **1.20 s**. These are whole admission
timings, including compilation and test orchestration, not cipher throughput.

Local ignored receipts are
`target/stdlib-work/tls-peer-auth-admission/build-gcm.log` and
`target/stdlib-work/tls-peer-auth-admission/gcm-all.log`. The accepted
whole-target command from the repository root was:

```sh
RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
LANIUS_DEBUG_STAGE_ERRORS=1 timeout --kill-after=2s 100s \
  flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s \
  target/stdlib-build/debug/deps/extended_aes_gcm_execution-d22601c5f57c7420 \
  --nocapture --test-threads=1
```

The binary name identifies the accepted local build; a fresh build may
produce another suffix. Whole-program performance measurements are pending.
User GPU kernels and other execution targets remain unverified. Existing
TLS record code is unchanged; adding AES-based TLS cipher suites requires a
separate integration gate.
