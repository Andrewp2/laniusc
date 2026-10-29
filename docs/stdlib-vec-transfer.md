# Vector ownership transfers

`alloc::vec::Vec<T>` adds four direct ownership-transfer methods under the
[vector-transfer contract](library-vector-transfer-plan.md). The source is
implemented and accepted on the finite Linux x86_64 CPU profile: all eight
library groups and four application groups/133 native cases pass. Earlier
vector, clone and iterator receipts retain their original operation scope.
The full library goal remains open.

## API

These are inherent methods on `Vec<T>`, with no new trait bounds:

```text
take() -> Vec<T>
try_append(other: &Vec<T>) -> Result<i32, Error>
try_split_off(at: i32) -> Result<Vec<T>, Error>
try_extract_range(start: i32, end: i32) -> Result<Vec<T>, Error>
```

All methods borrow the actual owner descriptor. They transfer shallow entries
without invoking Clone, Destroy or a user callback. Nested owners acquire no
duplicate cleanup authority, and borrowed pointers inside entries retain their
original backing/lifetime obligations. Ordinary Vec destruction still releases
only outer storage; explicitly retire any nested owners exactly once.

### Whole owner: `take`

`take()` transfers the allocation, capacity and every initialized entry into
the returned Vec, then resets the actual source to zero storage, length and
capacity. It performs no allocation, element copying or destruction. A reserved
empty source transfers its reservation too. The reset source is independently
reusable; taking it again returns an empty zero-capacity Vec.

End earlier borrows before taking the owner. Copied descriptors that referred
to its old allocation remain inactive aliases; resetting one descriptor does
not reset or validate those copies.

### Append another owner's entries

`try_append(other)` preserves order, returns the destination's new length and
empties the donor's initialized range. Donor backing and capacity remain
unchanged and reusable. If destination capacity suffices, there is no allocation;
growth uses at most one allocation and the existing geometric growth policy.
Nonempty success invalidates prior views of both owners, even when no backing
moves. An empty donor is a successful no-op preserving both owners and views.

The destination receives each donor entry's cleanup authority. The emptied
donor still owns its outer reservation, which must eventually be reused or
destroyed. Spare slots contain no active entries and confer no cleanup duty.

### Extract a range or split a suffix

`try_extract_range(start,end)` accepts exactly
`0 <= start <= end <= source.len()`. It returns `[start,end)` in its original
order and compacts the retained suffix after the retained prefix. Both retained
and extracted entries preserve their relative order. Source backing and
capacity remain unchanged, including when the complete range is extracted.

The result is an independent owner; a nonempty result for nonzero-sized T has
independent outer storage. Removed entry handles transfer their cleanup
authority into that result; nested resources are not cloned. Successful
nonempty extraction invalidates prior source views. An empty
range returns `new()` with zero capacity and preserves source state and views.

`try_split_off(at)` uses the same extraction operation for `[at,len)`. Splitting
at zero transfers all entries into an independent result while retaining the
empty source reservation. Splitting at length returns an empty zero-capacity
result without allocation or source changes.

## Valid owners, aliases and lifetimes

Use valid existing owners and keep one active cleanup authority for each
allocation. Public field visibility does not validate forged counts, expired
backing or copied owner handles.

Append requires **two distinct, exclusively active owner descriptors with
independent backing**. Neither descriptor may live inside storage that the
operation can relocate or overwrite. Self-append, shallow aliases and
overlapping owners violate this caller precondition. The API does not promise
runtime alias detection. Distinct empty and zero-sized owners may both use a
zero storage pointer; pointer equality is not an owner-identity check.

End borrowed views and cursors before an operation that can succeed and
invalidate them. Recoverable errors preserve existing views; documented empty
append/extraction operations preserve them too. Concurrent or reentrant access
through an alias is outside the contract. Entries that borrow from a source
allocation still depend on that allocation after transfer; moving a descriptor
does not repair self-references or extend lifetimes. These are manual rules,
not compiler-enforced moves, uniqueness or destruction.

## Failure and zero-sized values

The existing `alloc::vec::Error` is unchanged:

| Condition | Result and effects |
| --- | --- |
| Negative/reversed/past-end split or extraction bounds | `Bounds`, before allocation or entry reads |
| Combined append count exceeds the element-capacity limit | `CapacityOverflow`, before mutation or allocation |
| Required result or destination-growth allocation fails | `AllocationFailed`, with no partial transfer or result |

Every error preserves all participating owner descriptors, capacities,
initialized values, nested resources and existing views. Extraction reserves
the result before reading removed entries or compacting the source. Append
clears the donor only after destination extension succeeds. There is no rollback
envelope for invalid caller ownership or a process trap.

Counts remain i32, with at most `i32::MAX` allocated bytes. The maximum entry
count depends on `size_of<T>()`. The four new operations use descriptor-only
paths for zero-sized T after bounds/count checks: no entry loops and no
allocation, including valid maximum-length owners. A positive reservation
establishes capacity `i32::MAX`; empty extraction/split results have zero
capacity. A reserved-empty `take()` preserves the transferred reservation.
Zero-sized append preserves the donor capacity, and zero-sized extraction
preserves source capacity, exactly like the nonzero-sized paths.

## Work and storage

With constant-cost element assignment:

| Operation | Work | Additional storage |
| --- | --- | --- |
| `take` | O(1) | None |
| Nonzero-sized append | O(donor length), plus old destination length when growing | At most one growth allocation; constant scratch |
| Nonzero-sized range extraction | O(removed count + retained suffix count) | One independent result allocation for a nonempty range; constant scratch |
| Nonzero-sized suffix split | O(suffix length) | Same result policy as extraction |
| Zero-sized operations | O(1) after count/bounds checks | None |

Typed views use each actual owner's capacity. Composite physical element
positions can depend on capacity, so copying raw bytes, reallocating raw
storage or sharing offset allocations would not establish this contract.
The existing eight-byte allocator alignment profile remains in force. These
are algorithmic bounds, not throughput or formal-proof claims.

## Relationship to existing APIs

- `try_extend(View<T>)` atomically copies borrowed values and supports a view
  into the same Vec. It does not empty a donor or infer ownership transfer.
- `take_iter()` transfers whole storage into an owning cursor; `take()` returns
  a Vec directly. Both reset the source. Cursor `take_remaining()` can compact
  a consumed prefix in O(n); it is not the O(1) whole-owner `take()` operation.
- `core::iter::try_transfer_up_to` preserves accepted-prefix progress and
  returns a rejected item on failure. The new Vec operations instead commit
  the complete requested transfer or preserve both participating states.
- `Deque.try_split_off` already has an independent suffix and retained source
  capacity. This increment adds the equivalent Vec boundary and range removal.

The [row-moving program](stdlib-move-rows.md) composes these four methods over
owned CSV records, then serializes complete staged output. The
[base Vec guide](stdlib-vec.md) retains its ordinary edit/clone contracts;
[owning iteration](stdlib-owning-iterators.md) and
[nested explicit cleanup](stdlib-nested-clone.md) retain their own protocols.

## Evidence and remaining dependencies

### Direct contracts

The first compound native admission passes for source
`d1c9d25dafa885e5ae082d8072fe2092a16487e5e22024ae12eb22056c104935`:
one test in 4.89 seconds after a separate 37.16-second Rust build, recorded in
`target/stdlib-work/vector-transfer-admission.log`. The tiny fixture is
`9387c039`, with driver `976fd504` at invocation. No compiler dependency was
encountered. The range/capacity/bounds group then passed in a mixed command
with two fixture compile failures: 10.01 seconds, separate build 1.91 seconds,
`vector-transfer-direct.log`. Those two fixtures needed explicitly typed null
pointers rather than untyped integer zero; production was unchanged. Their
focused retry passed both groups in 9.03 seconds, build 0.19 seconds,
`vector-transfer-direct-retry.log`. All four direct groups are accepted, with
four, 31, 26 and zero exact allocation lifetimes respectively. The maximum Unit
witness constructs a valid zero-byte state to test counts; it does not claim
billions of pushes executed. See the
[direct fixture guide](../tests/fixtures/stdlib_vec_transfer/README.md).

### Independent operation model

