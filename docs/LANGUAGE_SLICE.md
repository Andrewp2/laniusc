# Lanius Language Slice And Versioning Policy

Lanius currently exposes one documented language edition:

```text
unstable-alpha
```

`unstable-alpha` is not a stable compatibility promise. It names the current
compiler slice so external users can tell which parser, semantic, backend, and
tooling contracts a binary claims to support. Source compatibility, diagnostic
wording, package metadata, stdlib APIs, and backend coverage may change between
compiler releases until a stable edition is introduced.

## Version Surface

`laniusc --version` is the supported machine-checkable summary for the local
binary. It must print:

- compiler package version on the first line as `laniusc <version>`
- `language-edition: unstable-alpha`
- `edition-policy: ...`
- `targets: wasm, x86_64`
- `target-triples: wasm32-unknown-unknown, x86_64-unknown-linux-gnu`
- `x86_64: ...`
- `slangc: ...`
- `wgpu: ...`
- `build-profile: ...`
- `shader-artifact-digest: ...`

The version command is metadata-only: it must not require source files, perform
GPU compilation, write outputs, or validate unrelated compile flags.

`laniusc doctor` is the no-run local installation check for the same bounded
tooling surface. It emits a JSON document with schema version, compiler version,
language edition, accepted emit targets, accepted target triples, Slang
availability, build metadata, the accepted diagnostic render formats and LSP
diagnostic metadata, and explicit no-run guards. If `SLANGC` is set, doctor
checks that configured path; otherwise it checks `slangc` on `PATH`. The command
must not compile source, create a GPU device, invoke Pareas, or run generated
workloads.

## Diagnostic Format

Text diagnostics are the default CLI format. `--diagnostic-format=json` emits a
single JSON diagnostic object for compiler diagnostics and covered CLI
validation errors that already have stable external diagnostic records. JSON
diagnostics include the registry-backed stable `title` and `category` alongside
contextual `message` text.
`--diagnostic-format=lsp-json` emits the same covered diagnostics as a single
LSP Diagnostic-shaped JSON object without a language-server envelope; LSP
`data` carries the same title/category metadata, diagnostic notes, and the
primary-label policy.
`laniusc lsp capabilities` reports the no-run editor metadata, and
`laniusc lsp serve --stdio` handles the minimal `initialize`, `shutdown`, and
`exit` JSON-RPC handshake without compiling source, creating a GPU device, or
generating target code. The stdio server stores opened documents with
full-document `didChange` updates only and rejects ranged incremental changes
as invalid parameters. It also serves bounded `textDocument/diagnostic` pull
requests as full LSP diagnostic reports; document diagnostics invoke the GPU
compile/type-check path for the opened source but still do not generate target
code.
Covered unsupported option values report `LNC0018`, covered unknown flags report
`LNC0020`, and selector/unknown-flag validation happens before source loading
when possible. Other CLI argument errors remain text errors until they are
promoted to stable diagnostic records.

`laniusc check` is the current diagnostic-only CLI surface. It runs the same
bounded GPU compile path as normal compilation for single-entry in-memory,
source-root, stdlib-root, package-manifest, and package-lockfile cases, then
exits without writing target bytes. Descriptor/source-pack preparation modes are
not accepted by `check` yet because they are artifact-building workflows rather
than diagnostic-only checks.

`laniusc fmt` is the current formatter CLI surface. File inputs are rewritten in
place unless `--check` is present. `laniusc fmt --stdin` and `laniusc fmt -`
read source from stdin and print the formatted source to stdout, so editor
wrappers can format buffers without creating temporary files.

## Package Tooling

