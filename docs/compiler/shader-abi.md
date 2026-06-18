# Shader Artifact And Reflection ABI

This chapter documents the ABI between Slang shader source, generated shader
artifacts, Slang reflection JSON, and Rust pass construction.

The ABI is intentionally narrow:

- shader source owns the parallel data transform
- the shader build script owns SPIR-V and reflection artifact production
- `reflection.rs` owns conversion from Slang reflection to wgpu layouts
- `gpu::passes_core` owns pass construction and reflected bind groups
- phase code owns buffer lifetime, pass order, dispatch counts, and semantics

Do not use this ABI as a place to preserve old shader paths, old parameter
names, or old binding layouts. Compatibility is only useful when another human
being needs it. Otherwise it is net negative: it leaves extra paths that look
intentional, increases review surface, and makes the current resource contract
harder to see.

## What This Chapter Owns

Use this chapter when changing:

- shader artifact keys
- shader compile/freshness behavior
- runtime artifact lookup
- generated artifact metadata
- Slang reflection structs
- binding-type conversion
- dynamic-offset detection
- reflected bind-group creation
- shader resource names
- debug versus embedded artifact behavior

Use [GPU passes and shader artifacts](gpu-passes.md) for the broader pass
authoring workflow. Use [GPU infrastructure](gpu.md) for device, pipeline
cache, dispatch planning, timers, tracing, and readback helpers.

This chapter does not own phase-specific pass order. Lexer, parser, type
checker, WASM, and x86 docs own what each pass means.

## Source Map

| Source | Responsibility |
| --- | --- |
| `shaders/` | Slang source files, imports, compute entry points, reflected parameters, custom attributes. |
| `crates/laniusc-shaders/build.rs` | Walks shader source, compiles active entry points, checks freshness, writes SPIR-V/reflection/stamps/metadata, removes stale artifacts, emits generated lookup code. |
| `crates/laniusc-shaders/src/lib.rs` | Public artifact-root/path helpers, generated embedded lookup, metadata access. |
| root `build.rs` | Publishes the shader artifact root to the root crate from `laniusc-shaders`. |
| `crates/laniusc-compiler/build.rs` | Publishes compiler build metadata and the same shader artifact root path. |
| `crates/laniusc-compiler/src/shader_artifacts.rs` | Compiler runtime artifact-path and artifact metadata helper. |
| `crates/laniusc-compiler/src/reflection.rs` | Slang reflection data model, JSON parsing, binding-type conversion, texture/sampler format mapping, thread-group-size extraction. |
| `crates/laniusc-compiler/src/gpu/passes_core.rs` | Pass construction from artifact keys, reflected bind-group-layout creation, reflected bind-group creation, dispatch planning, pass macros. |
| phase pass wrappers | Select shader keys, provide Rust resources by reflected name, cache bind groups only while buffers remain valid. |

The split matters because artifact production is build-time work, reflection
conversion is ABI interpretation, and phase pass wrappers are the only layer
that knows which resident buffer should satisfy a shader parameter.

## Artifact Identity

A shader artifact key is the path under `shaders/` without the `.slang`
extension. Slashes are preserved.

Examples:

| Source file | Artifact key | Runtime files |
| --- | --- | --- |
| `shaders/lexer/tokens_build.slang` | `lexer/tokens_build` | `lexer/tokens_build.spv`, `lexer/tokens_build.reflect.json` |
| `shaders/parser/hir/nodes.slang` | `parser/hir/nodes` | `parser/hir/nodes.spv`, `parser/hir/nodes.reflect.json` |
| `shaders/codegen/x86/virtual/regalloc.slang` | `codegen/x86/virtual/regalloc` | `codegen/x86/virtual/regalloc.spv`, `codegen/x86/virtual/regalloc.reflect.json` |

Rust pass loaders should use the key without extensions. The helper appends
`.spv` and `.reflect.json`.

