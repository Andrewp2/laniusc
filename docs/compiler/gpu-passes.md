# GPU Passes And Shader Artifacts

The compiler is built around explicit GPU compute passes. Rust owns artifact
lookup, pass construction, bind-group assembly, dispatch planning, submission,
timing, and readback. Slang shaders own the parallel data transformations.

Use this document when adding a shader, moving shader files, changing reflected
resources, changing pass wrappers, changing bind-group caching, or debugging a
Rust-to-Slang resource mismatch. Use `gpu.md` for reusable device, buffer,
pipeline-cache, timing, and trace infrastructure. Use
[Shader artifact and reflection ABI](shader-abi.md) for the deeper artifact-key,
freshness, runtime lookup, reflection, binding-type, dynamic-offset, and
resource-name contracts.

## Ownership

The shader/pass boundary has three owners:

| Area | Owner |
| --- | --- |
| Shader source | `shaders/` |
| Artifact production | `crates/laniusc-shaders/build.rs` |
| Runtime pass construction | `crates/laniusc-compiler/src/gpu/passes_core.rs` and phase pass wrappers |

Phase modules own the semantics and pass order. The reusable GPU layer owns the
mechanics for turning SPIR-V plus reflection JSON into a `wgpu::ComputePipeline`
and reflected bind groups.

Do not move phase policy into `gpu::passes_core`. A pass wrapper should say
which shader it loads, which resident buffers it binds, and how it dispatches.
The owning phase should still decide when the pass runs and what its outputs
mean.

## Source And Artifact Layout

Shader source files live under `shaders/`. Current phase roots are:

- `shaders/lexer`
- `shaders/parser`
- `shaders/type_checker`
- `shaders/codegen`

Shared helpers live at the shader root or in small helper directories. Common
imports include `prefix_scan`, `radix`, `scatter`, `range_query`, `atomics`,
`byte_packing`, `bit_packing`, `status`, and `gpu_index`.

Artifact keys are shader paths relative to `shaders/` without the `.slang`
extension. For example:

- `shaders/lexer/tokens_build.slang` -> `lexer/tokens_build`
- `shaders/parser/hir/nodes.slang` -> `parser/hir/nodes`
- `shaders/type_checker/modules/05_resolve_imports.slang` ->
  `type_checker/modules/05_resolve_imports`

Runtime pass loaders append `.spv` and `.reflect.json` to the key.

Put a new shader under the phase that owns the data structure it mutates. Do not
choose a path only because an adjacent pass happens to call it. The Rust owner
and shader path should tell the same ownership story.

## Artifact Production

`crates/laniusc-shaders/build.rs` walks the workspace `shaders/` tree and
compiles Slang files that contain a `[shader(...)]` entry point. Files without
an entry point are still tracked as dependencies but are not compiled as
entrypoint artifacts.

For each active entry point, the build script emits:

| File | Purpose |
| --- | --- |
| `{artifact-key}.spv` | SPIR-V module passed to wgpu |
| `{artifact-key}.reflect.json` | Slang reflection consumed by Rust |
| `{artifact-key}.stamp` | compile command fingerprint for freshness checks |
| `artifacts.env` | digest/count/size metadata for CLI and pipeline-cache identity |
| generated Rust lookup | optional embedded lookup in `laniusc-shaders` |

The stable artifact root is:

```text
target/laniusc-shader-artifacts/{profile}/shaders
```

or the same path under `CARGO_TARGET_DIR` when that variable is set.

The compiler crate has its own build script that publishes the same
`LANIUS_SHADER_ARTIFACT_ROOT` path plus version metadata, but it does not compile
the shaders itself. The shader crate is the producer. A clean build path that
runs compiler code must ensure the shader artifact producer has run first.

## Freshness Model

The shader build script tracks:

- `SLANGC`
- `LANIUS_SHADER_DEBUG`
- `LANIUS_SHADER_OPT_LEVEL`
- `LANIUS_SHADER_MAX_SPV_BYTES`
- `LANIUS_SHADER_COMPILE_TIMEOUT_MS`
- `SLANGC_EXTRA_FLAGS`
- every file under `shaders/`

Each compiled shader has a stamp containing the selected `slangc`, optimization
level, and extra flags. An artifact is fresh only when the stamp matches and the
oldest output is newer than the entrypoint and all recursively imported Slang
dependencies.

