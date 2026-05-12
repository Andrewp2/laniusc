# Lanius Source Standard Library

This directory contains the initial Lanius standard library as plain `.lani`
source files.

The full desired standard library surface is tracked in
[STANDARD_LIBRARY_SPEC.md](STANDARD_LIBRARY_SPEC.md). The long-term roadmap is
tracked in [PLAN.md](PLAN.md). Compiler and runtime prerequisites for
implementing those layers are tracked in
[LANGUAGE_REQUIREMENTS.md](LANGUAGE_REQUIREMENTS.md).

These files are not auto-imported by the compiler. The old CPU source import
expander has been removed; the GPU syntax path now accepts one leading
`module path;` declaration plus leading `import path;` or `import "path";`
declarations as source metadata only. Imports are not loaded or resolved, and
GPU type checking still rejects import items until a resolver exists. Duplicate
or non-leading `module` declarations and non-leading imports remain rejected so
they cannot be silently ignored. Call-shaped qualified value paths can pass GPU
syntax as HIR evidence, and GPU type checking now resolves same-source
qualified function calls whose prefix matches the leading module declaration.
Imports, external qualified calls such as `core::i32::abs(-7)`, qualified
constants such as `core::i32::MIN`, and general qualified value paths remain
rejected.

The GPU lexer now has an explicit source-pack upload path for already-supplied
source strings. It concatenates their bytes, uploads `source_file_count`,
`source_file_start`, and `source_file_len`, resets the DFA at GPU-visible file
starts, clamps token starts to file starts after skipped trivia, and writes
per-token `token_file_id` on GPU. The GPU syntax checker uses that sideband to
validate leading `module` and `import` metadata per file. An explicit
source-pack type-check entrypoint records the resident GPU
lexer/parser/type-checker path against source-pack buffers. Already-supplied
multi-file source packs can flow through that resident GPU path when the files
contain independent module metadata and supported declarations. Path imports in
an already-uploaded source pack now resolve on GPU to matching module metadata,
while unresolved imports, string imports, and duplicate module paths reject. The
type checker treats module/import headers as parser-owned HIR item spans, not
as token-neighborhood patterns. This still does not load files, follow module
declarations to files, make declarations visible across files, or make the
normal compiler path a package compiler. The normal compiler now records the
LL(1) tree/HIR path. That path receives the lexer-produced `token_file_id`
sideband, validates it during GPU syntax checking, and feeds it into LL(1) HIR
ownership metadata. The older direct-HIR helper still mirrors the sideband, but
it is not the semantic path to extend.

Module-form helpers live under `stdlib/core/` and use module names such as
`core::i32::abs`, but the normal compiler path does not resolve those imports
yet. The leading module header is metadata for source-shape seeds, not a
visibility or lookup boundary. Legacy flat files keep the `lstd_` prefix so
copied or manually concatenated helpers are less likely to collide with
application functions.

The GPU parser now preserves early HIR evidence for module items, import items,
and complete qualified path spans, but those records are not resolution results.
They do not imply that imports were loaded, modules were matched to files, or
qualified names were bound to declarations.

The LL(1) parser tree path additionally emits parser-owned HIR item-field
metadata from production ids and AST ancestry. It records top-level item facts
for modules, imports, consts, functions, extern functions, structs, enums, and
type aliases while excluding impl methods from top-level function declarations.
Those records are not yet a resolver or dense declaration table.

Current scope is intentionally small. When a seed is described as type-checking
below, that means direct single-file GPU parser/type-check acceptance only; it
does not imply import resolution, qualified value lookup, runtime services, or
backend lowering:

- `core/i32.lani` has module-form integer constants and helpers built from
  supported arithmetic and comparison operators, including a source-level
  `saturating_abs` seed. It now has direct GPU type-check coverage as a
  single-file module seed, though normal imports and backend execution are still
  separate blockers.
- `core/u8.lani`, `core/u32.lani`, and `core/i64.lani` seed additional integer
  helper modules with the same source-level shape as `core/i32`; `core/u8`
  adds byte-oriented ASCII classification helpers, and `core/u32` also includes
  source-level `saturating_add` and `saturating_sub` seeds.
- `core/f32.lani` seeds a small floating-point helper module using currently
  parseable float literals, comparisons, and arithmetic.
