# leafA resume notes

Worktree /home/andrew-peterson/code/laniusc-wt/leafA, branch leafA (from origin/lang 61e755d92).
Task: prove F14 open leaves ReadFilesHeight, ValidateFilesHeight, PostFrontEndWords (claimed, --agent leafA).
Coordinator merges/pushes; never push.

## State
- [x] ReadFilesHeight proved 0580b151f
- [x] ValidateFilesHeight proved 999f0ca38
- [x] PostFrontEndWords proved (HEAD)
- [x] quick gate passed (25 steps, 0 failed); LaniusOpen builds; claims released. Done, reported.
- worktree target/: release, claude-work/bin, claude-work/cache symlinked to main checkout (gate needs them)

## 11-03 next task: PostCompileSource
- Merged origin/lang (1271fc07b, fast-forward). Claim attempt: still held by leafB.
- Finding: a dry run of pre_certs.py with root compile_source (into scratchpad, repo untouched)
  emits `post_compile_source` with exactly PostCompileSource's type (367 post groups behind it:
  the whole compiler). A hand post would duplicate leafB's GenPC; once GenPC lands, Proof.lean is
  `theorem Lanius.Open.PostCompileSource.proof : Lanius.Open.PostCompileSource := post_compile_source`
  (import the GenPC module holding it). Asked coordinator; waiting.

## F5 references: design and statement graph (11-03)
- PostCompileSource was never claimed by leafA (leafB held it); cancelled, nothing to release.
- Design note: formal/SEMANTIC_DECISIONS.md "References: the memory model (decided 11-03, F5)".
- Model (untrusted defs): formal/Lanius/Mini/Refs/Model.lean (Homes, RefTo/RefAt, SrcType.sub, refView,
  loadSlots/storeSlots, RPlace/RCtx/code/Resolves/Bad, RefsAgree). Names Agree/localValue clashed; renamed.
- Graph: formal/Lanius/Open/F5/: root RefsCorrect (Red1 = conjunction) + 12 leaves:
  RefLoad RefStore PlaceAddr PlaceAddrTraps CorePlace CoreRead CoreAssign CoreBorrow
  HomesPush HomesFrame HomesLeave HomesCongr. Statements only; nothing proved.
- Next: stop and report to coordinator; trusted-base delta to be audited separately.
- 11-03 later: lang renamed SrcType_size→SrcType_same, added str, HoldsAt takes sx. F5 recommitted as one
  commit 6cfcbf202 on origin/lang (old 9ff27a134 dropped: open_graph's unchanged check). Sent to coordinator.
- Now proving Mini leaves: RefLoad, RefStore, PlaceAddr, PlaceAddrTraps (claimed).

## 11-03: F5 revision committed (aeaafd272 on origin/lang 2fc31d7e9)
- One commit: SEMANTIC_DECISIONS F5 section, Mini/Refs/Model.lean (NativeLayout homes, age order, RefHeld, RPlace with pure index), Open/F5 with 15 leaves + root RefsLemmas (RefsCorrect gone).
- Old RefLoad proof and Lemmas.lean (old layout) dropped from the commit; saved in f5-old/ to adapt. Revision backup in f5-rev/.
- LaniusOpen builds (1676 jobs); open_graph check 0 problems; quick gate 25 steps, 0 failed.
- NEXT: wait for the reviewer's check of the revision, then re-prove RefLoad (then RefStore, PlaceAddr, PlaceAddrTraps), all still claimed by leafA.

## 11-03: review fixes folded in (8775794a1 on origin/lang 73c2bcc63; replaces aeaafd272)
- Index order = Core's: RPlace.index carries the index's code, run right after the base's code; Indexed -> IndexRuns (simulation hyp over scratch slots); Bad -> Traps (index's own trap + negative + beyond, with reason/state).
- slotAt native widths (widthOf; enum tag m32; payload widths must agree: variantsAgree in homeOk/uniform); refSlotAt = one byte for u8 referents; loadsFrom/storesFrom use refSlotAt; span by refSlotAt.
- Homes.statics added. Note: Addressed.pointer redefinition in the trusted delta; lifetime rule covers borrowed slices stored in homes.
- Build/open check/quick gate all pass. NEXT: wait for coordinator merge, then re-prove RefLoad (old lemmas in f5-old/ need width changes).
- 11-03: checked-trap limit (undefinedTrap r = false) in IndexRuns + PlaceAddrTraps, .slice widths comment; amended -> 4680df32c on origin/lang 46ed7558f.

