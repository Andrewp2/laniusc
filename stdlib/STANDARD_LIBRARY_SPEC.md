# Lanius Standard Library Specification

This document is the canonical target inventory for the Lanius standard
library. It describes the whole library we want to grow into once the language,
compiler, and runtime are capable of supporting it. It is intentionally broader
than the current source-level seed files in this directory, and it should be
updated whenever a new standard-library idea becomes part of the target design.

The short version:

- `core` is always available and has no heap or OS dependency.
- `alloc` requires heap allocation but no OS.
- `std` requires a host environment.
- `test` provides assertions, harnesses, fuzzing, property tests, and
  benchmarks.
- `gpu` provides explicit data-parallel primitives and validation support.
- Compiler-oriented utilities are first-class because Lanius should be a good
  language for building compilers, build tools, and GPU tooling.
- Some useful libraries should stay outside the core distribution until their
  contracts are clear. Cryptography, TLS, full Unicode normalization, async
  runtimes, and higher-level protocols should start as carefully reviewed
  optional packages unless the language grows a strong reason to bless one
  implementation.

The current implementation is only a seed. Today, `stdlib/*.lani` files are
included explicitly before user code and still use `lstd_` prefixes to avoid
name collisions. This spec describes the long-term desired shape.

## Design Principles

- Keep the library layered. No-heap, no-OS APIs belong in `core`; heap-backed
  APIs belong in `alloc`; host APIs belong in `std`.
- Make allocation visible. APIs that allocate should say so through type,
  module, or naming.
- Make failure visible. Recoverable failure should use `Result`; programmer
  bugs and violated preconditions may use `panic` or `assert`.
- Keep target requirements explicit. Embedded, WASM, native, and GPU-capable
  targets should be able to opt into only what they support.
- Prefer deterministic behavior. This matters for compilers, reproducible
  builds, tests, and GPU parity.
- Keep compatibility promises honest. Experimental APIs should be marked as
  experimental until the language and runtime underneath them are stable.
- Do not rush cryptography, async, or unsafe low-level APIs into the stable
  standard library before the language can express their contracts clearly.

## Library Layers

### `core`

`core` is always available. It should not require a heap, host calls, file
descriptors, threads, clocks, environment variables, or process APIs.

Expected contents:

- Primitive helpers.
- `bool`, integer, float, `char`, and byte helpers.
- `Option<T>`, `Result<T, E>`, `Ordering`.
- Fixed arrays, slices, ranges, tuples, and basic memory utilities.
- Panic/assert primitives.
- Minimal formatting hooks that can write into caller-provided buffers.
- Basic traits/interfaces once the language has them.
- Compiler intrinsics and target-independent low-level utilities.

### `alloc`

`alloc` requires heap allocation but not an OS.

Expected contents:

- `String`, owned byte buffers, and string builders.
- `Vec`, `VecDeque`, `BinaryHeap`, maps, sets, and bit vectors.
- Arenas, bump allocators, slabs, slot maps, and interning utilities.
- Reference-counted or owned heap utilities if the ownership model supports
  them.
- Allocator interfaces and fallible allocation paths.

### `std`

`std` requires a host environment.

Expected contents:

- Standard input, output, and error.
- Files, directories, paths, and metadata.
- Program arguments, environment variables, exit codes, and process spawning.
- Time, clocks, sleep, and timers.
- Threads, locks, atomics, once cells, lazy initialization, and channels.
- Networking.
- Platform-specific extension points.

### `test`

`test` is available to tests, examples, fuzzers, and benchmarks.

Expected contents:

- Assertions and expected-failure helpers.
- Test harness registration and discovery.
- Snapshot and golden-file helpers.
- Temporary files and directories.
- Property testing and shrinking.
- Fuzz harness support.
- Benchmark harness support.

### `gpu`

`gpu` is optional and explicit. It should expose data-parallel primitives and
host/device interop support without pretending every target has a GPU.

Expected contents:

- Buffer layout helpers.
- Compute dispatch helpers.
- Prefix scan, segmented scan, reduce, compact, scatter/gather, histogram, and
  radix-sort primitives.
- CPU fallback or CPU/GPU parity testing hooks.
- Device availability and shader/dispatch error reporting.

### Optional Distribution Packages

Some packages can ship with the standard distribution without being part of the
default language surface. These should have clear target requirements and
versioning, and they should be easy to omit from embedded or no-host builds.

Candidates:

- `diagnostic`, `source_map`, and related compiler-tooling packages.
- `json`, `csv`, `toml`, and compact binary encoding packages.
- `regex`, once the language can support a robust implementation.
- `url`, `uuid`, checksums, and compression.
- Full Unicode tables, normalization, and locale-aware text processing.
- Higher-level network protocols such as HTTP.
- Cryptography and TLS only after careful API and implementation review.

## Module Map

The eventual module tree should look roughly like this. Names can change, but
the responsibilities should remain clear.

### Core Modules

