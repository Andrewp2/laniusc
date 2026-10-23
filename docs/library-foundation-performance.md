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

## Arbitrary precision integers and Unicode 17

The same existing harness measured the following entries on 2026-10-23, using
one warmup and three measured private entry rebuilds with
`LANIUS_PERF_REBUILD_ENTRY=1`. Imported files remained unchanged during each
run. Each emitted ELF executed with exit 0 and empty stdout/stderr. These are
warm imported-library observations; other desktop processes were uncontrolled.
They establish neither cold compilation nor a cross-compiler speed ratio.

| Entry | Import closure | Emitted ELF | Median | Range |
| --- | --- | --- | --- | --- |
| `tests/fixtures/extended_library/big_uint_contracts.lani` | 15 files, 146,762 bytes | 176,435 bytes | 326.882 ms | 266.474–382.767 ms |
| `tests/fixtures/extended_library/big_int_contracts.lani` | 16 files, 165,610 bytes | 229,597 bytes | 223.419 ms | 215.799–256.737 ms |
| `tests/fixtures/stdlib_foundation/unicode_contracts.lani` | 14 files, 294,487 bytes | 263,058 bytes | 164.888 ms | 151.872–169.778 ms |
| `tests/fixtures/extended_library/unicode_normalize_contracts.lani` | 24 files, 609,420 bytes | 638,066 bytes | 190.090 ms | 185.852–191.902 ms |
| `tests/fixtures/extended_library/unicode_graphemes_contracts.lani` | 21 files, 226,741 bytes | 257,153 bytes | 216.319 ms | 194.275–232.467 ms |
| `sample_programs/library/text_normalize.lani` | 39 files, approximately 761 KB | 926,938 bytes | 327.759 ms | 311.604–376.309 ms |

Counts describe the measured source snapshot; later copyright comments add a
few hundred bytes to two generated tables without changing generated data or
behavior. Results are sequential observations, not a paired comparison between
entries with different import/cache histories. The normalizer entry executes
with empty stdin and no options, verifying its empty-text stdout/stderr/exit
contract; large-input native runtime is measured separately. In particular, a lower observed
BigInt median does not establish that importing more code makes compilation
faster. All entries except `unicode_contracts` require the `extended` source root.
For example:

```sh
timeout --kill-after=2s 100s env LANIUS_PERF_REBUILD_ENTRY=1 \
  target/stdlib-build/debug/examples/stdlib_gpu_perf \
  tests/fixtures/extended_library/unicode_normalize_contracts.lani stdlib - 1 3 extended
```

Unicode tables use printable static hexadecimal data without startup allocation
or local giant arrays. Normalization's complete import closure still includes
all scalar casing/property tables because it imports `core::unicode` for CCC;
this increases emitted code/data even when an application only needs combining
classes. Import granularity and selective distribution remain open completion
work. No compiler, shader, runtime or ABI implementation changed.

Separate native process measurements cover the
[4,000-digit calculator](extended-bigcalc.md) and
[293,745-byte normalization workload](extended-text-normalize.md). Their timing
includes native process I/O and excludes compilation. All target claims here
concern x86_64 Linux output from GPU compilation, with no user-kernel execution
claim.

## TOML, regular expressions, calendars and full casing

At source snapshot `8568e938` on 2026-10-23, the same repository harness measured one warmup and three private
entry rebuilds for each entry below, with `LANIUS_PERF_REBUILD_ENTRY=1`. Imported
sources remained unchanged within each process. All emitted executables exited
0 with expected empty stdout/stderr. Counts include the entry and its recursive
imports. Desktop activity was uncontrolled; results are observations across
different workloads/cache histories, not a paired compiler regression test.

| Entry | Import closure | Emitted ELF | Median | Range |
| --- | --- | --- | --- | --- |
| `tests/fixtures/stdlib_foundation/calendar_contracts.lani` | 13 files, 136,173 bytes | 204,239 bytes | 197.722 ms | 176.457–204.930 ms |
| `tests/fixtures/extended_library/toml_smoke.lani` | 25 files, 340,113 bytes | 635,112 bytes | 389.009 ms | 384.094–433.276 ms |
| `tests/fixtures/extended_library/regex_contracts.lani` | 26 files, 467,082 bytes | 608,041 bytes | 317.291 ms | 309.521–342.764 ms |
| `tests/fixtures/extended_library/unicode_case_contracts.lani` | 26 files, 435,094 bytes | 463,549 bytes | 160.525 ms | 159.712–167.898 ms |
| `sample_programs/library/toml_normalize.lani` | 33 files, 410,033 bytes | 791,769 bytes | 328.063 ms | 323.420–359.827 ms |

