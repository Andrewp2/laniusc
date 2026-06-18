# Module And Source-Root Resolution

This document explains how `.lani` files become semantic modules. It is the
compiler-author guide for the boundary between CLI/package loading,
source-pack metadata, GPU parser HIR, and the resident type-checker module-path
state.

Use this page when changing module declarations, import loading, source-root
search, package manifests, package lockfiles, or any pass that consumes
qualified paths. Use `generated/reference.md` for exact current function names,
pass load sites, and status-code numbers.
Use [Source-level standard library](standard-library.md) for the current
stdlib-root source contract, user/stdlib boundary, and stdlib evidence policy.

## Core Rule

Module identity comes from source code that reaches the GPU frontend.

The host may discover candidate files, canonicalize roots, reject malformed
metadata, upload source bytes, preserve file paths for diagnostics, and persist
package/source-pack planning records. It must not make a package name, root
directory, filesystem path, symlink spelling, output artifact, or old alias into
semantic module identity.

The durable boundary is:

| Plane | Owns | Must not own |
| --- | --- | --- |
| CLI and package loading | input mode, root selection, path validation, lockfile loading | declaration lookup, visibility, type identity, source rewriting |
| Source-root discovery | finding `.lani` files for leading module-path imports | import alias expansion, glob expansion, quoted-path includes, fallback semantic names |
| Source packs | file/library metadata, source strings, job scheduling, artifact records | language module identity or name resolution |
| Lexer/parser | source-file ids, token-file ids, module/import/item HIR records | host path policy or package fallback policy |
| Type checker `module_path` | module ids, import edges, declaration tables, resolved type/value paths | file discovery, path canonicalization, package persistence |
| Diagnostics | source labels from file ids and token spans | raw internal ids without source context |

If a proposed change would make the host "help" by rewriting source, expanding
imports, accepting old path names, or doing declaration lookup, it belongs
somewhere else or should be rejected.

## Input Surfaces

There are several ways source reaches the compiler, but they converge on a
source pack before parser/type-checker semantic resolution:

| Surface | Loading behavior | Semantic module source |
| --- | --- | --- |
| one input file | read one file or source string | parser HIR from that file |
| explicit source pack | caller supplies source strings and library ids | parser HIR from supplied files |
| path-backed source pack | caller supplies file metadata and deferred paths | parser HIR when jobs load source |
| `--source-root` | discover imports under user roots | parser HIR from discovered files |
| `--stdlib-root` | discover stdlib fallback imports | parser HIR from discovered files |
| package manifest | validate package-relative roots and entry, then use source-root loading | parser HIR from package sources |
| package lockfile | validate persisted roots, source identities, and import graph, then replay loading | parser HIR from replayed sources |
| source-pack descriptor/work queue | persisted metadata and claimable jobs | parser HIR inside frontend work items |

Package names and package paths are control-plane data. They explain where
source files are allowed to live and which files were discovered, but they do not
stand in for `module app::main;` or `import app::util;`.

## Data Flow

The normal source-root compile/check path is:

1. CLI parsing selects a single entry input plus optional `EntrySourceRoots`.
2. `load_entry_with_source_roots` calls `collect_entry_source_root_paths`.
3. The entry source is scanned only for leading module/import metadata needed to
   discover more files.
4. Imports are mapped to candidate paths by replacing `::` with path segments
   and adding `.lani`.
5. Discovered paths are partitioned into stdlib and user source lists.
6. `load_explicit_source_pack_manifest_from_paths` reads source text and
   attaches provenance paths.
7. `GpuCompiler::type_check_source_pack_manifest` or backend compile paths pass
   those sources into the GPU lexer/parser/type-checker pipeline.
8. The lexer writes source-file boundaries and `token_file_id` rows.
9. The parser emits HIR item/path metadata for module declarations, imports,
   declarations, and qualified paths.
10. `type_checker/module_path` records module/import/declaration/path rows,
    resolves them, and projects resolved paths into later type/call/value facts.
11. Diagnostics map parser/type-check status back through token file ids and
    diagnostic source paths.

The package-manifest and package-lockfile paths add metadata validation before
step 2. The explicit source-pack path starts at step 6 because the caller has
already provided the source list.

## Source-Root Discovery

Source-root discovery is a loader, not a semantic resolver. Its job is to build
a complete enough source-pack input for the GPU resolver.

Discovery currently accepts only leading module-path import forms:

```lani
module app::main;
import app::util;
import core::i32;
```

It rejects these shapes before lookup:

| Shape | Reason |
| --- | --- |
| `import app::util as util;` | aliases are not represented by GPU module/import records yet |
| `import app::*;` | globs would require host-side expansion or missing visibility rows |
| `import "app/util.lani";` | quoted paths would turn host files into semantic import evidence |
| `import app/util;` or `import app.util;` | filesystem/package separators are not module separators |
| imports after ordinary items | discovery would miss edges and persist incomplete package metadata |
| import paths deeper than eight segments | current GPU module-key storage has an eight-segment slice |

