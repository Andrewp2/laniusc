# Canonical slice cursors and shared iteration

The shared protocol uses the existing `core::slice::Iter<T>` directly. Checked
construction, borrowed owner factories, forward iteration and backward access
operate on one cursor state. The earlier `core::iter::SliceIter<T>` wrapper is
removed; there is no alias or second forwarding cursor.

## Types and imports

| Constructor | Cursor | Shared item |
| --- | --- | --- |
| `core::iter::from_slice<T>(values,count)` | `Result<core::slice::Iter<T>,ViewError>` | `T` after successful construction |
| `core::iter::from_view<T>(view)` | Same result | `T` |
| `core::slice::View<T>::iter()` | `core::slice::Iter<T>` | `T` |
| `alloc::vec::Vec<T>::iter()` | `core::slice::Iter<T>` | `T` |
| `core::text::Text::iter_bytes()` | `core::slice::Iter<u8>` | `u8` |
| `core::vec::iter(&Vec<T,N>)` / `core::set::iter(&Set<T,N>)` | `core::slice::Iter<T>` | `T` |
| `alloc::binary_heap::BinaryHeap<T>::iter()` | `core::slice::Iter<T>` | `T`, in unspecified heap order |
| `View<T>::chunks(width)` | `Result<Chunks<T>,ViewError>` | `View<T>` |
| `View<T>::windows(width)` | `Result<Windows<T>,ViewError>` | `View<T>` |

Import `core::iter` to load the shared forward implementations. `core::slice`
defines the cursor records, constructors, borrowing, metadata and backward
operations. `core::iter` defines their single `Iterator` implementation and
forward `next` body. This direction keeps imports acyclic without duplicate
inherent and trait methods with the same name and receiver.

Existing clients migrate `core::iter::SliceIter<T>` annotations and generic
arguments to `core::slice::Iter<T>`. Direct slice-cursor clients also import
`core::iter`. Constructor names and logical validation errors remain the same.
Recompile callers after the nominal-type change; binary compatibility is not
claimed. Historical compiler captures retain their original source names.

## Bounds, state and ownership

The checked factories reject negative start/length or an end beyond i32::MAX
before creating a cursor. They do not prove physical backing or lifetimes.
Owner factories capture the already initialized prefix or Text byte range.
Every view and cursor preserves the underlying slice descriptor and stride.

`Iter` retains `remaining`, `next_back`, `advance` and `advance_back`. Forward
and backward traversal share one range. Skipping reports actual progress,
rejects negative requests without advancing and never reads skipped elements.
Copies fork positions while sharing backing. Borrowed adapters share their
source cursor object, which must outlive them.

Chunks include the final short view; windows include only complete views and
advance by one element. Both reject nonpositive widths with `InvalidSize`.
Their items alias backing elements, including overlapping windows. They create
no element copies or allocations. All three forward implementations are fused.
The moved bodies retain the existing arithmetic and ordinary native indexing.

Items remain shallow values. Iteration does not clone, transfer unique
ownership or destroy nested resources. Source-specific mutation/invalidation
rules still apply. See [slice contracts](stdlib-slice-views.md),
[collection ownership](stdlib-collection-iterators.md),
[text splitting](stdlib-text-split-iterators.md) and
[heap iteration](stdlib-heap-iterators.md).

Fixed-capacity factories retain their symbolic `T,N` free-function interfaces.
Pass borrowed owners to those functions directly in generic helpers; the
separately captured symbolic-capacity `.borrow()` lookup limitation is not
repaired by cursor integration.

## Current verification

The [focused driver](../tests/stdlib_slice_iterator_integration_execution.rs)
passed both gates in 8.30 seconds: two strict-checked native ELFs and two
native executions. The contract fixture exercises generic pulls, compound
items, packed and strided backing, mixed forward/backward traversal, borrowed
adapters, and symbolic `T,N` fixed-capacity helpers, including empty and
zero-sized elements. Its `mmap`/`munmap` trace was empty. The model fixture
compares 126 commands against independent slice chunk/window models: lengths
zero through six, six positive widths including i32::MAX, and three quotas.
It checks complete view summaries, remaining cursor/quota state, callback
counts and repeated exhaustion.

Freshly built regression drivers also passed the migrated callers:

| Gate | Native executions | Wall time | Local log |
| --- | --- | --- | --- |
| New slice protocol contracts and 126 model commands | 2 | 8.30 s | `slice-protocol-final.log` |
| Existing typed adapter contracts and String cleanup | 1 | 5.98 s | `adapter-contracts.log` |
| Combined slice views, chunks/windows, compound/ZST items and native strides | 1 | 5.90 s | `slice-contracts-fresh.log` |
| Existing iterator bounds, quotas and fusion | 1 | 6.03 s | `iterator-contracts.log` |
| Borrowed String cleanup and intentional physical-bounds failure | 2 | 6.40 s | `owners-and-physical-bounds.log` |
| Text bytes/scalars and bitset views | 1 | 6.33 s | `collection-views.log` |
| Vec String aliases and explicit owner cleanup | 1 | 5.61 s | `collection-owners.log` |
| Window-report application, valid and invalid input | 30 from one ELF | 6.50 s | `window-report.log` |

[Text splits](stdlib-text-split-iterators.md) add two accepted native gates
with 1,042 model records. [Heap iteration](stdlib-heap-iterators.md) adds two
accepted native gates with 42 multiset/adapter records and exact String-owner
cleanup. Their guides record their commands and the heap fixture correction.
Existing unchanged application fault cases and broader compiler suites were
not rerun for this cursor integration.

Earlier diagnostic attempts ran an older test executable without first
checking its build freshness and reported LNC0047 detail 10. Those attempts
are not current compiler-boundary evidence. Rebuilding the regression drivers
took 5.42 seconds; the full combined fixture then passed without diagnostic
flags or compiler changes. Temporary host-side diagnostic printing was removed.
Four minimal probes and six isolated source-group probes also passed, but
their success is not counted as a compiler repair. The accepted fresh run is
recorded in `slice-contracts-fresh.log`; the earlier local diagnostic logs are
retained separately.

Evidence is local under `target/stdlib-work/cursor-integration-admission/`.
The final slice driver build took 1.14 seconds (`build-final-slice.log`).
After building with the current compiler, its runtime command was:

```sh
timeout --kill-after=2s 100s flock -E 75 -w 35 \
  target/stdlib-work/library-gpu.lock timeout --kill-after=2s 60s \
  env RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
  target/stdlib-build/debug/deps/stdlib_slice_iterator_integration_execution-f1dea56aa323bfbb \
  --test-threads=1 --nocapture \
  > target/stdlib-work/cursor-integration-admission/slice-protocol-final.log 2>&1
```

Compiler source remains at `0519160c` for these checks; this integration
changes only library code, callers, tests and documentation. No compiler,
shader, runtime or ABI repair is claimed.
The target is native x86_64 Linux output from the GPU compiler. User-program
GPU execution, other platforms and throughput improvements are not established.

## Historical reproduction

The original nested View-result capture remains byte-for-byte intact. Its
[current reproduction supplement](../tests/fixtures/stdlib_compiler_state/iterator_view_result/CURRENT_REPRODUCTION.md)
restores both the captured iterator module and its matching historical slice
module. The original manifests still verify; a separate manifest pins the new
paired source and instructions. This preserves the old input while production
cursor methods move to the shared protocol.
