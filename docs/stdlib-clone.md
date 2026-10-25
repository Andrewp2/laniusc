# Fallible cloning and explicit memory-owner release

`core::clone` defines explicit value-cloning and memory-release protocols.
`alloc::clone` uses them to clone every element of a borrowed View into an
independent `alloc::vec::Vec`. Allocation failures and element errors are
reported, and completed destination elements are released on error. Production
behavior is Lanius; the allocator supplies memory.

The optional [nested Vec module](stdlib-nested-clone.md) supplies explicit
TryClone/Destroy implementations for Vec when its entries satisfy the leaf
protocols. It reuses this engine at every level, retaining nested error indexes
and cleanup. Ordinary collection clone/destroy methods keep their shallow
policies. Mutating a nested owner through a copied handle requires transferring
it out and restoring its updated descriptor before recursive release.

## Protocols

```lanius
pub trait TryClone<T,E> {
    pub fn try_clone_value(source: T) -> core::result::Result<T,E>;
}
pub trait Destroy<T> {
    pub fn destroy_value(owned: T);
}
```

Passing `source` copies its ordinary value or handle. For this protocol that
copy is a read-only borrowed descriptor: cloning must preserve the source and
its existing views. Each `Ok` preserves its logical value/content and transfers
a separate owner, independent of the
source and every other successful clone. Returning the same cached owner for
two calls violates the contract, including calls on duplicate source handles.
Types must state what their owned resources and borrowed external lifetimes
are. There is no blanket implementation for arbitrary records or pointers.

An element `Err` must release that call's partial construction before returning.
The error retains its own ownership and lifetime contract. It may own memory or
borrow caller storage, but it must not borrow destination data that failure
cleanup will release. An error containing an owned String transfers that String
to the caller; copying the error descriptor does not create additional owners.
The caller explicitly releases such resources after inspecting the error.

`Destroy::destroy_value` logically consumes one valid memory owner. It must
finish without allocating, panicking, or reporting failure. It is explicit
manual release, not automatic Drop, and is unsuitable for file/socket resources
whose close can fail. After passing an owned descriptor to it, stop using that
descriptor and its borrowed views. By-value release cannot reset other shallow
copies of the descriptor.

Owned String implements both protocols. Its clone copies UTF-8 bytes into an
independent allocation, preserving NUL and all valid scalars. Its clone error is
`alloc::string::Error`; valid String cloning can fail allocation. Its Destroy
implementation releases the String's byte storage. User records containing
several owners implement their own field-by-field construction and cleanup.

These protocols do not introduce compiler-enforced uniqueness, moves,
destructors, derive, implicit cloning, or automatic cleanup during panic/trap.
The [manual ownership conventions](library-api-conventions.md) still apply.

## Clone a View

```lanius
alloc::clone::from_view<T,E>(source: core::slice::View<T>)
    -> Result<alloc::vec::Vec<T>,alloc::clone::Error<E>>
    where T: core::clone::TryClone<T,E>, T: core::clone::Destroy<T>

alloc::clone::Error<E> = Bounds
    | Storage(alloc::vec::Error)
    | Element(i32,E)
```

The helper first validates nonnegative logical start/count and their checked
sum. It then reserves the complete outer vector before invoking any element
clone. Elements are cloned in increasing logical index order; the returned Vec
preserves that order. `Element(index,error)` reports the zero-based logical
index and transfers the exact typed error. It is relative to the selected View,
not its underlying start. `Storage` preserves the vector's capacity/overflow/
allocation error; `Bounds` denotes malformed View metadata.

On success, the caller owns every returned entry and the outer allocation.
On a recoverable error, the helper releases all completed destination entries
and outer storage. The failing element is responsible for its own unfinished
fields. Only destination resources are released: source owners, contents,
capacity and existing views stay valid. No partially cloned vector is returned.
Cleanup ordering is not an API promise.

The source must physically back the selected initialized entries and remain
alive and immutable throughout the call. Valid nonzero starts and native
physical strides are supported through `View.get`. Metadata validation cannot
prove physical backing, and source storage must not overlap mutable owner
metadata. Duplicate borrowed source descriptors are allowed; they are not
separate owners to destroy. No source entry is consumed.

Empty Views return an empty vector without allocation or element calls.
Zero-sized elements retain their logical counts and use the vector's documented
zero-sized capacity behavior. Outer count and byte capacity follow
[`alloc::vec`](stdlib-vec.md), including the `i32::MAX` byte limit for nonzero
elements. Nested resource limits and costs are those of the element clone.
There is no aggregate nested-memory quota or clock deadline in this API.

The helper performs O(n) container work plus the sum of element-clone costs;
failure additionally releases the completed prefix. It reserves outer storage
once. Those bounds assume the user implementations terminate and honor the
protocol. A panic, invalid physical source, or violating Destroy implementation
does not have the recoverable cleanup guarantee.

## Release a cloned vector

