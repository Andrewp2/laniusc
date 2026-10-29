# Shared iterator comparison direct contracts

All four registered direct tests are accepted in two separate runtime commands:

| Receipt under `target/stdlib-work/` | Accepted scope | Time |
| --- | --- | --- |
| `iterator-comparison-admission-typed-retry.log` | One all-eight admission test and native process | 6.48s |
| `iterator-comparison-direct-first.log` | One five-scenario native contract test and two capability-bound tests containing eight marked rejections; admission filtered | 8.90s |

The broader direct command followed a separate 1.72s driver build. Root ran
compiler, Cargo and native commands; authors performed static review only.
Independent model, owner/guard/scale and application gates have separate
receipts.

The first admission attempt stopped before ELF/native execution with LNC0006
after 2.60s: the library constructed Pair fields from inline generic Option
unwrap calls. Production now extracts explicitly typed T/U locals before the
Pair construction; the admission fixture itself was unchanged.
The corrected admission passed on its next attempt, and all three remaining
direct gates passed on their first attempt. No fixture behavior changed during
these runs.

The admission executes all eight public consumers on real slice cursors.
Custom pair callbacks compare i32/u64 items, total comparison returns an actual
ordering, partial comparison returns Unordered at a NaN or custom decisive
pair, natural sortedness rejects a NaN adjacency, and a strict custom adjacency
relation rejects equal consecutive items. Counters and cursor fields check
that the decisive operands were consumed. Inputs remain unchanged.

`contracts.lani` has five finite scenario functions. One probe and shared event
log record every left/right pull, EOF observation, callback, back pull and count
query. All six pairwise APIs cover empty inputs, both prefix directions, equal
inputs and a decisive mismatch, with literal event lists and resumed suffixes.
The longer prefix-side item is consumed without a callback. Tests forbid a
count shortcut or extra final probe. Odd/even aliased cursors observe actual
sequential source state; mixed-end remainders and Rev/Map composition exercise
the existing protocols. Descending element policy preserves structural prefix
ordering.

Sortedness checks empty/singleton identities, duplicate values, actual
(previous,current) adjacency, first rejected adjacency, strict and descending
relations, and resumption after the consumed violating item. IEEE f32/f64
checks exercise NaN inequality, explicit Unordered and singleton NaN
sortedness. Further f64 cases cover decisive order before a later NaN,
unmatched NaN prefix items, signed-zero equality and infinities. Original
floating-point bits are preserved. Heterogeneous
record/key callbacks inspect full-width fields and nested Option/Result/array
payloads without any natural comparison implementations. An Option-valued
source delivers Some(None) as an item before its true EOF.

Eight small negative fixtures require LNC0008 at a marked public call. Five
check missing/mismatched source items and natural PartialEq/Ord/PartialOrd
bounds; three check wrong equality/partial outputs and reversed heterogeneous
Comparator arguments. Positive runtime controls exercise the correct callback
shapes. These are capability tests, not arbitrary compile-failure acceptance.

The harness requires x86_64 ELF, shared jump checks, successful native exit,
empty output and a full syscall trace containing process entry/exit only.
Both accepted native processes satisfied these checks, with no allocation,
release or host service calls.

Accepted source hashes:

| Source | SHA-256 |
| --- | --- |
| `admission.lani` | `d5f8c94d55192aa1ecc0b0228fbe28413882716529948187ba6e67d455e2af64` |
| `contracts.lani` | `b870037b21249318696e54033c55fc375a09d91be8bc5020fc88d593f967d37b` |
| `negative_missing_iterator.lani` | `45150dc30c12c0a5e1a3fb44764bc3221961a9fd97c1402254e9af73fc332398` |
| `negative_wrong_right_item.lani` | `468a5669161afc4ebbeff4b12f019c059aac876bacf6e933c8c0b3b49c55c3f5` |
| `negative_missing_partial_eq.lani` | `fefa1f6a3e36f0abf12c529d3f787b4ba15cc0657fb3988277380ff27ef6761f` |
| `negative_missing_ord.lani` | `fe0624718c1fe2d9b2dd74ef8dd2137701f1c2c3f344afcc8706148777c1eb47` |
| `negative_missing_partial_ord.lani` | `51578a7f0cd7ec798db1623a39e60ef780022843d925d13b046da187a820e215` |
| `negative_wrong_equality_output.lani` | `d091e46950d8ec2dcd69274092ae63da3b826b6e60066ad607c269206e30f968` |
| `negative_reversed_comparator.lani` | `47ca9c45c52579ff023c590b849cfbdaf6fd9922375b0778710c85ec81876635` |
| `negative_wrong_partial_output.lani` | `1363709dd3351b269a03c9c3405e4e315b67618fa91f7cc2b0a846811e1cea04` |
| `stdlib/core/iter.lani` | `0efff466fc31a96918d9cd55ad69d4073586803608b35bc1d5a7d743a4ba6211` |

```text
cargo test --test stdlib_iterator_comparison_execution iterator_comparison_all_eight_consumers_execute_native_admission -- --exact
cargo test --test stdlib_iterator_comparison_execution iterator_comparison_executes_exact_effects_prefixes_aliases_partial_orders_and_resumption -- --exact
cargo test --test stdlib_iterator_comparison_execution iterator_comparison_requires_matching_sources_and_natural_comparison_traits -- --exact
cargo test --test stdlib_iterator_comparison_execution iterator_comparison_requires_exact_pair_callback_items_and_outputs -- --exact
```

The accepted target is native Linux x86_64 CPU execution of GPU-compiler
output. GPU device execution, other targets and formal correctness need
separate evidence.
