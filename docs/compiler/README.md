# Compiler Internals

This directory is for compiler authors. It documents how data moves through the
current compiler, which algorithms own each phase, and which Rust/shader
boundaries matter when adding a feature.

The public language and tool state is documented elsewhere. Start at
[Lanius Documentation](../README.md) for the maintained user-facing stack:
language reference, invocation, packages, targets, tooling, diagnostics,
stdlib, generated references, and production-readiness notes. In particular,
use [Language reference](../language/README.md),
[Name resolution](../language/name-resolution.md),
[Diagnostics guide](../diagnostics/README.md), and the generated
[unstable-alpha slice](../language/generated/unstable-alpha-slice.md) before
changing behavior that users can observe.

These compiler notes are allowed to be implementation-specific and should be
updated when compiler ownership, buffer lifetimes, shader pass order, or
diagnostics change.

## Map

Start here:

- [Building and running the compiler](building.md): local prerequisites,
  workspace targets, shader artifacts, generated tables, CLI runs, Rustdoc, and
  acceptance/measurement scaffolds.
- [Maintainer tools and generated inputs](maintainer-tools.md): checked-in
  table generators, developer probes/fuzzers, benchmark scaffolds, acceptance
  scripts, shader-loop audits, generated references, repo maps, and evidence
  policy for tool output.
- [Grammar and generated tables](grammar-and-tables.md): token IDs, grammar
  source rules, lexer/parser table formats, parse-table metadata, production
  IDs, shader-facing constants, and evidence for token or syntax changes.
- [Compiler source tour](source-tour.md): workspace roots, compiler crate
  ownership zones, shader roots, tests/tools, generated files, and navigation
  checklist.
- [Compiler conventions](conventions.md): cross-cutting rules for ownership,
  compatibility, diagnostics, buffers, shaders, persistence, generated facts,
  tests, docs, and naming.
- [Compiler architecture](architecture.md): ownership boundaries, phase
  lifecycle, resident-state rules, diagnostics ownership, and change routing.
- [Data flow](data-flow.md): end-to-end control flow, resident buffers, and phase
  boundaries.
- [Capacity and limits](capacity-and-limits.md): how to distinguish storage,
  dispatch, chunking, API, and language limits; how exhaustion should become a
  source-addressed diagnostic; and how to remove accidental bounds.
- [GPU passes and shader artifacts](gpu-passes.md): shader artifact production
  and freshness, runtime artifact lookup, pass construction, reflection,
  bind-group contracts, dispatch planning, batching, failure modes, and pass
  authoring rules.
- [GPU infrastructure](gpu.md): device lifecycle, backend selection, pipeline
  cache identity/pruning, typed buffers, pass construction, reflection-driven
  bind groups, dispatch planning, batching, submission/readback, timers,
  tracing, environment flags, and infrastructure failure modes.
- [Shader artifact and reflection ABI](shader-abi.md): artifact keys, shader
  freshness, debug/runtime lookup, reflection parsing, binding-type conversion,
  dynamic offsets, reflected bind groups, and shader ABI change rules.
- [CLI and tooling surface](cli.md): command parsing, compile/check modes,
  diagnostic-format selection, output contracts, source-pack CLI modes,
  package tooling, diagnostics metadata, doctor, formatter, and LSP behavior.
- [Formatter internals](formatter.md): lexical formatting contract, token
  preservation, layout state, CLI file/stdin/check modes, LSP formatting reuse,
  diagnostics, no-run metadata, and formatter test evidence.
- [LSP surface internals](lsp.md): LSP capability metadata, stdio JSON-RPC
  framing, lifecycle rules, open-document state, formatting, pull diagnostics,
  error-data boundaries, no-run guards, and LSP test evidence.
- [Public compiler API](public-api.md): Rust call surfaces below the CLI,
  `GpuCompiler` construction and methods, process-global helpers, planning and
  execution API families, descriptor workers, and API evidence rules.
- [API docs and Rustdoc](api-docs.md): item-level API documentation, Rustdoc
  build command, generated coverage heuristics, visibility contracts, and
  evidence for public or crate-public Rust items.
