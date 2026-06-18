# API Docs And Rustdoc

This chapter documents the item-level API documentation layer for compiler
authors. Use it when adding or changing public, crate-public, or scoped-public
Rust items in `crates/laniusc-compiler/src`, and when deciding whether a fact
belongs in Rustdoc, generated reference output, or a narrative guide chapter.

Rustdoc is the local equivalent of rustc's generated internal API docs. It is
not a replacement for the compiler guide. The guide explains ownership,
invariants, and workflows; Rustdoc explains the callable item in front of the
reader.

## Layer Contract

Use each documentation layer for a different kind of fact:

| Layer | Owns |
| --- | --- |
| Rustdoc | Item-level signatures, local contracts, visibility reason, lifetime assumptions, failure behavior, and small examples when useful. |
| Generated compiler reference | Volatile inventories: public operation names, Rustdoc coverage, shader load sites, pass loaders, record sites, buffer carriers, large structs, and status layouts. |
| Narrative guide chapters | Phase ownership, data flow, algorithms, authoring workflows, diagnostics policy, and cross-phase invariants. |
| Tests and benchmarks | Executable proof for behavior, diagnostics, capacity, and performance claims. |

Do not copy a generated table into Rustdoc. Do not hide an ownership invariant
only in Rustdoc when it affects multiple phases. Do not leave a public item with
only a signature-level comment when a caller needs to know which phase,
resident lifetime, or failure boundary it belongs to.

## Building The API View

Build the API documentation with:

```bash
cargo doc -p laniusc-compiler --no-deps --document-private-items
```

Use this when:

- adding public or crate-public APIs
- adding intra-doc links or examples that need rustdoc rendering
- changing module-level documentation
- reviewing whether item-level comments expose the right ownership boundary

For docs-only changes under `docs/compiler`, this command is usually not needed.
Use markdown/link checks and the generated-reference check instead.

## Generated Coverage

The generated compiler reference includes a Rustdoc coverage section. In the
current tree it reports:

| Item | Count |
| --- | --- |
| Rustdoc-visible Rust items | `3525` |
| Undocumented Rustdoc-visible Rust items | `0` |
| Undocumented public compiler functions | `0` |

Those numbers come from `tools/compiler_inventory.py`. The extractor scans Rust
files under `crates/laniusc-compiler/src`, skips `src/bin`, and tracks items
matching public, crate-public, or scoped-public declarations for:

- `struct`
- `enum`
- `trait`
- `fn`
- `mod`
- `type`
- `const`
- `static`

An item is counted as documented when the nearest meaningful preceding line is
`///` or `/** ... */`, ignoring blank lines and attributes. The coverage table
is intentionally heuristic. If it misses a real public API pattern, update the
inventory tool instead of treating stale output as acceptable.

The generated reference is freshness evidence. It does not prove that comments
are useful. Reviewers still need to read the Rustdoc on changed items and ask
whether it explains the item-level contract.

## What Good Rustdoc Says

Good compiler Rustdoc answers the question a caller has at the item boundary:

- what owns this data or operation
- which phase or public API family it belongs to
- whether it is user-facing, maintainer-facing, test-only, generated, or a
  low-level infrastructure helper
- what resident buffer, source-pack, artifact, table, or status lifetime it
  assumes
- what failure class or diagnostic behavior callers should expect
- whether the item is a narrow helper for a larger narrative guide chapter

For example, `GpuCompiler` Rustdoc should name that it owns phase drivers and
resident caches tied to one `GpuDevice`, and that public methods serialize
resident pipeline use because buffers are reused across operations. That is
the item-level contract. The full phase sequencing belongs in
[Compiler orchestration](compiler-orchestration.md).

`PrecomputedParseTables` Rustdoc should describe the table family and binary
format at item level. The grammar authoring and generated-table workflow belong
in [Grammar and generated tables](grammar-and-tables.md).

## What Rustdoc Should Not Do

