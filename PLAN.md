Here is the explicit execution plan, in order. The sequence matters: correctness establishes the contract, architecture fixes memory scaling, and only then do performance measurements become trustworthy.

## Phase 1: Make the complete sample suite green

Run every sample on every target declared in [MANIFEST.tsv](/home/andrew-peterson/code/laniusc/sample_programs/MANIFEST.tsv), beginning from the latest verified state:

- `range_sum`: x86 and Wasm currently working.
- `array_return_helpers`: x86 currently working; decide whether its semantics are supported on Wasm and, if so, add Wasm coverage.
- Continue through all 37 checked samples rather than stopping after the first repaired failure.
- Fix each failure at the semantic-HIR, type-system, lowering-IR, runtime-ABI, or target-emission boundary that owns it.
- Do not add filename detection, sample-specific lowering, token-stream type checking, or structural pattern matching for a particular program.
- Record the final target matrix and output hashes, including the raytracer’s PPM artifact.

Exit condition: every declared x86 and Wasm sample compiles, runs, produces the expected output/files, and exits with the expected status.

## Phase 2: Finish the compact frontend boundary

Make `GpuHirView` the sole input to type checking:

1. Classify every field in `OwnedTypecheckParserBuffers` as one of:

   - Permanent compact HIR data.
   - A temporary parse/HIR-construction array.
   - Type-checker workspace.
   - Obsolete compatibility data.

2. Move legitimate permanent fields into the appropriate compact HIR core, links, payload, or family side table.

3. Translate every semantic reference into a dense HIR ID, compact family-row ID, token ID, or file ID during HIR materialization.

4. Ensure `raw_to_hir`, `hir_to_raw`, raw tree navigation, production records, bracket arrays, and parser compaction arrays stop being visible after HIR construction.

5. Convert type-checker stages in coherent semantic groups:

   - Generic parameters and parameter types.
   - Modules, imports, declarations, and name resolution.
   - Calls, arguments, return types, and entrypoints.
   - Arrays, structures, fields, variants, and matches.
   - Methods, traits, implementations, and predicates.
   - Control flow, ownership, and expression result metadata.

6. Delete `OwnedTypecheckParserBuffers` when its final consumer is gone.

Exit condition: the type checker can only access compact HIR and explicitly declared workspace; no shader or Rust type-checking code can bind raw parse-tree columns.

## Phase 3: Finish the compact backend boundary

Reduce `ResidentTypeCheckState` to reusable workspace and produce a compact `GpuSemanticArtifact`:

- Retain only declaration, expression, call, type, layout, control-flow, and ABI metadata that semantic lowering actually consumes.
- Move pointer jumping, scans, sorting keys, ownership relations, temporary call matching, visible-name construction, and similar intermediate data into phase-local workspace.
- Ensure semantic lowering consumes `GpuSemanticArtifact`, not type-checker implementation buffers.
- Finish aggregate-return, member/index access, stores, runtime calls, and control-flow coverage on both target IRs.
- Delete remaining direct raw-HIR or type-checker-buffer access from x86 and Wasm emission.

Exit condition: both backends receive the same compact semantic artifact, lower it into their respective target IR, and emit bytes without consulting parser or type-checker scratch storage.

## Phase 4: Make the compiler graph own temporary storage

Turn the existing graph into the authoritative resource-lifetime system:

- Give each logical resource a domain, element width, capacity expression, usage flags, producer, consumers, and lifetime.
- Derive shader binding access from Slang reflection where possible.
- Express prefix scan, radix sort, bracket matching, compaction, and similar algorithms as complete graph operations. Callers provide logical inputs and outputs; the operation owns its pipelines, internal arrays, bindings, and passes.
- Remove type-checker-local buffer constructors and large bind-group argument lists.
- Assign non-overlapping temporary resources to shared physical workspace slots.
- Preserve separate slots where simultaneous access, read/write hazards, usage flags, or indirect dispatch require it.
- Validate that overlapping writable resources never alias.
- Add phase fences for resources whose full lifetime cannot be inferred from shader bindings alone.
- Fail graph construction when a temporary resource lacks a bounded lifetime.

Exit condition: temporary GPU allocation follows the compiler graph’s workspace plan; individual type-checking subsystems no longer create independent scratch-buffer collections.

## Phase 5: Reuse capacity-stable job workspaces

Keep normal daemon startup lightweight while making repeated compilation jobs allocation-free:

- Configure a default maximum frontend compilation-unit size of 10 MB.
- During daemon startup, create every x86 and Wasm pipeline needed for compilation, but do not allocate or retain capacity-scaled compilation workspace buffers.
- Do not expose a separate prepare or warmup operation. The user starts the daemon and submits ordinary compilation jobs.
- Start request timing when the daemon receives a compilation job. Include buffer allocation, bind-group creation, capacity growth, compilation, and artifact writing performed for that request.
- On the first job, allocate the physical workspace slots needed for that job's capacity and create the bind groups that refer to those buffers. Keep the number of physical allocations and bind groups small by using the compiler graph's shared workspace slots.
- Reuse retained physical buffers and bind groups for sequential jobs whose required capacity fits the current workspace.
- When a later job needs more capacity, grow or replace the workspace and its bind groups during that timed request. Never create a pipeline after the daemon reports ready.
- Clear or overwrite only the regions needed by the next job, and dispatch using actual token, HIR, declaration, and family counts rather than workspace capacity.
- Allow an idle policy to release job workspaces and their bind groups. The next request then pays the measured cold-workspace creation cost; this is not a distinct user-visible phase.
- Add per-job counters for buffers, bind groups, pipelines, and other wgpu resources created after the daemon reports ready.
- Return a clear capacity error when an individual compilation unit exceeds the configured maximum.
- Report cold-workspace and retained-capacity request latency separately. Neither measurement may exclude work performed after job submission.

