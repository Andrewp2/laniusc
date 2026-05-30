# Diagnostics

Lanius diagnostics are part of the external tool surface. The GPU compiler
should produce compact error records with stable codes and source positions; the
CPU may format those records as text or JSON.

Diagnostic and readiness metadata is not performance evidence. No-run diagnostic
commands may report registry schemas, source-pack progress, toolchain metadata,
paper-pass order, and measurement-scaffold fields, but timing, VRAM, scaling, or
Pareas comparison claims must come from fresh local measurement artifacts with
claim-readiness status marked claimable.

Use `--diagnostic-format=json` for the diagnostic JSON shape, or
`--diagnostic-format=lsp-json` for a single LSP Diagnostic-shaped JSON object.
Use `laniusc check` when a tool wants diagnostics without target bytes on
stdout.
Use `laniusc fmt --stdin` or `laniusc fmt -` when a formatter wrapper wants
formatted source on stdout without rewriting a file. Use
`laniusc fmt --check --diagnostic-format=json` for file checks, or
`laniusc fmt --stdin --check --diagnostic-format=json` for stdin checks, when a
formatter wrapper wants machine-readable formatting failures without rewriting
the input. The alpha formatter keeps brace-delimited comma items, such as
struct-literal fields and expression match arms, on separate lines so formatter
output stays scannable in diagnostics and editor integrations.
Use `laniusc diagnostics [--diagnostic-format text|json|lsp-json] registry` to
print the combined diagnostic registry JSON directly, without compiling source.
Use `laniusc diagnostics [--diagnostic-format text|json|lsp-json] categories`
to print stable diagnostic categories with their grouped code metadata and
unsupported-feature code markers, without compiling source.
Use `laniusc diagnostics [--diagnostic-format text|json|lsp-json] formats` to
print the default and accepted diagnostic render formats with their
machine-readable payload contracts, without compiling source.
Use `laniusc diagnostics [--diagnostic-format text|json|lsp-json] explain
LNC0017` to print one code-specific JSON explanation with unsupported-feature
guidance directly, without compiling source.
Use `laniusc diagnostics [--diagnostic-format text|json|lsp-json]
source-pack-progress --source-pack-artifact-root ARTIFACT_DIR [--emit wasm|x86_64]`
to print persisted source-pack work-queue progress from the artifact record for
the selected emit target, without compiling source or scanning host source text.
Use `laniusc doctor` when an editor, CI wrapper, or installer wants the local
toolchain check and the accepted diagnostic renderer contract in one no-run JSON
document. The `diagnostics` object reports `--diagnostic-format`, the default
format, accepted format names, registry schema version, diagnostic format
registry schema version, LSP diagnostic source, and UTF-16 position encoding
without compiling source.
Use `laniusc lsp [--diagnostic-format text|json|lsp-json] capabilities` to
print the current no-run editor metadata: server name/version, stdio-server
status, diagnostic registry, diagnostic source, numeric LSP severity, and the
UTF-16 position encoding used by `Diagnostic::to_lsp_diagnostic`. It also
reports the document sync contract as full-document changes only
(`change: 1`, `change_kind: "full"`, `incremental_changes: false`). The same
metadata advertises the current formatter route as `laniusc fmt --stdin` and
`laniusc fmt --stdin --check`, while explicitly reporting that the LSP server
does not provide `textDocument/formatting` yet.
Use `laniusc lsp [--diagnostic-format text|json|lsp-json] serve --stdio` for
the current minimal JSON-RPC server. It
handles `initialize`, `initialized`, `textDocument/didOpen`, full-document
`textDocument/didChange`, `textDocument/didClose`, pull diagnostics with
`textDocument/diagnostic`, `shutdown`, and `exit`. Initialize/shutdown/exit do
not compile source, create a GPU device, or run target code; document diagnostic
requests run the existing GPU type-check path and return full LSP diagnostic
reports. The initialize response sets `documentFormattingProvider` to `false`
and carries the same CLI formatter route under the `experimental.laniusc`
metadata, so editor integrations do not need to infer formatter support from
the diagnostic method list. Ranged incremental `didChange` payloads are rejected
with JSON-RPC invalid-parameters error data instead of being treated as whole
documents. Unsupported method
requests with an `id` return a JSON-RPC method-not-found error whose
`data.diagnostic` carries `LNC0028`; invalid request objects, malformed JSON
payloads, and malformed LSP framing such as a missing `Content-Length` header
return JSON-RPC errors whose `data.diagnostic` carries `LNC0029`.

