# Pattern-defeating quicksort and run-adaptive stable sort

`core::slice` now sorts with two adaptive engines. Neither allocates.

| Function | Algorithm | Stable | Extra storage |
| --- | --- | --- | --- |
| `sort_unstable_by<T,C>(values, comparator)`, `sort_unstable<T>(values)`, `sort<T>(values, len)` | Pattern-defeating quicksort (pdqsort) | No | O(log n) index stack |
| `sort_stable_by<T,C>(values, scratch, comparator)`, `sort_stable<T>(values, scratch)` | Run-adaptive merge sort with galloping (TimSort shape) | Yes | Caller scratch of at least `values.length / 2` elements |

`sort_unstable_by` and `sort` keep their signatures; only the engine changed,
from heapsort to pdqsort. `sort_unstable` is a new natural-order View entry
point. The stable functions are new. Each checked entry point returns
`Err(Bounds)` for an invalid View before any read or comparator call; the
stable ones also return `Err(InvalidSize)` when scratch is shorter than half
the input. Scratch is overwritten with shallow copies, grants no cleanup
authority and must not overlap the input. `alloc::slice::sort_by` keeps its
bottom-up merge sort and its documented `n * ceil(log2 n)` comparison bound,
which galloping would not guarantee.

## Pattern-defeating quicksort

The engine follows Orson Peters' pdqsort:

- ranges below 24 elements use insertion sort;
- the pivot is the median of three, or Tukey's ninther above 128 elements;
- a partition reports whether it swapped anything. A balanced partition
  that swapped nothing gets a bounded insertion repair (at most eight moved
  elements per side), which finishes sorted and nearly sorted ranges in
  linear time;
- when the pivot equals the element before the range, all elements equal to
  it are partitioned off at once, so inputs with few distinct keys take
  linear time per key;
- a partition with a side below one eighth of the range swaps a few elements
  at fixed fractions to break the pattern. After `floor(log2 n)` such
  partitions the range falls back to the existing heapsort, so the worst case
  stays O(n log n) comparisons;
- the larger side is pushed on a 40-entry stack and the smaller one
  processed first, so pending work stays logarithmic.

Every scan is index-guarded, so a comparator that is not a total order can
produce an unspecified permutation but never reads outside the range.

## Run-adaptive stable merge sort

The engine follows CPython's listsort:

- natural runs are found left to right. Non-descending runs are kept,
  strictly descending runs are reversed in place (strictness keeps
  stability), and runs shorter than the minimum run length (32 to 64,
  computed from n) are extended by binary insertion;
- a run stack keeps listsort's length invariants, so at most 64 runs are
  pending for any i32 length and merges stay balanced;
- before each merge, exponential then binary search skips the prefix of the
  left run that is already below the right run's first element and the
  suffix of the right run that is already above the left run's last element;
- the smaller remainder is copied to scratch and merged from that end. After
  seven consecutive wins by one side the merge switches to galloping mode,
  with an adaptive threshold carried across merges.

Equal elements keep their input order. Sorted, strictly descending and equal
inputs take exactly n - 1 comparisons.

## Evidence

`tests/fixtures/stdlib_sort_algorithms/model.lani` and `oracle.py` (registered
as `tests/stdlib_sort_algorithms_model_execution.rs`) run 1,659 cases: 19
patterns at 29 sizes from 0 to 20,000, each through pdqsort, the new stable
sort and `alloc::slice::sort_by`, plus McIlroy's adversary at six sizes.
Patterns are random 64-bit keys, two, 16 and sqrt(n) distinct values, sorted,
reversed, strictly descending, descending with duplicates, all equal, organ
pipe, sawtooth, reverse sawtooth, sorted with 1% swaps, sorted with a random
tail, one element pushed to the front, random ascending and descending runs,
Musser's median-of-three killer, zigzag, and 64-bit extremes. Unstable output
must equal Python's `sorted(keys)`; stable output is the permutation of
original indices and must equal Python's stable `sorted` of the indices by
key. Every sort stays within 2 n log2 n + 2 n comparisons, and the stable
sort makes exactly n - 1 on sorted, strictly descending and equal inputs.

