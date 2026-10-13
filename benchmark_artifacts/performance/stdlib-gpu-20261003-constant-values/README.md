# Constant value performance checkpoint

Measured on 2026-10-03, shader digest `3143f245e4678848`: 741 artifacts,
maximum 522,460 bytes, unchanged enforced limit 524,288 bytes.
`artifacts.env` and `compiler-version.txt` identify the shader snapshot.
`identities.sha256` records the measured compiler drivers and generic fixture;
`identities-before-runner-build.sha256` preserves hashes before the canonical
runner's own CLI build. The runner rebuilt only the CLI binary; its version
still reports the same source-worktree metadata and shader digest.

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
  --output benchmark_artifacts/performance/stdlib-gpu-20261003-constant-values/canonical-1mb.json
```

The existing release compiler symlink points to `target/stdlib-perf/build/release`.
Twenty distinct million-byte programs, seeds 20–39, measure **41.726 ms compiler /
44.879 ms wall median**. Source hashes match frozen manifests. Timed samples
have zero compiled-unit cache hits and zero new buffers, bind groups, or pipelines.
The runner saves its report before an existing catalogue `list.get` exception.

Independent checks afterward:

```bash
timeout -k 2s 115s python3 tools/lanius_perf.py validate \
  benchmark_artifacts/performance/stdlib-gpu-20261003-constant-values/canonical-1mb.json
timeout -k 2s 115s python3 \
  benchmark_artifacts/performance/stdlib-gpu-20260929/canonical-1mb/validate_run.py \
  benchmark_artifacts/performance/stdlib-gpu-20261003-constant-values/canonical-1mb.json
```

Schema validation passes. All 20 emitted ELFs pass exact stdout, empty stderr,
and exit-zero checks. Validation records and logs retain the evidence.
`canonical-invariants.txt` records checked source/cache/resource invariants.

## Generic entry

The existing example was rebuilt before measurement. Its build log is
`tests/fixtures/stdlib_compiler_state/constant-value-perf-build.log`.

```bash
LANIUS_PERF_REBUILD_ENTRY=1 timeout -k 2s 115s \
  target/stdlib-perf/build/release/examples/stdlib_gpu_perf \
  tests/fixtures/stdlib_foundation/generic_many_parameter_composition_32.lani \
  stdlib benchmark_artifacts/performance/stdlib-gpu-20261001-nominal/generic-32.expected.txt \
  3 10
```

Ten entry recompiles after three warmups measure **285.815 ms median**,
274.309 ms minimum, 284.297 ms mean, and 297.206 ms maximum. Entry invalidation
is outside the timed interval; imports may remain cached. The final 78,746-byte
ELF passes exact stdout, empty stderr, and exit-zero checks. Raw samples and
validation are in `generic-32.log`.

The preceding unpaired medians were 41.711 ms compiler and 284.328 ms generic
entry. The present medians are about 0.04% and 0.5% higher. These results do not
isolate a cause, establish unchanged performance, or measure large generic-source
scaling or a cross-compiler 10x ratio. Warm measurements do not establish cold
pipeline initialization performance; the compiler performance document records
separate first-run test observations.