`laniusc package lock --manifest path -o path` is the current package tooling
command. It resolves the JSON package manifest through the existing
`PackageManifest` API and writes a JSON package lockfile through the existing
`PackageLockfile` API. The CLI layer does not parse, rewrite, or semantically
inspect Lanius source; package roots, entries, input identities, and import
graph metadata remain reproducibility/control-plane data. Compiling with
`--package-manifest` and direct public `PackageManifest` serde parsing both
enforce package-relative roots and `.lani` entry paths before source-root
loading. Compiling with
`--package-lockfile` still derives semantic module identity from GPU-parsed
module/import records. Lockfile import graph endpoint module paths are artifact
metadata copied from `source_identities`; loading a lockfile rejects endpoint
module paths that disagree with the persisted source identity table. Lockfile
generation rejects quoted imports before writing the lockfile; package-manifest
check mode still reports quoted imports through the GPU resolver diagnostic.
Persisted library dependencies also enforce the package boundary: stdlib
metadata may not declare a dependency on package/user roots. Live source-root
loading has the same boundary: package/user imports may fall back to stdlib
candidates, but imports discovered from stdlib files must resolve inside the
stdlib root or fail with `LNC0024` instead of depending on package/user source
roots.
Within the uploaded source pack, path imports expose public declarations through
GPU imported-visibility records. Same-name public declarations imported from
different modules are treated as ambiguous and must fail instead of resolving by
module load order.

## Compatibility Rules

For `unstable-alpha`, the compiler version is the compatibility boundary. A
program or package that needs reproducible behavior should record the `laniusc`
version plus the `slangc`, `wgpu`, build profile, and shader artifact digest
reported by `--version`.

Breaking source or package changes are allowed in `unstable-alpha`, but they
should be reflected in docs and tests before being treated as externally
usable. Once a future stable edition exists, source accepted by that edition
must either keep compiling under that edition or fail with a stable diagnostic
that names the unsupported migration boundary.

## Current Emit Targets

The current accepted emit targets are `wasm` and `x86_64`.

The current accepted target triples are `wasm32-unknown-unknown` for `--emit
wasm` and `x86_64-unknown-linux-gnu` for `--emit x86_64`. Passing `--target`
is optional, but when it is present it must name one of those triples and it
must match the requested emit target before any source file is loaded.

`wasm` is the primary small-slice byte-output path while the package,
diagnostic, stdlib, and linker surfaces are still being built.

`x86_64` is intentionally narrower than the final native target. The current
boundary is reported by `laniusc --version`; unsupported native source shapes
must fail closed through compiler status/diagnostics instead of silently using a
CPU semantic rewrite or another backend.

## Production Gate

The first production language edition needs a conformance matrix that names:

- supported syntax and HIR records
- supported type-system features
- supported stdlib modules
- supported package/import forms
- supported emit targets and target boundaries
- stable diagnostic codes for unsupported forms
- acceptance tests and performance gates required for release

The current machine-readable inventory for the documented alpha slice is
`docs/language_slice_unstable_alpha.tsv`. It is intentionally conservative:
`supported` and `bounded` rows must point at behavior or durable record tests,
and must name a behavior-facing `evidence_contract` class rather than relying on
source-string or helper-name checks. Allowed evidence classes are
`public-boundary`, `artifact-contract`, `record-invariant`,
`semantic-contract`, `execution-contract`, `fail-closed-diagnostic`, and
`measurement-scaffold`. `planned` and `unsupported` rows make unfinished
production work explicit.
`tools/compiler_acceptance.sh --tier readiness --check-plan` validates this file
without compiling tests or running GPU/scale work.
The performance rows are no-run scaffold claims only: their summary schema must
name replayable source, benchmark-binary hash, local-run provenance,
required-artifact completeness, Lanius wall-time, local performance, readback,
VRAM, and Pareas evidence statuses, production-readiness completion blockers,
explicit local-artifact-only evidence policy, `paper_numbers_accepted=false`,
local-Pareas-artifact comparison policy, freshness status, stale-artifact
names, command-environment schema/checkpoint freshness checks, command
environment hash, optional Pareas source-hash, wall-time/status, and
comparison-ratio fields before a measured run is accepted as
production-readiness evidence.

Until that matrix exists and passes, `unstable-alpha` remains the only
documented edition.
