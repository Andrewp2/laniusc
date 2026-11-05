# regen agent (11-03)

Task: formal/tools/regen.py (one-command regeneration of every generated Lean file),
.gitattributes merge driver for generated files, merge procedure doc, real-case check.
Worktree /home/andrew-peterson/code/laniusc-wt/regen, branch regen from origin/lang e51443e05.
Never push. Commit with specific paths.

## Findings so far
- faithful_pure.py's gen_closure/src_modules read the REAL Gen dir (GEN_DIR), not OUTDIR:
  that is why "Gen until 0 changed" needs 2-3 rounds (SelfOk/SelfDecl/SelfPrims/SelfPureBase
  import-all lists come from the stale tree). Fix: read OUTDIR.
- trusted_check.py prints "trusted definitions: N constants, hash H".
- GenP / GenPC: pre_certs writes 3 modules; lang tracks GenP 00-02, GenPC 00-01 (P02 failing,
  not checked in) -> regen copies only names already tracked.

## Status
- step 1: worktree baseline build (no .lake yet; restore from shared lake cache)
- 001751071 committed: regen.py, merge_driver.py, formal/.gitattributes, formal/tools/README.md,
  faithful_pure GEN_DIR=outdir fix, pre_certs --prefix. Unchanged tree: regen --force 32-45 s, 0 changed
  (extract 13-21, dump 7-12, gen 2.4, genb 1.6, term 6.6, hb 0.1, pre 1.1); no-op run 8 s.
  Synthetic merge test (scratchpad/mt) passed: generated keeps ours + stale list; import union.
- next: goal 3 real case (rename a local in compiler.lani), build, gate, revert, byte-for-byte check.
- 067baff36: lake builds bounded by --limit and logged to WORK/lake-*.log; README timing section.
- Goal 3 done: rename local in room_after -> regen 3 files (linkedSize, SelfSrcC_linkedSize, SelfBModel0),
  build 3 passes (290+290+221 s, 362 modules, ~7100 lean-s: GenB proofs 3600, Gen 1500, Open.F5 760),
  quick gate 25/25, trusted unchanged; revert -> regen -> git status clean (byte for byte).
- Merge test (rt-a/rt-b, -c driver config): driver kept ours, regen --resolve gave plain-merge text. Branches deleted.
- target/claude-work/bin symlinked into the worktree (gate needs heavy). Merges cleanly with origin/lang dca8f216b.
- DONE; reported. Not set: git config drivers (coordinator runs README commands).

## Task 2 (11-03 evening): narrow the rebuild of a one-function .lani change
Coordinator merged 640385095 and set git config drivers. Steps: (1) GenB per function (break model chain,
proof parts import only statement parts they use); (2) trim unused `import all` in Mini proofs/Open.F5 (Source.lean
first); (3) SrcDump not importing whole compiler. Measure rebuild count + lean seconds for the room_after
`code`->`next_code` rename before/after each step. GenP must regenerate identically. Merge origin/lang often.
- regen branch fast-forwarded to 640385095.
- 85a884fbb: regen.py --check + gate step regen-current (quick tier, 20 s cached); GenPC/SelfP01 regenerated (stale on lang).
- Findings for step 1: legacy (non-module) files rebuild when anything in their transitive closure changes (even private
  parts); modules stop at unchanged interfaces. A module cannot import a non-module (probe: error). GenB is legacy and
  imports Budget -> SelfAgree -> SelfPanics -> Gen.SelfTerm/SelfLiveAll (whole Gen) => every Gen change rebuilds all GenB.
  Plan: BudgetCore.lean = Budget.lean generic part (lines 1-205, imports Cost/Rep/BudgetAttr); BudgetTactic imports it;
  GenB legacy but narrow imports, grouped by Gen's bucket (extraction part): SelfBModel<g> (group SCCs merged),
  SelfBStmt<g>, SelfBProof<g>, cert chain kept; shims SelfBModel4/5 = SelfBModels (GenP, Open Stmt.lean frozen imports).
  Stats: 2327 fns, 1263 model comps, 1396 proofs; transitive callers among proofs median 35, p90 128; room_after 10.
