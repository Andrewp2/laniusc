# leafC resume (verified compiler, F5 Core leaves)
Worktree /home/andrew-peterson/code/laniusc-wt/leafC, branch leafC (from origin/lang a54edae54). Never push.
Worktree target/: release -> main target/release, claude-work/bin -> main bin (needed by gate.py).
## Done (all six assigned)
- 6a6e62c98 CorePlace. 9230df44b CoreRead + CoreBorrow (red1 from CorePlace).
- 2a5198eee CoreAssign + CoreAssignOp (red1s from CorePlace). Helpers: formal/Lanius/Mini/Refs/CoreLemmas.lean.
- 86ac71ab8 HomesCongr false (static region not kept; counterexample in its NOTES.md); HomesCongrV2 stated + proved.
## Open follow-up
- RefsLemmas conjoins HomesCongr, so it is false; needs RefsLemmasV2 using HomesCongrV2 (leafA/coordinator).
- 517592ab7 RefsLemmasV2 (RefStoreV2 + HomesCongrV2) + Red1. e20c62771 HomesFrame/Leave/Push proved.
- Next: HomesLend (claimed), then FrameCorrHomes.
- c4425bbed HomesLend; 640b761cc merge of lang (RefStoreV2 proof); 3rd: FrameCorrHomes proved (see git log).
- All assigned work done. RefsLemmasV2 waits only on PlaceAddr, PlaceAddrTraps (leafA).

## F5 stage 1 plan (11-03, coordinator's job)
Constraint: compileSource_correct covers every program compile_source accepts, so the lowering of
reference forms stays rejected (none) in compile_source until stage 2 proves it; lowering code is
written and tested through an ungated entry (compile_source_refs) meanwhile. `&self` stays by value
(point 10 waits for the ungating, else existing &self programs would stop compiling).
Steps (each: extract, regen certs, LaniusMini + top modules build, gate quick incl. extract,
self-current, frontend-cases, trusted; merge origin/lang before commit):
- S1 SrcType.Ref(Box<SrcType>) in compiler.lani: size 1, `same`, every SrcType match gets an arm
  (rejecting in lowering). Lean: .ref arms everywhere; Refs/Model defs get .ref arms. Trusted: SrcType.ref.
