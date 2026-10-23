# Stable arena storage

`alloc::arena` amortizes many allocations across stable chunks. Returned raw
blocks and typed views keep their addresses while the arena grows. `reset`
invalidates allocations and retains chunks for reuse; `clear` releases them;
`destroy` releases them and closes the owner. The implementation is Lanius,
using the existing allocator and native layout helpers.

Executable evidence covers **x86_64 Linux using the GPU compiler**. Other hosts
and GPU-kernel execution have not been established.

## API

```text
Config { chunk_size: usize, max_retained: usize, max_chunks: i32 }
Stats { retained: usize, chunks: i32, used: usize,
        requested: usize, allocations: usize }
Block { data: ptr, length: usize }

default_config() -> Config
new(config: Config) -> Result<Arena, Error>
Arena.borrow() -> &Arena
Arena.is_live() -> bool
Arena.stats() -> Stats
Arena.allocate(size: usize, alignment: usize) -> Result<Block, Error>
Arena.reset() -> Result<bool, Error>
Arena.clear() -> Result<bool, Error>
Arena.destroy()

alloc<T>(arena: &Arena, value: T) -> Result<View<T>, Error>
alloc_slice<T>(arena: &Arena, count: i32, fill: T) -> Result<View<T>, Error>
copy_slice<T>(arena: &Arena, input: View<T>) -> Result<View<T>, Error>
```

Defaults are a preferred 4,096-byte chunk payload, 64 MiB retained storage and
16,384 chunks. Construction is lazy and allocates nothing. A preferred payload
must be positive and leave room for its internal header within
`MAX_CHUNK_BYTES = 2,147,483,647`. Negative chunk limits are invalid. A zero
byte or chunk retention limit remains useful for zero-sized requests.

## Raw and typed storage

Raw `allocate` returns exactly the requested logical byte length. The returned
bytes are **uninitialized storage**: a reset can expose earlier contents, and
the arena does not zero them. Initialize bytes or values before reading them.
There is no per-block deallocation or reallocation.

Supported raw alignments are 1, 2, 4 and 8, with `MAX_ALIGNMENT = 8`. Zero and
non-powers of two return `InvalidAlignment`; larger powers return
`UnsupportedAlignment`. Chunks request 8-aligned backing, and their native
header occupies a multiple of eight bytes. Each allocation aligns its checked
payload offset. No pointer-to-integer conversion or assumed page alignment is
used. Eight serves every current native Lanius type.

Arbitrary over-alignment needs an additional pointer/alignment capability; the
current compiler rejects pointer-to-integer casts. The
[dependency fixtures](../tests/fixtures/stdlib_foundation/arena_dependency/README.md)
record that boundary explicitly. Rejecting an unsupported alignment leaves
the owner and prior blocks unchanged.

Typed operations allocate and initialize complete native storage extents.
`alloc` returns one initialized element, `alloc_slice` repeats a value, and
`copy_slice` copies the selected logical elements. Negative counts and invalid
logical input bounds are errors. Input copies may borrow earlier allocations
from the same arena: growth never relocates their chunks.

Storage uses `core::mem::size_of<T>()` and
`core::mem::typed_slice_from_storage<T>()`. Raw byte and `i32` views are packed
with strides +1 and +4. Other types use their descending native word layout,
including records, enums, arrays, strings and borrowed slices; the helpers set
the correct starting address. Do not reconstruct a descending view from the
same low storage address with a different extent: that changes element zero.
Use the returned counted view and its ordinary subviews.

One shared internal allocator returns a primitive pointer result; the public
raw API wraps it in `Block` separately. The dependency fixtures retain a
reduced provider whose nominal `Block` result inside a generic copy reports
`LNC0047`, alongside the working primitive-pointer control. This is a compiler
composition limitation, while the current general typed APIs execute.

Zero-sized raw requests return a non-null aligned dangling pointer and consume
no chunk space. The pointer must not be dereferenced. Empty typed requests and
zero-sized types likewise need no backing allocation. Huge zero-sized counts
do not run a per-element initialization loop. They still produce a counted
view whose values occupy no bytes. Each successful request, including a
zero-sized one, increments the current allocation counter.

## Ownership and invalidation

Keep one active arena owner. Copies alias the same chunks and must not be used
as independent owners. Arena operations are unsynchronized. Raw blocks and
views borrow storage; none owns or frees
an individual allocation. The language does not enforce these lifetimes,
exclusive ownership, immutable input views or sufficient physical backing.

Every `reset`, `clear` or `destroy` invalidates **all** previous blocks, pointers
and typed views, including values that happen to retain the same address.
There is no mark/rewind API or generation-checked handle. Stop using old
references before resetting the owner.

