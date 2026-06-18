# Compiler Change Walkthroughs

This page turns the architecture and authoring checklists into concrete
maintenance workflows. Use it when you know roughly what feature or fix you
want, but need to decide which files, buffers, status paths, and tests should
move together.

For the testing evidence model behind these workflows, see
[Compiler testing and verification](testing.md).

These are not exhaustive recipes. They are examples of the shape a good change
should have: identify the owning phase, preserve source-mappable evidence, make
the smallest coherent implementation, prove the contract with a focused test,
and update generated or narrative docs only where the change moved the facts.

## Walkthrough: Adding A Source-Labeled Type Error

Goal: reject a semantic pattern and report the source construct that caused it.

Start by deciding whether the type checker is the first phase that has the
needed evidence. If the parser can only see syntax shape and the error depends
on resolved declarations, type refs, trait obligations, method receivers, or
visibility, the type checker owns the rejection.

Implementation shape:

1. Pick the relation family that already owns adjacent facts, such as names,
   visible declarations, type instances, calls, methods, predicates, or module
   paths.
2. In the shader pass that detects the problem, write a compact status payload:
   accepted flag, source token or source-mappable row, `GpuTypeCheckCode`, and
   detail.
3. If the pass can only see a derived row, thread through the token or HIR node
   that introduced that row before writing status.
4. Decode the code in `type_checker::GpuTypeCheckCode` only when the numeric
   status code is new.
5. Map the status in the compiler boundary that finishes type checking. Single
   source and source-pack paths must both preserve source labels.
6. Add a focused test with the smallest Lanius source that reaches the new
   rejection. The assertion should check the stable diagnostic code or the
   source-label behavior, not an incidental buffer row.

Evidence to preserve:

| Evidence | Why it matters |
| --- | --- |
| token id | best primary label when the bad source spelling is visible |
| HIR node id | useful when the error is attached to a construct rather than a token |
| source-file id | required for source-pack diagnostics |
| detail word | useful for secondary classification, but not enough for a primary label |

Docs and generated outputs:

- Update `diagnostics.md` if the mapping changes the diagnostic contract.
- Update `type-checker.md` if the pass family or status invariant changes.
- Regenerate `generated/reference.md` if a new `GpuTypeCheckCode` or shader
  load/record site appears.

Verification:

```bash
cargo test -p laniusc-compiler <focused_diagnostic_or_typecheck_test>
tools/compiler_inventory.py --check docs/compiler/generated/reference.md
```

Use broader GPU compile tests only after the focused diagnostic proves the
contract.

## Walkthrough: Adding Parser HIR Data For Later Phases

Goal: expose a new syntax fact from parser HIR to type checking or codegen.

The parser owns syntactic facts: tree topology, semantic HIR node identity,
source spans, owner/child/rank relationships, and typed HIR rows. It should not
decide module visibility, type identity, call compatibility, or backend layout.

Implementation shape:

1. Extend grammar/table inputs only when the syntax shape itself changed.
2. Add or extend HIR record buffers in the parser buffer model.
3. Add parser pass parameters, bind resources, and shader writes that populate
   the new row.
4. Keep the pass in the parser phase where all input topology exists and before
   any scratch row it needs is reused.
5. If type checking needs the row after parser resident buffers are released,
   add it to the owned parser wrapper used by type checking.
6. If x86 needs the row after type checking succeeds, add it to the x86 parser
   wrapper or route it through retained type-check metadata when the fact is
   semantic rather than syntactic.
7. Add a focused test at the smallest available parser/HIR or compile boundary.

Ownership checks:

| Question | If yes |
| --- | --- |
| Is this only about syntax shape or source span? | Parser HIR row is appropriate. |
| Does it require resolved declarations or type refs? | Type checker should compute it. |
| Does it only affect target layout or ABI? | Backend should compute it from retained metadata. |
| Does a later phase need the row after parser release? | Add an explicit owned retained wrapper field. |

Docs and generated outputs:

- Update `parser.md` if the HIR record family or pass order changes.
- Update `type-checker.md` or `codegen.md` when a later phase consumes the new
  retained row.
