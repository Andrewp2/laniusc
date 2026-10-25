# Recursive deque cloning

`alloc::clone_deque` opts a deque into `core::clone::TryClone` and
`core::clone::Destroy`. It duplicates initialized entries through their selected
leaf protocols, including nested Strings, vectors, and deques. Ordinary
`Deque.try_clone()` and `Deque.destroy()` keep their shallow entry policy.

## Import and call

Import the opt-in implementations in both the composition entry and each generic
consumer that selects them. For `Deque<Vec<String>>`, the canonical imports are:

```lani
import alloc::clone;
import alloc::clone_deque;
import alloc::clone_vec;
import alloc::deque;
import alloc::string;
import alloc::vec;
import core::clone;
import core::result;

fn duplicate(source: &alloc::deque::Deque<alloc::vec::Vec<alloc::string::String>>)
    -> core::result::Result<alloc::deque::Deque<alloc::vec::Vec<alloc::string::String>>,alloc::clone_deque::Error<alloc::clone::Error<alloc::string::Error>>> {
    return alloc::clone_deque::try_clone<alloc::vec::Vec<alloc::string::String>,alloc::clone::Error<alloc::string::Error>>(source);
}
```

The module provides:

| API | Contract |
| --- | --- |
| `Error<E>::Storage(alloc::deque::Error)` | Outer deque storage failed. |
| `Error<E>::Element(i32, E)` | A leaf failed at this logical front-to-back index. |
| `try_clone<T,E>(&Deque<T>) -> Result<Deque<T>,Error<E>>` | Requires `T: TryClone<T,E>` and `T: Destroy<T>`. |
| `destroy_deque<T>(&Deque<T>)` | Requires only `T: Destroy<T>`; consumes entries, frees backing storage, and resets the actual owner. |
| `TryClone<Deque<T>,Error<E>> for Deque<T>` | Delegates to `try_clone` with the same leaf bounds. |
| `Destroy<Deque<T>> for Deque<T>` | Recursively releases the passed owner descriptor. |

An error index refers to the initialized logical sequence, regardless of the
ring's physical head or split into two views. Capacity and physical placement are
not part of the clone's value contract. The source must be a valid deque and must
remain unchanged throughout the call, including mutation through aliases.

## Ownership and rollback

The helper reserves space for all outer entries before calling any leaf. It then
clones only initialized entries in logical order. Empty deques and zero-sized
entry storage require no allocation. Zero-sized entries still receive their
individual clone and destruction calls.

Each successful leaf transfers a separate destination owner. If a leaf returns
`Err(E)`, that leaf must have released its own partial result. The deque helper
releases every completed destination entry and its outer storage, then returns
`Element(index,E)`. It preserves `E` without interpreting or destroying it. If a
destination insertion fails, the helper also releases the current successful
leaf before cleaning up the completed prefix.

`E` retains its own lifetime and cleanup contract. It may contain an independent
String or another owned payload; it cannot borrow a partial destination that
rollback will release. The caller owns any cleanup that the returned error needs.

All selected `Destroy` implementations must be infallible, allocation-free, and
finish without panicking. These protocols manage memory owners. They do not add
automatic destruction, moves, reference counting, or fallible resource closing.
The helper imposes no aggregate quota on nested leaf allocations. Its own work
is linear in the initialized entry count, plus the selected leaf work.

### Borrowed aliases and independent clones

A deque may hold repeated borrowed descriptors while their actual backing owners
remain live. Such a source can be cloned: each successful clone must be independent
of the source and every other destination entry. The source's outer storage can
then be released shallowly, and each original backing owner released once.

Do not deep-destroy a source whose entries repeat borrowed owner descriptors.
`destroy_deque` requires cleanup authority for every entry. Descriptor copies
alias one owner; copying does not create another cleanup authority.

### Mutating nested owners

An accessor returns a shallow descriptor. Before a nested operation can grow or
replace backing storage, transfer the actual child out with `remove`,
`pop_front`, or `pop_back`. Mutate the transferred owner and reinstall its updated
descriptor into the vacated capacity, including on an error path. For example:

```lani
let row: alloc::vec::Vec<alloc::string::String> = rows.pop_front().unwrap();
let text: alloc::string::String = row.remove(0).unwrap();
let edited = text.try_push_scalar(88);
row.try_insert(0,text).unwrap();
rows.try_push_front(row).unwrap();
// Handle edited after the active owner descriptors have been reinstalled.
```

The contract fixture follows this pattern for both `Deque<Vec<String>>`
and `Vec<Deque<String>>`. It destroys the original source owners before reading
the deep copies, grows one transferred String, checks independent siblings, and
tests a popped owner surviving destruction of its former container.

### Resetting an owner

Call `destroy_deque(owner.borrow())` when the actual owner must remain reusable.
It removes and destroys each initialized entry before calling the ordinary
shallow storage release, leaving length, capacity, head, and storage empty.
Calling it again on that reset owner does nothing.

The trait method takes a descriptor by value. After
`T::destroy_value(owned)`, any shallow aliases of the consumed owner must remain
inactive. The by-value call cannot reset stale copies in other variables.

## Focused verification

The Linux x86-64 execution gate is:

```sh
cargo test --test stdlib_clone_deque_execution -- --test-threads=1
```

Execution status: all four test groups passed through the production GPU
compiler and native Linux x86-64 execution. The gate compiled five programs and
ran 51 native executions, including the 379 model cases within one process.

| Receipt | Passed coverage | Reported duration |
| --- | --- | --- |
| `clone-deque-contracts-first.log` | Nested ownership contracts, empty and zero-sized paths | 7.80 seconds |
| `clone-deque-model-failures.log` | Logical model, all 13 nested allocation failures, six owned error paths, and all 33 owned-error allocation failures | 12.28 seconds |

These receipts establish runtime support for the tested native Linux x86-64
profile. The CPU oracle sanity check also passed all 379 generated model cases.

All five programs passed the strict shared native executable checker. Coverage
includes:

- Nested opt-in traits, wrapped rings, repeated borrowed source descriptors,
  transferred owner mutation, recursive release, repeated reset, and a leaf with
  only `Destroy`.
- Empty and wrapped zero-sized paths, with exact leaf-call events and no mapping
  allocation or release.
- 379 cases covering capacities through six, every head, retained length, and
  logical failure position. A mathematical interval model checks the value order,
  clone calls, completed owner set, and unchanged source metadata. Cleanup order
  is not part of the oracle.
- Thirteen reached allocation failures in `Deque<Vec<String>>`. Runtime
  `size_of` values determine mapping sizes, and returned typed errors identify
  the exact outer row and inner leaf index.
- Six failures across three logical positions and two leaf stages. Their generic
  error payload includes a high-bit integer, an array, and an independently owned
  String. Every one of the 33 reached allocation attempts is also failed once.

The mapping ledger requires a matching release for every successful mapping,
no double release, and no allocation after the injected failure. For owned errors,
it checks that the caller releases the error String after all source, partial,
and completed destination owners have gone. These tests cover the stated finite
cases and failure paths; they do not prove arbitrary leaf implementations valid.

Sources: [implementation](../stdlib/alloc/clone_deque.lani),
[execution gate](../tests/stdlib_clone_deque_execution.rs), and
[fixtures](../tests/fixtures/stdlib_foundation/clone_deque/).
