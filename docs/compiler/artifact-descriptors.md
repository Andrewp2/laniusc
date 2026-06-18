# Artifact Descriptors And Output Contracts

Artifact descriptors are JSON contracts for source-pack artifacts. They describe
what a library-interface, codegen-object, partial-link, or linked-output artifact
contains without requiring the CLI, worker scheduler, or downstream tooling to
interpret backend-specific bytes directly.

Use this chapter when changing descriptor fields, descriptor validation,
descriptor-mode source-pack execution, runtime-service requirements, or CLI
contract output behavior. Use [Source packs, artifacts, and work queues](source-packs.md)
for the persisted build graph and work-queue model. Use [Codegen and backends](codegen.md)
for backend lowering and target-byte production.

## What This Chapter Owns

`compiler/artifact_descriptor.rs` owns the descriptor JSON schema and contract
validation. The descriptor executor in `compiler/gpu_compiler/source_pack_executor.rs`
owns writing descriptor artifacts during source-pack work-queue execution. The
CLI output layer owns the user-facing guard that prevents descriptor JSON from
being mistaken for executable bytes.

| Concern | Descriptor layer owns | Other layer owns |
| --- | --- | --- |
| JSON schema | Descriptor fields, schema version, serde shape, runtime ABI metadata. | Source-pack manifest/page layout. |
| Stage contract | Which descriptor stage is valid for which source-pack job phase. | Which work item is ready to run. |
| Record arrays | Logical array names, input/output split, bounded counts, storage keys. | Actual backend buffers or final binary layout. |
| Semantic rows | Domain/kind/flow rows that explain important arrays. | How a backend computes those rows. |
| Runtime services | Contract-only service requirements and ABI metadata. | A future runtime/linker binding that makes services executable. |
| CLI descriptor output | `--emit-contract` gating, JSON validation, executable-byte rejection. | Producing real target bytes. |

Descriptors are not debug dumps. They are persisted contracts. If a downstream
tool or CLI path can observe a descriptor field, treat the field like a file
format element: change the writer, reader, validation, tests, and docs together.

## Source Tree

| File | Responsibility |
| --- | --- |
| `compiler/artifact_descriptor.rs` | Descriptor schema, stage/domain/kind/flow enums, constructors, validation, runtime ABI/service contract, unit tests. |
| `compiler/gpu_compiler/source_pack_executor.rs` | Descriptor-mode source-pack executor that validates dependency artifacts and writes descriptor JSON under artifact keys. |
| `compiler/gpu_compiler/descriptor_work_queue.rs` | Prepared descriptor worker entry points used by CLI and public GPU APIs. |
| `compiler/gpu_public_api.rs` | Public wrappers for running or stepping descriptor workers for a prepared target. |
| `cli/source_pack/descriptor.rs` | CLI source-pack descriptor-mode orchestration and linked-output path checks. |
| `cli/output/contract.rs` | Reads linked-output descriptor JSON, rejects executable magic bytes, and validates stage/target before emission. |
| `cli/output/tests.rs` | User-facing output contract tests for descriptor emission. |
| `compiler/tests/work_queue_artifacts.rs` | Persisted descriptor/work-queue/link validation tests. |

The generated reference lists `GpuSourcePackArtifactDescriptor` as a large
compiler struct. Use that table to find volatile field counts; use this chapter
for what the fields mean.

## Descriptor Shape

`GpuSourcePackArtifactDescriptor` is the top-level JSON object. Important field
groups are:

| Field group | Fields | Meaning |
| --- | --- | --- |
| Schema and identity | `version`, `target`, `stage`, `job_index`, `group_index`, `phase` | Which compiler schema, artifact target, source-pack job, and optional link group produced the descriptor. |
| Source coverage | `library_id`, `first_source_index`, `source_file_count`, `source_bytes`, `source_lines` | Source range covered by the artifact. |
| Dependency counts | `dependency_interface_count`, `dependency_codegen_object_count`, `dependency_partial_link_count`, `dependency_interface_batch_count` | Summary of artifact inputs consumed by this stage. |
| Record arrays | `input_record_arrays`, `output_record_arrays`, `record_arrays` | Flat logical arrays consumed and produced by this artifact. |
| Semantic records | `descriptor_records` | Domain/kind/flow rows that explain important record arrays. |
| Runtime requirements | `required_runtime_abi_version`, `required_runtime_service_ids`, `required_runtime_services`, `runtime_abi` | Contract-only runtime requirements for artifacts that cannot yet claim standalone executable bytes. |