## Current Code Registry

| Code | Title | Category | Primary label policy |
| --- | --- | --- | --- |
| `LNC0001` | missing source-root module | package/import loading | `required` |
| `LNC0002` | import cycle | module resolution | `required` |
| `LNC0003` | ambiguous source-root module | package/import loading | `required` |
| `LNC0004` | source-root escape | package/import loading | `required` |
| `LNC0005` | unresolved identifier | name resolution | `required` |
| `LNC0006` | type mismatch | type checking | `required` |
| `LNC0007` | unknown type | type checking | `required` |
| `LNC0008` | unsatisfied trait bound | trait solving | `required` |
| `LNC0009` | ambiguous trait bound | trait solving | `required` |
| `LNC0010` | unresolved import | module resolution | `required` |
| `LNC0011` | unsupported import form | module resolution | `required` |
| `LNC0012` | import path too deep | module resolution | `required` |
| `LNC0013` | duplicate module declaration | module resolution | `required` |
| `LNC0014` | module path too deep | module resolution | `required` |
| `LNC0015` | invalid module path | module resolution | `required` |
| `LNC0016` | syntax error | parsing | `required` |
| `LNC0017` | x86 backend boundary | native codegen | `required` |
| `LNC0018` | unsupported CLI option value | tooling | `none` |
| `LNC0019` | formatter check failed | tooling | `required` |
| `LNC0020` | unknown CLI option | tooling | `none` |
| `LNC0021` | invalid trait implementation | trait solving | `required` |
| `LNC0022` | linked-output contract descriptor | native codegen | `required` |
| `LNC0023` | missing CLI option value | tooling | `none` |
| `LNC0024` | source-root package boundary | package/import loading | `required` |
| `LNC0025` | missing CLI subcommand | tooling | `none` |
| `LNC0026` | missing CLI argument | tooling | `none` |
| `LNC0027` | call resolution failed | type checking | `required` |
| `LNC0028` | unsupported LSP method | tooling | `none` |
| `LNC0029` | invalid LSP message | tooling | `none` |
| `LNC0030` | non-source source-root module | package/import loading | `required` |
| `LNC0031` | unexpected CLI argument | tooling | `none` |
| `LNC0032` | incompatible CLI options | tooling | `none` |
| `LNC0033` | invalid generic parameter list | type checking | `required` |
| `LNC0034` | output write failed | tooling | `required` |
| `LNC0035` | output stream write failed | tooling | `none` |
| `LNC0036` | WASM backend boundary | target codegen | `required` |
| `LNC0037` | package metadata invalid | package/import loading | `none` |
| `LNC0038` | runtime service boundary | runtime binding | `required` |

## Stable Categories

Categories are part of the public diagnostics contract. They group codes for
tools that want to filter diagnostics without depending on English titles:

- `module resolution`
- `name resolution`
- `native codegen`
- `package/import loading`
- `parsing`
- `runtime binding`
- `target codegen`
- `tooling`
- `trait solving`
- `type checking`

New diagnostic codes should use one of these categories unless the language
surface needs a new externally meaningful class.

