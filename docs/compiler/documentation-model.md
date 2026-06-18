# Compiler Documentation Model

The compiler docs should work like a small version of the rustc documentation
stack: narrative guides explain how to think, generated references expose the
current shape of the code, API docs describe callable items, and tests/profiling
commands prove behavior.

## Layers

| Layer | Local source | Purpose |
| --- | --- | --- |
| Compiler guide | `docs/compiler/*.md` | Explain ownership, data flow, algorithms, invariants, and change workflow. |
| Getting started | `docs/getting-started.md` | Give source-checkout users the shortest honest path through version, doctor, check, format, bounded native compile, source-root, stdlib-root, and diagnostics commands. |
| Compiler invocation | `docs/invocation.md` | Explain user-facing `laniusc` commands, input modes, targets, output, diagnostics, formatter, package, LSP, and source-pack workflows. |
| Tooling and editor integration | `docs/tooling.md` | Explain user-facing formatter, diagnostics metadata, doctor, LSP, no-run metadata, wrapper, and CI contracts. |
| Targets and output | `docs/targets.md` | Explain user-facing target selectors, triples, x86_64 and WASM boundaries, check mode, target bytes, descriptor output, and runtime boundaries. |
| Packages and source roots | `docs/packages.md` | Explain user-facing source-root, stdlib-root, manifest, lockfile, import metadata, package diagnostics, and evidence boundaries. |
| Lexical structure | `docs/language/lexical-structure.md` | Explain user-facing token, literal, keyword, comment, and lexer/parser retag boundaries. |
| Syntax reference | `docs/language/syntax.md` | Explain user-facing syntax families, examples, operator grouping, and grammar/support boundaries. |
| Items and declarations | `docs/language/items-and-declarations.md` | Explain user-facing item families, module metadata, imports, functions, externs, constants, aliases, structs, enums, traits, impls, visibility, namespaces, and support boundaries. |
| Functions and calls | `docs/language/functions-and-calls.md` | Explain user-facing function signatures, parameters, arguments, direct calls, qualified calls, generic calls, constructor calls, method calls, extern/runtime boundaries, and call ABI notes. |
| Name resolution | `docs/language/name-resolution.md` | Explain user-facing local, generic, module, import, visibility, qualified path, enum variant, field, method, ambiguity, and diagnostic lookup rules. |
| Generics and bounds | `docs/language/generics-and-bounds.md` | Explain user-facing generic parameters, type arguments, const parameters, trait bounds, where clauses, generic calls, generic enums, aliases, methods, impls, and fail-closed boundaries. |
| Traits and impls | `docs/language/traits-and-impls.md` | Explain user-facing trait declarations, inherent impls, trait impl contracts, visibility agreement, method lookup, dispatch boundaries, obligations, and diagnostics. |
| Types and values | `docs/language/types-and-values.md` | Explain user-facing type/value semantics, primitive names, aliases, constants, generics, aggregates, traits, arrays, runtime-backed declarations, and backend boundaries. |
| Aggregates and indexing | `docs/language/aggregates-and-indexing.md` | Explain user-facing structs, enums, arrays, slices, literals, constructors, field access, indexing, copies, assignments, and aggregate backend boundaries. |
| Literals and operators | `docs/language/literals-and-operators.md` | Explain user-facing literal families, operator precedence, unary, binary, assignment, division, modulo, logical operators, diagnostics, and target execution notes. |
| Expressions and control flow | `docs/language/expressions-and-control-flow.md` | Explain user-facing statements, expressions, operators, returns, loops, matches, calls, indexing, literals, and target execution boundaries. |
| Patterns and matching | `docs/language/patterns-and-matching.md` | Explain user-facing match expressions, path patterns, tuple-payload patterns, literal patterns, binding scope, exhaustiveness, and backend boundaries. |
| Modules and imports | `docs/language/modules-and-imports.md` | Explain user-facing module identity, import loading, source-root, stdlib-root, package manifest, and lockfile rules. |
| Worked examples | `docs/language/examples.md` | Show copyable single-file, source-root, stdlib-root, package, diagnostics, and formatter examples while naming their evidence boundaries. |
| Standard library overview | `docs/stdlib/README.md` | Explain user-facing stdlib loading, module families, frontend evidence, runtime-bound APIs, target execution boundaries, and update policy. |
| Build/run guide | `building.md` | Explain local prerequisites, build targets, generated artifacts, and command routing. |
| Maintainer tools | `maintainer-tools.md` | Explain generated inputs, developer probes, fuzzers, benchmarks, acceptance scripts, audits, generated references, repo maps, and tool evidence policy. |
| Source tour | `source-tour.md` | Show stable source ownership zones and route navigation to generated maps/reference. |
| Conventions | `conventions.md` | State cross-cutting coding, documentation, compatibility, naming, and review defaults. |
| Generated reference | `docs/compiler/generated/reference.md` | List volatile facts extracted from Rust and Slang sources, including the stable diagnostic-code index. |
| Generated language slice | `docs/language/generated/unstable-alpha-slice.md` | List current public language/tooling slice rows extracted from the machine-readable TSV inventory. |
| Diagnostics guide | `docs/diagnostics/README.md` | Explain how users read diagnostic codes, labels, text/JSON/LSP formats, explanations, no-run metadata, and fail-closed boundaries. |
| Diagnostic code explanations | `docs/diagnostics/code-explanations.md` | Explain each stable `LNC####` code with user-facing meaning, likely causes, source-label expectations, and next actions. |
| Generated diagnostic index | `docs/diagnostics/generated/error-index.md` | List current public diagnostic codes, unsupported-feature explanations, and fail-closed codegen boundaries extracted from the registry. |
| Generated stdlib reference | `docs/stdlib/generated/reference.md` | List current source-level stdlib modules, imports, declarations, externs, and runtime-binding flags extracted from `.lani` files. |
| Relationship map | `tools/repo_map.py` output | Show coupling between Rust areas, shader groups, tests, and large directories. |
| API docs and Rustdoc | `api-docs.md` | Explain item-level API documentation expectations, generated coverage, and Rustdoc evidence. |
| Rust API docs | `cargo doc -p laniusc-compiler --no-deps --document-private-items` | Show item-level signatures and Rustdoc comments from the current code. |
| User and CLI docs | root `README.md`, `docs/invocation.md`, `docs/language/README.md`, `docs/DIAGNOSTICS.md`, CLI help | Explain user-facing language, commands, diagnostics, and contracts. |
| Design/history docs | existing phase plans under `docs/` | Preserve rationale, rejected approaches, and broader implementation plans. |
| Debugging and observability | `debugging.md`, trace/timing/readback flags, generated reference | Find the owning boundary for failures before broad tests or expensive readback. |
| Tests and benchmarks | `testing.md`, focused tests, `gpu_compile_bench`, shader-loop audits | Prove compiler behavior and performance claims. |
| Appendices | `glossary.md` | Define shared compiler vocabulary without duplicating volatile inventories. |

