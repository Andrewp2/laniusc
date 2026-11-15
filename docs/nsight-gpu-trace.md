# Complete compiler captures with Nsight Graphics

`tools/run_nsight_gpu_trace.sh` accepts a capture only when it covers an entire
application-bounded workload. It uses `--start-with-ngfx-sdk` and
`--stop-with-ngfx-sdk`. The duration setting is a safety ceiling, not the end of
the workload. Submit-count and elapsed-time windows cannot establish full
coverage and are not supported by this wrapper.

## Capture one warm full native compile

Build the driver without running GPU work:

```sh
cargo build --release -p laniusc-compiler --bin nsight_compile -j8
```

Prepare a JSON request with paths relative to the selected working directory
(absolute paths are preferable):

```json
{
  "input": "/path/to/main.lani",
  "stdlib_root": "/path/to/stdlib",
  "source_roots": ["/path/to/libraries"],
  "native_objects": [],
  "native_libraries": []
}
```

Then run under the GPU guard and the compiler validation lock:

```sh
flock /tmp/lanius-full-recompile-gpu-validation.lock \
  tools/nvidia_gpu_guard.sh -- \
  tools/run_nsight_gpu_trace.sh \
    --output-dir /tmp/settings-nsight-complete \
    --working-dir "$PWD" -- \
    "$PWD/target/release/nsight_compile" /path/to/request.json /tmp/settings 2
```

The last argument is the number of complete warmup builds (default 2, minimum
1). Initialization, shader compilation and warmups precede capture. The measured
workload is exactly one call to `compile_path_manifest_with_native_link`, covering
all original units, retention, catalog, discovery, substitution, projection,
lowering, symbol finalization and link. Writing the executable also finishes
before capture stops. Source manifest loading is setup, outside this warm
compile measurement.

The driver drains all GPU work before starting. It submits a unique begin
marker, compiles, writes the executable, submits the matching end marker, and
waits for GPU completion. Only then does it stop the SDK trace. It keeps the
device alive while Nsight exports; Nsight terminates the target afterwards.
The two boundary-marker dispatches are profiling overhead, not compiler work.

Use binaries with their matching shader artifacts. If using a pinned shader
directory, set `LANIUS_SHADER_ARTIFACT_ROOT` explicitly. The wrapper needs a C
compiler and the installed Nsight Graphics SDK headers; it builds a small bridge
in the capture directory. `LANIUS_NGFX_SDK_INCLUDE` can override header discovery.
No NVIDIA SDK dependency is added to the compiler library or its normal builds.

## What makes a capture complete

The output directory must be empty. The wrapper generates a new capture token
and validates all of these conditions after Nsight exits:

- The application wrote `workload-complete.json` for this token, after successful
  SDK start and stop calls. The SDK was still tracing when the workload finished.
- The workload completed below the duration ceiling (default 9999 ms).
- Nsight finished exporting and reported no timestamp/event overflow, dropped
  data or truncation. A zero Nsight exit status alone is insufficient.
- Nsight's own export metadata confirms SDK-controlled start and stop.
- The exported GPU labels begin and end with the unique workload markers, in
  order, exactly once, with workload events between them. No labeled warmup or
  subsequent build may be present outside the boundaries.

Only then is `coverage.json` written and the wrapper exits successfully. Partial
artifacts remain available for debugging, but have no completion certificate.
Increase `LANIUS_NGFX_TIMESTAMPS` or `LANIUS_NGFX_EVENT_BUFFER_KB` and recapture
when Nsight reports buffer exhaustion. Never treat a partial export as a full
compile profile. Multi-pass collection is rejected until the driver has a
repeatable workload protocol for it.

The raw capture and exported tables retain CPU submission gaps and the capture
interval. Summed shader durations are not elapsed compilation time. Hardware
frame metrics can include other GPU processes; per-pass attribution and an
unprofiled baseline are needed for compiler performance conclusions.

## Other workloads

An executable used with this wrapper must implement the same contract. The
wrapper supplies `LANIUS_NGFX_CONTROL_LIBRARY`, `LANIUS_NGFX_CAPTURE_TOKEN`, and
`LANIUS_NGFX_COMPLETION_FILE`. The SDK bridge exposes `lanius_ngfx_begin()` and
`lanius_ngfx_end()` (zero on success). All workload queues must be drained before
each call. The driver in `crates/laniusc-compiler/src/bin/nsight_compile.rs` is
the reference for markers and the receipt format. Do not wrap arbitrary programs
and assume process exit proves GPU coverage.

Focused checks:

```sh
python3 -m unittest tools.test_nsight_capture tools.test_summarize_nsight_gpu_trace
bash -n tools/run_nsight_gpu_trace.sh
```

Hardware validation on 2026-11-15 captured the settings snapshot `212c54dce`
after two warmups: two original frontend recordings, 1,338 instances and the
final native link, with 7,395 labeled workload events between the markers.
Both SDK calls succeeded; no trace-data warnings occurred. The resulting ELF
matched the unprofiled output byte-for-byte (SHA-256
`93d566611dd8ede39229ea3a440f9a4df67acd5917300d101bad52510eec0c31`).
The local receipt is
`target/compile-cost-evidence/nsight/sdk-capture-2/coverage.json`.
