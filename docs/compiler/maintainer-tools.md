# Maintainer Tools And Generated Inputs

This chapter documents the compiler-maintainer tools that live outside normal
`laniusc` user workflows: generated-table builders, developer probes, fuzzers,
benchmark scaffolds, acceptance scripts, generated-reference tools, and
relationship-map tools.

Use this chapter when changing `crates/laniusc-compiler/src/bin`, `tools/`,
`grammar/`, checked-in table files, generated Slang constants, benchmark source
generators, no-run audits, or the evidence policy for local compiler work. Use
[Building and running the compiler](building.md) for quick command selection and
[Compiler testing and verification](testing.md) for the test evidence ladder.
Use [Grammar and generated tables](grammar-and-tables.md) for token, grammar,
table-format, metadata, and production-id contracts.

## Tool Roles

The tools split into four roles:

| Role | Examples | Evidence kind |
| --- | --- | --- |
| Checked-in generators | `lex_gen_tables`, `parse_gen_tables` | Reproducible compiler inputs that must be committed when their sources change. |
| Developer probes and fuzzers | `lex_fuzz`, `lex_perf`, `parse_demo`, `parse_fuzz` | Debugging, local exploration, and invariant discovery. |
| Benchmark and acceptance scaffolds | `gpu_compile_bench`, `tools/compiler_acceptance.sh`, `tools/shader_loop_audit.sh` | Measurement, readiness, and no-run pass-shape evidence. |
| Derived documentation and maps | `tools/docs_check.py`, `tools/compiler_inventory.py`, `tools/diagnostic_index.py`, `tools/language_slice_summary.py`, `tools/stdlib_inventory.py`, `tools/repo_map.py` | Generated current-state facts and relationship views. |

Do not treat every tool result as the same kind of proof. A generator proves
that its own output can be written. A fuzz tool can find bugs, but a passing
fuzz run is not a public contract unless the command, seed, corpus, and checked
invariant are part of the evidence. A no-run audit can classify source shape,
but it does not prove runtime behavior.

## Checked-In Generated Inputs

Generated compiler inputs are checked into the repo so normal builds do not need
to regenerate language tables.

| Output | Generator | Primary source |
| --- | --- | --- |
| `tables/lexer_tables.bin` | `cargo run -p laniusc-compiler --bin lex_gen_tables` | `lexer::tables::dfa` and `lexer::tables::tokens` |
| `shaders/generated_token_ids.slang` | `cargo run -p laniusc-compiler --bin lex_gen_tables` | `lexer::tables::tokens::TokenKind` |
| `tables/parse_tables.bin` | `cargo run -p laniusc-compiler --bin parse_gen_tables` | `grammar/lanius.bnf` and parser table code |
| `tables/parse_tables.meta.json` | `cargo run -p laniusc-compiler --bin parse_gen_tables` | grammar analysis, predictions, projections, productions |
| `shaders/parser/generated_parse_production_ids.slang` | `cargo run -p laniusc-compiler --bin parse_gen_tables` | grammar production tags |
| `docs/compiler/generated/reference.md` | `tools/compiler_inventory.py --output docs/compiler/generated/reference.md` | current Rust and Slang source |
| `docs/diagnostics/generated/error-index.md` | `tools/diagnostic_index.py --output docs/diagnostics/generated/error-index.md` | diagnostic registry and fail-closed boundary metadata |
| `docs/language/generated/unstable-alpha-slice.md` | `tools/language_slice_summary.py --output docs/language/generated/unstable-alpha-slice.md` | `docs/language_slice_unstable_alpha.tsv` |
| `docs/stdlib/generated/reference.md` | `tools/stdlib_inventory.py --output docs/stdlib/generated/reference.md` | `stdlib/**/*.lani` |

Generated files should say how to regenerate them. Do not edit these files by
hand except as a temporary investigation that is reverted before the final
change.
The source-of-truth contracts for the token namespace, grammar file, table
formats, and generated Slang constants are documented in
[Grammar and generated tables](grammar-and-tables.md).

