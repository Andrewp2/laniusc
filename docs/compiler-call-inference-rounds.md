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
- dependency bound collection `03l1`, explicit admission `03a0b` (the bound clear and the local collection `03l2` run once before the rounds)
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

## Where an idle dispatch's time goes (2026-11-17)

A late round of the traced settings build costs 1.0 to 1.3 ms for 58 dispatches, 16 to 22 µs each, while a dispatch that does nothing costs a few µs. Untimed encoder timestamps around whole rounds (a temporary diagnostic, `idle-dispatch-diag.patch` in the evidence directory) and two forced variants of extra rounds after convergence separate the parts:

| Converged round, untraced | µs per round | Per dispatch |
|---|---|---|
| Every pass at zero workgroups (indirect arguments zeroed) | about 40 | 0.7 |
| Every pass at one workgroup | 180 to 250 | 3 to 4 |
| Every pass at its normal grid | 380 to 460 minimum | 6 to 7 |
| The 28 masked passes at zero workgroups, the rest normal | 275 minimum | |

- The timestamp traces add about 4 µs to every dispatch. That is most of the gap between a traced 16 µs and an untraced idle dispatch.
- Barriers, bind groups and pipeline switches cost under 1 µs per dispatch. The round's passes bind 69 to 126 buffers each, and nearly all are indirect over the HIR grid (828 workgroups) or the token grid (1,773). Removing per-dispatch overhead (read-only declarations, shared layouts, pass order) cannot save more than that 0.7 µs.
- A one-workgroup dispatch of a real round kernel costs 2 to 3 µs more than a trivial one. That is the cost of launching a large kernel and draining it before the next dependent one.
- The rest of an idle round is the passes' own grids. Masked lanes that test their function's stamp and return cost at most about 0.1 ms per round together, so a compacted list of active rows (option b of the task) would save at most that, minus the dispatches that build the list. The earlier compaction experiment above measured the same. Most of the idle cost is in unmasked passes that visit every HIR row or every live type row and do real work there (interning, atomics) in every round.
- A late round's real changes add to this: in round 10, receiver binding (75 µs traced), contextual result requests (60), claim emission and argument matching (45 each) and the resolve table (40) spend their time on the few changed functions' items, as described under "Activity finer than whole functions".

Idle cost per pass, traced, in a round after convergence (minimum of 5 builds, fef2db596): bound collection 31.7 µs, call-root expansion 26.6, the two type indexes (`02c`) 19.5 each, method collection 18.4, imported fields 18.4, explicit admission 18.4, field expectations 17.4, call environments 16.4. The floor of a traced dispatch is 5 to 6 µs.

Two of these were changed:

- **Bound collection.** `03l2` collected the unit's trait implementations and the bounds of its generic functions in every round, after a clear of the tables' counts. Those are declaration facts. The clear and the collection now run once before the rounds (and before the final pass of a job without rounds), and a copy keeps the counts (`bound_inference_local_counts`). A unit with dependency interfaces restores the counts at the start of each round and collects the resident pages' rows again on top of the local ones. The table order changes from dependency rows first to local rows first. `03l3` does not depend on it: the rows of one pass were already appended in atomic order.
- **Call-root expansion.** `substitution/04` pushes every accepted call result and argument context in every round. The push is once per job (a mark bit per canonical ID), but each push was an atomic OR on the mark bitmap. `ct_expand_push` now reads the mark first and returns when it is set. Marks are only set during a job, so a stale read falls through to the atomic.

Settings at ab296f5f6 with the canonical re-arm change, traced, sum of the per-pass minimum over the last 3 builds:

| | Before | Bound collection once | Expand mark check |
|---|---|---|---|
| Call-root expansion per round | 23 to 24 µs | 23 to 24 µs | 15 to 16 µs |
| Round totals, rounds 1 to 10 plus final pass | 15,977 µs | 15,783 µs | 15,503 µs |
| Dispatches per round | 58 | 57 | 57 |
| Type-check GPU time | 29.05 ms | 28.56 ms | 28.11 ms |
| Type-check dispatches | 1,431 | 1,421 | 1,421 |
| Settings executable | `115a4d52a2ae77e0` | byte-identical | byte-identical |

Tried and not kept: skipping complete imported applications inside the rounds in `07_project_imported_fields` left its 17 µs unchanged. Its cost is the visit of every live type row (one per token), not the work on the imported ones. The two `02c` indexes have the same shape: they visit every live row and skip the ones already indexed. A list of the rows that can hold a type would serve all three.

## Bound inference and call clears (2026-11-17, second pass)

Settings at ab03bbe44, traced, sum of the per-pass minimum over the last 3 builds.