The key is a real ABI string because Rust stores it in shader load-site
literals and the generated reference extracts it. Moving a shader requires
updating all load sites. Do not leave an alias for the old path unless another
maintainer is actively depending on that old path during a coordinated change.

## Build-Time Producer

`crates/laniusc-shaders/build.rs` is the producer for active shader artifacts.
It:

1. Locates the workspace root.
2. Tracks every file under `shaders/` for Cargo rebuild decisions.
3. Finds `slangc` from `SLANGC`, `PATH`, or a sibling `bin` directory inferred
   from `LD_LIBRARY_PATH`.
4. Chooses the stable artifact root under `target/laniusc-shader-artifacts`.
5. Walks every `.slang` file.
6. Compiles only files that contain a `[shader(...)]` entrypoint attribute.
7. Skips explicitly unwired entrypoint fixtures.
8. Checks whether outputs are fresh against the compile stamp and recursively
   imported shader dependencies.
9. Runs `slangc` for stale active entrypoints.
10. Validates the SPIR-V size guard.
11. Removes stale output files for inactive keys.
12. Writes generated Rust lookup code into `OUT_DIR`.
13. Writes `artifacts.env` metadata into the artifact root.
14. Emits artifact metadata as rustc environment variables only when artifacts
   are embedded for the target/profile.

Helper `.slang` files without entry points are dependencies, not artifacts.
They should be imported by entrypoint shaders, not compiled directly.

## Artifact Root

The stable artifact root is:

```text
target/laniusc-shader-artifacts/{profile}/shaders
```

When `CARGO_TARGET_DIR` is set, that target directory replaces `target`.

The build scripts publish this path through `LANIUS_SHADER_ARTIFACT_ROOT`.
Runtime helpers derive paths by joining file names under that root. A pass that
loads `parser/hir/nodes` therefore reads:

```text
${LANIUS_SHADER_ARTIFACT_ROOT}/parser/hir/nodes.spv
${LANIUS_SHADER_ARTIFACT_ROOT}/parser/hir/nodes.reflect.json
```

Do not construct alternate artifact roots in phase code. Root selection belongs
to the build scripts and artifact helper modules.

## Freshness

The shader build script rebuilds an active entrypoint when any of these change:

- `SLANGC`
- `LANIUS_SHADER_DEBUG`
- `LANIUS_SHADER_OPT_LEVEL`
- `LANIUS_SHADER_MAX_SPV_BYTES`
- `LANIUS_SHADER_COMPILE_TIMEOUT_MS`
- `SLANGC_EXTRA_FLAGS`
- the entrypoint source
- any recursively imported shader dependency

Freshness uses two pieces of evidence:

| Evidence | Meaning |
| --- | --- |
| `{artifact-key}.stamp` | The selected `slangc`, optimization level, and extra flags match the previous compile. |
| artifact/dependency mtimes | The oldest output is newer than the entrypoint and every resolved import dependency. |

Import dependency scanning is intentionally simple. It strips line comments,
then recognizes lines shaped like `import NAME;`. Import resolution checks the
importing directory, the shader root, and the phase roots.

This gives the property we want for normal development: changing a shared helper
such as `gpu_index` or `prefix_scan` rebuilds affected entrypoints without
recompiling unrelated entrypoints.

## Compile Command Contract

The shader producer invokes `slangc` with:

- `-target spirv`
- `-profile glsl_450`
- `-fvk-use-entrypoint-name`
- `-reflection-json {artifact}.reflect.json`
- `-emit-spirv-directly`
- `-O{LANIUS_SHADER_OPT_LEVEL}`, default `-O1`
- include paths for `shaders/`, `lexer`, `parser`, `type_checker`, and
  `codegen`
- optional `-g3` when `LANIUS_SHADER_DEBUG` is truthy
- optional whitespace-split `SLANGC_EXTRA_FLAGS`
- the entrypoint source as the final argument