Imports are collected by parsing simple `import ...;` lines after stripping
line comments. Resolution checks the importing file's directory, the shader
root, and phase roots. This is what lets changing a shared helper such as
`gpu_index`, `prefix_scan`, or `status` rebuild affected entry points without
forcing unrelated entrypoints to compile.

The build script removes stale artifact files for keys that are no longer
active. Do not rely on obsolete `.spv` files staying in the artifact directory.

## Compile Command

The build script invokes `slangc` with:

- target `spirv`
- profile `glsl_450`
- `-fvk-use-entrypoint-name`
- `-reflection-json {artifact}.reflect.json`
- `-emit-spirv-directly`
- optimization level from `LANIUS_SHADER_OPT_LEVEL`, default `1`
- include paths for `shaders/` and the phase roots
- optional `-g3` when `LANIUS_SHADER_DEBUG` is truthy
- optional tokens from `SLANGC_EXTRA_FLAGS`

The entrypoint source is passed as the final argument. Module/helper sources are
not passed as separate compilation units; Slang resolves them through imports
and include paths.

The default compile timeout is 120 seconds per shader. Set
`LANIUS_SHADER_COMPILE_TIMEOUT_MS=0` only when deliberately debugging a stuck
compiler process.

## Size Guard

`LANIUS_SHADER_MAX_SPV_BYTES` caps each compiled SPIR-V artifact. The default is
4 MiB. If a shader exceeds the cap, the build fails with an error telling the
maintainer to split the shader into smaller record/count/scan/scatter/join
passes before relying on it.

Set `LANIUS_SHADER_MAX_SPV_BYTES=0` only for local investigation. A large shader
artifact is a compile-time and pipeline-construction smell, not just a storage
concern.

`artifacts.env` records the size-guard status, configured maximum, largest
artifact name, and largest artifact byte size. CLI doctor/help surfaces read
that metadata through the compiler's `shader_artifacts` module.

## Runtime Artifact Lookup

The compiler crate's runtime path is `shader_artifacts::artifact_path(file)`,
where `file` is usually `{artifact-key}.spv` or
`{artifact-key}.reflect.json`. `gpu::passes_core::make_pass_data_from_shader_key`
turns a key into those two file names.

In current compiler code, pass construction reads SPIR-V and reflection bytes
from files under `LANIUS_SHADER_ARTIFACT_ROOT`. Debug native builds use
`make_pass_data_from_artifact_files`, and non-debug or wasm-target builds use
the same artifact path helper before reading bytes.

The `laniusc-shaders` crate also generates an embedded artifact lookup for
non-debug or wasm-style builds of that crate. Do not assume the compiler pass
loader is using that embedded lookup unless the compiler's `shader_artifacts`
module and `passes_core` are changed together.

## Pass Construction

`PassData` is the reusable descriptor for a compiled GPU pass. It stores:

- the `wgpu::ComputePipeline`
- bind group layouts derived from Slang reflection
- a stable `shader_id`
- reflected thread-group size
- parsed `SlangReflection`

Construction flow:

1. read SPIR-V bytes
2. read reflection JSON bytes
3. parse reflection into `SlangReflection`
4. derive bind group layouts from reflected descriptor sets or flat parameters
5. create a shader module through SPIR-V passthrough
6. create a pipeline layout from the reflected bind group layouts
7. create a compute pipeline, using the device pipeline cache when available
8. store reflected thread-group size, defaulting to `[1, 1, 1]` with a warning
   if reflection omits it

The SPIR-V passthrough call is intentionally unsafe. The invariant is that
Slang produced the module for the selected backend and profile. Do not replace
this with Naga translation casually; shader validation and supported feature
surface would change.

Validation scopes can wrap pass creation when `LANIUS_VALIDATION_SCOPES` is
enabled. A validation error during pipeline construction is returned as a pass
creation error.

## Pass Macros And Wrappers

Most simple pass wrappers use these macros:

- `make_shader_pass!(device, label, entry: "...", shader: "...")`
- `make_main_pass!(device, label, shader: "...")`
- `make_traced_main_pass!(device, trace, stage, label, shader: "...")`
- `impl_static_shader_pass!(PassType, label: "...", shader: "...")`