- **Owner filter for bound inference.** `03l3` scanned every predicate row for each generic call's callee (`next_predicate`), in every round, to find out that most callees have no bounds. The collectors (`03l1`, `03l2`) now also set one bit per hash of the row's owner in a 256-word filter after the three counts (`BOUND_OWNER_FILTER` in `bound_tables.slang`). `03l3` returns early when the callee's bit is clear. The filter is cleared with the counts once per job. The per-round restore copies only the counts, so the bits of earlier rounds' dependency rows stay set; they can only cost a scan, never skip a row. Bound inference per round, rounds 3 to 7: 94 to 97 µs before, 22 to 28 µs after. Type check 29.01 to 28.76 ms.
- **Context slots in `calls.clear`.** `01_resolve` cleared all 32 slots of `call_context_ref_tag` and `call_context_ref_payload` for every HIR row (about 54 MB at settings' size) before the rounds. Every reader checks the slot's bit in `call_context_arg_mask` first: argument and call environments (`contextual_call_environment.slang`), explicit applications (`03a8`), the publisher's priors (`ct_context_publish.slang`, through the same helper), generic call results (`00c`), bound-member routing (`09`, only slots it wrote itself), and the host's readback in `generic_calls.rs`. Every writer sets a bit only for a slot it wrote (`03a8`, `ct_context_publish`, `07a`, `15b`, `09`). The body-specialization rewrite (`00g`) touches every slot but only rewrites tag 2, which no unmasked reader sees. The masks are still cleared. `calls.clear` 200 to 134 µs; type check 28.76 to 28.51 ms.

Settings stayed byte-identical (`115a4d52a2ae77e0`, 5 of 5 builds) and the dispatch count is unchanged (1,421).

## Listed live type rows (2026-11-17, second pass)

Three passes of every round visit every live type row: the closed application index twice (`02c`, as `calls.argument_context_type_index` and `calls.return_types.index`) and the imported fields (`07`). Live rows are one source row per token (about 454,000 on settings) and the generated rows after them. Most source rows hold no type, and the three passes skip a row without a kind.

The source rows that hold a type are now listed once before the rounds (and before the final pass of a job without rounds): `type_check.calls.type_rows.clear` zeroes the count, `02d_list_type_rows` appends every source row with a kind, and `02e_type_row_list_args` sizes the three passes over the list plus the generated rows so far. The three passes visit the listed rows, then the generated rows by index from `source_rows`, as before. Rows generated later in the rounds are reached by striding, as before. (`shaders/type_checker/type/instances/live_type_row_list.slang`.)

Whether a pass inside the rounds gives a source row a kind, settled by reading every writer of `type_instance_kind`:

| Writer | Rows | Inside the rounds |
|---|---|---|
| `type/instances/00_clear`, `01b`, `01c`, `modules/10e0l`, `dependencies/14`, `dependencies/07_project_calls`, `methods/02b` | source rows | no, before the rounds |
| `allocate_application`, `ct_realize`, `methods/08` | generated rows (`source_rows + ordinal`) | yes, but past the source rows |
| `methods/06_mark_call_keys` (a path receiver's token) | source rows | yes (`methods.mark_call_keys.inference`) |
| `semantic/artifact/00c` | | no, after the rounds |

So `06` is the only pass inside the rounds that can give a source row its first kind. It now sets the kind with a compare-exchange and appends the row to the list when the old kind was 0. `06` also runs before the list is built; those appends go to the previous job's list, which the clear and the listing replace (`mark_zero_initialized` declares that).

`02c` is one kernel for its seven passes. A listed copy would be a new kernel with the structural hash's per-thread array, which the local array budget forbids. A uniform selects the rows instead: `gTypeRowList.listed` is 1 for the rounds' pass (`TypeRowListParams`, bound with `ComputeOperation::indirect_with_uniform`) and 0 in the shared resource map. The imported fields have no per-thread array, so the rounds use `07b_project_listed_imported_fields`, which shares `imported_fields.slang` with `07`.

Settings, traced, per-pass minimum over the last 3 builds:

| Pass, per round | Before | After |
|---|---|---|
| `calls.argument_context_type_index`, rounds 8 to 11 | 16 µs | 6 to 7 µs |
| `calls.return_types.index`, rounds 6, 7, 9 to 11 | 16 to 17 µs | 6 to 7 µs |
| `calls.return_types.imported_fields` | 17 to 18 µs | 9 to 11 µs |
| Sum of the three over 11 rounds | 592 µs | 379 µs |
| New passes, once: `type_rows.list`, `type_rows.args` | | 14 µs, 5 µs |

Type-check dispatches 1,421 to 1,423. The executable stayed byte-identical (5 of 5 builds). A screen recorder shared the GPU during these traces, and whole-build sums moved by more than 1 ms between runs of the same binary, so this change is measured by its passes.

## What remains

- Activity per item, as above.
- Fusing passes: each removed dispatch saves about 8 µs of host recording and 1 µs of GPU time. Most passes in a round write the shared interner tables, so a fused group needs an argument that it behaves like the passes run in order.
