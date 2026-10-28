# Iterator fold sequence/state model

This fixture exercises all eight APIs in
[the fold contract](../../../../docs/library-iterator-fold-plan.md), followed
by direct front/back pulls and resumptions. Its Python reference uses finite
materialized deques and observable state, independently of the Lanius fold
bodies. Python and the binary transport are test infrastructure only.

## Finite coverage

The deterministic corpus has **10,696 cases and 37,104 commands**, using seed
`0xf01d20261029` and four source forms:

- A metered native slice iterator over a nonzero subview with untouched guards.
- A metered range mapped from `i32` to `i64`.
- A reverse adapter over that mapped range.
- A metered native slice mapped by `item * 2 + 1`.

Exhaustive short inputs cover empty and partially consumed cursors, all eight
APIs, zero/exact/oversized/`u64::MAX` quotas, and six callback error policies.
Additional schedules mix both ends, bounded chunks, direct pulls, reductions,
unbounded folds, explicit fresh seeds and returned-accumulator/error recovery.
There are 1,600 seeded mixed schedules over lengths zero through eight.

The oracle checks every result field, successful callback count, observed EOF,
the exact transferred error, source pull/success counters, mapper and callback
counts, and ordered argument/event traces. Metered metadata queries are recorded
and must remain absent. Thus a correct final accumulator alone cannot pass.

The callback is `accumulator * 17 + item + 1`. Every source has at most eight
items; the largest mapped item is 17, fresh seeds are at most three, and a
reduction starts at an item no larger than 17. Each callback consumes a distinct
item, including on error. A conservative bound allowing eight applications
from 17 is
`17 * 17^8 + 18 * (17^8 - 1) / 16 = 126435603617 < 2^37`.
Carry recovery cannot introduce another item or an application. The corpus
checks this bound; its largest generated successful accumulator is 1460228637.
All callback arithmetic therefore fits in `i64` without wrapping.

Command counts for `reduce`, `try_reduce`, `rfold`, `try_rfold`, `fold_up_to`,
`try_fold_up_to`, `rfold_up_to`, `try_rfold_up_to`, direct front and direct back
are respectively:
`967, 1038, 1040, 954, 7578, 3229, 7518, 3197, 5791, 5792`.

## Protocol and checks

Each input case starts with eight little-endian `u64` words:
`source_kind, length, consumed_front, consumed_back, failure_mode, target,
initial, command_count`. Each command adds `operation, quota, seed`; seed
`u64::MAX` reuses the current accumulator or the error's actual prior
accumulator. The model checks input size limits and keeps its source backing
unchanged.

Each command emits 16 words: operation, result tag, accumulator, folded count,
EOF flag, four error-identity fields, front/back success counts, front/back
poll counts, callback count, mapper count and metadata-query count. Each case
then emits its trace length and triples of event kind and two arguments.
The oracle rejects truncated, extra or mismatched output.

CPU reference controls pass, including rejection of a deliberately corrupted
error identity. The registered Rust gate is
`independent_fold_models_match_progress_errors_traces_and_mixed_end_resumption`
in `stdlib_iterator_fold_model_execution`. It uses the shared strict x86 ELF
checks and runs one batched native process through the oracle, with an
85-second outer timeout and a 70-second child timeout.

The first registered runtime run passed: **one test, 10,696 cases and 37,104
commands in 9.10 seconds**, with all four source forms and seed
`0xf01d20261029`. The log is
`target/stdlib-work/iterator-fold-model-first.log`; its oracle summary is
`iterator-folds cases=10696 commands=37104 sources=4 seed=0xf01d20261029`.
The accepted executable target is native Linux x86_64 output from the GPU
compiler. This finite run establishes the listed observations for this corpus;
it makes no direct GPU execution or formal verification claim.

Tested SHA-256 identities:

| Source | SHA-256 |
| --- | --- |
| `stdlib/core/iter.lani` | `1c9ab092a890bda7fa61bdc102034802309421df746df90370f2719e8d294627` |
| `model.lani` | `8d20079c35976ae868b9360252253ffa7b6fdf7f0d8c67d19c5c45ceca07cf14` |
| `oracle.py` | `36f1cc60629eaa7750005da5ed8a4f54f63cdab418b5f4e1003bba1b765f128e` |

```sh
python3 -B tests/fixtures/stdlib_foundation/iterator_folds/oracle.py controls
python3 -B tests/fixtures/stdlib_foundation/iterator_folds/oracle.py /path/to/model
```
