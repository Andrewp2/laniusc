# Lazy map operation model

`model.lani` executes both map families through their public natural and
borrowed-query operations. `oracle.py` supplies a deterministic binary action
stream and compares every returned value, initializer/updater event and complete
logical snapshot against a Python dictionary. It models no hash-table or AVL
storage structure. Hash iteration is unordered; tree iteration must be sorted.

The corpus uses seed `0x6a90261106`: eight operation histories, each executed
with three HashMap hash distributions and one TreeMap order. The 32 cases have
5,920 actions, including 2,104 natural and 2,192 borrowed lazy operations.
Expected paths include 1,879 lazy insertions, 1,015 updates, 318 initializer
errors, 1,084 candidate mismatches and 550 Result-valued update errors. A bad
initializer is deliberately ignored on 786 hits. Full snapshots compare 90,439
entries, including their independently stamped representative keys.

The histories mix ordinary replacement insertion, remove, clear, observation
and both lazy operations; fill collision groups; remove and reuse slots; and
exercise empty maps, failure before insertion, all-ones/high-bit values and
updates after prior errors. Values contain an `Option<bool>` field and a
per-entry visit count. Every hit and recoverable lazy error also checks that
backing, capacity and length remain unchanged. Initializer failures and
candidate mismatches return exact payloads. Tree candidates may legitimately
change a non-ordering hash-code field; HashMap rejects a mismatching hash.

Host observer controls reject 15 corruptions: omitted/extra callbacks, changed
callback input, wrong initializer error, damaged recovered candidates, wrong
success variant, replaced key identity, update-error rollback, wrong callback
counts, missing/duplicate entries, unordered tree iteration and broken framing.
Run the controls with:

```sh
python3 -B tests/fixtures/stdlib_lazy_map/model/oracle.py controls
```

The registered native selector is
`lazy_map_operations_match_dictionary_candidates_callbacks_and_representatives`
in `tests/stdlib_lazy_map_model_execution.rs`. It passed one Rust test in 6.48 s,
recorded in `target/stdlib-work/lazy-map-model-complete.log`, with all 32 cases,
5,920 actions and path counts above. Initial fixture match blocks were rewritten
as valid expressions; no production map or compiler change was needed.
Host controls alone do not establish Lanius behavior.
Allocation denial and nested-owner cleanup belong to the separate resource
fixtures, not this model. User policies here obey the global key-consistency
laws; detecting every unlawful comparator is outside the API contract.
