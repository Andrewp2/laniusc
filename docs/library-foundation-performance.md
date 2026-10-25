# Library foundation compilation measurements

Tables below are chronological source snapshots. Current selective source
bundling is documented in [distribution](library-distribution.md); it does not
change the compiler's emitted-code granularity or make earlier timings current.

For the measurements below, the harness validated the final emitted ELF in
each process, after all warmups and measured compilations. Earlier wording
incorrectly described validation of every iteration. The timings are unchanged.
The subsequent harness correction validates each emitted program outside the
measured compiler span; new measurements must identify that stronger check.

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

The final emitted native executable for each row exited 0 with the expected empty stdout/stderr.
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
with imported files unchanged and `LANIUS_PERF_REBUILD_ENTRY=1`. The final emitted
ELF for each row executed with exit 0 and empty stdout/stderr. Source closure counts include
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
run. The final emitted ELF for each row executed with exit 0 and empty stdout/stderr. These are
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
sources remained unchanged within each process. The final emitted executable for each row exited
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
unchanged imports remain warm. The final emitted ELF for each row exited 0 with empty expected
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

## Native integers, portable media, geometry, HTTP and tables

On 2026-10-23 the existing `stdlib_gpu_perf` harness measured the final library
sources with one warmup and three measured private entry rebuilds per row.
`LANIUS_PERF_REBUILD_ENTRY=1` invalidates the entry cache. The process/device and
unchanged imports remain warm. Counts include the entry and recursive imports.
The final emitted x86_64 Linux ELF for each row exited 0 with empty stdout/stderr for these six
contract entries.

| Entry | Import closure | Emitted ELF | Median | Range |
| --- | --- | --- | --- | --- |
| `tests/fixtures/stdlib_foundation/native_integer_contracts.lani` | 9 files, 102,765 bytes | 90,132 bytes | 157.176 ms | 151.403–165.226 ms |
| `tests/fixtures/extended/png_contracts.lani` | 17 files, 153,183 bytes | 260,831 bytes | 167.066 ms | 146.123–199.805 ms |
| `tests/fixtures/extended/audio_contracts.lani` | 14 files, 137,834 bytes | 191,020 bytes | 177.002 ms | 164.167–182.290 ms |
| `tests/fixtures/extended/geometry_contracts.lani` | 12 files, 119,723 bytes | 128,895 bytes | 259.977 ms | 255.024–332.641 ms |
| `tests/fixtures/extended/http_contracts.lani` | 21 files, 288,608 bytes | 766,828 bytes | 404.922 ms | 381.100–426.568 ms |
| `tests/fixtures/extended/table_contracts.lani` | 23 files, 226,817 bytes | 268,740 bytes | 311.078 ms | 292.928–326.660 ms |

For example, each command is bounded separately:

```sh
timeout --kill-after=2s 100s env LANIUS_PERF_REBUILD_ENTRY=1 \
  target/stdlib-build/debug/examples/stdlib_gpu_perf \
  tests/fixtures/stdlib_foundation/native_integer_contracts.lani stdlib - 1 3
timeout --kill-after=2s 100s env LANIUS_PERF_REBUILD_ENTRY=1 \
  target/stdlib-build/debug/examples/stdlib_gpu_perf \
  tests/fixtures/extended/png_contracts.lani stdlib - 1 3 extended
```

### Generated 1 MB imported-library workload

`tools/generate_stdlib_workload.py` now calls the current borrowed inline
Vec/Set APIs, checks explicit mutation failures and uses complete record
equality. Its independent model and generated native checks cover all 23
operation kinds, including out-of-range operations and records sharing a key
but differing in another field. `--record-generics` selects the record-focused
operation set; it replaces the obsolete internal `--backlog` option.

The measured default workload has an exact 1,000,000-byte entry, 631 leaves,
56 record declarations, a four-record type pool and 12,274 qualified stdlib
calls. Its import closure is 10 files and 1,073,989 bytes. The generator's
106 generic-body statistic estimates its own helper shapes; it does not count
all transitive compiler instantiations.