`record_arrays` is the combined form of `input_record_arrays` followed by
`output_record_arrays`. When either split list is present, validation requires
the combined list to match exactly. That invariant lets older or simpler
consumers read one flat list while newer code still distinguishes inputs from
outputs.

`GpuSourcePackRecordArrayDescriptor` describes one logical array:

- `name`: stable logical array name
- `element_count`: known record count, if bounded when written
- `byte_len`: known byte length, only valid when `element_count` is present
- `storage_key`: optional persisted storage key for arrays stored separately

`GpuSourcePackDescriptorRecord` gives semantic meaning to one record array:

- `domain`: interface, object, partial-link, or linked-output
- `kind`: section, symbol, unresolved-symbol, relocation, or runtime-service
- `flow`: input or output
- `record_array`: the array containing that row family
- `element_count`: exact count when the backing array is bounded

## Stages

Descriptor stages mirror source-pack artifact stages.

| Stage | Expected source-pack job phase | Group index | Main output contract |
| --- | --- | --- | --- |
| `LibraryInterface` | `LibraryFrontend` | forbidden | Interface symbol records, plus frontend record arrays such as tokens, parse tree, HIR, resolver, type instances, and semantic interface records. |
| `CodegenObject` | `Codegen` | forbidden | Object section, symbol, virtual instruction/register, and relocation record arrays. |
| `PartialLink` | `Link` | required | Partial-link sections, symbols, unresolved symbols, and relocations for one hierarchical link group. |
| `LinkedOutput` | `Link` | required when partial-link dependencies are consumed | Final linked sections and symbols, plus exactly one target-byte array when no runtime services remain unbound. |

Stage validation is deliberately strict:

- library-interface and codegen-object descriptors must not carry a link group
- library-interface descriptors must not describe object, partial-link, or
  linked-output records
- codegen-object descriptors must not describe partial-link or linked-output
  records
- partial-link descriptors must consume object or partial-link inputs and must
  not output linked-output records
- linked-output descriptors must consume object or partial-link inputs and must
  not output unresolved symbols or relocations

If a backend wants to add a new artifact stage, start by deciding the expected
source-pack job phase, group-index rule, input dependency types, output domain,
and final CLI behavior. Do not add a new enum variant without also adding the
stage validation and tests.

## Record Arrays

Record arrays are logical, not necessarily direct memory dumps. A descriptor may
say an array is pending when the exact element count or byte length is not known
at descriptor-write time.

Validation enforces these rules:

- array names must be nonempty
- array names are unique within each array list
- `byte_len` requires `element_count`
- nonempty `storage_key` values are unique within an array list
- split input/output lists must recombine into `record_arrays`
- descriptor records must reference declared arrays
- descriptor record names are unique
- descriptor records with `Input` flow reference input arrays
- descriptor records with `Output` flow reference output arrays
- one record array must not be described by multiple semantic rows
- bounded reserved arrays must be counted exactly once by their descriptor row

Reserved record array names pin semantic shape. For example:

| Array family | Required domain/kind |
| --- | --- |
| `dependency_semantic_interface_records`, `semantic_interface_records` | Interface symbols |
| `object_section_records`, `allocated_instruction_records` | Object sections |
| `object_symbol_records`, `function_offset_records` | Object symbols |
| `relocation_records`, `link_relocation_records` | Object relocations |
| `partial_link_*` and `input_partial_link_*` arrays | Partial-link sections, symbols, unresolved symbols, or relocations |
| `linked_section_records`, `linked_symbol_records` | Linked-output sections or symbols |

Do not reuse a reserved array name for a different semantic row. That would make
old validators accept a descriptor with the wrong meaning.

## Runtime ABI And Services

Runtime-service requirements are represented inside descriptors because some
linked outputs cannot honestly claim executable target bytes until a runtime or
linker binding exists.

