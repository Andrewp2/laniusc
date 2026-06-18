# Compiler Authoring Guide

This guide is for common changes to the compiler. It assumes the reader has the
data-flow and algorithm documents open.

For concrete end-to-end examples of how the checklist items fit together, see
[Compiler change walkthroughs](change-walkthroughs.md).

## First Question: Which Phase Owns The Data?

Before editing, identify the earliest phase that has enough information to own
the new fact.

| Change | Likely owner |
| --- | --- |
| new token spelling or lexical class | `lexer/tables` plus lexer shaders if GPU behavior changes |
| new syntax form | parser tables, parser token frontend, parser HIR passes |
| new HIR field for existing syntax | parser HIR record passes and retained buffer wrappers |
| name/module/import behavior | `type_checker/module_path` and `shaders/type_checker/modules` |
| type ref, generic arg, member, struct-init, or aggregate behavior | type-instance passes |
| function call behavior | call passes, then method/module value-call consumers if relevant |
| method lookup/receiver behavior | method key/call resolution and type-instance member passes |
| trait or predicate behavior | predicate passes and predicate status mapping |
| x86 lowering | x86 backend plus retained parser/type-check metadata |
| source-pack scheduling | `codegen::unit` planning or `compiler` worker/executor APIs |

Do not solve a later phase problem by smuggling policy into an earlier phase.
For example, the parser should emit enough HIR to describe a construct; module
visibility, type identity, and call resolution belong to type checking.

## Adding Syntax

Checklist:

1. update grammar/table generation inputs
2. regenerate parse tables if required
3. add parser token frontend context only if raw tokens need additional
   structural classification
4. add HIR record fields or node kind constants
5. add parser HIR passes that populate the new rows
6. retain the new parser buffers in `OwnedTypecheckParserBuffers` or
   `OwnedX86ParserBuffers` only if later phases need them
7. add type-check passes that consume the new rows
8. update diagnostics for syntax/type errors
9. add focused tests at the smallest boundary that proves the behavior

If later codegen needs the new syntax, retain data intentionally. Do not rely on
parser resident buffers remaining available after `release_current_resident_buffers`.

## Adding A Type-Checker Relation

Checklist:

1. define the row/key/status layout in Rust and Slang
2. allocate or intentionally reuse storage in `type_checker::bind_groups`
3. create bind group resources using stable shader parameter names
4. add pass loading in `type_checker::pass_loaders`
5. record the pass in `resident.rs` at the phase where all inputs are ready and
   before any scratch input is reused
6. expose retained data only through codegen buffer structs when a backend needs
   it
7. map status failures to `GpuTypeCheckCode` and then compiler diagnostics

Pay close attention to the resident cache key. If a pass depends on a buffer
identity or capacity that is not already fingerprinted, update the cache key or
resident state can silently reuse invalid bind groups.

## Adding A Shader Pass

Checklist:

1. put the `.slang` file under the owning phase in `shaders/`
2. import shared helpers explicitly
3. include a compute entry point only if the file should compile to an artifact
4. add a Rust pass wrapper or loader using the shader key without extension
5. bind resources by the names reflected from Slang
6. size dispatch from the owning capacity or an indirect dispatch buffer
7. add the pass to the recorder in dependency order
8. add or update a focused test that exercises the pass through the owning Rust
   boundary

Avoid broad dynamic loops in shaders. Prefer count, scan, radix, range-query,
scatter, or fixed repeated projection passes. If a fixed repeated projection is
used, document what converges and what source shape would exceed it.

## Adding Backend Support

Checklist:

1. identify whether parser HIR or type-check metadata is the source of truth
2. retain any parser buffers before the parser resident cache is released
3. expose any type-check metadata through `GpuCodegenBuffers` or
   `GpuX86CodegenBuffers`
4. measure active backend features if capacity depends on source shape
5. record backend passes after type-check status succeeds
6. map backend status to diagnostics using token/file data retained for that
   purpose

Backend code should not rerun semantic decisions already made by type checking.
It should consume resolved declarations, type refs, call metadata, and status
rows.

## Diagnostics

GPU phases generally report compact status words. Host Rust is responsible for
mapping them into user-facing diagnostics.

For the full diagnostic registry, source-mapping, renderer, explain-command,
and test-evidence contract, see [Compiler diagnostics and status](diagnostics.md).

When adding an error:

1. write a status code that identifies the semantic class
2. include a token, HIR node, path id, or row id that can be mapped back to
   source
3. add a `GpuTypeCheckCode` or backend status name
4. map it to a stable diagnostic code and message
5. include a primary label at the source location most indicative of the problem

Do not emit only a capacity or row id if the compiler can cheaply preserve the
source token that caused the error.

## Scratch Reuse

Scratch reuse is intentional but dangerous. The compiler often reuses buffers
from earlier phases once their data is dead. Existing examples are documented in
comments around `typecheck_external_scratch_from_frontend_buffers` and
`x86_external_scratch_from_frontend_buffers`.

Rules:

- never reuse source bytes, token rows, or HIR rows while diagnostics or later
  phases still need them
- document why each reused buffer is dead at that phase boundary
- include the reused buffer in resident-state fingerprinting if bind groups
  depend on its identity
- prefer a new typed buffer over clever reuse when lifetime is not obvious

## Tests

Use the smallest test that proves the behavior:

- lexer behavior: lexer table/unit test or focused lexer integration test
- parser HIR row behavior: parser/HIR focused test
- type-check semantic behavior: type-check integration test
- backend lowering: backend-specific compile test
- source-pack behavior: source-pack/package test

Generated large workloads are useful for performance/regression checks, but they
are a poor first proof for a semantic change.

## Useful Commands

```bash
tools/repo_map.py
tools/repo_map.py --svg /tmp/laniusc-repo-map.svg --png /tmp/laniusc-repo-map.png
tools/compiler_inventory.py --output docs/compiler/generated/reference.md
tools/compiler_inventory.py --check docs/compiler/generated/reference.md
cargo check -p laniusc-compiler
cargo test -p laniusc-compiler <focused_test_name>
```

Environment flags useful while debugging:

```bash
LANIUS_GPU_COMPILE_HOST_TIMING=1
LANIUS_GPU_TIMING=1
LANIUS_PIPELINE_TRACE=1
LANIUS_GPU_PIPELINE_PROGRESS=1
LANIUS_VALIDATION_SCOPES=1
LANIUS_READBACK=1
```

## Documentation Freshness

Regenerate the compiler reference when a change affects any generated inventory:

- public compile/check/planning/execution operation functions
- Rust shader load literals
- Slang imports or shader entry points
- type-check pass loader fields
- type-check record sites
- retained parser/type-check/codegen buffer structs
- GPU status code layouts
- large compiler structs that compiler authors are likely to edit

Run the `--check` command after regeneration. If it fails, the checked-in
reference does not match the current code.