The [stateful model](../tests/fixtures/stdlib_vec_transfer_model/README.md)
passes one native test in 9.42 seconds after a separate 0.20-second Rust build,
`target/stdlib-work/vector-transfer-model-final.log`. The seed is
`0x7ec7a0261114`; producer `bf71c4bd`, oracle `9c3f1ccb` and driver `3cdb249f`
record 56 cases and 3,584 actions across five element shapes:

- 787 introduced entries, including 170 real nested byte-vector owners;
- 3,698 moved entries, 913 nonempty transfers and 397 documented empty transfers;
- 242 bounds errors, 112 reserve capacity errors, 1,049 saved-view observations
  and 28,352 complete snapshot entries.

The reference compares ordered list states and full compound/nested payloads,
using public capacity/address transitions rather than reproducing the storage
algorithm. The 112 capacity errors belong to reserve; this model does not
claim append-overflow or OOM coverage. Those boundaries have separate direct
and resource witnesses. Twenty-seven host corruption controls are separate
from the native corpus and add no native cases.

The first model attempt failed compilation with LNC0072 before runtime because
a test observer used a prohibited direct ptr-to-usize cast: 3.94 seconds, separate
build 1.70 seconds. It was replaced with the existing raw pointer-store
observation. This changes fixture reporting only; production and compiler
sources are unchanged.

### Resources and scale

All three [resource groups](../tests/fixtures/stdlib_vec_transfer_resources/README.md)
pass together in 12.52 seconds after a separate 1.90-second Rust build,
`target/stdlib-work/vector-transfer-resources.log`:

- Nested transfer preserves 17 entries and their 34 inner owners, with 39
  exact allocations/releases and complete payload observation.
- One baseline and three reached outer-reservation denials cover append
  growth, split and range extraction, at allocation attempts 37, 73 and 109.
  Each process has 109 successful allocations and exact releases. Errors
  preserve captured old views and all inner owners; the same actual owners
  recover on retry. No failure is invented for allocation-free `take`.
- Packed/composite scale cases check all 532,480 values and 4,259,904 output
  bytes, with 12 exact allocations/releases. The traced native process took
  0.369045 seconds, separately from its 3.183870-second compilation. That time
  includes setup, checking and publication; it is not isolated transfer
  throughput or a GPU compiler performance claim.

These are three baseline processes plus three denial/recovery processes;
they are distinct from application allocation-failure cases.

### Consumer and selected regressions

The row-moving consumer passes four groups/133 native cases, including 40
reached allocation denials;
standalone compilation and both examples pass separately. Its detailed
[application receipt](stdlib-move-rows.md#target-and-evidence) keeps syscall,
publication and defensive-limit scopes explicit. Historical vector and
iterator receipts do not establish these new methods.

Five selected existing groups pass on this source, separately from new-family
acceptance: all four `stdlib_alloc_vec_execution` groups in 24.26 seconds
(separate Rust build 1.71 seconds; `vector-transfer-existing-vec.log`), and
`typed_owning_cursor_resource_handoffs_execute` in 7.00 seconds (build 1.81
seconds; `vector-transfer-existing-owning.log`). These retain the earlier
6,000-step vector model, edit/allocation/panic cases and 36-allocation owning
handoff ledger within their own scopes. Logs are under `target/stdlib-work/`.

### Target and remaining dependencies

Initial acceptance targets Linux x86_64 CPU output from the GPU compiler.
Other hosts, user-program GPU execution, automatic ownership and formal proofs
need separate evidence. No compiler feature, ABI change or protected-vector
migration is part of this increment. The protected `std::vec` remains heap
backing with active formal vector contracts; the mini compiler and extractor
use `List`. Any newly encountered compiler failure needs a separate reduced
reproduction. See the [dependency ledger](library-dependencies.md).

## Source context

Rust's [Vec append, split_off and drain contracts](https://doc.rust-lang.org/std/vec/struct.Vec.html)
provide reference behavior for ordered transfer, retained split-source capacity
and range removal. [`mem::take`](https://doc.rust-lang.org/std/mem/fn.take.html)
provides the whole-owner replacement model. These references were read on
29 October 2026. Lanius adds signed bounds, explicit allocation failure and
manual ownership; range extraction eagerly returns an independent Vec instead
of leaving a borrowed drain cursor with suspended cleanup.
