# CompileFuncSlotsV2

- 11-03 (leafB): replaces CompileFuncSlots (its NOTES), whose `slotTop` missed that a call copies its
  arguments to the callee's first slots and a return its sources to the frame's first slots
  (`copy_bytes` needs `p0 + p2 + length ≤ 2^24`), and which lacked the code's size (`link_onto`,
  `layout`, `Code_size`) and the instructions' numbers (`encode_onto`'s `nb` premise). Its two claims
  that were unchecked in V1 hold, read off compiler.lani (compileArgs.lean): `Stmt.within` checks
  `target + count ≤ locals` for a call, and a `sys` needs `args.length = 3`, so its slots
  `slot .. slot + 2` are temporaries.
- Used by `vals_compileFuncs` (SelfPre/CompileOpt), which turns it into `codesSlack codes = 0` and
  `codesNb codes ≤ max (nb fs) 2^40` for `compileFuncs`; pre_certs.py's overrides carry those from
  `compile_program` through `link`, `room_after`, `link_fitting` and `link_onto` to `encode_onto` and
  `Instr_encode`. The pre lemmas from `compile_source` down to `compile_program` assume it
  (`Tactic.openProp`), so PreCompileSourceV4's assembly is a reduction from this leaf.
- 11-03 (leafB): proved (Proof.lean, helpers in SelfPre/CompileSlotsProof.lean): slots by
  `reach_compileStmt` (`Stmt.within` keeps locals below `locals`; temporaries at `locals + depth`,
  `depth < Stmt.temps`; argument k at `locals + k` with `args.length ≤ argsTemps args 0`), size by
  `codeSize_le` and the room check (`10 + 7 * locals + 64 * 2^30 ≤ 2^40`), numbers by
  `nb_compileStmt` (jump targets are positions up to the code's end; `brk`/`cont` are earlier ones).
