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

- `import core::name;` and quoted source includes have GPU syntax metadata
  coverage only. They are not loaded, expanded, or resolved, and GPU type
  checking rejects import items until a resolver exists.
- Type aliases are not expanded before GPU type checking.
- Generic enum, generic struct, trait, impl, `match`, and `for` conveniences no
  longer get CPU HIR precheck or erasure before reaching GPU stages.
- Generic function calls no longer get hidden substitution before reaching GPU
  type checking. Full monomorphization and backend specialization are separate
  future work.
- Option/Result/Ordering scalar lowering for codegen is gone until implemented
  on the GPU path.

This is intentional. A feature should not be counted as supported unless the GPU
compiler path accepts it directly or a GPU-side transform implements it.

## Still Usable

- Direct single-file GPU lexing, parsing, type checking, and narrow WASM codegen.
- GPU lexer source-file metadata for single-source and explicit source-pack
  lexer inputs. The source-pack path accepts already-supplied source strings,
  uploads file-span metadata, resets the DFA at GPU-visible file starts, clamps
  token starts to the containing file after skipped trivia, and writes
  per-token `token_file_id` on GPU. The GPU syntax checker consumes that
  sideband metadata, rejects invalid token ownership, and validates leading
  `module`/`import` metadata per file. The normal compiler now records LL(1) HIR
  construction for single-source inputs and for the explicit source-pack
  type-check entrypoint. That path receives the lexer-produced `token_file_id`
  sideband, validates it during GPU syntax checking, and feeds it into LL(1) HIR
  ownership metadata. Already-supplied multi-file source packs can flow through
  the resident GPU parser and type checker when those files contain independent
  module metadata and supported declarations. The type checker suppresses
  module/import headers through parser-owned HIR item spans rather than
  token-neighborhood discovery. The older direct-HIR helper still carries the
  same sideband into `hir_token_file_id`, but it is not the semantic path to
  extend. This still does not load imports, resolve modules, make declarations
  visible across files, or make the normal compiler path a package compiler.
- One leading `module path;` source header as GPU-only metadata. It does not
  load files, resolve imports, or create cross-file namespaces. The module
  header enables a narrow same-source qualified type-path slice for function
  signatures, parameter use, and returns, such as `app::main::Point`, when the
  prefix matches the leading module declaration and `Point` is a struct or enum
  declared in the same source. This is implemented by a GPU precheck plus a
  post-scope `visible_type` patch pass. GPU syntax now admits call-shaped
  qualified value paths as HIR evidence, and GPU type checking resolves the
  bounded same-source function-call slice, such as `app::helper()` or
  `app::main::helper()`, when the prefix matches the leading module declaration
  and the function is declared in the same source. It does not resolve imports,
  external modules, qualified constants, or general qualified value paths.
- GPU parser/syntax coverage for leading `import path;` and `import "path";`
  metadata. GPU type checking now has a bounded path-import resolver for
  already-uploaded source packs: `import core::math;` resolves to a matching
  GPU module record when that module is present in the same source pack,
  unresolved path imports reject, string imports still reject, and duplicate
  module paths reject.
- A GPU-only module/import metadata slice records leading module/import HIR item
  kind, path token span, path hash, import target kind, and enclosing module
  token into resident type-checker buffers. The split declaration metadata pass
  records sparse top-level declaration records keyed by declaration name token:
  item kind, name hash, name length, namespace, visibility, file id, and source
  HIR node. Collection is driven by
  parser-owned `hir_item_kind`, `hir_item_path_start`, `hir_item_path_end`, and
  `hir_item_file_id` metadata plus parser-owned declaration fields. Import
  path-vs-string target classification is also parser-owned metadata derived
  from the import-tail production, not a token-kind peek in the type checker.
  A GPU path-import resolver consumes those sparse module/import records and
  writes `import_resolved_module_token`; this does not yet make declarations
  visible across files.
- The LL(1) parser tree path now emits parser-owned HIR item-field metadata for
  top-level module/import and declaration items using production ids and
  parent/grandparent ancestry. It records item kind, name or path token span,
  namespace, visibility, and file id, and deliberately excludes impl-method
  `fn_item` nodes from top-level function declarations. This metadata now feeds
  the sparse module/import metadata collector, but is not yet a dense
  declaration table or resolver.
- Simple generic function-call substitution for direct calls whose type
  parameters can be inferred from arguments, including generic forwarding from
  one generic function to another. Full monomorphization and backend
  specialization remain separate later requirements.
- GPU parser table coverage for the grammar fixtures in `tests/parser_tree.rs`.
- GPU parser coverage for generic item `where`-clause syntax, with predicates
  such as `where T: core::cmp::Eq<T> + core::hash::Hash<T>`.
