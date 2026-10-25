# IETF ChaCha20

`core::chacha20` implements the IETF ChaCha20 stream cipher with a 32-byte key, 12-byte nonce, and 32-bit block counter. It uses fixed storage and performs no allocation.

## Source and scope

The algorithm follows [RFC 8439 sections 2.1–2.4](https://www.rfc-editor.org/rfc/rfc8439.html#section-2.1): little endian key/nonce words, ten column/diagonal round pairs, modulo `2^32` feed-forward, and a 64-byte keystream block. The known answers come from [section 2.3.2](https://www.rfc-editor.org/rfc/rfc8439.html#section-2.3.2), [section 2.4.2](https://www.rfc-editor.org/rfc/rfc8439.html#section-2.4.2), and [appendices A.1–A.2](https://www.rfc-editor.org/rfc/rfc8439.html#appendix-A.1).

This module provides the cipher primitive. Authenticated encryption belongs to the separate ChaCha20-Poly1305 construction. Each message needs a unique nonce for its key; restarting or copying a stream position does not create a new nonce.

## API

```lanius
pub enum Error {
    Bounds, InvalidKeyLength, InvalidNonceLength,
    BufferTooSmall, CounterOverflow
}

pub fn new(key: core::slice::View<u8>, nonce: core::slice::View<u8>, counter: u32)
    -> core::result::Result<State, Error>;
pub fn block(key: core::slice::View<u8>, nonce: core::slice::View<u8>, counter: u32,
    output: core::slice::View<u8>) -> core::result::Result<i32, Error>;
pub fn xor_into(key: core::slice::View<u8>, nonce: core::slice::View<u8>, counter: u32,
    input: core::slice::View<u8>, output: core::slice::View<u8>)
    -> core::result::Result<i32, Error>;
pub fn xor_in_place(key: core::slice::View<u8>, nonce: core::slice::View<u8>, counter: u32,
    bytes: core::slice::View<u8>) -> core::result::Result<i32, Error>;

// State methods:
pub fn borrow(&self) -> &State;
pub fn xor_into(&self, input: core::slice::View<u8>, output: core::slice::View<u8>)
    -> core::result::Result<i32, Error>;
pub fn xor_in_place(&self, bytes: core::slice::View<u8>)
    -> core::result::Result<i32, Error>;
```

`block` writes exactly 64 bytes and returns 64. It preserves any extra output suffix. The XOR functions return the complete input length and preserve any larger destination suffix. Encryption and decryption use the same XOR operation.

`new` copies the decoded key and nonce into the state. It does not borrow their views. A `State` keeps unused bytes from its last generated block, so a sequence of updates produces the same output as one update over their concatenation. There is no reset method.

For example, callers can allocate their destination before starting a stream:

```lanius
let key: [u8; 32] = [0; 32];
let nonce: [u8; 12] = [0; 12];
let input: [u8; 3] = [97, 98, 99];
let output: [u8; 3] = [0; 3];
let state: core::chacha20::State = core::chacha20::new(
    core::slice::View<u8> { values: key, start: 0, length: 32 },
    core::slice::View<u8> { values: nonce, start: 0, length: 12 }, 1
).unwrap();
assert(state.xor_into(
    core::slice::View<u8> { values: input, start: 0, length: 3 },
    core::slice::View<u8> { values: output, start: 0, length: 3 }
).unwrap() == 3);
```

Import `core::chacha20`, `core::slice`, and `core::result` for this example. Its zero key/nonce are fixed example data; a protocol must supply its own key and nonce policy.

## Preflight and aliasing

Every operation validates all supplied logical view metadata before reading key/input bytes or changing output/state. Error priority is:

1. `Bounds` for a negative start or length, or overflowing `start + length`, in any supplied view.
2. `InvalidKeyLength` unless the key length is 32.
3. `InvalidNonceLength` unless the nonce length is 12.
4. `BufferTooSmall` unless output can hold the requested bytes.
5. `CounterOverflow` if the complete XOR request exceeds the remaining keystream.

State methods have no key/nonce arguments and apply the relevant metadata, output-size, and counter checks. All failures preserve every destination byte and state field. A rejected request does not consume a cached suffix. Empty XOR requests succeed with zero progress, including after counter exhaustion; invalid metadata still rejects them.

The caller supplies physical backing for each claimed view. Key/nonce bytes remain immutable during an operation, and output must be disjoint from its key, nonce, and state storage. Input/output may identify exactly the same logical cells or be wholly disjoint. Partial overlap is unsupported and is not detected. Different packed/strided descriptors qualify as exact aliasing only if their corresponding logical cells are physically identical.

## Counter and copy contract

The initial counter selects the first block. A new stream can supply `(2^32 - counter) * 64` bytes. The block at counter `4294967295` is usable once; after generating it, the state can still consume its cached suffix. A full preflight rejects any request that would need another block. The counter never wraps or reuses block zero.

The state owns 16 words, one 64-byte cache, `used`, and a widened `next` counter. Valid states have `used` in `0..=64` and `next` in `0..=2^32`. If `used < 64`, the cache suffix belongs to counter `next - 1`; `next == 2^32` means no further block can be generated. Construct states with `new`; arbitrary public-field mutations are outside the contract.

Value copies have independent words, cache bytes, and stream position. `borrow` refers to the same state. A copy retains the same key, nonce, and keystream position: using both copies to encrypt different messages would reuse keystream. The copy fixtures test storage behavior, and do not establish nonce authority for an application. Key and stream cleanup remain caller concerns; this API makes no secure-erasure guarantee.

## Cost and source control flow

Each generated block uses 80 quarter rounds, explicit `core::u32::wrapping_add`, and `core::u32::rotate_left`. The implementation uses fixed round counts and public word indices. Its source branches and memory indices do not depend on key bytes. This describes the source; it is not a compiler or machine-code constant-time guarantee.

XOR time is linear in the requested length, plus block generation. The state and block function use fixed arrays. No operation allocates or performs IO.

## Verification

Both focused gates passed. The focused driver is [stdlib_chacha20_execution.rs](../tests/stdlib_chacha20_execution.rs); sources are in [chacha20](../tests/fixtures/stdlib_foundation/chacha20/). The scope is native Linux x86-64.

| Gate | Scope | Result |
| --- | --- | --- |
| `ietf_chacha20_plain_imported_consumer_executes_without_error_projection` | Full RFC block, destination guards, split 1+63 update, and in-place roundtrip without matching imported `Error` variants | Passed in 3.65 s; one ELF, one native process |
| `ietf_chacha20_vectors_streaming_layouts_and_counter_contracts_match_libsodium` | RFC answers, independent C oracle, chunks/layouts/in-place use, counter limits, and atomic failures/copies | Passed in 5.96 s; one ELF, one native process |

The fresh Rust driver build took 1.22 s. Its accepted local binary is `target/stdlib-build/debug/deps/stdlib_chacha20_execution-a4ad4e9735dc6a35`. Local logs under `target/stdlib-work/tls-crypto-admission/` are ignored artifacts and are not checked in: `build-chacha20.log`, `chacha20-plain.log`, and `chacha20-model.log`. The accepted gates produced two strict ELFs and ran two native processes; all 1112 model commands ran within the second process.

An initial model attempt rejected generic type/assignment spacing that formed a `>=` token. That syntax rejection took 4.12 s and appears in `chacha20-fixture-syntax.log`. Correcting the fixture spacing admitted the accepted model above; production and compiler code did not change. The log does not provide a saved copy of the original fixture.

Each gate compiles one strict ELF and runs one native process under `strace`. Both require an empty `mmap`/`munmap` trace. The differential gate sends 1112 commands through one native process, rather than compiling each case:

- 1040 generated commands span 13 lengths from zero through 1024, counters zero/`MAX-1`/`MAX` where the request fits, four XOR entry paths, four chunk schedules for stateful paths, and four combinations of packed/strided input/output. Key/nonce layouts also vary; every view has a nonzero start.
- 24 block commands cover four appendix A.1 vectors, the section 2.3.2 vector, and the terminal counter, across the four layouts.
- 48 encryption commands cover the section 2.4.2 message and appendix A.2 zero/poem examples, all XOR paths, and all four layouts.

Python `ctypes` calls `libsodium.so.23`'s `crypto_stream_chacha20_ietf_xor_ic` with a 32-bit initial counter as an independent oracle. It checks fixed RFC answers before producing model outputs. The Lanius implementation calls no oracle or foreign crypto backend. Mismatches report operation, counter, input length, schedule, layout, and the first differing response byte.

The native contracts independently serialize all 16 words, all 64 cached bytes, `used`, and `next` before rejected calls. They reject 65 bytes at counter `MAX`, accept one byte, reject 64 without discarding the cached 63, consume those 63, reject another byte, and accept empty without mutation. They also check malformed-view/error priority, short output, one-shot failures, divergent copied streams, retained-state snapshots, untouched source/key/nonce bytes, and destination guards.

The accepted build and direct gate commands are below. Run them separately from the repository root, each within its own 100-second outer limit and 60-second inner limit:

```sh
timeout --kill-after=2s 100s flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  cargo test --test stdlib_chacha20_execution --no-run
```

```sh
timeout --kill-after=2s 100s flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s env \
  RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
  target/stdlib-build/debug/deps/stdlib_chacha20_execution-a4ad4e9735dc6a35 \
  --exact ietf_chacha20_plain_imported_consumer_executes_without_error_projection \
  --nocapture --test-threads=1
```

```sh
timeout --kill-after=2s 100s flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s env \
  RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
  target/stdlib-build/debug/deps/stdlib_chacha20_execution-a4ad4e9735dc6a35 \
  --exact ietf_chacha20_vectors_streaming_layouts_and_counter_contracts_match_libsodium \
  --nocapture --test-threads=1
```

The basename identifies the accepted local build. Use the path reported by a fresh build if its basename differs.
