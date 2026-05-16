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

- `import core::name;` path imports have GPU syntax metadata and resolve only
  against modules that are already present in the explicit source pack. Quoted
  source includes are not loaded or expanded by the host.
- Type aliases are not expanded by a CPU prepass. A bounded GPU projection can
  resolve scalar aliases through parser/HIR declaration records and the
  table-driven module resolver; generic, recursive, and broad alias targets
  remain unsupported.
- Generic enum, generic struct, trait, impl, `match`, and `for` conveniences no
  longer get CPU HIR precheck or erasure before reaching GPU stages.
- Generic function calls no longer get hidden substitution before reaching GPU
  type checking. Full monomorphization and backend specialization are separate
  future work.
- Broad Option/Result/Ordering scalar lowering for codegen is gone until
  implemented on the GPU path. The current bounded GPU exceptions are the
  `Ordering` unit enum tag/match dispatch proof and tag-only `Option`/`Result`
  predicate helper slices that derive variant tags from parser HIR metadata and
  GPU name-id tables. Payload enum layout, payload projection, and broad enum
  lowering remain unsupported until parser/type metadata provides constructor
  and call argument records for backend consumption.

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
  the resident GPU parser and the paper-style module/import tables now consume
  module headers, path imports, declaration visibility, qualified type paths,
  bounded scalar type aliases, regular/extern qualified function calls,
  top-level qualified constants, and one-segment constants made visible by path
  imports. The
  older direct-HIR helper still carries the same sideband into
  `hir_token_file_id`, but it is not the semantic path to extend. This still
  does not load imports, resolve quoted imports, support general qualified value
  paths, or make the normal compiler path a package compiler.
- One leading `module path;` source header as GPU-only metadata. It does not
  load files, discover import closures, or create cross-file namespaces by
  itself. The source-pack resolver can enable table-driven qualified
  struct/enum type paths, regular/extern qualified function calls, top-level
  qualified constants, and imported one-segment constants when all declaring
  modules are explicitly supplied.
  Same-source qualified shortcuts were deleted, so paths such as `app::main::Point`,
  `app::helper()`, or `app::LIMIT` only type-check through the sorted lookup
  resolver and HIR consumers.
- GPU parser/syntax coverage for leading `import path;` and `import "path";`
  metadata. Path imports resolve only against modules already present in the
  explicit source pack; quoted imports are recorded as unsupported metadata.
  The module/import resolver foundation now uses the paper-aligned shape:
  sort/deduplicate identifiers into stable GPU name ids, build
  path/module/import/declaration records from parser-owned AST/HIR spans, sort
  module and declaration keys, validate duplicates with adjacent comparisons,
  materialize visibility tables, resolve type/value paths through sorted lookup
  tables, and let narrow HIR consumers accept regular/extern qualified function calls,
  top-level constants, and imported one-segment constants. It still does not load imports, do package discovery,
  support quoted import loading, or support general qualified value lookup. The
  prior scan-based path-import resolver and dense hash/prefix-scan metadata
  slice have been deleted so they cannot be mistaken for the intended
  sorted-table design. Import path-vs-string target classification remains
  parser-owned metadata derived from the import-tail production, not a
  token-kind peek in the type checker.
- The LL(1) parser tree path now emits parser-owned HIR item-field metadata for
  top-level module/import and declaration items using production ids and
  parent/grandparent ancestry. It records item kind, name or path token span,
  namespace, visibility, and file id, and deliberately excludes impl-method
  `fn_item` nodes from top-level function declarations. Bounded scalar
  type-alias support consumes these records through the same GPU declaration
  tables; unsupported alias targets still fail closed in GPU type checking.
- The LL(1) parser tree path also emits parser-owned enum/match metadata from
  production ids and inverted tree arrays: enum variant parent, ordinal, payload
  type spans, match scrutinee, match arms, arm payload patterns, and arm result
  nodes. This is parse evidence for later GPU semantic/codegen consumers, not a
  CPU fallback or token-text rediscovery path.
- The LL(1) parser tree path also emits parser-owned struct metadata from
  production ids and inverted tree arrays: struct declaration field starts and
  counts, field parent/ordinal/type nodes, struct literal heads, literal field
  starts and counts, literal field parent nodes, and literal field value nodes.
  This is syntactic aggregate evidence only; declaration matching, type refs,
  scalar layout, and field projection semantics remain GPU semantic/codegen
  responsibilities.
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
  seeds in `stdlib/bool.lani` and `stdlib/i32.lani`. Module-form `core::*`
  scalar helpers can participate in explicit source-pack module/type/function
  lookup. Allocator and `std::*` extern declarations can now participate in
  resolver-backed qualified source-pack call type checking when their modules
  are explicitly supplied, but they remain non-executable source artifacts
  until runtime services, quoted import loading, host ABI lowering, broad
  qualified value lookup, and backend lowering exist.