Avoid comments that only restate the signature:

```rust
/// Returns the GPU.
pub fn gpu(&self) -> &GpuDevice
```

Prefer the contract:

```rust
/// Return the GPU device used by this compiler and all resident phase drivers.
pub fn gpu(&self) -> &GpuDevice
```

Avoid putting cross-phase policy only in Rustdoc:

- A buffer lifetime rule that affects parser, type checking, and backends
  belongs in the relevant guide chapter.
- A generated table format belongs in the generated-table chapter.
- A public operation family belongs in the public API chapter.
- A diagnostic mapping rule belongs in the diagnostics chapter.

Rustdoc can point at those chapters by name, but it should not be the only place
where a maintainer can discover a multi-phase invariant.

## Visibility And Ownership

Visibility is part of the contract:

| Visibility | Documentation expectation |
| --- | --- |
| `pub` | Explain the external or cross-module caller contract. |
| `pub(crate)` | Explain the crate-wide ownership boundary and why crate-wide access is needed. |
| `pub(super)` or `pub(in ...)` | Explain the narrow neighbor boundary, especially for resident buffers, bind groups, generated tables, and source-pack stores. |
| private helper | Use normal comments when needed; promote to Rustdoc if it becomes an ownership boundary or appears in generated/API docs. |

Do not widen visibility to make a nearby call compile without documenting the
new boundary. If no real caller should depend on the item, keep it private and
move the code to the owner that needs it.

## Module Documentation

Module-level `//!` comments should orient a reader before they open individual
items. They are most useful at ownership boundaries:

- crate root
- phase roots such as `lexer`, `parser`, `type_checker`, `codegen`, and `gpu`
- public API modules
- generated-table or persisted-format modules
- modules with many related buffer carrier structs or pass wrappers

A module comment should say what the module owns and what it does not own. It
should not become a second source tour. Link or route to the narrative chapter
when the module has a broader maintainer workflow.

## Public API Changes

When changing a public compiler API:

1. Add or update Rustdoc on the public item and any new visible helper types.
2. Name the operation family: global convenience, explicit `GpuCompiler` method,
   input loading, planning, execution, descriptor worker, or benchmark.
3. Document whether the function only plans, mutates persisted progress,
   executes compiler work, or emits target bytes.
4. Document source identity and target identity when either affects diagnostics
   or artifacts.
5. Regenerate or check `docs/compiler/generated/reference.md`.
6. Run `cargo doc -p laniusc-compiler --no-deps --document-private-items` when
   changing rendered Rustdoc structure, module docs, intra-doc links, or
   examples.
7. Add focused behavior tests at the owning API family when behavior changed.

Do not add old public names as compatibility aliases unless another human
maintainer needs that compatibility and there is a documented removal condition.
Otherwise the API docs become false evidence that both surfaces still matter.

## Evidence

Use this evidence ladder for API documentation work:

| Change | Evidence |
| --- | --- |
| Docs-only edit under `docs/compiler` | Generated-reference check, markdown link/anchor check, ASCII check, trailing-whitespace check. |
| Rustdoc comment edit only | `cargo fmt --check` for touched Rust files; generated-reference check if coverage or public item locations changed. |
| New public or crate-public item | Generated-reference check, Rustdoc coverage review, and focused behavior test if behavior changed. |
| Module-level Rustdoc or intra-doc links | `cargo doc -p laniusc-compiler --no-deps --document-private-items`. |
| Public API behavior change | Public API evidence from [Public compiler API](public-api.md), plus generated-reference freshness. |

The generated coverage table can prove that every tracked visible item has a
comment. It cannot prove that the comments are good. Treat weak comments as
documentation bugs even when the coverage count is `100.0%`.

## Update Rule

Update this chapter when any of the following changes:

- the Rustdoc command or package layout
- generated-reference Rustdoc coverage extraction
- public API visibility conventions
- item-level documentation expectations
- evidence required for Rustdoc or API documentation changes
