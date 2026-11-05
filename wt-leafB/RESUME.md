# leafB resume (compile side of F14's open graph)

Worktree /home/andrew-peterson/code/laniusc-wt/leafB, branch leafB. Leaves claimed:
PreCompileSource, PreBinaryWords, PostCompileSource (claims under target/claude-work/open/claims, 6 h).

## Done
- pre_certs.py: module prefix from OUTDIR; `--ns NS` option (header namespace).
- Tactic.lean: genLookup? (current namespace first, then SelfPre) for post_/pre_/HBPost lookups.
- GenPC generated: `python3 -I tools/pre_certs.py --ns Lanius.Faithful.SelfPre.Compile Lanius/Faithful/GenB Lanius/Faithful/SelfPre/GenPC compile_source binary_words` (from formal/).
  Shared with build_files: 4 models (cons_of SrcType, cons_of/single_of usize, length_of List usize) + 2 uposts (index_of, only): hence the namespace.

## Next
- build GenPC modules, record failures.
- (11-03) PostCompileSource released to leafA (coordinator); GenPC's post_compile_source states it anyway.
- Tactic.lean further: uint8_ofNat_lit in hbNormNames; decide_true/decide_false in normNames; `omega_atoms` syntax.
- pre_certs.py: `--base MOD`; compile section (bytes_hand, POST_HAND for bump/frame_memory/sys bytes + link; HAND_CASE SrcStmt_declare ifEval/matchArm). POST_HAND hook in non-recursive post branch.
- SelfPre/CompileValues.lean: byte-list length lemmas (pcCons etc.).
- Probe helpers: target/claude-work/leafB/bin/probe.py (deps-aware extract, DEBUG=1), extract.py. Logs in target/claude-work/leafB/logs.
- SelfP00, SelfP01 pass (P01 72 s own time). P02: fixed lower_match_arm (decide True) and SrcStmt_declare (hand) in probes.
- 706616c0b GenPC posts; 7d2f67367 merge (pushed by coordinator); 004a7add9 V2 statements + PreCompileWords.red2,
  FrontEndOutputSmall (open, for leafA/coordinator). Claims: PreCompileSourceV2, PreBinaryWordsV2.
- Tactic: val_<T>_<f> lookup first; CompileValues: enum value lemmas -> DivOp_size, FOp_number, FOp_size pass.
- Pre probe: target/claude-work/leafB/probe/Pre.lean (P03-07 concatenated, lcheck ~60 s, Lean stops at 100 errors).
- Next: V2 proof design: cost-free numeric bounds in terms of the program (not M + cost).
- 2fc31d7e9: merged lang (f14c certs, statics); --compile flag for compile hands; auto_bytes; P01 35 s.
- V2 analysis in PreCompileSourceV2/NOTES.md: need a size measure sz + weight bounds (2^22); hb not enough.
  Waiting on coordinator for go-ahead on the sz generator plan.
- 46ed7558f: hb_gen --sum -> SelfPre/SZ.lean (+SZAttr), builds 10 s. Step 2 stopped: whole-program linear
  sz bound false (monomorphization: 2^d instances, quadratic); V2/PreBinaryWordsV2 probably false at any
  budget. Proposal in PreCompileSourceV2/NOTES.md: tw max-measure (type weights) + per-function sz bound
  + whole-program sums via budget or a compiler image_limit check. Waiting on coordinator.
- 3c21158f2 + merge bd39f6c30 (11-03): compiler.lani room_after/link_fitting (image limit as sizes add up),
  roomAfter_eq/compileProgram_eq (Correct.lean), Gen x2/term/GenB regenerated (bin/regen_gen.py from f6v),
  trusted d75635f4ee0dd1d2, SEMANTIC_DECISIONS entry. hb_gen --slots -> TS.lean. New statements:
  FrontEndTypeSlots, FrontEndStmtDepth, PreCompileSourceV3, PreBinaryWordsV3; PreCompileWords.red3.
  V2 claims released. GenPC is 3 modules now (P02 = pres, failing, kept at probe/GenPC_SelfP02_pre.lean).
  Self-host fixpoint passed (186 s). Top-module build: bin/tops.sh LOG (290 s chunks).
