# TLS hash and suite foundations

`ext::tls_hash` provides allocation-free SHA-256/SHA-384 selection, streaming
state, and owned digest snapshots. `ext::tls_suite` provides the three TLS 1.3
suite identities below and a copied, ordered policy of one to three distinct
suites. These modules do not perform a TLS handshake or establish peer trust.

## Sources

Hash arithmetic is supplied by the existing `core::sha256` and `core::sha512`
implementations of [FIPS 180-4](https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.180-4.pdf).
The selected algorithms and suite properties follow
[RFC 8446 §4.4.1](https://www.rfc-editor.org/rfc/rfc8446.html#section-4.4.1) and
[Appendix B.4](https://www.rfc-editor.org/rfc/rfc8446.html#appendix-B.4).

The executable oracle retains published empty-message answers from the
[NIST complete-byte CAVP vectors](https://csrc.nist.gov/csrc/media/projects/cryptographic-algorithm-validation-program/documents/shs/shabytetestvectors.zip)
and the `abc` answers from NIST's
[SHA-256 worked example](https://csrc.nist.gov/CSRC/media/Projects/Cryptographic-Standards-and-Guidelines/documents/examples/SHA256.pdf)
and [SHA-384 worked example](https://csrc.nist.gov/CSRC/media/Projects/Cryptographic-Standards-and-Guidelines/documents/examples/SHA384.pdf).
Python `hashlib` supplies independent full-byte expectations for all streamed
messages, snapshots, forks, and continuations. It is test orchestration only.

## Hash API

| API | Result |
| --- | --- |
| `Algorithm::{Sha256, Sha384}` | Algorithm selection |
| `hash_length(algorithm)` | `i32`, respectively 32 or 48 |
| `new(algorithm)` | Fresh owned `State` |
| `State.borrow()` | Borrowed state for mutation |
| `State.algorithm()` | The active algorithm |
| `State.update(input)` | `Result<i32, Error>` with the accepted logical length |
| `State.snapshot()` | Independent owned `Digest`; streaming can continue |
| `digest(algorithm, input)` | `Result<Digest, Error>` for one complete message |
| `digest_from_view(algorithm, input)` | Copy exactly 32 or 48 existing digest bytes |
| `Digest.view()` | Stable-owner borrowed view of the active digest bytes |

`Digest` contains an algorithm tag and 48 owned bytes. SHA-256 results have a
zero 16-byte tail; their view exposes only the first 32 bytes. SHA-384 exposes
all 48. Snapshots finish a copy of the active core state. Repeated snapshots
are equal and do not prevent later updates. A copied valid `State` can receive
a different continuation, and copied `Digest` byte arrays are independent.

There is one active core hash state in private tagged storage. Values must
originate from `new()` or valid copies. Public implementation metadata is not
a restoration format: callers must preserve the count/core-state relation,
the selected algorithm, and the unfinished core-state invariant. `Digest`
views borrow a live, unmoved owner whose bytes and tag remain unchanged during
the borrow. Copying an owner does not retarget an existing borrowed view.

### Limits and errors

Both algorithms share `MAX_BYTES = 2^61 - 1`. This common TLS wrapper limit is
deliberately smaller than SHA-384's underlying 128-bit length domain.
`update()` checks the complete logical view metadata before its count limit,
and before changing either state or count. A valid empty update at the limit
succeeds; an already excessive count rejects even an empty update.

| Error | Meaning |
| --- | --- |
| `Bounds` | Negative start/length, or `start + length` exceeds signed `i32` |
| `InvalidLength` | `digest_from_view` did not receive exactly the selected digest length |
| `LengthOverflow` | The next update would exceed the common byte domain |

Logical metadata checks cannot prove physical backing. Every input view must
refer to enough live elements with its real stride, remain immutable during
the call, and be disjoint from mutated state. Strides and nonzero offsets are
preserved. No allocation, fallback digest, or host service is used. There is
no finalize/reset lifecycle; create a fresh state to restart a stream.

## Suite API

| `Suite` | ID | Hash | Key bytes | `is_aes` |
| --- | --- | --- | --- | --- |
| `Aes128GcmSha256` | `0x1301` | SHA-256 | 16 | true |
| `Aes256GcmSha384` | `0x1302` | SHA-384 | 32 | true |
| `ChaCha20Poly1305Sha256` | `0x1303` | SHA-256 | 32 | false |

The free helpers `id`, `hash`, `key_length`, and `is_aes` report these
properties. `from_id` returns `Result<Suite, Error>` and rejects other IDs
with `Unsupported`.

`policy(View<Suite>) -> Result<Policy, Error>` copies a nonempty ordered list
of at most three distinct suites. Invalid metadata returns `Bounds` before
length or duplicate checks. Empty, oversized, or duplicate policies return
`InvalidPolicy`. Source storage may be changed after successful construction.

`Policy { order: [Suite; 3], length: i32 }` is an owned value.
`validate_policy(policy) -> Result<i32, Error>` checks only the active prefix;
inactive slots are ignored. All slots must still contain valid enum values.
Constructor-created inactive slots contain `ChaCha20Poly1305Sha256`.
`default_policy()` returns ChaCha20-Poly1305, AES-128-GCM, then AES-256-GCM.
Manual policy edits require validation before consumption. These helpers do
not add AES-256/SHA-384 to any existing connection or record implementation.

## Focused executable gates

The driver is `tests/extended_tls_hash_execution.rs`; sources are in
`tests/fixtures/extended/tls_hash/`.

| Exact gate | Coverage |
| --- | --- |
| `tls_hash_suite_ordinary_composition_consumer` | Ordinary calls without Error patterns; concurrent algorithms and suite-driven hashing |
| `tls_hash_published_hashlib_streams_forks_and_owned_snapshots` | Published empty/`abc`, padding and block boundaries, deterministic messages, chunks, divergent copies, input overwrite, repeated snapshots and full owned bytes |
| `tls_hash_factory_metadata_atomicity_and_common_count_seams` | Exact digest lengths, metadata precedence, retained factory copies, common-count rejection and independent continuations |
| `tls_suite_mappings_all_ordered_policies_and_active_slot_contracts` | All mappings, unsupported IDs, all 15 nonempty unique policies, duplicates, invalid lengths, copied storage and active-only validation |

Hash messages cover 55/56/63/64 and 111/112/127/128/129-byte boundaries and
multiple blocks. Native strided byte arrays and packed byte storage use a
nonzero offset with complete input/guard checks. Suite IDs are read through
both byte layouts, then supplied to the typed policy constructor at a
nonzero enum-array offset. All digest outputs compare the complete 48 bytes,
including SHA-256's unused tail. Owned results remain live across later
hashes, state updates, and deliberate mutations of other copies.

Counter seams inject only the wrapper count at `MAX_BYTES`, above it,
`MAX_BYTES-1`, `MAX_BYTES-3`, and `u64::MAX`. Small accepted inputs are tracked
independently. In the `MAX_BYTES-1` case, one byte is accepted and a second
byte rejects without changing the accepted state. The real count is restored
before snapshots; known hash continuations check that rejected operations did
not change observable core state. These are arithmetic/admission tests, not
huge-message hashing or support for manually fabricated production states.

The binary protocol batches at most 64 commands per native process. Each
process runs under an empty `mmap/mremap/munmap/brk` trace requirement. There
is no JSON/Wasm transport or Rust/Python production hashing backend.

## Admission status

All four exact gates passed on x86_64 Linux through the GPU compiler and
native execution. Each was invoked separately, compiling four strict x86_64
ELFs. The protocol covered **1,634 commands** across **27 native batches**;
the ordinary consumer added one native process. All 28 allocation traces were
empty.

| Gate | Commands / native processes | Elapsed |
| --- | --- | --- |
| Ordinary composition | One consumer / 1 | 4.48 s |
| Hash streams and snapshots | 356 / 6 | 6.06 s |
| Factories, metadata and count seams | 820 / 13 | 5.99 s |
| Suite mappings and policies | 458 / 8 | 6.12 s |

Production hashes were `tls_hash` SHA-256 `71416493…e18ef52` and
`tls_suite` `c65e3aa9…004e2`. Driver `816aee41`, protocol `cd4a526e`, plain
consumer `76c1b7f3`, and independent model `e8f99c06` identify the reviewed
sources. Independent source and oracle review found no blockers. No gate
failed or required a production change.

The focused Rust build completed in 1.21 s and also built the separate
signature test driver. Local logs are
`target/stdlib-work/hash-signature-build-first.log`,
`tls-hash-ordinary-first.log`, `tls-hash-streams-first.log`,
`tls-hash-limits-first.log`, and `tls-suite-policy-first.log`, with the latter
four under `target/stdlib-work/`. They are ignored execution receipts, not
checked-in captures. Timings measure those test invocations, not hashing
throughput or a compiler comparison.

To rebuild the focused Rust target and run each gate separately:

```sh
CARGO_TARGET_DIR=target/stdlib-build CARGO_INCREMENTAL=0 \
CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
timeout --kill-after=2s 100s cargo test --test extended_tls_hash_execution --no-run
```

After resolving the fresh executable path from that build, set `HASH_TEST`
to it and `HASH_GATE` to one exact gate above:

```sh
RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
timeout --kill-after=2s 100s flock -E 75 -w 35 \
target/stdlib-work/library-gpu.lock timeout --kill-after=2s 60s \
"$HASH_TEST" --exact "$HASH_GATE" --nocapture --test-threads=1
```

Native execution evidence, once admitted, applies to x86_64 Linux. GPU work
here runs the compiler; it does not establish user GPU-kernel behavior.
These tests do not prove compiled constant-time execution or secure erasure.
