# PreCompileSourceV4

- 11-03 (leafB): stated to replace PreCompileSourceV3 (probably false: `params_size` adds the parameters'
  sizes with no per-function bound, V3/NOTES.md). The new premise is a plain hypothesis,
  `∀ f ∈ p.funcs, Lanius.Mini.paramsSize f.params ≤ 2 ^ 40`, for the front end's leaf to supply (leafA's
  params-slot limit, FrontEndParamSlots, not yet stated); PreCompileWords.red5 then uses V4 with it,
  FrontEndTypeSlots and FrontEndStmtDepth as red3 does. Struct fields need no premise: a struct's size
  is the sum of its fields' and `ts p ≤ weightLimit` bounds it.
- Work under it: GenPC's SelfP02 (pres, 71 failing at c4336d4de) with the leaves LowerFuncsTemps and
  OptimizeKeepsNumbers; the lowering side's invariants (slots below params + depth) next.
- 11-03 (leafB): red5 (PreCompileWords) uses V4 with FrontEndParamSlots, FrontEndTypeSlots and
  FrontEndStmtDepthV2.
- 11-03 (leafB): `frame_block` probably makes V4 false too, and `room_fits` does not bound it.
  `lower_func`'s precondition has `frame_block`'s right after `params_size`'s: `paramsArrayBytes`
  plus `SrcStmt.arrayBytes`, which adds `declBytes` over every let of the source body (both branches
  of an `if`, every arm) with no cost check between the additions. `room_fits` bounds the weight of
  the Mini body in `compile_func`, after lowering, so nothing bounds the source body's lets when
  `frame_block` runs. Their number is bounded only by the budget (`slice_uses`, which walks every
  node, is charged before), and a wildcard arm copied per variant and nested gives many lets from few
  words. So the sum reaches about `2^25 * 2^62` (`arrayBytesOf ≤ 8 * ts ≤ 2^25` per let). Fix: a
  front-end or lowering check, e.g. `frameBlock` summed against a limit as it adds up (as `stmt_room`
  does), or a per-function bound on the source body's lets before `frame_block`; the same goes for
  any other whole-body sum in lowering (`SrcStmt_array_bytes`, `params_array_bytes`).
- 11-03 (leafA): `frame_block` is now checked as it adds up (compiler.lani `params_room`,
  `block_room`, `block_limit` = 2^31 - 1): each parameter's and let's bytes come out of the room,
  and a block over it is 2^31. So `frameBlock f ≤ 2^31` (`frameBlock_le`, Mini/FrameRoom.lean), with
  no premise, and V4 holds as stated as far as `frame_block` goes. The check changes no result of the
  compiler (`compileSource_unchecked`).