- GPU parser/syntax coverage for trailing commas in stdlib-shaped lists:
  function arguments, array literals, match arms, pattern lists, enum variants,
  enum payload fields, generic type arguments/parameters, struct fields, and
  struct literals.
- GPU parser/syntax coverage for method receiver spellings `self`,
  `self: Type`, and `&self`.
- GPU type-check coverage for `self`, `self: Type`, and `&self` receiver
  parameters with direct `self.field` access inside impl method bodies.
- Existing `.lani` stdlib seed files as design/source artifacts. Bounded
  single-file GPU type-check acceptance is covered for the primitive helper
  seeds in `stdlib/bool.lani`, `stdlib/i32.lani`, `core::bool`,
  `core::char`, `core::f32`, `core::i32`, `core::i64`, `core::ordering`,
  `core::panic`, `core::target`, `core::u8`, `core::u32`, and
  `test::assert`; for the limited const-generic `core::array_i32` seed; and
  for raw extern declaration seeds under `alloc::allocator` and `std::*`.
  This does not imply imports, qualified value lookup, runtime services, or
  backend lowering.
- Direct WASM codegen for the currently supported top-level statement subset.
  This does not make module-form primitive helper seeds executable; helper
  execution still needs GPU module/value-path resolution plus function-body
  lowering.

## Strict Blockers For A Real Stdlib

- GPU module/import expansion or a real package model.
  The explicit GPU lexer source-pack path can upload multiple already-supplied
  source strings and keep their tokens file-local, but the current compiler
  still does not discover files from imports, build dense module/import tables,
  or resolve cross-file paths.
  `tests/parser_tree.rs` currently accepts one leading `module path;` metadata
  header followed by leading import metadata, and has fast-failing GPU syntax
  rejection tests for non-leading imports, duplicate module declarations, and
  non-leading module declarations so they cannot be silently ignored by the
  normal compile path.
  `tests/type_checker_modules.rs` still rejects import items and covers only
  same-source qualified type paths for signatures, parameter use, returns, and
  local annotations, plus same-source qualified function calls whose prefix
  matches the leading module declaration; external qualified type paths such as
  `core::option::Option<i32>` and external qualified calls still fail until real
  module/source-pack lookup exists.
  The first module/import metadata pass exists only as GPU-resident sparse
  records; it does not build dense module tables, resolve import targets, patch
  import visibility, or enable external qualified value calls.
  `tests/parser_tree.rs` keeps non-call qualified value paths rejected in GPU
  syntax, and `tests/type_checker_modules.rs` keeps imports, unresolved module
  prefixes, external qualified calls, and missing qualified callees rejected in
  GPU type checking so this bounded slice cannot be mistaken for full module
  value resolution.
- GPU type-alias handling.
  `tests/parser_tree.rs` currently has a fast-failing GPU syntax rejection test
  for type-alias declarations so this gap cannot be mistaken for working
  semantic support.
- GPU backend lowering for primitive helper modules.
  Parser and type-check coverage for `stdlib/core/*.lani` seeds is not execution
  coverage. The default WASM backend does not wire the stalled function-module
  shader path, does not lower from HIR/type metadata, and cannot compile
  `core::i32::abs`, `core::bool::not`, or `test::assert::eq_i32` as qualified
  helper calls. The first executable slice should be GPU source-pack resolution
  plus HIR-driven WASM lowering for no-loop scalar helpers: constants,
  parameters, returns, local lets, unary/binary arithmetic, comparisons, boolean
  operators, `if`/`else`, and direct calls. `while` helpers, assertions/panic,
  arrays, slices, generics, traits, allocation, and host APIs remain rejected
  until their GPU lowering/runtime exists.
- GPU semantic support for structs, enums, generics, traits, impls, and `match`
  without CPU precheck/erasure.
  `tests/type_checker_semantics.rs` currently has a fast-failing rejection test
  for trait declarations, trait impl declarations, and `match` expressions so
  these gaps cannot be mistaken for working trait or pattern-matching support.
  `tests/type_checker_modules.rs` also keeps the full `core::cmp`,
  `core::hash`, `core::option`, and `core::result` seed files rejected while
  they depend on those unsupported semantics. Bounded generic enum constructor
  payload substitution now works for annotated concrete local contexts such as
  `let value: Maybe<i32> = Some(1)` and `Result<i32, bool>` constructors, but
  symbolic generic enum returns, `match`, imports/external paths, enum layout,
  and backend lowering remain unsupported. The full `core::range` seed now
  type-checks as a direct single-file GPU input, and concrete inherent method
  calls type-check for direct single-file receivers, but backend lowering
  remains unsupported.
  `for` loops have GPU type-check coverage for iterator-scope shape, but still
  need backend lowering before they are executable stdlib infrastructure.