## Lexer Table Generator

`lex_gen_tables` builds the compact lexer DFA table consumed by
`GpuLexer::new_with_device` and shader token-id constants consumed by Slang.

Command:

```bash
cargo run -p laniusc-compiler --bin lex_gen_tables
```

Outputs:

- `tables/lexer_tables.bin`
- `shaders/generated_token_ids.slang`

The binary table begins with the magic bytes `LXDFA001`, then stores:

- state count
- reserved flags word
- one packed `u16` transition/emission entry for each byte and DFA state
- one packed `u16` token id for each DFA state

The Slang constants file contains:

- `TOKEN_KIND_COUNT`
- `TOKEN_INVALID`
- one `TK_*` constant for each `TokenKind::ALL` entry

Change `lexer::tables::tokens` when the source language adds, removes, or
renames token kinds. Change DFA construction when the byte-level recognition
rules change. Then regenerate both outputs and run a focused lexer/parser proof
for the changed token behavior.

Successful generation is not enough. It does not prove contextual retagging,
parser token facts, HIR construction, diagnostics, type checking, or backend
behavior.

## Parser Table Generator

`parse_gen_tables` builds parser tables and generated production-id constants
from the grammar file.

Commands:

```bash
cargo run -p laniusc-compiler --bin parse_gen_tables
cargo run -p laniusc-compiler --bin parse_gen_tables -- grammar/lanius.bnf
```

Outputs:

- `tables/parse_tables.bin`
- `tables/parse_tables.meta.json`
- `shaders/parser/generated_parse_production_ids.slang`

The generator accepts:

- `%start NonTerminal;`
- production lines of the form `lhs [tag] -> rhs;`
- quoted lexer `TokenKind` names for terminals
- bare identifiers for nonterminals
- empty right-hand sides

It validates the grammar boundary before writing tables:

- undefined nonterminals are fatal
- left recursion is fatal
- LL(1) conflicts are fatal
- unreachable nonterminals are warnings
- LLP projection conflicts are reported in metadata and summary output

The metadata file records the grammar path, start symbol, lookback/lookahead,
diagnostics, stack-change and partial-parse projections, LL(1) runtime table
shape, predictions, and production metadata. The generated Slang constants are
derived from production tags and fail generation on duplicate generated constant
names.

Changing syntax usually requires more than regenerating tables. After table
generation, run the smallest parser/HIR or diagnostic test that proves the new
syntax shape at the parser-owned boundary.

## Grammar Tags And Production IDs

Production tags are stable names for parser and shader code. They become
`PROD_*` constants in `shaders/parser/generated_parse_production_ids.slang`.

When changing a tag:

1. update `grammar/lanius.bnf`
2. regenerate parse tables
3. update parser/shader code that consumes the production id
4. run focused parser/HIR tests that would fail if the production id were wrong
5. update docs if the syntax-authoring workflow changed

Do not keep old production constants as compatibility aliases unless another
human maintainer needs a short-lived migration path during a coordinated
change. Otherwise aliases create false evidence that both names have meaning.

## Parser Generator Tests

The parser generator has local Rust tests under
`crates/laniusc-compiler/src/bin/parse_gen_tables/tests.rs`.

Those tests cover generator behavior such as:

- current grammar cleanliness at the generator boundary
- LL(1) prediction and conflict behavior
- LLP pair-table construction for small grammars
- production metadata and generated constant behavior

Use these tests when changing the generator itself. Use parser/HIR integration
tests when changing the language grammar.

## Developer Lexer Tools

`lex_fuzz` is developer fuzz tooling. It is not part of the compiler pipeline.
It may compare GPU-facing behavior with explicitly named test CPU lexer oracles
and optional sidecar goldens.

Use it to investigate lexer bugs, produce minimized cases, or validate a fixed
corpus during local development. Do not cite a broad ad hoc fuzz run as the only
evidence for a public token contract. Promote the discovered case into a
focused test when the behavior should remain fixed.

