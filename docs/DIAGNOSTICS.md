# Diagnostics

Lanius diagnostics are part of the external tool surface. The GPU compiler
should produce compact error records with stable codes and source positions; the
CPU may format those records as text or JSON.

Diagnostic and readiness metadata is not performance evidence. No-run diagnostic
commands may report registry schemas, source-pack progress, toolchain metadata,
paper-pass order, and measurement-scaffold fields, but timing, VRAM, scaling, or
Pareas comparison claims must come from fresh local measurement artifacts with
claim-readiness status marked claimable.

Readiness evidence for external diagnostics must come from the public registry,
CLI, artifact, or protocol payloads. Tests that inspect compiler or shader
source text, helper names, command implementation details, or private tables do
not establish the external diagnostic contract.
`tools/compiler_acceptance.sh --tier readiness --check-plan` cross-checks the
language-slice diagnostic/tooling rows against the non-scale acceptance plan so
registered-code, registry/code-index/focused-code/category/explain/format, runtime
API/service, formatter, LSP protocol, package, and command-discovery evidence
stays behavior-facing and no-run.

Use `--diagnostic-format=json` for the diagnostic JSON shape, or
`--diagnostic-format=lsp-json` for a single LSP Diagnostic-shaped JSON object.
Use `laniusc check` when a tool wants diagnostics without target bytes on
stdout.
Unknown-option invocation diagnostics include public `help` metadata as well
as notes listing the rejected option and accepted options, so wrappers can show
recovery guidance without parsing the text renderer output.
Missing CLI argument/subcommand diagnostics and unknown-subcommand diagnostics
carry the same public `help` metadata, pointing at the focused `--help`
surface for the command that rejected the invocation.
Use `laniusc fmt --stdin` or `laniusc fmt -` when a formatter wrapper wants
formatted source on stdout without rewriting a file. Use
`laniusc fmt --check --diagnostic-format=json` for file checks, or
`laniusc fmt --stdin --check --diagnostic-format=json` for stdin checks, when a
formatter wrapper wants machine-readable formatting failures without rewriting
the input. LSP formatter metadata publishes the exact request options currently
accepted by `textDocument/formatting`: `params.options` is required,
`tabSize` must be `4`, and `insertSpaces` must be `true`.
The alpha formatter keeps brace-delimited comma items, such as
struct-literal fields and expression match arms, on separate lines so formatter
output stays scannable in diagnostics and editor integrations.
Use `laniusc diagnostics [--diagnostic-format text|json|lsp-json] registry` to
print the combined diagnostic registry JSON directly, without compiling source.
Use `laniusc diagnostics [--diagnostic-format text|json|lsp-json] codes` to
print a compact diagnostic code index for wrapper completion, lookup, and
filter UIs, without compiling source.
For the generated reader-facing code index, use
`docs/diagnostics/generated/error-index.md`. Regenerate it with
`tools/diagnostic_index.py --output docs/diagnostics/generated/error-index.md`
and check it with
`tools/diagnostic_index.py --check docs/diagnostics/generated/error-index.md`.
For maintained user-facing explanations of what each `LNC####` code means and
what to do next, use `docs/diagnostics/code-explanations.md`.
Use `laniusc diagnostics [--diagnostic-format text|json|lsp-json] code
LNC0018` to print one compact diagnostic code row, or a successful `known:
false` JSON payload for an unknown code, without compiling source.
The readiness gate treats `diagnostics codes` and focused `diagnostics code`
lookup as the same wrapper-facing code discovery contract: the focused payload
must use `schema_name: "laniusc.diagnostics.code"`, report `known`, project the
same diagnostic row as the public code index for known selectors, publish
selector examples/patterns plus `diagnostics codes` and `diagnostics registry`
recovery commands, and carry the same no-run guards.
Use `laniusc diagnostics code --help` for selector-specific help and copyable
examples without attempting a code lookup.
Use `laniusc diagnostics explain --help` for explanation-specific selector
help and unknown-code behavior without attempting an explanation lookup.
The focused code payload includes accepted selector examples, selector pattern
descriptions, and copyable `diagnostics codes` / `diagnostics registry`
discovery commands so wrapper UIs can recover from an unknown code without
scraping help text.
Use `laniusc diagnostics [--diagnostic-format text|json|lsp-json] categories`
to print stable diagnostic categories with their grouped code metadata and
unsupported-feature code markers, without compiling source.
Use `laniusc diagnostics [--diagnostic-format text|json|lsp-json] formats` to
print the default and accepted diagnostic render formats with their
machine-readable payload contracts, without compiling source.
Use `laniusc diagnostics [--diagnostic-format text|json|lsp-json] formatter`
to print the alpha formatter policy with its schema identity,
token-preservation contract, file/stdin CLI commands, LSP formatting request
options, diagnostic codes, and no-run guards, without compiling source,
scanning source roots, creating a GPU device, invoking Slang, or running Pareas.
Use `laniusc diagnostics [--diagnostic-format text|json|lsp-json] commands`
to print the no-run metadata command index directly, including command schema
names, focused command placeholders, selector examples, selector result
policies, per-command selector/input/artifact classifications, and no-run
guards.
Use `laniusc diagnostics [--diagnostic-format text|json|lsp-json]
version-policy` when a wrapper needs machine-readable compiler package version,
language edition, release/distribution status, compatibility policy, target
surface, and tooling schema versions without scraping `--version` text,
compiling source, probing Slang, running shader audits, or invoking Pareas.
Use `laniusc diagnostics [--diagnostic-format text|json|lsp-json] explain
LNC0017` to print one code-specific JSON explanation with unsupported-feature
guidance, a canonical explain command, selector examples, and discovery commands
directly, without compiling source.
Use `laniusc diagnostics [--diagnostic-format text|json|lsp-json] runtime-api
std::io::print_i32` or `runtime-api stdio::print_i32` to print the known-unbound
runtime binding row and owning runtime service boundary for one qualified or
service-qualified stdlib API, without compiling source or scanning stdlib
files.
Use `laniusc diagnostics [--diagnostic-format text|json|lsp-json] runtime-apis`
to print the full known-unbound stdlib runtime-bound API index and service
boundary table, without compiling source or scanning stdlib files.
Use `laniusc diagnostics [--diagnostic-format text|json|lsp-json]
runtime-service std::io` to print one known-unbound runtime service boundary by
service id, service name, module path, capability constant, status probe,
binding probe, qualified runtime-bound API, or service-qualified API such as
`stdio::print_i32`, without compiling source or scanning stdlib files.
Use `laniusc diagnostics [--diagnostic-format text|json|lsp-json]
runtime-service-apis std::io` to print the known-unbound runtime-bound API rows
owned by one runtime service selected by service id, service name, module path,
capability constant, status probe, binding probe, or qualified runtime-bound
API, or service-qualified API such as `stdio::print_i32`, without compiling
source or scanning stdlib files.
Use `laniusc diagnostics [--diagnostic-format text|json|lsp-json]
runtime-services` to print the known-unbound runtime service boundary table
directly, without compiling source or scanning stdlib files.
The runtime metadata commands publish stable payload identities through
`schema_name`: `laniusc.diagnostics.runtime-api`,
`laniusc.diagnostics.runtime-apis`,
`laniusc.diagnostics.runtime-service`,
`laniusc.diagnostics.runtime-service-apis`, and
`laniusc.diagnostics.runtime-services`.
Unknown runtime API or service selectors remain successful no-run metadata
queries with `known: false`, null matched rows, and the same `no_run_guards`;
they also carry accepted selector kinds, concrete selector examples, and
discovery commands, so they do not become stderr diagnostics or source-loading
failures just to explain the valid lookup surface.
Focused runtime selector commands are copy/paste friendly: `runtime-api`,
`runtime-service`, and `runtime-service-apis` treat a value copied from JSON
with its surrounding double quotes the same as the unquoted selector. For
example, `"std::io::print_i32"`, `"stdio::print_i32"`, and `"std::io"` resolve
like `std::io::print_i32`, `stdio::print_i32`, and `std::io`; wrappers should
use the returned `selector_examples`, `runtime_api_index_command`, and
`runtime_service_index_command` fields to show valid selector shapes and bulk
discovery commands.
Use `laniusc diagnostics [--diagnostic-format text|json|lsp-json]
source-pack-progress --source-pack-artifact-root ARTIFACT_DIR [--emit wasm|x86_64]`
to print persisted source-pack work-queue progress from the artifact record for
the selected emit target, without compiling source or scanning host source text.
The source-pack progress payload publishes
`schema_name: "laniusc.diagnostics.source-pack-progress"` and the standard
`no_run_guards` object.
Use `laniusc doctor` when an editor, CI wrapper, or installer wants the local
toolchain check and the accepted diagnostic renderer contract in one no-run JSON
document. The `diagnostics` object reports `--diagnostic-format`, the default
format, accepted format names, registry schema version, diagnostic format
registry schema version, LSP diagnostic source, and UTF-16 position encoding
without compiling source. The `distribution` object reports the current release
boundary: this worktree is not a production release, has no stable install
artifact or package-manager channel, has no release-artifact workflow yet, and
requires source-control provenance before any production-readiness claim. The
`toolchain.slangc` probe is bounded; if the configured `SLANGC` or `PATH`
candidate stalls, doctor returns `status: "action-required"` with
`toolchain.slangc.status: "error"`, `error_kind: "timeout"`, the attempted
version argument, and the timeout budget in milliseconds instead of waiting for
the process indefinitely. Wrappers that need metadata without launching a
runtime Slang subprocess can pass `--skip-slangc-probe`; the report then uses
`status: "not-checked"`, `toolchain.slangc.status: "skipped"`, and
`toolchain.slangc.probe_attempted: false` while still reporting the configured
`SLANGC` or `PATH` selector. The `toolchain.build_timeouts` object reports the
build-script timeout budgets used for Slang version probing and shader
compilation so wrappers can distinguish the runtime doctor probe from
build-time guardrails. The
`readiness` object reports the default no-run inventory gate,
`tools/compiler_acceptance.sh --tier readiness --check-plan`, marks generated
scale and Pareas lanes as opt-in, and keeps paper numbers reference-only until
local artifacts and claimable pass/link contracts exist. Its
`test_discipline` object names the same no-run inventory policy used by the
acceptance gate: named test filters must resolve, duplicate same-lane evidence
is rejected, Rust integration tests are audited for compiler/shader
product-source inspection, and source-scoped evidence is restricted to public,
artifact, execution, or measurement-scaffold contracts. The `pass_contracts`
object reports the shader-loop audit commands and paper/Pareas primitive
requirements without running the audit, including the dedicated source-sized
symbolic-cap gate used to keep `MAX_*_NODES`-style caps out of performance
claims until they are justified or rewritten. The
`stdlib` object reports the current external
stdlib boundary: the library is not auto-imported, callers must pass
`--stdlib-root stdlib`, root loading does not rewrite source, and host/runtime
APIs remain known-unbound contracts rather than executable services. Doctor
keeps that payload compact by reporting runtime service/API counts and pointing
at `laniusc diagnostics explain LNC0038`, `diagnostics runtime-apis`, and
`diagnostics runtime-services` for row-level runtime metadata. It does not scan
stdlib source or execute readiness gates while reporting this contract.
Use `laniusc lsp [--diagnostic-format text|json|lsp-json] capabilities` to
print the current no-run editor metadata: server name/version, stdio-server
status, diagnostic registry, diagnostic format registry, diagnostic source,
numeric LSP severity, and the UTF-16 position encoding used by
`Diagnostic::to_lsp_diagnostic`. It also reports the document sync contract as
full-document changes only
(`change: 1`, `change_kind: "full"`, `incremental_changes: false`). The same
metadata advertises the current formatter route as `laniusc fmt --stdin` and
`laniusc fmt --stdin --check`, and reports document formatting support through
`textDocument/formatting` with a single full-document replacement edit when the
lexical formatter changes the open document, without source scanning,
compilation, GPU device creation, or target codegen. It also advertises the
JSON-RPC transport contract as
`schema_name: "laniusc.lsp.transport"`, `schema_version: 1`, so editor
wrappers can discover the stdio framing boundary without trial messages:
`Content-Length` framing, byte-counted UTF-8 JSON-RPC bodies, stdout responses,
no stderr diagnostics, parse-error responses for malformed frames, and explicit
request/notification method groups. It also advertises the
JSON-RPC error-data payload identity as
`schema_name: "laniusc.lsp.error-data"`, `schema_version: 2`, so editor
wrappers can recognize protocol error `data` without inferring the shape from
incidental fields. The same `error_data` metadata includes an
`unsupported_method` contract: requests with an `id` return JSON-RPC
method-not-found (`-32601`) error data carrying `LNC0028`,
`failure_boundary: "lsp-method-dispatch"`, `requested_method`, and
`supported_methods`; unsupported notifications are ignored without a protocol
response or diagnostic. Its document-diagnostics
metadata is an explicit pull-diagnostics contract for single open-document text: full
reports only, no `publishDiagnostics` envelope, no workspace diagnostics, no
inter-file dependency claims, no result-id cache, no source scanning, and no
source-root or stdlib-root loading. The same LSP metadata now carries the
release/distribution boundary from `--version` and `doctor`: this is a
`source-worktree`, not a production release, with no stable install artifact or
package-manager channel. The top-level capabilities document uses schema
version 15, and the initialize-response `experimental.laniusc` metadata uses
schema version 13 for the same source-scanning, transport, error-data,
distribution, formatter request-options, formatter policy, and LSP lifecycle
guards.
Use `laniusc lsp [--diagnostic-format text|json|lsp-json] serve --stdio` for
the current minimal JSON-RPC server. It
handles `initialize`, `initialized`, `textDocument/didOpen`, full-document
`textDocument/didChange`, `textDocument/didClose`, pull diagnostics with
`textDocument/diagnostic`, `shutdown`, and `exit`. Initialize/shutdown/exit do
not compile source, create a GPU device, or run target code; document diagnostic
requests run the existing GPU type-check path and return full LSP diagnostic
reports. The initialize response sets `documentFormattingProvider` to `true`
and carries the same diagnostic format registry and formatter metadata under
the `experimental.laniusc` metadata. `textDocument/formatting` requests must
name an open document and include a `params.options` object with positive LSP
uinteger `tabSize` and boolean `insertSpaces`; malformed formatting parameters
return JSON-RPC invalid-parameters error data carrying `LNC0029` and do not
rewrite the stored document. `didOpen` requests must use the advertised
`languageId: "lanius"`; other language ids are rejected with JSON-RPC
invalid-parameters error data and do not open the document. Ranged incremental
`didChange` payloads
and full-document change items without string `text` are rejected with JSON-RPC
invalid-parameters error data instead of being treated as whole documents or
silently skipped.
Before the server answers `initialize`, it accepts only `initialize` and
`exit`: later stateful requests with an `id` return JSON-RPC
`ServerNotInitialized` error data carrying `LNC0029`, and stateful
notifications are ignored without opening documents, formatting, or running
diagnostics.
After the server answers `shutdown`, it accepts only the `exit` notification:
later requests with an `id` return JSON-RPC invalid-request error data carrying
`LNC0029`, and later notifications are ignored without starting formatting or
diagnostic work.
Repeated `initialize` requests after the first successful initialize response
return JSON-RPC invalid-request error data carrying `LNC0029`; the server keeps
the existing session state instead of reinitializing or dropping open-document
state.
The same lifecycle policy is published in `laniusc lsp capabilities` and in the
initialize response under `experimental.laniusc.lifecycle`, so editors can
learn the accepted pre-initialize and post-shutdown method sets without first
triggering an error.
Unsupported method
requests with an `id` return a JSON-RPC method-not-found error whose
`data.diagnostic` carries `LNC0028`; invalid request objects, malformed JSON
payloads, request objects without `jsonrpc: "2.0"`, valid JSON bodies that are
not request objects, and malformed LSP framing such as a missing
`Content-Length` header return JSON-RPC errors whose `data.diagnostic` carries
`LNC0029`. Those protocol error payloads include
`schema_name: "laniusc.lsp.error-data"`, `schema_version: 2`, and
`no_run_guards.source_scanning: false` so editor wrappers can distinguish
protocol validation from filesystem source discovery. When a malformed frame
still has a parseable `Content-Length`, the stdio server drains that body before
reporting the framing diagnostic so the next valid frame remains aligned.
The same request/notification split for unsupported methods is discoverable in
`laniusc lsp capabilities` and the initialize response under
`error_data.unsupported_method`, including the no-run guards showing that this
protocol classification does not scan source, create a GPU device, or run codegen.

