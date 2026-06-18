# Lanius Language Reference

This is the user-facing reference entry point for the language accepted by the
current compiler. It is intentionally conservative: Lanius is in early alpha,
and the only documented language edition today is `unstable-alpha`.

For the exact compatibility policy and machine-readable slice inventory, use:

- [Language slice and versioning policy](../LANGUAGE_SLICE.md)
- [Lexical structure](lexical-structure.md)
- [Syntax reference](syntax.md)
- [Items and declarations](items-and-declarations.md)
- [Functions and calls](functions-and-calls.md)
- [Name resolution](name-resolution.md)
- [Generics and bounds](generics-and-bounds.md)
- [Traits and impls](traits-and-impls.md)
- [Types and values](types-and-values.md)
- [Aggregates and indexing](aggregates-and-indexing.md)
- [Literals and operators](literals-and-operators.md)
- [Expressions and control flow](expressions-and-control-flow.md)
- [Patterns and matching](patterns-and-matching.md)
- [Modules, imports, and packages](modules-and-imports.md)
- [Worked examples](examples.md)
- [generated unstable-alpha slice reference](generated/unstable-alpha-slice.md)
- [raw unstable-alpha slice inventory](../language_slice_unstable_alpha.tsv)
- [Diagnostics](../DIAGNOSTICS.md)

The compiler-internals notes live separately under
[Compiler internals](../compiler/README.md). Use them to change the compiler.
Use this page to understand what the current public language surface claims.

## Edition Contract

`unstable-alpha` is not a stable compatibility promise. It names the current
compiler slice so users, tests, package metadata, and tools can agree on what a
binary claims to accept, reject, or expose as metadata.

The compiler reports this surface through:

- `laniusc --version`
- `laniusc doctor`
- `laniusc diagnostics version-policy`
- `laniusc lsp capabilities`

The source constants for the current public selectors are:

| Selector | Current value |
| --- | --- |
| Language edition | `unstable-alpha` |
| Edition policy | no stable production language edition yet; accepts the current alpha slice only |
| Emit targets | `x86_64`, `wasm` |
| Default emit target | `x86_64` |
| Target triples | `x86_64-unknown-linux-gnu`, `wasm32-unknown-unknown` |
| Diagnostic formats | `text`, `json`, `lsp-json` |

Unsupported edition, emit target, target triple, or diagnostic-format selectors
should fail before source loading when possible. That failure is part of the
tooling surface, not a language parse error.

## Reading The Slice Inventory

The generated
[unstable-alpha slice reference](generated/unstable-alpha-slice.md) is the
reader-facing row index for the current edition. It is generated from
`docs/language_slice_unstable_alpha.tsv`, which is the machine-readable source
inventory. Each source row has:

| Column | Meaning |
| --- | --- |
| `kind` | Area of the language/tooling surface, such as `semantics`, `stdlib`, `packages`, `codegen`, `diagnostics`, or `tooling`. |
| `id` | Stable row name for the current claim. |
| `status` | Current support status. Today almost all rows are `bounded`; unfinished rows are `planned`. |
| `evidence_scope` | Test or artifact lane that proves the row. |
| `evidence_test` | Concrete test, command, or artifact name. |
| `evidence_contract` | Kind of proof the row requires. |
| `notes` | Short description of the accepted or fail-closed behavior. |

Allowed evidence contracts are:

- `public-boundary`
- `artifact-contract`
- `record-invariant`
- `semantic-contract`
- `execution-contract`
- `fail-closed-diagnostic`
- `measurement-scaffold`

Rows are deliberately more precise than prose. If this page and the generated
reference disagree, regenerate the reference from the TSV. If this page and the
TSV disagree, treat the TSV and the referenced tests/artifacts as the stronger
current evidence, then update this page.

```bash
tools/language_slice_summary.py --output docs/language/generated/unstable-alpha-slice.md
tools/language_slice_summary.py --check docs/language/generated/unstable-alpha-slice.md
```

## Syntax Surface

