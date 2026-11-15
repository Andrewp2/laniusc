# Call inference rounds

The type checker infers call types in rounds. `resident.rs` records a batch of rounds. Each round runs the passes of `type_checker/calls`, `methods`, `dependencies`, `type/instances`, `modules` and `substitution` in a fixed order. `call_inference_state[1]` counts the facts a round changed. The host repeats rounds until a round changes nothing, then records one final round with `call_inference_state[0] = 0`.

On the settings app the rounds change these numbers of facts:

| Round | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 (final) |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Changes | 116,491 | 18,454 | ~5,230 | ~1,620 | ~690 | ~240 | ~116 | 51 | 20 | 8 | 0 |

Before this change each round cost about 1.7 to 2.0 ms of GPU time, independent of the number of changes.

## Activity per function

`shaders/type_checker/calls/inference_activity.slang` decides which items a round recomputes.

- `call_inference_round[0]` is the round number. It is 0 outside the rounds and 1 in the first round. Before each round the host records a clear of the change count and a copy of the round's number from the table `call_inference_round_numbers`. Neither is a dispatch.
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

The round start was first a one-lane kernel. It is now a buffer clear and a buffer copy, so it adds no dispatch. The bound-table clear (`03l0`) zeroed only four counts and is now a buffer clear as well. Settings at c44f3c2dc, minimum per pass over 3 timestamp traces:

| | c44f3c2dc | Round start and bound clear as buffer operations |
|---|---|---|
| Inference GPU time | 17,588 µs | 17,100 µs |
| Inference dispatches | 836 | 816 |
| Dispatches per round | 76 | 74 |
| Build dispatches | 5,336 | 5,315 |

## How many rounds run

The host does not read back a change count per round on a warm build. It records as many rounds as the last two builds of the same workspace shape converged in, and the final pass stands for the round that changes nothing (`call_inference_unwaited_rounds` in `resident.rs`). Settings converges in 10 rounds plus the final pass. Round 10 is the last round that changes a fact, with 1 to 8 changes. So no round runs after convergence, and a GPU "converged" flag would not remove any round.

## What a dispatch costs

Measured untraced on the settings build: a block of 760 dispatches was recorded after the rounds and submitted alone, and the host timed the GPU from submit to idle. Minimum of 10 builds:

| Block of 760 dispatches | GPU time | Per dispatch |
|---|---|---|
| Empty submission | 0.031 ms | |
| Zero-sized indirect dispatches | 0.194 ms | 0.21 µs |
| One-workgroup direct dispatches of a trivial kernel | 0.825 ms | 1.0 µs |
| 10 masked rounds after convergence | 5.90 ms | 7.7 µs |

The timestamp traces add about 4 µs to every dispatch, so their 5 to 12 µs floor is not the real cost. A converged round costs about 0.59 ms of GPU time, and most of it is the work of the passes, not the dispatches. Recording costs the host about 8 µs per dispatch: the batch of rounds took 6.95 ms to record for 836 dispatches, and the GPU waits for that recording.

## Compaction of active items (tried, not kept)

Each round's active functions were listed in one workgroup at the round start. The heaviest HIR passes (`03d`, `03e`, `03f`, `03g`, `03k1`) were dispatched over those functions' rows only, through a lane-to-row map. The result matched, but inference GPU time fell only from 17,588 to 17,198 µs, and the one-workgroup round start cost 22 µs more per round. A late round recomputes a few large functions, and their items do long serial work: receiver binding still took 77 µs in round 10. The inactive lanes the masks already skip were cheap. The patch is kept in the evidence directory (`compaction-experiment.patch`) and is not part of the compiler.

## What remains

- Finer activity than whole functions: an item whose inputs did not change in the last round need not recompute. In round 10 only 8 facts change, but every item of the active functions recomputes.
- Fusing passes: each removed dispatch saves about 8 µs of host recording and 1 µs of GPU time. Most passes in a round write the shared interner tables, so a fused group needs an argument that it behaves like the passes run in order.
