# Source Packs, Artifacts, And Work Queues

Source-pack support is the compiler boundary that turns a set of source files
into a library-aware build graph with persisted metadata, artifact manifests,
and resumable workers. It exists so larger builds can be prepared once, resumed
after interruption, and executed by workers without loading every source file or
every dependency edge into memory at the same time.

Use this guide for the compiler-author model: ownership, data flow, persisted
contracts, and change rules. Use `generated/reference.md` for the exact current
operation list, public structs, large persisted records, and Rustdoc coverage.
Use [Module and source-root resolution](module-resolution.md) for the separate
question of how loaded source files become semantic modules. Use
[Public compiler API](public-api.md) for the public planning/execution function
families that expose this model.

## What This Chapter Owns

The source-pack layer owns build topology and persisted execution state. It does
not own syntax, type identity, module identity, method lookup, backend lowering,
or final native linking semantics.

| Concern | Source-pack responsibility | Not source-pack responsibility |
| --- | --- | --- |
| Input grouping | Validate libraries, source counts, paths, and library dependency edges. | Decide what an import means inside a source file. |
| Build graph | Plan frontend, codegen, and link jobs from source/library topology. | Parse source text or infer semantic types. |
| Persistence | Store versioned metadata, schedules, artifact refs, shards, progress, and locks. | Hide corrupt stores behind fallback behavior. |
| Artifact identity | Assign stable target-qualified artifact keys and file paths. | Decide the binary encoding of a real backend artifact. |
| Work execution | Claim, execute, complete, and resume bounded work items. | Invent work outside the prepared graph. |
| Validation | Fail when persisted records disagree across stages. | Treat mismatched pages as harmless cache misses. |

The guiding rule is that in-memory and persisted builds should differ in source
loading and storage, not in the logical graph they compile. If a feature changes
the graph, the source-pack planner should expose that change consistently across
the in-memory and persisted paths.

## Source Tree

Most of the implementation is under
`crates/laniusc-compiler/src/compiler/source_pack`.

| Area | Files | Responsibility |
| --- | --- | --- |
| Public re-export surface | `source_pack/mod.rs` | Re-export the persisted contract types used by public planning and execution APIs. |
| Input shapes | `inputs.rs` | In-memory packs, path manifests, path streams, and validation helpers. |
| Persisted records | `records.rs`, `artifact_model.rs`, `build_state.rs`, `prepare_types.rs` | Versioned serde records, prepare receipts, progress snapshots, claims, and result types. |
| Package metadata | `package_manifest.rs`, `package_lock.rs`, `metadata.rs` | Package/source-root metadata and lockfile records used before planning. |
| Library planning | `library_pages.rs`, `schedule.rs` | Library partitions, source-file pages, build-unit pages, job schedules, and locators. |
| Batches and shards | `batches/` | Job batches, link batches, reverse dependents, artifact shards, compact manifests, and work-queue pages. |
| Link planning | `link_plan/` | Hierarchical link leaf/reduce groups and executable link pages. |
| Filesystem store | `store.rs`, `store/` | Path construction, load/store helpers, artifact I/O, progress files, manifests, and locks. |
| Execution helpers | `execution/`, `executors.rs` | In-memory/path/artifact execution traits, lookup helpers, sync/async shard execution, and link execution. |
| Validation | `validation/` | Cross-page and cross-index checks for schedules, batches, link plans, source files, and work queues. |
| Public API wrappers | `compiler/public_planning_api*`, `compiler/public_execution_api*` | Stable call surfaces for CLI, GPU public APIs, and tests. |

`codegen/unit` is also part of the source-pack mental model. It defines the
unit/job/batch/manifest structures that the source-pack persistence layer later
stores and resumes. The source-pack module should not duplicate that planning
logic by hand; it should convert path and package inputs into the codegen unit
model, then persist the resulting graph.

See [Public compiler API](public-api.md) for the caller-facing planning,
execution, descriptor-worker, and process-global wrappers around these records.

## Execution Modes

There are two major execution modes.

| Mode | Main types | Use case |
| --- | --- | --- |
| In-memory source pack | `ExplicitSourcePack`, `ExplicitSourceLibrary`, `BuildExecutor` | Small checks and compile paths that already own source strings. |
| Persisted artifact build | `ExplicitSourcePackPathManifest`, `FilesystemArtifactStore`, `PreparedBuild`, work queues | Larger builds, resumable preparation/execution, and worker processes. |

