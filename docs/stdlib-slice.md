# Generic slices

`core::slice` supplies ten allocation-free access and copying functions with
shared generic Lanius bodies. The other 27 public functions in this module
remain i32 arithmetic, comparison, search, and ordering algorithms.

## Supported execution

The generic functions execute through imported calls on x86_64 Linux ELF output
from the GPU compiler. Runtime tests cover i32, u32, bool, f32, char, i8, i16,
u8, and u16 views borrowed from fixed arrays. They also cover typed i32 views
constructed from raw storage. Narrow integer spellings share their signed or
unsigned 32-bit compiler identity; distinct-width type checking remains a
compiler dependency. Focused compiler tests also execute record access,
mutation, reversal, fill, and copying, plus string access, swap, and fill.
The [compiler checkpoint](compiler-generic-types.md) lists the exact cases;
nested-view and native i64/u64 elements remain unverified.

GPU compiler execution does not establish user-program GPU-device support.
Wasm is not a dependency or a claimed target.

## Operations and failures

Callers supply a logical element length because Lanius source cannot yet read
slice metadata. A logical length must fit the physical view. Checked logical
bounds do not validate a fabricated pointer or its allocation.

| Function | Result and behavior |
| --- | --- |
| `first<T>(values)` | Returns element zero. An empty physical view traps. |
| `first_or<T>(values, len, fallback)` | Returns the fallback for `len <= 0`; otherwise reads element zero. |
| `get_or<T>(values, len, index, fallback)` | Returns the fallback for a negative index or `index >= len`; otherwise reads that element. |
| `set<T>(values, len, index, value)` | Returns false without mutation for an invalid logical index; otherwise assigns and returns true. |
| `swap<T>(values, len, left, right)` | Returns false without mutation if either index is invalid; otherwise exchanges the two values. Equal valid indices succeed. |
| `fill<T>(values, len, value)` | Writes the first `len` elements and returns the number written. Nonpositive lengths return zero without accessing storage. |
| `reverse_in_place<T>(values, len)` | Reverses the prefix and returns the number of swaps. Lengths at most one return zero. |
| `copy_within<T>(values, len, source_start, source_end, destination_start)` | Copies a half-open source range within one view, supporting overlap in either direction. Invalid logical bounds return false without mutation. Empty ranges at the end are valid. |
| `copy_nonoverlapping_prefix<T>(destination, destination_len, source, source_len)` | Copies the source prefix. Negative lengths or insufficient destination length return false without mutation. An empty source succeeds. Copied storage ranges must not overlap. |
| `copy_nonoverlapping_range<T>(destination, destination_len, destination_start, source, source_len, source_start, count)` | Copies a requested range. Negative or out-of-range arguments return false before writing. Empty ranges at either end are valid. Copied storage ranges must not overlap. |

If indexing reaches beyond the physical view, native execution terminates with
exit 101. An overstated logical length can remain unobserved when an operation
returns before accessing that position. Raw views require live, correctly
aligned backing storage for their declared length. They borrow that storage
and never allocate or free it.

The ten generic names replace the former i32-suffixed access/copy names in
`core::slice`; callers use `core::slice::get_or` and similar unsuffixed names.
The separate concrete slice modules retain their own APIs.

## Compiler boundary

Indexing a symbolic T requires its concrete storage stride even if the function
returns only a Boolean or count. Such bodies are deferred and replayed using a
GPU-checked concrete call environment. Unspecialized bodies publish no guessed
native implementation.

Local generic calls in a combined source pack now have body scheduling.
`tests/fixtures/stdlib_foundation/repro_generic_slice_local_body.lani` is a
minimal reproduction: it reverses three i32 elements through a local generic
function and now executes in the template suite. The owned i32, i8, i16,
u8, u16, and bool vectors reverse their concrete allocation cells directly in
Lanius; their storage, logical length, and capacity remain intact. Refactoring
those concrete vector bodies is separate from these compiler fixes. General
generic collections remain unfinished.

The imported-call validator resolves a field argument from the field's type,
including `extent.length`, instead of its receiver's type. Array/slice generic
claims bind T to the checked element, preserving the distinction from a direct
T parameter that receives an entire slice. Wrong element relations and Boolean
field lengths are rejected with LNC0006.

## Executable evidence

`tests/stdlib_slice_generic_execution.rs` has eight tests. They execute all ten
functions across the nine scalar spellings above, normal and invalid bounds,
empty operations, overlap in both directions, preserved source storage, raw
views, NaN, negative zero, native bounds traps, and wrong-type rejection. A
focused matrix reverses all six owned vector types after the API migration.
The reading-summary program composes generic slice access with Option, ranges,
and arithmetic and prints `4\n20\n`.

All 30 adjacent template, generic memory, Option payload/slice, and Result
checks also pass in `generic-slice-adjacent-runtime-tests.log` in that directory.
They include the explicit local-specialization failure reproduction.

The latest focused run also checks nonzero first elements and equal-index
swaps; all eight tests pass in `generic-slice-complete-runtime-tests.log`.

The combined checkpoint also passes all seven foundation tests, including the
139-entry executable source matrix. Its log is
`tests/fixtures/stdlib_compiler_state/generic-slice-foundation-complete-tests.log`.

```sh
CARGO_INCREMENTAL=0 CARGO_PROFILE_RELEASE_DEBUG=0 \
CARGO_TARGET_DIR="$PWD/target/stdlib-perf/build" \
timeout 110s cargo test --locked --release \
  --test stdlib_slice_generic_execution \
  --test stdlib_foundation_execution -- --test-threads=1
```

The latest compiler changes have no fresh performance comparison. Earlier
measurements are recorded in [the GPU compiler performance report](stdlib-gpu-performance.md).