`reset` clears chunk bump positions, current usage and request counters, then
reuses retained chunks in order. It neither zeroes nor releases them. `clear`
frees all chunks, resets counters and leaves the same owner usable with its
original configuration. Both return `Ok(true)` for a live owner, including an
already empty owner. `destroy` is terminal and idempotent on that same handle.
Subsequent allocations, resets and clears return `Destroyed`; queries remain
available and show zero retained storage.

Typed values are shallow copies. The arena does not move nested owners or run
destructors for values, overwritten data, reset allocations or destroyed
chunks. Arrange any resource cleanup before invalidating their storage. An
arena-backed map of borrowed keys can destroy its map storage first and the
arena second. Independently owned resources copied into the arena still need
an explicit, correct ownership plan.

## Limits, accounting and failure

Each chunk has one underlying allocation containing its native header and
payload. Chunk metadata does not use a vector or move when the arena grows.
Normal requests bump within the current chunk. When it cannot fit, allocation
checks later retained chunks before adding a new one. A larger request gets a
payload large enough for itself. If the remaining retention budget is smaller
than the preferred chunk, the arena can use that smaller available payload.

`Stats.retained` counts actual bytes requested from the underlying allocator,
including internal headers. It does not count the host allocator's page
rounding. `chunks` counts those retained allocations. `used` counts consumed
payload bytes including alignment padding, `requested` counts caller payload
bytes, and `allocations` counts successful requests since reset/clear. Retained
bytes and chunks survive reset; all other counters become zero.

All limits and arithmetic are checked before a successful bump or chunk-link
change. Invalid alignment, size overflow, exhausted retention/chunk budgets
and allocation failure preserve every counter, bump position, earlier content
and borrowed view. Typed count multiplication is checked before allocation.
A request larger than one supported native allocation is `SizeOverflow` even
when a larger aggregate retention limit was configured. The per-chunk cap
keeps requests within the bounded native allocator path; it does not imply an
allocation that large will succeed.

Allocation is normally constant time; searching reusable later chunks is
bounded by retained chunk count. Reset, clear and destroy visit retained chunks
once. Typed initialization and copying additionally visit actual nonzero-sized
elements. The design follows the slab/bump allocation technique illustrated by
[LLVM's allocator](https://llvm.org/doxygen/Allocator_8h_source.html), with this
module's explicit errors and policy of retaining all chunks on reset.

Errors are `InvalidConfig`, `InvalidAlignment`, `UnsupportedAlignment`,
`Bounds`, `SizeOverflow`, `RetainedLimit`, `ChunkLimit`, `AllocationFailed`
and `Destroyed`. Exhausting `max_chunks` takes precedence over retaining an
additional chunk; zero-sized requests need neither budget. If several
contracts fail, the first validation reached determines the error.

## Executable evidence and measurements

`tests/stdlib_arena_execution.rs` covers:

- Relative alignment, stable content through growth, invalid requests,
  zero-byte requests, reset reuse, clear reuse and terminal destruction.
- Signed/unsigned primitive widths, pointers, `f32`, stored `f64` value 3.25
  with stride -8, strings, nested records, arrays, slices and generic enums.
- Packed byte/`i32` source copies and descending compound storage.
- Eight configurations with 1,210 generated operations each, compared against
  a separate resource model while checking every live block's complete bytes.
- Every observed chunk-allocation failure, preserving counters and every prior
  typed value, with each successful mapping paired with its release.
- Zero-sized counts through `i32::MAX` and empty typed requests with every
  allocator call denied.
- 16,384 and 262,144 record batches, stable earlier values, chunk-level
  allocation counts and a second complete pass after reset without new chunks.

Native process measurements on 2026-10-23 used CPU 8, one warmup and five
measured runs. Each run initialized the arena, allocated `count + 1` records,
validated them, reset, allocated `count` records, checked reuse and destroyed
the owner. The fixture uses 65,536-byte preferred chunk payloads and a
1,024-chunk limit. Records occupy 48 native bytes. These are complete fixture timings,
not a comparison with another allocator or compiler.

| Records per main pass | Retained chunks / allocator calls | Median | Observed range |
| --- | --- | --- | --- |
| 16,384 | 13 | 17.932 ms | 17.489–18.276 ms |
| 262,144 | 193 | 265.337 ms | 242.105–274.135 ms |

The real `arena-words` program combines arena-owned word bytes with an ordered
map of borrowed keys. Its [application documentation](stdlib-arena-words.md) describes input, output,
limits and cleanup order. Rust and Python in the test harness provide reference
models and process control only; production storage behavior is Lanius.

All seven arena runtime groups passed together in 13.42 s. The three typed
word-count application groups separately passed in 8.31 s.