With one warmup and three private entry rebuilds, compilation took 999.836,
1,147.183 and 1,084.105 ms: median **1,084.105 ms**. The final emitted 2,171,687-byte
ELF exited 0 and matched the model's 15 output lines with empty stderr.

```sh
timeout --kill-after=2s 100s env PYTHONPATH=tools \
  python3 tools/generate_stdlib_workload.py \
  --out target/stdlib-work/workload-current --target-bytes 1000000 \
  --seed 20 --type-pool 4
timeout --kill-after=2s 10s python3 - <<'PY'
import json
from pathlib import Path
root = Path('target/stdlib-work/workload-current')
manifest = json.loads((root / 'manifest.json').read_text())
(root / 'expected.stdout').write_text(manifest['expected_stdout'])
PY
timeout --kill-after=2s 100s env LANIUS_PERF_REBUILD_ENTRY=1 \
  target/stdlib-build/debug/examples/stdlib_gpu_perf \
  target/stdlib-work/workload-current/stdlib_generic.lani stdlib \
  target/stdlib-work/workload-current/expected.stdout 1 3
```

This is the imported-library workload measured through the repository's
existing harness. The current `lanius_perf.py` generic presets use
`generate_generic_workload.py` and locally defined types; this change does not
switch those workload identities or establish the canonical synthetic speed
ratio. These sequential observations under uncontrolled desktop activity are
neither cold-compilation measurements nor a cross-compiler comparison.

The module/application guides separately record native scale checks for
[786,687-pixel image transforms](extended-image-tool.md),
[400,000-frame WAVE data](extended-wave.md),
[12,004-point convex hull input](extended-shape-hull.md) and
[65,536-cell CSV tables](extended-csv-table.md), alongside model and failure
coverage. No compiler, runtime, shader, IR, ABI, extractor or proof implementation
changed. User GPU execution, selective distribution and the full library
completion audit remain unverified or unfinished.


## Primitive integers, sets, math and portable protocol/storage/signal libraries

On 2026-10-23, the existing `stdlib_gpu_perf` harness measured the sources in
this checkpoint with one warmup and three private entry rebuilds per row.
`LANIUS_PERF_REBUILD_ENTRY=1` invalidates the entry cache; the process/device and
unchanged imports remain warm. The final emitted ELF for each row executed with exit 0 and the
expected empty stdout/stderr. Counts include the entry and recursive imports.

| Entry | Import closure | Emitted ELF | Median | Range |
| --- | --- | --- | --- | --- |
| `tests/fixtures/stdlib_foundation/narrow_integer_contracts.lani` | 12 files, 170,534 bytes | 157,877 bytes | 188.054 ms | 183.863–208.211 ms |
| `tests/fixtures/stdlib_foundation/math_import_contracts.lani` | 7 files, 71,884 bytes | 82,326 bytes | 118.094 ms | 109.180–123.200 ms |
| `tests/fixtures/stdlib_foundation/owned_sets_contracts.lani` | 17 files, 174,974 bytes | 214,354 bytes | 412.363 ms | 388.260–412.426 ms |
| `tests/fixtures/extended/timezone_contracts.lani` | 17 files, 195,737 bytes | 406,006 bytes | 360.171 ms | 347.807–365.507 ms |
| `tests/fixtures/extended/dns_contracts.lani` | 11 files, 119,211 bytes | 265,359 bytes | 405.439 ms | 373.726–411.460 ms |
| `tests/fixtures/extended/websocket_contracts.lani` | 24 files, 327,842 bytes | 954,973 bytes | 473.069 ms | 433.127–540.914 ms |
| `tests/fixtures/extended/kv_contracts.lani` | 12 files, 103,990 bytes | 118,797 bytes | 322.137 ms | 298.165–338.995 ms |
| `tests/fixtures/extended/signal_contracts.lani` | 14 files, 171,350 bytes | 265,328 bytes | 374.257 ms | 334.815–378.207 ms |