## Current Code Registry

The current code registry is generated at
`docs/diagnostics/generated/error-index.md` from
`DIAGNOSTIC_CODE_REGISTRY`. Treat that file as the docs-side analogue of
rustc's error-code index. Do not maintain a second hand-written table here.

```bash
tools/diagnostic_index.py --output docs/diagnostics/generated/error-index.md
tools/diagnostic_index.py --check docs/diagnostics/generated/error-index.md
```

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
  "schema_version": 7,
  "schema_name": "laniusc.diagnostics.registry",
  "codes": [],
  "categories": [],
  "unsupported_features": [],
  "no_run_guards": {
    "source_compilation": false,
    "source_scanning": false,
    "gpu_device_creation": false,
    "target_codegen": false
  }
}
```

`schema_name` is the stable payload identity; use it with `schema_version`
instead of inferring the document kind from incidental fields. `codes` contains
`code`, `title`, `category`, `primary_label_policy`,
`default_severity`, `lsp_source`, and `lsp_severity` entries.
`primary_label_policy` is `required` when normal reports for that code include a
primary label, and `none` when the code is intentionally spanless, such as
covered CLI option diagnostics. The LSP severity value uses the protocol's
numeric diagnostic severity, where `1` means error. `categories` contains the
stable category strings accepted by the code registry. `unsupported_features`
contains `code`, `boundary`, `summary`, and `next_step` entries for diagnostics
that mark a recognized but unsupported compiler boundary. `no_run_guards` marks
the registry query as metadata-only: it does not compile source, scan source
roots, create a GPU device, or run target codegen. `next_step` is a
short tooling-facing remediation hint, not a promise that the feature is
supported elsewhere.

For tools that only need the code list, `laniusc diagnostics codes` returns the
same public code rows without unsupported-feature guidance:

```json
{
  "schema_version": 1,
  "schema_name": "laniusc.diagnostics.codes",
  "registry_schema_version": 7,
  "code_count": 40,
  "codes": [
    {
      "code": "LNC0018",
      "title": "unsupported CLI option value",
      "category": "tooling",
      "primary_label_policy": "none",
      "default_severity": "error",
      "lsp_source": "laniusc",
      "lsp_severity": 1,
      "explain_command": "laniusc diagnostics explain LNC0018"
    }
  ],
  "no_run_guards": {
    "source_compilation": false,
    "source_scanning": false,
    "gpu_device_creation": false,
    "target_codegen": false
  }
}
```

`code_count` matches the number of rows in `codes`, and each row preserves the
same stable registry-backed fields as the full combined registry, plus the
matching no-run explanation command. The code index is validated as a projection
of the CLI registry output itself, so tools do not need to rely on compiler
source text or a separate private list to detect missing or phantom diagnostic
codes. `schema_name` is the stable payload identity for this compact projection.
For a focused lookup, `laniusc diagnostics code CODE` returns one compact row
with `known: true`, or `known: false` with `diagnostic: null` for unknown codes,
plus accepted selector examples, selector pattern descriptions, and copyable
`code_index_command` / `registry_command` values so detail panes can recover
from a bad copied code without scraping help text or loading source.

For tools that need a compact category index for filtering or UI grouping,
`laniusc diagnostics categories` returns:

```json
{
  "schema_version": 3,
  "schema_name": "laniusc.diagnostics.categories",
  "registry_schema_version": 7,
  "categories": [
    {
      "name": "tooling",
      "code_count": 12,
      "codes": [
        {
          "code": "LNC0018",
          "title": "unsupported CLI option value",
          "category": "tooling",
          "primary_label_policy": "none",
          "default_severity": "error",
          "lsp_source": "laniusc",
          "lsp_severity": 1,
          "explain_command": "laniusc diagnostics explain LNC0018"
        }
      ],
      "unsupported_feature_codes": []
    }
  ],
  "no_run_guards": {
    "source_compilation": false,
    "source_scanning": false,
    "gpu_device_creation": false,
    "target_codegen": false
  }
}
```

`categories` preserves the stable category order from the registry. Each group
contains only diagnostics in that category, and `unsupported_feature_codes`
lists the subset of grouped codes that also have unsupported-feature guidance.
Grouped code rows use the same fields as the compact code index so filtering
tools can link directly to `diagnostics explain CODE` without joining outputs.
`schema_name` is the stable payload identity for this grouped projection.

For tools that need to choose a renderer before compiling source,
`laniusc diagnostics formats` returns:

```json
{
  "schema_version": 9,
  "schema_name": "laniusc.diagnostics.output-formats",
  "cli_flag": "--diagnostic-format",
  "default_format": "text",
  "accepted_formats": ["text", "json", "lsp-json"],
  "formats": [
    {
      "name": "json",
      "output_stream": "stderr",
      "payload": "Diagnostic JSON object",
      "payload_schema_name": "laniusc.diagnostics.rendered-json",
      "payload_schema_version": 3,
      "payload_schema_location": "top-level",
      "position_encoding": "one-based source line and column",
      "includes_source_snippet": true,
      "language_server_envelope": false,
      "check_mode_supported": true,
      "formatter_check_supported": true,
      "description": "diagnostic object preserving payload schema name/version, registry schema version, severity, stable code/title/category/primary-label policy, help, explain command, message, optional primary_label, and notes"
    }
  ],
  "no_run_guards": {
    "source_compilation": false,
    "source_scanning": false,
    "gpu_device_creation": false,
    "target_codegen": false
  }
}
```

The default format is `text`. The `accepted_formats` list is the stable selector
surface for wrappers, and the detailed `formats` rows describe each payload.
Machine-readable rows also publish `payload_schema_name`,
`payload_schema_version`, and `payload_schema_location`: `json` uses the
rendered diagnostic schema at the top level, while `lsp-json` uses the Lanius
diagnostic metadata schema under the LSP Diagnostic `data` field. Text
diagnostics keep those fields `null`.
Each accepted selector has exactly one `formats` row, and every row name is one
of the accepted selectors, so wrappers can treat the two fields as the same
format set at different detail levels. `schema_name` is the stable payload
identity for renderer discovery, and `no_run_guards` is part of schema version
9 so wrappers can confirm renderer discovery does not compile source, scan
source roots, create a GPU device, or run target codegen.
The current accepted format names are `text`, `json`, and `lsp-json`. All three
are supported by `laniusc check`, file-backed
`laniusc fmt --check`, and stdin `laniusc fmt --stdin --check`, emit diagnostics
on `stderr`, and do not claim a language-server publish envelope. For no-run
tooling queries such as `laniusc diagnostics ...` and `laniusc lsp ...`,
`--diagnostic-format` is a global selector and may appear before or after the
subcommand being queried; malformed `--diagnostic-format...` flags still report
the command-specific accepted surface.

For tools that need release, edition, compatibility, and schema policy without
scraping human-readable `--version` text, `laniusc diagnostics version-policy`
returns:

```json
{
  "schema_version": 6,
  "schema_name": "laniusc.diagnostics.version-policy",
  "compiler": {
    "name": "laniusc",
    "package_version": "0.1.0",
    "language_edition": "unstable-alpha",
    "edition_policy": "no stable production language edition yet; accepts the current alpha slice only"
  },
  "distribution": {
    "release_channel": "source-worktree",
    "status": "not-production-release; no stable install artifact or package manager channel",
    "production_release_claim": false,
    "stable_install_artifact": false,
    "package_manager_channel": false,
    "source_control_required_for_claims": true
  },
  "compatibility": {
    "machine_readable_contract": "schema_name and schema_version identify the JSON payload contract",
    "cli_version_text_contract": "human-readable summary; wrappers should prefer diagnostics version-policy",
    "language_edition_contract": "unstable-alpha only",
    "breaking_change_policy": "unstable-alpha worktree metadata may change until a stable production release policy exists"
  },
  "target_surface": {
    "emit_targets": "x86_64, wasm",
    "default_emit_target": "x86_64",
    "target_triples": "x86_64-unknown-linux-gnu, wasm32-unknown-unknown"
  },
  "tooling": {
    "formatter": "unstable-alpha lexical full-document formatter",
    "diagnostic_registry_schema_version": 8,
    "diagnostic_output_formats_schema_version": 9,
    "lsp_error_data_schema_name": "laniusc.lsp.error-data",
    "lsp_error_data_schema_version": 2,
    "command_discovery": {
      "schema_version": 3,
      "schema_name": "laniusc.diagnostics.command-discovery",
      "policy": "wrappers should use these machine-readable metadata commands instead of scraping --help text",
      "preferred_policy_command": "laniusc diagnostics version-policy",
      "command_index_command": "laniusc diagnostics commands",
      "human_help_command": "laniusc --help",
      "placeholder_policy": "uppercase words in command rows are user-supplied arguments; use placeholder rows to build focused lookup UIs and completion",
      "placeholder_count": 4,
      "placeholders": [
        {
          "placeholder": "CODE",
          "meaning": "stable diagnostic code selector",
          "accepted_selector_examples": [
            "LNC0018",
            "lnc0018",
            "error[LNC0018]: unsupported CLI option value"
          ],
          "bulk_discovery_command": "laniusc diagnostics codes",
          "used_by": [
            "laniusc diagnostics code CODE",
            "laniusc diagnostics explain CODE"
          ]
        },
        {
          "placeholder": "API",
          "meaning": "runtime-bound stdlib API selector",
          "accepted_selector_examples": [
            "std::io::print_i32",
            "stdio::print_i32",
            "\"std::io::print_i32\""
          ],
          "bulk_discovery_command": "laniusc diagnostics runtime-apis",
          "used_by": ["laniusc diagnostics runtime-api API"]
        },
        {
          "placeholder": "SERVICE",
          "meaning": "runtime service selector",
          "accepted_selector_examples": [
            "stdio",
            "std::io",
            "STDIO_HAS_RUNTIME_BINDING",
            "stdio_service_status()",
            "std::io::print_i32"
          ],
          "bulk_discovery_command": "laniusc diagnostics runtime-services",
          "used_by": [
            "laniusc diagnostics runtime-service SERVICE",
            "laniusc diagnostics runtime-service-apis SERVICE"
          ]
        },
        {
          "placeholder": "DIR",
          "meaning": "persisted source-pack artifact root directory",
          "accepted_selector_examples": [
            ".lanius/source-pack",
            "/abs/path/to/source-pack-artifacts"
          ],
          "bulk_discovery_command": "laniusc diagnostics source-pack-progress --source-pack-artifact-root DIR",
          "used_by": [
            "laniusc diagnostics source-pack-progress --source-pack-artifact-root DIR"
          ]
        }
      ],
      "selector_policy_count": 4,
      "selector_result_policies": [
        {
          "placeholder": "CODE",
          "commands": [
            "laniusc diagnostics code CODE",
            "laniusc diagnostics explain CODE"
          ],
          "missing_selector_diagnostic_code": "LNC0026",
          "unknown_selector_behavior": "successful metadata query with known: false",
          "known_field": "known"
        },
        {
          "placeholder": "API",
          "commands": ["laniusc diagnostics runtime-api API"],
          "missing_selector_diagnostic_code": "LNC0026",
          "unknown_selector_behavior": "successful metadata query with known: false",
          "known_field": "known"
        },
        {
          "placeholder": "SERVICE",
          "commands": [
            "laniusc diagnostics runtime-service SERVICE",
            "laniusc diagnostics runtime-service-apis SERVICE"
          ],
          "missing_selector_diagnostic_code": "LNC0026",
          "unknown_selector_behavior": "successful metadata query with known: false",
          "known_field": "known"
        },
        {
          "placeholder": "DIR",
          "commands": [
            "laniusc diagnostics source-pack-progress --source-pack-artifact-root DIR"
          ],
          "missing_selector_diagnostic_code": "LNC0023",
          "unknown_selector_behavior": "diagnostic with LNC0037 when the artifact record is missing or unreadable",
          "known_field": null
        }
      ],
      "command_count": 16,
      "commands": [
        {
          "command": "laniusc diagnostics commands",
          "schema_name": "laniusc.diagnostics.command-discovery",
          "purpose": "no-run metadata command discovery without the broader version-policy envelope",
          "selector_placeholder": null,
          "input_kind": "none",
          "source_input": false,
          "artifact_input": false,
          "no_run_boundary": "metadata query; source compilation, source scanning, GPU device creation, and target codegen are false in no_run_guards"
        },
        {
          "command": "laniusc diagnostics codes",
          "schema_name": "laniusc.diagnostics.codes",
          "purpose": "diagnostic code completion and filtering",
          "selector_placeholder": null,
          "input_kind": "none",
          "source_input": false,
          "artifact_input": false,
          "no_run_boundary": "metadata query; source compilation, source scanning, GPU device creation, and target codegen are false in no_run_guards"
        },
        {
          "command": "laniusc diagnostics code CODE",
          "schema_name": "laniusc.diagnostics.code",
          "purpose": "single diagnostic code lookup for detail panes and direct links",
          "selector_placeholder": "CODE",
          "input_kind": "selector",
          "source_input": false,
          "artifact_input": false,
          "no_run_boundary": "metadata query; source compilation, source scanning, GPU device creation, and target codegen are false in no_run_guards"
        },
        {
          "command": "laniusc diagnostics categories",
          "schema_name": "laniusc.diagnostics.categories",
          "purpose": "diagnostic category grouping for filter-building tools",
          "selector_placeholder": null,
          "input_kind": "none",
          "source_input": false,
          "artifact_input": false,
          "no_run_boundary": "metadata query; source compilation, source scanning, GPU device creation, and target codegen are false in no_run_guards"
        },
        {
          "command": "laniusc diagnostics formats",
          "schema_name": "laniusc.diagnostics.output-formats",
          "purpose": "diagnostic renderer selection",
          "selector_placeholder": null,
          "input_kind": "none",
          "source_input": false,
          "artifact_input": false,
          "no_run_boundary": "metadata query; source compilation, source scanning, GPU device creation, and target codegen are false in no_run_guards"
        },
        {
          "command": "laniusc diagnostics formatter",
          "schema_name": "laniusc.formatter.policy",
          "purpose": "formatter policy, CLI commands, LSP request options, and no-run guard discovery",
          "selector_placeholder": null,
          "input_kind": "none",
          "source_input": false,
          "artifact_input": false,
          "no_run_boundary": "metadata query; source compilation, source scanning, GPU device creation, and target codegen are false in no_run_guards"
        },
        {
          "command": "laniusc diagnostics version-policy",
          "schema_name": "laniusc.diagnostics.version-policy",
          "purpose": "compiler version, edition, distribution, compatibility, target, and tooling schema policy",
          "selector_placeholder": null,
          "input_kind": "none",
          "source_input": false,
          "artifact_input": false,
          "no_run_boundary": "metadata query; source compilation, source scanning, GPU device creation, and target codegen are false in no_run_guards"
        },
        {
          "command": "laniusc diagnostics explain CODE",
          "schema_name": "laniusc.diagnostics.explanation",
          "purpose": "code-specific explanation and unsupported-boundary recovery guidance",
          "selector_placeholder": "CODE",
          "input_kind": "selector",
          "source_input": false,
          "artifact_input": false,
          "no_run_boundary": "metadata query; source compilation, source scanning, GPU device creation, and target codegen are false in no_run_guards"
        },
        {
          "command": "laniusc diagnostics runtime-api API",
          "schema_name": "laniusc.diagnostics.runtime-api",
          "purpose": "focused known runtime-bound stdlib API lookup",
          "selector_placeholder": "API",
          "input_kind": "selector",
          "source_input": false,
          "artifact_input": false,
          "no_run_boundary": "metadata query; source compilation, source scanning, GPU device creation, and target codegen are false in no_run_guards"
        },
        {
          "command": "laniusc diagnostics runtime-apis",
          "schema_name": "laniusc.diagnostics.runtime-apis",
          "purpose": "known runtime-bound stdlib API discovery",
          "selector_placeholder": null,
          "input_kind": "none",
          "source_input": false,
          "artifact_input": false,
          "no_run_boundary": "metadata query; source compilation, source scanning, GPU device creation, and target codegen are false in no_run_guards"
        },
        {
          "command": "laniusc diagnostics runtime-service SERVICE",
          "schema_name": "laniusc.diagnostics.runtime-service",
          "purpose": "focused runtime service boundary lookup",
          "selector_placeholder": "SERVICE",
          "input_kind": "selector",
          "source_input": false,
          "artifact_input": false,
          "no_run_boundary": "metadata query; source compilation, source scanning, GPU device creation, and target codegen are false in no_run_guards"
        },
        {
          "command": "laniusc diagnostics runtime-service-apis SERVICE",
          "schema_name": "laniusc.diagnostics.runtime-service-apis",
          "purpose": "focused runtime service API listing",
          "selector_placeholder": "SERVICE",
          "input_kind": "selector",
          "source_input": false,
          "artifact_input": false,
          "no_run_boundary": "metadata query; source compilation, source scanning, GPU device creation, and target codegen are false in no_run_guards"
        },
        {
          "command": "laniusc diagnostics runtime-services",
          "schema_name": "laniusc.diagnostics.runtime-services",
          "purpose": "known runtime service boundary discovery",
          "selector_placeholder": null,
          "input_kind": "none",
          "source_input": false,
          "artifact_input": false,
          "no_run_boundary": "metadata query; source compilation, source scanning, GPU device creation, and target codegen are false in no_run_guards"
        },
        {
          "command": "laniusc diagnostics source-pack-progress --source-pack-artifact-root DIR",
          "schema_name": "laniusc.diagnostics.source-pack-progress",
          "purpose": "persisted source-pack work-queue progress inspection",
          "selector_placeholder": "DIR",
          "input_kind": "source-pack-artifact-root",
          "source_input": false,
          "artifact_input": true,
          "no_run_boundary": "metadata query; source compilation, source scanning, GPU device creation, and target codegen are false in no_run_guards"
        },
        {
          "command": "laniusc lsp capabilities",
          "schema_name": "laniusc.lsp.capabilities",
          "purpose": "editor capability and protocol contract discovery",
          "selector_placeholder": null,
          "input_kind": "none",
          "source_input": false,
          "artifact_input": false,
          "no_run_boundary": "metadata query; source compilation, source scanning, GPU device creation, and target codegen are false in no_run_guards"
        },
        {
          "command": "laniusc doctor --skip-slangc-probe",
          "schema_name": "laniusc.doctor.report",
          "purpose": "local install/readiness metadata without compiling source or launching Slang",
          "selector_placeholder": null,
          "input_kind": "toolchain-metadata",
          "source_input": false,
          "artifact_input": false,
          "no_run_boundary": "metadata query; source compilation, source scanning, GPU device creation, and target codegen are false in no_run_guards"
        }
      ],
      "no_run_guards": {
        "source_compilation": false,
        "source_scanning": false,
        "stdlib_source_scanning": false,
        "gpu_device_creation": false,
        "target_codegen": false,
        "slangc_probe": false,
        "shader_loop_audit_execution": false,
        "pareas_invocation": false
      }
    }
  },
  "no_run_guards": {
    "source_compilation": false,
    "source_scanning": false,
    "stdlib_source_scanning": false,
    "gpu_device_creation": false,
    "target_codegen": false,
    "slangc_probe": false,
    "shader_loop_audit_execution": false,
    "pareas_invocation": false
  }
}
```

`schema_name` and `schema_version` are the payload identity for wrappers. The
document is policy metadata only: it does not prove production readiness,
performance, scaling, local toolchain health, or source-control provenance.
The `tooling.command_discovery` object is the wrapper-facing index for no-run
metadata commands; use its command rows and schema names rather than scraping
human-readable help text to discover diagnostic, LSP, doctor, runtime-boundary,
or source-pack progress metadata surfaces. The same object is available
directly through `laniusc diagnostics commands` with
`schema_name: "laniusc.diagnostics.command-discovery"`, so wrappers that only
need command discovery do not have to parse the broader version-policy payload.
Rows with uppercase placeholders, such as `CODE`, `API`, `SERVICE`, and `DIR`,
are command templates for focused lookup surfaces. Command-discovery schema
version 3 makes those placeholders explicit through `placeholder_policy`,
`placeholder_count`, and `placeholders`: each placeholder row describes the
user-supplied selector, gives copyable examples, points at the bulk discovery
command wrappers should use for completion, and lists the command templates
that consume the selector. Each command row also publishes
`selector_placeholder`, `input_kind`, `source_input`, `artifact_input`, and
`no_run_boundary`, so wrappers can distinguish selector-only metadata commands,
artifact-root lookups, toolchain metadata, and no-input metadata queries without
parsing the command string. The same payload also publishes
`selector_policy_count` and `selector_result_policies`: `CODE`, `API`, and
`SERVICE` lookups report missing selectors with `LNC0026`, while unknown
selectors remain successful metadata queries whose payloads carry
`known: false`. `DIR` is an artifact-record lookup, so a missing
`--source-pack-artifact-root` value reports `LNC0023`, and a missing or
unreadable progress record reports `LNC0037` instead of a `known` field.
Compiler diagnostics use the same renderer as stable CLI option validation
diagnostics. Today the CLI maps unsupported values for `--diagnostic-format`,
`--emit`, `--edition`, and `--target` to `LNC0018`, formatter check failures to
`LNC0019`, unknown flags in covered CLI paths to `LNC0020`, unknown public
subcommands to `LNC0039`, linked-output contract descriptor failures to
`LNC0022`, and missing public option selector values such as `--emit`,
`--edition`, `--target`, and `--diagnostic-format`, plus
missing public path values such as `--stdlib`, `--stdlib-root`, `--source-root`,
`--package-manifest`, `--package-lockfile`, `-o`/`--out`,
`--source-pack-manifest`, `--source-pack-library-manifest`, and
`--source-pack-artifact-root`, plus source-pack numeric limit values such as
`--source-pack-max-items`, to `LNC0023`; invalid source-pack numeric limit
values use `LNC0018` with the accepted non-negative-integer value class.
`laniusc package lock` also uses `LNC0023` for missing `--manifest` and
`-o`/`--out` values when a diagnostic renderer is selected, uses `LNC0026` when
a required `--manifest path` or `-o`/`--out path` selector is absent, and uses
`LNC0031` for unexpected positional input paths and `LNC0032` when `-o`/`--out`
would overwrite the selected package manifest.
Unknown package, diagnostics, and LSP subcommands use `LNC0039`, missing package
subcommands use `LNC0025`, and missing diagnostics explanation codes and missing
formatter input files use `LNC0026`, and extra positional arguments on no-run
diagnostics, doctor, LSP metadata commands, package lock generation, and
formatter multi-input validation use `LNC0031`, through the same renderer.
Incompatible public option
combinations, such as `laniusc check -o`, `laniusc fmt --stdin input.lani`, and
mutually exclusive source-pack manifest or preparation-stage selectors, plus
source-pack metadata/preparation-only modes combined with `-o`/`--out`, and
`--source-pack-build-prepare-only` without `--source-pack-build-from-metadata`,
use `LNC0032` before source loading.
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
Output path write failures, including failed target-byte writes, failed
executable-bit updates for native outputs, and formatter file rewrite failures,
use `LNC0034` with a primary label on the requested output path.
Output stream write failures for stdout target bytes, stdout linked-output
contract descriptors, or formatted stdin output, including late flush failures
after buffered writes, use spanless `LNC0035` with recovery help to keep stdout
open or pass `-o`/`--out`. The diagnostic notes report output stream,
operation, emit mode, I/O error kind, and I/O error message as separate entries
so wrappers can classify broken pipes and flush failures without parsing one
fused sentence.
Formatter input read failures use `LNC0040` with a primary label on the
requested input path or `<stdin>` and separate notes for the formatter
operation, I/O error kind, and recovery path. The same recovery guidance is
also published through the structured `help` field, so editors and wrappers do
not need to parse a raw `read ... for formatting` string.
Formatter file rewrite failures use `LNC0034` with separate notes for the
formatter output path, write operation, I/O error kind, and I/O error message,
so wrappers can distinguish input-read failures from output-write failures
without parsing a raw `write formatted ...` string.
Runtime-bound stdlib and core ABI surfaces must stay separate from ordinary
diagnostic I/O failures: `core::panic`, `std::io`, `std::fs`, `std::time`,
`std::process`, and `std::env` expose public descriptor-metadata,
contract-only, and runtime-binding probes. The `core::runtime`
`runtime_service_requirement_row_is_contract_only(id, abi, status)` helper
names the descriptor-row predicate external tools should use before treating a
runtime requirement row as metadata, while linked-output descriptors with
required but unbound runtime services remain `LNC0022` contract-boundary
diagnostics rather than executable target-byte claims.
Function and method lookup failures that reach the GPU type-checker call
resolver use `LNC0027` instead of the broader assignment/type-mismatch
diagnostic. Unsupported
JSON-RPC requests sent to `laniusc lsp serve --stdio` use `LNC0028` inside the
error `data.diagnostic`, along with the supported-method list and no-run
guards. Invalid JSON-RPC request objects, malformed JSON payloads, and malformed
LSP framing such as missing `Content-Length` use `LNC0029` inside the same
error-data shape. Request objects with an `id` but without `jsonrpc: "2.0"`
also return `LNC0029` and are rejected before method dispatch. Valid JSON
messages that are arrays, strings, numbers, or other non-object JSON values also
return `LNC0029` with `id: null`, because the stdio server only accepts one
request object per frame. Framing errors are reported in-band on stdout when the
server can still write a response, so editor wrappers do not need to parse
stderr for protocol mistakes.
`textDocument/diagnostic` returns a full document report whose `items` are the
same LSP Diagnostic-shaped compiler diagnostics used by
`--diagnostic-format=lsp-json`, without target codegen. The current stdio
server diagnoses only the stored open-document text; it does not load
source roots, load `--stdlib-root`, publish diagnostics, or provide workspace
diagnostics.
`textDocument/formatting` is similarly scoped to the stored open-document text:
malformed formatting options are rejected before edits are computed, and the
server keeps the previous open-document text for later valid formatting or
diagnostic requests.
Source-root imports whose canonical target is not a `.lani` file use `LNC0030`
before GPU type checking, so source-looking symlinks cannot load non-source
files as modules. Package lock generation also uses `LNC0011` for quoted
imports before writing a lockfile, because persisted import graphs must not
omit unsupported import edges. Invalid GPU-recorded generic parameter lists use
`LNC0033`.
The
covered selector/path/limit,
unknown-subcommand/unknown-flag, missing-argument, unsupported-LSP-method,
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
diagnostics, formatter input-read JSON diagnostics, and descriptor-mode
linked-output contract failures. Output-emission evidence covers
structured output-path write failures and spanless stdout stream write-or-flush
failures with separated stream/operation/emit/error context, without source
loading or target execution. Artifact-record tooling evidence covers
source-pack work-queue progress status loaded from the persisted progress index,
with explicit guards against source loading and target codegen. LSP stdio
evidence covers
unsupported request methods, malformed LSP framing, request objects without a
string method, non-object JSON-RPC bodies, and malformed JSON payloads as
JSON-RPC errors with stable diagnostic data, post-shutdown request rejection,
ranged incremental change rejection, malformed-frame body draining before the
next valid frame, plus opened-document pull diagnostics for malformed source.

For tools that only need one code, `laniusc diagnostics explain CODE` returns a
machine-readable explanation document and succeeds even when the code is
unknown. Public diagnostic-code inputs are trimmed and canonicalized to
`LNC####`, so `lnc0017` and ` LNC0017 ` resolve to the same registry,
unsupported-feature, codegen-boundary, and explanation metadata:

```json
{
  "schema_version": 14,
  "schema_name": "laniusc.diagnostics.explanation",
  "registry_schema_version": 8,
  "requested_code": "LNC0017",
  "explain_command": "laniusc diagnostics explain LNC0017",
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
  "codegen_boundary": {
    "diagnostic_code": "LNC0017",
    "boundary": "x86 backend",
    "target": "x86_64",
    "stage": "native codegen lowering",
    "partial_artifact_policy": "fail-closed before emitting a partial instruction prefix",
    "target_bytes_emitted": false,
    "diagnostics_only_command": "laniusc check",
    "fallback_emit": "wasm"
  },
  "runtime_service_boundaries": null,
  "runtime_bound_apis": null,
  "accepted_selector_examples": [
    "LNC0018",
    "lnc0018",
    "error[LNC0018]: unsupported CLI option value"
  ],
  "accepted_selector_patterns": [
    "LNCdddd",
    "lncdddd",
    "copied text containing one LNCdddd token"
  ],
  "code_index_command": "laniusc diagnostics codes",
  "registry_command": "laniusc diagnostics registry",
  "no_run_guards": {
    "source_compilation": false,
    "source_scanning": false,
    "gpu_device_creation": false,
    "target_codegen": false
  }
}
```

Unknown codes set `known` to `false` and use `null` for `diagnostic` and
`unsupported_feature`; `codegen_boundary`, `runtime_service_boundaries`, and
`runtime_bound_apis` are also `null`. That query is still a successful no-run
tooling request, and `requested_code` still uses the canonical `LNC####`
spelling.
`schema_name` is present for known and unknown codes, so wrappers can identify
the explanation payload before inspecting `known`. `no_run_guards` is present
for known and unknown codes and keeps the stable machine-readable promise that
explanation queries do not scan source, compile source, create a GPU device, or
run target codegen. The same known and unknown explanation payloads carry
`accepted_selector_examples`, `accepted_selector_patterns`,
`explain_command`, `code_index_command`, and `registry_command`, so tools can
recover from a bad copied code without scraping help text or launching a
source-loading command.
Use `laniusc diagnostics explain --help` when a wrapper or user wants the
selector syntax and unknown-code behavior first; that focused help exits before
lookup, ignores later lookup-only arguments, and writes human help to stderr
like the other CLI help surfaces.

