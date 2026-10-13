# Result-only constant inference checkpoint

Measured on 2026-10-03 in the stdlib worktree. Shader digest is
`49ceefb7cccfcae5`: 741 artifacts, maximum 522,460 bytes, unchanged enforced
524,288-byte guard. No source, shader, or test edits occurred during builds or
measurements. Runtime checks execute GPU-compiler-emitted x86_64 Linux ELFs on
the host; they do not establish user-program GPU execution.

Builds use `CARGO_INCREMENTAL=0`, `CARGO_PROFILE_RELEASE_DEBUG=0`,
`CARGO_TARGET_DIR=target/stdlib-perf/build`, Slang 2026.2, and
`LANIUS_SHADER_MAX_SPV_BYTES=524288`. Each command has a timeout below two minutes.

## Canonical existing 1 MB runner

```bash
timeout -k 2s 115s python3 tools/lanius_perf.py run-lanius --preset single-file-1mb --target x86_64 --modes daemon_warm_workspace --skip-profile --startup-timeout 45 --job-timeout 30 --output benchmark_artifacts/performance/stdlib-gpu-20261003-result-constants/canonical-1mb.json
```

Compiler median is **56.074 ms**; wall median is **59.229 ms**. All 20 distinct
million-byte inputs, seeds 20–39, match their frozen workload hashes. Every timed
sample has zero compiled-unit cache hits and zero new buffers, bind groups, or
compute pipelines. `canonical-invariants.txt` records these checks.

The runner saves its report before the existing catalogue `list.get` exception
in `canonical-run.log`. Independent checks of the saved report and every ELF pass:

```bash
timeout -k 2s 115s python3 tools/lanius_perf.py validate benchmark_artifacts/performance/stdlib-gpu-20261003-result-constants/canonical-1mb.json
timeout -k 2s 115s python3 benchmark_artifacts/performance/stdlib-gpu-20260929/canonical-1mb/validate_run.py benchmark_artifacts/performance/stdlib-gpu-20261003-result-constants/canonical-1mb.json
```

Evidence is in `canonical-schema-validation.log`,
`canonical-runtime-validation.log`, and `canonical-1mb.validation.json`.
All 20 artifacts pass exact stdout, empty stderr, and exit-zero validation.
The runner rebuilds the CLI: `identities.sha256` records the measured binary;
`identities-before-runner-build.sha256` preserves the preceding combined-build
identity. `compiler-version.txt` and `artifacts.env` record the shader metadata.

## Existing generic entry driver

```bash
LANIUS_PERF_REBUILD_ENTRY=1 timeout -k 2s 115s target/stdlib-perf/build/release/examples/stdlib_gpu_perf tests/fixtures/stdlib_foundation/generic_many_parameter_composition_32.lani stdlib benchmark_artifacts/performance/stdlib-gpu-20261001-nominal/generic-32.expected.txt 3 10
```

`generic-32.log` records ten entry recompiles after three warmups. Entry
invalidation is outside the timed interval; imports may remain cached. Median is
**293.330 ms**, minimum 288.373 ms, mean 293.625 ms, maximum 298.787 ms. The final
78,746-byte ELF passes exact stdout, empty stderr, and exit-zero validation.
The driver, source, expected output, and CLI hashes in `identities.sha256` verify.

The preceding unpaired compiler/generic medians are 41.726/285.815 ms: current
values are 34.4%/2.6% higher. Tracked live compiler GPU bytes increase from
1,544,163,247 to 1,573,654,315, about 1.9%. This excludes raw user-owned wgpu
buffers with unknown byte sizes. The timings do not isolate the cause of the
increase. Warm runs also do not characterize cold pipeline initialization.

## Paired existing mixed-source controls

The preserved baseline binary uses matching `baseline-shaders`, digest
`5aa50faa5dc57d25`: 713 artifacts, maximum 522,600 bytes, guard 524,288 bytes.
It predates the immediately preceding constant-value checkpoint. Each run uses:

```bash
timeout -k 2s 115s BINARY --emit x86_64-elf --source mixed --target-bytes 1000000 --seed 20 --warmups 3 --iters 10 --run-x86-output --allow-large
```

This source is 1,000,134 bytes and 34,167 lines. Both binary-generated sources
have SHA-256 `09b3794912fc81fccf5b0c73c48d176b65d336c7dfbc6e804372b5191259c7f3`,
verified by their existing `--dump-source` mode and recorded in
`baseline-control-source.sha256` and `current-control-source.sha256`.
Every measured compile executes and validates its output; timing includes that
validation. This nongeneric source differs from the canonical corpus.

| Log, in run order | Average | Minimum |
| --- | ---: | ---: |
| `baseline-1mb.log` | 64.241 ms | 62.358 ms |
| `current-1mb.log` | 64.749 ms | 62.937 ms |
| `current-1mb-reverse.log` | 63.974 ms | 62.059 ms |
| `baseline-1mb-reverse.log` | 64.182 ms | 63.561 ms |

Current averages differ by +0.79% and -0.32% in the two orders. These controls
support the specific nongeneric comparison; they do not resolve the canonical
increase or establish generic workload scaling or a cross-compiler 10x ratio.

Baseline runs temporarily switch
`target/stdlib-perf/build/laniusc-shader-artifacts/release/shaders` to the matched
baseline set. An EXIT trap restores its exact current target after each process.
No build or other compiler process overlaps these switches. The current link
was restored and both binary identities were verified after the runs.

| Binary | SHA-256 |
| --- | --- |
| Preserved `baseline-gpu-compile-bench` | `854868fff988a62b2874b1bf296641b10473cee7c5f296acdfb4f3f8a737c189` |
| Current `gpu_compile_bench` | `668cfffe96b53cd541785c9f7582e784cc57a7b5f2d888aa59d2b31e16af67ad` |

`comparison-identities.sha256` retains those hashes. GPU snapshots before and
after controls report 40%/39% utilization, 1,950/1,530 MHz SM clocks,
75/61 degrees Celsius, and 240.33/118.82 watts. Concurrent GPU use was observed.
These snapshots do not quantify contention within individual samples or prove
the cause of a timing difference.
