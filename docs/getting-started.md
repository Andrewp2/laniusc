# Getting Started

This chapter is the shortest honest path from a source checkout to useful
`laniusc` commands. It is for someone trying the current compiler, not for
compiler-author workflow details. For full command reference, use
[Laniusc Invocation](invocation.md). For target behavior, use
[Targets And Output](targets.md). For compiler-author build and test workflow,
use [Building And Running The Compiler](compiler/building.md).

## Current Distribution Boundary

Lanius is currently a source-worktree alpha compiler. There is no stable install
artifact, package-manager channel, production release, or stable language
edition yet.

The only documented language edition is `unstable-alpha`. The default emit
target is `x86_64`, and `wasm` is an accepted selector that currently fails
closed at the backend boundary instead of producing executable Wasm. Treat
target support and stdlib support as bounded evidence, not as production
platform support.

## Prerequisites

A local build needs:

- a Rust toolchain with edition 2024 support
- the Slang compiler available as `slangc`, or selected with `SLANGC`
- any platform loader path needed by the local Slang runtime library

The repository intentionally does not commit workstation-local Slang paths or
runtime library paths. Configure those through your shell, a wrapper, or
untracked local configuration.

## First Commands

From the repository root, start with no-run metadata:

```bash
cargo run -- --version
cargo run -- doctor
cargo run -- doctor --skip-slangc-probe
```

`doctor` reports local toolchain metadata, target metadata, diagnostic policy,
readiness metadata, stdlib boundary metadata, and Slang availability. It does
not compile source, create a GPU device, run generated workloads, run shader
loop audits, or invoke Pareas.

If `doctor` reports a missing or stalled Slang compiler, fix `SLANGC` or `PATH`
before treating target compilation failures as language failures. Use
`--skip-slangc-probe` only when a wrapper or editor needs the rest of the JSON
metadata without running `slangc --version`.

## Check A Sample

The maintained sample programs are documentation-smoke fixtures. Start with the
small single-file sample:

```bash
cargo run -- check sample_programs/checkout_fee.lani
cargo run -- fmt --check sample_programs/checkout_fee.lani
```

`check` is the right first compile-like command because it runs the bounded
frontend/type-check diagnostic path and writes no target bytes. A successful
`check` does not prove the program can execute on every backend.

Compile through the default native target when you specifically want target
bytes:

```bash
cargo run -- --emit x86_64 sample_programs/checkout_fee.lani -o /tmp/checkout_fee
```

On Unix, successful non-WASM file output is marked executable. The x86_64 path
is still bounded; unsupported native shapes should fail closed with diagnostics
instead of silently producing partial native code.

## Try A Split Source Tree

Use a source root when a program imports another module by module path:

```text
src/app/main.lani
src/app/math.lani
```

Check the entry file with:

```bash
cargo run -- check --source-root src src/app/main.lani
```

The source root maps `import app::math;` to `src/app/math.lani`, but semantic
module identity still comes from parsed `module app::math;` source. Package
names, directory names, and old path aliases do not create module identity.

Use [Worked Examples](language/examples.md) for a copyable source-root layout.
Use [Modules, Imports, And Packages](language/modules-and-imports.md) for the
full module, source-root, stdlib-root, package-manifest, and lockfile rules.

## Load The Standard Library Explicitly

Stdlib source is not implicitly preloaded. If the source imports `core::i32`,
`core::option`, `std::path`, or another stdlib module, pass `--stdlib-root`:

```bash
cargo run -- check --source-root src --stdlib-root stdlib src/app/main.lani
```

Runtime-backed stdlib APIs can be known and type-checkable without being
executable host services. Inspect the current runtime-service boundary with
no-run metadata commands:

```bash
cargo run -- diagnostics runtime-apis
cargo run -- diagnostics runtime-services
cargo run -- diagnostics runtime-api std::io::print_i32
```

Use the [standard library overview](stdlib/README.md) and generated
[stdlib reference](stdlib/generated/reference.md) for the current source-level
module, declaration, and runtime-service inventory.

## Read Diagnostics

Text diagnostics are the default. Use JSON or LSP-shaped JSON when tooling needs
structured payloads:

```bash
cargo run -- check --diagnostic-format json sample_programs/checkout_fee.lani
cargo run -- --diagnostic-format lsp-json check sample_programs/checkout_fee.lani
cargo run -- diagnostics explain LNC0017
cargo run -- diagnostics codes
```

Use the [Diagnostics guide](diagnostics/README.md) for reading errors, then use
[Diagnostics](DIAGNOSTICS.md) and the generated
[diagnostic code index](diagnostics/generated/error-index.md) for stable code
metadata, categories, renderer contracts, source-label policy, and
unsupported-feature boundaries.

## Where To Go Next

| Task | Start here |
| --- | --- |
| Learn accepted language syntax and semantics | [Language reference](language/README.md) |
| Copy small program layouts | [Worked examples](language/examples.md) |
| Choose command flags and input modes | [Laniusc Invocation](invocation.md) |
| Wire editors, wrappers, formatting, and diagnostics metadata | [Tooling And Editor Integration](tooling.md) |
| Understand target and output limits | [Targets And Output](targets.md) |
| Use source roots, stdlib roots, manifests, and lockfiles | [Packages And Source Roots](packages.md) |
| Understand language module/import syntax | [Modules, Imports, And Packages](language/modules-and-imports.md) |
| Inspect stdlib declarations | [Standard library generated reference](stdlib/generated/reference.md) |
| Work on the compiler | [Compiler internals](compiler/README.md) |
| Check documentation freshness | [Freshness check](README.md#freshness-check) |

## Common Early Mistakes

- Treating `wasm` as an executable output target. It is currently a fail-closed
  selector boundary.
- Treating `check` success as proof of native execution.
- Expecting stdlib modules to be auto-imported.
- Expecting runtime-backed stdlib APIs to be executable host services.
- Using package names or paths as semantic module names.
- Running broad test suites for docs-only changes. Use `tools/docs_check.py`
  for maintained documentation edits.
