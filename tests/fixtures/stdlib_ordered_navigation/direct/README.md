# Ordered navigation direct fixtures

Driven by `tests/stdlib_ordered_navigation_execution.rs`; the contract guide is
[docs/stdlib-ordered-navigation.md](../../../../docs/stdlib-ordered-navigation.md).

| Fixture | Checks |
| --- | --- |
| `contracts.lani` | Exact policy calls on a perfect 15-key AVL tree, all bound kinds, equal and reversed points, two-ended pulls, full-domain i32 intervals, InvalidRange, TreeSet forms and TextPrefix families over owned Strings. In-program checks: navigation leaves every owner field unchanged, and all twelve String owners are released exactly once. |
| `edits.lani` | Range removal, extraction and split_off on 40,000-entry maps and sets. The fixture lowers its own RLIMIT_AS soft limit to 1 MiB (prlimit64), shows a fresh 20,000-node owner is refused, and checks that failed extractions leave every owner field and the contents unchanged while removal, navigation, InvalidRange and empty extraction behave normally. With the limit restored: exact extracted capacities and contents, retained source capacity, refill without growth, and eight moved Strings released exactly once. |
| `negative_tree_map_missing_comparator.lani` | `last_below_by` without `Comparator<K,Q>` on an empty map |
| `negative_tree_set_reversed_comparator.lani` | `range_bounds_by` with a query-first `Comparator<Q,T>` |
| `negative_tree_map_range_bounds_without_ord.lani` | `range_bounds` for a key without `Ord` |
| `negative_tree_set_last_at_most_without_ord.lani` | `last_at_most` for an element without `Ord` |

Each negative fixture must fail with LNC0008 at the line holding
`rejected_navigation_bound`.
