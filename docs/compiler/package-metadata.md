# Package Metadata And Lockfiles

This chapter documents package manifests, package lockfiles, source-root replay,
and package import-graph validation. This is control-plane source discovery. It
selects source roots, validates source identity, and records replay evidence; it
does not define semantic module identity for the language.

Semantic module identity is still produced from `.lani` source by the lexer,
parser, and type checker. Package metadata can say where files live and whether
a replay is stale. It must not make a package name, filesystem root, old path,
or persisted edge become the semantic source of truth.

## What This Chapter Owns

This chapter covers:

- package manifest JSON shape and path resolution
- package lockfile JSON shape and replay validation
- input/source-identity/import-graph sections
- leading `module` and `import` scanning used for package discovery
- source-root versus stdlib-root precedence
- optional package artifact evidence
- `laniusc package lock`
- package-manifest and package-lockfile entry points used by compile/check and
  source-pack metadata preparation

It does not cover:

- language-level module/import semantics; see
  [Module and source-root resolution](module-resolution.md)
- stdlib source tree contracts and runtime-service boundaries; see
  [Source-level standard library](standard-library.md)
- source-pack artifact/work-queue execution; see
  [Source packs, artifacts, and work queues](source-packs.md)
- parser HIR module/import records; see [Parser and HIR](parser.md)
- type-checker resolved module-path records; see
  [Resident type checker](type-checker.md)

## Source Map

| Source | Responsibility |
| --- | --- |
| `compiler/source_pack/package_manifest.rs` | Manifest JSON, package-relative path validation, canonical root/entry resolution, and conversion to source-pack loaders. |
| `compiler/source_pack/package_lock.rs` | Lockfile JSON, replay validation, input/source/import graph computation, source-root precedence, and package replay entry points. |
| `compiler/source_pack/package_lock/source_scan.rs` | Lightweight leading `module`/`import` scanner used before GPU parsing to build replay metadata and diagnostics. |
| `compiler/source_pack/package_lock/import_graph.rs` | Import graph record shape, canonical ordering, endpoint ownership, cross-library dependency validation, and reachability helpers. |
| `compiler/source_pack/package_lock/artifacts.rs` | Optional produced-artifact identity evidence: target/kind/path/byte length/digest. |
| `cli/package.rs` | `laniusc package lock` command parsing and output-path guard. |
| `cli/args/*` and `cli/compile/source_pack.rs` | Integration of package manifests and lockfiles into compile/check and bounded source-pack preparation modes. |

Keep package metadata changes inside this boundary unless the change alters
language module semantics. If a package test starts asserting semantic lookup,
it is probably testing the wrong layer.

## Manifest Contract

A package manifest is relocatable control-plane metadata. Its paths are relative
to the manifest file's directory.

| Field | Meaning |
| --- | --- |
| `package` | Dot-separated package name. It is package identity, not language module identity. |
| `roots` | Package-relative directories containing user `.lani` source files. |
| `stdlib_root` | Optional package-relative standard-library source root. |
| `entry` | Package-relative entry `.lani` file. |

Manifest validation enforces:

- package names use dot-separated ASCII segments
- each segment starts and ends with a letter or digit and may contain letters,
  digits, `_`, or `-`
- at least one source root is declared
- at most `PACKAGE_MANIFEST_MAX_ROOTS` roots are declared
- manifest paths are relative, portable, and cannot escape with parent
  components
- duplicate and overlapping roots are rejected
- `stdlib_root`, when present, cannot overlap a user source root
- `entry` must be a `.lani` file under one declared user source root
- the entry's source-root-relative path must map to a valid module path

`PackageManifest::resolve_from_dir` canonicalizes roots and entry paths against
the manifest directory. The resolved form uses absolute canonical paths so later
replay can compare filesystem identity instead of trusting the manifest
spelling.

## Lockfile Contract

A package lockfile is resolved replay evidence. It records absolute canonical
inputs and enough package discovery facts to reject stale or tampered metadata
before compiling from it.

The serialized lockfile document contains:

| Section | Meaning |
| --- | --- |
| `version` | Lockfile document version. |
| `package` | Package name copied from the resolved manifest. |
| `language_edition` | Edition marker for the lockfile format. |
| `compiler_version` | Compiler crate version that generated the lockfile. |
| `roots` | Canonical absolute user source roots. |
| `stdlib_root` | Optional canonical absolute standard-library root. |
| `entry` | Canonical absolute entry source path. |
| `inputs` | Stable digest rows for every loaded source file. |
| `source_identities` | File-to-root and file-to-module metadata for every source file. |
| `import_graph` | Resolved source-file import edges plus coarse library dependency edges. |
| `artifacts` | Optional produced-artifact path/digest evidence. |

Only `artifacts` is optional as a caller-supplied produced-output section.
`inputs`, `source_identities`, and `import_graph` are computed when serializing
a generated lockfile. A lockfile loaded from disk keeps these sections as replay
integrity evidence and validates them before use.

## Generation Flow

`laniusc package lock --manifest PATH -o OUT` performs this flow:

1. Parse the package manifest JSON.
2. Resolve manifest-relative paths against the manifest directory.
3. Check the output path does not identify the manifest path.
4. Create `PackageLockfile` from the resolved manifest.
5. Serialize the lockfile, which recomputes replay sections from live source.
6. Reject output paths inside source roots or paths that are also recorded
   produced artifacts.
7. Write the JSON atomically.

Serialization is intentionally not a dumb struct dump.
`to_document_for_serialization` validates source state, loads a path manifest,
computes input identities, source identities, and import graph edges, validates
artifact/source collisions, and then emits the durable document.

## Replay Flow

Compile/check and source-pack preparation can use either a manifest or a
lockfile.

Manifest replay:

1. Resolve the manifest.
2. Create an ephemeral `PackageLockfile` from the resolved manifest.
3. Use the lockfile loading path to validate entry metadata and import graph.
4. Load an in-memory source pack or path-backed source-pack manifest.

Lockfile replay:

1. Parse lockfile JSON with unknown fields denied.
2. Validate shape: versions, roots, entry, sorted roots, source-root overlap,
   compiler version, and existing filesystem state.
3. Validate persisted replay sections: inputs, source identities, import graph,
   and section consistency.
4. Validate artifacts when present.
5. Recompute live source identities/import graph from the current filesystem.
6. Reject stale, moved, retargeted, or precedence-changing imports.
7. Load the source pack or path manifest from validated roots.

The replay path fails closed. If input bytes changed, a source file moved, a
module declaration no longer matches its path, or an import target changed,
package replay reports the lockfile as stale instead of silently falling back to
fresh discovery.

## Input Identities

The `inputs` section records the materialized file set:

- library id
- canonical file path
- byte length
- stable content digest

The digest algorithm is `lanius-fnv1a64-v1`. It is a stable project-local
identity check, not a cryptographic security boundary. Its job is to detect
ordinary stale replay and accidental mutation.

Input validation checks:

- digest algorithm matches
- file set count matches
- each sorted `(library_id, path)` entry matches
- byte length matches
- digest matches current file bytes
- entry source is present in the user library

Input identity owns bytes and path identity only. It does not prove module
identity; that belongs to source identities and import graph validation.

## Source Identities

The `source_identities` section maps each source file to the root and module
metadata package replay needs:

- library id
- canonical file path
- source-root index
- source-root-relative path
- declared module path

Source identity validation checks:

- every source file belongs to exactly one declared library/root
- source-root-relative paths are valid source paths
- source-root-relative paths map to valid module paths
- each source file has a leading module declaration
- declared module path matches the source-root-relative path
- duplicate module identities inside one library are rejected
- entry source has a source identity row

Package names are not substituted for module declarations. A package named
`foo.bar` can help validate metadata, but a source file still declares its own
module path and must match its root-relative file path.

## Leading Source Scanner

Package replay needs source identity and import graph evidence before full GPU
semantic resolution. `package_lock/source_scan.rs` therefore implements a small
leading-declaration scanner.

It accepts:

- leading whitespace and comments
- one leading `module path;` declaration
- zero or more leading `import path;` declarations

It rejects:

- imports before the module declaration
- non-leading module declarations
- multiple module declarations
- non-leading imports after ordinary items
- quoted imports
- aliased imports
- glob imports
- self-imports
- duplicate leading imports
- missing semicolons
- invalid `::` module path segments
- module/import paths deeper than `PACKAGE_MODULE_PATH_SEGMENT_LIMIT`

The scanner is intentionally narrow. It exists so package replay can build
source metadata and good diagnostics without running the full parser. It must
not grow into a second parser for the language. See
[Capacity and limits](capacity-and-limits.md) before changing path-depth limits
or adding new source-shape bounds.

## Import Graph

The `import_graph` section records:

- `library_dependencies`: coarse cross-library dependency edges
- `imports`: exact source-file import edges

Each import edge records:

- source library id
- source file path
- source module path
- import path written by the source file
- target library id
- target file path
- target module path

Import graph validation checks:

- dependency edges are sorted and unique
- imports are sorted by canonical edge identity
- library ids are known replay ids
- dependency rows do not contain self-dependencies
- stdlib cannot depend on the user/package library
- endpoint paths are resolved source paths
- endpoint module paths are valid
- target module path matches the import path
- endpoints match source identity metadata
- exact duplicate import edges are rejected
- a source file cannot import itself
- cross-library imports must be allowed by the coarse library dependency graph

The coarse dependency graph is not enough by itself. It only permits
cross-library edges. The exact source import edge and source identities are the
replay evidence that proves what was resolved.

## Import Resolution Precedence

Package import replay searches user/package roots before stdlib roots for user
sources. This prevents stdlib fallback from masking package modules.

For a user source import:

1. Search user roots.
2. If exactly one user match exists, use it.
3. If multiple user matches exist, report ambiguity.
4. If no user match exists, search stdlib.
5. If exactly one stdlib match exists, use it.
6. If no match exists, report a source-labeled missing import diagnostic.

For a stdlib source import:

1. Search stdlib roots.
2. If exactly one stdlib match exists, use it.
3. If no stdlib match exists, check whether user roots would match.
4. If user roots match, report a package-boundary violation.
5. Otherwise report a source-labeled missing import diagnostic.