For `LNC0017`, `codegen_boundary` gives wrappers a structured x86 target
boundary contract without parsing the prose summary: the compiler failed closed
before target bytes were emitted, `laniusc check` remains the diagnostics-only
path, and `fallback_emit` names the alternate emit selector currently advertised
by the diagnostic.

For `LNC0038`, the explanation document includes
`runtime_service_boundaries`: one row per known runtime service descriptor. Each
row names the diagnostic code, service id, service name, stdlib module path,
capability constant, status probe, runtime-binding probe, current status, and
whether that service is executable. Each service row also carries
`accepted_selector_kinds`, the stable `matched_by` values accepted by
`diagnostics runtime-service` and `diagnostics runtime-service-apis`:
`service_id`, `service_name`, `module_path`, `capability_constant`,
`status_probe`, `binding_probe`, `api_name`, and `service_api_name`. In the
active compiler slice every row has
`current_status: "known-unbound"` and `executable: false`, so external tools can
distinguish recognized contract-only stdlib APIs from unknown service ids
without parsing prose. It also includes `runtime_bound_apis`: one row per
currently declared runtime-bound stdlib extern API. Each API row names the
qualified API, owning module, runtime service id/name, the owning service's
module path, capability constant, status/runtime-binding probes, current status,
and executable flag as `service_current_status` and `service_executable`, the
API-level executable and runtime-binding probes, current status, and
`executable: false`. Each API row also carries `accepted_selector_kinds` with
the stable `runtime-api` selector classes `api_name` and `service_api_name`.
Each API row also carries the extern ABI namespace such as
`lanius_alloc`, `lanius_std`, or `lanius_panic`, so wrappers can map calls such
as `std::io::print_i32` to `LNC0038` without scraping source or joining the
service table before they can explain why the visible extern declaration is not
runnable.