The first three entries need only `stdlib`; the rest also need `extended`.
The math entry is a quiet executable import contract; independent accuracy and
special-value gates use the separate model driver. Measurements ran
sequentially under uncontrolled desktop activity. They establish neither a
compiler speedup/regression nor a cold-build or cross-compiler speed ratio.
The generated 1 MB imported-library workload above remains the larger-workload
evidence; these smaller entries answer the added module-import question.

For example, each compile batch is bounded and uses the shared GPU lock:

```sh
timeout --kill-after=2s 100s flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s env LANIUS_PERF_REBUILD_ENTRY=1 \
  target/stdlib-build/debug/examples/stdlib_gpu_perf \
  tests/fixtures/stdlib_foundation/owned_sets_contracts.lani stdlib - 1 3
timeout --kill-after=2s 100s flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s env LANIUS_PERF_REBUILD_ENTRY=1 \
  target/stdlib-build/debug/examples/stdlib_gpu_perf \
  tests/fixtures/extended/timezone_contracts.lani stdlib - 1 3 extended
```

Lock exit 75 means no measurement was taken. Correctness, malformed inputs,
numerical profiles, modeled operation sequences and native allocation/I/O
fault evidence are recorded in the corresponding module guides. In particular,
DNS inspects a 1,600-record, 25,631-byte message in an observed 40 ms native
process run. The time-zone model includes a 30,000-transition file, and the
key/value model exercises 2,048-entry snapshots. These are native execution
observations, distinct from compilation timings.

No compiler, runtime, shader, IR, ABI, extractor or proof implementation changed.
Verified execution remains x86_64 Linux output from GPU compilation; user GPU
execution and other targets remain unverified. Source bundling is executable,
while binary SDK installation, complete API reference and final completion
audit remain open.

## Type/value namespace guard and per-iteration output verification

The unit-variant consumer now checks that a row is a value expression before
writing its checked reference. The retained [collision cases and paired
measurement](../tests/fixtures/stdlib_compiler_state/variant_type_collision/README.md)
record the exact baseline (`3fa72ac2`), reconstruction flags, frozen stdlib and
workload hashes, pinned shader manifests and functional rejection controls.
The existing harness now executes **every emitted ELF**, including warmups,
after stopping that iteration's compiler timer. Earlier rows on this page
verified only the final ELF of each process; their original timings remain valid
observations, with that narrower correctness check.

The unchanged 1,000,000-byte imported-library workload has 12,274 stdlib call
sites and emits 2,171,815 ELF bytes. An initial chronological before/after run
showed +24.18%, but did not preserve separate shader directories and is not a
reproducible regression conclusion. The corrected comparison pins complete
shader sets with `LANIUS_SHADER_ARTIFACT_ROOT` and runs before/after/after/before,
each with one warmup and three private entry rebuilds. All sixteen executables
exit 0 and match the expected output.

| Shader set | Six measured samples, median | Observed range |
| --- | --- | --- |
| Before | 1323.2275 ms | 1212.939–1334.753 ms |
| After | 1243.462 ms | 1130.256–1307.283 ms |

The observed median difference is -6.03%; the initial slowdown did not repeat.
Desktop load, clocks and temperature were uncontrolled, so this does not
establish a causal speedup or fixed performance bound. The changed consumer
adds eight fully inlined instructions (37,187 to 37,195) and 188 SPIR-V bytes
(193,168 to 193,356), measured with the existing size analyzer. This is a
focused compiler correction with functional and scale evidence, not a new
cross-compiler comparison or a claim about user GPU execution.

## Native host, Unicode, settings and distribution checkpoint

The corrected existing harness measured the current source closures on
2026-10-23 with one warmup and three private entry rebuilds per row. Every one
of the twenty emitted executables passed exact stdout, empty stderr and exit-0
checks outside its compilation timer. Processes/devices/imports were warm;
entry timestamps changed to force private entry compilation. These sequential
unpaired desktop observations are not cold-library rebuilds or baseline
speedup/regression measurements.

