# Standard Library Language Requirements

This audit maps the standard library roadmap in `PLAN.md` to the compiler and
runtime features needed to implement it. It is implementation-facing: each layer
lists what is usable today, what blocks source growth, and what acceptance checks
should prove before the next layer depends on it.

## Already Supported Today

Current source-level stdlib files are plain `.lani` sources that can be included
with explicit source imports such as `import core::i32;` for module-form helpers
or `import "stdlib/i32.lani";` for legacy flat helpers. `tests/stdlib.rs`
verifies that every `stdlib/*.lani` file parses, lowers to HIR, and that
representative imported usage type-checks through the bounded GPU frontend.
`tests/imports.rs` covers stdlib package lookup, relative, duplicate, cyclic
imports, and module import expansion for functions, enums, and structs.

Supported enough for the seed library:

- Global `pub fn` declarations with typed parameters and return types, used by
  `stdlib/i32.lani`, `stdlib/bool.lani`, and `stdlib/array_i32_4.lani`.
- Module-form `core::i32`, `core::u8`, `core::u32`, `core::i64`,
  `core::f32`, `core::char`, `core::bool`, `core::array_i32`, and
  `core::array_i32_4` seed files now expose namespaced helpers such as
  `core::i32::abs()`, `core::u8::is_ascii_digit()`, `core::u32::max()`,
  `core::f32::clamp()`, `core::char::is_ascii_digit()`,
  `core::bool::to_i32()`, `core::array_i32::first()`, and
  `core::array_i32_4::sum()`.
  `core::i32::saturating_abs()`, `core::u32::saturating_add()`, and
  `core::u32::saturating_sub()` provide source-level seeds for part of the
  saturating integer family.
- Module-form `core::option` and `core::result` declaration seeds now expose the
  parseable enum shapes for `Option<T>` and `Result<T, E>`. Module-form
  `core::ordering` exposes the non-generic `Ordering` enum plus a type-checked
  `compare_i32()` helper built from supported enum constructors.
- Module-form `core::cmp` declaration seeds now expose generic `Eq<T>` and
  `Ord<T>` traits plus bounded `i32` trait impls, and `core::hash` exposes a
  generic `Hash<T>` trait plus an `i32` impl. This validates `impl Trait for
  Type` syntax, module import rewriting for trait impl heads, CPU HIR
  conformance precheck, and type-check-only method calls such as
  `left.eq(right)`, `left.lt(right)`, and `value.hash()`. Generic type
  parameter bounds such as `T: core::cmp::Eq<T>` and
  `K: core::cmp::Eq<K> + core::hash::Hash<K>` now parse, lower to HIR, and
  allow bounded CPU precheck lookup for calls inside generic functions.
- Module-form `core::range` declaration seeds now expose the parseable generic
  struct shapes for `Range<T>`, `RangeInclusive<T>`, `RangeFrom<T>`,
  `RangeTo<T>`, and the unit-like `RangeFull` product type. It also includes
  `i32` construction, endpoint, emptiness, and containment helpers that validate
  bounded generic struct literal and member-access type checking in concrete
  contexts, plus bounded type-check-only `Range<i32>` impl methods for
  `start`, `end`, `is_empty`, and `contains`.
- Module-form `core::slice` now exposes source-level `[i32]` view helpers using
  explicit length parameters. This validates slice parameter and indexing
  coverage in the bounded GPU frontend, and fixed arrays can now be passed to
  these helpers through the default WASM/native fallback paths as covered by
  `sample_programs/slice_helpers`. Real slice metadata, borrow semantics, and
  general backend representation are still missing.
- Module-form `core::panic` now exposes source-level `panic()` and
  `unreachable()` helpers by reusing the current `assert(false)` failure path.
  Panic payloads, hooks, unwinding, and source locations are still missing.