- 536290684 step 1 DONE: GenB by group (709 modules), BudgetCore split, pre_certs reads SelfBModels order listing;
  GenP/GenPC byte-identical; gate 26/26. Measure (rename room_after code->next_code, logs m1a-d, load avg ~14-21):
  315 modules / 6591 s (before: 362 / 7130 s at lower load). GenB 24 mods ~430 s (was 89 / 3827 s).
  Remaining big: Open.F5 84 (2197 s), Gen.SelfTerm 60 (912), SelfLiveOk 24 (542), Mini.Refs 9, Mini* via import all.
  Measurement helpers: target/claude-work/regen/{lb.sh,sumbuild.py,closure.py}; ONE build pass per command.
- 0836eb08b merge lang 5f7f1dcd4 (regen --resolve settled GenB modify/delete), ba3c3200a merge lang bfc3e1e3d; gate 26/26 both.
- next: step 2 (import all trimming; Source.lean first).
- Baseline after merges (r2a-d logs, rename room_after code->next_code): 328 modules / 7090 s (load 15-19).
  SelfTerm 61/1710, Open.F5 90/1307, Open.F14 38/645, SelfLiveOk 24/561, SelfPre 11/347, Mini.Refs 9/243.
- FINDING: warnings (unused simp arg, unused var, simpa) are stored in the PUBLIC .olean with the absolute source
  path (toy test in scratchpad/ol/c). Cache restores from another worktree (rfront) then rebuild here => olean
  differs only by path => downstream modules rebuild (LowerEval etc.). 75 public oleans carry paths (pathy.txt),
  28 in Mini. Fix = remove those warnings.
- FINDING: P.linkedSize local rename changes only .olean.private (public olean, ir same). Legacy files rebuild on any
  closure change; Open.F5 reaches 102/106 compiler parts via public imports, so import-all trimming can't help Open.F5.
- Plan: (a) Source.lean trim; (b) make SelfTerm*/SelfTermInfo/SelfLive* modules (legacy deps only Sim.Live,
  Sim.Term, Sim.TermSound); (c) Mini warnings; (d) SrcDump.
- helpers: path.py FROM TO, importers.py, reach.py, legacy.py ROOTGLOB.., hash snapshots hash{0,1,2}.txt
- a64b556b8 step 2a: Sim/Term,TermSound,Live -> modules; term_gen + faithful_pure write SelfTerm*/SelfLive* as modules.
- de4368c7c step 2b: import-all trim (trimrun.py/trimbisect.py/direct.py); Extract uses-block = direct names only.
  Checker files (Sim/CheckFast,Check,ProgOk,DeclStep,Boxed) must keep their lists (faithful_pure reads them).
- dc4e9f1dd step 3: FrontLex no longer imports Compiler (RunAll, self_compile.py, frontend_difftest.py import it).
- 1782ef866 + f5bf241db merge lang 938574f47; TypeSound took lang's list; PreBinaryWordsV3 Proof imports Mini.Source.
- Measure r5 (this_code rename): 215 modules / 5283 s (before r2 328 / 7090). Lake "Built (Ns)" includes leanslot
  queue wait: SelfBProofC_elementBase 246 s in log, 8.4 s by lcheck. Count modules, not seconds.
- Lake semantics (Lake/Build/Module.lean): module importer trace = public-closure olean hashes (no cutoff at
  unchanged intermediates); import all = all arts; legacy = everything. Open.F5/F14 legacy+frozen = 128 mods per change.
- Mini.Correct public olean leaks P-body local names (realized eq lemmas from simp [roomAfter]) -> cascades.
- 11-03 night (coordinator decisions): 80305b6e6 open_graph compares statement only; 45 F5 Stmt modules.
  fd5220251 51 F5 Red/Proof modules (fixalls.py). 634773e27 Correct private rfl eqs (olean unchanged on rename).
  96718caae warnings fixed in 44 modules (warnfix.py); no module olean holds a path now.
  Rename: 215 -> 137 (F5 modules) -> 125 (Correct) -> 125 (warnings; cross-worktree gain only).
  Left: Open.F14 41 (25 Stmt import legacy GenB/SelfPre/SelfBounded), SelfPre 14, GenB 22, Fwd 7.