Debug and test builds assert that every `Diagnostic` uses a code from this
registry, so new externally reported errors must be registered before they can
become normal compiler output.
The compiler library also exposes the code registry and unsupported-feature
registry as pretty JSON for tooling experiments that need a machine-readable
diagnostic catalog before a full LSP exists. The same combined registry is
available from the CLI with `laniusc diagnostics registry`.
Use `laniusc::compiler::diagnostic_registry_json_pretty()` for the combined
registry document. Its top-level shape is:

```json
{
  "schema_version": 5,
  "codes": [],
  "categories": [],
  "unsupported_features": []
}
```

`codes` contains `code`, `title`, `category`, `primary_label_policy`,
`default_severity`, `lsp_source`, and `lsp_severity` entries.
`primary_label_policy` is `required` when normal reports for that code include a
primary label, and `none` when the code is intentionally spanless, such as
covered CLI option diagnostics. The LSP severity value uses the protocol's
numeric diagnostic severity, where `1` means error. `categories` contains the
stable category strings accepted by the code registry. `unsupported_features`
contains `code`, `boundary`, `summary`, and `next_step` entries for diagnostics
that mark a recognized but unsupported compiler boundary. `next_step` is a
short tooling-facing remediation hint, not a promise that the feature is
supported elsewhere.

For tools that need a compact category index for filtering or UI grouping,
`laniusc diagnostics categories` returns:

```json
{
  "schema_version": 1,
  "registry_schema_version": 5,
  "categories": [
    {
      "name": "tooling",
      "code_count": 12,
      "codes": [
        {
          "code": "LNC0018",
          "title": "unsupported CLI option value",
          "primary_label_policy": "none",
          "default_severity": "error",
          "lsp_source": "laniusc",
          "lsp_severity": 1
        }
      ],
      "unsupported_feature_codes": []
    }
  ],
  "no_run_guards": {
    "source_compilation": false,
    "gpu_device_creation": false,
    "target_codegen": false
  }
}
```

`categories` preserves the stable category order from the registry. Each group
contains only diagnostics in that category, and `unsupported_feature_codes`
lists the subset of grouped codes that also have unsupported-feature guidance.

For tools that need to choose a renderer before compiling source,
`laniusc diagnostics formats` returns:

```json
{
  "schema_version": 6,
  "cli_flag": "--diagnostic-format",
  "default_format": "text",
  "accepted_formats": ["text", "json", "lsp-json"],
  "formats": [
    {
      "name": "json",
      "output_stream": "stderr",
      "payload": "Diagnostic JSON object",
      "position_encoding": "one-based source line and column",
      "includes_source_snippet": true,
      "language_server_envelope": false,
      "check_mode_supported": true,
      "formatter_check_supported": true,
      "description": "diagnostic object preserving payload schema version, registry schema version, severity, stable code/title/category/primary-label policy, message, optional primary_label, help, and notes"
    }
  ]
}
```

