# Iterator sequence comparison model

This fixture checks all eight `core::iter` sequence-comparison consumers through
real canonical iterators. Production remains Lanius; the Python reference and
binary transport are test infrastructure only.

## Independent decisions and effects

For independent sources, the oracle materializes the complete remaining lists,
computes all corresponding relations and selects their first decisive index.
That prefix and a length/EOF witness determine the expected result, exact pulls
and callback pairs. Sortedness computes every adjacent relation first and finds
the first rejected adjacency. No production traversal loop, iterator engine or
callback implementation is reproduced in Python.

Shared sources use alternating positions in one materialized sequence. The
corpus distinguishes two heterogeneous maps sharing one actual upstream cursor
from selected natural operations borrowing the exact same metered cursor twice.
Three equal items therefore produce one equal pair followed by Some/None, not
reflexive equality. Structural shorter-prefix ordering remains independent of
ascending/descending element policies.

Every result includes the exact ordered Some/None pull trace and applicable
callback operand IDs, full-width keys, raw bit payloads and answers. All custom
callbacks are observed. Natural equality and partial comparison/sortedness log
their existing scalar-trait dispatch. Natural total comparison checks the
result, pulls and remaining data without imposing an internal `Ord.lt` call
strategy on existing `ordering::Natural`.

After observing the consumer trace, the fixture disables instrumentation and
emits every remaining item, left then right. For shared sources, draining left
naturally leaves right empty. Complete compound values are checked: IDs, key,
raw bits, high-bit markers, Option<bool> states or heterogeneous two-word array
payloads. Original input tables and both complete byte backings, including all
guards, must remain unchanged.

## Sources, policies and finite corpus

Canonical slice Iter plus Map produces compound operands from nonzero-start
byte Views. Both actual byte representations execute: native negative stride
and packed stride +1. No negative stride magnitude or alternate record ABI is
assumed. Small Rev and Take source families and front/back pre-consumed slice
cursors supplement the ordinary sources. Deliberately shared sources borrow the
same adapter/cursor state; independent cursors over the same spelling are not
mistaken for aliases.

The corpus has **11,502 distinct cases**, seed `0xc0a0261104`, with at most
12 elements per physical input:

| API | Cases |
| --- | ---: |
| eq | 1,806 |
| eq_by | 1,734 |
| cmp | 1,386 |
| cmp_by | 1,348 |
| partial_cmp | 1,812 |
| partial_cmp_by | 1,668 |
| is_sorted | 754 |
| is_sorted_by | 994 |

All 225 pairs of binary-alphabet sequences of length 0..3 run through every
pairwise API and both layouts. A ternary-alphabet length 0..3 corpus distributes
additional pairs across the six pairwise APIs. Sortedness checks all 40 ternary
sequences under ascending, descending and equivalence-class policies, with
strict/non-strict custom relations. Prefix changes, first/late decisions,
duplicates, full i64 limits, empty/singleton, partially consumed cursors and
seeded length 0..12 cases supplement those systematic inputs.

There are 10,564 plain, 480 Rev and 458 Take cases. Alias cases comprise 738
shared-upstream cases and 282 same-meter cases; 10,482 cases use independent
sources. These are corpus distributions, not independently traced production
coverage counters. Source-only no-allocation and large-scale work gates are
separate.

Partial IEEE expectations classify raw f64 integer encodings and order their
non-NaN ranks without constructing Python floats. Lanius comparison policies use
actual f64 comparisons. Cases include signed zeros, both subnormal signs,
normal boundaries, infinities and quiet/signaling NaN encodings, preserving raw
payload bits in observed values. Unordered stops a pairwise comparison;
singleton NaN is vacuously sorted, while an unordered adjacent pair is rejected.
These are compound test-item trait policies; direct native-f64 capability cases
belong to the separate contracts gate. Total cmp never receives the partial
NaN policy.

Literal CPU controls pin decisive pairs, exact equal-input EOF polls, both
prefix length outcomes, descending structural prefix order, odd shared aliases,
strict duplicate rejection, empty/singleton and Unordered/signed-zero behavior.
Eight deliberately corrupted serialized outputs test the verifier's rejection
of altered result, side/presence, callback identity, remainder framing, backing,
unordered conversion and trace length. They are verifier controls, not
production mutations or a formal proof.

## Protocol and acceptance

Each request has fourteen little-endian u64 header words selecting API, layout,
policy, strictness, alias/source form, both lengths, front/back preparation and
Take bounds. Key/raw-bit pairs follow. Signed values retain all their bits.
Responses contain result and event count, eight words per event, tagged
remaining compound values, complete byte backings and all key/bit table cells.
The oracle checks exact framing/full values with seed, case and full-input
failure diagnostics.

The registered native test **passed**: one test in **9.25 seconds**, with all
**11,502 cases / eight operations / two layouts**, seed `0xc0a0261104`.
The receipt is `target/stdlib-work/iterator-comparison-model-spaced-retry.log`
(incremental driver build 0.21 seconds). The registered test is
`independent_iterator_comparison_models_match_decisions_effects_aliases_and_remainders`
in `stdlib_iterator_comparison_model_execution`. It checks executable ELF
admission and shared strict x86 jumps, then runs one batched native process with
a 75-second child timeout and a 90-second outer timeout. Accepted scope is finite
native Linux x86_64 CPU output produced by the GPU compiler. This model makes no
GPU-device, other-target, automatic ownership, unbounded-termination or formal
verification claim.

The first attempt stopped **before native execution**, in 4.29 seconds:
`target/stdlib-work/iterator-comparison-model-first.log` reported LNC0021 at the
first compound Pair callback header. Static reduction found contiguous `>=`
tokens in twenty generic-type/assignment boundaries. Separating those boundaries
as `> =` admitted the unchanged records, nested Pair headers, callbacks and all
assertions. The parser's diagnostic fallback had labeled an unrelated nested
trait header after the syntax failure. The first producer identity was
`fca3eee7ce5569f676913451dba043bd8569ac974a5a57b75adc507d87a18562`.
No nested-Pair restriction, library repair or compiler dependency follows from
that invalid assignment spelling. Production and the independent oracle stayed
unchanged, and no additional syntax probes were executed or retained.

Tested SHA256 identities:

| Source | SHA256 |
| --- | --- |
| `stdlib/core/iter.lani` | `0efff466fc31a96918d9cd55ad69d4073586803608b35bc1d5a7d743a4ba6211` |
| `stdlib/core/ordering.lani` | `b09a297dcc64fb3440ae802d691fbdb5c317f521dc886b2d8cacb493124e67ac` |
| `model.lani` | `20916e2a5142ad87d7f76515b31969e588f6b53efe2fbe6259061c5557b79945` |
| `oracle.py` | `d3f9fecb4fd4f561700b59d5e94decc3e0312ef6af34201813eed434834c10f1` |

```sh
python3 -B tests/fixtures/stdlib_foundation/iterator_comparison_model/oracle.py controls
cargo test --test stdlib_iterator_comparison_model_execution independent_iterator_comparison_models_match_decisions_effects_aliases_and_remainders -- --nocapture
```
