# TODO

## GPU Prefix Scans

- Keep delimiter matching and layer/rank assignment on the shared GPU scan
  path. The old lexer close-retag pipeline has been removed; the active lexer
  emits raw punctuation/operator tokens plus keyword retags in `tokens_build`.
- Audit the remaining prefix-scan helpers for duplicated scan orchestration.
  Parser, type-checker, and codegen now each have local scan steps; the next
  cleanup is a shared resident scan helper so new passes do not recreate the
  same bind-group and ping-pong buffer plumbing.

## Parser

- Keep replacing the `--gpu-codegen` syntax surface with real parser summaries.
  That path now avoids the transitional LL(1) stack-walk parser and requires a
  wave-sized GPU syntax validation pass before type checking/codegen. The pass
  catches the current fixture subset plus representative syntax errors, but it is
  still token-directed validation rather than complete AST/HIR materialization.
- Replace the current witness-projected partial-parse table with a real LLP
  table construction pass. The grammar now covers the current file/function/
  block/statement/type/expression surface. The GPU now runs a full LL(1)
  acceptance/error pass and emits the exact LL(1) production stream from the
  generated grammar tables. Test-only CPU parser oracles remain only in parser
  tests and fuzz tooling. The generated LLP pair-production stream is still a
  witness projection with conflicts, so it remains a parallel parser artifact
  rather than the correctness source for resident HIR/type/codegen.
- Replace the transitional sequential seed stitch with a true LLP/PSLS
  summary-composition pass. `ll1_blocks_02_stitch`/`ll1_blocks_03_seeded`
  snapshot parser stacks at block boundaries and rerun blocks from those seeds.
  This proves the seeded block shape, but the seed stitch still replays from the
  file start to each boundary on the GPU rather than composing parser summaries
  with a deterministic LLP table/reduction.
- Replace the witness-projected pair summaries with a real context-bearing LLP
  summary representation. `tables/parse_tables.meta.json` currently reports
  projection conflicts for both `sc_projection` and `pp_projection`, so the
  projected pair stream is useful as a parallel artifact but is not yet a
  correctness source for the resident compiler's HIR.
- Add AST materialization from the production tree. The GPU currently returns a
  production-id tree plus HIR-facing classification buffers. The old Rust
  `src/hir.rs` source-token frontend has been removed, so the remaining bridge
  is GPU-side lowering from the production tree and token spans into the stable
  semantic IR.

## Semantic Frontend

- Move semantic analysis from token validation to typed HIR/IR. The
  `--gpu-codegen` path now runs a GPU token type-check pass for the current
  scalar/array/function/let/return/name subset and rejects unknown types,
  unresolved identifiers, simple assignment mismatches, return mismatches, and
  invalid condition types. It still needs full scoped name resolution over HIR
  scopes: file scope, function scope, block scopes, parameters, locals, and later
  imports/modules.
- Add type checking over the stable HIR/IR instead of the current token-directed
  subset checker.

## Code Generation

- Keep the resident GPU compiler path as the default CLI path. `GpuCompiler`
  owns a reusable `GpuDevice`, lexer, parser, type checker, and GPU backend;
  supported codegen paths must compile directly from lexer token buffers through
  parser/type/codegen without a CPU token readback/reupload between stages.
- Move HIR construction and code emission onto the GPU. The default
  GPU-codegen path now runs GPU lexing, GPU parse acceptance/HIR span
  discovery, GPU token type checking, and the narrow GPU WASM emission path.
  The x86_64 backend module exists but is not wired into the compiler until it
  has a non-hanging GPU-only path. General semantic HIR lowering and checked
  type analysis still need a real GPU IR path instead of token-directed
  lowering.
- Keep x86_64 as the primary backend target. WASM can remain useful as a compact
  validation target, but native executable emission is the compiler direction.
