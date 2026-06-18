# Source-Level Standard Library

This chapter documents the compiler-facing standard-library boundary. The
standard library in this repo is a source-level seed under `stdlib/`, not a
preloaded runtime or stable language edition promise.

Use this chapter when changing `stdlib/*.lani`, stdlib-root loading, package
stdlib metadata, runtime-service descriptor contracts, stdlib tests, or the
claim that a library helper is frontend-only, descriptor-only, or executable.
Use `stdlib/STANDARD_LIBRARY_SPEC.md` for the long-term target inventory and
`stdlib/README.md` for the source tree's own current-state notes.

## Current Contract

The active standard-library contract is explicit:

- stdlib files are ordinary `.lani` source files
- the compiler does not auto-import stdlib modules
- callers load stdlib modules through `--stdlib-root`, package
  `stdlib_root`, or public compiler APIs that name a stdlib root
- leading `module` and `import` declarations provide source metadata
- path imports load by module-path-to-file convention
- quoted imports remain unsupported
- type-check success is usually frontend evidence only
- host-facing `std` APIs do not become executable just because their
  declarations type-check

Do not describe a stdlib helper as supported without naming the evidence class:
source-root loading, type-check acceptance, backend execution, runtime-service
descriptor metadata, or a fail-closed diagnostic.

## Source Map

| Path | Role |
| --- | --- |
| `stdlib/README.md` | Current stdlib implementation notes and active boundary warnings. |
| `stdlib/STANDARD_LIBRARY_SPEC.md` | Desired long-term standard distribution inventory. |
| `stdlib/LANGUAGE_REQUIREMENTS.md` | Compiler features needed before stdlib seeds become normal library code. |
| `stdlib/PLAN.md` | Roadmap notes for growing the stdlib surface. |
| `docs/stdlib/generated/reference.md` | Generated source-level module, import, declaration, and runtime-flag inventory. |
| `stdlib/core/*.lani` | Source-level core helpers, primitive modules, generic sum types, target/runtime descriptor contracts. |
| `stdlib/alloc/*.lani` | Allocation/runtime-service contract seeds. |
| `stdlib/std/*.lani` | Host-service contract seeds and lexical helper modules. |
| `stdlib/test/*.lani` | Test assertion and harness source-level contracts. |
| `stdlib/*.lani` | Legacy flat seed files that keep `lstd_`-prefixed names. |
| `tests/stdlib_*.rs` | Source-level stdlib type-check, runtime-descriptor, and selected execution/fail-closed evidence. |
| `tests/cli_stdlib_root.rs` | CLI validation and structured diagnostics for `--stdlib-root`. |
| `tests/source_pack_package_boundaries.rs` | Source-root and stdlib-root package boundary tests. |

Compiler docs should explain the boundary and evidence. The long-term API wish
list belongs in `stdlib/STANDARD_LIBRARY_SPEC.md`, not in this chapter. Exact
current declaration lists belong in the generated stdlib reference, not in
hand-maintained prose.

## Layout

The source tree mirrors the intended standard-library layers:

| Layer | Current meaning |
| --- | --- |
| `core` | No-heap, no-host source helpers and descriptor constants. |
| `alloc` | Allocation service contracts that currently fail closed without runtime binding. |
| `std` | Host-facing service contracts plus some pure lexical helpers. |
| `test` | Assertion helpers and test-harness service contracts. |
| root flat files | Legacy seed helpers with `lstd_` prefixes for manual or explicit source-pack use. |

Module-form files begin with a module declaration such as `module core::i32;`
or `module std::path;`. Their file path is part of the source-root contract:
`core::i32` maps to `stdlib/core/i32.lani`, and `std::path` maps to
`stdlib/std/path.lani`.

## Loading Paths

The supported loading surfaces are:

| Surface | Meaning |
| --- | --- |
| `--stdlib-root DIR` | Entry source may import stdlib modules from `DIR`. |
| `--source-root USER --stdlib-root STD` | User imports are searched in user roots first, then stdlib fallback where allowed. |
| package manifest `stdlib_root` | Package metadata names the stdlib root for replay/loading. |
| package lockfile `stdlib_root` | Lockfile replay validates the previously resolved stdlib root and source identities. |
| `load_entry_with_stdlib` | Public API loads entry plus stdlib-root imports into an in-memory source pack. |
| `load_entry_path_manifest_with_stdlib` | Public API returns the path manifest that would be loaded. |
| `type_check_entry_with_stdlib` | Public API loads and type-checks entry plus stdlib-root imports. |
| target-specific `compile_entry_to_*_with_stdlib` | Public API loads stdlib-root imports before backend compilation. |