No single layer is enough. A compiler author should be able to start from the
guide, jump to generated reference tables for exact current names and files,
then use Rust API docs or source for item-level details.

## Freshness Rules

Generated material must be reproducible without human editing:

```bash
tools/docs_check.py
tools/compiler_inventory.py --output docs/compiler/generated/reference.md
tools/compiler_inventory.py --check docs/compiler/generated/reference.md
tools/language_slice_summary.py --output docs/language/generated/unstable-alpha-slice.md
tools/language_slice_summary.py --check docs/language/generated/unstable-alpha-slice.md
tools/diagnostic_index.py --output docs/diagnostics/generated/error-index.md
tools/diagnostic_index.py --check docs/diagnostics/generated/error-index.md
tools/stdlib_inventory.py --output docs/stdlib/generated/reference.md
tools/stdlib_inventory.py --check docs/stdlib/generated/reference.md
tools/repo_map.py --output /tmp/laniusc-repo-map.md
```

`tools/docs_check.py` is the default maintained-docs gate. It runs the generated
reference freshness checks and basic local Markdown hygiene for the maintained
documentation stack, including local link targets and heading anchors, while
intentionally excluding imported paper text.

The generated compiler reference owns facts that are expected to move often:

- public compiler operation entry points
- stable diagnostic code registry rows
- shader groups, imports, and Rust load sites
- type-check pass loader fields and record sites
- public/crate-public Rustdoc coverage
- buffer carrier structs and large struct edit surfaces
- GPU type-check, parser LL, x86 backend, and WASM backend status-code layouts