The default format is `text`. The `accepted_formats` list is the stable selector
surface for wrappers, and the detailed `formats` rows describe each payload.
The current accepted format names are `text`, `json`, and `lsp-json`. All three
are supported by `laniusc check`, file-backed
`laniusc fmt --check`, and stdin `laniusc fmt --stdin --check`, emit diagnostics
on `stderr`, and do not claim a language-server publish envelope. For no-run
tooling queries such as `laniusc diagnostics ...` and `laniusc lsp ...`,
`--diagnostic-format` is a global selector and may appear before or after the
subcommand being queried; malformed `--diagnostic-format...` flags still report
the command-specific accepted surface.
Compiler diagnostics use the same renderer as stable CLI option validation
diagnostics. Today the CLI maps unsupported values for `--diagnostic-format`,
`--emit`, `--edition`, and `--target` to `LNC0018`, formatter check failures to
`LNC0019`, unknown flags in covered CLI paths to `LNC0020`, linked-output
contract descriptor failures to `LNC0022`, and missing public option selector
values such as `--emit`, `--edition`, `--target`, and `--diagnostic-format`, plus
missing public path values such as `--stdlib`, `--stdlib-root`, `--source-root`,
`--package-manifest`, `--package-lockfile`, `-o`/`--out`,
`--source-pack-manifest`, `--source-pack-library-manifest`, and
`--source-pack-artifact-root`, plus source-pack numeric limit values such as
`--source-pack-max-items`, to `LNC0023`; invalid source-pack numeric limit
values use `LNC0018` with the accepted non-negative-integer value class.
`laniusc package lock` also uses `LNC0023` for missing `--manifest` and
`-o`/`--out` values when a diagnostic renderer is selected, uses `LNC0026` when
a required `--manifest path` or `-o`/`--out path` selector is absent, and uses
`LNC0032` when `-o`/`--out` would overwrite the selected package manifest.
Unknown package, diagnostics, and LSP subcommands use `LNC0020`, missing package
subcommands use `LNC0025`, and missing diagnostics explanation codes and missing
formatter input files use `LNC0026`, and extra positional arguments on no-run
diagnostics, doctor, LSP metadata commands, and formatter multi-input validation
use `LNC0031`, through the same renderer. Incompatible public option
combinations, such as `laniusc check -o`, `laniusc fmt --stdin input.lani`, and
mutually exclusive source-pack manifest or preparation-stage selectors, use
`LNC0032` before source loading.
`--package-manifest` mixed input modes, such as combining the manifest selector
with positional input files, also use `LNC0032` before manifest or source
loading. `--package-lockfile` mixed input modes use the same diagnostic before
lockfile or source loading. Manifest and lockfile read/parse/validation failures
use `LNC0037` with separate notes for the selector, metadata path, and public
validation reason, so wrappers can render package metadata failures as JSON or
LSP JSON without treating raw compiler text as a protocol.
Source-pack descriptor mode without `--emit-contract` also uses `LNC0032`, so
wrappers can distinguish the contract-output boundary from file-loading
failures without parsing plain text.
Output path write failures, including failed target-byte writes and failed
executable-bit updates for native outputs, use `LNC0034` with a primary label
on the requested output path.
Output stream write failures for stdout target bytes or stdout linked-output
contract descriptors, including late flush failures after buffered writes, use
spanless `LNC0035` with recovery help to keep stdout open or pass
`-o`/`--out`. The diagnostic notes report output stream, operation, emit mode,
I/O error kind, and I/O error message as separate entries so wrappers can
classify broken pipes and flush failures without parsing one fused sentence.
Runtime-bound stdlib host ABI surfaces must stay separate from ordinary
diagnostic I/O failures: `std::io`, `std::fs`, `std::time`, `std::process`, and
`std::env` expose public descriptor-metadata, contract-only, and
runtime-binding probes, while linked-output descriptors with required but
unbound runtime services remain `LNC0022` contract-boundary diagnostics rather
than executable target-byte claims.
Function and method lookup failures that reach the GPU type-checker call
resolver use `LNC0027` instead of the broader assignment/type-mismatch
diagnostic. Unsupported
JSON-RPC requests sent to `laniusc lsp serve --stdio` use `LNC0028` inside the
error `data.diagnostic`, along with the supported-method list and no-run
guards. Invalid JSON-RPC request objects, malformed JSON payloads, and malformed
LSP framing such as missing `Content-Length` use `LNC0029` inside the same
error-data shape. Framing errors are reported in-band on stdout when the server
can still write a response, so editor wrappers do not need to parse stderr for
protocol mistakes. `textDocument/diagnostic` returns a full document report
whose `items` are the same LSP Diagnostic-shaped compiler diagnostics used by
`--diagnostic-format=lsp-json`, without target codegen.
Source-root imports whose canonical target is not a `.lani` file use `LNC0030`
before GPU type checking, so source-looking symlinks cannot load non-source
files as modules. Package lock generation also uses `LNC0011` for quoted
imports before writing a lockfile, because persisted import graphs must not
omit unsupported import edges. Invalid GPU-recorded generic parameter lists use
`LNC0033`.
The
covered selector/path/limit,
unknown-command/unknown-flag, missing-argument, unsupported-LSP-method,
invalid-LSP-message, and unexpected-argument diagnostics can render as
machine-readable data before source loading. Covered incompatible-option
diagnostics can also render as machine-readable data before source loading.
Other CLI argument errors may still be plain text until they are assigned stable
diagnostic classes.
JSON diagnostics carry a payload `schema_version`, the
`registry_schema_version` used for code metadata, the contextual `message`, the
registry-backed stable `title`, and the registry-backed `primary_label_policy`;
tools should use `title` when they need a message class that is less likely to
change than source-specific wording. Current stable compiler
diagnostic evidence covers single-file syntax errors,
source-root/package leading metadata syntax errors, imported source-root syntax
errors, source-root stdlib-to-user package-boundary errors, source-root
non-source canonical import targets, and single-file type
mismatches. Those paths must render public
`LNC####` diagnostics with source context instead of raw GPU or pass rejection
strings. Current stable tooling diagnostic evidence covers
unsupported emit-target JSON diagnostics, covered unknown-flag JSON diagnostics,
missing selector/path/limit-value JSON diagnostics, invalid source-pack
limit-value JSON diagnostics, package-lock missing-value JSON diagnostics,
unknown package-subcommand JSON diagnostics, unknown flags passed to no-run
diagnostic/LSP command surfaces, position-independent diagnostic-format
selectors for no-run diagnostic subcommands, extra-argument JSON diagnostics
for no-run metadata commands, diagnostic category grouping with no-run guards,
package-manifest mixed-input JSON diagnostics, invalid package metadata JSON
diagnostics, and descriptor-mode
linked-output contract failures. Output-emission evidence covers
structured output-path write failures and spanless stdout stream write-or-flush
failures with separated stream/operation/emit/error context, without source
loading or target execution. Artifact-record tooling evidence covers
source-pack work-queue progress status loaded from the persisted progress index,
with explicit guards against source loading and target codegen. LSP stdio
evidence covers
unsupported request methods, malformed LSP framing, request objects without a
string method, and malformed JSON payloads as JSON-RPC errors with stable
diagnostic data, ranged incremental change rejection, plus opened-document pull
diagnostics for malformed source.

