# Deep cloning heap memory owners

`alloc::clone_binary_heap` adds opt-in deep cloning and explicit destruction to
`alloc::binary_heap::BinaryHeap<T>`. The heap has one concrete type with
`Order::Min` or `Order::Max`; the clone preserves that order. Ordinary heap
`try_clone`, `clear` and `destroy` retain their documented shallow behavior.

All five focused groups pass through actual GPU compilation and native
Linux x86_64 execution. They cover both priority orders, nested ownership,
empty/zero-sized values, typed failures and balanced allocation cleanup.

## API and imports

Import `alloc::clone_binary_heap` in the entry and in generic consumers that
select its protocol implementations. Its public surface is:

```lanius
pub enum Error<E> {
    Storage(alloc::binary_heap::Error),
    Element(i32,E),
}

pub fn try_clone<T,E>(source: &alloc::binary_heap::BinaryHeap<T>)
    -> core::result::Result<alloc::binary_heap::BinaryHeap<T>,Error<E>>
    where T: core::cmp::Ord<T>,
          T: core::clone::TryClone<T,E>,
          T: core::clone::Destroy<T>;

pub fn destroy_heap<T>(owner: &alloc::binary_heap::BinaryHeap<T>)
    where T: core::clone::Destroy<T>;
```

The module also implements
`TryClone<BinaryHeap<T>,Error<E>>` for heaps with the same three leaf bounds,
and `Destroy<BinaryHeap<T>>` when the leaf implements `Destroy<T>`. `E` is an
explicit selected error type, following the existing
[recursive Vec protocol](stdlib-nested-clone.md).

For example, a `BinaryHeap<String>` deep clone has error
`alloc::clone_binary_heap::Error<alloc::string::Error>`. A heap of user records
that clone nested `Vec<String>` can retain
`Error<alloc::clone::Error<alloc::string::Error>>` without erasing either layer's
index or error payload. Import `alloc::clone_vec` where that nested vector
implementation is selected.

Generic factories need an explicit element type when the expected type would
otherwise have to flow through `Result::unwrap`, for example:

```lanius
let source = alloc::binary_heap::with_capacity<alloc::string::String>(5,alloc::binary_heap::Order::Min).unwrap();
```

A destination `BinaryHeap<String>` annotation alone does not supply that
inference through the nested result. Explicit factory arguments or a typed
`Result` intermediate follow the [existing compiler inference boundary](library-dependencies.md);
the clone API and production heap are unchanged by that limitation.

## Cloning and failures

The source is a read-only borrowed descriptor. Its backing, capacity, values,
priority order and existing borrowed views remain unchanged on success and
failure. Repeated borrowed leaf descriptors are permitted: each successful
clone owns a separate value. The source's actual owners remain the caller's
responsibility.

The implementation reserves one final backing vector before leaf calls, then
clones each initialized heap entry once in `source.as_view()` storage order.
It retains the newest returned `std::vec` descriptor after every mutation.
Successful staging transfers directly to the heap's existing `from_vec`, which
performs bottom-up heapification without another allocation or clone. Clone
cost is the sum of leaf clone costs plus O(n) heap work; backing capacity may
differ from the source.

The heap currently uses its existing `std::vec` backing contract. This module
preserves that boundary and reports the heap's own `InvalidCapacity`,
`CapacityOverflow` and `AllocationFailed` storage errors. It does not convert
the heap to another vector implementation or add compatibility aliases.

`Element(index,E)` identifies a source heap-storage position, not an index in
sorted pop order. Ties have no stable traversal order beyond the source view
used for that call. On leaf failure, the implementation retains `E`, destroys
every completed independent clone, frees the staging vector, and returns the
same owned error payload. No destructor runs on `E`. Its owner must release it
under the leaf's contract; it must not borrow a partial destination that this
cleanup releases.

