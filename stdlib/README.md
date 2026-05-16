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
declarations as source metadata. Path imports resolve only against modules
already supplied in the source pack; the host does not load import closures or
rewrite source. Duplicate or non-leading `module` declarations and non-leading
imports remain rejected so they cannot be silently ignored.
Qualified value paths can pass GPU syntax as HIR evidence. Regular qualified
function calls, qualified extern calls, top-level qualified constants, local or
qualified unit enum variants, and bounded contextual local or qualified generic
enum constructors can type-check when the GPU module/import resolver resolves
the path to a matching declaration. Bounded module-qualified generic calls such as
`core::option::unwrap_or(value, fallback)` can type-check when the return type is
inferred from scalar literal or annotated local arguments through GPU type-ref
metadata. General qualified value paths, non-constructor symbolic generic enum
returns, methods, and broader generic callees remain rejected.

The GPU lexer now has an explicit source-pack upload path for already-supplied
source strings. It concatenates their bytes, uploads `source_file_count`,
`source_file_start`, and `source_file_len`, resets the DFA at GPU-visible file
starts, clamps token starts to file starts after skipped trivia, and writes
per-token `token_file_id` on GPU. The GPU syntax checker uses that sideband to
validate leading `module` and `import` metadata per file. An explicit
source-pack type-check entrypoint records the resident GPU
lexer/parser/type-checker path against source-pack buffers. The rebuilt
foundation follows the paper's name extraction pattern: sort/deduplicate
identifiers into stable ids, build path/module/import/declaration records from
AST/HIR spans, sort module and declaration keys, validate duplicates with
sorted adjacent comparisons, resolve path imports to module ids through a GPU
sorted lookup table, materialize visibility tables, resolve type/value paths,
  and connect narrow HIR consumers for regular/extern qualified function calls,
top-level constants, and unit enum variants. The prior scan-based resolver and the later dense
hash/prefix-scan metadata slice were deleted so neither can be mistaken for the
intended sorted-table design. This still does not load files, follow module
declarations to files, support quoted import loading, support general qualified
value lookup, or make the normal compiler path a package compiler. The normal
compiler now records the LL(1) tree/HIR path. That path receives the
lexer-produced `token_file_id` sideband, validates it during GPU syntax
checking, and feeds it into LL(1) HIR
ownership metadata. The older direct-HIR helper still mirrors the sideband, but
it is not the semantic path to extend.

Module-form helpers live under `stdlib/core/` and use module names such as
`core::i32::abs`, but the normal compiler path does not resolve those imports
yet. The leading module header is metadata for source-shape seeds, not a
visibility or lookup boundary. Legacy flat files keep the `lstd_` prefix so
copied or manually concatenated helpers are less likely to collide with
application functions.

The GPU parser now preserves early HIR evidence for module items, import items,
and complete qualified path spans. Those records feed the current GPU
module-key, import-target, declaration, visibility, and path-resolution tables,
but they do not imply that imports were loaded or that general qualified values
were bound to executable backend lowering.

The LL(1) parser tree path additionally emits parser-owned HIR item-field
metadata from production ids and AST ancestry. It records top-level item facts
for modules, imports, consts, functions, extern functions, structs, enums, and
type aliases while excluding impl methods from top-level function declarations.
Bounded scalar type aliases now have semantic effect through a GPU alias
projection pass that consumes those records and the sorted module/type resolver;
generic aliases and alias chains remain unsupported.

Current scope is intentionally small. Module-form seeds below are parser and
source-pack frontend evidence; regular/extern qualified calls, top-level
constants, bounded scalar aliases, and local or qualified unit enum variants
can type-check through the current resolver when their declaring modules are
explicitly supplied. Flat compatibility seeds without module headers can still
type-check directly. None of this implies import loading, general qualified
value lookup, runtime services, or backend lowering:

- `core/i32.lani` has module-form integer constants and helpers built from
  supported arithmetic and comparison operators, including a source-level
  `saturating_abs` seed.
