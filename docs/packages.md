# Packages And Source Roots

This chapter is the user-facing reference for source roots, stdlib roots,
package manifests, and package lockfiles. It explains how `laniusc` finds files
for multi-file programs without making package metadata the semantic source of
truth.

For language-level module syntax, use
[Modules, Imports, And Packages](language/modules-and-imports.md). For command
syntax, use [Laniusc Invocation](invocation.md). For implementation details, use
[Package metadata and lockfiles](compiler/package-metadata.md) and
[Module and source-root resolution](compiler/module-resolution.md).

## Core Rule

Package and source-root metadata select files. They do not create language
meaning.

Semantic module identity comes from `.lani` source:

```lanius
module app::math;
```

Imports also come from source:

```lanius
import app::math;
```

Package names, directory names, lockfile edges, artifact metadata, and old path
aliases do not become module names. If source imports `example::app`, a real
loaded source file still needs a matching `module example::app;` declaration.

## Input Modes

`laniusc` selects one input mode:

| Input shape | Meaning |
| --- | --- |
| one positional file | Compile or check that file as an isolated input. |
| `--source-root DIR entry.lani` | Load leading user module-path imports from one or more user roots. |
| `--stdlib-root DIR entry.lani` | Load leading stdlib module-path imports from the stdlib root. |
| `--source-root DIR --stdlib-root DIR entry.lani` | Search user roots first, then stdlib fallback candidates. |
| `--package-manifest FILE` | Load manifest metadata that owns entry, source roots, and optional stdlib root. |
| `--package-lockfile FILE` | Replay a resolved package lockfile. |

Do not combine package manifest or lockfile input modes with positional source
files, `--source-root`, `--stdlib-root`, or explicit `--stdlib` inputs. The
package metadata already owns those selectors for the invocation.

## Source Roots

A source root is a directory searched for module-path imports. The loader maps
`::` to path segments and appends `.lani`:

```text
import app::math; -> app/math.lani
```

Example layout:

```text
src/app/main.lani
src/app/math.lani
```

`src/app/math.lani`:

```lanius
module app::math;

pub fn add_fee(value: i32) -> i32 {
    return value + 4;
}
```

`src/app/main.lani`:

```lanius
module app::main;

import app::math;

fn main() {
    print(app::math::add_fee(36));
    return 0;
}
```

Check the entry:

```bash
laniusc check --source-root src src/app/main.lani
```

Source-root loading discovers files needed to build the source pack. The GPU
parser and type checker still own semantic module identity, import edges,
visibility, and qualified path resolution.

## Standard Library Roots

The standard library is ordinary source and is not implicitly preloaded. Use
`--stdlib-root` when source imports stdlib modules:

```bash
laniusc check --source-root src --stdlib-root stdlib src/app/main.lani
```

User roots are searched before stdlib fallback candidates. Stdlib files may
import other stdlib files, but stdlib-to-user-root imports are rejected so
application code cannot silently become part of the standard-library graph.

Use [Standard Library Overview](stdlib/README.md) for stdlib module families,
runtime-bound API contracts, and execution boundaries.

## Package Manifests

A package manifest is relocatable JSON metadata. Its paths are relative to the
manifest file:

```json
{
  "package": "example.app",
  "roots": ["src"],
  "stdlib_root": "stdlib",
  "entry": "src/app/main.lani"
}
```

Check or compile through the manifest:

```bash
laniusc check --package-manifest lanius.package.json
laniusc --package-manifest lanius.package.json -o main
```

Manifest fields:

| Field | Meaning |
| --- | --- |
| `package` | Package identity metadata. It is not a language module path. |
| `roots` | Package-relative user source roots. |
| `stdlib_root` | Optional package-relative stdlib source root. |
| `entry` | Package-relative entry `.lani` file. |

The entry must be a `.lani` file under a declared user source root. Its
root-relative path is expected to match its leading `module path;` declaration.

