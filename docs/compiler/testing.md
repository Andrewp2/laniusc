# Compiler Testing And Verification

Compiler tests are executable documentation. They should say which contract a
phase owns, which source or record shape proves it, and which broader claim is
still out of scope.

This page is the compiler-internals companion to the root
`docs/TESTING_STRATEGY.md`. The root strategy defines production-readiness
discipline and larger acceptance gates. This page routes everyday compiler work
to the smallest useful evidence.

## Package And Test Layout

There are two common Cargo surfaces:

| Surface | Command shape | Typical use |
| --- | --- | --- |
| Compiler crate tests | `cargo test -p laniusc-compiler <filter>` | Unit/model tests inside `crates/laniusc-compiler/src`. |
| Root integration tests | `cargo test -p laniusc --test <file> <filter>` | CLI, parser HIR, type-checker, codegen, stdlib, and source-pack integration tests under `tests/`. |

Important test locations:

| Location | Coverage role |
| --- | --- |
| `crates/laniusc-compiler/src/compiler/tests.rs` | Source-pack validation, work-queue progress, persisted manifest contracts. |
| `crates/laniusc-compiler/src/codegen/unit/tests.rs` | Source-pack unit, job, schedule, artifact, shard, and link planning invariants. |
| `crates/laniusc-compiler/src/cli/source_pack/tests.rs` | Source-pack CLI preparation, metadata, limits, and resume behavior. |
| `crates/laniusc-compiler/src/cli/output/tests.rs` | Output emission and structured tooling diagnostics. |
| `tests/parser_hir_*.rs` | Parser/HIR handoff and record invariants. |
| `tests/type_checker_*.rs` | Semantic acceptance/rejection and type-check diagnostics. |
| `tests/codegen_x86*.rs`, `tests/codegen_wasm.rs` | Backend boundary behavior and generated x86 properties. |
| `tests/cli_*.rs` | Public command, diagnostic, LSP, formatter, package, and version surfaces. |
| `tests/stdlib_*.rs` | Source-level stdlib contracts through public compile/type-check surfaces. |
| `crates/laniusc-compiler/src/bin/gpu_compile_bench/tests.rs` | Benchmark command, generated workload, measurement scaffold, and pass-contract metadata. |

Use the generated reference when you need an inventory of current public entry
points, stable diagnostic codes, shader load sites, buffer carriers, status
codes, or large structs. Do not write tests that inspect source text for those
facts; use
`tools/compiler_inventory.py --check docs/compiler/generated/reference.md`
instead.
Use `tools/docs_check.py` for docs-only changes that need the maintained
Markdown link/anchor hygiene gate plus all generated-reference freshness checks.
Use [Maintainer tools and generated inputs](maintainer-tools.md) for the
evidence policy around generators, fuzz/demo tools, benchmarks, acceptance
scripts, shader-loop audits, generated references, and repo maps. Use
[Grammar and generated tables](grammar-and-tables.md) for token, grammar,
table-format, metadata, and production-id evidence.
Use [API docs and Rustdoc](api-docs.md) when the change is item-level
documentation, public API Rustdoc, module docs, or Rustdoc coverage.

## Test Charter

Before adding or running tests, write the charter in one paragraph:

- contract: what behavior or record invariant must stay true
- owner: which compiler phase or public boundary owns it
- state space: which source shapes, rows, pages, limits, or graph forms matter
- fault model: what bug this test should catch
- smallest proof: the narrowest test that can expose that bug
- stop condition: when the evidence is enough

If the charter names only a file, helper function, shader spelling, or private
loop form, the test is probably too implementation-shaped.

## Evidence Ladder

Escalate one rung at a time:

1. Pure Rust model/unit tests for planning, ranges, progress pages, manifests,
   serialization, and deterministic schedulers.
2. Persisted round-trip tests for pages, stores, descriptors, shards, and work
   queues.
3. Parser/HIR record tests with small sources and explicit row invariants.
4. Type-check integration tests with small accepted or rejected source strings.
5. Backend integration tests with the smallest source that reaches the target
   status or output path.
