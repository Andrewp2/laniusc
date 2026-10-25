# SHA-224 and SHA-256

`core::sha256` provides incremental SHA-224 and SHA-256 with fixed caller storage and no allocation. It accepts byte messages through `core::slice::View<u8>`.

Verified execution is x86_64 Linux output from GPU compilation. User GPU
kernels and other execution targets remain unverified.
The [stdin hashing program](stdlib-hash-bytes.md) and
[performance record](library-foundation-performance.md#sha-2-hmac-and-hkdf)
provide application and scale evidence.

## Source and scope

The implementation follows [FIPS 180-4](https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.180-4.pdf): the SHA-256 functions and constants in sections 4.1.2 and 4.2.2, padding and initial values in section 5, and the SHA-256/SHA-224 algorithms in sections 6.2–6.3. Both use 512-bit blocks and 32-bit words; SHA-224 has its own initial values and publishes seven words. Input words, the final length, and output words use big endian order.

The official NIST [SHA-256 worked examples](https://csrc.nist.gov/CSRC/media/Projects/Cryptographic-Standards-and-Guidelines/documents/examples/SHA256.pdf) and [SHA-224 worked examples](https://csrc.nist.gov/CSRC/media/Projects/Cryptographic-Standards-and-Guidelines/documents/examples/SHA224.pdf) supply the `abc` and 56-byte known answers used by the fixtures. The generated cases use Python `hashlib` as a separate executable oracle. These checks do not constitute FIPS certification.

## API

```lanius
pub enum Error { Bounds, LengthOverflow, Finished }
pub struct Digest { bytes: [u8; 32], length: i32 }

pub fn new() -> State;
pub fn new224() -> State;
pub fn digest(input: core::slice::View<u8>) -> core::result::Result<Digest, Error>;
pub fn digest224(input: core::slice::View<u8>) -> core::result::Result<Digest, Error>;

// State methods:
pub fn borrow(&self) -> &State;
pub fn update(&self, input: core::slice::View<u8>) -> core::result::Result<i32, Error>;
pub fn finish(&self) -> Digest;
pub fn reset(&self);
```

`new` selects SHA-256; `new224` selects SHA-224. `Digest.length` is 32 or 28 respectively. SHA-224 leaves bytes 28 through 31 zero. The digest contains inline bytes with independent value storage; it borrows no state or input. A digest remains valid across later updates, resets, one-shot calls, and mutations of another digest copy.

For example:

```lanius
let data: [u8; 3] = [97, 98, 99];
let input: core::slice::View<u8> = core::slice::View<u8> {
    values: data, start: 0, length: 3
};
let state: core::sha256::State = core::sha256::new();
assert(state.update(input).unwrap() == 3);
let value: core::sha256::Digest = state.finish();
assert(value.length == 32 && value.bytes[0] == 186);
```

Import `core::sha256`, `core::slice`, and `core::result` for this example. The implementation is in [sha256.lani](../stdlib/core/sha256.lani).

## Update and lifecycle contract

`update` accepts the complete logical view or rejects it before reading input or mutating the state. Successful calls return `input.length`, including zero for an empty update. The total message length may reach `2^61 - 1` bytes, so its bit length fits the final 64-bit field.

The checks run in this order:

1. A negative start, negative length, or overflowing `start + length` returns `Bounds`.
2. A finished state returns `Finished`, including for an empty update.
3. A message that would exceed the byte limit returns `LengthOverflow`.

These failures preserve all chaining words, pending bytes, counters, variant, and lifecycle state. Logical metadata checks cannot establish physical backing: the caller must supply readable storage for the claimed range. Input must remain immutable and disjoint from the state throughout the call. Both packed bytes and native strided byte arrays retain their view stride and start offset.

`finish` pads the message once, records the result in the state, and returns its digest. Further calls return the same bytes without applying padding again. Exhausting a message does not reset it. `reset` keeps the selected variant, restores its initial words, clears the pending buffer and counters, and permits further updates. Reset does not promise secure erasure by the compiler.

A `State` value owns its inline pending block and scalar chaining words. Copying a partial state creates an independent continuation; `borrow` refers to the same mutable state. Two constructed or copied states can receive interleaved, different updates.

## Representation and cost

The public state fields support explicit storage and inspection. Construct states with `new`, `new224`, or `reset`; arbitrary field values are outside the hashing contract. Before finish, `count` is the accepted byte count, `used == count % 64`, the first `used` block bytes are the pending suffix, and `h0` through `h7` describe the preceding complete blocks.

The tests fabricate only the count near its limit while preserving the count/remainder relation. This checks acceptance of the last legal byte and rejection of the next byte. The fabricated chaining words do not describe an enormous processed prefix, so the tests reset that state without claiming a digest for that history.

Updates buffer each logical byte and compress complete 64-byte blocks. Compression uses a fixed 64-word schedule and 64-word constant table. Rotations, logical shifts, and two-term sums use the existing `core::u32` primitives. Four- and five-term sums widen to `u64`, stay below `2^34` and `2^35`, then mask to 32 bits. No arithmetic depends on an implicit overflowing 32-bit addition.

Time is linear in input length with 64 rounds per compressed block. Storage is constant: the state holds one 64-byte block, and compression uses fixed arrays. No operation allocates, destroys nested owners, flushes, or performs IO.

## Verification

The focused Linux x86-64 driver is [stdlib_sha256_execution.rs](../tests/stdlib_sha256_execution.rs), with fixtures in [sha256](../tests/fixtures/stdlib_foundation/sha256/). Each test compiles one native program through the common strict ELF and native instruction checks. Each program runs once under `strace`; its `mmap`/`munmap` trace must be empty.

| Gate | Scope | Result |
| --- | --- | --- |
| `sha224_and_sha256_plain_imported_consumers_execute_without_error_projection` | Both official `abc` digests and incremental SHA-256 through an ordinary imported consumer, without matching any `Error` variant | Passed in 4.30 s; one ELF, one native process |
| `sha2_vectors_chunk_schedules_and_state_contracts_match_hashlib` | Generated byte messages and NIST examples, both variants, streaming and one-shot use, state lifecycle and copy contracts | Passed in 5.42 s; one ELF, one native process |

The driver build shared with the application target took 1.26 s. Together the two gates compiled two strict native ELFs and ran two native processes. The 976 commands belong to the model process. Local admission logs under `target/stdlib-work/sha2-admission/` are ignored artifacts and are not checked in: `build-initial.log`, `sha256-plain.log`, and `sha256-model.log`.

The model contains 976 commands in one process: 30 lengths × 8 schedules × 2 physical layouts × 2 variants, plus 16 official example cases. Lengths include 0, 1, 55, 56, 63, 64, 65 and later block boundaries through 4096. Schedules include one-byte updates, widths around 64, a mixed schedule containing empty updates, and whole-input updates. Both layouts use nonzero starts and preserve source sentinels and bytes.

The native fixture also checks malformed-view priority, finished-state rejection, the exact count limit, reset variant retention, idempotent finish, two active variants, divergent partial-state copies, and retained/mutated digest copies. Rejection checks serialize every state scalar and pending byte into separate storage; comparing two potentially aliased `State` copies alone would not establish atomicity. The host compares complete digest bytes and lengths with `hashlib`, including SHA-224's zero tail. On mismatch it reports the command's variant, length, schedule, layout, and first differing response byte.

The accepted build and direct gate commands are below. Run each command separately from the repository root. Each has an outer 100-second limit and a 60-second inner limit; the shared lock serializes compiler access:

```sh
timeout --kill-after=2s 100s flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  cargo test --test stdlib_sha256_execution --test stdlib_hash_bytes_execution --no-run
```

```sh
timeout --kill-after=2s 100s flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s env \
  RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
  target/stdlib-build/debug/deps/stdlib_sha256_execution-fd0be40de02780ad \
  --exact sha224_and_sha256_plain_imported_consumers_execute_without_error_projection \
  --nocapture --test-threads=1
```

```sh
timeout --kill-after=2s 100s flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s env \
  RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
  target/stdlib-build/debug/deps/stdlib_sha256_execution-fd0be40de02780ad \
  --exact sha2_vectors_chunk_schedules_and_state_contracts_match_hashlib \
  --nocapture --test-threads=1
```

The basename records the accepted local build. A fresh build can produce a different basename; use its reported executable path for direct gates.