- `core/char.lani` seeds ASCII classification helpers using currently parseable
  char literals and boolean expressions. `core/char.lani`, `core/u32.lani`, and
  `core/ordering.lani` also have direct GPU type-check coverage as single-file
  module seeds.
- `core/bool.lani` has module-form boolean combinators and conversions built on
  the current bool expression surface, including `true` and `false` literals.
  `core/bool.lani` and `test/assert.lani` remain covered by GPU type-check
  seed tests.
- `core/array_i32_4.lani` has module-form fixed-size `[i32; 4]` helper seeds
  for length, first/last element access, lookup, counting, min/max, sum, copy,
  fill, and reverse. It is still a concrete stopgap for helpers that need a
  known length value or loops. The GPU type checker accepts concrete identifier
  returns for matching `[i32; literal]` signatures, but array literal returns
  and loop-built array returns remain source seeds until fuller GPU array
  identity and backend lowering exist.
- `core/array_i32.lani` has early const-generic `[i32; N]` helpers such as
  `first()` and `get_unchecked()`. The full seed type-checks as a direct
  single-file GPU input and validates named array lengths in frontend type
  checking for concrete `i32` elements. A bounded GPU slice now accepts generic
  array/slice declarations and indexed element returns such as
  `fn first<T, const N: usize>(values: [T; N]) -> T { return values[0]; }`,
  plus `ArrayVec<T, const N: usize>` field declarations. Generic array/slice
  calls, generic array returns, local generic array annotations, full const
  evaluation, slice ABI, and array-valued backend lowering are still missing.
- Generic function declarations, generic type annotations, and simple generic
  function-call substitution now have GPU type-check coverage for direct calls
  inferred from arguments, including generic forwarding from one generic
  function to another and nested direct helper calls such as `keep(keep(7))`.
  Full monomorphization and backend specialization are separate work.
- `core/option.lani` and `core/result.lani` have declaration seeds for the
  generic core sum types. `core/ordering.lani` has the non-generic `Ordering`
  enum plus `compare_i32`, and that concrete `core/ordering.lani` seed
  type-checks as a direct single-file GPU input. The full `core/option.lani`
  and `core/result.lani` seeds remain rejected by GPU type-check module tests
  because they still depend on `match`, symbolic generic returns, imports, and
  enum layout/lowering. Bounded GPU generic enum constructor payload
  substitution now works for annotated concrete locals such as
  `Maybe<i32> = Some(1)` and `Result<i32, bool>` constructors. Generic return
  positions, import resolution, external qualified type paths, exhaustive match
  semantics, full monomorphization, general enum layout, and verified backend
  execution are not implemented yet. Same-source qualified type paths have a
  narrow GPU-only slice for signatures, parameter use, and returns.
- `core/cmp.lani` has declaration seeds for generic `Eq<T>` and `Ord<T>`
  traits plus bounded `i32` trait impls. `core/hash.lani` similarly seeds a
  generic `Hash<T>` trait and an `i32` impl. This validates trait and impl
  parsing on the GPU path. `where` clauses now have GPU frontend parser
  coverage for generic item declarations, but they do not yet drive trait
  solving, method lookup, dictionaries, or backend lowering. Associated items,
  full trait solving, and backend lowering are not implemented yet. The full
  `core/cmp.lani` and `core/hash.lani` seed files remain rejected by GPU
  type-check module tests.
- `core/range.lani` has declaration seeds for `Range<T>`,
  `RangeInclusive<T>`, `RangeFrom<T>`, `RangeTo<T>`, and `RangeFull`, plus
  source-level `i32` helpers for construction, endpoints, emptiness, and
  containment. It also has bounded `Range<i32>` impl method declarations using
  value, explicit-type, and reference receiver forms. These exercise generic
  struct declaration, receiver, member-access, and `for` syntax in
  parser/source-shape coverage.
  `self`, `self: Type`, and `&self` receiver forms now parse through the GPU
  frontend, direct `self.field` access type-checks for those receiver spellings
  in concrete `Range<i32>` impl bodies, and concrete inherent method calls
  type-check for direct single-file receivers. The full seed type-checks as a
  direct single-file GPU input. `&self` does not yet imply a general reference or
  borrow model. General range operators, slicing integration, trait/generic
  method lookup, imported method visibility, full monomorphization, and general
  backend representation are not implemented yet.
