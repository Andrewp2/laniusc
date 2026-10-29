# Independent slice segmentation model

This finite runtime model covers `Split`, `SplitInclusive` and `ChunkBy` over
borrowed byte Views. The Python reference represents each cursor as remaining
element indices, separately from the mutable backing and shared callback
context. For each pull it evaluates the candidate cuts from the current
snapshot, selects the first semantic boundary, and admits only the callback
prefix through that boundary. It does not copy the production scan loops or
inspect cursor fields.

## Corpus and observations

Seed `0x5e6a0261109` fixes 277 input profiles:

- All 85 inputs of length zero through three over NUL, LF, comma and `0xff`.
- All 112 inputs of length four through six over NUL and comma.
- 16 literal profiles covering empty/terminal separators, repeated values,
  a changed adjacent boundary operand, all byte values and long runs.
- 64 seeded profiles up to 511 bytes, alternating delimiter-heavy and uniform
  byte distributions.

The first 213 profiles use four initial predicate configurations; the other
64 use one each. All run through three cursor families and both actual byte
layouts: native arrays with stride `-8` and packed raw views with stride `+1`.
Selected Views begin at origins 3, 5 or 7. The complete corpus has **5,496
cases**, **183,248 pulls**, **98,114 yielded segments**, **313,978 callbacks**,
**79,326 cursor copies**, **26,924 backing edits**, **25,464 context edits** and
**25,152 observations of saved Views**.

Each case first traverses an unchanged original to exhaustion. The reference
requires exactly n unary calls or max(n-1,0) adjacent calls. Later actions copy
cursors in both directions, restart from an unchanged original cursor, edit
individual backing cells, change predicate mode/key, and interleave pulls of
copies sharing one callback context. Predicate configurations include pure
equality, asymmetric adjacent comparisons and decisions based on the global
callback ordinal. They require no equivalence or transitivity law.

The callback trace records every operand in order, its answer, ordinal and
context. The changed-boundary witness requires `ChunkBy` to reread the left
operand of its next pair after a between-pull write. Already selected bounds
are retained. Saved yielded Views are observed again after edits, checking
that they remain live borrowed views. Both cursors are drained, then probed
again after backing and context edits and copying an exhausted cursor.

Every segment includes its absolute start, byte length, actual stride and
complete bytes. `Some(empty)` and `None` are distinct. Initial/final original
descriptors and complete 520-cell backing arrays, including guards outside
the selected View, are compared. Callback-written context is compared after
every action. Only explicit test edits may change backing.

## Execution and controls

One native process handles the complete binary batch. Input uses seven
little-endian u64 fields, input bytes and fixed four-byte action records.
Output frames actions, callback events, segments, context and backing bytes.
No JSON or aggregate hash substitutes for full comparisons. Payloads are at
most 511 bytes, action lists at most 64 records and output staging 4,096 bytes.
The reference may examine hypothetical later cuts; it publishes only the
callback prefix that a lazy pull is permitted to perform.

Host-only controls pass the full corpus and reject 14 deliberate corruptions
of metadata, callback ordering/operands/answers, item framing/content, backing,
and missing/extra output. Literal controls independently check empty split
segments, inclusive terminal behavior and the changed adjacent operand.
These validate the reference/verifier and are separate from native execution.
The revised root-owned native gate passed one test in 8.75 seconds, with a
separate Rust build of 0.18 seconds:

```text
stdlib_slice_segmentation_model_execution::independent_slice_segmentation_matches_partitions_callbacks_copies_and_alias_edits
```

The first gate stopped during compilation with `LNC0027` at `model.lani:83`:
one fixture receiver implemented both unary and adjacent `Mapper` applications.
It failed one test in 3.94 seconds, with a separate Rust build of 1.78 seconds;
no native model executed. The receipt is
`target/stdlib-work/slice-segmentation-model.log`. This is the existing
[distinct trait applications on one receiver dependency](../../stdlib_foundation/slice_ordering_dependency/README.md).
The revised fixture uses `UnaryPredicate` and `AdjacentPredicate`, both
borrowing the same `Context`. The predicate decisions, shared callback ordinal,
corpus, oracle, schedules and production interfaces are unchanged.

The successful receipt is `target/stdlib-work/slice-segmentation-model-revised.log`.
It confirms 5,496 cases, 183,248 pulls, 98,114 yielded items, 313,978 callbacks,
79,326 copies, 26,924 backing edits, 25,464 context edits and 25,152 saved-view
observations with seed `0x5e6a0261109`.

The accepted source identities are:

| File | SHA-256 |
| --- | --- |
| `model.lani` | `511fcff4907a9c17fb8ac207d5cb893f157b4e4f600cb852aa8feabffec96fc7` |
| `oracle.py` | `2f145b8d202c65e025d4597ddd293b6fcbee93925640751b6df711cb4a1d60e2` |
| `tests/stdlib_slice_segmentation_model_execution.rs` | `1e7ded3aa046cc03453a57286fed602db16ef7f85a1a75c65a6de17408ff070e` |

The tested target is Linux x86_64 CPU execution. Compiler GPU use does not
establish user-program device execution. The model covers byte elements;
separate direct gates cover compound element types, invalid logical metadata
and capability errors. This is finite executable evidence, not a proof or
lifetime/alias enforcement. Physical backing, stable storage and lifetime
remain caller obligations. The test makes no mutation during a callback and
does not test reentrancy, forged cursor state or callback trap recovery.