The parser grammar is [grammar/lanius.bnf](../../grammar/lanius.bnf). The
grammar is accepted syntax, not a promise that every parsed shape is
semantically supported by every backend.
Use [Lexical structure](lexical-structure.md) for tokens, comments, literals,
keywords, punctuation, and lexer/parser retag boundaries.
Use [Syntax reference](syntax.md) for the user-facing syntax chapter and this
section for the shorter support-boundary summary.
Use [Items and declarations](items-and-declarations.md) for the user-facing
item, visibility, namespace, function, extern, constant, alias, struct, enum,
trait, and impl declaration reference.
Use [Functions and calls](functions-and-calls.md) for the user-facing function
signature, parameter, argument, direct call, qualified call, generic call,
constructor call, method call, extern/runtime, and call-ABI boundary reference.
Use [Name resolution](name-resolution.md) for the user-facing rules that decide
which declaration a local name, generic parameter, import, qualified path,
enum variant, field, method, or pattern binding refers to.
Use [Generics and bounds](generics-and-bounds.md) for the user-facing generic
parameter, type argument, const parameter, trait bound, where-clause, generic
function, generic enum, alias, method, and fail-closed boundary reference.
Use [Traits and impls](traits-and-impls.md) for the user-facing trait
declaration, inherent impl, trait impl, visibility, method lookup, obligation,
dispatch-boundary, and trait diagnostic reference.
Use [Types and values](types-and-values.md) for the user-facing type/value
chapter: primitive names, aliases, constants, generics, aggregates, traits,
arrays, runtime-backed declarations, and backend boundaries.
Use [Aggregates and indexing](aggregates-and-indexing.md) for the user-facing
struct, enum, array, slice, field access, indexing, aggregate copy/assignment,
generic aggregate, and aggregate backend-boundary reference.
Use [Literals and operators](literals-and-operators.md) for the user-facing
literal families, operator precedence, unary, binary, assignment, division,
modulo, and short-circuit support-boundary reference.
Use [Expressions and control flow](expressions-and-control-flow.md) for the
user-facing statement, expression, operator, return, loop, match, call,
indexing, literal, and target execution boundaries.
Use [Patterns and matching](patterns-and-matching.md) for the user-facing match
arm, path pattern, tuple-payload pattern, literal pattern, binding, and
exhaustiveness-boundary reference.

The current grammar includes these source forms:

| Area | Current forms |
| --- | --- |
| Items | functions, extern functions, imports, module declarations, type aliases, impl blocks, trait declarations, constants, enums, structs, and `pub` item forms. |
| Function signatures | named parameters, `self`, `&self`, optional return types, generic parameters, const generic parameters, and where clauses. |
| Types | path types, type arguments, array types, slice types, references, and bounded generic type expressions. |
| Statements | `let`, `return`, `if`/`else`, `while`, `for`, `break`, `continue`, blocks, and expression statements. |
| Expressions | assignment and compound assignment, binary operators, unary operators, calls, indexing, member access, grouped expressions, paths, array literals, struct literals, literals, booleans, and `match`. |
| Patterns | path patterns, tuple-like payload patterns, integer literals, `true`, and `false`. |

Several parser-accepted forms remain bounded or fail-closed later. Examples:

- broad runtime-backed stdlib APIs type-check as source-level contracts but are
  not executable host services yet
- `wasm` is an accepted target selector but currently fails closed at the
  backend boundary
- some generic, trait, enum, aggregate, and backend-lowering shapes are accepted
  only inside the bounded rows named by the TSV

Do not infer "in the grammar" as "fully supported by every target."

## Semantic Surface

The current bounded semantic slice is tracked by the TSV, especially the
`semantics`, `imports`, `packages`, `stdlib`, and `parser-hir` rows.

Broadly, the current compiler has behavior-facing evidence for:

- scalar functions, locals, returns, conditionals, loops, calls, and selected
  aggregate records
- parser-owned HIR records and source spans feeding type checking
- module/import resolution through source roots, package manifests, and
  package lockfiles
- selected generic function, generic instance, trait-bound, method, enum, and
  predicate cases
- fail-closed diagnostics for unsupported semantic shapes that the compiler can
  recognize at a public boundary

