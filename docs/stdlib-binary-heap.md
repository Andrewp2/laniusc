# Binary heaps

`alloc::binary_heap::BinaryHeap<T>` is an owned generic priority queue implemented
in Lanius. `Order::Min` returns the smallest priority first; `Order::Max` returns
the largest. Its public operations have native execution coverage on
**x86_64 Linux using the GPU compiler**. GPU user-program execution and other
targets remain unverified.

## Ordering and ownership

The [fallible iterator sink](stdlib-iterator-collection-sinks.md) implements
`TrySink<T,Error>` through checked `try_push`, with the same Ord requirement.
It preserves this heap's selected Min/Max order and accepts duplicate entries.
Bounded transfer reports its accepted prefix and returns any rejected item
without an implicit destructor or rollback.

Operations that compare entries require `T: core::cmp::Ord<T>` and use only
`T::lt`. The relation must be a strict weak order: irreflexive, asymmetric and
transitive, with transitive equivalence for tied priorities. Ordering-relevant
state must remain unchanged while an entry is stored. Custom records can compare
only their priority field. Equal priorities have no stable insertion order.
The existing f32 comparison works for ordinary finite values; NaNs require a
wrapper with an explicit ordering policy and are outside this heap's default
ordering contract.

The heap owns its vector allocation. Entry copies are shallow; the heap does
not clone or destroy allocations nested inside entries. Keep one active heap
owner and use `borrow()` when a helper needs to mutate it. A copied heap handle
aliases the same allocation and must not be independently destroyed. These
rules are conventions, not compiler-enforced moves or borrowing.

For owned nested resources, successful insertion transfers responsibility to
the heap's owner; a failed insertion leaves it with the caller. Pop and root
replacement transfer the removed entry back. Destroy remaining nested resources
before clearing or destroying the heap. Borrowed entries instead retain their
original external owner. `peek`, `as_view`, `from_view`, `try_extend` and
`try_clone` do not create independent nested resources.

Views expose initialized entries in unspecified heap order. Treat them and
ordering-relevant nested state as read-only. Mutations invalidate previous
views; failed fallible edits preserve them. The owner must outlive every view.
An input `View<T>` must satisfy its physical backing and lifetime preconditions.

The current `as_view` constructs its view directly from the owner's proven
initialized count. An earlier nested `unwrap(slice::view(...))` source shape
failed LNC0047 for a minimal i64 consumer. The
[original source and controls](../tests/fixtures/stdlib_compiler_state/checked_sample_heap/README.md)
are retained; the corrected method executes empty, full-width i64 and mixed
record views, plus the existing self-extension and generic-value contracts.
This source correction changes no backing storage or public signature and does
not establish that every unrelated generic layout composition works.

## API

```lanius
let scores: alloc::binary_heap::BinaryHeap<i64> =
    alloc::binary_heap::new(alloc::binary_heap::Order::Min);
let inserted: core::result::Result<i32, alloc::binary_heap::Error> =
    scores.try_push(42);
// Handle insertion failure before relying on the value being stored.
let first: core::option::Option<i64> = scores.pop();
scores.destroy();
```

| Operation | Contract |
| --- | --- |
| `new<T>(order)` | Empty heap, no allocation |
| `with_capacity<T>(capacity, order)` | Result containing an empty heap with room for the requested entries |
| `from_vec<T>(items, order)` | Consume the vector and heapify in place; no allocation |
| `from_view<T>(values, order)` | Result containing independent backing storage with shallow entry copies |
| `borrow()` | Reference to the actual owner |
| `len()`, `capacity()`, `is_empty()`, `order()` | Size, storage capacity and priority direction |
| `as_view()` | Borrowed view in unspecified heap order |
| `peek()` | Optional shallow copy of the highest-priority entry; ownership stays with the heap |
| `try_reserve(additional)` | Result containing capacity sufficient for `len + additional` |
| `try_push(value)` | Insert and return the new length, or an explicit error |
| `try_extend(values)` | Append the entire view and return the new length; self-aliasing is supported |
| `pop()` | Transfer the highest-priority entry, or None when empty |
| `replace_top(value)` | Transfer the old root and store the supplied value; empty returns None without inserting |
| `push_pop(value)` | Return the highest-priority entry of the incoming value and existing heap, retaining the rest |
| `try_clone()` | Independent vector containing shallow entry copies |
| `try_shrink_to_fit()` | Result containing capacity reduced to length for nonzero-sized entries |
| `take_vec()` | Transfer the backing vector in heap order; reset the heap to empty |
| `take_sorted_vec()` | Transfer a vector in pop order: Min ascending, Max descending; no allocation |
| `clear()` | Discard entries while retaining capacity |
| `destroy()` | Free backing storage and reset the owner |

