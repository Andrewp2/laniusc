# Heap iterators

`alloc::binary_heap::BinaryHeap<T>::iter()` returns the canonical
`core::slice::Iter<T>` over the heap's initialized entries. It implements
[`core::iter::Iterator<T>`](stdlib-iterators.md), supports `next_back`,
`remaining`, `advance` and `advance_back`, and works with generic consumers,
`take` and `map`. Import `core::iter` to use forward iteration.

Iteration follows unspecified heap order. It preserves the heap's length,
capacity, priority direction and root. It neither sorts nor removes entries.
No `Ord<T>` bound is needed to construct or consume a cursor; the heap's
ordering requirements still apply to operations that insert or reorder entries.

```lanius
let cursor: core::slice::Iter<i64> = heap.iter();
let selected: core::iter::Take<core::slice::Iter<i64>, i64> =
    core::iter::take<core::slice::Iter<i64>, i64>(cursor.borrow(), 2);
let progress: core::iter::Advance =
    core::iter::advance_up_to<core::iter::Take<core::slice::Iter<i64>, i64>, i64>(selected.borrow(), 3);
```

The cursor copies the existing native slice descriptor and captures its
initialized range. It retains native stride and physical bounds. Construction
and each forward or backward step take O(1) time and allocate no storage.
Forward and backward calls share one remaining range. Once exhausted, both
directions keep returning `None`. Copying a cursor forks its position while
retaining the same backing entries.

Keep the heap alive and at the same location while a cursor exists. Heap
mutations invalidate outstanding cursors; failed fallible edits preserve them.
Treat yielded values and ordering-relevant nested state as read-only while
stored. Writable public slice fields do not grant permission to violate heap
invariants. See the [heap contract](stdlib-binary-heap.md) for mutation and
ownership rules.

Items are shallow copies. Reading, mapping or discarding a String or another
owning descriptor does not clone its allocation, transfer release authority or
call `Destroy`. Keep one explicit owner for every nested resource. Releasing
heap storage does not release allocations owned elsewhere and referenced by
borrowed entries. Such yielded aliases remain usable only while their separate
owners remain alive. End cursor use before destroying heap storage.

Adapters borrow the cursor object. Keep that cursor, the heap backing and any
mapper state alive until adapter use ends. Copying an adapter shares its
upstream references. Lanius does not enforce these lifetime rules.

## Native verification

The [native test driver](../tests/stdlib_heap_iterator_execution.rs) contains two
accepted gates on x86_64 Linux. Together they emitted two ELFs, passed the
unchanged common strict x86 checks and ran two native processes.

- `heap_cursors_and_adapters_match_independent_multisets` compiles one fixture
  containing 42 small Min/Max cases: lengths zero through six and quotas zero,
  two and eight. A Rust oracle checks complete compound-entry multisets,
  including equal entries, wide signed priorities, full-width unsigned values,
  byte arrays and optional flags. It derives mixed-end and adapter positions
  from an observed scan without prescribing a heap array layout. It checks
  generic `pull`, borrowed `Take`, deferred typed `Map`, copied positions,
  repeated exhaustion and unchanged heap metadata and peek. Empty heaps of a
  type with no ordering implementation exercise an unconstrained generic
  read-only helper.
- `heap_iterator_string_aliases_release_only_explicit_owners` compiles one
  fixture with an external String owner and three borrowed copies in one
  reserved heap allocation. Its memory trace requires exactly two allocations
  and one matching release per allocation, with heap storage released before
  the String. Yielded String aliases remain readable after heap storage is
  released. Extra adapter allocation, implicit cloning, premature destruction
  or duplicate release fails the gate.

The first full-target invocation had one pass and one failure. The String-owner
gate passed, including its allocation and release ledger. The contract fixture
failed to parse at an unsupported `else if` spelling (LNC0016), before native
execution. Rewriting that branch as `else { if ... }` corrected the fixture.
Only the contract gate was rerun; it then passed all 42 model records and the
two internal empty-`Unordered` controls. The accepted owner fixture and driver
were unchanged and were not rerun. This was a fixture correction, with no
compiler bug or repair claimed.

| Invocation | Result | Wall time | Log |
| --- | --- | --- | --- |
| Initial full target | String-owner gate passed; contract fixture parse failed; overall target failed | 8.76 s for both tests | `target/stdlib-work/cursor-integration-admission/heap-iterators.log` |
| Corrected contract gate only | One test passed; one strict ELF and one native process | 5.80 s | `target/stdlib-work/cursor-integration-admission/heap-contracts-fixed.log` |

The Rust driver build took 1.10 s; its log is
`target/stdlib-work/cursor-integration-admission/build-heap.log`. Both invocations
used
`target/stdlib-build/debug/deps/stdlib_heap_iterator_execution-3f3f0e51fb245cbb`.
They used compiler source checkpoint `0519160c` with the stdlib cursor changes
and ran before subsequent temporary compiler diagnostic instrumentation.

From the repository root, the runtime gate commands were:

```sh
timeout --kill-after=2s 100s flock -E 75 -w 35 \
  target/stdlib-work/library-gpu.lock timeout --kill-after=2s 60s \
  env RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
  target/stdlib-build/debug/deps/stdlib_heap_iterator_execution-3f3f0e51fb245cbb \
  --test-threads=1 --nocapture \
  > target/stdlib-work/cursor-integration-admission/heap-iterators.log 2>&1

timeout --kill-after=2s 100s flock -E 75 -w 35 \
  target/stdlib-work/library-gpu.lock timeout --kill-after=2s 60s \
  env RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
  target/stdlib-build/debug/deps/stdlib_heap_iterator_execution-3f3f0e51fb245cbb \
  --exact heap_cursors_and_adapters_match_independent_multisets --nocapture \
  > target/stdlib-work/cursor-integration-admission/heap-contracts-fixed.log 2>&1
```

These fixtures extend cursor integration coverage. Existing heap algorithm and
allocation-failure models remain in `tests/stdlib_binary_heap_execution.rs`.
The reported durations are gate wall times, not compiler-throughput or runtime
performance measurements. Other targets remain unverified.
