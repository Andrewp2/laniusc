# ZIP byte-stream application

`sample_programs/library/zip_bytes.lani` is a complete native application using
[`ext::zip`](extended-zip.md), CLI parsing, bounded owned I/O, generic optional
values, vectors and descriptor streams. It reads binary stdin and writes binary
stdout. It creates ZIP archives and reads archive contents without filesystem
extraction.

Executable evidence covers **x86_64 Linux using the GPU compiler to produce
native programs**. GPU-kernel execution and other targets are unverified.

## Modes

```text
zip-bytes [--list|--get NAME|--create NAME|--verify]
          [--store] [--utf8]
          [--max-input N] [--max-output N] [--max-archive N]
          [--max-entries N] [--max-entry N] [--max-total N] [--max-work N]
```

Choose at most one mode, including repeated occurrences of the same mode.
The default is `--list`. `-t`, `-g`, `-c` and `-v` are the respective short
options. `--help` or `-h` prints usage after validating the arguments and does
not read stdin. Positional operands and empty get/create names are errors.

| Mode | Input | Output and validation |
| --- | --- | --- |
| `--list` | Complete ZIP archive | Raw entry names, each followed by NUL, in central-directory order. Validates all archive metadata before output. Payloads are not decompressed or CRC checked. |
| `--get NAME` | Complete ZIP archive | The selected member's bytes. Validates all archive metadata, requires exactly one raw-byte name match, then checks that payload's exact size, complete compressed-data consumption and CRC before output. |
| `--verify` | Complete ZIP archive | No stdout. Validates all metadata and extracts/checks every payload sequentially, releasing each before checking the next. |
| `--create NAME` | One member's bytes | Complete single-entry ZIP archive, using DEFLATE by default. The archive is built successfully before output begins. |

`--store` or `-s` chooses uncompressed ZIP storage during creation. `--utf8`
sets the ZIP UTF-8 metadata flag and requires the creation name to be valid
UTF-8. Both options require `--create`; using them in another mode is an error.
Without `--utf8`, creation preserves name bytes with the encoding flag unset.
Readers may then interpret non-ASCII names using CP437 or another legacy policy.
Use `--utf8` when interoperating with Unicode filenames.

Creating the same name, bytes and options produces the same archive. Creation
uses the library's stable 1980-01-01 timestamp and empty archive comment. The
writer accepts relative forward-slash names up to 65535 bytes and rejects
leading slash, a colon in the second byte, backslash and NUL. It does not
normalize dot components. The CLI also rejects an empty creation name.

Reads preserve raw names, including non-UTF-8 bytes, slashes, backslashes,
whitespace and dot components. Name matching is byte-for-byte, without case
folding or path normalization. Duplicate names can be listed and verified, but
`--get` rejects duplicate matches. A name containing NUL cannot be represented
unambiguously in the listing, so `--list` rejects the complete operation before
output if any name contains NUL. `--get` and `--verify` do not impose that
listing-specific restriction. Shell argument conventions already prevent a
requested name from containing NUL.

Listing is a metadata operation. A bad CRC or malformed compressed payload in
an otherwise structurally valid archive can still be listed. `--get` checks
only its selected payload; a corrupted unselected payload can remain undetected.
Use `--verify` when every payload's integrity matters. Directories and other
ZIP attribute values are metadata here; getting a directory entry returns its
stored payload, usually empty. No member name is used as a filesystem path.

The underlying ZIP profile supports classic single-disk stored and DEFLATE
entries, including compatible data descriptors. ZIP64, encryption, unsupported
methods and other unsupported format extensions fail explicitly. See the
[library contract](extended-zip.md) for the complete accepted format.

## Resource bounds

| Option | Default | Contract |
| --- | ---: | --- |
| `--max-input` | 16777216 | Maximum stdin bytes, including raw member bytes during creation |
| `--max-output` | 67108864 | Maximum stdout bytes: complete created archive, selected payload or NUL-delimited names |
| `--max-archive` | 67108864 | Maximum ZIP archive bytes during reading or creation |
| `--max-entries` | 4096 | Maximum directory entries; creation needs at least one |
| `--max-entry` | 67108864 | Maximum declared uncompressed size of every entry |
| `--max-total` | 134217728 | Maximum sum of declared uncompressed entry sizes |
| `--max-work` | 16777216 | ZIP parser/encoder work budget, as defined by the library |

Counts use unsigned decimal syntax without a sign. Byte and entry bounds must
fit i32; total size and work bounds accept u64. All may be zero. Exact input,
output and archive limits are accepted. Input collection checks EOF, so a byte
beyond `--max-input` fails before archive processing or stdout.