- Direct WASM codegen for the currently supported top-level statement subset.
  A bounded HIR-driven WASM body pass can also emit a single `main` function
  with scalar local `let` statements, scalar return expressions, and bounded
  terminal `if`/`else` branches whose arms return scalar expressions or another
  terminal branch. The scalar expression subset includes arithmetic,
  comparisons, and boolean `!`, `&&`, and `||`. A separate bounded HIR-driven
  WASM module pass can emit `main` plus one selected scalar helper when `main`
  has a bounded scalar body, the selected helper has scalar parameters or no
  parameters, the selected helper has either a linear `let`/`return` body, a
  direct terminal `if`/`else` with scalar `return` arms, or one nested tail
  `else { if ... }` branch whose nested arms return scalar atoms, and `main`
  performs a direct call resolved by GPU type-check metadata. The module pass
  can also emit one bounded helper-to-helper scalar call when the selected
  helper calls one additional scalar helper resolved by `call_fn_index`.
  The same WASM codegen path can now consume explicitly supplied source packs
  through the GPU source-pack lexer path, and the module pass can lower either
  one resolver-backed source-pack selected scalar helper-call WASM slice from a
  helper module that may contain other uncalled functions, or one
  resolver-backed source-pack module-qualified scalar-const WASM slice read
  from another supplied module. These consume GPU module resolver metadata at
  the HIR path head; they are not source-text qualified-name scans. The bounded
  selected HIR scalar helper module slice is enough to lower boolean helpers
  such as `core::bool::not`, `core::bool::and`, `core::bool::or`,
  `core::bool::xor`, `core::bool::eq`, and `core::bool::from_i32`,
  zero-parameter helpers such as
  `core::target::has_threads`, `core::array_i32_4::len`, and
  `core::array_i32_4::is_empty`, direct terminal
  helper branches such as `core::i32::abs`, one bounded helper-to-helper scalar
  call such as `core::i32::saturating_abs`, and one-level tail helper branches
  such as `core::i32::clamp` and `core::i32::signum`, simple scalar terminal
  branches such as `core::i32::min` and `core::i32::max`, direct scalar
  predicates such as `core::i32::is_zero`, `core::i32::is_negative`,
  `core::i32::is_positive`, and `core::i32::between_inclusive`, direct
  wrapping arithmetic helpers such as `core::i32::wrapping_add`,
  `core::i32::wrapping_sub`, and `core::i32::wrapping_mul`, plus one bounded
  local-mutation `while` helper shape such as `core::i32::is_power_of_two` and
  `core::i32::next_power_of_two`, and bounded unsigned scalar helpers such as
  `core::u32::MIN`, `core::u32::MAX`, `core::u32::min`,
  `core::u32::max`, `core::u32::clamp`, `core::u32::wrapping_add`,
  `core::u32::wrapping_sub`, `core::u32::wrapping_mul`,
  `core::u32::saturating_add`, `core::u32::saturating_sub`,
  `core::u32::between_inclusive`, `core::u32::is_zero`,
  `core::u32::is_power_of_two`, `core::u32::next_power_of_two`,
  `core::u8::MIN`, `core::u8::MAX`, `core::u8::min`,
  `core::u8::max`, `core::u8::clamp`, `core::u8::wrapping_add`,
  `core::u8::wrapping_sub`, `core::u8::wrapping_mul`,
  `core::u8::saturating_add`, `core::u8::saturating_sub`,
  `core::u8::saturating_mul`, `core::u8::between_inclusive`,
  `core::u8::is_zero`, `core::u8::is_power_of_two`,
  `core::u8::next_power_of_two`,
  `core::u8::is_ascii_digit`, `core::u8::is_ascii_lowercase`,
  `core::u8::is_ascii_uppercase`, `core::u8::is_ascii_alphabetic`,
  `core::u8::is_ascii_alphanumeric`, `core::u8::is_ascii_hexdigit`, and
  `core::u8::is_ascii_whitespace`, when
  the full explicit helper source is supplied. The unsigned scalar path uses GPU
  call parameter type metadata to choose unsigned WASM comparison/division
  opcodes and emits high-bit scalar constants as signed LEB128 `i32.const`
  values. A separate bounded HIR-driven
  assertion helper pass can also lower resolver-selected void scalar helpers
  whose body is a typed `assert(bool)` expression statement followed by
  `return;`; true assertion helpers return normally and false assertion helpers
  trap deterministically in WASM. That pass consumes HIR call, return, and type
  metadata and must not recognize stdlib helper names. A bounded array-helper
  body pass can also lower
  resolver-selected fixed `[i32; 4]` helpers such as
  `core::array_i32_4::first`, `core::array_i32_4::last`, and the
  nested-conditional `core::array_i32_4::get_or` shape plus the bounded
  fixed-scan `core::array_i32_4::contains`, `core::array_i32_4::count`, and
  `core::array_i32_4::index_of_or`, `core::array_i32_4::sum`,
  `core::array_i32_4::min`, and `core::array_i32_4::max` shapes when `main`
  initializes a local array literal and calls the helper with that local; it
  consumes GPU array-literal metadata, HIR return/if/while spans, and
  `call_fn_index` rather than helper names. Stdlib execution still needs package loading, broader
  qualified call lowering, broader nested helper branches, broader helper
  loops, broader helper-to-helper calls, richer assertion/panic reporting, and
  broader scalar function-body support.

## Strict Blockers For A Real Stdlib