`lex_perf` is a lexer throughput probe. It accepts an optional source file path
or generates valid source with a deterministic seed. Environment variables
control source length, seed, warmups, and repetitions:

| Variable | Meaning |
| --- | --- |
| `LEX_PERF_LEN` | Generated source length, default 10000000. |
| `LEX_PERF_SEED` | Generated source seed, default 42. |
| `LEX_PERF_WARMUP` | Warmup count, default 1. |
| `LEX_PERF_REPS` | Measured repetitions, default 10. |

Use `lex_perf` for local throughput exploration after a correctness proof
already exists. It is not a replacement for `gpu_compile_bench` when the claim
is end-to-end compiler runtime.

## Developer Parser Tools

`parse_demo` is a local parser inspection tool. It lexes one sample or file,
loads `tables/parse_tables.bin`, and runs parser paths. Environment flags expose
additional detail:

| Variable | Effect |
| --- | --- |
| `LANIUS_PARSE_DEMO_TOKENS` | Print token rows and source text. |
| `LANIUS_PARSE_DEMO_RESIDENT` | Use the resident parser path and print status and node summary. |
| `LANIUS_PARSE_DEMO_FULL` | Print expanded parser/HIR rows in resident mode. |

Use it while debugging parser state. When the behavior matters, move the case
into a parser/HIR validator or integration test.

`parse_fuzz` runs fixed parser corpora and random parser inputs. It loads
`tables/parse_tables.bin`, may check sidecar `*.parse.json` goldens, and uses
test CPU oracles for some parser-internal invariants. It is developer tooling,
not a production parser path.

Example command shapes:

```bash
cargo run -p laniusc-compiler --bin parse_fuzz
cargo run -p laniusc-compiler --bin parse_fuzz -- parser_tests/tricky_combo.lani
cargo run -p laniusc-compiler --bin parse_fuzz -- --iters=10 --len=2000000 --seed=123
```

Keep large fuzz lengths out of the default verification path. If a fuzz run
finds a bug, minimize the input and add a focused parser/HIR or diagnostic test.

## GPU Compile Bench

`gpu_compile_bench` is the main runtime-flow and measurement scaffold for the
compiler pipeline. It measures reused `GpuCompiler` runtime after construction.

Common command shapes:

```bash
cargo run -p laniusc-compiler --bin gpu_compile_bench -- \
  --phase typecheck --source mixed --lines 500 --warmups 1 --iters 3

cargo run -p laniusc-compiler --bin gpu_compile_bench -- \
  --phase x86 --source call-graph --lines 500 --warmups 1 --iters 1 \
  --validate-output
```

Important options:

| Option | Meaning |
| --- | --- |
| `--phase lex|parse|typecheck|wasm|x86` | Pipeline boundary to measure or exercise. |
| `--emit wasm|x86_64-elf` | Target output for compile phases. |
| `--source simple-lets|mixed|call-graph|expr-dense|abi-calls|varied|long-function|module-pack|all` | Generated source family. |
| `--lines N` | Generated source line count, default 5000. |
| `--target-bytes N` | Generated source byte target when supported by the source family. |
| `--seed N` | Deterministic source seed. |
| `--warmups N`, `--iters N` | Warmup and measurement counts. |
| `--validate-output` | Validate produced target output where supported. |
| `--run-x86-output` | On Unix x86_64, execute x86 output and validate zero exit. |
| `--allow-large` | Opt into large live runs. |
| `--estimate-only` | Print static capacity estimate without live execution. |
| `--estimate-live` | Print live capacity estimate. |
| `--dump-source` | Print generated source. |
| `--source-pack-descriptors` | Prepare module-pack filesystem artifacts and advance descriptor work queues. |

The source families live under `crates/laniusc-compiler/src/bin/gpu_compile_bench/sources`.
The capacity estimator lives under `gpu_compile_bench/capacity.rs`. Tests for
the bench command, generated workloads, and measurement scaffold live under
`gpu_compile_bench/tests.rs`.

