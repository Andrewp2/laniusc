# Lanius Standard Library Plan

This document describes the full standard library we want Lanius to grow into.
It is intentionally broader than the source files that exist today. The current
`stdlib/*.lani` files are a source-level seed package; they are not imported
automatically and should stay explicit until real modules, package imports,
generics, heap allocation, traits/interfaces, and target-specific runtime
support exist.

The guiding idea is that the standard library should make ordinary programs
pleasant without hiding control flow or surprising the compiler. Lanius values
honesty: helpers should do what their names say, expose allocation and failure
where it matters, and avoid implicit magic.

## Goals

- Provide a small always-available core that works without an OS or heap.
- Provide predictable collections, strings, and algorithms once allocation
  exists.
- Make compiler-oriented data structures first-class enough that Lanius can use
  its own library to build compilers, tools, and GPU-oriented applications.
- Keep APIs explicit about allocation, mutation, error handling, and target
  requirements.
- Keep WebAssembly embedding and native compilation both in mind.
- Grow in layers so early source-level helpers are useful before the complete
  runtime exists.

## Non-Goals

- Do not pretend real modules/package imports exist before they do.
- Do not make every package part of the core standard library.
- Do not silently allocate from APIs that look like simple scalar operations.
- Do not bake in one async runtime as the only possible I/O story too early.
- Do not include high-risk cryptography APIs until they can be designed and
  tested carefully.

## Library Layers

The eventual standard library should be split into capability layers.

### `core`

`core` is always available. It has no OS dependency and no heap dependency.

Expected contents:

- Primitive helpers.
- Fixed arrays and slices.
- `Option`, `Result`, `Ordering`, ranges.
- Basic traits/interfaces when the language has the feature.
- Panic/assert primitives.
- Minimal formatting hooks that do not require heap allocation.
- Compiler intrinsics and target-independent low-level utilities.

### `alloc`

`alloc` depends on heap allocation but not on an OS.

Expected contents:

- `String`.
- `Vec`.
- Heap-backed maps, sets, and priority queues.
- Reference-counted or owned heap utilities if the ownership model supports
  them.
- Arena and bump allocation utilities.

### `std`

`std` depends on a host environment.

Expected contents:

- Files, paths, directories.
- Standard input/output/error.
- Environment variables.
- Process arguments and exit codes.
- Time, clocks, sleep.
- Threads, locks, channels.
- Networking.
- Platform-specific extension points.

### `test`

`test` is available to tests, examples, fuzzers, and benchmarks.

Expected contents:

- Assertions.
- Golden test helpers.
- Property testing.
- Fuzzing harness support.
- Benchmark harness support.
- Temporary files and directories.

### `gpu`

`gpu` is optional and should expose explicit GPU-friendly primitives.

Expected contents:

- Prefix scan/reduce abstractions.
- Parallel partition/compact helpers.
- GPU buffer layout helpers.
- Compute dispatch helpers.
- Deterministic validation utilities for GPU/CPU parity.

## Current Source-Level Seed

The current `stdlib/` directory contains plain `.lani` files:

- `core/i32.lani`
- `core/bool.lani`
- `core/array_i32_4.lani`
- `i32.lani`
- `bool.lani`
- `array_i32_4.lani`

Use explicit source imports before program source:

```lani
import core::i32;
import core::bool;

fn main() {
    return core::i32::abs(-7);
}
```

These imports are source-level includes expanded before lexing/parsing. They use
stdlib package lookup and a source-level namespace bridge. The module-form files
use names such as `core::i32::abs()`. The older flat files still use an `lstd_`
prefix to avoid collisions and remain available as compatibility shims.

Top-level primitive constants are available for source stdlib modules. Current
examples include `core::i32::MIN`, `core::i32::MAX`, `LSTD_I32_MIN`, and
`LSTD_I32_MAX`.

## Module And Package Model

The stdlib should eventually be organized as modules, not as prefixed global
names.

Candidate module names:

- `core::bool`
- `core::i32`
- `core::u32`
- `core::i64`
- `core::f32`
- `core::char`
- `core::option`
- `core::result`
- `core::range`
- `core::slice`
- `alloc::vec`
- `alloc::string`
- `alloc::hash_map`
- `alloc::btree_map`
- `std::io`
- `std::fs`
- `std::path`
- `std::time`
- `std::process`
- `std::net`
- `test::assert`
- `test::prop`

Import behavior should be explicit. A small prelude can exist later, but it
should be documented and stable.

Candidate prelude:

- `Option`
- `Result`
- `Ordering`
- `Range`
- `assert`
- Primitive conversion helpers.
- Iterator traits/interfaces, once available.

