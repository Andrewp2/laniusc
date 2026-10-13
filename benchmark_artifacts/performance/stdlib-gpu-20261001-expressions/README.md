# Complete expression-inference checkpoint

Measured on 2026-10-01 in the stdlib worktree. Shader digest is
`96ddfc90abad06ef`: 733 artifacts, maximum 523,396 bytes, enforced guard
524,288 bytes. The correctness gate passes 115 focused checks.

The freshly built existing `stdlib_gpu_perf` example uses current host code
and shaders. Build environment: `CARGO_INCREMENTAL=0`,
`CARGO_PROFILE_RELEASE_DEBUG=0`, `CARGO_TARGET_DIR=target/stdlib-perf/build`,
and Slang 2026.2.

| Input | SHA-256 |
| --- | --- |
| Current `examples/stdlib_gpu_perf` binary | `4edf69191147ad0a6846cade8af120805ea722e4234de44bf6ed0549b5080e92` |
| `generic_many_parameter_composition_32.lani` | `078460041864ae1f4457bff13dcabc41d61e9d96a966dee76147b0c2330a6e5d` |
| Expected stdout | `8c310f2ef145f0339cff8fcadb4c8291ba04cd6161401d7c06cfcf4dcdfcd47b` |

```bash
timeout -k 5s 105s env LANIUS_PERF_REBUILD_ENTRY=1 target/stdlib-perf/build/release/examples/stdlib_gpu_perf tests/fixtures/stdlib_foundation/generic_many_parameter_composition_32.lani stdlib benchmark_artifacts/performance/stdlib-gpu-20261001-nominal/generic-32.expected.txt 3 10
```

`generic-32.log` records ten entry recompiles after three warmups. Entry
invalidation occurs outside the timed interval; imported-unit caches remain
warm. Median is 248.106 ms, minimum 233.660 ms, average 248.737 ms, maximum
269.007 ms. The final 66,433-byte ELF passed exact stdout, empty stderr, and
zero exit checks.

This is an unpaired measurement. It does not establish an improvement over
the preceding 265.165 ms median, large generic-source throughput, or a current
10x comparison. The large canonical corpus and matched controls were not
rerun for this checkpoint.
