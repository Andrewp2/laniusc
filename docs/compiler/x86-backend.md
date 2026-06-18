# x86 Backend Internals

This chapter documents the GPU x86_64 backend: the compiler boundary that takes
parser HIR plus retained type-check metadata and records GPU passes that produce
x86_64 ELF/object bytes or a source-addressable backend diagnostic.

The x86 backend is not a second frontend. It must not recover language meaning
from source text, file names, package metadata, or parser implementation details
that were not published as parser or type-check records. If x86 needs a semantic
fact, add that fact to the phase that owns it before extending backend lowering.

## What This Chapter Owns

This chapter covers:

- x86 compile orchestration on `GpuCompiler`
- retained parser/type-check/diagnostic buffers consumed by x86
- x86 feature measurement and capacity planning
- `RecordElfInputs` and the x86 recording boundary
- backend scratch reuse and pooled allocation
- x86 recording pass families
- output/status readback and diagnostic mapping
- bounded-pass contracts and blocked replacement directions
- source-pack interaction for x86 output
- x86-specific authoring and test rules

It does not cover:

- target-independent source-pack job planning; see
  [Source packs, artifacts, and work queues](source-packs.md)
- the broad backend boundary and WASM behavior; see
  [Codegen and backends](codegen.md)
- parser HIR record construction; see [Parser and HIR](parser.md)
- parser readback invariants; see
  [Parser readback and HIR validators](parser-readback.md)
- type-check codegen metadata construction; see
  [Resident type checker](type-checker.md)

## Source Map

| Source | Responsibility |
| --- | --- |
| `compiler/gpu_compiler/x86_codegen.rs` | End-to-end x86 orchestration, parser/type-check/backend boundaries, feature measurement, backend submission, output readback, and diagnostic mapping. |
| `compiler/gpu_compiler/buffers.rs` | `OwnedX86ParserBuffers` and `OwnedX86DiagnosticBuffers`, the retained frontend rows x86 can use after parser/lexer caches are released. |
| `codegen/x86.rs` | x86 public backend surface: status codes, feature summary, metadata input structs, capacity helpers, pass contracts, and `GpuX86CodeGenerator`. |
| `codegen/x86/record.rs` | Main `record_elf_from_hir` implementation: allocation, bind-group creation, dispatch sequencing, readback copies, and buffer retention. |
| `codegen/x86/record/*` | Recording submodules for capacity, allocation, metadata bind groups, semantic rows, calls, instruction planning, virtual rows, emission, status tracing, and timing. |
| `codegen/x86/support.rs` | Buffer pools, uniform helpers, dispatch helpers, trace flags, output decoding, and status-to-error conversion helpers. |
| `codegen/x86/finish.rs` | `RecordedX86Codegen::read_output` entry point. |
| `shaders/codegen/x86` | Slang passes that implement feature counts, metadata rows, instruction planning, virtual instructions, register allocation, text/reloc/ELF emission, and status writes. |

The Rust side owns orchestration, buffer lifetimes, capacity planning, and
diagnostic mapping. Shader passes own row transforms and status writes.

## End-To-End Flow

The single-source and source-pack x86 paths share the same shape. The
source-pack path also carries diagnostic-file tables so global token spans can
be mapped back to the owning file.

1. Lex source into resident token buffers.
2. Ask the parser for projected tree capacity.
3. Record parser LL/HIR work in a parser-boundary encoder.
4. Submit the parser boundary and read parser status.
5. Read semantic-HIR count for backend capacity planning.
6. Clone parser rows into `OwnedTypecheckParserBuffers` and
   `OwnedX86ParserBuffers`.
7. Release parser resident buffers and poll the device so released storage can
   be reused.
8. Clone lexer rows needed for x86 diagnostics into
   `OwnedX86DiagnosticBuffers`.
9. Record type checking from retained parser rows.
10. Finish type checking and take `OwnedGpuX86CodegenBuffers`.
11. Measure x86 feature usage from retained parser rows.
12. Create an x86 backend encoder.
13. Call `record_x86_from_parse_buffers_with_codegen`, which builds
   `RecordElfInputs` and records x86 passes.
14. Submit the backend boundary.
15. Read output/status from `RecordedX86Codegen`.
16. Return target bytes or map `X86OutputError` to a diagnostic.

This split is deliberate. Parser status is checked before type checking, and
type-check status is checked before x86 output is trusted. Backend recording
must not be used to compensate for a bad frontend status.

## Retained Inputs

x86 consumes retained records, not live frontend caches.

