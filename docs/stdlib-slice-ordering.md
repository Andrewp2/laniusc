# Comparator-driven slice ordering

This increment adds seven checked `core::slice` algorithms over counted
`View<T>` values and moves the shared comparison protocol to
`core::ordering`. The fixed [slice-ordering contract](library-slice-ordering-plan.md)
defines the increment. All six new library gates, four CSV application groups
and three selected iterator migration regressions pass on the finite native
Linux x86_64 profile below. This selected increment is accepted.
Earlier slice, iterator and fold receipts retain their own source/API scope;
the full standard and extended library goal remains open.

The separate [nth-element selection increment](stdlib-slice-selection.md)
reuses the same Comparator/Natural policy for a checked rank and one-element
borrowed result. Admission and direct contract/bound gates pass, with one
selected existing ordering regression. The real select-value program passes
four groups/101 cases. All six new library gates pass, including the
11,976-case independent model and both owner/scale tests; the finite native
selection increment is accepted. The seven-API receipts below do not establish
either new selection function.

## One comparator and direct migration

```lani
// Declared in core::ordering.
pub trait Comparator<L,R> {
    pub fn compare(&self,left:L,right:R) -> Ordering;
}
pub struct Natural<T> {}
```

`Natural<T>` implements `Comparator<T,T>` under `T:core::cmp::Ord<T>`.
It checks the two less-than directions and otherwise returns `Equal`.
Its borrowed accessor lets an explicitly typed local provide the comparison
context. Native partial-order floats need an explicit lawful total policy or
the [float-order wrappers](api/core/float_order.md).

The same trait serves equal-type ordering and heterogeneous element/key
queries. A query comparator implements `Comparator<T,K>`; neither a global
`Ord<T>` nor a separate key-mapping trait is required. Every comparison
receives a shallow element first and another element or the key second.