- Module-form `core::target` now exposes source-level target capability
  constants and helper functions such as `core::target::has_filesystem()` and
  `core::target::is_wasm()`. These validate namespace import expansion and bool
  constant/function usage, but they are static defaults until the compiler has a
  real target configuration model and compile-time capability evaluation.
- Module-form `alloc::allocator` now exposes source-level extern declarations
  for allocation, reallocation, deallocation, and allocation failure hooks. This
  validates the allocator ABI source shape and frontend call checking, and the
  WASM backend can lower direct calls as imports, but it is not a runtime
  allocator implementation.
- Module-form `std::io` now exposes source-level extern declarations for stdin,
  stdout, stderr, flushing, and a minimal `i32` print hook. This validates a
  host-I/O ABI source shape and frontend call checking, and the WASM backend can
  lower direct calls as imports, but it is not a host runtime implementation.
- Module-form `std::process` and `std::env` now expose source-level extern
  declarations for process args, exit codes, and environment variables. They
  validate host ABI source shapes and namespace import expansion, but stable
  strings, byte slices, errors, runtime initialization, native lowering, and
  implemented host services are still missing.
- Module-form `std::time` and `std::fs` now expose source-level extern
  declarations for clocks, sleeping, and basic file operations. They validate
  additional host ABI source shapes and namespace import expansion, but stable
  paths, strings, byte slices, handles, concrete errors, capability gates, and
  implemented host services are still missing.
- Module-form `std::net` now exposes source-level extern declarations for basic
  TCP and UDP operations. It validates networking host ABI source shapes, but
  stable socket address types, DNS, blocking mode, concrete errors, capability
  gates, native lowering, and implemented host services are still missing.
- Module-form `test::assert` now exposes parseable source-level assertion
  helpers such as `test::assert::is_true()` and `test::assert::eq_i32()` on top
  of the current `assert(bool)` builtin. A harness, formatted diagnostics,
  source locations, and panic reporting are still missing.
- Top-level `module core::name;`, `import core::name;`, and quoted
  `import "path.lani";` items now parse and lower to HIR. Normal compilation
  still expands import directives before parsing. Imported files with a module
  declaration get a source-level namespace bridge: declarations are mangled to
  compiler-private identifiers, calls like `core::i32::abs()` are rewritten
  before lexing, public declarations are visible through the module path, and
  private declarations can be used by other code in the same imported module.
  This does not yet provide full package boundaries.
- Namespaced paths in type expressions, value expressions, struct literals, and
  match patterns now parse and lower to HIR directly. Normal compilation still
  rewrites imported module paths to compiler-private identifiers before GPU
  lexing.
- Top-level primitive `const` items, including public constants for module
  exports, used by `stdlib/i32.lani` for `LSTD_I32_MIN` and `LSTD_I32_MAX`.
- Top-level `enum` declarations with unit variants and tuple payload syntax now
  parse and lower to HIR. Non-generic enum names are recognized as frontend
  types by the GPU type checker, and non-generic unit/tuple variant
  constructors type-check for argument count and field types. Public variants
  of module-form enums are also exported through the source-level namespace
  bridge, so paths such as `core::option::Some` rewrite to compiler-private
  constructor names before GPU lexing. Exhaustive pattern semantics, generic
  enum layout, and backend representations are still missing.
- Generic type parameter syntax on enums and structs, plus generic type-use
  syntax such as `Option<T>` and `Result<T, E>`, now parse and lower to HIR. The
  resident GPU type-check path accepts generic enum/struct declarations for
  `Option<T>`, `Result<T, E>`, and similar declaration seeds. Concrete generic
  type uses such as `Option<i32>` and `Result<i32, bool>` are now accepted in
  function parameters, return types, and local annotations after stdlib module
  import expansion. Generic enum constructor calls now have bounded CPU HIR
  precheck coverage when an expected enum type is available, so
  `Option<i32> = Some(1)`, `return Ok(value)`, and mismatched payload types are
  checked before the resident GPU frontend runs. The type-check path erases
  these generic enum value uses to scalar placeholders after precheck because
  the GPU frontend still erases generic enum arguments. A separate codegen-only
  lowering now rewrites the seed `Option`, `Result`, and all-unit enum shapes
  to `i32`-backed source for backend input. `sample_programs/option_result_helpers`
  verifies the narrow `Option<i32>` and `Result<i32, i32>` helper path on the
  executable WASM and native fallbacks. Full inference without context,
  monomorphization, trait/interface resolution, general layout, and
  exhaustiveness are still missing.
