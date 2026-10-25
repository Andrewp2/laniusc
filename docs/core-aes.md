# AES block cipher

`core::aes` implements AES-128, AES-192 and AES-256 in Lanius, following
[FIPS 197, sections 4–5](https://doi.org/10.6028/NIST.FIPS.197-upd1).
It expands keys into fixed inline storage and encrypts or decrypts one
16-byte block. Accepted on 2026-10-24 for x86_64 Linux output from GPU
compilation. The block primitive does not authenticate messages or
provide a message-encryption mode. See [AES-GCM](extended-aes-gcm.md) for AEAD.

## API and failure behavior

Every byte-view argument is `core::slice::View<u8>`.

| Call | Result |
| --- | --- |
| `new(key)` | `Result<Schedule, Error>` |
| `schedule.encrypt_into(input, output)` | `Result<i32, Error>` |
| `schedule.decrypt_into(input, output)` | `Result<i32, Error>` |
| `schedule.borrow()` | `&Schedule` |

`new` accepts exactly 16, 24 or 32 key bytes. Its checking order is `Bounds`
for invalid logical key metadata, then `InvalidKeyLength`. It copies and
expands the key into a 240-byte inline array, using 10, 12 or 14 rounds.
Subsequent source-key changes have no effect. The schedule retains no borrow;
ordinary value copies have independent inline storage. Construct schedules
with `new`; arbitrary field mutation or fabricated schedules are outside the
state contract.

Block methods check both views for `Bounds`, then require exactly 16 input
bytes (`InvalidBlockLength`), then at least 16 output bytes
(`BufferTooSmall`). Logical bounds mean nonnegative start and length with an
end no greater than `i32::MAX`. These checks precede all writes. Success
returns 16, writes precisely the first 16 output bytes, and preserves a
larger output suffix. Every error preserves the whole destination. Methods
leave the schedule unchanged, including across repeated calls.

Views must have physical backing for their complete logical ranges and be
disjoint from the schedule. Array and byte-slice accesses honor their signed
byte stride; no packed-layout assumption is made. The entire source block is
staged before the first destination write, so disjoint buffers, exact
in-place use and forward or backward partial overlap are supported. Input
bytes must remain stable until staged. View metadata cannot establish
physical capacity, ownership or protection from concurrent mutation.

## Source structure and limits

The state uses the FIPS column-major byte order. Encryption applies the
forward round sequence; decryption reverses it with inverse substitution,
row shift and column mixing. All three key schedules include the AES-256
extra `SubWord` step. Finite-field inversion uses a fixed exponentiation
chain and multiplication uses eight masked iterations. Forward and inverse
S-boxes use algebraic transformations with no secret-indexed lookup table.
Round counts and state/key indices depend on public key width and loop
positions. This source structure is **not a compiled constant-time
guarantee**. No secure erasure, hardware acceleration or FIPS validation is
claimed. Work and inline state are bounded per block; there is no allocation
or host call in the module.

## Admission

[core_aes_execution.rs](../tests/core_aes_execution.rs) compiles one batched
protocol fixture and one separate ordinary consumer to strict x86_64 Linux
ELFs through the GPU compiler. The independent test-only oracle uses
OpenSSL EVP through Python `ctypes`, with padding disabled for a single
block; production has no OpenSSL or Python dependency.

| Gate | Accepted commands |
| --- | ---: |
| `fips197_all_key_widths_and_full_byte_domain_match_openssl` | 752 |
| `constructor_block_and_destination_errors_preserve_bytes` | 928 |
| `ordinary_consumer_retains_copied_schedule_and_overlapping_blocks` | Separate executable |

The success group pins encryption and decryption from the original
[FIPS 197 appendix C](https://csrc.nist.gov/files/pubs/fips/197/final/docs/fips-197.pdf),
whose algorithm is unchanged by the 2023 update. It also covers all 256
initial forward S-box byte inputs and diverse keys/blocks. Cases exercise
all key widths, both signed native-array and packed-byte layouts, nonzero
offsets, exact and partial overlap, copied schedules after source-key
overwrite and original-schedule reassignment, and repeated immutable use.
Failures exercise every view's negative start/length and overflowing end,
wrong key/block lengths, short output and check ordering. Fixture assertions
cover whole source and destination guards, including untouched capacity.

The complete three-test target passed in **5.96 s**, covering **1,680
protocol commands**, a separate ordinary consumer, two strict ELF
compilations and three native processes. Protocol groups shared one ELF
through `OnceLock`. Each protocol native process has a 30-second timeout;
the ordinary consumer has five seconds. All three native groups traced
`mmap`, `munmap`, `mremap` and `brk` and had empty traces. The fresh Rust
driver build took **1.36 s**. These timings describe whole admission work,
not block throughput.

The initial three-test attempt stopped at parsing in **2.56 s**: source
used `else if`, while Lanius requires a nested `else { if (...) }` block.
Only that source syntax was corrected; the algorithm, oracle, fixtures and
assertions were preserved. Local ignored evidence is in
`target/stdlib-work/tls-peer-auth-admission/`: `build-aes.log`, initial
`aes-all.log`, and accepted `aes-corrected.log`.

The accepted whole-target command from the repository root was:

```sh
RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
LANIUS_DEBUG_STAGE_ERRORS=1 timeout --kill-after=2s 100s \
  flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s \
  target/stdlib-build/debug/deps/core_aes_execution-8edbb1aa07b08704 \
  --nocapture --test-threads=1
```

The binary name identifies the accepted local build; a fresh build may
produce another suffix.

Whole-program performance measurements are pending. User GPU kernels and
other execution targets remain unverified.
