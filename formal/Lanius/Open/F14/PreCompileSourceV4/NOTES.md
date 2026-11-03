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
