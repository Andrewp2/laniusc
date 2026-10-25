# HMAC-SHA-256 and HKDF-SHA-256

`ext::hmac_sha256` authenticates byte views with SHA-256. `ext::hkdf_sha256`
extracts and expands key material with that MAC. Both use fixed local storage
and caller-owned output; neither allocates.

Accepted on 2026-10-24 for x86_64 Linux output from GPU compilation. User GPU
kernels and other execution targets remain unverified.
The [key-derivation program](extended-derive-key.md) provides a streaming
application, and the [performance record](library-foundation-performance.md#sha-2-hmac-and-hkdf)
includes the combined compiler workload.

## Algorithms

HMAC follows [RFC 2104, section 2](https://www.rfc-editor.org/rfc/rfc2104.html#section-2).
It hashes keys longer than 64 bytes first, pads the normalized key to 64 bytes,
and applies the SHA-256 inner and outer pads. Every tag is a full 32-byte
`core::sha256::Digest` with `length == 32`.

HKDF follows [RFC 5869, sections 2.2–2.3](https://www.rfc-editor.org/rfc/rfc5869.html#section-2.2).
Extract uses the salt as the HMAC key and input keying material as the message.
Empty salt represents the RFC's omitted salt: it has the same HMAC padded key
as 32 zero bytes. Expand streams the previous block, context and one-byte block
counter through keyed HMAC, then copies the required prefix to output.

## API

Import the modules from the `extended` source root. All arguments below are
`core::slice::View<u8>`.

| Call | Result |
| --- | --- |
| `hmac_sha256::new(key)` | `Result<State, hmac_sha256::Error>` |
| `hmac_sha256::authenticate(key, message)` | `Result<sha256::Digest, hmac_sha256::Error>` |
| `State.update(message)` | `Result<i32, hmac_sha256::Error>` |
| `State.finish()` | `sha256::Digest` |
| `State.reset()` | Restores the same keyed seed |
| `hkdf_sha256::extract(salt, ikm)` | `Result<sha256::Digest, hkdf_sha256::Error>` |
| `hkdf_sha256::expand(prk, info, output)` | `Result<i32, hkdf_sha256::Error>` |
| `hkdf_sha256::derive(salt, ikm, info, output)` | `Result<i32, hkdf_sha256::Error>` |

`State.borrow()` supplies a reference for helpers. Finishing is idempotent;
updating a finished state returns `Finished` until reset. Construction retains
keyed SHA states, with no borrow of the original key. Completed updates retain
no borrow of their message chunks. State and digest copies are independent
values. Use constructors and methods; public fields do not validate fabricated
states.

HMAC errors are `Bounds`, `LengthOverflow` and `Finished`. Logical bounds are
checked before `Finished`. A length error rejects the entire update before
mutation. The maximum accumulated user message is SHA-256's byte limit minus
its 64-byte inner pad: `2^61 - 1 - 64` bytes.

HKDF errors are `Bounds`, `PrkTooShort`, `OutputLimit` and
`Hash(hmac_sha256::Error)`. Expand requires at least 32 PRK bytes, including for
zero output; longer PRKs are accepted. Output length is 0 through 8160 bytes.
Bounds checks precede the PRK and output limits. Derive checks all four views
and the output limit before extraction. Invalid views, short PRKs and excessive
output requests leave output unchanged.

## Storage and work

Every view must be physically backed for its complete logical range. Inputs
remain immutable during a call. `State.update` input must also be disjoint from
the State being mutated. HKDF output must be writable and disjoint from all
inputs. Nonzero offsets, native strided arrays and packed bytes use the same
APIs. No operation implicitly clones or releases external resources.

HMAC work is linear in key and message length; finish and keyed reset use
bounded local state. HKDF extraction is linear in salt and input length.
Expansion costs key normalization plus `ceil(output_length / 32)` times the
context length and bounded block work. These byte-oriented APIs provide no
elapsed-time bound, tag-verification function, constant-time verification claim
or secure-erasure guarantee. Reset retains keyed state.

## Admission

[extended_hmac_hkdf_execution.rs](../tests/extended_hmac_hkdf_execution.rs)
compiles one protocol fixture per driver invocation through `OnceLock`. It
compares all seven SHA-256 vectors in [RFC 4231](https://www.rfc-editor.org/rfc/rfc4231.html#section-4), the
SHA-256 cases A.1/A.2/A.3 in [RFC 5869](https://www.rfc-editor.org/rfc/rfc5869.html#appendix-A),
and block/output boundaries against independent Python `hashlib`/`hmac` results.
RFC 4231 case 5 supplies only a 16-byte expected prefix; the API returns all 32
bytes, which the Python oracle also checks. The fixture checks streamed/reset
states, interleaved keys, copied partial states, retained digest independence,
source sentinels, malformed views and unchanged rejected output. Memory traces
contained no allocation calls in the accepted gates.

| Gate | Accepted commands | Evidence |
| --- | ---: | --- |
| `rfc4231_sha256_vectors_and_streamed_key_block_boundaries_match_python` | 190 | Passed in the corrected two-test invocation, 6.43 s total |
| `rfc5869_sha256_extract_expand_and_full_output_boundaries_match_python` | 88 | Passed in the initial three-test invocation, 7.64 s total; that invocation also had two fixture failures |
| `keyed_state_and_digest_values_are_independent_and_invalid_views_preserve_output` | 4 | Passed in the corrected two-test invocation, 6.43 s total |

The accepted observations total **282 commands in three successful native
processes across two driver invocations**. Each invocation compiled one strict
ELF and shared it across its selected tests. The fresh joint Rust build with
the derive-key target took 1.32 s and produced
`target/stdlib-build/debug/deps/extended_hmac_hkdf_execution-2e879f40586e8c8e`.
These are correctness and allocation observations, not throughput measurements.

### Fixture correction history

The initial invocation passed the HKDF gate and failed the other two tests:
their fixture paths trapped before stdout. Four calls treated
`View.subview(start, end)` as `(start, count)`. The fixture correction changed
`ma.subview(3, 5)` to `(3, 8)`, `mb.subview(5, 23)` to `(5, 28)`,
`b.subview(prefix, b.len() - prefix)` to `(prefix, b.len())`, and streaming
`b.subview(at, count)` to `(at, at + count)`. No production code, Rust oracle
or assertions changed. Root reran only the two affected gates; the unchanged
HKDF gate retains its initial accepted result. The initial full invocation
was not an overall pass.

Local ignored evidence is under `target/stdlib-work/sha2-admission/`:
`build-keyed-final.log`, `hmac-fixture-subview.log`, `hmac-corrected.log`, and
the exact original fixture `hmac-protocol-subview-original.lani`. These artifacts
are not checked in.

### Driver commands

Run these separately from the repository root. The first command records the
mixed initial run; the second selects the two corrected gates. Both use the
shared compiler lock, 100-second outer timeout and 60-second inner timeout.

```sh
timeout --kill-after=2s 100s flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s env \
  RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
  target/stdlib-build/debug/deps/extended_hmac_hkdf_execution-2e879f40586e8c8e \
  --nocapture --test-threads=1
```

```sh
timeout --kill-after=2s 100s flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s env \
  RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
  target/stdlib-build/debug/deps/extended_hmac_hkdf_execution-2e879f40586e8c8e \
  --skip rfc5869_sha256_extract_expand_and_full_output_boundaries_match_python \
  --nocapture --test-threads=1
```

The executable basename identifies the accepted local build. A fresh build may
report another basename. Replaying the first command with today's corrected
fixture runs all three corrected gates; it does not recreate the historical
fixture failure.