Exit condition: no compilation job creates a pipeline; the first job after startup, idle release, target change, or capacity growth may create the required workspace buffers and bind groups; after one ordinary job establishes sufficient x86 capacity, twenty subsequent x86 jobs create no buffers or bind groups; and after one ordinary job establishes sufficient Wasm capacity, twenty subsequent Wasm jobs create no buffers or bind groups.

## Phase 6: Complete bounded source-pack compilation

Make project size independent of GPU workspace size:

- Partition source packs into dependency-ready compilation units no larger than 10 MB.
- Do not split an individual source file or language unit at an unsafe semantic boundary.
- Compile one unit through frontend, type checking, lowering, and object/interface emission.
- Persist only the compact interface and target artifact needed by dependent units.
- Release all unit-local HIR, semantic metadata, and workspace contents before starting the next unit.
- Reuse the same workspace slots for every unit.
- Link emitted objects in bounded batches if total linker input would otherwise scale with project size.
- Produce an explicit diagnostic when one indivisible unit exceeds capacity.

Exit condition: a 1 GB multi-unit project uses approximately the same peak GPU workspace as a 10 MB project, aside from bounded interface and linking metadata.

## Phase 7: Enforce the memory gates

Extend telemetry to report, for every compilation:

- Current and peak tracked GPU bytes.
- Current and peak unique allocation identities.
- Physical workspace slots and their logical occupants.
- Snapshots after lexing, parsing, HIR materialization, type checking, semantic lowering, target lowering, and artifact emission.
- Source bytes, tokens, raw nodes, HIR nodes, declarations, calls, and type instances.
- Bytes per source byte, raw nodes per token, HIR nodes per token, and retained bytes per HIR node.

Run these acceptance workloads:

- 1 MB single-unit x86 and Wasm.
- 10 MB single-unit x86 and Wasm.
- 50 MB source pack.
- 100 MB source pack.
- 1 GB source pack.

Required results:

- No raw parse or bracket allocation remains live after compact HIR materialization.
- 1 MB compilation peaks at no more than 512 MB tracked GPU memory.
- 10 MB compilation peaks at no more than 6 GB.
- The 10 MB workload succeeds on an 8 GB physical GPU.
- Increasing total project size from 50 MB to 1 GB does not increase frontend workspace capacity.

If one of these fails, fix the phase responsible for the amplification before doing shader-level micro-optimization.

## Phase 8: Produce trustworthy performance results

Use generated workloads that resemble real projects:

- Most functions around three source lines.
- A distribution of medium functions.
- A small long tail reaching thousands of lines, with some functions approaching 10,000 lines.
- Multiple modules, calls, control flow, arrays, structures, methods, generics, strings, and runtime operations.
- Different generated programs for each seed with independently computed expected output.

Measure:

- At least 20 samples per point.
- Median and MAD.
- Separate daemon load, compile, artifact-write, and end-to-end wall time.
- x86 and Wasm.
- 1 MB, 10 MB, 50 MB, and 100 MB direct/project workloads.
- C, C++, Rust, Zig, Lanius, and compatible Pareas inputs.
- Debug information disabled consistently.
- Comparable optimization settings and artifact boundaries.
- Exact output or checksum validation for every measured program.

Initial performance targets:

- Preserve or improve the latest measured 1 MB mixed-workload x86 median of 210.947 ms.
- Bring Lanius closer to Pareas around 1 MB.
- Demonstrate increasing advantage over GCC as input grows.
- Establish whether the intended 10–100× GCC result appears around \(10^7\)–\(10^8\) bytes.

Only after these measurements should Nsight be used to optimize the shaders dominating warm compile time.

## Phase 9: Simplify and delete obsolete architecture

Once each replacement path is accepted:

- Delete legacy parser/type-checker/backend adapters.
- Replace repeated sort and scan plumbing with graph operations.
- Replace handwritten binding lists with reflected resource mappings.
- Collapse target-specific emission fragments into target-IR operations.
- Remove unused shader variants, redundant buffer wrappers, duplicate capacity arithmetic, and duplicated dispatch code.
- Move universally applicable GPU buffer creation and ownership logic out of the type checker and into the GPU layer.
- Require new graph operations to reduce caller-visible resource construction rather than merely wrap it.
- Track Rust and Slang line counts after every architectural deletion.

Exit condition: the total codebase is smaller than the current 422,838 Rust/Slang lines, the type checker no longer has its own parallel GPU infrastructure, and no accepted feature or target has been removed.

## Phase 10: Final public-readiness gate

Run one final reproducible acceptance package containing:

- All checked examples on declared targets.
- The PPM raytracer with exact artifact validation.
- Every required runtime facility.
- Randomly generated valid programs with x86/Wasm behavioral comparison.
- Invalid programs with stable diagnostics.
- 1 MB and 10 MB memory results.
- 50 MB, 100 MB, and 1 GB bounded-project results.
- Warm resource-creation counters.
- Compilation benchmark medians and MADs.
- Runtime comparisons.
- Machine, driver, compiler, generator, command, and source provenance.