## 11-03 status
- 1e7e3aa1b: RefStore false (enum with 2^32+1 variants); RefStoreV2 statement + SrcType.tagsFit in Model. Reported.
- 320514aa4: RefStoreV2 proved (Refs/Store.lean helpers). Reported.
- leafC owns RefsLemmasV2 (uses RefStoreV2 + HomesCongrV2), Homes* leaves, FrameCorrHomes, Core* leaves. I dropped my RefsLemmasV2 draft.
- Next: PlaceAddr, then PlaceAddrTraps. Merge origin/lang before each commit.
- d904f69f3 PlaceAddr (Refs/Place.lean: RPlace.addr_exec, traps_stop), 697d38548 PlaceAddrTraps. Reported. All my F5 leaves done; awaiting next assignment.
- c5f102995 RefsLemmasV2 assembled. ea0290c8c stage 2 statements (Refs/Homed.lean HomedCorr; BorrowRefHeld, CallRefsAgree, HomedCorrOfCorr, HomedCorrLocal, HomedCorrKeeps, AssignAfterRhs). Proofs commit next (Refs/HomedLemmas.lean). Not covered: let pushing a homed binding (HomesPush + HomedCorr push).
- 704135493 statements (Value.Names; HomedCorrPush, HomedCorrPopHome, HomesPopHome, HoldsAtDropHomes), then proofs commit. Not covered: plain (unhomed) let push/pop inside HomedCorr.
- 4b1bf403c plain let statements, then proofs commit. Asked main which part of stage 1 I can take.

