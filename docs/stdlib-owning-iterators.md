# Owning Vec and deque iterators

`alloc::vec::Vec<T>::take_iter()` and `alloc::deque::Deque<T>::take_iter()`
transfer backing storage into an `IntoIter<T>`. They reset the actual source
owner to empty with zero capacity, so it can be reused independently. The
cursor implements the shared [`Iterator<T>` protocol](stdlib-iterators.md).
Each successful pull transfers the source's cleanup authority for that item to
its caller. There is no implicit element destruction.

The focused gates below passed on **native x86_64 Linux**, with the GPU compiler
emitting CPU executables. They establish neither user-program GPU execution nor
support for other targets. The compiler and runtime were unchanged.

The same ownership and explicit-finish policy now applies to
[hash map/set cursors](stdlib-owning-hash.md),
[ordered map/set cursors](stdlib-owning-tree.md) and
[priority heap cursors](stdlib-owning-heap.md). Their dedicated guides describe
remainder recovery, ordering costs, minimal trait bounds and native tests.

## One active storage owner

End source views and borrowed cursors before `take_iter()`. The call transfers
the existing allocation and initialized entries without allocation, cloning or
destruction. For a deque it also retains the ring's head. The source's storage,
length and capacity become zero; its head also becomes zero for a deque.

Keep one active owning cursor handle. Ordinary by-value copies still alias its
allocation, with copied positions. They cannot be used to fork traversal,
item cleanup or storage release. Resetting the actual source or cursor does
not reset stale aliases. The compiler does not enforce these rules.

An owning cursor only transfers authority that the source actually held.
Putting borrowed String aliases in a Vec does not make those aliases distinct
String owners. Retain their external ownership policy. The explicit Destroy
helpers below require every remaining entry to be one valid owner.

## API

Both modules define their own `IntoIter<T>` and
`IntoIterError { Remaining(i32) }`.

| Operation | Result and effect |
| --- | --- |
| `Vec<T>::take_iter()` / `Deque<T>::take_iter()` | Corresponding `IntoIter<T>`; transfer storage and reset source |
| `borrow()` | Reference to the active cursor for adapters, consumers or helpers |
| `remaining() -> i32` | Exact count of unconsumed items |
| `capacity() -> i32` | Retained allocation capacity |
| `is_empty() -> bool` | Whether the remaining count is zero |
| `next() -> Option<T>` | Remove the front item and transfer its cleanup authority |
| `next_back() -> Option<T>` | Remove the back item and transfer its cleanup authority |
| Vec cursor `as_view() -> core::slice::View<T>` | Borrow the initialized remainder |
| Deque cursor `as_views() -> alloc::deque::Views<T>` | Borrow the remainder as `.first` then `.second` |
| `try_finish() -> Option<IntoIterError>` | Reject unconsumed items or release empty backing and disarm |
| `take_remaining() -> Vec<T>` / `Deque<T>` | Transfer remainder and allocation into a reusable collection; disarm cursor |

Import `core::iter` for the forward trait method. Backward access and lifecycle
methods are inherent. Public metadata is not a validation boundary; use the
factory and preserve its invariants.

## Pulls, views and exhaustion

Front and back pulls consume one shared logical interval. They never overlap.
The item is removed before `Some(item)` returns. Later cleanup of the cursor
cannot release a yielded item: its caller must retain it, transfer it into a
destination or explicitly release it once. Any nested borrowed data must remain
valid for the item's later uses; shallow transfer does not repair self-references
or extend borrowed lifetimes.

Both ends are fused. After the interval is empty, pulls return `None` without
reading an entry. **Exhaustion retains the allocation and capacity.** It does
not call `Destroy`, release backing or reset the cursor. This also applies to
an initially empty cursor with reserved storage.

Remainder views borrow items; they transfer no cleanup authority. End them before
another pull, `take_remaining()` or successful `try_finish()`. A rejected finish
preserves all state, backing and existing views. Deque views concatenate in
front-to-back order; their split point is not a separate ownership boundary.

## Finish or recover the remainder

`try_finish()` first checks the remaining count. A nonzero count returns
`Some(IntoIterError::Remaining(count))` and changes nothing. With zero remaining,
it releases nonzero-sized backing using the original capacity and alignment,
resets every cursor field to zero and returns `None`. Calling it again on that
same reset cursor is harmless. It releases no previously yielded items.

