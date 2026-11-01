# Stable-sort independent ordering model

This fixture executes `alloc::slice::sort` and `sort_by` and compares complete
outputs with host stable key ordering. Python and binary framing are test
infrastructure only. No merge passes, workspace contents or production sorting
engine are reproduced in the reference.

## Independent stable whole-value expectations

Host `sorted` supplies the exact selected output sequence, including original
representative order within every equivalent key class. Every record has a
unique original ordinal and independently derived payload. Stable ties are
therefore observable even when distinct primary keys compare Equal under a
coarse context. Entire output is compared exactly, rather than accepting any
sorted permutation.

The compound type is `Row<Payload>`. Payloads include high-bit u64 markers,
two-word arrays, all three Option<bool> states and both Result<u64,[i64;2]>
variants. Keys, secondary keys, IDs and every payload field are preserved.
Every action checks all 72 backing elements, including every value outside the
selected View. Bytes form a second family with ordinary byte ordering.

Natural Ord compares primary key only. Custom contexts select primary ascending,
primary descending, low-two-bit equivalence classes, secondary ascending or
secondary descending. No source ordinal tie-breaker is used by the comparator.
Multi-action cases perform successive stable sorts, and each host sort starts
from the previous exact expected output. This checks that stable secondary/key
composition preserves the order established by earlier passes.

Valid comparisons are not matched to a particular merge trace. The fixture
checks no callback on invalid or length 0/1 input, and the documented finite
comparison ceiling on nontrivial inputs. Custom helper counts are at most
n*ceil(log2(n)); natural record Ord.lt counts allow twice that ceiling. Natural
byte Ord does not use the fixture's callback counter. Allocation counts and
reached allocation failures have separate focused resource gates.

## Layout and admission

Both actual byte representations execute: native negative stride and packed
stride +1. Generic records use native arrays and independently prepared canonical
typed storage, both with descending descriptors. No positive or packed record
ABI is invented. Selected Views are literal start/length descriptors; there are
no `view_range`/`subview` convention assumptions.

Metadata uses arbitrary-precision host arithmetic. Negative start/length and
start+length overflow expect Bounds before callbacks or mutation. Admitted
length zero and one return that length even for a non-backed logical start,
without accessing its payload. No nontrivial physically unbacked accepted View
is requested.

The producer reports `size_of<T>()`; the oracle binds a consistent actual size
per family across cases/layouts and computes the byte-cap admission independently
as length*size > i32MAX. Record capacity-overflow requests select one entry
beyond the dynamically derived existing Vec cap. Additional literal i32MAX
length and metadata/capacity precedence cases reject before allocation/backing
access. No record size or staging cap is hardcoded into native expectations.
Synthetic CPU verifier records use an explicitly synthetic size and never claim
a native allocation or an actual comparison count.

## Finite corpus and controls

There are **5,946 distinct cases / 9,942 sort actions**, seed
`0x57ab1e0261104`: 1,528 byte cases and 4,418 generic-record cases, each across
the two backing forms. The corpus includes all ternary-key sequences of length
0..5 for records and length 0..4 for bytes under the selected natural/custom
profiles. It adds interior Views, duplicate-heavy/all-Equal, ascending/reverse,
sawtooth and organ-pipe inputs; irregular lengths 6,7,8,9,15,16,17,23,31,32,33,
47,63,64,65; full i64 limits; exact/trivial/invalid metadata; six dynamic
capacity-selector cases and seeded partial subviews. Maximum physical payload
length is **65**, with the larger resource/scale domain covered elsewhere.

Literal CPU controls pin stable ID order, equivalent-class ties, successive
secondary/primary stable sorts, trivial metadata behavior and capacity versus
Bounds precedence. Eight deliberately corrupted serialized outputs test the
verifier's rejection of status/count/callback/layout/guard/payload defects and
swapping complete equal-key rows. The latter corruption is still sorted and a
whole-record permutation, but unstable. These are verifier controls, not
production mutants or a formal proof. Corpus counts are reference distributions,
not separately traced production coverage counters.

## Protocol and acceptance

Each request has eight little-endian u64 header words: family, layout, physical
payload count, View start/length, dynamic-capacity selector, action count and
record identity seed. Primary/secondary pairs and natural/custom policy actions
follow. Signed words preserve all their bits. Each response contains typed
result, before/after callback count, actual element size/stride and the entire
backing after the action. The oracle checks exact framing and every field with
full case/action/seed diagnostics.

The registered native test **passed on its first run**: one test in
**8.43 seconds**, with **5,946 cases / 9,942 actions / two families / two backing
forms**, seed `0x57ab1e0261104`. The receipt is
`target/stdlib-work/stable-sort-model-first.log` (Rust driver build 1.70 seconds).
The registered test is
`independent_stable_sort_models_match_tie_order_records_guards_and_admission`
in `stdlib_stable_sort_model_execution`. It checks executable ELF admission and
shared strict x86 jumps, then runs one batched native process with a 75-second
child timeout and 90-second outer timeout. Accepted scope is finite native
Linux x86_64 CPU output produced by the GPU compiler. Resource faults, automatic
ownership, large-scale complexity, GPU-device execution, other targets and
formal verification require separate evidence.

Producer, oracle and production required no amendments for this acceptance.
The CPU literal and serialized-output corruption controls above remain separate
from the native case/action counts. The Rust driver identity is omitted because
root may format that file after the gates.

Tested SHA256 identities:

| Source | SHA256 |
| --- | --- |
| `stdlib/alloc/slice.lani` | `e56129df41d435c226a11612d67b52cd9364e25d35d295e90f592376009aa667` |
| `stdlib/core/ordering.lani` | `b09a297dcc64fb3440ae802d691fbdb5c317f521dc886b2d8cacb493124e67ac` |
| `stdlib/alloc/vec.lani` | `2bd5cd02a445360696c981255253940caf7ba9ec85556f859e1b13df437e1e49` |
| `model.lani` | `7c9be6d8508561589508d38bb15bf9645fd91a40913d1792edf83c6140e2956a` |
| `oracle.py` | `b4a229a72a6fc2a5ed52307f0f32de2370d7891bbda04af1cf622bd7825d585f` |

```sh
python3 -B tests/fixtures/stdlib_foundation/stable_sort_model/oracle.py controls
cargo test --test stdlib_stable_sort_model_execution independent_stable_sort_models_match_tie_order_records_guards_and_admission -- --nocapture
```
