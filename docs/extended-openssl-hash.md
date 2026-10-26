# Hashing stdin with OpenSSL

[`sample_programs/library/openssl_hash.lani`](../sample_programs/library/openssl_hash.lani)
reads binary stdin, updates an owned
[`ext::openssl_digest`](extended-openssl-digest.md) context, and prints one
lowercase hexadecimal digest followed by a newline.

```text
openssl-hash sha256|sha512|sha3-256|sha3-512
             [--max-input N] [--max-io-calls N]
```

Select exactly one algorithm. `sha256` and `sha3-256` produce 64 hexadecimal
digits; `sha512` and `sha3-512` produce 128. Input includes every byte, including
NUL, high bytes and final newlines. The program never treats stdin as text.
OpenSSL 3 EVP performs every digest operation; the sample contains no hash
rounds, padding or custom digest implementation.

The executable uses the [Linux x86_64/glibc native C profile](library-native-c.md), libc startup
and the system OpenSSL 3 `libcrypto`. From the repository root:

```sh
export CARGO_TARGET_DIR="$PWD/target/stdlib-build"
timeout --kill-after=2s 100s "$CARGO_TARGET_DIR/debug/laniusc" \
  --native-link --native-library crypto \
  --stdlib-root stdlib --source-root extended \
  sample_programs/library/openssl_hash.lani -o /tmp/openssl-hash

printf '%s' 'binary input' > /tmp/hash-input
timeout --kill-after=2s 20s /tmp/openssl-hash sha3-256 < /tmp/hash-input
openssl dgst -sha3-256 /tmp/hash-input
```

The OpenSSL CLI adds its own label; compare its digest with the sample's single
hexadecimal line. The application uses the default OpenSSL library context and
provider policy. A selected algorithm that the configured providers cannot
supply produces an OpenSSL error.

## Bounds and stream behavior

Input defaults to at most 16 MiB. `--max-input` accepts unsigned decimal values
through `i32::MAX`, including zero. The loop reads at most 1,024 bytes per call
and hashes each successful chunk. Once it reaches the byte limit, it requests
one additional byte to distinguish exact EOF from excess input. A limit error
can therefore consume one byte beyond the allowed input; that byte is never
hashed and no digest is printed.

`--max-io-calls` defaults to 65,536. It bounds the combined stdin read attempts
and stdout write attempts. Every short transfer, EOF probe and EINTR retry
spends one attempt. It also bounds stdout when `--help` / `-h` prints usage.
An exhausted call budget returns a limit error. The budget bounds attempts;
it does not impose a timeout on a blocking descriptor.

Short reads are normal. Short writes resume at the first unwritten byte.
EINTR retries within the call budget; EAGAIN, host errors, invalid transfer
counts and zero-progress writes return I/O errors. The program finishes the
digest and closes the EVP owner before the first stdout attempt. Input,
OpenSSL and input-limit failures publish no stdout. A later write failure or
call limit can leave a hexadecimal output prefix.

Repeated limit options use their last values. Options can precede or follow
the algorithm, with separate or `=` values. Signs, overflow, empty values,
unknown options and additional operands are errors. Argument capture permits
16 arguments and 4,096 total bytes. Help validates all supplied arguments
before writing usage.

## Errors and ownership

| Exit | Meaning |
| --- | --- |
| 0 | Complete digest output or help |
| 2 | Invalid arguments, input limit or I/O call limit |
| 3 | Argument capture, stdin or stdout I/O failure |
| 4 | OpenSSL failure or argument allocation failure |

Failures print one short diagnostic on stderr. Diagnostics have a separate
eight-attempt budget, retry EINTR, and preserve the original exit status if
stderr fails. The program releases the argument snapshot and owned EVP method
and context on every completed success and error path. The read, digest and
hexadecimal buffers use fixed stack storage. Stdin, stdout and stderr are
borrowed descriptors and remain open.

## Focused executable checks

[`tests/extended_openssl_hash_execution.rs`](../tests/extended_openssl_hash_execution.rs)
compiles the sample through the native C linking profile and checks the linked
ELF's generated function boundaries before execution. Its cases cover:

- OpenSSL CLI comparison for all four algorithms, empty and binary inputs,
  1,024-byte read boundaries and larger streams.
- CLI validation, help, exact byte limits, zero input limits, exact I/O attempt
  limits and argument count/byte bounds.
- The actual sample stream loop with scripted short reads/writes, EINTR,
  EAGAIN, host failures, invalid counts, zero progress, EOF probing and retry
  exhaustion.
- A test-only native observer that forwards normal calls to `libcrypto`,
  forces each EVP failure stage, and checks method/context release on success
  and on errors. Real descriptor input and output errors are also covered.

Rust, the OpenSSL command and the small C observer provide test orchestration,
the digest reference and native lifecycle observation. Production argument
handling, streaming, bounds, cleanup and hexadecimal output are Lanius code.
All three focused groups pass in 10.11 s, recorded in
`target/stdlib-work/openssl-hash-execution-first.log`. These checks compile the
actual sample on the GPU and execute its linked Linux x86_64 ELF with dynamic
`libcrypto.so.3`. The shared native ABI/linking and digest gates have also
passed; their receipts are recorded in the [native C guide](library-native-c.md).

```sh
timeout --kill-after=2s 110s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test extended_openssl_hash_execution -- --nocapture --test-threads=1
```