- 11-03/04: regen-modules cd0251075: GenB models/stmts/proofs modules (+Cost, BudgetAttr, BudgetCore, BudgetTactic meta
  sections); proofs import all SelfSrc/SelfStmt + model's mini parts. Rename r9 (new_code): 118 modules (was 125).
  Not yet merged to regen (regen-modules is from 96718caae).
- On regen: merged origin/lang 602f7227b (leafA-slots; LowerEval/LowerStmt theirs + _under fixes), committed; then
  merging c896a1b6c (S6a-2: deleted 5 HomedCorr* in favour of V2; V2 Proof/Red modulized) — building (h*.log).
  Used names: next_code code_next this_code my_code cur_code the_code new_code.
- 11-04: regen 2af163e77 = merges of 602f7227b (ebe64bc60) + c896a1b6c; build rc=0, gate 26/26. Reported.
  HAZARD found: at 02:14 lean wrote truncated outputs (SelfProofF_lxDotAt.olean.private 64 KiB vs 1.9 MB; empty
  SelfStmtF_Inline_pTypePathIdent; SelfStmtF_variantIn ilean/c) and lake cached them -> segfault (139) importing.
  Quarantined cache mappings in regen/badcache/ (95043a9d0cb1c774, 327a11163ef5fd28, aac4e3d6db2160ed .json).
  Tools: badolean.py MODULE (prefix bisection of import crash). Fault addr vs olean base addrs found it.
- NEXT (coordinator 11-04): per-function extraction, opaque outside own module; proofs import only parts used;
  pre/budget certs regenerate only changed functions; generated proof modules named by statement hash (cert spike:
  SelfP02 405 s tactics). Then (5) generated files not committed. Merge LOCAL lang (push broken), not origin/lang.
  No Lean language server. regen-modules (cd0251075) folds into this.
- 11-04 LANDED for coordinator: regen-modules cc8cfec22 (ff of local lang 52118889e; build rc=0, gate 27/27).
  All legacy files of the self chain are modules except GenP/GenPC (post_auto times out on SelfP01's nestedOf in
  module mode, 280 s+) and the 8 files importing them. Generators: budget_certs (cert chain + SelfBFree modules,
  whole-program import all), hb_gen (HB/NB/SZ/TS modules). Tools: legacyorder.py, convlayer.sh, fixfailed.sh,
  fixalls.py (error-driven), metasplit.py, staticalls.py, wholeprog.py, simrebuild.py [--what-if].
  Body change id_absent: simulated 145 -> 67; real 49 built + ArrayCall (its proof unfolds id_absent) failed.
  Next (not started; waiting): GenP as modules, per-function parts (stable names; import alls go stale when parts
  regroup), statement-hash proof modules, generated files out of git.

## 11-04 per-function parts: benchmark result (stopped, waiting for coordinator)
- Benchmark merge of 7affee0ff (adds lower_let_view) on regen-modules WIP HEAD, simrebuild.py: 575 (cc8cfec22) -> 435 now.
- simrebuild.py --stable=REGEX what-if: models' interfaces stable -> 308; also all index files' interfaces stable -> still 308
  (199 changed sources: ~150 are index chunks SelfTerm 51, SelfDecl 25, SelfOk 24, SelfLiveOk 24, SelfCertPart 16, SelfLookFn 6, SelfBCert 3,
  whose literal function/callee indices shift on insertion, plus their import-all dependents).
- <100 needs position-independent per-function checks: theorems per function with callee indices as parameters and
  callee signatures as hypotheses (checkers over a slot environment + substitution lemma), index only instantiates. Redesign of 6 generators.
- WIP commits (per-function parts, chunked Gen buckets, de-aggregation) still unbuilt (~3000 new part modules).