`--max-entry` and `--max-total` apply to the entire archive, including entries
that are not requested by `--get`. The parser validates their declared sizes
before extraction. Payload decoding must then produce exactly its declared
size. `--verify` produces no stdout and does not use `--max-output` as an
extraction limit; its per-entry and aggregate limits still apply. Work limits
cover ZIP parsing/encoding, with payload processing also bounded by input and
uncompressed-size limits.

The program buffers stdin and its complete stdout result. Verification keeps
the input archive plus one extracted payload at a time. Limits bound individual
data sizes, not peak process memory: argument storage, vector growth, codec
scratch and old/new buffers during growth add overhead. The argument snapshot
accepts at most 64 arguments after the executable and 131072 aggregate argument
bytes.

## Errors and output

Exit status is 0 for success, 2 for arguments, format, missing/duplicate member
or resource limits, 3 for stdin/stdout I/O failure, and 4 for allocation failure.
Diagnostics identify the failure category on stderr and are best effort: a
failed stderr write does not replace the original status.

Format, metadata, selected-payload integrity and limit errors produce no stdout.
Metadata errors late in the archive are detected before listing or returning
an earlier selected entry. An I/O failure during final output may leave a
written prefix. EINTR is retried; EAGAIN, other host errors and a zero-progress
write fail. All owned arguments, input, output and codec allocations are
released on success and failure.

## Build and use

From the repository root, with an existing compiler build:

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  --stdlib-root stdlib --source-root extended \
  sample_programs/library/zip_bytes.lani -o /tmp/zip-bytes

printf 'example payload\n' | timeout --kill-after=2s 10s \
  /tmp/zip-bytes --create data.txt > /tmp/example.zip
timeout --kill-after=2s 10s /tmp/zip-bytes --list \
  < /tmp/example.zip > /tmp/member-names.bin
timeout --kill-after=2s 10s /tmp/zip-bytes --get data.txt \
  < /tmp/example.zip > /tmp/data.txt
timeout --kill-after=2s 10s /tmp/zip-bytes --verify < /tmp/example.zip
```

The listing file contains `data.txt` followed by NUL. UTF-8 creation can use
`--create 'café.txt' --utf8`; use `--store` to select stored members.

## Verification evidence

`tests/extended_zip_bytes_execution.rs` executes the compiled Lanius
application. Python's standard `zipfile` is an independent test reference,
not a production implementation or transport. Five focused groups cover:

- Stored and DEFLATE creation readable by Python, empty and binary input,
  chunk boundaries, larger repeated input, deterministic output and UTF-8 flags.
- Reading Python multi-entry archives with and without data descriptors,
  directory/empty entries, raw non-UTF-8 names, Unicode and exact selected bytes.
- Argument combinations, empty inputs, exact input/archive/output/entry/total
  limits, work limits and mode-specific flags.
- Late invalid metadata, corrupt selected and unselected CRCs, duplicate
  names, NUL names, trailing/truncated data and unsupported/encrypted metadata.
- Every allocation, read and write observed in successful create-stored,
  create-DEFLATE, list, get and verify runs, injected individually; allocation
  traces show no leaks. EINTR retries, EAGAIN, zero-progress output and failure
  of diagnostics are also exercised.

All five groups passed: the interoperability, metadata and fault groups in a
7.03-second run, and the argument/limit group in a 5.40-second focused run.
Run the focused suite with:

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR=/home/andrew-peterson/code/laniusc/target/stdlib-build \
  CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test extended_zip_bytes_execution -- --nocapture
```

## Native measurements

Measured on 2026-10-23, AMD Ryzen 9 5950X, Linux x86_64, pinned to CPU 8 with
the existing compiler based on `441e66f9`. One warm run preceded five measured
runs, alternating case order. Parent CPU tests and benchmarks were idle.
Times include process startup, argument handling, bounded input collection,
encoding/decoding, CRC checking, final output and Python subprocess pipe
transport. Input generation and Python `zipfile` validation were outside the
timed interval. No compiler startup is included.

| Operation | Stdin bytes | Stdout bytes | Median ms | Min–max ms |
| --- | ---: | ---: | ---: | ---: |
| Create DEFLATE, random input | 1048576 | 1048779 | 542.912 | 536.312–549.255 |
| Create DEFLATE, repeated records | 1048576 | 8282 | 359.565 | 357.973–371.706 |
| Create stored, repeated records | 1048576 | 1048696 | 190.342 | 189.613–196.795 |
| Get repeated-record payload | 8282 | 1048576 | 88.531 | 87.370–89.659 |
| Verify repeated-record archive | 8282 | 0 | 82.799 | 76.372–89.008 |

The random input uses xorshift64 shifts 13, 7, 17, seed
`0x0123456789abcdef`, taking each resulting low byte. Repeated records are
`data=123456789\tstatus=success\n`, truncated to 1 MiB. Creation uses the names
`random.bin` and `records.bin`. These observations establish whole-application
behavior at that size; they are not comparisons with another compiler or ZIP
implementation.