- `core::prelude`
- `core::bool`
- `core::i8`, `core::i16`, `core::i32`, `core::i64`, `core::i128`
- `core::u8`, `core::u16`, `core::u32`, `core::u64`, `core::u128`
- `core::usize`, `core::isize`
- `core::f32`, `core::f64`
- `core::char`
- `core::byte`
- `core::ascii`
- `core::utf8`
- `core::option`
- `core::result`
- `core::ordering`
- `core::range`
- `core::array`
- `core::slice`
- `core::tuple`
- `core::mem`
- `core::ptr`, only when the language has a defined unsafe boundary.
- `core::marker`, for zero-sized marker types and marker traits.
- `core::ops`, for operator traits/interfaces if the language exposes them.
- `core::iter`, once iterator traits/interfaces exist.
- `core::num`, for shared numeric helpers.
- `core::math`, for no-heap math constants and scalar math functions.
- `core::convert`
- `core::cmp`
- `core::hash`
- `core::fmt`
- `core::panic`
- `core::intrinsics`
- `core::target`

### Alloc Modules

- `alloc::vec`
- `alloc::vec_deque`
- `alloc::string`
- `alloc::bytes`
- `alloc::array_vec`
- `alloc::small_vec`
- `alloc::box`
- `alloc::rc`, if reference counting is supported.
- `alloc::arc`, if atomic reference counting is supported.
- `alloc::binary_heap`
- `alloc::hash_map`
- `alloc::hash_set`
- `alloc::btree_map`
- `alloc::btree_set`
- `alloc::bit_vec`
- `alloc::arena`
- `alloc::bump`
- `alloc::slab`
- `alloc::slot_map`
- `alloc::interner`
- `alloc::graph`
- `alloc::rope`, if text-heavy tooling needs it.

### Std Modules

- `std::prelude`
- `std::io`
- `std::fs`
- `std::path`
- `std::env`
- `std::process`
- `std::time`
- `std::thread`
- `std::sync`
- `std::atomic`
- `std::net`
- `std::dns`
- `std::random`
- `std::os`
- `std::ffi`
- `std::terminal`
- `std::logging`
- `std::backtrace`
- `std::async`, after the async model is defined.

### Test Modules

- `test::assert`
- `test::harness`
- `test::snapshot`
- `test::golden`
- `test::prop`
- `test::fuzz`
- `test::bench`
- `test::temp`
- `test::mock`
- `test::coverage`, if coverage instrumentation becomes available.

### GPU Modules

- `gpu::buffer`
- `gpu::layout`
- `gpu::dispatch`
- `gpu::scan`
- `gpu::reduce`
- `gpu::compact`
- `gpu::sort`
- `gpu::histogram`
- `gpu::parity`
- `gpu::atomics`
- `gpu::profiler`

### Tooling Modules

These may live under `std`, `alloc`, or a future `compiler` package, but the
standard distribution should include them because Lanius is expected to build
compiler-like tools well.

- `diagnostic`
- `source_map`
- `span`
- `symbol`
- `arena`
- `index_vec`
- `bit_set`
- `graph`
- `work_queue`
- `lexer`
- `parser`
- `cfg`
- `dataflow`
- `intern`

## Prelude

The prelude should stay small and stable. It should make ordinary code pleasant
without hiding large modules or surprising target requirements.

Candidate `core::prelude` items:

- `Option`
- `Some`
- `None`
- `Result`
- `Ok`
- `Err`
- `Ordering`
- `Less`
- `Equal`
- `Greater`
- `Range` types and range constructors.
- `assert`
- Primitive conversion traits or functions.
- `Iterator` family, once available.
- `Eq`, `Ord`, `Hash`, `Debug`, `Display`, once traits/interfaces exist.

Candidate `std::prelude` additions:

- `print` and `println`, if formatting and host output exist.
- Common I/O result aliases.
- Common path and environment aliases only if they do not pollute names.

## Error Handling

The library should standardize failure around `Result<T, E>` for recoverable
errors and panic/assert for bugs or violated preconditions.

Core error families:

- `ParseError`
- `Utf8Error`
- `BoundsError`
- `ConversionError`
- `OverflowError`
- `AllocError`
- `IoError`
- `PathError`
- `TimeError`
- `ProcessError`
- `NetError`
- `GpuError`

Rules:

- Checked operations return `Option` or `Result`.
- Panicking operations are named plainly when they match ordinary expectations,
  like indexing, but must have checked alternatives.
- Unchecked operations must be named `unchecked_*` and require an explicit unsafe
  boundary once the language supports one.
- Allocation failure must never become silent memory corruption.

## Panic, Debug, And Backtrace

Panic is for bugs and violated preconditions, not ordinary recoverable errors.

Expected APIs:

- `panic`
- `assert`
- `assert_eq`
- `debug_assert`
- Source location capture when available.
- Panic message formatting once formatting exists.
- Target-specific panic hooks.
- Backtrace capture in host builds when supported.
- Trap or abort behavior for minimal targets.

Expected policy:

- `core` can expose panic/assert declarations and target-independent contracts.
- `std` can install richer hooks that write to stderr or capture backtraces.
- Panics across FFI boundaries require an explicit policy and should default to
  aborting or trapping until unwinding semantics are specified.

## Primitive APIs

Every primitive type should have a coherent helper module. These helpers can be
implemented as functions first, then methods once method syntax exists.

### Bool

Types:

- `bool`

Expected APIs:

- `not`
- `and`
- `or`
- `xor`
- `eq`
- `ne`
- `to_i32`
- `from_i32`
- `then`
- `then_some`
- `select`, returning one of two values without control-flow boilerplate.

### Signed Integers

Types:

- `i8`
- `i16`
- `i32`
- `i64`
- `i128`
- `isize`