6. CLI/output tests when the public command or rendering contract changes.
7. Generated/property tests only when name, shape, or scale variation is the
   actual contract.
8. Acceptance, measurement, and benchmark gates only when proving capacity,
   performance, or production-readiness scaffolding.

Stop when the evidence matches the risk. A large generated program is not a
better proof of a one-row parser invariant.

## Phase-Specific Proofs

| Change | Smallest useful proof |
| --- | --- |
| Lexer token class or table behavior | focused lexer/table test or smallest public tokenization path that exposes the token class |
| Grammar or generated table contract | generator-local test, metadata review, and the smallest parser/HIR or diagnostic proof that exercises the user-visible syntax |
| Parser HIR row | `tests/parser_hir_*.rs` invariant over owner, range, ordinal, span, or source-file mapping |
| Parser status diagnostic | smallest rejected source whose diagnostic points at the parser-owned token |
| Type-check relation | accepted/rejected program in `tests/type_checker_*.rs` with stable diagnostic or semantic output |
| Type-check status code | diagnostic assertion plus generated reference update/check if the code list changed |
| Compiler orchestration or retained phase handoff | smallest public API or CLI compile/check path that reaches the handoff, plus generated reference check if buffer carriers changed |
| x86 lowering | smallest `tests/codegen_x86*.rs` source that reaches the new backend path |
| WASM boundary | `tests/codegen_wasm.rs` backend-boundary acceptance or fail-closed diagnostic |
| Source-pack planner | small library/dependency graph in `codegen/unit/tests.rs` or `compiler/tests.rs` |
| Persisted source-pack store | tiny manifest/page/shard/work-queue test with target-specific paths and resume behavior |
| CLI output or diagnostics | `tests/cli_*.rs` or `cli/output/tests.rs` with stable JSON/text/output contract |
| Formatter rule or mode | smallest `tests/formatter.rs` source for the rule, plus `tests/cli_formatter.rs` or `tests/cli_lsp.rs` when public boundaries change |
| LSP protocol behavior | smallest `tests/cli_lsp.rs` transcript proving capability, lifecycle, formatting, diagnostics, or error-data shape |
| Standard-library helper or runtime contract | focused `tests/stdlib_*.rs`, `tests/cli_stdlib_root.rs`, or `tests/source_pack_package_boundaries.rs` proof matching source-root, type-check, runtime descriptor, fail-closed, or execution claim |
| Maintainer tool behavior | focused tool-local test or dry-run/check mode that proves the stable command contract without broad compiler execution |
| Generated reference input | regenerate and run `tools/compiler_inventory.py --check docs/compiler/generated/reference.md` |
| Docs-only maintained Markdown change | `tools/docs_check.py` |
| Rustdoc or API-doc change | generated-reference check, Rustdoc coverage review, and `cargo doc -p laniusc-compiler --no-deps --document-private-items` when rendered Rustdoc structure, links, or examples changed |
| Relationship/coupling claim | `tools/repo_map.py` output; do not hand-maintain graph facts |

## Diagnostics Tests

Diagnostics tests should prove the user-facing contract, not the internal row
that happened to trip it.

Required evidence for a stable diagnostic:

- diagnostic code or category when one exists
- primary label path and span when source location exists
- note/help text only when it is part of the public recovery contract
- source-pack file id/path behavior when the failure can occur across files
- fail-closed behavior when an unsupported shape reaches a public boundary

Do not assert raw GPU status words unless the test is specifically for status
transport. A user-facing diagnostic test should fail when the source label is
lost, even if the internal status code remains the same.

## Parser And HIR Tests

Parser/HIR tests should protect handoff contracts:

- semantic nodes map back to source tokens and source files
- owner ranges are contiguous and counts match actual children
- ordinals are stable within the owner
- previous/next links are symmetric where the record family promises symmetry
- spans stay inside the owning source construct
- unsupported syntax fails before later phases consume partial HIR

Prefer small sources with one construct under test. When testing source-pack
behavior, use two or three files and library ids only when cross-file mapping is
the contract.

