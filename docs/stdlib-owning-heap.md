# Owning heap iteration

`alloc::binary_heap::BinaryHeap<T>::take_iter()` transfers the canonical heap
into `alloc::binary_heap::IntoIter<T>`. It resets the actual source to an empty,
zero-capacity heap while preserving its `Order`. The source can then be reused
independently. The cursor implements the shared
[`Iterator<T>` protocol](stdlib-iterators.md).

All four focused groups pass through the GPU compiler and native Linux x86_64
CPU execution. The gate finished in **17.37 seconds**; its receipt is
`target/stdlib-work/owning-heap-native.log`. Other targets and user-program GPU
execution have separate acceptance requirements.

## API

The heap module adds:

```lanius
pub enum IntoIterError { Remaining(i32) }
pub struct IntoIter<T> { heap: BinaryHeap<T> }
```

| Operation | Effect | Bound |
| --- | --- | --- |
| `BinaryHeap<T>::take_iter() -> IntoIter<T>` | Transfer the heap and reset the actual source, preserving `Order` | None |
| `borrow() -> &IntoIter<T>` | Borrow the active cursor for generic consumers or cleanup | None |
| `remaining() -> i32` | Count of unconsumed values | None |
| `capacity() -> i32` | Original retained backing capacity | None |
| `order() -> Order` | Configured `Min` or `Max` order | None |
| `is_empty() -> bool` | Whether no values remain | None |
| `Iterator<T>::next() -> Option<T>` | Transfer the canonical heap's next priority value | `T: Ord<T>` |
| `try_finish() -> Option<IntoIterError>` | Reject a nonempty remainder; otherwise release backing and reset | None |
| `take_remaining() -> BinaryHeap<T>` | Transfer the valid remaining heap and reset the cursor | None |

Import `core::iter` to select `next`. Only pulling a priority value needs
`Ord<T>`; inspection, finish and recovery do not compare values. The cursor
contains the existing `BinaryHeap<T>` and retains its protected `std::vec`
backing contract.

## Priority and cost

Every successful `next` delegates to canonical `BinaryHeap::pop`. A `Min`
cursor yields ascending priorities; a `Max` cursor yields descending
priorities. Equal-priority representatives have no stable relative order.
Comparisons must define the same consistent, unchanged ordering required by
the [heap itself](stdlib-binary-heap.md).

A successful pull takes O(log n) heap work and performs no allocation. An
empty pull is O(1). Once empty, repeated pulls return `None`. There is no
`next_back`: a heap maintains one priority end. The existing borrowed
`BinaryHeap::iter()` visits physical heap storage in unspecified order; it
has its own [borrowed iterator contract](stdlib-heap-iterators.md).

Taking the cursor, inspecting its count/capacity/order, attempting finish and
recovering the remainder are O(1). Recovery does no sorting, heapification,
element copying, comparison or allocation. Cursor operations do not clone or
implicitly destroy nested values.

## One cleanup authority

End source views and borrowed cursors before `take_iter`. Keep one active
owning cursor handle. Ordinary descriptor copies alias the same allocation;
they cannot fork traversal, cleanup or storage release. Resetting the actual
source or cursor does not reset stale aliases. Public fields are not a
validation boundary. Preserve the canonical heap's invariants.

Each `Some(value)` removes that value from the heap before returning it and
transfers its cleanup authority to the caller. The caller must retain it,
transfer it into another owner or release it exactly once. Cursor cleanup
cannot release a value already yielded. End borrowed copies of an entry before
mutating or freeing that entry's nested owners. Transfer does not extend any
borrowed lifetime or repair self-references.

The cursor transfers only the authority its source actually held. Repeated
borrowed String descriptors inside a heap do not become distinct String
owners. Use the source's existing ownership policy when releasing such values.
The language does not enforce these rules.

## Finish or recover

Exhaustion retains the allocation and its capacity, including for an initially
empty heap with reserved storage. `try_finish()` on a nonempty cursor returns
`Some(IntoIterError::Remaining(count))` and leaves all values, capacity and order
unchanged. It can be resumed or recovered afterward.