These are not compatibility cases. Do not add aliases, globs, quoted include
fallbacks, old path spellings, or separator normalization unless a real other
human depends on that behavior and there is a bounded migration/removal plan.
Without that human dependency, compatibility is a net negative: it adds branches
and leaves a false signal that the old shape is meaningful.

### Root Precedence

Source-root imports use two library classes:

| Importer | Search behavior |
| --- | --- |
| user/package source | search user roots first, then stdlib fallback |
| stdlib source | search stdlib roots only |

User/package roots take precedence over stdlib fallback. A stdlib source cannot
import back into a user/package root. If a stdlib import only resolves in a user
root, the loader reports the package-boundary diagnostic instead of letting
stdlib code acquire a user dependency.

User roots must be canonical, distinct, and non-overlapping. This prevents root
order, symlink spelling, or overlapping directories from choosing semantic
module identity.

### File Candidate Rules

A source-root import `app::util` maps to candidate path
`<root>/app/util.lani`. A candidate is accepted only when it:

- canonicalizes inside the selected root
- is a regular `.lani` source file
- is not ambiguous with another candidate in the same search class
- has not already been loaded by canonical path

The path mapping is discovery metadata. The target file still has to publish
GPU-visible module/import records. Package replay additionally validates that a
source-root-relative path and the leading module declaration agree before it
writes or trusts lockfile source identities.

## Source Packs And Libraries

`ExplicitSourcePack` is the in-memory source-pack shape. It stores:

- `sources`
- optional diagnostic/provenance `source_paths`
- per-source `library_ids`
- validated library dependency edges

`ExplicitSourcePackPathManifest` is the path-backed persisted-planning shape. It
stores file metadata rather than source strings:

- path
- byte length
- optional modified time
- optional line count
- library id
- validated library dependency edges

Both shapes validate library ids and dependency topology. Those checks are build
graph checks, not language checks. They prove that frontend/codegen jobs can be
scheduled and replayed, not that an import resolves or a declaration is visible.

The source-pack layer must stay out of semantic language decisions. It may say
"this file belongs to library 1" or "this job depends on an earlier frontend
job"; it may not say "this file is module `app::util` because its path is
`app/util.lani`."

## Package Manifest And Lockfile Replay

Package manifests describe package-relative loading metadata:

- package name
- user source roots
- optional stdlib root
- entry file

Resolved manifests canonicalize roots, reject parent-directory escapes, require
portable `/` path separators in manifest metadata, reject overlapping roots, and
ensure the entry is below a declared source root. This keeps package metadata
relocatable and keeps symlink/root evidence out of semantic resolution.

Package lockfiles persist resolved control-plane evidence:

- canonical roots
- input/source identity rows
- import graph edges
- optional produced artifact identities

Replay validates the persisted evidence before recompiling. Important checks:

- source identities must include source-root index, source-root-relative path,
  and module path metadata
- import graph endpoints must refer to known source identities
- endpoint module paths must match source identities
- user/package edges cannot be replaced by stdlib fallback edges when a
  user/package module now exists
- artifact identities must remain outside source roots
- lockfile metadata cannot invent extra library ids or duplicate dependency
  rows

The dependency evidence is the explicit source import edge plus validated source
identities. A coarse library dependency row is never enough by itself.

See [Package metadata and lockfiles](package-metadata.md) for the detailed
manifest/lockfile schema, leading-source scanner, import graph validation, and
replay failure rules.

## Parser/HIR Boundary

The lexer and parser are the first GPU-visible source boundary. The source-pack
lexer records file starts, file lengths, and token file ids. The parser consumes
that sideband and emits HIR records for module declarations, imports, items, and
paths.

The parser does not know package roots. It sees token streams and source-file
ids. A source file path is useful for diagnostics, but the parser-owned semantic
facts are the HIR rows produced from source text.

When changing syntax that affects modules or imports, make sure the parser emits
enough HIR data for the type checker to own the semantic decision. Do not patch
source-root discovery to compensate for missing HIR.

## Type-Checker Module Path State

`type_checker/module_path` owns the resident semantic resolver.

The major pass groups are:

| Group | Role |
| --- | --- |
| `RecordDiscovery` | mark module/import/declaration/path HIR records, scan flags, scatter compact rows |
| `ModuleIndex` | build module keys, sort/deduplicate modules, resolve imports, validate import cycles |
| declaration passes | collect declaration rows, validate duplicate declarations, split type/value namespaces |
| import-visible passes | build imported type/value visibility tables |
| path resolution passes | resolve local, imported, and qualified type/value paths |
| projection passes | turn resolved paths into type refs, calls, consts, enum facts, and match payload bindings |
| `ModulePathState` | retain buffers and bind groups for later passes and backend metadata |

