# Inferred-call closure checkpoint

Measured on 2026-10-01 in the stdlib worktree. Current shader digest is
`5b0b8f17178ea693`: 732 artifacts, maximum 523,396 bytes, enforced guard
524,288 bytes. Baseline shader digest is `5aa50faa5dc57d25`.

The fresh current drivers use the current host code and shader set. Builds use
`CARGO_INCREMENTAL=0`, `CARGO_PROFILE_RELEASE_DEBUG=0`,
`CARGO_TARGET_DIR=target/stdlib-perf/build`, and Slang 2026.2.

| Binary | SHA-256 |
| --- | --- |
| Matched baseline `baseline-gpu-compile-bench` | `854868fff988a62b2874b1bf296641b10473cee7c5f296acdfb4f3f8a737c189` |
| Current `gpu_compile_bench` | `fea2cb8c5831b29d0dc3110227be9b54ec7a7b5c54b7eecd78650194b852e1da` |
| Current `examples/stdlib_gpu_perf` | `4f14d33f9e197cada374d4f91d97221ca7e791466dde97fdd5ef88ec5b02f69f` |

## Matched 1 MB controls

Each run uses the existing benchmark:

```bash
timeout -k 5s 105s BINARY --emit x86_64-elf --source mixed --target-bytes 1000000 --seed 20 --warmups 3 --iters 10 --run-x86-output --allow-large
```

The source is 1,000,134 bytes, 34,167 lines, SHA-256
`09b3794912fc81fccf5b0c73c48d176b65d336c7dfbc6e804372b5191259c7f3`.
Every measured compile executes and validates its output. Thus timing includes
validation. This nongeneric source does not exercise the inference closure.

Run order is baseline, current, generic program, current reverse, baseline
reverse. The baseline binary uses its matched `baseline-shaders`; an EXIT
trap restores the shared shader link to `current-shaders`. Never change that
link while a build or compiler run is active. All commands run sequentially
and have a timeout below two minutes.

| Log | Average | Minimum |
| --- | ---: | ---: |
| `baseline-1mb.log` | 64.119 ms | 57.376 ms |
| `current-1mb.log` | 69.620 ms | 64.710 ms |
| `current-1mb-reverse.log` | 68.257 ms | 61.932 ms |
| `baseline-1mb-reverse.log` | 66.413 ms | 63.773 ms |

Average increases are 8.6% and 2.8%. The difference above 5% did not repeat;
these results do not establish unchanged performance or identify a cause.

## Real generic program

```bash
timeout -k 5s 105s env LANIUS_PERF_REBUILD_ENTRY=1 target/stdlib-perf/build/release/examples/stdlib_gpu_perf tests/fixtures/stdlib_foundation/generic_many_parameter_composition_32.lani stdlib benchmark_artifacts/performance/stdlib-gpu-20261001-nominal/generic-32.expected.txt 3 10
```

`generic-32.log` contains ten entry recompiles after three warmups. Entry
invalidation occurs outside the timed interval; imports may remain cached.
Median is 265.165 ms, minimum 252.001 ms, average 264.256 ms, maximum
273.262 ms. The final 66,433-byte ELF passes exact expected stdout, empty
stderr, and zero exit status. The older 246.051 ms median is unpaired.

These measurements do not establish large generic-source throughput or a
current general 10x comparison against other compilers. The preceding frozen
canonical corpus measurements remain in `../stdlib-gpu-20261001-nominal/`.
