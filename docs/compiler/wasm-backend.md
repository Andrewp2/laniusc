# WASM Backend Internals

This chapter documents the GPU WASM backend: the compiler boundary that takes
parser HIR plus retained type-check metadata and records GPU passes that either
produce WASM bytes or report a source-addressable backend diagnostic.

The WASM backend is not a second frontend. It must not recover language meaning
from source text, file names, package metadata, or parser implementation details
that were not published as parser or type-check records. If WASM needs a
semantic fact, add that fact to the phase that owns it before extending backend
lowering.

## What This Chapter Owns

This chapter covers:

- WASM compile orchestration on `GpuCompiler`
- retained parser/type-check/diagnostic buffers consumed by WASM
- WASM pass loading, artifact names, and recording order
- resident WASM buffer and bind-group reuse
- WASM metadata buffer groups
- output capacity, dispatch planning, and readback
- WASM status words and diagnostic mapping
- source-pack interaction for WASM output
- WASM-specific authoring and test rules

It does not cover:

- target-independent source-pack job planning; see
  [Source packs, artifacts, and work queues](source-packs.md)
- the broad backend boundary and x86 behavior; see
  [Codegen and backends](codegen.md)
- x86 lowering internals; see [x86 backend internals](x86-backend.md)
- parser HIR record construction; see [Parser and HIR](parser.md)
- type-check codegen metadata construction; see
  [Resident type checker](type-checker.md)

## Source Map

| Source | Responsibility |
| --- | --- |
| `compiler/gpu_compiler/wasm_codegen.rs` | End-to-end WASM orchestration, frontend/type-check/backend recording, backend finish, and diagnostic mapping. |
| `codegen/wasm.rs` | WASM public backend surface: status wrapper, metadata input structs, pass loading, resident buffer cache, dispatch sequencing, and finish entry point. |
| `codegen/wasm/support.rs` | Trace flag, uniform/status encoders, readback/output decoding, output-capacity estimate, dispatch grid helper, and resident fingerprint helper. |
| `shaders/codegen/wasm` | WASM-specific Slang passes for aggregate layout, HIR body lowering, aggregate-body boundary, enum/match records, constant values, module building, and module assertions. |
| `shaders/codegen/pack_output.slang` | Shared output packing pass used by WASM after module status succeeds. |
| `tests/codegen_wasm.rs` | Public backend-boundary tests for current WASM behavior. |

The Rust side owns orchestration, buffer lifetimes, capacity selection, pass
ordering, and diagnostic mapping. Shader passes own row transforms and compact
backend status writes.

## End-To-End Flow

The WASM single-source and source-pack paths use the same backend recorder after
lexing, parsing, and type checking have produced GPU-resident records.

1. Prepare source text for GPU input.
2. For single-source compile, run a type-check preflight before batched WASM
   recording. This keeps expected user type errors from executing the current
   backend batch until WASM has the same staged boundary shape as x86.
3. Lock the resident pipeline.
4. Lex source or source pack into resident token buffers.
5. Ask the parser for projected tree capacity.
6. Record parser LL/HIR work with that tree capacity.
7. Record type checking from parser HIR rows.
8. Borrow type-check codegen metadata through `with_codegen_buffers`.
9. Call `record_wasm_from_gpu_token_buffer` with parser rows, source/token
   buffers, type-check codegen rows, and grouped parser metadata.
10. Submit the command encoder through the lexer resident helper.
11. Finish parser status.
12. Finish type-check status.
13. Finish WASM status/output readback.
14. Return target bytes or map `WasmOutputError` to `CompileError::Diagnostic`.

The finish order matters. WASM output is trusted only after parser and
type-check status both accept the input. Backend status must not compensate for
bad frontend state.

## Retained Inputs

WASM consumes records, not live syntax trees.

