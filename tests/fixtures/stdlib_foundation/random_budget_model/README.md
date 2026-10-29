# Shared random draw-budget state model

This fixture independently models finite scripted source effects, shared draw
budgets, existing random samplers and complete byte backings across sequences.
Production remains Lanius; Python and binary framing are test infrastructure.
No generator, entropy source or cryptographic implementation is supplied here.

## Independent observations

Each case starts with one source, a DrawBudget and an independent copy of that
counter. Five adapter arrangements are selected per operation:

1. The original adapter using counter A.
2. A copied adapter sharing the original source and counter A references.
3. An adapter using copied counter B and the same source.
4. An outer B adapter wrapping the A adapter.
5. An outer A adapter wrapping the A adapter, spending A twice if it reaches
   the source, or spending its last remaining draw before the inner rejection.

The reference represents these arrangements as explicit ordered counter
routes. It observes both remaining counts, actual source attempts, consumed
script events, exact values/errors/Host payloads, fill/shuffle failure progress
and the complete backing after every operation. Source errors spend admitted
draws. Inner exhaustion can spend an outer draw without any source call.
Copied adapters share counters; copied budget values remain independent.

Scalar references use unbounded integer interval sizes and `2^64 mod bound`
admission, with no wrapped unsigned negation. Inclusive signed intervals are
modeled directly as mathematical signed ranges, including the full i64 range.
Unit-float expected encodings are constructed from integer bit lengths and
fields, without Python floating conversion. Fill uses independent little-endian
byte chunks; choose indexes materialized bytes; shuffle applies the specified
descending Fisher-Yates choices to a Python list. No PRNG recurrence is mirrored.

Each scripted event is either a full-width source word or one exact Error.
After the finite script, the provider returns NoProgress on each reached call,
leaving its event index at the script end. This distinguishes source calls from
consumed event count and bounds even u64::MAX-budget rejection schedules.
No helper/source call that fails to return is simulated as a timeout.

## Finite corpus

There are **7,130 distinct cases / 57,040 actions**, seed `0xb0d6e0261101`,
with eight actions per case. Case identities are excluded from deduplication.
Every scenario covers native descending and packed ascending byte backings.

| Operation | Actions |
| --- | ---: |
| Direct Source64 draw | 7,886 |
| below | 9,242 |
| inclusive_u64 | 7,420 |
| inclusive_i64 | 7,438 |
| boolean | 840 |
| unit_f32 | 814 |
| unit_f64 | 836 |
| fill | 7,714 |
| choose | 7,464 |
| shuffle | 7,386 |

Corpora cover bounds 0/1, powers of two, nonpowers and high full-width values;
threshold-minus-one/threshold/threshold-plus-one; unsigned/signed singleton,
full and invalid ranges; zero/one/MAX budgets; each source Error before or
after progress; exact byte-word fill boundaries; malformed/empty/singleton
Views; shared/nested adapter sequences; and 300 seeded mixed programs. Valid
nonempty backing spans are physically small. Logically invalid metadata is
rejected before access, and valid zero-length spans can use large starts.

CPU controls check the biased-fallback counterexample `below(3)` from source
word zero with a one-draw budget: it must fail DrawLimit after rejection,
never return zero. They also check success exactly at threshold and on the
last admitted draw, no-draw operations, shared/copied/nested counter behavior,
partial-fill bytes and progress, full-width decrement and signed Host payloads.
Eight deliberate corruptions of exhaustion, sampled value, delegated calls,
shared/independent counters, partial progress, guard bytes and Host bits fail.
These deterministic checks make no statistical uniformity claim.

## Protocol and acceptance

Each request has an eight-word header followed by at most sixteen two-word
source events and eight four-word actions. All words are little-endian u64;
signed fields retain their bit patterns. Every action emits 43 words: action,
adapter, result/error/value/progress, both remaining budgets, source call and
event counts, and all 32 backing bytes. Exact framing, values and effects are
checked, with complete case and seed diagnostics on mismatch.

The native gate passed on its first attempt: **1 registered test in 8.50s**,
reporting **7,130 cases / 57,040 actions / 2 byte layouts / 5 adapter
arrangements** at seed `0xb0d6e0261101`. The receipt is
`target/stdlib-work/random-budget-model-first.log`. Exact results, source
effects, remaining counters, failure progress and backing states execute
against the reference, beyond compilation. Operation counts above classify
the finite input corpus; the native summary reports cases/actions/layouts/
adapters rather than separate runtime coverage counters for every outcome.

The registered test is
`scripted_random_budget_sequences_match_values_draws_and_backing` in
`stdlib_random_budget_model_execution`. It checks executable ELF admission
and shared strict x86 jumps, then runs one batched native process with a
90-second outer timeout and 75-second child timeout. Accepted scope is finite
Linux x86_64 CPU output produced by the GPU compiler. Owned-record cleanup,
pure-phase host effects, extended distributions and the real sampling program
have separate gates. No GPU-device, wall-clock, thread-safety, adversarial-source
uniformity or formal verification guarantee is claimed.

Frozen tested identities (SHA256):

| Source | SHA256 |
| --- | --- |
| `stdlib/core/random.lani` | `7f1bf3857137cd610a23d69a3d6d3e0bdfb4df62d5d4e0fc160f811460cdf09b` |
| `model.lani` | `f6e0f1a18dc2af798e5e5d98c389616dd9aa30fc5553d7bb5c7c734137b85460` |
| `oracle.py` | `c748cf217144cc472e1a8eb0ad527d10826f91c7cd46d1a409f455d5dbd950a9` |

```sh
python3 -B tests/fixtures/stdlib_foundation/random_budget_model/oracle.py controls
cargo test --test stdlib_random_budget_model_execution scripted_random_budget_sequences_match_values_draws_and_backing -- --nocapture
```
