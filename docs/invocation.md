# Laniusc Invocation

This chapter is the user-facing reference for invoking `laniusc`. It is the
local equivalent of the command-focused part of the rustc documentation stack:
what the compiler command accepts, which commands compile source, which
commands are no-run metadata surfaces, how output is written, and how
diagnostics are rendered.

For implementation details, use [Compiler CLI internals](compiler/cli.md). For
language behavior, start with [Language reference](language/README.md). For
target and output behavior, use [Targets and output](targets.md). For
formatter, diagnostics metadata, doctor, and LSP wrapper behavior, use
[Tooling And Editor Integration](tooling.md). For diagnostic payloads and stable
codes, start with the [Diagnostics guide](diagnostics/README.md), then use
[Diagnostics](DIAGNOSTICS.md) for the detailed surface contract.

## Source Of Truth

Use these layers together:

| Question | Primary source |
| --- | --- |
| What is the current public command surface? | `laniusc --help`, `laniusc --version`, and this chapter |
| What language slice does the compiler claim? | [Language slice policy](LANGUAGE_SLICE.md) and [generated unstable-alpha slice](language/generated/unstable-alpha-slice.md) |
| What do errors look like? | [Diagnostics guide](diagnostics/README.md), [Diagnostics](DIAGNOSTICS.md), and [generated error index](diagnostics/generated/error-index.md) |
| How does package/source-root loading work? | [Packages and source roots](packages.md), [Modules and imports](language/modules-and-imports.md), and [Package metadata](compiler/package-metadata.md) |
| How does stdlib loading work? | [Standard library](../stdlib/README.md) and [generated stdlib reference](stdlib/generated/reference.md) |
| What target or output form should I choose? | [Targets and output](targets.md) |
| How should wrappers, editors, formatter checks, and no-run metadata work? | [Tooling and editor integration](tooling.md) |
| How is the CLI implemented? | [Compiler CLI internals](compiler/cli.md) |

The command help is intentionally verbose because `unstable-alpha` exposes many
bounded surfaces. This page is the maintained, readable form of the public
contract.

## Quick Commands

Common invocations:

```bash
laniusc --help
laniusc --version
laniusc doctor
laniusc check src/main.lani
laniusc src/main.lani -o main
laniusc --emit wasm --target wasm32-unknown-unknown src/main.lani -o main.wasm
laniusc --source-root src --stdlib-root stdlib src/app/main.lani -o main
laniusc --package-manifest lanius.package.json -o main
laniusc package lock --manifest lanius.package.json -o lanius.lock.json
laniusc fmt src/main.lani
laniusc fmt --check src/main.lani
laniusc diagnostics codes
laniusc diagnostics explain LNC0017
laniusc lsp capabilities
```

`laniusc` without an input file compiles a tiny built-in demo source to stdout
using the default emit target. That path is useful as a smoke check, not as a
package or project entry point.

## Command Families

| Command | Source compilation | GPU device | Primary output |
| --- | --- | --- | --- |
| `laniusc [options] [input]` | yes, except source-pack prep-only modes | yes for compile work | target bytes or contract descriptor |
| `laniusc check ...` | parser/type-check only | yes | diagnostics only |
| `laniusc fmt ...` | no | no | rewritten files, formatted stdout, or check diagnostic |
| `laniusc doctor ...` | no | no | toolchain/readiness JSON |
| `laniusc diagnostics ...` | no | no | registry, policy, runtime, or progress JSON |
| `laniusc package lock ...` | no | no | package lockfile JSON |
| `laniusc lsp capabilities` | no | no | editor capability JSON |
| `laniusc lsp serve --stdio` | only for pull diagnostics | only for pull diagnostics | JSON-RPC responses |

No-run commands are deliberate public surfaces. They should be safe for editor
wrappers, installers, shell completions, and metadata discovery because they do
not scan project source, compile source, create a GPU device, or run codegen
unless their command description says otherwise.

## Edition And Targets

The only accepted language edition today is:

```bash
--edition unstable-alpha
```

`unstable-alpha` is not a stable compatibility promise. It names the current
bounded alpha surface so tools and diagnostics can agree on what this compiler
claims.

Accepted emit targets:

| Emit target | Target triple | Current status |
| --- | --- | --- |
| `x86_64` | `x86_64-unknown-linux-gnu` | Default target. Bounded executable slice. |
| `wasm` | `wasm32-unknown-unknown` | Accepted target selector; backend currently fails closed at the backend boundary. |

