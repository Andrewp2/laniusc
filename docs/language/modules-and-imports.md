# Modules, Imports, And Packages

This chapter describes the current `unstable-alpha` module, import,
source-root, stdlib-root, package manifest, and package lockfile surface.
It is the language-facing companion to
[Packages and source roots](../packages.md),
[Name resolution](name-resolution.md),
[Module and source-root resolution](../compiler/module-resolution.md), and
[Package metadata and lockfiles](../compiler/package-metadata.md).

The core rule is simple: semantic module identity comes from `.lani` source,
not from package names, directory names, lockfile edges, or old path aliases.
Package metadata can decide which files are valid inputs and whether replay is
stale, but the compiler still gets module/import meaning from source that
reaches the lexer, parser, and type checker.

## Source Files And Module Declarations

A single-file program can be compiled without a leading `module` declaration
when it does not need source-root or package module identity:

```lanius
fn main() {
    print(1);
    return 0;
}
```

Source-root and package workflows use leading module declarations to connect a
source file to a module path:

```lanius
module app::main;

import app::math;

fn main() {
    print(app::math::add_fee(36));
    return 0;
}
```

Module paths use `::` separators and identifier-shaped segments. In source-root
and package replay paths, a module declaration is expected to match the file's
root-relative path. For example, `module app::math;` maps to
`app/math.lani` under the selected source root.

## Import Declarations

The documented import form is a module-path import:

```lanius
import app::math;
import core::option;
```

Imports used for source-root and package discovery must appear in the leading
metadata region after the `module` declaration and before ordinary items:

```lanius
module app::main;

import app::math;
import core::option;

fn main() {
    return 0;
}
```

The grammar has a quoted import token path, but source-root and package loading
reject quoted imports before treating them as durable module metadata. Current
code should not use:

- `import "app/math.lani";`
- `import app::*;`
- `import app::math as math;`
- `import app/math;`
- `import app.math;`

Those forms are rejected because they would require host-side import expansion,
path inclusion, alias metadata, or separator normalization that the GPU
module/import records do not own today.

## Source Roots

A source root is a directory searched for module-path imports. The loader maps
an import path to a candidate `.lani` path by replacing `::` with path
segments:

```text
import app::math; -> app/math.lani
```

Example layout:

```text
src/app/main.lani
src/app/math.lani
```

Example command:

```bash
laniusc check --source-root src src/app/main.lani
```

Source-root loading discovers enough files to build a source pack, then the
GPU parser and type checker own semantic module identity, import edges,
declaration visibility, and qualified path resolution.

Source-root loading rejects ambiguous, escaping, non-source, malformed, or
unsupported imports before GPU work when it can report a better source label.
It does not rewrite source or guess a module name from a package or directory.

## Standard Library Roots

The standard library is ordinary source loaded explicitly from a stdlib root.
It is not implicitly preloaded.

```bash
laniusc check --source-root src --stdlib-root stdlib src/app/main.lani
```

User/package imports search user roots first, then stdlib fallback candidates.
Stdlib sources may import other stdlib modules, but they may not import back
into user/package roots. This keeps application code from silently becoming
part of the standard-library dependency graph.

Use [Standard library](../../stdlib/README.md) and the generated
[stdlib reference](../stdlib/generated/reference.md) for the current
source-level stdlib modules and runtime-service warnings.

## Visibility

Only public declarations are imported across module boundaries. Private
declarations remain usable inside their declaring module.

```lanius
module app::math;

pub fn add_fee(value: i32) -> i32 {
    return value + 4;
}

fn hidden(value: i32) -> i32 {
    return value;
}
```

A consumer that imports `app::math` can use public declarations:

```lanius
module app::main;

import app::math;

fn main() {
    print(app::math::add_fee(36));
    return 0;
}
```

Imported declarations must be unambiguous. If two imported modules expose the
same public name and the consumer uses the unqualified name, the current type
checker rejects the ambiguity instead of selecting by source order or import
order.