Expected constants:

- `MIN`
- `MAX`
- `BITS`
- `BYTES`

Expected APIs:

- `min`
- `max`
- `clamp`
- `abs`
- `checked_abs`
- `signum`
- `checked_add`
- `checked_sub`
- `checked_mul`
- `checked_div`
- `checked_rem`
- `saturating_add`
- `saturating_sub`
- `saturating_mul`
- `wrapping_add`
- `wrapping_sub`
- `wrapping_mul`
- `overflowing_add`
- `overflowing_sub`
- `overflowing_mul`
- `rotate_left`
- `rotate_right`
- `count_ones`
- `count_zeros`
- `leading_zeros`
- `trailing_zeros`
- `is_power_of_two`
- `next_power_of_two`
- `checked_next_power_of_two`
- `to_unsigned`
- `try_from_unsigned`
- `parse`
- `format_decimal`
- `format_hex`
- `format_binary`
- `format_octal`

### Unsigned Integers

Types:

- `u8`
- `u16`
- `u32`
- `u64`
- `u128`
- `usize`

Expected constants:

- `MIN`
- `MAX`
- `BITS`
- `BYTES`

Expected APIs:

- `min`
- `max`
- `clamp`
- `checked_add`
- `checked_sub`
- `checked_mul`
- `checked_div`
- `checked_rem`
- `saturating_add`
- `saturating_sub`
- `saturating_mul`
- `wrapping_add`
- `wrapping_sub`
- `wrapping_mul`
- `overflowing_add`
- `overflowing_sub`
- `overflowing_mul`
- `rotate_left`
- `rotate_right`
- `count_ones`
- `count_zeros`
- `leading_zeros`
- `trailing_zeros`
- `is_power_of_two`
- `next_power_of_two`
- `checked_next_power_of_two`
- `to_signed`
- `try_from_signed`
- `parse`
- `format_decimal`
- `format_hex`
- `format_binary`
- `format_octal`

### Floats

Types:

- `f32`
- `f64`

Expected constants:

- `MIN`
- `MAX`
- `INFINITY`
- `NEG_INFINITY`
- `NAN`
- `EPSILON`

Expected APIs:

- `min`
- `max`
- `clamp`
- `abs`
- `floor`
- `ceil`
- `round`
- `trunc`
- `fract`
- `sqrt`
- `pow`
- `sin`
- `cos`
- `tan`
- `asin`
- `acos`
- `atan`
- `atan2`
- `is_nan`
- `is_finite`
- `is_infinite`
- `is_normal`
- `signum`
- `copysign`
- `parse`
- `format`

### Char

Types:

- `char`, representing a Unicode scalar value.

Expected APIs:

- `from_u32`
- `to_u32`
- `is_ascii`
- `is_ascii_digit`
- `is_ascii_hexdigit`
- `is_ascii_alphabetic`
- `is_ascii_alphanumeric`
- `is_ascii_whitespace`
- `to_ascii_lowercase`
- `to_ascii_uppercase`
- `is_digit`
- `to_digit`
- `from_digit`
- `len_utf8`
- `encode_utf8`
- `decode_utf8`
- `escape_debug`

Full Unicode properties and normalization should be optional or staged; ASCII
and UTF-8 correctness are the required baseline.

### Bytes

Types:

- `u8`
- `byte`, if the language distinguishes bytes from `u8`.

Expected APIs:

- ASCII classification.
- Hex encoding and decoding.
- Base64 encoding and decoding.
- Byte-slice comparison.
- Byte searching.

## Numeric And Math APIs

Numeric helpers should be split between primitive-specific modules and shared
math modules. Scalar math can live in `core` when it does not require allocation
or host services; larger numeric types may live in `alloc` or optional packages.

Core numeric types and concepts:

- Fixed-width signed integers.
- Fixed-width unsigned integers.
- Pointer-sized integers.
- Floating-point numbers.
- Non-zero integer wrappers, if useful for layout optimizations.
- Numeric limits and classification.
- Checked, wrapping, saturating, and overflowing arithmetic families.
- Explicit casts and fallible conversions.

Core math constants:

- `PI`
- `TAU`
- `E`
- `FRAC_PI_2`
- `FRAC_PI_4`
- `SQRT_2`
- `LN_2`
- `LN_10`

Expected math APIs:

- Integer absolute value, gcd, lcm, exponentiation, and modular arithmetic.
- Floating-point roots, powers, logarithms, trigonometry, and classification.
- Min/max/clamp helpers.
- Rounding and decomposition helpers.
- Simple slice statistics such as sum, mean, min, max, and variance.

Optional or later numeric packages:

- `BigInt`
- `BigUint`
- `BigDecimal` or decimal fixed-point.
- Rational numbers.
- Complex numbers.
- Matrix/vector math for graphics or scientific work.

## Sum Types

### Option

`Option<T>` represents an optional value.

Variants:

- `Some(T)`
- `None`

Expected APIs:

- `is_some`
- `is_none`
- `unwrap`
- `expect`
- `unwrap_or`
- `unwrap_or_else`
- `map`
- `and_then`
- `or`
- `or_else`
- `filter`
- `take`
- `replace`
- `as_ref`
- `as_mut`
- `ok_or`
- `ok_or_else`

### Result

`Result<T, E>` represents recoverable success or failure.