Hand-written docs should not duplicate those tables unless they are explaining
why the table matters. If a hand-written sentence names a volatile field, pass,
or status code, it should point to the generated reference or be narrow enough
that a compiler author can verify it quickly.

## Quality Bar

A compiler-internals doc is good enough only if it answers these questions:

1. What phase owns this data or decision?
2. What buffers or records carry it across phase boundaries?
3. What shader or Rust pass produces it?
4. What status path reports errors from it?
5. What source location should a user see if it fails?
6. What test, benchmark, or generated reference check proves the doc is still
   true?

When a doc cannot answer a question yet, say that directly. Do not leave prose
that sounds authoritative while relying on guesses.

## Current Coverage

The current compiler docs now cover the main guide and generated-reference
layers:

- `README.md` is the entry point and update policy.
- `docs/getting-started.md` gives source-checkout users the shortest honest
  first-run path through no-run metadata, sample checking, formatting, bounded
  native compilation, source roots, stdlib roots, and diagnostics.
- `docs/invocation.md` explains user-facing `laniusc` commands, input modes,
  targets, output, diagnostics, formatter, package lockfiles, LSP commands, and
  source-pack workflow boundaries.
- `docs/tooling.md` explains user-facing formatter, diagnostics metadata,
  doctor, LSP capability/server, no-run metadata, wrapper, and CI contracts.
- `docs/targets.md` explains user-facing target selection, target triples,
  x86_64 and WASM support boundaries, check mode, target bytes, descriptor
  output, and runtime-bound stdlib output boundaries.
- `docs/packages.md` explains user-facing source-root, stdlib-root, package
  manifest, lockfile, import metadata, package diagnostics, and evidence
  boundaries.
- `docs/language/lexical-structure.md` explains source tokens, comments,
  literals, keywords, punctuation, and lexer/parser retag boundaries.
- `docs/language/syntax.md` explains user-facing syntax forms, examples,
  operator grouping, and the boundary between parser acceptance and support
  evidence.
- `docs/language/items-and-declarations.md` explains user-facing item families,
  module metadata, imports, functions, externs, constants, aliases, structs,
  enums, traits, impls, visibility, namespaces, and support boundaries.
- `docs/language/functions-and-calls.md` explains user-facing function
  signatures, parameters, arguments, direct calls, qualified calls, generic
  calls, constructor calls, method calls, extern/runtime boundaries, and call
  ABI notes.
- `docs/language/name-resolution.md` explains user-facing local, generic,
  module, import, visibility, qualified path, enum variant, field, method,
  ambiguity, and diagnostic lookup rules.
- `docs/language/generics-and-bounds.md` explains user-facing generic
  parameters, type arguments, const parameters, trait bounds, where clauses,
  generic calls, generic enums, aliases, methods, impls, and fail-closed
  boundaries.
- `docs/language/traits-and-impls.md` explains user-facing trait declarations,
  inherent impls, trait impl contracts, visibility agreement, method lookup,
  dispatch boundaries, obligations, and diagnostics.
- `docs/language/types-and-values.md` explains user-facing type/value
  semantics, primitive names, aliases, constants, generics, aggregates, traits,
  arrays, runtime-backed declarations, and backend boundaries.
- `docs/language/aggregates-and-indexing.md` explains user-facing structs,
  enums, arrays, slices, literals, constructors, field access, indexing, copies,
  assignments, and aggregate backend boundaries.
- `docs/language/literals-and-operators.md` explains user-facing literal
  families, operator precedence, unary, binary, assignment, division, modulo,
  logical operators, diagnostics, and target execution notes.
- `docs/language/expressions-and-control-flow.md` explains user-facing
  statements, expressions, operators, returns, loops, matches, calls, indexing,
  literals, and target execution boundaries.
- `docs/language/patterns-and-matching.md` explains user-facing match
  expressions, path patterns, tuple-payload patterns, literal patterns, binding
  scope, exhaustiveness, and backend boundaries.
