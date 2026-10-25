# Binary TAR application

[`tar_bytes.lani`](../sample_programs/library/tar_bytes.lani) creates one-file
ustar archives, lists archive names and reads one exact member. It combines
[`ext::tar`](extended-tar.md), [`ext::compression`](extended-compression.md),
CLI parsing, owned byte buffers, argument snapshots and native I/O. All
library and application behavior is implemented in Lanius.

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  --stdlib-root stdlib --source-root extended \
  sample_programs/library/tar_bytes.lani -o target/stdlib-work/tar-bytes
printf 'hello\n' | target/stdlib-work/tar-bytes --create greeting --gzip \
  > target/stdlib-work/greeting.tar.gz
target/stdlib-work/tar-bytes --gzip --list \
  < target/stdlib-work/greeting.tar.gz
target/stdlib-work/tar-bytes --gzip --get greeting \
  < target/stdlib-work/greeting.tar.gz
```

Listing writes NUL-delimited raw names, including the final NUL. A terminal
may not visibly separate them. `--get` writes only the selected data bytes.
Neither operation creates filesystem objects or follows archive links.

## Interface

```text
tar-bytes [--list|--get NAME|--create NAME] [--gzip]
          [--max-input N] [--max-archive N] [--max-output N]
          [--max-entries N]
```

No mode means `--list`. At most one explicit mode is accepted. Short forms are
`-t`, `-g NAME`, `-c NAME`, `-z` and `-h`/`--help`. Operands and unknown options
are errors. Limits are unsigned decimal integers through 2,147,483,647;
repeated limits use the last value. Parsing finishes before help or input I/O.
Argument capture permits 32 arguments and 4,096 total argument bytes.

Names are exact raw bytes: no Unicode conversion, separator folding,
dot-segment removal or path normalization. Prefix and name fields are joined
with the ustar separator. A directory named `folder/` differs from `folder`.
NUL cannot appear in a host argument or accepted ustar name. Newlines,
non-UTF-8 bytes, absolute paths and `..` are preserved; the program does not
interpret names as host paths.

`--get` requires one matching regular or contiguous-file entry. No match,
multiple exact matches, and a matching directory/device/link/FIFO are distinct
errors. Links are never resolved. Listing retains every supported entry kind,
including duplicate names. Creation emits a regular file with mode 0644,
zero owner/group/time, empty owner names and exactly two final zero blocks.
Output is deterministic, including the optional gzip envelope.

## Bounds and integrity

| Limit | Default | Meaning |
| --- | --- | --- |
| `--max-input` | 16,777,216 | Bytes read from stdin, in every mode |
| `--max-archive` | 67,108,864 | Raw TAR bytes, including headers and padding; also caps gzip decompression |
| `--max-output` | 67,108,864 | Final stdout bytes: archive, selected payload or NUL listing |
| `--max-entries` | 4,096 | All archive members, including directories and links; creation requires at least one |

The complete bounded stdin is read into owned storage. For gzip input, the
container decoder validates all members, checksums, sizes and trailing data
before TAR parsing. Its gzip member limit is 1,024. The TAR reader checks every
header, data extent, zero padding and final footer before a successful listing
or read. A selected member near the start does not bypass a malformed later
header. Extra complete zero blocks are accepted; nonzero trailing data and
partial final blocks are rejected.

Raw TAR has a header checksum only. It cannot detect a changed payload byte;
`--gzip` adds container CRC-32 validation. This utility accepts the library's
strict POSIX ustar profile; unsupported GNU/PAX extensions and base-256 numeric
fields report format failure.

Listing makes two linear passes over the immutable archive, first validating
and measuring, then copying names into one exact output allocation. Reading
copies the selected member after complete archive validation. Creation allocates
the complete raw archive; gzip adds its encoder's scratch and result owners.
Limits bound each relevant buffer, rather than their combined peak memory.
Owners remain alive while borrowed views are used, and are released before
stdout or on every returned failure.

No stdout begins before a complete result is prepared. I/O failure while
writing can leave a stdout prefix. Error diagnostics go to stderr and are best
effort; failure to report a diagnostic preserves the original exit status.

| Exit | Meaning |
| --- | --- |
| 0 | Success or help |
| 2 | Arguments, archive/member format, lookup ambiguity, missing member or resource limit |
| 3 | Argument host read, stdin or stdout I/O failure |
| 4 | Allocation failure |

Interrupted native reads/writes retry. Would-block errors and a zero-progress
write return I/O failure. Borrowed stdin/stdout/stderr handles are not closed.

## Executable evidence

[`extended_tar_bytes_execution.rs`](../tests/extended_tar_bytes_execution.rs)
compiles the actual application and executes the emitted x86_64 Linux ELF.
Coverage includes independent Python `tarfile` reading and writing, binary
payloads, 511/512/513-byte boundaries, 65,536-byte input, maximum ustar path
splits, raw argument bytes, directories/links/duplicates, exact limits,
malformed late headers, truncated footers and corrupt gzip checksums.
Allocation and read/write fault injection checks cleanup and output prefixes.

All three application groups passed. The two interoperability/host-failure
groups passed in the initial run; the resource/format group passed after its
last additions in 5.30 s. Checks include every observed allocation failure and
read/write failure, interrupted calls, would-block, zero-progress writes and
failed error diagnostics. Raw payload corruption is explicitly accepted by
TAR, while a corrupt gzip CRC fails before stdout.

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test extended_tar_bytes_execution -- --test-threads=1
```

GPU compilation of a native executable does not establish GPU-kernel execution.

## Native scale measurements

On 2026-10-23, the application was pinned to CPU 8 with one warmup and five
measured processes per row. Every output was checked; Python `tarfile`
independently validated created archives. The 1,048,576-byte payload repeats
`bytes(0..255)` and `entry,id,value\nexample,123,456\n`. Measurements include
process startup, binary pipes, argument capture, input buffering, archive
validation, result ownership and output. Other desktop work was not controlled.

| Format | Operation | Archive bytes | Median | Range |
| --- | --- | --- | --- | --- |
| TAR | Create | 1,050,112 | 183.176 ms | 160.294–264.180 ms |
| TAR | Read member | 1,050,112 | 160.052 ms | 158.165–269.452 ms |
| TAR | List | 1,050,112 | 138.204 ms | 137.553–139.429 ms |
| TAR + gzip | Create | 11,341 | 367.243 ms | 366.270–412.903 ms |
| TAR + gzip | Read member | 11,341 | 141.687 ms | 139.796–143.043 ms |
| TAR + gzip | List | 11,341 | 120.184 ms | 119.389–122.135 ms |

The creation profile uses one raw result allocation plus input storage; gzip
adds the compression owners documented by that module. These are application
measurements, without a throughput comparison to another TAR implementation.
