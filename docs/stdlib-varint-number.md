# Convert one varint number

`sample_programs/library/varint_number.lani` converts one native 64-bit integer
to or from a canonical base-128 varint:

With the compiler already built, compile from the repository root:

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc sample_programs/library/varint_number.lani --stdlib-root stdlib -o target/stdlib-work/varint_number
target/stdlib-work/varint_number encode-u64 300 > number.varint
target/stdlib-work/varint_number decode-u64 ac02
target/stdlib-work/varint_number encode-i64 -1 > signed.varint
target/stdlib-work/varint_number decode-i64 01
```

The decode examples print `300` and `-1`, respectively, followed by LF. Encode
output is raw binary without a newline. The CLI is exactly
`varint_number MODE VALUE`, or sole `--help` / `-h`. It never reads stdin.

## Values and wire policy

| Mode | VALUE | Output |
| --- | --- | --- |
| `encode-u64` | ASCII decimal u64 | 1..10 raw unsigned varint bytes |
| `encode-i64` | ASCII decimal i64 | 1..10 raw ZigZag varint bytes |
| `decode-u64` | 2..20 ASCII hex digits, in pairs | Canonical unsigned decimal plus LF |
| `decode-i64` | 2..20 ASCII hex digits, in pairs | Canonical signed decimal plus LF |

Decimal input is 1..20 bytes, including any sign. Unsigned input admits digits
only; signed input admits one optional leading `+` or `-` followed by at least
one digit. Leading zeros are allowed. The existing
`core::decimal::parse_u64_range` and `parse_i64_range` enforce the complete native
ranges. Empty values, whitespace, prefixes, separators, non-ASCII digits and
overflow are errors.

Hex accepts uppercase and lowercase ASCII digits only. Odd lengths, a `0x`
prefix, signs, whitespace and separators are errors. Existing `core::u8`
hex-digit helpers convert pairs into caller-backed byte scratch. The program
then calls `core::varint::read_u64` or `read_i64`; it contains no private varint
implementation.

Unsigned wire values use seven payload bits per byte, with least-significant
groups first and a high continuation bit. Signed values use ZigZag; they are
not signed LEB128 or Protobuf `int64` negative encodings. Decoding requires the
shortest encoding. Truncation, overflow and noncanonical overlong values are
errors. The returned next position must equal the complete supplied byte count:
even a valid first value followed by another byte is rejected.

Encoding delegates to public `core::varint::write_u64` or `write_i64`. Decimal
decode output delegates to the existing formatter, so `+0` / `-0` input encoding
and leading zeros decode back to canonical decimal without a leading plus or
unnecessary zeros.

## Storage, bounds and cleanup

Capture admits two arguments and at most 64 argument bytes, excluding trailing
NULs. Sole help uses the same capture path. After successful capture, every
argument check, hex conversion, varint operation and decimal formatting operation
finishes before the snapshot owner is explicitly destroyed. Preparation returns
only plain help and length metadata; no argument View survives that cleanup.

Main retains a 32-logical-byte output array and a separate 10-logical-byte hex
decode array throughout preparation and publication. Raw wire output needs at
most ten bytes; decimal plus LF needs at most twenty-one. All byte access uses
ordinary slices and counted Views, retaining their native stride. No pointer
cast assumes these native arrays have packed byte storage. There is no payload
allocation or output buffer owner; only argument capture owns allocations.

| Resource | Bound |
| --- | ---: |
| Captured arguments / total bytes | 2 / 64 |
| Decimal token bytes | 1..20 |
| Hex token bytes / decoded wire bytes | 2..20 / 1..10 |
| Caller output / wire scratch | 32 / 10 logical bytes |
| Data output bytes | At most 21 |
| Data or help stdout attempts, including Interrupted | 64 total |
| Diagnostic stderr attempts | At most 8 |

The one stdout counter spans the complete chosen data or help result.
Interrupted retries consume attempts. The output cursor advances only by a
confirmed positive count; zero, invalid counts, other errors or exhaustion stop
publication. Output failure may leave a confirmed prefix; there is no rollback
or replay. The attempt limit does not impose a wall-clock timeout on a host
write. Standard descriptors are borrowed and never closed.

## Exit statuses

| Exit | Meaning |
| ---: | --- |
| 0 | Complete conversion output, or help written |
| 2 | Invalid CLI, decimal range, hex or canonical single-value wire input |
| 3 | Argument-capture host failure |
| 4 | Argument allocation failure |
| 5 | Data/help stdout or SIGPIPE-policy failure |
| 6 | Unexpected encoder, formatter or internal contract failure |

SIGPIPE is ignored before argument capture. Setup failure returns 5 without a
diagnostic. Other errors attempt the exact 32-byte line
`varint_number: operation failed\n` with at most eight stderr attempts after
argument cleanup. Diagnostic failure preserves the primary status. Successful
runs have no stderr output. Help is exactly 536 bytes.

## Target and acceptance

All four registered groups passed on the first runtime attempt, totaling 150
distinct native cases. The receipt is
`target/stdlib-work/native-varint-number-first.log`: four tests passed, none
filtered, in 6.62s after a 1.67s driver build.

| Accepted group | Cases | Evidence directory |
| --- | ---: | --- |
| Model | 76 | `/tmp/varint-number-model-p_ioatgr` |
| Wire rejection | 30 | `/tmp/varint-number-wire-xpzx6cfj` |
| CLI | 34 | `/tmp/varint-number-cli-oqwvx0qs` |
| I/O | 10 | `/tmp/varint-number-io-8oxxnny8` |

The driver compiled through the GPU compiler, required an actual little-endian
ELF64 x86-64 executable and applied the shared strict jump gate before native
Linux x86_64 CPU execution. Existing argument, allocator, signal and stream
services supplied the host operations. GPU-device execution and other backends
remain unverified.

Executed application source SHA-256:
`6dea3d57ce10a7e8cacae21494177c05c7fb6807c0854f99a8ad0e81dde02609`.
Oracle SHA-256:
`459aa33f6e27ffd17bab535894ee9758fb1d0cee40028d0bda5fbb00f1c4d834`.
Native varint module SHA-256:
`a0ef8c9ff2c5fc83fb8449c6baeaff4f24d9c3a0f32b962b68dfc11efbcc147b`.

The independent test-only oracle constructs wire bytes with arbitrary-precision
integer division and decodes using a weighted digit sum plus minimal-encoding
admission. Signed expectations use mathematical ZigZag, including i64::MIN.
Literal vectors anchor the generated expectations; this is not roundtrip-only
coverage. Models exercise all four modes, every unsigned encoded-length
transition, signed boundaries, extrema, case-insensitive hex and seeded values.
Wire cases reject malformed hex, truncation, nonminimal values, tenth-byte
payload/continuation overflow and trailing bytes. CLI cases cover arity, mode,
help, decimal grammar/range/length, leading zeros, explicit plus and negative
zero.

The full-width unsigned baseline trace observes exactly two argument mappings
(80 and 30 requested bytes), both explicitly released before the ten-byte raw
stdout write. Full selected traces reject stdin reads, borrowed descriptor
closes or additional allocation services and match successful mapping releases
by address and requested length. Both selected argv ENOMEM sites are reached,
return 4 with empty stdout and release every successfully acquired mapping
before the diagnostic. A noncanonical-wire failure likewise releases both
owners before returning 2 and reporting.

Actual closed data/help stdout produces EPIPE and status 5. Injected output EIO
returns 5; one injected EINTR retries to the exact expected raw wire. Injected
signal setup failure returns 5 silently. The compact attempt-budget trace
observes 64 write errors followed by one successful diagnostic, preserving
status 5. That summary establishes the attempt bound; it does not provide a
full mapping-release trace. No successful transfer count is fabricated.

Argument-host status 3 and internal status 6 were not fault-reached. Positive
short writes and partial-output behavior were not tested. These finite selected
observations do not establish exhaustive failure safety, automatic lifetime
enforcement, general alias safety, leak freedom or formal correctness.

The standalone compiler command and four usage examples above also passed.
Those examples overlap the 150-case corpus and do not increase its case count.

The fixture guide is `tests/fixtures/stdlib_execution/varint_number/README.md`;
the registered driver is `tests/stdlib_varint_number_execution.rs`. With a warm
build and configured GPU, reproduce using:

```sh
timeout --kill-after=2s 100s flock -w 95 target/stdlib-work/library-gpu.lock \
  env CARGO_TARGET_DIR=target/stdlib-build LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=70000 \
  cargo test --test stdlib_varint_number_execution -- --nocapture --test-threads=1
```

Production is entirely Lanius. It adds no compiler, ABI, host service, Rust or
Python library implementation, JSON transport or Wasm dependency. Caller backing
and lifetime obligations remain explicit; this program does not introduce
automatic lifetime enforcement or a proof of general alias safety. See the
[native varint plan](library-native-varint-plan.md) and
[varint guide](stdlib-varint.md) for the separate codec contract.
