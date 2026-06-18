# CLI And Tooling Surface

`laniusc` is the public compiler invocation layer. It owns command parsing,
cross-option validation, diagnostic-rendering selection, output writing,
no-run metadata commands, formatter and LSP tooling, package lock generation,
and source-pack work-queue entry points. It should stay thin around compiler
semantics: the CLI decides how an invocation is shaped; compiler modules decide
what the language means.

For the user-facing command reference, use [Laniusc invocation](../invocation.md).
This chapter is the maintainer-facing implementation guide.

Use this chapter when changing flags, subcommands, output contracts,
diagnostic-format behavior, no-run tooling metadata, source-pack CLI modes,
package lock generation, formatter behavior, or LSP command behavior. Use
[generated/reference.md](generated/reference.md) for exact public compiler
operation inventories and Rustdoc coverage. Use
[Public compiler API](public-api.md) when changing the Rust call surface that
the CLI invokes.

## Ownership Boundary

| Concern | CLI owns | Compiler or phase owns |
| --- | --- | --- |
| Raw process arguments | Collecting args, parsing flags, forwarding subcommands. | None. |
| Invocation shape | Compile/check mode, input mode, target selector, output path, source-pack mode flags. | The public compile/check APIs selected by the request. |
| Cross-option validation | Rejecting incompatible flags before compiler work starts. | Semantic validation after source is parsed. |
| Diagnostics rendering | Selecting text, diagnostic JSON, or LSP-shaped JSON for invocation errors. | Producing structured `Diagnostic` objects and source labels. |
| Target bytes | Writing bytes to stdout or `-o/--out`, setting executable bit for non-WASM on Unix. | Producing target bytes or persisted artifacts. |
| No-run metadata | Diagnostics registry commands, version policy, doctor, LSP capabilities. | Source parsing/type checking/codegen are deliberately not run. |
| Tooling commands | Formatter CLI, package lockfile command, LSP stdio protocol shell. | Formatter implementation, package metadata model, compiler diagnostics. |

Do not put language semantics, source-root/module rules, parser behavior,
type-check behavior, or backend lowering policy in `cli`. Route to the owning
compiler API and preserve structured diagnostics from that API.

## Source Roots

The main CLI source tree is `crates/laniusc-compiler/src/cli`.

| Module | Responsibility |
| --- | --- |
| `entry.rs` | Process entry point, diagnostic-format preselection, exit code, final error rendering. |
| `dispatch.rs` | Top-level command routing after parsing. |
| `args/*` | Top-level compile/check parsing, source-pack flag parsing, request builder, validation. |
| `compile/*` | Compile/check dispatch across source-pack, package, source-root, single-file, and default-demo modes. |
| `source_pack/*` | Source-pack CLI options, metadata preparation, descriptor worker execution, manifest/path-list helpers. |
| `output/*` | `CliEmission`, target byte/contract writing, stdout and file write diagnostics. |
| `common/*` | Shared constants, diagnostics, path helpers, numeric parsing, package metadata errors. |
| `diagnostics/*` | No-run diagnostics metadata commands. |
| `doctor/*` | No-run toolchain/readiness report and optional `slangc` probe. |
| `fmt.rs` | Lexical formatter command. |
| `lsp/*` | Capability metadata, JSON-RPC framing, open-document state, formatting, pull diagnostics. |
| `package.rs` | Package lockfile tooling. |
| `help.rs` | User-facing help and version text. |

When adding a command, decide which module owns the public contract before
editing `dispatch.rs`. Dispatch should route already-parsed command objects; it
should not learn option-specific policy.

## Entry And Dispatch Flow

`cli::run_from_env` is the binary-facing entry point:

1. `entry::run_from_env` collects `std::env::args().skip(1)`.
2. `diagnostic_format_from_args` scans raw args to choose final error rendering
   before parsing can fail.
3. `dispatch::run` calls `args::parse_args`.
4. `args::parse_args` consumes leading `--diagnostic-format` selectors, forwards
   subcommands, or builds a `CompileRequest`.
5. `dispatch::run` routes the parsed command to `compile`, `fmt`, `doctor`,
   `package`, `lsp`, or `diagnostics`.