## Qualified Paths

Qualified paths use the same `::` separator as module declarations and imports.
They can name modules, types, constants, functions, enum variants, and other
visible declarations depending on context.

```lanius
let value: core::option::Option<i32> = core::option::Some(1);
let max: i32 = core::i32::MAX;
```

Path syntax is not itself a support guarantee. The generated
[unstable-alpha slice reference](generated/unstable-alpha-slice.md) names the
bounded rows for qualified type paths, generic type arguments, imported
visibility, calls, constants, enum facts, and backend execution. Use
[Types and values](types-and-values.md) for the user-facing type and value
semantics behind those contexts.

## Package Manifests

A package manifest is relocatable JSON metadata. It describes where package
source files live, which file is the entry point, and optionally where stdlib
source lives.

```json
{
  "package": "example.app",
  "roots": ["src"],
  "stdlib_root": "stdlib",
  "entry": "src/app/main.lani"
}
```

Compile/check can use the manifest as the input-mode selector:

```bash
laniusc check --package-manifest package.json
```

For this mode, do not also pass positional source files, `--source-root`,
`--stdlib-root`, or explicit `--stdlib` inputs. The manifest already owns the
entry, source roots, and stdlib root for that invocation.

The package name is package metadata only. It does not become a module path.
If a source file imports `example::app`, that import must still resolve to a
real source file with a matching `module example::app;` declaration.

## Package Lockfiles

A package lockfile is resolved replay evidence. It records canonical roots,
input identities, source identities, import graph edges, and optional produced
artifact identities so later runs can reject stale or tampered package state.

Generate a lockfile with:

```bash
laniusc package lock --manifest package.json -o package.lock.json
```

Use a lockfile with:

```bash
laniusc check --package-lockfile package.lock.json
```

Lockfile replay fails closed. If source bytes changed, a source file moved, a
module declaration no longer matches its root-relative path, an import target
changed, stdlib fallback precedence changed, or persisted graph metadata is
inconsistent, the compiler rejects the lockfile instead of silently falling
back to fresh discovery.

## Current Boundaries

Current source-root and package workflows intentionally reject some shapes that
could exist in a future language edition:

| Shape | Current boundary |
| --- | --- |
| quoted imports | rejected before source-root/package metadata can omit import graph evidence |
| import aliases | rejected until alias metadata is represented by GPU module/import records |
| glob imports | rejected until expansion and visibility are represented without host guessing |
| imports before `module` | rejected because source identity is unknown |
| imports after ordinary items | rejected for source-root/package discovery because metadata would be incomplete |
| filesystem or dotted separators | rejected; module paths use `::` |
| over-deep module/import paths | rejected at current source-root/package depth limits |
| stdlib importing user roots | rejected as a package-boundary violation |
| package name as module evidence | rejected; source declarations own module identity |

These are fail-closed boundaries, not compatibility gaps. Adding fallback
resolution for them would make package metadata look more meaningful than the
source declarations and GPU records that actually own language semantics.

## Evidence And Diagnostics

The generated slice rows under `packages` and `imports` are the current
evidence index:

- [Packages rows](generated/unstable-alpha-slice.md#packages)
- [Imports rows](generated/unstable-alpha-slice.md#imports)

Useful diagnostics and tooling references:

- [Diagnostics](../DIAGNOSTICS.md)
- [generated diagnostic code index](../diagnostics/generated/error-index.md)
- [Module and source-root resolution](../compiler/module-resolution.md)
- [Package metadata and lockfiles](../compiler/package-metadata.md)

Use `laniusc check` when validating package/source-root behavior without
writing target bytes.

## Update Rule

Update this chapter when module declaration rules, import forms, source-root
search, stdlib fallback, visibility semantics, package manifest shape,
lockfile replay evidence, or package/source-root diagnostics change in a way
users can observe. Update the generated slice first when the change adds or
removes support evidence.