Do not pass helper modules as extra source files. The import graph is the
source of truth for shared shader code.

The default per-shader compile timeout is 120 seconds. Setting
`LANIUS_SHADER_COMPILE_TIMEOUT_MS=0` disables the timeout and should be reserved
for local investigation.

## Size Guard

`LANIUS_SHADER_MAX_SPV_BYTES` caps each active SPIR-V artifact. The default cap
is 4 MiB. A cap failure means the shader is too large for the current compiler
shape; split it into smaller record/count/scan/scatter/join passes.

Disabling the cap with `LANIUS_SHADER_MAX_SPV_BYTES=0` is not a fix. It removes
evidence that one shader has become an expensive compile and pipeline
construction unit.

`artifacts.env` records:

- artifact digest
- artifact count
- largest SPIR-V byte size
- largest SPIR-V artifact name
- size-guard status
- configured size-guard maximum

CLI version and doctor paths expose this metadata so maintainers can see the
active shader artifact set without reading the artifact directory by hand.

## Debug And Embedded Artifacts

Native debug builds should not embed SPIR-V/reflection bytes. They read artifact
files at runtime through `LANIUS_SHADER_ARTIFACT_ROOT`.

The `laniusc-shaders` generated lookup follows this split:

| Build shape | Generated lookup behavior |
| --- | --- |
| native debug | `embedded_artifact` returns `None`; metadata reads `artifacts.env` at runtime. |
| release or wasm-style target | `embedded_artifact` can return `include_bytes!` data; metadata can come from compile-time environment variables. |

The compiler pass loader currently resolves file paths and reads bytes through
`shader_artifacts::artifact_path`. Do not assume that the compiler is using the
`laniusc-shaders` embedded lookup unless `shader_artifacts.rs` and
`gpu::passes_core` are changed together.

The practical rule is:

- debug native: fast edit/debug loop, no giant embedded SPIR-V blobs in the
  compiler binary
- release/wasm-style artifact crate behavior: generated lookup may embed bytes
  when that crate is built for such a shape

If this changes, update this chapter, [GPU passes and shader artifacts](gpu-passes.md),
and the CLI metadata tests that prove version/doctor output still reports the
active artifact set.

## Runtime Artifact Lookup

Runtime pass construction starts from a shader key:

```text
make_pass_data_from_shader_key(device, label, entry, "parser/hir/nodes")
```

That helper calls:

```text
make_pass_data_from_shader_artifacts(
    device,
    label,
    entry,
    "parser/hir/nodes.spv",
    "parser/hir/nodes.reflect.json",
)
```

For native debug builds, `make_pass_data_from_artifact_files` reads the exact
SPIR-V and reflection files from the artifact root. For other compiler builds,
the current compiler helper still resolves artifact paths and reads files.

Missing `.spv` or `.reflect.json` files usually mean one of:

- the shader producer did not run
- the Rust shader key is stale
- the artifact root is different from the one used by the producer
- a shader was moved and stale compatibility paths hid the real key change

Fix the producer/key/root mismatch directly. Do not add fallback lookup paths
unless another maintainer needs a temporary migration path.

## PassData Construction

`PassData` is the reusable runtime product of the shader ABI. It contains:

| Field | Source |
| --- | --- |
| `pipeline` | wgpu compute pipeline built from SPIR-V and reflected layouts. |
| `bind_group_layouts` | wgpu bind-group layouts derived from Slang reflection. |
| `shader_id` | Stable pass label used by cache keys, traces, and diagnostics. |
| `thread_group_size` | Reflected compute thread-group size, or `[1, 1, 1]` with a warning if omitted. |
| `reflection` | Parsed Slang reflection tree used by reflected bind-group builders. |

The construction flow is:

1. Read SPIR-V bytes.
2. Read reflection JSON bytes.
3. Parse reflection into `SlangReflection`.
4. Find the compute entry point.
5. Build bind-group layouts from program-layout parameter sets or flat
   parameters.
