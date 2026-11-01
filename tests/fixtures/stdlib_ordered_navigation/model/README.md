# Ordered navigation model

`model.lani` reads 64-byte commands (eight little-endian words) from stdin and
applies them to a `TreeMap<Key,u64>` or `TreeSet<Key>`, where `Key` orders by
an i32 identity and carries a stamp. A `Band` query policy makes identities
below `low` Less, above `high` Greater and the rest Equal, so one query can
denote a run of several keys. The policy writes every call (stored key and
which bound it serves) to stdout.

`oracle.py` generates 48 seeded cases, runs the executable once and checks the
transcript against a dict with per-query sorting. It checks results, cursor
pulls from both ends, fused exhaustion and full snapshots, and it checks every
policy call sequence as a lawful binary-search descent without fixing an AVL
shape (see the module docstring). Nine corruptions of the real transcript must
each be rejected. The printed summary is compared exactly by
`tests/stdlib_ordered_navigation_model_execution.rs`.

Commands: 0 reset to a family, 1 insert/replace, 2 remove, 3 same-key
navigation, 4 policy navigation, 5 same-key `range_bounds`, 6 policy
`range_bounds_by`, 7 snapshot, 8 clear, 9 `remove_range`, 10 `remove_range_by`,
11 `try_extract_range`, 12 `try_extract_range_by`, 13 `try_split_off`. Edit
responses report the count or extracted entries in order and the capacity
facts (source capacity unchanged, extracted capacity exact); the oracle
applies the same edit to its dict and checks the following snapshots.