- GPU module/import expansion or a real package model.
  The explicit GPU lexer source-pack path can upload multiple already-supplied
  source strings and keep their tokens file-local, but the current compiler
  still does not discover files from imports or behave as a package compiler.
  `tests/parser_tree.rs` currently accepts one leading `module path;` metadata
  header followed by leading import metadata, and has fast-failing GPU syntax
  rejection tests for non-leading imports, duplicate module declarations, and
  non-leading module declarations so they cannot be silently ignored by the
  normal compile path.
  `tests/type_checker_modules.rs` exercises the GPU source-pack module resolver
  for path imports, same-module/source-pack qualified struct/enum type paths,
  regular qualified function calls including extern declarations, top-level
  qualified constants, imported one-segment constants, local or qualified unit enum variants, and bounded
  contextual local or qualified generic enum constructors, while keeping
  unresolved modules, missing declarations, non-function call targets, quoted
  imports, non-constructor symbolic generic enum returns, generic/method
  callees, and general qualified value paths rejected.
  The partial module/import type-checker metadata pass was deleted because it
  did not sort/deduplicate names, validate duplicates, resolve import targets,
  patch visibility, or enable qualified value calls. The replacement foundation
  now performs GPU name interning, module-key sorting, duplicate module
  validation, import-path-to-module lookup, declaration visibility table
  materialization, per-namespace path resolution, type-path projection, and
  narrow HIR value consumers for calls/constants/imported constants/unit enum variants.
  `tests/parser_tree.rs` preserves qualified value paths as HIR evidence, and
  `tests/type_checker_modules.rs` keeps unresolved module prefixes, missing
  qualified callees, non-call function values, and general qualified values
  rejected in GPU type checking so no shortcut can be mistaken for full module
  value resolution.
- Broad GPU type-alias handling.
  The GPU parser now accepts `type` declarations, and a bounded GPU module pass
  projects scalar aliases such as `type Count = i32;` from parser/HIR
  declaration spans into `module_type_path_type`. Alias names still resolve
  through the sorted module/import declaration tables; there is no token-level
  alias lookup or CPU expansion. Imported public scalar aliases can type-check
  when the defining module is explicitly supplied in the source pack. Generic
  aliases, alias chains, recursive aliases, and broad alias targets remain
  rejected until type refs and substitution support them.
- GPU backend lowering for primitive helper modules.
  Parser and type-check coverage for `stdlib/core/*.lani` seeds is not execution
  coverage. The default WASM backend now has a bounded HIR main-return body
  slice with local lets, scalar expressions, boolean operators, and bounded
  terminal `if`/`else` returns, plus a bounded selected HIR scalar helper
  module slice for constants, parameters, local lets, direct calls, boolean
  expressions, and WASM function/module emission. One resolver-backed
  source-pack selected scalar helper-call WASM slice can now lower the helper
  actually referenced by `main`, even when the supplied helper module contains
  other uncalled helpers. It can execute `core::i32::abs`,
  `core::target::has_threads`, `core::array_i32_4::len`,
  `core::array_i32_4::is_empty`,
  `core::i32::saturating_abs`, `core::i32::is_power_of_two`, and
  `core::i32::next_power_of_two`, plus direct selected helpers such as
  `core::i32::min`, `core::i32::max`, `core::i32::is_zero`,
  `core::i32::is_negative`, `core::i32::is_positive`,
  `core::i32::between_inclusive`, `core::i32::wrapping_add`,
  `core::i32::wrapping_sub`, and `core::i32::wrapping_mul`, plus bounded
  unsigned scalar helpers such as `core::u32::MIN`, `core::u32::MAX`,
  `core::u32::min`, `core::u32::max`, `core::u32::clamp`,
  `core::u32::wrapping_add`, `core::u32::wrapping_sub`,
  `core::u32::wrapping_mul`, `core::u32::saturating_add`,
  `core::u32::saturating_sub`, `core::u32::between_inclusive`,
  `core::u32::is_zero`, `core::u32::is_power_of_two`,
  `core::u32::next_power_of_two`, `core::u8::MIN`, `core::u8::MAX`,
  `core::u8::min`, `core::u8::max`, `core::u8::clamp`,
  `core::u8::wrapping_add`, `core::u8::wrapping_sub`,
  `core::u8::wrapping_mul`, `core::u8::saturating_add`,
  `core::u8::saturating_sub`, `core::u8::saturating_mul`,
  `core::u8::between_inclusive`, `core::u8::is_zero`,
  `core::u8::is_power_of_two`, `core::u8::next_power_of_two`,
  `core::u8::is_ascii_digit`,
  `core::u8::is_ascii_lowercase`, `core::u8::is_ascii_uppercase`,
  `core::u8::is_ascii_alphabetic`, `core::u8::is_ascii_alphanumeric`,
  `core::u8::is_ascii_hexdigit`, and `core::u8::is_ascii_whitespace` from full explicit helper source packs. A
  separate HIR-driven assertion/panic lowering
  pass can compile resolver-selected void helpers such as `test::assert::eq_i32` when the helper
  body contains a typed assertion expression statement and void return, without
  a stdlib-name special case. A separate bounded array body pass can execute
  `core::array_i32_4::first`, `core::array_i32_4::last`, and
  `core::array_i32_4::get_or` from explicit source packs for a local `[i32; 4]`
  literal argument by reading the helper's HIR return/if shape and the GPU array
  literal table. It can also execute the bounded fixed-scan
  `core::array_i32_4::contains`, `core::array_i32_4::count`, and
  `core::array_i32_4::index_of_or`, plus the bounded fixed-fold
  `core::array_i32_4::sum` shape and the bounded fixed-extreme
  `core::array_i32_4::min` / `core::array_i32_4::max` shapes, by reading the
  helper's HIR while/if shape and the same GPU array literal table. Broader
  nested helper branches, broader `while` helpers, arrays beyond this fixed
  projection slice, slices, generics, traits, allocation, host APIs, package
  loading, richer assertion/panic reporting, broader helper-to-helper calls,
  and broad qualified value lowering remain rejected until their GPU
  lowering/runtime exists.