| Retained input | Owner | Purpose |
| --- | --- | --- |
| `OwnedX86ParserBuffers` | Parser boundary | HIR topology, token spans, item/type/expression/statement/list rows, and scratch rows that are dead before backend recording. |
| `OwnedX86DiagnosticBuffers` | Lexer boundary | Token rows and source byte length used to map x86 status details back to source labels. |
| `OwnedGpuX86CodegenBuffers` | Type checker | Resolved declarations, calls, visible types, type instances, method receiver metadata, aggregate metadata, and entrypoint tags. |
| `RecordElfInputs` | x86 boundary | The grouped Rust contract passed into `record_elf_from_hir`. |

If a new pass needs parser or type-check state after the frontend cache is
released, add the buffer to the retained wrapper. Do not extend a borrow across
the release boundary.

## RecordElfInputs Groups

`RecordElfInputs` is intentionally grouped by semantic source:

| Group | Examples |
| --- | --- |
| Global shape | source length, token capacity, HIR count, instruction-HIR count. |
| Parser status/topology | LL status, active-HIR dispatch args, HIR kind, item kind, parent, subtree end. |
| Function metadata | item declaration/name tokens, HIR token position, return type node, parameter records, enclosing function rows, method receiver metadata. |
| Expression metadata | expression record, expression result root, integer value, statement record, type form, type length. |
| Call metadata | parser call rows, member rows, resolved call rows, call return types, call parameter types. |
| Array/enum/struct metadata | parser aggregate rows plus type-check declaration/field/variant rows. |
| Type metadata | declaration type refs, visible types, type-instance rows. |
| Entrypoint metadata | visible declarations and function entrypoint tags. |
| Feature summary | enum/match/aggregate/call/param/scalar counts. |
| External scratch | frontend buffers known to be dead before x86 recording starts. |

This grouping is a code review aid. A change that wires a call row through type
metadata, or a type row through parser metadata, is usually a boundary mistake.

## Feature Measurement

Before full recording, x86 measures backend feature usage with
`GpuX86CodeGenerator::measure_features`. The feature summary contains:

- feature mask bits for enums, matches, aggregates, and calls
- enum count
- match count
- aggregate count
- scalar instruction capacity estimate
- call count
- parameter count

Feature measurement is used for capacity planning and conditional pass work. It
is not semantic validation. If a source program is invalid, type checking or an
explicit x86 backend status should report that failure.

Scalar-only programs can use a tighter scalar instruction estimate. Programs
with enums, matches, aggregates, or calls fall back to more conservative
capacity planning because those feature families introduce additional rows and
control/data-flow records.

## Capacity Planning

`RecordCapacity::for_hir` derives all backend capacities and step lists before
recording passes:

- HIR row count
- instruction capacity
- output capacity and output readback bytes
- scan row counts and block counts
- pointer-jump step lists
- function-slot capacity
- virtual next-call scan steps
- register-allocation chunk count
- WebGPU dispatch grid splits
- encoded `X86Params`

The host capacity estimator uses HIR rows, token capacity, instruction-HIR
basis rows, feature summary, minimum/slack constants, and hard caps. If the
estimate hits the instruction cap, the code logs a warning. That warning is not
a correctness path; status buffers still must fail closed if later passes run
out of rows.

Capacity planning also derives repeated step lists from helper functions:

| Helper | Use |
| --- | --- |
| `pointer_jump_steps_for_items` | Parent/owner propagation over HIR-sized row sets. |
| `scan_steps_for_blocks` | Prefix scans over block counts. |
| `workgroup_grid_1d` | Splits workgroup counts across WebGPU's x/y dispatch limits. |
| `regalloc_recorded_chunk_count` | Fixed-size register-allocation chunk plan. |
| `x86_function_slot_capacity` | Function slot bound from instruction-HIR count, HIR rows, and token density. |

When adding a pass, decide whether its rows are proportional to HIR rows,
tokens, instruction rows, function slots, feature counts, or output bytes. Do
not hide a new row family behind an unrelated existing capacity just because the
buffer is large enough today.

## Allocation And Scratch

x86 allocation uses three patterns:

- owned buffers for durable backend rows
- pooled storage/readback buffers for large temporary/output buffers
- external scratch buffers borrowed from retained frontend rows that are known
  dead before backend recording

`GpuX86ExternalScratchBuffers` is the explicit scratch boundary. It exists to
avoid allocating duplicate temporary rows after frontend data has already been
copied into durable parser/type-check records. Each alias must be reviewed as a
lifetime fact, not as a naming convenience.

Rules for scratch reuse:

- a borrowed scratch buffer must not be read later as its old frontend meaning
- the backend must initialize or overwrite the borrowed range before use
- the count passed to the scratch wrapper must match the backend row family
- live parser/type-check input buffers must not be reused as scratch
- when in doubt, allocate a real backend buffer

The x86 path also opens WGPU out-of-memory error scopes around backend buffer
allocation. Allocation failures should become backend infrastructure errors, not
misleading language diagnostics.

## Recording Architecture

`record_elf_from_hir` has four broad phases:

1. Compute capacities and allocate buffers.
2. Create bind groups for all pass families.
3. Record metadata, instruction, virtual, and emit dispatches.
4. Copy output/status into readback buffers and retain buffers/bind groups until
   readback finishes.

The pass families are:

| Family | Main role |
| --- | --- |
| Dispatch setup | Clear active dispatch rows, derive active-HIR, node-order, virtual, and output dispatch arguments. |
| Function discovery | Build function metadata, owner rows, function slots, and expression resolution seeds. |
| Enum/match records | Build enum value/type records, match records, match pattern rows, and match ownership rows. |
| Semantic records | Build enclosing return/let/statement rows, aggregate records, declaration widths, and layout rows. |
| Call records | Build call rows, constant values, parameter registers, local literals, intrinsic-call rows, and call ABI rows. |
| Instruction planning | Count and order per-node instructions, derive same-end ranks, subtree bounds, semantic types, and instruction locations. |
| Instruction generation | Scatter worklist rows into virtual instruction rows and aggregate-copy rows. |
| Virtual rows | Compute liveness, next-call information, function virtual row ranges, value-definition rows, parameter masks, and register allocation. |
| Emit | Select physical instructions, compute sizes, scan text/reloc offsets, encode bytes, patch relocations, lay out ELF, and write output. |
| Status trace | Optionally copy status buffers for debugging. |

The family order is a data-dependency order. Reordering is only safe when every
status buffer, scratch alias, dispatch-args buffer, and copied uniform that
crosses the boundary has been audited.

## Dispatch Patterns

x86 uses several dispatch helpers:

| Helper | Use |
| --- | --- |
| `dispatch_x86_stage` / `dispatch_x86_stages` | Direct passes over one computed workgroup grid. |
| `dispatch_compute_pass_indirect` | Passes whose work count is produced by an earlier pass. |
| `dispatch_compute_pass_indirect_offsets_with_dynamic_uniform_offsets` | Repeated indirect passes with per-step uniform rows. |
| `dispatch_indirect_dynamic_sequence` | Step sequences with different bind groups and dynamic offsets. |
| `dispatch_compute_pass_indirect_ping_pong_scan_steps` | Ping-pong scans with alternating buffers. |
| `dispatch_compute_pass_indirect_bind_group_steps` | Pointer-jump or owner-propagation step chains. |

Prefer scan, scatter, sort/join, pointer-jump, or indirect-dispatch patterns
over shader loops whose trip count scales with source size. If a remaining loop
is deliberately bounded, document the bound and make the status path identify
the HIR node or token that exceeded it.

## Status And Output

x86 backend output uses an output buffer plus a four-word status copied into the
same readback allocation. `RecordedX86Codegen::read_output` maps the readback,
decodes status, and either returns exact output bytes or produces
`X86OutputError`.

`X86OutputError` carries:

- stable error name
- numeric backend error code
- detail word

The error decides how to interpret `detail`:

- `detail_is_token` means the detail is already a token index
- `detail_is_hir_node` means the detail must be mapped through retained
  `hir_token_pos`
- non-addressable details fall back to a first-source-span label

When adding a status, choose a token or HIR-node detail whenever possible.
Global target errors are allowed, but they are worse for users and harder for
maintainers to debug.

## Diagnostic Mapping

Single-source diagnostics and source-pack diagnostics share the same backend
status, but map source spans differently.

| Path | Mapping |
| --- | --- |
| Single source | Read retained token row and label that span in the source passed to the compile call. |
| Source pack | Read retained token row, map global token span to the owning diagnostic file, then label the local span. |
| Fallback | Label the first non-whitespace byte of the source or first source-pack file. |

Type-check failures on the x86 path are mapped before backend recording. x86
backend failures are mapped only after type checking has accepted and x86 status
readback rejects the output.

## Bounded Contracts

The x86 module exposes explicit pass contracts used by tests and trace output.
They describe where bounded loops remain and whether they block broad backend
claims.

