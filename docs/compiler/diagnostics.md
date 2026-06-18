# Compiler Diagnostics And Status

Diagnostics are both an internal compiler contract and a public tooling
surface. GPU phases report compact status records. Host Rust maps those records
to stable `Diagnostic` objects with source labels, registry metadata, renderers,
and no-run explanation commands.

Use this document when changing status words, diagnostic codes, source-span
mapping, CLI diagnostic output, LSP diagnostic payloads, package/source-root
diagnostics, or backend fail-closed errors. Use `generated/reference.md` for the
current parser/type-check/backend status-code inventories.

## Core Rule

The status code is not the diagnostic.

A status code is a compact transport value from a compiler phase. A diagnostic
is the user-facing object after the compiler has recovered source context,
looked up stable public metadata, attached help/notes, and selected a renderer.

Every user-facing diagnostic should answer:

1. What stable `LNC####` code describes the class of failure?
2. Which source construct should the user edit?
3. Which phase owns the rejection?
4. Which renderer and metadata command can explain it without compiling more
   source?
5. Which focused test would fail if the source label or public payload broke?

If a status cannot be mapped back to source, the status payload is usually
incomplete.

## Diagnostic Stack

| Layer | Main types or files | Responsibility |
| --- | --- | --- |
| Shader pass | phase-specific `.slang` status writes | detect a failure and write compact, source-mappable status words |
| Phase driver | parser/type-check/backend finish paths | submit work, read back status buffers, decode raw words |
| Compiler mapper | `compiler/gpu_compiler/typecheck.rs`, backend mappers, source-pack/package loaders | map phase status or loading errors to `CompileError::Diagnostic` |
| Diagnostic object | `Diagnostic`, `DiagnosticLabel`, `LspDiagnostic` | hold stable code metadata, message, primary label, help, and notes |
| Registry/explain metadata | `DIAGNOSTIC_CODE_REGISTRY`, `diagnostic_explanation`, CLI diagnostics commands | expose stable codes, categories, unsupported boundaries, runtime metadata, and renderer contracts |
| CLI/LSP renderers | `Diagnostic::render`, JSON, LSP conversion, CLI output modules | project the same diagnostic object into text, JSON, or LSP-shaped JSON |
| Tests/generated docs | registry tests, CLI tests, generated reference | prove public metadata and status inventories stay current |

Do not let these layers collapse into one another. Shaders should not own user
wording. CLI code should not infer semantic status classes from strings. Tests
should not inspect private helper names when the public diagnostic contract is
what matters.

## Stable Codes And Registry

Stable diagnostic codes live in `DIAGNOSTIC_CODE_REGISTRY`. A registry row
contains:

- code
- title
- category
- primary-label policy
- default severity
- LSP source
- numeric LSP severity

The registry is the source of truth for public diagnostic identity. It is
consumed by:

- `Diagnostic::error`, which canonicalizes selector forms and attaches registry
  metadata
- `laniusc diagnostics registry`
- `laniusc diagnostics codes`
- `laniusc diagnostics code CODE`
- `laniusc diagnostics categories`
- `laniusc diagnostics explain CODE`
- LSP capability metadata
- JSON and LSP diagnostic renderers

The registry is sorted and unique by test. Adding a new `LNC####` code is a
public metadata change, not just a local error-message edit. It should update
the registry row, any explanation metadata, focused tests, and generated
reference checks when the registry or a status-code inventory changed.

