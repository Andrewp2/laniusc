# Compiler Source Tour

This tour helps compiler authors find the right source area before reading
individual files. It is not an inventory. Use `generated/reference.md`,
`tools/repo_map.py`, and Rustdoc for exact current names, counts, item
signatures, and coupling.

## Workspace Roots

| Path | Role |
| --- | --- |
| `src/main.rs` | Thin root binary that calls the compiler crate CLI entry point. |
| `crates/laniusc-compiler/src` | Main compiler library, CLI, GPU phases, source-pack planning, and compiler tools. |
| `crates/laniusc-shaders` | Cargo build script and runtime helpers for shader artifact generation. |
| `shaders` | Slang source for lexer, parser, type checker, codegen, and shared GPU helpers. |
| `grammar` | Parser grammar input used to regenerate parse tables. |
| `tables` | Checked-in generated lexer and parser table binaries/metadata. |
| `stdlib` | Source-level standard library contracts used by package/source-root paths; see [Source-level standard library](standard-library.md). |
| `tests` | Root integration tests for public CLI/compiler behavior and phase handoff contracts. |
| `tools` | Maintainer scripts for focused tests, generated references, repo maps, audits, and acceptance scaffolds; see [Maintainer tools and generated inputs](maintainer-tools.md). |
| `docs/compiler` | Compiler-author docs and generated compiler reference. |

The root crate is the command-line package. Most implementation work happens in
`crates/laniusc-compiler`. Shader artifacts are built by the shader crate and
then loaded by compiler infrastructure through artifact helpers.

## Compiler Crate

The active compiler source is organized by ownership boundary:

| Area | Start here for |
| --- | --- |
| `cli` | Command parsing, validation, diagnostics formatting, no-run metadata commands, LSP, formatter, package and source-pack CLI flags. |
| `compiler` | Public compile/check APIs, `GpuCompiler`, phase orchestration, diagnostic mapping, source-pack planning/execution APIs, and work-queue progress; see [Public compiler API](public-api.md) and [Compiler orchestration](compiler-orchestration.md). |
| `gpu` | Device creation, typed buffers, reflected pass construction, bind groups, dispatch planning, submission, readback, timing, tracing, and environment flags. |
| `reflection` | Slang reflection parsing and conversion into wgpu layout information; see [Shader artifact and reflection ABI](shader-abi.md). |
| `shader_artifacts` | Runtime paths and metadata for compiled shader artifacts; see [Shader artifact and reflection ABI](shader-abi.md). |
| `lexer` | Token kinds, compact DFA tables, GPU lexing passes, resident token buffers, and token readback. |
| `parser` | Parse tables, parser token facts, tree recovery, semantic HIR construction, resident parser buffers, and parser status/readback. |
| `type_checker` | Resident semantic relation pipeline: modules, names, paths, generics, calls, methods, predicates, visibility, and codegen metadata. |
| `codegen` | Source-pack unit planning plus x86/WASM backend recording and status/output finishing. |
| `dev` | Developer-only helpers that should not become public compiler contracts by accident. |
| `bin` | Maintainer tools such as lexer/table generation, parser demos/fuzzing, and `gpu_compile_bench`. |

Use the phase docs for intent and invariants. Use
[API docs and Rustdoc](api-docs.md) plus
`cargo doc -p laniusc-compiler --no-deps --document-private-items` when you
need item-level signatures, visibility contracts, and Rustdoc.
Use [Maintainer tools and generated inputs](maintainer-tools.md) before changing
table generators, fuzz/demo binaries, benchmark scaffolds, or repo tools.

## Compiler Orchestration

`compiler/gpu_compiler.rs` defines the main live compiler object. See
[Compiler orchestration](compiler-orchestration.md) for the instance lifecycle,
phase sequencing, retained buffers, backend dispatch, descriptor workers, and
timing hooks. Its submodules split operation families:

| Area | Role |
| --- | --- |
| `backends` | Backend initialization and availability. |
| `buffers` | Retained parser/type-check buffer wrappers that cross phase lifetimes. |
| `typecheck` | Type-check operation entry points and status mapping. |
| `x86_codegen` | x86 compile orchestration, retained metadata, backend status mapping, and output readback. |
| `wasm_codegen` | WASM backend boundary orchestration and fail-closed output mapping. |
| `source_pack_executor` | Execution of planned source-pack jobs through the compiler. |
| `descriptor_work_queue` | Persisted descriptor/work-queue worker entry points. |
| `host_timer` and `benchmarks` | Maintainer timing and benchmark-facing operation helpers. |

When a public operation behaves incorrectly, first identify whether the bug is
in command selection (`cli`), operation orchestration (`compiler`), phase-owned
records (`lexer`/`parser`/`type_checker`/`codegen`), or GPU infrastructure
(`gpu`). Avoid fixing an orchestration symptom when a phase boundary failed to
preserve the right source-mappable data.

## Frontend Source Areas

The frontend is split by data representation:

| Phase | Important subareas |
| --- | --- |
| Lexer | `tables`, `passes`, `driver`, `debug`, `readback` helpers. |
| Parser | `tables`, `buffers`, `driver`, `passes`, `hir_records`, `syntax`, `readback`. |
| Type checker | `pass_loaders`, `resident`, `record`, `bind_support`, `bind_groups`, `module_path`, `params`, `bind_models`. |

The lexer owns source bytes, token rows, token counts, and source-file token
metadata. The parser owns tree topology and HIR record arrays. The type checker
owns semantic relations and retained backend metadata.

Do not move semantic policy into parser code because parser passes are near a
syntax record. Do not reconstruct syntax in type-checker or backend code if the
parser should have published a HIR row. Do not borrow a resident buffer across a
phase release unless it is explicitly cloned into a retained wrapper.

## Backend And Source-Pack Areas

`codegen` has two responsibilities that should stay distinct:

| Area | Role |
| --- | --- |
| `codegen/unit` | Target-independent source-pack units, jobs, artifacts, schedules, shards, batches, and link plans. |
| `codegen/x86` | x86 feature measurement, backend record passes, bind groups, status/output buffers, and ELF finishing. |
| `codegen/wasm` | Current WASM backend boundary and fail-closed output paths. |

`compiler/source_pack` and `compiler/public_*_api` own persisted preparation,
filesystem stores, manifests, validation, work queues, execution handles, and
worker-facing APIs. If a change affects how work is split, claimed, resumed, or
linked, start in source-pack planning and validation. If it affects how one
already-checked unit lowers to target bytes, start in the backend.

## Standard Library Source

The `stdlib` tree is ordinary Lanius source. `--stdlib-root`, package
`stdlib_root`, and public `*_with_stdlib` APIs load module-path imports into an
explicit source pack before GPU parsing/type checking. See
[Source-level standard library](standard-library.md) for the current
source-level contract, runtime-service boundary, and stdlib test evidence.

## Shader Source

Shader roots mirror compiler phase ownership at a coarse level:

| Shader root | Owner |
| --- | --- |
| `shaders/lexer` | Lexer DFA, pair-scan, compaction, and token build passes. |
| `shaders/parser` | Parser token facts, LL streams, bracket/tree recovery, HIR rows, and generated parser constants. |
| `shaders/type_checker` | Semantic relation passes for modules, names, calls, methods, predicates, type refs, visibility, and control. |
| `shaders/codegen` | Backend lowering passes for x86 and WASM boundaries. |
| Shared helper roots | Prefix scans, radix/sort/scatter helpers, range queries, status helpers, fixed/sorted utilities, and generated token ids. |

A shader belongs under the phase that owns the data it mutates. Rust load sites
use shader keys without extension. Slang reflection supplies bind layouts, but
Rust and Slang still share the shader key and parameter-name contracts. After
changing shader paths, imports, entrypoints, or Rust load literals, regenerate
or check the generated compiler reference.