6. Create the SPIR-V shader module through wgpu passthrough.
7. Create the pipeline layout.
8. Create the compute pipeline, using the device pipeline cache when available.
9. Extract the reflected thread-group size.

The passthrough shader-module call is unsafe because it bypasses normal shader
translation. The invariant is that Slang produced the SPIR-V for the selected
target/profile. Treat changes to the Slang target, profile, or validation route
as ABI changes.

## Reflection Payload Model

`reflection.rs` models only the reflection fields the compiler consumes:

| Reflection type | Compiler use |
| --- | --- |
| `SlangReflection` | Top-level parameters, entry points, named type layouts. |
| `EntryPointReflection` | Compute-stage selection, program layout, thread-group size. |
| `ProgramLayoutReflection` | Descriptor-set parameter lists. |
| `ParameterSetReflection` | One reflected parameter space, mapped to bind-group index. |
| `ParameterReflection` | Resource name, binding metadata, type layout, user attributes. |
| `BindingInfo` | Binding index plus optional offset/size metadata. |
| `TypeLayout` | Resource kind, base shape, access, texture format, uniform size, array shape. |
| `UserAttribute` | Custom attributes such as `DynamicOffset` and `CustomFormat`. |

Reflection supports two input shapes:

- compute entry point with a program layout and descriptor-set parameter lists
- flat top-level parameter list

The program-layout form is preferred when Slang emits it. The descriptor-set
`space` maps to the bind-group index, and each parameter's `binding.index`
maps to the binding inside that group.

## Binding-Type Conversion

`slang_category_and_type_to_wgpu` converts a reflected parameter/type pair into
a `wgpu::BindingType`.

The main mappings are:

| Slang reflection shape | wgpu binding |
| --- | --- |
| uniform-scale `constantBuffer` or `parameterBlock` | uniform buffer |
| `structuredBuffer`, `buffer`, or `byteAddressBuffer` | storage buffer |
| sampled texture resource | texture binding |
| storage texture resource | storage texture binding |
| sampler state | sampler binding |

Storage-buffer read-only state comes from reflected access. Texture format and
view dimensions come from reflected shape/format, with `CustomFormat` as a
targeted escape hatch when Slang does not emit enough texture format detail.

If conversion returns `None`, that parameter is skipped when building the
layout. That is only acceptable for reflection shapes the compiler deliberately
does not bind. An unexpected warning about an unhandled kind, shape, access, or
format should be treated as an ABI bug.

## Dynamic Offsets

Dynamic uniform offsets are detected in two ways:

1. A reflected `DynamicOffset` custom attribute on the parameter.
2. A small explicit fallback-name set for known x86 global constant buffers
   where Slang reflection currently omits the attribute.

The fallback names are:

- `gRegalloc`
- `gNextCallScan`
- `gFuncOwnerBlockScan`
- `gNodeInstBlockScan`

This fallback list is ABI debt, not a naming convention. If a new dynamic
uniform needs fallback treatment, first check whether Slang can reflect the
attribute. If fallback is still necessary, update `reflection.rs`, reflection
unit tests, this chapter, and the owning backend documentation.

Do not rename a shader parameter just to inherit one of these fallback names.
The parameter name should describe the shader resource; dynamic-offset behavior
should be explicit.

## Bind-Group Layouts

`bgls_from_reflection` builds one or more `wgpu::BindGroupLayout`s from the
parsed reflection.

It requires a compute entry point. Without one, pass construction fails with
`no compute entry point found in reflection`.

For program-layout reflection, it creates one bind-group layout per reflected
parameter set. For flat reflection, it creates one layout from the top-level
parameters.

Each layout entry uses:

- reflected binding index
- compute visibility
- converted binding type
- no array binding count

