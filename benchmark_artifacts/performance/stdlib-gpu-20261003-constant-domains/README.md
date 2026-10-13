# Constant domain performance checkpoint

Measured on 2026-10-03. Shader digest `1e60d9e7da516426`: 741 artifacts,
maximum 522,460 bytes, unchanged enforced limit 524,288 bytes. `artifacts.env`
and `compiler-version.txt` identify this snapshot. `identities.sha256` records
both compiler drivers, the 32-parameter source, and its expected stdout.

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
  --output benchmark_artifacts/performance/stdlib-gpu-20261003-constant-domains/canonical-1mb.json
```

The release compiler is exposed through the existing `target/release` symlink
to `target/stdlib-perf/build/release`. Twenty distinct million-byte programs,
seeds 20–39, measure **41.711 ms compiler / 44.831 ms wall median**. All source
hashes match their frozen manifests. Timed samples have zero compiled-unit cache
hits and zero newly created buffers, bind groups, and compute pipelines.

The runner saves the report before an existing catalogue `list.get` exception.
Independent verification completed afterward:

```bash
timeout -k 2s 115s python3 tools/lanius_perf.py validate \
  benchmark_artifacts/performance/stdlib-gpu-20261003-constant-domains/canonical-1mb.json
timeout -k 2s 115s python3 \
  benchmark_artifacts/performance/stdlib-gpu-20260929/canonical-1mb/validate_run.py \
  benchmark_artifacts/performance/stdlib-gpu-20261003-constant-domains/canonical-1mb.json
```

Schema validation passes. All 20 emitted ELFs pass exact stdout, empty stderr,
and exit-zero validation. `canonical-1mb.validation.json`,
`canonical-runtime-validation.log`, `canonical-schema-validation.log`, and
`canonical-invariants.txt` retain the evidence.

## Generic entry

The existing driver was rebuilt with the current source and shaders. Its build
log is `tests/fixtures/stdlib_compiler_state/constant-domain-perf-build.log`.

```bash
LANIUS_PERF_REBUILD_ENTRY=1 timeout -k 2s 115s \
  target/stdlib-perf/build/release/examples/stdlib_gpu_perf \
  tests/fixtures/stdlib_foundation/generic_many_parameter_composition_32.lani \
  stdlib benchmark_artifacts/performance/stdlib-gpu-20261001-nominal/generic-32.expected.txt \
  3 10
```

Ten entry recompiles after three warmups measure **284.328 ms median**,
275.093 ms minimum, 284.466 ms mean, and 292.381 ms maximum. Entry invalidation
is outside the timed interval; imports may stay cached. The final 78,746-byte
ELF passes exact stdout, empty stderr, and exit-zero checks. `generic-32.log`
retains samples and the validation result.

The preceding unpaired medians are 40.162 ms compiler and 268.152 ms generic
entry. Present medians are higher by 3.9% and 6.0%. These observations do not
isolate a cause or establish unchanged performance. They also do not establish
general generic-source scaling or a current cross-compiler 10x ratio.