For one API at a time, `laniusc diagnostics runtime-api API` returns a focused
no-run document with `schema_name: "laniusc.diagnostics.runtime-api"` and
schema version 2. `API` can be a canonical qualified API such as
`std::io::print_i32` or a service-qualified API such as `stdio::print_i32`.
Known runtime-bound APIs set `known: true`, report whether the selector matched
by `api_name` or `service_api_name`, include the canonical API path in
`canonical_api_name`, include the matching `runtime_bound_api` row, include the
owning `runtime_service_boundary` row, and report
`diagnostic_code: "LNC0038"`. The returned API and service rows include their
`accepted_selector_kinds` arrays, so wrappers can present the same selector
surface that the CLI uses without deriving it from prose. Unknown API names set
`known: false` and use
`null` for the match kind, canonical API path, diagnostic code, and both rows.
Both known and unknown API documents carry top-level
`accepted_selector_kinds` and `service_accepted_selector_kinds`, so wrappers can
render valid selector help from a failed lookup without scanning stdlib files or
joining row metadata. They also carry `selector_examples`,
`runtime_api_index_command`, and `runtime_service_index_command`, so an unknown
selector response can point users at a concrete lookup shape and the bulk
discovery commands without parsing prose.
Focused runtime selectors are intended to accept values copied directly from
machine-readable rows: a selector copied with surrounding JSON double quotes is
trimmed to the same lookup value as its unquoted form. This applies to
qualified APIs, service-qualified APIs, service ids/names, module paths,
capability constants, and status or binding probes, so tools can offer
copy-to-query flows from `selector_examples`, `runtime_bound_apis`, or
`runtime_service_boundaries` without stripping quotes first.
The `no_run_guards` include `stdlib_source_scanning: false` so editors and
wrappers can query visible stdlib APIs without treating the command as proof
that host runtime support exists.

