# Standard Library Language Requirements

This document tracks what the compiler must support before the standard library
can move from source seeds to normal language/library code.

## Current Boundary

The CPU parser, Rust HIR parser, CPU import expander, type-alias expander, and
CPU semantic precheck path have been removed from the normal compiler pipeline.
Source is now handed directly to the GPU lexer, GPU parser, GPU type checker,
and GPU codegen path.

That means several previously documented stdlib conveniences are no longer
available as hidden CPU-prepass features:

- `import core::name;` and quoted source includes are not expanded.
- Type aliases are not expanded before GPU type checking.
- Generic enum, generic struct, trait, impl, `match`, and `for` conveniences no
  longer get CPU HIR precheck or erasure before reaching GPU stages.
- Option/Result/Ordering scalar lowering for codegen is gone until implemented
  on the GPU path.

This is intentional. A feature should not be counted as supported unless the GPU
compiler path accepts it directly or a GPU-side transform implements it.

## Still Usable

- Direct single-file GPU lexing, parsing, type checking, and narrow WASM codegen.
- GPU parser table coverage for the grammar fixtures in `tests/parser_tree.rs`.
- Existing `.lani` stdlib seed files as design/source artifacts.
- Direct WASM codegen for the currently supported top-level statement subset.

## Strict Blockers For A Real Stdlib

- GPU module/import expansion or a real package model.
- GPU type-alias handling.
- GPU semantic support for structs, enums, generics, traits, impls, `match`, and
  `for` without CPU precheck/erasure.
- GPU lowering for Option, Result, Ordering, arrays, slices, function bodies,
  extern calls, and host ABI declarations.
- A target/runtime model for allocator, I/O, filesystem, process, time, and
  networking APIs.

## Acceptance Rules

A stdlib feature is not complete unless it has:

- Parser coverage through the GPU parser path.
- Type-check coverage through the GPU type checker path.
- Backend coverage when codegen is part of the claim.
- Documentation that does not imply CPU fallback or CPU prepass support.
- Failure tests for unsupported target/runtime behavior.
