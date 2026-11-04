# LowerSlotsSmall

- 11-04 (leafB): new leaf for GenPC's `lower_body` and `compile_declared` pre lemmas.
  `lower_body` computes the body's `Stmt.extent`, whose `+ 1`s need the lowered slots bounded;
  `compile_lowered` (now a `COMPILE_FIXED_ROOTS` member) needs the lowered functions' numbers
  below `2^62`. SelfPre/LowerSlots takes the leaf to `lowerFunc`'s body (`lowered_body`, stated up
  front in `lower_func`'s pre lemma by `COMPILE_FACTS`) and to `lowerFuncs` (`val_lowerFuncs`,
  which `Tactic.valueFacts` finds by name and passes the leaf to). The pre lemmas from
  `compile_source` down to `lower_func` assume it, so PreCompileSourceV5's assembly is a reduction
  from this leaf.
- Proof plan: induction over `SrcStmt.lower`, `SrcEff.eval` and their helpers with the slot
  invariants the pre lemmas already carry (`COMPILE_OVERRIDES`' `SrcStmt_lower` and `SrcEff_eval`
  bounds, `scopeTop`, the evaluator's `evalSlotLimit` checks), plus the numbers each helper writes
  (callee ids and shifts from the statement, sizes from `ts`/`tsd`, static offsets below `2^31`).
