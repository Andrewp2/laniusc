# PreCompileSourceV5

- 11-04 (leafB): stated to replace PreCompileSourceV4, which lacks two premises (V4/NOTES.md, 11-04):
  `nb p ≤ M` (the program's numbers reach `M`-bounded parameters; `hb` counts no numbers) and
  `∀ f ∈ p.funcs, SrcStmt.slotNest f.body ≤ 2 ^ 55` (a right-nested `eApply`/`eDivide` chain with
  zero-cost left operands, such as `eBorrow`, moves the slot one further per level at no cost). Both
  are for the front end to supply: its numbers are below the source's length, and its expressions'
  nesting below the parse's depth (as FrontEndStmtDepthV2 does for the lets).
- Work under it: GenPC's SelfP02 pre lemmas (`compile_source` assumes `nestMax p.funcs ≤ 2^55` and
  `nb p ≤ M`, `COMPILE_OVERRIDES`), the lowering's slot invariants (SelfPre/EvalSlots, `slot_kind` and
  `slot_tiers` in tools/pre_certs.py). At 11-04: P02 9 failing (from 40).
- Not yet known to hold: `array_args` adds each array argument's bytes (`argBytes`, up to 2^25) to its
  offset with no check until `arrayCallCode` compares the total with the callee's block, so a call
  with more than 2^39 array arguments overflows. Nothing in V5 bounds a call's argument count (`hb p`
  only bounds it by 2^62). Fix: a check in `array_args` as the offset adds up (against the block
  limit, as `params_room` does), or a premise bounding parameter counts (V6).
