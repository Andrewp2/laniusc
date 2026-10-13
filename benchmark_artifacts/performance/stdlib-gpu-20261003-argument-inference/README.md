# Argument inference performance checkpoint

Measured on 2026-10-03. Shader digest `60cb26d5a7d42101`: 741 artifacts, maximum
522,460 bytes, unchanged enforced limit 524,288 bytes. `artifacts.env` and
`compiler-version.txt` identify this snapshot. `identities.sha256` records both
compiler drivers, the 32-parameter source, and its expected stdout.

## Canonical 1 MB corpus

```bash
CARGO_INCREMENTAL=0 CARGO_PROFILE_RELEASE_DEBUG=0 \
CARGO_TARGET_DIR="$PWD/target/stdlib-perf/build" \
LANIUS_SHADER_MAX_SPV_BYTES=524288 \
PATH="/home/andrew-peterson/tools/slang-2026.2-linux-x86_64/bin:$PATH" \
timeout -k 2s 115s python3 tools/lanius_perf.py run-lanius \
  --preset single-file-1mb --target x86_64 \
  --modes daemon_warm_workspace --skip-profile \
  --startup-timeout 45 --job-timeout 30 \
  --output benchmark_artifacts/performance/stdlib-gpu-20261003-argument-inference/canonical-1mb.json
```

The current release compiler is exposed through the existing `target/release`
symlink to `target/stdlib-perf/build/release`. Twenty distinct million-byte
programs, seeds 20–39, measure 40.162 ms compiler and 42.941 ms wall median.
Source hashes match the frozen workload manifests. Timed samples have zero
compiled-unit cache hits and zero new buffers, bind groups, or compute pipelines.

The runner saves the report before a pre-existing catalogue `list.get` exception.
Independent `tools/lanius_perf.py validate` passes. The existing
`benchmark_artifacts/performance/stdlib-gpu-20260929/canonical-1mb/validate_run.py`
executes all 20 ELFs and verifies exact stdout, empty stderr, and exit zero.
The report, validator records, and assertions are retained in `canonical-1mb.json`,
`canonical-1mb.validation.json`, `canonical-runtime-validation.log`, and
`canonical-invariants.txt`.

## Generic entry

The existing `stdlib_gpu_perf` example was rebuilt on this snapshot. Its build
log is `tests/fixtures/stdlib_compiler_state/literal-argument-inference-perf-build.log`.

```bash
LANIUS_PERF_REBUILD_ENTRY=1 timeout -k 2s 115s \
  target/stdlib-perf/build/release/examples/stdlib_gpu_perf \
  tests/fixtures/stdlib_foundation/generic_many_parameter_composition_32.lani \
  stdlib benchmark_artifacts/performance/stdlib-gpu-20261001-nominal/generic-32.expected.txt \
  3 10
```

Ten entry recompiles after three warmups measure 268.152 ms median, 260.610 ms
minimum, 269.741 ms mean, and 282.603 ms maximum. Entry invalidation is outside
the clock; imports may remain cached. The final 78,746-byte ELF passes exact
stdout, empty stderr, and exit-zero checks. Samples and validation are in
`generic-32.log`.

These measurements are unpaired. They do not establish a causal speed change,
general generic-source scaling, or a current cross-compiler 10x ratio.