- [Compiler orchestration](compiler-orchestration.md): `GpuCompiler` instance
  shape, backend selection, resident pipeline locking, retained buffer
  wrappers, target-specific compile flow, descriptor workers, timing, and
  orchestration test evidence.
- [Module and source-root resolution](module-resolution.md): source-root and
  package loading, parser module/import HIR, type-checker module-path state,
  diagnostics, compatibility policy, and source-pack identity boundaries.
- [Package metadata and lockfiles](package-metadata.md): package manifest
  resolution, lockfile replay evidence, input/source/import graph validation,
  leading import scanning, artifact evidence, and `laniusc package lock`.
- [Source-level standard library](standard-library.md): `stdlib/` layout,
  explicit `--stdlib-root` loading, user/stdlib source boundaries, current core
  and runtime-service contracts, evidence classes, and stdlib authoring rules.
- [Lexer](lexer.md): lexer ownership, entry-point choices, compact DFA tables,
  token record contracts, source-pack file identity, resident lifetimes,
  readback/debug paths, pass order, and token-authoring rules.
- [Parser and HIR](parser.md): parser entry points, token facts, parse tables,
  resident buffers, tree/HIR construction, source-file identity, retained
  parser rows, status mapping, and syntax-authoring rules.
- [Parser readback and HIR validators](parser-readback.md): parser staging
  buffers, decoded readback surfaces, live row-capacity checks, parser-owned
  HIR validators, and readback authoring rules.
- [Algorithms](algorithms.md): the current lexer, parser, type-checker, module,
  generic, call, and backend algorithms at the level needed to change them.
- [Resident type checker](type-checker.md): the type-check entry points,
  resident cache, buffer ownership, pass families, status contract, backend
  metadata handoff, performance bounds, and relation-authoring invariants.
- [Codegen and backends](codegen.md): backend entry points, source-pack unit
  planning, x86_64 capacity/status contracts, WASM fail-closed boundaries,
  diagnostics, and backend authoring rules.
- [x86 backend internals](x86-backend.md): x86 compile orchestration, retained
  frontend inputs, feature/capacity planning, recording pass families, status
  readback, diagnostics, bounded contracts, and x86 authoring rules.
- [WASM backend internals](wasm-backend.md): WASM compile orchestration,
  retained parser/type-check inputs, metadata groups, resident buffer reuse,
  recording stages, status/output readback, diagnostics, source-pack behavior,
  and WASM authoring rules.
- [Artifact descriptors and output contracts](artifact-descriptors.md):
  descriptor JSON schema, stage/domain/kind/flow contracts, runtime-service
  requirements, target-byte policy, descriptor executor behavior, CLI
  `--emit-contract` gating, and descriptor validation rules.
- [Source packs, artifacts, and work queues](source-packs.md): source-pack
  ownership boundaries, public API families, input and target identity,
  persisted preparation stages, store/path contracts, artifact shards,
  hierarchical link planning, work-queue leases/progress, descriptor execution,
  and source-pack record change rules.
- [Diagnostics and status](diagnostics.md): GPU status transport, stable
  diagnostic registry rows, source-span mapping, renderers, no-run explanation
  commands, LSP payloads, and diagnostic test evidence.
- [Compiler debugging and observability](debugging.md): maintainer debugging
  order, signal cost, environment flags, phase triage, and performance evidence.
- [Authoring guide](authoring-guide.md): where to make common compiler changes
  and which invariants to preserve.
- [Compiler change walkthroughs](change-walkthroughs.md): worked examples for
  diagnostics, HIR data, shader passes, x86 lowering, source-pack records, and
  public operation changes.
- [Compiler testing and verification](testing.md): executable-documentation
  expectations, test lanes, phase-specific proof shapes, and performance
  evidence boundaries.
- [Documentation model](documentation-model.md): how these notes, generated
  references, API docs, and tests fit together.
- [Compiler glossary](glossary.md): shared terminology for resident state,
  HIR, status, artifacts, source packs, work queues, and GPU infrastructure.
- [Generated compiler reference](generated/reference.md): extracted tables for
  public compiler operations, shader load sites, type-check pass loaders,
  type-check record sites, Rustdoc coverage, buffer carrier structs, large
  structs, stable diagnostic codes, and status codes.

