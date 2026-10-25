# OpenSSL digest contexts

`ext::openssl_digest` hashes byte views through OpenSSL 3's EVP interface. It
provides streaming SHA-256, SHA-512, SHA3-256 and SHA3-512 contexts, with 32-byte
or 64-byte output. OpenSSL performs every digest operation. The Lanius module
handles byte layout, errors and resource ownership.

The [checked native C profile](library-native-c.md) executes this module on
Linux x86_64/glibc with dynamic `libcrypto.so.3`. Four focused runtime groups
pass 2,124 digest cases and 12 native failure modes. The
[stdin hashing program](extended-openssl-hash.md) supplies a real consumer.

## Public API

Import `ext::openssl_digest` through the `extended` source root and `stdlib`
standard library root.

| API | Result |
| --- | --- |
| `Algorithm::{Sha256,Sha512,Sha3_256,Sha3_512}` | Select a fixed-size EVP digest. |
| `digest_size(algorithm)` | Return the selected output length, 32 or 64. |
| `new(algorithm)` | Return `Result<Context,Failure>`. |
| `context.borrow()` | Borrow the active manual owner. |
| `context.is_open()` | Report whether that owner still holds an initialized operation. |
| `context.output_size()` | Return its digest size, including after cleanup. |
| `context.update(input)` | Consume the whole `View<u8>` and return its byte count. |
| `context.finish_into(output)` | Write the first `output_size()` bytes of a `View<u8>`, close the context, and return the count. |
| `context.destroy()` | Close an unfinished operation; repeated calls through the same owner do nothing. |

Use `View::subview` to select input or output ranges. The module rejects a
negative start, negative length or a start-plus-length overflow before accessing
OpenSSL. Metadata checks precede the open-state check. A view still requires
physically backed storage: its logical length cannot establish a pointer's
validity. Invalid backing can trap during Lanius indexing.

An empty update succeeds with zero bytes while the context is open and makes no
native call. Update or finish after finish/destroy returns `Cause::Closed`.
Finish rejects a short output view with `Cause::OutputTooSmall`, preserving the
operation and output so the caller can retry with a larger view. Malformed view
metadata also preserves both.

## Streaming, byte layout and output

Lanius byte views can have different physical strides. Update copies each
logical input chunk into 1024 packed bytes backed by `[i32;256]`, then calls
`EVP_DigestUpdate`. It converts each positive chunk length to C `size_t` only
after the view checks. The native call borrows the staging buffer until it
returns; OpenSSL does not retain an input pointer.

New contexts fetch the selected implementation from OpenSSL's default library
context, using its configured provider and property policy. The algorithm name
is copied from a counted Lanius string into packed storage with an explicit NUL
terminator. No implicit string terminator crosses the C boundary.

The fetched output size must match the selected algorithm before initialization.
Finish uses a separate 64-byte packed output buffer. Its optional C
`unsigned int *` length argument is null because the fixed output size is
already known. Only successful finalization copies bytes into caller storage;
the remaining output view is untouched. Finish closes native resources before
copying the successful digest.

## Errors and cleanup

`Failure` has these fields:

| Field | Meaning |
| --- | --- |
| `cause` | `Bounds`, `Closed`, `OutputTooSmall`, `UnexpectedSize(actual)`, or `OpenSsl`. |
| `stage` | `Fetch`, `Size`, `Context`, `Init`, `Update`, or `Final`. |
| `code` | OpenSSL's earliest queued diagnostic for a failed native call; zero for wrapper errors. A native failure can also have code zero. |
| `completed` | Bytes successfully consumed by earlier native chunks in this update call. Zero for every other operation. |

The module clears the current thread's OpenSSL error queue immediately before
each fallible native operation. On failure it captures the first queued code
and clears the remaining queue before cleanup. It owns those queue operations;
callers must not keep outstanding raw OpenSSL diagnostics across wrapper calls.
Diagnostic codes are values, so cleanup cannot invalidate the captured error.

A failed native update closes the operation. Its failed chunk does not count
toward `completed`, and the context cannot be resumed. Earlier successful
updates are not included in that call's count. Failed finalization also closes
the operation and leaves caller output untouched. Construction failures release
every resource already acquired.

One active owner controls the context and fetched algorithm. Copies alias those
resources and must stay inactive. Use `borrow()` for operations; do not edit the
owner's fields, access it concurrently, or overlap its storage with input/output
views. `destroy()` clears both stored pointers before freeing the context and
then the algorithm. OpenSSL owns both allocations; Lanius never deallocates them
through its allocator. The language does not automatically destroy or track
copies of this owner.

## Native profile

The first supported profile targets Linux x86_64 with the System V C ABI and
LP64 widths: `int` is 32 bits; pointers, `size_t` and `unsigned long` are 64 bits.
The raw declarations use only `ptr`, `i32`, `usize`, `u64` and void. Every raw
declaration is `pub extern "C"`; each retains OpenSSL's native symbol name.

The host audit found OpenSSL 3.0.13 headers and both `libcrypto.so` and
`libcrypto.so.3`. The default provider advertises all four selected algorithms.
Linking requires `libcrypto`; the digest module does not require `libssl`.
OpenSSL's provider/configuration policy can make a fetch unavailable, which the
module reports at `Stage::Fetch`.

Build with `--native-link --native-library crypto` through the
[native C profile](library-native-c.md). It emits ordinary ELF objects and uses
the system C driver and CRT for libc startup and thread local storage. The
checked call path supplies argument/return normalization, stack alignment,
register preservation and symbol resolution. Default raw syscall startup is
not the supported OpenSSL entry. The module does not use C aggregate layout,
callbacks, foreign thread entry or a per-library compiler service.

The raw declarations expose an unchecked native boundary: direct callers own
all pointer, buffer, lifetime and cleanup requirements. The checked context
methods supply the staging and lifecycle contract described above.

## Executable checks

[`extended_openssl_digest_execution`](../tests/extended_openssl_digest_execution.rs)
passes four focused groups in 8.11 s. The retained receipt is
`target/stdlib-work/openssl-digest-execution-first.log`. The checks compile the
real Lanius module on the GPU, inspect the linked native ELF and execute it
against dynamic `libcrypto.so.3`.

The 2,124 digest cases cover empty and `abc` reference values, binary NUL and
all-byte input, every partition of short inputs, chunked long inputs, nonzero
view offsets, and stack, packed and Vec byte layouts. Digest block boundaries
and 1023/1024/1025-byte staging boundaries are included. Lifecycle checks cover
empty updates, short-output retry, malformed metadata, closed contexts,
sentinels and repeated destruction.

Twelve native failure modes exercise fetch/size/context/init/update/final
failures, consumed prefixes of 0/1024/2048 bytes, first-error capture, absent
diagnostics, final-buffer scribbles and exactly-once resource release. The
OpenSSL CLI and independent CPython SHA implementations are test oracles;
Rust/Python and the C fault observer supply no production cryptography.
Native subprocesses have time bounds.

```sh
timeout --kill-after=2s 110s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test extended_openssl_digest_execution -- --nocapture --test-threads=1
```

The primary API sources are OpenSSL's [EVP digest documentation](https://docs.openssl.org/3.0/man3/EVP_DigestInit/)
and [error queue documentation](https://docs.openssl.org/3.0/man3/ERR_get_error/).
The installed `openssl/evp.h` and `openssl/err.h` confirm the audited signatures.
