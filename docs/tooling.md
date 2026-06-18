# Tooling And Editor Integration

This chapter is the user-facing reference for `laniusc` tooling surfaces:
formatter commands, diagnostics metadata, doctor reports, and the current LSP
experiment. It is for wrappers, editors, shell integrations, and CI jobs that
need stable command behavior without reading compiler internals.

For all command syntax, use [Laniusc Invocation](invocation.md). For reading
diagnostics, use the [Diagnostics guide](diagnostics/README.md). For diagnostic
payload shape and stable codes, use [Diagnostics](DIAGNOSTICS.md). For
runtime-bound stdlib APIs, use [Standard Library Overview](stdlib/README.md).
For target bytes and `check` behavior, use [Targets And Output](targets.md). For
implementation details, use [Compiler CLI internals](compiler/cli.md),
[Formatter internals](compiler/formatter.md), and
[LSP surface internals](compiler/lsp.md).

## Tooling Surface Summary

The current tooling surface is intentionally small and explicit:

| Surface | Command | Current role |
| --- | --- | --- |
| Version metadata | `laniusc --version` | Human-readable compiler, edition, target, distribution, and build metadata. |
| Installation/readiness metadata | `laniusc doctor` | No-run JSON report for local toolchain, diagnostics, target, stdlib, readiness, and Slang probe metadata. |
| Diagnostics metadata | `laniusc diagnostics ...` | No-run JSON metadata for codes, categories, formats, runtime-service boundaries, command discovery, and source-pack progress artifacts. |
| Frontend diagnostics | `laniusc check ...` | Compile-like parser/type-check diagnostics without target bytes. |
| Formatting | `laniusc fmt ...` | Lexical source formatting for files or stdin. |
| LSP capability metadata | `laniusc lsp capabilities` | No-run JSON capability document for editor experiments. |
| LSP stdio server | `laniusc lsp serve --stdio` | Minimal JSON-RPC server for full-document sync, formatting, and opened-document pull diagnostics. |

The no-run surfaces are a public contract. Do not make a no-run metadata command
scan project source, create a GPU device, compile source, run target codegen, run
shader-loop audits, invoke Pareas, or execute generated workloads unless the
command is renamed or its contract is deliberately changed.

## Diagnostic Formats

Structured diagnostics render on stderr for failing invocations:

| Format | Select with | Shape |
| --- | --- | --- |
| text | default or `--diagnostic-format text` | Human-readable diagnostic text. |
| JSON | `--diagnostic-format json` | One structured diagnostic JSON object. |
| LSP JSON | `--diagnostic-format lsp-json` | One LSP Diagnostic-shaped JSON object, not a `publishDiagnostics` envelope. |

Examples:

```bash
laniusc check --diagnostic-format json src/main.lani
laniusc --diagnostic-format lsp-json check src/main.lani
laniusc fmt --check --diagnostic-format json src/main.lani
```

The selector can appear before no-run diagnostic subcommands or inside supported
subcommands. Successful metadata commands still print the requested metadata to
stdout.

## Diagnostics Metadata Commands

`laniusc diagnostics` is the machine-readable metadata family. It is meant for
wrappers that should not scrape text diagnostics or source files to discover the
current compiler contract.

Common commands:

```bash
laniusc diagnostics codes
laniusc diagnostics code LNC0017
laniusc diagnostics categories
laniusc diagnostics formats
laniusc diagnostics explain LNC0017
laniusc diagnostics registry
laniusc diagnostics commands
laniusc diagnostics formatter
laniusc diagnostics version-policy
```

Runtime-bound stdlib metadata:

```bash
laniusc diagnostics runtime-apis
laniusc diagnostics runtime-api std::io::print_i32
laniusc diagnostics runtime-services
laniusc diagnostics runtime-service std::io
laniusc diagnostics runtime-service-apis std::io
```

Source-pack progress metadata:

```bash
laniusc diagnostics source-pack-progress --source-pack-artifact-root ARTIFACT_DIR
laniusc diagnostics source-pack-progress --source-pack-artifact-root ARTIFACT_DIR --emit x86_64
```

These commands report public schemas, selectors, known/unknown lookup results,
no-run guards, and recovery commands. Unknown diagnostic codes or runtime
selectors should remain successful metadata queries with `known: false` when the
command contract says so; they should not need to compile source just to explain
valid selector shapes.

## Doctor Reports

Use `doctor` when an editor, installer, CI preflight, or wrapper needs local
toolchain and compiler-boundary metadata in one JSON document:

```bash
laniusc doctor
laniusc doctor --skip-slangc-probe
```

`doctor` reports:

- compiler version, language edition, release/distribution boundary, and build
  metadata
