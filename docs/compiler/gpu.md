# GPU Infrastructure

The compiler's GPU layer is the shared runtime used by the lexer, parser,
resident type checker, source-pack metadata users, and backends. It owns device
creation, typed buffer allocation, shader pipeline construction,
reflection-driven bind groups, dispatch planning, submission/readback helpers,
timing, trace output, and low-level environment parsing.

Use this chapter when changing reusable GPU helpers. Use
[GPU passes and shader artifacts](gpu-passes.md) when changing shader artifact
production, shader ownership, pass loading, or Rust-to-Slang resource maps. Use
[Shader artifact and reflection ABI](shader-abi.md) when changing artifact keys,
runtime artifact lookup, Slang reflection conversion, dynamic offsets, or
reflected bind-group contracts. Use
[Compiler debugging and observability](debugging.md) when choosing between
progress logs, validation scopes, timers, trace files, and readback while
investigating a failure.

## Ownership Boundary

The `gpu` module owns mechanics, not compiler semantics.

| Module | Responsibility |
| --- | --- |
| `device` | Global `wgpu::Device`/`Queue`, adapter selection, feature/limit requests, pipeline-cache loading/persistence/pruning. |
| `buffers` | `LaniusBuffer<T>` and allocation helpers for uniform, storage, scratch, and readback buffers. |
| `passes_core` | Compute pipeline construction, reflected bind-group layouts, bind-group creation, dispatch planning, pass recording, batching, submission, validation scopes, readback polling. |
| `scan` | Reusable ping/pong prefix-scan step planning. |
| `readback` | Fixed-width readback decoders for `u32` and `i32` words. |
| `timer` | Timestamp-query allocation, stamping, resolving, and timestamp readback. |
| `trace` | Chrome/Perfetto trace event collection and flushing. |
| `debug` | Optional staged debug-copy buffers. |
| `env` | Environment variable parsing for GPU infrastructure. |

Compiler phases still own resident buffer families, pass order, diagnostics,
and semantic meaning. A GPU helper should make phase ownership easier to
express; it should not learn about lexer tokens, parser HIR, type-check
relations, module paths, or backend lowering policy.

## Device Lifecycle

`GpuDevice::new` creates the native GPU context. `gpu::device::global` lazily
creates one process-global context, and CLI compile paths call
`gpu::device::persist_pipeline_cache` after compile/check work.

Device creation does the following:

1. Reads `LANIUS_BACKEND` and selects a wgpu backend set.
2. Requests a high-performance adapter without a compatible surface.
3. Starts from default limits, then raises storage-buffer limits to the selected
   adapter's native capacity where the compiler needs wide record tables.
4. Always requests `PASSTHROUGH_SHADERS` because the compiler consumes
   Slang-produced SPIR-V directly.
5. Requests timestamp-query features when the adapter supports them.
6. Requests pipeline-cache support when the adapter supports it.
7. Creates the `wgpu::Device` and `wgpu::Queue`.
8. Registers an uncaptured-error callback that prints wgpu errors.
9. Creates and registers a wgpu pipeline cache if supported.

The context is intentionally process-global for the normal compiler path.
Subsystems that accept an explicit device do so for tests, alternate entry
points, or lower-level reuse, not because phases should each create their own
GPU device.

## Backend Selection And Limits

`LANIUS_BACKEND` accepts:

| Value | wgpu backend |
| --- | --- |
| `vulkan` or `vk` | Vulkan only |
| `dx12` | DirectX 12 only |
| `metal` or `mtl` | Metal only |
| `gl` | GL only |
| `auto` or unset | all native backends |

Unknown values warn and fall back to all native backends. This is a device
selection fallback, not a compiler semantic fallback.

The compiler requests large storage-buffer binding and buffer sizes because GPU
passes operate over wide resident tables. If a selected adapter cannot support
the requested limits, device creation fails early. Do not hide that failure in
phase code; phase code should only allocate buffers after the selected device
exists.

## Pipeline Cache

Pipeline-cache support is optional and depends on the adapter. When available,
the compiler creates one wgpu `PipelineCache` for the device and registers it
in a weak global registry keyed by device pointer so pass construction can find
the cache.

Cache files live under `LANIUS_PIPELINE_CACHE_DIR`, defaulting to
`target/wgpu-pipeline-cache`. Cache identity includes:

- adapter key from wgpu;
- `laniusc` package version;
- build profile;
- wgpu version;
- Slang version;
- shader artifact digest.