Do not duplicate the full code table in hand-written docs. Use the registry
commands, the public
[generated diagnostic code index](../diagnostics/generated/error-index.md), or
the [Stable Diagnostic Codes](generated/reference.md#stable-diagnostic-codes)
section of the compiler generated reference when a source-location inventory is
needed.

## Diagnostic Object

`Diagnostic` is the structured object carried by `CompileError::Diagnostic`.
It stores:

- rendered diagnostic JSON schema name/version
- diagnostic registry schema version
- severity
- code, title, category, and primary-label policy
- `laniusc diagnostics explain CODE` command
- occurrence-specific message
- optional primary source label
- optional help text
- notes

All renderers are projections of this one object. If text, JSON, and LSP output
need different facts, put the fact on `Diagnostic` or derived LSP metadata
instead of recomputing it in one renderer.

`Diagnostic::error` also attaches default help for unsupported-feature
diagnostics. Keep that help actionable and public: it should tell a user or tool
what boundary was hit and what command or source shape can recover.

## Output Formats

The accepted diagnostic formats are exposed by
`DIAGNOSTIC_OUTPUT_FORMATS` and `laniusc diagnostics formats`:

| Format | Shape | Source positions |
| --- | --- | --- |
| `text` | human-readable stderr diagnostic | one-based line and column with optional source snippet |
| `json` | versioned `Diagnostic` JSON object | one-based line and column plus optional byte span |
| `lsp-json` | single LSP `Diagnostic`-shaped JSON object | zero-based UTF-16 range, with Lanius metadata under `data` |

All three formats should carry the same stable code and message. JSON and LSP
payloads must keep schema names and versions so wrappers can detect contract
changes without scraping text.

`lsp-json` is a diagnostic object, not a `publishDiagnostics` envelope. The
stdio LSP server has separate protocol responses for pull diagnostics.

## Parser Status

Parser LL/HIR construction reports six words:

| Word | Meaning |
| --- | --- |
| `0` | accepted flag |
| `1` | token position for the primary source location |
| `2` | parser error code |
| `3` | status-specific detail |
| `4` | LL/action step count |
| `5` | production/HIR emission length |

The generated reference extracts this layout from `parser/driver/results.rs`.
The compiler maps parser failures through:

- `parser_ll1_error_to_compile_error_for_source`
- `parser_ll1_error_to_compile_error_for_source_pack`

Single-source diagnostics use the caller-supplied path or `<source>`.
Source-pack diagnostics read the rejected token, find the file that owns the
global byte span, convert it to a file-local span, and then build `LNC0016`.

Parser diagnostics should point at the token or source span where syntax became
invalid. They should not report the parser action, production id, or table row
as the user-facing location.

## Type-Check Status

The resident type checker owns a four-word status buffer:

| Word | Meaning |
| --- | --- |
| `0` | accepted flag |
| `1` | token or source-related index |
| `2` | `GpuTypeCheckCode` |
| `3` | status-specific detail |

`GpuTypeCheckCode` is decoded in `type_checker/mod.rs`. The current numeric
mapping is generated into `generated/reference.md` under GPU type-check status
codes.

Host mapping happens in `compiler/gpu_compiler/typecheck.rs`. There are separate
paths for single-source and source-pack inputs because source-pack token spans
are global across concatenated source. When adding or changing a type-check
status, update both paths or prove one cannot reach the status.

Good type-check statuses carry one of:

- the source token that introduced the bad spelling
- a HIR node with retained token-position metadata
- a path id whose owner token can be recovered
- a call/type/member/predicate row that stores the introducing token or HIR node

The detail word can refine the explanation, but it is rarely enough for a
primary label.

## Backend Status

Backends report target-specific failures after parser and type-check status
have accepted the input. Backend diagnostics must use retained parser or
type-check metadata; they should not rerun semantic analysis.

x86 backend status uses named `X86_ERR_*` constants and classifies the detail
payload with helper logic such as whether the detail is a HIR node or token.
The generated reference extracts those constants. When adding a backend status:

1. name the backend status constant
2. decide whether the detail payload is token, HIR node, row id, or target-only
   metadata
3. preserve enough retained metadata to map source locations
4. map the failure to a stable diagnostic code such as a backend-boundary code
5. prove that no partial target artifact is emitted before the fail-closed
   diagnostic

WASM should stay aligned with shared frontend/type-check diagnostics and fail
closed for unsupported backend slices. See
[WASM backend internals](wasm-backend.md) for `WasmOutputError` detail
classification, source-pack token mapping, and fallback label behavior.

## Source Mapping

Source mapping is the difference between an internal rejection and a usable
diagnostic.

`diagnostic_label_from_source_span` converts a byte span into a primary label.
It snaps byte offsets to UTF-8 boundaries, computes one-based text coordinates,
preserves optional byte start/end offsets, trims CRLF lines for text rendering,
and keeps the full source line for snippets and LSP range conversion.

`DiagnosticLabel` stores one-based line/column for text and JSON. LSP conversion
turns the same label into zero-based UTF-16 positions and preserves the original
one-based label metadata under `data.primary_label`.

Source-pack diagnostics use `DiagnosticSourceFile` rows:

- display path
- source text
- global start offset in the concatenated source-pack stream
- global end offset

When a token from source-pack lexing reports a global byte offset, the mapper
finds the owning file and converts the span to a local offset before building
the label.

Do not surface:

- token ids
- HIR ids
- module ids
- source-root indexes
- source-pack job ids
- GPU capacity counters

These are debugging facts. A user-facing diagnostic should recover path, line,
column, source line, and a narrow label.

## Metadata And Explainability

The diagnostics CLI mirrors rustc-style explainability, but it is deliberately
machine-readable and no-run.

Important no-run commands:

| Command | Purpose |
| --- | --- |
| `laniusc diagnostics registry` | full registry, categories, unsupported-feature rows, codegen-boundary rows |
| `laniusc diagnostics codes` | compact code index for completion and lookup UIs |
| `laniusc diagnostics code CODE` | focused code lookup with `known` result |
| `laniusc diagnostics explain CODE` | code explanation with unsupported/codegen/runtime metadata when applicable |
| `laniusc diagnostics categories` | category grouping and unsupported-feature code markers |
| `laniusc diagnostics formats` | renderer contracts and schema metadata |
| `laniusc diagnostics runtime-*` | known-unbound runtime service/API metadata |
| `laniusc diagnostics source-pack-progress ...` | persisted work-queue progress without compiling source |

These commands must not compile source, scan source roots, create a GPU device,
or run target codegen. Their payloads carry no-run guard metadata for wrappers.

Unknown code or runtime selectors should usually be successful metadata queries
with `known: false`, selector examples, and discovery commands. Do not turn
unknown metadata lookup into a source-loading or stderr diagnostic failure.

The generated reference also publishes a Markdown code index extracted from the
same registry. That index is for compiler-author browsing and review. The CLI
commands remain the machine-readable public surface for tools.

## Unsupported And Fail-Closed Boundaries

Some diagnostics intentionally describe unsupported compiler slices:

- import forms not represented by GPU module/import records
- path-depth limits
- backend lowering gaps
- descriptor/target-byte boundary confusion
- runtime services known to the compiler but not bound by the runtime

These are still real diagnostics. They should fail closed, explain the boundary,
and avoid producing partial target artifacts or incomplete persisted metadata.

Unsupported-feature metadata lives beside the diagnostic registry so tools can
explain the current boundary without running a compile. If a boundary becomes
supported, remove or update that metadata rather than leaving stale "unsupported"
guidance behind.

## CLI And Tooling Errors

CLI diagnostics are part of the same public surface. Argument parsing,
incompatible options, missing values, output-write failures, formatter checks,
LSP protocol errors, package metadata failures, and input-read failures should
use stable `Diagnostic` objects when the failure is intended for users or tools.

Plain message errors are acceptable only for internal or transitional failures
that have not become a public diagnostic contract. New public CLI behavior
should prefer a registered code and renderer-compatible diagnostic.

No-run commands, such as `doctor`, `diagnostics`, `lsp capabilities`, and
formatter metadata surfaces, should report contracts without accidentally
creating GPU devices, probing source trees, or starting codegen.

## Adding A Diagnostic

Checklist:

1. Choose the earliest phase that has enough information to detect the problem.
2. Decide whether this is parser, type-check, backend, package/source-root,
   source-pack, CLI/tooling, LSP, formatter, or runtime metadata.
3. Add or reuse a compact status code when the error crosses a GPU boundary.
4. Carry a source-mappable payload: token, HIR node, path owner, row with token
   metadata, or a concrete source span.
5. Add a stable `LNC####` registry row if this is a new public class.
6. Add explanation metadata when the code represents an unsupported or
   fail-closed boundary.
7. Map the failure to `CompileError::Diagnostic` at the host boundary that owns
   source text and diagnostic paths.
8. Preserve single-source and source-pack mapping when both can reach the
   failure.
9. Add a focused test with the smallest source, CLI invocation, or metadata
   query that proves the public contract.
10. Regenerate or check `generated/reference.md` if diagnostic registry rows,
    parser/type-check/backend status inventories, public operations, or
    renderer-visible structs changed.

For fixed pass-count exhaustion, the status should point at the source
construct whose shape exceeded the algorithmic limit. Prefer eliminating the
limit with scan/range-query/segmented storage, but if a bound remains, the
diagnostic must name the source shape rather than reporting only that an
internal loop ran out. See [Capacity and limits](capacity-and-limits.md) for
the broader policy on storage bounds, dispatch bounds, and language limits.

## Test Evidence

Diagnostics tests should prove the public contract:

| Contract | Useful evidence |
| --- | --- |
| registry row | sorted/unique registry test, category coverage, code lookup |
| renderer shape | text, JSON, and LSP payload assertions over stable fields |
| parser rejection | smallest invalid source with `LNC0016` and correct label |
| type-check rejection | smallest semantic source with stable code and label |
| source-pack mapping | multi-file source-pack fixture whose failure labels the right file |
| backend fail-closed | smallest backend input proving code and no partial artifact |
| CLI/tooling error | public command invocation and diagnostic-format assertions |
| no-run metadata | command output plus guard fields proving no compile/source scan/GPU/codegen |

Avoid tests that assert private shader filenames, bind-group labels, helper
function names, or raw row ids when the public diagnostic is the contract. Use
generated-reference checks for inventories and focused behavior tests for
diagnostic payloads.

## Common Mistakes

Avoid these:

- adding a `GpuTypeCheckCode` without a source-mappable payload
- mapping single-source diagnostics but forgetting source-pack diagnostics
- returning `GpuTypeCheck(err.to_string())` for a user-facing semantic failure
- creating CLI text that bypasses `Diagnostic`
- adding a registry code without explanation metadata for an unsupported
  boundary
- changing JSON/LSP payload fields without bumping schema versions and tests
- using source-root/package metadata as a substitute for source labels
- treating diagnostic metadata commands as readiness or performance evidence
- hiding a backend lowering gap behind a partial target artifact

Diagnostics are only useful when they are stable enough for tools and precise
enough for a human to edit the right source code.