- `core/slice.lani` has source-level `[i32]` view helpers such as
  `first_i32`, `get_or_i32`, `contains_i32`, and `sum_i32`. Direct `[i32]`
  slice parameter/indexing fixtures have GPU type-check coverage, but the full
  `core/slice.lani` file is still a source seed rather than an accepted stdlib
  module seed. Slice runtime metadata, borrowing, mutation views, and backend
  representation are not implemented yet.
- `core/panic.lani` has source-level `panic()` and `unreachable()` helpers
  built on the current deterministic `assert(false)` failure path. The seed
  type-checks as a direct single-file GPU input. Rich panic payloads,
  formatting, hooks, unwinding, and source locations are not implemented yet.
- `core/target.lani` has source-level target capability constants and helpers
  intended to become paths such as `core::target::has_filesystem()` and
  `core::target::is_wasm()` once module resolution exists. The seed type-checks
  as a direct single-file GPU input. These are static defaults for the current
  host-backed test environment; real target configuration and compile-time
  capability evaluation are still missing.
- `alloc/allocator.lani` has source-level allocator ABI declarations for
  allocation, growth, deallocation, and allocation failure hooks. The full
  declaration seed type-checks as a direct single-file GPU input, and the
  extern signatures can type-check as calls in direct single-file fixtures, but
  no GPU module import, target runtime implementation, native linker
  integration, heap ownership model, or allocator runtime exists yet.
- `std/io.lani` has source-level host I/O ABI declarations for stdin,
  stdout, stderr, flushing, and a minimal `print_i32` hook. The full
  declaration seed type-checks as a direct single-file GPU input, and these
  extern signatures can type-check as calls in direct single-file fixtures, but
  no GPU module import, host runtime, capability gating, string/slice ABI, or
  native backend lowering exists yet.
- `std/process.lani` and `std/env.lani` seed source-level host ABI declarations
  for process args, exit codes, and environment variables. Their raw extern
  declaration seeds type-check as direct single-file GPU inputs and match the
  direct single-file WASM import shape, but these module files are not normal
  compile-path inputs until GPU module/import resolution exists. Stable string,
  byte-slice, error, capability, and runtime initialization models are still
  missing.
- `std/time.lani` and `std/fs.lani` seed source-level host ABI declarations for
  clocks, sleeping, and basic file operations. Their raw extern declaration
  seeds type-check as direct single-file GPU inputs and match the direct
  single-file WASM import shape, but these module files are not normal
  compile-path inputs yet. Stable path/string/byte-slice
  representations, handle ownership, concrete error types, capability gating,
  native lowering, and host services remain future work.
- `std/net.lani` seeds source-level host ABI declarations for basic TCP and UDP
  operations using opaque handles and raw pointer/length buffers. Its raw
  extern declaration seed type-checks as a direct single-file GPU input and
  matches the direct single-file WASM import shape, but this module file is not
  a normal compile-path input yet. Stable socket address
  types, DNS, blocking mode, error reporting, capability gating, native
  lowering, and host services remain future work.
- `test/assert.lani` has source-level assertion helpers built on the current
  `assert(bool)` builtin. It parses as a source artifact, but importing it
  remains blocked until GPU module/import resolution exists. A real test
  harness, formatted assertion messages, source locations, and panic reporting
  are not implemented yet.
- `i32.lani`, `bool.lani`, and `array_i32_4.lani` keep the older `lstd_`
  compatibility helpers. The flat `i32.lani` and `bool.lani` seeds type-check
  as direct single-file GPU inputs. Const-generic array parameters have limited
  frontend coverage for `[i32; N]`, while concrete `[i32; 4]` identifier
  returns have a bounded GPU type-check slice. Copy-style helpers are closer,
  but fill/reverse remain source-level seeds because array literal returns,
  loops, and backend lowering for array-returning helpers are still incomplete.

Import declarations remain syntax metadata only until the compiler has a real
resolver; GPU type checking rejects them. The accepted type-check module surface
is one leading `module path;` header treated as metadata, same-source qualified
type paths, and same-source qualified function calls whose prefix matches that
module header. External qualified value paths such as `core::i32::helper()` are
still rejected on that path. The old source-level include expander and namespace
rewrite were removed with the CPU prepass. A real module/package model must be
implemented on the GPU-compatible frontend path before `import core::i32;`,
quoted imports, visibility across modules, or `core::i32::helper()` lookup can
be counted as supported.