- GPU semantic support for structs, enums, generics, traits, impls, and broad
  `match`
  without CPU precheck/erasure.
  `tests/type_checker_semantics.rs` currently has a fast-failing rejection test
  for trait declarations and trait impl declarations so these gaps cannot be
  mistaken for working trait support. Bounded `match` result typing and
  `Option<T>`-style tuple payload bindings now have GPU type-check acceptance
  coverage, but exhaustive pattern analysis, guards, nested/destructuring
  patterns, enum layout, and backend lowering are still not implemented.
  `tests/type_checker_modules.rs` still keeps the full `core::cmp` and
  `core::hash` seed files rejected while they depend on unsupported trait
  semantics. `core::option` and `core::result` now type-check as explicitly
  supplied source-pack seeds through bounded match payload typing and symbolic
  generic enum constructor returns. Bounded generic enum constructor
  payload substitution now works for annotated concrete local contexts such as
  `let value: Maybe<i32> = Some(1)` and `Result<i32, bool>` constructors,
  local and qualified unit enum variants can type-check through source-pack
  module resolver arrays, and bounded contextual local or qualified generic enum
  constructors can type-check when their modules are explicitly supplied.
  `core::ordering` now type-checks as an explicitly supplied source-pack seed.
  Symbolic generic enum constructor returns can type-check when the return
  expression is validated against `fn_return_ref_*` metadata. Bounded
  stdlib-shaped matches such as `Some(inner) -> inner` / `None -> fallback`
  can type-check through HIR match spans, resolver arrays, and type-instance
  payload substitution. Bounded module-qualified generic calls such as
  `core::option::unwrap_or(value, fallback)` and
  `core::result::unwrap_or(value, 3)` can type-check through HIR call spans,
  resolver arrays, GPU name-id tables, and type-ref metadata; match
  exhaustiveness and payload enum layout remain unsupported. A bounded
  codegen-only unit enum slice now lowers `core::ordering::compare_i32` plus a
  `match` over `Ordering` variants from an explicit source pack by deriving
  variant tags from parser HIR item metadata and resolver arrays. The same
  enum/match module can lower a bounded tag-only predicate shape where `main`
  stores an explicitly constructed `Option` or `Result` variant tag in a scalar
  local and returns a resolver-selected helper such as
  `core::option::is_some(value)` or `core::result::is_ok(value)`. That slice
  uses parser HIR match scrutinee, arm-count, arm-pattern, arm-payload, and
  arm-result metadata compacted into a GPU `uint4` record table, resolver call
  metadata, and GPU name-id tables to map variant names to HIR variant
  ordinals; it does not project payload values, prove full enum layout, or
  claim `is_none`/`is_err` or unwrap helpers.
  Payload helper execution remains blocked until codegen consumes parser/type
  records for constructor payload values and call argument values instead of
  rediscovering them from token punctuation.
  Concrete inherent method calls type-check for direct single-file no-module
  receiver fixtures, including receivers that are already resolved GPU call
  results. The `core::range` seed now type-checks as an explicitly supplied
  source pack, including bounded `Range<i32>` method calls on annotated
  receivers and on `core::range::range_i32(...)` call-result receivers. The
  same bounded source-pack path now covers `RangeInclusive<i32>` construction
  and inclusive endpoint/containment method shapes through the same
  parser/HIR-derived aggregate and method metadata. Broad method/aggregate
  backend lowering remains unsupported, but the WASM codegen boundary now
  receives the GPU-produced parser tree, interned-name, aggregate,
  and method metadata needed for the next slice:
  `node_kind`/`parent`/`first_child`/`next_sibling`,
  `name_id_by_token`, `type_expr_ref_*`, `fn_return_ref_*`, type-instance
  argument refs, member-result refs, struct-init field refs, method declaration
  receiver mode/offset, and method call receiver refs. Executable aggregate
  slices walk those AST/HIR records and flatten aggregate values from those
  records rather than recognizing `core::range` names or inferring field layout
  from token spelling. A WASM aggregate layout pair now runs on GPU before
  emission and publishes parser/type-derived struct-init/member field indices. A
  bounded HIR aggregate-body pass consumes those indices to execute a
  non-generic scalar-field struct literal plus member projection in `main`, and
  the resolver-selected `core::range::range_i32` / `start_i32` helper path now
  executes from a full explicit source pack. The same aggregate path now has a
  bounded method-projection slice for an annotated local receiver such as
  `range.start()`: aggregate layout derives the method-body `self.field`
  projection from GPU method receiver refs, and body emission maps the implicit
  receiver through `call_fn_index` and method receiver metadata. A second
  bounded slice executes a direct call-result receiver such as
  `core::range::range_i32(1, 4).start()` by storing the resolver-selected
  aggregate constructor result into scalar slots before projecting the
  table-resolved method body. The aggregate body path also lowers bounded
  receiver-field comparison method/helper bodies such as `is_empty()` and
  `contains(value)` by consuming aggregate field indices, call argument spans,
  and method resolver output; this now includes the inclusive range helper and
  method shapes. Aggregate returns/parameters and broader generic aggregate
  specialization remain separate backend work.
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
  types for the token checker. The array-return ref pass now also accepts
  concrete `[i32; literal]` returns from identifiers or HIR-backed i32 literal
  arrays with matching lengths. Generic array/slice calls, generic array
  returns, local generic array annotations,
  call returns, broader length unification, slice ABI, and backend lowering
  remain rejected.
