# Editing vectors of owned values

`alloc::vec::Vec<T>` provides five explicit `_destroy` methods for stable
filtering, adjacent deduplication and tail cleanup. They keep the vector's
allocation and capacity while releasing removed values through
`core::clone::Destroy<T>`. The implementation follows the
[owned-editing plan](library-vec-edit-plan.md). All nine library groups pass on
the finite native Linux x86_64 profile: seven execute programs and two check
capability rejection. The migrated application passes all four groups/132 group
cases. Earlier
vector, transfer and sort-row receipts keep their original scope.

The current Mapper path is `core::function::Mapper`. The
[lazy-outcome migration](stdlib-lazy-outcomes.md) records a selected current
regression separately; earlier receipts below keep their original source scope.

## Methods and order

All five methods borrow the actual Vec owner and require
`T: core::clone::Destroy<T>`.

| Method | Additional bound | Result and effect |
| --- | --- | --- |
| `retain_destroy<P>(&self, predicate: &P) -> i32` | `P: core::function::Mapper<T,bool>` | Visit original items left to right; retain true items in order and immediately destroy false items. Return the removed count. |
| `dedup_by_destroy<P>(&self, same: &P) -> i32` | `P: core::function::Mapper<core::pair::Pair<T,T>,bool>` | Compare `(last retained, current)` left to right; true immediately destroys current, false retains it. Return the removed count. |
| `dedup_destroy(&self) -> i32` | `T: core::cmp::PartialEq<T>` | Use the same deduplication engine with partial equality. |
| `truncate_destroy(&self, length: i32) -> Result<i32,Error>` | None | Reject negative length with `Bounds`; otherwise destroy any removed tail from back to front. Return the resulting length. |
| `clear_destroy(&self)` | None | Destroy all logical items from back to front, leaving an empty reusable vector. |

For original length `n`, retain makes exactly `n` predicate calls and dedup makes
exactly `max(n-1,0)` calls. A rejected value is destroyed before the next
predicate call. Empty retain/dedup and singleton dedup make no predicate calls.
Every retained value keeps its original relative order and cleanup authority.

Dedup keeps the first representative. A rejected current item never becomes
the representative for the next comparison. For example, using the relation
`current - last_retained <= 1` on `[1,2,3]` retains `[1,3]`: rejecting 2 does not
make it the next comparison's left operand. The callback need not define an
equivalence relation. `dedup_destroy` uses the element's partial equality;
floating NaNs remain distinct and positive/negative zero compare equal.

Tail cleanup has the opposite direction. Truncating `[a,b,c,d]` to length 2
destroys `d` then `c`; clearing it destroys `d,c,b,a`. A negative truncation
length returns `Bounds` before reads, callbacks or destruction. A length at or
above the current length returns the unchanged current length with no cleanup.
Clearing an already empty vector has no effects.

## Temporary borrows and cleanup authority

Each initial element must hold one distinct cleanup authority. End old views
and cursors before editing. Copied owner handles remain inactive aliases.
The methods do not detect invalid owner duplication or repair expired backing.
Survivors and later callbacks must not depend on resources owned by removed
elements. For example, a surviving Text/View into a removed String becomes
invalid when that String is destroyed; distinct cleanup owners alone do not
make such cross-element borrows valid.

Predicate arguments are **temporary read-only borrowed descriptors**, despite
being passed as shallow values. They allow inspection only during that call.
Do not mutate them or their represented resources, destroy them, retain them
beyond the call, or acquire cleanup authority from a copy. Both members of the
deduplication Pair follow this rule. The predicate context may update independent
instrumentation, such as a separate call log, while obeying its own lifetime
contract.

Predicates and destructors must not access the vector owner or its backing
through aliases, reenter the operation, or observe its intermediate length.
The edit operation owns the unvisited suffix; the public descriptor can already
name only the retained prefix during traversal. This internal state supplies no
callback observation API. The receiver descriptor itself must remain live and
outside storage that editing can overwrite or destroy.

Removed values are destroyed exactly once on normal completion. After
compaction, stale descriptors beyond the new length are inactive storage, not
additional owners to inspect or clean up. Survivors keep their authority and
must later be transferred or destroyed once. `clear_destroy` releases entries
but retains the outer reservation; eventually reuse it or call ordinary
`Vec.destroy()` to release that backing.

`Destroy<T>` is the existing explicit memory-owner protocol: it must finish
without allocation, panic or reportable failure. It may release owned memory.
It is not a fallible close protocol for files, sockets or similar host handles.
Predicate instrumentation has its own effects; the vector adds no allocation
or hidden Clone calls. There is no unwinding, rollback or recovery guarantee
when a callback or destructor violates its contract. These rules remain manual,
not borrow-checker enforcement or automatic drop.