- Regenerate `generated/reference.md` if public items, shader load sites, buffer
  carriers, or large structs changed.

Verification:

```bash
cargo test -p laniusc-compiler <focused_parser_or_compile_test>
tools/compiler_inventory.py --check docs/compiler/generated/reference.md
```

If no focused parser assertion exists for the row, add one before relying on a
large compile fixture.

## Walkthrough: Adding A GPU Shader Pass

Goal: add a compute pass to an existing compiler phase.

First choose the owner. A pass belongs to the earliest phase that owns its
inputs and output contract. Avoid adding a pass to a later phase just because it
has a convenient buffer; avoid adding a pass to an earlier phase if it would
smuggle semantic policy into syntax construction.

Implementation shape:

1. Put the `.slang` file under the owning shader directory.
2. Import shared helpers explicitly.
3. Add a compute entry point only when the file should produce a compiled
   shader artifact.
4. Create or extend the Rust pass wrapper/loader for the owning phase.
5. Bind resources by reflected Slang names, not by positional guesses.
6. Size dispatch from the owner capacity, active-count buffer, or indirect
   dispatch args.
7. Record the pass after all inputs are initialized and before outputs are read
   or reused.
8. Add status reporting when the pass can reject source rather than silently
   writing partial rows.

Shader design checks:

| Check | Preferred answer |
| --- | --- |
| Does the pass need unbounded search? | Reformulate as scan, scatter, radix, range query, or repeated fixed projection with status on exhaustion. |
| Does the pass write status? | Include a source-mappable token/HIR payload. |
| Does the pass use shared helpers? | Import them explicitly so dependency edges are visible. |
| Does a bind-group layout change? | Let reflection drive Rust binding and update generated reference. |

Docs and generated outputs:

- Update `gpu-passes.md` if the pass changes artifact/reflection conventions.
- Update the owning subsystem page when phase order or invariants change.
- Regenerate `generated/reference.md` for new shader files, imports, load
  sites, or record sites.

Verification:

```bash
cargo test -p laniusc-compiler <focused_owner_phase_test>
tools/compiler_inventory.py --output docs/compiler/generated/reference.md
tools/compiler_inventory.py --check docs/compiler/generated/reference.md
```

Run broader compile tests only when the pass affects a shared phase boundary.

## Walkthrough: Extending x86 Lowering

Goal: make the x86 backend emit or validate a new supported source shape.

The backend should consume parser HIR and type-check metadata. It should not
rerun semantic decisions that type checking already made.

Implementation shape:

1. Identify whether the required input is syntactic parser HIR or semantic
   type-check metadata.
2. If the input is syntactic and not currently retained, add it to the x86
   parser wrapper before parser resident buffers are released.
3. If the input is semantic, expose it through `GpuX86CodegenBuffers` or the
   relevant retained type-check wrapper.
4. Update x86 feature measurement if capacity or optional pass execution
   depends on the new shape.
5. Add or extend backend record passes after type-check status has succeeded.
6. Add backend status when unsupported or invalid shapes can still reach x86.
7. Map backend status to a diagnostic using retained token/HIR data.

Capacity and scratch checks:

| Check | Why it matters |
| --- | --- |
| Does feature measurement see the new shape? | x86 buffer sizing and optional passes depend on it. |
| Is a frontend buffer reused as backend scratch? | Document why its frontend value is dead at that boundary. |
| Does a new metadata buffer affect bind groups? | Retain it explicitly and avoid hidden raw-buffer dependencies. |
| Does the backend status detail name a token or HIR node? | Diagnostics need source labels. |

Docs and generated outputs:

- Update `codegen.md` if backend phase order, metadata inputs, or status changes.
- Update `architecture.md` only when ownership boundaries change.
- Regenerate `generated/reference.md` if new status constants, buffer carriers,
  shader load sites, or Rustdoc-visible items changed.

Verification:

```bash
cargo test -p laniusc-compiler <focused_x86_test>
tools/compiler_inventory.py --check docs/compiler/generated/reference.md
```