- Generic type parameter syntax on functions, such as `fn first<T>(value: T) ->
  T`, now parses, lowers to HIR, and has frontend GPU type-checker support for
  using `T` consistently in parameter, local, and return type positions inside
  the generic function declaration. Bounded generic function calls now have CPU
  HIR precheck coverage when the result type is expected or inferable from
  arguments, and the type-check-only GPU source erases those calls after
  precheck. This is enough for source-level helpers such as `Option<T>::unwrap_or`
  and `Result<T, E>::unwrap_or` in concrete contexts. Full instantiation,
  monomorphization, full trait/interface resolution, and code generation are
  still missing.
- Generic type parameter bounds such as `fn same<T: Eq<T>>(left: T, right: T)`
  and multiple bounds such as `fn key<K: Eq<K> + Hash<K>>(value: K)` now parse,
  lower to HIR, validate that each named trait exists with the right type
  argument count, and drive bounded CPU method lookup on generic receiver
  parameters. This is a type-check-only frontend feature: `where` clauses,
  associated items, dictionaries/vtables, full solver behavior, and backend
  lowering are still missing. The CPU/HIR frontend and GPU-prepared source path
  normalize adjacent nested generic closers in type contexts, so `Eq<T>>` and
  `Eq<T> + Hash<T>>` work without manual spacing.
- Function, extern function, and trait method parameter lists now accept a
  trailing comma. This keeps long source-level ABI declarations maintainable
  without changing call semantics.
- Const generic parameter syntax in generic parameter lists, such as
  `fn first<T, const N: usize>(values: [T; N]) -> T`, now parses and lowers to
  HIR, and fixed-array lengths may be identifiers as well as integer literals.
  The resident GPU frontend now ignores named array lengths as value expressions
  and caches value parameters after generic parameter lists, so limited helpers
  such as `fn first<const N: usize>(values: [i32; N]) -> i32` type-check and can
  be called with concrete `[i32; 4]` arrays. These names still do not participate
  in const evaluation, monomorphization, or backend layout.
- Top-level `struct` declarations with named fields and generic parameters now
  parse and lower to HIR. Non-generic struct names are recognized as user-defined
  frontend types by the GPU type checker. Bounded CPU HIR precheck now validates
  concrete generic struct literals and member access, then the type-check-only
  GPU source erases those generic struct values and type uses after precheck.
  The default WASM/native fallback paths now have a narrow scalar representation
  for the current two-`i32` `Range<i32>` seed shape so range constructors,
  `start`/`end` member reads, helper calls, and range iteration can execute.
  The WASM/native fallback paths also execute simple non-generic all-scalar
  product values, including local copies, field assignment, flattened
  parameter passing, and flattened return values, as covered by
  `sample_programs/struct_fields`. Full generic struct instantiation, nested or
  heap-backed struct layout, and GPU backend lowering are still missing.
- Named struct literal expressions such as `VecHeader { ptr: 0, len: 0 }` now
  parse, lower to HIR, and type-check against non-generic structs and bounded
  concrete generic struct contexts such as `Range<i32>`. Literal field
  existence, required fields, field value types, member access, field assignment
  targets, and struct function parameter/return types have frontend type-checker
  coverage. Local all-scalar struct literals, copies, field reads, field
  assignments, function parameters, and return values now have executable
  fallback coverage, but nested fields and heap/object layout are still missing.