## Storage and work

All operations retain the same outer backing and capacity. They use typed slots
anchored to that capacity, including multiword and zero-sized elements; raw byte
compaction is not the contract. Successful nonempty edits invalidate earlier
views and cursors even though the allocation stays in place.

With constant-cost shallow assignments, vector work is O(n) for retain/dedup,
O(number removed) for truncation and O(n) for clear, with constant auxiliary
storage. Callback and destruction costs are additional. Each removed value adds
one Destroy call; zero-sized elements receive the same predicate and destruction
calls as ordinary elements. There is no descriptor-only shortcut that skips
zero-sized logical effects.

The existing [shallow Vec methods](stdlib-vec.md) keep their contracts:
`clear`, `truncate`, shrinking resize and ordinary `destroy` do not recursively
clean up entries. [Transfer methods](stdlib-vec-transfer.md) transfer authority
without invoking Destroy. Choose the explicit operation matching the caller's
ownership policy; the `_destroy` names introduce no implicit cleanup elsewhere.

## Real consumer and target

The [sort-rows program](stdlib-sort-rows.md) uses retain to drop empty selected
keys, stable sorting followed by adjacent deduplication to retain the earliest
equal-key record, and truncation for a data-row limit. Its `Row` destructor
releases the owned CSV Record; final cleanup uses `clear_destroy` before
releasing outer storage. Complete input/key validation and staged publication
remain application policies.

The initial target is native Linux x86_64 CPU output from the GPU compiler.
All five [registered direct groups](../tests/fixtures/stdlib_vec_edit/README.md)
pass on source `a5b93853`: tiny admission (5.73 s), exact callback/cleanup and
bounds contracts (4.76 s), generic compound/float cases (5.58 s), and two bound
tests with twelve intended source-local LNC0008 rejections (6.15 s together).
The three positive programs execute and check exact allocation/release pairs;
the negative fixtures check capability admission only. Logs under
`target/stdlib-work` are `vec-edit-tiny-rust.log`, `vec-edit-contracts.log`,
`vec-edit-types.log` and `vec-edit-bounds.log`.

The earlier direct raw tiny execution overlaps the registered admission and
adds no separate API-coverage count. All three
[resource groups](../tests/fixtures/stdlib_vec_edit_resources/README.md) also pass
in 8.75 seconds (`vec-edit-resources.log`):

- Nested owners: 30 entries, 60 inner owners and capacity 257, with all 2,188
  output bytes and 62 exact allocation/release pairs checked.
- Scale: 4,096/65,536 inputs, 59,482 complete record observations and 951,880
  output bytes, with two allocations/releases. The traced native run took
  0.068286 seconds; this is a finite observation, not a general benchmark.
- Zero-sized values: 17 retain, 11 custom-dedup and eight equality calls,
  26 destruction calls and no allocations. Maximum length 2,147,483,647 is
  exercised only through no-op/error metadata paths, not a huge edit loop.

Observed operation phases allocate nothing. Callback effects and valid-owner
preconditions retain their documented scope. The migrated sort-rows application
passes four groups/132 group cases, including 57 reached allocation denials;
its guide records those separately, together with three selected older groups/
109 cases. Counts are not added across those corpora.

The [independent state model](../tests/fixtures/stdlib_vec_edit_model/README.md)
passes one test in 6.59 seconds (`vec-edit-model-final.log`): 24 cases and 1,920
actions, 1,082 created/destroyed authorities including 541 nested owners,
2,480 effect events and 4,876 complete snapshot items. It checks 56 Bounds
results, 120 empty edits, 20 singleton edits and 196 refills. Its 25 host
corruption controls are separate from native cases. The first registered model
invocation failed before execution on a fixture-only public-impl/private-trait
visibility error (LNC0021, 3.46 seconds); the corrected fixture passes without
changing production or the oracle.

The source uses an explicitly typed local for the last-retained value before
constructing a generic Pair. The [reduced compiler dependency](../tests/fixtures/stdlib_vec_edit_dependency/README.md)
confirms that the inline indexed field expression rejects with LNC0006 while
the typed-local control compiles and executes with status 0 and empty output.
This is a narrow expression-form limitation, not a loss of generic element
support or a compiler repair. The original admission also required a separate
fixture-only partial-equality implementation correction. These controls do
not replace the full runtime gates.

No device execution, other-host support, automatic lifetimes, formal proof or
compiler repair is claimed. The broader
[library roadmap](library-roadmap.md) remains open.