Variants:

- `Ok(T)`
- `Err(E)`

Expected APIs:

- `is_ok`
- `is_err`
- `unwrap`
- `expect`
- `unwrap_err`
- `expect_err`
- `unwrap_or`
- `unwrap_or_else`
- `map`
- `map_err`
- `and_then`
- `or`
- `or_else`
- `as_ref`
- `as_mut`
- `ok`
- `err`

### Ordering

`Ordering` represents comparison results.

Variants:

- `Less`
- `Equal`
- `Greater`

Expected APIs:

- `reverse`
- `then`
- `then_with`
- `is_less`
- `is_equal`
- `is_greater`

## Comparison, Hashing, And Conversion

Expected traits/interfaces once available:

- `Eq`
- `PartialEq`, if partial equality is modeled.
- `Ord`
- `PartialOrd`, if partial ordering is modeled.
- `Hash`
- `Hasher`
- `Debug`
- `Display`
- `Default`
- `Clone`
- `Copy`
- `Drop`
- `From`
- `Into`
- `TryFrom`
- `TryInto`

Expected helpers:

- `compare`
- `min`
- `max`
- `clamp`
- `min_by`
- `max_by`
- `min_by_key`
- `max_by_key`
- Hash combine utilities.
- Deterministic hashing utilities.

## Ranges

Types:

- `Range<T>`, for `start..end`.
- `RangeInclusive<T>`, for `start..=end`.
- `RangeFrom<T>`.
- `RangeTo<T>`.
- `RangeToInclusive<T>`.
- `RangeFull`.

Expected APIs:

- `contains`
- `is_empty`
- `len`, for countable integer ranges.
- Integer iteration.
- Slice indexing integration.
- Checked construction for invalid ranges when relevant.

## Arrays And Slices

Fixed arrays belong in `core`. Slices are the shared view over contiguous
memory.

Expected fixed-array APIs:

- `len`
- Checked indexing.
- Unchecked indexing through an unsafe boundary.
- `first`
- `last`
- `fill`
- `copy`
- `clone`
- `swap`
- `reverse`
- `rotate_left`
- `rotate_right`
- `map`
- `fold`
- `as_slice`
- `as_mut_slice`

Expected slice APIs:

- `len`
- `is_empty`
- `first`
- `last`
- `get`
- `get_mut`
- `split_at`
- `split_first`
- `split_last`
- `chunks`
- `chunks_exact`
- `windows`
- `contains`
- `starts_with`
- `ends_with`
- `find`
- `binary_search`
- `sort_unstable`
- `sort_stable`
- `dedup`
- `partition`
- `copy_from_slice`
- `fill`
- `swap`
- `reverse`
- `rotate_left`
- `rotate_right`

Early Lanius may use concrete generated modules like `array_i32_4`. Long-term,
those should collapse into generic array and slice APIs with const parameters or
an equivalent length abstraction.

## Strings And Text

Strings should be UTF-8 by default.

Types:

- `str`, a borrowed UTF-8 string slice.
- `String`, an owned growable UTF-8 string.
- `StringBuilder`, if repeated formatting/appending needs a dedicated type.
- `Utf8Error`.
- `Bytes` or `ByteString` for non-UTF-8 data.

Expected `str` APIs:

- `len_bytes`
- `is_empty`
- `as_bytes`
- `chars`
- `starts_with`
- `ends_with`
- `contains`
- `find`
- `rfind`
- `split`
- `split_once`
- `lines`
- `trim`
- `trim_start`
- `trim_end`
- `strip_prefix`
- `strip_suffix`
- `parse_bool`
- `parse_i32`
- `parse_u32`
- `parse_f32`
- `parse_f64`
- `escape_debug`

Expected `String` APIs:

- `new`
- `with_capacity`
- `from_str`
- `len`
- `capacity`
- `is_empty`
- `clear`
- `push_char`
- `push_str`
- `insert`
- `remove`
- `replace`
- `reserve`
- `try_reserve`
- `shrink_to_fit`
- `as_str`
- `as_bytes`
- `into_bytes`

Text support should include:

- ASCII helpers.
- UTF-8 validation.
- Unicode scalar iteration.
- Debug escaping.
- Formatting.
- Unicode normalization later as an optional package or staged module.

## Formatting And Parsing

Formatting should be explicit and allocation-aware.

Expected capabilities:

- Format to a writer.
- Format into a caller-provided buffer.
- Format into a `String`.
- Debug formatting.
- Display formatting.
- Integer formatting.
- Float formatting.
- Bool formatting.
- Char and string escaping.
- Parse primitives from strings and byte slices.

Formatting should not require macros initially. A builder-style API is enough
until macros or compile-time formatting exist.

## Collections

### Vec

`Vec<T>` is the standard growable array.

Expected APIs:

- `new`
- `with_capacity`
- `len`
- `capacity`
- `is_empty`
- `push`
- `try_push`
- `pop`
- `insert`
- `remove`
- `swap_remove`
- `clear`
- `reserve`
- `try_reserve`
- `shrink_to_fit`
- `as_slice`
- `as_mut_slice`
- `extend`
- `append`
- `retain`
- `sort`
- `sort_by`
- `binary_search`

### Fixed-Capacity And Compact Vectors

Types:

- `ArrayVec<T, N>`, fixed-capacity stack storage.
- `SmallVec<T, N>`, inline storage with heap spillover.
- `BitVec`, packed booleans.
- `Bytes`, owned byte buffer.

Expected APIs:

- Construction with capacity.
- Checked push.
- Pop.
- Slice view.
- Clear.
- Extend.
- Conversion to `Vec` when heap-backed storage exists.

### VecDeque, Queue, And Stack

Types:

- `VecDeque<T>`
- `Queue<T>`, possibly a thin wrapper or alias.
- `Stack<T>`, possibly a thin wrapper or alias.

Expected `VecDeque` APIs:

- `new`
- `with_capacity`
- `len`
- `is_empty`
- `push_front`
- `push_back`
- `pop_front`
- `pop_back`
- `front`
- `front_mut`
- `back`
- `back_mut`
- `rotate_left`
- `rotate_right`
- `clear`

### BinaryHeap

`BinaryHeap<T>` provides a priority queue.

Expected APIs:

- `new`
- `with_capacity`
- `push`
- `pop`
- `peek`
- `len`
- `is_empty`
- `clear`
- `from_vec`
- `into_vec`
- `into_sorted_vec`

Support min-heap and max-heap behavior through ordering adapters.

### HashMap And HashSet

Types:

- `HashMap<K, V>`
- `HashSet<T>`
- `HashBuilder`
- `Hasher`

Expected APIs:

- `new`
- `with_capacity`
- `len`
- `is_empty`
- `contains_key`
- `get`
- `get_mut`
- `insert`
- `remove`
- `entry`
- `keys`
- `values`
- `iter`
- `iter_mut`
- `clear`
- `reserve`
- `try_reserve`

Hashing policy:

- Provide a fast deterministic hasher for compiler/tooling workloads.
- Provide a randomized or DoS-resistant hasher for externally supplied keys.
- Make hasher choice explicit when behavior or security matters.

### BTreeMap And BTreeSet

Types:

- `BTreeMap<K, V>`
- `BTreeSet<T>`

Expected APIs:

- `new`
- `len`
- `is_empty`
- `contains_key`
- `get`
- `get_mut`
- `insert`
- `remove`
- `range`
- `first_key_value`
- `last_key_value`
- `pop_first`
- `pop_last`
- `keys`
- `values`
- `iter`
- `iter_mut`
- `clear`

B-trees are important when deterministic order matters, especially for
compilers, build tools, diagnostics, and reproducible output.

### Specialized Compiler Collections

Types:

- `Arena<T>`
- `Bump`
- `Interner`
- `Symbol`
- `DenseMap<K, V>`
- `DenseSet<T>`
- `IndexVec<I, T>`
- `BitSet`
- `BitMatrix`
- `SlotMap<T>`
- `GenIndex`
- `Graph<N, E>`
- `WorkQueue<T>`

Expected use cases:

- AST/HIR storage.
- String and symbol interning.
- Control-flow graphs.
- Data-flow analysis.
- Type inference tables.
- Worklist algorithms.
- Stable node IDs.
- Deterministic compiler output.

### Caches, Tables, And Indexing Helpers

These are not always part of a minimal stdlib, but they are valuable for
compiler tooling and long-running services.

Possible types:

- `LruCache<K, V>`
- `MemoMap<K, V>`
- `IdMap<I, V>`
- `IdSet<I>`
- `SparseSet<T>`
- `DenseVecMap<I, V>`
- `UnionFind<T>`
- `Table<R, C, V>`

Expected APIs:

- Insert, lookup, remove, and clear.
- Capacity limits for caches.
- Deterministic eviction where reproducibility matters.
- Stable ID allocation and lookup.
- Efficient union/find operations for equivalence classes.

### Linked Lists

Linked lists should not be a priority. If included, they should be documented as
specialized data structures, not general-purpose defaults.

Possible type:

- `LinkedList<T>`

Expected APIs:

- `push_front`
- `push_back`
- `pop_front`
- `pop_back`
- `front`
- `back`
- `len`
- `is_empty`

## Iterators

Once the language has the needed abstraction support, iterators should become
the backbone of collection APIs.

Expected traits/interfaces:

- `Iterator`
- `ExactSizeIterator`
- `DoubleEndedIterator`
- `IntoIterator`
- `FromIterator`
- `Extend`

Expected adapters:

- `map`
- `filter`
- `filter_map`
- `flat_map`
- `take`
- `skip`
- `enumerate`
- `zip`
- `chain`
- `rev`
- `inspect`
- `fold`
- `reduce`
- `collect`
- `all`
- `any`
- `find`
- `position`
- `count`

Iterator design should not block early APIs. Collections can expose direct
loops and slice views first, then add iterator integration once traits,
closures, and generics are ready.

## Algorithms

General algorithms:

- Sort unstable.
- Sort stable.
- Binary search.
- Partition.
- Dedup.
- Reverse.
- Rotate.
- Min/max.
- Min/max by key.
- Clamp.
- Fold/reduce.
- Prefix sum/scan.
- Map/filter/collect through iterators.
- Heap operations.
- Topological sort.
- Breadth-first search.
- Depth-first search.
- Strongly connected components.
- Shortest path algorithms as optional tooling support.

Numeric algorithms:

- Absolute value.
- Greatest common divisor.
- Least common multiple.
- Integer exponentiation.
- Modular arithmetic helpers.
- Checked numeric conversions.
- Simple statistics such as sum, mean, min, and max over slices.

