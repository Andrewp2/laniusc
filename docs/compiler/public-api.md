# Public Compiler API

This chapter documents the public compiler API boundary: the Rust call surface
that sits below the CLI and above lexer/parser/type-check/codegen internals.

It is the local analogue of rustc's driver/interface documentation. It explains
which functions are convenience entry points, which methods operate on an
explicit compiler instance, which APIs prepare persisted source-pack work, and
which APIs execute prepared work.

Use [Generated compiler reference](generated/reference.md) for the exact current
function list and signatures. This chapter owns the taxonomy and change rules,
not a copied inventory of every public function.

Use [Compiler orchestration](compiler-orchestration.md) for the host-side
sequencing inside `GpuCompiler`: resident locking, retained buffers, parser and
type-check boundaries, backend recording, descriptor execution, and timing.

## What This Chapter Owns

Use this chapter when changing:

- `CompileError`
- `GpuCompiler` construction or backend selection
- process-global compile/check convenience functions
- explicit `GpuCompiler` compile/check methods
- public source-root/source-pack loading helpers
- public planning APIs
- public execution/work-queue APIs
- descriptor-worker APIs
- benchmark/measurement APIs exposed from `compiler`
- public API evidence in generated reference or Rustdoc
- item-level documentation rules in [API docs and Rustdoc](api-docs.md)

Use [CLI and tooling surface](cli.md) for process invocation and output
rendering. Use [Source packs, artifacts, and work queues](source-packs.md) for
the persisted graph and store model. Use
[Compiler orchestration](compiler-orchestration.md) for live `GpuCompiler`
phase sequencing. Use [Diagnostics and status](diagnostics.md) for diagnostic
payloads and rendering contracts.

## Source Map

| Source | Responsibility |
| --- | --- |
| `compiler.rs` | Public re-export boundary, `CompileError`, benchmark result structs, module wiring. |
| `compiler/gpu_compiler.rs` | `GpuCompiler` owner, phase-driver construction, backend selection, resident pipeline lock. |
| `compiler/gpu_compiler/typecheck.rs` | Explicit `GpuCompiler` type-check methods. |
| `compiler/gpu_compiler/wasm_codegen.rs` | Explicit `GpuCompiler` WASM compile methods. |
| `compiler/gpu_compiler/x86_codegen.rs` | Explicit `GpuCompiler` x86_64 compile methods. |
| `compiler/gpu_compiler/descriptor_work_queue.rs` | Explicit `GpuCompiler` persisted descriptor-worker methods. |
| `compiler/gpu_compiler/benchmarks.rs` | Explicit benchmark/measurement methods. |
| `compiler/gpu_public_api.rs` | Process-global convenience functions and target-specific worker wrappers. |
| `compiler/public_planning_api.rs` and submodules | Public source loading, compact-manifest planning, metadata preparation, artifact-build preparation. |
| `compiler/public_execution_api.rs` and submodules | Public manifest/work-queue claiming, execution, ready-state, progress, sync/async workers. |
| `compiler/source_pack/*` | Persisted source-pack records, stores, validation, execution traits, and result types re-exported by public APIs. |

The public API layer should compose existing compiler boundaries. It should not
invent lexer, parser, type-checker, backend, or store semantics.

## Re-Export Shape

`compiler.rs` is the public face of the compiler module. It re-exports:

- artifact descriptor contracts
- source-pack model and persisted record types
- `GpuCompiler`
- public planning APIs
- public execution APIs
- process-global GPU public APIs
- diagnostics

That broad re-export is a convenience surface for callers. It is not permission
to place all new behavior in `compiler.rs`. Add new behavior in the module that
owns the boundary, then re-export it deliberately.

The generated reference lists public compiler functions and Rustdoc coverage.
If a new public function is not visible there, either the extractor missed an
expected pattern or the API was not actually placed on the public compiler
surface.

## Error Boundary

All public compile/check/planning/execution APIs return `CompileError` when they
can fail.

| Variant | Meaning |
| --- | --- |
| `Diagnostic` | Preferred user-facing error with stable code, message, labels, and notes. |
| `GpuFrontend` | Failure before syntax/type-check/codegen ownership is available, including input loading and setup. |
| `GpuSyntax` | Parser/syntax failure that has not been converted to a structured diagnostic. |
| `GpuTypeCheck` | Type-check failure that has not been converted to a structured diagnostic. |
| `GpuCodegen` | Backend failure that has not been converted to a structured diagnostic. |

`Diagnostic` should be the destination for user-source failures. String variants
are acceptable for infrastructure failures or gaps where the owning phase has
not yet exposed a structured diagnostic. Do not add a new string variant just to
avoid mapping a source-addressable error.