[McIlroy's adversary](https://www.cs.dartmouth.edu/~doug/mdmspe.pdf) freezes
values lazily so that every pivot is as bad as possible. Against pdqsort it
forced 48, 1,479, 2,059, 24,683, 131,881 and 781,937 comparisons at n = 24,
100, 129, 1,000, 4,096 and 20,000, within 4 n log2 n + 2 n; a quadratic
quicksort would make about n^2/2 (200 million at 20,000). Removing the
heapsort fallback breaks that bound at n = 129.

Totals over all 1,659 cases: pdqsort 4,131,903 comparisons, the stable sort
2,320,575, `alloc::slice::sort_by` 4,732,602, Python's `sorted` 2,379,588 on
the same inputs (counted with a `__lt__` wrapper). At n = 20,000:

| Pattern | pdqsort | stable | alloc merge | Python |
| --- | --- | --- | --- | --- |
| random | 320,970 | 260,782 | 267,388 | 259,663 |
| 2 distinct | 50,087 | 90,413 | 214,973 | 95,761 |
| 16 distinct | 110,275 | 157,458 | 262,789 | 156,888 |
| sorted | 40,009 | 19,999 | 153,424 | 19,999 |
| reversed | 60,028 | 19,999 | 139,216 | 19,999 |
| organ pipe | 426,396 | 39,999 | 149,213 | 39,999 |
| sawtooth | 117,867 | 147,036 | 246,439 | 149,842 |
| 1% swaps | 205,808 | 37,012 | 224,361 | 46,281 |
| random runs | 244,256 | 198,349 | 229,364 | 204,733 |
| median-of-3 killer | 316,845 | 75,223 | 197,555 | 76,970 |

Four deliberately broken engines were run against the model. Three fail it:
no heapsort fallback (adversary bound), merge ties taken from the right
(stability), and non-strict descending runs reversed (stability). The
fourth, an unbounded partial insertion repair, is an efficiency limit that
these inputs do not expose. The oracle and native process take 3.2 s.

`tests/fixtures/stdlib_sort_algorithms/bench.lani` times 100,000 u64 keys per
pattern natively. The machine was shared with other compile jobs, so times
are indicative. Heapsort is the previous `sort_unstable_by` engine, built
from the prior `core::slice` source:

| Pattern | heapsort (old) | pdqsort | stable | alloc merge |
| --- | --- | --- | --- | --- |
| random | 163 ms / 3.02 M | 82 ms / 1.84 M | 90 ms / 1.53 M | 91 ms / 1.57 M |
| sorted | 132 ms / 3.11 M | 5 ms / 0.20 M | 3 ms / 0.10 M | 57 ms / 0.88 M |
| reversed | 129 ms / 2.93 M | 10 ms / 0.30 M | 5 ms / 0.10 M | 56 ms / 0.82 M |
| 16 distinct | 130 ms / 2.87 M | 21 ms / 0.56 M | 60 ms / 0.79 M | 86 ms / 1.54 M |
| organ pipe | 137 ms / 3.05 M | 88 ms / 2.55 M | 9 ms / 0.20 M | 52 ms / 0.87 M |
| sawtooth (period 1,000) | 147 ms / 2.99 M | 50 ms / 1.50 M | 27 ms / 0.57 M | 68 ms / 1.24 M |
| 1 in 997 replaced | 132 ms / 3.11 M | 45 ms / 1.63 M | 11 ms / 0.11 M | 64 ms / 1.14 M |

The existing slice-ordering model (2,808 cases), the stable-sort model
(5,946 cases), the slice-ordering contracts, owners and scale fixtures, the
three exhaustive small-sort fixtures and four other `core::slice` users pass
on the new engine. The compiler is the prebuilt one through `lcc`; the
registered Rust test was not compiled or run.
