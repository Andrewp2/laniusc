# Poly1305

`core::poly1305` implements the one-time authenticator from
[RFC 8439, section 2.5](https://www.rfc-editor.org/rfc/rfc8439.html#section-2.5).
A 32-byte key and a byte message produce a 16-byte tag. The module supports
incremental updates, allocates no memory, and retains no caller view.

## API and one-time-key authority

- `new(key: View<u8>) -> Result<State, Error>` accepts exactly 32 key bytes.
- `authenticate(key: View<u8>, message: View<u8>) -> Result<Tag, Error>` computes
  a complete tag in one call.
- `State.borrow() -> &State` names the actual state for borrowed calls.
- `State.update(message: View<u8>) -> Result<i32, Error>` accepts the complete
  view and returns its length, or preserves all state on a reported error.
- `State.finish() -> Tag` finalizes once and returns the same value thereafter.
- `Tag` has one field, `bytes: [u8;16]`, containing the little-endian tag.

There is no reset operation. A State carries one message's one-time-key
authority. Copying its descriptor or fields does not authorize authenticating
another message with that key. Key generation, uniqueness, and protocol binding
belong to the caller. Repetitions of publicly known test keys are oracle
computations, not an application key-management pattern.

```lanius
let state: core::poly1305::State = core::poly1305::new(key).unwrap();
state.update(first).unwrap();
state.update(second).unwrap();
let tag: core::poly1305::Tag = state.finish();
```

The returned Tag owns its fixed bytes. Mutating a copied Tag does not change
another returned Tag or the State's cached result. State fields are manual
implementation state; they do not provide automatic zeroization.

## Validation and input lifetime

`Error` is `{ Bounds, InvalidKeyLength, LengthOverflow, Finished }`.
Logical validation rejects negative start or length and overflowing
`start + length`. `new` checks this before key length. `authenticate` checks
both logical views before checking key length.

Update checks logical bounds, then finalization, then accumulated length, all
before mutation. Its accepted user-byte count is at most `u64::MAX`; the addition
is checked as `length <= u64::MAX - total`. Empty updates return zero while
active and return `Finished` after finish. A malformed view returns `Bounds`
even on a finished state or at the length limit. Finalization does not add its
internal marker or padding to `total`.

The caller must physically back every referenced byte for the complete call,
keep input immutable, and keep it disjoint from the State being mutated.
Logical checks cannot establish backing of a raw slice or detect arbitrary
aliases. New copies the clamped multiplier and pad into the State; key storage
can be reused after it returns. Message and key views are never retained.

## Polynomial representation and bounds

The implementation uses five little-endian limbs with radix `B = 2^26`, for
the modulus `p = B^5 - 5`. The multiplier uses overlapping 32-bit reads and
the masks `3ffffff`, `3ffff03`, `3ffc0ff`, `3f03fff`, and `00fffff` (hex).
These implement the RFC's byte clamp. The upper four multiplier limbs also
have precomputed five-times values for the wrapped convolution terms.

At each block boundary the stored limbs satisfy:

- `h0`, `h2`, `h3`, and `h4` are below `B`.
- `h1` is below `B + 2^10`.

Adding a block puts every multiplicand below `3B`; multiplier limbs are below
`B` and their five-times values below `5B`. Each of the five product sums is
therefore below `75B²`. A propagated carry is below `2^33`, so even with that
carry each accumulator is below `76B² < 2^59`. The products and sums fit `u64`
without overflow. Folding the top carry via `B^5 ≡ 5 (mod p)` gives a final
carry into `h1` below 641, restoring the same invariant.

Finish performs a fixed carry sweep. If the initial carry from `h1` is one,
its masked remainder is small, so the possible final carry into it still
leaves it below `B`; if the initial carry is zero, no carry chain starts.
Thus all limbs are below `B`. Adding five across the limbs produces a top
carry exactly when the value is at least `p`. An arithmetic zero/all-ones mask
selects the reduced value. Only this mask construction intentionally uses
wrapping unsigned subtraction (`0 - carry`).

The canonical accumulator is packed into four 32-bit columns and the pad is
added with carries. Each column sum is below `2^33`; discarding the last carry
implements the final addition modulo `2^128`. No 128-bit primitive is needed.

Full 16-byte blocks receive their high marker during update. A partial block
gets one appended byte and zero fill only at finish; empty messages add no
block. Splitting an update never introduces an extra marker or padding block.

The production arithmetic, carry sweeps, and final selection use fixed source
schedules and addresses. Branches depend on metadata, message length, or
lifecycle. This is a source-level property; compiled constant-time behavior has
not been established.

Manual fields are `r0`–`r4`, `s1`–`s4`, `h0`–`h4`, `pad0`–`pad3`, `tag0`–`tag3`,
`total`, `used`, `block`, and `finished`. Besides the limb bounds above, active
state requires `0 <= used < 16`, `used == total % 16`, the specified clamp,
`s_i == 5*r_i`, and pad columns below `2^32`. Chaining limbs, byte count, and
buffered prefix must describe the same message. Arbitrary field fabrication
does not authenticate a genuinely huge message.

## Native execution evidence

The focused driver is
[`tests/stdlib_poly1305_execution.rs`](../tests/stdlib_poly1305_execution.rs).
Both focused tests passed on x86_64 Linux through the GPU compiler: two strict
ELFs and native execution, 6.72 s total. The accepted log is
`target/stdlib-work/tls-crypto-admission/poly1305.log`.

| Gate | Accepted scope |
| --- | --- |
| Batched model | 1,920 cases and four tag publications per case, checked by libsodium and Python bigints |
| Official answers | Complete section 2.5.2 and appendix A.3 vectors, both layouts and all four schedules |
| Plain stream consumer | Six streams, including 1,000,003 bytes, without Error variant projection |
| Allocation tracing | Zero allocation-related syscalls, with allocation attempts denied |

`poly1305_rfc8439_libsodium_bigint_incremental_views_and_lifecycle_execute`
compiles one runtime fixture for 1,920 batched native cases. It contains the
complete section 2.5.2 example and all 11
[appendix A.3 vectors](https://www.rfc-editor.org/rfc/rfc8439.html#appendix-A.3),
in both layouts and all four schedules. It also covers 15/16/17-byte boundaries,
multiple blocks, five structured keys, 256 seeded random cases, and 64 pairs
that differ only in clamped key bits. The random seed is
`0x13058439c0de17ff`.

Each result is checked independently against `libsodium.so.23` through Python
`ctypes` and a Python arbitrary-precision formula using byte-wise clamping.
Four retained tag publications per case exercise concurrent distinct-key
states, unrelated calls and stack reuse, repeated finish, and independent
mutation of Tag copies. Error tests capture every scalar and block byte into
independent numeric snapshots. Fabricated near-limit counters establish count
arithmetic and rejection atomicity, not enormous-message authentication.

[`rfc8439_vectors.txt`](../tests/fixtures/stdlib_foundation/poly1305/rfc8439_vectors.txt)
retains the exact vector keys, messages and tags with source provenance. The
retrieved RFC text SHA-256 is
`25bef70fbf7a07ff45c2fe4cb7c6ce954eac687413d8610603268b4e4415324c`.

`poly1305_plain_stream_consumer_without_error_projection_allocates_nothing`
compiles an ordinary fixed-scratch consumer with no Error variant projection.
It checks six streams, including 1,000,003 bytes, against both oracles. Both
tests traced allocation-related syscalls and denied allocation attempts; the
accepted executions showed zero such calls. These are functional checks, not a
throughput measurement, a compiled constant-time result, or a GPU-kernel
execution claim.

The accepted binary was
`target/stdlib-build/debug/deps/stdlib_poly1305_execution-b95f1beb02e4cea2`.
The fresh joint build of four Rust targets took 1.60 s and is recorded in
`target/stdlib-work/tls-crypto-admission/build-crypto.log`. That shared build
time is not a standalone Poly1305 compiler measurement. The whole binary ran
with `--nocapture --test-threads=1`; a bounded rerun uses:

```sh
CARGO_TARGET_DIR=target/stdlib-build CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 timeout --kill-after=2s 100s flock -E 75 -w 35 target/stdlib-work/library-gpu.lock timeout --kill-after=2s 60s target/stdlib-build/debug/deps/stdlib_poly1305_execution-b95f1beb02e4cea2 --nocapture --test-threads=1
```
