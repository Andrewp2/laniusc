# CompileFuncSlots

- 11-03 (leafB): stated for PreCompileSourceV4's group C (V4/NOTES.md): the Mini compile's encoders turn
  slots into 32-bit displacements, and `nb` of a code list also counts its jump targets (pc offsets up to
  2^40), so the slots need their own measure (`codeSlotTop`, SelfPre/CompileSlots.lean). Not yet used:
  pre_certs.py would carry `codeSlotTop instrs ≤ slots ≤ frameLimit` from `compile_func` to the encoders
  (`COMPILE_OVERRIDES`), with `slotTop` facts for the `match`es on an instruction. Unchecked parts of the
  "why": `sys` uses slots `slot .. slot + 2`, and a call's results go to `target .. target + count - 1`;
  whether `Stmt.within` bounds both is to be read off `within`.
- 11-03 (leafB): superseded by CompileFuncSlotsV2 (its NOTES): the unchecked claims hold, but `slotTop`
  does not count what a call or a return copies, and the encoders also need the code's size and the
  instructions' numbers. Nothing uses this statement.