`impl_static_shader_pass!` generates a `new(device)` constructor that loads
`PassData` and stores it in the pass wrapper. The wrapper still implements
`Pass<Buffers, DebugOutput>` to define:

- a stable pass name
- logical dispatch dimensionality
- access to `PassData`
- mapping from reflected shader resource names to resident Rust buffers
- optional debug readback behavior

Large pipelines, especially type checking and x86 codegen, often use explicit
pass loader structs and phase-specific bind-group builders. That is expected
when a phase has many passes sharing resident buffers, dynamic offsets, or
precomputed bind groups.

## Reflection Contract

`reflection.rs` parses the Slang JSON reflection payload. The compiler uses it
to derive:

- compute entry point selection
- descriptor-set parameter lists
- binding indices
- storage, uniform, texture, and sampler binding types
- dynamic uniform offsets
- thread-group size

Reflection supports two shapes:

- entrypoint program layout with descriptor sets
- flat top-level parameter list

The descriptor-set `space` maps to a wgpu bind-group index. The parameter
`binding.index` maps to the binding inside that group.

Reflection reduces hand-written binding numbers, but it does not remove the
Rust/Slang resource-name contract. If a shader parameter is called
`tokens_out`, the Rust pass wrapper must provide a resource with that exact
name. A typo is a real ABI break.

Some dynamic-offset decisions come from reflected custom attributes. There are
also explicit fallback names for known global constant buffers where Slang's
JSON reflection currently omits the attribute. Treat those fallback names as
ABI debt: update this document, [Shader artifact and reflection ABI](shader-abi.md),
and the reflection tests if that list changes.

## Bind Groups

There are two reflected bind-group helpers:

- `create_bind_group_from_reflection` accepts a `HashMap<String,
  BindingResource>` and looks up each reflected parameter by name.
- `create_bind_group_from_bindings` accepts an ordered slice of named resources,
  uses the fast reflected-order path when the slice matches reflection, and
  falls back to name lookup otherwise.

Simple `Pass` implementations normally build a resource map on every dispatch
or use a `BindGroupCache` supplied by the phase. Large phases often build bind
groups once and store them in phase-specific structs.

`BindGroupCache` is keyed by `shader_id` and set index. Cached bind groups are
valid only while every referenced `wgpu::Buffer`, texture view, or sampler is
still the same object. Owners must clear or remove cache entries after resizing
or replacing resident buffers.

The lexer is the clearest example: it clears the whole cache on resident-buffer
resize and removes specific pass entries when ping/pong scratch buffers are
reused with changed roles.

## Dispatch Planning

`plan_workgroups` is the shared direct-dispatch planner. It translates logical
input sizes into `(gx, gy, gz)` using the pass's reflected thread-group size.

Supported logical inputs:

- `InputElements::Elements1D(n)`
- `InputElements::Elements2D(width, height)`

The central WebGPU limit is `MAX_GROUPS_PER_DIM = 65_535`. For oversized 1D
inputs, `plan_workgroups` tiles across Y by using `gx = 65_535` and
`gy = ceil(groups / 65_535)`. Pass-specific code should not duplicate that
limit.

The planner always dispatches at least one workgroup for direct passes. Shaders
must guard against `i >= logical_count` when the logical count can be zero or
when padding/tiled groups exceed the true record count.

Indirect dispatch is used when an earlier GPU phase computes workgroup counts.
The shared `Pass` trait exposes `record_pass_indirect`, and
`ComputePassBatch` exposes `record_pass_indirect_cached`.

## Pass Context

`PassContext<'a, B, D>` carries the shared recording state:

- `device`
- mutable `CommandEncoder`
- phase-owned resident buffer bundle `B`
- optional `GpuTimer`
- optional phase-specific debug output `D`
- optional `BindGroupCache`

The `Pass` trait consumes that context to record direct or indirect dispatches.
The trait deliberately does not know concrete phase semantics. `B` and `D` are
generic so lexer, parser, type-checker, and backend pass wrappers can use the
same machinery without sharing buffer types.

If a pass cannot be expressed by `PassContext`, prefer a local wrapper in the
owning phase over making `PassContext` understand a special compiler concept.

## Compute-Pass Batching

`ComputePassBatch` records multiple compatible passes into one
`wgpu::ComputePass`. This reduces pass-boundary overhead when passes can share
the same encoder pass without timers, debug output, or validation scopes.

