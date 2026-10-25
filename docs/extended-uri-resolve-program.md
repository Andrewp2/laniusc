# Resolving URI references from the command line

[`sample_programs/library/uri_resolve.lani`](../sample_programs/library/uri_resolve.lani)
combines CLI parsing, owned byte arguments, borrowed URI parsing, owned
[RFC 3986 resolution](extended-uri-resolve.md) and checked output streams.

```text
uri-resolve [--max-bytes N] [--] BASE REF...
```

BASE must have a scheme and no fragment. At least one reference is required;
an empty string is a reference. Each result is written as its encoded URI
followed by LF. URI syntax excludes raw newlines, so record boundaries remain
unambiguous. No percent decoding, DNS lookup or network access occurs.

For example:

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  --stdlib-root stdlib --source-root extended \
  sample_programs/library/uri_resolve.lani -o /tmp/uri-resolve

timeout --kill-after=2s 10s /tmp/uri-resolve \
  'https://example.test/a/b?old' '../c' '?new' '%2e/%2f'
```

Output:

```text
https://example.test/c
https://example.test/a/b?new
https://example.test/a/%2e/%2f
```

Resolution preserves percent encodings and case. Literal dot segments are
removed where the RFC requires; encoded dots and slashes remain data. A
reference with its own scheme is resolved strictly: `https:g` stays `https:g`.
An empty reference inherits the base query, while `?` supplies a present empty
query. The resolver documentation defines the complete selection/merge rules.

`--max-bytes N` / `-n N` limits each final URI, excluding its output LF. It
defaults to 1,048,576 and accepts unsigned decimal values up to `i32::MAX`.
Options may appear among operands; the last limit applies to every reference,
including those listed earlier. Use `--` to pass a reference beginning with a
dash. Snapshot limits are 1,026 arguments and 65,536 total argument bytes.

The application validates all argument syntax, the base and every reference
before emitting results. Each resolution is then independently owned and freed
after writing. A later output-limit, allocation or I/O error can leave previous
results or a partial output write. Invalid later reference syntax produces no
output because it is found during validation. Reads from stdin are not used.

Exit 0 means success, 2 means arguments/syntax/base/output limits, 3 means output
I/O failure, and 4 means allocation failure. Writes retry EINTR; EAGAIN and
zero-progress writes fail. `--help` / `-h` prints usage without requiring
operands; malformed provided options or URI operands still fail validation.

## Execution evidence

[`tests/extended_uri_resolve_program_execution.rs`](../tests/extended_uri_resolve_program_execution.rs)
compiles and executes this Lanius application on **x86_64 Linux**. Its three
groups passed in 7.55 seconds:

- Multiple references, inherited/empty queries, authority changes, strict
  scheme handling, encoded dots/slashes, dash-prefixed references, final option
  precedence, exact output limits, 64 KiB output and 1,025 references.
- Complete pre-output validation, base/argument/count/byte limits and help.
- Every observed allocation and output syscall failing in turn, owner cleanup,
  valid output prefixes, EINTR retry, EAGAIN and zero-progress writes.

Rust provides test orchestration; production behavior is Lanius. GPU-kernel
execution and other hosts are unverified. Run the application gate with:

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test extended_uri_resolve_program_execution -- --nocapture
```

## Native performance sample

On 2026-10-23, one warmup and five measured processes per workload ran on CPU 0.
Each process resolved one reference against `http://example.test/a/b`, checked
its exact output and exited. Times include startup, argument snapshots, syntax
validation, allocation, resolution, writes and cleanup.

| Reference | Input bytes | Median | Measured range |
| --- | --- | --- | --- |
| 512 copies of `a/`, then `g` | 1,025 | 2.835 ms | 2.607–3.175 ms |
| 8,192 copies of `a/`, then `g` | 16,385 | 13.467 ms | 13.267–16.089 ms |
| 512 copies of `a/../`, then `g` | 2,561 | 3.118 ms | 3.086–3.246 ms |
| 8,192 copies of `a/../`, then `g` | 40,961 | 35.270 ms | 32.993–36.222 ms |

The cancelling paths reduce to the base directory plus `g`; the ordinary paths
retain all their segments. These measurements cover both growing output and
repeated dot-segment removal at the stated sizes. They measure native library
execution and do not compare compiler performance or another URI implementation.