6. Command owners return `Result<(), CliError>`.
7. `entry::report_error` renders structured diagnostics as text, JSON, or one
   LSP Diagnostic-shaped JSON object.

This is the core invariant: command owners return `CliError`; they do not
choose the final renderer. That keeps parse errors, command validation errors,
compiler diagnostics, formatter diagnostics, and output diagnostics on the same
public surface.

## Command Groups

| Command | Owner | Runs source compilation? | Creates GPU device? | Primary output |
| --- | --- | --- | --- | --- |
| `laniusc` | `compile` | yes, except prep-only source-pack paths | yes for compile/check work | target bytes or linked-output contract descriptor |
| `laniusc check` | `compile` | parser/type-check only | yes | diagnostics only |
| `laniusc fmt` | `fmt` | no | no | rewritten files, formatted stdout, or check diagnostic |
| `laniusc doctor` | `doctor` | no | no | readiness JSON |
| `laniusc diagnostics ...` | `diagnostics` | no | no | registry/policy/runtime/progress JSON |
| `laniusc lsp capabilities` | `lsp` | no | no | capability JSON |
| `laniusc lsp serve --stdio` | `lsp` | only for pull diagnostics | only for pull diagnostics | JSON-RPC responses |
| `laniusc package lock` | `package` | no | no | package lockfile JSON |

No-run commands are deliberate tooling surfaces. They are safe for editor
wrappers, install checks, shell completion, diagnostics discovery, and metadata
inspection. Do not add source scanning, source compilation, target codegen, or
GPU device creation to a no-run command without renaming the command contract
or documenting the changed guard.

## Argument Parsing And Validation

Top-level compile/check parsing is split into a permissive builder and a
cross-option validation step.

`CompileRequestBuilder` accepts flags in CLI order. It stores raw inputs,
stdlib paths, source roots, package selectors, output path, emit target, target
triple, language edition, check mode, and source-pack options. It does not try
to decide every conflict as each token is read.

`CompileRequestBuilder::finish` owns cross-option validation:

| Validation | Examples |
| --- | --- |
| Target and emit | `--target wasm32-unknown-unknown` requires `--emit wasm`; `--target x86_64-unknown-linux-gnu` requires `--emit x86_64`. |
| Edition | Only the current `unstable-alpha` edition is accepted. |
| Package mode | `--package-manifest` and `--package-lockfile` describe entry/roots; they reject positional files, explicit stdlib files, and source roots. |
| Source-root mode | `--source-root`/`--stdlib-root` requires exactly one entry input and rejects explicit `--stdlib` source files. |
| Source-pack mode | Manifest forms, metadata-only, prepare-only, build-from-metadata, build-prepare-only, descriptor, and artifact-root flags are validated as a mode family. |
| Check mode | `check` rejects output paths, explicit source-pack descriptor/prep flags, explicit `--stdlib`, and multi-input source packs. |
| Descriptor output | Source-pack descriptor output must be explicit with `--emit-contract`. |

Keep new validation near the layer that has all necessary context. Token-local
errors such as missing option values belong in parsing. Cross-option errors
belong in `validation.rs` or `CompileRequestBuilder::finish`.

## Diagnostic Format Selection

`--diagnostic-format` has two jobs:

1. The raw scan in `entry.rs` chooses how a later `CliError::Diagnostic` will be
   rendered.
2. Parsing validates the selector value and strips leading selectors before
   forwarded subcommands.

Accepted values are:

| Value | Output |
| --- | --- |
| `text` | Human-readable diagnostic text on stderr with the `laniusc:` prefix for plain messages. |
| `json` | Pretty `Diagnostic` JSON on stderr when the error is structured. |
| `lsp-json` | Pretty single LSP Diagnostic-shaped JSON object on stderr when the error is structured. |

The LSP JSON format is one diagnostic object, not a `publishDiagnostics`
envelope. Subcommands should accept and validate `--diagnostic-format` only to
preserve consistent invocation behavior; they should not render diagnostics
themselves.

## Compile And Check Modes

Plain `laniusc` compiles by selecting one input mode, then one target backend.
`check` selects the same frontend/type-check paths but exits before writing
target bytes.