Use `gpu_compile_bench` when the claim is runtime flow, capacity, backend output
validation, or measurement scaffolding. Do not use it as the first proof for a
single semantic rule, parser row, diagnostic span, or backend lowering bug.

## Source-Pack Descriptor Bench Mode

`gpu_compile_bench --source-pack-descriptors` exercises persisted source-pack
descriptor paths with bounded one-item submissions.

It can:

- prepare module-pack filesystem artifacts
- resume metadata chunks for a target
- prepare artifact-build chunks
- create a `PreparedBuild`
- step descriptor work queues with bounded `max_items` and `max_ready_items`

This mode is useful when changing descriptor execution, progress files, or
source-pack artifact contracts. It still needs focused source-pack tests for
record-level correctness.

## Acceptance Script

`tools/compiler_acceptance.sh` is a tiered acceptance and measurement scaffold.
It is dry-run by default.

Useful no-run commands:

```bash
tools/compiler_acceptance.sh --tier readiness --check-plan
tools/compiler_acceptance.sh --tier generated --check-env
tools/compiler_acceptance.sh --measurement-plan
```

Execution requires explicit `--run`:

```bash
tools/compiler_acceptance.sh --tier focused --run
tools/compiler_acceptance.sh --tier properties --run
tools/compiler_acceptance.sh --tier generated --run --allow-scale
```

Tiers:

| Tier | Role |
| --- | --- |
| `focused` | Small CPU-only compile/model and behavior checkpoint. |
| `smoke` | Generated gate inventory plus no-GPU capacity estimate gate. |
| `generated` | Parameterized generated compiler gates, 5000 lines by default. |
| `properties` | Named deterministic randomized/property-style compiler tests. |
| `readiness` | No-run inventory for current production-readiness contracts. |
| `pareas` | Optional Pareas comparison provenance scaffold. |
| `all` | Runs focused, smoke, generated, properties, and Pareas lanes. |

Use acceptance tiers at checkpoints or when the change needs broad evidence.
For routine compiler work, start with focused tests and generated reference
checks.

## Shader Loop Audit

`tools/shader_loop_audit.sh` is a no-run source-shape audit over Slang loops.

Useful commands:

```bash
tools/shader_loop_audit.sh --summary-only
tools/shader_loop_audit.sh --summary-only --fail-on-paper-pass-blocker
```

It classifies shader loops by bound shape and emits detail or summary rows for
review routing. It can fail on data-dependent loops, large fixed bounds,
source-sized symbolic caps, suspicious loop attributes, and subsystem-specific
review requirements.

The audit is evidence about pass shape only. It is not correctness evidence,
performance evidence, VRAM evidence, or Pareas-equivalence evidence. If a
summary row says a pass-shape blocker is gone, still run behavior-facing tests
before claiming the compiler feature is correct.

## Focused Test Wrapper

`tools/focused_test.sh` finds the narrowest Cargo target that owns one exact
Rust test function. It refuses ambiguous or partial matches and defaults to
lower-impact execution:

- `CARGO_BUILD_JOBS=2`
- `RUST_TEST_THREADS=1`
- `nice -n 10` when available
- `ionice -c 3` when available

Command shapes:

```bash
tools/focused_test.sh --print test_function_name
tools/focused_test.sh test_function_name -- --nocapture
```

Use it when iterating on a single behavior proof. If it cannot map a test to one
Cargo target, fix the target structure or run the explicit Cargo command
instead of broadening by habit.

## Generated Reference Tools

`tools/docs_check.py` is the default maintained-docs gate. It runs the generated
reference checks plus local Markdown link target, heading-anchor, ASCII, and
trailing-whitespace checks for the maintained docs stack.

`tools/compiler_inventory.py` creates `docs/compiler/generated/reference.md`.
The language-slice, diagnostic, and stdlib generators create the public
generated references for their narrower source inventories.