An empty `replace_top` leaves the incoming value with its caller. An empty
`push_pop` returns the incoming value. If the incoming value ties or outranks
the current root, `push_pop` returns that incoming value unchanged, preserving
the identity of the existing root. Otherwise it replaces and returns the root.
These two methods and `pop` never allocate. They do not shrink capacity.

`from_vec` consumes the supplied vector by convention: stop using its old handle
and views. Both `take` methods leave the heap reusable in its original order.
Destroying the same reset owner twice is harmless; a stale copied handle remains
invalid. Sorting does not preserve the relative order of equal entries.

## Failure and resource bounds

Errors are `InvalidCapacity` for negative capacity requests,
`CapacityOverflow` when counts or storage exceed supported bounds, and
`AllocationFailed` when the allocator cannot provide storage. Lengths and
capacities use i32. Nonzero-sized storage is limited to `i32::MAX` bytes; the
entry limit is `floor(i32::MAX / size_of<T>())`.

Fallible mutations validate bounds and obtain storage before changing contents.
Failure preserves the original entries, capacity and borrowed views. Bulk
extension keeps the old allocation alive while copying aliased inputs and
copies every input before reordering. Empty extension is a successful no-op.
Clone failure preserves the source. Clearing does not free backing storage;
shrinking an empty nonzero-sized heap does.

Zero-sized entries allocate no storage. A positive reservation establishes
capacity `i32::MAX`; shrink leaves that logical capacity intact. Entry counts
and overflow checks still apply. Destroy and ownership transfer reset capacity
to zero. Empty clones need no allocation.

## Algorithms and costs