## Type-Checker Tests

Type-checker tests should prove semantic behavior:

- accepted programs compile/check for the semantic reason under test
- rejected programs fail at the correct source construct
- renaming or reordering independent inputs does not change semantics
- module path, visibility, generic, trait, call, and method rules are tested at
  their public boundary
- unsupported semantic shapes fail closed with a stable diagnostic

Avoid tests that mention pass names, bind-group names, shader filenames, or
private helper functions. Those are generated-reference or Rustdoc facts, not
semantic behavior.

## Backend Tests

Backend tests should use the smallest source that reaches the backend behavior:

- x86 tests should prove emitted output, backend status, or fail-closed
  diagnostic at the x86 boundary
- WASM tests should prove the current backend boundary contract, including
  fail-closed behavior for unsupported slices
- backend diagnostics should preserve retained token/HIR evidence
- generated x86 property tests should vary names and shapes only when that
  variation catches a realistic backend bug

Do not use benchmark-sized generated sources as the first proof for backend
lowering. They are useful after the small backend contract passes.

## Source-Pack Tests

Source-pack tests are graph and persistence tests. Good small cases include:

- one library with one source
- two libraries with one dependency
- a diamond dependency graph
- one oversized source or over-limit unit
- one page boundary
- one claim/complete/resume transition
- target-qualified paths for generic, wasm, and x86 artifacts

Assert durable invariants:

- every job appears exactly once
- dependencies run before consumers
- pages and shards cover their input ranges exactly once
- persisted records round trip through the public schema
- corrupt or mismatched records fail before execution
- resume cursors do not duplicate completed work

The reference-model style in `source_pack_work_queue_progress_page_transitions_match_reference_model`
is the preferred shape for mutable work-queue logic.

## Generated References And Maps

Generated docs are part of the test surface.

Run the compiler inventory when changes affect:

- public compiler functions
- stable diagnostic code registry rows
- shader load literals or Slang imports
- type-check pass loaders or record sites
- Rustdoc-visible item coverage
- buffer carrier structs or large structs
- parser/type-check/backend status-code layouts

```bash
tools/compiler_inventory.py --output docs/compiler/generated/reference.md
tools/compiler_inventory.py --check docs/compiler/generated/reference.md
```

Run the relationship map when a change might affect coupling or ownership:

```bash
tools/repo_map.py
tools/repo_map.py --svg /tmp/laniusc-repo-map.svg --png /tmp/laniusc-repo-map.png
```

Do not edit generated output by hand.

## Performance And Readiness Evidence

Performance claims require local artifacts. A passing semantic test, shader-loop
audit, generated reference check, or no-run measurement plan is not a compile
latency or scaling result.

Use this order:

1. prove the behavior contract with a small test
2. run no-run measurement scaffolds to confirm the intended evidence shape
3. collect local benchmark/readback/VRAM artifacts only when the claim needs
   performance evidence
4. keep claims scoped to the exact source, binary, machine, and run metadata

Useful no-run commands:

```bash
tools/compiler_acceptance.sh --tier readiness --check-plan
tools/compiler_acceptance.sh --tier generated --check-env
tools/compiler_acceptance.sh --measurement-plan
```

Run real generated or benchmark lanes only when the changed surface requires
that evidence and after the smaller proof has passed.

## Capacity And Limit Evidence

Capacity and limit changes need tests that match the claim. If the work removes
an accidental limit, add the smallest source that crosses the old boundary and
now succeeds. If a limit remains user-visible, add the smallest source that
trips it and assert the stable diagnostic, source line, and label. See
[Capacity and limits](capacity-and-limits.md) for the ownership policy.

## Documentation-Only Changes

For docs-only changes, do not run cargo tests by default. Use checks that prove
the docs are fresh and navigable:

```bash
tools/compiler_inventory.py --check docs/compiler/generated/reference.md
git diff --check -- docs README.md
```

Also check local markdown links when docs in `docs/compiler` changed. If a docs
change mentions generated facts, regenerate or verify the generated reference.