Use the smallest source that reaches the new x86 path. Avoid benchmark-sized
fixtures as the first proof.

## Walkthrough: Adding A Source-Pack Persisted Record

Goal: persist new build-graph metadata for resumable source-pack preparation or
worker execution.

Source-pack records are persisted contracts. A new field or page affects
resumption, validation, target-specific paths, and worker compatibility.

Implementation shape:

1. Decide which stage owns the record: metadata, library schedule, artifact
   refs, job batches, dependents, artifact shards, hierarchical link, work
   queue, or progress.
2. Add the record or field to the versioned type for that stage.
3. Use `#[serde(default)]` only to read older or partially prepared stores; new
   writers should still populate the field.
4. Add store path helpers rather than constructing paths directly in worker
   code.
5. Update validation so mismatched persisted records fail at load or preparation
   boundaries.
6. Update resume logic so the stage can continue from existing files without
   rewriting completed records.
7. Add focused tests with tiny libraries and dependency edges.

Record-contract checks:

| Check | Required behavior |
| --- | --- |
| Versioned persisted type? | Readers can reject or default intentionally. |
| Target-specific path? | Generic, wasm, and x86 stores do not collide. |
| Validation boundary? | Corrupt or mismatched stores fail before execution. |
| Resume cursor? | Bounded preparation can continue without duplicate writes. |
| Worker lookup helper? | Worker code does not interpret compact pages ad hoc. |

Docs and generated outputs:

- Update `source-packs.md` for new stage, record family, or validation rule.
- Regenerate `generated/reference.md` if public planning/execution entry points
  or large structs changed.

Verification:

```bash
cargo test -p laniusc-compiler <focused_source_pack_test>
tools/compiler_inventory.py --check docs/compiler/generated/reference.md
```

Good source-pack tests use very small manifests and assert invariants directly:
dependency ordering, exact coverage, page counts, claim transitions, target
qualification, or validation errors.

## Walkthrough: Changing A Public Compiler Operation

Goal: add or change a compile/check/planning/execution function that callers can
use.

Public operation changes need both API evidence and tooling evidence. The CLI
may not expose every public function, but the generated reference should still
record the operation-facing surface.

Implementation shape:

1. Decide whether the function belongs to single-source compile/check,
   in-memory source packs, path-backed planning, persisted artifact execution,
   or work queues.
2. Keep input preparation and validation at the public boundary.
3. Preserve diagnostic paths or source-pack file ids before entering resident
   GPU phases.
4. Reuse existing orchestration helpers instead of duplicating phase sequencing.
5. Return `CompileError::Diagnostic` when a stable user-facing diagnostic is
   available.
6. Add a focused public API or CLI test depending on the exposed surface.

Docs and generated outputs:

- Update `cli.md` if command behavior changes.
- Update `source-packs.md` when planning/execution semantics change.
- Regenerate `generated/reference.md`; public compiler entry points are
  extracted there.

Verification:

```bash
cargo test -p laniusc-compiler <focused_public_api_or_cli_test>
tools/compiler_inventory.py --output docs/compiler/generated/reference.md
tools/compiler_inventory.py --check docs/compiler/generated/reference.md
```

If the operation changes output rendering, add an output-contract test near the
CLI output module rather than proving it through a full compile.

## Choosing The Smallest Proof

Prefer tests that prove the owning contract directly:

| Contract | Small proof |
| --- | --- |
| Parser row exists | parser/HIR assertion or smallest compile that exposes that row |
| Type rejection maps to source | one source string that triggers the status and checks diagnostic code/label |
| Backend lowering accepts a shape | one source string that reaches backend output/status |
| Source-pack scheduling invariant | small library graph with exact expected jobs/waves/batches |
| Work queue transition | in-memory progress page model with claim/complete/dependency steps |
| CLI output behavior | output module test with fake bytes or writer failure |

Large generated workloads and benchmark fixtures are second-line evidence. They
are useful for performance and integration regressions after the small proof
has already established the behavior contract.