- GPU semantic support for generic array and slice element types such as
  `[T; N]` and `[T]`.
  A bounded GPU-only slice now accepts parameter and struct-field declarations
  such as `fn first<T, const N: usize>(values: [T; N]) -> T { return values[0]; }`,
  `fn first_slice<T>(values: [T]) -> T`, and `ArrayVec<T, const N: usize>` when
  `T`/`N` resolve to the owning type/const generic parameters. The dedicated
  `type_check_type_instances_07_array_index_results.slang` pass consumes
  precomputed array/slice element refs and publishes indexed element result
  types for the token checker. Generic array/slice calls, generic array
  returns, local generic array annotations, array literal returns, call returns,
  broader length unification, slice ABI, and backend lowering remain rejected.
- GPU semantic substitution for generic struct literals and generic field
  projection.
  The metadata passes now record named generic instance candidates, bind them to
  declarations, publish argument refs, and precompute substituted struct
  field/member refs on GPU. `Range<i32>` construction, `range.start`
  projection, and the full `core::range` seed have GPU type-check coverage for
  the direct single-file frontend path. Full monomorphization and backend
  specialization remain separate work.
- GPU semantic use of generic parameter bounds and `where` predicates for trait
  solving and method lookup.
  `tests/type_checker_semantics.rs` currently has a fast-failing rejection test
  for generic bounds and `where` clauses so parser coverage cannot be mistaken
  for working predicate semantics.
- GPU semantic support for full method calls and method lookup.
  The first GPU-only method metadata slice records method declaration receiver
  types, impl tokens, name tokens, parameter offsets, and lookup-table entries
  from `impl` bodies. A bounded GPU resolver now consumes that metadata for
  concrete inherent calls on direct single-file receivers and validates simple
  value arguments. Trait dispatch, generic methods, method visibility across
  modules, imported methods, and backend lowering remain blocked.
- GPU semantic support for array-returning function signatures and return
  values. A bounded GPU-only consumer now accepts concrete identifier returns
  for matching `[i32; literal]` signatures, such as returning a parameter or
  annotated local with the same concrete length. This is implemented by
  `type_check_type_instances_05_array_return_refs.slang`, which compares
  precomputed type-instance element/length records and writes a return-token
  sentinel consumed by `type_check_tokens_min.slang`; it does not reparse type
  spans in the hot token checker. Array literal returns, generic `[T; N]`
  returns, call returns, and mismatched concrete lengths remain rejected until
  GPU generic element substitution and full array identity semantics exist.
  `tests/type_checker_modules.rs` keeps the flat and module-form
  `array_i32_4` seed files rejected so their copy/fill/reverse helpers cannot
  be mistaken for accepted array-return semantics.
- Real reference/borrow semantics for `&self`; it currently type-checks direct
  field access as a receiver form, not as a general reference model.
  `tests/parser_tree.rs` currently has a fast-failing GPU syntax rejection test
  for ordinary `&T` and `&value` references so receiver syntax cannot be
  mistaken for general borrowing.
- GPU lowering for Option, Result, Ordering, arrays, slices, function bodies,
  extern calls, and host ABI declarations.
- A target/runtime model for allocator, I/O, filesystem, process, time, and
  networking APIs.

## Prompt-To-Artifact Checklist

This is the working checklist for the current objective: build the language
features strictly necessary for the desired `stdlib/PLAN.md`, while keeping the
compiler GPU-only.