The ABI expectation is that shader parameter names and binding indices come
from Slang reflection. Rust should not duplicate those binding numbers in phase
code unless the local helper is documenting a deliberate reflected layout.

## Bind-Group Creation

There are two reflected bind-group creation helpers:

| Helper | Input shape | Failure behavior |
| --- | --- | --- |
| `create_bind_group_from_reflection` | `HashMap<String, BindingResource>` | Requires every reflected parameter in the set to have a resource by exact name. |
| `create_bind_group_from_bindings` | Ordered slice of `(name, resource)` | Uses reflected-order fast path when names match, otherwise falls back to exact name lookup. |

Both helpers use reflected parameter names as the contract. A failure like:

```text
no resource provided for 'tokens_out' in bind group '...'
```

means the Rust resource map and Slang parameter list disagree. Fix the resource
owner or the shader parameter. Do not add a duplicate Rust resource under the
old name unless another maintainer needs a short-lived migration path.

The ordered helper is a performance/convenience path, not a semantic
difference. It must produce the same bind group as name lookup.

## Bind-Group Caches

`BindGroupCache` stores bind groups by `shader_id` and set index. The cache does
not understand compiler semantics. It only remembers concrete GPU resource
objects.

A cached bind group is valid only while every captured resource remains:

- the same buffer/texture/sampler object
- large enough for the current dispatch
- semantically assigned to the same row family
- alive for the duration of pass recording/submission

Phase code must clear or remove cache entries when it resizes buffers, replaces
buffers, swaps ping/pong roles, reuses scratch storage with a different meaning,
or changes the pass/resource relationship.

If a phase cannot state the invalidation rule, it should not cache the bind
group.

## Thread-Group Size

`get_thread_group_size` reads the compute entry point's reflected
`thread_group_size`. `make_pass_data` stores it in `PassData`.

If reflection omits the size, the compiler warns and defaults to `[1, 1, 1]`.
That default lets pass construction continue, but it is not proof that dispatch
planning is efficient. A missing thread-group size should be investigated when
adding or moving a shader.

Dispatch planning uses the reflected size. A shader with a wrong or missing
workgroup declaration can therefore change performance or logical coverage even
when all bindings validate.

## Metadata Surfaces

Shader artifact metadata appears in user-visible no-run surfaces:

- `laniusc --version`
- `laniusc doctor`
- diagnostics metadata commands that report runtime/toolchain state

Those surfaces read:

- digest
- count
- largest artifact name
- largest artifact byte size
- size-guard status
- size-guard maximum
- `slangc` and shader compile timeout metadata from the compiler build script

This metadata is not language semantics. It is build/runtime evidence used to
debug stale artifacts, oversized shaders, and pipeline-cache identity.

## Changing A Shader Resource

Use this sequence when adding, removing, or renaming a shader parameter:

1. Change the Slang parameter in the owning shader.
2. Confirm the reflected type is one that `reflection.rs` maps to the intended
   wgpu binding.
3. If the parameter is a uniform with dynamic offset, prefer a reflected
   `DynamicOffset` attribute.
4. Update the owning Rust pass wrapper or phase-specific bind-group builder
   with the exact reflected name.
5. Update buffer allocation/lifetime ownership in the phase.
6. Audit bind-group cache invalidation for any changed resource object.
7. Run a focused pass construction or compile path that reaches the pass.
8. Regenerate/check the generated compiler reference when shader inventory or
   load sites changed.

Keep the smallest source that exercises the pass. If a shader resource mismatch
can be caught at pass construction time, do not rely on a broad compile test to
discover it later.

## Moving Or Renaming A Shader

Moving a shader changes the artifact key. The correct sequence is:

1. Move the `.slang` file.
2. Update imports if relative import resolution changes.
3. Update every Rust shader key literal.
4. Run the generated reference check to catch stale load sites.
5. Let the shader build script remove stale artifact files.
6. Run the narrow phase test or compile path that constructs the moved pass.