Root loading feeds discovered files into the GPU source-pack resolver. It does
not rewrite source, expand imports, decide declaration visibility on the host,
or make source-root mode a full package compiler.

## Import Resolution Boundary

`--stdlib-root` uses the same module-path metadata path as source roots:

1. lexer/parser accept leading `module` and `import` declarations as metadata
2. source-root loaders map path imports to `.lani` files by convention
3. the loaded source files become one explicit source pack
4. GPU parser/type-check records establish semantic module identity,
   declarations, visibility, and qualified paths

The source-root loader rejects filesystem problems before GPU work when it can
name the problem precisely. Examples include missing stdlib modules, roots that
are not directories, explicit `--stdlib` sources mixed with root mode, duplicate
canonical roots, same canonical file crossing user/stdlib boundaries, symlink
escapes, quoted imports, glob imports, aliases, malformed import paths, and
reserved path segments.

Do not add host-side semantic shortcuts for stdlib modules. If a module path
matters semantically, publish it through parser/type-check records.

## User And Stdlib Boundary

User/package roots and stdlib roots are separate libraries in the source-pack
model. The boundary matters:

- stdlib files must not depend on user/package roots
- user/package imports may fall back to stdlib roots when no user module wins
- imports discovered from stdlib files must resolve inside the stdlib root
- same canonical file cannot appear through both user and stdlib roots
- overlapping package roots and stdlib roots are rejected
- lockfile replay rejects stale source identities and import graph evidence

This prevents stdlib fallback from masking package modules or allowing a stdlib
module to accidentally bind to application code.

## Current Core Seeds

Current `core` modules are source-level seeds. Important families include:

| Module | Current role |
| --- | --- |
| `core::bool` | Boolean combinators, equality, and selection helpers. |
| `core::i32`, `core::i64`, `core::u32`, `core::u8` | Numeric constants, classification, range, checked/saturating/wrapping helper seeds. |
| `core::f32` | Small scalar floating-point predicate and range helper seed. |
| `core::char` | ASCII classification and ASCII case-insensitive equality helpers. |
| `core::option`, `core::result` | Generic sum type seeds and bounded helper families. |
| `core::ordering` | `Ordering` enum and integer comparison helper seeds. |
| `core::range` | Range overlap/containment helper seeds. |
| `core::array_i32_4`, `core::array_i32`, `core::slice` | Fixed and early generic array/slice helper seeds. |
| `core::mem` | No-runtime generic value helpers and raw-memory contract probes. |
| `core::target` | Conservative target capability constants and helpers. |
| `core::runtime` | Runtime ABI and service descriptor constants plus fail-closed predicates. |
| `core::panic`, `core::cmp`, `core::hash` | Panic hook and trait/predicate-oriented source seeds. |

Unless a focused backend test says otherwise, these are frontend/type-check
contracts. A helper can type-check through `--stdlib-root` without implying
native, WASM, allocation, layout, or host-service execution.

## Host And Runtime Seeds

`alloc`, `std`, and `test` modules are mostly runtime-service contracts today.
They expose source-level metadata that lets programs and descriptors talk about
services without pretending the service exists.

Current service families include:

| Module | Service boundary |
| --- | --- |
| `alloc::allocator` | Allocator service contract and fail-closed pointer/result helpers. |
| `std::io` | Stdio service contract and operation result helpers. |
| `std::fs` | Filesystem service contract, path mutation gates, file handle/result helpers. |
| `std::time` | Clock service contract and time/sleep result helpers. |
| `std::net` | Network service contract and socket/listener result helpers. |
| `std::process` | Process service contract and exit/argument result helpers. |
| `std::env` | Environment service contract and read result helpers. |
| `std::random` | Secure RNG service contract and fail-closed operation helpers. |
| `std::gpu` | Host GPU service contract. |
| `std::thread` | Thread service contract. |
| `std::host` | Aggregate host-service contract. |
| `test::harness` | Test harness service contract. |

These modules usually set `*_HAS_RUNTIME_BINDING` or equivalent availability
constants to false. That false value is a contract, not a TODO marker to
paper over. Runtime-bound APIs must fail closed until linker/runtime support and
descriptor evidence exist.

## `std::path`

`std::path` is a special case: it is currently a lexical helper module, not a
host filesystem API. It exposes byte-level constants and classifiers for path
headers and components. The tests exercise helpers such as ASCII letter checks,
normal relative components, rooted headers, absolute headers, and Windows
component headers through `--stdlib-root`.

