# Comparator-driven slice sequence model

This fixture exercises all seven checked View APIs in
[the ordering plan](../../../../docs/library-slice-ordering-plan.md). The
Lanius producer is a binary test adapter. The independent Python reference
uses sorting, bisect, filtering and whole-record multisets; it does not
reproduce heapsort or predict an unstable tie layout.

## Finite coverage

There are **2,808 cases and 44,928 actions**, with seed `0x510ce0261029`:

- Every sequence of length zero through four over `[-1, 0, 1]`, under all six
  comparison policies, in both backing forms: 1,452 cases.
- Explicit interior subviews for every backing length zero through twelve,
  under all policies and both forms: 156 cases.
- 600 seeded datasets over lengths zero through twelve, paired across both
  forms: 1,200 cases.

Each case repeats sortedness, partition, sorting and all four searches, then
switches comparison context, sorts again, repeats the searches and partitions
again. Contexts order by ascending/descending key, ascending/descending
absolute key, absolute-key buckets with a width, or distance from a center.
Several policies deliberately equate distinct keys. A policy remains fixed
throughout each public call.

Rows have unique identities and nested payloads containing a full-width
marker, two integer fields and an optional Boolean. Search keys are a distinct
record type with a checked canary. Sort and heterogeneous callbacks have
distinct receiver types borrowing the same policy context: the compiler
currently rejects two `compare` implementations on one receiver despite
different Comparator arguments. The separate minimal diagnostic/control
fixtures document that dependency; the library API stays generic.

Backing form zero is a native stack record array; form one uses explicit
caller storage through `typed_slice_from_storage<Row>`. Both have the native
descending record stride. A parent view and selected subview both introduce
nonzero offsets. Every action reports all twenty backing rows, including the
unselected active records and surrounding guards. This checks subview-relative
results, whole-record permutation and preservation of every unselected field.
It does not claim an arbitrary-stride constructor or a positive record ABI.

The oracle checks ordered projected keys and the multiset of complete records
after sort. For partition it checks the Less boundary and exact multisets on
both sides. It accepts any valid permutation within those constraints, adopts
that actual state, and then checks later calls. Read-only APIs must preserve
the entire backing. Duplicate searches must return the first/last equivalent
index. Empty calls and singleton sorting must make no comparator call;
nonempty comparison schedules are not pinned to an implementation.

Operation counts for sort, sortedness, lower bound, upper bound, first search,
last search and partition are respectively
`5616, 11232, 5616, 5616, 5616, 5616, 5616`.
The 5,616 search query groups include 1,002 duplicate matches, 896 singleton
matches and 3,718 misses; 1,240 are empty-view queries, 910 precede every rank
and 1,384 follow every rank. Those categories overlap where stated.

All generated row keys are in `-12..=12`, lookup values in `-20..=20`, centers
in `-4..=4`, and widths in `1..=4`. The callback's negation, absolute value,
subtraction and division are therefore representable. This corpus tests
ordering semantics, not arbitrary arithmetic in a user callback.

## Protocol and acceptance

Input starts with eight little-endian `u64` words:
`layout, backing_count, selected_start, selected_length, action_count,
case_identity, reserved, reserved`. The active keys follow, then four words per
action: operation, lookup value, policy and policy parameter. Signed words use
two's complement. The producer bounds-checks the finite framing.

Each action emits operation, result and comparator count, then six words for
each of twenty backing rows. Missing searches are encoded as `-1`; sorting
returns selected length. The oracle rejects extra or truncated output and
includes the seed, full case and action in mismatch diagnostics.

CPU controls pass: two distinct legal unstable layouts are accepted, while
corrupted guard storage, a nested payload, a partition boundary and a non-first
duplicate hit are rejected. The registered gate is
`independent_slice_models_match_whole_records_orders_bounds_and_partition_sides`
in `stdlib_slice_ordering_model_execution`. The driver uses shared strict x86
ELF checks and one batched native process, with an 85-second outer timeout and
a 70-second child timeout.

The first registered runtime run passed: **one test, 2,808 cases and 44,928
actions in 6.59 seconds**, across both backing forms and all six policies.
The log is `target/stdlib-work/slice-ordering-model-first.log`; the exact oracle
summary is
`slice-ordering cases=2808 actions=44928 layouts=2 policies=6 seed=0x510ce0261029`.
The accepted target is native Linux x86_64 CPU output from the GPU compiler.
This finite run checks the listed observations for this corpus; it supplies
no direct GPU execution or formal proof claim.

Tested SHA-256 identities:

| Source | SHA-256 |
| --- | --- |
| `stdlib/core/slice.lani` | `a39b2bb5661cac046caf06c367b72da39b36e1ae3b211db12af68c9c9b7ac2f0` |
| `stdlib/core/ordering.lani` | `b09a297dcc64fb3440ae802d691fbdb5c317f521dc886b2d8cacb493124e67ac` |
| `model.lani` | `1c99e1a00c2247fdffea3e51b82ed866fe15baf8e6f754b700c98f7031c6b3ed` |
| `oracle.py` | `48d9622dd214aa3c5121e76246d1e4c4ca66d1c5120f9fe18c663dfa17267754` |

```sh
python3 -B tests/fixtures/stdlib_foundation/slice_ordering/oracle.py controls
python3 -B tests/fixtures/stdlib_foundation/slice_ordering/oracle.py /path/to/model
```