- 11-03 task 1 (per-function sums): chose the stmt_room incremental check in compile_func (uncommitted at
  first): compiler.lani spend/expr_room/args_room/stmt_room/fits; re-extracted; imageLimit part is gone
  (now in compileArgs; linkedSize/roomAfter/compileProgram in P/linkedSize; compileFunc in P/compileFunc).
  Imports fixed; CompileCorrect spec (.1 more), Link Stmt.room_rename. LaniusMini builds.
  Next: Gen x2, term, GenB, GenP, GenPC, tops, trusted, SEMANTIC_DECISIONS, fixpoint, gate, commit.
- 23b827a8a (11-03): stmt_room check committed (fits renamed room_fits: a front-end local `fits` made the
  extractor add spurious imports). Mini/Room.lean: stmtRoom_eq, weight_le_codeSize, codeSize_le (64x),
  compileProgram_unchecked. trusted c6e25c9ba4f62ae4. Gate quick 25/25, fixpoint passed (180 s).
  GenPC P02: 97 fail, all omega on numbers hb ignores (categories in PreCompileSourceV3/NOTES.md);
  proposed a number measure nb (needs pre_parts change, f14c core) -> waiting on coordinator.
  P02 copy: probe/GenPC_SelfP02_pre.lean, failure list probe/fails.p02, errors probe/P02.out.