- `core/u8.lani`, `core/u32.lani`, and `core/i64.lani` seed additional integer
  helper modules with the same source-level shape as `core/i32`; `core/u8`
  adds byte-oriented ASCII classification helpers, and `core/u32` also includes
  source-level `saturating_add` and `saturating_sub` seeds.
- `core/f32.lani` seeds a small floating-point helper module using currently
  parseable float literals, comparisons, and arithmetic.
- `core/char.lani` seeds ASCII classification helpers using currently parseable
  char literals and boolean expressions. `core/char.lani`, `core/u32.lani`, and
  `core/ordering.lani` are parser/source-shape evidence while module headers
  remain blocked in GPU type checking.
- `core/bool.lani` has module-form boolean combinators and conversions built on
  the current bool expression surface, including `true` and `false` literals.
  `core/bool.lani` and `test/assert.lani` remain parser/source-shape seeds
  until module headers type-check through the future resolver.
- `core/array_i32_4.lani` has module-form fixed-size `[i32; 4]` helper seeds
  for length, first/last element access, lookup, counting, min/max, sum, copy,
  fill, and reverse. It is still a concrete stopgap for helpers that need a
  known length value, but the flat and module-form seed files now type-check on
  the GPU. They rely on bounded concrete i32 array signatures, HIR-backed array
  returns, HIR index expressions, while/if control typing, and compound scalar
  assignments. Backend lowering has a bounded GPU WASM slice for `first`,
  `last`, the nested-conditional `get_or` shape, and fixed-scan scalar shapes
  for `contains`, `count`, `index_of_or`, `sum`, `min`, and `max` when a local
  `[i32; 4]` array literal is passed to the resolver-selected helper; broader
  array helpers, loops, and array returns are still not implemented.
- `core/array_i32.lani` has early const-generic `[i32; N]` helpers such as
  `first()` and `get_unchecked()`. The full module-form seed now rejects with
  the rest of module headers, but direct fixtures still validate named array
  lengths in frontend type checking for concrete `i32` elements. A bounded GPU slice now accepts generic
  array/slice declarations and indexed element returns such as
  `fn first<T, const N: usize>(values: [T; N]) -> T { return values[0]; }`,
  plus `ArrayVec<T, const N: usize>` field declarations. Generic array/slice
  calls, generic array returns, local generic array annotations, full const
  evaluation, slice ABI, and array-valued
  backend lowering are still missing.
- Generic function declarations, generic type annotations, and simple generic
  function-call substitution now have GPU type-check coverage for direct calls
  inferred from arguments, including generic forwarding from one generic
  function to another and nested direct helper calls such as `keep(keep(7))`.
  Full monomorphization and backend specialization are separate work.
