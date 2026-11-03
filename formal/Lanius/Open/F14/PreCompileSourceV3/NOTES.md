# PreCompileSourceV3

- 11-03 (leafB): replaces PreCompileSourceV2 (probably false at any budget). Used by
  PreCompileWords.red3 with PostFrontEndWords (proved), FrontEndTypeSlots, FrontEndStmtDepth and
  PreBinaryWordsV3. The generated M-form pre lemmas are in `SelfPre/GenPC/SelfP02.lean` (not checked
  in: at least 97 of them fail, on the numbers below). Their posts are in SelfP01 (all pass, 55 s).
- The weak point is a function's `code_size` and pc offsets. Nothing bounds a function's code except the
  budget. A wildcard arm's per-variant copies are each compiled, so a function's code can be
  exponential in its source. So `code_size` is below 2^64 only if the compile spends at least about
  1/8 of a unit of cost per byte of code it plans (an `imm` is 10 bytes; it is built with at least one
  cons and its `Instr` box, and concat copies it again). If that fails, a cheap fix is in the
  compiler: check each function's code against `image_limit` as `compile_stmt`'s pc advances, as
  `room_after` does for the whole image.