- Top-level `impl` blocks with optional generic parameters now lex, parse, and
  lower to HIR with method declarations preserved. Bounded CPU HIR precheck
  resolves method calls by using the first declared method parameter as the
  receiver and validating remaining call arguments against the impl target.
  The type-check-only GPU source erases these method calls and strips impl
  blocks after precheck. `self` receiver syntax, visibility enforcement beyond
  import/export preservation, trait-driven method lookup, and general backend
  lowering are still missing. The default WASM/native fallback paths now compile
  impl methods as ordinary functions and lower direct receiver-style calls such
  as `range.start()` for the current source-level method shape.
- Top-level `trait` declarations with optional generic parameters and
  semicolon-terminated method signatures now lex, parse, and lower to HIR.
  Bounded `impl Trait for Type` blocks parse and get CPU HIR conformance
  precheck for required method names, arity, parameter types, and return types
  after trait type substitution. Trait declarations and impl blocks are erased
  from the type-check-only GPU source after precheck. Single trait bounds on
  generic type parameters can drive bounded method lookup during CPU precheck.
  Full trait solving, associated items, vtables/dictionaries, and backend
  lowering are still missing.
- Top-level `type Name = Target;` aliases, including generic and const-generic
  parameter lists, now lex, parse, lower to HIR, and participate in source-level
  module namespace rewriting. After import rewriting, the compiler performs a
  CPU HIR-guided source prepass that expands non-const type alias uses in type
  positions before the resident GPU frontend runs. This covers direct aliases,
  alias chains, imported namespaced aliases, and generic aliases with type
  arguments. Alias declarations are then stripped from the GPU-prepared source
  because their type identity has already been reduced to the target type.
  Const-generic alias instantiation, alias-specific diagnostics, and backend
  type identity beyond this source expansion are still incomplete.
- Top-level `extern "abi" fn name(...) -> Type;` declarations now lex, parse,
  lower to HIR, participate in source-level module namespace rewriting, and
  type-check as callable frontend signatures. The full WASM module emitter can
  lower direct calls to those declarations as host imports for integer-shaped
  arguments and return values, including void imports used as statements. This
  preserves the source shape needed by allocator and host-call ABIs, but native
  lowering, safety rules, a target-specific std runtime ABI, precise integer
  width semantics, and implemented host services are still missing.
- `match (expr) { pattern -> expr, ... }` expressions with identifier,
  tuple-style, wildcard, integer, and boolean patterns now parse and lower to
  HIR. A CPU HIR precheck validates scalar arm result consistency and tuple
  enum pattern bindings for the type-check path, then scalar match expressions
  are erased to dummy expressions before the resident GPU frontend runs.
  Exhaustiveness, guards, borrow-aware bindings, and backend lowering to control
  flow are still missing.
- `i32` arithmetic, comparisons, unary minus, logical operators, assignment, and
  compound assignment, used by `lstd_i32_abs`, `lstd_i32_clamp`, and array
  loops.
- `bool` values produced by comparisons, logical expressions, and direct
  `true`/`false` literals.
- `if`/`else`, `while`, `break`, `continue`, recursion, blocks, and shadowing, as
  shown in `sample_programs/*.lani`.
- `for name in expr { ... }` now lexes, parses, and lowers to HIR, with the
  LL(1) table path accepting simple path iterables such as `for x in values`.
  CPU HIR precheck binds the loop variable for fixed arrays, slices, and
  range-like `Range<T>` seed structs, then the type-check-only GPU source
  rewrites the loop to a non-executed `while` body with a dummy loop binding.
  The current executable WASM/native fallback paths lower fixed-array iteration
  with `break` and `continue`, as covered by `sample_programs/for_array_control`,
  and lower the current `Range<i32>` seed shape as covered by
  `sample_programs/range_sum`. Iterator protocol lookup, borrow semantics,
  executable slice iteration, general range forms, and GPU backend lowering are
  still missing.