## 11-03 machine side done
- f154fda47 states RefCodeWithin and RefCodeRuns; the proofs commit follows it (MachineLemmas.lean). Gate quick passed, open graph 52/36.
- Spec note for leafC: target/claude-work/leafA/lowering-spec.md
- Next: wait for S1/S2 on lang (don't edit Refs/Lemmas.lean or Refs/Store.lean before then). Then item 3 (.ref / HoldsAt.ref arms), then item 1 (lowering = shapes), then the return wrapper.
- S1 (de639783f) merged: it added all .ref arms in my files itself; LaniusOpen builds. HoldsAt.ref waits for S2.
- Item 1 vs spec: PlaceLoad stated 93bf84754, proved next commit (the deref-load shape = PlaceAddr + RefLoad). Borrow = BorrowRefHeld, store = AssignAfterRhs. Remaining for item 1: equality with leafC's real lowering once compiler.lani emits it.

## 11-03 front-end limits check (committed on leafA, waiting for f6v)
- b3ddf6e08 states FrontEndStmtDepthV2; db44e68c3 adds the check + proofs (SelfPre/Limits.lean, Red4, docs, hash ff0b6700416a975f).
- Quick gate: 25 steps all pass at 11239b11e. Gate must run via `bin/leanslot python3 -I formal/tools/gate.py` (leanroot).
- NEXT: when main says f6v has landed: merge origin/lang, re-extract frontend, regen_gen.py regen (+ term via leanslot),
  budget_certs.py, pre_certs.py, build LaniusMini LaniusOpen, update the TRUSTED_BASE hash, run the quick gate, report.
- Then: the HoldsAt.ref cases (Place/Homed*/Machine*), the return wrapper.

## 11-03 branch leafA-ref (from origin/lang e60025697): HoldsAt.ref cases + return wrapper
- d812dcd0a statements, 37c305bae proofs: HomedCorrPushHeld, CallRefsHeld, BorrowHoldsAt, HomedCorrReturn;
  SrcType.HoldsAt.reference in Refs/HomedLemmas.lean. Quick gate 25/25, open 59/42.
- leafC's S2 had already added every .ref arm in my files; nothing else needed for exhaustive matches.
- Afterwards: `git switch leafA` for the f6v re-merge when main says.

## 11-03 re-merge done (leafA at 1403ca5d5 on origin/lang 640385095)
- b37589c4c merge of f6v (dca8f216b) + lim_param_slots; 2b263b145 states FrontEndParamSlots; 1403ca5d5 merge
  640385095 (regen.py --resolve) + FrontEndParamSlots proof. Hash 6f0e7f37780ae7cf. Quick gate 25/25, open 63/45.
- New procedure: formal/tools/README.md (merge drivers configured; regen.py --resolve; regen.py --only trusted --trusted).
- Open question to main: frame_block (sum of arrayBytes over every let) is not bounded by any check.

## 11-03 late: decisions doc + frame_block check
- leafA 5f7f1dcd4: SEMANTIC_DECISIONS "Stage 2's design points" (coordinator's 8a-c decisions + 8d). Reported.
- Branch leafA-frame (from origin/lang d1a92bf8a/4d15027d3): aa20e2dea frame_block room check
  (compiler.lani params_room/block_room/block_limit=2^31-1, block 2^31 when over), Mini/FrameRoom.lean
  (frameBlock_eq, frameBlock_le, compileSource_unchecked), faithful_pure.py SelfNeeds imports compileArgs,
  hash 35dc6691985d71c6. Build + quick gate pass. Reported.
- WAIT: do not merge lang into leafA-frame until coordinator says leafC's S3 landed; then merge,
  regen.py (--resolve), build, hash, gate, report.
- Then/meanwhile: P1 proofs (six F5 statements from 4d15027d3) on leafA.
- leafA-frame ef2e15377: needs saturated (need_limit 2^40, need_capped sticky, need_round_at, lower_func
  rejects need at limit); compileSource_unchecked = if NeedsBelow then old else none. Hash 329cf49b61666582.
  Build + gate pass. Reported. Still WAIT for S3 before merging lang.
- leafA: HoldsAtNamesPlaces/Proof.lean written (untracked, checks with lcheck); P1 next: KeepsConsAbove,
  HomedCorrToCorr, HomedCorrEnvCongr, HomedCorrCellsCongr (template HomedCorr.keeps), HomedCorrAssignPlain.
- leafA d78cba990: P1 six statements proved; gate passes; reported. Next: wait for S3 (then merge lang into
  leafA-frame, regen --resolve, build, hash, gate, report); P2-P6 after leafC's S6.

## 11-03 late (after F14 leaves)
- leafA 7e94787b6 PreBinaryWordsV3 proved; 934cd5fae OptimizeKeepsNumbers proved (merged to lang, 53/69).
- LowerFuncsTemps: superseded by compile_func reorder (coordinator approved), claim released.
- leafA-frame now: b03f1f367 reorder (Room.lean temps_le_weight, compileFunc_checksLast, SEM_DEC section),
  971fe2f53 merge lang 5f3bf3734 (S3; setPlace cases in block_room/FrameRoom; hash 22cfeaed626f1154),
  938574f47 merge lang 628b71648. Built, gated, reported. Worktree laniusc-wt/leafA is ON leafA-frame now.
- Merge trick: if extractor fails on stale ours-side generated Compiler parts, `git checkout origin/lang --`
  those parts + Compiler.lean, delete our-only parts, then regen --only extract recreates them.
- NEXT: slot limit (V4 false for evalArgs slots, leafB2 NOTES on lang 891126cf2). Asked coordinator to pick:
  1 dynamic check in SrcEff.eval + full unchecked-copy proof (big), 2 dynamic + prose, 3 static eff_fits in
  lower_func + small FrameRoom-style proof. Wait for answer.
- leafA-slots 0a9a4a1be: eval_slot_limit 2^40 checked in eval_args/eval_let_body/eval_arm_in (approved); lands after S5
  (merge lang, regen, build, hash, gate). Proof fix pattern: `split at h; · simp at h` before old splits.
- leafA-p2 (from lang e42dc6727): Refs/HomedSound.lean: RCtx.ofScope (homes []), Corr.refsAgree, Corr.homed,
  HomedCorr.plain, HMatches, HSimulates, StmtSoundH/EvalSoundH (+ .homed/.plain both ways), sound_both_homed.
  FrameCorr stays until S6a (Homes switch goes with lending without copy). Worktree is on leafA-p2.

## S6a-1 (11-03): done on leafA-s6a, 947ac021e + merge 4ec7e3af0 (origin/lang 72df86e5e)
- Mini/Homes.lean (Homes + layout defs moved from Refs/Model), Mini/LentHomes.lean (Lent, LentHomes,
  FrameCorr's API under same names, words-based via Addressed.Within). FrameCorr keeps only its structure.
- Simulation renamed FrameCorr -> LentHomes; ArrayCall.lend rewritten (indexed_append/indexed_of_pairwise);
  restrict -> LentHomes.drop. Build + quick gate green. Reported to main.
- Next: S6a-2 (Binding.home None) on leafA-slots after S5; then P3 / S6b proof cases.

## leafA-slots round (11-03): 602f7227b (merge of lang 6163ae1f2 = S5, regen, hash 1ab522a8e6fc9323), gate green, reported.
- S6a-2 NOT in it: Binding.home breaks anonymous ⟨id, next, ty⟩ in 5 immutable statements (HomedCorrPush,
  PushPlain, PushHeld, PopHome, PopPlain Stmt.lean). Asked coordinator for option B (V2 statements). Hand fixes
  needed when it goes in: Guard.lean (letStr_lower_inv ⟨pointer, next, .ptr⟩ and :475), TypeSound:669,
  SelfPre/CompileTypes:573, plus the ⟨..⟩ :: scope sites (grep "⟩ :: scope" in Mini).

## S6a-2 round (11-04): branch leafA-home, c896a1b6c on lang 602f7227b. Built, gate 26/26, hash unchanged.
- Binding.home None x16; 5 statements -> V2 (any home); HomedLemmas generalized {home}; OPEN_STATEMENTS rule.
- RCtx.ofScope keeps homes := [] (decision in SEMANTIC_DECISIONS S6a-2 Done note).
- WAITING: coordinator says when regen has landed -> merge origin/lang, (regen if needed), build, gate, report.

## P3 (11-04): branch leafA-p3 from lang c896a1b6c (S6a-2 merged+pushed by coordinator).
- lowering-spec.md gained section "S6b" (shapes P3 needs); sent to main for leafC (leafC not reachable directly).
- 1st commit: scopeHomes + scopeHomes_lookup + scopeHomes_none in Refs/HomedSound.lean (not yet wired into ofScope).
- Plan: wait for leafC's confirmation of shapes (esp. pure homed reads = None, homed let shape, frame slot = count),
  then: ofScope homes := scopeHomes; StmtSoundH/EvalSoundH as the real induction (case moves, section 4 of
  stage2-plan); new cases (section 3). Merge origin/lang when regen and S5b+S6b land.

## 11-04 (after compaction)
- 39527a8fe (leafA-p3): PlaceLoadHeld, HomedLetStore, HomeLendArgs proved; SrcType.homeInit (+ _size,
  _refSlotAt) at the end of Mini/Refs/Store.lean. Stmt files in regen's module format; Proofs plain until
  regen lands (they import non-module Open proofs). Gate quick 26/26. Reported to main.
- leafC accepted home_init. S6c draft appended to lowering-spec.md (entry stores, args, no copy, return
  check: lower_func None when homed binding + ret has slice/ref). Two questions for leafC there.
- Next: statement for a borrowed parameter's entry store (rehome a bound local: cell exists, binding
  None -> Some(offset)); lemma "slice/ref-free type's held value names nothing"; then P3 cases once
  leafC's S6b lowering lands (merge origin/lang).
- 986052b70: HomedParamStore proved (entry store of a bound unhomed local; scope unchanged, context gains
  home). HomedLetStore.firstStore = shared heap half. Gate 26/26, open 75/58.
- leafC answered S6c: t = count+1 free; 8a check in lower_func (has homes = borrow/slice uses non-empty,
  ret contains slice/ref -> None). Pending: "names nothing" lemma for slice/ref-free types once leafC's
  predicate name exists; P3 cases after leafC's S6b lowering lands.

## 11-04 P3 on leafA-p3b: PAUSED by the coordinator (usage limit; resume after the reset)
Worktree /home/andrew-peterson/code/laniusc-wt/leafA is on branch leafA-p3b at b8044e46e. Never push.
The approved order is (a) → (b) → (c), with a report to main after each one.

**Commits so far**
- f3640e74e: (a) Mini/LowerCases.lean. One case lemma per SrcStmt constructor; it builds.
  - Eval twins are stated as the twin constructor's lowering:
    - `.let` / `.letStruct` / `.letCall` / `.letEnum` reading a homed local → `.letEval` of ePure / eStruct (pures) / eCall (pures) / eVariant (pures);
    - set / setField / setCall / setIndex / setEval / setIndexEval / setFieldEval on a homed local → `.setPlace`;
    - non-homed reads → setEval / setFieldEval;
    - if / while / return → ifEval / whileEval / returnEval of ePure;
    - letIndex on a homed array → letEval (eAt (ePure (local s)) (ePure i)).
  - The same commit has the S6b import renames, LowerExpr's `lookupSlot_some`, and Guard's `unhomedThen_some`.
- 17f203cc4: trusted fix, eBorrow toCore = `.borrow ty.referentOf.toCore …`. referentOf moved to SourceCore. TRUSTED_BASE has a "Pending, not yet in the hash" note, and SEMANTIC_DECISIONS S3 a "Fixed 11-04" note. The hash must be recomputed (`regen --only trusted --trusted`) once the top modules build.
- e0f3fa852, b8044e46e: TypeSound WIP (does not build).
- 50c7cfdfb: merge of leafC-s6b 417fceb72 (import fixes).
- lowering-spec.md "P3 file ownership" section: leafC writes the five `same` ref cases (eq_of_same, same_cases, same_toCore, same_nv, same_nv_left) in its own commit on top of leafA-p3b.
- S6c is on leafC-s6c 3ad0fb287. It removes the ArrayArgs path (stmtEval = eval) and adds evalLent for arraySlice. LowerCases needs no change; the `stmtEval_eq_of` side conditions become unused.

**TypeSound: done in WIP**
- Imports: all P modules via `target/claude-work/leafA/scripts/import_all_p.py FILE` (run from formal/), plus `public import Lanius.Mini.LowerCases`.
- `ScopeOk.cons` takes any home.
- Factored lemmas: `evalApply_typed`, `evalNegate_typed`, `evalNot_typed`, `evalCast_typed`, `evalPure_typed`.
- Place lemmas: `homePlace_some`, `subField_some`, `fieldPlace_some`, `indexPlace_some`, `placeIndex_some`, `derefOf_some`, `placeCode_typed` (Expr ∧ Place ∧ declared), `evalPlaceAt_typed`, `evalHomed_typed`.
- eval_typed: ePure (evalPureAny split), eIndex (evalIndexAny), and eBorrow/eDeref/eField/eAt, with the lookupSlot sites fixed. All of these checked clean.
- Note: there is no `TypeDeclared.ref`, and S6b's declare rejects `.ref`, so the eDeref place case is vacuous. S6c will need `TypeDeclared.ref`.

**TypeSound: next steps, in order**
1. `arrayArgs_typed` (about line 2567): add `{frame}` and pass it to `arrayArgs` (S6b signature `arrayArgs frame scope args types t offset`). This dies with S6c anyway.
2. Fix the errors around 2441–2449 (look at them first).
3. Assembly lemmas before `lower_typed`:
   - `letEval_assemble`: from `lowerLetEval ty (stmtEval value ..) (some tail) = some out`, `dv` and `bodyTyped`, conclude `.letLocal`. It is the old letEval case body.
   - `ifEval_assemble` and `whileEval_assemble`: the same pattern.
4. Standalone non-recursive theorems:
   - `setEval_typed`, `setFieldEval_typed`, `returnEval_typed` and `setIndexEval_typed`, taking `dv : ∀ t ∈ value.types, TypeDeclared P t`;
   - `setPlace_typed`, from storePlace via `placeCode_typed`'s Place part, `.assign` and `.set`;
   - `setPlaceOp_typed`, from storePlaceOp = evalApply (placeOpOf op) …; it needs AssignOpHasType op.toCore. Check what placeOpOf and SrcAssignOp.toCore give.
   - Lemmas: `toCoreList_pures : SrcEff.toCoreList (pures fs) = fs.map SrcExpr.toCore` and `effsTypes_pures = []`; lowerLet/lowerLetCall give `∃ vs, values = some vs` when the body is some.
5. Rewrite each case of `SrcStmt.lower_typed` (about line 2655) through `lower_X` from LowerCases:
   - Do `obtain ⟨-, b, hb, hh⟩ := lower_let h`, take bodyTyped once, then `rcases hh`.
     - Plain branch: the old body after guarded_some.
     - Twin branch: `obtain ⟨-, b', hb', h⟩ := lower_letEval h`, then `letEval_assemble`. The tail is generic, so b' need not equal b.
   - Twins need a `show`/`rw [← toCoreList_pures]` so toCore matches.
   - The unhomed declarations: `obtain ⟨-, h⟩ := lower_letAlloc h`, then the old body without `simp only [SrcStmt.lower]`.
   - Unchanged constructors: `rw [lower_X] at h`.
   - New cases: setPlace and setPlaceOp. matchArm, letView and letStr already go through Guard's `_inv` lemmas.
6. Then the Sig.frame errors at about 3090–3750: `Fields missing: frame` in Sig literals (sigsWith sets `frame := 0`) and `withBudget sigs room block frame` (4 arguments).
7. Build: `lv build Lanius.Mini.TypeSound`, then report (b) to main. Then FrameRoom (lowerFunc's new shape) and Simulation/Correct, if they fail.
- Tools:
  - `target/claude-work/leafA/scripts/errs.py LOG TypeSound.lean LO HI N` prints errors with their messages.
  - `lv check` waits for the lane, sometimes about 5 minutes. When the deadline runs out, retry once.

**Then (c)**
- Restate StmtSound/EvalSound over HomedCorr (stage2-plan section 4).
- The LowerStmt case proofs start from LowerCases. Each twin branch calls the twin's stmt_* theorem (StmtSound is not structural, so a direct call works).
- New cases: setPlace/setPlaceOp (RefStoreV2, AssignAfterRhs), homed let tails (`declTail`; HomedLetStore), and the eval place loads (PlaceLoadHeld). LowerStmt and LowerEval build together at the end.