For API discovery, `laniusc diagnostics runtime-apis` returns the same
registered runtime-bound API rows as an index, with
`schema_name: "laniusc.diagnostics.runtime-apis"`, schema version 1,
`diagnostic_code: "LNC0038"`, an `explain_command`, the focused
`runtime_api_query_command`, top-level API and service selector-kind arrays,
row counts, the full `runtime_bound_apis` table, the
`runtime_service_boundaries` table, and no-run guards including
`stdlib_source_scanning: false`. The API rows expose
`accepted_selector_kinds: ["api_name", "service_api_name"]`, and the service
rows expose the runtime-service selector kinds accepted by the focused service
commands. This is the command wrappers should use for completion or validation
of contract-only stdlib host APIs when they do not want to scrape stdlib source
or join against `diagnostics explain LNC0038`.

For focused service-boundary queries, `laniusc diagnostics runtime-service
SERVICE` returns one no-run service document with
`schema_name: "laniusc.diagnostics.runtime-service"`. `SERVICE` can be a
numeric service id, a registered service name, the service module path such as
`std::io`, a capability constant, a status/runtime-binding probe, a qualified
runtime-bound API such as `std::io::print_i32`, or a service-qualified API such
as `stdio::print_i32`.
Known services set `known: true`, report whether the selector matched
`service_id`, `service_name`, `module_path`, `capability_constant`,
`status_probe`, `binding_probe`, `api_name`, or `service_api_name`, include the
selected `runtime_service_boundary`, and expose the bulk `runtime-apis` and
`runtime-services` commands for discovery. The returned service row carries the
same selector list as `accepted_selector_kinds`. Focused service documents also
carry top-level `accepted_selector_kinds` and
`runtime_api_accepted_selector_kinds`, including when the selector is unknown.
They include `selector_examples` for every accepted service selector class, so
an editor or installer can render actionable lookup help from the focused
response alone.
`runtime-service-apis` uses the same selectors to return every known-unbound
API row for that service, using
`schema_name: "laniusc.diagnostics.runtime-service-apis"`, so a tool can start
from a canonical visible API name like `std::io::print_i32` or a
service-qualified name like `stdio::print_i32` and discover the rest of its
runtime boundary without scanning stdlib source. Unknown selectors stay
machine-readable with `known: false`, `matched_by: null`, top-level selector
metadata, and a null service row rather than rendering a diagnostic.

