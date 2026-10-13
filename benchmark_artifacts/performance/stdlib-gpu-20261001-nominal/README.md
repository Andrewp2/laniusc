# Complete nominal graph checkpoint

Measured on 2026-10-01 in the stdlib worktree. See
[the performance report](../../../docs/stdlib-gpu-performance.md) for scope and
interpretation. Every invocation used a timeout under two minutes; run commands
separately and keep GPU measurements sequential.

## Canonical corpus

```bash
timeout 110s python3 tools/lanius_perf.py run-lanius --preset single-file-1mb --target x86_64 --modes daemon_warm_workspace --skip-profile --startup-timeout 60 --job-timeout 30 --output benchmark_artifacts/performance/stdlib-gpu-20261001-nominal/generic-nominal-graph-1mb.json
```

`generic-nominal-graph-1mb.json` contains all 20 measured compiles.
`generic-nominal-graph-1mb.validation.txt` contains the 20 executable validations
with hashes matched to the previous frozen corpus. The runner completed
measurement, then failed during catalogue generation on an auxiliary JSON list.
The log records that failure; measurement was not repeated to bypass it.

Current shader digest: `969718dcfd9ce8a8`, 732 shaders, enforced maximum
524,288 bytes, largest 523,396 bytes.

## Same-session controls

The preserved matched baseline binary and shader set are in
`target/stdlib-perf/results/baseline-gpu-compile-bench` and `baseline-shaders`.
Baseline shader digest: `5aa50faa5dc57d25`.
The freshly built current binary is
`target/stdlib-perf/build/release/gpu_compile_bench`, using `current-shaders`.
Both generators produced source SHA-256
`09b3794912fc81fccf5b0c73c48d176b65d336c7dfbc6e804372b5191259c7f3`.

Each run used:

```bash
timeout -k 5s 105s BINARY --emit x86_64-elf --source mixed --target-bytes 1000000 --seed 20 --warmups 3 --iters 10 --run-x86-output --allow-large
```

Run order: baseline-0, current-0, current-1, baseline-1. The four corresponding
logs retain averages and minimums. Each iteration compiles and executes its
output, including validation in the measured interval. Old runs temporarily
pointed `target/stdlib-perf/build/laniusc-shader-artifacts/release/shaders` to
the matched `baseline-shaders`; an EXIT trap restored `current-shaders`.
Never change that shared link during a build or another compiler run.

Binary SHA-256:

| Binary | SHA-256 |
| --- | --- |
| Matched baseline bench | `854868fff988a62b2874b1bf296641b10473cee7c5f296acdfb4f3f8a737c189` |
| Current bench | `86bde104b0b7644afa994caaadbdae529617ad05c8b3cd13a228c1fcf4a3a8c8` |
| Current stdlib example | `0b0fb79f9b54e2c7ebcb39dccc07dd61e58f2fdb9c2eef0811b98938b4c80490` |

Current binaries were built with `CARGO_INCREMENTAL=0`,
`CARGO_PROFILE_RELEASE_DEBUG=0`, and `CARGO_TARGET_DIR=target/stdlib-perf/build`,
using Slang 2026.2 from `/home/andrew-peterson/tools/slang-2026.2-linux-x86_64/bin`.

## Real generic program

```bash
timeout -k 5s 105s env LANIUS_PERF_REBUILD_ENTRY=1 target/stdlib-perf/build/release/examples/stdlib_gpu_perf tests/fixtures/stdlib_foundation/generic_many_parameter_composition_32.lani stdlib benchmark_artifacts/performance/stdlib-gpu-20261001-nominal/generic-32.expected.txt 3 10
```

`generic-32.log` contains ten entry recompile times and successful validation of
the final ELF against `generic-32.expected.txt`. Entry cache invalidation happens
outside the timed interval; imports may remain cached. No matched historical
timing exists for this program. The measurements do not establish large generic
source throughput or a general 10x comparison against other compilers.
