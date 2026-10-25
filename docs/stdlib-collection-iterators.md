# Collection and text iterators

Borrowed collection cursors, set-bit cursors and UTF-8 scalar cursors implement
the shared [`core::iter::Iterator<T>` protocol](stdlib-iterators.md). Their
existing `.next()` calls also work through generic consumers, `take` and
`chain`. Each cursor has one item type:

| Constructor | Cursor | Item |
| --- | --- | --- |
| `alloc::vec::Vec<T>::iter()` | `core::slice::Iter<T>` | `T` |
| `alloc::deque::Deque<T>::iter()` | `alloc::deque::Cursor<T>` | `T` |
| `alloc::hash_map::HashMap<K,V>::iter()` | `alloc::hash_map::Iter<K,V>` | `alloc::hash_map::Entry<K,V>` |
| `alloc::tree_map::TreeMap<K,V>::iter()` or `range(lower,upper)` | `alloc::tree_map::Cursor<K,V>` | `alloc::tree_map::Entry<K,V>` |
| `alloc::hash_set::HashSet<T>::iter()` | `alloc::hash_set::Iter<T>` | `T` |
| `alloc::tree_set::TreeSet<T>::iter()` or `range(lower,upper)` | `alloc::tree_set::Cursor<T>` | `T` |
| `core::bitset::BitView::iter_ones()` or `alloc::bitset::BitSet::iter_ones()` | `core::bitset::Ones` | `i32` bit index |
| `core::text::Text::scalars()` | `core::text::Scalars` | `core::text::Scalar { byte_index, value }` |
| `core::text::Text::iter_bytes()` | `core::slice::Iter<u8>` | `u8` |

Each cursor offers `borrow()` for adapters and consumers. Deque cursors retain
`remaining()` and `next_back()`. Ordered map and set cursors retain `is_empty()`
and `next_back()`. Front and back calls share one cursor position and cannot
yield the same element twice. Tree ranges remain half-open. Hash traversal order
is unspecified; tree traversal follows key order. Set cursors continue to use
the map engines through their existing typed facade and storage boundary.

```lani
let values: alloc::vec::Vec<i32> = alloc::vec::new();
let added: core::result::Result<i32, alloc::vec::Error> = values.try_push(7);
assert(core::result::is_ok(added));
let cursor: core::slice::Iter<i32> = values.iter();
let selected: core::iter::Take<core::slice::Iter<i32>, i32> =
    core::iter::take<core::slice::Iter<i32>, i32>(cursor.borrow(), 1);
let progress: core::iter::Advance =
    core::iter::advance_up_to<core::iter::Take<core::slice::Iter<i32>, i32>, i32>(selected.borrow(), 2);
// progress == { advanced: 1, exhausted: true }.
values.destroy();
```

These cursor constructors and adapter bookkeeping allocate nothing; sources
and mapping callbacks retain their own behavior. `Vec.iter()`
captures the owner's initialized prefix. `Text.iter_bytes()` captures its byte
range, including a nonzero start. Both retain the existing native slice
descriptor and stride through `core::slice::Iter`; byte values in packed storage and
strided stack arrays have the same logical sequence.

`Scalar.byte_index` is relative to the selected Text, including for a Text
subview. `value` is the Unicode scalar as `u32`. Scalar iteration follows the
valid UTF-8 view and advances by one to four bytes. Byte iteration exposes the
encoded bytes individually.

## Ownership and state

These borrowed cursors return shallow copies. Map entries copy both key and
value shallowly; set items copy their key shallowly. Yielding, skipping or
discarding a borrowed owner handle does not clone it, transfer its cleanup
authority or call `Destroy`. A yielded
`String` can share the allocation owned by an element or another handle. Keep
one release authority for each allocation and release nested owners once,
after all borrowed uses.

Vec and deque also provide separate
[`take_iter()` owning cursors](stdlib-owning-iterators.md). They transfer storage,
reset the actual source and hand off each consumed item's source cleanup
authority. Their copied handles must not fork traversal or cleanup. Exhaustion
retains backing until explicit finish or recovery. Discarding such a yielded
owner can leak it; a remainder Destroy helper cannot recover it. The borrowed
cursor copy and lifetime rules below apply to the table above.

