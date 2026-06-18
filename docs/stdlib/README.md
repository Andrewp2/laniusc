# Standard Library Overview

This chapter is the user-facing overview for the current Lanius source standard
library. It explains how stdlib source is loaded, which module families exist,
which parts are frontend/type-check contracts, and which parts are runtime-bound
metadata rather than executable host services.

For the generated declaration inventory, use
[Generated Standard Library Reference](generated/reference.md). For source-tree
maintainer notes, use the [stdlib source README](../../stdlib/README.md). For
desired future stdlib scope, use [STANDARD_LIBRARY_SPEC](../../stdlib/STANDARD_LIBRARY_SPEC.md),
[PLAN](../../stdlib/PLAN.md), and
[LANGUAGE_REQUIREMENTS](../../stdlib/LANGUAGE_REQUIREMENTS.md).

## Current Boundary

The standard library is ordinary `.lani` source under `stdlib/`. It is not
implicitly preloaded, and importing a stdlib module requires an explicit
stdlib root through the CLI or package metadata.

```bash
laniusc check --source-root src --stdlib-root stdlib src/app/main.lani
```

The current stdlib is an `unstable-alpha` source-level surface. A module can be
known to the compiler, type-check through `--stdlib-root`, and appear in the
generated reference without being executable on every backend.

Use these terms narrowly:

| Term | Meaning |
| --- | --- |
| source-level module | A `.lani` file with a module declaration that can be loaded as source. |
| frontend evidence | The parser/type-checker can accept the explicitly supplied or loaded source shape. |
| runtime-bound API | A known stdlib API whose execution requires a future runtime service or linker binding. |
| executable evidence | A generated slice row names target-specific execution evidence for the shape. |

Frontend evidence is not executable evidence. A helper that type-checks through
`--stdlib-root` should still be treated as non-executable until the generated
language slice names backend execution evidence for that exact kind of shape.

## Module Families

The generated reference owns the exact module list and declaration counts. Read
the summary and module index there when exact names matter.

Current source families:

| Family | Examples | Current role |
| --- | --- | --- |
| `core` scalar helpers | `core::i32`, `core::u32`, `core::u8`, `core::i64`, `core::f32`, `core::bool`, `core::char` | Source-level primitive helper modules and constants. Mostly frontend/type-check evidence. |
| `core` generic/value helpers | `core::option`, `core::result`, `core::ordering`, `core::range`, `core::slice`, `core::mem`, `core::cmp`, `core::hash` | Source-level types and helpers for bounded generic, enum, range, memory-contract, comparison, and hash shapes. |
| Runtime metadata | `core::runtime`, `core::target` | Source-level constants and predicates that describe target/runtime capability boundaries. |
| `std::path` | `std::path` | No-host lexical byte/path helper contracts. Some narrow helper execution can have target-specific evidence; broad path buffers and host normalization remain unsupported. |
| Runtime-bound `std` services | `std::io`, `std::fs`, `std::env`, `std::time`, `std::process`, `std::net`, `std::gpu`, `std::thread`, `std::random`, `std::vec`, `std::host` | Known service/API contracts and probes. These are not executable host services today. |
| `alloc` | `alloc::allocator` | Allocator service metadata and known-unbound allocator API declarations. |
| `test` | `test::assert`, `test::harness` | Source-level assertion and harness contracts. Harness/runtime execution is not implemented. |
| legacy flat files | `stdlib/i32.lani`, `stdlib/bool.lani`, `stdlib/array_i32_4.lani` | Compatibility source seeds kept as plain files; prefer module-form imports for new examples. |

Generated inventory:

```bash
tools/stdlib_inventory.py --output docs/stdlib/generated/reference.md
tools/stdlib_inventory.py --check docs/stdlib/generated/reference.md
```

Do not edit the generated reference by hand.

## Loading Rules

A stdlib import is a normal module-path import:

```lanius
module app::main;

import core::i32;

fn main() {
    let magnitude: i32 = core::i32::abs(-7);
    print(magnitude);
    return 0;
}
```

Check it with an explicit stdlib root:

```bash
laniusc check --source-root src --stdlib-root stdlib src/app/main.lani
```

