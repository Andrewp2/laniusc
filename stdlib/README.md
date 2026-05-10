# Lanius Source Standard Library

This directory contains the initial Lanius standard library as plain `.lani`
source files.

The full desired standard library surface is tracked in
[STANDARD_LIBRARY_SPEC.md](STANDARD_LIBRARY_SPEC.md). The long-term roadmap is
tracked in [PLAN.md](PLAN.md). Compiler and runtime prerequisites for
implementing those layers are tracked in
[LANGUAGE_REQUIREMENTS.md](LANGUAGE_REQUIREMENTS.md).

These files are not auto-imported by the compiler. To use a helper, add explicit
module-style source import lines before the code that calls it:

```lani
import core::i32;
import core::bool;

fn main() {
    return core::i32::abs(-7);
}
```

Module-form helpers live under `stdlib/core/` and use module names such as
`core::i32::abs`. Legacy flat files are still available through quoted imports
and keep the `lstd_` prefix so copied files are less likely to collide with
application functions.

Current scope is intentionally small:

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
  char literals and boolean expressions.
- `core/bool.lani` has module-form boolean combinators and conversions built on
  the current bool expression surface, including `true` and `false` literals.
- `core/array_i32_4.lani` has module-form fixed-size `[i32; 4]` helpers for
  length, first/last element access, lookup, counting, min/max, sum, copy,
  fill, and reverse. It is still a concrete stopgap for helpers that need a
  known length value, loops, or array-valued returns.
- `core/array_i32.lani` has early const-generic `[i32; N]` helpers such as
  `first()` and `get_unchecked()`. This validates named array lengths in
  frontend type checking, but full const evaluation and generic element types
  are still missing. Array-valued helper definitions currently rely on a
  type-check-only erasure path and still do not have backend lowering.
- `core/option.lani` and `core/result.lani` have declaration seeds for the
  generic core sum types. `core/ordering.lani` has the non-generic `Ordering`
  enum plus `compare_i32`. They parse and import, public variants are available
  through module paths such as `core::option::Some`, and bounded frontend
  type-checking accepts generic constructors and helper calls such as
  `is_some`, `is_none`, `unwrap_or`, `is_ok`, and `is_err` in concrete
  contexts. A narrow codegen-only scalar lowering now rewrites the seed
  `Option`, `Result`, and unit-enum shapes to `i32`-backed source after
  precheck. Exhaustive match semantics, full monomorphization, general enum
  layout, and verified backend execution are not implemented yet.
- `core/cmp.lani` has declaration seeds for generic `Eq<T>` and `Ord<T>`
  traits plus bounded `i32` trait impls. `core/hash.lani` similarly seeds a
  generic `Hash<T>` trait and an `i32` impl. This validates `impl Trait for
  Type` parsing, import expansion, conformance precheck, and type-check-only
  method calls. Generic parameter bounds such as `T: core::cmp::Eq<T>` and
  `K: core::cmp::Eq<K> + core::hash::Hash<K>` can drive bounded
  type-check-only method lookup in generic functions. `where` clauses,
  associated items, dictionaries, full trait solving, and backend lowering are
  not implemented yet.
- `core/range.lani` has declaration seeds for `Range<T>`,
  `RangeInclusive<T>`, `RangeFrom<T>`, `RangeTo<T>`, and `RangeFull`, plus
  source-level `i32` helpers for construction, endpoints, emptiness, and
  containment. It also has bounded type-check-only `Range<i32>` impl methods
  for `start`, `end`, `is_empty`, and `contains`. These exercise generic struct
  literals, member access, method calls, and `for` traversal over range-like
  seed structs in concrete contexts, with narrow executable fallback coverage
  for the current `Range<i32>` shape. General range operators, slicing
  integration, full monomorphization, and general backend representation are not
  implemented yet.
- `core/slice.lani` has source-level `[i32]` view helpers such as
  `first_i32`, `get_or_i32`, `contains_i32`, and `sum_i32`. They take length
  explicitly because slice runtime metadata, borrowing, mutation views, and
  backend representation are not implemented yet.
- `core/panic.lani` has source-level `panic()` and `unreachable()` helpers
  built on the current deterministic `assert(false)` failure path. Rich panic
  payloads, formatting, hooks, unwinding, and source locations are not
  implemented yet.
- `core/target.lani` has source-level target capability constants and helpers
  such as `core::target::has_filesystem()` and `core::target::is_wasm()`.
  These are static defaults for the current host-backed test environment; real
  target configuration and compile-time capability evaluation are still missing.
- `alloc/allocator.lani` has source-level allocator ABI declarations for
  allocation, growth, deallocation, and allocation failure hooks. These extern
  signatures parse, import, type-check as calls, and can be lowered as direct
  WASM host imports, but no target runtime implementation, native linker
  integration, heap ownership model, or allocator runtime exists yet.
- `std/io.lani` has source-level host I/O ABI declarations for stdin,
  stdout, stderr, flushing, and a minimal `print_i32` hook. These extern
  signatures parse, import, type-check as calls, and can be lowered as direct
  WASM host imports, but no host runtime, capability gating, string/slice ABI,
  or native backend lowering exists yet.
- `std/process.lani` and `std/env.lani` seed source-level host ABI declarations
  for process args, exit codes, and environment variables. These can lower as
  direct WASM imports, but they are still raw pointer/length hooks until stable
  string, byte-slice, error, capability, and runtime initialization models
  exist.
- `std/time.lani` and `std/fs.lani` seed source-level host ABI declarations for
  clocks, sleeping, and basic file operations. These can lower as direct WASM
  imports, but they are still raw host hooks:
  stable path/string/byte-slice representations, handle ownership, concrete
  error types, capability gating, native lowering, and host services remain
  future work.
- `std/net.lani` seeds source-level host ABI declarations for basic TCP and UDP
  operations using opaque handles and raw pointer/length buffers. These can
  lower as direct WASM imports, but stable socket address types, DNS, blocking
  mode, error reporting, capability gating, native lowering, and host services
  remain future work.
- `test/assert.lani` has source-level assertion helpers built on the current
  `assert(bool)` builtin. It parses and imports, but a real test harness,
  formatted assertion messages, source locations, and panic reporting are not
  implemented yet.
- `i32.lani`, `bool.lani`, and `array_i32_4.lani` keep the older `lstd_`
  compatibility helpers. Const-generic array parameters have limited frontend
  coverage for `[i32; N]`, while concrete `[i32; 4]` array-returning helpers
  are available as source-level seeds for copy/fill/reverse and the default
  WASM/native fallback paths execute concrete fixed-array return values.

Imports are source-level includes expanded before lexing/parsing. Module-style
imports such as `core::i32` resolve through the package stdlib lookup. Quoted
user file imports resolve relative to the importing file; source-only compiler
APIs also look relative to the current working directory and package root.

Imported files may declare `module app::name;`. In that case, source expansion
rewrites module declarations and uses such as `app::name::helper()` to
compiler-private identifiers before lexing. Public declarations are visible
through the module path, and private declarations can be used by other code in
the same imported module. This is still a source-level namespace bridge, not a
full package system.
