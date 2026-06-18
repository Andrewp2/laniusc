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

For a reader-oriented entry point into the current public language surface, see
`docs/language/README.md`. For a generated row-by-row reference to the current
slice, see `docs/language/generated/unstable-alpha-slice.md`. This file remains
the policy and inventory contract.

## Version Surface

`laniusc --version` is the supported machine-checkable summary for the local
binary. It must print:

- compiler package version on the first line as `laniusc <version>`
- `language-edition: unstable-alpha`
- `edition-policy: ...`
- `targets: x86_64, wasm`
- `default-target: x86_64`
- `target-triples: x86_64-unknown-linux-gnu, wasm32-unknown-unknown`
- `x86_64: ...`
- `release-channel: source-worktree`
- `distribution-status: ...`
- `slangc: ...`
- `wgpu: ...`
- `build-profile: ...`
- `shader-artifact-digest: ...`
- `shader-artifact-count: ...`
- `shader-artifact-max-bytes: ...`
- `shader-artifact-max-name: ...`
- `shader-artifact-size-guard: enforced|disabled`
- `shader-artifact-max-spv-bytes: ...`
- `slangc-version-timeout-ms: ...`
- `shader-compile-timeout-ms: ...`

The version command is metadata-only: it must not require source files, perform
GPU compilation, write outputs, or validate unrelated compile flags.

`laniusc doctor` is the no-run local installation check for the same bounded
tooling surface. It emits a JSON document with schema version, compiler version,
language edition, accepted emit targets, accepted target triples, Slang
availability, build metadata including active shader artifact size-guard
metadata and build-time Slang timeout guardrails, distribution/release status,
readiness gate metadata, the accepted
diagnostic render formats and LSP diagnostic metadata, and explicit no-run
guards. If `SLANGC` is set, doctor checks that configured path; otherwise it
checks `slangc` on `PATH`. The distribution object is
deliberately negative in the current edition: there is no production release
claim, stable install artifact, package-manager channel, or release-artifact
workflow yet. The readiness object is likewise conservative: generated scale
and Pareas lanes are opt-in, paper numbers are reference-only, and production
claims require local artifacts plus claimable pass/link contracts. The command
must not compile source, create a GPU device, execute readiness gates, invoke
Pareas, or run generated workloads.

`laniusc lsp capabilities` and the initialize-response
`experimental.laniusc` object carry the same distribution object for editor
wrappers. This keeps release-channel and production-claim metadata available in
one LSP metadata query, without requiring an editor to shell out to `doctor`.
These CLI, LSP, and version fields prove only that the queried binary publishes
the bounded metadata contract and does not present a source worktree as a
production release. They do not prove that shader artifacts currently build,
that emit targets pass their acceptance tests, or that editor diagnostics have
measured latency/responsiveness evidence; those claims still require fresh
build/test artifacts and the production-readiness gates named below.

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
`laniusc lsp capabilities` reports the no-run editor metadata, including the
CLI diagnostic format registry used by fallback editor wrappers, and
`laniusc lsp serve --stdio` handles the minimal `initialize`, `shutdown`, and
`exit` JSON-RPC handshake without compiling source, creating a GPU device, or
generating target code. The stdio server stores opened documents with
full-document `didChange` updates only, rejects ranged incremental changes as
invalid parameters, and rejects malformed `textDocument/formatting` options
before computing edits while preserving the stored open-document text. It also
serves bounded `textDocument/diagnostic` pull
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
Direct reverse import edges may be persisted as lockfile replay metadata, but
package check/compile still reports the normal GPU import-cycle diagnostic when
those edges form a two-module cycle.
Persisted library dependencies also enforce the package boundary: stdlib
metadata may not declare a dependency on package/user roots. Live source-root
loading has the same boundary: package/user imports may fall back to stdlib
candidates, but imports discovered from stdlib files must resolve inside the
stdlib root or fail with `LNC0024` instead of depending on package/user source
roots.
Package roots are candidate search roots, not a whole-root source inventory:
lockfile replay rejects input and source-identity rows that are not reachable
from the package entry through persisted import graph edges. This keeps
hand-edited lockfiles from promoting unrelated `.lani` files into package input
evidence before GPU module/import records revalidate the live source pack.
Optional produced-artifact identities are likewise control-plane metadata:
their `target` or `kind` labels may not reuse source-pack link artifact,
link-record, or runtime-service evidence labels, so package lockfiles cannot
present a produced file as GPU/link evidence by naming convention.
Within the uploaded source pack, path imports expose public declarations through
GPU imported-visibility records. Same-name public declarations imported from
different modules are treated as ambiguous and must fail instead of resolving by
module load order.

