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
- 11-03 (leafB): the number measure. `hb_gen.py --nums` generates `SelfPre/NB.lean` (`nb`, the largest
  number in a value, a max). With `--compile` (only), pre_certs.py gives a pre lemma `x ≤ M` or
  `nb x ≤ M` for each parameter whose numbers its precondition uses (`num_used`, a fixpoint over the
  `Pre_` models: in a `plus`/`times` or a callee's used position), and states its structure fields'
  bounds (`have hn_x_f`). GenP is unchanged. P02: 97 failing -> 83. A function in `COMPILE_NUM_SKIP`
  (66, found by iterating: a caller failed on its number premise) keeps no number hypotheses: its
  callers pass a number they cannot bound from `M`, mostly a recursion that counts up
  (`zero_locals (first + 1) (count - 1)`, `slot_vars`, `compile_expr`'s depth) or a type size
  (`x.size`), or a callee's result (`Code_size`, `seq_code`, `offset_after`). Next: invariant
  hypotheses for the counting recursions (`first + count ≤ M`, as the front end's OVERRIDES), and
  value lemmas for the computed numbers.
- 11-03 (leafB): type sizes and the code-size invariants. Pre lemmas get `ts x ≤ 2^22` where a type's
  size is used (`num_used` now records the kind of use: numbers or type sizes). The Mini program's
  compile (what `compile_optimized` reaches, `COMPILE_FIXED_ROOTS`) bounds the program's numbers by
  `K = 2^62` instead of `M`: they are its own slots, indices and counts and do not grow as it
  compiles, and a caller's `M ≤ K` gives them. `COMPILE_OVERRIDES` add invariants: a temporary's
  depth plus the expression's (arguments') weight below `2^40` (`compile_expr`, `compile_args`;
  `hb` does not count tree nodes, so the height cannot be the measure), a pc offset plus 64 bytes
  per unit of the weight left below `2^40` (`compile_stmt`, `seq_code`, `ite_code`, `loop_code`,
  from `CompileValues`' `val_compileStmt`/`val_compileExpr`, the `codeSize_le` bounds), a code
  list's or an instruction's size below `K` (`code_size`, `Instr_size`), and `first + count ≤ K`
  (`zero_locals`). P02: 81 failing -> 73, none newly failing. Failed: tagging pattern variables of
  every `match` as their parameter (`match_aliases`, behind `PRE_NUMS_ALIAS=1`): 101 failing, the
  callers then need numbers of callee results (`factsAfter`, `optimizeProgram`) that no post bounds.
  `compile_func` stays skipped: `locals + temps` needs a bound on `Stmt.temps` of the lowered,
  optimized body, which nothing upstream states yet.
- 11-03 (leafB): two open leaves for the Mini compile's cuts, `LowerFuncsTemps` (a lowered body's
  temporaries are at most the lowering's cost) and `OptimizeKeepsNumbers` (the optimizer raises no
  number and no temporaries count). With `funcsTemps ≤ K` carried from `compile_lowered` down to
  `compile_func` (`COMPILE_OVERRIDES`; `CompileValues`' `funcsTemps`/`optTemps`) and `compile_funcs`'
  and `compile_lowered`'s pattern variables taken as their parameter (`COMPILE_NUM_ALIAS`), P02 has 71
  failing (73 before): `compile_func`, the temps functions, `compile_funcs`, `compile_program`,
  `compile_or` pass; `compile_optimized` waits on OptimizeKeepsNumbers and `compile_declared` on
  LowerFuncsTemps and on a bound of the lowered program's numbers (lowering side, next).
- 11-03 (leafB): V3 is probably false as stated. `lower_func`'s precondition starts with
  `params_size`'s, which adds the parameters' type sizes with no cost check between them. A program
  with 2^43 parameters of a type of 2^22 slots has `ts p ≤ weightLimit`, depths 0 and `hb p` about
  2^43, and a budget of about 2^44 reaches `lower_func` (declaring and sigs cost about a step per
  parameter), with `M + b ≤ 2^62`; the sum is 2^65. The same holds for `frame_block` and the other
  per-function sums over parameters and fields. A replacement needs a per-function bound on the
  parameters' slots (as `SrcStmt.depth ≤ 2^55` for the lets), e.g. `paramsSize f.params ≤ 2^55`, from
  the front end as FrontEndStmtDepth does for depths (a parameter takes at least one word).
- 11-03 (leafB): unused. Replaced by PreCompileSourceV4, which adds `∀ f ∈ p.funcs, paramsSize f.params
  ≤ 2^40` (the parameters' slots; the counterexample above). PreCompileWords.red3 stays as written; a
  red5 from V4 waits on the front end's leaf for that bound (leafA's FrontEndParamSlots).