- GPU semantic substitution for generic struct literals and generic field
  projection.
  The metadata passes now record named generic instance candidates, bind them to
  declarations, publish argument refs, and precompute substituted struct
  field/member refs on GPU. `Range<i32>` construction and `range.start`
  projection have GPU type-check coverage in direct no-module fixtures and in
  the explicitly supplied module-form `core::range` source-pack seed. Full
  monomorphization and backend specialization remain separate work.
- GPU semantic use of generic parameter bounds and `where` predicates for trait
  solving and method lookup.
  `tests/type_checker_semantics.rs` currently has a fast-failing rejection test
  for generic bounds and `where` clauses so parser coverage cannot be mistaken
  for working predicate semantics.
- GPU semantic support for full method calls and method lookup.
  The first GPU-only method metadata slice records method declaration receiver
  types, receiver type-ref tags/payloads, defining module ids, impl HIR nodes,
  name tokens, interned method name ids, receiver modes, and parameter offsets
  from parser/HIR method records. A bounded GPU table resolver now marks
  concrete inherent calls from HIR member/call records, binary-searches the
  sorted method key order for `(module_id, receiver type-ref tag/payload,
  interned method name id)`, canonicalizes named type-instance payloads through
  their resolved declaration tokens, rejects adjacent duplicate method keys, and
  validates simple value arguments by walking HIR arg-list records. A split
  call-result receiver marker consumes `call_fn_index` plus `fn_return_ref_*`
  metadata after GPU call resolution, so direct receivers such as
  `make_range().contains(2)` and source-pack receivers such as
  `core::range::range_i32(1, 4).start()` use resolved function declaration
  return refs instead of source-text lookup. The current slice covers direct
  calls whose receiver declaration already has a concrete annotated type ref,
  plus bounded call-result receivers with concrete return refs. Broader
  receiver type-ref propagation, trait dispatch, generic methods beyond this
  bounded concrete instance, richer visibility policy beyond the current
  module-id public/private checks, and backend lowering remain blocked.
- GPU semantic support for array-returning function signatures and return
  values. A bounded GPU-only consumer now accepts concrete identifier returns
  and HIR-backed i32 value array returns for matching `[i32; literal]`
  signatures, such as returning a parameter, annotated local, or `[1, 2, 3, 4]`
  literal with the same concrete length. Bounded index-expression elements such
  as `values[3]` are accepted when the base resolves to a concrete i32 array
  type and the HIR index expression has an i32 scalar index. This is implemented by
  `type_check_type_instances_05_array_return_refs.slang`, which compares
  precomputed type-instance element/length records plus parser HIR
  array-expression and index-expression evidence and writes a return-token
  sentinel consumed by `type_check_tokens_min.slang`; the hot token checker only
  consumes the sentinel. Generic `[T; N]` returns, call returns, broader indexed
  expressions, and mismatched concrete lengths remain rejected until GPU generic
  element substitution and full array identity semantics exist.
  `tests/type_checker_modules.rs` now accepts the flat `array_i32_4` seed as a
  direct GPU type-check fixture and the module-form `core::array_i32_4` seed as
  an explicit source-pack fixture. This is frontend coverage only; GPU backend
  lowering for those helper bodies is still blocked.
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

### Plan-Derived Blocker Checklist

The `stdlib/PLAN.md` layers require these language/runtime surfaces. Each item
must remain blocked until the named GPU-only implementation exists; CPU
prepasses, CPU fallbacks, source concatenation, or documentation-only claims do
not count.

- `core` modules/imports: blocked until a GPU-compatible module/package
  resolver loads explicit source packs, builds sorted module/import/declaration
  tables, validates duplicates, applies visibility, and resolves cross-file
  declarations.
- Broad qualified values such as `core::i32::abs` and `core::i32::MIN`:
  blocked until package loading, general GPU qualified value lookup, and backend
  lowering exist. The current source-pack frontend can type-check regular
  qualified function calls and top-level qualified constants only through the
  table-driven resolver and HIR consumers.