Iterator `min_by` and `max_by` migrate from `core::iter::Comparator<T>` to
`core::ordering::Comparator<T,T>`. Update imports, implementations and bounds
directly. There is one canonical trait, with no old-name alias or forwarding
implementation. Their representative/tie behavior remains in the
[iterator extrema guide](stdlib-iterator-lookahead.md#minimum-and-maximum).
`core::slice` imports ordering rather than iterators; the trait's ordering
home avoids introducing a dependency cycle through comparison helpers.

## Checked View APIs

All seven are free functions in `core::slice`:

| Function | Result | Bound |
| --- | --- | --- |
| `sort_unstable_by<T,C>(values:View<T>,comparator:&C)` | `Result<i32,ViewError>` | `C:core::ordering::Comparator<T,T>` |
| `is_sorted_by<T,C>(values:View<T>,comparator:&C)` | `Result<bool,ViewError>` | Same element/element bound |
| `lower_bound_by<T,K,C>(values:View<T>,needle:K,comparator:&C)` | `Result<i32,ViewError>` | `C:core::ordering::Comparator<T,K>` |
| `upper_bound_by<T,K,C>(values:View<T>,needle:K,comparator:&C)` | `Result<i32,ViewError>` | Same element/key bound |
| `binary_search_first_by<T,K,C>(values:View<T>,needle:K,comparator:&C)` | `Result<Option<i32>,ViewError>` | Same element/key bound |
| `binary_search_last_by<T,K,C>(values:View<T>,needle:K,comparator:&C)` | `Result<Option<i32>,ViewError>` | Same element/key bound |
| `partition_lt_by<T,K,C>(values:View<T>,pivot:K,comparator:&C)` | `Result<i32,ViewError>` | Same element/key bound |

Indices and boundaries are relative to the selected view. Lower/upper bounds
can equal `values.length`; optional search indices always identify a match
within it. Sort returns the number of selected elements sorted. Partition
returns the number of elements in its Less prefix.

### Metadata admission

Negative start, negative length or a start/length sum beyond `i32::MAX`
returns `ViewError::Bounds` before reading elements, mutating backing or
calling the comparator. A valid empty view touches no elements and makes no
comparison:

- sort, partition and both bounds return zero;
- sortedness returns true;
- first/last search return `None`.

A singleton sort makes no comparison. Logical descriptor checks establish
neither physical allocation length nor unchecked memory authority. Keep the
full selected backing live, initialized and physically valid, including for
offset or signed-stride native slices. The [View guide](stdlib-slice-views.md)
documents those manual obligations.

## Ordering, queries and partition

Sorting requires a consistent total ordering that may have equivalent
elements. `Equal` can group records with the same key even when their other
fields differ. Unstable sorting preserves no relative order among those
equivalent records. For stable source-row behavior, include an explicit
original-row tie-breaker in the comparator.

Bounds and searches require each query's Less, Equal and Greater classes to
occur in that order in the selected view. They do not scan to validate this
precondition. Descending policies work when the view and query comparator
use the same ordering; Less refers to that policy rather than built-in `<`.

| Query | Meaning |
| --- | --- |
| Lower bound | First index whose comparison is not Less |
| Upper bound | First index whose comparison is Greater |
| First search | First Equal index, or `None` |
| Last search | Last Equal index, or `None` |

The duplicate choice is explicit: search never substitutes an arbitrary
matching index for the requested first/last one.

Partition requires no previously sorted input. It places every Less element
before every Equal/Greater element, returns that boundary and preserves a
permutation of whole shallow values. It promises no internal order or tie
layout within either side. Sort and partition leave surrounding backing
elements untouched.

## Shared engines, storage and cost

The selected sort is an iterative heapsort: build a max heap, exchange the
root with the last live element, shrink and sift down. The algorithm family
is described by the [NIST heapsort reference](https://xlinux.nist.gov/dads/HTML/heapSort.html).
It sorts in place without allocation or recursive stack growth. Bounds use
subtraction-based midpoints; heap traversal checks child existence before
doubling an `i32` index.

| Algorithm | Worst-case comparator calls | Auxiliary storage |
| --- | --- | --- |
| Sort | `O(n log n)` | `O(1)` |
| Bounds and first/last search | `O(log n)` | `O(1)` |
| Sortedness and partition | `O(n)` | `O(1)` |

Comparator cost is additional. Instrumentation can observe calls, but exact
sort/search callback schedules are not API promises. Loops remain structurally
bounded even with inconsistent answers, provided callbacks return and preserve
storage; inconsistent answers do not establish sorted/query semantics.

Existing raw slice/count Ord APIs retain their signatures, return policies
and nonpositive-as-empty behavior. They delegate through `Natural<T>` to
these shared engines; there is no parallel handwritten Ord heapsort/search
family. Checked View functions retain strict negative-metadata errors.

Rust's [unstable comparison sort](https://doc.rust-lang.org/std/primitive.slice.html#method.sort_unstable_by)
and [comparison search](https://doc.rust-lang.org/std/primitive.slice.html#method.binary_search_by)
are related API references. Lanius supplies borrowed callback objects,
checked View metadata and deterministic first/last duplicate searches; it
does not adopt Rust's current sorting implementation or arbitrary duplicate
selection.

## Ownership and failure effects

The algorithms add no allocation, clone, destruction or cleanup transfer.
Swapping an owned record moves its current shallow handle between initialized
slots. Keep exactly one cleanup authority per actual owner, and release the
final reordered owners explicitly. A borrowed shallow value passed to a
comparator grants no ownership of its backing.

Comparators must not retire arguments, mutate/invalidate source or key
backing, change their ordering policy through aliases or reenter the same
operation. Keys and borrowed context must remain valid while sort/partition
reorder selected slots. Call logging is permitted when it leaves ordering
answers unchanged.

The comparator returns `Ordering`, with no fallible callback envelope.
`ViewError::Bounds` covers malformed logical descriptors; it does not catch a
callback trap or nontermination. Those callbacks provide no rollback or
completion guarantee. Physical backing, lifetimes and alias rules remain
manual; no runtime resource checker or borrow checker is introduced.

## Verification and remaining scope

All six new registered library tests pass against ordering source
`b09a297d`, slice source `a39b2bb5` and iterator source `83707f34`:

| Gate | Accepted observation | Receipt |
| --- | --- | --- |
| Three contracts | All seven APIs execute without memory services; malformed metadata, empty/singleton behavior and compound payloads are checked; five invalid capability compositions reject | `slice-ordering-contracts-role-contexts.log`, 8.64s |
| Owner and scale tests | Actual nested String owners, whole-record permutation, untouched backing guards, no memory services in pure phases and exact mapping cleanup | `slice-ordering-owner-first.log`, 12.20s |
| Independent sequence model | 2,808 cases / 44,928 actions / two backing forms / six policies, seed `0x510ce0261029` | `slice-ordering-model-first.log`, 6.59s |

Logs are retained under `target/stdlib-work/`. The
[model fixture guide](../tests/fixtures/stdlib_foundation/slice_ordering/README.md)
records the independent sorting/bisect/filter and whole-record multiset checks.
Both tested compound-record layouts have native descending stride; this is
not evidence for an arbitrary positive-stride record constructor.

The owner test uses `Vec<Record<Pair<Leaf>>>` with two independent Strings
per record. Seven pure phases add no mapping or release services, and all
29 allocations have exact address/size releases, with String owners released
before vector backing. These are finite observed owners, not a general
ownership proof or an allocation-failure campaign for these algorithms.

The scale test uses 32,768 compound duplicate-key records and guards, five
pure phases and two exact backing releases. It observes 881,019 custom sort
comparisons, 32,767 sortedness comparisons, 32,768 partition comparisons and
at most 17 comparisons for a query. The shared legacy Ord path observes
1,134,417 `lt` calls. Comparator calls and primitive `lt` calls have different
units: `Natural` can call `lt` twice. The instrumented whole-process native
lifecycle is 267ms, including construction, checks, legacy operations and
cleanup; it is not isolated sorting throughput or a compiler performance ratio.

The first complete contract producer was rejected before runtime because
one receiver implemented both element/element and element/key `compare`.
The [retained dependency](../tests/fixtures/stdlib_foundation/slice_ordering_dependency/README.md)
captures that source. Current contracts and models use separate receiver
types borrowing a shared policy; the public `Comparator<T,K>` bounds remain
general. Two focused dependency checks pass in 2.92s
(`slice-ordering-dependency-first.log`): the import-free same-receiver
reproduction reports LNC0027 at its second `compare`, while the split-receiver
control compiles and executes compound/full-width assertions. This is one
reproduced diagnostic and one native control, with no compiler repair claim.

The real [CSV row-ordering program](stdlib-sort-rows.md) sorts decoded whole
rows using a borrowed text/numeric policy and an explicit original-row
tie-breaker. All four registered groups pass with 122 process cases: model37
in 12.78s (`slice-ordering-sort-rows-model-first.log`), then CLI39,
rejection33 and I/O13 in 9.65s (`slice-ordering-sort-rows-boundaries.log`,
model filtered). Full output is staged before publication and cleanup remains
explicit. These application receipts are separate from library model actions.

Three selected current iterator migration tests pass in 16.23s
(`slice-ordering-iterator-migration-regression.log`, two unrelated tests
filtered). They cover 1,280 four-action schedules, 320 extrema cases,
180 position cases, cached/borrowed String-owner cleanup and exact-bound
rejections through the migrated comparator trait. The old application and
overflow-trap groups were not rerun. The new scale fixture separately
exercises the shared raw-Ord engines. Earlier slice, iterator and fold
receipts retain their source scope; this is no historical-suite-wide claim.

The executable target is native Linux x86_64 CPU output from the GPU
compiler. Device execution, broader targets, formal proofs, arbitrary generic
compositions and automatic ownership remain unclaimed.