Copying a leaf cursor forks its position while keeping the same backing
storage. Copying an adapter copies its quota and terminal state while sharing
its borrowed upstream cursor. The source cursor object must outlive every
adapter borrowing it; keeping only the collection alive is insufficient.
Lanius does not enforce these lifetimes.

The source APIs retain their existing invalidation rules:

- Vec and deque successful edits, storage changes and destruction invalidate
  earlier views and cursors. Failed fallible edits preserve them.
- Map and set mutations and destruction invalidate outstanding cursors and
  borrowed entry/key views. Ordered-map failed fallible edits preserve cursors.
- Text backing must stay alive and unchanged while its cursors exist. A cursor
  retains its copied Text descriptor, so the original Text record need not stay
  in scope.
- Ones captures its BitView metadata and reads current backing words. Valid bit
  changes before exhaustion can affect later items. After the first `None`,
  later bit changes cannot revive that cursor. Backing storage must remain valid.

Every integrated source is fused: after its first `None`, subsequent `next`
calls return `None`. Preserve constructor invariants and cursor fields. Public
fields do not make forged metadata, rewound positions or invalid owner aliases
safe. Concurrent cursor access is outside these contracts.

Slice, deque, hash, Text, Ones and adapter cursor construction is O(1). Ordered
tree cursors and ranges take O(log n) to locate their endpoints. Per-item work
follows the source: deque and slice access are O(1), tree cursor advancement
can traverse O(log n) links, hash cursors can scan empty or deleted buckets,
and Ones can scan backing words. Generic `advance_up_to` bounds direct `next`
calls; it does not bound each source call's internal work.

## Native verification

The original gates below used the earlier `core::iter::SliceIter<T>` wrapper
for Vec/Text bytes. [Canonical cursor integration](stdlib-cursor-integration.md)
replaces that wrapper with `core::slice::Iter<T>` and records current execution
of the shared forward protocol and its backward operations.

All three focused groups in the
[`stdlib_collection_iterator_execution` driver](../tests/stdlib_collection_iterator_execution.rs)
passed on x86_64 Linux. The GPU compiler emitted three ELF programs; each passed
the unchanged common x86 jump checker and ran once. The 408 collection model
commands ran inside one of those three native processes.

| Group | Accepted behavior | Gate time | Log |
| --- | --- | --- | --- |
| Collections | All 408 host sequence models passed: wrapped deque mixed ends, ordered tree ranges, hash tombstones and wide compound entries, both set facades through borrowed Take and bounded consumers | 6.31 s | `collections.log` |
| Text and bits | Packed and strided Text subviews, all UTF-8 widths, relative scalar offsets, captured bitset metadata, live bit changes, copied positions and fused exhaustion; empty mmap/munmap trace | 5.14 s | `views.log` |
| Owner aliases | Vec String aliases remain usable after Vec storage release; exactly two allocations, each released once with matching address and size, Vec before String; no implicit clone or destruction | 5.50 s | `owners.log` |

The Rust driver build took 1.16 s (`build.log`). All four logs are under
`target/stdlib-work/collection-iterator-admission/`. The accepted test binary was
`target/stdlib-build/debug/deps/stdlib_collection_iterator_execution-0628cb770de54105`.
Each group used exact test selection, `--nocapture --test-threads=1`, a 100 s
outer timeout, a 35 s wait for `library-gpu.lock` with contention exit 75, and a
60 s inner timeout. The environment set `RUST_MIN_STACK=16777216` and
`LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000`.

These gates used compiler checkpoint
`59612b3431d7b0cdff16a6faecf881f62a675503` and the pre-rebuild bundle of 918 SPVs
recorded in `target/stdlib-work/implementation-applications/v2-spv.sha256`, with
manifest digest
`455fcd353d3e883a50b2e6f9c113fe1ab1c50974350f276b1eed9c8da78cfaca`.
This evidence covers that compiled shader bundle, before the subsequent
array-repeat count checker fix was rebuilt. It does not establish acceptance
of the rebuilt checker.

These checks concern native CPU programs. They do not establish user-program
GPU execution or support for other targets. `for` retains its existing compiler
lowering; implementing the trait does not extend that syntax.
