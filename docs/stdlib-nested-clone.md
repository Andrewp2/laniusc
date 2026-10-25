# Opt-in nested Vec cloning and explicit release

**Accepted on native Linux x86-64**, using GPU compiler checkpoint `59612b34`.
All seven canonical groups passed on 2026-10-24: ten compilation jobs produced
six strict-checked ELF programs and four expected source rejections, followed
by sixteen native runs. The exact evidence is recorded below. No Wasm or
user-program GPU execution is claimed.

An earlier ignored String-edit fixture returned zero despite mutating a copied
owner and leaving its parent with stale storage. That result was an invalid
cleanup oracle and is not accepted evidence. The corrected canonical fixture
transfers/reinstalls actual owners and passed a balanced live-address/length
allocation trace. This later gate supersedes the old exit-zero observation.

`alloc::clone_vec` composes the existing `core::clone` protocols and
`alloc::clone` engine for ordinary nested `alloc::vec::Vec` values. Import this
opt-in module in the composition entry and generic consumers that use its
implementations. It does not change ordinary `Vec.try_clone()` or
`Vec.destroy()`: those retain shallow entry copies and outer-storage release.

## Surface and implementation availability

```lanius
import alloc::clone_vec;

alloc::clone_vec::try_clone<T,E>(source: &alloc::vec::Vec<T>)
    -> Result<alloc::vec::Vec<T>,alloc::clone::Error<E>>
    where T: core::clone::TryClone<T,E>, T: core::clone::Destroy<T>
```

The module also provides these explicit protocol implementations:

```lanius
impl<T,E> TryClone<Vec<T>,alloc::clone::Error<E>> for Vec<T>
    where T: TryClone<T,E>, T: Destroy<T>

impl<T> Destroy<Vec<T>> for Vec<T> where T: Destroy<T>
```

The helper borrows the source owner and delegates to
`alloc::clone::from_view<T,E>`. The Vec TryClone implementation delegates to
that helper, so another Vec level uses the same leaf-cloning and prefix-cleanup
algorithm. The Vec Destroy implementation delegates to
`alloc::clone::destroy_vec<T>`; it introduces no parallel destruction loop.

Use explicit `<T,E>` arguments or a complete expected Result when selecting a
leaf error contract. If a leaf supports several error types, an unannotated
call may be ambiguous. The receiver alone does not determine E. Missing leaf
TryClone or Destroy prerequisites, absent implementation imports and a
contradictory receiving error type must reject. Empty runtime input does not
waive these static requirements. An import enables explicit operations; it
does not turn shallow aliases into independent owners.

## Source, destination and mutation ownership

Source descriptors borrow live initialized storage. They remain read-only
through the call, including through other aliases. Source Vec lengths,
capacities, contents, nested owners and existing views survive success or
recoverable failure. A source View may repeat the same borrowed String or row
handle: each successful clone must produce a separate destination owner.

That distinction matters during release. A source Vec containing borrowed row
handles owns its outer storage only. Release the separate row and leaf owners
once; do not recursively destroy borrowed entries. A successful deep-clone
result instead owns every initialized entry independently and may be released
recursively. Physical backing, live storage, read-only use and single-owner
discipline remain caller preconditions.

To reset the actual top-level owner, use the existing helper:

```lanius
alloc::clone::destroy_vec<T>(owner: &alloc::vec::Vec<T>)
    where T: core::clone::Destroy<T>
```

For nested Vec entries, the opt-in Destroy implementation recursively releases
each owned child. The helper frees outer backing and resets the borrowed owner
to empty with zero capacity. Repeating it on that same reset owner is harmless.
By-value `Destroy::destroy_value` consumes the passed descriptor and cannot
reset other stale copies; stop using that descriptor and its old views.

Accessors return shallow borrowed values. Growing a copied String or child Vec
changes only that local descriptor and can leave its parent pointing at freed
storage. Transfer a child out with pop/remove before an owning mutation, then
reinstall its updated descriptor. For multiple levels, transfer and reinstall
each changed container as well. On mutation Err, retain and reinstall the
unchanged owner or release it separately. A popped/replaced child is owned by
the caller until explicitly transferred back.

An [owning Vec or deque cursor](stdlib-owning-iterators.md) offers another
explicit transfer boundary. For a source that owns its children, `take_iter()`
resets the actual source and a yielded child Vec belongs to the caller. That
child may be mutated as the active owner. Its
updated descriptor need not be reinstalled in the emptied source. The cursor
still owns its unconsumed children and outer backing until recovery or finish.
`alloc::clone::destroy_vec_iter<T>` and `destroy_deque_iter<T>` release those
remaining children using the same opt-in recursive Destroy implementation.
They recover the drained empty collection and release its backing through the
canonical owner `destroy()`, disarming the cursor without a finish-result call.
They cannot release already yielded or rejected children, or recover child
owners discarded by adapters. Copying an owning cursor does not create a
second cleanup authority.

There are no implicit moves, derive, automatic cloning, automatic Drop,
compiler-enforced uniqueness or cleanup during panic/trap. This memory-owner
Destroy contract is infallible and allocation-free; files, sockets and other
resources with fallible close require their own lifecycle operations. See the
[base clone contracts](stdlib-clone.md) and
[ownership conventions](library-api-conventions.md).

## Exact nested errors

Each vector level adds one `alloc::clone::Error` layer:

| Value | Error type |
| --- | --- |
| String | `alloc::string::Error` |
| Vec of String | `alloc::clone::Error<alloc::string::Error>` |
| Vec of Vec of String | `alloc::clone::Error<alloc::clone::Error<alloc::string::Error>>` |
| Vec of Vec of a leaf with error E | `alloc::clone::Error<alloc::clone::Error<E>>` |