- Generic `Option`, `Result`, `Range`, collections, iterators, and helpers:
  blocked until GPU monomorphization or equivalent specialization, generic
  layout, and backend lowering exist, except for the bounded GPU type-check
  slices already listed below, including simple qualified `Option`/`Result`
  helper calls inferred from scalar literal or annotated local arguments.
- Traits/interfaces for `Eq`, `Ord`, `Hash`, `Debug`, iterator traits, allocator
  traits, and method dispatch: blocked until GPU trait/interface solving,
  impl-conformance checks, bound/`where` predicate use, dispatch metadata, and
  backend lowering exist.
- Module-form inherent methods such as `core::range::Range<i32>.start()`:
  partially covered for explicitly supplied source packs when the receiver has a
  concrete annotated type ref resolving through parser/HIR-derived GPU method
  declaration records and method-call records, or when the receiver is a
  GPU-resolved call result with a concrete `fn_return_ref_*`, as in the
  `core::range::Range<i32>` and `core::range::RangeInclusive<i32>` method
  fixtures. The WASM codegen boundary exposes the relevant GPU parser tree and
  aggregate/method records, and the bounded source-pack helper projection
  `core::range::start_i32(core::range::range_i32(...))` now executes through
  aggregate metadata. A bounded method-call body slice can also lower annotated
  local receiver `.start()` / `.contains(value)` and direct call-result receiver
  `.start()` / `.end()` / `.is_empty()` for exclusive and inclusive ranges by
  consuming the GPU method resolver result plus aggregate/method metadata;
  broader receiver inference, trait methods, richer visibility policy beyond
  current module-id public/private checks, and broader backend lowering remain
  blocked.
- Arrays, slices, and ranges as reusable stdlib APIs: blocked until GPU generic
  element/length semantics, slice ABI, array literal/return/call lowering, loop
  lowering, and range iteration lowering exist, beyond the bounded direct
  fixtures already listed below.
- `String`, `Vec`, maps, sets, trees, arenas, and allocation-aware formatting:
  blocked until GPU-visible heap allocation, ownership/lifetime rules,
  pointer/string/slice ABI, fallible allocation reporting, and collection
  lowering exist.
- Panic/assert primitives and the test assertion helpers: bounded explicit
  source-pack helpers can lower through HIR-driven assertion/panic codegen when
  they are resolver-selected void helpers with typed assertion expression
  statements and void returns on the GPU-only codegen path. Full panic
  reporting, source locations, formatted assertion messages, harness
  integration, package loading, and broader helper bodies remain blocked.
- `extern fn`, host ABI declarations, allocator hooks, I/O, filesystem, process,
  environment, time, networking, and test harness integration: blocked until a
  GPU-only compile path has target capability metadata, host ABI lowering,
  linking/runtime bindings, and executable backend support.