The precise boundary is intentionally row-based. If a feature is important,
look for the row in `docs/language_slice_unstable_alpha.tsv`, then follow the
named evidence test or artifact.
Use [Modules, imports, and packages](modules-and-imports.md) for the
user-facing module identity, source-root, stdlib-root, manifest, and lockfile
rules.

## Standard Library Surface

The active standard library is source-level. It lives under
[stdlib](../stdlib/README.md) and is loaded explicitly with `--stdlib-root` or
package metadata. The generated source-level declaration reference is
[docs/stdlib/generated/reference.md](../stdlib/generated/reference.md). It is
not implicitly preloaded.

Current source-level stdlib evidence includes:

- `core` scalar helper modules such as integer, boolean, char, option, result,
  range, slice, runtime, and target metadata modules
- `std::path` lexical byte/path helper contracts
- runtime-service and runtime-bound API metadata for areas such as `std::io`,
  `std::fs`, `std::env`, `std::time`, `std::process`, `std::net`, `std::gpu`,
  and `std::thread`

Runtime-backed APIs can be known and queryable without being executable. Use:

```bash
laniusc diagnostics runtime-apis
laniusc diagnostics runtime-services
laniusc diagnostics runtime-api std::io::print_i32
```

Those commands are no-run metadata queries. They do not scan stdlib source,
compile source, create a GPU device, or prove that a runtime service is linked.

## Targets And Execution

`x86_64` is the primary executable byte-output path in `unstable-alpha`. It has
bounded execution evidence for selected scalar, branch, loop, call, source-pack,
array, division, and method cases. Unsupported native shapes should fail closed
with source-spanned diagnostics instead of silently compiling a partial target
program.

`wasm` is accepted as a target selector, but the current backend fails closed
at the backend boundary while the byte emitter is rebuilt as record/count/prefix
sum/scatter passes.

Use target-specific rows in the TSV and the backend docs when a target claim
matters:

- [Targets and output](../targets.md)
- [Codegen and backends](../compiler/codegen.md)
- [x86 backend internals](../compiler/x86-backend.md)
- [WASM backend internals](../compiler/wasm-backend.md)

## Diagnostics And Tooling

Diagnostics are part of the public language/tooling contract. The default CLI
format is text; JSON and LSP-shaped JSON are available for tools.

Useful no-run discovery commands:

```bash
laniusc diagnostics codes
laniusc diagnostics categories
laniusc diagnostics formats
laniusc diagnostics explain LNC0017
laniusc diagnostics registry
```

Use [Diagnostics](../DIAGNOSTICS.md) for payload shape, stable code metadata,
unsupported-feature boundaries, runtime metadata queries, LSP diagnostic
metadata, and renderer behavior. The generated diagnostic code index is
[docs/diagnostics/generated/error-index.md](../diagnostics/generated/error-index.md).

`laniusc check` is the current diagnostic-only compile surface. It runs the
bounded GPU diagnostic path without writing target bytes.

`laniusc fmt` is the current lexical formatter. It preserves non-whitespace
token text and token order while rewriting whitespace, newlines, and
indentation.

`laniusc lsp serve --stdio` is the current minimal JSON-RPC surface. It uses
full-document synchronization only and supports document formatting plus bounded
pull diagnostics for one open document.

## Examples

Use [Worked examples](examples.md) for copyable single-file, source-root,
stdlib-root, package-manifest, diagnostics, and formatting examples.

Small source examples also live under
[sample_programs](../../sample_programs/README.md). They are smoke examples for
the current alpha slice, not a complete language tutorial or broad backend,
conformance, package, stdlib, or performance evidence.

## Update Rule

Update this language reference when any of the following changes:

- accepted language edition or selector policy
- grammar-level syntax families
- TSV evidence schema or support-status meaning
- source-level standard library boundary
- target support boundaries
- diagnostic or tooling discovery commands
- sample-program role or location
- worked-example commands, layouts, or evidence boundaries

If a feature claim is added here, it should either point at a row in
the generated unstable-alpha slice reference, a stable diagnostics/tooling
command, the generated stdlib reference, or a source file that owns the grammar
or stdlib contract. New or changed row-level claims belong in
`docs/language_slice_unstable_alpha.tsv` first, then in the generated
reference.