## Tests And Tools

Root integration tests under `tests` protect public behavior and phase handoff
contracts. Compiler crate tests under `crates/laniusc-compiler/src` protect
pure planning, serialization, model, and helper contracts close to their owners.
The detailed owner/evidence policy for maintainer tools lives in
[Maintainer tools and generated inputs](maintainer-tools.md).

Important tools:

| Tool | Use |
| --- | --- |
| `tools/focused_test.sh` | Run one exact Rust test through the narrowest owning Cargo target. |
| `tools/compiler_inventory.py` | Generate/check compiler reference tables from Rust and Slang sources. |
| `tools/repo_map.py` | Generate a relationship map from Rust references, shader load/import edges, tests, and file layout. |
| `tools/shader_loop_audit.sh` | Classify shader loop shapes for pass-contract review. |
| `tools/compiler_acceptance.sh` | Dry-run or execute tiered acceptance, readiness, generated, property, measurement, and Pareas scaffolds. |

Do not use source-inspection tests as evidence for behavior. If the important
fact is a current list of files, functions, shader load sites, status codes, or
large structs, put that fact in generated reference output instead of a brittle
test.

## Generated And Derived Files

Checked-in generated inputs:

| Output | Generator |
| --- | --- |
| `tables/lexer_tables.bin` | `cargo run -p laniusc-compiler --bin lex_gen_tables` |
| `shaders/generated_token_ids.slang` | `cargo run -p laniusc-compiler --bin lex_gen_tables` |
| `tables/parse_tables.bin` | `cargo run -p laniusc-compiler --bin parse_gen_tables` |
| `tables/parse_tables.meta.json` | `cargo run -p laniusc-compiler --bin parse_gen_tables` |
| `shaders/parser/generated_parse_production_ids.slang` | `cargo run -p laniusc-compiler --bin parse_gen_tables` |
| `docs/compiler/generated/reference.md` | `tools/compiler_inventory.py --output docs/compiler/generated/reference.md` |

Runtime build artifacts under `target/laniusc-shader-artifacts` are generated by
Cargo build scripts and should not be checked in. Relationship-map SVG/PNG
outputs should also be generated on demand unless there is a specific review
artifact reason to save them.
For token, grammar, parse-table, metadata, and production-id ownership, see
[Grammar and generated tables](grammar-and-tables.md).

## Navigation Checklist

Use this routing table before opening a random file:

| Question | First place to inspect |
| --- | --- |
| What command or flag owns this behavior? | `docs/compiler/cli.md`, then `crates/laniusc-compiler/src/cli`. |
| Which phase owns this data? | `architecture.md` and `data-flow.md`, then the phase guide. |
| Which shader or Rust owner loads this pass? | `generated/reference.md`, then `gpu-passes.md`. |
| Which buffers survive a phase boundary? | `architecture.md`, `data-flow.md`, and generated buffer carrier structs. |
| Is this number a storage capacity or a language limit? | `capacity-and-limits.md`, then the owning phase guide. |
| Why did a diagnostic point there? | `diagnostics.md`, `debugging.md`, and the owning phase status mapper. |
| How do I run a narrow proof? | `building.md` for command choice, `testing.md` for evidence shape. |
| Which token, grammar, or production-id source owns this generated fact? | `grammar-and-tables.md`, then `maintainer-tools.md` for generator commands. |
| Is this coupling expected? | `tools/repo_map.py` output plus the relevant phase docs. |
| Does this term mean a specific Lanius thing? | `glossary.md`. |

If the answer requires exact current item names, rely on generated reference or
Rustdoc. If the answer requires ownership, invariants, or change workflow, rely
on the hand-written guide chapters.

## Update Rule

Update this source tour when a new top-level source area appears, a directory
changes ownership, generated-file boundaries move, or maintainer tools change
their purpose. Do not update it for every new pass, buffer, status code, or
test; those belong in generated reference output or subsystem docs.