Batching is controlled by `LANIUS_BATCH_COMPUTE_PASSES`; it defaults to enabled
unless set to `0` or `false`. Phase code must also disable batching when:

- GPU timers need per-pass stamps
- debug readback is active
- validation scopes are active
- the phase lacks a valid bind-group cache
- pass ordering requires a different command-encoder operation between passes

Batching does not change data dependencies. A pass can be batched only when the
same sequence would also be valid as separate compute passes in one command
encoder.

## Submission And Readback

`submit_with_progress` submits a command buffer, records a host trace span, and
emits progress logging when GPU progress tracing is enabled.

`submit_with_optional_validation` wraps submission in a wgpu validation scope
when requested, then reports any validation error from the scope.

Readback helpers provide two styles:

- queue a map and rely on a later device poll
- block with progress output and `LANIUS_READBACK_TIMEOUT_MS`

Readback is not a neutral observation mechanism in this compiler. It can force
host/device synchronization and dominate runtime. Prefer resident GPU
continuation unless a diagnostic, test, CLI command, or exact-count boundary
really needs host data.

## Timers And Traces

`GpuTimer` writes timestamp queries into a command encoder, resolves them into a
readback buffer, and converts timestamps with the queue's timestamp period.
Phases should allocate a timer only when the device supports timestamp queries
and an environment flag or trace path asks for timing.

The trace module writes Chrome/Perfetto-compatible JSON when
`LANIUS_PERFETTO_TRACE` or `LANIUS_GPU_TRACE_JSON` is set. It records host spans,
GPU spans, instants, and counters. Trace collection is cheap when disabled
because each public recorder checks the global state before appending events.

Pipeline construction progress uses `LANIUS_PIPELINE_TRACE`. Coarse submission,
map, and poll progress also becomes visible when `LANIUS_GPU_PIPELINE_PROGRESS`,
`LANIUS_PIPELINE_TRACE`, `LANIUS_WASM_TRACE`, or `LANIUS_X86_TRACE` is truthy.

## Environment Variables

Shader artifact production:

| Variable | Effect |
| --- | --- |
| `SLANGC` | path to `slangc` |
| `LANIUS_SHADER_DEBUG` | adds debug info to Slang compile command |
| `LANIUS_SHADER_OPT_LEVEL` | Slang optimization level, default `1` |
| `LANIUS_SHADER_MAX_SPV_BYTES` | maximum SPIR-V bytes per shader, `0` disables |
| `LANIUS_SHADER_COMPILE_TIMEOUT_MS` | per-shader compile timeout, `0` disables |
| `SLANGC_EXTRA_FLAGS` | extra whitespace-split flags passed to `slangc` |

Runtime pass behavior:

| Variable | Effect |
| --- | --- |
| `LANIUS_BATCH_COMPUTE_PASSES` | enables compatible compute-pass batching |
| `LANIUS_VALIDATION_SCOPES` | enables selected wgpu validation scopes |
| `LANIUS_PIPELINE_TRACE` | logs pipeline creation stages |
| `LANIUS_GPU_PIPELINE_PROGRESS` | logs submit/map/poll progress |
| `LANIUS_READBACK_TIMEOUT_MS` | timeout for blocking readback maps |
| `LANIUS_GPU_TIMING` | enables GPU timing in selected direct paths |
| `LANIUS_GPU_COMPILE_HOST_TIMING` | prints host timing spans in compile paths |
| `LANIUS_PERFETTO_TRACE` / `LANIUS_GPU_TRACE_JSON` | writes trace JSON |

Document new flags here and in `gpu.md` when they affect reusable GPU behavior.

## Adding A Shader Pass

When adding a simple phase pass:

1. Place the `.slang` file under the owning phase root.
2. Give it a compute entry point with a stable entry name.
3. Import shared helpers rather than copying helper code.
4. Add Rust buffers in the owning phase's resident buffer struct.
5. Add a pass wrapper or loader that points at the artifact key.
6. Implement `create_resource_map` or a phase-specific bind-group builder using
   reflected parameter names.
7. Add the pass to the owning phase's pass-order recorder.
8. Update the owning phase doc if the pass changes data flow or invariants.
9. Regenerate `docs/compiler/generated/reference.md` if shader load-site or
   shader inventory tables changed.