For an auto-updating relationship view, run:

```bash
tools/repo_map.py
tools/repo_map.py --svg /tmp/laniusc-repo-map.svg --png /tmp/laniusc-repo-map.png
```

The generated map is derived from Rust `crate::...` references, shader ownership
literals, Slang `import` lines, test names, and current file layout. Use it to
spot coupling and ownership changes; do not edit generated output by hand.

For generated compiler reference tables, run:

```bash
tools/compiler_inventory.py --output docs/compiler/generated/reference.md
tools/compiler_inventory.py --check docs/compiler/generated/reference.md
tools/diagnostic_index.py --output docs/diagnostics/generated/error-index.md
tools/diagnostic_index.py --check docs/diagnostics/generated/error-index.md
tools/stdlib_inventory.py --output docs/stdlib/generated/reference.md
tools/stdlib_inventory.py --check docs/stdlib/generated/reference.md
```

The generated compiler reference is derived from Rust function signatures,
shader literals, Slang imports, diagnostic registry rows, type-check pass
loader calls, type-check record sites, Rustdoc coverage, buffer carrier
structs, and status-code definitions. The generated diagnostic index is derived
from the public diagnostic registry and fail-closed boundary metadata. The
generated stdlib reference is derived from `stdlib/**/*.lani` module imports
and public declarations.

## Current Shape

The active compiler lives under `crates/laniusc-compiler/src`.

| Area | Main responsibility |
| --- | --- |
| `cli` | Commands, argument validation, diagnostics formatting, package/source-pack loading. |
| `compiler` | Public compile/check APIs, source-pack planning/execution, and cross-phase orchestration; see [Public compiler API](public-api.md). |
| `lexer` | GPU lexing, resident token buffers, lexer table loading, and token readback. |
| `parser` | GPU LL/parser passes, token frontend normalization, tree/HIR construction, and parser diagnostics. |
| `type_checker` | GPU type checking, module/import resolution, name/type/call/method/predicate records, and retained codegen metadata. |
| `codegen` | WASM and x86_64 GPU backend recorders plus source-pack unit planning. |
| `gpu` | Device, buffer, pass, reflection, readback, scan, timing, and tracing infrastructure. |
| `reflection` | Slang reflection parsing and bind layout interpretation. |
| `shader_artifacts` | Runtime access to compiled shader SPIR-V/reflection artifacts. |

The shader source tree under `shaders/` mirrors compiler phases at a coarser
grain: `lexer`, `parser`, `type_checker`, `codegen`, plus shared helper modules
such as `prefix_scan`, `radix`, `scatter`, `range_query`, `status`, and
`gpu_index`.

## Update Rule

When changing compiler internals, update the relevant note in this directory if
the change affects any of the following:

- phase order or submission boundaries
- capacity, dispatch, row-stride, source-pack chunking, or user-visible limit
  behavior
- build scripts, generated tables, shader artifact generation, or local tool
  commands
- top-level source areas, directory ownership, or maintainer navigation paths
- cross-cutting conventions for ownership, compatibility, naming, status,
  generated facts, or review expectations
- ownership of buffers across lexer/parser/type-check/codegen
- status-buffer layout, diagnostic registry metadata, renderer payloads, or
  diagnostic mapping
- debugging, timing, trace, readback, or measurement flags
- shader artifact loading or reflection/bind-group behavior
- algorithms for parsing, module resolution, generic/type-instance handling,
  call/method resolution, or backend lowering
- source-root discovery, package replay, module/import HIR, or path-resolution
  consumer behavior
- artifact descriptor JSON schema, runtime-service requirements, target-byte
  policy, source-pack inputs, artifact targets, persisted preparation stages,
  work-queue progress, leases, artifact manifests, or descriptor execution
- shared terminology used across compiler-author docs
- generated-reference inputs such as public operation entry points, shader load
  sites, retained buffer wrappers, Rustdoc coverage, stable diagnostic registry
  rows, status-code layouts, public stdlib declarations, or large compiler
  structs

If a change affects generated-reference inputs, regenerate
`docs/compiler/generated/reference.md` and run the `--check` command before
considering the docs current.