```lanius
alloc::clone::destroy_vec<T>(owner: &alloc::vec::Vec<T>)
    where T: core::clone::Destroy<T>
```

This helper removes and releases each initialized entry, frees the outer
allocation, and resets the actual Vec owner to empty with zero capacity. It
needs no TryClone bound or error type, allocates nothing, and supports empty
owners and repeated calls on that same reset owner. All earlier views and
borrowed entry copies become invalid.

Every entry must be a distinct active owner under its Destroy implementation.
This condition holds for a successful `alloc::clone::from_view` result. A Vec
built by shallow `alloc::vec::from_view` or `try_clone` of borrowed String handles
is not eligible merely because String implements Destroy: releasing those
borrowed handles could destroy the original owners or release one allocation
twice. Resetting the actual Vec does not reset stale Vec/String aliases.

Use ordinary Vec removal/pop to transfer an entry out when it needs separate
mutation or ownership. Release that transferred entry once, and use
`destroy_vec` for the entries still in the vector. Calling ordinary
`Vec.destroy()` alone releases only outer storage; it does not release nested
String allocations.

## Release an owning cursor's remainder

```lanius
alloc::clone::destroy_vec_iter<T>(owner: &alloc::vec::IntoIter<T>)
    where T: core::clone::Destroy<T>
alloc::clone::destroy_deque_iter<T>(owner: &alloc::deque::IntoIter<T>)
    where T: core::clone::Destroy<T>
```

These helpers explicitly consume remaining items front-to-back and call
`T::destroy_value` once for each. They recover the drained empty collection with
`take_remaining()`, which disarms the cursor, then call the canonical owner's
`destroy()` to release backing. They require no TryClone or Clone bound,
allocate nothing and support empty or already finished cursors. Every remaining
entry must be one valid owner under
Destroy; ordinary borrowed aliases are not eligible solely because their type
implements the trait. End remainder views before calling either helper.

[`take_iter()`](stdlib-owning-iterators.md) resets the actual source collection
and transfers its storage and source item cleanup authority to one active
cursor. Successful pulls transfer individual cleanup duties to their caller.
The helper releases only items still unconsumed; yielded and rejected items
must be handled separately. Skipping, filtering, unmatched Zip and other
discarding operations can lose transferred owners. A later Destroy helper
cannot recover them, even if the exhausted cursor finishes successfully.

The canonical empty-owner release avoids the helper-only finish-result replay
dependency documented in the
[owning-cursor guide](stdlib-owning-iterators.md#remaining-compiler-dependency).
It does not claim a compiler fix or require caller-side error projections.

## Existing collection clones

Existing `Vec.try_clone`, Deque, map, set and heap clones continue to allocate
independent container storage with shallow entry/key/value copies. They do not
invoke this protocol. String's existing `try_clone()` already copies its owned
bytes. A new user record's protocol implementation is an explicit choice;
containers do not silently acquire deeper destruction behavior.

## Focused verification

`tests/stdlib_clone_execution.rs` contains native contracts for independent
String and nested owners, duplicate aliases, nonzero/count/strided Views,
zero-sized values, Destroy-only types, malformed metadata and allocation-free
empty results. Its failure fixture selects every element and both partially
constructed fields, returns an error owning a String after prefix cleanup,
uses that String after the original source is destroyed, and releases it at
the caller. Allocation injection visits every mapping reached by the fixture;
ledgers compare exact mapping addresses and requested lengths.

Native acceptance on 2026-10-23 covers Linux x86-64 programs compiled by the GPU
compiler. The independent-owner contracts passed 1/1 in 6.38 seconds; metadata,
typed capacity preflight and trap-on-leaf empty checks passed 1/1 in 5.47 seconds.
The owned-error gate passed all 12 element/field cases and all 83 reached
allocation-failure positions, with exact address/length cleanup ledgers. It was
not rerun after the [empty-function lowering correction](compiler-unit-body-contract.md) because
its native behavior was already green. The two previously blocked groups were
rerun individually after that correction; no whole collection suite was run.

The fourth Rust test compiles `clone_fixture/zero_sized.lani`, passes the unchanged
shared x86 checker, and executes it with no mapping or unmapping calls. It checks
three logical zero-sized entries, the vector's `i32::MAX` zero-sized capacity,
and explicit destruction through an empty-body user implementation. It also
has a separate successful manual compile/checker/native trace. The durable
fourth Rust gate passed 1/1 in 4.09 seconds.

Logs are under `target/stdlib-work/clone-production/`: `final-contracts.log`,
`final-metadata.log`, `focused-second.log`, `final-zero-sized-rust.log`, and
`final-zero-sized.trace`.
`final-identity.txt` records the repository head, CLI hash, and the hash of the
actual SPIR-V artifact manifest; `final-compiler-version.log` records reported
build metadata. These results establish native execution, not only declarations
or type checking. Wasm and GPU execution of user programs remain unestablished.