`--target` is optional, but if present it must match `--emit`:

```bash
laniusc --emit x86_64 --target x86_64-unknown-linux-gnu src/main.lani
laniusc --emit wasm --target wasm32-unknown-unknown src/main.lani
```

Unsupported editions, emit targets, target triples, or emit/target mismatches
are rejected before source loading when possible.

Use [Targets and output](targets.md) for the target-support matrix, x86_64
execution boundary, WASM fail-closed boundary, `check` semantics, target-byte
output rules, and source-pack descriptor-output contract.

## Inputs

`laniusc` selects one input mode.

| Input shape | Meaning |
| --- | --- |
| no input | Compile the built-in demo source to stdout. |
| one positional file | Compile or check that file as an isolated entry. |
| `--source-root DIR entry.lani` | Load leading user module-path imports from one or more user roots. |
| `--stdlib-root DIR entry.lani` | Load leading stdlib module-path imports from the stdlib root. |
| `--source-root DIR --stdlib-root DIR entry.lani` | Search user roots first, then stdlib root for stdlib fallback imports. |
| `--package-manifest FILE` | Load a package manifest that owns entry, source roots, and optional stdlib root. |
| `--package-lockfile FILE` | Replay a resolved package lockfile. |
| explicit `--stdlib FILE` or multiple positional files | Enter source-pack dispatch. |
| source-pack manifest/library/artifact flags | Enter source-pack metadata, preparation, descriptor, or progress workflows. |

Source roots and package metadata are loading metadata. They do not rename
modules or rewrite source. Semantic module identity still comes from parsed
`module path;` and `import path;` records.

## Check Mode

`laniusc check` runs the bounded frontend/type-check diagnostic path without
writing target bytes:

```bash
laniusc check src/main.lani
laniusc check --source-root src --stdlib-root stdlib src/app/main.lani
laniusc check --package-manifest lanius.package.json
laniusc check --package-lockfile lanius.lock.json
```

Current check-mode constraints:

- it requires an input file, `--package-manifest`, or `--package-lockfile`
- it rejects `-o/--out`
- it rejects explicit source-pack descriptor, metadata, preparation,
  artifact-root, contract-output, explicit `--stdlib`, or multi-input forms

Use `check` for tooling that wants diagnostics without target bytes on stdout.

## Output

Compile mode writes bytes to stdout unless `-o/--out` is provided:

```bash
laniusc src/main.lani > main
laniusc src/main.lani -o main
```

On Unix, file output for non-WASM targets is marked executable. WASM output is
not marked executable.

Source-pack descriptor output is different from target bytes. Descriptor modes
that produce linked-output contract descriptors require:

```bash
--emit-contract
```

Without `--emit-contract`, descriptor-producing source-pack modes are rejected
instead of silently treating contract metadata as executable target bytes.

Use [Targets and output](targets.md) for the user-facing target-byte and
descriptor-output distinction.

## Diagnostic Formats

`--diagnostic-format` selects how structured diagnostics render on stderr:

| Format | Payload |
| --- | --- |
| `text` | Human-readable text. This is the default. |
| `json` | Pretty diagnostic JSON. |
| `lsp-json` | One LSP Diagnostic-shaped JSON object, not a `publishDiagnostics` envelope. |

Examples:

```bash
laniusc check --diagnostic-format json src/main.lani
laniusc --diagnostic-format lsp-json check src/main.lani
laniusc fmt --check --diagnostic-format json src/main.lani
```

The selector can appear before a no-run subcommand or inside supported
subcommands. It controls invocation diagnostics; no-run metadata commands still
print their requested metadata to stdout on success.

## Diagnostics Metadata

`laniusc diagnostics` is the no-run metadata command family.

| Command | Use |
| --- | --- |
| `registry` | Full diagnostic registry JSON. |
| `codes` | Compact code index for completions and lookup UIs. |
| `code CODE` | One compact diagnostic code row, or `known:false`. |
| `categories` | Stable diagnostic categories with grouped code metadata. |
| `formats` | Accepted diagnostic render formats and payload contracts. |
| `formatter` | Formatter policy, CLI/LSP formatter commands, and no-run guards. |
| `version-policy` | Compiler, edition, target, distribution, schema, and command-discovery policy. |
| `explain CODE` | One code-specific explanation JSON document. |
| `runtime-api API` | One known-unbound runtime-bound stdlib API row. |
| `runtime-apis` | Full known-unbound runtime-bound API index. |
| `runtime-service SERVICE` | One runtime service boundary. |
| `runtime-service-apis SERVICE` | Runtime-bound APIs owned by one service. |
| `runtime-services` | Full runtime service boundary table. |
| `commands` | Machine-readable metadata command discovery. |
| `source-pack-progress --source-pack-artifact-root DIR [--emit TARGET]` | Persisted source-pack work-queue progress. |