The cache filename includes sanitized identity components and a stable identity
hash. The file payload is wrapped in a Lanius header:

| Header field | Purpose |
| --- | --- |
| magic | Distinguishes Lanius pipeline-cache files from opaque blobs. |
| version | Allows future cache-file format changes. |
| header length | Rejects malformed or unexpected headers. |
| identity hash | Rejects cache files from different adapter/compiler/shader identities. |
| payload length | Rejects partial writes and truncation. |
| payload hash | Rejects corrupted payload bytes. |

Invalid, stale, truncated, mismatched, or corrupt cache files are discarded and
removed when possible. Cache write uses a temporary file and rename. A loaded
cache is persisted only when it was missing/invalid or
`LANIUS_PIPELINE_CACHE_PERSIST_ALWAYS` is truthy.

The `fallback: true` flag passed to wgpu's pipeline cache is only wgpu
cache-data recovery for stale cache blobs. It is not a CPU compiler fallback,
does not bypass GPU execution, and does not change the requirement for a real
adapter.

## Pipeline Cache Pruning

`prune_pipeline_cache_dir` runs before the current cache file is read. It only
considers files whose names start with the current adapter key and never removes
the current path. Controls:

| Environment variable | Default | Meaning |
| --- | --- | --- |
| `LANIUS_PIPELINE_CACHE_PRUNE` | `true` | Strict boolean gate for pruning. |
| `LANIUS_PIPELINE_CACHE_MAX_FILES` | `8` | Maximum retained files for the adapter key. |
| `LANIUS_PIPELINE_CACHE_MAX_BYTES` | `256 MiB` | Maximum retained aggregate bytes. |
| `LANIUS_PIPELINE_CACHE_MAX_AGE_DAYS` | `30` | Maximum retained file age. |
| `LANIUS_PIPELINE_CACHE_PERSIST_ALWAYS` | `false` | Persist even when cache was loaded from disk. |

Pruning sorts by newest modified time, then larger file size, then path. Older
or budget-exceeding files are removed best-effort and warnings do not abort
compilation.

## Buffers

`LaniusBuffer<T>` wraps a `wgpu::Buffer` with:

- allocated byte size;
- logical element count;
- phantom element type;
- `Deref<Target = wgpu::Buffer>` for wgpu call sites.

Use `LaniusBuffer<T>` at ownership boundaries where count or byte size matters.
Use raw `&wgpu::Buffer` when the caller owns the buffer or when a helper is
operating at the wgpu API level.

Allocation helpers:

| Helper | Use |
| --- | --- |
| `uniform_from_val` | Create and initialize a uniform buffer from an `encase::ShaderType` value. |
| `uniform_from_val_with_queue` | Create a uniform buffer and upload through `queue.write_buffer`. |
| `storage_ro_from_bytes` | Create read-only storage from already-packed bytes. |
| `storage_ro_from_u32s` | Pack host `u32` values into read-only storage. |
| `storage_ro_from_u32s_with_queue` | Create read-only `u32` storage and upload through the queue. |
| `storage_rw_for_array` | Allocate read/write storage for an array using `encase` storage layout. |
| `storage_rw_uninit_bytes` | Allocate explicit byte-sized read/write scratch. |
| `readback_bytes` | Allocate a map-readable copy destination. |

`create_buffer_init_checked` pads nonempty initialized buffers to
`COPY_BUFFER_ALIGNMENT`, creates the buffer under validation/internal/OOM error
scopes, copies only the unpadded input bytes, and panics if buffer creation
reports an error. Empty initialized inputs create a zero-sized buffer. Callers
should not depend on hidden padding bytes.

Use `encase` helpers for Rust structs shared with shaders. Use explicit byte
helpers only when the shader-side layout is owned and documented by the phase.

## Pass Construction

`PassData` is the reusable compute-pass descriptor:

| Field | Meaning |
| --- | --- |
| `pipeline` | Reflected compute pipeline. |
| `bind_group_layouts` | Bind group layouts derived from Slang reflection. |
| `shader_id` | Stable pass id used for cache keys, diagnostics, and tracing. |
| `thread_group_size` | Reflected compute workgroup size. |
| `reflection` | Parsed Slang reflection JSON. |

