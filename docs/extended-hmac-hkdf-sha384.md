# HMAC and HKDF with SHA384

`ext::hmac_sha384` and `ext::hkdf_sha384` provide portable, allocation-free
SHA384 constructions following [RFC2104](https://www.rfc-editor.org/rfc/rfc2104.html),
[RFC4231](https://www.rfc-editor.org/rfc/rfc4231.html) and
[RFC5869](https://www.rfc-editor.org/rfc/rfc5869.html). Production is Lanius;
Python and OpenSSL appear only in independent test orchestration.

## HMAC API

| Operation | Result |
| --- | --- |
| `new(key)` | `Result<State, Error>` |
| `State.borrow()` | Shared reference for updates/reset/finalization |
| `State.update(message)` | `Result<i32, Error>` accepted byte count |
| `State.finish()` | Owned `core::sha512::Digest` |
| `State.reset()` | Restores the original keyed seed |
| `authenticate(key, message)` | `Result<core::sha512::Digest, Error>` |

Inputs are `core::slice::View<u8>`. SHA384 uses 128-byte inner and outer pads.
Keys longer than 128 bytes are first reduced by SHA384 to 48 bytes; a key of
exactly 128 bytes is not hashed first. The keyed seeds own their copied state;
no key-input borrow survives construction.

Every returned Digest has `length == 48`, contains the full 48-byte tag in
`bytes[0..48]`, and has a zero 16-byte tail in its 64-byte storage. Finalization
is idempotent. Returned Digest copies and copied partial States are independent
values. Reset preserves the original key and permits a fresh message without
re-reading the original key backing.

`Error` is `Bounds`, `LengthOverflow`, or `Finished`. Update validates complete
logical metadata before lifecycle and accumulated-length checks. A valid empty
update succeeds with zero bytes while active; after finalization it reports
`Finished`. A malformed view reports `Bounds` even after finalization. The
underlying SHA384 counter includes the 128-byte inner pad and checks its full
128-bit bit-length domain before mutation.

## HKDF API

| Operation | Result |
| --- | --- |
| `extract(salt, ikm)` | `Result<core::sha512::Digest, Error>` PRK |
| `expand(prk, info, output)` | `Result<i32, Error>` written byte count |
| `derive(salt, ikm, info, output)` | `Result<i32, Error>` extract then expand |

Extract publishes a full 48-byte PRK with the same zero-tail Digest contract.
Empty salt has the same padded HMAC key as 48 zero salt bytes. Empty input key
material and info are supported. Expand accepts PRKs of at least 48 bytes,
including longer PRKs; it does not truncate them to 48 bytes. This minimum is
checked even when output is empty.

`MAX_OUTPUT` is `255 * 48 = 12240` bytes. Expand generates RFC5869's one-byte
counters 1 through 255, never wrapping to zero. A 12241-byte request is rejected.
`Error` distinguishes `Bounds`, `PrkTooShort`, `OutputLimit`, and nested
`Hash(hmac_sha384::Error)`. All supplied metadata is checked first. Expand then
checks PRK length, output limit, and empty output in that order. Derive checks
metadata and output limit before extraction.

Metadata and limit failures preserve the entire output backing. Success changes
only the requested output range, leaving prefix/suffix guards untouched. Output
must be physically backed, writable, and disjoint from salt, input key material,
PRK and info. The library validates logical start/length arithmetic; physical
backing and alias separation remain manual contracts. Inputs remain immutable
through each call. No host calls or allocation are needed.

State fields are implementation storage. Construct States with `new`, copy
valid States by value, and use the methods to update, finish or reset them.
Methods trust the internal SHA mode, counters, keyed seeds and cached Digest;
arbitrary field mutation does not create a valid State. The counter tests below
deliberately cross this boundary to exercise arithmetic rejection.

These APIs supply keyed primitives, not a protocol, entropy source or tag
verification policy. They do not promise constant-time compiled code, secure
secret erasure, thread safety or protected key storage. Reset deliberately keeps
keyed seeds. Message work is linear in validated input length; there is no work
budget or deadline API.

## Focused verification

All four focused gates pass on native x86_64 Linux. The GPU compiler produced
four x86_64 executables; they ran in 32 native processes with empty allocation
traces. The three protocol gates cover 930 commands across both byte layouts;
the fourth runs the ordinary composition program. This does not establish
user GPU-kernel execution, machine constant-time behavior or TLS integration.

`tests/extended_hmac_hkdf_sha384_execution.rs` contains four independently
selectable exact gates:

- `hmac_hkdf_sha384_ordinary_no_error_projection_consumer`: ordinary composition
  of HMAC, HKDF and SHA384 without matching either new Error enum; published
  HMAC bytes and full zero-tail/copy checks.
- `hmac_sha384_rfc4231_blocks_streams_resets_and_owned_copies`: all seven
  RFC4231 SHA384 cases plus independent Python hmac/hashlib boundary cases,
  streaming schedules, source overwrite, reset, forks and returned Digest copies.
- `hkdf_sha384_independent_openssl_full_counter255_and_guards`: independent
  SHA384 HKDF recurrence and actual OpenSSL HKDF output comparisons, including
  every output byte through block 255.
- `hmac_hkdf_sha384_atomic_errors_and_private_counter_seams`: logical metadata,
  PRK/output limits and error priority, atomic output rejection, complete State
  snapshots and explicit fabricated SHA384-counter seams.

RFC4231 case 5 publishes only a 16-byte truncated answer. The test checks that
published prefix, then independently checks the full 48-byte Python HMAC result
against actual OpenSSL HMAC bytes. It does not label the remaining 32 bytes as
published RFC data. Other six cases compare all 48 published bytes. The HKDF
expected values are computed independently with Python hmac/hashlib and the
RFC5869 recurrence; they are not claimed as published SHA384 appendix vectors.
Six actual OpenSSL HKDF derivations compare full binary results, including a
12240-byte output. The command interface follows
[OpenSSL's kdf documentation](https://docs.openssl.org/3.5/man1/openssl-kdf/).

The key boundary corpus includes empty, 127/128/129/131-byte keys. Message
boundaries include 111/112/127/128/129/255/256 bytes. Streamed States fork after
a common prefix and finish different suffixes. Consumed message bytes and the
original key backing are overwritten before later finalization/reset; original
bytes are restored before guard checks. Independent second-key calculations and
later one-shot calls challenge aliasing of saved Digests and keyed seeds.
Returned storage is checked in all 64 bytes, including its zero tail. One
explicitly mutated copy has a changed tag byte and tail byte to show that other
copies and subsequent state results remain independent; it is not a returned
library tag with a nonzero tail.

Both native strided and packed byte layouts use nonzero offsets. The native
protocol asserts all 4096 input/guard bytes are unchanged after each case. HKDF
cases compare all 12256 output/guard bytes, including atomic failures. Output is
serialized exactly in binary words; neither lengths alone nor digest-only
witnesses substitute for the output bytes. Each native process must exit with
empty stderr and an empty mmap/mremap/munmap/brk trace. The driver compiles one
protocol ELF per invocation and batches 32 cases per native process.

### Explicit private-counter seams

These fixtures directly modify SHA384 counters inside an HMAC State. They test
arithmetic/error handling; they do **not** hash or authenticate huge historical
messages. Fabricated states are never finalized. After each seam, reset restores
the real keyed seed (byte count 128, high count zero, used count zero), and a
normal message tag is compared with the independent HMAC oracle.

The seam corpus includes low-word carry into the high word, the last permitted
high-word carry, rejection beyond the `2^61-1` high-byte limit, rejection after
an accepted prefix at the final boundary, malformed metadata before overflow,
and finalization-state priority. Every rejected update is checked against a
489-word primitive snapshot of all HMAC/SHA state scalars, blocks, keyed seeds,
flags and cached result bytes. This is a scalar/byte serialization taken before
the call, not a shallow State copy that could change together with its subject.
Accepted carries also check that keyed seeds and cached result storage remain
unchanged. Reset and subsequent known-message MACs provide an independent
continuation check after the seam.

Admission used the shared GPU lock and this exact gate command shape:

```sh
RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
  timeout --kill-after=2s 100s flock -E 75 -w 35 \
  target/stdlib-work/library-gpu.lock timeout --kill-after=2s 60s \
  target/stdlib-build/debug/deps/extended_hmac_hkdf_sha384_execution-9f70622193ce01e0 \
  --exact hmac_hkdf_sha384_ordinary_no_error_projection_consumer \
  --nocapture --test-threads=1
```

Cargo used `CARGO_TARGET_DIR=target/stdlib-build`, `CARGO_INCREMENTAL=0`,
`CARGO_PROFILE_DEV_DEBUG=0` and `CARGO_PROFILE_TEST_DEBUG=0`. Building only this
test driver took 1.38 seconds. Runtime invocations also set
`LANIUS_DEBUG_STAGE_ERRORS=1`. Each command had a 100-second outer bound,
35-second lock wait and 60-second execution bound.

| Exact gate | Commands / native processes | Result / elapsed |
| --- | --- | --- |
| `hmac_hkdf_sha384_ordinary_no_error_projection_consumer` | ordinary program / 1 | passed / 6.08 s |
| `hmac_sha384_rfc4231_blocks_streams_resets_and_owned_copies` | 426 / 14 | passed / 6.82 s |
| `hkdf_sha384_independent_openssl_full_counter255_and_guards` | 292 / 10 | passed / 7.44 s |
| `hmac_hkdf_sha384_atomic_errors_and_private_counter_seams` | 212 / 7 | passed / 6.93 s |

Logs are retained locally under `target/stdlib-work/hmac384-admission/`:
`build-first.log`, `ordinary-first.log`, `hmac-first.log`, `hkdf-first.log` and
`limits-first.log`. Times include compilation and orchestration; they are not
cryptographic throughput measurements. No compiler source changed.

The SHA-256 checksums of the admitted production source snapshots begin with
`fb8d13aa` (HMAC) and `bd5590ce` (HKDF). The test snapshots are `7aa46ef6`
(driver), `9db818cf` (ordinary program), `9501542a` (protocol) and `7b5933be`
(independent model). Independent source and fixture review found no blocking
issue; runtime evidence comes from the invocations above.