The in-memory path validates library topology, plans units and jobs, topologically
orders dependencies, and calls frontend/backend compiler paths against source
slices.

The persisted path records source metadata and graph pages under an artifact
root. Preparation and execution can then resume without rescanning all files,
replanning all edges, or rebuilding unrelated artifacts.

## Public API Families

The public APIs are split by the boundary they own. When adding a feature, pick
the boundary first; avoid adding a new convenience wrapper until the owning
stage has the behavior.

| API family | Representative entry points | Boundary |
| --- | --- | --- |
| Input loading | `load_entry_with_source_root*`, `load_entry_path_manifest_with_source_root*`, `load_explicit_source_pack_*_from_paths` | Convert CLI/package/source-root inputs into in-memory packs or path manifests. |
| Package metadata | `PackageManifest`, `PackageLockfile`, package lock helpers | Resolve package roots, validate replay evidence, and convert package inputs into source-pack loading shapes. |
| In-memory planning | `ExplicitSourcePack::{codegen_unit_plan, frontend_unit_plan, job_plan, job_schedule, build_plan}` | Plan source strings without persistence. |
| Path planning | `plan_pack_frontend_from_paths`, `plan_pack_artifacts_from_paths`, `plan_libraries_*_from_paths` | Plan path-backed inputs when callers already have path vectors. |
| Stream planning | `plan_*_streams_compact_manifest*` | Plan compact manifests from streamed paths/dependencies. |
| Metadata preparation | `prepare_*_metadata*`, `prepare_metadata_chunk_for_target`, `resume_metadata_chunk_for_target` | Write library/source metadata before artifact planning. |
| Artifact preparation | `prepare_artifact_build_chunk`, `prepare_artifact_build`, `prepare_*_chunk` stage helpers | Advance or finish the persisted preparation state machine. |
| Prepared build handle | `PreparedBuild::{bounded_summary, work_queue_progress_snapshot, submit_*}` | Reopen a prepared artifact root and submit worker steps. |
| Manifest execution | `execute_artifact_manifest_build_for_target` and manifest worker helpers | Execute compact/manifest-backed artifact batches. |
| Work-queue execution | `claim_ready_work_queue_item`, `complete_claimed_work_queue_item`, `step_work_queue`, `run_work_queue`, path and async variants | Claim, execute, complete, and summarize prepared work items. |
| GPU descriptor workers | `GpuCompiler::{step_descriptor_work_queue, run_descriptor_work_queue}` and GPU public API wrappers | Exercise persisted planning/execution using descriptor artifacts. |

This split is intentional. Source loading, graph preparation, artifact execution,
and queue mutation have different invariants. A helper may compose them, but the
underlying operation should remain testable at the owning boundary.

Package manifests and lockfiles are documented in
[Package metadata and lockfiles](package-metadata.md). They select and validate
source roots before this source-pack layer plans persisted metadata, artifacts,
and work queues.

## Input Identity And Library Topology

`ExplicitSourcePack` is the in-memory input shape. It owns source strings plus a
library id for each source. It accepts optional source paths only as provenance
or diagnostic metadata; compilation still uses the strings stored in the pack.

`ExplicitSourcePackPathManifest` is the persisted-planning input shape. It owns
file metadata instead of source strings:

- library id
- path
- byte length
- optional modified time
- optional line count
- library dependency edges

`line_count == None` means planning did not scan file contents while collecting
metadata. That is not an unknown source file; it is an explicit choice to defer
that part of the source read.

The input API has three caller shapes:

| Shape | Types | Contract |
| --- | --- | --- |
| In-memory libraries | `ExplicitSourceLibrary`, `ExplicitSourcePack` | Caller provides source strings. The pack validates source/library counts and dependency topology. |
| Path vectors | `ExplicitSourceLibraryPaths`, `ExplicitSourcePackPathManifest` | Caller provides materialized path lists. Planning records file metadata and defers source loading. |
| Path streams | `ExplicitSourceLibraryPathStream`, `ExplicitSourceLibraryPathDependencyStream` | Caller can stream paths and dependency ids while still supplying counts for validation and scheduling. |

All library input shapes enforce the same topology rules:

- the source list is nonempty where a pack is being built
- there is one library id per source
- library ids referenced by dependencies exist
- libraries cannot depend on themselves
- duplicate dependency edges are rejected
- the library graph must be acyclic and topologically orderable

Do not move semantic import resolution into this layer. The dependency graph
here is package/library topology. Source-file imports and module paths are
resolved by the parser/type-checker path described in
[Module and source-root resolution](module-resolution.md).

## Target And Artifact Identity

`SourcePackArtifactTarget` namespaces persisted artifacts and store paths. The
current targets are:

| Target | Meaning |
| --- | --- |
| `Generic` | Target-independent planning or frontend/type-check artifacts. |
| `Wasm` | WASM backend artifact namespace. |
| `X86_64` | x86_64 backend artifact namespace. |

`SourcePackArtifactTarget::key_prefix()` returns the optional prefix used in
artifact keys. The filesystem store applies the same target identity to paths:
generic stores use the base file name, while target-specific stores insert the
target before the `.json` suffix. For example, a generic build-state path uses
`source-pack-state.json`; a WASM build-state path uses
`source-pack-state.wasm.json`.

The target is part of the persisted contract. Every page/index that carries a
target must match the target requested by the caller. If a store contains a WASM
manifest and the caller asks for x86_64, the right behavior is an error, not a
fallback to a nearby file.

Artifact keys are also logical identities, not just filenames. Worker code
should ask the store or lookup helpers to resolve keys. Do not construct artifact
paths by concatenating strings in an executor; that bypasses the target and
manifest contracts.

## Planning And Job Model

Source-pack planning is built around `SourcePackJob`.

| Job phase | Meaning | Main output |
| --- | --- | --- |
| `LibraryFrontend` | Parse/type-check a library interface slice. | Library-interface artifact. |
| `Codegen` | Produce backend object metadata for a source/codegen slice. | Codegen-object artifact. |
| `Link` | Combine interfaces and objects for the final build. | Linked-output artifact, or hierarchical partial/final link artifacts in the persisted path. |

`codegen::unit` builds the core graph:

- frontend units
- codegen units
- source-pack jobs
- job dependency edges
- topological schedules and waves
- job batches
- artifact references
- compact build manifests
- link interface/object batch plans

Jobs carry source ranges, library ids, dependency job indices or ranges,
byte/file/line counts, and phase. Execution waves are topological layers. Batches
group ready jobs within limits so a worker can claim bounded work without
loading the full graph.

The source-pack persistence layer then materializes the graph as pages and
indexes. It should preserve the planner's logical job indices. Direct vector
positions can be used as fast paths only when validation proves they still match
the recorded indices.

## Persisted Preparation Pipeline

Persisted preparation is a bounded state machine. The main entry point,
`prepare_artifact_build_chunk`, writes at most a clamped number of new items and
returns the current `BuildPrepareStage`. `prepare_artifact_build` loops over the
same chunk operation until the full-prepare step limit is reached.

The stage order is:

| Stage | Main output | Next durable boundary |
| --- | --- | --- |
| `LibrarySchedule` | Library partitions, source-file pages, build-unit pages, schedule pages, job locators. | `source-pack-library-schedule*.json` and locator indexes exist. |
| `ArtifactRefs` | Artifact-reference pages. | Artifact ref index exists. |
| `JobBatches` | Executable job-batch pages and job locator pages. | Job-batch page index exists. |
| `LinkBatches` | Link interface/object batch pages. | Link-batch page index exists. |
| `JobBatchDependents` | Reverse batch dependency pages. | Dependents progress reaches the final batch. |
| `ArtifactShards` | Artifact execution shards, progress shards, progress directory pages. | Artifact shard index exists. |
| `HierarchicalLinkLeafGroups` | Leaf groups for partition-local link fan-in. | Link-plan progress reaches the final partition. |
| `HierarchicalLinkPlanReduceGroups` | Reduce groups above leaf outputs. | Hierarchical link plan index exists. |
| `HierarchicalLinkExecution` | Executable link pages and sidecar input pages. | Hierarchical link execution index exists. |
| `WorkQueuePages` | Claimable work-item pages. | Work-queue index exists. |
| `WorkQueueProgress` | Initial progress pages and directory summaries. | Work-queue progress index exists. |
| `BuildManifests` | Compact path build manifest and artifact manifest. | Manifest files exist. |
| `BuildState` | Initial mutable build state. | Build-state file exists. |
| `Complete` | No new preparation work. | `PrepareResult` can be reconstructed from indexes. |