For service-boundary discovery, `laniusc diagnostics runtime-services` returns
only the registered service rows, with
`schema_name: "laniusc.diagnostics.runtime-services"`, schema version 1,
`diagnostic_code: "LNC0038"`, an `explain_command`, a
`runtime_api_index_command`, top-level service and runtime-API selector-kind
arrays, `runtime_service_boundary_count`, the full
`runtime_service_boundaries` table, and no-run guards including
`stdlib_source_scanning: false`. Each service row carries
`accepted_selector_kinds`, making the stable focused-query selector surface
available without reading the API table or stdlib source. This is the command
installers and editor wrappers should use when they need the known-unbound
service IDs, module paths, capability constants, probe names, and accepted
selector kinds.

For source-pack build dashboards and editor task integrations,
`laniusc diagnostics source-pack-progress --source-pack-artifact-root
ARTIFACT_DIR --emit wasm` returns a compact artifact-record status document:

```json
{
  "schema_version": 1,
  "schema_name": "laniusc.diagnostics.source-pack-progress",
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
  "no_run_guards": {
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
source diagnostics. `schema_name` is the stable payload identity for dashboards
and editor task integrations; `no_run_guards` is the no-run guard field.

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
registry schema metadata, title/category metadata, primary-label policy, and an
`explain_command` from the registry-backed `Diagnostic` value:

```json
{
  "schema_version": 3,
  "schema_name": "laniusc.diagnostics.rendered-json",
  "registry_schema_version": 7,
  "severity": "error",
  "code": "LNC0016",
  "title": "syntax error",
  "category": "parsing",
  "primary_label_policy": "required",
  "explain_command": "laniusc diagnostics explain LNC0016",
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
  "schema_version": 3,
  "schema_name": "laniusc.diagnostics.rendered-json",
  "registry_schema_version": 7,
  "severity": "error",
  "code": "LNC0018",
  "title": "unsupported CLI option value",
  "category": "tooling",
  "primary_label_policy": "none",
  "explain_command": "laniusc diagnostics explain LNC0018",
  "message": "unsupported CLI option value",
  "primary_label": null,
  "notes": [
    "--emit value \"llvm\" is not supported",
    "accepted --emit values: x86_64, wasm"
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
for code metadata, a stable `schema_name`, and repeats the `position_encoding`
value so standalone
`lsp-json` consumers do not need to fetch LSP capabilities first. For registered
codes, `data` takes the stable Lanius title, category, and primary-label policy
from the diagnostic registry, not from caller-local context, so tools can filter
diagnostics without reparsing human text or immediately joining against the
registry. It also carries the explain command, help, and note metadata for
accepted values or remediation hints. When a source span exists,
`data.primary_label` carries the source path plus one-based line, column,
length, and label message from the compiler diagnostic; it intentionally omits
`source_line` so `lsp-json` remains snippet-free. Diagnostic notes are carried
as `data.notes`; the top-level object does not contain the legacy JSON
diagnostic `notes` field. Diagnostics without a source span omit
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
    "schema_version": 4,
    "schema_name": "laniusc.diagnostics.lsp-data",
    "registry_schema_version": 7,
    "position_encoding": "utf-16",
    "title": "syntax error",
    "category": "parsing",
    "primary_label_policy": "required",
    "explain_command": "laniusc diagnostics explain LNC0016",
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
- Unsupported semantic-shape diagnostics should describe the language shape
  that is accepted or rejected. Internal relation names, row layouts, and
  pass names belong in design docs, not user notes.
- Late semantic and backend passes should return source-addressable status rows
  derived from HIR, resolver, type, instruction, relocation, or link records.
- CPU formatting may read source files or snippets for display. It must not use
  source text as a semantic fallback for parsing, type checking, codegen, or
  linking.