- 11-03 merges: 1871e5c69 (lang 86e698363, TRUSTED_BASE by hand), 721038aeb (lang 11239b11e, f14c's PostIH/PreIH),
  936760674 hash f4b274867e23528a, GenPC P01 regenerated (17 s). Quick gate 25/25.
- e51443e05: NB.lean (hb_gen --nums), pre_certs --compile number hyps (num_used/num_hyps/num_facts,
  COMPILE_NUM_SKIP 66 found by bin/numloop.sh iteration). P02 97 -> 83 failing (probe/P02nb.out, fails.nb).
  Next: ts hypotheses for type sizes (size_le_tySlots), counting-recursion invariants, value lemmas
  for code sizes (Room.lean codeSize_le) -- program-level facts, so hand lemmas / open statements.
- 5e62d98e7: ts hyps (`ts x ≤ 2^22`, kinds in num_used); 83 -> 81. match_aliases behind PRE_NUMS_ALIAS=1 (bad:
  101, callers need nb of callee results); PRE_NUMS_ALIASES=a,b for chosen functions (COMPILE_NUM_ALIAS).
- fca636894: COMPILE_OVERRIDES (depth+weight, pc+64*weight < 2^40, code/Instr size ≤ K, zero_locals),
  COMPILE_NUM_DROP, PRE_PREAMBLE (local hb_simp: weights, codeSize, Instr.size, roomFits_stmtRoom, nb lemmas),
  COMPILE_FIXED_ROOTS=[compile_optimized] → numbers ≤ K there. CompileValues: val_compileStmt/Expr/Args,
  val_zeroLocals (imports Mini.Room). 81 -> 73, 0 new. Baseline list probe/fails.p02 (= 81 run).
  Tools: bin/numloop.sh "<skip>" (ATTR=1 option), bin/dbg.sh THEOREM (debug premise failures -> probe/DBG.out).
  Next: compile_func chain needs Stmt.temps bound of lowered+optimized body (funcsTemps measure; optimizer
  lemmas or open leaf at compile_optimized), compile_funcs needs alias + nb chain to compile_lowered (cut).
- c4336d4de: leaves LowerFuncsTemps, OptimizeKeepsNumbers (Open/F14); funcsTemps/optTemps overrides from
  compile_lowered to compile_func; COMPILE_NUM_ALIAS={compile_funcs, compile_lowered}. P02 71 failing
  (baseline probe/fails.p02 = this run). compile_optimized/compile_declared wait on leaves.
  Finding (V3 NOTES): V3 probably false — params_size sums 2^43 params x 2^22 slots, no cost guard.
  Next: lowering-side invariants; needs a V4 with per-function params-slot bound (coordinator).
- cf1802022 (after merging lang 5a9e8be8e): PreCompileSourceV4 stated + claimed (params premise
  `∀ f ∈ p.funcs, paramsSize f.params ≤ 2^40`); V3 marked unused. red5 waits on leafA's FrontEndParamSlots
  (coordinator sends name). Depth premise 2^55 is met by FrontEndStmtDepthV2 (2^40). Next: lowering-side
  invariants aimed at V4 (params_size/frame_block/sizes etc. with params-slot override).
- 99a42c43f (on lang 640385095): GenPC P01 was stale since c7212ef22 (host text posts); regen.py PRE_HELD_OUT
  hides SelfP02. P02 baseline now 72 (host_write_code new from F8). Use regen.py for regeneration from now on.
- red5 committed; frame_block needs a lowering check (V4 NOTES), told coordinator.
- params_size piece committed (71). Declared struct sizes not covered by ts (V4 NOTES) — blocks type-size invariants.
- 11-03 tsd task (coordinator: option 1, separate measure, don't change ts; commit when the 19 callers pass).
  WIP patch target/claude-work/leafB/tsd-wip.patch (uncommitted): COMPILE_TS_SEED (SrcType_size/sizes/max_size
  p0 tagged 'ts'), overrides sizes/max_size ≤ K, preamble + tySlots* and ts_simp lemmas. Result 92 failing
  (22 new). Cause: callers take types out of lookups (`lookup scope id = some b`, b.ty; structFields;
  enumVariants; sigs) — no fact bounds them. Plan: (1) vals_ lemmas `F xs = some v → ts v ≤ ts xs` for the
  lookup functions (scope bindings, sigs, structFields/enumVariants with tsd for sums), (2) alias the
  functions that match on them (COMPILE_NUM_ALIAS; match_aliases owns scrutinee params), (3) tsd over SrcDecls
  (structs count sizes fields, enums 1 + maxSize) + val_declareProgram : tsdOpt (declareProgram p) ≤ ts p
  (hand lemma over SrcType.declare/declareTypes/declareVariants/SrcStmt.declare/declareFuncs).
- (11-03, second context) 9727d8b4e: tsd task done. CompileTypes.lean (tsd, val_declareProgram, lookup lemmas),
  pre_certs ts alias/TS_HYPS/sz+ms kinds, Tactic valueFacts ts facts (projections, constructor eqs, normalized).
  P02 71 -> 68, none new; baseline probe/fails.p02 = 68. Gate quick 25/25. GenP byte-identical (regen --only pre).
  Tools: bin/round.sh (probe + new/fixed), bin/summ.py (first error per theorem -> probe/summ.txt),
  bin/dbgs.sh THEOREM (failed premise + context). Still waiting: leafA's frame_block/needs .lani change.
- dbade50db: P02 67. Then 04958681d: CompileEvalTypes.lean (val_SrcEff_eval etc., generator probe in
  probe/tp/mkmut.py + tval_gen.py), vals_<T>_<f> lookup in Tactic, ht_x (ts ≤ W from tsd) in pre_certs,
  val_SrcType_size. P02 66, none new; baseline probe/fails.p02 = 66.
  Gate quick 25/25; GenP 0 files changed; GenPC P01 built. Type-size task done. Left: slot/number invariants
  (param_scope, step_eval_args' `x4 + size ≤ M + Cost`), extents, code sizes; frame_block/needs and the
  temps overrides wait for leafA-frame (coordinator: drop COMPILE_OVERRIDES temps lines for compile_func,
  compile_funcs, compile_program, compile_optimized, compile_lowered, compile_or when it lands; not before).
- 2910fcd7e: re-landed 04958681d on S3 (merge origin/lang, revert 4e7b53609, S3's eBorrow/eDeref/eField/eAt
  and setPlace/setPlaceOp arms). Gate quick 25/0 (needs LEAN_SYSROOT=/home/andrew-peterson/code/laniusc/
  target/claude-work/leanroot: the worktree has no leanroot). P02 66.
- Grouping of the 66 (V4 NOTES, probe/groups.txt from bin/groups.py over probe/DBGALL.{lean,out}):
  A lowering slots 36, B type sizes as numbers 7, C Mini frames/code 17, D needs 4, E program 2.
  Finding: V4 probably false at A (the evaluator's temporaries are unlimited; counterexample in NOTES).
  Waiting on the coordinator for the .lani limit before A.
- (this commit) B and E: CompileOpt.lean + COMPILE_PRE_IMPORTS (E: compile_optimized), 'w' kind (word_stride,
  element_base), str_words override + strAscii_eq_true/_false (hb_simp, CompileValues). P02 62, none new;
  baseline probe/fails.p02 = 62. Gate quick 25/0 (target/claude-work/leanroot now a symlink to the main
  checkout's). Next: A after leafA's slot limit; C/D after leafA-frame; then compile_declared.
- (this commit) after leafA-frame (938574f47): temps overrides dropped (COMPILE_FACTS val_Stmt_temps for
  compile_func), CompileNeeds.lean + needs overrides (D). P02 58, none new; baseline = 58. Gate 25/0.
  Next: C (Mini frames/code), then A once SrcEff.eval's slot check lands (after leafC's S5; slot < 2^40).
- (this commit) C part 1: counter overrides (slot_range, dying_extent, arg_slots: counter + hb ≤ K),
  Instr_encode aliased; open leaf CompileFuncSlots (+ SelfPre/CompileSlots.lean slotTop/codeSlotTop).
  P02 55, none new; baseline = 55. Gate 25/0, open graph 70 statements. Next: wire CompileFuncSlots into
  the encoders' overrides; the rest of C (round_*, Stmt_within, Code_size, layout, extents); then A.
- (this commit) C part 2: CompileFuncSlots' unchecked claims hold, but the encoders need more: new leaf
  CompileFuncSlotsV2 (slotReach counts call/ret copies by length, codeSize ≤ 2^40, nb instrs ≤ max (nb
  func) 2^40); V1 left unused. vals_compileFuncs (CompileOpt) gives codesSlack = 0 / codesNb; overrides
  carry them compile_program → link/room_after/link_fitting/link_onto → encode_onto/Instr_encode.
  codesSlack_cons_eq_zero (unfolded max/- gave kernel deep recursion). round_*: val_packRound(s);
  extents/Stmt_within aliased; val_layout for link_onto's entries. Tactic openProp: open premises
  from context. P02 55 → 40, none new; baseline = 40. Next: group A (after S5 + leafA-slots).
- Coordinator FYI for A (leafA-slots, after S5): eval_args (arg start slot), eval_let_body and eval_arm_in
  (match_dst) return None at slot ≥ eval_slot_limit() = 2^40; leafA edits CompileEvalTypes.lean's evalArgs
  nil/cons and eLet ts proofs (expect on merge). Between checks a slot grows ≤ 2^22 + nesting depth.
- (this commit) CompileFuncSlotsV2 proved: SelfPre/CompileSlotsProof.lean (reach_compileStmt,
  nb_compileStmt, zeroLocals_facts, compileFunc_slots) + Open/F14/CompileFuncSlotsV2/Proof.lean.
  Open graph 54 proved. Next: group A (after S5 + leafA-slots).
- (this commit, 11-04) group A on merged lang (602f7227b): P02 40 → 9, none new; baseline probe/fails.p02 = 9.
  SelfPre/EvalSlots.lean: SrcEff/SrcStmt.slotNest, depthMax/nestMax, scopeTop/optTop/optScopeTop (a binding's
  last slot), optSizes, slots_* lemmas (lookup, armScope, paramScope, armBodyScope, matchVariants, matchDst,
  size, getElem_variants, slotVars, packedWidth, fieldOffset, strWords) and slotsSome_* (lookup, armScope).
  pre_certs.py: 's' slot kind (slot_kind: seeds, up/down spreading within `lowering`, field indices under
  fieldOffset excluded), slot_tiers (2^58 + 2^42 per call-graph level, Tarjan SCCs), BINDING_HYPS (≤ 2^57+2^56),
  COMPILE_SLOT_LOOSE (counters bounded by hb + slot ≤ 2^63), SB/BB placeholders in overrides, Sig param sizes
  ≤ 2^40, `set_option lanius.hb.slots true` in the pres' preamble. Tactic: slots_/slotsSome_ facts (gated by
  lanius.hb.slots), addSlotFacts for a premise's own terms (+ a type split's SrcType.size), try-guarded fact
  typing, closeArith deltas nullary constants before an if split (fixed GenPC SelfP01, broken since 0a9a4a1be).
  New statement PreCompileSourceV5 (V4 + nb p ≤ M + slotNest ≤ 2^55; V4 probably false, its NOTES).
  Left (9): pick/put_element (k*size, nonlinear), array_args/array_arg_local (arg bytes sum unbounded: finding,
  V5 NOTES), array_call_sig + SrcStmt_lower (nb of scope ≤ M: Binding's nb counts its slot), SrcEff_eval
  (eLet's armScope [id] [ty] slot: second-round slot facts), lower_body + compile_declared (nb of the lowered
  program: a LowerFuncs numbers leaf). Debug files: probe/t/T*.lean (isolated theorem checks).
- 077043ea0 (11-04): array_args/array_arg_before block_limit checks (compiler.lani, approved by coordinator;
  queues after leafC's S5b+S6b: then merge origin/lang, regen, gate, report). trusted 449ff9754ce0ed32.
  ArrayCall.arrayArgs_nil; SelfNeeds imports bindingBytes (faithful_pure.py). Gate quick 26/26.
  Coordinator: keep V5's broad nb p ≤ M (leafA writes lim_nums). Next: the 8 other P02 pres.
- 1f0c5bccf + merge 1144bfb67 (local lang 0d5c1662f; coordinator merges ff-only from local lang now,
  origin push broken): P02 9 -> 4 (lower_body, SrcEff_eval, SrcStmt_lower, compile_declared). Gate 26/26.
  SrcStmt_lower blocker: letView puts Binding{ty: View(length)} in the scope, ts scope ≤ 2^22 fails
  (length bounded only by depth ≤ 2^55; lower_view's < 2^31 check runs after the body is lowered,
  eagerly). Plan: compiler.lani lower_let_view helper checking length first (no acceptance change)
  + scope ts hyps looser (≤ 2^31) -- told coordinator. Rule: every command and loop ≤ 5 min total.

## 11-04 a0250560e + merge of lang b05dd7020
- P02 4 -> 2: lower_body and compile_declared closed by the new open leaf LowerSlotsSmall
  (Open/F14/LowerSlotsSmall; SelfPre/LowerSlots: lowered_body via COMPILE_FACTS, val_lowerFuncs;
  compile_lowered a fixed root; extent overrides; valueFacts term branch passes open leaves).
- Left: pre_step_SrcEff_eval, pre_step_SrcStmt_lower: wait on leafB-lv 7affee0ff (then loosen the
  scope ts hyp to 2^31 and drop eval_str's offset nb hyp). Then assemble PreCompileSourceV5
  (now also reduces from LowerSlotsSmall).
- Merged lang: regen 0 changed, lv build ok (wall clock inflated by a laptop suspend), gate 27/27.