The CLI wraps `CompileError` into `CliError` and chooses a renderer. Public
compiler APIs should not print diagnostics, choose text versus JSON, or write
target bytes to stdout.

## Compiler Instance Boundary

`GpuCompiler` is the explicit compiler instance. It owns:

- one `GpuDevice`
- lexer driver
- parser driver
- precomputed parse tables
- resident type checker
- optional WASM generator
- optional x86 generator
- a resident pipeline lock

Construction paths:

| Constructor | Use |
| --- | --- |
| `GpuCompiler::new` | Create a compiler on the process-global GPU device with all backend families. |
| `GpuCompiler::new_with_device` | Reuse an existing `GpuDevice` and initialize all backend families. |
| `GpuCompiler::new_with_device_and_backends` | Reuse an existing `GpuDevice` and initialize only selected backend families. |
| `GpuCompiler::gpu` | Access the owned device for lower-level integration or tests. |

Frontend phases are always initialized. Disabled or failed backends are stored
as deferred errors so frontend-only operations can still run. This lets a caller
create a frontend-only compiler without paying backend pipeline construction
costs.

`GpuCompilerBackends` selects backend availability:

| Selector | WASM | x86 | Use |
| --- | --- | --- | --- |
| `all` | yes | yes | General explicit compiler. |
| `frontend_only` | no | no | Type-check/check-only work. |
| `wasm_only` | yes | no | WASM compile paths. |
| `x86_only` | no | yes | x86 compile paths. |

Do not add a fake backend fallback. If a backend is disabled or failed to
initialize, the backend compile method should report that backend error when
the caller asks for that target.

## Resident Pipeline Lock

Public `GpuCompiler` methods serialize resident phase use through the resident
pipeline lock. This is required because lexer, parser, type-check, and backend
drivers reuse resident buffers and bind groups across operations.

The lock protects the compiler instance, not global source semantics. A caller
that needs concurrent compile operations should use separate compiler instances
or an API that prepares persisted work for external workers. Do not bypass the
lock to make one new method look asynchronous; doing so risks mixing resident
buffer state between operations.

## Process-Global Convenience APIs

`gpu_public_api.rs` exposes convenience functions for callers that do not want
to own a `GpuCompiler`.

The process-global families are:

| Family | Examples | Compiler used |
| --- | --- | --- |
| Single-source type check | `type_check_source_with_gpu`, `type_check_source_with_gpu_from_path` | frontend-only global compiler |
| Source-pack type check | `type_check_source_pack_with_gpu`, `type_check_source_pack_manifest_with_gpu`, entry/root variants | frontend-only global compiler |
| Single-source WASM | `compile_source_to_wasm_with_gpu_codegen`, path variant | WASM global compiler |
| Source-pack WASM | source-pack manifest and entry/root variants | WASM global compiler |
| Single-source x86 | `compile_source_to_x86_64_with_gpu_codegen`, path variant | x86 global compiler |
| Source-pack x86 | source-pack manifest and entry/root variants | x86 global compiler |
| Prepared descriptor workers | `run_prepared_descriptor_worker_for_target`, `step_prepared_descriptor_worker_for_target` | target-specific global compiler |
| Path/dependency stream workers | `run_*_worker_to_wasm`, `step_*_worker_to_x86_64`, etc. | target-specific global compiler |

These helpers are intentionally target-specific at the function name level. A
caller should not pass a target string and rely on hidden inference when a
concrete function can make the backend choice obvious.

## Explicit Compiler Methods

Use explicit `GpuCompiler` methods when the caller needs to:

- control the GPU device
- reuse one initialized compiler across many operations
- choose backend initialization upfront
- avoid process-global state in tests
- interleave compile work with lower-level compiler measurements

Core method families:

| Family | Examples | Boundary |
| --- | --- | --- |
| Type check | `type_check_source`, `type_check_source_from_path`, `type_check_source_pack`, `type_check_source_pack_manifest` | Frontend through type checking; no target bytes. |
| WASM compile | `compile_source_to_wasm`, `compile_source_to_wasm_from_path`, source-pack variants | Frontend plus WASM backend. |
| x86 compile | `compile_source_to_x86_64`, `compile_source_to_x86_64_from_path`, source-pack variants | Frontend plus x86 backend. |
| Descriptor work queue | `step_descriptor_work_queue`, `run_descriptor_work_queue`, path/dependency stream worker methods | Prepared source-pack work executed through target-specific backend handles. |
| Benchmarks | `benchmark_lex_source`, `benchmark_parse_source`, `benchmark_live_capacity_estimate` | Measurement-only entry points used by tools and tests. |

