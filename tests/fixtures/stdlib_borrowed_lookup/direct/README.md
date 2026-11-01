# Borrowed lookup direct contracts

These fixtures target the sixteen heterogeneous point methods in
`docs/library-borrowed-lookup-plan.md`. The registered driver is
`tests/stdlib_borrowed_lookup_execution.rs`.

## Behavioral witnesses

- `admission.lani`: all sixteen methods on all four collection types, with a
  distinct query record, compound value, full-width integers and a returned
  `Result::Err`. Missing keys skip updates; hit updates install the new value
  even when their report is an error. Stored representatives survive lookup
  and transfer through removal. Four collection allocations are released.
- `contracts.lani`: exact query hashing, cached-hash filtering, one tree
  comparator call per visited node, and search completion before updates or
  removals. Hashes deliberately share an initial bucket while differing in
  their complete cached value. Independent live-key/value tables check every
  survivor after collision/tombstone and AVL removal/reuse sequences. The
  returned representative tag differs from query instrumentation. Comparison
  prefixes match ordinary borrowed searches without fixing an incidental AVL
  shape. Every callback log tail is guarded. Four allocations are released.
- `types.lani`: enum queries containing borrowed byte Views, scalar queries,
  multiword array values, and nested `Option<bool>` reports pass through generic
  forwarding. Helpers require only the documented query/update bounds. An
  opaque stored type has no Hash/Eq/Ord; all sixteen empty queries still execute
  without calling poisoned policies. A separate tree query has no Hash/Eq/Ord.
  TextKey checks UTF-8 byte equality/order, embedded NUL, prefix, case and lack
  of normalization, preserving all backing bytes. Existing same-key tree
  queries explicitly retain `lt(query,stored)` then `lt(stored,query)` effects.
  Six allocations are released: four collections, one String and one separate
  tree for the natural comparison-order control.
- Seven hash and six tree negative fixtures isolate missing or mismatched
  query/policy/update capabilities on empty collections. These require
  `LNC0008` at the marked call in the fixture itself. The executable positive
  fixtures provide controls for both map and set policy forms; expected
  compile rejection is never presented as runtime behavior.

All executable groups require native x86_64 ELF output and the shared
in-function jump validation, execute their assertions, and inspect the full
syscall trace. Only one exec, the exact matched allocation/release lifetimes
above, and successful exit are accepted; stdout/stderr must be empty. No
allocation is attributable to a query or its scalar instrumentation in these
fixtures. Real nested ownership, externally backed String/Text queries,
resource retirement and scale are covered separately by the resource suite.

## Receipts

Accepted against the frozen production files below:

| Group | Result | Duration | Local log |
| --- | --- | --- | --- |
| Tiny admission | 1 passed | 6.57 s | `target/stdlib-work/borrowed-lookup-admission.log` |
| Representatives/effects/removal | 1 passed | 6.63 s | `target/stdlib-work/borrowed-lookup-contracts.log` |
| Generic types and TextKey | 1 passed | 6.78 s | `target/stdlib-work/borrowed-lookup-types-qualified.log` |
| Hash bounds (7 fixtures) | Passed | 10.19 s combined mixed run | `target/stdlib-work/borrowed-lookup-types-bounds.log` |
| Tree bounds (6 fixtures) | Passed | Same mixed run | `target/stdlib-work/borrowed-lookup-types-bounds.log` |

The tiny driver build took 1.42 s separately. Tiny admission used driver
`6068937d3679b49c7915289edc1e497bd958500cc2245a6e22dceed393e9fc48`.
The contracts gate used driver
`6103cdba9bac120e7955bd322cd6387bc6e1ab88f71a16d530caa112c0c852dc`.
The final driver adds three selectors without changing those two test bodies
or the execution helper. Independent static review passed for the direct fixtures, all thirteen
negative sources, and the shared driver. Static review is separate from the
native receipts.

Three types-fixture attempts failed before the accepted native retry; none changed the
production library or the expected six allocation lifetimes:

- `borrowed-lookup-types-bounds.log`: 2 passed / 1 compile failure in 10.19 s.
  Types `a2c35a9a` called nonexistent `HashMap::with_capacity` (`LNC0027`);
  the fixture now calls `new` and `try_reserve(4)`. Both negative groups passed.
- `borrowed-lookup-types-fixed.log`: 1 compile failure in 3.71 s, at types
  `b68620aa`. Two `Mapper` implementations on `Never` collided on `apply`
  (`LNC0027`). Separate `NeverUpdate` preserves the minimal-bound witness;
  the same-receiver dispatch limitation is tracked separately from authoring
  mistakes.
- `borrowed-lookup-types-separated.log`: 1 compile failure in 3.80 s, at
  types `6c4e4203`. Unqualified imported `Equal` was ambiguous (`LNC0005`).
  All five TextKey ordering patterns now use `core::ordering::` qualification.

All five direct groups are accepted across these scoped runs: three native
execution groups and two compile-rejection groups covering thirteen fixtures.
The final types run accepted source `96c6cf09` with exactly six matching
allocation/release lifetimes. Independent review also passed each narrow
fixture correction; accepted groups were not repeated.

These are finite Linux x86_64 runtime observations from the GPU compiler.
They do not establish GPU-device execution, arbitrary invalid descriptor
safety, automatic borrowing/destruction, a universal complexity benchmark or
formal verification. No byte snapshot of internal allocation padding or AVL
node arrangement is an API assertion.

## Frozen sources

| File | SHA-256 |
| --- | --- |
| `stdlib/alloc/hash_map.lani` | `71eaba30c301152407d425da005306b0debc42ff425e34b9cf2131c76c1ae993` |
| `stdlib/alloc/hash_set.lani` | `57bc87c07be46954e50f0fb15a0d662f5db8569ba8f80bb738849f61977188e1` |
| `stdlib/alloc/tree_map.lani` | `0580aa43d59b75287a64b520d98399fe56d7f98043a2b417a6db72c7695f33db` |
| `stdlib/alloc/tree_set.lani` | `b8db6d379b37c5ed0fd923f1cc6782f5be4567cc78b98abe1c095a418dbebea5` |
| `stdlib/alloc/string.lani` | `1507bddaa17bc1f57142392a3f9f8ffcd5003adf55f1ff97a2a02c8b67a714d8` |
| Driver | `420bfc6bd3884c3abdd5ebeea8715d0804288540e5deb3f78f8bdb9040560771` |
| `admission.lani` | `c30d51aebbf46715db0094e7501658e9768d08461af61480db4bbd5b1ba72956` |
| `contracts.lani` | `2a4f878319ae3f833530cfea039aed09950464d9ca49d4119804a594be545dd2` |
| `types.lani` | `96c6cf090367889a197258471e5b6917616ef483d631ce99f2143a905c563632` |
