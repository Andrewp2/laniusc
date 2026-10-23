# Library foundation compilation measurements

On 2026-10-23, the existing `examples/stdlib_gpu_perf.rs` harness compiled and
executed these real imported-library contract programs. Each row used one
warmup and three measured entry rebuilds, with `LANIUS_PERF_REBUILD_ENTRY=1`.
The process/device remained warm; imported files remained unchanged. Other
desktop activity was not controlled.

| Entry | Import closure | Emitted ELF | Median | Range |
| --- | --- | --- | --- | --- |
| `tests/fixtures/stdlib_foundation/net_contracts.lani` | 13 files, approximately 128 KB | 178,899 bytes | 192.247 ms | 184.353–198.963 ms |
| `tests/fixtures/stdlib_foundation/arena_contracts.lani` | 10 files, approximately 72 KB | 47,226 bytes | 133.323 ms | 129.215–148.302 ms |
| `tests/fixtures/extended/cbor_contracts.lani` | 17 files, approximately 167 KB | 229,273 bytes | 281.598 ms | 270.909–301.194 ms |

Every emitted native executable exited 0 with the expected empty stdout/stderr.
The CBOR entry used `extended` as an additional source root; the other entries
used only `stdlib`. These measurements use GPU compilation to x86_64 Linux,
without establishing user-program GPU execution, fully cold library builds,
canonical 1 MB synthetic workloads or a cross-compiler speed ratio. No compiler
implementation changed for these libraries.

```sh
timeout --kill-after=2s 100s env LANIUS_PERF_REBUILD_ENTRY=1 \
  target/stdlib-build/debug/examples/stdlib_gpu_perf \
  tests/fixtures/stdlib_foundation/net_contracts.lani stdlib - 1 3
timeout --kill-after=2s 100s env LANIUS_PERF_REBUILD_ENTRY=1 \
  target/stdlib-build/debug/examples/stdlib_gpu_perf \
  tests/fixtures/stdlib_foundation/arena_contracts.lani stdlib - 1 3
timeout --kill-after=2s 100s env LANIUS_PERF_REBUILD_ENTRY=1 \
  target/stdlib-build/debug/examples/stdlib_gpu_perf \
  tests/fixtures/extended/cbor_contracts.lani stdlib - 1 3 extended
```

Separate native execution measurements cover
[262,144 arena records and reset reuse](stdlib-arena.md#executable-evidence-and-measurements),
[address filtering](stdlib-address-filter.md),
[CBOR item and float-bit batches](extended-cbor.md) and
[1 MiB ZIP payloads split across one or 1,024 members](extended-zip-manifest.md#native-scale-measurements).
Each description records its input, validation, timing scope and observed range.

## Floating conversion, exact numbers and JSON validation

The same harness measured the following additional imported entries on
2026-10-23. Each row used one warmup and three measured private entry rebuilds,
with imported files unchanged and `LANIUS_PERF_REBUILD_ENTRY=1`. Every emitted
ELF executed with exit 0 and empty stdout/stderr. Source closure counts include
the entry and recursively imported source files.

| Entry | Import closure | Emitted ELF | Median | Range |
| --- | --- | --- | --- | --- |
| `tests/fixtures/stdlib_foundation/float_decimal_contracts.lani` | 11 files, approximately 107 KB | 166,931 bytes | 178.622 ms | 164.487–238.368 ms |
| `tests/fixtures/stdlib_foundation/decimal_number_contracts.lani` | 10 files, approximately 93 KB | 121,510 bytes | 186.626 ms | 168.566–219.021 ms |
| `tests/fixtures/extended_library/schema_import_contracts.lani` | 22 files, approximately 288 KB | 523,624 bytes | 348.073 ms | 326.699–367.412 ms |

The schema entry is a quiet, valid integer-schema example; the larger
conformance, fault and scale tests are recorded in [schema validation](extended-schema.md).
It requires the additional `extended` source root. The numeric entries use only
`stdlib`. These are warm imported-library measurements, not cold compilation or
a claim about the compiler's large synthetic workload ratio.

```sh
timeout --kill-after=2s 100s env LANIUS_PERF_REBUILD_ENTRY=1 \
  target/stdlib-build/debug/examples/stdlib_gpu_perf \
  tests/fixtures/stdlib_foundation/float_decimal_contracts.lani stdlib - 1 3
timeout --kill-after=2s 100s env LANIUS_PERF_REBUILD_ENTRY=1 \
  target/stdlib-build/debug/examples/stdlib_gpu_perf \
  tests/fixtures/stdlib_foundation/decimal_number_contracts.lani stdlib - 1 3
timeout --kill-after=2s 100s env LANIUS_PERF_REBUILD_ENTRY=1 \
  target/stdlib-build/debug/examples/stdlib_gpu_perf \
  tests/fixtures/extended_library/schema_import_contracts.lani stdlib - 1 3 extended
```

### Cost of float support in the formatter

`format_import_contracts.lani` uses the same boolean/integer entry with both
the `bface65d` stdlib and the current stdlib. One warmup and five measured entry
rebuilds ran sequentially in separate harness processes; imported libraries
remained unchanged within each process. The compiler binary was identical.

| Library source | Import closure | Emitted ELF | Median | Range |
| --- | --- | --- | --- | --- |
| `bface65d` | 15 files, 121,918 bytes | 151,315 bytes | 179.739 ms | 161.610–194.516 ms |
| Current float-enabled formatter | 20 files, 205,131 bytes | 265,388 bytes | 206.054 ms | 181.319–243.454 ms |

Float conversion adds approximately 114 KB to this emitted executable even
though the entry formats only an integer and boolean. The observed median rose
14.6%; sample ranges overlap and desktop/other-process activity was uncontrolled.
This exposes an import-size cost, not evidence that float formatting is free or
that the compiler implementation regressed. Selective library packaging and
import granularity remain part of the completion audit. No compiler, shader,
runtime or ABI implementation was changed for this milestone.

The baseline library tree can be extracted from commit `bface65d` into
`target/stdlib-work/float-baseline`, retaining its `stdlib/` directory. Commands:

```sh
timeout --kill-after=2s 100s env LANIUS_PERF_REBUILD_ENTRY=1 \
  target/stdlib-build/debug/examples/stdlib_gpu_perf \
  tests/fixtures/stdlib_foundation/format_import_contracts.lani \
  target/stdlib-work/float-baseline/stdlib - 1 5
timeout --kill-after=2s 100s env LANIUS_PERF_REBUILD_ENTRY=1 \
  target/stdlib-build/debug/examples/stdlib_gpu_perf \
  tests/fixtures/stdlib_foundation/format_import_contracts.lani stdlib - 1 5
```

Separate native measurements cover [2,048 exact float conversions](stdlib-float-decimal.md#executable-evidence)
and [1,024 streaming decimal records](stdlib-float-normalize.md#executable-evidence).
They include process I/O and exclude compilation; they do not compare with
optimized Ryu or claim GPU execution of library programs.
