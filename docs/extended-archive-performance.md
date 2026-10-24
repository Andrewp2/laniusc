# Archive compilation measurements

On 2026-10-23, the existing `examples/stdlib_gpu_perf.rs` harness compiled and
executed the TAR and ZIP contract programs. Each run used `extended` as its
additional source root, one warmup and three measured entry rebuilds. The
compiler process/device stayed warm; imported files remained unchanged.
Other desktop work was not controlled.

| Entry | Source closure | Emitted ELF | Median | Range |
| --- | --- | --- | --- | --- |
| `tests/fixtures/extended/tar_contracts.lani` | 9 files, approximately 77 KB | 201,342 bytes | 156.211 ms | 128.925–167.702 ms |
| `tests/fixtures/extended/zip_contracts.lani` | 22 files, approximately 214 KB | 403,933 bytes | 284.848 ms | 242.101–318.113 ms |

The final emitted executable for each row exited 0 with the expected empty stdout/stderr.
The fixtures exercise real imported library behavior, including buffer edits
and archive ownership. These figures measure GPU compilation to native x86_64
Linux executables, not user-program execution on a GPU. They do not establish
a fully cold library rebuild, a canonical 1 MB synthetic workload or a
cross-compiler speed ratio. No compiler implementation changed for this work.

```sh
timeout --kill-after=2s 100s env LANIUS_PERF_REBUILD_ENTRY=1 \
  target/stdlib-build/debug/examples/stdlib_gpu_perf \
  tests/fixtures/extended/tar_contracts.lani stdlib - 1 3 extended
timeout --kill-after=2s 100s env LANIUS_PERF_REBUILD_ENTRY=1 \
  target/stdlib-build/debug/examples/stdlib_gpu_perf \
  tests/fixtures/extended/zip_contracts.lani stdlib - 1 3 extended
```

The [TAR application measurements](extended-tar-bytes.md#native-scale-measurements)
separately cover 1 MiB payloads, with and without gzip, including input pipes,
argument capture, archive validation, allocations and native output. The
[ZIP application](extended-zip-bytes.md) records its own native measurements.