| Entry | Closure including entry | ELF bytes | Three compiler samples (ms) | Median (ms) |
| --- | --- | ---: | --- | ---: |
| `unicode_sentences_contracts.lani` | 22 files / 289,365 bytes | 324,957 | 277.694, 254.226, 275.408 | 275.408 |
| `unicode_lines_contracts.lani` | 18 files / 210,127 bytes | 250,849 | 199.916, 198.918, 207.182 | 199.916 |
| `settings_contracts.lani` | 41 files / 625,683 bytes | 1,424,655 | 674.392, 672.047, 660.225 | 672.047 |
| `distributions_contracts.lani` | 13 files / 146,695 bytes | 198,080 | 434.011, 430.024, 416.958 | 430.024 |
| Existing 1,000,000-byte imported-library workload | 10 files / 1,073,989 bytes | 2,171,815 | 1368.346, 1365.326, 1334.167 | 1365.326 |

The four contract entries are under `tests/fixtures/extended/` and use the
additional `extended` source root. Settings writes the exact two bytes `QQ`;
the other three write nothing. The unchanged large workload uses its existing
71-byte expected output. No fixture was rewritten to make a quiet measurement.
The larger workload supplies scale evidence alongside the family import rows;
neither establishes a tenfold cross-compiler ratio.

Source closures were checked before and after measurement. Closure digests hash
sorted lines `SHA256  BYTE_COUNT  REPOSITORY_RELATIVE_PATH` including the entry.
All four emitted ELFs per row have identical contents:

| Entry | Closure SHA-256 | ELF SHA-256 |
| --- | --- | --- |
| Sentences | `b98a83f4d23e58a58e2a5445003cc84975403bffb551b11507c41bdf08f79a52` | `8e0bdcfdf71589193323340b41da84e0d1a8fc67a75a83665515584468e8feac` |
| Lines | `da1e6bd61ff46aaaa04f25a72c8e0e199844d0a25bafbea11c83af6c563f6fe2` | `ce111bcf18db3e3e5c2b93f625b8f199981248bdb96e49d186157a8c3f2498fb` |
| Settings | `ec847881a534c2fbfeca89fbf5ade1a483642b6f5c0c0e3f4a7308a1e76a5e80` | `f3e3e3f47fa4934fbd158fda1933244134ccb2def82a4777fa2e1215329a88d9` |
| Distributions | `09f6640e76c3a32f120bc5618c94737f62988e1220cd391dc4b0bc9bcc58e028` | `0709f47db9f36b3ce235af05fe92b18084d74613c86abbf58bb90ffc8aead043` |
| 1 MB workload | `a6cac880e4b0580ff19346ccdaad389036861e6733b8eccbb588ff2546b9c46b` | `367c90a713e010df9a1dc8b456f7af67becb5f8ebea17f8493b344ed1613b3c3` |

The harness source hash is
`d8070c0c10fb5ff7eb7ce861256264de417558ae26c477814f2577a0ce5adbbf`;
its driver hash is
`eaf53a5a1a56e83742e87955f786011cd8b92178bb0849a991ba56d6f82e66e0`.
Exact commands, per-source hashes and retained executable hashes are recorded
under `target/stdlib-work/new-module-perf-20261023/`. The family guides record
native behavior/scale separately: complete official sentence/line corpora,
settings reports through 2,000 entries, distribution references and sampled
values, loopback sockets, filesystem traversal and child-process lifecycle.
Supported execution remains x86_64 Linux output from GPU compilation.

## Streaming runtime formatting

On 2026-10-24 the existing `stdlib_gpu_perf` harness compiled the unchanged
`tests/fixtures/stdlib_foundation/format_strings_contracts.lani` entry against
the stdlib at `0b03990bfd7b658f0c419cf4ec2c32477ccb186e` and the streaming
formatter source. The baseline stdlib was extracted with git archive. Both
used the same compiler, shader set and harness binary; no compiler source
changed. Each variant used one warmup and three private entry rebuilds with
`LANIUS_PERF_REBUILD_ENTRY=1`. Every emitted ELF executed successfully outside
the compilation timer with exact empty stdout/stderr and exit zero.