| Stdlib requirement | Required compiler/runtime artifact | Current evidence | Status |
| --- | --- | --- | --- |
| Source files in modules | GPU-compatible module/import resolution, visibility, and path lookup | `module path;` and leading `import path;` / `import "path";` have GPU syntax metadata coverage. The replacement foundation now uses paper-style name interning, sort/deduplication, module-key duplicate validation, sorted import-to-module lookup, per-namespace declaration lookup, type-path projection, a HIR value-call consumer for regular and extern qualified function calls plus bounded scalar/literal generic return inference, a HIR value-const consumer for top-level qualified and imported one-segment constants, a HIR unit-enum-variant consumer for local and qualified unit enum variants, and a type-instance projection feeding bounded local or qualified enum constructor calls. The prior scan-based path-import resolver, dense metadata slice, and same-source qualified-path shortcuts have been deleted. Path imports only resolve against explicitly supplied source-pack modules; non-leading modules, non-leading imports, quoted import loading, broad generic/method callees, non-constructor symbolic generic enum returns, and general qualified value paths remain rejected | Blocked |
| Primitive helper modules | GPU parser/type checker plus GPU module/value-path resolution and HIR-driven function-body codegen for scalar and bounded aggregate helpers | Flat compatibility helpers such as `stdlib/bool.lani` and `stdlib/i32.lani` type-check directly. Module-form scalar helpers and constants can participate in source-pack module/type/function lookup when explicitly supplied, but broad package loading is still blocked. Backend execution has top-level-statement support, a bounded HIR `main` local-let/return-expression slice, one selected same-source scalar helper direct-call WASM slice, one resolver-backed source-pack selected scalar helper-call WASM slice from a supplied helper module that may contain other uncalled helpers, one bounded helper-to-helper scalar helper call, one bounded local-mutation `while` helper shape, one resolver-backed source-pack module-qualified scalar-const WASM slice, one separate HIR-driven assertion/panic slice for resolver-selected void helpers with typed assertion expression statements and void returns, one bounded array helper slice for local `[i32; 4]` literals passed to helpers whose HIR body returns `values[constant]`, a nested conditional over a scalar index parameter, or a fixed scan/fold returning a scalar result, and one bounded aggregate helper slice that lowers `core::range::range_i32` construction plus `core::range::start_i32` / `contains_i32` projection/comparison helpers, annotated-local `.start()` / `.contains(value)` method bodies, and direct call-result `.start()` / `.end()` / `.is_empty()` method bodies from a full explicit source pack, without stdlib-name recognition. Boolean selected helpers such as `core::bool::not`, `core::bool::and`, `core::bool::or`, `core::bool::xor`, `core::bool::eq`, and `core::bool::from_i32`, zero-parameter selected helpers such as `core::target::has_threads`, `core::array_i32_4::len`, and `core::array_i32_4::is_empty`, fixed array projection helpers such as `core::array_i32_4::first` and `core::array_i32_4::last`, one bounded fixed-array conditional lookup helper such as `core::array_i32_4::get_or`, bounded fixed-array scan helpers such as `core::array_i32_4::contains`, `core::array_i32_4::count`, `core::array_i32_4::index_of_or`, `core::array_i32_4::sum`, `core::array_i32_4::min`, and `core::array_i32_4::max`, direct terminal helper branches such as `core::i32::abs`, one bounded helper-to-helper scalar call such as `core::i32::saturating_abs`, one bounded local-mutation loop shape such as `core::i32::is_power_of_two` and `core::i32::next_power_of_two`, one-level tail helper branches such as `core::i32::clamp` and `core::i32::signum`, bounded aggregate helpers such as `core::range::range_i32` / `core::range::start_i32` / `core::range::contains_i32`, bounded annotated-local and call-result method bodies such as `range.start()`, `range.contains(2)`, and `core::range::range_i32(4, 4).is_empty()`, bounded assertion helpers such as `test::assert::eq_i32`, and bounded tag-only enum predicate helpers such as `core::option::is_some` and `core::result::is_ok` can be lowered from full explicit helper source packs. Full stdlib helper modules are not broadly lowered, broader nested helper branches, broader helper loops, broader helper-to-helper calls, aggregate returns/parameters beyond the bounded slice, array returns/loops beyond the fixed projection slice, broader method-body lowering, enum payload layout/projection, and native stdlib-helper lowering remain unsupported | Partial for flat/source-pack frontend and scalar helper/const/assertion/array/aggregate-helper/enum-tag-predicate WASM; blocked for stdlib module execution |
| `Option`, `Result`, `Ordering` | GPU enum semantics, match exhaustiveness, enum layout/lowering | Parser coverage plus concrete GPU constructor payload type/arity checks; bounded contextual generic enum constructor checks now accept annotated concrete locals such as `Maybe<i32> = Some(1)` and `Result<i32, bool> = Ok(1)`/`Err(false)` on GPU, local and qualified `Ordering` unit variants can type-check through source-pack resolver arrays, `core::ordering`, `core::option`, and `core::result` now type-check as explicitly supplied source-pack seeds, explicitly supplied local or module-qualified constructors such as `Some(1)` and `core::maybe::Some(1)` can type-check in annotated concrete local contexts, symbolic generic constructor returns such as `fn wrap<T>(value: T) -> Option<T> { return Some(value); }` can type-check through return-ref metadata, bounded stdlib-shaped matches such as `Some(inner) -> inner` / `None -> fallback` can type-check through HIR match spans and type-instance payload substitution, and bounded module-qualified calls such as `core::option::unwrap_or(value, fallback)` / `core::result::unwrap_or(value, 3)` can infer scalar returns from type-ref metadata. Backend execution now has a bounded HIR-driven unit-enum tag and match dispatch slice for `core::ordering::compare_i32` selected from a full explicit source pack, plus bounded tag-only `Option`/`Result` predicate helper execution for explicit source-pack shapes such as `core::option::is_some(value)` and `core::result::is_ok(value)`, without stdlib-name recognition. The tag-only predicate slice represents explicitly constructed unit or payload variants by tag only through parser HIR variant ordinals and GPU name-id lookup; it does not lower payload projection helpers such as `unwrap_or`, does not claim `is_none`/`is_err`, and rejects ambiguous duplicate variant names. Package loading, exhaustive match semantics, payload enum layout, generic enum monomorphization, and broad backend lowering are still missing | Partial for parser/type-check plus bounded `Ordering` and tag-only `Option`/`Result` WASM; blocked for general enum codegen |
| Generic function calls | Simple GPU call substitution for callee type parameters, with full monomorphization/backend specialization as separate later work | `keep(7)`, `keep(true)`, nested direct calls such as `keep(keep(7))`, generic forwarding from one generic function into another, and bounded module-qualified `Option`/`Result` helpers inferred from scalar literal or annotated local arguments have GPU type-check tests; conflicting repeated generic arguments are rejected | Partial |
| Generic arrays and slices | Const generics, generic element types, slice metadata representation, GPU type-instance records | Limited `[i32; N]` and `[i32]` type-check tests; `type_check_type_instances_01_collect.slang` records array/slice element and length refs on GPU, `type_check_type_instances_07_array_index_results.slang` publishes bounded generic `values[0]` element result types for parameter/struct-field declarations, and `type_check_type_instances_05_array_return_refs.slang` accepts concrete identifier returns plus HIR-backed i32 value array returns, including bounded concrete index-expression elements, for matching `[i32; literal]` signatures. The flat and module-form `[i32; 4]` seeds now type-check on GPU, but generic array/slice calls, generic array returns, local generic array annotations, call returns, mismatched concrete lengths, and backend lowering remain rejected | Partial |
| Traits/interfaces and methods | Trait bounds, impl conformance, module-aware method lookup, dictionaries or static dispatch | Parser coverage for trait/impl/where and receiver syntax; direct `self.field` access type-checks for `self`, `self: Type`, and `&self` in impl bodies. Concrete inherent method calls use GPU method declaration records, sorted method key tables, interned names, type-ref metadata, and current module-id public/private checks. The bounded `core::range::Range<i32>` source-pack method fixture type-checks for annotated receivers and concrete call-result receivers such as `core::range::range_i32(1, 4).start()`. WASM backend lowering is available only for bounded aggregate method bodies over annotated-local/direct call-result receivers, including field projection, receiver-field comparison, and one explicit scalar value parameter; trait dispatch, broader generic methods, richer visibility policy, and broader backend lowering remain unavailable | Blocked |
| `String` and `Vec` | Heap allocation, ownership model, pointer/slice/string ABI | Allocator ABI seeds only | Blocked |
| Maps, sets, heaps, trees | Generics, allocation, traits, ordering/hashing, loops | No complete prerequisites | Blocked |
| Formatting/parsing | Strings, writers/builders, integer/float formatting, error types | No string/runtime representation | Blocked |
| `std` host APIs | Target capability model, ABI, native linking/x86 codegen | Raw extern ABI declaration seed files type-check as single-file inputs, and bounded source-pack fixtures can type-check resolver-backed qualified calls such as `std::io::flush_stdout()` or allocator hooks when the defining module is explicitly supplied. There is still no quoted import loading, host runtime, capability model, native linking, or executable backend support | Blocked |
| Test framework | Assertions, panic reporting, source locations, harness | `assert(bool)` and explicit source-pack assertion helper seeds can type-check. A bounded HIR-driven assertion/panic WASM pass proves true assertion helpers return normally, false assertion helpers trap deterministically, and the shader contains no stdlib-specific helper-name checks. Panic reporting, source locations, formatted messages, automatic package loading, and harness integration remain unavailable | Partial |
| Native output | GPU register allocation and x86_64 binary emission wired into compiler | The old WASM-translation prototype has been deleted. A new direct GPU HIR-to-x86 slice records the `main` function from GPU `fn_entrypoint_tag` metadata, lowers a literal return including HIR-backed unary signed integer literals and boolean literals, up to two scalar locals initialized from scalar literals, HIR-backed unary negation over bounded scalar locals, HIR-backed logical-not over bounded boolean atoms, one bounded two-atom integer or boolean binary return, one scalar comparison return, or one terminal scalar `if`/`else` with a comparison condition into vregs, materializes live intervals by scanning explicit GPU value-edge records, assigns registers from those liveness records with no token/declaration-index register map, selects fixed x86 instruction records including `cmp`/`setcc`/`movzx` for predicate returns, `and`/`or` records for boolean binary returns, and conditional/unconditional branch records for terminal branches, computes instruction sizes and byte offsets, encodes packed `.text` bytes with zeroed relocation fields, patches branch displacements from explicit GPU relocation records, computes ELF layout records, emits final ELF64 bytes for the bounded `main` return shapes, and rejects unsupported return expressions through GPU-written status. The x86 lowerer consumes parser-owned packed `hir_expr_record` rows for binary/comparison operators and operands, parser-owned HIR literal value records for integer immediates, parser-owned `hir_stmt_record` rows for local binding, return, const, and terminal `if` block facts, and explicit `x86_vreg_arg0/1` plus packed branch-arm value edges for branch condition/arm values rather than reparsing source bytes, token punctuation/layout, or hard-coded branch vreg positions. The same direct x86 route can now receive explicit source packs and emit ELF for a module `main` that uses the bounded scalar main-return shape while supplied modules flow through GPU frontend/type metadata, plus one resolver-backed module-qualified scalar constant return such as `core::i32::MAX` through GPU `visible_decl` metadata, parser-owned return value tokens, and parser HIR path spans, and one resolver-backed module-qualified direct helper call whose callee is the bounded scalar terminal-if parameter branch shape. The helper branch path uses call/value records, function return eval/vreg records, function layout rows, planned compare/branch/return instruction rows, and GPU relocation patch rows rather than helper-name or token-text recognition; the CLI explicit `--stdlib`/input file-list path forwards to that same GPU source-pack x86 entrypoint without import discovery or host semantic passes. Package imports, broad call lowering, broader native source-pack helper execution, nested branches/loops, spilling, and broader executable backend coverage remain missing | Partial |

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

Type aliases must remain GPU-semantic features, not syntax-only claims. The
current bounded slice accepts syntax only because a GPU declaration-span alias
projection validates scalar targets and feeds the existing type-path projection.
Generic aliases, alias chains, recursive aliases, and broad alias targets must
stay rejected until a GPU type-ref/substitution design supports them.

## Acceptance Rules

A stdlib feature is not complete unless it has:

- Parser coverage through the GPU parser path.
- Type-check coverage through the GPU type checker path.
- Backend coverage when codegen is part of the claim.
- Documentation that does not imply CPU fallback or CPU prepass support.
- Failure tests for unsupported target/runtime behavior.
