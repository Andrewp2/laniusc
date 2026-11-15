# Call inference rounds

The type checker infers call types in rounds. `resident.rs` records a batch of rounds. Each round runs the passes of `type_checker/calls`, `methods`, `dependencies`, `type/instances`, `modules` and `substitution` in a fixed order. `call_inference_state[1]` counts the facts a round changed. The host repeats rounds until a round changes nothing, then records one final round with `call_inference_state[0] = 0`.

On the settings app the rounds change these numbers of facts:

| Round | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 (final) |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Changes | 116,491 | 18,454 | ~5,230 | ~1,620 | ~690 | ~240 | ~116 | 51 | 20 | 8 | 0 |

Before this change each round cost about 1.7 to 2.0 ms of GPU time, independent of the number of changes.

## Activity per function

`shaders/type_checker/calls/inference_activity.slang` decides which items a round recomputes.

- `call_inference_round[0]` is the round number. It is 0 outside the rounds and 1 in the first round. `03z_begin_inference_round` increments it and clears the change count.
- `call_inference_round[1]` is the last round that changed a fact with no owning function.
- `call_inference_fn_stamp[g]` is the last round that changed a fact of function `g`. `g` is `enclosing_fn[token]`, the function's HIR row plus 1. Row 0 means outside every function.
- Every site that adds to `call_inference_state[1]` also calls `inference_note_item_change()`. Sites that leave an item unfinished (BUSY outcomes) also stamp it.

A masked pass recomputes an item in round `r` when one of these holds:

1. `r <= 1`, or the pass runs outside the rounds.
2. `call_inference_round[1] >= r - 1`.
3. The item's function has `call_inference_fn_stamp[g] >= r - 1`.

An item outside every function is recomputed only under rules 1 and 2. An item without a token is recomputed every round.

## Why the result is the same

The argument has three parts.

1. A round reads only facts that earlier passes wrote. Facts of one function are computed from facts of that function and from global facts. A cross-function fact, such as a callee's signature or an imported field, is either global or is written by a change that stamps the global word.
2. Suppose function `g` has no counted change in round `r - 1`, and no global change happened in round `r - 1`. Then round `r` starts with the same facts for `g` as round `r - 1` did. Each masked pass would compute the same values and write them over themselves. Skipping those items leaves every buffer unchanged.
3. Passes that stay unmasked must not write a location that a masked pass writes later in the same round. Otherwise a skipped item would leave the unmasked pass's value in place. A script over the reflected writer table checked this for every pass in the round.

The per-round change counts vary by a few between runs even without masking, because some passes count races between lanes. Settings converges in the same 11 rounds with and without masking. The final round runs unmasked with `call_inference_round[0] = 0`, so it writes every final fact.

## Passes that stay unmasked

These passes work on global rows or on compacted rows with no stable owner:

- claim scan and emit (`03a1`), claim index clear and build (`03a2`, `03a3`)
- bound clear and local collection (`03l0`, `03l2`), `03l1`, explicit admission `03a0b`
- required generics mark and scan, constant claim index and environment
- aggregate scans and conditions, the type index `02c`
- substitution expansion `04` to `06`, and imported fields `07`. Progress in these stamps the global word.
- semantic and artifact passes, `match/01`, method resolution, and `03j` (final round only)

## Measurement

Settings app, minimum per pass over at least 3 timestamp traces:

| | Base 26a151c3f | Activity masking |
|---|---|---|
| Inference GPU time | 19,370 µs | 16,746 µs |
| Inference dispatches | 827 | 836 |
| Rounds | 11 | 11 |
| Settings executable | | byte-identical |

The 9 extra dispatches are the one-lane round start, one per round, less the clear it replaces.

A round in which every function is inactive still costs about 0.9 to 1.0 ms. The unmasked passes take most of that time: claim emit about 90 µs, local collection 25 µs, call roots 25 µs, imported fields 20 µs, type indexes about 18 µs each. Each masked pass still launches a lane per row and costs 10 to 20 µs.

Late rounds stay expensive because a few large functions, such as the float tables, remain active. Most masked lanes in an active function have nothing to change. Finer granularity, or compacting the active items and dispatching indirectly, would reduce this further.