- Fixed-size array type syntax, array literals, and indexing for concrete
  arrays, used by `stdlib/array_i32_4.lani` and `sample_programs/array_sum.lani`.
  The limited const-generic `core::array_i32` seed covers scalar element access
  for `[i32; N]`, while the concrete `core::array_i32_4` and compatibility
  `lstd_i32x4_*` seeds still cover helpers that need a known length value such
  as length, first/last, lookup, count, min, max, sum, copy, fill, and reverse.
  The CPU HIR precheck validates concrete array-valued function returns and
  calls, then the type-check-only GPU source erases array-returning signatures
  and calls to scalar or literal placeholders. The default WASM/native fallback
  paths execute concrete fixed-array return values through flattened array
  results as covered by `sample_programs/array_return_helpers`. General GPU
  backend lowering, generic element arrays, and dynamic lengths are still
  missing.
- `str` type annotations are recognized by the GPU type checker and string
  literals have a distinct frontend type. Runtime representation, string
  operations, and backend lowering are still missing.
- `u8`, `u32`, `i64`, `f32`, and `char` names and literals are parseable enough
  for source-level primitive module seeds. The GPU frontend currently collapses
  integer widths into broad signed/unsigned families and float widths into a
  broad float family; precise width semantics, overflow behavior, and backend
  representations are still missing.
- Slice type syntax such as `[i32]` now parses and lowers to HIR, and the
  bounded GPU frontend accepts simple `[i32]` parameters and indexing as used by
  the `core::slice` seed. The default WASM/native fallback paths support a
  bounded fixed-array-to-slice call ABI for the current `[i32]` helper shape.
  It does not yet have runtime metadata, borrow semantics, mutation-view rules,
  or general backend lowering.
- Reference type syntax such as `&i32` and `&[i32]` now parses, lowers to HIR,
  and is accepted by syntax validation as a type form. It does not yet have
  borrow checking, lifetime rules, aliasing rules, or backend representation.
- Lexing/HIR representation for integer, float, string, and char literals.
  Primitive type checking is still much narrower than the final stdlib needs.

Important limitations visible in current files:

- No full package system or target-aware stdlib distribution rules.
  Module/import syntax and a source-level namespace rewrite exist, but names
  still lower to global compiler-private identifiers and `stdlib/README.md`
  documents the temporary `lstd_` prefix for the current seed files.
- No full generic instantiation or const-parameter evaluation.
  `core::array_i32` provides limited `[i32; N]` scalar element-access coverage,
  but helpers that need the numeric value of `N`, other element types, or
  array-valued function returns still need concrete source files. Concrete
  fixed-array return helpers now type-check through CPU precheck plus
  type-check-only erasure and execute through the default WASM/native fallback
  paths, but generic element arrays and dynamic lengths still need real const
  evaluation and layout support.
- `for` loops have bounded type-check-only lowering for arrays, slices, and
  range-like seed structs. Fixed-array iteration now executes through the
  default WASM/native fallback paths, including `break` and `continue`, and the
  current `Range<i32>` seed shape executes through the same fallbacks. Executable
  slice iteration, general range forms, and GPU backend lowering are still
  missing.
- No complete enum/sum type semantics, full struct/product backend representation,
  full trait solving, slice runtime semantics, reference semantics,
  match semantics, or heap
  allocation. Non-generic enum constructors and bounded concrete-context
  generic enum constructors have frontend type-checker coverage, and the
  compile path has a narrow scalar lowering for the current `Option`, `Result`,
  and all-unit enum seeds. This is still short of full `Option<T>` and
  `Result<T, E>` semantics because general layout, exhaustiveness,
  unconstrained inference, and verified backend execution are missing. Generic
  range declarations now have bounded concrete `i32` helper coverage through
  type-check-only generic struct and method-call erasure, plus narrow fallback
  execution for the current `Range<i32>` constructor/member/iteration shape.
  Range operators, slicing integration, general backend representation, and GPU
  backend lowering are still missing.
