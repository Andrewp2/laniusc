# Checked slice order-statistic selection

The [selection increment](library-slice-selection-plan.md) adds two
`core::slice` operations for finding a zero-based rank without sorting the
whole input. Native admission, literal contracts and capability rejections pass,
along with the independent model, owner/scale gates and one selected ordering
regression. The finite native increment is accepted; the full standard and
extended library goal stays open.

## Public API and borrowed result

```text
select_nth_unstable_by<T,C>(values:View<T>, nth:i32, comparator:&C)
    -> Result<View<T>,ViewError> where C:core::ordering::Comparator<T,T>
select_nth_unstable<T>(values:View<T>, nth:i32)
    -> Result<View<T>,ViewError> where T:core::cmp::Ord<T>
```

The natural-order wrapper constructs `core::ordering::Natural<T>` and uses
the same selection engine. Comparison receives two shallow values through the
existing borrowed [Comparator protocol](stdlib-slice-ordering.md).

Success returns a length-one View with the original backing and
`start = values.start + nth`. It aliases the actual stored nth element, with
the original native stride; it is not a detached value or a new memory owner.
After success, existing half-open subviews expose the partitions:

- `values.subview(0, nth)` contains the elements before the selected slot;
- `values.subview(nth + 1, values.length)` contains the elements after it.

These views share backing. A later selection or mutation can change their
contents and invalidate an earlier rank/selected-position interpretation.

## Admission and rank guarantees

Before element access, mutation or comparison, revalidate nonnegative start
and length, a nonoverflowing `start + length`, then `0 <= nth < length`.
Every rejection is `ViewError::Bounds` and preserves the complete backing and
comparator state. Empty views always reject. A valid singleton returns its
one-element alias without comparing.

For a consistent total comparator, the stored nth element has that rank in
the sorted input: no preceding element compares Greater and no following
element compares Less. Both sides remain internally unordered. Equivalent
elements have no stable representative or relative-order guarantee. Less and
Greater follow the supplied policy; a reversed comparator selects descending
ranks.

The selected range remains a permutation of whole shallow values, and backing
outside it stays unchanged. Logical descriptor checks do not establish physical
backing length or unchecked memory authority. Keep every selected slot live,
initialized and physically valid; the [View guide](stdlib-slice-views.md)
describes the manual backing and lifetime requirements.

## Deterministic groups of five

The engine uses median-of-medians selection with a fixed explicit frame stack:

1. A frame holds relative half-open low/high endpoints, its view-relative
   target index and a phase. At most five elements are handled by insertion sort.
2. Otherwise, sort groups of at most five and move each group's middle into
   the active prefix. Include a final short group, using its floor(length/2)
   middle. Select the middle rank of that median prefix.
3. Suspend the parent while selecting its medians. Four i32 arrays have
   sixteen slots each. Median-child length is `1 + (n - 1) / 5`; descending
   from i32::MAX needs at most fourteen active frames. Selecting a remaining
   parent partition reuses that frame rather than pushing another one.
4. Keep the chosen pivot at the active end, outside the scan. Partition the
   other elements into Less/Equal/Greater bands, then insert that protected
   pivot into the equal band. The equal band therefore contains at least the
   pivot even under inconsistent answers.
5. Complete the frame if its target is in the equal band; otherwise continue
   with a strictly smaller side. A completed child reports its target position
   to its suspended parent. The root completes at the original nth slot.

Subtraction-based group arithmetic and child-existence checks keep indices
within the admitted relative range. There is no native recursion or heap
allocation. The sixteen-frame capacity bounds pending median work for this
i32-indexed API; it does not require allocating an i32::MAX-element input.

With a lawful total order, group sorting and partitioning take linear work;
the median child has ceil(n/5) elements and the retained side has at most
7n/10 + O(1). Thus worst-case comparisons and swaps are O(n), with callback
cost additional. This is the classical algorithm argument, not a formal proof
or the optimized PICK comparison constant.