`make_pass_data` parses reflection JSON, creates reflected bind group layouts,
builds a compute pipeline from SPIR-V using passthrough shader modules, uses the
device pipeline cache when available, validates creation under an optional wgpu
validation scope, and extracts the compute thread-group size. If reflection
does not report a thread-group size, the code warns and defaults to `[1, 1, 1]`.

Pass-loading macros such as `make_shader_pass!`, `make_main_pass!`, and
`impl_static_shader_pass!` are thin wrappers around artifact lookup and
`make_pass_data`. They should stay mechanical. Phase-owned pass groups decide
which shaders are loaded and when they run.

In debug builds on native targets, shader artifact files are read from the
artifact root. Release and wasm paths also resolve artifact paths through the
same shader-artifact access layer. See [GPU passes and shader artifacts](gpu-passes.md)
for artifact production, root selection, and freshness rules, and
[Shader artifact and reflection ABI](shader-abi.md) for the debug/native versus
embedded-artifact contract.

## Reflection And Bind Groups

Bind group layouts are built from Slang reflection. Bind groups are populated
by matching reflected parameter names to Rust-provided resources.

There are two public creation paths:

| Helper | Contract |
| --- | --- |
| `create_bind_group_from_reflection` | Takes a `HashMap<String, BindingResource>` and requires every reflected parameter in the set to have a resource. |
| `create_bind_group_from_bindings` | Takes an ordered slice of `(name, resource)` pairs; uses the fast reflected-order path when names match, then falls back to lookup by name. |

Reflection removes hand-written binding indices from most Rust code, but shader
parameter names are still a Rust/Slang contract. Renaming a shader parameter
requires updating the owning phase's resource map or bind-group helper.

If a pass uses program-layout parameter sets, bind-group construction reads the
requested set from the compute entry point. If no program layout is present, it
uses the flat reflection parameter list.

## Bind Group Cache

`BindGroupCache` stores reflected bind groups keyed by `shader_id`, with one
cached vector per pass. It is valid only while every buffer captured by those
bind groups remains live and semantically correct.

Use the cache only when:

- buffer handles are stable for the cached pass;
- buffer capacities are still sufficient for the current dispatch;
- the phase owner clears or removes cache entries after resizing or replacing
  buffers.

The cache does not know phase lifetimes. It cannot tell whether a resident
buffer was replaced, whether parser scratch was repurposed, or whether a
source-pack unit changed. Those invalidation rules belong to the phase owner.

## Dispatch Planning

`plan_workgroups` centralizes WebGPU dispatch sizing. It is the only reusable
place that should know about `MAX_GROUPS_PER_DIM = 65_535`.

| Input | Behavior |
| --- | --- |
| `DispatchDim::D1` with `Elements1D(n)` | Computes `ceil(n / tgsx)`, minimum 1, and tiles across Y if X would exceed `65_535`. |
| `DispatchDim::D2` with `Elements2D(w, h)` | Computes `ceil(w / tgsx)` and `ceil(h / tgsy)`, each minimum 1. |
| `DispatchDim::D2` with `Elements1D(n)` | Uses the same 1D tiling behavior for wrappers that model logical 1D input through a D2-capable pass. |
| mismatched D1/D2 input | Returns an error. |

The planner protects direct dispatches from the per-dimension workgroup limit.
Indirect dispatch buffers are produced by phase-owned shaders; those shaders
must apply equivalent limits or construct valid dispatch arguments.

Do not duplicate the `65_535` rule in phase code. If a phase needs a different
work decomposition, add the reusable planning shape here and document it.

## Pass Recording

Generated/static pass wrappers implement the `Pass<Buffers, DebugOutput>`
trait:

- `NAME` names validation scopes, timers, and traces.
- `DIM` selects dispatch planning shape.
- `data` returns `PassData`.
- `create_resource_map` maps shader parameter names to phase-owned buffers.
- `record_pass` records a direct dispatch.
- `record_pass_indirect` records an indirect dispatch.
- `record_debug` optionally copies debug buffers after the dispatch.

`PassContext` carries the shared recording state: device, command encoder,
phase-owned buffers, optional timer, optional debug output, and optional
bind-group cache. The phase still owns pass order and the command encoder
lifetime.

Direct dispatch recording:

1. Optionally pushes a wgpu validation scope.
2. Builds or reuses bind groups.
3. Plans workgroups from reflected thread-group size and logical input.
4. Opens a compute pass.
5. Sets pipeline and bind groups.
6. Dispatches workgroups.
7. Stamps the optional timer.
8. Pops validation scope and reports any error.
9. Records optional debug readback work.