- `extern fn` declarations have a narrow WASM import-lowering path for direct
  integer-shaped calls. Calls are checked for argument count, argument type, and
  declared return type, but there is still no native lowering, target-specific
  std runtime ABI, allocator ABI, complete import/export linker, precise
  calling-convention model, or implemented host I/O runtime surface.
- No package/prelude mechanism, panic/assert runtime, or formatting runtime.

## Source-Level Seed Library

The seed library is the highest-value near-term layer because it can grow before
runtime work lands.

Strict blockers:

- A real package boundary model beyond the current source-level namespace
  bridge.
- Migration of the remaining flat seed files into module declarations so
  `lstd_` can be retired or isolated behind compatibility shims.
- A stable source fixture path for stdlib tests, extending the current
  `tests/stdlib.rs` and `tests/imports.rs` checks.

Nice-to-have:

- Broader compile-time constant evaluation beyond primitive literal constants.
- Better diagnostics for duplicate names when multiple source files are
  imported.
- Doc examples that can be parsed or compiled as tests.

Acceptance checks:

- A user program can import `core::i32` and `core::bool` explicitly through the
  source-level package lookup.
- Existing `lstd_i32_*`, `lstd_bool_*`, and `lstd_i32x4_*` examples still parse
  and type-check through a compatibility path.
- A stdlib test uses bool literals in a helper and verifies bounded frontend
  type-check success. Full WASM/native codegen checks remain opt-in integration
  tests while the backend path is too slow for the default suite.

## Core Layer

`core` should remain no-heap and no-OS. It includes primitives, fixed arrays,
slices, `Option`, `Result`, `Ordering`, ranges, panic/assert primitives, and
minimal formatting hooks.

Strict blockers:

- Full enum/sum types with payloads for `Option<T>`, `Result<T, E>`, and
  `Ordering`. Declaration syntax, non-generic constructors, namespaced public
  variants, concrete generic annotations, and bounded generic constructor
  prechecking now exist for the type-check path. Generic enum values are still
  erased before GPU type checking. A narrow codegen-only lowering covers the
  current seed shapes, but exhaustiveness analysis, general layout, full
  monomorphization, and verified backend execution are still missing.
- Generics for primitive-independent helpers and generic array/slice algorithms.
  Syntax exists for enum parameters, function parameters, and type uses, and
  generic function declarations have limited frontend type-checker coverage.
  Concrete generic enum/struct annotations type-check in simple signatures and
  locals, bounded generic function calls work in expected or inferable contexts,
  concrete generic struct literals/member access have CPU precheck plus
  type-check-only erasure coverage, and single trait bounds can drive bounded
  method lookup on generic parameters. Full generic type identity and
  instantiation, monomorphization, full trait/interface resolution, and codegen
  support are still missing.
- Full const parameters or equivalent array length abstraction, replacing files
  like `array_i32_4.lani`. Limited `[i32; N]` parameter helpers now type-check,
  but semantic checking, const evaluation, generic element arrays, and codegen
  support are still missing.
- Type alias semantic expansion is now handled as a source prepass for
  non-const alias uses before GPU type checking and backend lowering. Remaining
  gaps are const-generic alias instantiation, richer diagnostics, and any future
  type-identity model that needs aliases preserved past source expansion.
- Borrowed views or references for slices and non-owning APIs. `[i32]`
  parameters and indexing now have source-level seed coverage through
  `core::slice`, and fixed arrays can execute through these helpers in the
  default WASM/native fallback paths. Slice length metadata, mutation views,
  aliasing rules, and general backend lowering are still missing.
- A defined panic lowering path. `assert(bool)` has a minimal builtin lowering
  that traps on WASM and exits nonzero through native lowering, and
  `core::panic` now reuses that path for source-level `panic()` and
  `unreachable()` helpers.
