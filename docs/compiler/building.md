# Building And Running The Compiler

This chapter is the compiler-author on-ramp. It explains which commands build
the real compiler binary, which commands regenerate checked-in compiler tables,
which commands produce runtime shader artifacts, and which checks are useful
after common changes.

Use `testing.md` for the evidence ladder and test design. Use this chapter when
you need to get a local compiler build, run a narrow command, or decide which
generated artifacts must be refreshed.
Use [Maintainer tools and generated inputs](maintainer-tools.md) for the
ownership, outputs, and evidence policy of the tools named here.

## Prerequisites

Local builds require:

- a Rust toolchain with edition 2024 support
- `slangc`, found from `SLANGC` first and then `PATH`
- the platform loader path for any Slang runtime library required by the local
  installation

The lightweight installation check is:

```bash
cargo run -- doctor
cargo run -- doctor --skip-slangc-probe
```

`doctor` reports build metadata, target surface, shader artifact metadata,
diagnostic policy, readiness metadata, and Slang availability. It must not
compile source, create a GPU device, run generated gates, run shader-loop
audits, or invoke Pareas.

## Workspace Targets

| Target | Command shape | Role |
| --- | --- | --- |
| Root CLI binary | `cargo run -- ...` or `cargo check --bin laniusc` | Real user-facing `laniusc` command and root shader build path. |
| Compiler crate | `cargo test -p laniusc-compiler ...` | Internal compiler libraries, model tests, and compiler-tool binaries. |
| Shader crate | built through Cargo build scripts | Compiles active Slang entrypoints into SPIR-V/reflection artifacts. |
| Root integration tests | `cargo test -p laniusc --test <target> <filter>` | Public CLI/compiler behavior through integration tests. |

Prefer `cargo check --bin laniusc` when the change touches shaders, shader
artifact metadata, the CLI binary, build metadata, or anything that should be
validated through the same path as the real compiler executable.

Prefer focused crate or integration tests when the change is a pure planning,
parser record, diagnostic, or semantic contract. The focused-test wrapper can
locate exact Rust test functions:

```bash
tools/focused_test.sh --print test_function_name
tools/focused_test.sh test_function_name -- --nocapture
```

## Shader Artifacts

`crates/laniusc-shaders/build.rs` compiles active `.slang` files that contain a
compute entrypoint. It writes stable artifacts under:

```text
target/laniusc-shader-artifacts/<profile>/shaders
```

For each active shader key it emits:

- `{shader-key}.spv`
- `{shader-key}.reflect.json`
- `{shader-key}.stamp`
- generated Rust lookup code
- `artifacts.env` metadata

The build script tracks the shader tree, Slang imports, compile stamps, artifact
sizes, and stale artifact removal. It skips unwired shader entrypoint fixtures
that are kept for source or audit purposes but are no longer loaded by the
compiler.

Important shader build environment:

| Variable | Use |
| --- | --- |
| `SLANGC` | absolute path to the Slang compiler; falls back to `PATH` |
| `LANIUS_SHADER_DEBUG` | adds Slang debug info when truthy |
| `LANIUS_SHADER_OPT_LEVEL` | Slang optimization level, default `1` |
| `LANIUS_SHADER_MAX_SPV_BYTES` | per-artifact SPIR-V size guard, default 4 MiB, `0` disables locally |
| `LANIUS_SHADER_COMPILE_TIMEOUT_MS` | per-shader compile timeout, default 120 seconds |
| `SLANGC_EXTRA_FLAGS` | extra flags appended to each Slang invocation |

The compiler crate build script records the same artifact root in
`LANIUS_SHADER_ARTIFACT_ROOT`. Debug native compiler executions read shader
metadata and artifacts from that stable target directory, so a shader edit
should be validated through a root binary build or check.

For shader-shape review, use the no-run audit:

```bash
tools/shader_loop_audit.sh --summary-only
tools/shader_loop_audit.sh --summary-only --fail-on-paper-pass-blocker
```

That audit classifies loop shapes. It is pass-shape evidence, not performance
or correctness evidence by itself.

## Generated Tables

Lexer and parser tables are checked-in generated inputs. Regenerate them only
when their sources change.
See [Maintainer tools and generated inputs](maintainer-tools.md) for the
tool roles, and [Grammar and generated tables](grammar-and-tables.md) for the
source-of-truth contracts, output formats, grammar metadata, production IDs, and
evidence policy.

Lexer table generation:

```bash
cargo run -p laniusc-compiler --bin lex_gen_tables
```

Outputs:

- `tables/lexer_tables.bin`
- `shaders/generated_token_ids.slang`

Parser table generation:

```bash
cargo run -p laniusc-compiler --bin parse_gen_tables
cargo run -p laniusc-compiler --bin parse_gen_tables -- grammar/lanius.bnf
```

Outputs:

- `tables/parse_tables.bin`
- `tables/parse_tables.meta.json`
- `shaders/parser/generated_parse_production_ids.slang`

After regenerating tables, run the focused tests for the changed token, grammar,
parser HIR, or diagnostic behavior. Do not treat successful table generation as
proof that downstream HIR, type-check, or backend contracts still hold.

## Running The CLI

Useful local commands:

```bash
cargo run -- --version
cargo run -- doctor
cargo run -- diagnostics registry
cargo run -- check path/to/file.lani
cargo run -- --emit x86_64 path/to/file.lani -o /tmp/lanius-out
cargo run -- fmt --check path/to/file.lani
```

Use `check` when the change should exercise parsing and type checking without
writing target bytes. Use compile modes when the changed behavior is target
output, backend status, output emission, or source-pack descriptor output.

`laniusc diagnostics ...`, `laniusc doctor`, `laniusc fmt`, and
`laniusc lsp capabilities` are no-run or metadata surfaces. They should remain
usable without source compilation or GPU target codegen unless their public
contract is deliberately changed.

## Runtime Flow And Bench Harness

For a narrow runtime-flow probe, use `gpu_compile_bench` with small inputs:

```bash
cargo run -p laniusc-compiler --bin gpu_compile_bench -- \
  --phase typecheck --source mixed --lines 500 --warmups 1 --iters 3

cargo run -p laniusc-compiler --bin gpu_compile_bench -- \
  --phase x86 --source call-graph --lines 500 --warmups 1 --iters 1 \
  --validate-output
```

Supported phases are `lex`, `parse`, `typecheck`, `wasm`, and `x86`. The bench
binary measures reused `GpuCompiler` runtime after construction. If shader
artifacts are missing or stale, run `cargo check --bin laniusc` first so the
root shader build path refreshes them. Use `--allow-large` only for intentional
large live runs.
See [Maintainer tools and generated inputs](maintainer-tools.md) for the full
bench source families, descriptor mode, and measurement evidence boundaries.

Tracing and timing flags are documented in `debugging.md`; common examples are:

```bash
LANIUS_GPU_COMPILE_HOST_TIMING=1 cargo run -- check path/to/file.lani
LANIUS_PERFETTO_TRACE=/tmp/lanius-trace.json cargo run -- check path/to/file.lani
```

## Rustdoc And Generated Docs

Build the API view when changing public or crate-public compiler items:

```bash
cargo doc -p laniusc-compiler --no-deps --document-private-items
```

Use [API docs and Rustdoc](api-docs.md) for the item-level documentation
contract, coverage heuristic, visibility expectations, and evidence rules.

Refresh or check generated compiler docs when the change affects public compiler
entry points, shader load sites, Slang imports, type-check pass loaders, record
sites, Rustdoc coverage, buffer carrier structs, large structs, or status-code
layouts:

```bash
tools/compiler_inventory.py --output docs/compiler/generated/reference.md
tools/compiler_inventory.py --check docs/compiler/generated/reference.md
```

Refresh the relationship map when making or reviewing coupling claims:

```bash
tools/repo_map.py
tools/repo_map.py --svg /tmp/laniusc-repo-map.svg --png /tmp/laniusc-repo-map.png
```

Generated output is a source of current facts. Do not edit it by hand.

## Acceptance And Measurement Scaffolds

The acceptance script is dry-run by default and is intentionally tiered:

```bash
tools/compiler_acceptance.sh --tier readiness --check-plan
tools/compiler_acceptance.sh --tier generated --check-env
tools/compiler_acceptance.sh --measurement-plan
```

Use real execution tiers only when the change requires that evidence:

```bash
tools/compiler_acceptance.sh --tier focused --run
tools/compiler_acceptance.sh --tier properties --run
tools/compiler_acceptance.sh --tier generated --run --allow-scale
```

Generated, Pareas, VRAM, and broad performance lanes are opt-in. A no-run plan,
shader-loop audit, or generated reference check is not a local performance
claim.
See [Maintainer tools and generated inputs](maintainer-tools.md) before treating
acceptance or audit output as proof for a compiler claim.

## Command Routing By Change

| Change | First useful commands |
| --- | --- |
| Docs only | `tools/docs_check.py`, then `git diff --check -- docs README.md stdlib/README.md tools` |
| CLI parsing/output | `cargo check --bin laniusc`, focused `tests/cli_*.rs` test |
| No-run metadata command | `cargo run -- doctor --skip-slangc-probe` or the specific `diagnostics`/`lsp capabilities` command |
| Lexer token/table change | `cargo run -p laniusc-compiler --bin lex_gen_tables`, focused lexer/parser test, generated reference check if inventories changed |
| Grammar/parser table change | `cargo run -p laniusc-compiler --bin parse_gen_tables`, focused parser/HIR or diagnostic test |
| Parser HIR record change | focused `tests/parser_hir_*.rs` test, retained-wrapper review, generated reference check |
| Type-check relation/status change | focused `tests/type_checker_*.rs` test, generated reference check if status/pass inventories changed |
| Shader pass/resource change | `cargo check --bin laniusc`, shader-loop audit when loop shape changed, focused owner-phase test |
| x86/WASM backend change | smallest backend integration test, `gpu_compile_bench` only after the small contract passes |
| Source-pack planning/store change | small model or persisted round-trip test, then source-pack CLI/work-queue test if public behavior changed |
| Performance or scale claim | acceptance measurement plan first, then explicit local artifacts from the relevant opt-in lane |

## Update Rule

Update this chapter when a build script, generated artifact, local tool,
workspace target, or recommended command changes. Keep test-selection policy in
`testing.md`; keep debugging signal choice in `debugging.md`; keep volatile
inventories in `generated/reference.md`.
