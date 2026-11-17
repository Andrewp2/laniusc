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

## Claim emission

`03a1` writes each argument's claims into spans that the claim scan places by prefix over all arguments. A change in one function can move the spans of arguments in other functions. So `03a1` skips an argument only when its function is inactive and both spans (generic and constant, start and count) equal the spans it last emitted at, kept in `call_claim_emitted_span`. No other pass writes the claim rows. The other locations `03a1` writes (`call_return_type`, `call_result_instance`, `semantic_argument_mode_by_hir`) are written in the round only by masked passes of the same function, so a skipped argument keeps the values a recomputation would write again. On settings `03a1` costs about 45 µs in the late rounds instead of 89 µs. The rest is lanes of active functions.

## Passes that stay unmasked

These passes work on global rows or on compacted rows with no stable owner:

- the claim scan, claim index clear and build (`03a2`, `03a3`)
- bound clear and local collection (`03l0`, `03l2`), `03l1`, explicit admission `03a0b`
- constant claim index and environment
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

## Activity finer than whole functions (measured, not built)

Two rounds were added after convergence (a temporary `LANIUS_EXTRA_ROUNDS` setting, not kept). They change nothing, so their cost is the floor of a fully masked round: 927 µs traced. Rounds 3 to 10 cost 3,677 µs above that floor in total. The largest parts:

| Pass | Above the floor, rounds 3 to 10 (µs) | Round 10 | Floor |
|---|---|---|---|
| `03d` receiver binding | 644 | 77 | 9 |
| `03l3` bound inference | 409 | 18 | 11 |
| `03a4b` contextual result requests | 402 | 66 | 23 |
| `03a1` claim emission (before skipping) | 343 | 45 | 9 |
| `03a` argument matching | 314 | 44 | 11 |
| `methods/07` resolve table | 296 | 41 | 11 |
| `substitution/02` call environments | 238 | 33 | 13 |

Two diagnostics masked a pass to the items whose own token had a counted change in the previous round. Neither was kept.

- Receiver binding with this mask built settings byte-identically, and still cost 72 µs in round 10. Its late cost is in calls that themselves change or stay BUSY. Activity per item would not lower it.
- Argument matching and contextual result requests with this mask failed to compile settings (LNC0006). Their items read facts that other items of the function change, so a mask per item needs the dependency edges between items.

A mask per item that keeps the fixed point needs, for each masked pass, the set of items whose facts an item reads: its argument and receiver expressions, the expression that gives it a context type, and the declarations of the locals it reads. Each change would stamp the changed item's readers through an adjacency built once per job. Every masked pass's reads would then have to be checked against that adjacency, in the same way as the writer table check for the masks per function.

## Why settings needs 10 rounds (measured 2026-11-17)

A temporary diagnostic (not kept; `call-inference-round-diag.patch` in the evidence directory) copied `call_inference_state[1]` after every operation of a round, in waited rounds. Counted changes per round on settings, by the pass that counted them:

| Round | Method selection | `03k` argument contexts | `03e` return types | `03k1` literal contexts | `03g` expression types | `03f` return bindings | Other | Total |
|---|---|---|---|---|---|---|---|---|
| 1 | 0 | 18,321 | 8,198 | 5,599 | 81,446 | 2,658 | 269 | 116,491 |
| 2 | 819 | 149 | 907 | 1,241 | 14,745 | 586 | 10 | 18,457 |
| 3 | 829 | 377 | 845 | 174 | 2,781 | 204 | 8 | 5,218 |
| 4 | 267 | 108 | 333 | 24 | 770 | 122 | 3 | 1,627 |
| 5 | 65 | 40 | 98 | 7 | 425 | 63 | 0 | 698 |
| 6 | 20 | 6 | 33 | 2 | 147 | 26 | 5 | 239 |
| 7 | 19 | 5 | 20 | 2 | 66 | 5 | 1 | 118 |
| 8 | 11 | 3 | 14 | 0 | 16 | 8 | 0 | 52 |
| 9 | 1 | 0 | 1 | 0 | 24 | 0 | 0 | 26 |
| 10 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 1 |
| 11 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |

"Other" is match payloads, array literal elements, bound inference and the argument-context type index. No other pass counts a change after round 1.

The diagnostic also logged the token of every change from round 3 on. The late changes are chains of statements in which each local's type comes from a method or generic call on the previous local:

```
let recorded = ...;          // round 7
if (recorded.is_err()) {     // round 8
let e = recorded.unwrap_err();
return Err(Error::Gpu(e));   // round 9
```

and nested method calls, such as `let target=field(self.target.unwrap().field())?; let point=field(target.insertion())?; let bounds=covered(point.clip); ... bounds.unwrap()`, which reach round 10. One step of such a chain needs method selection (start of the round), then argument matching and claims, receiver and call environments, return materialization, expression projection `03g` and local bindings `03f` (end of the round). The step's result is read by the next step's method selection, so a chain advances one call per round. The passes of the step span the whole round: an ordering of the round's 64 passes by their reads and writes (shared intern tables left out) has 40 dependent layers, and the chain uses nearly all of them. Running a subset of the round more often, or a jump over several steps, would need the same passes again, so the round count was not reduced.

## Passes taken out of the round (2026-11-17)

- The required-generic mark and its scan (three dispatches) ran in every round. Only the required-binding validation after closure reads them, so they now run once at the start of `record_required`.
- The candidate reset (`06c`) and the local table lookup (`methods/07`) ran as two dispatches over the same token grid in every method transaction (direct, eight lookup sweeps, every round). The reset writes only its token's record and ownership and its call's context masks, and the lookup reads neither the masks nor another token's record. `07` now resets first in the same lane.

Settings, 618f4be1b against the two changes, sum of the per-pass minimum over 6 traced builds each:

| | 618f4be1b | After |
|---|---|---|
| Type-check dispatches | 1,425 | 1,375 |
| Build dispatches | 4,257 | 4,207 |
| Type-check GPU time (traced) | 28.22 ms | 27.53 ms |
| Rounds | 10 + final pass | 10 + final pass |
| Settings executable | `115a4d52a2ae77e0` | byte-identical |

## What remains

- Activity per item, as above.
- Fusing passes: each removed dispatch saves about 8 µs of host recording and 1 µs of GPU time. Most passes in a round write the shared interner tables, so a fused group needs an argument that it behaves like the passes run in order.
