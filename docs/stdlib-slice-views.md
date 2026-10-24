# Borrowed slice views and cursors

`core::slice::View<T>` stores a native slice, a logical start and an element
count. Subviews and cursors retain that slice's stride and physical bounds.
They allocate nothing and use ordinary Lanius indexing, including for packed
buffers, stack arrays, compound payloads and zero-sized elements.

## Construction and lifetime

- `view(values, count)` selects a prefix.
- `view_range(values, start, count)` selects a range of the original slice.
- Both return `Result<View<T>, ViewError>`. Negative arguments and an end beyond
  `i32::MAX` return `Bounds` without accessing storage.
- **The caller must supply a physically backed range.** Lanius cannot yet read
  slice lengths. Construction checks integer bounds only; overstated counts
  remain invalid and an out-of-bounds native access traps. `len` reports the
  supplied logical count, not a verified physical allocation size.
- The original storage must remain alive and initialized. Destroying or
  reallocating its owner invalidates all views, windows, chunks and cursors.
  These lifetime rules are not compiler-enforced.
- Copying a view copies its descriptor. Copies alias the same writable elements.
  Reading or returning an element makes a shallow value copy, with no implicit
  clone or destruction of resources it contains.

Use the constructors to establish the descriptor invariants. Subsequent
operations use view-relative indices; callers do not resupply lengths.

## Operations

| API | Contract |
| --- | --- |
| `len`, `is_empty` | Logical element count and emptiness; O(1) |
| `get`, `first`, `last` | `Option<T>`; invalid indices and empty endpoints return `None` |
| `subview(start, end)` | Half-open range, returning `Result<View<T>, ViewError>`; negative, reversed or out-of-range indices return `Bounds` |
| `try_set(index, value)` | Return the displaced element; `Bounds` leaves storage unchanged |
| `copy_within(start, end, destination)` | Copy a half-open range, including either overlap direction; return copied count; validate all logical bounds before mutation |
| `reverse` | Reverse only this view; return the number of swaps |
| `fill(value)` | Replace all elements; return the number written |
| `iter` | Cursor over the current elements |
| `chunks(width)` | Nonoverlapping views, including a final short chunk |
| `windows(width)` | Every overlapping view of exactly `width` elements, stepping by one |

Zero-length subviews at the end are valid. Empty copies, fills and reversals
succeed without touching elements. Chunks/windows reject nonpositive widths
with `InvalidSize`. Empty inputs produce no chunks or windows; a width larger
than the input produces one short chunk and no windows.

Access, construction and cursor metadata operations are O(1); copy, fill and
reverse are O(number of affected elements). Creating a chunk or window copies
only a descriptor, not its elements.

## Cursor behavior

`Iter<T>` supports `next`, `next_back`, `remaining`, `advance` and `advance_back`.
The two ends share one remaining range, so an element is never yielded twice
by one cursor. `advance` and `advance_back` skip up to the requested number
without reading storage and return the actual count skipped. Negative requests
return `Bounds` without advancing; larger requests exhaust the cursor.

`Chunks<T>` and `Windows<T>` expose `next` and `remaining`. All three cursors
stay exhausted once they return `None`. Copying a cursor forks its position;
backing elements remain shared. Mutations through a valid alias are visible
when a cursor later reads those elements. Overlapping windows also alias.

These are inherent cursor methods. The separate
[shared iteration module](stdlib-iterators.md) now exposes a checked
`SliceIter<T>` constructor, the fused `Iterator<T>` protocol, borrowed take/chain
adapters and bounded consumption. Its own execution gates cover generic
dispatch and preserve these native stride, backing and shallow-copy contracts.

## Executable example

`sample_programs/window_report.lani` reads a window width followed by signed
32-bit sample lines, then emits CSV with each complete window's zero-based
start, minimum, maximum and exact 64-bit sum. It combines borrowed text,
decimal parsing, owned vectors, slice windows, cursors and host I/O.

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  sample_programs/window_report.lani --stdlib-root stdlib \
  -o target/stdlib-work/window_report
```

After successful compilation:

```sh
printf '3\n2\n-1\n7\n4\n' | timeout 5s target/stdlib-work/window_report
```

Output:

```text
start,min,max,sum
0,-1,7,8
1,-1,7,10
```

The width is 1..4096; at most 4096 sample lines and 1 MiB of input are accepted.
ASCII whitespace around numbers and CRLF are accepted. A single final newline
is optional; interior blank lines, invalid UTF-8, malformed numbers and values
outside i32 fail. Empty sample lists and widths larger than the sample count
produce only the header. Data is fully validated before output begins.

Exit statuses: 0 success, 2 invalid input or limit, 3 I/O failure, 4 allocation
failure. Output errors may leave a CSV prefix. Input `Interrupted` is retried;
other unrecovered I/O errors are reported. Every exit path releases owners.
The sample computes each window independently, O(samples × width), within the
stated limits. It is an integration example, not an optimized rolling aggregate.
Native i64 sums use the [decimal writer](stdlib-decimal.md) directly.

## Evidence and targets

Supported execution target: **x86_64 Linux**, compiled by the GPU compiler.
This is CPU execution evidence; it does not claim user-program GPU execution.
The view implementation has no host or allocator calls. Other target support
requires separate execution evidence.

- `tests/stdlib_slice_view_execution.rs`: native contracts for subviews,
  aliasing, mutation, independent cursor positions, exhaustion, negative and
  maximum integer arguments, strided stack storage, packed u8/i32 storage,
  strings, nested Option/array/u64 payloads and zero-sized elements.
- Its model test executes 6,388 commands: all subranges of a 16-element array
  across 20 chunk/window widths, overlapping and rejected copies, then
  reproducible stateful mutations. Replies are compared to Rust slice behavior.
- A separate executable verifies physical overclaims trap with status 101.
- `tests/library_window_report_execution.rs`: reference statistics for 4,096
  samples and seven widths, i32 extremes with wider sums, malformed input and
  limits, every observed allocation failure, validation cleanup, read errors,
  interruption and partial output failure. Syscall traces check resource release.

Run either focused test target with the absolute stdlib build directory and
a command timeout below two minutes, as in [the execution setup](stdlib-string.md).