- S2 trusted layout: move Access/accessKind/words/slotAt/refSlotAt/sub/subStep/RefTo/RefHeld before
  HoldsAt (new trusted module or Source.lean); HoldsAt.ref via RefHeld; HoldsAt.borrowed generalized
  (homes' sub-places, any element); Addressed.pointer native. TRUSTED_BASE entries.
- S3 Source forms: SrcPlace (local/deref param/field/index), SrcEff EBorrow/EDeref/EPlace read,
  SrcStmt assign (set/op) to a place; toCore; Typing PlaceHasType.deref + checkPlaceAnyFuel; lowering none.
- S4 stage-2 top statement as an open statement (compile_source_refs correct), in the graph.
- S5 front end: &T/&mut T params, &x/&mut x/&x.f/&x[i], *r, auto-deref of ref params in field/index
  reads and writes; lifetime check rejects ref results/lets/fields/elements, ref param reassignment,
  refs to refs, borrows of temporaries. frontend_cases for each.
- S6 lowering (ungated entry): homes in frame blocks (frame_block/funcNeeds), RPlace code (base,
  index, bounds check), loadSlots/storeSlots, ref args; a difftest of compile_source_refs vs Core.
## Stage 1 state
- S1: starting.
- 11-03: ff to origin/lang ea0290c8c (leafA stage 2 leaves: HomedCorr etc. in Refs/Homed.lean; RefsLemmasV2 proved). Note: a 'let gives its local a home' leaf may be needed by my top statement. S1 in progress (uncommitted): Ref in both .lani, extracted; fixing Lean.
- 11-03: S1 committed de639783f (merge with lang; Gen/GenB/TS regen; hb_gen --slots template gained ref). S2 committed 648682f08 (Mini/Layout.lean trusted; HoldsAt.ref; pointer native). Coordinator: generalized borrowed deferred to Homes step (approved). Wait for coordinator's word (leafA frontend.lani untyped_rejected change) and merge origin/lang before S3's .lani edits. S3 Lean-only part first: PlaceHasType.deref + checkPlaceAnyFuel (Lanius/Typing.lean, Typing/Check/Expressions.lean). leafA spec: target/claude-work/leafA/lowering-spec.md (RPlace home/deref/field/index; index is SrcEff-like Core expr that keeps state).
- Build helpers: blloop.sh TARGETS (reruns bl.sh till done); gate targets list in gate.py build().
- 11-03: S3 typing committed b762c0e93 (PlaceHasType.deref + checker; hash 07a55955abaf2624). Rest of S3 waits for coordinator's go (leafA + f6v frontend.lani commits). Then: merge origin/lang; run s3/s3lani.py lani/mini/compiler.lani and s3/s3front.py lani/mini/frontend.lani (from formal/); extract; SourceCore: new trusted `exprPlace : Core.Expr → Core.Place` (exhaustive: local→local, field/index→of place, dereference r→deref r, else deref e); toCore eBorrow ty p = .borrow ty.toCore (exprPlace p.toCore); eDeref _ r = .dereference r.toCore; eField b f = .field b.toCore f; eAt b i = .index b.toCore i.toCore; assign p v = .expression (.assign .set (exprPlace p.toCore) v.toCore); assignOp op p v with SrcAssignOp.toCore (AAdd→add ... AShr→shiftRight). Then fix Lean arms, regen certs, gate, commit. S4: add compile_source_refs (same pipeline) + open statement CompileSourceRefsCorrect (compileSource_correct's shape).
- 11-03: coordinator approved S3 design. exprPlace drafted + checked: s3/exprPlace.lean (exhaustive over all 30 Core.Expr ctors, goes in SourceCore.lean namespace Lanius.Mini). TRUSTED_BASE must say why fallback harmless: PlaceHasType.deref types `.deref e` only if e : reference (then it is that reference's place); otherwise Core typing rejects it, and stage 1's compiler rejects all forms. S4 draft checked: s4/Stmt.lean (CompileSourceRefsCorrect, compileSource_correct's shape with compileSourceRefs; Try.lean proves the compileSource version). Waiting for coordinator: frontend.lani commits landed -> do S3 .lani + S4.
- 11-03: coordinator: NO compile_source_refs, no refs field in SrcDecls. S4 committed 86e698363: Open/F5/SourceRefsCorrect (compileSource, places=[]), proved by compileSource_correct. S6: extend compileSource_correct's proof with F5 leaves, else temporary untrusted decidable `noRefs p` hypothesis (TRUSTED_BASE temporary; self program by decide), SourceRefsCorrect left open. Still waiting for go on .lani (S3 rest).
- 11-03: leafC fast-forwarded to lang 640385095 (S1-S4 all on lang). Use formal/tools/regen.py (and --resolve after merges; README "Merging without conflicts") instead of my regen_gen/budget/hb commands. Note: regen.py on clean lang tip rewrote GenPC/SelfP01.lean (+24 lines, "not added: SelfP02.lean") — reverted, told coordinator. Waiting: leafA's front-end check lands, then coordinator says go for S3 .lani.
- 11-03: coordinator: leafB fixes GenPC/regen.py mismatch; until then revert GenPC after each regen.py run.
- 11-03: GenPC fixed on lang (99a42c43f); stop reverting GenPC.
- S3: extract compiler AND frontend in ONE lani_extract run (extract exe depends on Frontend parts). Renamed Assign→SetPlace (Mini Stmt has Assign).
- 11-03: S3 in progress (uncommitted in worktree): .lani + extract done; SourceCore exprPlace/SrcAssignOp.toCore/toCore arms; Grows.lean (PlaceGrows, evalPlace_grows, assign_op_grows_eff, exprPlace_grows, new eff/stmt cases) and TypeSound arms build; Pure/Cost arms none/true/[]. TRUSTED_BASE entry draft: s3/tb_entry.txt (prepend before "The change before (11-03, leafA, giving 6f0e7f37780ae7cf"). Next: LaniusMini build loop, then rest of libs, regen.py, hash, ROADMAP F5 row, gate, commit, report. Coordinator design points (stage2-plan sec 8): Binding.home, homed reads only in statements, slice-return rule, S6a/b/c with leafA P2/P3/P4.
- 11-03: S3 committed fad538859 + merge of origin/lang 934cd5fae (hash 793d1e4339a7c10d, quick gate 25/25). Also touched: tools/frontend_difftest.py (Lean prelude arms), tools/term_gen.lean, SelfFaithful RepList 37->38, Safe/Grows trap lemmas (PlaceGrowsT etc.). Next: S5 (reading + lifetime check), S6a-c per coordinator design points.
- 11-03: S3 merged+pushed (5f3bf3734). Coordinator: narrow S5 approved (Lanius has no &x/*r; refs only from &self receivers or ref-returning fns; probes in leafC/s5probe, p4 returned 76). SEMANTIC_DECISIONS gained "S5 in Lanius's syntax" + "S5b: point 10" (uncommitted, after "When it is proved, point 10 lands."). Asked coordinator: S5b reading land with S6b or first.
  S5 plan (on branch; do NOT merge origin/lang until coordinator says leafA-frame landed):
  1. frontend.lani: Ty gains TyRef(Box<Ty>) (extracted Frontend/Types); ty_of reads type_ref/type_ref_mut ONLY for params (param type reading), lower_ty TyRef -> SrcType Ref; MEff gains XBorrow?/XDeref/XField/XAt? and MStmt mSetPlace/mSetPlaceOp; field/index reads of a ref param p -> XField(XDeref(XPure local p)); writes p.f = v / op= / p.f[i] = v -> MSetPlace; p passed at a same-ref param -> XPure(local p).
  2. Lean: TyR stays (no ref); new param-type relation; LowerR.ref; Effs/Stmts relations + soundness + Det; Close (EffClosed/StmtClosed new cases).
  3. lifetime check (untyped_rejected-like): reject reassigned ref params, whole uses of p other than same-ref args, method calls on p, inferred lets of ref types.
  Grammar: type_expr [type_ref] -> 'TypeAmpersand' type_expr; [type_ref_mut] -> 'TypeAmpersandMut' 'Mut' type_expr. frontend.lani ty_of at ~2625, lower_ty ~2950, params reading ~11177-11310.
- 11-03 S5 (narrow) in progress, uncommitted in worktree (do NOT merge origin/lang until coordinator says leafA-frame landed):
  frontend.lani edited via s5/s5ty.py + s5/s5front.py (+ manual moves: field_ty_at/field_ty_of/elem_ty_of before eff_ty;
  ref_ty/param_ty_of before params_of; refs filter fns ordered callee-first; extractor needs def-before-use in source order).
  Ty.TyRef, MEff XDeref/XPlaceField/XPlaceAt, MStmt MSetPlace/MSetPlaceOp; param_ty_of; field_value/field_of_ty (referent_or);
  eff_step XPlaceAt; assign_target/compound_eval ref branches (set_place_of/set_place_op_of, has_ty(eff_ty) required);
  refs_checked filter in read_fn (tree walk ref_uses_ok; not in relations).
  Re-extract recipe if Frontend Lean is broken: git checkout formal/Lanius/Mini/Frontend{.lean,/}, rm untracked P files, regen --only extract.
  Lean edited: Reading/{Lower,Close,Calls(FieldTyAt moved here, EffTy deref/placeField/placeAt),Effs(EffChain.field referentOr, .at),
  Stmts(AssignTargetR.place, indexEval +isRefTy false, CompoundR.placeEval),Funcs(ParamTyR, refsChecked_some),Prods(pTypeRef 285/Mut 324)},
  Det/{Lower,Close,EffParts,Effs,Stmts,Program}. Next: build LaniusMini etc, fix arms, regen all, TB entry, frontend_cases rejects, gate.

## 11-03 ~19:45: coordinator says leafA-frame landed (938574f47). Plan: S5 full build (s5/full.log) -> commit S5 ->
git merge origin/lang -> regen.py --resolve (all stages) -> build -> regen --trusted -> TRUSTED_BASE entry (s5/tb_entry.txt,
on top of leafA's paragraph) -> ref_param expect.out (has compile_rejects) -> quick gate -> commit merge -> report main.

## 11-03 ~21:00 S5 merged (129ebe82a merge commit, S5 commit 9eb2b452a); fixing budget certs (SelfBProof73 omega on
lazy && with costed right side followed by more stmts). Fix: ref_target helper (one-return fn) + set_place_of/_op_of take
target and match eff_of themselves. Det/Agree chain_member got `at` arm + referentOr. Det/Effs + Det/Stmts imports added.
NEW SPLIT (coordinator): leafA takes S6a whole. After S5 lands I do S5b reading (receivers as borrows) + S6b lowering
(borrows, deref loads/stores, places); leafA does P3 proofs. Prepare S5b+S6b on a branch after S5 lands.

## 11-03 S5 DONE: (final merge with 4ec7e3af0 at top of git log) 0ac84e412 on leafC (merge of origin/lang 72df86e5e), hash 8383ab6c600c2220, quick gate 26/26.
Point 3 (ref param passed whole) moved to S5b (needs MatchTy/fitTy ref patterns + Det). Lexer got mutKeyword (203).
Next: S5b reading (receivers as borrows + point 3) and S6b lowering (borrows, deref loads/stores, places) on a new branch;
leafA does S6a and P3. Transient lake error "failed to read Subarray.olean.private: unreachable" -> just rerun.

## S5b on branch leafC-s5b (from lang 6163ae1f2)
- step 1 committed: point 3 (ref param passed whole): match_ty/fit_ty ref patterns, param_ty_list in param_expects,
  arg_expected via param_ty_of; Lean MatchTy.ref/refMut, ParamTyR moved to Reading/Types.lean, paramTyR_unique to Det/EffParts.
  Not yet regen'd/gated. Debug harness: s5/bis/dbg.lean (readFn pieces), s5/bis/cases (variants).
- next: &self as reference (self param TyRef, drop writes_local), method receivers as XBorrow, home rules; S6b after leafA-slots.
- lowering spec: target/claude-work/leafA/lowering-spec.md (RPlace home/deref/field/index; index must be state-pure).
- step 2 IN PROGRESS (uncommitted, lani done + extracted; Lean relations TODO): &self/&mut self = TyRef(impl type)
  (self_param_ty, p_param_self_ref_mut=325 kid2 token, pattern_of), read_fn drops ref_checked, filter: primary_names
  (self ok), names_field_base allows method receivers, arg_names; MEff XBorrow(Ty, Box<MEff>) (arms via s5b/front.py);
  receivers: eff_found_with -> eff_bound_recv(receivers_of(fd, pre)); receiver_of(self_by_ref(fd), t, x): ref->pass,
  by_ref->borrow_of(t, place_of(x)), by-value on ref -> None; method lookup on referent_or.
  Lean TODO: Prods pParamSelfRefMut; EffTy.borrow; EffClosed.borrow; Receivers rel (nil | one: EffTy a t ->
  receiverOf (selfByRef fd) t a = some r); EffChain.method/EffR.method: MethodFor on referentOr, Receivers -> EffInfer pre';
  effFoundWith spec + sound; PatternOf.selfRefMut; ParamsR.cons prod list + SelfParamTyR; readFn_sound drop refChecked;
  Det for all. Then frontend cases (try_method, reject_self_write change), regen, gate.
- 11-04: S5b step 2 Reading + Det build (receivers_unique in Det/Effs, selfParamTyR_unique in Det/Program). Coordinator: leafA-slots landed; queue regen(module headers) -> leafA S6a-2 (Binding.home) -> me. My merge must follow S6a-2. New F5 proof files need module headers (OPEN_STATEMENTS.md after regen lands). Next: regen stages, frontend cases, LaniusMini+gate targets, gate, commit.
- 11-04 ~03:00: S5b step 2 regen+build; fixed self-host (frontend.lani place_of: SrcExpr::Char/Float qualified, laniusc ambiguity). expect.out for self_ref_method (new), self_write (was reject_self_write), try_method (compiles->compile_rejects). TRUSTED_BASE entry written (hash 0a6475e07ff0859d; recheck after rebuild). Next: gate pass -> commit S5b -> merge origin/lang (S6a-2 c896a1b6c + regen) -> S6b.
- S6b shapes agreed with leafA in target/claude-work/leafA/lowering-spec.md (sections S6b, leafC answer, leafA reply home_init, S6c + leafC answers). compiler.lani twins needed: words, slot_at, ref_slot_at, sub_step, element_addr, loads/stores, home_ok, tags_fit, home_init (Lean: Mini/Layout.lean, Mini/Homes.lean, Refs/Model.lean RPlace.code, Refs/Store.lean homeInit).
- S6b compiler.lani plan: (A) home uses = slice_uses + borrow bases; decl_bytes 8*words when homed. (B) let/param home = Some(stack offset) when in body uses; check offset+8*words<=block, home_ok, tags_fit. (C) block>0: frame in slot count, body from count+1, entry stores for homed params. (D) leaf checks b.home==None in lower_scalar_local/lower_field_of/eval_copy/set paths. (E) eval twins for pure stmts reading homes; ePure structural lift. (F) place code (home/deref/field/index), EBorrow/EDeref/EField/EAt, SetPlace/SetPlaceOp; Set/SetField on homed via setPlace shape. (G) array_arg_local homed: frame+off, no copies, drop Frame pair. (H) lower_func 8a: homes && ret has slice/ref -> None.
- 11-04 ~04:10: merge of local lang 07bb5c4a3 into leafC-s5b: regen --resolve rc=0 (staged); gate-target build running (s5b/build6.log). TRUSTED_BASE has HASHX placeholder -> replace after `regen.py --only trusted --trusted`. Then gate, commit, send hash to main.
- S6b: s6b/apply.py applies drafts (layout/homes/stmts.lani) to a copy of lang compiler.lani; order check clean (order.py in scratchpad). slice_uses block moved before SrcStmt.lower; unhomed before lookup; array_words/enum_slot_at/array_slot_at/expr_roots reordered in drafts.
- 11-04 ~05:15: coordinator stopped multi-round builds (rule: no blloop rounds until regen's per-function modules land). Committed merge 315e4330d (leafC-s5b, contains lang 07bb5c4a3, trusted 0f6a55aee2f2995d). Unbuilt: Lanius.Faithful.SelfBounded, Lanius.Faithful.SelfPre, LaniusOpen; quick gate not run. Waiting on coordinator (supervised build or wait for regen fix). S6b apply.py ready but NOT applied (needs builds).
- 11-04 ~05:30: coordinator decision: wait for regen's per-function extraction; then merge lang (with leafA-lims + regen) into leafC-s5b and build once. S6b on branch leafC-s6b = 5e23d48fa (on 315e4330d); checked only lani_extract + `lake build Lanius.Mini.Compiler` + lcheck Semantics/Source. Renames to avoid Lean clashes: MemAccess, lay_*, place_op_of, frame_body_start, expr_home_place, store_place(_op); lookup = any, lookup_slot = unhomed. Note appended to leafA/lowering-spec.md. apply.py regenerates S6b from lang's compiler.lani (rebase: rerun on new compiler.lani).
- 11-04 ~05:50: S6c on leafC-s6c 3ad0fb287 (on leafC-s6b 417fceb72 = S6b + frontend re-extract + import fix). s6c/apply.py (same Ref, eval_lent, stmt_eval=eval); s6c/sync.sh (extract compiler+frontend with built extractor via lx_nobuild.py, drop missing imports); s6c/fix_imports.py BASE (replace imports of vanished parts). Spec note appended. Still waiting for regen.

## STATE AT PAUSE (11-04 ~17:10, coordinator paused agents: usage 80%, resume after Saturday 9pm reset)

The worktree /home/andrew-peterson/code/laniusc-wt/leafC is clean, on branch leafC-same. No processes are running.

### Branches (all local, none pushed)
- **leafC-s5b = 315e4330d**: S5b merged with lang 07bb5c4a3, trusted 0f6a55aee2f2995d.
  - Unbuilt: Lanius.Faithful.SelfBounded, SelfPre, LaniusOpen. Quick gate not run.
  - Coordinator decision: after regen's per-function extraction lands on lang, merge local lang into leafC-s5b, run `lv regen`, build once (`lv build`), gate (`lv gate`), then report the commit. It must contain lang (ff-only rule).
- **leafC-s6b = 417fceb72** (5e23d48fa S6b plus a fix: frontend re-extracted, and hand imports of the vanished parts SrcType_same and elementBase pointed at SrcType_uintKind and subField). leafA merged it into leafA-p3b (50c7cfdfb).
- **leafC-s6c = 3ad0fb287** (on s6b): `same` on Ref compares referents, `eval_lent` (ArraySlice eval arm: frame+offset plus length, homed i32/u8 arrays only), `stmt_eval` = eval.
  - Checked: lani_extract, `lv build Lanius.Mini.Compiler`, lv check of Semantics and Source.
- **leafC-same = fa774c886** (on leafA-p3b 17f203cc4): ref cases of eq_of_same (SliceLayout), same_cases (LowerExpr, new disjunct, use at equality_holds updated) and same_toCore (TypeSound).
  - same_nv and same_nv_left need no change.
  - Checked against S6c's compiler in the worktree: LowerExpr and SliceLayout build. TypeSound not built (LowerStmt has leafA's S6b errors). Coordinator wants it on top of leafA-p3b, with only these files.

### TODO when resumed
1. **NOT STARTED (coordinator asked):**
   - On leafC-s6c: make `SrcType.declare (.ref referent)` accept references; declare the referent if the layout needs it (see the declare fn in compiler.lani, `Ref(referent) -> None` arms around lines 2995-3250). leafA adds TypeDeclared.ref in TypeSound.
   - Also add a frontend case that COMPILES (no compile_rejects): a fn taking `&mut S` of a struct and writing a field through it, plus a caller. Use `&self`-style or a ref param per S5 syntax (refs come only from &self receivers or ref params; there is no `&x` expression). expect.out from laniusc. Put it under formal/tools/frontend_cases/<name>/.
2. Tell leafA (in lowering-spec.md) that same_cases' statement gained a disjunct (only its use in LowerExpr is updated).
3. Then the s5b merge and build once regen lands; then rebase S6b/S6c onto the new lang. Rerun s6b/apply.py and s6c/apply.py on the new compiler.lani, or merge.

### Tools (target/claude-work/leafC/)
- **s6b/apply.py**: applies S6b to lang's compiler.lani.
- **s6c/apply.py**: applies S6c on top of S6b.
- **s6c/sync.sh**: extracts compiler and frontend with the built extractor (lx_nobuild.py), runs fix_imports, then drops missing imports. Run `fix_imports`/`follow_imports` BEFORE any drop.
- **s6c/follow_imports.py BASE**: for hand files, adds imports of the parts that now hold the definitions an imported part held at BASE.
- **s6b/parsepos.py FILE.lani**: CPU parse; prints the line of a parse failure.
- **scratchpad order.py**: checks definition-before-use order of new functions (lost on reboot; easy to rewrite).
- **Pitfalls found:**
  - Lean keyword names (`at`).
  - Inline params must be prefixed (clash check).
  - Function names that camelCase to a constructor (set_place clashed with SrcStmt.setPlace).
  - Names already in leafA's Lean spec (Access, addOff, ...).
  - Callee defined after caller.