| Selector shape | Compile path |
| --- | --- |
| no input | built-in `fn main() { return 7; }` demo source |
| one positional input | isolated single-file compiler API |
| `--source-root` and optional `--stdlib-root` | entry-source-root compiler APIs |
| `--stdlib-root` without user roots | stdlib-root compiler APIs |
| `--package-manifest` | load package manifest, convert to entry source roots |
| `--package-lockfile` | load resolved package lockfile, convert to entry source roots |
| explicit `--stdlib` files, multiple positional files, or source-pack flags | source-pack dispatch |

The accepted emit targets are `x86_64` and `wasm`. `--target` is validation
metadata; it must imply the same backend as `--emit`. The CLI does not infer a
different backend from a target triple after validation.

`compile::run` persists the GPU pipeline cache after compile/check work and
before output writing. If the request is `check_only`, it returns before
writing `CliEmission`.

See [Module and source-root resolution](module-resolution.md) for the boundary
between CLI input-mode selection, source-root file discovery, package replay,
and GPU semantic module/import resolution.
See [Source-level standard library](standard-library.md) for the current
`--stdlib-root` contract and evidence policy for stdlib helper claims.

## Output Contract

Compile and source-pack paths return `CliEmission`:

| Form | Meaning | Writer behavior |
| --- | --- | --- |
| `Bytes(Vec<u8>)` | In-memory target bytes. | Write to `-o/--out` or stdout; mark non-WASM file output executable on Unix. |
| `ContractDescriptorFile(PathBuf)` | Path to a persisted linked-output contract descriptor. | Read descriptor bytes, then write to `-o/--out` or stdout. |

Source-pack descriptor paths intentionally require `--emit-contract`. Without
that explicit flag, the CLI rejects descriptor output instead of silently
treating an artifact contract as target bytes.

See [Artifact descriptors and output contracts](artifact-descriptors.md) for
the descriptor JSON schema, runtime-service requirements, target-byte policy,
and linked-output descriptor validation boundary.

Output failures should become structured output diagnostics where possible.
Stream and file write helpers preserve emit mode, operation, path or stream
name, and stable I/O error kind.

## Source-Pack CLI Modes

Source-pack flags expose bounded metadata preparation, persisted build
preparation, and descriptor worker execution. The CLI layer decides which path
to run; the source-pack compiler/store layers own the persisted record formats.

| Mode | Main flags | Behavior |
| --- | --- | --- |
| Metadata chunk | `--source-pack-metadata-only --source-pack-artifact-root ROOT --source-pack-library-manifest FILE` | Prepare one bounded metadata chunk and exit. |
| Package metadata chunk | `--package-manifest` or `--package-lockfile` with `--source-pack-metadata-only` | Load package metadata, convert to path manifest, prepare one bounded metadata chunk. |
| Input preparation chunk | `--source-pack-prepare-only` | If metadata is incomplete, prepare metadata; otherwise prepare one build-work chunk. |
| Build preparation chunk | `--source-pack-build-from-metadata --source-pack-build-prepare-only` | Prepare one bounded build-work chunk from persisted metadata. |
| Descriptor worker from metadata | `--source-pack-build-from-metadata --emit-contract` | Run a bounded descriptor worker under the artifact root. |
| Descriptor worker from manifest/library manifest | `--source-pack-manifest` or `--source-pack-library-manifest` with descriptor flags | Require or use prepared metadata/build state, then run descriptor work. |
| Direct descriptor worker | source-pack descriptor mode without manifest inputs | Require prepared metadata/build state and run descriptor work. |

JSONL library manifests are the bounded metadata-preparation format. Raw
positional path lists and whole JSON path manifests are rejected for
metadata-only chunking because they would require reading too much source-pack
structure at once.

The source-pack CLI caps user-provided work limits:

| Limit | Default/cap owner |
| --- | --- |
| metadata libraries per chunk | `DEFAULT_SOURCE_PACK_METADATA_MAX_LIBRARIES` |
| metadata source files per chunk | `DEFAULT_SOURCE_PACK_METADATA_MAX_SOURCE_FILES` |
| build-preparation items per chunk | `DEFAULT_SOURCE_PACK_BUILD_MAX_ITEMS` |
| descriptor worker items per run | `DEFAULT_SOURCE_PACK_MAX_ITEMS` |
| ready items inspected per worker run | `DEFAULT_SOURCE_PACK_MAX_READY_ITEMS` |

