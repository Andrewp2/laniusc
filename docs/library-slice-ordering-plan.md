# Comparator-driven slice algorithms

Current slice sorting, bounds, binary searches and pivot partitioning require
the element type's global `Ord<T>`. Complete this existing family with a
per-call comparison context and heterogeneous key lookup. Runtime evidence and
remaining compiler/target boundaries are recorded in the
[ordering guide](stdlib-slice-ordering.md); the whole standard/extended-library
goal remains open.

## One comparison contract

Move the existing iterator Comparator to `core::ordering`, which already owns
`Ordering`. Generalize its two operand types explicitly:

```lani
pub trait Comparator<L,R> {
    pub fn compare(&self,left:L,right:R) -> Ordering;
}
pub struct Natural<T> {}
```

`Natural<T>` implements `Comparator<T,T>` where `T:core::cmp::Ord<T>`, using
the two less-than directions and Equal otherwise. It has a borrowed accessor;
call sites can construct an explicitly typed local. This is one comparison
protocol for both sorting and heterogeneous searches, with no second mapping
trait, allocation or type-specific implementation.

`core::iter::min_by` and `max_by` now require
`core::ordering::Comparator<T,T>`. Migrate current fixture consumers and guide
signatures directly. There is no known external human compatibility need, so
remove the old trait identity without aliases or forwarding implementations.
Do not edit historical snapshots or compiler/formal sources.

`core::slice` may import `core::ordering`; it must not import `core::iter`.
Putting Comparator in cmp would create a dependency cycle through ordering's
represented-width helpers. Its existing Ordering home avoids that cycle.

## Checked public functions in `core::slice`

| Function | Result | Bound |
| --- | --- | --- |
| `sort_unstable_by<T,C>(values:View<T>,comparator:&C)` | `Result<i32,ViewError>` | `C:Comparator<T,T>` |
| `is_sorted_by<T,C>(values:View<T>,comparator:&C)` | `Result<bool,ViewError>` | `C:Comparator<T,T>` |
| `lower_bound_by<T,K,C>(values:View<T>,needle:K,comparator:&C)` | `Result<i32,ViewError>` | `C:Comparator<T,K>` |
| `upper_bound_by<T,K,C>(values:View<T>,needle:K,comparator:&C)` | `Result<i32,ViewError>` | `C:Comparator<T,K>` |
| `binary_search_first_by<T,K,C>(values:View<T>,needle:K,comparator:&C)` | `Result<Option<i32>,ViewError>` | `C:Comparator<T,K>` |
| `binary_search_last_by<T,K,C>(values:View<T>,needle:K,comparator:&C)` | `Result<Option<i32>,ViewError>` | `C:Comparator<T,K>` |
| `partition_lt_by<T,K,C>(values:View<T>,pivot:K,comparator:&C)` | `Result<i32,ViewError>` | `C:Comparator<T,K>` |

These free functions are the selected surface; no duplicate inherent facade
is required. Returned indices are relative to the selected view. The raw
slice/count Ord APIs retain their current signatures, return policies and
nonpositive-as-empty meanings, delegating to shared engines through Natural.
Do not keep a parallel handwritten Ord heapsort/search implementation.

## Validation and semantics

All checked entries reject negative start/length or start+length overflow with
`ViewError::Bounds` before element access, mutation or callbacks. A valid empty
view accesses nothing: sort/partition/bounds return zero, sorted returns true,
and both searches return None. A singleton sort makes no comparison. Initial
physical backing and its lifetime remain caller preconditions; logical checks
do not establish physical length or unchecked memory authority.

The comparator receives a shallow element first and another element/key second.
For sorting it must describe a consistent total order allowing equivalent
elements. Binary searches require each query's Less/Equal/Greater classes to
occur in that order; they do not scan to validate this precondition. Lower
bound is the first not-Less index; upper bound is the first Greater index.
First/last searches return exactly the first/last Equal index, not an arbitrary
duplicate. Missing matches return None. Lower/upper may equal view.length.

Sort is an iterative, allocation-free heapsort: build a max heap, exchange its
root with the final live element, shrink and sift down. It is unstable and
preserves a permutation of whole shallow values. Success returns the selected
view length, not a swap or comparison count. Partition puts all Less
items before all other items, returns the boundary and preserves the same
permutation; neither relative order nor a tie layout is promised. Surrounding
backing elements stay untouched, including offset and strided native views.

Use subtraction-based midpoints and guard child existence before doubling an
i32 index. Sorting has O(n log n) worst-case comparisons; bounds/search have
O(log n), sortedness/partition O(n), and all use O(1) auxiliary storage. A
callback's own cost is outside those bounds. Callback traces/counts are
observable, but exact sort/search callback schedules are not public promises.

The existing heapsort family and [NIST heapsort definition](https://xlinux.nist.gov/dads/HTML/heapSort.html)
are the algorithm reference. Rust's [unstable comparison sort](https://doc.rust-lang.org/std/primitive.slice.html#method.sort_unstable_by)
and [comparison search](https://doc.rust-lang.org/std/primitive.slice.html#method.binary_search_by)
provide related API contracts. Lanius uses explicit borrowed callback objects,
checked View metadata and deterministic first/last duplicate searches; it does
not copy Rust's current implementation or unspecified duplicate selection.

## Ownership and effects

No allocation, clone, destruction or cleanup transfer is added by these
algorithms. Reordering an owned record moves its current shallow handle between
initialized slots; callers retain one cleanup authority per actual owner.
Comparators must neither retire their arguments nor invalidate/mutate the
source, keys, backing or comparison context's ordering policy through aliases.
Instrumentation may record calls without changing their ordering answers.
Maintain live backing/context and prevent reentrancy. Trapping or nonterminating
callbacks supply no rollback or completion guarantee. Inconsistent answers
cannot justify a sorted/search result; structural loop bounds still avoid an
algorithmic infinite loop, assuming callbacks return and preserve storage.

## Executable acceptance

- Pure semantic and exact-bound rejection tests for every new function and the
  migrated iterator comparator; compound/nested records, heterogeneous keys,
  offset/negative-stride views, forged metadata and zero/singleton cases.
- Independent order/permutation/partition/first-last models over ascending,
  descending, equivalent-key and context-dependent comparisons. Do not assert
  an unstable tie placement or reproduce the heapsort in the oracle.
- Actual owned String records retain one owner after sorting/partitioning;
  observer traces permit no algorithm allocation or release, and explicit
  cleanup must match every actual allocation. Include generic owned shapes.
- A finite scale/callback-count gate checks practical large input, comparison
  growth and legacy raw Ord delegation without a timing-ratio claim.
- A real CSV row-ordering program accepts a column, numeric/text ordering and
  descending direction, uses these APIs, stages output, and reports bounds,
  allocation and I/O failures explicitly. Stable input order can be obtained
  by an explicit source-row tie-breaker in its comparator.

Root owns all compiler/native/Cargo commands, each under two minutes. No
compiler IR, extractor, proof, ABI or human-root-document edits are part of
this increment. Unsupported compiler forms get minimal reproductions rather
than type-specific library exceptions. Native Linux x86_64 CPU output from the
GPU compiler is the initial executable target; device execution is unclaimed.