GPU-oriented algorithms:

- Prefix scan.
- Segmented scan.
- Reduce.
- Compact.
- Scatter/gather.
- Histogram.
- Radix sort.
- Parallel partition.

## Memory, Allocation, And Ownership

Allocation should be explicit and target-aware.

Expected APIs:

- Global allocator hooks.
- Fallible allocation.
- Allocator traits/interfaces.
- Bump allocator.
- Arena allocator.
- Fixed-capacity buffers.
- Alignment utilities.
- Raw pointer utilities if the language exposes pointers.
- Move/copy/drop hooks once the language supports them.

Expected contracts:

- `core` does not allocate.
- `alloc` may allocate, and fallible allocation paths must be exposed.
- `std` may initialize a default allocator when a host runtime exists.
- Containers document whether operations invalidate references, indices, or
  iterators.
- Drop/destructor behavior must be deterministic.

## Unsafe And Low-Level Utilities

Low-level utilities should exist only after the language has a clear unsafe
boundary. They are necessary for allocators, FFI, and high-performance
collections, but they should not leak into ordinary APIs.

Possible APIs:

- Raw pointer creation and arithmetic.
- Volatile reads and writes.
- Uninitialized memory wrappers.
- Alignment and layout calculations.
- Byte reinterpretation with explicit layout contracts.
- Unsafe unchecked indexing.
- Atomic memory-ordering primitives.
- Intrinsics for target-specific operations.

Policy:

- Unsafe APIs must be named and documented as unsafe.
- Safe wrappers must state their invariants.
- Undefined behavior must be minimized and specified precisely where it cannot
  be avoided.

## I/O

Types:

- `Reader`
- `Writer`
- `BufReader`
- `BufWriter`
- `Cursor`
- `Stdin`
- `Stdout`
- `Stderr`

Expected APIs:

- `read`
- `read_exact`
- `read_to_end`
- `read_to_string`
- `read_line`
- `write`
- `write_all`
- `write_str`
- `flush`
- `copy`

WASM embeddings may not have file descriptors. I/O should be layered by target
capability and use explicit host imports where needed.

## Filesystem And Paths

Types:

- `Path`
- `PathBuf`
- `File`
- `OpenOptions`
- `DirEntry`
- `Metadata`
- `FileType`
- `Permissions`

Expected APIs:

- Open file.
- Create file.
- Read file to bytes.
- Read file to string.
- Write bytes.
- Write string.
- Append.
- Remove file.
- Create directory.
- Create directory recursively.
- Remove directory.
- Remove directory recursively.
- Read directory.
- Rename.
- Copy.
- Canonicalize.
- Current directory.
- Path join.
- Extension helpers.
- Stem helpers.
- File-name helpers.
- Parent helpers.

## Processes And Environment

Expected APIs:

- Program arguments.
- Environment variable lookup.
- Environment variable iteration.
- Current working directory.
- Set current working directory.
- Exit process.
- Spawn process.
- Process status.
- Capture stdout and stderr.
- Pass stdin/stdout/stderr handles.

Process spawning belongs in `std`, not `core` or `alloc`.

## Command Line And Terminal

Command-line support should make small tools straightforward without turning
the standard library into a full CLI framework.

Expected command-line APIs:

- Access raw arguments.
- Access executable path when the host provides it.
- Parse flags and positional arguments through a small helper layer.
- Render usage text.
- Report parse errors with spans into the argument list.
- Read stdin and write stdout/stderr.
- Return explicit exit codes.

Terminal support:

- Detect whether a stream is a terminal.
- Query terminal width and height when available.
- Enable or disable color based on capability and environment.
- Basic ANSI styling helpers.
- Prompt and line-reading helpers later.
- Raw terminal mode later, behind platform support.

## Time

Types:

- `Duration`
- `Instant`
- `SystemTime`

Expected APIs:

- Monotonic clock.
- Wall clock.
- Elapsed time.
- Sleep.
- Timeout helpers.
- Duration arithmetic.
- Date/time formatting later.
- Timezone support later or in a separate package.

## Concurrency And Synchronization

Types:

- `Thread`
- `JoinHandle`
- `Mutex`
- `RwLock`
- `Condvar`
- `Once`
- `Lazy`
- `AtomicBool`
- `AtomicI32`
- `AtomicU32`
- `AtomicUsize`
- `Channel<T>`
- `Sender<T>`
- `Receiver<T>`

Expected APIs:

- Spawn thread.
- Join thread.
- Lock/unlock.
- Try lock.
- Wait/notify.
- Send/receive.
- Try send/receive.
- Compare/exchange.
- Fetch add/sub/and/or/xor.
- Memory ordering constants once the memory model is specified.

The memory model must be specified before atomics become stable.

## Async And Networking

Async should wait until the language has enough function/type-system support to
avoid locking into a weak design.

Networking types:

- `TcpStream`
- `TcpListener`
- `UdpSocket`
- `SocketAddr`
- `IpAddr`
- `Ipv4Addr`
- `Ipv6Addr`
- `DnsResolver`

Expected networking APIs:

- Connect.
- Bind.
- Listen.
- Accept.
- Send.
- Receive.
- Set blocking/nonblocking mode.
- Resolve hostnames.
- Read/write through I/O traits where practical.