Important loading rules:

- stdlib modules are not auto-imported
- `--stdlib-root` supplies stdlib files by module-path convention
- semantic module identity still comes from parsed `module path;` declarations
- package names and directory names do not become module names
- quoted imports remain unsupported for durable stdlib loading
- broad package discovery is not a full package manager

Use [Modules, Imports, And Packages](../language/modules-and-imports.md) for the
full source-root, stdlib-root, package-manifest, and lockfile rules.

## Frontend Examples

Use `check` for stdlib examples unless a generated language-slice row names
target execution evidence for the exact shape.

Primitive helper:

```lanius
module app::main;

import core::i32;

fn main() {
    let value: i32 = core::i32::saturating_abs(-7);
    print(value);
    return 0;
}
```

Option helper:

```lanius
module app::main;

import core::option;

fn main() {
    let value: core::option::Option<i32> = core::option::Some(4);
    print(core::option::unwrap_or(value, 0));
    return 0;
}
```

Check either shape with:

```bash
laniusc check --source-root src --stdlib-root stdlib src/app/main.lani
```

The maintained sample
[sample_programs/option_result_helpers.lani](../../sample_programs/option_result_helpers.lani)
is useful for reading qualified generic types, enum constructors, and
`core::option` / `core::result` helper calls together. It is still a
documentation-smoke fixture unless promoted by a behavior-facing test or
generated language-slice row.

## Runtime-Bound APIs

Runtime-bound APIs are known contracts for future host/runtime services. They
can be queryable and type-checkable while remaining non-executable.

Use no-run metadata commands to inspect the current runtime boundary:

```bash
laniusc diagnostics runtime-apis
laniusc diagnostics runtime-api std::io::print_i32
laniusc diagnostics runtime-services
laniusc diagnostics runtime-service std::io
laniusc diagnostics runtime-service-apis std::io
```

Those commands do not compile source, scan stdlib files, create a GPU device, or
prove that a runtime service is linked. Unknown selectors are metadata lookups,
not source-loading failures.

Examples of runtime-bound areas:

- stdio input/output
- filesystem operations
- environment variables
- time and clocks
- process APIs
- networking
- secure random number generation
- GPU host services
- threading
- vector allocation and allocator services
- panic hooks and test harness runtime behavior

Do not call a runtime-bound API in a native execution example unless the
generated language slice names target-specific execution evidence for that API.

## Execution Boundary

The current executable target surface is narrower than the source-level stdlib
surface.

`x86_64` has bounded execution evidence for selected scalar/control-flow,
direct-call, source-pack helper, array/aggregate, method, and diagnostic
fail-closed cases. Some stdlib helper shapes have focused target evidence, but
most source-level helpers remain frontend contracts only.

`wasm` is currently an accepted selector with a fail-closed backend boundary.
Do not treat stdlib source that type-checks as executable Wasm evidence.

Use:

- [Targets And Output](../targets.md) for target/output rules
- [Language slice inventory](../language/generated/unstable-alpha-slice.md) for
  exact target evidence rows
- [Codegen and backends](../compiler/codegen.md) for maintainer-facing backend
  internals

## What Not To Infer

Do not infer these claims from the stdlib source or generated reference:

- stdlib modules are implicitly available
- runtime-bound APIs are executable
- every type-checking helper lowers on x86_64
- accepted `wasm` target selection means Wasm stdlib execution works
- generated declaration inventory is production API stability
- legacy flat files are the preferred new import style
- package metadata changes semantic module identity

The generated reference is an inventory of current source declarations. It is
not a stability promise and not an execution matrix.

## Updating Stdlib Docs

When changing stdlib behavior or docs:

1. Update the owning `.lani` source under `stdlib/`.
2. Regenerate or check [Generated Standard Library Reference](generated/reference.md).
3. Update `docs/language_slice_unstable_alpha.tsv` when the change makes or
   removes a public support claim.
4. Regenerate the generated language-slice reference when the TSV changes.
5. Update this overview, source-tree README, examples, and target docs only for
   claims that are actually supported.

For docs-only stdlib changes, run:

```bash
tools/docs_check.py
```