`take_remaining()` transfers every unconsumed entry and the allocation into a
collection, keeping its capacity. It disarms the cursor without freeing backing
or destroying elements:

- Vec copies remaining typed entries forward within the same allocation. This
  safely handles overlap and keeps the original capacity-dependent layout.
  Recovery takes O(n) element copies when compaction is needed.
- Deque adjusts its head with the existing ring index calculation in O(1).
  Empty recovered deques normalize their head to zero.

Taking the remainder of an exhausted cursor recovers an empty collection that
still owns any retained reservation. Taking it again from the disarmed cursor
returns an empty collection with zero capacity. Finish then remains harmless.

```lani
let values: alloc::vec::Vec<i32> = alloc::vec::new();
let added: core::result::Result<i32, alloc::vec::Error> = values.try_push(7);
assert(core::result::is_ok(added));
let source: alloc::vec::IntoIter<i32> = values.take_iter();
let first: core::option::Option<i32> = source.next();
assert(core::option::unwrap(first) == 7);
// values is independently reusable; source still owns its old reservation.
assert(core::option::is_none(source.try_finish()));
values.destroy();
```

## Explicitly release unconsumed owners

`alloc::clone` provides two opt-in helpers:

```lani
alloc::clone::destroy_vec_iter<T>(owner: &alloc::vec::IntoIter<T>)
    where T: core::clone::Destroy<T>
alloc::clone::destroy_deque_iter<T>(owner: &alloc::deque::IntoIter<T>)
    where T: core::clone::Destroy<T>
```

Each helper pulls remaining entries front-to-back and invokes `T::destroy_value`
exactly once per remaining entry. It then calls `take_remaining()` to recover an
empty collection and disarm the cursor, checks that owner is empty and calls its
canonical `destroy()` to release backing. No Clone or TryClone bound is required.
The helper allocates nothing; Destroy must honor its existing infallible,
allocation-free contract. Empty and already finished cursors are supported.
For nested Vec entries, import the
[opt-in nested Destroy implementation](stdlib-nested-clone.md).

Only use these helpers when each remaining entry is a distinct valid owner.
They cannot release yielded items, rejected transfer items, or items already
discarded by another adapter or consumer. Those items no longer belong to the
cursor. An empty cursor can finish successfully while a discarded item leaks.

### Remaining compiler dependency

The first helper implementation drained entries, then called
`try_finish().is_none()`. A minimal imported String-only caller failed with
LNC0047: a generic replay argument lacked a complete native layout. Giving the
helper a typed `Option<IntoIterError>` local still failed. With that typed-local
helper, explicitly projecting `IntoIterError::Remaining` at the caller made the
paired control compile. A later run also verified that projection control
against the staged byte-original helper. These probes establish compilation
outcomes, not native execution. The
[preserved minimal sources and reproduction](../tests/fixtures/stdlib_compiler_state/owning_string_application/README.md)
record this boundary.

The current helpers use the empty-owner recovery and canonical release above,
with the same public API, allocation behavior and cleanup effects. Callers need
no error-layout projection merely to destroy a String cursor's remainder. This
library path does not fix the underlying generic-replay dependency or establish
unrestricted composition of finish-result helpers. The caller-projection
control is diagnostic evidence, not a required application pattern.

## Composition and discarded owners

Adapters borrow the active cursor; they do not take over its storage cleanup.
Keep it alive for every adapter use. A Take quota can end before the owning
source is empty; finish or recover the source's remainder separately.

The shared protocol performs shallow value copies. It never inserts a Destroy
call when an operation omits an input from its output:

| Operation | Items requiring explicit cleanup or retained tracking |
| --- | --- |
| `Skip`, `SkipWhile` | Skipped prefix |
| `Filter` | Rejected items |
| `Map`, `FilterMap` | Input resources omitted by the callback, including skipped `None` results |
| `TakeWhile` | Consumed false boundary item |
| `Zip` | Successful left item consumed before right returns `None` |
| `Enumerate` at index overflow | Extra successful item consumed before panic |
| `advance_up_to` | Every consumed item |
| `find`, `find_map` | Unreturned inputs; a returned item/output belongs to the caller |
| `any`, `all` | Every tested item, including the decisive one |
| `fold`, `try_fold` | Items or old accumulators omitted by the callback; an error need not retain them |