The primary sources are [Blum et al.](https://people.csail.mit.edu/rivest/pubs/BFPRT73.pdf)
and [Chen and Dumitrescu, section 2](https://arxiv.org/pdf/1409.3600), with a
compact [NIST Select description](https://xlinux.nist.gov/dads/HTML/select.html).
This implementation adds duplicate bands and explicit frames to that family.
Rust's [selection API](https://doc.rust-lang.org/std/primitive.slice.html#method.select_nth_unstable_by)
provides a related rank/partition contract; Lanius returns a checked one-element
View and exposes the other partitions through existing subviews.

## Callbacks, ownership and failures

Selection allocates, clones and destroys nothing and transfers no cleanup
authority. Swaps relocate shallow handles between initialized slots. Release
each actual owner once from its final position after all borrowed views expire.
Comparator arguments likewise grant no authority to retire their backing.

Keep the comparator's ordering policy and all source/context backing valid
throughout the call. Do not mutate source elements, reenter the operation or
retire owners through interfering aliases. Call counters/logging are permitted
when they leave comparison answers and storage unchanged.

The callback returns Ordering, without a recoverable error envelope. A trap or
divergence may follow partial permutation; there is no rollback. Inconsistent
answers give no rank, partition or linear-cost guarantee. Structural loops
still progress if callbacks return and preserve storage, because the protected
pivot cannot be excluded from its own band.

## Application, verification and targets

The [`select_value INDEX` program](stdlib-select-value.md) reads bounded
signed-i64 decimal tokens from stdin and prints the ascending order statistic.
It uses the public natural-order function, stages output and releases explicit owners before
publication. All four registered groups pass in 8.60s: model 33, rejection 25,
CLI 28 and I/O 15, totaling 101 native cases. Three reached owner-allocation
denials, genuine EOF/last-read failure and cleanup before output are checked;
these are application effects, not allocations by the selection engine.

| Receipt in `target/stdlib-work/` | Accepted scope |
| --- | --- |
| `slice-selection-admission-first.log` | One test/6.93s: custom 17-element median and natural 17-element maximum; returned aliases mutate the original subview, with outside guards preserved. Full syscall trace contains only entry/exit. |
| `slice-selection-contracts-first.log` | Two tests/7.25s: one native five-scenario process and three marked Comparator/Ord bound rejections; admission filtered. |
| `slice-selection-ordering-regression.log` | One selected existing checked-ordering test/7.11s: payload/bounds behavior without memory services; two tests filtered. |
| `slice-selection-value-app-first.log` | Four application tests/8.60s: all 101 native cases on unchanged app `b942ea04`. |
| `slice-selection-owner-scale-first.log` | Two tests/14.53s: 57 exact owner releases/five pure phases; 180 scale selections/180 pure phases/two reused backing releases. |
| `slice-selection-model-stride-oracle-retry.log` | One test/8.71s: 11,976 sorted-reference cases, three families/two backing forms/three record policies, seed `0x5e1ec0261101`; source lengths at most 40. |

This [direct fixture](../tests/fixtures/stdlib_foundation/slice_selection/README.md)
executes slice source `d77cb28c`. The [owner/scale fixtures](../tests/fixtures/stdlib_foundation/slice_selection_owners/README.md)
check nested String/Vec payloads, zero-sized Unit, actual aliases and full
address/extent cleanup, with no host calls in selection phases. Scale covers
257/4096/65536 elements, six families, five ranks and both APIs. Observed
maxima are 9.369766235351563 custom Compare calls/n and 12.4439697265625
Natural lt calls/n, under separate finite 100n/200n ceilings. Natural may make
two lt calls per comparison; these counters are not interchangeable, a
throughput measurement or a proof of complexity.

The [independent model](../tests/fixtures/stdlib_foundation/slice_selection_model/README.md)
checks sorted rank, both partitions, whole-value permutation, surroundings,
returned metadata and actual alias mutation. Its first run failed an oracle-
only native-byte-stride assumption; the correction requires negative native
stride, packed +1 and exact returned/input stride equality. Producer and
production were unchanged. CPU corruption/depth controls are separate from
native case counts. No earlier ordering receipt establishes either new function.

The accepted executable profile is native Linux x86_64 CPU output produced by
the GPU compiler. Direct GPU execution, other targets, formal verification and
automatic ownership/lifetimes are unverified. Production remains Lanius; this
increment adds no compiler, ABI or host-service change.