Effective values are clamped to the cap and at least one. If a user needs more
work, they should rerun the command; the work queue and progress records are
the resumability contract. See [Capacity and limits](capacity-and-limits.md)
for the broader rule that chunk sizes should preserve valid large builds by
returning progress instead of becoming language limits.

## Package Tooling

`laniusc package lock` resolves a package manifest and writes a package
lockfile. It is control-plane package metadata work, not source compilation.
See [Package metadata and lockfiles](package-metadata.md) for the lockfile JSON
sections, replay checks, source scanner, and import graph rules.

Required flags:

- `--manifest PATH`
- `-o/--out PATH`

The output path must not identify the same file as the manifest path. The
validator canonicalizes existing path prefixes so it can catch obvious
overwrite cases even when the output file does not exist yet.

Package manifests and lockfiles can also feed compile/check mode and bounded
source-pack metadata preparation. In those cases the package metadata selects
entry/source roots; semantic module identity still comes from GPU-parsed
module/import records.

## Diagnostics Metadata Commands

`laniusc diagnostics` is the no-run metadata surface. It should stay aligned
with [Diagnostics and status](diagnostics.md).

| Command | Contract |
| --- | --- |
| `registry` | Full diagnostic registry JSON. |
| `commands` | No-run metadata command discovery and placeholders. |
| `codes` | Compact diagnostic code index. |
| `code CODE` | One diagnostic code row, or `known:false`. |
| `categories` | Codes grouped by stable category. |
| `formats` | Accepted diagnostic output formats and payload contracts. |
| `formatter` | Formatter policy, CLI/LSP request metadata, and no-run guards. |
| `version-policy` | Compiler, edition, distribution, target, schema, and command-discovery policy. |
| `explain CODE` | One code-specific explanation JSON document. |
| `runtime-api API` | One fail-closed runtime-bound API row. |
| `runtime-apis` | Full runtime-bound API index. |
| `runtime-service SERVICE` | One runtime service boundary. |
| `runtime-service-apis SERVICE` | APIs owned by one runtime service. |
| `runtime-services` | Full runtime service boundary table. |
| `source-pack-progress` | Persisted work-queue progress for an artifact root and emit target. |

These commands validate argument counts and print JSON to stdout. They should
not compile source, scan source roots, create a GPU device, or run codegen.

## Doctor

`laniusc doctor` prints a compact no-run readiness report. It may probe `slangc`
through `SLANGC` or `PATH`, unless `--skip-slangc-probe` is passed. It must not
compile source, create a GPU device, run shader loop audits, execute readiness
gates, or invoke unrelated compiler work.

The doctor schema version lives in `common/constants.rs`. Changing the JSON
shape is a metadata contract change, not an incidental formatting edit.

## Formatter

`laniusc fmt` is a lexical formatter command. It does not create a GPU device.

| Mode | Behavior |
| --- | --- |
| file inputs | Rewrite changed files in place. |
| `--check` with file inputs | Read all files, collect formatting failures, and return one structured diagnostic if any differ. |
| `--stdin` or `-` | Read stdin, write formatted stdout. |
| `--check --stdin` | Compare stdin to formatted output and return a structured diagnostic on mismatch. |

Formatter diagnostics use stable codes for input read failure, output write
failure, formatter check failure, and stream write failure. The primary label
for a check failure points at the first byte where formatted output diverges
from input.

See [Formatter internals](formatter.md) for the lexical formatting contract,
token preservation invariant, layout rules, CLI/LSP behavior, formatter
metadata, diagnostics, and formatter test evidence.

## LSP Surface

The LSP command has two modes:

| Command | Behavior |
| --- | --- |
| `laniusc lsp capabilities` | Print no-run capability metadata and exit. |
| `laniusc lsp serve --stdio` | Start a minimal JSON-RPC stdio server. |