Command shapes:

```bash
tools/docs_check.py
tools/compiler_inventory.py --output docs/compiler/generated/reference.md
tools/compiler_inventory.py --check docs/compiler/generated/reference.md
tools/diagnostic_index.py --output docs/diagnostics/generated/error-index.md
tools/diagnostic_index.py --check docs/diagnostics/generated/error-index.md
tools/language_slice_summary.py --output docs/language/generated/unstable-alpha-slice.md
tools/language_slice_summary.py --check docs/language/generated/unstable-alpha-slice.md
tools/stdlib_inventory.py --output docs/stdlib/generated/reference.md
tools/stdlib_inventory.py --check docs/stdlib/generated/reference.md
```

The generated reference owns volatile facts:

- public compiler function inventory
- shader source groups, imports, entrypoints, and Rust load sites
- type-check pass loader entries
- type-check record sites
- Rustdoc-visible item coverage
- buffer carrier structs
- large structs
- stable diagnostic registry rows
- GPU type-check, parser, x86, and WASM status layouts

When one of those facts changes, regenerate the reference instead of editing it
by hand. When a hand-written doc needs an exact list, link to the generated
reference instead of copying the list.

## Relationship Map Tool

`tools/repo_map.py` generates a current relationship view from source
references, shader ownership, Slang imports, tests, and file layout.

Command shapes:

```bash
tools/repo_map.py
tools/repo_map.py --output /tmp/laniusc-repo-map.md
tools/repo_map.py --svg /tmp/laniusc-repo-map.svg --png /tmp/laniusc-repo-map.png
```

The map is useful when reviewing coupling or explaining ownership changes. It
is not a substitute for subsystem docs, because it shows relationships without
the invariants behind them.

Generated SVG/PNG output should usually be written to `/tmp` or another review
artifact path, not checked in. Regenerate it when needed.

## Evidence Policy

Use the tool whose evidence matches the claim:

| Claim | Tool evidence |
| --- | --- |
| Checked-in lexer or parser tables are current | regenerate the relevant table, then run focused behavior tests. |
| Maintained docs stack is current | `tools/docs_check.py`. |
| Generated compiler reference is current | `tools/compiler_inventory.py --check docs/compiler/generated/reference.md`. |
| Generated language, diagnostic, or stdlib reference is current | run the matching `--check` command from the generated file header. |
| Repo coupling map is current | rerun `tools/repo_map.py`; do not hand-maintain graph output. |
| One Rust test function proves a contract | `tools/focused_test.sh <exact_test>`. |
| Shader loop shape is acceptable for a pass-shape review | `tools/shader_loop_audit.sh` with the relevant fail gate. |
| Compile runtime or capacity changed | `gpu_compile_bench` or acceptance measurement scaffolds with saved command, seed, source family, line count, iterations, and environment. |
| Public compiler behavior changed | focused integration/unit tests at the owning public boundary. |
| Production-readiness checkpoint is needed | `tools/compiler_acceptance.sh` tier with `--run` only after no-run plan/env checks are understood. |

Avoid source-inspection tests for inventories that the generated reference or
repo map already owns. Source-inspection tests look useful but fossilize private
layout and make refactors harder without proving behavior.

## Updating Tools

When changing a maintainer tool:

1. identify whether it is a generator, probe, benchmark, acceptance gate, or
   generated-doc tool
2. document new outputs, options, environment variables, and failure modes here
3. update `building.md` if command routing changes
4. update `testing.md` if the evidence ladder changes
5. update `debugging.md` if the tool becomes a recommended triage signal
6. update generated reference only if the extracted facts changed
7. add or update focused tests close to the tool when the tool has stable
   behavior

Do not add compatibility flags or aliases for old tool names unless another
human maintainer needs them during an active transition. Unneeded compatibility
in maintainer tools is still complexity, and it leaves the false impression that
old and new surfaces are both meaningful.