| Input group | Owner | Examples |
| --- | --- | --- |
| Source and token buffers | Lexer | source bytes, token rows, token count, token file ids for source packs. |
| Parser topology | Parser | node kind, parent, first child, next sibling. |
| Parser HIR identity | Parser | HIR kind, token start/end, parser status. |
| Parser expression rows | Parser | expression records, result-root nodes, integer values, statement records, nearest statement/block/control nodes. |
| Parser call rows | Parser | callee node, context statement, argument start/end/count, argument parent, argument ordinal. |
| Parser aggregate rows | Parser | struct literal field parent, member name token, enum variant ordinal, match arm rows. |
| Type-check codegen rows | Type checker | visible declarations/types, name ids, enclosing function, resolved calls, entrypoint tags, call return/parameter types, method receiver metadata, type-instance rows, aggregate field ordinals, expected field refs. |

If a new WASM pass needs a semantic fact after type checking, first identify the
parser or type-check row that should own it. If no row exists, add one at the
owning phase. Do not infer language meaning from token spelling inside WASM.

## Metadata Buffer Groups

`record_wasm_from_gpu_token_buffer` has many inputs, so the Rust surface groups
related parser/type-check rows into small structs:

| Group | Fields represented |
| --- | --- |
| `GpuWasmStructMetadataBuffers` | Struct literal field ownership, member name tokens, member result field ordinals, and struct-init field ordinals. |
| `GpuWasmEnumMatchMetadataBuffers` | Variant ordinals, match scrutinee rows, match arm ranges, payload ranges, pattern nodes, and result nodes. |
| `GpuWasmCallMetadataBuffers` | Call callee/context rows and argument ownership/count/ordinal rows. |
| `GpuWasmExprMetadataBuffers` | Expression records, result roots, integer values, statement records, and nearest enclosing statement/block/control rows. |

These groups are a review boundary. Adding a field should answer two questions:

1. Which phase owns the fact?
2. Which WASM pass reads it?

If several passes need the same new fact, put it in a named group instead of
threading one more raw `wgpu::Buffer` through unrelated call sites.

## Resident Buffer Cache

`GpuWasmCodeGenerator` owns a `Mutex<Option<ResidentWasmBuffers>>`. The resident
slot caches output storage, status storage, scratch rows, readbacks, and bind
groups across compile operations.

The cache is valid only while these facts still cover the next compile:

- input buffer fingerprint
- output capacity
- token capacity
- HIR node capacity

The input fingerprint hashes every source, token, parser, and type-check buffer
used by the bind groups. If a new pass reads a buffer and that buffer is not in
the fingerprint, the generator can reuse a bind group that points at stale
inputs. That is a correctness bug, not a performance detail.

Capacity reuse is one-way: a larger existing resident allocation can satisfy a
smaller later compile, but smaller cached storage forces a rebuild.

## Resident Storage

`ResidentWasmBuffers` stores three kinds of data:

| Storage kind | Examples |
| --- | --- |
| Uniform/dispatch/status | `WasmParams`, body dispatch args, body status, backend status. |
| Backend row storage | body words, aggregate layout rows, enum/match records, constant-value records, module output words, packed output words. |
| Host readback | output readback and four-word status readback. |

Most storage is allocated as `LaniusBuffer<u32>` so the owner preserves logical
element counts. Raw `wgpu::Buffer` appears at externally owned inputs, readback
buffers, and the low-level wgpu binding/copy boundary.

## Pass Loading

`GpuWasmCodeGenerator::new_with_device` loads these artifacts:

| Stage | Artifact key |
| --- | --- |
| `agg_layout_clear` | `codegen/wasm/agg/layout/clear` |
| `agg_layout` | `codegen/wasm/agg/layout` |
| `hir_body` | `codegen/wasm/hir/body` |
| `hir_agg_body` | `codegen/wasm/hir/agg_body` |
| `hir_assert_module` | `codegen/wasm/hir/assert_module` |
| `hir_enum_match_records` | `codegen/wasm/hir/enum_match_records` |
| `const_values` | `codegen/wasm/const_values` |
| `module` | `codegen/wasm/module` |
| `pack` | `codegen/pack_output` |

Artifact lookup, reflection parsing, and bind group layout construction follow
the shared shader artifact ABI. See [Shader artifact and reflection ABI](shader-abi.md)
for artifact freshness and reflection rules.

## Recording Stages

`wasm_record_boundaries()` exposes the durable WASM stage contract:

| Stage | Reads | Writes |
| --- | --- | --- |
| `agg_layout_clear` | WASM params | aggregate layout records |
| `agg_layout` | HIR records, struct records, existing aggregate records | aggregate layout records |
| `const_values` | HIR status, expression rows, statement rows | constant-value records |
| `hir_body` | HIR records, type-check records, call records, constant-value records | body words, body status, backend status |
| `hir_agg_body` | backend status | backend status |
| `hir_enum_match_records` | match records | enum/match records |
| `module` | body words, body status | module words, backend status |
| `hir_assert_module` | backend status | backend status |
| `pack_output` | module words, backend status | packed bytes, backend status |

The current order is also the command recording order:

1. clear aggregate layout rows
2. build aggregate layout rows
3. build constant-value rows
4. build body words and body status
5. run the aggregate-body boundary
6. build enum/match records
7. build module words
8. run module assertion
9. pack output bytes
10. copy backend status to readback

When adding a pass, update both the actual dispatch order and
`WASM_RECORD_BOUNDARIES` if the pass becomes a durable stage. A stage in the
boundary list should describe real read/write ownership, not merely a convenient
place to put a dispatch.

## Capacity And Dispatch

WASM uses a conservative host output-capacity estimate:

- `source_len * 16`
- `token_capacity * 32`
- plus 4096 bytes of slack
- at least 4096 bytes

The backend records with several dispatch domains:

| Domain | How it is sized |
| --- | --- |
| token domain | `token_capacity.div_ceil(256).max(1)` |
| aggregate/HIR domain | `max(token_capacity, hir_node_capacity).div_ceil(256).max(1)` split through `workgroup_grid_1d` |
| assertion output domain | `min(output_capacity, WASM_ASSERT_OUTPUT_TARGET_LIMIT).div_ceil(256).max(1)` split through `workgroup_grid_1d` |
| module/pack domain | indirect dispatch from `body_dispatch_buf` |

`workgroup_grid_1d` splits large dispatches across the WebGPU x/y workgroup
limits. It does not prove that the shader algorithm is unbounded. If normal
source code can hit a shader-side loop or shape bound, replace the bound with a
scan, range query, segmented relation, or additional row family rather than
documenting the bound as a language restriction.

## Status And Output

WASM status is four `u32` words:

| Word | Meaning |
| --- | --- |
| 0 | output length |
| 1 | output mode |
| 2 | backend error code |
| 3 | backend detail |

Before dispatch, `status_buf` is initialized to an unsupported-shape status.
This makes the backend fail closed unless a later pass proves success by writing
an accepted mode and clearing the error code.

`read_wasm_output` reads status first. It accepts output modes `1`, `2`, `3`,
and `5`; rejects any nonzero error code as `WasmOutputError`; rejects output
lengths larger than the planned capacity; then copies exactly the output bytes
from either the packed output buffer or the raw output buffer.

Known status names currently include:

| Code range | Name shape |
| --- | --- |
| `2` | unsupported for loop |
| `3` | unsupported WASM body HIR-node budget |
| `800..=899` | unsupported array-helper body shape or budget |
| `900..=999` | unsupported retired enum-match module shape or budget |
| other nonzero | unsupported source shape |

The generated reference owns volatile status inventories. Update it when status
layouts, constants, or extraction inputs change.

## Diagnostic Mapping

`WasmOutputError` carries an error name, numeric code, and detail word.
`detail_is_token` currently treats these details as token indices:

- code `2`
- codes `800..=899` except `830` and `831`

Single-source diagnostics read the token row from the retained token buffer and
map the token span into the original diagnostic path. If the detail is not a
token or the token read fails, the mapper labels the first non-whitespace byte
in the source.

Source-pack diagnostics use the same token detail when possible, but token
spans are global offsets in the packed source stream. The source-pack mapper
finds the owning `DiagnosticSourceFile`, converts the global span to a local
span, and labels that file. If mapping fails, it labels the first file.

A new backend status should prefer one of these detail forms, in order:

1. source token
2. HIR node that can map through `hir_token_pos`
3. source-pack file plus local span
4. backend-local row plus a note only if no source-level location exists
5. target-only failure for truly global backend errors

A raw row id or capacity counter is not enough for a user-facing diagnostic
when the backend had access to source-mappable metadata.

## Source-Pack Interaction