## Error Handling

The library should standardize failure through `Result<T, E>` where recovery is
reasonable.

Core error families:

- Parse errors.
- I/O errors.
- Allocation errors.
- UTF-8 errors.
- Bounds/index errors.
- Conversion errors.
- Time errors.
- Process errors.
- Network errors.

Panic should be reserved for bugs, violated preconditions, or intentionally
unchecked APIs.

## Primitive Types

Every primitive type should have a coherent helper module.

### Integers

For signed and unsigned integer types:

- `min`
- `max`
- `clamp`
- `abs` for signed types.
- `signum` for signed types.
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
- `rotate_left`
- `rotate_right`
- `count_ones`
- `count_zeros`
- `leading_zeros`
- `trailing_zeros`
- `is_power_of_two`
- `next_power_of_two`
- Parse from text.
- Format to decimal, hex, binary, octal.

### Floats

For floating-point types:

- `min`
- `max`
- `clamp`
- `abs`
- `floor`
- `ceil`
- `round`
- `trunc`
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
- Parse and format.

### Bool

Bool helpers:

- `not`
- `and`
- `or`
- `xor`
- `eq`
- `to_i32`
- `from_i32`
- `then`
- `then_some`

### Char

Char helpers:

- ASCII classification.
- Unicode scalar value support.
- Case conversion.
- Digit conversion.
- UTF-8 encoding length.
- Encode to UTF-8.
- Decode from UTF-8.

## Option And Result

`Option<T>` should represent optional values.

Expected APIs:

- `is_some`
- `is_none`
- `unwrap`
- `unwrap_or`
- `map`
- `and_then`
- `or_else`
- `filter`
- `take`
- `replace`

`Result<T, E>` should represent recoverable errors.

Expected APIs:

- `is_ok`
- `is_err`
- `unwrap`
- `unwrap_err`
- `unwrap_or`
- `map`
- `map_err`
- `and_then`
- `or_else`

## Ordering And Comparison

Types:

- `Ordering`: `Less`, `Equal`, `Greater`.

Expected helpers:

- `compare`
- `min`
- `max`
- `clamp`
- Sort comparison adapters.
- Reverse ordering.

## Ranges

Range types:

- `Range<T>` for `start..end`.
- `RangeInclusive<T>` for `start..=end`.
- `RangeFrom<T>`.
- `RangeTo<T>`.
- `RangeFull`.

Expected APIs:

- `contains`
- `is_empty`
- Iteration for integer ranges.
- Slicing integration.

## Arrays And Slices

Fixed arrays should be in `core`. Slices become the common view over contiguous
memory.

Expected fixed-array APIs:

- Length.
- Checked indexing.
- Unchecked indexing for explicitly unsafe contexts.
- Fill.
- Copy.
- Swap.
- Reverse.
- Rotate.
- Map.
- Fold.

Expected slice APIs:

- `len`
- `is_empty`
- `first`
- `last`
- `get`
- `get_mut`
- `split_at`
- `chunks`
- `windows`
- `contains`
- `starts_with`
- `ends_with`
- `binary_search`
- `sort_unstable`
- `sort_stable`
- `dedup`
- `partition`

Early Lanius may need generated modules like `array_i32_4` until generics and
const parameters exist. Long-term, those should collapse into generic array and
slice APIs.

## Strings And Text

Strings should be UTF-8 by default.

Types:

- `str`: borrowed UTF-8 string slice.
- `String`: owned growable UTF-8 string.
- `Utf8Error`.
- `StringBuilder`.
- `Bytes`.

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
- `parse_i32`
- `parse_bool`

Expected `String` APIs:

- `new`
- `with_capacity`
- `len`
- `capacity`
- `clear`
- `push_char`
- `push_str`
- `insert`
- `remove`
- `replace`
- `reserve`
- `shrink_to_fit`
- `into_bytes`

Text support should also include:

- ASCII helpers.
- UTF-8 validation.
- Unicode scalar iteration.
- Unicode normalization later, likely as an optional package.
- Formatting.
- Debug escaping.

## Formatting And Parsing

Formatting should be explicit and allocation-aware.

Expected capabilities:

- Format to a writer.
- Format to a `String`.
- Debug formatting.
- Display formatting.
- Integer formatting.
- Float formatting.
- Bool formatting.
- Char/string escaping.
- Parse primitives from strings.

Formatting should not require macros initially. A builder-style API is enough
until the language has macro or compile-time formatting support.

## Dynamic Arrays

`Vec<T>` should be the standard growable array.