| Stdlib | Three compiler samples (ms) | Median (ms) | ELF bytes |
| --- | --- | ---: | ---: |
| Baseline | 360.199, 340.444, 309.490 | 340.444 | 480,323 |
| Streaming formatter | 350.073, 351.335, 344.633 | 350.073 | 493,167 |

The observed median increased 2.83%, and executable size increased 12,844
bytes (2.67%). Sample ranges overlap. These chronological baseline/current
runs used warm imports and an uncontrolled desktop; they do not establish a
causal regression, a cold build bound or a cross-compiler speed ratio.

The serialized command for each stdlib root was:

```sh
RUST_MIN_STACK=16777216 LANIUS_PERF_REBUILD_ENTRY=1 \
  timeout --kill-after=2s 100s \
  flock -E75 -w35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s \
  target/stdlib-build/debug/examples/stdlib_gpu_perf \
  tests/fixtures/stdlib_foundation/format_strings_contracts.lani STDLIB_ROOT - 1 3
```

The baseline root was
`target/stdlib-work/format-write-admission/baseline/stdlib`; the current root
was `stdlib`. Local logs are `perf-baseline-1.log` and `perf-current-1.log`
under that admission directory. A separate [native scale gate](stdlib-format-write.md#verification)
renders one MiB with 256-byte scratch and checks every output byte through an
independent hash. Its timings include startup and hashing and measure a
different workload from these compilation samples.

## SHA-2, HMAC and HKDF

On 2026-10-24 the unchanged `stdlib_gpu_perf` harness compiled the
[combined consumer](../tests/fixtures/extended/sha2_crypto_perf.lani) with
the new SHA-2, HMAC-SHA-256 and HKDF-SHA-256 modules. It checks complete
expected digests for all six hash variants and the RFC 5869 case-1 PRK/output.
The harness executed every emitted ELF outside the compiler timer, requiring
exact empty stdout/stderr and exit zero.

| Workload | Compiler samples (ms) | Median (ms) | ELF bytes |
| --- | --- | ---: | ---: |
| Six SHA-2 variants, HMAC and HKDF | 229.515, 211.419, 211.746 | 211.746 | 377,636 |

There was one warmup and three measured private entry rebuilds, with warm
imports and an uncontrolled desktop. This is a current library workload;
there is no baseline implementation or cross-compiler comparison. The exact
serialized command, after a fresh build of the example, was:

```sh
RUST_MIN_STACK=16777216 LANIUS_PERF_REBUILD_ENTRY=1 \
  timeout --kill-after=2s 100s \
  flock -E75 -w35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s \
  target/stdlib-build/debug/examples/stdlib_gpu_perf \
  tests/fixtures/extended/sha2_crypto_perf.lani stdlib - 1 3 extended
```

The independent [stdin hashing application](stdlib-hash-bytes.md) also
processed exactly one MiB for each algorithm and compared full output with
Python hashlib. Observed case wall times were:

| Algorithm | Case wall (ms) |
| --- | ---: |
| SHA-224 | 201.502 |
| SHA-256 | 189.622 |
| SHA-384 | 89.378 |
| SHA-512 | 98.241 |
| SHA-512/224 | 121.628 |
| SHA-512/256 | 104.298 |

Each value includes input-file setup, strace, native process startup and trace
parsing. Compilation and the independent oracle run are outside that interval.
These single-case observations do not isolate hash throughput or establish a
stable performance ratio. The same application passed its separate exact
16-MiB input cap, one-byte excess probe and persistent-interruption call budget.

Ignored local evidence is under `target/stdlib-work/sha2-admission/`:
`build-perf.log`, `perf-current.log` and `hash-bytes-scale.log`. An earlier
performance-fixture attempt omitted its required module declaration and
failed before execution; `perf-fixture-syntax.log` preserves it. The successful
workload adds that declaration without changing any algorithm or expected byte.
No compiler, runtime, shader, IR, ABI or proof source changed. Supported
execution remains x86_64 Linux output from GPU compilation.