For tools that only need one code, `laniusc diagnostics explain CODE` returns a
machine-readable explanation document and succeeds even when the code is
unknown:

```json
{
  "schema_version": 4,
  "registry_schema_version": 5,
  "requested_code": "LNC0017",
  "known": true,
  "diagnostic": {
    "code": "LNC0017",
    "title": "x86 backend boundary",
    "category": "native codegen",
    "primary_label_policy": "required",
    "default_severity": "error",
    "lsp_source": "laniusc",
    "lsp_severity": 1
  },
  "unsupported_feature": {
    "code": "LNC0017",
    "boundary": "x86 backend",
    "summary": "the program reached a native-codegen construct outside the current x86 lowering slice and is rejected instead of emitting a partial instruction prefix",
    "next_step": "use `laniusc check` for diagnostics-only validation or `--emit=wasm` until this construct is covered by x86 lowering"
  },
  "runtime_service_boundaries": null,
  "runtime_bound_apis": null
}
```

Unknown codes set `known` to `false` and use `null` for `diagnostic` and
`unsupported_feature`; `runtime_service_boundaries` and `runtime_bound_apis`
are also `null`. That query is still a successful no-run tooling request.

For `LNC0038`, the explanation document includes
`runtime_service_boundaries`: one row per known runtime service descriptor. Each
row names the diagnostic code, service id, service name, stdlib module path,
capability constant, status probe, runtime-binding probe, current status, and
whether that service is executable. In the active compiler slice every row has
`current_status: "known-unbound"` and `executable: false`, so external tools can
distinguish recognized contract-only stdlib APIs from unknown service ids
without parsing prose. It also includes `runtime_bound_apis`: one row per
currently declared runtime-bound stdlib extern API. Each API row names the
qualified API, owning module, runtime service id/name, executable probe,
runtime-binding probe, current status, and `executable: false`, so wrappers can
map calls such as `std::io::print_i32` to `LNC0038` without scraping source or
assuming that visible extern declarations are runnable.