Preparation is resumable because each stage checks for its own durable outputs
before writing new data. A later stage must not assume earlier in-memory data is
still available; it should reload the needed indexes/pages from the store and
validate them.

The final `build_state_path_for_target` is the prepared/buildable boundary. If
that file exists, `prepare_artifact_build_chunk` reconstructs a `PrepareResult`
from stored indexes instead of rewriting the graph. If the build-state file is
missing, preparation continues from the first missing durable stage.

## Prepare Results And Handles

There are two families of preparation result types:

| Type family | Meaning |
| --- | --- |
| `*PrepareStepResult` | One bounded stage step: stage, next stage, completion flag, new item count, and cursor-like progress fields. |
| `PrepareResult` | Final receipt for the files/counts written under an artifact root. |
| `PreparedBuild` | Reopenable handle for an artifact root and target after preparation. |
| `PreparedBuildSummary` | Cross-index summary plus current work-queue progress. |

`PrepareResult` is intentionally broad. It records paths and counts for library
metadata, schedules, artifacts, link execution, work queues, progress, and build
state so a caller can report a prepared build without reopening every page.

`PreparedBuild::bounded_summary` is stronger than a display helper. It reloads
multiple indexes and checks that partition counts, job counts, batch counts,
artifact counts, source totals, and progress totals still agree. Treat summary
loading failures as store-contract failures, not as optional UI errors.

## Store And Path Contract

`FilesystemArtifactStore` owns the artifact root and all path construction. It
is responsible for:

- storing and loading manifests, indexes, pages, shards, and progress files
- checking artifact existence
- acquiring build-state locks during preparation and mutation
- updating ready frontiers after completed work
- preserving target-specific filenames

Path helpers live in `source_pack/store/paths.rs`. They take a
`SourcePackArtifactTarget` because multiple target stores can share one artifact
root. Compiler code should go through store helpers rather than constructing
paths by hand.

The filename conventions are part of the resumability contract:

- root indexes have stable names such as `source-pack-work-queue.json`
- target-specific roots insert the target before `.json`
- page files include zero-padded indices so listing and debugging are stable
- progress files are separate from data pages so preparation can resume without
  rewriting completed records
- lock files are derived from the build-state path and acquired only through
  store/build-state helpers

If a new persisted record needs a path, add a store helper and use it everywhere.
Manual path construction creates hidden compatibility assumptions and makes it
easy for one target namespace to read another target's records.

## Versioned Records And Defaults

Persisted records carry version constants. Validation should check those
versions at the first boundary that reads the record for behavior.

Many records also use `#[serde(default)]`. That is a read compatibility tool at
the persistence boundary. It does not mean new writers may omit the field, and
it does not make the field optional in the logical contract. A defaulted field
still needs a clear invariant:

- why old stores may be missing it
- what value old records should mean
- which writer now populates it
- which validator checks the populated value

Do not add compatibility defaults just because serde makes it easy. Compatibility
is justified only when another human being needs an existing stored artifact or
workflow to continue working. Otherwise, extra defaults make the record harder
to reason about and suggest a historical promise that does not exist.

## Library Metadata And Schedule Pages

Library metadata converts a path manifest into pages that later stages can load
one bounded unit at a time.

The pipeline is:

1. partition metadata records library ids, dependency ids, source ranges, and
   source totals
2. compact build-unit pages summarize frontend and codegen unit counts
3. source-file record pages retain path metadata
4. frontend-unit and codegen-unit pages expand the compact plan
5. schedule pages assign global source-pack job indices
6. dependency pages record library/job dependency inputs
7. locator pages map libraries and jobs back to owning partition pages

The compact pages let preparation validate totals before writing expanded unit
pages. The expanded pages let later stages and workers load a bounded piece of
the graph. Schedule preparation is the boundary where library-local unit indexes
become global job indexes.

When changing library metadata, update validation with the writer. The common
failure mode is writing a count in an index while forgetting to make the
corresponding page range loadable by later stages.

## Artifact Refs, Batches, And Shards

Artifact references describe the produced and consumed artifacts for each
planned job. Job batches group executable jobs. Link batches describe
interface/object inputs for link jobs. Shards make those records loadable by
workers without opening the full compact manifest.

The persisted artifact path has two related shapes:

| Shape | Use |
| --- | --- |
| Compact manifest | Count-only durable summary stored at the artifact root. |
| Execution records and shards | Worker-readable batches, jobs, source-file records, artifact refs, and progress pages. |

`compact_artifact_manifest` deliberately removes inline execution records. A
worker that needs inline rows must call `ensure_manifest_execution_records` or
use the persisted execution-shard lookup path. If a compact manifest says there
are 100 jobs and carries zero inline job rows, that is not a partial success; it
means the caller is using the wrong execution path.

Shard preparation writes:

- normal job-batch execution shards
- link-input shard indexes for interface/object batches
- batch-to-shard locator pages
- build progress shards
- build progress directory pages
- build progress directory index pages

The compact artifact-shard index and link-input shard index should be written
only after every shard and progress directory page has been validated and stored.

## Artifact Lookup

Artifact execution uses lookup helpers as the boundary between compact persisted
records and worker code. The helpers resolve:

- execution shards, which embed the batches, jobs, source files, and artifact
  references needed for bounded execution
- compact manifests, which store global batches, job artifact manifests, and
  artifact references by index
- hierarchical link pages and sidecar input pages

Worker code should not interpret these layouts by hand. Lookup helpers provide
the contract checks:

- referenced batches, jobs, source ranges, and artifacts exist
- source-file metadata still matches the path manifest
- interface input ranges expand to library-interface artifacts
- link jobs have exactly one linked-output artifact when a batch reports a
  linked result
- work-queue item kind matches the referenced artifact job or link page

The direct-index fast path is only an optimization. Helpers fall back to looking
for records by their recorded logical index, so correctness depends on the
recorded index rather than the current vector slot.

## Hierarchical Link Planning

Hierarchical link planning caps link fan-in by splitting link work into groups:

- leaf groups consume library-interface and codegen-object artifacts from one
  partition
- reduce groups consume outputs from earlier link groups
- the final group produces the linked output artifact key recorded in the
  artifact-reference index

Execution pages are derived from the link plan plus artifact-reference pages.
Large interface, object, or partial-link input lists spill into sidecar pages so
the main execution page stays bounded.

Do not treat hierarchical link records as final backend semantics. The source
pack layer decides which inputs a link group receives and which output key it
writes. The executor decides what the artifact means.

Completed link execution is valid only when the final execution page and its
sidecars still match the current link plan and artifact-reference index.

## Work Queue Pages And Leases

The work-queue path represents artifact jobs and hierarchical link groups as one
claimable dependency graph. It is the path used by descriptor workers and by the
GPU source-pack executor.

Work item kinds are:

| Kind | Execution path |
| --- | --- |
| `LibraryFrontend` | Singleton artifact batch producing a library-interface artifact. |
| `Codegen` | Singleton artifact batch producing a codegen-object artifact. |
| `LinkLeaf` | Hierarchical link execution page for a leaf group. |
| `LinkReduce` | Hierarchical link execution page for a reduce group. |

Work-queue pages record:

- item index and job index
- item kind
- dependencies and dependents, inline or paged
- source/library partition inputs
- artifact batch index for frontend/codegen items
- hierarchical link group index for link items
- input frontend/codegen/link group counts
- source byte/file/line totals

Progress pages record completed, ready, claimed, and remaining dependency state.
Directory pages summarize progress pages so workers can find ready or expiring
work without scanning every progress page.

Claims are leases. A claim records the item index, worker id, and optional lease
expiry. Claims without an expiry do not expire through the normal expiry
predicate. Expired claims are pruned during state mutation and ready scans.

Completion is not just "mark this item done". It must:

1. verify the item is already complete or claimed by the worker completing it
2. release non-final output artifacts when the existing execution path expects
   release
3. mark the item completed on the owning progress page
4. decrement remaining dependency counts on dependents
5. record newly ready dependents
6. refresh progress page summaries, directory pages, and the root progress index
7. return a bounded progress snapshot

Artifact-backed work items have one extra invariant: a frontend/codegen work
item maps to a singleton artifact batch. Claiming such an item through
`claim_ready_artifact_work_queue_item` mirrors the claim onto the backing
artifact batch. The generic `execute_claimed_work_queue_item` path also mirrors
that batch claim before executing if the item was not already completed. This
keeps the work-queue progress state and artifact-batch progress state from
disagreeing about who owns the work.

