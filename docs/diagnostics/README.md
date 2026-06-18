# Diagnostics Guide

This guide explains how to read and act on Lanius diagnostics. It is the
human-facing companion to the detailed [diagnostics surface contract](../DIAGNOSTICS.md)
and the generated [diagnostic code index](generated/error-index.md).

Use this page when you are compiling source and need to understand an error.
Use [../DIAGNOSTICS.md](../DIAGNOSTICS.md) when you are changing diagnostic
formats, registry metadata, LSP payloads, or wrapper-facing command contracts.
Use [Diagnostic code explanations](code-explanations.md) when you have a
specific `LNC####` code and want the human explanation, likely causes, and next
actions.

## Quick Reference

| Need | Command or document |
| --- | --- |
| Check source without target bytes | `laniusc check PATH` |
| Emit structured JSON diagnostics | `laniusc check --diagnostic-format json PATH` |
| Emit one LSP Diagnostic-shaped object | `laniusc --diagnostic-format lsp-json check PATH` |
| List known codes | `laniusc diagnostics codes` |
| Explain one code | `laniusc diagnostics explain LNC0017` |
| Read maintained code explanations | [code-explanations.md](code-explanations.md) |
| Read generated code inventory | [generated/error-index.md](generated/error-index.md) |
| Read full format and metadata contract | [../DIAGNOSTICS.md](../DIAGNOSTICS.md) |

`check` is the right command when you want parser, resolver, type-checker, or
bounded backend diagnostics without writing target bytes. It still exercises the
same bounded compiler path used by normal compilation up to the relevant
failure boundary.

## Diagnostic Shape

A source diagnostic normally has:

| Part | Meaning |
| --- | --- |
| Code | Stable `LNC####` selector, such as `LNC0006`. |
| Title | Short category-specific summary, such as `type mismatch`. |
| Message | The main user-facing explanation. |
| Primary label | The source span that best explains what went wrong, when the code requires one. |
| Notes | Extra context, recovery hints, accepted selector values, or boundary details. |
| Format | Text, JSON, or LSP-shaped JSON selected by `--diagnostic-format`. |

The primary label policy is registry-backed. Some tooling diagnostics, such as
unknown command-line selectors, do not have a source span and therefore have no
primary label. Source diagnostics should point at the token, declaration, call,
match arm, import, or backend boundary that explains the rejection.

## Codes And Explanations

Every registered code is listed in the generated
[diagnostic code index](generated/error-index.md). The index is generated from
the compiler registry and groups:

- all known `LNC####` codes
- unsupported-feature boundaries
- codegen fail-closed boundaries
- category and primary-label counts
- the `laniusc diagnostics explain CODE` command for each code

The maintained [Diagnostic code explanations](code-explanations.md) page gives
the rustc-style prose layer for each code: what the code means, likely causes,
where the primary label should point, and what to do next.

Use `diagnostics explain` when the short diagnostic is not enough:

```bash
laniusc diagnostics explain LNC0017
```

Unknown code lookups are metadata queries, not source compilation failures.
They should report that the selector is unknown and provide discovery commands
instead of requiring source input.

## Text Diagnostics

Text diagnostics are the default:

```bash
laniusc check src/main.lani
```

Use text diagnostics for terminal work. Text should be readable without knowing
the GPU pass or Rust helper that produced the error. If a text diagnostic leaks
raw shader status, buffer indices, or backend internals without explaining the
user source construct, treat that as a diagnostic quality bug.

## JSON Diagnostics

JSON diagnostics are for tools and wrappers:

```bash
laniusc check --diagnostic-format json src/main.lani
```

The JSON shape carries schema and registry metadata so a wrapper can use the
payload without scraping terminal text. Wrapper code should use stable fields,
the code selector, and registry metadata rather than matching exact prose.

## LSP Diagnostics

LSP-shaped diagnostics are for editor integrations:

```bash
laniusc --diagnostic-format lsp-json check src/main.lani
```

The payload is one LSP Diagnostic-shaped object with Lanius-specific `data`.
It is not a `publishDiagnostics` notification envelope. The current LSP server
uses full-document sync and pull diagnostics for one opened document; it does
not claim workspace diagnostics, source-root loading, or incremental edit
analysis.

## Fail-Closed Boundaries

Lanius is in `unstable-alpha`, so some grammar-valid or type-checked constructs
are intentionally rejected before the compiler would emit incomplete output.
Those rejections are fail-closed diagnostics.

Common fail-closed categories include:

| Category | Typical meaning |
| --- | --- |
| Module/import loading | Source-root, stdlib-root, package, or lockfile metadata did not match source declarations. |
| Type checking | A value, type, call, trait bound, generic argument, or pattern did not satisfy current semantic rows. |
| Runtime binding | A stdlib or host-service declaration exists as metadata but has no executable runtime binding. |
| Target codegen | The selected backend cannot lower the accepted frontend shape yet. |
| Tooling | A command, option, selector, format, or file operation failed before source compilation. |

Fail-closed does not mean the parser failed. It means the compiler reached a
boundary where accepting the program would imply support the current evidence
does not prove.

## Acting On A Diagnostic

Use this order:

1. Read the primary label first. It should point at the most useful source
   location.
2. Use the code to look up the generated index row.
3. Run `laniusc diagnostics explain CODE` for the longer explanation.
4. Check the relevant user docs: language reference, invocation, packages,
   targets, stdlib, or tooling.
5. If the error is a backend boundary, run `laniusc check` to separate frontend
   validity from target execution.
6. If the error is a runtime-service boundary, use the runtime metadata commands
   to inspect the known-unbound API or service.

Useful runtime metadata commands:

```bash
laniusc diagnostics runtime-apis
laniusc diagnostics runtime-api std::io::print_i32
laniusc diagnostics runtime-services
laniusc diagnostics runtime-service std::io
```

## Diagnostics Without Running Source

The `laniusc diagnostics ...` command family is no-run metadata. It can report
codes, categories, formats, command discovery, version policy, runtime services,
formatter policy, and source-pack progress without loading or compiling source.

That distinction matters for tools:

- use `laniusc check` to diagnose a source file
- use `laniusc diagnostics ...` to discover the diagnostic surface itself
- use `laniusc doctor` to report local toolchain and readiness metadata
- use `laniusc lsp capabilities` to discover editor-facing diagnostic metadata

## Quality Bar

A good diagnostic should:

- name a stable code and category
- label the source location that explains the failure when source exists
- distinguish parser, resolver, type-checker, runtime, tooling, and backend
  boundaries
- suggest a next action when the boundary has an obvious user choice
- avoid exposing raw GPU status words or implementation-only names as the main
  explanation
- avoid pretending an unsupported construct is a successful compile

If a diagnostic cannot identify the exact source location yet, it should still
fail closed and point at the narrowest available source span. The next compiler
work should improve the source record rather than accepting the unsupported
shape silently.

## Updating Diagnostics Docs

When a diagnostic changes:

1. Update the compiler registry and focused tests for the user-visible behavior.
2. Regenerate `docs/diagnostics/generated/error-index.md` if code metadata or
   unsupported-boundary rows changed.
3. Update [../DIAGNOSTICS.md](../DIAGNOSTICS.md) for format, registry, LSP, or
   no-run command contract changes.
4. Update this guide only when the way users read or act on diagnostics changes.
5. Run `tools/docs_check.py`.