Higher-level protocols:

- HTTP client eventually.
- WebSocket eventually.
- TLS likely as a separate carefully reviewed package.

## Platform, OS, And FFI

Platform APIs should be explicit and isolated so portable code can avoid them.

Expected platform APIs:

- Target family and architecture detection.
- OS error codes and descriptions.
- Handles, descriptors, and owned handle wrappers.
- Dynamic library loading later, if the safety model supports it.
- Foreign-function declarations and calling conventions.
- C-compatible strings and byte buffers.
- Endianness helpers.
- Page size and memory-map APIs later.
- Platform extension namespaces such as `std::os::linux` or
  `std::os::windows`.

FFI should require a clear unsafe boundary once the language has one. The
standard library should provide the boring, correct building blocks, not hide
foreign lifetime or aliasing hazards.

## Encoding, Serialization, And Data Formats

Core encoding formats:

- UTF-8.
- Hex.
- Base64.
- Binary encode/decode.

Useful data formats:

- JSON.
- CSV.
- TOML later.
- YAML probably optional.
- MessagePack later.
- CBOR later.

Expected APIs:

- Streaming encoder.
- Streaming decoder.
- DOM/value tree for JSON.
- Pretty printing.
- Error spans or byte offsets.
- Typed derive support later if the language gets derivation/macros.

Related utility packages:

- URL parsing and formatting.
- Percent encoding.
- UUID parsing, formatting, and generation.
- Glob matching for file tools.
- Regular expressions after strings, slices, and allocation are solid.
- Checksums such as CRC32 and non-cryptographic hashes.
- Compression such as gzip, zlib, and zstd as optional packages.

## Randomness

Types:

- Deterministic PRNG.
- Secure RNG.
- Seed.
- Distribution helpers.

Expected APIs:

- Generate integers.
- Generate floats.
- Generate ranges.
- Fill byte buffers.
- Shuffle.
- Sample distributions.

Policy:

- Deterministic PRNGs are useful in `alloc` or `std` for tests, tools, and
  reproducibility.
- Secure RNG belongs in `std` and should fail explicitly if unavailable.
- APIs must not accidentally use weak randomness for security-sensitive use.

## Cryptography

Cryptography should not be rushed into the stable standard library.

Possible future modules:

- SHA-256.
- BLAKE3.
- HMAC.
- Constant-time equality.
- Secure zeroing.

Likely separate audited packages:

- TLS.
- Public-key cryptography.
- Password hashing.
- Certificate validation.

## Diagnostics And Source Tools

The standard distribution should make good errors easy because Lanius itself is
a compiler-oriented project.

Types:

- `Span`
- `SourceFile`
- `SourceMap`
- `LineMap`
- `Diagnostic`
- `DiagnosticBuilder`
- `Label`
- `Severity`
- `FixIt`

Expected APIs:

- Add primary span.
- Add secondary labels.
- Add notes.
- Add help.
- Add fix suggestions.
- Render plain text.
- Render colored text when supported.
- Render JSON diagnostics for tools.
- Map byte offsets to line/column positions.

## Logging And Tracing

Expected APIs:

- Log levels.
- Structured fields.
- Target/module names.
- Subscriber/sink.
- Tracing spans.
- Timing scopes.

Policy:

- Logging should be optional.
- Disabled logging should have low overhead.
- Host sinks belong in `std`; minimal formatting hooks may live below it.

## Testing

The `test` layer should support:

- `assert`
- `assert_eq`
- `assert_ne`
- `assert_lt`
- `assert_le`
- `assert_gt`
- `assert_ge`
- Expected panic/failure.
- Test registration.
- Test filtering.
- Golden file helpers.
- Snapshot testing.
- Temporary files/directories.
- Property testing.
- Shrinking.
- Fuzz harnesses.
- Benchmarks.

Expected behavior:

- Assertion failures include source location when possible.
- `assert_eq` reports expected and actual values for core primitives first.
- Rich formatting can grow as `fmt`, `String`, and diagnostics mature.
- Tests should work without `std` when only `core` or `alloc` features are
  under test.

## GPU

The `gpu` layer should be explicit about host/device memory, layout, and
dispatch.

Types:

- `Device`
- `Queue`
- `Buffer<T>`
- `BufferView<T>`
- `Dispatch`
- `WorkgroupSize`
- `GpuError`

Expected APIs:

- Create device or report missing support.
- Create buffers.
- Upload data.
- Dispatch kernels.
- Read back data.
- Validate layouts.
- Run CPU/GPU parity tests.

Expected algorithms:

- `scan_i32`
- Generic scan once generics and operation traits exist.
- Reduce.
- Compact.
- Histogram.
- Radix sort.
- Scatter/gather.
- Parallel partition.

GPU APIs should not be part of the default prelude.

## Target Capabilities

The library should expose target capabilities explicitly.

Examples:

- `target::is_wasm`
- `target::is_native`
- `target::has_allocator`
- `target::has_filesystem`
- `target::has_stdio`
- `target::has_threads`
- `target::has_network`
- `target::has_clock`
- `target::has_secure_rng`
- `target::has_gpu`

Capability checks should be compile-time where possible and runtime where
necessary.

## Naming Rules