- Integer intrinsics or checked arithmetic primitives for `checked_*`, the full
  `saturating_*` family, wrapping operations, bit counts, rotations, and
  power-of-two helpers. A few source-level saturating seeds now exist, but they
  are not a substitute for target-defined overflow semantics and intrinsics.
- Type-checker and codegen support for all types exposed by `core`; partial
  frontend support for floats, strings, or chars is not enough.

Nice-to-have:

- Traits/interfaces for `Debug` and iterator-like APIs. `Eq<T>`, `Ord<T>`, and
  `Hash<T>` now have bounded source seeds, impl conformance checks, and
  multi-bound method lookup, but not full solver behavior or backend lowering.
- Method syntax for primitive helpers. Bounded impl method calls and
  single-bound trait method calls now type-check, and direct impl method calls
  execute through the default WASM/native fallback paths for simple receiver
  methods. Full trait-directed backend lowering is still missing.
- Compile-time evaluation for simple constants and bounds.
- Unsafe or intrinsic boundaries for unchecked indexing and low-level utilities.

Acceptance checks:

- `Option<i32>` and `Result<i32, i32>` parse, type-check, and compile through
  branch-heavy helper functions.
- One limited const-generic fixed-array helper replaces a concrete
  `array_i32_N` element-access helper in a frontend stdlib fixture.
- Slice `first`, `get_or`, `contains`, and `sum` have source-level `[i32]`
  frontend coverage with explicit length parameters and executable fallback
  coverage through `sample_programs/slice_helpers`. Real `len` metadata and
  general slice backend execution are still missing.
- Assert behavior is deterministic for WASM and native targets; source-level
  `core::panic` currently uses the same failure path, while richer panic
  reporting remains future work.

## Alloc Collections

`alloc` depends on heap allocation but not an OS. It covers `String`, `Vec`,
maps, sets, heaps, arenas, and related owned utilities.

Strict blockers:

- Allocator ABI: allocation, reallocation/growth, deallocation, alignment, and
  allocation failure semantics.
- Usable struct/product types. Non-generic declarations, literals, field access,
  and field-level type checking now have frontend coverage, and simple
  all-scalar local structs execute through the fallback backends. Parameter and
  return passing, nested/heap layout, generic instantiation, and GPU backend
  support are still missing.
- Owned heap pointer/reference representation and lifetime or ownership rules
  sufficient to prevent use-after-free in ordinary library code.
- Generics for `Vec<T>`, maps, sets, queues, and arenas.
- Move/copy/drop semantics for values stored in collections.
- Slice interop for `as_slice`, `as_mut_slice`, sorting, searching, and bulk
  operations.
- Error handling via `Result` for fallible allocation and parsing.

Nice-to-have:

- Allocator traits/interfaces for custom allocators.
- Iterators and closures for `map`, `filter`, `fold`, `extend`, and traversal.
- Hash and ordering traits for map/set APIs.
- Specialized collection forms such as `SmallVec<T, N>`, `ArrayVec<T, N>`, and
  `BitVec`.

Acceptance checks:

- A `Vec<i32>` fixture can push, pop, index, grow past initial capacity, and
  expose a slice.
- `String` stores UTF-8 bytes, grows, appends, and returns length/capacity.
- Allocation failure has a documented, tested path: either `Result` or trap, but
  not silent undefined behavior.
- Collection tests run in a no-OS WASM environment with only allocator imports.

## Std Host APIs

`std` depends on a host environment and should expose files, paths, environment,
process, time, threads, networking, and platform extensions.

Strict blockers:

- Target-specific import/export ABI for WASM and native host calls.
- Stable representations for strings, byte slices, paths, handles, and error
  codes across the Lanius/host boundary.
- `Result` and concrete error types for recoverable host failures.
- Runtime initialization and shutdown hooks for process args, environment,
  standard streams, and allocator setup.