Indirect dispatch recording follows the same bind/validation/timer/debug shape
but reads workgroup counts from a GPU buffer at offset zero.

## Compute Pass Batching

`ComputePassBatch` records multiple compatible passes into one
`wgpu::ComputePass`. Batching avoids pass-boundary overhead, but it removes
per-pass compute-pass boundaries.

Only batch passes when the caller has confirmed that batching is compatible with
the requested debug mode:

- no per-pass validation scope is needed;
- no timer stamp is needed between those passes;
- no debug readback copy depends on the individual pass boundary;
- the passes can share one command encoder scope without changing ordering
  semantics.

`LANIUS_BATCH_COMPUTE_PASSES` controls whether compatible higher-level paths may
batch. It defaults to enabled; `0` or `false` disables it.

## Submission, Validation, And Readback

Submission helpers:

| Helper | Role |
| --- | --- |
| `submit_with_progress` | Submit one command buffer, record a host trace span, and emit optional progress logs. |
| `submit_with_optional_validation` | Wrap submission in a wgpu validation scope when requested. |
| `map_readback_for_progress` | Queue a map request and record trace/progress events. |
| `wait_for_map_progress` | Poll the device while emitting progress logs for an already-queued map. |
| `map_readback_blocking` | Wait for readback map completion using `LANIUS_READBACK_TIMEOUT_MS`. |
| `wait_for_readback_map` | Explicit-timeout readback wait loop with progress every 500 ms. |

`map_readback_blocking` defaults to a 120 second timeout. The wait loop polls
with `wgpu::PollType::Poll`, checks the map callback through a channel, logs
progress periodically, and sleeps 1 ms between polls. A timeout is an error
from the owning phase's perspective; do not silently treat it as a rejected
program.

`readback::read_u32_words` and `read_i32_words` decode fixed-width little-endian
word arrays and reject truncated buffers with context. Use these helpers for
status buffers and small fixed readbacks instead of ad hoc byte slicing.

## Timers

`GpuTimer` wraps timestamp queries for one command encoder. It owns:

- a timestamp query set;
- a resolve buffer;
- a readback buffer;
- query labels;
- timestamp period from the queue.

Callers stamp labels into the encoder, resolve queries before submission ends,
then map the readback buffer after GPU work completes. Extra stamps beyond
capacity are ignored gracefully by returning the last valid index.

Only create timers when the selected device supports timestamp queries and the
relevant timing flag is enabled. Do not make timer availability part of
correctness.

## Trace Output

`trace` writes Chrome/Perfetto-compatible JSON when either
`LANIUS_PERFETTO_TRACE` or `LANIUS_GPU_TRACE_JSON` names an output path.

Trace events include:

- metadata events naming lanes;
- host duration spans;
- GPU duration spans anchored to a host submit instant;
- instant events;
- counter events.

Trace collection is cheap when disabled: public record functions check the
global trace state before appending events. `flush` sorts metadata events before
ordinary events, creates the parent directory if needed, and writes a JSON
payload with `displayTimeUnit: "ms"`.

## Environment Flags

GPU infrastructure flags:

| Environment variable | Parser | Effect |
| --- | --- | --- |
| `LANIUS_BACKEND` | string | Selects native backend set. |
| `LANIUS_VALIDATION_SCOPES` | truthy bool | Enables selected wgpu validation scopes. |
| `LANIUS_BATCH_COMPUTE_PASSES` | custom bool | Enables compatible compute-pass batching; enabled by default. |
| `LANIUS_READBACK_TIMEOUT_MS` | positive `u64` | Timeout for blocking readback maps. |
| `LANIUS_GPU_PIPELINE_PROGRESS` | strict truthy check in progress helper | Logs pipeline/submit/readback progress. |
| `LANIUS_PIPELINE_TRACE` | strict bool | Logs pipeline construction stages and also enables progress logging. |
| `LANIUS_WASM_TRACE` / `LANIUS_X86_TRACE` | strict progress trigger | Also enable GPU progress logging for backend-specific traces. |
| `LANIUS_GPU_TIMING` | phase-owned | Enables GPU timing in selected paths. |
| `LANIUS_GPU_COMPILE_HOST_TIMING` | truthy bool | Prints host timing spans in compile/pipeline-cache paths. |
| `LANIUS_PERFETTO_TRACE` / `LANIUS_GPU_TRACE_JSON` | path presence | Writes trace JSON. |
| `LANIUS_PIPELINE_CACHE_DIR` | path | Selects pipeline-cache directory. |
| `LANIUS_PIPELINE_CACHE_PRUNE` | strict bool | Enables pipeline-cache pruning. |
| `LANIUS_PIPELINE_CACHE_MAX_FILES` | positive `u64` | Cache pruning file budget. |
| `LANIUS_PIPELINE_CACHE_MAX_BYTES` | positive `u64` | Cache pruning byte budget. |
| `LANIUS_PIPELINE_CACHE_MAX_AGE_DAYS` | positive `u64` | Cache pruning age budget. |
| `LANIUS_PIPELINE_CACHE_PERSIST_ALWAYS` | truthy bool | Persist loaded pipeline caches. |

