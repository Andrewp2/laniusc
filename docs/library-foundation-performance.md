# Arena, network-value and CBOR compilation measurements

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