`compile_source_pack_to_wasm` validates that the in-memory pack fits the
default codegen unit before running the frontend/backend path. It records
diagnostic file metadata for every source, runs the same parser/type-check/WASM
recording shape, and maps backend token details back to the owning source file.

`compile_source_pack_manifest_to_wasm` currently delegates to
`compile_source_pack_to_wasm` with the manifest sources. Source-pack planning,
artifact targets, persisted stores, descriptor workers, and target-qualified
paths are owned by the source-pack docs, not by the WASM backend.

When a WASM change affects persisted source-pack records, update
[Source packs, artifacts, and work queues](source-packs.md). When it only
changes the single backend lowering of one already-planned unit, update this
chapter and the generated reference if volatile facts changed.

## Observability

The main WASM-specific signals are:

| Signal | Use |
| --- | --- |
| `LANIUS_WASM_TRACE=1` | Emit Rust-side WASM compile/codegen trace lines. |
| `LANIUS_WASM_READBACK_TIMEOUT_MS=...` | Override status/output readback timeout for WASM. |
| `LANIUS_GPU_COMPILE_HOST_TIMING=1` | See coarse host timing around parser, type-check, and WASM recording stamps. |
| `LANIUS_GPU_PIPELINE_PROGRESS=1` | Debug submit/readback progress when a map appears stuck. |
| `LANIUS_VALIDATION_SCOPES=1` | Debug resource or bind layout validation failures. |

Use normal diagnostics and generated reference tables before adding new
readbacks. WASM already reads status and output; broad extra readback can
dominate the runtime of small test inputs.

## Adding WASM Behavior

Use this checklist for WASM backend changes:

1. Identify the parser/type-check record that owns the semantic fact.
2. Add the fact to parser or type checking first if it does not already exist.
3. Add the buffer to the appropriate `GpuWasm*MetadataBuffers` group when it is
   part of a coherent metadata family.
4. Add the input buffer to the WASM fingerprint before binding it.
5. Allocate durable resident storage for any new row family.
6. Create bind groups with reflected resource names that match the Slang pass.
7. Initialize status so unsupported paths fail closed.
8. Record the new pass in dependency order.
9. Add the stage to `WASM_RECORD_BOUNDARIES` when it is a durable boundary.
10. Make backend detail source-addressable when possible.
11. Update single-source and source-pack diagnostic mapping if the detail kind
    changes.
12. Add the smallest `tests/codegen_wasm.rs` input that reaches the new path.
13. Regenerate `docs/compiler/generated/reference.md` when shader load sites,
    buffer carriers, status shapes, or Rustdoc-visible surfaces changed.

When the required semantic fact does not exist in parser or type-check output,
the correct first patch is not in WASM. Backend reconstruction of language
semantics is a phase boundary bug.

## Common Mistakes

| Mistake | Better boundary |
| --- | --- |
| Treating WASM as feature-equivalent to x86 because it shares frontend input shape | Document the current WASM support surface and fail closed for unsupported shapes. |
| Adding a WASM input buffer without updating the fingerprint | Add it to the fingerprint before bind-group reuse can observe stale inputs. |
| Reporting unsupported behavior with only a numeric detail | Use a token or HIR node detail when source labeling is possible. |
| Reading source text in a WASM shader to recover semantics | Publish the semantic fact from parser or type checking. |
| Hiding target-independent source-pack rules inside WASM | Put unit/job/artifact planning in `codegen::unit` or source-pack modules. |
| Adding broad readback to debug a row issue | Prefer status, traces, generated reference, or a small focused test first. |

## Test Evidence

For docs-only edits to this chapter, run:

```bash
tools/compiler_inventory.py --check docs/compiler/generated/reference.md
```

plus Markdown link, whitespace, and ASCII checks.

For behavior changes, choose the smallest proof that reaches the changed
contract:

- parser/type-check rows added for WASM should have parser or type-check tests
- backend status changes should have a diagnostic assertion
- WASM lowering support should have a small `tests/codegen_wasm.rs` source
- source-pack mapping changes should include a multi-file source-pack case
- capacity or dispatch changes should include focused backend evidence before
  any benchmark-sized generated input

Do not use a large generated source as the first proof for a WASM change. It is
useful only after the minimal backend contract already passes.