The application row executes with empty stdin and no options, exercising its
empty-document path. Large nonempty workloads are measured in the application
execution tests. Every row except calendar needs the additional `extended`
source root. For example:

```sh
timeout --kill-after=2s 100s env LANIUS_PERF_REBUILD_ENTRY=1 \
  target/stdlib-build/debug/examples/stdlib_gpu_perf \
  tests/fixtures/extended_library/regex_contracts.lani stdlib - 1 3 extended
timeout --kill-after=2s 100s env LANIUS_PERF_REBUILD_ENTRY=1 \
  target/stdlib-build/debug/examples/stdlib_gpu_perf \
  sample_programs/library/toml_normalize.lani stdlib - 1 3 extended
```

Native, compile-excluded observations cover
[100,299 bytes of nested TOML configuration](extended-toml-normalize.md),
[12,000 streamed regex-search records](extended-text-grep.md), and
[198,450 bytes of full casing](extended-text-case.md). These exercise the real
Lanius libraries and process I/O. The calendar guide separately records full
native-year-range differential/algebra checks; Unicode case/word guides record
full scalar and official boundary conformance.

No compiler, shader, runtime, IR, ABI, extractor or proof implementation changed.
These measurements concern native x86_64 Linux output of GPU compilation, not
user-kernel execution, cold compilation or the canonical synthetic speed ratio.

## Collections, finite decimals and numerical algorithms

On 2026-10-23 the existing harness measured the final collections/mathematics
sources with one warmup and three measured private entry rebuilds per row.
`LANIUS_PERF_REBUILD_ENTRY=1` invalidates the entry cache; the process/device and
unchanged imports remain warm. Every emitted ELF exited 0 with empty expected
stdout/stderr. Counts include the entry and its recursive imports.

| Entry | Import closure | Emitted ELF | Median | Range |
| --- | --- | --- | --- | --- |
| `tests/fixtures/stdlib_foundation/bitset_owned_smoke.lani` | 17 files, 155,215 bytes | 124,138 bytes | 191.782 ms | 186.497–217.774 ms |
| `tests/fixtures/stdlib_foundation/calendar_keys_collections.lani` | 19 files, 205,445 bytes | 560,766 bytes | 633.514 ms | 607.629–646.398 ms |
| `tests/fixtures/extended_library/decimal_arithmetic_contracts.lani` | 21 files, 281,465 bytes | 527,438 bytes | 234.573 ms | 224.446–368.130 ms |
| `tests/fixtures/extended_library/statistics_contracts.lani` | 10 files, 110,423 bytes | 149,092 bytes | 173.401 ms | 168.499–177.914 ms |
| `tests/fixtures/extended_library/linalg_contracts.lani` | 12 files, 139,005 bytes | 252,988 bytes | 194.198 ms | 193.625–278.643 ms |

The calendar entry executes generic ranges, vector sorting and hash/tree maps;
its workload differs from the preceding calendar table. These sequential
observations under uncontrolled desktop activity do not isolate a compiler
regression or compare module compilation speeds. The library import closure
and emitted code size remain material costs; selective imports/distribution
still need completion work. No compiler or shader implementation changed.

```sh
timeout --kill-after=2s 100s env LANIUS_PERF_REBUILD_ENTRY=1 \
  target/stdlib-build/debug/examples/stdlib_gpu_perf \
  tests/fixtures/stdlib_foundation/bitset_owned_smoke.lani stdlib - 1 3
timeout --kill-after=2s 100s env LANIUS_PERF_REBUILD_ENTRY=1 \
  target/stdlib-build/debug/examples/stdlib_gpu_perf \
  tests/fixtures/extended_library/decimal_arithmetic_contracts.lani stdlib - 1 3 extended
```

Calendar uses only `stdlib`; decimal, statistics and linear algebra also use
the `extended` source root. The [bitset guide](stdlib-bitset-owned.md) records
the million-bit stateful workload. Separate compile-excluded native process
observations cover the [twenty-million-candidate prime sieve](stdlib-primes.md),
[512-row exact ledger](extended-decimal-ledger.md) and
[4,096-row multiple regression](extended-data-analyze.md). Their timing includes
process setup and I/O. Numerical conformance, failure and ownership checks are
recorded per module. All target claims remain native x86_64 Linux output from
GPU compilation, without user GPU execution evidence.
Selective imports, distribution and the broader library completion audit remain.

## Inline collections, precision formatting, parsers and patches