Use `env_bool_truthy` when any value other than explicit `0`/`false` should
enable behavior. Use `env_bool_strict` when only `1`/`true` should enable
behavior and invalid values should fall back to the default.

`env_string`, `env_path`, and `env_u64` warn when values are missing or invalid.
That is useful for infrastructure debugging, but do not use these helpers for
user-facing CLI validation; CLI flags should produce structured diagnostics.

## Failure Modes

Common infrastructure failures and where they should surface:

| Failure | Expected handling |
| --- | --- |
| No suitable adapter or device creation failure | Fail early while creating `GpuDevice`; do not fabricate CPU compilation. |
| Unsupported requested limits/features | Fail during device creation or pass construction. |
| Missing shader artifact | Pass construction error from artifact loading. |
| Reflection does not match Rust resources | Bind-group creation error naming the missing reflected parameter. |
| Stale/corrupt pipeline cache | Warn, discard/remove cache, create fresh wgpu cache. |
| Readback timeout | Error from readback helper; phase maps or reports the infrastructure failure. |
| Validation-scope error | Error from pass creation/recording/submission with the pass or validation label. |
| Timer unsupported | Phase should skip timing, not fail correctness. |
| Trace write failure | Warn and continue after work has completed. |

Infrastructure errors are not semantic rejections. Do not map them to parser,
type-check, or backend status codes unless the owning phase has actually
produced a semantic status.

## Changing GPU Infrastructure

Checklist:

1. Name the reusable mechanism being changed.
2. Confirm the change belongs in `gpu`, not in a phase owner.
3. Preserve `LaniusBuffer<T>` ownership metadata when count or byte size
   matters.
4. Keep shader parameter names and reflected bind groups as explicit
   Rust/Slang contracts.
5. Clear or invalidate bind-group caches when captured buffer handles change.
6. Keep `plan_workgroups` as the central dispatch-limit policy.
7. Do not add per-phase semantics to pass construction, dispatch, submission,
   readback, timer, or trace helpers.
8. Document any new environment variable in this chapter.
9. Add focused tests for pure helpers or small decoders when behavior changes.
10. Regenerate or check `docs/compiler/generated/reference.md` when public
    items, shader load sites, Rustdoc coverage, or status inventories change.

## Common Mistakes

Avoid these changes:

- Duplicating dispatch-limit math in a phase instead of extending
  `plan_workgroups`.
- Treating pipeline-cache fallback as a non-GPU compiler fallback.
- Adding language-specific branches to `gpu` helpers.
- Caching bind groups across buffer replacement or resize without invalidation.
- Adding a shader parameter rename without updating Rust resource maps.
- Using byte buffer helpers for shared structs when an `encase` helper should
  define layout.
- Enabling timers or debug readback in a path that assumes compute-pass
  batching is transparent.
- Turning readback timeouts into semantic diagnostics.
- Adding an environment flag without documenting its parser semantics.

## Evidence To Update

Choose the narrowest evidence that covers the change:

- Unit tests for pure helpers such as pipeline-cache header decode, scan
  planning, reflected parameter selection, dispatch planning, or readback word
  decoding.
- A focused phase test when a GPU helper change affects phase recording or
  buffer lifetime.
- A shader artifact/reference check when pass loading or artifact lookup
  changes.
- A docs update and environment flag audit when adding observability or cache
  controls.
- `tools/compiler_inventory.py --check docs/compiler/generated/reference.md`
  when generated-reference inputs changed.

Docs-only edits do not require compiler tests, but they should still pass the
generated-reference freshness check and Markdown link validation.