Known runtime service ids are contiguous and currently cover allocator,
filesystem, stdio, clock, networking, panic hook, generic host services,
threads, secure random, host GPU, process, environment, and test harness
services. The descriptor contract stores:

- `required_runtime_service_ids`: sorted, deduplicated service ids
- `required_runtime_services`: one row per service id
- `required_runtime_abi_version`: the ABI version those rows require
- `runtime_abi`: metadata for the runtime ABI inventory

`set_required_runtime_services` canonicalizes ids, creates contract-only rows,
sets the current runtime ABI, and synchronizes the runtime-service record-array
contract.

The rows are fail-closed by design. `GpuSourcePackRuntimeServiceRequirement::contract_only`
starts each required service as unavailable. A descriptor that requires runtime
services records a contract requirement, not proof that the service is bound.

Validation rejects:

- unknown service ids
- duplicate or unsorted service ids
- missing runtime ABI metadata for runtime-bound descriptors
- unknown or unsupported runtime ABI versions
- service rows whose ids, ABI versions, or statuses disagree with the canonical
  requirement list
- service rows that claim available runtime bindings inside a contract-only
  descriptor
- runtime-bound descriptors that also claim target-byte output arrays

That last rule is important. If a descriptor still needs runtime services, it
must not pretend to contain executable target bytes. A future runtime linker can
produce a new descriptor once services are actually bound.

## Target Bytes

Linked-output descriptors have a special target-byte policy.

If a linked-output descriptor has no runtime service requirements, it must
declare exactly one target-byte output record array. The recognized target-byte
array names are:

- `emitted_byte_records`
- `x86_file_bytes`
- `x86_packed_file_words`
- `wasm_module_bytes`

If runtime service requirements are present, validation rejects every target-byte
array. This keeps descriptor-mode output honest: it may describe what still has
to be linked or bound, but it cannot masquerade as a final executable payload.

The CLI adds a second guard at output time. `read_linked_output_contract_descriptor`
reads the descriptor file, rejects ELF and WASM magic bytes, parses JSON as a
`GpuSourcePackArtifactDescriptor`, and validates it as a `LinkedOutput`
descriptor for the requested emit target. Descriptor output requires
`--emit-contract`; without that explicit flag, source-pack descriptor paths are
not treated as target bytes.

## Constructors

Use the descriptor constructors rather than constructing descriptor JSON by
hand.

| Constructor | Use |
| --- | --- |
| `library_interface_for_job` | Descriptor for a frontend/library-interface source-pack job. |
| `codegen_object_contract_for_job` | Descriptor for a codegen-object source-pack job. |
| `linked_output_contract_for_job` | Direct linked-output descriptor for a source-pack link job. |
| `partial_link_contract_for_page` | Descriptor for one hierarchical partial-link execution page. |
| `hierarchical_linked_output_contract_for_page` | Descriptor for one hierarchical final-link execution page. |

The constructors encode the stage-specific record arrays and descriptor records.
They also preserve source coverage, dependency counts, target, phase, job index,
and group index.

Hierarchical link constructors apply runtime requirements from
`SourcePackLinkDescriptorSummary`. That is how runtime requirements discovered
while planning/linking propagate to partial-link and linked-output descriptors.

## Descriptor Executor

`GpuSourcePackArtifactExecutor` emits descriptor artifacts while executing a
prepared source-pack work queue.

Current behavior:

1. Library-interface jobs validate source metadata, read source files, run
   `GpuCompiler::type_check_source_pack`, and write a library-interface
   descriptor.
2. Codegen-object jobs validate source metadata, require the owning interface
   artifact to exist, count dependency interface batches, and write a codegen
   descriptor.
3. Direct link jobs validate dependency artifacts, count interface/object
   inputs, and write a linked-output descriptor.
4. Hierarchical partial-link groups validate dependency artifacts, count
   interface/object/partial-link inputs, and write partial-link descriptors.
5. Hierarchical final-link groups do the same and write linked-output
   descriptors.

Descriptor artifacts are written under keys shaped like:

```text
gpu-source-pack/{target}/{stage}/{suffix}.json
```