These commands are for wrappers and humans who need current metadata without
running a compile.

Use [Tooling And Editor Integration](tooling.md) for the wrapper-facing view of
diagnostics metadata, formatter, doctor, LSP capability, and no-run command
boundaries.

## Doctor

`laniusc doctor` prints a compact JSON report for local installation and
wrapper checks:

```bash
laniusc doctor
laniusc doctor --skip-slangc-probe
```

The report includes compiler version, language edition, target surface,
diagnostic format metadata, Slang availability, build metadata, readiness-gate
metadata, pass-contract metadata, stdlib boundary counts, and no-run guards.
It does not compile source, create a GPU device, run readiness gates, run
shader-loop audits, or invoke Pareas.

`--skip-slangc-probe` suppresses the runtime `slangc --version` probe while
still reporting the configured selector.

## Formatter

`laniusc fmt` is a lexical formatter for the current alpha slice. It does not
parse or type-check on the CPU, and it does not create a GPU device.

```bash
laniusc fmt src/main.lani
laniusc fmt --check src/main.lani
laniusc fmt --stdin < src/main.lani
laniusc fmt --stdin --check < src/main.lani
```

File mode rewrites changed files in place. `--check` verifies formatting
without writing. `--stdin` and `-` read standard input and write formatted
source to stdout unless `--check` is also present.

## Package Lockfiles

`laniusc package lock` resolves a package manifest and writes a package
lockfile:

```bash
laniusc package lock --manifest lanius.package.json -o lanius.lock.json
```

The command is package metadata work, not source compilation. The output path
must not identify the same file as the manifest. Lockfiles can later feed
compile/check mode:

```bash
laniusc check --package-lockfile lanius.lock.json
laniusc --package-lockfile lanius.lock.json -o main
```

Package names and paths remain control-plane metadata. Module identity still
comes from source declarations.

## LSP Commands

The LSP command family has a no-run metadata mode and a stdio server mode:

```bash
laniusc lsp capabilities
laniusc lsp serve --stdio
```

`lsp capabilities` prints capability metadata without compiling source.

`lsp serve --stdio` starts a minimal JSON-RPC server. It supports initialize,
initialized, full-document open/change/close, full-document formatting, pull
diagnostics, shutdown, and exit. Formatting is lexical and does not run GPU
work. Pull diagnostics run the bounded GPU diagnostic path for the opened
document and do not run target codegen.

The current LSP surface is explicitly not a full workspace service: no
incremental document edits, no workspace diagnostics, no source-root loading,
and no stdlib-root loading are claimed.

## Source-Pack Workflows

Source-pack flags expose bounded metadata, preparation, descriptor, and progress
workflows for larger or persisted compilation experiments. They are not the
normal single-file or package path.

Important public rules:

- `--source-pack-manifest` and `--source-pack-library-manifest` describe all
  source-pack libraries; do not combine them with positional files,
  `--stdlib`, `--stdlib-root`, or `--source-root`
- metadata-only and preparation-only modes do not write target bytes and reject
  `-o/--out`
- package manifest and package lockfile selectors currently feed source-pack
  metadata preparation only with `--source-pack-metadata-only`
- descriptor-producing modes require `--emit-contract`
- work limits are chunk sizes for resumable progress, not language limits

Use [Source packs, artifacts, and work queues](compiler/source-packs.md) and
[Artifact descriptors and output contracts](compiler/artifact-descriptors.md)
for the maintainer-facing model.

## Update Rule

Update this chapter when a user-visible command, option, target selector,
diagnostic format, no-run metadata command, output behavior, formatter mode,
LSP capability, package mode, source-root mode, stdlib-root mode, or source-pack
workflow changes.

For implementation-only changes, update [Compiler CLI internals](compiler/cli.md)
instead. For language behavior changes, update the language reference and
generated slice before changing invocation prose.