Do not route filesystem behavior through `std::path`. Path normalization,
canonicalization, allocation, filesystem inspection, and host path services
belong to later runtime-bound APIs.

## Runtime Descriptor Contract

`core::runtime` defines the source-level runtime ABI descriptor vocabulary:

- metadata and ABI version constants
- service id range and service count
- service requirement row field count and field ordinals
- status values for unknown, unavailable, and available services
- stable service ids for allocator, filesystem, stdio, clock, network,
  panic-hook, aggregate host service, threads, secure RNG, GPU host service,
  process, environment, and test harness
- helper predicates for known, unavailable, contract-only, fail-closed, and
  binding-required states

Rust descriptor code exposes corresponding constants and diagnostics. Tests in
`tests/stdlib_runtime_contract.rs` keep these inventories aligned with
source-pack artifact descriptors and stable diagnostics.

Runtime-bound descriptors are accepted as ABI-pinned contract metadata today.
They do not prove that a service can execute.

## Evidence Classes

Use these evidence labels when documenting or reviewing stdlib changes:

| Evidence class | Meaning |
| --- | --- |
| Source-root loading | The loader finds the module under `--stdlib-root` and includes the expected file in the source-pack manifest. |
| Type-check contract | A focused `tests/stdlib_*.rs` case type-checks a small caller through `type_check_entry_with_stdlib`. |
| Diagnostic contract | CLI/source-root tests prove a missing or invalid stdlib import reports a stable, source-labeled diagnostic. |
| Runtime descriptor contract | Descriptor tests prove service ids, ABI versions, requirement rows, and diagnostics stay aligned. |
| Fail-closed contract | Runtime-bound APIs or unsupported backend paths reject with the expected diagnostic or descriptor failure. |
| Execution contract | A backend test executes generated target bytes or validates target output for the helper. |

Most current stdlib rows are source-root loading, type-check contract, runtime
descriptor contract, or fail-closed contract. Execution contracts are narrow and
must be named specifically.

## Tests

Use the smallest test that matches the claim:

| Change | Evidence |
| --- | --- |
| New pure `core` helper | Focused `tests/stdlib_*.rs` caller that imports the module through `--stdlib-root` and type-checks the helper. |
| New helper with dependencies | Path manifest assertion that all expected stdlib files are loaded, plus type-check test. |
| New missing-import or root validation behavior | `tests/cli_stdlib_root.rs` or source-root boundary tests with stable diagnostic text/code. |
| New user/stdlib package boundary | `tests/source_pack_package_boundaries.rs` or package manifest/lockfile tests. |
| New runtime service id or runtime-bound API | `tests/stdlib_runtime_contract.rs` descriptor, diagnostic, and source-level type-check tests. |
| New executable helper claim | Small backend test proving output or fail-closed behavior at the target boundary. |
| Long-term spec change only | Update `stdlib/STANDARD_LIBRARY_SPEC.md`; do not add compiler docs that imply implementation. |

Do not use one broad `stdlib_runtime_contract.rs` run as the first proof for a
small pure helper. Add or run the focused helper test first.

## Adding A Standard-Library Module

When adding a module:

1. place it under the layer that matches its requirements: `core`, `alloc`,
   `std`, or `test`
2. add a leading `module path;` declaration matching the file path
3. keep imports as leading path imports
4. decide whether the module is pure source, runtime descriptor metadata, or an
   executable helper
5. keep availability constants conservative when runtime support is absent
6. add a focused source-root/type-check test
7. add descriptor/fail-closed tests if the module names runtime services
8. update `stdlib/README.md` and this chapter if the boundary changes
9. update `stdlib/STANDARD_LIBRARY_SPEC.md` only for target-surface decisions

Do not add flat compatibility files for new modules unless another human
maintainer needs them during an active migration. The flat `lstd_` files are
legacy seeds, not the direction for new stdlib work.

## Unsupported Claims

The current stdlib does not imply:

- automatic prelude or auto-imports
- package-manager dependency resolution
- quoted import loading
- hidden CPU import expansion
- host filesystem, process, network, thread, clock, environment, or random
  service execution
- heap allocation
- destructor, borrow, move, or layout semantics
- broad enum/backend lowering
- broad array-valued backend lowering
- Unicode, locale, path normalization, or canonicalization behavior
- stable source compatibility beyond `unstable-alpha`

If a new test makes one of these true for a narrow slice, document that exact
slice and keep the broader unsupported claim in place.