The implementation uses binary-heap sift-up, sift-down and bottom-up
construction, as described in [Princeton's MaxPQ implementation](https://github.com/kevin-wayne/algs4/blob/master/src/main/java/edu/princeton/cs/algs4/MaxPQ.java).
It uses zero-based indices and an explicit min/max order. Child existence is
checked before computing `2 * parent + 1`, avoiding index overflow at the count
limit. Shrinking is explicit, so removal cannot fail allocation.

The combined root operations follow the multiset behavior described by
[heapq's push/pop and replacement operations](https://docs.python.org/3/library/heapq.html).
Lanius uses Option for empty removal/replacement and Result for allocation
failure. Storage and nested-resource ownership are explicit.

For constant-cost comparisons and element copies:

- Peek, size queries, clear and vector transfer are O(1).
- Push, pop, replacement and push/pop require O(log n) comparisons. A push that
  grows storage also copies O(n) entries; geometric growth amortizes that copy.
- `from_vec` and `from_view` are O(n). Extending with m entries is O(n + m).
- Clone, relocating reserve and nonempty shrink copy O(n) entries.
- Sorted transfer takes O(n log n) time and O(1) extra storage.

The backing vector currently lives at `std::vec`. This is the same temporary
layering dependency used by String; move it and its consumers to `alloc` when
consolidating the vector API. The heap itself needs no host services beyond the
allocator.

## Example: largest scores

`sample_programs/top_scores.lani` reads K on the first line, then signed i64
scores. It retains the largest K scores in a min-heap, then prints them in
descending order, preserving duplicates. It combines heap operations, owned
byte input, streams, borrowed UTF-8 text and integer parsing/formatting.

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  sample_programs/top_scores.lani --stdlib-root stdlib \
  -o target/stdlib-work/top_scores
printf '3\n8\n-2\n10\n8\n4\n' | timeout --kill-after=2s 10s \
  target/stdlib-work/top_scores
# 10
# 8
# 8
```

K is 0–4,096; input is limited to 1 MiB and 100,000 score lines. ASCII whitespace
around numbers and one final newline are accepted; internal blank lines,
malformed UTF-8 and out-of-range numbers are rejected. K=0 still validates every
score. Header-only input succeeds without output. Score storage is O(K), but
the program buffers the complete input before parsing.

Exit codes are `0` success, `2` invalid input or a configured limit, `3` I/O
failure, and `4` allocation failure. Input is completely validated before
output begins. All owners are released on handled errors. Output failures can
leave a prefix. The low-level decimal/byte writers used here report interrupted
writes as I/O failures; input uses the stream adapter's interrupted-read retry.

## Execution evidence

On 2026-10-22, all five test groups in
`tests/stdlib_binary_heap_execution.rs` passed across focused runs:

- Contracts: empty and duplicate values, both priority directions, root
  replacement, vector transfer, clone independence, capacity errors, shrink,
  self-extension with and without growth, reset and reuse.
- Generic values: all ten integer types at their extrema, bool, char, finite
  f32, borrowed String values, and nested records with i64, Option<bool> and
  arrays. Zero-sized entries execute under a trace requiring no allocation.
- Model: 6,000 mixed commands for each priority direction, comparing complete
  outputs with a sorted multiset. Seed `0x4ea92026`, 32-bit LCG
  `1664525*x + 1013904223`; duplicate priorities and integer extrema are injected.
- Allocation failures: fail each observed allocation and every later one across
  construction, growth, reserve, shrink, aliased extension and clone. Check
  preserved contents, capacity and old views, plus complete allocation cleanup.
- Application: generated scores and all K boundaries, 100,000/100,001 records,
  exact input-byte limits, invalid encodings/numbers, all observed allocation
  failures and injected read/write errors. Reference seed `0x7a122026`.
- Complexity: 65,536 ascending records check the heap invariant, key range,
  sum and sum of squares. Bulk construction must use at most `2*n`
  comparisons; repeated insertion must use at most `16*n`. Wall time and exact
  comparison counts are not test gates.

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test stdlib_binary_heap_execution -- --nocapture
```

The first run found an untyped u32-maximum literal in the test fixture, checked
as i32 before its cast. Giving it a u32-typed local fixed the fixture; the generic
contracts then passed. No compiler changes were needed for this module.

## Native construction measurement

The complexity fixture `binary_heap_workload.lani` also compares both construction
paths in the same executable. Both reserve once, construct 65,536 records,
validate contents, release storage and print the comparison count. Each record
holds a key and a reference to the comparison counter.

On an AMD Ryzen 9 5950X, one warm-up pair followed by four alternating measured
pairs produced these medians:

| Construction | Comparisons | Native program time | Allocation calls | Peak requested bytes |
| --- | ---: | ---: | ---: | ---: |
| Bottom-up heap construction | 131,040 | 23.86 ms | 1 | 1,048,576 |
| Repeated insertion | 917,522 | 117.40 ms | 1 | 1,048,576 |

Timing includes comparison instrumentation, validation, process startup and
capturing stdout. The syscall traces confirm that both paths free their
allocation. Requested bytes are not RSS. This measures native library execution,
not GPU compiler throughput or a compiler regression.

Compile the fixture with the ordinary stdlib root; run without an argument for
bulk construction and with `push` for repeated insertion. Each measured process
had a ten-second bound. Raw measurements, source/binary hashes and traces are
under the ignored `target/stdlib-work/binary-heap-*` paths.
