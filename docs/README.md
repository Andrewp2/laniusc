# Lanius Documentation

This directory is the documentation entry point for the current Lanius
compiler, language surface, generated references, diagnostics, and
production-readiness notes.

The docs are intentionally split into layers:

| Layer | Start here | Purpose |
| --- | --- | --- |
| Getting started | [getting-started.md](getting-started.md) | First-run path from source checkout to version, doctor, check, format, compile, source-root, stdlib-root, and diagnostics commands. |
| Language reference | [language/README.md](language/README.md) | User-facing reference for the current `unstable-alpha` language surface. |
| Compiler invocation | [invocation.md](invocation.md) | User-facing `laniusc` command, input-mode, target, output, diagnostics, formatter, package, LSP, and source-pack reference. |
| Tooling and editor integration | [tooling.md](tooling.md) | User-facing formatter, diagnostics metadata, doctor, LSP, no-run metadata, wrapper, and CI reference. |
| Targets and output | [targets.md](targets.md) | User-facing target selection, target triples, check mode, target-byte output, descriptor-output, and runtime boundary reference. |
| Packages and source roots | [packages.md](packages.md) | User-facing source-root, stdlib-root, package manifest, lockfile, import metadata, and package evidence-boundary reference. |
| Lexical structure | [language/lexical-structure.md](language/lexical-structure.md) | User-facing token, literal, keyword, comment, and lexer/parser retag boundary reference. |
| Syntax reference | [language/syntax.md](language/syntax.md) | User-facing syntax families, examples, operator grouping, and grammar/support boundary notes. |
| Items and declarations | [language/items-and-declarations.md](language/items-and-declarations.md) | User-facing item families, module metadata, imports, functions, externs, constants, aliases, structs, enums, traits, impls, visibility, namespaces, and support boundaries. |
| Functions and calls | [language/functions-and-calls.md](language/functions-and-calls.md) | User-facing function signatures, parameters, arguments, direct calls, qualified calls, generic calls, constructor calls, method calls, extern/runtime boundaries, and call ABI notes. |
| Name resolution | [language/name-resolution.md](language/name-resolution.md) | User-facing local, generic, module, import, visibility, qualified path, enum variant, field, method, ambiguity, and diagnostic lookup rules. |
| Generics and bounds | [language/generics-and-bounds.md](language/generics-and-bounds.md) | User-facing generic parameters, type arguments, const parameters, trait bounds, where clauses, generic calls, generic enums, aliases, methods, impls, and fail-closed boundaries. |
| Traits and impls | [language/traits-and-impls.md](language/traits-and-impls.md) | User-facing trait declarations, inherent impls, trait impl contracts, visibility agreement, method lookup, dispatch boundaries, obligations, and diagnostics. |
| Types and values | [language/types-and-values.md](language/types-and-values.md) | User-facing type/value semantics, primitive names, aliases, constants, generics, aggregates, traits, arrays, runtime-backed declarations, and backend boundaries. |
| Aggregates and indexing | [language/aggregates-and-indexing.md](language/aggregates-and-indexing.md) | User-facing structs, enums, arrays, slices, literals, constructors, field access, indexing, copies, assignments, and aggregate backend boundaries. |
| Literals and operators | [language/literals-and-operators.md](language/literals-and-operators.md) | User-facing literal families, operator precedence, unary, binary, assignment, division, modulo, logical operators, diagnostics, and target execution notes. |
| Expressions and control flow | [language/expressions-and-control-flow.md](language/expressions-and-control-flow.md) | User-facing statement, expression, operator, return, loop, match, call, indexing, literal, and backend execution boundaries. |
| Patterns and matching | [language/patterns-and-matching.md](language/patterns-and-matching.md) | User-facing match expression, path pattern, tuple-payload pattern, literal pattern, binding, exhaustiveness, and backend-boundary reference. |
| Modules and imports | [language/modules-and-imports.md](language/modules-and-imports.md) | User-facing module identity, import, source-root, stdlib-root, package manifest, and lockfile reference. |
| Worked examples | [language/examples.md](language/examples.md) | User-facing single-file, source-root, stdlib-root, package, diagnostics, and formatter examples with explicit evidence boundaries. |
| Language slice inventory | [language/generated/unstable-alpha-slice.md](language/generated/unstable-alpha-slice.md) | Generated row-by-row inventory of current language, tooling, diagnostics, package, stdlib, parser-HIR, codegen, linking, architecture, and performance claims. |
| Compiler internals | [compiler/README.md](compiler/README.md) | Maintainer guide for compiler ownership, data flow, GPU passes, source packs, diagnostics, codegen, tests, and generated references. |
| Compiler generated reference | [compiler/generated/reference.md](compiler/generated/reference.md) | Generated inventory of Rust and shader entry points, pass/load relationships, Rustdoc coverage, status codes, diagnostics, buffers, and large structs. |
| Diagnostics guide | [diagnostics/README.md](diagnostics/README.md) | User-facing guide to reading diagnostic codes, labels, text/JSON/LSP formats, explanations, and fail-closed boundaries. |
| Diagnostic code explanations | [diagnostics/code-explanations.md](diagnostics/code-explanations.md) | Maintained rustc-style explanations for each `LNC####` code: meaning, likely causes, source-label expectations, and next actions. |
| Diagnostics surface contract | [DIAGNOSTICS.md](DIAGNOSTICS.md) | Public diagnostic formats, registry commands, renderer contracts, LSP payloads, and source-label policy. |
| Diagnostic code index | [diagnostics/generated/error-index.md](diagnostics/generated/error-index.md) | Generated index of `LNC####` codes, unsupported-feature explanations, and fail-closed codegen boundaries. |
| Standard library | [stdlib/README.md](stdlib/README.md) | User-facing source-level stdlib loading, module families, frontend/runtime/execution boundary, and update policy. |
| Standard library generated reference | [stdlib/generated/reference.md](stdlib/generated/reference.md) | Generated inventory of source-level stdlib modules, imports, declarations, externs, and runtime-binding flags. |
| Production readiness | [PRODUCTION_READINESS.md](PRODUCTION_READINESS.md) | Current readiness matrix, evidence policy, blockers, and no-run gate boundaries. |

Historical plans and imported paper text remain in this directory, but the
maintained documentation stack above is the source to use for current compiler
and language behavior.

## Freshness Check

Run the maintained-docs check after documentation or generated-reference
changes:

```bash
tools/docs_check.py
```

That command checks generated-reference freshness, local Markdown links and
anchors, ASCII text, and trailing whitespace for the maintained docs stack. It
intentionally does not enforce ASCII or whitespace policy on imported paper
text under `docs/`.