- accepted targets, target triples, and diagnostic format metadata
- Slang selector/probe status and bounded timeout errors
- shader artifact metadata and build-time timeout budgets
- stdlib-root and runtime-boundary metadata
- readiness-gate metadata and opt-in generated/Pareas lane boundaries
- no-run guards

`doctor` may run a bounded `slangc --version` probe unless
`--skip-slangc-probe` is passed. It must not compile source, create a GPU
device, scan stdlib source, run readiness gates, run generated workloads, run
shader-loop audits, or invoke Pareas.

## Formatter

`laniusc fmt` is a lexical formatter for the current alpha slice:

```bash
laniusc fmt src/main.lani
laniusc fmt --check src/main.lani
laniusc fmt --stdin < src/main.lani
laniusc fmt --stdin --check < src/main.lani
```

Formatter contract:

- preserves non-whitespace token text and token order
- preserves string literal, character literal, and comment contents
- emits LF line endings
- uses four-space indentation
- formats full documents only
- does not parse, type-check, resolve imports, load source roots, create a GPU
  device, or rewrite semantics

File mode rewrites changed files in place. `--check` reports a structured
diagnostic when input is not formatted and does not write files or formatted
stdout. `--stdin` writes formatted source to stdout unless `--check` is also
present.

For wrapper discovery, use:

```bash
laniusc diagnostics formatter
```

That metadata reports formatter policy, accepted CLI shapes, LSP formatting
request options, diagnostic codes, and no-run guards.

## LSP Capability Metadata

Use capability metadata before wiring an editor integration:

```bash
laniusc lsp capabilities
```

This command prints a JSON document and exits without compiling source, scanning
source roots, creating a GPU device, or running target codegen. It reports:

- server and schema metadata
- supported method inventory
- language id and position encoding
- diagnostic source and diagnostic registry metadata
- supported diagnostic formats
- full-document text synchronization policy
- formatter request metadata
- pull-diagnostic metadata
- unsupported workspace claims
- distribution and production-readiness claim boundaries
- JSON-RPC error-data contract metadata
- no-run guards

The capability command is the preferred source for wrapper feature detection.
Do not infer editor readiness from method names alone; the metadata explicitly
marks performance, production-editor, workspace, source-root, and stdlib-root
claims that are not supported today.

## LSP Stdio Server

Start the current server with:

```bash
laniusc lsp serve --stdio
```

Current supported behavior:

- LSP-style `Content-Length` framing over stdin/stdout
- initialize, initialized, shutdown, and exit lifecycle handling
- full-document open, change, and close notifications
- full-document formatting through the same lexical formatter as `laniusc fmt`
- pull diagnostics for one opened document through the bounded GPU diagnostic
  path
- structured JSON-RPC errors for unsupported methods, invalid requests, invalid
  framing, pre-initialize requests, post-shutdown requests, and malformed
  formatting options

Current non-claims:

- no workspace diagnostics
- no incremental/ranged text edits
- no source-root loading
- no stdlib-root loading
- no target codegen
- no latency, throughput, production-editor, or local-performance claim

Formatting requests require `params.options`, `tabSize: 4`, and
`insertSpaces: true`. Additional options are ignored. Range formatting is not
supported.

Opened-document diagnostics operate on the stored open document text. They are
not package or workspace diagnostics, and they do not load source-root or
stdlib-root imports.

## CI And Wrapper Defaults

Use these defaults unless a workflow specifically needs more:

| Need | Preferred command |
| --- | --- |
| Verify local toolchain metadata | `laniusc doctor` |
| Check formatting without rewriting | `laniusc fmt --check PATH` |
| Format stdin without touching files | `laniusc fmt --stdin` |
| Get frontend diagnostics without target bytes | `laniusc check PATH` |
| Get machine-readable diagnostics | `laniusc check --diagnostic-format json PATH` |
| Discover diagnostic codes | `laniusc diagnostics codes` |
| Explain one code | `laniusc diagnostics explain LNC0017` |
| Discover LSP/editor capability | `laniusc lsp capabilities` |

For docs-only changes in this repository, use:

```bash
tools/docs_check.py
```

Do not use broad compiler execution, generated workloads, shader-loop audits,
or performance scaffolds as documentation freshness checks unless the docs
change specifically touches those artifacts or claims.

## Updating Tooling Docs

Update this chapter when any user-facing tooling contract changes:

- formatter file/stdin/check behavior
- diagnostic format names or payload shapes
- diagnostics metadata subcommands or schemas
- `doctor` JSON schema or no-run guard behavior
- LSP capability metadata, supported methods, lifecycle rules, or error-data
  contract
- no-run metadata boundaries
- wrapper-facing command examples

If the implementation changes but the public tooling contract does not, update
the relevant compiler-internals chapter instead. If a new tooling claim needs
evidence, add or update the corresponding row in
`docs/language_slice_unstable_alpha.tsv`, regenerate the generated slice
reference, and keep this page aligned with the proven boundary.
