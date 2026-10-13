# Known zero-sized layouts checkpoint

Measured on 2026-10-01 in the stdlib worktree. Shader digest is
`3979aa9b02a9bb6b`: 733 artifacts, maximum 518,612 bytes, enforced guard
524,288 bytes. The correctness gate passes 123 focused compiler/stdlib checks
and three checked body-replay packet unit tests. Logs are
`tests/fixtures/stdlib_compiler_state/generic-zero-runtime-checkpoint.log` and
`generic-zero-retention-checkpoint.log`.

The existing `stdlib_gpu_perf` example was rebuilt against current host code
and shaders. Build environment: `CARGO_INCREMENTAL=0`,
`CARGO_PROFILE_RELEASE_DEBUG=0`, `CARGO_TARGET_DIR=target/stdlib-perf/build`,
and Slang 2026.2. The build log is `generic-zero-perf-build.log` in the same
compiler checkpoint log directory.

| Input | SHA-256 |
| --- | --- |
| Current `examples/stdlib_gpu_perf` binary | `f9355a7cd00a25dea8f39f6834579dd6449926a17102673813b554b52c3d3241` |
| `generic_many_parameter_composition_32.lani` | `078460041864ae1f4457bff13dcabc41d61e9d96a966dee76147b0c2330a6e5d` |
| Expected stdout | `8c310f2ef145f0339cff8fcadb4c8291ba04cd6161401d7c06cfcf4dcdfcd47b` |

```bash
timeout -k 5s 105s env LANIUS_PERF_REBUILD_ENTRY=1 target/stdlib-perf/build/release/examples/stdlib_gpu_perf tests/fixtures/stdlib_foundation/generic_many_parameter_composition_32.lani stdlib benchmark_artifacts/performance/stdlib-gpu-20261001-nominal/generic-32.expected.txt 3 10
```

`generic-32.log` records ten entry recompiles after three warmups. Entry
invalidation occurs outside the timed interval; imported units may remain
cached. Median is 265.524 ms, minimum 242.884 ms, average 263.156 ms, maximum
280.107 ms. The final 66,433-byte ELF passed exact stdout, empty stderr, and
zero-exit checks.

This is an unpaired measurement. It does not isolate the pointer/zero-layout
changes, establish unchanged performance, measure large generic-source
throughput, or establish the current 10x target. Large corpus controls and
external compiler comparisons were not rerun for this checkpoint.
