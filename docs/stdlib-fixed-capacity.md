# Inline fixed-capacity collections

`core::vec::Vec<T, N>` and `core::set::Set<T, N>` store an `[T; N]` array and a logical length inline. Construction, copying, lookup, mutation, traversal, and sorting make no heap allocations. Capacity is fixed. `N = 0` is valid. Lengths and indices use `i32`; constructors reject capacities above `2147483647` by panicking.

Operations are free functions with borrowed `&Vec<T, N>` or `&Set<T, N>` parameters. Obtain a reference from a concrete owner with `.borrow()`. The language currently permits mutation through `&self`; this borrow is not a read-only reference. A generic function can accept the reference and forward it with both `T` and `N` symbolic:

```lanius
import core::vec;
import core::option;
import core::result;

fn push_and_pop<T, const N: usize>(owner: &core::vec::Vec<T, N>, item: T)
    -> core::result::Result<core::option::Option<T>, core::vec::Error> {
    let pushed: core::result::Result<i32, core::vec::Error> = core::vec::try_push(owner, item);
    if (core::result::is_err(pushed)) {
        return core::result::Err(core::result::unwrap_err(pushed));
    }
    return core::result::Ok(core::vec::pop(owner));
}
```

The caller can construct `let values: core::vec::Vec<i64, 2> = core::vec::from_storage([0, 0]);` and pass `values.borrow()`. There are no aliases for the former APIs that returned a silently unchanged container on failure.

## Vector operations

All entries below take a borrowed vector as their first argument. Reads return shallow copies of elements. Mutations change that owner in place.

| Operation | Return and behavior |
| --- | --- |
| `from_storage([T; N])` | Empty vector; supplied values are spare-slot filler. |
| `from_array([T; N])` | Full vector, in array order. |
| `len`, `capacity` | Current logical length and fixed capacity. |
| `is_empty`, `is_full` | Length predicates; both are true for capacity zero. |
| `get(index)`, `first`, `last` | `Option<T>`; invalid index or empty vector gives `None`. `last` also serves as stack peek. |
| `get_or(index, fallback)` | Copied element, or caller's fallback for an invalid index. |
| `try_push(item)` | `Result<i32, Error>` containing new length; `Full` leaves the owner unchanged. |
| `pop` | `Some(removed)` from the end, or `None` if empty. |
| `try_set(index, item)` | `Result<T, Error>` containing the displaced value; invalid index gives `Bounds`. |
| `try_insert(index, item)` | Insert before an index in `0..=len`; return new length. Invalid index gives `Bounds`, checked before `Full`. |
| `try_remove(index)` | Preserve remaining order; return the removed value or `Bounds`. |
| `try_swap(left, right)` | Return unchanged length on success, including swapping an index with itself; invalid indices give `Bounds`. |
| `reverse` | Reverse the active prefix and return its length. |
| `truncate(new_len)` | Keep exactly that prefix and return the number discarded. Requests outside `0..=len` give `Bounds`. |
| `clear` | Return the number discarded and set length to zero. |
| `as_view` | Borrowed `core::slice::View<T>` over exactly the active prefix. |
| `iter` | Borrowed, double-ended `core::slice::Iter<T>` over the active prefix. |
| `contains(item)`, `position(item)` | Linear search using `core::cmp::Eq<T>`; position returns the first index as `Option<i32>`. |
| `sort`, `is_sorted` | Ascending order using `core::cmp::Ord<T>`; sort returns length. |
| `lower_bound(item)`, `upper_bound(item)` | Sorted input required; return the first index at least / strictly greater than item, or length. |
| `binary_search(item)` | Sorted input required; return the first equivalent index as `Option<i32>`. |

Import `core::iter` to use this cursor's forward `next` method or shared generic
adapters/consumers. [Canonical cursor integration](stdlib-cursor-integration.md)
retains the existing factory signatures and symbolic `T,N` free functions.

Sort is stable insertion sort, with `O(len²)` comparisons and constant extra storage. An empty vector is sorted, its bounds are zero, and its searches return `None`. Binary search equality is the equivalence induced by the lawful total order. Native floats need a lawful order wrapper such as `core::float_order`; their ordinary partial comparisons do not satisfy `Ord`.

Every rejected vector mutation checks all logical preconditions before writing. It preserves length, contents, spare slots, and existing views. There is no allocation-failure branch because these operations do not allocate. Successful insert/remove shifts cost `O(len)`; push/pop and indexed reads/replacement are constant time.

## Set equality and operations

`core::set::Set<T, N>` uses `core::cmp::Eq<T>` directly. The relation must be reflexive, symmetric, and transitive, with `ne == !eq`. Equality can use the full value width and multiple record fields. Hashes, projected `u32` keys, and the removed `core::set::Key` trait are not involved. A lawful equality relation can intentionally ignore record metadata; the first stored representative remains until removal. Equality-relevant state, including data reached through shallow pointers or slices, must stay stable while stored. Mutating that data through an external alias can create equivalent representatives and violates the set contract.

All operations take a borrowed set first:

| Operation | Return and behavior |
| --- | --- |
| `from_storage([T; N])` | Empty set over copied inline filler. |
| `len`, `capacity`, `is_empty`, `is_full` | The corresponding vector-style queries. |
| `contains(item)` | Linear full equality lookup. |
| `position(item)`, `position_or(item, fallback)` | First insertion-order index, or `None` / supplied fallback. |
| `get(ordinal)`, `at_or(ordinal, fallback)` | Copied stored representative at its insertion-order index; invalid indices are absent. |
| `try_insert(item)` | `Result<bool, Error>`: `Ok(true)` inserted, `Ok(false)` already present, `Err(Full)` distinct item cannot fit. Duplicate lookup precedes fullness. |
| `remove(item)` | `Some(stored representative)` or `None` if absent. Remaining elements keep their order. |
| `clear` | Number discarded; length becomes zero. |
| `iter` | Borrowed double-ended cursor in insertion order. |
| `is_subset(other)`, `is_disjoint(other)`, `equals(other)` | Compare sets of the same element type and any capacities, passing the other set by reference too. Equality ignores insertion order. |

Insertion and removal preserve the complete owner on full/absent outcomes. Removal followed by insertion appends at the end. The empty set is a subset of every set, is disjoint from every set, and equals another empty set regardless of capacities. Membership and mutation are linear; cross-set predicates are `O(left.len * right.len)`.

No mutable set view is offered. A cursor's supported operations read values and move its position; changing its underlying `values` field would violate the set contract. Likewise, manually editing collection fields or implementing unlawful `Eq` can break uniqueness; the language does not enforce those invariants for applications.

## Copies, borrows, views, and nested ownership

A by-value collection copy owns an independent inline array. Mutating the copy does not change the original collection or the array supplied to construction. Elements themselves are shallow values: copying a pointer, slice, resource handle, or owning record does not clone its referenced resource. A `.borrow()` reference aliases one existing container; mutations through it affect that owner.

Only the prefix below logical length contains live elements. Filler and the stale tail after pop/remove/truncate/clear are not additional owners and must not be destroyed. Reads, cursors, views, and a by-value container copy do not transfer ownership by themselves. Applications must keep one active owner for each nested resource.

On successful vector push/insert, an application may treat the inserted value as transferred to the collection and stop using its original handle. Set insertion transfers it only on `Ok(true)`: `Ok(false)` retains the previously stored representative, so the caller still owns the uninserted input, including any distinct nested handle. On `Err(Full)` the caller also retains the input. Pop/remove and successful replacement return the value whose ownership leaves the collection. Destroy or transfer that returned value explicitly. `clear` and `truncate` only discard shallow values: remove and destroy resource-owning entries first if they must be released. There is no automatic destruction or deep clone.

Views and cursors borrow the original container storage. Keep that owner alive at the same location, and end all such borrows before successful structural mutation, moving/reassigning the owner, or discarding it. A copied collection gets different storage; an existing view still refers to the original. Indexed replacement through a vector view is permitted and visible to its owner. Returned element payloads can themselves contain borrowed data whose lifetime the application must preserve.

`as_view` retains the array's native descriptor and signed stride, rather than reconstructing addresses from element size. Cursor copies share the backing elements but have independent positions. Forward and backward iteration converge on one remaining range; once exhausted, both directions remain `None`. The standard slice cursor's advance operations reject negative counts without moving and clamp positive counts to the remaining range.

## Execution evidence and compiler boundary

`tests/stdlib_fixed_capacity_execution.rs` exercises successful and failed operations, bounds/full/absence distinctions, zero capacity, independent copies and aliases, view mutation, double-ended and copied cursors, stable record sorting, binary search boundaries, wide signed/unsigned equality, record representatives with a deliberately colliding former key projection, nested `Option<Result<Record, i64>>` payloads, zero-size records, raw slice and slice-bearing record payloads with signed descriptor strides, and explicit destruction of displaced and popped nested owners.

The deterministic stateful test guarantees successful replacement/removal, unequal sorting/reversal, shifting, fill/rejection, and set duplicate/full/absent transitions before seeded exploration. It compares 32 transitions against independent Rust vector and insertion-ordered set models using seed `0x8e37100dcafe2026`. It checks outcomes, returned values, all active entries, membership, and copy independence after each transition. The pure vector and set fixture programs are additionally traced on Linux when `strace` is available; their `brk`, `mmap`, `mremap`, and `munmap` traces must be empty.

The migrated `generic_record_vec.lani` consumer forwards borrowed vectors through multiple user generic functions with symbolic element types and capacities. It executes records, record arrays, nested records, `Option<Record>`, and `Pair<Record, i32>` payloads. `generic_containers.lani` exercises all public free collection functions, and `p50_user_impl_of_stdlib_bound_trait.lani` implements the imported equality contract for a user record.

The compiler still rejects imported **method** lookup on `Vec<T, N>` with symbolic `N` (`LNC0027`), including `.borrow()` inside such a user generic. Acquire references at concrete call sites and pass them into generic functions. The canonical free functions avoid that limitation. Reduced failure, fixed-capacity method control, and successful borrowed free function control live under `tests/fixtures/stdlib_compiler_state/fixed_capacity/`. No compiler or runtime change is part of these collection APIs.

Verified execution is x86_64 Linux output from the GPU compiler. Other targets
and user GPU kernels have not been verified.