- `docs/language/modules-and-imports.md` explains module declarations, imports,
  source roots, stdlib roots, visibility, package manifests, and lockfile
  replay from the user-facing language side.
- `docs/language/examples.md` shows copyable single-file, source-root,
  stdlib-root, package, diagnostics, and formatter examples without promoting
  smoke fixtures into broad conformance, backend, or performance evidence.
- `docs/diagnostics/README.md` explains how users read diagnostic codes,
  labels, text/JSON/LSP formats, explanations, no-run metadata, and
  fail-closed boundaries.
- `docs/diagnostics/code-explanations.md` explains each stable `LNC####` code
  with user-facing meaning, likely causes, source-label expectations, and next
  actions.
- `docs/stdlib/README.md` explains user-facing stdlib loading, module families,
  frontend evidence, runtime-bound APIs, target execution boundaries, and
  update policy.
- `building.md` explains local build prerequisites, workspace targets, shader
  artifacts, checked-in generated tables, CLI runs, Rustdoc, and acceptance
  scaffolds.
- `maintainer-tools.md` explains checked-in generators, developer
  probes/fuzzers, benchmark scaffolds, acceptance scripts, shader-loop audits,
  generated references, repo maps, and what each tool result can prove.
- `grammar-and-tables.md` explains the token namespace, grammar source file,
  lexer/parser table contracts, parse-table metadata, production IDs,
  shader-facing generated constants, and evidence expected after token or syntax
  changes.
- `source-tour.md` explains workspace roots, compiler crate ownership zones,
  shader roots, tests/tools, generated-file boundaries, and navigation routes.
- `conventions.md` records cross-cutting compiler defaults for ownership,
  compatibility, diagnostics, buffer lifetimes, shaders, source-pack
  persistence, generated facts, tests, docs, naming, and review.
- `architecture.md` explains compiler ownership boundaries, lifecycle, resident
  state rules, diagnostics ownership, source-pack graph placement, and edit
  routing.
- `data-flow.md` explains phase boundaries and resident buffer lifetimes.
- `capacity-and-limits.md` explains how capacities, row strides, dispatch
  shapes, source-pack chunks, and user-visible language limits differ, and how
  exhaustion must be diagnosed or removed.
- `gpu-passes.md` explains shader artifact production and freshness, runtime
  artifact lookup, pass construction, reflection, bind-group contracts,
  dispatch planning, batching, failure modes, and pass authoring rules.
- `gpu.md` explains reusable GPU infrastructure: device lifecycle, backend
  selection, pipeline cache identity/pruning, typed buffers, pass construction,
  reflection-driven bind groups, dispatch planning, batching, submission,
  readback, timers, tracing, environment flags, and infrastructure failure
  modes.
- `shader-abi.md` explains the shader artifact/reflection ABI: artifact keys,
  build freshness, debug/runtime lookup, reflection parsing, binding-type
  conversion, dynamic offsets, reflected bind groups, metadata surfaces, and
  shader ABI change rules.
- `cli.md` explains command parsing, compile/check mode selection,
  diagnostic-format selection, output contracts, source-pack CLI modes, package
  tooling, diagnostics metadata, doctor, formatter, and LSP behavior.
- `formatter.md` explains the lexical formatting contract, token preservation,
  layout state, CLI file/stdin/check modes, LSP formatting reuse, diagnostics,
  no-run metadata, and formatter test evidence.
- `lsp.md` explains LSP capability metadata, stdio JSON-RPC framing, lifecycle
  rules, open-document state, formatting, pull diagnostics, error-data
  boundaries, no-run guards, and LSP test evidence.
- `public-api.md` explains the Rust compiler API surface below the CLI:
  `CompileError`, `GpuCompiler` construction and methods, process-global
  helpers, planning/execution APIs, descriptor workers, executor traits,
  benchmarks, and public API evidence.
- `api-docs.md` explains item-level API documentation: Rustdoc build commands,
  generated coverage, visibility contracts, module comments, public API
  Rustdoc, and evidence for API documentation changes.
- `compiler-orchestration.md` explains the live `GpuCompiler` driver layer:
  instance shape, backend selection, resident pipeline locking, retained buffer
  wrappers, target-specific compile flow, descriptor workers, timing hooks, and
  orchestration evidence.
