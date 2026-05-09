# Standard Library Language Requirements

This audit maps the standard library roadmap in `PLAN.md` to the compiler and
runtime features needed to implement it. It is implementation-facing: each layer
lists what is usable today, what blocks source growth, and what acceptance checks
should prove before the next layer depends on it.

## Already Supported Today

Current source-level stdlib files are plain `.lani` sources that must be
concatenated ahead of user code. `tests/stdlib.rs` verifies that every
`stdlib/*.lani` file parses, lowers to HIR, and that representative concatenated
usage compiles to WASM.

Supported enough for the seed library:

- Global `pub fn` declarations with typed parameters and return types, used by
  `stdlib/i32.lani`, `stdlib/bool.lani`, and `stdlib/array_i32_4.lani`.
- `i32` arithmetic, comparisons, unary minus, logical operators, assignment, and
  compound assignment, used by `lstd_i32_abs`, `lstd_i32_clamp`, and array
  loops.
- `bool` values produced by comparisons and logical expressions. There are no
  bool literals yet, so `stdlib/bool.lani` and `lstd_i32x4_contains` return
  comparisons such as `1 == 1` instead of `true`.
- `if`/`else`, `while`, `break`, `continue`, recursion, blocks, and shadowing, as
  shown in `sample_programs/*.lani`.
- Fixed-size array type syntax, array literals, and indexing for concrete
  arrays, used by `stdlib/array_i32_4.lani` and `sample_programs/array_sum.lani`.
- Lexing/HIR representation for integer, float, string, and char literals, but
  only integer and bool-oriented source patterns are exercised by the current
  stdlib.

Important limitations visible in current files:

- No modules or imports. `stdlib/README.md` documents concatenation and the
  temporary `lstd_` prefix.
- No generics or const parameters. `stdlib/array_i32_4.lani` is tied to
  `[i32; 4]`; every other element type or length would need another source file.
- No enum/sum types, structs, methods, traits/interfaces, slices, references, or
  heap allocation. These block `Option`, `Result`, `String`, `Vec`, maps, and
  most ergonomic APIs from `PLAN.md`.
- No package/prelude mechanism, target-specific std runtime ABI, allocator ABI,
  panic/assert runtime, formatting runtime, or host I/O API surface.

## Source-Level Seed Library

The seed library is the highest-value near-term layer because it can grow before
runtime work lands.

Strict blockers:

- Module/import syntax and package lookup, so users can write explicit imports
  instead of concatenating files.
- Name visibility and namespace rules, so `lstd_` can be retired or isolated
  behind compatibility shims.
- Bool literals, so bool helpers and tests can use `true` and `false` directly.
- A stable source fixture path for stdlib tests, extending the current
  `tests/stdlib.rs` concatenation check.

Nice-to-have:

- `const` values for primitive limits, array lengths, and module constants.
- Better diagnostics for duplicate names when multiple source files are
  concatenated or imported.
- Doc examples that can be parsed or compiled as tests.

Acceptance checks:

- A user program can import `core::i32` and `core::bool` explicitly without
  source concatenation.
- Existing `lstd_i32_*`, `lstd_bool_*`, and `lstd_i32x4_*` examples still compile
  through a compatibility path.
- A stdlib test uses bool literals in a helper and verifies both WASM output and
  type-check success.

## Core Layer

`core` should remain no-heap and no-OS. It includes primitives, fixed arrays,
slices, `Option`, `Result`, `Ordering`, ranges, panic/assert primitives, and
minimal formatting hooks.

Strict blockers:

- Enum/sum types with payloads for `Option<T>`, `Result<T, E>`, and `Ordering`.
- Generics for primitive-independent helpers and generic array/slice algorithms.
- Const parameters or equivalent array length abstraction, replacing files like
  `array_i32_4.lani`.
- Borrowed views or references for slices and non-owning APIs.
- A defined panic/assert lowering path, even if the first implementation traps.
- Integer intrinsics or checked arithmetic primitives for `checked_*`,
  `saturating_*`, wrapping operations, bit counts, rotations, and power-of-two
  helpers.
- Type-checker and codegen support for all types exposed by `core`; parse-only
  support for floats, strings, or chars is not enough.

Nice-to-have:

- Traits/interfaces for `Eq`, `Ord`, `Hash`, `Debug`, and iterator-like APIs.
- Method syntax for primitive helpers.
- Compile-time evaluation for simple constants and bounds.
- Unsafe or intrinsic boundaries for unchecked indexing and low-level utilities.

Acceptance checks:

- `Option<i32>` and `Result<i32, i32>` parse, type-check, and compile through
  branch-heavy helper functions.
- One generic fixed-array helper replaces a concrete `array_i32_N` helper in a
  test fixture.
- Slice `len`, `get`, and `first` work without heap allocation.
- Panic/assert behavior is deterministic for WASM and native targets.

## Alloc Collections

`alloc` depends on heap allocation but not an OS. It covers `String`, `Vec`,
maps, sets, heaps, arenas, and related owned utilities.

Strict blockers:

- Allocator ABI: allocation, reallocation/growth, deallocation, alignment, and
  allocation failure semantics.
- Owned heap pointer/reference representation and lifetime or ownership rules
  sufficient to prevent use-after-free in ordinary library code.
- Struct/product types for collection layouts such as pointer, length, and
  capacity.
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

- Panic/assert runtime and source location metadata.
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
   Acceptance: existing `tests/stdlib.rs` still passes; add bool literal coverage
   once literals land; keep source concatenation documented until imports exist.

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