- Capability-gated modules so `std` APIs are unavailable on no-host targets.

Nice-to-have:

- Async or nonblocking I/O model. This should wait until the synchronous host ABI
  is stable.
- Threads, locks, and channels. These depend on a memory model and should not
  block basic file/process/time APIs.
- Platform extension namespaces.

Acceptance checks:

- A WASM embedding can pass process args, print to stdout/stderr, read an env
  variable, and return an exit code through documented imports.
- File read/write tests round-trip bytes and report host errors through
  `Result`.
- `core` and `alloc` tests still pass with `std` disabled.

## Test And GPU Layers

`test` is for assertions, golden tests, fuzzing, property tests, benchmarks, and
temporary resources. `gpu` should expose explicit GPU-friendly primitives such as
scan/reduce, partition/compact, buffer layout helpers, dispatch helpers, and
CPU/GPU parity validation.

Strict blockers for `test`:

- Panic/assert runtime and source location metadata. A source-level
  `test::assert` seed exists for bool and `i32` checks, but it only wraps the
  current `assert(bool)` builtin.
- Harness discovery or explicit test registration.
- Formatting enough to print assertion failures.
- Host APIs for temporary files and clocks when those helpers are enabled.

Nice-to-have for `test`:

- Property-test shrinking, fuzz harness integration, and benchmark statistics.
- Golden file helpers after `std::fs` and stable strings exist.

Strict blockers for `gpu`:

- A stable host/device buffer ABI and layout rules.
- Explicit address spaces or buffer view types for GPU data.
- Kernel/compute dispatch declaration model.
- Deterministic CPU fallback or parity harness for each primitive.
- Error reporting for device availability, shader compilation, dispatch, and
  readback.

Nice-to-have for `gpu`:

- Generic scan/reduce over operation traits.
- Integration with future collection slices.
- Profiling hooks. Existing repo GPU infrastructure already has pass-level
  timing and wave-sized shader audits in `tests/gpu_audit.rs`, which can inform
  this layer.

Acceptance checks:

- `test::assert_eq` reports expected/actual values for `i32` and bool without
  requiring heap allocation; richer formatting can come later.
- A golden-test helper works once `std::fs` and strings are available.
- A `gpu::scan_i32` fixture validates CPU/GPU parity over several sizes and has
  explicit failure reporting for missing GPU support.

## Realistic Implementation Order

1. Stabilize the source seed.
   Acceptance: existing `tests/stdlib.rs` still passes; source import coverage
   exists for stdlib and relative files; bool literal coverage exists in
   frontend, type-checker, and codegen tests.

2. Add modules/imports and namespace visibility.
   Acceptance: stdlib helpers are imported by module path; compatibility names
   either remain available or have a documented migration test.

3. Add enum/sum types and minimal generics.
   Acceptance: `Option<T>`, `Result<T, E>`, and `Ordering` are implemented in
   source and used by primitive helpers.

4. Add const parameters or array length abstraction plus slices/references.
   Acceptance: generic array/slice helpers replace the concrete
   `array_i32_4.lani` pattern for at least one checked fixture.

5. Add panic/assert and primitive intrinsics.
   Acceptance: bounds/assert failures have deterministic target behavior, and
   checked/saturating/wrapping integer helpers compile without source-level
   overflow tricks.

6. Add allocator ABI, structs, and ownership/drop semantics.
   Acceptance: `Vec<T>` and `String` pass no-OS WASM tests with explicit
   allocation failure behavior.

7. Add host ABI and `std` capability gating.
   Acceptance: stdout, args, env, file bytes, time, and exit-code fixtures pass
   on supported host targets while `core` and `alloc` remain host-independent.

8. Add harness and GPU library layers.
   Acceptance: assertions, golden tests, and at least one GPU scan/reduce
   primitive are tested with deterministic CPU/GPU parity checks.