| Contract | Current meaning |
| --- | --- |
| `x86_encode_pass_contract` | Encoding has a bounded-local byte loop per instruction, fails closed, does not consume source text, and is not a broad blocker. |
| `x86_regalloc_pass_contract` | Register allocation is bounded and blocked; it needs segmented value-definition rows and pressure/spill scans. |
| `x86_control_flow_bridge_pass_contract` | Control-flow bridge rows are bounded and blocked; replacement should use basic-block edge rows and segmented control-flow scans. |
| `x86_lowering_pass_contract` | Shape-specific lowering is bounded and blocked; replacement should use generic operation records and segmented virtual-instruction scatter. |

Do not paper over a blocked contract with compatibility aliases or fallback
syntax recognition. If normal user code can hit the bound, the fix is to
replace the bounded formulation with a scan/range/segmented design and keep a
source-addressable error until that replacement exists.

## Source-Pack Interaction

For in-memory source packs, x86 first validates that the pack fits the default
bounded codegen unit. It then runs the same parser/type-check/backend boundaries
as the single-source path while preserving source paths for diagnostics.

Persisted source-pack/work-queue paths can target `SourcePackArtifactTarget::X86_64`.
Those paths should plan and claim jobs through source-pack APIs, then call the
backend through the owning execution boundary. Do not add source-pack scheduling
logic to x86 lowering code; the backend lowers one already-bounded frontend
result.

## Observability

x86-specific signals:

| Signal | Use |
| --- | --- |
| `LANIUS_X86_TRACE=1` | Print x86 pass recording trace events. |
| `LANIUS_X86_STATUS_TRACE=1` | Copy selected x86 status buffers into a readback trace. |
| GPU host timing stamps | Identify expensive host-side capacity, allocation, bind-group, or recording phases. |
| GPU timer stamps | Measure device-side x86 pass families when timing is enabled. |
| Generated reference | Check current x86 shader load sites, status constants, and large buffer carrier structs. |

Start with status and generated reference before enabling broad trace/readback.
x86 status trace is useful when the final output status is too coarse to show
which family first rejected the program.

## Adding x86 Behavior

Use this checklist for x86 backend changes:

1. Identify the parser or type-check row that owns the semantic fact.
2. Add/retain that row at the frontend boundary before using it in x86.
3. Add the field to the narrow metadata group that matches its owner.
4. Decide whether feature measurement needs to count the shape.
5. Add capacity rows for the new pass based on the right unit: HIR, tokens,
   instructions, function slots, feature count, or output bytes.
6. Allocate a durable backend buffer unless scratch reuse is provably dead and
   local.
7. Add bind groups with reflected names that match the shader resources.
8. Record the pass in dependency order.
9. Add status words for unsupported or invalid backend shapes.
10. Make status detail source-addressable when possible.
11. Add focused tests for the smallest source that reaches the new path.
12. Regenerate generated reference if shader load sites, status constants, or
    large buffer carriers changed.

When the backend needs a row that the frontend does not publish, stop and add
the frontend row first. Backend reconstruction of syntax or type semantics is a
phase-boundary bug.

## Common Mistakes

| Mistake | Better boundary |
| --- | --- |
| Reading source text or file names in x86 lowering | Publish parser/type-check records and retain them. |
| Adding x86-only interpretation of language syntax | Add parser HIR or type-check metadata first. |
| Reusing a retained frontend buffer as scratch while it is still read as input | Allocate a backend buffer or move the scratch after the final read. |
| Treating feature measurement as validation | Use type checking or explicit x86 status for semantic rejection. |
| Adding source-pack schedule decisions in x86 modules | Keep planning in source-pack/codegen-unit APIs. |
| Adding a backend status without source-addressable detail | Use token or HIR-node detail when the bad construct has a source span. |
| Treating a blocked bounded contract as acceptable forever | Replace it with segmented scans/range rows and keep fail-closed diagnostics in the interim. |

## Test Evidence

Use the smallest test that proves the changed boundary:

| Change | Evidence |
| --- | --- |
| Capacity helper or bounded contract | x86 helper unit tests. |
| Metadata grouping or retained buffer | focused compile test plus generated-reference check when large structs changed. |
| New shader pass or status | smallest x86 compile source reaching the pass, status diagnostic test, generated-reference regeneration/check. |
| Diagnostic mapping | single-source and source-pack diagnostics when token/file mapping can differ. |
| Source-pack x86 execution | source-pack worker/descriptor test for the target path. |
| Performance/capacity claim | focused host/GPU timing or benchmark artifact for the changed pass family. |

For docs-only edits to this chapter, run generated-reference freshness, local
Markdown link checks, ASCII checks, and trailing-whitespace checks. Rust tests
are not required unless code, generated inventory inputs, or behavior changed.