For source-pack build dashboards and editor task integrations,
`laniusc diagnostics source-pack-progress --source-pack-artifact-root
ARTIFACT_DIR --emit wasm` returns a compact artifact-record status document:

```json
{
  "schema_version": 1,
  "artifact_root": "target/lanius-artifacts",
  "target": "wasm",
  "data_source": "source-pack work queue progress index artifact",
  "record_contract": {
    "kind": "source-pack-work-queue-progress-index",
    "schema_version": 1,
    "expected_schema_version": 1,
    "path": "target/lanius-artifacts/wasm-source-pack-work-queue-progress.json"
  },
  "status": "ready",
  "progress": {
    "work_item_count": 4,
    "artifact_item_count": 3,
    "completed_item_count": 1,
    "ready_item_count": 2,
    "ready_artifact_item_count": 1,
    "claimed_item_count": 0,
    "first_ready_item_index": 1,
    "first_ready_artifact_item_index": 1,
    "page_size": 64,
    "page_count": 1,
    "complete": false
  },
  "guards": {
    "source_compilation": false,
    "source_scanning": false,
    "gpu_device_creation": false,
    "target_codegen": false
  }
}
```

The progress command reads the persisted work-queue progress index artifact and
uses the artifact record schema version as the contract. It is intentionally
separate from `laniusc check`: it reports source-pack scheduling state, not
source diagnostics.

## Unsupported Feature Boundaries

Unsupported-feature diagnostics mean the compiler recognized the program shape
well enough to reject it at a stable boundary instead of emitting a partial
prefix artifact or leaking a raw pass failure.
Current unsupported-feature mappings are:

| Code | Boundary | Meaning | Tool next step |
| --- | --- | --- | --- |
| `LNC0011` | import form | The module resolver understood the import position but rejected the import shape. | Use module-path imports such as `import app::module;`; quoted imports are not supported in this edition. |
| `LNC0012` | import path depth | The import path exceeded the compiler's currently supported module depth. | Shorten or flatten the import path before compiling with this edition. |
| `LNC0014` | module path depth | The declared module path exceeded the compiler's currently supported module depth. | Shorten or flatten the module declaration before compiling with this edition. |
| `LNC0017` | x86 backend | The program reached a native-codegen construct outside the current x86 lowering slice and is rejected instead of emitting a partial instruction prefix. | Use `laniusc check` for diagnostics-only validation or `--emit=wasm` until this construct is covered by x86 lowering. |
| `LNC0022` | linked-output contract descriptor | Descriptor-mode linked output is expected to be JSON contract metadata, not executable bytes or incoherent descriptor data. | Treat descriptor-mode linked output as JSON contract metadata; use non-descriptor compilation when target bytes are required. |
| `LNC0024` | source-root package boundary | Source-root loading rejected an import edge that crosses from stdlib roots back into package/user source roots. | Keep stdlib modules independent from package/user roots; move shared APIs into stdlib roots or pass package sources through package manifest/lockfile metadata. |
| `LNC0036` | WASM backend | The program reached a WASM-codegen construct outside the current GPU lowering slice and is rejected instead of emitting a partial module prefix. | Use `laniusc check` for diagnostics-only validation until this construct is covered by WASM lowering. |
| `LNC0038` | runtime service binding | The program reached a stdlib or host API whose runtime service descriptor is known but not bound by the current linker/runtime contract. | Treat the API as contract metadata only, check the matching `*_requires_runtime_binding()` helper, or supply a future runtime binding before emitting executable output. |