On 2026-10-23 the same existing harness measured one warmup and three private
entry rebuilds for each final entry below. `LANIUS_PERF_REBUILD_ENTRY=1` forces
entry cache misses; unchanged imports and the process/device stay warm. Every
emitted ELF executed with exit 0 and the expected empty stdout/stderr. Counts
include the entry and recursive imported sources.

| Entry | Import closure | Emitted ELF | Median | Range |
| --- | --- | --- | --- | --- |
| `tests/fixtures/stdlib_foundation/fixed_capacity_vec.lani` | 9 files, 81,256 bytes | 51,165 bytes | 164.778 ms | 162.882–194.986 ms |
| `tests/fixtures/stdlib_foundation/float_precision_contracts.lani` | 11 files, 131,016 bytes | 212,855 bytes | 187.002 ms | 170.530–214.904 ms |
| `tests/fixtures/stdlib_foundation/format_strings_contracts.lani` | 20 files, 259,248 bytes | 440,745 bytes | 226.385 ms | 204.295–256.585 ms |
| `tests/fixtures/extended/parse_contracts.lani` | 17 files, 183,333 bytes | 241,325 bytes | 222.081 ms | 220.576–300.681 ms |
| `tests/fixtures/extended/diff_contracts.lani` | 12 files, 123,272 bytes | 223,411 bytes | 301.131 ms | 292.451–323.794 ms |
| `sample_programs/library/expr_calc.lani` | 32 files, 364,230 bytes | 665,485 bytes | 349.964 ms | 340.921–382.544 ms |

The first three entries use only `stdlib`; the rest also use `extended`.
The calculator entry's output check covers empty stdin. Its nonempty workload
is measured separately by the execution tests. Measurements ran sequentially;
other desktop activity was uncontrolled. Workload and import-cache differences
prevent attributing relative row timings to individual library algorithms.
No compiler, shader, runtime, IR, ABI, extractor or proof implementation changed.

```sh
timeout --kill-after=2s 100s env LANIUS_PERF_REBUILD_ENTRY=1 \
  target/stdlib-build/debug/examples/stdlib_gpu_perf \
  tests/fixtures/stdlib_foundation/format_strings_contracts.lani stdlib - 1 3
timeout --kill-after=2s 100s env LANIUS_PERF_REBUILD_ENTRY=1 \
  target/stdlib-build/debug/examples/stdlib_gpu_perf \
  tests/fixtures/extended/diff_contracts.lani stdlib - 1 3 extended
```

### Existing formatter import cost

The identical `format_import_contracts.lani` entry was compiled against the
`8cb1af7b` stdlib and the new precision-enabled stdlib using the same compiler
and harness binary. Each source tree used one warmup and five measured private
entry rebuilds. Both emitted programs passed their exact output/exit contract.

| Library source | Import closure | Emitted ELF | Median | Range |
| --- | --- | --- | --- | --- |
| `8cb1af7b` | 20 files, 220,103 bytes | 277,544 bytes | 221.701 ms | 207.800–275.060 ms |
| Precision-enabled | 20 files, 230,577 bytes | 310,473 bytes | 178.348 ms | 165.429–229.232 ms |

The emitted program grows by 32,929 bytes (11.9%) even though this entry formats
only an integer and a boolean. Additional imported precision functions have an
observable code-size cost. Selective imports and distribution remain completion
work. Timing ranges overlap; process/import-cache histories and desktop activity
were uncontrolled, so this comparison establishes no compiler speedup or
repeatable latency regression.

The earlier source tree was extracted with `git archive 8cb1af7b stdlib` into
`target/stdlib-work/precision-baseline`. Reproduction:

```sh
timeout --kill-after=2s 100s env LANIUS_PERF_REBUILD_ENTRY=1 \
  target/stdlib-build/debug/examples/stdlib_gpu_perf \
  tests/fixtures/stdlib_foundation/format_import_contracts.lani \
  target/stdlib-work/precision-baseline/stdlib - 1 5
timeout --kill-after=2s 100s env LANIUS_PERF_REBUILD_ENTRY=1 \
  target/stdlib-build/debug/examples/stdlib_gpu_perf \
  tests/fixtures/stdlib_foundation/format_import_contracts.lani stdlib - 1 5
```

Separate native observations cover [5,000 integer expressions](extended-expr-calc.md)
and [20,000-line sparse diff/application](extended-text-patch.md), including
process setup and I/O while excluding compilation. Float precision conformance
covers roughly 112,000 independent reference comparisons; parser and collection
tests cover modeled operations, errors, copies and ownership. These are native
x86_64 Linux observations, without a user GPU kernel or cross-compiler speed
ratio claim.