## Standard Library Semantics

The active stdlib contract is source-level and explicit. A program must supply
or load stdlib modules through `--stdlib-root`; stdlib files are not implicitly
preloaded and host-facing `std` APIs do not become executable just because their
declarations type-check.

`core::char` exposes ASCII classification helpers and
`eq_ignore_ascii_case` as source-level helpers. They type-check through
`--stdlib-root` and remain frontend evidence only; they do not imply Unicode
case folding, locale behavior, string support, or backend execution coverage.

`std::path` is currently a lexical helper module, not a host path API. It can
type-check through `--stdlib-root` and exposes byte-level constants and
classifiers for Unix/Windows separators, NUL/control bytes, Windows-reserved
component punctuation, drive-prefix headers, `.`/`..` component markers, and
normal relative component headers. The separator classifier also has a focused
source-pack x86 execution gate. Broader path helpers remain source-level
`--stdlib-root` evidence only: they do not allocate path buffers, normalize or
canonicalize paths, inspect the filesystem, or bind runtime path services.

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

`x86_64` is the primary executable byte-output path while the package,
diagnostic, stdlib, and linker surfaces are still being built. The `wasm`
target is accepted for target-surface compatibility but currently fails closed
at the backend boundary until Wasm lowering is rebuilt as record/count/prefix
sum/scatter passes.

## Beginner Smoke Examples

`sample_programs/` contains small external-facing programs with paired
`.stdout` files. `sample_programs/checkout_fee.lani` is a beginner-oriented
helper-call smoke: it exercises a typed helper function, integer arithmetic,
single-file compilation, and printed output without requiring packages,
stdlib-root setup, or native linking. The focused executable checks now belong
to the x86 backend; `tests/codegen_wasm.rs` only checks the stable fail-closed
Wasm backend boundary.

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

The current machine-readable inventory source for the documented alpha slice is
`docs/language_slice_unstable_alpha.tsv`. The reader-facing generated reference
is `docs/language/generated/unstable-alpha-slice.md`; regenerate and check it
with:

```bash
tools/language_slice_summary.py --output docs/language/generated/unstable-alpha-slice.md
tools/language_slice_summary.py --check docs/language/generated/unstable-alpha-slice.md
```

The inventory is intentionally conservative:
`supported` and `bounded` rows must point at behavior or durable record tests,
and must name a behavior-facing `evidence_contract` class rather than relying on
source-string or helper-name checks. Allowed evidence classes are
`public-boundary`, `artifact-contract`, `record-invariant`,
`semantic-contract`, `execution-contract`, `fail-closed-diagnostic`, and
`measurement-scaffold`. `planned` and `unsupported` rows make unfinished
production work explicit.
Source-level stdlib usability rows that use `semantic-contract` describe
stdlib-root loading and type-check behavior only; they do not claim runtime
service execution unless a separate `execution-contract` row names that
executable behavior.
Linking `artifact-contract` rows must exercise persisted behavior: store-input
tests should prove that a rejected link page is not written and that replay-only
sidecar counts cannot stand in for concrete interface, object, partial-link, or
linked-output artifact records. Final linked-output evidence must not be backed
by object-domain descriptor contracts; object records are link inputs, not final
artifact outputs.
`tools/compiler_acceptance.sh --tier readiness --check-plan` validates this file
without compiling tests or running GPU/scale work.
Passing the no-run plan check is documentation and inventory evidence only; it
does not prove that every advertised emit target currently has a green local
build lane. Native `x86_64` production readiness still requires fresh local
build artifacts and claimable pass/link contracts, so a blocked native shader
lane must be reported as a current production-readiness limit rather than as an
accepted release claim.
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