Use the static pass macro path for one-off reflected passes. Use a
phase-specific bind-group builder when the pass needs dynamic offsets, shared
bind groups, repeated scan steps, or precomputed groups for many related
passes.

## Moving Or Renaming A Shader

Shader paths are not just organization. The path without extension is the
artifact key loaded by Rust. Moving a shader requires:

1. moving the `.slang` file
2. updating every Rust shader key literal
3. checking imports still resolve from the new location
4. letting stale artifacts be removed by the shader build script
5. regenerating the generated compiler reference

Do not leave compatibility aliases for old shader paths unless another human
being needs that compatibility. Extra aliases create the false impression that
old paths are meaningful supported API.

## Changing Shader Resources

When adding, removing, or renaming a shader resource:

1. Update the Slang parameter.
2. Confirm reflection emits the expected binding type and set.
3. Update the Rust resource map or named binding slice.
4. Update resident buffer allocation and lifetime ownership.
5. Clear or invalidate bind-group caches if buffer object identity can change.
6. Run a focused test or compile path that constructs the pass and records it.

The fastest failure is usually `no resource provided for ...` from reflected
bind-group creation. Treat that as a resource-map mismatch, not a shader logic
failure.

## Failure Modes

Common failures and owning layers:

| Symptom | Likely owner |
| --- | --- |
| `slangc` not found | shader artifact build setup |
| shader compile timeout | shader artifact build or pathological shader |
| SPIR-V size guard failure | shader too large; split passes |
| missing `.spv` or `.reflect.json` | artifact producer did not run, stale key, or wrong artifact root |
| no compute entry point in reflection | shader source or Slang reflection output |
| missing thread-group size | reflection output; defaults to `[1,1,1]` with warning |
| no resource provided for parameter | Rust resource map/bindings mismatch |
| validation error while creating pass | reflected layout, SPIR-V, or wgpu binding type mismatch |
| validation error while submitting pass | dispatch, resource usage, or pass ordering mismatch |
| incorrect output with valid submit | shader semantics or phase pass order |

Prefer locating the owning layer before broad readback. Most shader/pass bugs
are cheaper to diagnose by constructing the pass, checking reflected resources,
and narrowing to one phase than by dumping large resident buffers.

## Generated Evidence

The generated compiler reference owns volatile shader facts:

- shader source file count
- compute entrypoint count
- Rust shader load sites
- shader group/import coupling
- type-check pass loader entries
- buffer carrier structs and large edit surfaces
- status-code inventories

Run:

```bash
tools/compiler_inventory.py --output docs/compiler/generated/reference.md
tools/compiler_inventory.py --check docs/compiler/generated/reference.md
```

Treat a "missing shader source" row as a real break. Treat "entrypoints not
found by recognized Rust literal patterns" as an extractor-coverage signal
first; inspect the load path before deleting or renaming a shader.

## Common Mistakes

- Editing a shader path without updating Rust artifact keys.
- Hand-writing binding numbers that reflection already provides.
- Renaming a Slang parameter without updating the Rust resource map.
- Keeping a cached bind group after replacing a buffer handle.
- Adding broad host readback to debug a phase that can be isolated with
  validation scopes or a focused pass construction test.
- Duplicating the `65_535` dispatch-dimension limit in phase code.
- Treating the shader crate's embedded lookup as if the compiler pass loader
  automatically uses it.
- Passing helper/module `.slang` files to `slangc` as entrypoint sources.
- Disabling the SPIR-V size guard instead of splitting oversized shaders.
- Adding path compatibility aliases for shader moves when no other human needs
  the old path.

## Evidence To Update

| Change | Evidence |
| --- | --- |
| New or moved shader | regenerated compiler reference; focused pass construction or compile path |
| Import/helper change | shader artifact freshness rebuild; affected phase test |
| Reflected resource change | pass construction plus focused phase run |
| Bind-group cache change | test or compile path that resizes/reuses resident buffers |
| Dispatch-planning change | focused `plan_workgroups` tests or a phase path exceeding one dimension |
| Artifact build behavior | shader crate build-script check or clean build that regenerates artifacts |
| Environment flag change | update this document and `gpu.md` |
| Large shader split | size-guard metadata and focused phase behavior test |

For documentation-only updates to this file, run the generated-reference check
and Markdown hygiene checks. For Rust or Slang changes, add the focused compiler
or shader checks that exercise the owning phase.