Expected APIs:

- `new`
- `with_capacity`
- `len`
- `capacity`
- `is_empty`
- `push`
- `pop`
- `insert`
- `remove`
- `swap_remove`
- `clear`
- `reserve`
- `shrink_to_fit`
- `as_slice`
- `as_mut_slice`
- `extend`
- `append`
- `sort`
- `binary_search`

Specialized variants:

- `SmallVec<T, N>` later.
- `ArrayVec<T, N>` for fixed-capacity stack storage.
- `BitVec` for packed booleans.

## Deques, Queues, And Stacks

Types:

- `VecDeque<T>`
- `Stack<T>` as a thin wrapper or alias around `Vec<T>`.
- `Queue<T>` as a thin wrapper or alias around `VecDeque<T>`.

Expected `VecDeque` APIs:

- `push_front`
- `push_back`
- `pop_front`
- `pop_back`
- `front`
- `back`
- `rotate_left`
- `rotate_right`

## Heaps And Priority Queues

`BinaryHeap<T>` should provide a priority queue.

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
- `into_sorted_vec`

Support min-heap and max-heap behavior through ordering adapters.

## Hash Maps And Hash Sets

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
- `clear`
- `reserve`

Hashing should be explicit about security tradeoffs:

- A fast deterministic hasher for compiler/tooling workloads.
- A randomized or DoS-resistant hasher for externally supplied keys.

## B-Trees

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

B-trees are useful when deterministic order matters, which is important for
compilers, build tools, and reproducible output.

## Compiler-Oriented Data Structures

Lanius should include data structures that make compiler implementation
pleasant.

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
- String/symbol interning.
- Control-flow graphs.
- Data-flow analysis.
- Type inference tables.
- Deterministic compiler output.

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
- BFS.
- DFS.
- Strongly connected components.

GPU-oriented algorithms:

- Prefix scan.
- Segmented scan.
- Reduce.
- Compact.
- Scatter/gather.
- Histogram.
- Radix sort.

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
- `fold`
- `reduce`
- `collect`
- `all`
- `any`
- `find`
- `position`

## Memory And Allocation

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

Avoid hiding allocation inside APIs that look pure or constant-time.

## I/O

Types:

- `Reader`
- `Writer`
- `BufferReader`
- `BufferWriter`
- `Stdin`
- `Stdout`
- `Stderr`

Expected APIs:

- Read bytes.
- Read exact bytes.
- Read line.
- Write bytes.
- Write string.
- Flush.
- Copy reader to writer.

WASM embeddings may not have file descriptors. I/O should be layered by target.

## Filesystem And Paths

Types:

- `Path`
- `PathBuf`
- `File`
- `DirEntry`
- `Metadata`

Expected APIs:

- Open file.
- Create file.
- Read file to bytes/string.
- Write bytes/string.
- Append.
- Remove file.
- Create directory.
- Remove directory.
- Read directory.
- Rename.
- Copy.
- Canonicalize.
- Path join.
- Extension/stem/file-name helpers.

## Processes And Environment

Expected APIs:

- Program arguments.
- Environment variables.
- Current working directory.
- Exit process.
- Spawn process.
- Process status.
- Capture stdout/stderr.

Process spawning belongs in `std`, not `core`.

## Time

Types:

- `Duration`
- `Instant`
- `SystemTime`

Expected APIs:

- Monotonic clock.
- Wall clock.
- Sleep.
- Timeout helpers.
- Date/time formatting later.

## Concurrency

Types:

- `Thread`
- `JoinHandle`
- `Mutex`
- `RwLock`
- `Once`
- `Lazy`
- `AtomicBool`
- `AtomicI32`
- `AtomicU32`
- Channels.

Expected APIs:

- Spawn thread.
- Join thread.
- Lock/unlock.
- Try lock.
- Send/receive.
- Compare/exchange.
- Fetch add/sub/and/or/xor.

The memory model must be specified before atomics become stable.

## Async And Networking

Async should be designed after the language has enough function/type-system
support to avoid locking into a poor design.

Networking types:

- TCP stream.
- TCP listener.
- UDP socket.
- DNS resolver.
- Socket address.

Higher-level protocols:

- HTTP client eventually.
- WebSocket eventually.
- TLS likely as a separate carefully reviewed package.

## Serialization

Core serialization formats:

- Binary encode/decode.
- JSON.
- UTF-8.
- Hex.
- Base64.

Later formats:

- TOML.
- YAML, probably optional.
- MessagePack.
- CBOR.

Expected APIs:

- Streaming encoder/decoder.
- DOM/value tree for JSON.
- Typed derive support later if the language gets derivation/macros.

## Randomness

Types:

- Deterministic PRNG.
- Secure RNG.
- Seed.

Expected APIs:

- Generate integers.
- Generate floats.
- Generate ranges.
- Shuffle.
- Sample distributions.

The secure RNG should be target-specific and fail explicitly if unavailable.

## Cryptography

Cryptography should not be rushed into the core stdlib.

Possible future modules:

- SHA-256.
- BLAKE3.
- HMAC.
- Constant-time equality.
- Secure zeroing.

TLS, public-key cryptography, and password hashing should likely live in
separate audited packages.

## Diagnostics

The stdlib should make good errors easy.

Types:

- `Span`
- `SourceFile`
- `SourceMap`
- `Diagnostic`
- `DiagnosticBuilder`
- `Severity`

Expected APIs:

- Add primary span.
- Add labels.
- Add notes.
- Add help.
- Render to text.
- Render with colors when supported.

This is especially important because Lanius itself is a compiler.

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
- Golden file helpers.
- Snapshot testing.
- Temporary files/directories.
- Property testing.
- Fuzz harnesses.
- Benchmarks.

Property testing is a strong fit for Lanius's stated future direction.

## Logging And Tracing

Expected APIs:

- Log levels.
- Structured fields.
- Target/module names.
- Subscriber/sink.
- Tracing spans.
- Timing scopes.

Logging should be optional and low overhead when disabled.

## Platform And Target Support

The library should expose target capabilities explicitly.

Examples:

- `target::has_filesystem`
- `target::has_threads`
- `target::has_network`
- `target::has_clock`
- `target::has_secure_rng`
- `target::is_wasm`

This keeps embedded and WASM use cases honest.

## Naming Principles

- Prefer clear names over abbreviations.
- Use module namespaces once real modules/package imports exist.
- Use `lstd_` prefixes only for the current source-level stopgap.
- Avoid names that imply allocation when an API does not allocate, and vice
  versa.
- Use `try_` or `checked_` for fallible operations where the failure is central.
- Use `unchecked_` only for explicitly unsafe or precondition-heavy APIs.

## Stability Levels

The library should eventually mark APIs by stability:

- Experimental: can change.
- Provisional: expected shape, may still change.
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

Near-term additions:

- More fixed-size array helpers.
- More primitive helpers.
- Source-level examples.

### Phase 1: Core Types

Requires enum/sum types or equivalent representation.

- `Option`
- `Result`
- `Ordering`
- Ranges.
- Assertion helpers.
- More complete primitive modules.

### Phase 2: Modules And Imports

Requires module/import support.

- Organize stdlib into modules.
- Remove need for source include paths and compatibility prefixes.
- Define explicit prelude.
- Define visibility and package boundaries.

### Phase 3: Generics And Traits/Interfaces

Requires generics and shared behavior abstraction.

- Generic arrays/slices.
- Generic `Vec`.
- Generic maps/sets.
- Iterators.
- Sort/search algorithms.
- `Display`, `Debug`, `Hash`, `Eq`, `Ord`.

### Phase 4: Allocation

Requires heap/runtime allocation.

- `String`.
- `Vec`.
- `HashMap`.
- `BTreeMap`.
- `BinaryHeap`.
- Arena and bump allocators.

### Phase 5: Host `std`

Requires target-specific runtime support.

- Files.
- Paths.
- Process.
- Environment.
- Time.
- Threads.
- Networking.

### Phase 6: Advanced Tooling

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
- Basic `String`/UTF-8 once allocation exists.
- `Vec`.
- Assertions and test helpers.
- Diagnostics/source spans.
- Arena and interner.

Medium priority:

- `HashMap`, `HashSet`.
- `BTreeMap`, `BTreeSet`.
- `BinaryHeap`.
- Formatting/parsing.
- Files/path/time.
- Random deterministic PRNG.
- JSON.
- Property testing.

Lower initial priority:

- Networking.
- Async.
- TLS/crypto.
- Full Unicode normalization.
- Big integers/rationals.
- Linked lists.

## Open Design Questions

- What is the exact ownership and borrowing model for heap collections?
- How should fallible allocation surface in APIs?
- What is the module/import syntax?
- What belongs in the prelude?
- How should panics work on WASM and embedded targets?
- How should formatting be implemented without macros?
- What is the trait/interface system for `Eq`, `Ord`, `Hash`, `Debug`, and
  `Display`?
- How should async be represented?
- How much GPU functionality belongs in the stdlib versus separate packages?
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