where `{target}` is `generic`, `wasm`, or `x86_64`; `{stage}` is
`library-interface`, `codegen-object`, `partial-link`, or `linked-output`; and
the suffix is usually `job-{job_index}` or `group-{group_index}`.

The executor validates dependency artifact paths before counting them. Missing
dependencies are codegen errors, not absent optional metadata.

## Validation Boundaries

The descriptor validation boundary is `GpuSourcePackArtifactDescriptor::validate_contract`.
It checks:

- descriptor schema version
- stage/phase pairing
- stage-specific group-index rules
- dependency count sanity
- record-array shape
- combined input/output array ordering
- descriptor record references
- stage-specific required and rejected semantic rows
- output domains for descriptor records and output arrays
- reserved record-array coverage
- runtime ABI and service rows
- linked-output target-byte policy

`validate_contract_for` adds the boundary-specific stage and target check used
by the CLI. Use it when reading a descriptor for a known user-facing purpose.
Use `validate_contract` when testing or building descriptors before the final
consumer has chosen a stage/target expectation.

Do not downgrade descriptor validation errors to warnings. A descriptor that
fails validation is not a partially usable artifact contract; it is a contract
the compiler can no longer interpret safely.

## CLI Output Boundary

The CLI has two descriptor responsibilities:

1. Source-pack descriptor compile modes run or resume the prepared descriptor
   work queue and return the linked-output descriptor path only when the queue
   completes.
2. Output writing copies descriptor JSON only when descriptor output was
   explicitly requested and the JSON validates for the selected emit target.

`cli/source_pack/descriptor.rs` also verifies the completed linked-output path:

- the worker run must report complete progress
- the run must report a linked output key and path
- the linked output path must exist
- the linked output path must equal the store path for the linked output key
- the canonical output path must stay under the artifact root

This prevents a worker result from causing the CLI to emit a descriptor path that
does not correspond to the artifact store's linked-output key.

## Changing Descriptor Contracts

Use this checklist when changing artifact descriptors:

1. Decide whether the change is schema, stage contract, record-array shape,
   runtime-service policy, descriptor executor behavior, or CLI output behavior.
2. Add or update constructors first. Callers should not hand-build descriptor
   JSON.
3. Update `validate_contract` and `validate_contract_for` if the meaning changes.
4. Decide whether old descriptors need read compatibility for another human
   being's existing artifacts. If not, prefer a schema/version validation error
   over permissive defaults.
5. Add tests near `compiler/artifact_descriptor.rs` for pure schema/validation
   behavior.
6. Add source-pack/work-queue tests when persisted link pages, descriptor
   summaries, or artifact keys are affected.
7. Add CLI output tests when `--emit-contract`, executable-byte guards, or
   descriptor file emission changes.
8. Update [Source packs, artifacts, and work queues](source-packs.md) if the
   work-queue or persisted artifact behavior changes.
9. Update [Codegen and backends](codegen.md) if descriptor changes reflect a new
   backend artifact shape.
10. Regenerate the generated reference if public operations, large structs,
    Rustdoc coverage, or status layouts changed.

## Common Mistakes

- Treating descriptor JSON as target bytes. Descriptor output requires
  `--emit-contract`.
- Adding a record array without a semantic descriptor row.
- Reusing a reserved record-array name with a different domain or kind.
- Adding `byte_len` without an `element_count`.
- Adding runtime service ids without canonical sorting and matching service rows.
- Claiming target-byte output while runtime services are still unbound.
- Writing a descriptor artifact without validating source/job metadata or
  dependency artifact existence.
- Adding stage-specific fields without saying which source-pack job phase owns
  them.

## Evidence To Update

Relevant focused tests and checks:

```bash
cargo test -p laniusc-compiler artifact_descriptor
cargo test -p laniusc-compiler contract_descriptor_emission
cargo test -p laniusc-compiler descriptor_compile
tools/compiler_inventory.py --check docs/compiler/generated/reference.md
```

For docs-only descriptor edits, the generated-reference and Markdown checks are
usually enough. For schema, validation, executor, or CLI output behavior, add or
run the focused Rust tests at the boundary that owns the changed contract.