## Package Lockfiles

A package lockfile is replay evidence. It records canonical roots, input
digests, source identities, import graph edges, and optional produced artifact
identities so later invocations can reject stale or tampered package state.

Generate a lockfile:

```bash
laniusc package lock --manifest lanius.package.json -o lanius.lock.json
```

Use it:

```bash
laniusc check --package-lockfile lanius.lock.json
laniusc --package-lockfile lanius.lock.json -o main
```

Lockfile replay fails closed. If source bytes changed, a file moved, a module
declaration no longer matches its source-root-relative path, an import target
changed, stdlib fallback precedence changed, or persisted graph metadata is
inconsistent, replay rejects the lockfile instead of silently falling back to
fresh discovery.

Lockfiles are package integrity artifacts. They are not semantic language
records and do not override live source declarations.

## Supported Import Metadata

Imports used for source-root and package discovery must appear in the leading
metadata region after the optional leading `module` declaration and before
ordinary items:

```lanius
module app::main;

import app::math;
import core::option;

fn main() {
    return 0;
}
```

Current workflows intentionally reject:

| Shape | Reason |
| --- | --- |
| `import "app/math.lani";` | quoted path imports would require path inclusion evidence outside module records |
| `import app::*;` | glob expansion has no current GPU-owned visibility metadata |
| `import app::math as math;` | alias metadata is not represented by current module/import records |
| imports before `module` | source identity is not known yet |
| imports after ordinary items | package/source-root discovery would miss dependency metadata |
| `import app/math;` or `import app.math;` | module paths use `::` separators |
| package name as module evidence | source declarations own module identity |

These are fail-closed boundaries. Adding fallback resolution would make package
metadata look more meaningful than the source and GPU records that actually own
language semantics.

## Diagnostics And Evidence

Package and source-root diagnostics should point at the source of truth:

- malformed source imports should point at the import declaration
- missing or mismatched module declarations should point at the source file
- package manifest metadata errors should point at the manifest selector or
  invalid manifest field when possible
- stale lockfile replay should report the stale persisted/live boundary rather
  than proceeding with fresh discovery

The generated [unstable-alpha slice reference](language/generated/unstable-alpha-slice.md)
contains exact package/import evidence rows. Important row families include:

- `manifest-*`
- `lockfile-*`
- `package-name-not-import-evidence`
- `stdlib-fallback-precedence`
- `stdlib-import-user-boundary`
- `source-root-*`
- `imports/*` rows for visibility and ambiguity

Rows marked `bounded` describe current bounded evidence. Rows marked `planned`
are not support claims.

## Source-Pack Workflows

Source-pack metadata, preparation, descriptor, and progress flags are lower
level workflows for larger or persisted compilation experiments. They are not
the normal single-package entry path.

Use source-pack modes only when you specifically need bounded metadata chunks,
prepared artifact roots, descriptor output, or work-queue progress. Use
[Source packs, artifacts, and work queues](compiler/source-packs.md) and
[Artifact descriptors and output contracts](compiler/artifact-descriptors.md)
for the maintainer-facing model.

## What Not To Infer

Do not infer these claims from package support:

- package names become module names
- package manifests are a full package manager
- lockfiles override source module declarations
- quoted imports, aliases, or globs are supported
- stdlib modules are auto-imported
- source-root checks prove native execution
- descriptor or artifact metadata is executable target output

## Updating Package Docs

Update this chapter when any user-visible package/source-root contract changes:

- manifest JSON shape
- package lockfile behavior
- source-root or stdlib-root loading
- import metadata accepted for package discovery
- package/lockfile diagnostics
- package input-mode CLI examples
- source-pack descriptor/progress boundary if it affects user routing

If a new package claim needs evidence, add or update the row in
`docs/language_slice_unstable_alpha.tsv`, regenerate the generated slice
reference, and keep this chapter aligned with the proven behavior.