At each level `Storage(alloc::vec::Error)` describes that container's backing
failure. `Element(index,error)` preserves the logical index and exact child
error. For example, a leaf failure in row1/column0 returns
`Element(1,Element(0,leaf_error))`; failure reserving row1 returns
`Element(1,Storage(error))`. Errors are not flattened into status codes by the
library. `Bounds` remains the existing View metadata rejection.

The failing leaf releases its own partial construction. Its enclosing
from_view releases completed leaf entries and inner backing, then transfers
the child error. Outer from_view releases completed child Vec owners and its
own backing, then transfers the nested error. A reservation failure invokes no
leaf clone at that level. No partial destination escapes, and cleanup order is
not a public promise.

E may own memory, including a String. It is a separate owner transferred
unchanged to the caller. It must not borrow failed-destination storage or the
completed prefix that cleanup releases. Borrowing source storage requires the
leaf's explicit lifetime contract. The library never automatically destroys E;
the caller inspects and releases its owned resources exactly once. Releasing
E and releasing the failed destination are separate obligations.

## Empty, zero-sized and resource profiles

An empty Vec clone allocates nothing and invokes no leaves. Empty inner Vecs
preserve their logical positions. Zero-sized leaf entries retain their counts,
use the existing zero-sized Vec capacity policy and allocate no leaf backing.
A Vec descriptor stored as an outer element is nonzero-sized, so a nonempty
outer Vec still allocates its own storage.

Each container retains alloc::vec's i32 count and byte limits. Total work and
memory follow all logical cloned entries, including repeated source handles,
plus user leaf-clone/release costs. There is no aggregate tree-memory quota,
clock deadline or new runtime recursion limit. Deeper static types remain
subject to ordinary compiler resource limits. Termination and ownership
guarantees depend on lawful, terminating leaf implementations.

## Native acceptance evidence

`tests/stdlib_nested_clone_execution.rs` compiles against the production stdlib
root and the durable `tests/fixtures/stdlib_foundation/nested_clone/` user root.
It applies the unchanged common strict x86 ELF checker. It has no ignored
prototype dependency or source overlay. All seven canonical groups passed:

1. Nested Strings, duplicate borrowed rows, independent mutation through
   transferred owners, source release and exact balanced mapping lifetimes.
2. A typed leaf error owning a String, inspected after source/destination
   release and explicitly freed by the caller.
3. Missing opt-in implementations rejected with LNC0008 at the exact caller.
4. Three String-vector levels, empty inner/outer values, zero-sized leaves,
   independent edits, pop transfer and repeated active-owner reset. A separate
   empty/ZST executable requires zero mapping calls.
5. A ten-attempt allocation baseline and one ENOMEM injection at every reached
   position. Runtime size_of values determine expected request lengths. Exact
   error levels/indexes, source preservation before cleanup and balanced live
   address/request-length ledgers are checked independently.
6. Eight owned-error row/column/stage cases, before/after partial leaf storage.
   Each separate five-byte error mapping must outlive source and destination
   cleanup and be released last by the caller.
7. Contradictory selected error types and each missing leaf prerequisite
   rejected at exact source calls.

The groups ran separately against the same canonical sources. Timings include
each group's compilation and checks; they are not isolated library-operation
benchmarks. The focused test-target build completed in 1.09s.

All logs below are under `target/stdlib-work/nested-clone-production/`:

| Group | Result and scope | Elapsed | Log |
| --- | --- | ---: | --- |
| Corrected nested Strings | 1 ELF / 1 native run; actual-owner edit/restore, independence and exact balanced allocation lifetimes | 6.76s | `strings.log` |
| Nested contracts | 2 ELFs / 2 native runs; three levels, aliases, empty inner/outer values, pop/reset and zero-mapping empty/ZST paths | 11.16s | `contracts.log` |
| Allocation failures | 1 ELF / 11 native runs; exact ten-request baseline plus every reached OOM, source preservation, exact typed error paths/indexes and balanced lifetimes | 5.83s | `allocation.log` |
| Owned-error matrix | 1 ELF / 1 native run; eight row/column/stage cases and separately released E owners | 7.04s | `owned-error-matrix.log` |
| Contradictory/missing prerequisites | 3 expected source rejections at their exact caller locations | 3.64s | `prerequisites.log` |
| Owned leaf error | 1 ELF / 1 native run; typed owned E remains usable after source/destination cleanup | 6.43s | `owned-error.log` |
| Missing opt-in | Exact LNC0008 at `no_opt_in.lani:14` | 3.52s | `no-opt-in.log` |

`build.log` records the focused target build. These gates exercise explicit
nested memory ownership without duplicating the older broad leaf-allocation
suite. They do not establish automatic ownership, arbitrary user-leaf cleanup,
trap recovery or unrestricted generic composition.

The prerequisite group reports LNC0006 at `contradictory_error.lani:11` and
LNC0008 at both `missing_destroy.lani:11` and `missing_clone.lani:11`.

### Run a focused group

From the repository root, with the compiler dependencies built and
`target/stdlib-work/` present, select one group at a time. This example checks
the ten-position OOM contract. The codegen guard is 45 seconds; the shared-lock
queue and command execution remain inside the 100-second outer limit.

```sh
timeout --kill-after=2s 100s \
  flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s \
  env CARGO_TARGET_DIR="$PWD/target/stdlib-build" \
      CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
      RUST_MIN_STACK=16777216 \
      LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
  cargo test --test stdlib_nested_clone_execution \
    ten_reached_allocation_failures_preserve_borrowed_sources_and_release_all_destinations \
    -- --exact --nocapture --test-threads=1
```

Lock status 75 means the shared slot was not acquired and no test ran. Other
filters are the seven test function names in the focused driver. Keep the same
bounded setup when selecting another group.
