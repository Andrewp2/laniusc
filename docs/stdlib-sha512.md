# SHA-512 family

`core::sha512` implements SHA-512, SHA-384, SHA-512/224, and SHA-512/256 over
byte messages, with incremental updates and fixed caller-independent results.
It allocates no memory and retains no input view.

Verified execution is x86_64 Linux output from GPU compilation. User GPU
kernels and other execution targets remain unverified.
The [stdin hashing program](stdlib-hash-bytes.md) and
[performance record](library-foundation-performance.md#sha-2-hmac-and-hkdf)
provide application and scale evidence.

The implementation follows [FIPS 180-4](https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.180-4.pdf),
sections 4.1.3, 4.2.3, 5.1.2, 5.3.4–5.3.6, and 6.4–6.7: 128-byte blocks,
80 rounds of 64-bit arithmetic, big-endian words and length encoding, and
distinct initial values for the four algorithms. The two SHA-512/t functions
use their specified initial values; they are not truncations of an ordinary
SHA-512 digest.

## API

| Algorithm | State constructor | One-shot function | Digest length |
| --- | --- | --- | --- |
| SHA-512 | `new()` | `digest(input)` | 64 bytes |
| SHA-384 | `new384()` | `digest384(input)` | 48 bytes |
| SHA-512/224 | `new512_224()` | `digest512_224(input)` | 28 bytes |
| SHA-512/256 | `new512_256()` | `digest512_256(input)` | 32 bytes |

One-shot inputs are `core::slice::View<u8>` and results are
`core::result::Result<Digest, Error>`. `Digest` contains `bytes: [u8;64]` and
`length: i32`. Bytes from `length` through 63 are always zero, including the
partial fourth word of SHA-512/224.

Each `State` provides:

- `borrow() -> &State` to name the actual state for borrowed calls.
- `update(input) -> Result<i32, Error>`, returning the complete accepted count.
- `finish() -> Digest`, finalizing once and returning the same value thereafter.
- `reset()`, clearing the message and restoring the selected algorithm's IV.

```lanius
let state: core::sha512::State = core::sha512::new512_256();
state.update(first).unwrap();
state.update(second).unwrap();
let answer: core::sha512::Digest = state.finish();
```

Empty updates on an active state return zero. After finalization even an empty
update returns `Finished`, until reset. Reset retains the variant and zeros the
block buffer. The returned digest owns its fixed bytes; later state operations
do not borrow or overwrite that result. Copying a partial State forks its
chaining words and buffered prefix independently.

## Bounds, length, and mutation

`Error` is `{ Bounds, LengthOverflow, Finished }`. Update validates the entire
logical view first: negative start or length and overflowing `start + length`
return `Bounds`. Next it checks `Finished`, then the complete length addition.
Each reported error preserves chaining words, counters, buffer, lifecycle, and
variant. A malformed view therefore returns `Bounds` even for a finished state.

The message byte count is `(byte_high << 64) + byte_low`, using two `u64`
fields. The largest accepted whole-byte count is `2^125 - 1`. The high counter
must be at most `2^61 - 1`; this permits a final bit count below `2^128`.
Update computes a temporary wrapping low sum and its carry, checks the high
limit, and only then copies bytes or compresses a block. Since an individual
view has at most `i32::MAX` bytes, it contributes at most one low-word carry.

Finalization encodes the two bit-count words as
`(byte_high << 3) | (byte_low >> 61)` and `byte_low << 3`. Padding never changes
the stored message byte counters. Compression and schedule additions deliberately
wrap modulo `2^64`, as native `u64` arithmetic does; length overflow is checked
separately before mutation.

## Manual state and input contracts

The caller physically backs the complete slice range for the duration of update,
keeps it immutable, and keeps it disjoint from the State being mutated. Logical
metadata validation cannot establish raw backing or detect arbitrary aliases.
No view is retained after the call. Packed bytes and strided native byte arrays
use their slice indexing semantics.

Use a constructor and the methods to maintain State. Its manual fields are
`h0` through `h7`, `byte_low`, `byte_high`, `used`, `block`, `finished`, and
`output_length`. While unfinished, `0 <= used < 128`, `used == byte_low % 128`,
and `output_length` is one of 64, 48, 28, and 32. Chaining words, counters and
the initialized buffer prefix must describe the same message. After finish,
`used` is zero and chaining words include padding. Arbitrary field edits do not
construct the hash of an enormous message.

## Native execution evidence

The focused driver is
[`tests/stdlib_sha512_execution.rs`](../tests/stdlib_sha512_execution.rs).
Both focused tests passed on x86_64 Linux through the GPU compiler: two strict
ELFs and native execution, 7.50 s total. The accepted log is
`target/stdlib-work/sha2-admission/sha512.log`.

| Gate | Accepted scope |
| --- | --- |
| Batched model | 2,104 cases, including 92 official KATs in both layouts; three independently retained digest publications per case |
| Ordinary stream consumer | Six streams, all four variants concurrently, including million-`a` |
| Allocation tracing | Zero allocation-related syscalls, with allocation attempts denied |

`sha512_family_cavp_hashlib_streaming_views_snapshots_and_length_contracts_execute`
compiles one batched fixture and checks:

- 92 selected official byte-message vectors, 23 for each variant, against their
  fixed answers and independently against Python `hashlib`.
- Padding and block boundaries including 111/112/127/128/129 bytes, multiple
  blocks, packed and strided storage with nonzero offsets, four chunk schedules,
  empty updates, and reproducible random messages (seed `0x73b19ca551238428`).
- Partial State forks with divergent updates, repeated finish, variant-preserving
  reset, retained Digests across other calls and stack reuse, and independent
  mutation of copied Digest bytes.
- Complete scalar and block-byte snapshots on bounds, finished, and length
  errors. These snapshots do not rely on comparing two copied State records.
- Fabricated near-limit counters for carry, overflow rejection, and final length
  encoding against Python arbitrary-precision arithmetic. These are arithmetic
  and padding checks, not actual hashing of messages near `2^125` bytes.

The official data is retained in
[`nist_cavp_vectors.txt`](../tests/fixtures/stdlib_foundation/sha512/nist_cavp_vectors.txt)
with its source and archive hash. It comes from the NIST CAVP
[byte-oriented SHA vector archive](https://csrc.nist.gov/csrc/media/projects/cryptographic-algorithm-validation-program/documents/shs/shabytetestvectors.zip),
selected from the four `ShortMsg.rsp` and `LongMsg.rsp` files. The archive SHA-256
is `929ef80b7b3418aca026643f6f248815913b60e01741a44bba9e118067f4c9b8`.

`sha512_family_ordinary_stream_consumer_matches_hashlib_without_allocation`
compiles one ordinary fixed-scratch stream consumer, runs all four variants
concurrently, and compares six streams including the million-`a` example.
Both tests traced allocation-related syscalls and denied allocation attempts;
the accepted executions showed zero such calls. This is functional evidence,
not a throughput measurement or GPU kernel execution claim.

The test binary was
`target/stdlib-build/debug/deps/stdlib_sha512_execution-2b25096e567f2425`.
Its fresh build, shared with the derive target, took 1.36 s and is recorded in
`target/stdlib-work/sha2-admission/build-sha512-derive.log`; that shared build time
is not a standalone SHA-512 compiler measurement. A bounded rerun uses:

```sh
RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
  timeout --kill-after=2s 100s \
  flock -E75 -w35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s \
  target/stdlib-build/debug/deps/stdlib_sha512_execution-2b25096e567f2425 \
  --nocapture --test-threads=1
```

### Initial fixture syntax failures

The first run passed zero tests and rejected both fixtures with `LNC0016` in
3.73 s. `View<u8>=...` tokenized the generic close and assignment as `>=`.
Four fixture declarations were corrected to `View<u8> = ...`; no production
code, driver, expected result, or assertion changed. The corrected two-test run
above then passed.

The initial log is
`target/stdlib-work/sha2-admission/sha512-fixture-syntax.log`. Byte-preserved
initial fixtures are `sha512-runtime-syntax-original.lani` and
`sha512-consumer-syntax-original.lani` in that directory. These syntax failures
are excluded from accepted hash-behavior evidence.
