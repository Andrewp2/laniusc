# Owned vector editing plan

This increment completes stable filtering and adjacent deduplication for owned
vector elements. Existing shallow removal/truncation APIs cannot release rejected
nested owners; the raw slice compaction helpers leave inactive tail copies and
are not a cleanup protocol. The full library goal remains open.

## Public contract

Add five methods to `alloc::vec::Vec<T>`; each requires
`T: core::clone::Destroy<T>` and retains the backing allocation and capacity.

| Method | Result and effects |
| --- | --- |
| `retain_destroy<P>(&self, predicate: &P) -> i32` | `P: core::iter::Mapper<T,bool>`. Visit every original item once, left to right. Keep true items in original order; destroy false items immediately after the predicate. Return the number removed. |
| `dedup_by_destroy<P>(&self, same: &P) -> i32` | `P: core::iter::Mapper<core::pair::Pair<T,T>,bool>`. Compare `(last retained, current)` left to right. True destroys current; false retains it. Keep the first representative. Return the number removed. |
| `dedup_destroy(&self) -> i32` | Also requires `T: core::cmp::PartialEq<T>`; use the same deduplication engine with partial equality. NaNs do not compare equal; signed zeroes do. |
| `truncate_destroy(&self, length: i32) -> Result<i32,Error>` | Negative length gives `Bounds` before any effect. Length at or above the current length is unchanged. Otherwise destroy the removed tail from back to front. Return the resulting length. |
| `clear_destroy(&self)` | Destroy every logical element from back to front and leave an empty reusable vector; retain capacity. |

Retain makes exactly `n` predicate calls. Deduplication makes `max(n-1,0)`
calls, even for non-equivalence predicates; comparison is always against the
last retained item. Empty and singleton cases follow those counts. The vector
algorithms allocate no memory and do not call Clone. Callback instrumentation
has its own explicitly chosen effects. `Destroy` retains its existing contract:
normal completion without allocation, panic or reportable failure, for memory
owners rather than fallibly closed host handles.

Every initial element must represent one distinct cleanup authority. Old views
and cursors must end before editing. Shallow owner aliases remain inactive;
callbacks and destructors must not access the vector through aliases or reenter
it. Callback arguments are temporary read-only descriptors: do not mutate,
retain cleanup authority for, or destroy them. Independent instrumentation is
allowed. Survivors retain their authority; removed values are destroyed exactly
once. Surviving items and later callbacks must not depend on backing owned by a
removed item; end such cross-element borrows before editing. Tail descriptor
copies are inactive after compaction. No unwinding or
recovery guarantee is added for a callback that violates its contract.

Use capacity-anchored typed slots, including zero-sized and multiword types;
do not infer byte strides or copy storage as bytes. Preserve existing shallow
methods and manual lifetime rules. No compiler, ABI, proof, protected vector or
memory changes belong to this increment.

## Application

Extend the existing `sort_rows` CSV program with `--drop-empty`, `--unique`
and `--limit N`. Parse and validate the complete bounded input first, retain
nonempty selected keys when requested, perform the existing stable sort,
deduplicate equal selected keys when requested, then truncate to the limit.
Numeric key validation still happens before filtering. Equal-key deduplication
keeps the earliest input record, including in descending order. Header handling
and default output stay unchanged. Explicit `Row` destruction releases its CSV
record; cleanup uses the new clear operation. Keep publication and all existing
resource bounds explicit. New options need unambiguous duplicate/value rules.

## Ownership and acceptance

1. Source agent owns `stdlib/alloc/vec.lani` and tiny admission fixture only.
2. Contracts agent owns direct semantics/type-bound fixtures and their Rust test.
3. Model agent owns independent sequence oracle/fixture and its Rust test.
4. Resources agent owns nested-owner, zero-sized, no-allocation and scale gates.
5. Application agent owns `sample_programs/library/sort_rows.lani`.
6. Application-test agent owns focused new CLI/model/failure tests.
7. Documentation agent owns the module guide, existing application guide,
   overview/roadmap integration and generated-reference updates.
8. Reviewer independently checks contracts, changes and accepted evidence.

Root owns this plan, source/test integration and every Cargo/compiler/native
command. Commands are serial under `target/stdlib-work/library-gpu.lock`, each
capped at 100 seconds. Tests must execute the real imported Lanius APIs, compare
survivors and callback/destruction traces against an independent model, reject
missing/wrong trait bounds, and demonstrate nested cleanup and unchanged backing
capacity. Use a representative large input to expose accidental quadratic work.
Exercise application defaults/new combinations, malformed input, input/output
limits, reached allocation failures and owner cleanup with focused existing
test infrastructure. No broad GPU or performance campaign is needed.

Use the existing tested native Linux x86_64 compiler profile. Keep a supplied
compiler snapshot separate from the Cargo target, and build harnesses with
`CARGO_PROFILE_DEV_DEBUG=0` and `CARGO_PROFILE_TEST_DEBUG=0`. Record exact native
receipts and distinguish compiler dependencies from library defects. Root human
README/policy files and `tests/common/mod.rs` remain untouched. Commit/push only
the reviewed increment; acceptance does not complete the broader library goal.