Do not add a process-global helper until the explicit compiler method exists or
the operation is purely planning/execution work that does not need a compiler
instance. The explicit method is the easier boundary to test.

## Source Preparation

Single-source public helpers call source-preparation utilities before recording
GPU work. Path variants read source with path-labeled errors, while string
variants prepare the caller-provided source text.

Source-root helpers first convert an entry file plus roots into a source pack:

| Helper shape | Meaning |
| --- | --- |
| `*_with_stdlib` | Entry file plus standard-library root. |
| `*_with_source_root` | Entry file plus one user source root. |
| `*_with_source_roots` | Entry file plus explicit user and optional standard-library roots. |
| `*_from_path` | One isolated source file read from disk. |

The helpers should only load sources and preserve provenance. Semantic
module/import meaning still belongs to parser/type-check records described in
[Module and source-root resolution](module-resolution.md).
The stdlib-specific helpers load ordinary source files from a stdlib root; see
[Source-level standard library](standard-library.md) for the current stdlib
contract and runtime-service boundary.

## In-Memory Source-Pack Bound

In-memory source-pack compile/check helpers validate that the pack fits the
default bounded codegen unit. The validation rejects:

- too many source files
- a source file larger than the bounded source-byte limit
- total source bytes larger than the bounded source-byte limit
- byte-count overflow

The error tells callers to use persisted source-pack descriptor work queues for
larger codebases. That is an API contract, not a performance hint: in-memory
helpers are for bounded packs that can be compiled as one unit. See
[Capacity and limits](capacity-and-limits.md) for the distinction between this
public API bound and internal storage or dispatch capacities.

Do not relax the in-memory bound by silently switching to persisted mode. The
caller must choose persisted preparation because it creates files, progress
records, claims, and resumability semantics.

## Public Planning APIs

`public_planning_api` contains APIs that plan or prepare work before execution.
They should not execute GPU compiler phases unless the function name explicitly
states that it executes a store build or worker.

Main families:

| Family | Representative functions | Boundary |
| --- | --- | --- |
| Input loading | `load_entry_with_*`, `load_entry_path_manifest_with_*`, `load_explicit_source_pack_*_from_paths` | Convert paths/roots into source-pack input shapes. |
| Compact manifests | `plan_*_compact_manifest*` | Build compact planning records from path/dependency streams. |
| Direct plans | `plan_pack_frontend_from_paths`, `plan_pack_artifacts_from_paths`, library variants | Return in-memory plans from path lists. |
| Metadata preparation | `prepare_*_metadata*`, `prepare_metadata_chunk_for_target`, `resume_metadata_chunk_for_target` | Persist source/library metadata before artifact planning. |
| Artifact preparation | `prepare_artifact_build_chunk`, `prepare_artifact_build`, stage-specific `prepare_*_chunk` helpers | Advance or finish persisted build preparation. |
| Filesystem build wrappers | `prepare_pack_paths*`, `prepare_ordered_library_paths*`, `prepare_dependency_streams*` | Compose path inputs with persisted artifact preparation. |

Planning APIs should return records that describe what was planned or prepared.
They should not hide store validation failures as cache misses.

## Public Execution APIs

`public_execution_api` contains APIs that claim, execute, complete, and report
prepared work.

Main families:

| Family | Representative functions | Boundary |
| --- | --- | --- |
| Manifest progress | `artifact_manifest_build_state*`, `artifact_manifest_progress_*` | Inspect persisted artifact manifest progress. |
| Manifest claims | `claim_ready_artifact_manifest_batch*` | Reserve a ready manifest batch for a worker. |
| Manifest execution | `execute_artifact_manifest_build_for_target`, `execute_claimed_*`, `run_artifact_manifest_worker*` | Execute prepared artifact manifest batches. |
| Ready-state queries | `artifact_manifest_ready_batch_indices*` | Inspect ready batches without executing them. |
| Work-queue claims | `claim_ready_work_queue_item`, `complete_claimed_work_queue_item` | Reserve and complete claimable work items. |
| Work-queue execution | `execute_claimed_*_work_queue_item*`, `step_work_queue*`, `run_work_queue*` | Execute prepared work-queue items. |
| Progress snapshots | `work_queue_progress_snapshot*` | Inspect work-queue readiness and completion state. |

Execution APIs mutate progress and claim state. A caller that only wants to
inspect readiness should use ready/progress APIs, not a worker step with a zero
limit.

## Descriptor Workers

Descriptor workers are the public bridge between persisted source-pack planning
and GPU backend execution. They consume prepared descriptor artifacts and run
target-specific compiler work.

There are two layers:

| Layer | Examples | Use |
| --- | --- | --- |
| Explicit compiler methods | `GpuCompiler::step_descriptor_work_queue`, `GpuCompiler::run_descriptor_work_queue` | Caller owns compiler instance and target. |
| Process-global wrappers | `step_prepared_descriptor_worker_for_target`, target-specific stream workers | Caller wants global compiler reuse and a compact API. |

Descriptor workers require a concrete target. `Generic` is rejected because GPU
descriptor execution needs a backend. If a new target is added, update backend
selection, descriptor-worker target routing, source-pack target identity, and
the generated reference.

## Executor Trait Boundary

Many planning/execution APIs are generic over executor traits rather than over
`GpuCompiler` directly.

That split lets the same persisted graph be executed by:

- GPU-backed compiler handles
- path-producing descriptor executors
- sync artifact executors
- async artifact executors
- test executors that assert claim/progress behavior

Executor traits own artifact production for one prepared item or batch. They do
not own source-pack scheduling, claim validation, target path naming, or progress
mutation. Those remain in public execution APIs and store helpers.

When adding a new executor path, keep the trait boundary narrow: the executor
should receive already validated inputs and return the artifact result, not
decide which work is ready.

## Benchmark APIs

Benchmark entry points are public because tools need phase measurements without
copying compiler internals:

- `benchmark_lex_source`
- `benchmark_parse_source`
- `benchmark_live_capacity_estimate`

Benchmark results expose counts and capacity estimates, not phase-owned buffers.
They should stay measurement-only. Do not route user-facing compile behavior
through benchmark APIs.

## Adding A Public API

Use this checklist before adding or changing a public compiler API:

1. Identify the owning family: global convenience, explicit compiler method,
   input loading, planning, execution, descriptor worker, or benchmark.
2. Add behavior at the narrow owning boundary before adding convenience
   wrappers.
3. Return `CompileError`; prefer `Diagnostic` for source-addressable failures.
4. Preserve target identity explicitly instead of inferring from nearby strings.
5. Keep in-memory helpers bounded; route large builds through persisted
   preparation and workers.
6. Do not add compatibility aliases unless another human maintainer needs them.
7. Add Rustdoc on every public item.
8. Regenerate or check the generated compiler reference.
9. Add focused tests for the owning API family.
10. Update CLI docs only if the CLI exposes the new API.

The important review question is: can a caller tell whether this function only
plans, mutates persisted progress, executes compiler work, or writes target
bytes? If not, the API name or placement is wrong.

## Failure Modes

| Symptom | Likely owner |
| --- | --- |
| process-global helper initializes slowly | selected global compiler initialized more backends than needed |
| frontend-only check reports backend initialization error | backend error escaped before target use |
| source-pack helper rejects normal-sized file list | in-memory codegen-unit limit or wrong helper family |
| persisted worker sees `Generic` target | descriptor execution called without a concrete backend target |
| repeated worker claims same item | work-queue claim/progress mutation |
| ready query changes progress | execution API used instead of ready/progress API |
| CLI renders compiler error incorrectly | CLI renderer or `CliError` wrapping, not public compiler API |
| source label missing from syntax/type error | phase diagnostic mapping, not public API routing |

Start debugging from the API family. Planning, execution, and target-codegen
failures often have similar `CompileError` wrappers but different owners.

## Test Evidence

| Change | Evidence |
| --- | --- |
| New global convenience helper | focused test or call path proving it selects the intended global compiler/backend. |
| New explicit `GpuCompiler` method | focused compile/check/worker test on an explicit compiler when feasible. |
| New source-root loader | small temporary directory test proving source provenance and validation. |
| Planning API change | source-pack planning test over the smallest path/library graph. |
| Execution API change | claim/execute/complete/progress test with a minimal prepared graph or test executor. |
| Descriptor worker change | descriptor worker test for the concrete target. |
| Error mapping change | diagnostic or `CompileError` assertion at the API boundary. |
| Public item addition | Rustdoc coverage and generated-reference check. |
| Docs-only edit | generated-reference freshness, local Markdown link check, ASCII check, trailing whitespace check. |

Do not use a broad CLI integration test as the only proof for a public compiler
API change. The CLI is one caller of this layer, not the owner of its contracts.

## Generated Evidence

The generated compiler reference currently records:

- public compiler function names
- visibility
- source file and line
- compact signatures
- Rustdoc-visible item count
- undocumented public compiler function count
- undocumented Rustdoc-visible item count

Run:

```bash
tools/compiler_inventory.py --output docs/compiler/generated/reference.md
tools/compiler_inventory.py --check docs/compiler/generated/reference.md
```

A public API change is not done until the generated reference is fresh and any
new public item has Rustdoc. If the extractor misses a new API pattern, update
the extractor rather than accepting a stale inventory.