- `module-resolution.md` explains source-root/package loading, parser
  module/import HIR, type-checker module-path state, resolved path consumers,
  diagnostics, and compatibility boundaries for module-like behavior.
- `package-metadata.md` explains package manifest resolution, package lockfile
  replay evidence, input/source/import graph validation, leading import
  scanning, artifact evidence, and package CLI tooling.
- `standard-library.md` explains the source-level `stdlib/` contract, explicit
  stdlib-root loading, user/stdlib boundaries, generated declaration inventory,
  current core and runtime-service seeds, evidence classes, and stdlib
  authoring rules.
- `lexer.md` explains lexer ownership, public entry-point choices, compact DFA
  table loading, token record contracts, source-pack file identity, resident
  lifetimes, readback/debug paths, pass order, token-authoring rules, and lexer
  performance boundaries.
- `parser.md` explains parser entry points, token facts, parse tables,
  resident buffers, tree/HIR construction, source-file identity, retained
  parser rows, parser status, and syntax-authoring rules.
- `parser-readback.md` explains parser staging buffers, decoded readback
  surfaces, live row-capacity checks, parser-owned HIR validators, and readback
  authoring rules.
- `algorithms.md` explains the major compiler algorithms and reusable GPU
  patterns.
- `type-checker.md` explains resident type-check entry points, cache-key reuse,
  buffer ownership, pass families, status diagnostics, backend metadata handoff,
  performance bounds, and relation-authoring invariants.
- `codegen.md` explains backend entry points, source-pack unit planning,
  x86_64 capacity/status contracts, WASM fail-closed boundaries, diagnostics,
  and backend authoring rules.
- `x86-backend.md` explains x86 compile orchestration, retained frontend inputs,
  feature/capacity planning, recording pass families, status readback,
  diagnostics, bounded contracts, and x86 authoring rules.
- `wasm-backend.md` explains WASM compile orchestration, retained parser and
  type-check inputs, metadata groups, resident buffer reuse, recording stages,
  status/output readback, diagnostics, source-pack behavior, and WASM authoring
  rules.
- `artifact-descriptors.md` explains source-pack artifact descriptor JSON,
  stage/domain/kind/flow contracts, record-array validation, runtime-service
  requirements, target-byte policy, descriptor executor behavior, CLI
  `--emit-contract` gating, and descriptor change rules.
- `source-packs.md` explains source-pack ownership, source tree boundaries,
  public API families, in-memory and path-backed identity, artifact target
  namespaces, persisted preparation stages, store/path contracts, artifact
  shards, hierarchical link planning, work-queue leases/progress, descriptor
  execution, validation failures, and source-pack record change rules.
- `diagnostics.md` explains GPU status transport, stable diagnostic registry
  rows, source-span mapping, output renderers, no-run explanation commands, LSP
  payloads, unsupported/fail-closed boundary metadata, and diagnostic evidence.
- `debugging.md` explains the maintainer workflow for choosing diagnostics,
  generated inventories, host timing, traces, validation scopes, timers,
  readback, and performance artifacts.
- `authoring-guide.md` gives change checklists and diagnostic rules.
- `change-walkthroughs.md` gives worked examples for common compiler changes,
  including diagnostics, HIR data, shader passes, backend lowering,
  source-pack persisted records, and public operation changes.
- `testing.md` explains compiler-specific executable documentation: test lanes,
  phase-specific proof shapes, generated-reference checks, source-pack models,
  diagnostics assertions, and performance evidence boundaries.
- `glossary.md` defines shared compiler terms such as resident state, retained
  buffers, HIR, status, artifacts, source packs, work queues, and readback.
- `generated/reference.md` lists the current extracted operation entry points,
  stable diagnostic codes, Rustdoc coverage, shader/pass/buffer/status
  inventories, and generated health checks.

The remaining gap versus rustc-style docs is continued subsystem depth below the
current guide chapters and more worked examples for changing compiler behavior.
Use `cargo doc -p laniusc-compiler --no-deps --document-private-items` when you
need the API view, add Rustdoc comments at the ownership boundary being changed,
and prefer new subsystem chapters when a compiler area has enough invariants
that a future maintainer should not have to rediscover them from pass order
alone.