| Stdlib requirement | Required compiler/runtime artifact | Current evidence | Status |
| --- | --- | --- | --- |
| Source files in modules | GPU-compatible module/import resolution, visibility, and path lookup | `module path;` is accepted only as leading GPU metadata; leading `import path;` and `import "path";` have GPU syntax metadata coverage and a GPU-resident metadata pass records sparse module/import records; a bounded GPU path-import resolver now resolves already-uploaded path imports to matching module records and rejects unresolved imports, string imports, and duplicate module paths; same-source qualified type paths work for signatures, parameter use, returns, and local let annotations; same-source qualified function calls such as `app::helper()` work when the prefix matches the leading module declaration and the callee is declared in the same source; dense module/import tables, cross-file declaration visibility, non-leading modules, non-leading imports, external qualified type paths, external qualified calls, qualified constants, and general qualified value paths remain rejected | Blocked |
| Primitive helper modules | GPU parser/type checker plus GPU module/value-path resolution and HIR-driven function-body codegen for scalar helpers | Parser/type-check evidence exists for primitive helpers and consts, including `stdlib/bool.lani`, `stdlib/i32.lani`, `core::bool`, `core::char`, `core::f32`, `core::i32`, `core::i64`, `core::ordering`, `core::panic`, `core::target`, `core::u8`, `core::u32`, and `test::assert` seed files. Backend execution is blocked: default WASM codegen is top-level-statement only, qualified helper calls are not lowered, `test::assert` has no runtime lowering, and x86_64 reports unavailable | Partial for frontend; blocked for execution |
| `Option`, `Result`, `Ordering` | GPU enum semantics, match exhaustiveness, enum layout/lowering | Parser coverage plus concrete GPU constructor payload type/arity checks; bounded contextual generic enum constructor checks now accept annotated concrete locals such as `Maybe<i32> = Some(1)` and `Result<i32, bool> = Ok(1)`/`Err(false)` on GPU. `core::ordering` type-checks as a concrete seed, while full `core::option` and `core::result` seed files remain rejected because they still depend on `match`, symbolic generic returns, module/import resolution, enum layout, and backend lowering | Blocked for codegen |
| Generic function calls | Simple GPU call substitution for callee type parameters, with full monomorphization/backend specialization as separate later work | `keep(7)`, `keep(true)`, nested direct calls such as `keep(keep(7))`, and generic forwarding from one generic function into another have GPU type-check tests; conflicting repeated generic arguments are rejected | Partial |
| Generic arrays and slices | Const generics, generic element types, slice metadata representation, GPU type-instance records | Limited `[i32; N]` and `[i32]` type-check tests; `core::array_i32` type-checks as a single-file seed; `type_check_type_instances_01_collect.slang` records array/slice element and length refs on GPU, `type_check_type_instances_07_array_index_results.slang` publishes bounded generic `values[0]` element result types for parameter/struct-field declarations, and `type_check_type_instances_05_array_return_refs.slang` accepts concrete identifier returns for matching `[i32; literal]` signatures. Flat and module-form `[i32; 4]` seeds remain rejected because `fill`/`reverse` need array literal and loop lowering; generic array/slice calls, generic array returns, local generic array annotations, call returns, array literal returns, and mismatched concrete lengths remain rejected | Partial |
| Traits/interfaces | Trait bounds, impl conformance, method lookup, dictionaries or static dispatch | Parser coverage for trait/impl/where and receiver syntax; direct `self.field` access type-checks for `self`, `self: Type`, and `&self` in impl bodies | Blocked |
| `String` and `Vec` | Heap allocation, ownership model, pointer/slice/string ABI | Allocator ABI seeds only | Blocked |
| Maps, sets, heaps, trees | Generics, allocation, traits, ordering/hashing, loops | No complete prerequisites | Blocked |
| Formatting/parsing | Strings, writers/builders, integer/float formatting, error types | No string/runtime representation | Blocked |
| `std` host APIs | Target capability model, ABI, native linking/x86 codegen | Raw extern ABI declaration seed files type-check as single-file inputs, but there is no import resolution, host runtime, capability model, native linking, or executable backend support | Blocked |
| Test framework | Assertions, panic reporting, source locations, harness | `assert(bool)` path and seeds only | Partial |
| Native output | GPU register allocation and x86_64 binary emission wired into compiler | `src/codegen/gpu_x86.rs` exists but compiler reports unavailable | Blocked |

Any row marked partial or blocked is not done for the objective.

## Detailed GPU Implementation Plans

The broad blocker rows above now have focused implementation plans:

- `docs/MODULE_RESOLUTION_GPU_PLAN.md` covers source packs, module/import
  records, qualified type paths, qualified value paths, declaration lookup, and
  the first GPU-only module-resolution slice.
- `docs/GENERICS_GPU_PLAN.md` covers simple generic function-call substitution,
  the first GPU-resident type-instance metadata pass, the next consumers for
  generic structs/enums/arrays, then bounds/where predicates.
- `docs/X86_64_GPU_BACKEND_PLAN.md` covers direct GPU x86_64 ELF emission,
  including HIR-driven lowering, register allocation, instruction sizing,
  relocation patching, ELF writing, and final packed binary bytes.

An attempted direct acceptance of `type` aliases in the normal syntax path made
GPU type checking time out even before alias lookup was enabled. Until alias
declarations have a bounded GPU HIR/type-check path, `type` aliases must keep
fast-failing in GPU syntax rather than becoming another misleading accepted
surface.

## Acceptance Rules

A stdlib feature is not complete unless it has:

- Parser coverage through the GPU parser path.
- Type-check coverage through the GPU type checker path.
- Backend coverage when codegen is part of the claim.
- Documentation that does not imply CPU fallback or CPU prepass support.
- Failure tests for unsupported target/runtime behavior.
