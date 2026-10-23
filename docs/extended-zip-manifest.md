# Checked ZIP manifest in CBOR

[`zip_manifest.lani`](../sample_programs/library/zip_manifest.lani) reads a ZIP
archive from binary stdin, validates every payload and emits one CBOR manifest
to stdout. It combines the real ZIP and CBOR libraries with argument parsing,
owned byte buffers and native descriptor I/O. All production behavior is Lanius.

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  --stdlib-root stdlib --source-root extended \
  sample_programs/library/zip_manifest.lani -o target/stdlib-work/zip-manifest
timeout --kill-after=2s 20s target/stdlib-work/zip-manifest \
  < target/stdlib-work/example.zip > target/stdlib-work/manifest.cbor
```

The input uses the [classic single-disk ZIP profile](extended-zip.md). Metadata,
local/central agreement, descriptors and resource limits are checked first.
Every member is then extracted, checked for exact size and complete compressed
input consumption, and CRC checked. A late bad member prevents all output.
Names are never interpreted as filesystem paths.

## Manifest schema

The one root map contains `format: "zip"` and `entries: [...]`. Entries appear
in central-directory order, including duplicate names. Each entry map contains:

| Key | CBOR value | Meaning |
| --- | --- | --- |
| `name` | Byte string | Exact original name bytes, including non-UTF-8 bytes or NUL |
| `compressed_size` | Unsigned integer | Declared and checked compressed span size |
| `size` | Unsigned integer | Checked decoded byte count |
| `crc32` | Unsigned integer | Checked ZIP CRC-32 |
| `method` | Unsigned integer | 0 for stored, 8 for DEFLATE |
| `utf8` | Boolean | Original ZIP metadata encoding flag |

Maps/arrays have definite lengths, integer and length headers use their shortest
forms, and fields use a stable order. The same archive produces the same
manifest. The application makes no RFC core-deterministic map-order claim.
Names use byte strings, so no decoding, replacement or implicit Unicode
conversion changes them. An empty archive produces a map with an empty array.
Payload bytes, ZIP comments, extra fields, timestamps and attributes are not
included in this schema.

## Interface and limits

```text
zip-manifest [--max-input N] [--max-output N] [--max-entries N]
             [--max-entry N] [--max-total N] [--max-work N]
```

| Option | Default | Meaning |
| --- | --- | --- |
| `--max-input` | 16,777,216 | Complete ZIP stdin bytes and parser archive limit |
| `--max-output` | 67,108,864 | Complete encoded manifest bytes |
| `--max-entries` | 4,096 | Archive directory entries |
| `--max-entry` | 67,108,864 | Decoded bytes of each member |
| `--max-total` | 134,217,728 | Aggregate declared and subsequently checked decoded bytes |
| `--max-work` | 16,777,216 | ZIP structural validation budget |

Unsigned decimal values through `i32::MAX` are accepted for byte and entry
bounds; total/work accept the full `u64` range. Limits may be zero. Repeated
limits use their last values. Unknown options, operands, signs and overflow
are errors. `--help`/`-h` prints usage after complete argument validation and
does not read stdin. Argument capture permits 32 arguments and 4,096 total bytes.

The CBOR encoder separately uses eight frame slots, at most 1,000,000 items,
16,777,216 bytes per string and 134,217,728 work units. ZIP's classic entry
count and name bounds keep normal manifests within those limits. An encoder
limit still fails explicitly; `--max-work` configures ZIP validation only.
All output limits are measured before stdout begins.

## Ownership and failure behavior

The program buffers complete bounded input. It reserves exactly `7 + 14*N`
CBOR event slots, borrows names from that input and extracts only one payload
at a time. Each checked payload is destroyed before processing the next.
After checking every payload, it measures the event encoding, allocates an
exact output vector and encodes into it. Events and frame scratch are freed,
then the input owner is freed, before stdout starts. This retains no escaped
borrowed names. Limits bound individual buffers, not their combined peak size.

Format, limit, checksum and allocation failures produce no stdout. An output
I/O failure may leave a written prefix. Diagnostics are best effort on stderr;
failure to report an error preserves the original status. EINTR retries;
EAGAIN and a zero-progress output write fail. Borrowed descriptors are not closed.

| Exit | Meaning |
| --- | --- |
| 0 | Success or help |
| 2 | Arguments, ZIP/CBOR format, integrity or resource limit |
| 3 | Host argument read, stdin or stdout I/O failure |
| 4 | Allocation failure |

## Executable evidence

Three runtime groups in
[`extended_zip_manifest_execution.rs`](../tests/extended_zip_manifest_execution.rs)
passed in 6.96 s. They compile and execute the application on x86_64 Linux.
Python `zipfile` supplies independent archives; a separate test-only CBOR
decoder checks the manifest's schema, values, shortest headers and complete
consumption. There is no JSON transport or external CBOR package dependency.

Coverage includes both ZIP methods, descriptors, empty/directory entries,
Unicode and binary/NUL names, duplicates, 1,024-byte boundaries, 65,536-byte and
1 MiB payloads, deterministic results, exact limits, malformed later metadata
and late CRC failures. Every allocation and read/write observed during a
successful multi-entry run is fault-injected individually, with no leaked
owners. Interrupted calls, would-block, zero writes, failed diagnostics and
cleanup after late payload failure are also checked.

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test extended_zip_manifest_execution -- --test-threads=1
```

GPU compilation to this native executable does not establish GPU-kernel execution.

## Native scale measurements

On 2026-10-23, the process was pinned to CPU 8 with one warmup and five measured
runs. Each archive contains 1,048,576 total decoded bytes, split evenly among
the stated number of DEFLATE members. Data repeats `bytes(0..255)` followed by
`entry,id,value\nexample,123,456\n`. Python `zipfile` generated the input; every
output was independently decoded and compared with its metadata outside the
timed interval. Times include startup, pipes, buffering, all payload checks,
CBOR event ownership and output. Other desktop work was not controlled.

| Members | ZIP bytes | CBOR bytes | Median | Range |
| --- | --- | --- | --- | --- |
| 1 | 5,076 | 96 | 100.737 ms | 99.367–101.117 ms |
| 1,024 | 423,985 | 74,775 | 409.868 ms | 396.525–502.452 ms |

These are whole-program scale observations, without a throughput comparison
to another serializer or compiler.