The resident layout sizes module capacity by source-file capacity and record
capacity by token capacity. That means the module table is tied to loaded source
files, while paths, imports, and declarations scale with HIR/token records.

Module keys currently reserve eight path segments, and each segment contributes
four radix steps. If this limit changes, update all of these together:

- source-root/package path depth diagnostics
- `MODULE_KEY_SORT_SEGMENTS`
- shader row widths that use `SORT_PATH_SEGMENTS`
- module-key radix step counts
- generated reference tables and focused tests

If normal library code can plausibly hit the bound, prefer replacing the bound
with segmented storage and scans instead of documenting a larger arbitrary cap.

## Resolved Path Consumers

Module path resolution is not done when a table is sorted. It is done only when
the consumer that needs a semantic fact reads the resolved row and validates it
in context.

Important consumer boundaries:

- type paths consume `resolved_type_decl` and produce type refs/status
- value-call paths consume `resolved_value_decl` and become call rows
- value-const paths consume `resolved_value_decl` and write visible expression
  facts
- unit enum variants and enum constructors validate the resolved declaration
  kind and payload expectations
- match pattern binding uses resolved enum payload information

Do not treat a path-resolution array as feature support by itself. A feature is
supported only when parser HIR, resolver rows, projection consumers, diagnostics,
and backend metadata all agree.

## Diagnostics

Every module/source-root error should point at the source construct that made
the problem visible:

| Failure | Preferred source location |
| --- | --- |
| missing source-root module | the importing `import` declaration |
| ambiguous source-root module | the importing `import` declaration, with candidate notes |
| package boundary violation | the stdlib/user import declaration that crosses the boundary |
| unsupported import form | the alias/glob/quoted/path-separator token |
| over-depth import path | the whole import path span |
| over-depth module path | the whole module declaration path span |
| duplicate module declaration | the duplicate module declaration, with first declaration context when available |
| import cycle | an import declaration that participates in the cycle |
| unresolved type/value path | the path use, not a later consumer fallback |

Raw file ids, module ids, record indices, and root indices are not end-user
locations. They are useful in debug logs and generated inventories, but a
diagnostic that reaches a user should recover file path, line, column, source
line, and a narrow label length.

## Adding Module-Like Behavior

Use this checklist before editing:

1. Decide whether the change is file discovery, parser syntax/HIR, semantic
   module resolution, projection into type/value facts, backend metadata, or
   persisted package/source-pack metadata.
2. If it affects syntax, make the parser publish explicit HIR rows instead of
   teaching source-root discovery to infer behavior.
3. If it affects import visibility or declaration lookup, add rows/passes under
   `type_checker/module_path`.
4. If it affects source-root/package replay, keep host parsing limited to
   metadata completeness and source-spanned rejection.
5. If it affects persisted package/lockfile records, validate old and new record
   shape at the loading boundary and document any real human compatibility need.
6. If it affects path limits, either remove the limit with segmented data or
   keep the failure at the exact source path that exceeded it.
7. If it affects backend use, expose the new fact through retained type-check
   metadata wrappers instead of reaching into resident state.
8. Add the smallest source fixture that proves the behavior at the owning
   boundary.
9. Update `generated/reference.md` when public operations, pass load sites,
   status codes, or buffer carrier structs change.

## Common Wrong Fixes

Avoid these shapes:

- source concatenation or source rewriting to simulate imports
- CPU declaration lookup or visibility filtering
- path-to-module fallback when a file is missing `module path;`
- package-name prefixing in source module declarations
- filesystem separator normalization into module separators
- same-source shortcuts for qualified paths
- hash-only lookup without byte equality and duplicate validation
- old path aliases kept because internal callers or tests still use them

Internal callers and tests are code to update. They are not a compatibility
reason by themselves.

## Verification

For source-root and module-resolution changes, prefer focused tests by boundary:

| Change | Proof shape |
| --- | --- |
| source-root discovery | tiny directory fixture with entry/import files and diagnostic assertion |
| package manifest validation | manifest fixture that proves root/path/entry behavior |
| package lockfile replay | stale or tampered lockfile fixture with the expected replay diagnostic |
| parser module/import syntax | smallest source that accepts or rejects before type checking |
| module index/import resolution | source-pack fixture with two or three files |
| path projection | source fixture where the resolved type/value path is consumed |
| diagnostic mapping | assertion on diagnostic code plus labeled source span |
| performance-sensitive resolver change | focused compile/check timing or shader-loop audit, not a broad workspace test |

Do not use a passing single-file test to prove source-root behavior. Do not use
package metadata tests to prove GPU semantic resolution. Match the test to the
layer that owns the decision.
