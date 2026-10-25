# Compressing binary streams

[`sample_programs/library/compress_bytes.lani`](../sample_programs/library/compress_bytes.lani)
combines CLI parsing, owned arguments, bounded input buffering,
[compression containers](extended-compression.md) and checked native output.

```text
compress-bytes [-d] [--format raw|zlib|gzip]
               [--max-input N] [--max-output N] [--max-members N]
```

Input is binary stdin and output is binary stdout. Encoding is the default;
`--decompress` / `-d` selects decoding. The default format is gzip. `--format`
or `-f` selects raw DEFLATE, zlib or gzip explicitly. Short groups such as
`-dfgzip` work. There are no filename operands, automatic format detection or
implicit extraction of names stored in gzip headers.

For example, from the repository root:

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  --stdlib-root stdlib --source-root extended \
  sample_programs/library/compress_bytes.lani -o /tmp/compress-bytes

printf '%s\n' 'a repeated line' 'a repeated line' > /tmp/compression-input
timeout --kill-after=2s 20s /tmp/compress-bytes \
  < /tmp/compression-input > /tmp/compression-input.gz
timeout --kill-after=2s 20s /tmp/compress-bytes -d \
  < /tmp/compression-input.gz > /tmp/compression-restored
cmp /tmp/compression-input /tmp/compression-restored
```

## Limits and output

Input defaults to at most 16 MiB. Output defaults to at most 64 MiB, and decoding
accepts at most 1,024 members. Limits are unsigned decimal values through
`i32::MAX`; negative values, signs, overflow and missing values are errors.
Repeated options use their last values. Argument capture allows 32 arguments
and 4,096 total argument bytes. `--help` / `-h` prints usage after validating
the provided command-line syntax.

`--max-input` bounds all stdin bytes, in either mode. During encoding,
`--max-output` bounds the complete compressed result including the container.
During decoding it bounds cumulative decoded bytes across members.
`--max-members` applies to decoding; raw DEFLATE and zlib each count as one
member. Encoded empty inputs and decoded empty members are supported with a
zero byte limit where appropriate.

The program reads and transforms the complete bounded input before writing
stdout. Invalid input, checksum errors, limit errors and allocation failures
therefore publish no binary output. Once output starts, an I/O failure can
leave a written prefix. These are bounded whole-input operations; memory can
include input, codec scratch, growing results and temporary old/new allocation
pairs. Byte limits are not an exact process-memory quota.

The [container contract](extended-compression.md) defines accepted gzip optional
headers, concatenated members, window validation, checksums and strict rejection
of trailing junk. Preset zlib dictionaries return an explicit unsupported error.
Compression uses fixed Huffman LZ77 or smaller stored blocks; no compression
level selector is exposed.

## Errors and ownership

| Exit | Meaning |
| --- | --- |
| 0 | Successful complete output or help |
| 2 | Invalid arguments, format, checksum, input/output/member limit or other data error |
| 3 | Input or output I/O error |
| 4 | Allocation failure |

Failures report a short diagnostic on stderr, including distinct input/output
limits, truncation, checksum, header and unsupported dictionary messages.
Diagnostics are best effort: failure to write stderr preserves the original
exit status. Input and output retry EINTR, and report EAGAIN or zero-progress
writes as I/O failures. The program frees argument, input, scratch and output
owners on every completed success/error path and borrows stdin/stdout/stderr
without closing their descriptors.

## Executable evidence

`tests/extended_compress_bytes_execution.rs` compiles and executes the Lanius
application on **x86_64 Linux**. Three groups passed in 9.15 seconds:

- Independent zlib interoperability in all three formats, empty/binary inputs,
  descriptor chunk boundaries, deterministic output, real compression and
  larger decoded inputs above 256 KiB. Independent decoding checks that the
  encoded output contains exactly one complete stream.
- CLI validation, help, exact byte/member bounds, gzip concatenation, malformed
  headers, truncation, checksums and trailing junk, all before stdout publication.
- Every observed allocation, read and write failing in turn in both modes,
  owner cleanup, valid output prefixes, EINTR retry, EAGAIN, zero-progress writes
  and simultaneous stdout/diagnostic failures.

Rust and Python provide orchestration and reference zlib only. Production
compression and I/O behavior are implemented in Lanius. GPU-kernel execution
and other operating systems have not been verified.

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test extended_compress_bytes_execution -- --nocapture
```

Native runtime and compiler measurements are recorded in
[compression performance](extended-compression-performance.md).