- `core/option.lani` and `core/result.lani` have declaration seeds for the
  generic core sum types. They now type-check as explicitly supplied source-pack
  seeds through GPU generic enum constructor returns and bounded match payload
  typing. `core/ordering.lani` has the non-generic `Ordering` enum plus
  `compare_i32`; the full module-form seed type-checks when supplied explicitly
  with an app module, including local returns such as `return Less;` in
  `compare_i32` and qualified app uses such as `core::ordering::Less`.
  Bounded GPU generic enum constructor
  payload substitution now works for annotated concrete locals such as
  `Maybe<i32> = Some(1)` and `Result<i32, bool>` constructors.
  The same bounded validator now works through resolver arrays for local and
  qualified source-pack constructors such as `Some(1)` and
  `core::maybe::Some(1)` in annotated concrete local contexts. Symbolic generic
  constructor returns such as
  `fn wrap<T>(value: T) -> Option<T> { return Some(value); }` now type-check
  through return-ref metadata. Bounded stdlib-shaped match typing now covers
  arms such as `Some(inner) -> inner` and `None -> fallback` through HIR match
  spans and type-instance payload substitution. Bounded module-qualified generic
  calls such as `core::option::is_some(value)`,
  `core::option::unwrap_or(value, fallback)`, `core::result::is_ok(value)`, and
  `core::result::unwrap_or(value, 3)` now type-check in an explicitly supplied
  source pack. Bounded backend execution exists for tag-only predicates such as
  `core::option::is_some(value)` / `core::result::is_ok(value)` by consuming HIR
  match metadata, resolver-selected helper calls, and variant ordinals. Payload
  projection helpers such as `unwrap_or` remain blocked until backend lowering
  consumes parser-owned call/constructor argument records and typed payload value
  records instead of token-shaped call syntax. Package/import loading,
  exhaustive match semantics,
  non-constructor symbolic generic returns, full monomorphization, and general
  enum layout remain unsupported.
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
  source-level `i32` helpers for exclusive and inclusive construction,
  endpoints, emptiness, and containment. It also has bounded `Range<i32>` and
  `RangeInclusive<i32>` impl method declarations using value, explicit-type,
  and reference receiver forms. These exercise generic struct declaration,
  receiver, member-access, and `for` syntax in parser/source-shape coverage.
  `self`, `self: Type`, and `&self` receiver forms now parse through the GPU
  frontend, direct `self.field` access type-checks for those receiver spellings
  in direct concrete `Range<i32>` impl fixtures, and concrete inherent method
  calls type-check for direct single-file receivers. The module-form seed now
  type-checks in an explicit source pack, including qualified calls such as
  `core::range::range_i32(1, 4)`, qualified `core::range::Range<i32>`
  annotations, and bounded `Range<i32>` / `RangeInclusive<i32>` method calls on
  annotated receivers through parser/HIR-derived method declaration, call, and
  argument-list records.
  The bounded WASM aggregate path can execute `core::range::range_i32`,
  `start_i32`, and `contains_i32`, plus `Range<i32>` and
  `RangeInclusive<i32>` method bodies for `.start()`, `.end()`, `.is_empty()`,
  and `.contains(value)` when the receiver is an annotated local or a direct
  constructor call result. That lowering consumes GPU aggregate/method metadata
  and does not recognize helper names.
  `&self` does not yet imply a general reference or borrow model. General range
  operators, slicing integration, trait/generic method lookup, private/public
  method visibility enforcement, full monomorphization, and general backend
  representation are not implemented yet.
- `core/slice.lani` has source-level `[i32]` view helpers such as
  `first_i32`, `get_or_i32`, `contains_i32`, and `sum_i32`. Direct `[i32]`
  slice parameter/indexing fixtures have GPU type-check coverage, but the full
  `core/slice.lani` file is still a source seed rather than an accepted stdlib
  module seed. Slice runtime metadata, borrowing, mutation views, and backend
  representation are not implemented yet.
- `core/panic.lani` has source-level `panic()` and `unreachable()` helpers
  built on the current deterministic `assert(false)` failure path. The
  module-form seed now type-checks as an explicitly supplied source-pack seed,
  but assertion/panic helper execution still needs HIR-driven WASM lowering for
  resolver-selected void helpers with typed assertion expression statements and
  void returns. Rich panic payloads, formatting, hooks, unwinding, and source
  locations are not implemented yet.
- `core/target.lani` has source-level target capability constants and helpers
  intended to become paths such as `core::target::has_filesystem()` and
  `core::target::is_wasm()` once module resolution exists. The module-form seed
  now rejects with the module header. These are static defaults for the current
  host-backed test environment; real target configuration and compile-time
  capability evaluation are still missing.
- `alloc/allocator.lani` has source-level allocator ABI declarations for
  allocation, growth, deallocation, and allocation failure hooks. Direct extern
  signatures can type-check as calls in direct single-file fixtures, and bounded
  source-pack fixtures can type-check resolver-backed qualified calls such as
  `alloc::allocator::alloc(16, 4)` when the module is explicitly supplied. No
  quoted import loading, target runtime implementation, native linker
  integration, heap ownership model, allocator runtime, or backend lowering
  exists yet.