Do not add old-key lookup fallbacks by default. Old keys are not public API for
code consumers. They are implementation details for maintainers in this repo.
Keep only the current key unless another human maintainer needs a temporary
handoff path.

## Failure Modes

| Symptom | Owning layer | Usual fix |
| --- | --- | --- |
| `slangc` not found | shader producer setup | Install Slang or set `SLANGC`. |
| compile timeout | shader producer or pathological shader | Inspect the shader/import graph; split oversized work. |
| SPIR-V size guard failure | shader shape | Split the shader; do not disable the cap as a fix. |
| missing `.spv` or `.reflect.json` | producer/key/root mismatch | Run producer, update key, or fix artifact root. |
| stale output after helper edit | freshness import scan | Check import syntax and dependency resolution. |
| `no compute entry point found in reflection` | shader source/reflection | Add or fix compute entrypoint annotation. |
| missing thread-group-size warning | shader source/reflection | Confirm the compute declaration reflects its workgroup size. |
| unhandled reflection kind/shape/format warning | reflection ABI | Add a deliberate mapping or change shader resource shape. |
| `no resource provided for ...` | Rust resource map | Bind the exact reflected parameter name. |
| validation while creating pass | reflection, SPIR-V, wgpu binding type | Check layout conversion and shader resource declarations. |
| validation while submitting pass | phase pass order/resources/dispatch | Check cache invalidation, resource usages, and dispatch args. |
| valid submit but wrong data | shader semantics or phase order | Debug the owning phase, not the artifact ABI. |

Start with artifact key, reflection, and resource names before adding readback.
Most ABI failures are visible before the shader transforms any user data.

## Generated Evidence

The generated compiler reference owns volatile shader facts:

- shader source inventory
- compute entrypoint count
- Rust shader load sites
- shader group/import coupling
- status and large-struct inventories affected by pass changes

Run:

```bash
tools/compiler_inventory.py --output docs/compiler/generated/reference.md
tools/compiler_inventory.py --check docs/compiler/generated/reference.md
```

Treat a missing shader source or stale load site as a real break. Treat an
unknown extractor pattern as an inventory-tool coverage issue only after
inspecting the actual load path.

## Test Evidence

| Change | Evidence |
| --- | --- |
| Reflection binding conversion | `reflection.rs` unit test for the smallest reflected parameter shape. |
| Dynamic-offset fallback | reflection unit test plus owning backend doc update. |
| Bind-group helper behavior | `passes_core` bind-group unit test or focused pass construction. |
| Shader resource change | focused phase test or compile input that constructs and records the pass. |
| Shader move/rename | generated reference check plus focused pass construction. |
| Artifact producer freshness | shader crate build-script behavior or clean build that recompiles the affected artifact. |
| Metadata surface change | CLI version/doctor metadata tests. |
| Docs-only edit | generated reference freshness, local Markdown link check, ASCII check, trailing whitespace check. |

Avoid broad compiler tests for ABI-only docs changes. For Rust/Slang changes,
test the boundary that can actually fail.

## Common Mistakes

- Treating shader paths as cosmetic file organization.
- Leaving old shader path aliases after a move with no human migration need.
- Renaming a Slang parameter without updating the Rust resource map.
- Adding a Rust resource under both old and new names.
- Assuming debug native builds embed SPIR-V/reflection bytes.
- Assuming the compiler pass loader uses the `laniusc-shaders` embedded lookup.
- Adding a dynamic-offset fallback name instead of fixing/refining reflection.
- Hand-writing binding numbers that reflection already provides.
- Keeping a bind-group cache after replacing a buffer object.
- Debugging a resource-name mismatch with broad resident-buffer readback.
- Disabling shader size guards instead of splitting oversized passes.

The healthiest shader ABI is boring: one current artifact key, reflected
layouts, exact parameter names, phase-owned lifetimes, and focused evidence for
the pass that changed.