Do not add an executor path that completes a frontend/codegen work item without
respecting the singleton batch mapping. That would make artifact-manifest
progress and work-queue progress diverge.

## Build State And Progress

Persisted execution uses two mutable progress systems:

| State | Scope | Role |
| --- | --- | --- |
| `SourcePackBuildState` | Whole artifact-manifest build | Small locked summary: completed count, claimed count, linked output key. |
| `SourcePackBuildProgressShard` | Artifact shard | Ready, claimed, and completed batch indices for one shard. |
| `SourcePackBuildProgressDirectory*` | Ranges of artifact shards | Lets artifact workers find ready or expiring batches. |
| `SourcePackWorkQueueProgressPage` | Range of work items | Completed/ready/claimed item state plus remaining dependency counters. |
| `SourcePackWorkQueueProgressDirectory*` | Ranges of work-queue progress pages | Lets work-queue workers find ready or expiring items. |
| `SourcePackWorkQueueProgressIndex` | Whole work queue | Root progress summary and first ready item hints. |

These are persisted state, not advisory caches. A stale ready count or first
ready index can make a worker miss work, claim the wrong work, or spin. Mutating
progress should always refresh the owning page, directory summaries, and root
index through the existing helpers.

Worker and preparation APIs clamp caller-provided limits to default bounded
values. This keeps "run until idle" helpers from turning into unbounded
directory scans or huge progress rewrites. See
[Capacity and limits](capacity-and-limits.md) for the shared policy on
chunking bounds versus user-visible limits.

## Artifact Execution Interfaces

Executor traits describe how much source and dependency data an execution path
wants to hold at once.

| Trait | Use |
| --- | --- |
| `BuildExecutor` | In-memory source strings and in-memory artifacts. |
| `PathBuildExecutor` | Path metadata inputs with in-memory artifacts. |
| `PathHandleBuildExecutor` | Path metadata with cloneable handles and release hooks. |
| `PathHandleBatchedLinkBuildExecutor` | Linkers that receive interface/object batches instead of one large input list. |
| `ArtifactBuildExecutor` | Persisted artifacts loaded/stored by manifest key. |
| `PagedArtifactBuildExecutor` | Frontend/codegen execution with dependency batches. |
| `HierarchicalLinkExecutor` | Leaf/reduce/final hierarchical link execution. |
| `PagedHierarchicalLinkExecutor` | Synchronous executor supporting both paged artifacts and hierarchical links. |
| `AsyncPagedHierarchicalLinkExecutor` | Async version used by GPU/filesystem/remote-like workers. |

Choose the narrowest trait that matches the data boundary. For a persisted work
queue, prefer paged traits so a large dependency fan-in does not become a single
large allocation or source read.

The store traits are separate from executor traits. Executors build artifacts;
stores load, store, and release artifacts by manifest key. Keep that separation
when adding a backend so execution policy does not leak into path construction
or progress mutation.

## GPU Descriptor Executor

`GpuSourcePackArtifactExecutor` is the current GPU executor for persisted
descriptor artifacts. It implements async paged artifact and hierarchical link
executor traits.

Current behavior:

- library-interface jobs read source files and call
  `GpuCompiler::type_check_source_pack`
- codegen-object jobs validate that the owning interface artifact exists and
  write a descriptor artifact
- link jobs validate dependency artifacts and write descriptor artifacts
- hierarchical link groups count interface/object/partial-link inputs and write
  descriptor artifacts

These descriptor artifacts are contract records, not final native linked code.
The executor still matters because it exercises persisted planning, claiming,
dependency validation, link grouping, artifact-writing, and progress-update
contracts used by future real backend execution. See
[Artifact descriptors and output contracts](artifact-descriptors.md) for the
descriptor JSON schema, runtime-service rules, target-byte policy, and CLI
`--emit-contract` boundary.

## CLI Relationship

The CLI source-pack commands should remain thin wrappers around the planning and
execution APIs:

- parse source-pack options
- select `SourcePackArtifactTarget` from emit/backend options
- load package/path manifests
- call metadata/artifact preparation in bounded chunks
- print progress snapshots and prepared summaries
- submit descriptor or path work-queue chunks
- validate emitted descriptor/output contracts

CLI progress files and user-facing reporting should not define a second build
state. The artifact root and `FilesystemArtifactStore` remain the source of
truth for prepared state, work readiness, claims, and completion.