- `std/io.lani` has source-level host I/O ABI declarations for stdin,
  stdout, stderr, flushing, and a minimal `print_i32` hook. These extern
  signatures can type-check as calls in direct single-file fixtures, and bounded
  source-pack fixtures can type-check resolver-backed qualified calls such as
  `std::io::flush_stdout()` and `std::io::print_i32(code)` when the module is
  explicitly supplied. No quoted import loading, host runtime, capability
  gating, string/slice ABI, or native/backend lowering exists yet.
- `std/process.lani` and `std/env.lani` seed source-level host ABI declarations
  for process args, exit codes, and environment variables. Their raw extern
  declarations can type-check in direct no-module fixtures and match the direct
  single-file WASM import shape, but these module files now reject with module
  headers until GPU module/import resolution exists. Stable string,
  byte-slice, error, capability, and runtime initialization models are still
  missing.
- `std/time.lani` and `std/fs.lani` seed source-level host ABI declarations for
  clocks, sleeping, and basic file operations. Their raw extern declarations
  can type-check in direct no-module fixtures and match the direct single-file
  WASM import shape, but these module files now reject with module headers.
  Stable path/string/byte-slice
  representations, handle ownership, concrete error types, capability gating,
  native lowering, and host services remain future work.
- `std/net.lani` seeds source-level host ABI declarations for basic TCP and UDP
  operations using opaque handles and raw pointer/length buffers. Its raw
  extern declarations can type-check in direct no-module fixtures and match the
  direct single-file WASM import shape, but this module file now rejects with
  the module header. Stable socket address
  types, DNS, blocking mode, error reporting, capability gating, native
  lowering, and host services remain future work.
- `test/assert.lani` has source-level assertion helpers built on the current
  `assert(bool)` builtin. It type-checks as an explicitly supplied source-pack
  seed, and a bounded HIR-driven GPU WASM pass can execute resolver-selected
  void helpers such as `test::assert::eq_i32` by lowering true assertions to
  normal return and false assertions to a deterministic trap. Importing it
  automatically remains blocked until a real package model exists. A real test
  harness, formatted assertion messages, source locations, and panic reporting
  are not implemented yet.
- `i32.lani`, `bool.lani`, and `array_i32_4.lani` keep the older `lstd_`
  compatibility helpers. The flat `i32.lani` and `bool.lani` seeds type-check
  as direct single-file GPU inputs. The flat `array_i32_4.lani` seed also
  type-checks directly, and `core/array_i32_4.lani` type-checks as an explicit
  source-pack module seed. Const-generic array parameters have limited frontend
  coverage for `[i32; N]`; generic array APIs and backend lowering for
  array-returning helpers are still incomplete. The WASM backend can execute the
  bounded local-literal projection and scalar scan shapes used by
  `core::array_i32_4::first`, `core::array_i32_4::last`,
  `core::array_i32_4::get_or`, `core::array_i32_4::contains`,
  `core::array_i32_4::count`, `core::array_i32_4::index_of_or`, and
  `core::array_i32_4::sum`, `core::array_i32_4::min`, and
  `core::array_i32_4::max` from an explicit source pack.

Import declarations remain explicit metadata: path imports resolve only for
already supplied source-pack modules, and quoted import loading is not
implemented. Leading `module path;` headers can flow through the GPU
module/import resolver. Same-module/source-pack qualified struct/enum type
paths, regular/extern qualified function calls, top-level qualified constants,
local or qualified unit enum variants, and bounded contextual local or qualified
generic enum constructors can type-check through resolver arrays, but general
qualified value paths and symbolic/generic-return enum constructors are still
rejected.
Bounded module-qualified generic calls have source-pack type-check coverage only
for stdlib-shaped scalar/literal argument inference; this is not full
monomorphization or backend specialization.
The old source-level include expander and namespace rewrite were
removed with the CPU prepass. A real module/package model must still be
implemented on the GPU-compatible frontend path before quoted imports,
automatic package loading, or broad `core::*` lookup can be counted as
supported.