## Format Contract

Text diagnostics render as:

```text
error[LNC0016]: syntax error
 --> app.lani:1:4
  |
1 | fn fn main() {}
  |    ^^ invalid syntax here
```

JSON diagnostics preserve the same external fields plus stable payload and
registry schema metadata, title/category metadata, and primary-label policy from
the registry:

```json
{
  "schema_version": 1,
  "registry_schema_version": 5,
  "severity": "error",
  "code": "LNC0016",
  "title": "syntax error",
  "category": "parsing",
  "primary_label_policy": "required",
  "message": "syntax error",
  "primary_label": {
    "path": "app.lani",
    "line": 1,
    "column": 4,
    "length": 2,
    "source_line": "fn fn main() {}",
    "message": "invalid syntax here"
  },
  "notes": []
}
```

Diagnostics without a source span, including current `LNC0018` CLI option
diagnostics, use `null` for `primary_label` and place option-specific details
in `notes`:

```json
{
  "schema_version": 1,
  "registry_schema_version": 5,
  "severity": "error",
  "code": "LNC0018",
  "title": "unsupported CLI option value",
  "category": "tooling",
  "primary_label_policy": "none",
  "message": "unsupported CLI option value",
  "primary_label": null,
  "notes": [
    "--emit value \"llvm\" is not supported",
    "accepted --emit values: wasm, x86_64"
  ]
}
```

Formatter check diagnostics (`LNC0019`) use the same JSON shape with a
source-spanned `primary_label` pointing at the first formatting difference, and
the formatter does not rewrite the input file when `--check` is set.

`--diagnostic-format=lsp-json` emits one LSP Diagnostic-shaped JSON object for
the failing diagnostic, including no-source CLI selector diagnostics such as
`LNC0018`. It is not a `publishDiagnostics` envelope and does not start a
language server. LSP diagnostic JSON is derived from the same `Diagnostic` value
rather than a separate error model. Ranges are zero-based and use UTF-16 code
units, matching the LSP position contract. The Lanius-specific `data` extension
has its own `schema_version`, plus the diagnostic registry schema version used
for code metadata, and repeats the `position_encoding` value so standalone
`lsp-json` consumers do not need to fetch LSP capabilities first. For registered
codes, `data` takes the stable Lanius title, category, and primary-label policy
from the diagnostic registry, not from caller-local context, so tools can filter
diagnostics without reparsing human text or immediately joining against the
registry. It also carries help and note metadata for accepted values or
remediation hints. When a source span exists, `data.primary_label` carries the
source path plus one-based line, column, length, and label message from the
compiler diagnostic; it intentionally omits `source_line` so `lsp-json` remains
snippet-free. Diagnostic notes are carried as `data.notes`; the top-level object
does not contain the legacy JSON diagnostic `notes` field. Diagnostics without a
source span omit
`data.primary_label` and use an empty zero range:

```json
{
  "range": {
    "start": { "line": 0, "character": 3 },
    "end": { "line": 0, "character": 5 }
  },
  "severity": 1,
  "code": "LNC0016",
  "source": "laniusc",
  "message": "syntax error",
  "data": {
    "schema_version": 2,
    "registry_schema_version": 5,
    "position_encoding": "utf-16",
    "title": "syntax error",
    "category": "parsing",
    "primary_label_policy": "required",
    "notes": [],
    "primary_label": {
      "path": "app.lani",
      "line": 1,
      "column": 4,
      "length": 2,
      "message": "invalid syntax here"
    }
  }
}
```

## Architecture Notes

- Diagnostic codes describe user-visible failure classes, not implementation
  helpers.
- Late semantic and backend passes should return source-addressable status rows
  derived from HIR, resolver, type, instruction, relocation, or link records.
- CPU formatting may read source files or snippets for display. It must not use
  source text as a semantic fallback for parsing, type checking, codegen, or
  linking.