- 11-03 (leafA): the needs are saturated (coordinator's decision on leafB's finding): `need_capped`
  caps each round's need at `need_limit()` = 2^40 and keeps a need at the limit there, and
  `lower_func` rejects a need at the limit. So every need is at most 2^40 and `frame_block + callee
  need` at most 2^31 + 2^40, with no premise. The rooms are not below a fixed bound (a chain of
  callees with blocks makes a caller's need, and so its room, as large as their sum), so the limit
  does change what is accepted: `compileSource_unchecked` says `compileSource p` is the old
  compiler's result when every need is below 2^40 (`NeedsBelow`), and `none` otherwise. A need of
  2^40 bytes of frame memory is more than any binary has (`elf_fits`: stack < 2^40).
- 11-03 (leafB), on leafA's need_round note: the M-form does not bound the rounds. `funcNeeds` runs
  `needsAfter funcs [] funcs.length`: at most F + 1 rounds (F functions), each adding at most one
  `frameBlock` (≤ 2^31 with leafA's check) along a call cycle, so a need after k rounds is at most
  (k + 1) * 2^31. A round costs about F steps plus the bodies' walks, not 2^31, so `nb next ≤ M + Cost`
  fails, and `k ≤ F ≤ hb p ≤ 2^62` alone allows 2^93. What does hold: reaching round k costs at least
  k * F and k ≤ F + 1, so k^2 ≤ 2b ≤ 2^63, k < 2^32, and a need stays below 2^63 + 2^31. That is a
  cost-relative argument across rounds (rounds done times F against the budget spent), which the
  generated pre form (it sees only the budget left) cannot state; it would be a hand-proved group
  for `needs_after`/`need_round` with that invariant, tight at 2^64. Cheaper: a front-end limit on
  the number of functions (F ≤ 2^30 gives (F + 2) * 2^31 ≤ 2^62, an M-form override
  `nb p1 + 2^31 * (p2 + 1) ≤ 2^31 * (p0.length + 2)` plus F's premise), or needs that saturate at a
  limit in the compiler. Either is a new premise (V5) or a .lani change; for the coordinator.
- 11-03 (leafB): parameters' slots carried as `paramsMax ≤ K` (CompileValues; `paramsMax_le` from V4's
  premise) from `compile_source` down to `params_size`, which now passes (P02: 71 failing, none new).
  Type sizes do not go the same way yet: `ts` bounds each type's size, but `sizes` of a declared
  struct's fields (`SrcStructDecl`, whose `ts` is the max over its fields, not their sum) is bounded only
  because the struct type it was declared from is in the program, which no measure of `SrcDecls`
  states. Stating `SrcType.size p0 ≤ K`/`sizes p0 ≤ K` as invariants broke 19 callers that pass
  types or field lists from the declarations (`lower_struct_fields`, `copy_slots`, `eval_struct_of`,
  ...). Needs a `ts` of `SrcStructDecl` that includes `sizes fields` (an hb_gen.py TS change, with
  `declareProgram` keeping it) or a front-end leaf on declared structs' sizes.
- 11-03 (leafB, second context): type sizes carried through the lowering. `SelfPre/CompileTypes.lean`:
  `tsd` over `SrcDecls` (a struct counts its fields' `sizes` and slots, an enum `1 + maxSize` and its
  variants' slots; `ts` unchanged), `val_declareProgram : tsdOpt (declareProgram p) ≤ ts p` (by hand,
  through `SrcType.declare`/`declareTypes`/`declareVariants`/`SrcStmt.declare`/`declareFuncs`), and the
  lookups' lemmas (`vals_lookup`, `vals_structFields`, `vals_enumVariants`, `vals_elementOf`, index
  lemmas for signatures, field lists and variants, `val_sigs`, `val_withBudget`, `val_paramScope`,
  `val_repeatType`, `val_matchVariants`). pre_certs.py: the 'ts' kind follows `match` pattern variables
  (a lookup's result included) to the parameter they come from; SrcDecls parameters get `tsd x ≤ 2^22`,
  signatures `ts` plus their parameters' sum below K (`sigsParams`, from `paramsMax`); lists of types
  their `sizes`/`maxSize` below K ('sz'/'ms' kinds, seeded at `sizes`/`max_size`); skipped functions
  (COMPILE_NUM_SKIP) get these too. Tactic `valueFacts`: `ts_le_<S>_<f>` projection facts, `ts` of a
  constructor equation (`x.ty = .struct id fs`), index lemmas, all `ts` facts simp-normalized
  (`tySlots`). P02: 71 -> 68 failing, none new; no failure left on `SrcType_size`/`sizes`/`max_size`
  premises of those 19 callers.

**11-03, evaluator result types (leafB).** `CompileEvalTypes.lean`: `val_SrcEff_eval`/`val_evalArgs`
(`ts` of an evaluation ≤ the expression's, signatures', declarations', scope's, or 16) and the `val_`
lemmas of the 92 functions the evaluator reaches (`ts_auto`: split, `val_` facts, `omega_atoms`). The
mutual theorem is `tsm_SrcEff_eval` at a linear bound `M`, its cases stated apart (`tsm_eval_*`), so the
structural-recursion check sees only small terms (whole file about 8 s). `vals_SrcEff_eval` for
`eval .. = some v`; `valueFacts` now tries `vals_<T>_<f>` before `vals_<f>`. Tsd-bounded declarations
also get `ts x ≤ 2^22` (`ts_le_tsd`). `val_SrcType_size`. P02: 67 -> 66 (`binding_bytes`), none new.
`step_eval_args` passes its type premise; it now fails on the slot counter `x4 + size ≤ M + Cost`
(a slots invariant, like `param_scope`'s), not types.

**11-03, the 66 left, by the invariant each needs (leafB, after S3).** From one debug check of every
failing lemma (the failed omega goals and premises):
- A. The lowering's slot numbers (36): `SrcEff_eval`, `eval_args`, `eval_arms`, `param_scope`,
  `load_types`/`load_cases`, `store_type(s)`/`store_cases`, `store_eval(_byte/_word)`,
  `element_stores/loads`, `view_stores`, `str_placed`/`str_stores`, `lower_set_index_any`,
  `assign_from`, `slot_vars`, `eval_word_element`, `eval_len_of`, `bounds_guard`, `arm_payload`,
  `arm_bind`, `lower_arms`, `lower_body`, `SrcStmt_depth`, `SrcStmt_lower`, `array_args`,
  `array_call_sig`, `array_arg_local`, the four `*field_of`. Counters `slot + 1`, `slot + size`,
  `next`, `b.slot + offset` below 2^64. Most are in `COMPILE_NUM_SKIP` (no number hypotheses).
- B. Type sizes passed as plain numbers (7): `word_stride`, `element_base`, `pick_element`,
  `put_element` (`8 * words`, `k * size`, `< 2^32`), `params_array_bytes`, `SrcStmt_array_bytes`,
  `str_words` (`chars` bytes `* 256`).
- C. The Mini compile's frames and code (17): `frame_size`, `slot_offset`, `arg_base`, `copy_bytes`,
  `slot_range`, `sys_bytes`, `Instr_encode`, `encode_onto`, `Code_size`, `link_onto`,
  `host_text_code`, `dying_extent`, `arg_slots`, `Expr_extent`, `Stmt_extent`, `Stmt_within`,
  `layout`. `slot_offset`'s `(slot + 1) * 8 < 2^32` needs `compile_func`'s frame check (leafA-frame).
- D. Needs and rounds (4, leafA-frame): `round_cons`, `round_join`, `need_round`, `frame_block`.
- E. Whole-program numbers (2): `compile_optimized` (OptimizeKeepsNumbers, now proved), `compile_declared`.

**V4 is probably false at A (the evaluator's temporaries).** `evalArgs` evaluates each argument at
`slot +` the earlier arguments' sizes, and `eVariant`/`eStruct` likewise, so a nested call adds up to its
callee's parameters' slots per level. Nothing limits that: the front end's `depth_limit` counts the
lets' slots (`SrcStmt.depth`), `limEff` checks only types, and `compile_func`'s frame check comes after
lowering. A counterexample within V4's premises: `f(s, f(s, f(s, ..)))` nested 2^43 deep, `s` a
parameter whose struct type has 2^21 one-slot fields (`ts` ≤ 2^22, `paramsSize f` ≈ 2^21, no lets).
The innermost argument is at slot about 2^64, while the cost (about 2^45) and `hb` (about 2^43) stay
inside `M + b ≤ 2^62`. So `eval_args`' `slot + size < 2^64` fails. A fix needs a program-level limit
first: the front end counting the evaluator's temporaries along with the lets (in `limEff`/`depth_limit`),
or the lowering rejecting when `slot` passes a limit (capped, as `needs`). That is a .lani change.
After it, a V5 premise (or an extended FrontEndStmtDepthV2) bounds every slot the lowering computes, and
A's invariant is `slot + need ≤ 2^41`.

**11-03, groups B and E (leafB).** E: `CompileOpt.lean` (`val_optimizeProgram`, from the proved
OptimizeKeepsNumbers), imported by GenPC's pre modules (`COMPILE_PRE_IMPORTS`); `compile_optimized`
passes. `compile_declared` waits on the lowered program's numbers (A). B: a 'w' kind in pre_certs.py, a
`Nat` parameter that is a type size (`x ≤ 2^22`), seeded at `word_stride` and `element_base`; a caller's bare
variable passes it on, a `SrcType.size t` argument gives `ts t`. `str_words` gets `nb chars ≤ 255`
(`COMPILE_OVERRIDES`), from `lower_str`'s ASCII test (`strAscii_eq_true`/`_eq_false`, `hb_simp`).
`word_stride`, `element_base`, `str_words` pass. Left in B: `pick_element`/`put_element` (also add the
base slot `base + k * size`: A) and `params_array_bytes`/`SrcStmt_array_bytes` (the frame block's sums:
D). P02: 66 -> 62, none new.

**11-03, after leafA-frame (leafB).** The temps lines of `COMPILE_OVERRIDES` for `compile_func`,
`compile_funcs`, `compile_program`, `compile_optimized`, `compile_lowered` and `compile_or` are gone:
`compile_func` gets `Stmt.temps body ≤ weight` (`val_Stmt_temps`, stated up front by the new
`COMPILE_FACTS`, since only `Stmt_temps`' premise mentions it) and its room check bounds the weight.
D: `CompileNeeds.lean` (`val_SrcStmt_calleeNeed`/`val_SrcEff_calleeNeed`: a callee's need is at most the
largest need, `val_frameBlock` from `frameBlock_le`, and `val_needRound(At)`/`val_needsAfter`/`val_funcNeeds`:
every round is capped at `needLimit`), with `nb prev ≤ 2^40` as `need_round_at`'s, `need_round`'s and
`needs_after`'s invariant. leafA-frame's caps also fixed `frame_block` and the array-bytes sums.
P02: 62 -> 58, none new. `LowerFuncsTemps` is no longer used by the pre lemmas.

**11-03, group C, first part (leafB).** Counters along a list get "counter + the list's height ≤ K"
(`COMPILE_OVERRIDES`: `slot_range` `first + count`, `dying_extent`, `arg_slots`; the height, not
`.length`, since `hb` facts are in scope where a callee's premise needs them), and `Instr_encode`'s
`match` variables count as its instruction (`COMPILE_NUM_ALIAS`). P02: 58 -> 55, none new. The
encoders' slots (`slot_offset`'s `(slot + 1) * 8 < 2^32`, `frame_size`, `arg_base`, `copy_bytes`,
`sys_bytes`, `Instr_encode`'s `argBase slots`, `encode_onto`, `link_onto`) need a frame-slot bound that
`nb` cannot give (it also counts jump targets): the new open leaf CompileFuncSlots (`codeSlotTop
instrs ≤ slots ≤ frameLimit` for `compileFunc`'s code, measure in SelfPre/CompileSlots.lean), to be carried
by `COMPILE_OVERRIDES` from `compile_func` to the encoders. Not yet looked at: `round_cons`/`round_join`
(`count` sums), `Stmt_within`, `Code_size`, `layout`, `Expr_extent`/`Stmt_extent`. `host_text_code`
(`slot + 1 ≤ M`) belongs with A.

**11-03, group C, second part (leafB).** CompileFuncSlots' two unchecked claims hold (the leaf's NOTES),
but the encoders need more than it states, so it is replaced by CompileFuncSlotsV2: slots by
`slotReach` (a call's arguments and a return's sources also counted by number: `copy_bytes`), the
code's size `≤ 2^40` (`Code_size`, `layout`, `link_onto`), and the instructions' numbers
`≤ max (nb func) 2^40` (`encode_onto`'s `nb` premise). `vals_compileFuncs` (SelfPre/CompileOpt) turns it
into `codesSlack codes = 0` and `codesNb codes ≤ max (nb fs) 2^40`, and the overrides carry those from
`compile_program` through `link`, `room_after`/`room_next`, `link_fitting` and `link_onto` to
`encode_onto` and `Instr_encode` (`codesSlack_cons_eq_zero` reads the measure one code at a time: the
unfolded `max`/`-` form gave "(kernel) deep recursion" next to the other hypotheses). The pre lemmas
from `compile_source` down to `compile_program` assume CompileFuncSlotsV2 (Tactic's `openProp` takes an
open statement premise from the context), so V4's assembly becomes a reduction from it. `round_cons`/
`round_join`: a round's count is at most its bytes (`val_packRound`, `val_packRounds`).
`Expr_extent`/`Stmt_extent`/`Stmt_within`: their `match` variables count as the statement
(`COMPILE_NUM_ALIAS`), so their numbers come from the caller's `nb`. `link_onto`'s entries: `val_layout`.

**11-03 (leafB).** CompileFuncSlotsV2 is proved (its Proof.lean; SelfPre/CompileSlotsProof.lean), so the
Mini-compile side's assumption of it is discharged: V4 still waits on the lowering slots (group A).

- 11-03 (leafA, coordinator's decision, on leafB2's finding A): the evaluator's start slots are checked against
  `eval_slot_limit()` = 2^40 in `eval_args`, `eval_let_body` and `eval_arm_in` (the three steps that add a type
  size per nesting level), which return `None` at or past it. Between two checks a slot grows by at most one
  type size (≤ 2^22) plus one per nesting level, so A's sums stay below 2^64 with no new premise
  (SEMANTIC_DECISIONS "The evaluator's slots checked against a limit").

- 11-04 (leafB): V4 is probably false, and PreCompileSourceV5 replaces it. (1) "one per nesting level" is
  not bounded by anything in V4: an operator's right operand starts one slot past its left with no cost of
  its own, and an `eBorrow` (or `arraySlice`, ...) left operand costs nothing, so a right-nested
  `eApply op (eBorrow ..) (eApply op (eBorrow ..) ..)` of depth d reaches `slot + d` at the budget it
  started with; `Pre_plus slot 1` fails for d ≥ 2^64 whatever `b` is. V5 adds
  `∀ f ∈ p.funcs, SrcStmt.slotNest f.body ≤ 2^55` (SelfPre/EvalSlots). (2) `compile_source`'s pre needs
  `nb p ≤ M` (the program's ids, field indices and array lengths reach `M`-bounded parameters) and V4
  has only `hb p ≤ M`, which counts no numbers; V5 adds it.
- 11-04 (leafB): GenPC's SelfP01 (posts) did not build after 0a9a4a1be (the slot checks):
  `post_step_eval_arms`'s Lean side has `if evalSlotLimit ≤ dst` inline where the cost model calls
  `eval_arm_in`, and `simp` unfolding `evalSlotLimit` in the condition but not in its `Decidable` instance
  (`Nat.decLe evalSlotLimit x`) left a term `simp` cannot rewrite (`if_pos` failed at instance
  transparency) and the split never reduced. Tactic's `closeArith` now unfolds the condition's nullary
  constants with `delta` everywhere before it splits.