A leaf's `TryClone` implementation remains responsible for preserving its
borrowed source and releasing its own partial value before returning `Err`.
The heap cannot repair a leaf that violates that protocol. The leaf's ordering
must remain lawful and stable while stored, and a successful clone must
represent the same logical value.

## Destruction and transfers

`destroy_heap(actual_owner.borrow())` first takes the backing vector, resetting
that actual heap to empty with zero capacity and preserving its configured
order. It then invokes `Destroy<T>` once on each stored owner and releases the
backing once. No comparison, cloning, allocation or `Ord<T>` bound is needed.
Repeated destruction through the same reset owner is harmless.

Every stored value passed to deep destruction must be a distinct active memory
owner. A heap that only borrows repeated String or vector descriptors must be
released shallowly, and its separate source owners released once. A copied heap
descriptor is not another owner. The trait's by-value `destroy_value` consumes
the passed descriptor without resetting inactive aliases elsewhere.

`pop`, `replace_top`, `take_vec` and `take_sorted_vec` transfer their returned
owners to the caller. Remove a value from the heap before changing priority or
growing nested owners. Do not grow a String or vector reached through `peek`
or `as_view`: it is still a shallow borrowed descriptor. The focused contracts
pop an owned record, remove its String from the nested row, grow it, then
restore that String owner before releasing the record.

Empty clones allocate nothing. Nonempty zero-sized leaves need no backing
allocation when the current heap engine provides its zero-sized capacity;
their clone/destroy protocols still run for each logical element. These
protocols add no automatic moves, borrowing checks or destruction.

## Focused verification

[`tests/stdlib_clone_binary_heap_execution.rs`](../tests/stdlib_clone_binary_heap_execution.rs)
contains five runtime groups using only the production stdlib and the durable
[heap-clone fixture root](../tests/fixtures/stdlib_foundation/clone_binary_heap):

- Min/max heaps of String and ordered records owning nested Vec/String data,
  selected both directly and through imported generic trait consumers. Checks
  release source storage first, mutate transferred owners independently, verify
  duplicate counts, and reset actual owners through repeated destruction.
- Empty and zero-sized paths with a mapping ledger requiring zero allocations,
  plus destruction instantiated for a leaf with neither Ord nor Clone.
- Thirteen reached allocation positions across source setup, heap reserve,
  nested vector reserve and String leaves. The fixture reports typed storage
  and nested element errors; runtime `size_of` values determine expected byte
  requests. Each injected OOM must preserve source fields/views and balance
  every successful mapping.
- Both orders, four physical source positions and two leaf failure stages.
  Errors own separate binary String messages, which are inspected only after
  destination-prefix and source cleanup. The ledger checks each message is
  released last, and injects failure at all 96 reached baseline allocations,
  including the error-message allocation itself.
- An independent Rust priority/multiplicity model for 96 tied records in each
  order. It checks the 192 popped priority/id pairs and their complete ID set,
  without assuming tie order or a particular heap shape.

All native processes are bounded, and every produced ELF passes the unchanged
strict native transfer checker. The retained receipts are:

| Gate | Result | Receipt |
| --- | --- | --- |
| String/nested-record ownership contracts | 1 group passes in 5.96 s | `target/stdlib-work/clone-heap-contracts-current.log` |
| Model, empty/ZST, typed allocation failures and owned errors | 4 groups pass in 12.01 s; all 13 nested and 96 owned-error allocation failures pass | `target/stdlib-work/clone-heap-model-failures.log` |

These receipts establish Linux x86_64 CPU execution of GPU-compiled programs.
They do not establish Wasm, other platform or user GPU execution support.

From the repository root, after the required compiler build:

```sh
timeout --kill-after=2s 110s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test stdlib_clone_binary_heap_execution -- --nocapture --test-threads=1
```

The source contracts are the existing [clone protocols](stdlib-clone.md),
[nested Vec cloning](stdlib-nested-clone.md), and
[binary heap ownership/bulk build](stdlib-binary-heap.md).