The stdio server tracks open documents in memory. It supports initialize,
initialized, didOpen, full-document didChange, didClose, full-document
formatting, pull diagnostics, shutdown, and exit. It rejects ranged
incremental edits. Formatting is lexical and does not run GPU work. Pull
diagnostics use the GPU type-check path for the opened document and do not run
target codegen.

Server error responses include explicit failure-boundary metadata for important
protocol states such as parse errors, invalid requests, not initialized,
post-shutdown requests, repeated initialize, unsupported methods, and document
diagnostic failures. Keep the capability metadata, method list constants, and
protocol behavior in sync.

See [LSP surface internals](lsp.md) for the detailed LSP source map, capability
metadata, stdio transport contract, lifecycle rules, open-document model,
formatting contract, pull diagnostic path, error-data schema, and LSP test
evidence.

## Stable CLI Diagnostics

Shared CLI diagnostic builders live in `common/error.rs`.

| Helper | Typical code | Use |
| --- | --- | --- |
| `unsupported_cli_option_value_error` | `LNC0018` | Known flag with unsupported value. |
| `unknown_cli_option_error` | `LNC0020` | Unknown `--flag` or subcommand option. |
| `missing_cli_option_value_error` | `LNC0023` | Flag that requires a following value. |
| `missing_cli_subcommand_error` | `LNC0025` | Subcommand family with no subcommand. |
| `missing_cli_argument_error` | `LNC0026` | Missing positional or required argument. |
| `extra_cli_argument_error` | `LNC0031` or `LNC0020` | Extra positional argument or unexpected flag. |
| `incompatible_cli_options_error` | `LNC0032` | Mutually incompatible flags or modes. |
| `unknown_cli_subcommand_error` | `LNC0039` | Unknown subcommand. |

Prefer these helpers over ad hoc strings for public invocation failures. Plain
`CliError::Message` is acceptable for internal control-plane errors that have
not yet been promoted to a stable public diagnostic, but new user-facing CLI
contracts should use structured diagnostics.

## Adding CLI Behavior

Checklist:

1. Decide whether the command runs compiler work or is a no-run metadata/tooling
   surface.
2. Add or update help text in `help.rs`.
3. Add parsing in `args/parse.rs`, a subcommand owner, or a small owner-specific
   parser.
4. Put token-local missing-value/unknown-flag errors in parsing.
5. Put cross-option conflicts in `args/validation.rs` or the request builder.
6. Return `CliError`; do not write diagnostics directly.
7. Route parsed commands through `dispatch.rs`.
8. Use `CliEmission` for compile output and output helpers for file/stdout
   writes.
9. Preserve no-run guards for metadata commands.
10. Update this chapter and related diagnostics/source-pack docs if the public
    contract changed.
11. Regenerate or check `docs/compiler/generated/reference.md` if public
    operation inventories, Rustdoc coverage, status codes, or large structs
    changed.

## Common Mistakes

Avoid these changes:

- Adding language semantics to CLI validation.
- Letting a command print its own diagnostic format instead of returning
  `CliError`.
- Creating a GPU device in a no-run command.
- Reading whole source-pack manifests in a bounded metadata-preparation path.
- Treating linked-output contract descriptors as target bytes without
  `--emit-contract`.
- Adding a source-pack flag without updating the conflict matrix in validation.
- Adding LSP protocol behavior without updating capability and method metadata.
- Writing output files directly from compile handlers instead of using
  `CliEmission` and output helpers.
- Duplicating accepted target/format/edition strings instead of using
  `common/constants.rs`.

## Evidence To Update

Choose the narrowest evidence that covers the change:

- CLI parser/validation tests for new flags, incompatibilities, and diagnostic
  formats.
- Focused source-pack CLI tests for descriptor completion, artifact-root
  validation, bounded preparation, and progress reporting.
- Formatter tests for `fmt` check/write/stdin behavior.
- LSP protocol tests for capability metadata, method guards, and request/response
  shapes.
- `tools/compiler_inventory.py --check docs/compiler/generated/reference.md`
  when public operation inventories or Rustdoc coverage changed.
- Markdown link and style checks for docs-only edits.

Docs-only edits do not require compiler tests, but they should still pass the
generated-reference freshness check and Markdown link validation.