With an owning source, discarded cleanup authority can leak unless the caller
or callback explicitly releases or records it. A later `destroy_vec_iter` or
`destroy_deque_iter` cannot recover discarded items. Callbacks must also manage
any fresh owners they create. Panic/trap does not run automatic cleanup.

[`try_transfer_up_to`](stdlib-iterator-transfer.md) preserves the rejected item
in `TransferError.rejected`. With this owning source, successful acceptance
passes its cleanup authority to the destination; rejection passes it to the
caller. Resolve that item before resuming the source. The accepted prefix,
rejected item, cursor remainder and cursor backing have separate cleanup duties.

## Costs and limits

Construction, pulls, metadata, views, checked finish and deque recovery take
O(1) container work. Vec recovery takes O(n) when it compacts. None of these
operations allocates. The explicit Destroy helpers take O(remaining count)
plus element-release costs. Direct `try_finish()` releases backing only on
success; Destroy helpers instead recover an empty collection and destroy it.

Counts and reservations retain the original collection's i32 limits. Zero-sized
entries still have logical counts and cleanup calls; they require no allocation
or deallocation. A positive zero-sized reservation can retain `i32::MAX`
capacity until finish or recovery. Ownership remains manual; no automatic Drop
or new `for` lowering is introduced.

## Native verification

### Initial gates

The canonical sources are under
`tests/fixtures/stdlib_foundation/owning_iterators/`, `owning_iterator_faults/`
and `owning_iterator_bounds/`. The initial gates below used the helper's earlier
`try_finish()` release path. Production cursor bodies stayed unchanged. All six
successful ELF programs passed the unchanged common strict x86 checker before
native execution. Later helper/application acceptance is recorded separately.

| Focused group | Accepted evidence | Time | Local log |
| --- | --- | ---: | --- |
| Typed ownership | Wide/array/nested Option/Result payloads, individually owned String and nested Vec entries, actual source reuse, front/back handoff, typed overlap recovery, rejected-item cleanup and remaining Destroy; exact order for 36 matched allocation/release generations | 6.97 s | `contracts.log` |
| Independent models | 352 scenarios, 1056 recover/reopen rounds in one native process; Vec and wrapped Deque sequences, captured capacities, quotas, rejection, remainder conservation and exactly 672 setup allocations with no lifecycle allocation | 6.50 s | `models.log` |
| Allocation-free lifecycle | Two native cases, each with 14 setup allocations; mixed ends, failed/successful finish, recovery and Destroy, including an armed next allocation that remains unreached | 6.08 s | `lifecycle.log` |
| Zero-sized values | Two native cases, nine logical Destroy markers each, zero allocation/deallocation, including MAX reservation and armed allocation denial | 5.63 s | `zero-sized.log` |
| Vec destination failures | Seven native cases: four reached destination-growth denials and one independent original-source reuse failure, with retry before resumption and balanced owner lifetimes | 5.99 s | `vec-growth.log` |
| Deque destination failures | The corresponding seven native cases for owning Deque sources and destination growth | 6.06 s | `deque-growth.log` |
| Item/Destroy bounds | Three source-local LNC0008 rejections: missing Destroy, wrong Destroy item and wrong owning source item at the transfer call | 4.13 s | `bounds.log` |

These seven groups contain nine compilation jobs: six successful ELFs and three
intended source rejections. The six ELFs ran in **20 native processes**. Model
scenarios and recovery rounds are commands within one process, not separate
executions. Durations include compilation and checks; they are not isolated
operation benchmarks. Logs are local ignored files under
`target/stdlib-work/owning-iterators-admission/` and are not checked in.

The initial selected Rust target build took 1.44 s (`build.log`). After tighter
model/resource ledgers, the execution, application and nested-clone regression
target build took 2.06 s (`build-final.log`). The existing nested-clone group
`full_contracts_cover_three_levels_aliases_pop_reset_and_zero_sized_empty_paths`
also passed in 12.77 s: two additional strict-checked ELFs and two native
processes, recorded separately in `nested-clone-control.log`. It is not included
in the owning-cursor totals above.

### Current helper and application

The canonical empty-owner release path passed the new helper-only regression,
typed ownership rerun, all four fault groups and the application. The selected
execution driver rebuild took 1.41 s (`build-helper-regression.log`). All logs
below use the same ignored admission directory.