With zero remaining, `try_finish()` releases the empty backing and resets the
cursor to zero capacity, preserving `Order`. It returns `None`. Repeating it
on that same reset cursor is harmless. It does not release yielded values.

`take_remaining()` transfers the current canonical heap, including its
allocation, initialized remainder, capacity and order. It resets the actual
cursor to an empty, zero-capacity heap with the same order. The recovered heap
can immediately be inspected, used for insertion or popped under `Ord<T>`.
Recovering an exhausted cursor yields an empty heap that still owns its
reservation. Recovering again from the reset cursor yields zero capacity.

```lanius
let heap: alloc::binary_heap::BinaryHeap<i32> =
    alloc::binary_heap::with_capacity<i32>(8,alloc::binary_heap::Order::Min).unwrap();
heap.try_push(4).unwrap(); heap.try_push(1).unwrap();
let cursor: alloc::binary_heap::IntoIter<i32> = heap.take_iter();
assert(heap.is_empty() && heap.capacity()==0);
assert(cursor.next().unwrap()==1);
let remaining: alloc::binary_heap::BinaryHeap<i32> = cursor.take_remaining();
assert(cursor.is_empty() && cursor.capacity()==0);
remaining.try_push(2).unwrap();
assert(remaining.pop().unwrap()==2 && remaining.pop().unwrap()==4);
remaining.destroy();
```

## Explicit deep cleanup

The opt-in `alloc::clone_binary_heap` module adds:

```lanius
pub fn destroy_binary_heap_iter<T>(owner: &alloc::binary_heap::IntoIter<T>)
    where T: core::clone::Destroy<T>;
```

It first recovers and resets the actual cursor, then uses existing
[`destroy_heap`](stdlib-clone-binary-heap.md) to release each remaining active
owner and the backing. It requires neither `Ord<T>` nor `TryClone<T,E>`.
Cleanup uses physical storage order and promises no priority order. The
library cleanup performs no allocation; a user-defined `Destroy` callback
retains its own behavior and cost while obeying the `core::clone::Destroy`
contract: it must finish without allocation, panic or reportable failure.
Repeated calls on the same reset cursor are harmless. Each remaining entry
must be one distinct active owner under `Destroy<T>`.

Adapters that discard values do not destroy transferred owners. For
`try_transfer_up_to`, the accepted prefix belongs to the sink, the rejected
item belongs to the caller, and the unconsumed remainder belongs to the cursor.
Release or recover the rejected item before resuming. Finishing or destroying
the cursor does not clean up the accepted or rejected values.

## Focused gates

All four groups in `tests/stdlib_owning_heap_execution.rs` passed. They contain
six compilation jobs: three strict ELF programs and three source rejections.
The programs execute four times in total, including the lifecycle program's
baseline and allocation-canary runs:

- A multiset oracle checks 144 bounded cases across both orders, ties,
  empty/partial/full prefixes, imported generic `Iterator` dispatch, actual
  source reuse, O(1) recovery and reinsertion. It checks 1,368 transferred
  multiword representatives without requiring a tie order.
- Ten distinct binary/UTF-8 String owners exercise yielded-owner reinsertion,
  remaining-only cleanup and a rejecting sink followed by zero-quota and
  successful resumed transfer. Comparison guards reject accidental ordering
  work during recovery or deep cleanup.
- Empty and reserved owners, nine zero-sized values, no-trait empty lifecycle,
  and a nonempty Destroy-only type exercise the minimal bounds. Typed public
  backing initialization uses no cast or alternative storage representation.
- Three actual source calls reject missing `Ord<T>`, missing `Destroy<T>` and
  a `Destroy<Other>` implementation substituted for `Destroy<T>`.

The driver preserves the shared strict ELF checker. Exact address/length
mapping ledgers confirmed every backing and String allocation was released
once, with no extra cursor allocations. The lifecycle program passed with its
next, eighth `mmap` armed to fail; that call remained unreachable. All three
negative calls produced source-local `LNC0008` rejections. These checks are
finite acceptance evidence, not a formal proof or a claim about all heap
programs.
