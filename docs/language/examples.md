# Lanius Worked Examples

This chapter is the practical companion to the language reference. It shows
small source layouts and commands that fit the current `unstable-alpha` slice.
Use it together with [Laniusc Invocation](../invocation.md), [Modules, Imports,
And Packages](modules-and-imports.md), and the generated
[unstable-alpha slice reference](generated/unstable-alpha-slice.md).

The examples are intentionally conservative:

- `laniusc check` examples prove frontend diagnostics only.
- `laniusc fmt` examples prove lexical formatting only.
- `laniusc --emit x86_64` examples are target-byte examples only for the
  bounded x86_64 slice named by the generated slice inventory.
- Source-level stdlib examples require `--stdlib-root`; stdlib source is not
  implicitly preloaded.
- Package names, directories, and lockfile metadata do not create module
  identity. Parsed `module path;` declarations and `import path;` declarations
  do.

Small maintained smoke fixtures live in
[sample_programs](../../sample_programs/README.md). Each sample has a row in
[sample_programs/MANIFEST.tsv](../../sample_programs/MANIFEST.tsv) and a sibling
`.stdout` file. Those fixtures are documentation-smoke examples, not broad
language-conformance, backend, or performance evidence.

## Single-File Smoke Program

The smallest useful shape is a file with ordinary functions and a `main`
function:

```lanius
fn add_fee(value: i32) -> i32 {
    return value + 4;
}

fn main() {
    print(add_fee(36));
    return 0;
}
```

This is the source of
[sample_programs/checkout_fee.lani](../../sample_programs/checkout_fee.lani).
Check it, format-check it, or compile it through the default native target:

```bash
laniusc check sample_programs/checkout_fee.lani
laniusc fmt --check sample_programs/checkout_fee.lani
laniusc --emit x86_64 sample_programs/checkout_fee.lani -o /tmp/checkout_fee
```

When adding a new sample, also add a sibling `.stdout` file and a manifest row.
Do not use a sample as evidence for packages, imports, stdlib execution, x86
support, or performance unless a behavior-facing test or measured artifact
names that exact claim.

## Source-Root Modules

Use source roots when a program is split across module-path imports. The root
maps imported module paths to root-relative `.lani` paths:

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

Check or compile the entry file with the source root:

```bash
laniusc check --source-root src src/app/main.lani
laniusc --source-root src src/app/main.lani -o /tmp/app-main
```

The import path `app::math` maps to `src/app/math.lani`. The compiler does not
infer `app::math` from the file name alone, rewrite the source, or accept old
path-style import aliases. The source file still owns its semantic module
identity through `module app::math;`.

## Explicit Stdlib Root

The standard library is ordinary source under
[stdlib](../../stdlib/README.md). Load it explicitly when an example imports a
stdlib module:

```lanius
module app::main;

import core::i32;

fn main() {
    let magnitude: i32 = core::i32::abs(-7);
    print(magnitude);
    return 0;
}
```

Check with both roots:

```bash
laniusc check --source-root src --stdlib-root stdlib src/app/main.lani
```

This proves the frontend can load and type-check the explicitly imported
source-level stdlib module. It is not a claim that every stdlib helper is
available on every backend. Use the generated
[stdlib reference](../stdlib/generated/reference.md) and the
[standard library README](../../stdlib/README.md) for the current module list,
declaration list, and runtime-service warnings.

## Option And Result Helpers

Source-level generic helper examples should prefer `check` unless a backend row
names the exact executable shape. The maintained fixture
[sample_programs/option_result_helpers.lani](../../sample_programs/option_result_helpers.lani)
uses `core::option` and `core::result` helpers:

```bash
laniusc check --stdlib-root stdlib sample_programs/option_result_helpers.lani
```

That example is useful for reading qualified generic types, enum constructors,
`match`-backed helpers, and stdlib-root loading together. It should not be used
as proof for general enum lowering, broad generic execution, or runtime service
binding.

## Package Manifest

A package manifest is loading metadata for a source tree. It is not semantic
module identity.

Example layout:

```text
lanius.package.json
src/app/main.lani
src/app/math.lani
stdlib/core/i32.lani
```

Manifest:

```json
{
  "package": "example.app",
  "roots": ["src"],
  "stdlib_root": "stdlib",
  "entry": "src/app/main.lani"
}
```

Common commands:

```bash
laniusc check --package-manifest lanius.package.json
laniusc package lock --manifest lanius.package.json -o lanius.lock.json
laniusc check --package-lockfile lanius.lock.json
```

The package name `example.app` does not make an `example::app` module. If source
imports `example::app`, there must be a corresponding source file and parsed
`module example::app;` declaration reachable through the selected roots.

## Diagnostics And Formatting

For editor or CI diagnostics, use `check` with an explicit diagnostic format:

```bash
laniusc check --diagnostic-format json src/app/main.lani
laniusc --diagnostic-format lsp-json check src/app/main.lani
```

For human explanation of a stable compiler diagnostic:

```bash
laniusc diagnostics explain LNC0017
```

Use [Diagnostics](../DIAGNOSTICS.md) and the generated
[diagnostic code index](../diagnostics/generated/error-index.md) for payload
shape, source-label policy, code metadata, unsupported-feature boundaries, and
no-run metadata commands.

Formatting is a lexical operation:

```bash
laniusc fmt src/app/main.lani
laniusc fmt --check src/app/main.lani
laniusc fmt --stdin < src/app/main.lani
```

It does not type-check, run target codegen, or create a GPU device.

## What Not To Infer

Do not infer these claims from the examples above:

- `import "path/file.lani";` is supported.
- Package names become module names.
- Stdlib modules are auto-imported.
- A type-checking generic helper also lowers on every backend.
- A smoke fixture is benchmark or production-readiness evidence.
- The grammar accepting a shape means every target can compile it.

When an example needs to become evidence, add or update the row in
`docs/language_slice_unstable_alpha.tsv`, name the exact command or test that
proves it, regenerate the generated slice reference, and keep the example small.