| Group | Accepted current-helper evidence | Time | Local log |
| --- | --- | ---: | --- |
| Helper-only and typed ownership | Two strict-checked ELFs and two native processes; no caller finish-result projection in the String helper fixture, exact eight allocation/release generations there, and the unchanged 36-generation typed ownership ledger | 8.51 s | `ownership-final.log` |
| Fault reruns | Four strict-checked ELFs and 18 native processes; lifecycle, ZST, Vec growth/retry and Deque growth/retry checks retain their exact ledgers and injection counts | 11.23 s | `faults-final.log` |
| Unique words application | One strict-checked ELF and 126 native cases, with denial at each of 79 observed representative allocation positions; 4096-word scale input checks correctness only | 8.78 s | `unique-words.log` |

The new helper gate is
`imported_string_cursor_helpers_cleanup_without_caller_finish_result_projection`.
It uses only imported Vec/Deque String helpers and checks the exact cleanup
identities and order for six String allocations and two cursor backing owners.
These reruns and application processes are separate from the initial totals;
repeated gates do not represent additional unique fixture coverage. The minimal
compiler-state probes above remain compile-only evidence.

Final source hashes are recorded in the ignored `source.sha256` manifest in
that admission directory (SHA-256
`65342d43b6a01d59bd93e3d830d163cb18385c9bf03de5c142baad67a1363014`).
`binary.sha256` records the five current driver binaries after the helper-only
test rebuild. The initial model gate preceded that rebuild; its fixture and
model oracle stayed unchanged. These manifests identify local artifacts and
do not add runtime coverage.

### Reproduce one group at a time

From the repository root, build the three focused drivers with the existing
compiler dependencies. Each command has a 100 s outer bound, at most 35 s to
acquire the shared GPU slot, and a 60 s inner bound. Lock exit 75 means no test
ran. Keep compilation and gates serialized.

```sh
mkdir -p target/stdlib-work/owning-iterators-admission
timeout --kill-after=2s 100s \
  flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s \
  env CARGO_TARGET_DIR="$PWD/target/stdlib-build" \
      CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  cargo test --locked --test stdlib_owning_iterator_execution \
    --test stdlib_owning_iterator_faults --test stdlib_owning_iterator_bounds \
    --no-run
```

The accepted binaries were `stdlib_owning_iterator_execution-4586b20c4489bcba`,
`stdlib_owning_iterator_faults-275d1453c8512835` and
`stdlib_owning_iterator_bounds-243b0593f29f07e2` under
`target/stdlib-build/debug/deps/`. A fresh build may emit different suffixes;
use the paths printed by that build.

Define this shell function, then run each invocation separately:

```sh
owning_gate() {
  owning_binary="$1"
  shift
  timeout --kill-after=2s 100s \
    flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
    timeout --kill-after=2s 60s \
    env RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
    "target/stdlib-build/debug/deps/$owning_binary" \
    "$@" --nocapture --test-threads=1
}

owning_gate stdlib_owning_iterator_execution-4586b20c4489bcba \
  --exact typed_owning_cursor_resource_handoffs_execute

owning_gate stdlib_owning_iterator_execution-4586b20c4489bcba \
  --exact imported_string_cursor_helpers_cleanup_without_caller_finish_result_projection

owning_gate stdlib_owning_iterator_execution-4586b20c4489bcba \
  --exact owning_cursor_sequences_match_independent_models_without_lifecycle_allocations

owning_gate stdlib_owning_iterator_faults-275d1453c8512835 \
  --exact owning_cursor_mixed_ends_finish_restore_and_destroy_do_not_allocate_after_setup

owning_gate stdlib_owning_iterator_faults-275d1453c8512835 \
  --exact zero_sized_owning_cursors_destroy_logical_items_and_never_allocate

owning_gate stdlib_owning_iterator_faults-275d1453c8512835 \
  --exact owning_vec_strings_recover_each_destination_growth_and_original_source_reuse_failure

owning_gate stdlib_owning_iterator_faults-275d1453c8512835 \
  --exact owning_deque_strings_recover_each_destination_growth_and_original_source_reuse_failure

owning_gate stdlib_owning_iterator_bounds-243b0593f29f07e2
```

The execution and fault drivers apply bounded native-process timeouts as well.
The fault groups compare complete mmap/munmap ledgers and reached or deliberately
unreached injection counts. These gates do not claim cleanup after panic/trap,
arbitrary Destroy implementations, forged metadata or multiple active aliases.
