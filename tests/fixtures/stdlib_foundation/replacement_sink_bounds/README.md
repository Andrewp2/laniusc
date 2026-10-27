# Replacement-sink negative admission

Status: all five negative-admission Rust tests passed. Every caller was rejected
with the intended `LNC0008` on its source-local helper call.
These are invalid callers of the actual imported `core::iter::try_replace_up_to`
and actual collection facades, not fake APIs or a second transfer engine.
Positive execution of the four collection facades is a separate gate.

Each fixture specifies the source cursor, replacement destination, displaced
destination, helper generic arguments and receiving result explicitly. Exactly
one intended trait obligation is invalid; the receiving type does not invent
another item or error identity.

| Fixture | Accepted rejection |
| --- | --- |
| `hash_map_wrong_entry_module.lani` | HashMap is not a replacement sink for nominal TreeMap Entry; source and displaced Vec agree on TreeMap Entry. |
| `hash_map_missing_hash.lani` | Key implements exact `Eq<Key>` but has no `Hash<Key>`; item and both errors otherwise agree. |
| `hash_map_wrong_replacement_error.lani` | HashMap replacement returns raw storage Error, not duplicate-rejecting SinkError. |
| `wrong_displaced_item.lani` | Displaced Vec accepts TreeMap Entry while source and replacement use HashMap Entry. |
| `wrong_displaced_error.lani` | Displaced Vec returns Vec Error, not nominal Deque Error with similar variants. |

The Rust driver requires `LNC0008` (`TraitBoundUnsatisfied`) with its primary
label in the particular fixture on the explicit `try_replace_up_to` call.
Malformed syntax, ambiguous implementation headers, an earlier constructor
failure or an accepted ELF all fail the test. The key fixture has only one
ordinary public Eq implementation; no caller supplies a fake replacement
implementation or weakens collection bounds.

## Accepted receipt

`target/stdlib-work/replacement-bounds-first.log` records **5 passed, 0 failed**
in 5.67 seconds. The same Cargo command first rebuilt the test profile in
1 minute 00 seconds, then ran
`stdlib_replacement_sink_bounds-46dec5fe698b1bce`. The complete command returned
zero in under 100 seconds; 5.67 seconds is the test phase, not the whole
build-and-test duration.

The driver and five fixtures remained unchanged from the authored checkpoint.
The driver SHA-256 is
`3d2e617ef30f964ec5c50172ed6ed57b429e31c4691729779a37f93c402209af`.
All five diagnostic codes and primary labels passed the checks above. No
native program was executed by these tests. This is acceptance of the five
selected compiler rejections, not runtime ownership, collection behavior,
native-resource or user-program target acceptance.

## Bounded commands

Root serializes compiler work under the shared GPU lock. Each driver case
uses the existing bounded compiler harness; an outer command remains below
two minutes. A focused command after driver admission is:

```sh
timeout --kill-after=2s 110s env \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test stdlib_replacement_sink_bounds -- --nocapture --test-threads=1
```

Exact test filters:

- `replacement_sink_rejects_nominal_tree_entry_at_hash_map`
- `replacement_sink_requires_hash_bound_on_key`
- `replacement_sink_requires_exact_replacement_error`
- `replacement_sink_requires_exact_displaced_item`
- `replacement_sink_requires_exact_displaced_error`

Positive executable collection behavior and the broader replacement campaign
retain their separate receipts and acceptance obligations.
