# Streaming decimal float normalization

[`sample_programs/library/float_normalize.lani`](../sample_programs/library/float_normalize.lani)
reads decimal floats from stdin and writes one normalized value per line. It
combines `core::float_decimal`, `core::f32`/`f64`, generic `core::fmt::Display`,
counted byte views, native argument access and descriptor I/O. All production
behavior is Lanius. The verified target is **x86_64 Linux**; GPU compilation
produces the tested native program and does not establish GPU-kernel execution.

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  --stdlib-root stdlib sample_programs/library/float_normalize.lani \
  -o target/stdlib-work/float-normalize
printf '1.50000\n-0\n1e20\n5e-324\n' | \
  timeout --kill-after=2s 100s target/stdlib-work/float-normalize
```

The output is `1.5`, `-0`, `1e20` and `5e-324`, each followed by LF.

## Options and number rules

```text
float-normalize [--f32] [--sqrt] [--finite-only]
```

Default precision is binary64. `--f32` parses directly to binary32, avoiding an
intermediate binary64 rounding. `--sqrt` applies correctly rounded square root
before formatting. `--finite-only` rejects a nonfinite result after that optional
transformation. Thus a negative square-root input normally emits `NaN`, and
with `--finite-only` it reports an input error. Duplicate flags and operands are
errors. `--help` must be the only argument.

The decimal grammar, signed underflow/overflow, exact rounding and special
tokens are specified in [float conversion](stdlib-float-decimal.md). A leading
plus, leading zeroes, `.5` and `1.` are accepted; whitespace is not. NaN and
infinity tokens are ASCII case-insensitive. Output is shortest round-trip text,
with the shorter of fixed/scientific spelling and fixed spelling winning ties.
It preserves negative zero and uses `NaN`, `inf` and `-inf` for nonfinite values.

LF and CRLF records are supported, including a final record without LF. One
terminal CR is removed from each record. Empty input succeeds; an empty record
is invalid. The line limit is 1,024 bytes after removing CR, with at most 768
mantissa digits. Exponent digits count toward the byte limit. Parsing and
formatting each use the converter's 1,000,000-unit logical work budget per
record. These limits are explicit; excess input is never truncated into a
different number.

## Failures and storage

| Exit | Meaning |
| --- | --- |
| 0 | All records succeeded, or help was written |
| 2 | Invalid argument/number, rejected nonfinite result, line/digit limit or conversion failure |
| 3 | Argument capture or stream I/O failed, including zero-progress output |

Errors have a diagnostic on stderr and never emit the failing record. Earlier
successful records may already be written. Output errors can leave a partial
record, as permitted by `write_all`'s failure contract. Read/write interrupts
are retried. Diagnostics can also fail; the exit status remains 3.

The program allocates no heap storage. Chunk/line buffers and conversion
scratch live on the stack, with packed bytes adapted through `core::mem`.
Formatting stages one complete result before writing it. It does not open files
or use host float conversion or math functions.

## Executable evidence

`tests/stdlib_float_format_execution.rs` runs five native test groups. The
streaming groups compare both precisions, with/without square root, against
Rust primitives for boundary tokens and 256 generated bit patterns. They also
check idempotent normalization, signed zero, subnormals, large exponents,
finite-only errors, malformed input, exact 768/769-digit and 1,024/1,025-byte
boundaries, cross-chunk records, CRLF/final-CR input and prior-record output.
`strace` fault injection checks allocation denial, read/write EINTR and EIO,
zero-progress writes and help-output failure.

All five groups passed in 6.34 seconds on 2026-10-23. A subsequent isolated native
batch of 1,024 records (8,448 input/output bytes) took 288.711 ms, including process
startup and test-driver I/O, with compilation completed before starting the
timer. The output was byte-for-byte correct. This is one observed sample, not a
throughput guarantee or compiler speed ratio.

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test stdlib_float_format_execution -- --nocapture
```
