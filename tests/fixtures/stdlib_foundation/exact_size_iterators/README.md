# Exact-size iterator executable tests

`contracts.lani` exercises the public `ExactSizeIterator<T>` capability alongside
`Iterator<T>`. Its six bounded scenario functions check exact remaining counts
without polling the source, invoking a mapper, or reading item storage. The
instrumented generic source counts forward pulls, backward pulls and count
queries separately.

Coverage includes the full inclusive i32 range (2^32 items), virtual u64::MAX
sources, StepBy's first and subsequent phases, huge steps/skip offsets/take
quotas (including u64::MAX items at step two), live sequential consumption
through shared borrowed sources, fused
adapter completion, and Peekable's cached `Some(None)` and explicit recovery /
finish states, including closing an empty cache with unread upstream items.
Huge sources are queried or consumed only a few times; none is drained. A
deliberately inaccessible slice descriptor is used only for metadata queries
and cursor advances, never for an element read.

The fixture also checks nested Option/Result and wide compound values, zero-size
items, chunk/window counts including final short chunks and oversized windows,
and borrowed byte views with packed positive and fixed negative strides. No
allocation or automatic item destruction is part of these operations.

Five `negative_*.lani` fixtures require rejection at their marked
`require_exact` call: a forward-only source without the exact bound, an exact
implementation for the wrong item type, Filter, Chain, and Zip. Chain can
overflow a u64 cardinality, while Zip's two borrowed sources may alias and
consume one sequence jointly. Neither receives this capability.
A runtime control zips one five-item cursor with itself and obtains exactly two
pairs `(0,1)` and `(2,3)`, then consumes the unpaired final item while reaching
EOF. Excluding exact-size counting preserves that existing traversal behavior.

## Collections and independent model

`collections.lani` checks counts through pulls, rejected early finish, explicit
remainder recovery and final cleanup for vector, deque, hash map/set, tree
map/set and min/max heap owners. It includes zero-size items and transferred
String owners. The driver matches every source allocation with its release by
full address and size and requires no live allocation to remain; no incidental
allocation count is fixed by the test.

`model.lani` and `oracle.py` compare values, remaining counts and source/mapper
effects over 18 finite composition modes. The independent Python reference
materializes sequences and counts by draining isolated copies rather than
reusing the library's count formulas. The accepted run covers 10,714 cases and
35,922 steps with seed `0xe5ac72026`.

## Executed acceptance

The registered driver is `tests/stdlib_exact_size_iterator_execution.rs`. It
compiles through the GPU compiler and executes the generated raw x86-64 output
on Linux. All four distinct gates passed across these two commands:

- `target/stdlib-work/exact-size-runtime-accepted.log`: the metadata contract,
  collection ownership and negative-capability gates passed in a command that
  took 11.82 seconds. The pure contract allocation trace was empty; the
  collection releases matched their allocations. All five negative fixtures
  reported `LNC0008` at their own `require_exact` call. This command also tried
  an older model fixture, which failed compilation with `LNC0075` because its
  `Encoded` type was private in a public interface; the command as a whole
  therefore failed.
- `target/stdlib-work/exact-size-model-visibility-fixed.log`: the isolated final
  model gate passed in 8.44 seconds with the case/step counts above after making
  that fixture type public. The other three gates were unchanged.

Accepted source SHA256 values:

| Source | SHA256 |
| --- | --- |
| `contracts.lani` | `43e59a04c59d87a35d282562ed3680d73ba636dab07e80fa95ba09d32b31516c` |
| `collections.lani` | `a6e0e74a06322efc9cf2a02932e589642b812d8a222bbaa0ee170ea1154d3a92` |
| `model.lani` | `719f6d7fad7c23ab5d0ee594196cc806424cec8d5b205161e0bc1553557121b5` |
| `oracle.py` | `9b437774a1152a67c224090e07d1fa083a11c5980dc04878f928b14dfcb40a9f` |
| `stdlib/core/iter.lani` | `be05d6c26acab3786e02ecce1bda1af2f446556a7d877ffd065f5eebd705355d` |

The model also exposed a narrow generic receiver-resolution dependency:
`source.next().is_some()` can report `LNC0027` when the receiver is generic.
The model uses an explicit `Option<T>` local with unchanged pull behavior.
A [minimal reduction and executed typed-local control](../../stdlib_compiler_state/chained_generic_option/README.md)
separate this compiler dependency from exact-size traits and generic item
storage. Correcting the fixture visibility required no production change.

These receipts establish the finite Linux x86-64 behavior exercised here. They
do not establish user-program GPU execution, other targets or formal proof.