Replay also checks precedence staleness. If a persisted lockfile says a user
source imported a stdlib module, but a live user/package source now declares the
same module path, replay rejects the lockfile. The user/package root now wins,
so old metadata must be regenerated.

## Artifact Evidence

The `artifacts` section is optional control-plane reproducibility evidence for
produced files. Each artifact row records:

- target label
- kind label
- canonical file path
- byte length
- digest

Artifact validation checks:

- target and kind labels are ASCII identifier-like labels
- reserved semantic/link labels are not used as target or kind labels
- artifact paths are resolved and canonical
- artifact byte length is nonzero
- artifact digests match current file bytes
- artifact paths are unique
- artifact identities are sorted by target, kind, and path
- artifacts are outside package and stdlib source roots
- artifact paths do not collide with source input paths
- the lockfile output path is not itself a recorded artifact

Artifacts are not language artifacts. They are path/digest evidence attached to
the package lockfile. Source-pack artifact descriptors and backend output
contracts are documented in
[Artifact descriptors and output contracts](artifact-descriptors.md).

## CLI And API Entry Points

Use `laniusc package lock` when a human wants to materialize package replay
evidence:

```bash
laniusc package lock --manifest package.json -o package.lock.json
```

The command accepts `--diagnostic-format`, `--manifest`, and `-o/--out`. It
rejects positional source files and unknown options. The output path guard
compares canonical identity where possible and also handles not-yet-existing
output files by canonicalizing the longest existing prefix.

Compiler entry points use package metadata in three ways:

| Entry point | Behavior |
| --- | --- |
| `PackageManifest::load_json_file` | Parse and resolve a manifest from disk. |
| `ResolvedPackageManifest::load_source_pack` | Create an ephemeral lockfile and load an in-memory pack after replay validation. |
| `ResolvedPackageManifest::load_path_manifest` | Create an ephemeral lockfile and load a path manifest after replay validation. |
| `PackageLockfile::load_json_file` | Parse and validate persisted replay evidence from disk. |
| `PackageLockfile::load_source_pack` | Validate replay evidence and load an in-memory source pack. |
| `PackageLockfile::load_path_manifest` | Validate replay evidence and load a path-backed source-pack manifest. |

CLI compile/check modes treat `--package-manifest` and `--package-lockfile` as
input-mode selectors. They reject positional source files, explicit `--stdlib`,
`--stdlib-root`, and `--source-root` because package metadata already owns the
source roots for that invocation.

## Diagnostics

Package metadata errors should point at the source of truth for the failed
contract:

- malformed manifest JSON points at the manifest command/input context
- invalid manifest roots report the manifest-relative path rule
- invalid lockfile shape tells the user to regenerate the lockfile
- stale input bytes report the path and expected/found byte or digest evidence
- leading source-scan errors use source labels where possible
- missing imports label the import declaration and list searched paths
- package-boundary errors name the stdlib/user edge that crossed the boundary
- artifact collisions name the artifact path and the source/control-plane rule

Do not turn package replay errors into parser/type-check diagnostics. If replay
fails before source loading, the source package is not a valid compiler input
for that mode yet.

## Authoring Rules

When changing package metadata:

1. Decide whether the fact is control-plane metadata or semantic language data.
2. Keep control-plane data in manifests/lockfiles/source-pack records.
3. Keep semantic module/import meaning in parser/type-checker records.
4. Preserve manifest relocatability: manifest paths stay package-relative.
5. Preserve lockfile replay strictness: lockfiles store resolved absolute
   evidence and reject stale current state.
6. Add fields to the serialized lockfile only when replay needs new evidence.
7. Validate field ownership across `inputs`, `source_identities`, and
   `import_graph`; do not let one section invent rows absent from another.
8. Keep leading-source scanning narrow and source-labeled.
9. Use store/path helpers for artifact evidence and output paths instead of
   open-coding path identity comparisons.
10. Add tests for stale, ambiguous, duplicate, cross-boundary, and collision
    cases before relying on broad package compile tests.

Do not add compatibility aliases for old manifest or lockfile fields unless
another human being needs to keep using a real persisted file in the wild.
Unneeded compatibility makes stale metadata look intentional and weakens the
documentation value of the schema.

## Test Evidence

Use focused tests for the layer being changed:

| Change | Evidence |
| --- | --- |
| Manifest path/name validation | Package manifest unit tests or CLI package tests with tiny fixtures. |
| Leading source scanner | Direct scanner tests with minimal source strings. |
| Lockfile input/source/import graph replay | Package lockfile unit tests with small temporary package roots. |
| CLI `package lock` behavior | CLI package tests for argument validation and output-path identity. |
| Source-pack metadata integration | Focused source-pack CLI preparation tests. |
| Generated public surface or large struct changes | `tools/compiler_inventory.py --check docs/compiler/generated/reference.md`. |

Prefer the smallest fixture that proves the failed contract. A two-file package
is usually enough for import graph behavior; a package plus one stdlib root is
enough for precedence and boundary behavior.
