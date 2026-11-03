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
- 11-03 (leafB): per-function sums are now checked in the compiler (SEMANTIC_DECISIONS "A function's
  code checked against the image limit first"). `compile_func` asks `room_fits(stmt_room(image_limit(),
  body))`; `Mini/Room.lean` proves `stmtRoom_eq` (the check is `s.weight ≤ room`), `codeSize_le` (code is
  at most 64 bytes per unit of weight, so at most 2^36 bytes once the check passes) and
  `compileProgram_unchecked` (no result changes). The cost argument ("at least 1/8 cost per byte") was
  not taken: it needs a cost-relative measure, and a call emits 14 bytes per argument for one step.
- 11-03 (leafB): why GenPC's SelfP02 pre lemmas fail (regenerated after the check above). 97 of the
  390 step/pre lemmas fail, every one with `omega could not prove the goal`, on an overflow side
  condition (`a + b < 2^64`, `14 * n < 2^64`, `x + 24 < 2^64`). In 96 of them an atom of that
  condition is unconstrained in omega's counterexample. One cause covers them all: `hb` counts no
  numbers (`hb (x : Nat) = 0`, and a structure's `hb` is the highest of its lists), so `hb x ≤ M`
  bounds no number in `x`, and a post lemma `hb (F x) ≤ M + Cost` says nothing about a number `F`
  returns. It is not a missing hand case or a tactic gap.
  - About 40 add a constant to a number parameter or field (`round_cons`, `eval_right`,
    `bounds_guard`, `host_*_code`, `slot_offset`, `zero_locals`, ...). These are false as stated:
    the number can be 2^64 - 1 under the hypotheses.
  - About 40 add numbers a callee computes (`Code_size`, `seq_code`, `ite_code`, `loop_code`,
    `compile_func`'s `locals + temps`, `layout`, `link_onto`, `offset_after`, `frame_block`,
    `lower_field_of`, ...). Not provable from the posts, which bound no number.
  - About 16 multiply or add type sizes (`binding_bytes`, `array_bytes_of`, `params_size`,
    `match_dst`, ...). These need `ts p ≤ weightLimit`, which the M-form does not carry.
  - `Instr_size` also needs `14 * args.length < 2^64`, more than `length ≤ M ≤ 2^62` gives; the new
    `eval_str` and `str_placed` (f6v's str values) are in the first group.
  So the generated M-form is the wrong split of V3 for the compile side, and these are not leaves.
  The front end got by with `OVERRIDES` and `val_` lemmas because few of its numbers are not
  positions. A fix of the cause: a number measure (an `hb_gen.py` mode, a max over every number in a
  value, like `ts`), with `nb x ≤ N` hypotheses in the compile pres and posts
  `nb (F x) ≤ N + Cost` where a function only adds constants. Sums of two numbers (pc plus code
  size, slot plus offset) still need the program's bounds (`ts`, `SrcStmt.depth`, the new weight
  check), stated per family as hand lemmas. This touches `pre_parts`, the core of pre_certs.py
  (f14c's), so it waits for the coordinator.