- Prefer clear names over abbreviations.
- Use module namespaces once real modules and package imports exist.
- Use `lstd_` prefixes only for the current source-level stopgap.
- Avoid names that imply allocation when an API does not allocate.
- Avoid names that hide failure when an API can fail.
- Use `try_` or `checked_` for fallible operations where failure is central.
- Use `unchecked_` only for unsafe or precondition-heavy APIs.
- Prefer `as_*` for cheap views and `into_*` for consuming conversions.
- Prefer `to_*` for producing a converted value.

## Stability Levels

The library should eventually mark APIs by stability.

- Experimental: can change freely.
- Provisional: expected shape, but compatibility is not promised yet.
- Stable: compatibility promise.
- Deprecated: retained temporarily with migration guidance.

The current source-level stdlib is experimental.

## Implementation Phases

### Phase 0: Source-Level Seed

Current phase.

- Plain `.lani` files.
- Source-level imports expanded before lexing/parsing.
- Top-level primitive constants.
- `lstd_` prefix.
- CPU parser/HIR validation.
- Representative type-check/codegen tests.

Current files:

- `i32.lani`
- `bool.lani`
- `array_i32_4.lani`

### Phase 1: Core Declarations And Types

Requires enum/sum types, type-checking support, and backend representation.

- `Option`
- `Result`
- `Ordering`
- Ranges.
- Assertion helpers.
- More complete primitive modules.

### Phase 2: Modules And Imports

Requires module/import support.

- Organize stdlib into modules.
- Remove source include path leakage from user-facing APIs.
- Define explicit prelude.
- Define visibility and package boundaries.
- Retire or isolate compatibility prefixes.

### Phase 3: Generics, Traits, And Const Parameters

Requires reusable type-level abstraction.

- Generic arrays and slices.
- Generic `Vec`.
- Generic maps and sets.
- Iterators.
- Sort/search algorithms.
- `Display`, `Debug`, `Hash`, `Eq`, `Ord`.

### Phase 4: Allocation

Requires allocator ABI, ownership/drop rules, and heap-backed type layouts.

- `String`.
- `Vec`.
- `HashMap`.
- `BTreeMap`.
- `BinaryHeap`.
- Arenas, bump allocators, slabs, and interners.

### Phase 5: Host `std`

Requires target-specific runtime support.

- Files.
- Paths.
- Process.
- Environment.
- Time.
- Threads.
- Networking.

### Phase 6: Tooling And Advanced Libraries

- Diagnostics.
- Property testing.
- Fuzzing.
- Benchmarks.
- Serialization.
- Logging/tracing.
- GPU algorithms.

## Priority List

Highest priority:

- Primitive helpers.
- `Option`, `Result`, `Ordering`.
- Arrays and slices.
- Basic `String` and UTF-8 once allocation exists.
- `Vec`.
- Assertions and test helpers.
- Diagnostics and source spans.
- Arena and interner.

Medium priority:

- `HashMap`, `HashSet`.
- `BTreeMap`, `BTreeSet`.
- `BinaryHeap`.
- Formatting and parsing.
- Files, paths, and time.
- Deterministic PRNG.
- JSON.
- Property testing.

Lower initial priority:

- Networking.
- Async.
- TLS and broad crypto.
- Full Unicode normalization.
- Big integers and rationals.
- Linked lists.

## Language And Runtime Dependencies

The complete stdlib depends on language and runtime features that do not all
exist yet.

Required for `core`:

- Enum/sum types with payloads.
- Generics.
- Const parameters or an equivalent array length abstraction.
- References or borrowed views.
- Slice representation.
- Pattern matching or equivalent destructuring.
- Panic/assert lowering.
- Integer intrinsics.
- Type-checker and backend support for exposed primitive and compound types.

Required for `alloc`:

- Allocator ABI.
- Struct/product types.
- Ownership, move, copy, and drop semantics.
- Heap pointer/reference representation.
- Fallible allocation behavior.
- Generic collection layouts.

Required for `std`:

- Host import/export ABI.
- Runtime initialization and shutdown.
- Stable string, byte-slice, path, handle, and error-code representations.
- Capability gating.
- Process and environment integration.

Required for `test`:

- Source location metadata.
- Harness discovery or explicit registration.
- Formatting enough to report assertion failures.
- Panic/assert runtime behavior.

Required for `gpu`:

- Stable buffer ABI.
- Host/device layout rules.
- Kernel or compute dispatch declarations.
- Readback and parity test support.

## Open Design Questions

- What is the exact ownership and borrowing model for heap collections?
- How should fallible allocation surface in APIs?
- What is the final module/import syntax?
- What belongs in the prelude?
- How should panics work on WASM, native, and embedded targets?
- How should formatting work before macros exist?
- What is the trait/interface system for `Eq`, `Ord`, `Hash`, `Debug`, and
  `Display`?
- How should async be represented?
- How much GPU functionality belongs in stdlib versus separate packages?
- Which compiler-oriented structures belong in `alloc`, `std`, or a separate
  tooling package?
- What stability promise should early stdlib modules make?

## Definition Of Done For A Stdlib Feature

A new stdlib feature should have:

- Source implementation or compiler/runtime implementation.
- Parser/HIR coverage.
- Type-check coverage.
- Backend coverage when codegen is involved.
- Documentation.
- Examples.
- Clear target support notes.
- Failure-mode tests.
- No accidental reliance on unsupported language features.
- A compatibility story if it replaces an existing `lstd_` helper.