## Validation And Failure Modes

Source-pack code is intentionally validation-heavy. Important checks include:

- page/index version numbers
- target matches requested target
- source byte/file/line counts match job and partition records
- dependencies point to prior jobs/items
- dependents point to later jobs/items
- dependency/dependent ranges do not overflow item counts
- inline record counts do not exceed page caps unless spill pages exist
- artifact manifests agree with stored indexes
- compact manifests are not used where inline execution records are required
- source-file metadata still matches the path manifest
- work item kind matches its artifact job phase or hierarchical link page
- frontend/codegen work items map to singleton artifact batches
- link pages match link-plan group kind, job index, input sidecars, and output key
- claimed work is completed only by the claiming worker, unless it was already
  completed by a previous idempotent step

Do not remove a validation check as "defensive noise" unless another boundary
proves the same persisted contract. These checks protect resumability and make
corrupt or stale artifact stores fail near the bad record.

Common failure modes and likely owning boundaries:

| Symptom | Likely owner |
| --- | --- |
| Missing target-specific file | Store path helper or caller target selection. |
| Prepared summary count mismatch | Preparation stage wrote an index without matching pages, or validation missed a count. |
| Worker finds no ready work while unfinished work exists | Progress page/directory/root index refresh. |
| Work item kind disagrees with job phase | Work-queue page preparation or singleton artifact lookup. |
| Link item disagrees with execution page | Hierarchical link execution preparation or work-queue page preparation. |
| Compact manifest rejected for execution | Caller used compact manifest path instead of execution shards. |
| Artifact path exists under wrong backend | Target namespace or artifact key construction escaped store helpers. |

## Changing Source-Pack Records

Use this checklist when adding or changing persisted records:

1. Decide the owning stage: metadata, schedule, artifact refs, batches, shards,
   link plan, link execution, work queue, progress, or package metadata.
2. Add/update the record field, writer, reader, and validator together.
3. Decide whether old stores need read compatibility for another human being's
   existing workflow. If not, prefer a version bump or hard validation error
   over broad defaults.
4. Keep logical indices stable. Do not make vector position the only identity.
5. Add store path helpers for new files and use them everywhere.
6. Preserve bounded preparation. Long operations should advance by chunk and
   return progress.
7. Update ready-frontier logic if dependencies, dependents, or item kinds change.
8. Keep worker steps idempotent around already completed work and already
   worker-owned claims where the existing API expects resumability.
9. Add focused tests at the planning/validation/progress layer before exercising
   GPU compilation.
10. Regenerate `docs/compiler/generated/reference.md` if public operations,
    large structs, persisted status/layout fields, or Rustdoc coverage changed.

## Common Mistakes

- Building source-pack paths manually instead of using `FilesystemArtifactStore`.
- Treating `#[serde(default)]` as permission for new writers to omit fields.
- Adding a CLI path that mutates progress without going through public execution
  APIs.
- Completing a frontend/codegen work item without also respecting the backing
  artifact batch claim/completion contract.
- Loading a compact manifest and expecting inline execution rows to be present.
- Making target-specific artifacts share a generic key or path.
- Adding a source-pack dependency edge to compensate for unresolved source-file
  imports. That belongs in module/source-root resolution.
- Broadening worker loop limits to fix a stuck build instead of finding the bad
  progress index, directory summary, or validation check.

## Evidence To Update

Update this chapter when changes affect any of the following:

- source-pack input shapes or validation
- package/source-root loading that changes path manifests
- `SourcePackArtifactTarget` or artifact key/path conventions
- codegen unit/job/batch planning
- persisted source-pack record fields or version constants
- preparation stage order or completion boundary
- artifact shard, manifest, or lookup behavior
- hierarchical link planning or execution pages
- work-queue item kinds, dependency/dependent layout, claims, leases, or
  progress summaries
- descriptor executor behavior
- CLI source-pack commands or progress reporting

Useful checks after source-pack docs or contract changes:

```bash
tools/compiler_inventory.py --output docs/compiler/generated/reference.md
tools/compiler_inventory.py --check docs/compiler/generated/reference.md
cargo doc -p laniusc-compiler --no-deps --document-private-items
```

For docs-only edits, the generated-reference check plus link/format checks are
usually enough. For record or progress changes, add focused tests at the stage
that owns the changed contract.
