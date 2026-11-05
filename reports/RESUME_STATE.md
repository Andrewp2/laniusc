## Night stop (11-04, user closing the laptop)
- Local lang (not pushed: GitHub SSH auth fails) has: leafB2 array_args, leafA-lims (FrontEndSlotNest/NumbersSmall proved), lv tool, f6v stage (b), cert checker + soundness (LaniusCert), leafB2 P02 down to 4. Gate passes. Push first thing: `git push origin lang` once the user fixes the SSH key.
- Merge rule: fast-forwards of local lang only (lv merge / merge1); a tools-only or cert-only branch may be merged by hand, then `lv gate`.
- Waiting on regen's per-function extraction: leafC-s5b 315e4330d, leafC-s6b (417fceb72), leafC-s6c 3ad0fb287 (+ declare(.ref) fix and an end-to-end &mut case), leafB-lv 7affee0ff. Each then gets one full build.
- leafA: P3 on leafA-p3b (on leafC-s6b; LowerCases.lean done; borrow toCore fix 17f203cc4, hash pending; TypeSound in progress). leafC: five `same` ref cases on top of leafA-p3b.
- f6v: f6v-split (World/Files types vs meanings) needs up to 4 build passes, then stage (c).
- cert agent stopped: reflection in Lean is about 10 min per obligation (no gain); the Lanius-native verifier fork is the user's decision.
- 5-minute rule includes loops of reruns (blloop forbidden).

## Tooling direction (11-04)
- User: one-line change must verify in seconds; tooling is the bottleneck; no Lean LSP in tools; laptop only (memory tooling-seconds-target).
- regen: per-function extraction (opaque modules, certs only for changed functions), then generated files out of git.
- `lv` single front door: next free agent.
- cert agent (new, laniusc-wt/cert, branch cert-spike): MM0-style flat certificate checker in Lanius, certificates for a slice of the verified compiler, report in target/claude-work/cert/REPORT.md.
- .lani queue dropped: batch .lani branches into one regen/build/gate (after leafC S5b+S6b: leafB2 array_args + leafA-lims together).
- lang 0fec9e7dc. Disk: bin/cacheprune runs from merge1.

## regen round 2 (11-04 05:10)
- regen branch (96718caae, not merged): statements/F5 proofs as modules, Correct rfl equations, warning fixes; rename test 215 -> 125. Conflicts with lang in Mini/LowerEval+LowerStmt; waits for leafA-slots to land, then merges lang and reports. Approved: Budget/SelfPre/GenB chain to modules on branch regen-modules (SelfPre/Compile* and F14 proofs last, after leafB2 group A).
- f6v resumed for stages (b) and (c) on a fresh branch; (d) still queued after leafC S5b+S6b.
- Merge order: leafA-slots -> regen -> leafC S5b+S6b (+leafA P3) -> f6v (d).

## S5 merged (11-03 23:00)
origin/lang 6163ae1f2: leafC S5 (ref params read as SrcType.ref, eField/eAt over eDeref, setPlace/setPlaceOp, refsChecked, mut keyword; hash 8383ab6c600c2220). leafA S6a-1 (LentHomes replaces FrameCorr in the simulation), P2 (HomedSound). leafB2: groups B,C,D,E done, CompileFuncSlotsV2 proved, 40 failing P02 (group A waits on leafA-slots). regen: narrower rebuilds merged (215 modules per rename); doing statement modules (open_graph compares only docstring+def), warning fixes, Mini.Correct leak. Merge with target/claude-work/bin/merge1 COMMIT (pushes only on 0 failed). .lani queue: leafA-slots (+S6a-2 Binding.home) -> leafC S5b+S6b (with leafA P3) -> f6v (d).

## S3 merged (11-03 evening)
origin/lang 5f3bf3734: leafC S3 (SrcEff eBorrow/eDeref/eField/eAt, setPlace/setPlaceOp, exprPlace trusted, hash 793d1e4339a7c10d). regen.py + merge drivers on lang (640385095; git config set). .lani queue: leafA-frame (frame_block room, needs capped at 2^40 sticky, compile_func reorder) -> leafC S5 (reading + lifetime) -> f6v (d) file externs lowering. leafB replaced by fresh leafB2 (a73c93b9de3488770, same worktree) on GenPC type-size lookups (71 failing). leafA: P1 proved, PreBinaryWordsV3 + OptimizeKeepsNumbers proved; LowerFuncsTemps superseded by the reorder. regen agent: narrower rebuilds (GenB per function, trim import all) + gate check for stale generated files. f14c stopped.

## f14c stopped (11-03 13:35)
origin/lang 11239b11e: f14c GenP speed (heartbeats -44%/-41%, chain ~5 CPU-min cold; 60 s would need reflective checking, not tuning; remaining costs listed in target/claude-work/f14c/RESUME.md). f14c stopped at this natural point (load 13-14 with 5 agents). leafC S1-S4 merged (SrcType.ref, Layout.lean, HoldsAt.ref, PlaceHasType.deref, SourceRefsCorrect proved while refs rejected); S3 .lani edits wait on leafA front-end check + f6v str re-merge. leafB: re-merge 23b827a8a (room_fits per function) + number measure (--compile mode) for GenPC 97 overflow failures. f6v: re-merge 8e308d921 (str S2/S5).

## image_limit check + F5 stage 2 lemmas (11-03 04:35)
origin/lang 37396cc0d: leafB room_after (compiler.lani link checks image limit incrementally, trusted hash d75635f4ee0dd1d2), V3 compile-side statements (FrontEndTypeSlots, FrontEndStmtDepth, PreCompileSourceV3, PreBinaryWordsV3, PreCompileWords.red3; V2 + FrontEndOutputSmall probably false). f14c: GenP one module per kind, cold ~125 s, PreBuildFiles/PreStepLetFirst/PreFrontEndWords proved, gate builds GenP. leafA: F5 stage 2 lemmas all proved (HomedCorr*, HomesPopHome, HoldsAtDropHomes, plain let); next machine side, then ref cases once SrcType.ref lands, then lowering = RPlace shapes (spec note leafA/lowering-spec.md). leafC: stage 1 (references in Source). Gate at load 18 after a compiler change took >295 s (all difftests invalidated); rerun 44 s.

## F5 graph merged and mostly proved (11-03)
origin/lang 265b92b25: F5 design + graph (4680df32c, reviewed twice by a4cf46364dcbc6baa), RefLoad, RefStoreV2 (RefStore false: tags > 2^32), HomesCongrV2 (HomesCongr false: statics), CorePlace/Read/Borrow/Assign/AssignOp, Homes*, FrameCorrHomes, RefsLemmasV2 stated. 34 statements, 16 proved. Agents: leafA (PlaceAddr, PlaceAddrTraps, then RefsLemmasV2 proof), leafC (laniusc-wt/leafC: F5 stage 1, references in Source/frontend/compiler), leafB (incremental image_limit check in compiler.lani + V3 compile-side statements; V2 probably false: monomorphization blowup), f14c (GenP cold time), f6v (F8 S2-S5).

## GenP speed merged (11-03)
origin/lang 0bc8b87b0: leafB e8aa8bd00 (compile side on program size, PreCompileWords.red2, value lemmas) and f14c 042184f82 (certificates over variables; SelfP01 71->20 s, chain ~3 min cold). GenPC/SelfP01 stale (compileLowered takes statics): leafB regenerating, then size bounds for PreCompileSourceV2/PreBinaryWordsV2. f14c: SelfP07 parallelism, shorter chain, PreStepLetFirst NOTES, PreBuildFiles edge. leafA: F5 revision, then re-review by a4cf46364dcbc6baa. f6v: F8 S2-S5.

## F5 review (11-03 03:00)
leafA's F5 design (6cfcbf202, not merged) reviewed by a fresh agent: no compiled-vs-Core divergence, but root is only a conjunction, HoldsAt.ref must use the source type, CoreAssign too weak (effectful RHS, compound assign), no-views too strong, trusted delta incomplete, Homes must replace FrameCorr, adopt NativeLayout, age order instead of Plain, index as pure expr. leafA revising; then re-review, then merge. leafB doing PreCompileSourceV2 (small-height premise) + FrontEndOutputSmall leaf.

## F14 graph merged; leaf agents (11-03 01:30)
origin/lang 61e755d92: 12 F14 statements (root SelfCompilerTotalReason, heap limit 2^61). Agents: f14c (let_first step, GenP speed; edge PreBuildFiles<=PreStepLetFirst deferred until GenP < 2 min cold), leafA (laniusc-wt/leafA: ReadFilesHeight, ValidateFilesHeight, PostFrontEndWords), leafB (laniusc-wt/leafB: compile side, GenPC/), f6v (F8 str/pointer externs).

## Open-statement graph (11-03)
3b798f404: formal/OPEN_STATEMENTS.md + open_graph.py + gate step `open` (Prove2Me style, user-approved). f14c is converting the F14 remainder into statements. Next ideas: read-back audit of top statements; comparator/second kernel on top theorems; F5 (&mut) as a statement graph.

## f14c native tactic merged (11-03)
origin/lang dc4686f0c: native GenP tactic (chain 108 s fresh; not in the gate yet), new GenP layout P00-07, PRE_HAND hook + SelfPre/Values.lean. Left: 8 float routines (value lemmas), SelfP05-07 failures, then compile_words + top theorem. f6v on F8 str/pointer externs (write_text, write_byte, file io).

## f6v str stage (c) merged (11-02 22:00)
origin/lang has c9c4bc250: LetStr (string tables), trusted hash 8e49c84069f2b7bf; 9 string_data_ptr files 75 -> 157 agreeing calls; traps all index-out-of-range like laniusc. f6v next: str parameters. f14c: native tactic for GenP, then SelfP14-17.

## f14c height lemmas merged (11-02 20:30)
origin/lang 594ca03fc: build_files height lemmas, SelfP00-13 preconditions (not yet in the gate). Bug found: frontend.lani wide_isize/wide_sint overflow on literal -0 (self-built compiler traps); f14c is fixing it (+ frontend cases), then SelfP14-17. f6v on str stage (b) (LetStr).

## f6v point 6a merged (11-02 20:05)
origin/lang has 276bd837b: read-only static region in the mini language (r8 holds the static base; startup 95 bytes; trusted hash 64acd215bab52adb). The gate's lake build does rebuild runAll etc.; exe mtimes can look old because the Lake artifact cache restores them. f6v next: stage (b), str in the verified compiler.

## S1 stopping (11-02 19:30)
S1's codegen handoff (cold pickup): target/claude-work/s1/RESUME.md, section "codegen3: handoff for the next agent" (K::lt known semantics, per-step latency, i32 iterate placement). Open gap: 1M keys insertion-order probe 302 ms vs std::map 49. S1 stopped after the ||/&& fix (2bb432c7e, merged). Only f6v + f14c run.

## link1 done; codegen3 cmov merged (11-02 18:40)
origin/lang b216a0185: link1 finished (lib 974/974; concrete where-clause subjects in the interface) and is stopped. S1 f25969397 (cmov if-conversion, select-based find for <=2048 nodes; cached probe 986->651 ms vs std::map 369). Merge tests: build test binaries with --no-run first (heavy -t counts the test build). Agents now: f6v (str), f14c (build_files), S1 (return-shaped selects).

## f6v point 5 merged (11-02 17:45)
origin/lang 4954f2692: f6v LetView (i32_array_data_ptr) via merge 28ce43018; legacy Semantics RawFieldStore/WritePlaceTests fixed. f6v on point 6 (str). S1 on cmov + branchless find (mispredicts are most of the gap to std::map).

## codegen3 partial + f6v (11-02 17:20)
origin/lang fc4d8c120 has S1's e7ff16129 + 0c0ee747a (zero-param fns, main included, now get registers). f6v 097ccad8d (point 5 LetView) conflicts in GenB/SelfBCert0.lean: f6v is merging origin/lang and regenerating; merge its merge commit next. Then f6v does point 6 (str).

## Gate speed + merges (11-02 17:00)
origin/lang 7b660e184: link1 lib-test fixes (967/972; dead-mov fold bug fixed), f14c option (a) 51b83208d, and parsekey 2fc3977b5 cherry-picked: parse caches keyed on the front end, one parse server per step. Fresh quick gate 274 s -> 120 s (stdlib-io 165 -> 15 s).

## f14c 3da246e31 merged (11-02)
validate_files/files_fuel preconditions proved. f14c doing option (a): Cost_F 0 = 2^64 in budget_certs.py, regenerate certs, then build_files + compile_words. S1 codegen3: per-get 838 instrs vs std::map ~100; first compile-time inlining of cross-unit leaves.

## codegen2 merged (11-02)
bf007a775: find step 31/34 instrs, 6 stack operands; cached probe 991 ms (std::map 369); 1M key order 126 (std::map 133). S1 on codegen3: per-get instruction accounting vs std::map, then the biggest part.

## Lean process cap restored (11-02 15:55)
leanroot/bin/lean: 6 machine-wide slots (leanproc/slot.N) then memwait; memwait alone let 16 lean run (load 40). f14c 3f9746474 merged (SelfBounded.selfCost_of_pre); f14c on the two root preconditions, lexer first.

## codegen2 2a + f14c speedup merged (11-02)
origin/lang has S1's 01340b442 (find step 32-35 instrs, 6-7 stack operands; probe 1936->1234 ms) and f14c's ada741a29 (certificate tactic speedup, 74 work-balanced proof modules). heavy's build lane is the bottleneck with 3 agents: run merge tests in the background (heavy -t counts from lock).

## codegen1 merged (11-02)
S1's x86 code-quality work on origin/lang: same-object tiny inlining, link-time splice of <=9-byte callees (link/splice.rs), slice header reads from home, loop-weighted register choice, jmp->jmp threading. find step 52->37 instrs; probe 214->161 ns/get. Left: spills of middle/base/temps, call args via stack, only 4 callee-saved regs.

## link1 round 2 merged (11-02)
2c8b6cc7d on origin/lang: ELF validator fix, native C link with one runtime, x86 literal-compare miscompile fix (scatter.slang), stale x86_codegen tests. link1 resumed on the 17 failing lib tests (x86_artifact all-zero first).

## F14 step 1 merged (11-02)
c28a6d563 on origin/lang: all 2,244 budget certificates (BudgetFree kernel check, bclosed, budget tactic). f14c resumed on: speed up let_first/stmt_of, then CompileBounded T and selfCompiler_total_reason.

# AGENTS (2026-11-02 11:40): link1 (laniusc-wt/s3, branch link1: one runtime per x86 executable, fixes 13 jump-check test failures); S1 allocator merged 1bfddcaab (corruption = failing GPU driver 11-01); f6v (laniusc-wt/rfront, branch f6v: rfront 3.6 oracle check, then Addressed locals point 5 i32_array_data_ptr, point 6 str), f14c (laniusc-wt/review, branch f14c: GenB budget certs, CompileBounded, selfCompiler_total_reason), s1 (laniusc-wt/s1, stdlib-s1: rerun checks, explain allocator corruption, then BTreeMap). Briefs: reports/VC_RESTART_BRIEF.md, STDLIB_RESTART_BRIEF.md. I merge one at a time with the gate, then push.

# MEMORY (2026-11-02 10:30): one budget, nothing killed
- All work runs in work.slice (MemoryHigh = RAM - 4 GB, soft). Starts wait in target/claude-work/bin/memwait. lean.slice is gone; no MemoryMax anywhere (commit 54f3c9577 + bin/ scripts).

# CURRENT (2026-11-02 09:10): merges done through S4, all pushed
- origin/lang c77cd3f39 has review-fixes, front-fixes (rfront 3.5b), f11b (+ step D, F14 cost proofs ported to mstmt/qstmt fuel; trusted hash f991f205862cd76e, 4649 constants) and stdlib-s4. Quick gate 24/24 after each.
- F11b: literal_match_values had an untyped let of a match (SEMANTIC_DECISIONS excludes it), so it is now typed; 7 expect.out files written after checking each reading.
- S4: docs "Small copies" rewritten for lang's S9 register copies; uring stream.backpressured is now a 1-16 range check (kernel 7.0 gives 16 owed, the old kernel gave 15). stdlib_concurrency_execution 14/14.
- Left: stdlib-s1 allocator (unexplained one-byte corruption; don't merge), fuzz 1810cb663, gate-speed 2fc3977b5, S5, S8, S7 WIP b9cafe0e6, S9 spill WIP. No agents running.

# CURRENT (2026-11-02 08:00): Ubuntu 26.04.1, closed NVIDIA 595.99.02, GSP OFF
- The user reinstalled the OS. The driver is now the closed 595.99.02, with /etc/modprobe.d/nvidia-gsp.conf `NVreg_EnableGpuFirmware=0` (the GSP firmware timeout, Xid 119→79, caused both crashes). Verify with `grep EnableGpuFirmware: /proc/driver/nvidia/params` → 0.
- Cold pipeline cache: 156 s for the first compile; warm: 68 ms. The gate passed 24/24 with the GPU, and lang fc7a2df92 is pushed.
- After each reboot: `systemctl --user set-property --runtime lean.slice MemoryHigh=10G` (the file says 12G).
- Keep GPU load light: one GPU user at a time until it has proven stable.

# GPU DOWN (2026-11-01 23:10)
- Second GPU crash: Xid 119 (GSP RPC timeout), then Xid 79, in the lcc daemon (laniusc pid 11682), 37 min after the reboot. nvidia-smi finds no device. target/claude-work/GPU_DOWN is set.
- lean.slice MemoryHigh is 10G since 23:50. At 7G the throttling put pressure over oomd's 50% threshold, and it killed whole Lean builds. Re-set it after a reboot.
- Lang has local merges through 60d257f55 (S9, S3, S7, S10, S6). The rebuilt main compiler finished, but the quick gate's mini step failed because the GPU was lost. Not pushed: after the reboot, re-set lean.slice MemoryHigh, run the gate, push, then S4 merges origin/lang.
- S1 and S4 were told to commit and stop. The Lean agents (rfront, review, F11b, F12) keep going on the CPU.

- 00:40: the cause was 7 lean processes at 1.7 GB each hitting lean.slice MemoryHigh, where throttling made SelfProofF_lxCanonicalKind take more than 280 s instead of 68 s alone. The leanroot cap is now 4 (LEAN_PROCS), and SelfTotal built in 130 s. Reviewer A's merge is committed as review-fixes 2947a8cc4: trusted hash 339ca6217ec1aa8b, 4501 constants, 32 top theorems.
- ALL AGENTS STOPPED (00:40). Branches to merge after the reboot, each with its GPU checks then the gate: review-fixes 2947a8cc4, front-fixes 1af294c20 (rfront 3.5b), f11b e2b751c12 + 9af4023ad (step D changes the trusted hash again: needs the top-theorem build and trusted), stdlib-s4 a77e3376d, stdlib-s1 (do NOT merge the allocator until the corruption is explained). Lang already has f12 merged locally (fc7a2df92). Push only after the gate passes with the GPU.

- SOLVED 00:40: the post-merge cold build of Lanius.Faithful.SelfTotal (review worktree) builds only 4-7 modules per 290 s run, even with 7 lean processes, and stays at about 55 jobs left as lake discovers more. Certs take 23-100 s and up to 1.7 GB each. Find which modules sit in flight for the whole run (lake -v output, or ps etimes on lean processes), and whether a few huge certs (SelfPrimTab, SelfOk14/23, SelfLiveOk3) dominate. Then split or shrink them. Reviewer A has stopped; its finish steps are in its report: build, trusted, fill HASHNEW and NCONST, add ROADMAP, TRUSTED_BASE and GenB, commit.

- F12 has stopped. f12 af35f5e3c (import trimming; import all lines 11,674 → 6,253; defs hash 8884c49974b65a57, same as lang) is merged locally into lang as fc7a2df92, not pushed. A body edit to a Compiler.P part now rebuilds a median of 23 modules instead of 92; a SelfTypes or SelfRep change still rebuilds 313 or 520.

- Lean process cap: leanslot routes lake through target/claude-work/leanroot (bin/lean is a flock wrapper allowing 7 lean processes machine-wide). There are now 3 slots. LEAN_NUM_THREADS deadlocks lake, so don't use it.
- Reviewer A: the merge of origin/lang into review-fixes is staged, not committed. TRUSTED_BASE has the placeholder HASHNEW, and about 55 cert jobs are left. It is waiting for F12's import trimming; or build once the machine is idle.

- rfront 3.5b is on front-fixes as 1af294c20 (trusted and extract pass, defs hash d76509417115a874, FrameCorr ceiling/bounded). Merge it after the reboot, and rerun self-current and frontend-cases with the GPU up: their 23:45 "pass" was probably a cache hit. rfront has stopped. Its 3.6 is just the laniusc end-to-end checks (array calls in the oracle difftest), which I do at merge time after the reboot.

- F11b e2b751c12 (merged origin/lang, trusted hash 7eb93b7916d84bb4): waiting on the GPU for its steps (3)-(5) (expect.out, frontend-cases, slice_len in laniusc, the gate). Meanwhile it works on step D (while loops) in Lean.

- S4 has stopped. stdlib-s4 a77e3376d merges local lang 60d257f55, keeping lang's small-copy shaders, so it has no compiler change beyond lang. It hasn't been tested since. After the reboot and push: rerun its codegen subset, the oracle steps and small_copy_bench, fix the "Small copies" section of docs/stdlib-threads.md, then merge. All stdlib agents have now stopped.

- S1 has stopped. Branch stdlib-s1: allocator ef2d525a7, jump-check cddab3645, local-lang merge eda5c91c8, none of them built since. DO NOT MERGE until the rare one-byte corruption in multi-MiB blocks is explained (5 of ~215 runs, all while swapping; see docs/runtime-allocator.md). After the reboot: run the codegen_x86 suite. The jump check probably needs to allow the two trap entries from 53432d0f0. Steps are in target/claude-work/s1/RESUME.md.

# CURRENT (2026-11-01, 22:50): rebooted; GPU back. lang 300f9f07f (pushed), quick gate 24/24.
- heavy now refuses cargo builds into a target/release symlinked to another checkout (use CARGO_TARGET_DIR=$PWD/target/own). leanslot wraps bare lake/lean in lean.slice (8G scope), 2 slots. lean.slice MemoryHigh=9G (--runtime, re-set after reboot: systemctl --user set-property --runtime lean.slice MemoryHigh=9G) so compiler builds are not starved.
- Agents running: rfront 3.5b; review F14 (then merge lang + laniusc steps); f11b pure-fragment loops then GPU-side of its queued commits + slice_len in laniusc; S1 allocator bench + BTreeMap; S2 websocket; S3 sed fast path + grep speed; S4 small-copy compiler change + channels/pool (own target); S6 intrinsic fix test (own target); S7 zstd/xz finish + speed; S9 spill reuse (own target); S10 head/tail/cat/tee/paste/join/comm; F12 merge lang (53 Gen + ~20 Lean conflicts) + measure import trimming.
- Not restarted yet: fuzz (1810cb663, merge lang), gate-speed parsekey (2fc3977b5), S5, S8. Brief for stdlib agents: reports/STDLIB_RESTART_BRIEF.md.
- If the GPU drops again (Xid 79): touch target/claude-work/GPU_DOWN; user resets or reboots.

# CURRENT (2026-11-01, 17:30): GPU FELL OFF THE BUS (NVIDIA Xid 119 GSP 90 s timeout, then Xid 79) at 17:26; needs a reboot (user).
- After the reboot: `rm target/claude-work/GPU_DOWN` (heavy GPU lane and lcc refuse jobs while it exists), check `nvidia-smi`, then rerun the quick gate on lang.
- lang at 55ebc218b (pushed; rfront 3.5a frame needs+prologue+top premise, hash 8884c49974b65a57, self-host unrun; MoonBit bench lanes df9098cf6 (moon not installed); before: 4ead8ed86 T2; before that 6f96d663f T0-T1; before that rfront 3.3+3.4 Lean-only, hash d230774a2b033659, laniusc steps not rerun; check stdlib_oracle/oracle_difftest slice_stride expectations; was 7b94d94a1 3.2+3.3a hash 30cfc8a1287e8470): everything through front-fixes 3.1 (hash c1629d03f01a2c36), S1 thread-safe allocator, S2 client, S3 grep -r, S4 threads/exit_group, S5 kv_log, S6 kernel-pairing, S7 zstd, S8 LSP, S10 textutils, F11b, review restatement.
- Waiting to merge (each agent merges lang into its own branch first): S9 (runtime table conflict with S1), F12 (generator conflict), fuzz (float infinity, hash), S6 intrinsic-shadow fix (untested).
- Agents' tasks: S1 mid-size tier + btree; S2 websocket; S3 grep speed + sed; S4 channels + pool; S6 intrinsic shadow; S7 zstd encoder + xz; S9 spill reuse; S10 textutils gaps + head/tail...; F11b hex/octal/bin, cast shifts, literal patterns; F12 merge; rfront step 3.2-3.6; review capped type sizes then F14; fuzz merge; gate-speed agent: parse-capture cache keys + lcc routing.
- Ready after the GPU is back (gate the laniusc steps, then fast-forward): review-fixes 080cd1df6 (merged lang 7b94d94a1; hash 5aa62e3705d251c9; Lean steps pass; frontend-cases + self-host unrun); f11b 50bc1cd84 (literal match patterns, EIf/ELet, for over arrays/slices, Core Intrinsic.sliceLength + `slice_len(s)`: AFTER REBOOT add slice_len to laniusc intrinsic_result.slang + stdlib/core/mem.lani, then difftest; expect.out for slice_len, for_slice, reject_for_slice_write, literal_match_values, for_array too; earlier: 11a41c2d0 needs cert regen + hash + expect.out for int_bases/generic_shift_arg/literal_patterns); F12 21f8530bc (Lean steps pass); S9 408136294 (merged lang; stdlib-scalars/io unrun; spill-reuse WIP patch in laniusc-wt/s9/target/claude-work/s9/). S7 b999e5870 committed mid-task (zstd encoder + unxz; RESUME.md in laniusc-wt/s7/target/claude-work/s7/). S7's agent has EXITED; after the reboot, start a new S7 agent: rebuild probe + compressor, full encoder oracle + decoder regression, full unxz oracle (2 .lzma dict-size cases where xz refuses and we accept; decide), docs + metadata + docs/api, final commit. Reviewer A: CompileBounded T W (threshold is now a parameter, T=2^31 so K^2 fits); statement hash will change.
- SHARED BINARY BUG: 14 worktrees (f11 f11b f12 f6s f8 f9 gs review s10 s2 s3 s4 s5 s7) have target/release as a SYMLINK to main's. S4's compiler builds (small-copy change, 5883711be) overwrote main's laniusc, so gates on main after 17:20 may have run S4's compiler. After the reboot: (1) rebuild main's laniusc from lang (heavy --priority cargo build --release) before any gate; (2) give compiler-editing worktrees (s4, and any agent that runs cargo build) a real target/release (cp -a --reflink=auto or a fresh build); stdlib-only agents use lcc/main's binary and must not run cargo build.
- More committed mid-task: review-fixes 691ef5fde..17d1ccc4d (type weight cap 2^22; F14 generic part + conditional selfCompiler_total_reason_of_bounds, 32 top theorems, hash e5a4ad804bd2998c; Lean steps pass; recheck laniusc LNC0057 on nested_array/doubling chain after reboot), S3 46dda5251/9ff099dcd (grep 1.42x GNU; sed 8000/8000 vs GNU; literal fast path WIP; RESUME.md), S1 c98ce6978 (mid-tier allocator to 1 MiB + mremap; unmeasured; RESUME.md), gate-speed agent 2fc3977b5 on branch parsekey (worktree laniusc-wt/gs; parse-tree cache keyed on front-end digest + ParseServer per step; first post-reboot gate warms new keys, then measure), S10 5b75b2786/03819ef29 (tr gap closed; head uncompiled; tail without follow is right; RESUME_S10.md), S2 785032e38..265033d33 (websocket; RESUME_S2.md), S4 836ffc0d6/54730ccb2/5883711be (channels, pool, small-copy compiler change; RESUME.md), S6 ff64b8f8a (intrinsic fix, untested; two codegen_x86 failures to compare against lang), fuzz 1810cb663 (merged 38b30fae8, hash b530a822b9b0b6a5; needs one more lang merge for 7b94d94a1; then rerun shiftcast/literal-pattern probes on laniusc for F11b).
- Fuzzer slice gaps to route: raw views of i64/u64/u32/bool, slice elements holding arrays/slices, slice local reassigned after let, `for x in s`, struct patterns `S { e: A(x), .. }`, match guards -> F11b (front end) / rfront (lowering).
- Agents die with the session on reboot: restart them from this list (worktrees laniusc-wt/<name>, branches as named).
- Tool changes today (target/claude-work/bin, not in git): heavy compiles cargo test/run in the build lane first; heavy HEAVY_GPU_HELD nesting; lcc gpu_held skip; GPU_DOWN guard in both; run_cache.run_lean outputs (in git, cbf2de3c3).

# CURRENT (2026-10-31, 00:30): F1-F13 in progress; pushes allowed. lang at 6f20c943 (pushed).
- Done today: source break/continue (cd2bb855), f8 merge (6694392a), for over a range (7c0a89c9), block statements (6f20c943). Certs current.
- Agents: F9 floats (worktree laniusc-wt/f9, branch f9, still running); F8 rest (worktree laniusc-wt/f8, branch f8 fast-forwarded to 6694392a; world through HeapCorr, extern reading, oracle stdout). Merge each into lang when it reports, regen certs, gate, push.
- Now: F4 `?` and statement match arms via a new SrcStmt MatchArm(scrutinee, ety: SrcType, variant k, binders, body, rest) (binary node, no nested inductive): Core = ifThenElse (matchValue r [(variant k wildcards, true),(wildcard,false)]) (letLocal b_j t_j (matchValue r [(variant k .. bind b_j .., local b_j)]) ... body) rest; lowering = Ite on tag, binder copies (not aliases) at next. Then front end: match statements with block arms, `x = e?`, `let x = e?`, `e?;`.
- Gate can time out when an agent holds the Lean lock: run `python3 -I -c "import sys; sys.path.insert(0,'formal/tools'); import gate; gate.build()"` in background first.

# CURRENT (2026-10-30, evening): user: "complete F1-F13, push as parts complete, use subagents". Pushes allowed (lang -> origin).
- Agents (background): F9 floats in worktree /home/andrew-peterson/code/laniusc-wt/f9 (branch f9); F8 externs in /home/andrew-peterson/code/laniusc-wt/f8 (branch f8). They commit on their branch; I merge into lang, regenerate certificates, push. Worktrees have a copied formal/.lake and target/ with symlinks (release, claude-work/bin, claude-work/cache).
- Lean lock: every Lean build/probe holds <git-common-dir>/lean.lock (lb, leanp, l2/build.sh, run_cache.lean_lock in the tools). One Lean at a time; 14 GB laptop.
- I do F4 (control flow) in the main tree, then F6.
- PENDING: Faithful certificates (Gen/Self*) are stale since 19:03 (shift amountWant, &self, S::m front-end changes): run GENONLY=1 l2/pipeline.sh, faithful_pure.py, l2/build.sh loop, after F4.
- Full stdlib oracle costs ~6.5 min (3 shards): too slow, user said do not fix now; don't run it routinely.
- Done today: F3 done; oracle structs/enum results; &self; S::m on structs. lang at c6e530ca + lock commit.

# CURRENT (2026-10-30, latest): F1 done; F2 mostly done (local commits 2c4b83cf, 31559363, unpushed: push needs the user's yes). The extractor in Lanius (formal/lani/mini/extract.lani, driver Lanius/Tools/Extract.lean, run by formal/tools/lani_extract.py) writes compiler/frontend/extract/sqlite extractions byte-identical to extract.py; gate step `extract`. extract.py kept only for mut_pilot + TLS (need F4/F5). Cert generators stay Python (untrusted, kernel-checked). Plan/notes: target/claude-work/reports/F2_PLAN.md (incl. laniusc literal-context bug repro). Next: F3.
- After .lani edits: python3 -I formal/tools/lani_extract.py [NAME] (replaces extract.py for those four). For extract.lani edits also: tools/text_consts.py, tools/grammar_table.py, scratch/f2/reorder.py + order.py, then lani_extract.py extract (fixpoint).
# CURRENT (2026-10-30): F1 DONE (local commits d9c78d5b..e62d476c, not pushed; push needs user's yes). reading_unique in formal/Lanius/Mini/Reading/Det/, theorems use textReading_unique, lower_slice within_layout + lowerSlice_layout. Next: F2 (extractor in Lanius), plan in target/claude-work/reports/F2_PLAN.md. Gate: bash target/claude-work/scratch/f1/gate_all.sh (29 steps).

# CURRENT (2026-10-29, latest): V1-V8 done and pushed (origin/lang at 8c638ca9). User: verify the FULL compiler (the Lanius-written formal compiler, whole language, not the GPU compiler) incl. the extractor. Plan = formal/ROADMAP.md section 'The full verified compiler' F1-F13; extractor decision: proof-producing (CakeML style), moved into the verified compiler (F2). Working F1 (Reading determinism -> drop TextBuilt; lowerSlice layout limits).
# CURRENT (2026-10-29, latest): verified compiler V1-V8 ALL DONE (local commits, unpushed through 8c638ca9: push needs the user's yes). V8: formal/Lanius/Mini/Reading/* (relation Reading roots sp; buildFiles_sound in Reading/Program.lean), TextCorrect: TextReading = relation, TextBuilt = old builder-based (unique), statements carry both. Open (not in roadmap): determinism of the relation + fuel adequacy; lowerSlice should reject element types past Core layout limits (builder change). No work in flight; await the user's direction.
# CURRENT (2026-10-29, latest): verified compiler V1-V7 DONE (local commits, unpushed: push needs the user's yes). V7b: Faithful/Safe/* (func_safe: pure subset + boxed/unbox never trap undefinedly), Faithful/SafeDriver.lean (read_safe, write_safe, put_safe, driver_safe), selfCompiler_outcome now Faults | Returned with SelfOutput (no undefined disjunct). Next: V8 (the reading as an inductive relation on parse trees, build proved sound against it). Follow-up: lowerSlice should reject element types past Core layout limits.
# CURRENT (2026-10-29, latest): verified compiler V1-V6 DONE + V7a DONE (local commits, unpushed). V7a: Mini/SourceOutcome.lean (compileSource_outcome_from), Faithful/SelfCompiler.lean (selfStart/selfHeap layout, selfCompiler_outcome: Faults | Returned with SelfOutput (compileText files) | undefined trap). self_host.py native heap = theorem layout (input at 4, cursor selfNext). Next V7b: prove Core run of prog's w from selfStart never traps undefinedly (typeMismatch + 4 raw-memory traps): safety theorem for pure subset mirroring func_sim (Faithful/Sim), plus driver (oracle_read/put/write, slices) by hand; then V8.

# CURRENT (2026-10-29, latest): verified compiler V1-V6 DONE (local commits, unpushed: push needs the user's yes). V6: compiler.lani process section (elf_file; extracted to Mini/Compiler/P/larger.lean), Mini/Process.lean (Loaded/Exits trusted Linux spec; startup, atEntry_premises, exit_steps, process_exits/_behaviour, textProcess_*), runAll `elf` manifest line, gate step `elf` (formal/tools/elf_test.py). Next: V7 (self-built compiler emits the ELF; CakeML-style theorem), then V8.

# CURRENT (2026-10-29, latest): verified compiler V1-V5 DONE (local commits, unpushed: push needs the user's yes). V5: Mini/TextCorrect.lean (compileText_correct/_behaviour), Mini/TextWords.lean (driver words = filesWords; frontEndWords_files/_some, compileWords_files/_some), Faithful/SelfDriver.lean driver_files. The driver reads source bytes now (self_host.py layout from BASE.lani/.prods/.parents). faithful tactic gained an eq_def closer (Auto.lean). Next: V6 (ELF startup/exit wrapper composed with V5).
- After frontend.lani edits: extract, pipeline.sh GENONLY=1, faithful_pure.py, l2/build.sh SelfCert (resumable), lb Lanius.Faithful.SelfDriver, lake build runAll, then gate groups. After grammar changes also grammar_cert.py.

# CURRENT (2026-10-29, latest): verified compiler V1-V4 DONE (local commits, unpushed: push needs the user's yes). V4: picks rule in frontend.lani (validator), Mini/Unique.lean (Cert.parse_unique), Mini/GrammarCert.lean (generated by formal/tools/grammar_cert.py; kernel check 26 s, 3.6 GB), Mini/ParseUnique.lean (grammar_unique, validate_unique, sourceProgram(Files)_determined). Next: V5 (compileText_correct: driver from bytes via lex_source, one theorem text+untrusted tree -> x86).
- After frontend.lani edits: extract, pipeline.sh GENONLY=1, faithful_pure.py, l2/build.sh SelfCert (resumable), lb Lanius.Faithful.SelfDriver, lake build runAll, then gate groups. After grammar changes also grammar_cert.py.

# CURRENT (2026-10-29, latest): verified compiler V1+V2 DONE (local commits d2c1311f..ff8abf67, unpushed: push needs the user's yes). V3 DONE (lexSource_eq, formal/Lanius/Mini/LexCorrect.lean; lani lexer section in frontend.lani). Now V4 (grammar unambiguity). After frontend.lani edits: extract, pipeline.sh GENONLY=1, faithful_pure.py (target/claude-work/faithful/Self.lean formal/Lanius/Faithful/Gen/SelfProg.lean formal/Lanius/Faithful/Gen), build SelfCert (l2/build.sh, resumable) and Lanius.Faithful.SelfDriver.
- V2: compileSource_stops / compileSource_behaviour (formal/Lanius/Mini/SourceStops.lean), stmtStops_all (EvalStops.lean). Gate step `traps` (tools/trap_test.py).

# CURRENT (2026-10-28, latest): state-machine phases M0-M5 ALL DONE and pushed (M4 068c0541, M5 49e5d155). No work in flight; await the user's next direction.

# CURRENT (2026-10-28, latest): M1 implemented, full regression running (p2/reg/m1b.*); M1a regression (m1a) clean vs known. Then commit+push M1, start M2.
- M1 files: grammar arm_block (prod 326), tokens/delimiters/04_owner_apply (`{` after raw `->` = IfLBrace), hir/expr/fields, 10n (block = never), returns/01_mark+03_validate (BLOCK_ARM_FALLS_THROUGH 0x20000005, build.rs count 26), compiler/machine_elaboration.rs hooked in helpers.rs prepare_* and gpu_public_api read loops + diagnostics.rs label mapping; tests/machines_execution.rs + fixtures/machines; extended/ext/openssl_tls.lani Lifecycle machine (orig in target/claude-work/m1/openssl_tls.orig.lani); generate_library_reference.py knows `machine`.

# CURRENT (2026-10-28, latest): state-machine phases M0-M5 (docs/state-machines-design.md) approved; commit+push each. M0 DONE 163066b6. Now M1 (`machine` syntax, R1-R5, elaboration by reinterpretation; evidence: codegen test step rows == hand-written, ext::openssl_tls State ported).
- M0 pieces: extended/ext/sqlite_statement.lani, formal/Lanius/Machines/{Machine,SqliteStatement*,SqliteStatementCorrect}.lean, gate step machine-sqlite, tests/extended_sqlite_statement_execution.rs, benchmark_artifacts/machines_m0 (step 1.348 s / direct 0.506 s scan time).
- sqlite tests need LIBRARY_PATH=$PWD/target/claude-work/libs (libsqlite3.so symlink); sqlite3.h-dependent tests cannot run here.

# CURRENT (2026-10-27, latest): ALL phases 1-5 of the 10-27 plan DONE and pushed (0c037c80, a3a9a87f, 11e658b6, ce1d2d84, b8721d84). No work in flight; await the user's next direction.

# CURRENT (2026-10-27, latest): Phase 4 implemented (uncommitted), full regression running: p2/regall.sh p4 '*' (logs p2/reg/p4.*; summary p2/reg/p4.summary)
- &mut: TK_MUT 203 (lexer keyword), TK_TYPE_AMPERSAND_MUT 204 (parser retag of `&` before `mut`, keeps LL(1)); productions type_ref_mut 324, param_self_ref_mut 325.
- Exclusivity: shaders/type_checker/conditions/compact_exclusive.slang, detail EXCLUSIVE_REFERENCE_ALIAS 0x20000004 (LNC0006). Param name_token of &self/&mut self is the `&` (also fixed compact_distinct's receiver skip).
- Pilot: formal/lani/mini/mut_pilot.lani -> Lanius/Mini/MutPilot.lean, MutPilotCorrect.lean (7 theorems), gate step mut-pilot (fn_difftest --source/--lean-module). Gate 10/10.
- Callers need `.borrow()`/`.exclusive()` style methods: a plain value is not accepted for a `&T`/`&mut T` param.
- Next: regression clean vs known failures + lib tests -> commit + push Phase 4 -> Phase 5 (commit docs/state-machines-design.md).

# CURRENT (2026-10-27, latest): Phases 1-3 pushed (0c037c80, a3a9a87f, 11e658b6); next Phase 4 (&mut + exclusivity check + Aeneas-style extraction pilot), then Phase 5 (commit docs/state-machines-design.md)
- Phase 3 scratch: target/claude-work/p3 (bench binaries, run_bench.py). Regression helpers: p1/reg.sh LOG suites; p2/regall.sh PREFIX GLOB.
- Mini frontend: after grammar changes rerun formal/tools/grammar_table.py + extract.py on formal/lani/mini/frontend.lani, lake build runAll, gate.py.

# CURRENT (2026-10-27, latest): Phase 2 implemented, full regression running (p2/regall.sh all '*', logs p2/reg/; check with p2/check_new.sh)
- distinct + requires done (docs/verified-facts-design.md). requires fix: contract ELSE/TRAP/END rows at hir.token_end rank 0 (cond span includes parens so IF_BEGIN is last on `)`).
- Debug: LANIUS_DEBUG_CAPTURE_PASS=codegen/lir/optimization/structure_dominator_validate + decode bins (blocks = fn,pos,term,edges).
- Next: regression clean vs tests/known_test_failures.txt -> commit + push Phase 2 -> Phase 3 scoped stacks S0.

# CURRENT (2026-10-27, latest): Phase 1 of the 10-27 plan DONE; see memory lanius-phase-plan-10-27
- PHASE 1 DONE: commit 0c037c80 pushed to origin/lang. Next: Phase 2 (distinct via optional `distinct` symbol in the alias production + brand-check pass; requires/ensures as debug traps; docs/verified-facts-design.md).
- Done: 7 generic failures, sample DEDICATED.tsv, scatter 30640/30687 (schedule.slang split), wasm f64, codex fixtures (B1 static_result, B2 hash_insert, D, E, F, G, H, I, C_blanket, png fixed; READMEs carry "Status (2026-10-27)").
- Open with diagnosis in their READMEs: B1 partial_cmp (dependency method result has no checked row under a scrutinee), B2 buffered (needs receiver-context projection in 03a4b), B2 resumable (depends on another unit's generic body; q4/q5 reductions), J (deliberate 0xffff width limit), C_fixed_cap, cluster A, C foundation.
- Regression scripts: target/claude-work/p1/reg.sh LOG suites..., regall.sh PREFIX 'glob'; the pre-existing stdlib failures are now in tests/known_test_failures.txt (4 checked at 61df289b).
- Next: extended_* + remaining suites, commit + push Phase 1, then Phase 2 (distinct, requires/ensures, docs/verified-facts-design.md).

# CURRENT (2026-10-25, latest): certificates by name, committed 27b48289 + chain-of-tails lookups (unpushed); body edit 17 s, add function 30 s, cold ~7.5 min
- Edit loop: `target/claude-work/l2/pipeline.sh` (extract both .lani, prep_self + faithful_dump, faithful_certs with roots by name, build SelfCert; GENONLY=1 skips the build). Measurement edits: l2/addfn.py [revert]; body edit = `+ 0` in slot_offset (compiler.lani line 586).
- Layout: SelfSrc/Stmt/Proof/Look per bucket = extraction part of the head (C_<part>/F_<part>) else crc%8; Stmt_name abbrevs; link uses fn_K/np_K from Look (np by decide +kernel).
- Front end numbers locals from the fn name token (FrontEnv.base); Sim/Boxed, Unbox, Slice, SizeOf, Check templates renumbered; faithful_pure.py reads prims from SelfProg.lean.
- extract.py: private imports for hidden-body references; fixparts.py adds names to Mini import-parts blocks when a build says "imported privately".
- Lookups: prog = chain of named tails; SelfLook (at_K chain, drop_next) + SelfLookFn0..5 (fn_K get_of_drop, np_K decide +kernel). Add-function critical path: SelfProg 5 s -> SelfLook 2.5 -> LookFn 3 -> SelfCert 4. Next: the top theorem.

# CURRENT (2026-10-25, latest): certs as Lean modules, committed 7e763b3e (unpushed); body edit rebuild 41 s (was ~8 min)
- Module system (experimental.module in lakefile). Closure of SelfCert is `module`s; infra `@[expose] public section`, Tactic/Auto `public meta section`, Attr expands register_label_attr with `public meta initialize`. `private` dropped in converted files.
- extract.py: Compiler/Frontend split into parts P* (8 defs, hidden bodies); `-- import all: Lanius.Mini.Compiler` blocks rewritten by extract.py (Mini Semantics/Source/Unsigned/Shifts/LowerExpr/Grows). Non-module files see all bodies (LaniusMini proofs untouched).
- faithful_certs.py: SelfTypes (exposed), SelfSrcK (hidden, per proof module), SelfSrcRest, SelfProg (exposed prog), Self re-export; proofs `import all` own SelfSrcK + head parts (callee parts only for CALLEE_BODIES = effNode, exprOf).
- Measured: edit one Compiler part -> P, 6 Mini modules, 1-2 proof modules, link = 41 s. Adding/removing a function still renumbers indices -> full rebuild (~6 min). Next: name-keyed certs/stable chunks; then top theorem.

# CURRENT (2026-10-25, latest): whole bootstrapped compiler certified (1,547 certs, standard axioms), new incremental layout
- Gen/: SelfStmt (statements, no Auto import), SelfProof0..38 (independent; callee certs as `ext{c}` hyps; recursive groups as `step{i}`), SelfCert (link, ~2 s). Generate: `python3 -I formal/tools/faithful_certs.py [--dev] target/claude-work/faithful/Self.lean Lanius.Faithful.Self formal/Lanius/Faithful/Gen 14 15 16`.
- Build: `THREADS=3 MEM=8G LIMIT=290 target/claude-work/l2/build.sh` (two passes from scratch; 3 parallel fits 8G). failures.py [LOG] [N..]; one.sh MODULE NAMES (keep.py; PROFILE=1).
- Tactic fixes 10-25: repOf? cleanupAnnotations (pending never fired before), iteSplit (rw if_pos/neg; split at * hits 100k simp steps), ||/&& reassociation pure_rules, pinnedClash (constant clashes + substitution), casesKnown gated on use (grammar tables were >7 GB), maxRecDepth 100000, depth 100.
- Next: commit (after non-dev build + gate), then top theorem (driver + call_sim + certs), then name-based per-function statements so source edits rebuild only dependents.

# CURRENT (2026-10-22, latest): integ2 PUSHED to origin/integ2 (2f393cc4, user asked "push all work to remote"); all agent branches merged
- M11a/M11b done (self_compile.py, 400 tests each, 800/800 agree). Step 10 S3-S7 + set algebra merged (Std builds, standard axioms). Box agent: compiler.lani lowers whole.
- M11c: self_host.py + lake exe runAll (diag mode). Self program reads (1,646 fns), all compiler fns lower; driver fixed to i32 lengths; rerun pending: `python3 -I formal/tools/self_host.py target/claude-work/m11c`.
- No agents running. Future pushes still need the user's yes each time.

# CURRENT (2026-10-22, latest): shifts done (8e0bce9c), front-end agent merged (176c0d14), M11a passes (self_compile.py, uncommitted until run40 is green)
- Shifts: BinOp Shl/Shr/Sar by cl, Mini/Shifts.lean, 77 x86 forms; difftest/shift.log all green.
- M11a: formal/tools/self_compile.py --stage encode (default): encode_from compiled by the verified compiler (frontEndFiles + compileSource, native), by laniusc, and Lean #eval agree. `w` must be the first function (native call uses entries[0]). 3/3 at seed 1; run40 = target/claude-work/m11a/run40.log. --stage program (M11b, compile_program on mini_difftest programs) written, not yet run.
- Agents: a7ac357024e94907f Vec S3-S7 (merge its commits: b9707e36..67f26821 so far; row 10 conflicts). a1dcdb3032e5a235e NEW: step 6 Box<T> at enum-in-enum element types (98 of 646 compiler.lani instances fail lowering) -> needed for M11c.
- Next: run40 green -> commit harness, ROADMAP row 11; run --stage program; M11c = whole compiler self-compiled + fixpoint.

# CURRENT (2026-10-22, latest): F8 stage 2 done (d985ff2e proofs, 001a31cb oracle); step 10 S1/S2 merged (b6abed94); all difftests green (difftest/f8s2.log)
- F8 stage 2: Mini/ElementLayout.lean replaces FlatLayout (FieldReads/FieldWrites over Core words?/fieldOffset/payloadOffset); compiler.lani word_type/load_type/store_type mutual recursion; slice elements = any word type, enums nested anywhere. Oracle declares structs/enums in random order (NESTED).
- Agents: a7ac357024e94907f resumed on its branch for S3 rest + S4-S7 (merge its later commits; ROADMAP row 10 conflicts likely). ad9e076696388ebab front-end gaps (type aliases, unsigned/ptr/big literals, scalar method calls, panic arm, shifts) still running.
- Next for me: merge agents as they report; step 11 M11a (encoder slice self-compile; slot[0] on typed slices now possible), step 3 small-object allocator, step 12 stdlib gaps. Push still needs the user's yes.

# CURRENT (2026-10-22, latest): F8 committed (fd961941) + both agents merged (962c5417 front end, 643b256f stdlib oracle); difftest run_f8.sh running (log difftest/f8.log)
- F8: Mini/FlatLayout.lean (Leaves, Flat, WriteChain; Core words/offsets/reads/writes by leaves; mini holds by leaves); SliceLayout trimmed to one-word facts; LowerStmt exec_storeChain replaces exec_storeFields; front pass also copies aggregate fields in EPure (eval_field_copy). Oracle generates nested struct fields/payloads (NESTED flag; frontend_difftest sets it False). 100 oracle programs green before commit.
- New agents (10-22): a7ac357024e94907f = step 10 S1-S3 (formal/Lanius/Std/ only); ad9e076696388ebab = stdlib/self-host gaps (type aliases first, unsigned literals, ptr literal, big literals, shifts last). Both on worktrees from 643b256f.
- Next for me: wait for f8.log; then enum fields inside slice elements (F8 stage 2: enum leaf = tag word + max payload), S7 compileSource_correct with an initial HeapCorr heap, keep ROADMAP current. Push still needs the user's yes.

# CURRENT (2026-10-22, latest): C2, C4 (descending ABI) and C3 (mini widths) committed; all difftests green
- integ2 (unpushed): aa3be1ac C2 slice_stride, merges, 89ed2705 C4 (Core layout = laniusc: word 0 highest, fields/payloads/elements descend, slices 3 words; NativeStoreSpec slot = size bytes ending at addr+8; raw field place subtracts), fd0d4d33 C3 (u8/u32/u64/isize slice fields).
- User 10-22: "stop asking for my input" -> decide design questions myself, record in TRUSTED_BASE/ROADMAP.
- Runners: target/claude-work/difftest/run_c3.sh / run_c4.sh (bump seeds). Logs c3.log, c4.log green.
- Agents: front-end a408df595f188db35 (slice-return form, step 11 gaps), oracle afb60bef2c6097a49 (step 12 stdlib oracle). Merge when they report (their bases predate C4: expect conflicts in oracle_difftest.py WORDS and Compiler.lean -> re-extract).
- Next: F8 nested aggregates in slices (flatten word structs recursively; enums per variant), then step 10 specs S0-S7.

# CURRENT (2026-10-22, C1 done): C1 committed on integ2 (raw views: Heap.checkRange, heap unchanged); full build only has the 2 old failures (Lexer/Artifact, ELFExecutionBridge); all difftests green (difftest/c1.log)
- Next: C2 (Intrinsic.sliceStride in Core) + F3 slice_stride/size_of, F11 slice params/returns, F8 nested aggregates in slices, then std::vec (stdlib/std/vec.lani uses typed_slice_from_storage / typed_prefix_from_storage from stdlib/core/mem.lani).
- Agents: front-end a408df5 (isize random runs + F9 constants), oracle afb60be (STEP11_GAPS.md). Merge when they report.

# CURRENT (2026-10-22 later): F1 isize done + merged (front end reads it, oracle generates it, laniusc empty-unit-fn bug fixed 3f0a546b); all difftests green
- User APPROVED C1 on 10-22 (raw views keep owned; i32 views any 4-aligned range in one live block). I'm doing C1 now: Heap.checkRange replaces protect*AsBorrowed; fix ~15 dependent files; full `lake build` (all of Lanius) under systemd-run cap.
- Agents: front-end a408df5 = isize in random runs + F9 constants; oracle afb60be = STEP11_GAPS.md gap analysis.
- ALWAYS run lake/lean under `systemd-run --user --scope -q -p MemoryMax=6G -p MemorySwapMax=0` (Lean OOM crashed desktop 10-22).

# CURRENT (2026-10-22, latest): F5 done (eb9aee1e: unit fns, return;, assert); oracle + front end merged (e73e694f), all difftests green; 2 agents
- Oracle agent afb60bef2c6097a49: F5 generation (unit fns, return;, assert, unit calls). Front-end agent a408df595f188db35: read unit fns, return;, assert, panic.
- Next for me: F1 (isize), F9 (constants), F11 (slice params), F3 (slice_stride/size_of), F8 (nested aggregates in slices), front-pass modules. Vec needs step 6 / C1; C1 still waits for the user's OK.

# CURRENT (2026-10-21, latest): F7 done (element reads/writes, SetFieldEval); starting F5; 2 agents

- Committed on integ2 (unpushed): e692cc88 effectful struct/enum element reads, 5876d4fa element writes, SetFieldEval commit, 4910a189 merge of front end (build reads effectful forms) + oracle (struct/enum element reads and writes).
- Known: frontend_difftest.py non-generic with EFFECTS crashes (generator emits setIndexEval; printer lacks it). Front-end agent a408df595f188db35 fixing it + reading SetFieldEval. Oracle agent afb60bef2c6097a49: SetFieldEval generation.
- Runner: target/claude-work/difftest/run_f7s8.sh (bump seeds each run).
- F5 plan: SrcType.Unit (1 slot, any bits hold .unit), ReturnUnit -> .returnValue none, Assert(SrcEff) -> .expression (.intrinsic .assert e) lowering to e's code only; unit functions get a final Return [Lit 0]; Matches needs a .returned none case; call proofs need Core's .returned none / .next unit cases. C1 still waits for the user's OK.

# CURRENT (2026-10-21, latest): F7 stages 1-3 (EMatch pending commit); 2 agents

- Committed on integ2 (unpushed): 40839305 F7 s1, 6c9495c2 division merge, 3d088065 front-pass / %, e040a2fa F7 s2 (struct/enum literals), 3e20136e F7 s3a (EIndex), fed4873b merge of oracle Eval forms (3ef54fb5).
- F7 s3b EMatch (uncommitted until run_f7s3b.sh passes, log difftest/f7s3b.log): constructor is now EMatch(scrutinee, ety, ty, binders, values); scrutinee in slot, arm at matchDst = slot + max(ety.size, ty.size), copied down. Proofs: armScope_layout, evalArms_sound, eval_match (LowerEval); evalArms_typed (TypeSound). Helper renamed match_variants (Frontend.lean has variantsOf).
- Agents: a408df595f188db35 front end (generics/mono/heap/+=) still running; afb60bef2c6097a49 resumed for oracle EIndex generation (told: no EMatch yet).
- Next: commit EMatch, tell oracle agent the EMatch shape, then SetFieldEval/SetIndexEval, F5, F1, F8, front-pass modules. C1 still waits for the user's OK.

# CURRENT (2026-10-21, latest): F7 stage 1 proved; division agent done (merge pending); 1 agent

- F7 stage 1 (uncommitted until difftests pass): SrcEff (EPure/ECall/EApply/ENeg/ENot/ECast proved; EIndex/EStruct/EVariant/EMatch lower to None for now) + LetEval/SetEval/IfEval/WhileEval/ReturnEval/Discard. Proofs: formal/Lanius/Mini/LowerEval.lean (EvalSound + sound_both by strong induction on fuel; stmt_sound now lives here), TypeSound cases (SrcEff.eval_typed mutual), Grows (eff_grows). LaniusMini builds, 4 axiom checks standard. SrcEff's lists are Box<List<SrcEff>> in the .lani (laniusc rejects List<SrcEff> by value: infinite size); extractor erases Box so Lean unchanged.
- Difftest runner for this: target/claude-work/difftest/run_f7s1.sh (mini 67, fn 43, oracle 47).
- Division agent a8116e1b198a3bd38 DONE: commit d85a9531 on worktree-agent-a8116e1b198a3bd38 (base 3c28e9c2). Merge after F7 commit; regenerate Compiler.lean via extract. It added a `divide` arm to Exec.mono in LowerStmt.
- Front-end agent a408df595f188db35 still running.
- Next: commit F7 s1, merge division, spawn agent for oracle Eval-form generation (tools/oracle_difftest.py), then F7 stages 2-3, F4 front-pass lowering of / %, F5, F1, F8. C1 still waits for the user's OK.

# CURRENT (2026-10-21, latest): enum slices, ptr±usize, oracle slices, step 8+9 merged; 2 agents

- Committed on integ2 (unpushed; push needs the user's yes): 74453c5b enum slices, 3c28e9c2 ptr + usize / ptr - usize in the front pass, 888de269 oracle heap+slice programs (oracle_difftest.py SLICES flag; 320 programs ok), 00542f35 merge of step 8 front end (validate renamed validate_tree; frontend_difftest sets oracle.SLICES = False).
- Plan for steps 10-11: target/claude-work/reports/STEP10_11_PLAN.md (Core C1-C3 fixes; front-pass F1-F11; specs S0-S7; M11a). C1 (raw views keep `owned`, i32 sub-range views) changes Core's meaning: ASKED THE USER, waiting for OK. Don't start C1 without it.
- Agents: a8116e1b198a3bd38 = F4 division/remainder in the mini IR back end (worktree, back end only). a408df595f188db35 = front end (frontend.lani): heap/slice constructs, += desugaring, generics + mono. Merge when they report.
- Me: F7 effectful expressions in the front pass (calls inside expressions, Index, literals, match with effectful arms, short-circuit), design in target/claude-work/reports/F7_DESIGN.md. Then F5 (unit functions, assert, panic), F1 (isize), F8 (nested aggregates in slices).
- Test runner: target/claude-work/difftest/run_structslice.sh (seeds now mini 66, fn 42, oracle 46; bump before each run).

# CURRENT (2026-10-21, latest): 6(d) struct slices + step 13 merged; 2 agents

- Committed on integ2 (unpushed): bfbabe71 6(d) word-struct raw slices (SliceLayout.lean, exec_loadFields/exec_storeFields in LowerStmt), 16073785 merge of step 13 (validated optimizer; compile_lowered -> compile_optimized; compileOptimized_deterministic in Determinism). Step 14 determinism merged earlier (5007a926).
- Tests after merge: mini_difftest 201, fn_difftest 265 fns as 4 shards (`--shard i/4`, per-fn 20), oracle 300 programs: 0 differences. Runner: target/claude-work/difftest/run_structslice.sh (NO_ORACLE=1 to skip oracle). Axiom check for determinism: target/claude-work/mini/axioms_det.lean.
- Agents still running: a926654e9fa771560 step 8 front-end validation; ab47291879600e03e step 9 separate compilation. Merge when they report.
- Next for me: enums in slices (tag word + payload words, Core readNativeValue/writeNativeValue enumeration), then oracle on heap/slices, then Vec/generics (10, 11).

# CURRENT (2026-10-21 latest, after a desktop crash): steps 7, 12 started/done pieces; 2 agents

- Committed on integ2 (unpushed; push needs the user's yes): 9678e15b step 7, 0adeffe9 raw i32 slices (6(d) part), c2127511 step 12 oracle tool (formal/tools/oracle_difftest.py; 2,300 programs agree; `--only K` reproduces).
- Agents (resumed after the crash via SendMessage): a1600da0e09d31be8 step 14 determinism (uncommitted work in its worktree: DecodeUnique/DetSteps/Determinism/StepDet.lean); ae4ebeef180187de8 step 13 validated optimizer. Merge when they report.
- Me: 6(d) struct-element typed slices (Box). Plan: element struct with >=1 fields, each i32/bool/usize/ptr (one native word); words = field count; base = p - (i*w + w-1)*8, field j at base + 8j; i32/bool M32, usize/ptr M64. Core: mapRawNominalSlice (HeapCorr.protectRange exists), readNativeValue structure, writeNativeValue structure (foldlM). Then enums, then Vec (needs generics: steps 9-11 later).

# CURRENT (2026-10-21 late): step 6(c) done (83f34a4e), working 6(d); 2 agents running

- User asked "use subagents to go faster": 2 background agents in worktrees: step 7 (type checker soundness, new file formal/Lanius/Mini/TypeSound.lean) and step 14 (formal/TRUSTED_BASE.md + formal/tools/x86_model_test.py, x86 model vs CPU). Merge their branches when they report. No GPU work for them.
- 6(d) plan: (i) back end: mini IR `LoadWord(MemWidth, target, address)` / `StoreWord(MemWidth, address, value)` (M32 | M64, little-endian; mini Heap.readLE/writeLE), Instr LoadWordAt(w) = add rax,r12; mov eax/rax,[rax+0] and StoreWordAt(w, slot) = mov rcx,[slot]; add rcx,r12; mov [rcx+0],eax/rax (X86 load32/load64/store32/store64 exist; memoryBytes encodes). (ii) front pass: Core `typedSliceFromRawParts T p n` (struct/enum T; protectRangeAsBorrowed only flips `owned`, HeapCorr survives), `s[i]` read (readNativeValue: i32/bool 4 bytes, usize/ptr 8, struct fields one word each, enum tag 4 bytes + payload words; descriptor points at element 0's HIGH word, elements go downward, NativeLayout.elementBase?) and `s[i] = v` (writeNativeValue). Mini slot layout = native word layout. Box<T> = 1-element typed slice.
- Top theorem now: mini heap cursor 1, zero bytes from 1, limit < 2^62, final Core nextAddress <= limit. Native runs of compiled source must start r13 = 1.

# CURRENT (2026-10-21 night): verified compiler step 5, returns done

- User: "keep working until all of 1 through 14 is done" (memory verified-compiler-roadmap.md). Work step after step without asking; status column in formal/ROADMAP.md is the source of truth.
- Unpushed on integ2 (push needs the user's yes): fb6f3310, 70a4134f, 3c59afe3, 895258a8, 8b62cff5, 19943ee7, 7bd9995f, b59dc41b (structs), eccb868d (enums + match), 8c7ca9a6 (struct/enum returns: multi-slot Call/Ret in the mini IR; results replace the arguments below the return address, eax = last).
- Checks: `lake build LaniusMini` from formal/ (PATH=$HOME/.elan/bin). Difftests: mini_difftest.py (201 programs ok), fn_difftest.py needs PATH with elan and `--per-fn 20` (30+ trips a laniusc GPU buffer failure); native harness target/claude-work/mini/native.lean + run_native.py (3,368 calls ok, includes 2-result swap).
- Next: step 5 `match` arms with statement bodies; then Vec (needs step 6 heap) and generics; then steps 6-14.

# CURRENT (2026-10-21 evening): verified compiler roadmap, step 4 done, step 5 structs done

- b59dc41b: structs in the front pass, proved (scalar fields; literals, field reads/writes, copies, struct params; returns stay scalar). Unpushed too. Enums + match done next commit (tag + payload slots, match -> tag-test chain, binders alias payload slots; fn_difftest needs --per-fn 20 now). Next: struct/enum returns (backend multi-slot returns).
- Lean 4.33 handles nested inductives (List of self) with mutual structural recursion; `deriving DecidableEq` fails on them.

- User said "ok awesome do all of that" to formal/ROADMAP.md (14 steps; order 3, 1, 2, 4, then 5-14). Status column in ROADMAP.md is the source of truth.
- Unpushed on integ2 (push needs the user's yes): fb6f3310 parser `<` fix, 70a4134f MAP_32BIT removed, 3c59afe3 cons list, 895258a8 fn difftest, 8b62cff5 front pass, 19943ee7 expr proof, 7bd9995f statement proof + top theorem.
- Step 4: compile_source (end of formal/lani/mini/compiler.lani) lowers a typed Core subset to the mini IR. Proof: Source.lean (toCore), LowerExpr.lean, LowerStmt.lean (Corr/Layout/Keeps, stmt_sound by Nat.strongRecOn on fuel), SourceCorrect.lean (compileSource_correct, standard axioms). Docs in MINI_COMPILER.md "The front pass".
- Lean gotchas this round: omega doesn't see through `CellId` (use the `cell_omega` macro in LowerStmt); `matches` is a keyword; implicit autobound args come first (use named args); `have x := f ..` with implicit-heavy defs needs a type ascription.
- Next: step 5 (structs, enums + match, Vec, generics) on the front pass; step 3 leftovers (small-object allocator, block/if match arms).

# CURRENT (2026-10-21 afternoon): the mini compiler is finished (milestones 1-4)

- main = origin/main = 441e66f9 (milestones 1-4, pushed 10-21). Parser fix for match-arm commas after a comparison `<` (shaders/parser/tokens/match/pattern/arm_comma.slang + test x86_executes_match_arms_after_comparison_angles) committed on integ2 after that; push needs the user's yes.
- Lean 4.33.1 via elan: `export PATH=$HOME/.elan/bin:$PATH`, then `lake build LaniusMini` from formal/ (clean mini rebuild 9.8 s).
- Strategy: memory verified-compiler-strategy.md (CompCert shape, pure compiler, shallow extraction, top-level theorem first). Say "the verified compiler", never "VC".
- Milestone 4 (441e66f9): formal/lani/mini/compiler.lani (pure Lanius + prelude) -> formal/tools/extract.py -> formal/Lanius/Mini/Compiler.lean (generated; `--check` mode). Hand-written Syntax/Compile deleted; proofs run on extracted defs; `compileProgram_correct` standard axioms only. Encoders proved equal to X86 ones (Instr.encode_eq, prologue_eq). Details + limits in formal/MINI_COMPILER.md.
  - Difftest: `python3 -I formal/tools/mini_difftest.py target/claude-work/mini/diff --count 300 --seed 2` (seeds 2, 3: 602 programs, 0 mismatches). Native: target/claude-work/mini/native.lean + run_native.py (2,368 calls ok).
  - laniusc findings: a bare `<` comparison earlier in a file breaks later `Type::Ctor(..)` patterns (spawned task chip "Fix laniusc parse of Type::Ctor after bare <"); match arms are expressions only; runtime allocator = one MAP_32BIT page per allocation (1 GiB window, ~262k live allocations).
- Lean hazards: wildcard-match equation timeouts; `Step` clash (write Lanius.X86.Machine.Step); constructor implicit order = autobound order (#check); `8` vs `8#64` literal forms; `Int.ofNat` must be normalized (Int.ofNat_eq_natCast) before omega.
- Next (not started): the full verified compiler in the same style. Ask the user before choosing the next step.

# CURRENT (2026-10-20 night): read this first

- main = integ2 = 6c7085e1. **No agents running.** Perf work paused by the user. Lead is filling out the generic stdlib (user's request).
- Committed today (all on main):
  - 1c504c39 generic heap `std::vec::Vec<T>`; core::cmp Eq/Ord impls for every integer width; per-type vecs deleted.
  - 99a9be13 wide vecs -> Vec<WideI64/U64>; b15 fixed (impl_bindings binds same-unit impls; TemplateBlanking remaps same-unit dependency targets). b02/b13/b15 -> matrix p79-p81.
  - def44c60 explicit `as` casts in 17 samples/fixtures (checker rejects implicit int conversions).
  - 12906520 generic core::option / core::result (contains via Eq, unwrap/unwrap_err panic, ok_or/ok/err, free + method forms); Eq<f32>, Eq<ptr>; 22 option_*/result_* modules deleted; fixture tests/fixtures/stdlib_foundation/core_option_result.lani.
  - dbcd66d8 generic core::range (Range<T> etc. over Ord, 20 fns + 15 methods); Ord<f32>; range_* and wide_*_range modules deleted; fixture core_range.lani. full3.log after it: same failures as full2 (4 range-test fixes went in before the commit).
- Full test run after 12906520 (log target/claude-work/lead/out/full2.log + the 4 fixes after it): only pre-existing failures remain (cli_daemon 2, cli_diagnostics 4, cli_lsp 1, codegen_x86_properties 3, CGTE 7 known, raytracer 2 (wrong image on x86 AND wasm, pre-existing, unowned), sample_program_manifest/x86/wasm (missing .stdout files, pre-existing), runtime_contract alloc pointer 1, type_checker_generics 2, type_checker_semantics 5). Matrix x86 99/99.
- Backlog: b14 (Type::method(self) path call), b16 (Wasm: fn returning imported generic enum = invalid module), b17 (imported impl method returning record T from a generic body lowered as 4-byte scalar on x86).
- Other gaps: `print(str)` prints the pointer; `Vec::new()` needs `Vec<i32>::new()`; panic = SIGILL (-4) vs bounds 101; allocator = one mmap per allocation; Wasm can't compile std::vec programs; no slice length intrinsic; `Err(0)` as a bare argument can't infer T (expected).
  - 4fd177bc generic core::slice (40 fns, Eq/Ord) + core::ops::SaturatingAdd; 10 slice_* modules deleted. b18 recorded (`check` rejects imported-trait bounds; verify by compiling).
  - 2f25e486 generic std::deque::Deque<T> (20 fns) replaces 10 deque_* modules; full5: 30 known failures only.
  - 6c7085e1 generic std::set::Set<T> (19 fns) + std::map::Map<K, V> (16 fns) replace 10 linear set_*/map_* modules; full6: same 30 known failures as full5. Dense caller-backed set_bool/u8/i8, map_bool/u8/i8_u32 left (different API).
- Lesson: `git add -u PATHS` skips untracked files; stage new files with plain `git add`, check `git status` is clean before committing.
- Lesson: `open(f,'w').write(f(open(f).read()))` truncates before reading — read first.
- Next stdlib steps: dense small-key set/map design; String type replacing utf8_vec/vec_u8; number_* vs i8/i16 duplicates; file/io/binary/hex wide variants; core::set/core::vec inline Key-trait workaround.
- Lessons: never dedupe imports file-wide in .rs (embedded programs); avoid `cd X &&` and `rm $var/*` in Bash (permission prompts).
- Probes: target/claude-work/lead/optres/*; run `heavy --quiet python3 tools/generics_matrix.py --laniusc target/release/laniusc [--stdlib DIR] --probes DIR` (negative `// expect:` = signal).

# Lead resume state (written 2026-10-15 ~12:55, before a Claude Desktop restart)

Goal (set by /goal): generics working in Lanius; 30 KSLOC in < 100 ms with a pre-warmed
instance; compilation-service startup < 5 s with a warm shader cache.

## Where things stand
- **generics-gpu = 2be4b52c** (2026-10-17 21:47; f80e33a4 + P11 D0 352e48ea). Pin target/laniusc-pins/5c661f23c7d3ecbb/laniusc. integ15 green: matrix 43/43, casts 6/6, c-probes, m-probes, stdlib 180/180, stdlib_foundation 17/17, backlog 1/15 (unchanged), quiet 1 MB 64.0 ms compile / 66.5 ms wall.
- **generics-gpu = integ2 = f67f022a** = 2be4b52c + P9 d29fa859 + P12 03ab603f (u8 stride + as-usize test casts). Pin target/laniusc-pins/f049e1a53744da2b/laniusc. integ16 green: matrix 43/43, casts 6/6, probes, stdlib 180/180, foundation 17/17, backlog 1/15, quiet 1 MB 62.9 ms compile / 65.7 wall.
- **2026-10-17 21:42:** the laptop slept from 10-16 18:09 to 10-17 21:42, and the usage limit was hit. All agents stopped; resume each with SendMessage. Their queued heavy jobs (p9 build44, p9b build30/cpu22, p12 build_p, p14 test2, p11 job22) kept running; agents should read their own logs on resume.
- P13 290f8838: run11 had 2 failures (ordinary_trait_methods_execute_alongside_generic_value_calls; the owned_generic_trait_impl_operand one is P4's). Don't merge yet. P9b: hold25t result unknown, so wait.
- **Gate on 335e31b8:**
  - matrix 40/40 (includes m00–m05, p30–p34); casts 6/6; rvalue-receiver probes c1/c2/c3/c6/c7 exit 42;
  - convergence probes: r1 2 rounds, r2 3, p4_768 (740 KB generic) 3 rounds in 1.3 s.
- **Perf:**
  - warm 1 MB non-generic compile_ms 68 ms;
  - service second start 1.6 s with a warm driver cache (P9);
  - generic 1 MB original compile 97 ms;
  - monomorphization replays dominate: narrow 1 MB about 1.5–2 s; full-diversity 1 MB 15.9 s with P11's D′ phase 1 (was 90.8 s).
- **Sweep 8 (P10, 05eaaa8b):** 862/990 ok, 0 regressions, 0 bad jumps. Failures routed in reports/ROUTING_SWEEP8.md. (Previous: 782/985 on b695383e.)
- **Official warm 1 MB, quiet, on b5b4519b (integ12):** compile 64.7 ms, wall 67.5 ms median, 20/20. Meets < 100 ms for non-generic code. Generic: narrow 0.5 s, full 1.2 s on P11 hold14 (not merged yet).

## Gate scripts (scratchpad/lead/, under /tmp/claude-1000/.../scratchpad)
- **Use `gate.sh <tag>` now** (14:45): it builds, pins, runs integ3np.sh with heavy --priority, then perf_quiet.sh with heavy --priority --quiet. Perf numbers taken next to builds are noisy (P9 saw 95 vs 140 ms in one hold).
- `integ3.sh <pin>`: convergence probes, 3 small fixtures, matrix, casts, rvalue probes, warm 1 MB perf.
- `integ3np.sh <pin>`: the same without perf, plus the m-probes.
- Build: `heavy -t 40 env LANIUS_SHADER_BUILD_JOBS=2 LANIUS_SHADER_NOINLINE_MIN_INSTRUCTIONS=1 cargo build --release --offline -p laniusc --bin laniusc`
- Then pin: `python3 tools/pin_laniusc.py --target-dir target`. Retry the build if it exits 137 (low-memory guard).
- **Never run tools/lanius_perf.py without `--laniusc <pin>`**; without it, it rebuilds every shader without the harness.

## Agents: branch, worktree tip, pending
All worktrees are under .claude/worktrees/agent-<id>.

| Agent | id | Branch @ tip | Status |
|---|---|---|---|
| P11 (monomorphization) | a08326ac3a65a8f70 | p11-monomorphization @ 703cb7b5 | D′ phase 1 (90c2ae3e) + phase 2 (16477cf2) + merge of 335e31b8, which resolved the conflict with P13 in native_session.rs and packet.rs. Waiting on hold13; don't merge before it's green. Next: three-option comparison (same pack, separate instance unit, D = in-compile instances); end state is D. |
| P4 (ct_match/inference) | ad8000e4e3ac3b992 | p4-ct-match @ 4db8dfeb, 9 dirty | gate15 pending. It covers group A (expr_form guard on call rows), group B (intrinsic scalar results), 03a4 ID compares, the LLP parser pair fix, and the lookup-sweep early stop. Also owes a host-recording per-stage table. Constant-engine deletion approved. |
| P3 (ct_subst) | a0e2353ca3de4b17d | p3-ct-subst @ f497681d | Merged already. Working on P10 group D (negative const generic args) and P4's call_envs arity masks. |
| P13 (cross-module traits) | a18f5eaa07a7a4781 | p13-cross-module-traits @ be00582d, 4 dirty | dd42e37c merged. Now: routing through stdlib trait bounds (`T::eq` under `where T: core::cmp::Eq<T>`), then generic methods in generic impls, const-param impls, blanket impls. |
| P2 (stdlib generics) | a2aa7f217ffc3d844 | p2-stdlib-generics @ 2ef83dcb | Char ordering fix + char containers on char slots + checked core::char::from_u32 (08ad7732). Generic pilot: core::vec::Vec<T,N>, Pair, Set<T,N> (a28d9155). Verification hold pending, then merge. Must renumber backlog entries above P13's b02. |
| P12 (LIR/x86 gaps) | a1ac9b7bdf619d0ff | p12-lir-gaps @ b8172cdf, 17 dirty, uncommitted | Const-param CONVERT packing, char literal TY_CHAR, parenthesized receivers, fields of temporaries. Gate job I pending, then commit. |
| P9 (host/startup/cache) | a5bb1d5e0fce1d9b2 | p9c-tail @ a552e627, 4 dirty | The NVIDIA driver cache is keyed per exe path, which is why new pins and test binaries start cold. Testing __GL_SHADER_DISK_CACHE_APP_NAME plus a fallback. Then the readback.gather bind-group cache, then unit-facts decode (bulk reads; P11's table). |
| P9b (parser/LIR perf) | a2734a3bdf93de528 | p9b-parser-perf @ 25a23740, 5 dirty | Bracket heap search; lowering submit split; semantic-interface host gap; generalize record/GPU overlap. 8e12bbdd merged. |
| P7a (PEV kernels) | afc9d2f4adb04a904 | worktree-agent-afc9d2f4adb04a904 @ 078babfc | 53 split, Q1, walk split (54/59i), 02_09 split, native05; GPU-driven admission loop (planner kernel 70). hold_wave gate ran about 12:33. Fix proof_span test. |
| P10 (bench/sweep) | a5e130e51759ff068 | p10-test-combo @ fb5ce8ac | Casts series round 2 (WIP), KNOWN-GAP list, trace fix merged. |
| P14 (impl bindings in replays) | afef73f2b8f2e6f00 | its own worktree | New at 15:35. b12: dependency generic bodies call the caller's trait impls (a per-instance impl-binding table, reusable by D). P13 keeps the 09 hook. |

Finished, not running: P5a, P5b (a5f3c436b03095b7b), P12's cast work, P2's earlier canonical-ID work.

## Next merge queue (in order, gate each with integ3.sh)
1. ~~P11 83416a76~~ merged in b14b5c41.
2. ~~P4 53d197ed + P2 08fbc789~~ merged in f80e33a4. integ15 = P11 352e48ea (D0) merged as 2be4b52c, gating. Then integ16 = P9 d29fa859 (clean vs 2be4b52c, ready) + P9b + P13 290f8838+ + P12 0e409dd0 (u8 stride; plus an as-usize test-source commit coming), as each arrives.
3. ~~P12 4d6a7ee9 + P3 5d09cb0b~~ merged in b5b4519b.
4. ~~P2~~ merged in f80e33a4.
5. ~~P7a 918265a7 + P10 9ae9327b~~ merged in 4c041c2c.
6. ~~P9 a552e627~~ merged in 511d5a89. P9b still pending.
7. ~~P10 casts~~ merged 05eaaa8b.
Budget conflicts: `python3 tools/merge_inlined_budget.py`.

## Open issues to route
- typed_constant_transport/runtime_{array_only_nested_count,mixed_claim_priority}: no specialization for `narrow<const N: u8>` called with u64 (sent to P11, low priority).
- repro_ordinary_string_comparison: str element `!=` is unsupported; KNOWN-GAP, owner TBD.
- b02 two-level bound proof (`Twice<Twice<Rect>>`): LNC0008, predicates.
- The 11 kernels still over 40k inlined; 10 over 1 KB/thread. The DontInline harness stays until the budget is empty.

## heavy
- Queue tickets match by pid. To prioritize a job, rename its ticket to `1<epoch>-<pid>` in /tmp/claude-1000/lanius-heavy.queue.
- The build lane's second slot needs at least 12.5 GB free.

## Late finding (P4, ~13:00): a warm check is NOT host-recording-bound
- A warm narrow-generic type check is about 63 ms. It is a serial chain of 7 blocking readbacks: early canonical ×2, call inference ×3, late canonical ×2. That's 50 ms of waits, mostly GPU execution, plus 11 ms of host recording (~1006 dispatches at ~11 µs each) while the GPU idles.
- Levers:
  - overlap recording with execution (P9b's split): about 12 ms per check;
  - fewer readbacks, e.g. fold the second canonical batch into round 1;
  - fuse dispatches: about 11 µs each.
- Trace accounting bug: partial typecheck submissions don't stamp `submission.begin`, so idle gaps get charged to the next pass (the "slow" clears). Owner: P9/P9b.
- P4's script: scratchpad/p4/segments.py.

## Generic perf strategy (14:55, from P11 hold14)
- Copies are nearly free: 2,142 copies add 4 ms of GPU time to a run. A run's cost is re-checking the template (110–140 ms).
- So the next step is P11's option (b): a copies-only instance unit against the template's checked interface (~5–20 ms per run). D (re-keyed codegen) is only a fallback.
- After that, the critical path is the original generic compile: ~245 ms against 107 ms plain (traced). Program evidence is ~36 ms GPU + ~75 ms host, plus ~1.1k extra dispatches.
  - Owners: P7a (evidence: exact sizing, fewer syncs), P4/P9 (type check, dispatch count).
- b03/b04 (method routing through bounds) went to P13. b13 (generic returns generic Option<T>, LNC0006) is pre-existing in the per-unit path; P3 is bisecting the CT subst vs ct_match split.

## Plain 1 MB stage table (P9 hold40, pin 89341837; 74.5 ms with host timing, wall 78.4)
- GPU busy 67.8 ms traced (timestamps add ~10 ms), GPU idle 18 ms, 24 readbacks. Wall − compile = 3.6 ms (source load 2.5).
- Type-check readbacks (6 of them, 32 ms) all happen while the GPU is busy: NOT on the critical path, so readback folding is deprioritized.
- The idle time is a serial host tail of ~14 ms: x86 readback → unit facts 5.2 → PEV 4.5 → link 2.7 → job end 1.7. P9 is overlapping unit facts and PEV with lowering+x86 (split after type check, P9b's SubmissionSplit): −8–10 ms.
- Other cuts: parse-start idle 3.9 (P9b record overlap), indirect validation off ≈ −6 (P9b hold24), decode rewrite −1.4 (P9 f582c87d).
- Kernel time, traced: parse 21.7, type check 18.6, lowering 16.7.
- Next: the same table for narrow-generic's original compile (P9).
- Startup on pin 89341837: daemon 1.20 s then 0.83 s; CLI check 1.31 s then 1.42 s.

## Strategy update (15:50): go to D, starting with C on the GPU
- P11's comparison (warm, full [narrow]): today 0.51 s after the set-lookup fix [0.43]; (b) copies-only unit ≈ 0.33 [0.30]; D ≈ 0.25 [0.24].
  (b) needs as much plumbing as D's virtual keys, and D throws it away, so we skip (b).
- D1 = instance closure on the GPU (C): removes round 2 (≈ 105 ms) and the host scan (77 ms). P11 writes reports/D_PLAN.md with phases, owners and gates.
- Original generic compile ≈ 230 ms against 75 plain. ≈ 100 ms of it is PEV (23 proof-progress round trips × 4 ms + 40 ms host); P7a owns it, target ≤ 25 ms, using the GPU wave loop after exact sizing.
- (16:10) Lead decision: reject_mixed_exact_projection_identity follows the documented canonical design (array keys store the count class; `[T; 3u32]` = `[T; 3usize]`), so it's accepted (P3 option A). Fixture flipped and renamed, with a companion instantiated-misfit reject fixture. Option B (typed array lengths) was rejected as a large semantic change.
- (16:15) Lead decision: an uninitialized `let x: T;` means zero-initialized storage (P9b option a; stack buffers per stdlib-foundation item 25). `[v; N]` repeat syntax is approved as a P9b follow-up.
- (16:15) P9b hold24q quiet A/B: plain 1 MB 64.2 → 57.9 ms; narrow 1693 → 1604 ms; ELFs identical. Tip 2042b4e7 goes into integ15 once hold25t clears cli_daemon capacity retention and the parse_fuzz leak.
- (16:20) Lead decisions on b10 (P12):
  - `core::mem::size_of<T>()` = raw storage stride bytes (i32 4, u8 1, ZST 0, else 8 × words). Runtime only, type usize.
  - New `core::mem::typed_slice_from_storage<T>(storage, length) -> [T]`, which is direction-agnostic.
  - typed_slice_from_raw_parts stays unchanged.
- (16:20) P12 u8 stride fix: repro_u8_string_slice exits 122; u8 fixture sweep 72/73 unchanged plus 1 FAIL → PASS. Tip pending a last x86 test.
- (16:40) D_PLAN.md approved (reports/D_PLAN.md).
  - D0 is done (39688f4b: set lookups; full 0.52 s, narrow 0.47 s).
  - D1 (instance closure in the original job) has started; P3 gets 4 asks from P11.
  - D2–D5 go behind a flag with the D′ differential as oracle. D6 ≈ 0.27 s.
  - With P7a's evidence cut and the generic type-check overhead cut: ≈ 0.12–0.14 s full generic 1 MB.
  - D7 (library generics used from user code) must be sized early on P10's realistic workload: warm cache vs bodies-in-interface.
- (17:00) High-priority bug: on stdlib generics, a user generic over Vec<P,N> (record P) calling core::vec functions fails with "x86 callee function lost its checked aggregate result layout". Repro in scratchpad/p10/aggr/a*.lani. Owner P12, ahead of size_of; P11 consults.
- (17:00) P10 presets: generic-1mb-narrow/full, generic-scale-*, single-file-stdlib-generic{,-narrow}-30ksloc. The stdlib presets are blocked by the bug above, plus a "type-check execution failed" P10 is isolating.

## User decision (2026-10-17 ~22:00): the 100 ms target is THIS laptop (RTX 3070 Laptop)
- Desktop RTX 3090 did 30 KSLOC in ~30 ms pre-generics; that is not the target machine. Measure on the laptop with heavy --quiet.
- Consequence: D_PLAN's end state (full-generic 1 MB ≈ 0.12–0.14 s) is NOT enough. The generic 1 MB critical path needs < 100 ms here.
  - Budget: plain floor ~58 ms (P9b tip) plus a generic surcharge ≤ ~35 ms.
  - Levers beyond D_PLAN: the warm generic type check (63 ms, 7 serial readbacks; fold them and fuse dispatches), PEV ≤ 25 ms (P7a), the D6 instance-codegen residual, and the plain floor (P9b record overlap).
- Lead default (correct if the user disagrees): the headline measure is P10's realistic single-file-stdlib-generic-30ksloc preset. generic-1mb-full is a stress check reported alongside.
- 22:03: resumed a reduced fleet after the usage reset: P13 (trait-bound method calls b03/b04, plus its run11 failure), P12 (Vec<record> aggregate layout, then size_of), P11 (D1, a <100 ms section in D_PLAN, D7 sizing on P10 presets), P7a (PEV ≤ 25 ms, now required), P4 (composition bugs; P4_INFERENCE_UNIFORMITY.md audit BEFORE more point fixes), P9b (hold25t, then hand over the 57.9 ms tip for integ17). Paused: P2, P3, P9, P10, P14, pending the user's direction answer.
- (22:15) P7a exact sizing (tip f444cf45; committed ac4c1e3f + 92b74f0d; wave path uncommitted). PEV in the original compile: narrow 20.7 ms, full 26.4 ms (was ~100), byte-identical outputs. Job wall: narrow 526 → 454 ms, full 637 → 559. Asked for a gate of the committed part on f67f022a, for integ17.
  - The generic surcharge is now led by: specialization scan 84 / 88 ms (host; P11 D1 removes it), specialization compile 106 / 138 ms (P11), generic_calls unit_facts 25 / 36 ms (P9, resumed 22:15, target ≤ 5 ms, plus PEV host-prep overlap with lowering).
  - P7a's floor estimate: PEV 6–8 ms with the overlap, 15–18 ms without.
- (22:25) P13 on f67f022a (0953d2a2 + 2 commits):
  - e6229958: candidate_masks now include the call's context masks. 02's arity mask had dropped trait slots for a bound's required member; this fixes s01/s04, b04_trait_with_arguments_bound and the result side of b03.
  - 3529b815: test-source cast.
  - Run11's 2 failures were pre-existing on f67f022a. Lead decision: the :1228 expectation becomes LNC0021 (the impl-header check rejects earlier); literal const trait args stay a known limitation.
  - P13 now owns the b12 impl-binding semantics (it merges P14 0731ce63); P11 owns the instance-side plumbing.
  - Baseline: backlog 1/15, sprobes 1/12, b12 family 3/14.
- (22:35) P11 64c2155a (f67f022a + P14's 4 commits: per-instance impl bindings) passed P11's gate. Merged as integ2 = c737cea1; integ17 is gating (lead task bzh6uj2cg).
  - P11 warm, not quiet: narrow 389–407 ms, full 449–458, plain 72–76.
  - The stdlib 30 KSLOC presets fail in the original compile: (a) P12's aggregate layout bug at core/vec.lani:72; (b) LNC0047 CT_OVERFLOW_SUBST_MEMO on some reps, not a capacity problem. P3 was resumed 22:35 for (b).
  - P7a's "scan 84/88 ms" came from base b14b5c41, which lacks D0. P11 measured 13 ms on D0; hold18q will settle it.
- Paused now: P2, P10, P14 (P14's work carried by P11 and P13).
- (22:50) P3 (03fb216e = f67f022a merged, plus untested commits):
  - d03c56a3: ct_subst_memo_insert race. Lanes substituting a hot key each claimed a new slot while its first entry was in flight, filling the 64 probes; slots are now claimed with a key tag, one slot per key. This is the cause of the intermittent CT_OVERFLOW_SUBST_MEMO.
  - 68e6bc95: b13; 00c_generic_call_results now keeps the imported (library, unit, local) triple.
  - 4b70a555: extent diagnostic. 67e0228f: option-A fixture.
  - Asked P3 to confirm that tag collisions only lose an insert, and the z publish order. Approved the follow-on suppression rule if the first diagnostic is deterministic. pin29 is queued.
- (~22:15) P11 D_PLAN §0.1 / §4a / §3 D7 (laptop, tip 64c2155a, quiet hold18q): plain 66–73, stub 36–38, narrow 355–383, full 399–416 ms. Solver waves: no gain. Scan settled at 14.7 ms.
  - §4a path for full generic 1 MB: 407 → D1 −83 → P7a fused evidence −88 → D2–D6 + link −120 → type-check / unit-facts / catalog levers −24, ≈ 92–97 ms.
  - Margin 3–8 ms. BOTH the type-check lever (+26.7 → +12) and evidence ≤ 8 ms are required.
  - D7 (stdlibr_narrow, 31 KSLOC): core needs 4 runs (copies only work for the last file; one instance per function per original-scope run), ≈ 65 ms per run steady.
  - Lead decisions: D1 now; D7a (multi-file copies, needs a module-resolver owner, staff it after D1) + D7b (warm instance cache) after D1; D7c (bodies in the interface) open, to decide after D7a/b. §4a is a live budget table updated per merge.
  - Routed: the gpu/timer.rs 4096-query panic → P9; GPU-side inference convergence added to P4's audit.
- (~22:20) **generics-gpu = c737cea1** (integ17 green: matrix 43/43, casts 6/6, probes, stdlib 180/180, foundation 17/17, backlog 1/15; quiet plain 1 MB 64.5 ms / 67.6 wall). Pin target/laniusc-pins/c71f7cfe6215cf5d/laniusc. Contains P11 64c2155a + P14's impl bindings.
  - Next integ18 candidates: P7a committed sizing, P9b 57.9 ms tip, P13 tip, P3 memo race + b13 — each after its own gate.
- (~22:25) P13 a52533fa (on f67f022a; run12 green; s probes 9/12, backlog 3/15 with b03_static + b04_args, b12 family 7/14) merged as integ2 = 656fd44e. integ18 is gating (lead task bmk3zbgg1).
  - P13's bound-call stack on top is NOT gated yet: 85210931 (P14 merge), 5f970e52 (b06 imported requirements), e528555b, 0b75bc2d (09 routes to the evidence-selected impl, b12), 182be4c7 (const-param leaves). Open: b03_generic, LNC0006.
- (~22:35) P3 pin29 (d03c56a3 memo race + 30e27de5 + b13 + extent): P11's repro passes with 0 memo overflows; plain 1 MB A/B unchanged (64.35 vs 64.2); b13 r1/r2/r3 fixed; matrix 43/43. P3 is gating pin31 on c737cea1 (a5497bd0).
  - **HEADLINE realistic number (not quiet, pin29):** stdlibr_narrow 2909 / 1610 / 966 / 991 / 1020 ms; stdlibr_full 1685 / 1628 / 1001 / 1018 / 1014 ms. Steady ≈ 1.0 s against the 100 ms target.
  - P11 asked to make stdlibr the top rows of §4b, break down the 1.0 s, project the D1–D7b end state, and explain reps 0–1.
- (~22:45) P11 hold20 (quiet, laptop, pin29): stdlibr_narrow 952–980 ms, stdlibr_full 982–1047, plain 63–72.
  - Traced narrow compile, 1,072 ms: core library original 72 (recompiled every job; the resident executor never uses CompiledUnitCache) + app original and 5 replays 534 (4 core runs × ~75 + the app copy run ~136) + PEV 217 (88 readbacks) + unattributed host 188 + unit facts ~30.
  - Routing:
    - D7-0, caching library originals by content hash: P14, resumed for it, with P7a on catalog admission.
    - The 188 ms host gap: P9, first priority.
    - stdlibr PEV: P7a.
    - P11 adds a §4c stdlibr budget to D_PLAN.
- Paused now: P2, P10.
- (~22:55) P4 audit: scratchpad/p4/P4_INFERENCE_UNIFORMITY.md (left in the scratchpad; P4's worktree can't write to reports/).
  - A near-uniform per-node slot already exists (03g call_inference_result). ~15 readers bypass it with form switches or token keys, plus 9 expected-type climbs.
  - 8 of 25 probes fail, all in 03a_member_receivers:179-182 (receiver looked up by its first token, `(` for a group).
  - Nested ptr-arg passes on f67f022a, so P12 is told to close it.
  - Lead decisions:
    - 03a point fix + A15 (HIR_EXPR_INDEX 28→26) GO, with group C, as one tip.
    - Staged S/E rewrite GO: stages 1–2, then a checkpoint report (fixed probes, lines deleted, kernel sizes, perf) before 3–6; design for L2 incremental rounds.
    - L1 (GPU-driven inference loop, ≈2.3 ms) not staffed until after D1.
  - Type-check surcharge, narrow: 21.5 ms (16.6 GPU, 4.3 recording, 0.6 map). L1+L2+recording overlap → ~10–12 ms.
- (~23:00) P9b tip 208f4567 (f67f022a merged, hold25t green: ELFs identical, parser 254/254, residency OK).
  - build32 fixes, not yet verified: the `>>` oracle and the LNC0016 replay (Option<Option<T>>); cli_daemon dense capacity (SI name bytes come from the retained allocation; x86 page resources grow in steps); the postfix-endpoints member span.
  - Waiting on hold26t (are the 5 x86 failures pre-existing?) and the hold25q quiet A/B, then one tip for integ.
  - Decided: the for-iterable cases accept LNC0006; missing_main gets a clear message; void_main_return goes to P9b after core_utf16.
- (~23:05) **generics-gpu = 656fd44e** (integ18 green: matrix 43/43, stdlib 180/180, foundation 17/17, backlog 3/15; quiet plain 64.4 ms). Pin target/laniusc-pins/e53a1b75c998bb33/laniusc.
  - Backlog owners: P13 b01 / b02 / b03g / b04c / b05 / b06 / b12; P9b b08 / b09; P12 b10; P4 b11; P3 b13.
- (~23:10) P13 merged 656fd44e as fd527d42 and queued gate run16 for the bound-call stack (pin 30d10e9d).
  - u03 / b03_generic narrowed: it fails when a bound's trait arg is the caller's own param instantiated with a ROW type (struct or array). Scalars pass. So the call-context row isn't substituted or interned for row-typed bindings in replay.
  - b01 → P13 (concrete-subject bound proved once). b02 (two-level recursive proof) → P7a after P13's probe. b05 → P13.
- (~23:20) P11 D_PLAN §4b/§4c (stdlibr headline). Traced j3, 1,071.6 ms:
  - core original 71 + facts 9; app original (1.4 MB) 138;
  - PEV 285 (45_commit_normalized_terms is 138.7 ms of GPU in 9 dispatches; this went to P7a);
  - app facts 25; scan, plan and host 48; runs 397 + 65 of gaps; link 33.
  - Reps 0–1 come from type-check resident workspace rebuilds when upstream buffer identity changes → P9, pre-size for a pre-warmed instance.
  - **End state with every planned lever ≈ 164 quiet; with the type-check levers ≈ 139 quiet.** < 100 ms also needs the app original halved and the plain frontend floor down ≈ 40%.
  - Lead: the bar is KSLOC, per the goal. Real density: stdlib 35.8 B/line, verified_compiler 42.9, fixtures 48.2, so stdlibr (45) is fair. Asked P11 to add verified_compiler (~39 KSLOC of real code) as a headline row, and to say what "stub" is.
  - **Resumed P10 for a per-job dispatch and overhead census** (fixed overhead suspected: stub 36–38 ms of plain's 63). Output: reports/DISPATCH_CENSUS.md, ranked top 20.
- Paused now: P2 only.
- (~23:25) The stub keeps all 1,092 fn declarations, with bodies replaced by `return x;` (70.7 KB). Its 36–38 ms = fixed per-job cost + per-declaration cost + 71 KB of lex/parse. So ≈ 37 ms of the plain floor is size-independent and ≈ 30 ms scales.
  - P10 adds a main-only program to the census, plus plain1p4mb.
  - verified_compiler is real code but non-generic (no stdlib imports): compiler.lani's closure is 105 files, 25.2 KSLOC, 1.08 MB. P11 hold21 tests whether it compiles; if it does, it becomes the second headline row.
- (~23:50) **User decision: never type `-> !`** (P9b syntax / HIR / lowering; P4 typing + panic).
  - integ19 gating 0e08e2eb = 656fd44e + P3 30e27de5 (memo race, b13, extent) + P12 1b5de78c (aggregate layout: 01b_seed_body_rows) + P14 8b3dcfa3 (D7-0; stdlibr_narrow −82 ms) + P4 68e8183f (03a + HIR index const + group C; uni 26/26; sweep 992→1003) + P13 d6f1dd5c (bound-call stack; backlog 5/15, matrix 47).
  - Gate now includes stdlibr (lead/stdlibr_quiet.sh). Lead task b7yt9qaod.
  - P7a f444cf45 is not in it (its own gate pending): stdlibr 998 → 716 ms with the memo fix; 45_commit is next.
  - P9: 189 ms attributed, of which 69 is PEV. Regrowth cause: a lexer replacement drops parser + type-check workspace, which come back at the exact shape. The fix (parser kept, capacity floors) is agreed with P9b. `laniusc daemon --warmup SRC` was added.
  - P10 census report path: .claude/worktrees/agent-a5e130e51759ff068/target/claude-work/reports/DISPATCH_CENSUS.md. NEW BUG: after stdlibr ×4 in one daemon, the empty program takes 557 ms (534 ms of readback wait); P10 is isolating it.
  - verified_compiler fails at LNC0006 implicit i32→usize (host.lani:36); a sweep is needed (P12 after size_of).
- (10-18 ~00:05) P10 isolated the cross-job carry-over.
  - SEVERE (+530 ms on a small job after a big one): 5 type-check shaders grid-stride over capacity with stride = n_tokens (02c_index_closed_applications:21, 07_project_imported_fields:101, 01c_generic_native_words:492, 00_clear:147–175, 02b_clear_application_index:17/20). Sent to P4 as TOP priority; P4 is to send that tip on its own for a fast-track.
  - MILD (+10–15 ms): tree levels and pointer-jump steps sized from retained capacity → P10 #20/#3.
  - The census floor (24 ms) holds only in a fresh daemon.
- (10-18 ~00:30) **generics-gpu = 0e08e2eb** (integ19 green; pin 7226d510c232efe1).
  - matrix 47/47, stdlib 180/180, foundation 17/17, backlog 3/11 (4 moved to the matrix).
  - plain 64.4 ms; stdlibr steady: narrow ≈ 885, full ≈ 885–952 ms; reps 0–1 at 2.5 / 1.4 s (regrowth; P9 fixing).
  - r2 took 45.8 s on its first run: the driver cache compiling the new kernels, one time per pin.
  - Next integ20 candidates: P7a f444cf45 (after its predicates base check), P9b build34 tip, P4 grid-stride carry-over fix (fast-track).
- (10-18 ~00:20) integ20 is gating integ2 = 4306ba33 (0e08e2eb + P7a f444cf45 exact sizing). Lead task bho7vib21.
  - The 2 predicates tests are pre-existing; the programs run correctly. P7a is rewriting them as execute tests.
  - The cyclic struct gives an internal-sounding LNC0017 → P12, which should make it an infinite-size diagnostic.
- (10-18 ~00:25) P9 regrowth fixed on p9c-tail (d276cf42, bb9fd115, 703e7733).
  - The parser keeps its allocation across a lexer replacement; capacity floors; `--warmup`.
  - stdlibr_narrow reps: 1809 / 924 / 949 / 923 (was 2420 / 1542 / …). With `--warmup`: 916 / 953 / 914 / 976. Ready 2.5 s.
  - Waiting on hold49 to check whether a narrow 1 MB rise (367 → 384) is real.
- (10-18 ~00:28) P3 triage of the 8 routed failures.
  - Real: depth-24 ct_match path limit (fix to the documented 64 levels, with P4's OK); assigning an imported alias ctor gives "arena exhausted" (P3, coordinating with P4); alias-env body specialization (P3); a field of an imported generic struct with an &Item arg (08_validate_aggregate_access, P3).
  - Stale: `N*10 + M` u32/usize.
  - Decision: annotation arity/kind keeps LNC0007 (docs), with a better message if cheap.
  - P3's 8abf53e9: only language errors explain follow-ons. Open: two native-ELF 500 ms hangs in the CGTE binary; asked whether they're on 0e08e2eb.
- (10-18 00:33) P9b b6899b43 (long binary chain spans, the reason-17 cause; unit-typed bare return; bounded SI artifact growth; cli_daemon 5/5).
  - Quiet A/B: plain 1 MB 60.7 → 52.6 ms, narrow 362 → 329, ELFs identical.
  - Merged as integ2 = 6fbb171c, on top of integ20's 4306ba33. integ21 is gating (lead task bue3h9d1t); integ20 is still in its stdlib/perf steps.
  - 15 x86 code-shape tests are pre-existing failures → P12 triage, low priority.
- (10-18 00:40) **generics-gpu = 4306ba33** (integ20 green, pin 2cf17bfcb517fe9a): matrix 47/47, stdlib 180/180, foundation 17/17, plain 62.7 ms. stdlibr: narrow 2123 / 1202 / 695 / 645, full 1288 / 1235 / 658 / 675 ms, 0 overflows.
- (10-18 ~00:45) P13: b12 passes on 0e08e2eb (exit 42); b12 family 10/14 (open: b12f/g/l impl visibility, b12j ICE exporting a private Point).
  - Tip 38baddab, not yet gated: b05 Self slot (048f016f), b06 15b modulo fix (090c4986). b01 is next.
- (10-18 ~00:50) The CGTE "hangs" are not compiler bugs. On this laptop, expected-SIGILL ELFs take ~1.1–1.9 s to die, because core_pattern pipes to apport even with ulimit -c 0, and the tests/common limit is 500 ms.
  - P3 makes option (a): a ~5 s timeout only for expected-signal runs.
  - Apport is a system setting, left to the user.
- (10-18 ~00:55) P10 #9 (afcd8fc7): one layout round when there's no `enum` token; −189 dispatches; empty 16.9 → 16.0 ms (empty was 24 before b6899b43). #9b: rounds = min(64, count of `enum` words).
  - Mild carry-over: 77% comes from capacity-sized grids, not steps. A per-job "active capacity" design note was requested; it's scheduled after the generic levers.
  - --warmup makes every small job pay the carry-over. P9 is to measure it; keep --warmup opt-in.
- (10-18 00:56) P3 587a3ace gated green (lib 817/30 known; CGTE 460/18, no new failures; matrix 47/47; count-fit LNC0006 at the argument). Merged as integ2 = 94c6bffb (on top of 6fbb171c). It goes into integ22 with the next tips (P4 grid-stride fast-track, P9 3d5f3f54).
  - caf6dd5e touches calls/03c (P5a's, finished; P4 knows). The arity message is not cheap; LNC0007 kept as is.
- (10-18 01:40) The heavy --quiet deadlock is fixed: a quiet job releases its claimed build slots when it isn't first. Rule: quiet jobs ≤ 10 min.
  - integ21 (6fbb171c = 4306ba33 + P9b b6899b43) functional green; plain 1 MB 57.1 ms / 62.2 wall. Its stdlibr step was killed in the deadlock; re-running it non-quiet for correctness.
  - integ2 = 94c6bffb also has P3 587a3ace.
- (10-18 01:50) **generics-gpu = 6fbb171c** (integ21 green; pin 5ef2a2cb6ea2ee52). Plain 57.1 ms. stdlibr (re-run, not quiet): narrow 2175 / 1203 / 632 / 613, full 1297 / 1302 / 619 / 623, 0 overflows.
- (10-18 02:12) GPU lane queue 8 deep behind P13 gpu_job24 (ends ~02:22). P4 perf31 (quiet, grid-stride/capacity-loop fix pin31 vs 0e08e2eb) queued 3rd. Asked P9 to split hold50 (was quiet -t 45 incl. functional steps) into plain -t 15 + quiet -t 10 step-4-only. P14 agent ended its turn with d7a_func2 (heavy PID 421897) queued; lead watches for it (bg b45nr32bf) and resumes P14 by SendMessage.
- (10-18 02:25) integ2 = 590d3ee0 (94c6bffb + P13 38baddab: b05 Self slot, 090c4986). P4 interim: capacity-loop fix pin f9c7d59f, empty-after-stdlibr 563 -> 52 ms (fresh 24, plain 1 MB 61 unchanged); told P4 to ship tip once sweep+ELF pass, chase the 27 ms residue after. P14 D7a: root cause pub generic fns lost owner spans (75e8c3a5); branch d7a-gg = 508cf694/1596e1c0/99d5073f on 6fbb171c; d7af2 functional green (matrix 47/47, stdlibr ok, original_runs=0), D7a removes 2 runs/warm job; quiet A/B pending. 152-body app copy run 120-130 ms steady, 410-470 on reps 0-1 = §4c downstream_prepared regrowth (P9's 33c9df92 1/64 headroom is related).
- (10-18 02:35) integ2 = 7082506d (+ P10 p10-diet-i21 67502dd7: #9/#9b layout rounds; 566/566 ELFs identical; stdlibr_narrow 625.5 -> 602.7 quiet; empty 16.9 -> 15.3). integ22 still waiting for P4 capacity-loop tip and P9 tip50 (3d5f3f54) numbers.
- (10-18 ~02:35) integ22 gate started on integ2 = 24d92bf5: 94c6bffb (P3 587a3ace) + P13 38baddab + P10 67502dd7 + P12 bfae34cf + P9 3d5f3f54. P4 capacity-loop fix (pin f9c7d59f) not ready -> integ23. Main checkout tree frozen until build (and functional gate) finish. gate.sh build step now --priority. Declined P9's identical-job facts cache (would inflate repeated-job benchmarks).
- (10-18 ~02:40) integ22 build done (pin aeeda42b, rev 24d92bf5); functional gate running. Merged P4 c7f85b45 (capacity-loop fix; no stdlib/fixture changes) into integ2 -> fbe63039 = integ23 candidate, start after integ22 completes.
- (10-18 ~02:58) integ22 GREEN on 24d92bf5 (pin aeeda42b): matrix 47/47, stdlib 180/180, foundation 17/17, backlog 4/11 (b05,b07?,b12,b13 pass; fails b01,b02 LNC0008; b06 + 1 LNC0027; b08 + 1 LNC0016; b11 LNC0006). Quiet laptop: plain 1 MB 57.6 ms compile / 61.2 wall; stdlibr narrow 1608/581/586/609, full 953/607/611/621, 0 overflows; ready 0.8 s. generics-gpu -> 24d92bf5. integ23 = fbe63039 (+ P4 c7f85b45) started.
- (10-18 ~03:15) OPEN RISK: P10 hold 4 (49e145f8 = #9b + LIR jump pairs) failed 2 GPU lib tests: physical_gpu_job_bounds_match_conservative_lowering (#9b's renamed test; ensure_lowering_pipeline Err 'lowering workspace') and physical_gpu_lowers_the_compilers_checked_compact_hir_for_both_targets. #9b is on generics-gpu 24d92bf5 and its lib tests never ran before merge. P10 hold 5 checks on 24d92bf5 vs 6fbb171c. Lesson: lib tests aren't in gate.sh; don't merge a tip whose own new tests are still pending.
- (10-18 ~03:05) integ23 GREEN on fbe63039 (pin b4d9acf2): matrix 47/47, stdlib 180/180, foundation 17/17, backlog 4/11. Quiet: plain 1 MB 56.1 compile / 59.4 wall; stdlibr narrow 1544/580/571/607, full 968/601/603/603; ready 0.9 s. generics-gpu -> fbe63039. integ2 = bdff94b1 (+ P9 f96bca21); integ24 waits briefly for P3 pin35 / P14 d7a-gg. stdlibr_quiet.sh now also runs empty x4 after stdlibr_full (small-after-big row).
- (10-18 03:12) integ24 gate running on integ2 = d6414d14: fbe63039 + P9 f96bca21 (headroom + read-plan replay) + P14 99d5073f (D7a continuation-file copies, pub owner spans, 2 stale type_checker_modules expectations). P14 quiet A/B: stdlibr narrow ~616 -> ~504, full ~618 -> ~498, plain unchanged. Gate PID 702416, watcher bg 61... (see tasks). P10 still triaging 2 lib-test fails (#9b on generics-gpu).
- (10-18 03:15) heavy: a --quiet drain now gives back claimed build slots and claims none while a --priority build is queued (lead's integration builds go first); post-lock drain polls every 0.5 s instead of blocking in flock.
- (03:19) P10 hold 5a: checked_compact_hir test fails (Wasm shared_host_runtime_calls, flags=0x10) back to 6fbb171c = pre-existing, unrouted. #9b test fails via SIGILL in the CONSERVATIVE manual lowering of generic_enum_struct_payload (test path suspected; production check pending). 49e145f8 test hits a lowering bind-group aliasing error (semantic_member_field_ordinal RO vs checked_constant_atoms RW) after a grown TC workspace; P10 checking production reachability (big x86 job -> small Wasm/x86 job). P7a edeff58d green; P7a tip2 (b02 fix c5918729 + waves) -> integ25.
- (10-18 15:07) integ24 GREEN on d6414d14 (pin 6bb01b8f): matrix 47/47, stdlib 180/180, foundation 17/17, backlog 4/11. Quiet: plain 1 MB 55.6 compile / 58.9 wall; stdlibr narrow 1351/463/460/478, full 926/494/476/491; empty after stdlibr 50/43/43/42 (was ~560 before P4); ready 0.7 s. generics-gpu -> d6414d14.
- (10-18 15:10) USER: the 100 ms goal means ~10x faster than rustc/C++; check stdlibr is representative. Lead's view: it is not (0 loops, straight-line i32->i32 from ~20 step kinds, 5 stdlib modules, ~70 specializations, no user generics/traits/impls, single file, 35.8 B/line). P10 assigned: real-code stats (verified_compiler, stdlib), generator v2 calibrated to them, a Rust twin with measured cargo check/build baseline, verified_compiler bench row. P12: vc `as` sweep moved up, right after size_of.
- (10-18 15:10) P11 §4c.0 (from ~470 quiet, partly carried-over rows): evidence -140 (P7a), D2-D6 -110 (P11), app original 124->60 -64 (frontend floor P9b/P12 ~-20, generic surcharge P4/P3 -38), D1 -58 (P11, in test; ee46da07 fix, rebased 82c2787d), D7b -53, host gaps -55 (P9/P11). All six ~90-100 ms, no margin. Asked P7a for full evidence split on d6414d14. Caveat: projection is on stdlibr, which is being replaced/augmented by a representative benchmark (P10).
- (10-18 15:13) Laptop SUSPENDED 03:33:22 -> ~15:07 (systemd-logind); all queues paused, nothing lost. P9b b08 tip d5cd8cbb conflicts (matrix p43 taken by P13; backlog README) -> asked P9b to rebase on d6414d14 and renumber p47. Pre-existing: qualified_enum_variants_bind_qualifier_scope_before_members reject cases LNC0027 (want LNC0005/0042), names owner (P4) low prio.
- (10-18 15:27) P9 integ24 traced split (not quiet) of warm stdlibr_narrow: GPU busy 316 (TC 134.5, frontend 72.3, LIR 63.6, PEV 31.5), GPU idle 224, host on critical path ~172 (TC record 40, spec scan 38, encoder finish 28, unit facts 21, spec finish/prepare 20, x86 link 14). Map waits: canonical 134.6 x15 (->P3), call_inference 66.5 x10 (->P4 L1), proof counters 33.4 x28 (->P7a), lexer metadata 57 x4. Routed: P9 recording (#4 prepared TC recordings, then #5 finish on worker); P11 spec scan <5 ms + recheck evidence 150 row.
- (10-18 15:32) P11 §4c.0 v2: evidence 150 -> ~58 (stale), spec host ~52 -> <=8, ~80 ms unattributed; order D2-D6, evidence, app original, D1, D7b, host gaps, scan. P10 to add edit-per-rep bench mode.
- (10-18 15:35) P13 audit: import_visible lookup mismatch (calls/03_resolve:219, methods/06_mark_call_keys:377 probe with job n_tokens; builder uses alloc) -> P13 fixing with probe. P13 branch rebased on d6414d14: 21d80b6a w03, ccde3ba6 b01, 3d8bf9b8 b06, b4af4470 fixtures p49-p51; b06 = p53.
- (10-18 15:50) P10 hold 5g2: production never hits the LIR aliasing error; #9b x86 all 42 in every order -> #9b on generics-gpu is OK (test-harness issue). Latent arena-conflict hazard -> P10 fixing. NEW: Wasm enum-payload bug (fresh daemon too) -> P9b queue (p54). v2 generator tools/generate_project_workload.py (110 files, 28.9 KSLOC, Rust twin), edit mode in tools/workload_bench.py. rustc timing must be inside heavy --quiet.
- (10-18 15:51) integ2 += P4 aff0c4cb (bounded calls.clear / type_instances.clear; empty after stdlibr 52 -> 48.7). P4 saw 'corrupted double-linked list' abort at process teardown of type_checker_semantics test binary (after results) - host heap corruption, same family as pipe-drain exit 124; unrouted, watch. Routed to P10: record_phase_reset fills (1.7 ms), interface.type_topology.init fixed ~4 ms per job.
- (10-18 15:52) integ2 = e2930101: d6414d14 + P4 aff0c4cb + P7a 53864711 (incl edeff58d, b02) + P3 698eba7a (incl f6f0ee54). Waiting on P13 (b06/w03/b01/import_visible) and P9b (b08 p48) before integ25.
- (10-18 15:52) integ25 gate started on e2930101 (gate PID 952584). P13/P9b tips -> integ26.
- (10-18 16:00) P12: size_of eaad5c2d + recursive-type diag 4528e7b6 on p12-lir-gaps (matrix 49/49 on its pin) -> integ26. TELL P2 WHEN RESUMED: core::mem::size_of<T>() and typed_slice_from_storage<T> landed. vc: casts done; now LNC0057 'preparing frontend work' on compiler.lani/extractor.lani (internal), P12 rerunning with LANIUS_DEBUG_STAGE_ERRORS=1.
- (10-18 16:02) P11 hold 22: D1 functional OK but intake schedules 0 bodies (no effect yet); hold 23 per-stage counters queued. Traced split warm stdlibr_narrow (x0.89 quiet): app original+facts 134, evidence 55, scan 26, core copy run 61, app copy run 115, core depth-2 run 56 (D1 target), patch 4.5, link/gaps 17. Copy runs = ~232 ms quiet of ~460 -> D2-D6 / D7b / D1 are the strategic levers.
- (10-18 16:26) integ25 GREEN on e2930101: matrix 47/47, stdlib 180/180, foundation 17/17, backlog 5/11 (b02). Quiet: plain 1 MB 55.0 / 57.6 wall; stdlibr narrow 1265/434/431/436, full 848/460/443/444; empty after 44/40/43/43; ready 0.7 s. r2 10.5 s = first program on new pin (cold driver compiles), as before. generics-gpu -> e2930101.
- (10-18 16:31) P14: cross-file impl self type = 0 on all workloads (no build). D7a on narrowproj (20-file, 1 MB): 1,178 -> 252 ms quiet. P14 next: commit miss-reason trace, fullproj import cycle (generator), then D7b (warm library instance cache) co-owned with P11.
- (10-18 16:32) integ2 = 56611a43 (e2930101 + P9b a90285c2: never-type parse, b08 -> p48). P12 c2288de4 conflicts (params.rs, 00_materialize, README, predicates test) -> asked to merge e2930101 and resend. integ26 waits for P13 + P12.
- (10-18 16:33) Moved P11 hold23 (D1 zero-schedule diagnosis, critical path) to front of GPU queue. Asked P4 to split gate33 (-t 45). P14 owns D7b cache (P11 reviews).
- (10-18 16:44) P7a evidence split: d6414d14 51.5 ms, tip2 (in integ25) 44.0 traced (GPU 13.1, wait 6.4, host 5.7, idle 18.7 = per-dispatch uniform/bind-group rebuild in record_phase_with_resources). Untraced solve stdlibr 54 -> 30. Plan to <=10: 1 params ring + bind-group cache (-15), 2 GPU-driven solve via waves (-5), 5 init kernels (-3), 4 cross-job stdlib catalog (-4.5), 6 normalization (-1.5), 3 fewer solves per job w/ P11 (-5). Approved. P9 tip56 1aa7dadb; tip58 encoder_chunks (finish on 3 workers) building; ~70 ms finish() per job confirmed.
- (10-18 16:46) DECISION: D1 per-unit closure can't remove stdlibr depth-2 run (edges=0 across app->core). D1b (cross-unit closure summaries, library-only cross-job) -> P14 together with D7b (coupled); P11 fixes D1 decode bug (hold 24: every row rejected) then D2-D6. Transitive cache hits NOT approved (keep admitted-origin-in-job invariant). P3 reviews D1b CT side.
- (10-18 16:50) P10 bounded LIR resets quiet A/B (on stale 6fbb171c lineage): stdlibr 603 -> 592, empty-after 558 -> 553, plain1p4mb neutral. P10's 550 ms empty-after = already fixed by P4 (integ23/25: ~43 ms); told P10 to rebase on e2930101 and re-measure. Edit mode works: stdlibr identical 572.0 vs edit 574.6. Reminder for all: compare against generics-gpu, not older pins.
- (10-18 16:58) integ26 gate started on 3f97d222 = e2930101 + P9b a90285c2 + P14 0df4f589 + P4 332f42ff (stage 1). PID 1177580. P13 + P12 -> integ27.
- (10-18 16:58) DECISION: D1b admits predicated closure callees (kind-2 contexts proven in-job by packet evidence; failure demotes to miss). Separate commit, P7a reviews. stdlibr depth-2 target position_or<i32,4> has 'where T: Key'.
- (10-18 17:06) integ26 GREEN on 3f97d222: matrix 48/48 (p48), stdlib 180/180, foundation 17/17, backlog 5/10 (b08 moved out). Quiet: plain 1 MB 55.6; stdlibr narrow 1286/430/432/438, full 830/457/443/456; empty after 40/39/39; ready 0.8 s. generics-gpu -> 3f97d222.
- (10-18 17:09) P7a: 7f4b4e3f TRACK specialization (SPIR-V back near pre-c5918729). record_phase_with_resources is PEV-only (others use graph BindGroupCache). Order now: item 1 (params ring, LANIUS_PEV_PARAMS_RING) -> soft obligation class for D1b step 2 (context row word 7) -> 2 -> 5 -> 4 -> 6. P11 folds solve batching (7 -> 3 -> 2) into D2-D6.
- (10-18 17:19) integ27 gate started on 5268ccec = 3f97d222 + P12 d40a61d2 (size_of p52, b07 p47, recursive types) + P4 f4aac808 (28 fixtures) + P13 6e51ed99 (b06 p53, b05 p49, b12 p50, b01 p51, w03, import_visible). PID 1258905.
- (10-18 17:38) integ27 GREEN on 5268ccec: matrix 54/54, stdlib 180/180, foundation 17/17, backlog 2/4 left open (b09 [v;N], b11 diverging arm). Quiet: plain 1 MB 55.1; stdlibr narrow 1228/429/434/430, full 851/449/444/449; empty after 40/41/43; ready 0.7 s. generics-gpu -> 5268ccec. integ2 += P10 cdda8b74, P12 20be3ef5. USER DECISION: `path < ...` uses a C#-style lookahead rule (generic args only if matching > is followed by ( :: { etc.) -> P9b. vc blocker: computed pub consts across modules not folded (00a literal-only, 00b after) -> P3.
- (10-18 17:42) **P10 v2 bench (quiet, build 8 = cdda8b74+gen fix):** w1k 54/59 ms (identical/edit), w5k 135/152, **w30k (31.2 KSLOC) 300/339**, stdlibr_narrow 434/445; rep0 w30k 976. **Rust twin (rustc 1.101 nightly, -j16, NOT quiet: load 13.7):** w30k check full 1165, check edit 470, build full 1521, build edit 603; w5k 244/119/345/174. P10 rerunning rustc at low load + CARGO_INCREMENTAL=0 edit column; w30k becomes a permanent bench row. Empty-after-big gaps: TC submit +15 ms, PEV 00_initialize +6.8 (-> P7a), parser +4.3.
- (10-18 17:45) WATCH: host crashes after output: P4 'corrupted double-linked list' at type_checker_semantics teardown; P3 m63_call exit 139 after ELF written (1 of 5, not under gdb). Likely teardown (driver/wgpu drop order?), not seen in daemon. Asked P3 for bt if it recurs. P3 canonical gate36 green (sweep 1013 -> 1016); c59dc22d keeps deep programs synchronous; const fold design approved (R=8, STAGED/PRESENT, no readback).

- P9b `<` design APPROVED (msg to P9b). Bug: angle_kinds direct_semantic_lt_kind_for gives PATH_TYPE_ARG_LT for prev2 `::`/`:` with no tail check, and the type-position branch is not gated on value context. Rule: in value context, generic args iff the matching close is in the same container and is followed by `(`, `::` or struct-literal `{`; nested angles inherit from their parent. Lead added: check the `{` follow in condition positions, a byte-identical HIR check over 180 stdlib modules + stdlibr, an error hint, and Wasm UNSUPPORTED-flag triage (44 tests) before widening, so it ends fail-closed. Order: zero-init → b09 → p59 → p54.
- 10-18 17:5x P10 rustc baseline, quiet (load ~2, 3 reps, median). w30k_rs: check full 1187 / check edit 489 / build full 1577 / build edit 599 / check no-incr edit 929. w5k_rs: 261/134/361/190/193. Lanius w30k 300 identical / 339 edit; w5k 135/152. A 10x target vs check full ≈ 119 ms; the 100 ms goal stands. Reported to the user. rust_bench.py → tools/.
- 10-18 P7a: the +6.8 ms on 00_initialize is not PEV. The gap is measured from semantic_interface.submission.begin, so it includes the lowering lane. Empty job after stdlibr: lexer.source-pack.metadata 12.8 ms host vs 2.2 fresh, and lir.status.clear 2.9 ms GPU → sent to P10. PEV's own delta is +0.6 ms (admit bind groups?, item 5). Params ring is committed 6bebca75; tests and quiet A/B pending → integ28 candidate. Soft class gate B queued (pin bbb48377).
- 10-18 P11 D1 works: e5ecefcb (p11-monomorphization). Fixed closure_call taking kind-33 callee path rows as calls; export retries now 7 (one per closure level). Hold 25 (traced, not quiet): full1mb 513→433, narrowproj 310→228; stdlibr unchanged (needs D1b). Asked P11 for depth>7 fail-closed behaviour + probe, and the retry cost on empty jobs. Integrate after hold 26q + its own tests.
- 10-18 P10 hold 5i: lexer.source-pack.metadata is a GPU wait (count readback after the fused submit), not host packing. lir.status.clear was already fixed by 8d783406. Real cause of empty-after-big +18.5 ms GPU: direct ComputeOperations fix their workgroup counts from the built capacities (e.g. optimization.rs:3040). APPROVED: record_elements with job capacities, lowering first, with a kill switch LANIUS_JOB_SIZED_DIRECT_OPS=0 and a big/small/big/small byte-identity test. Then the type-check ops, coordinated with P4 (P4 told). Traced w30k hold 5j queued.
- 10-18 P9b correction: honouring UNSUPPORTED on Wasm breaks nothing. codegen_wasm is 44/115 red at a90285c2 regardless (34 LNC0057, 6 runtime, 4 code-built). Wasm is now fail-closed like x86 (build41). Asked for a committed Wasm red-set baseline; p54 stays last and narrow (Wasm is secondary). Zero-init needs a quiet A/B before merge (noisy +5–7%).
- 10-18 P12 census #11: stdlibr link tail ~20 ms, mostly host: relocation env::var per reloc ~2.5 ms, page source copy ~0.7, mapped→Vec 2.5, untraced fs::write 5 MB + chmod 3.6–4.2 (bounded_path_codegen.rs:151). Approved the cheap link fixes (−4…−6 ms expected). P12 also takes link_executable_to_writer for the output path (P9 told; atomic write, daemon.write span, byte-identical). Fused GPU link proposal comes later.
- 10-18 W30K ROADMAP (P10 hold 5j, traced, trace S/p10/reset/h5j/w30k_trace.json). Identical 344 ms traced: GPU busy 195, idle 149, 7,163 dispatches. Edit 386: same GPU, plus a 38 ms pre-GPU gap with no span. First edit: an extra frontend attempt (9,314 dispatches).
  Host owners: catalog_freeze 40–52 ms → P7a (TOP); typecheck recording 20.5 → P9 (overlap via chunked submit); finish.semantic_interface 10.5 → P9; edit pre-GPU 38 + first-edit retry + lir.status 5.4 → P10.
  GPU owners: hir_* 42.3/984 dispatches + lir.opt 21.5/867 → P9b (after p59, before p54); type_check.calls 19.1/633 → P9's ranked list.
  P10 is moving job_split.py and gpu_idle.py into tools/.
- 10-18 integ28 LAUNCHED on integ2 44de87da (379f2f83 + P7a params ring 6bebca75, which also brings in 7f4b4e3f). Gate PID 1507933; watcher task b38lco4o1. Next: P13 f19fbab7 (its gate is running), P11 e5ecefcb (after hold 26q).
- 10-18 P10: edit 38 ms pre-GPU = SourcePackCache::load throwing away a Resident pack on any stamp change → fix: re-read only changed files. First-edit retry = the parser shape cache stores the exact token count → fix (a): headroom buckets. Both approved; P10 owns both. tools/trace_job_split.py + trace_gpu_idle.py committed (a3a29cba).

- 10-18 generics-gpu = 44de87da (integ28 green: matrix 54/54, stdlib 180/180, sf 17/17, backlog only b09/b11 left; stdlibr 429–457, empty after stdlibr 36–42, 1 MB 55.7, ready 0.7 s; load 4.6–6.5 during quiet). Includes P10 cdda8b74, P12 20be3ef5, P7a 6bebca75.
- 10-18 integ2 = ef59ccaa (44de87da + P13 4be5b902: d3 fix f19fbab7, p57, b14). NOT gated yet; batch it with the next tips (P11 e5ecefcb after 26q, P12 link fixes) as integ29. p60 allocated to P13 (d3 probe). compiler_generic_types_execution baseline at 5268ccec: 474/481, 7 known failures, listed in P13_status.md. Pins: 6bb01b8f=d6414d14, 3b363efa=3f97d222, 9c39e634=e2930101, 7cf363bc=5268ccec, 7114566a=44de87da.
- 10-18 CORRECTION: w30k untraced first edit = 377 ms (the shape-miss retry); later edits 337/339. Headline w30k: 300 identical / 377 first edit / 339 edit median. workload_bench now prints the first edit (0bb1885d).
- 10-18 P3 computed-const fold landed: c29bd430 (fold be404925 + canonical c59dc22d). Gate38 green: matrix 61/61 (p58, p58a–f), CGTE 474/7, depth 9 → named LNC0057 (bit 0x4000). Clean merge onto ef59ccaa; merge into integ29 after P3's quiet A/B (deferred vs sync). Side items: layout assert 80→84 from eaad5c2d → P12; flapping allocation-count tests → P10.
- 10-18 integ2 = e628cbe6 (+ P7a soft class 44162e4c; word-7 ABI final for P14). Ungated.
- 10-18 integ29 LAUNCHED on ac3e6473 (44de87da + P13 4be5b902 + P7a 44162e4c + P3 c29bd430). P3 quiet A/B: canonical deferred saves 21–23 ms on stdlibr (419/431 vs 440/454).
- 10-18 P9b zero-init faab83b2 (parent a90285c2) ACCEPTED: quiet A/B flat (stdlibr 466→463, empty-after 41.8→41.7). Merge AFTER integ29 finishes (main checkout busy) → integ30. Wasm baseline: tests/fixtures/known_gaps_codegen_wasm.txt (44). The hir_* plan is approved: items 1–3 (~10 ms/job), later a Pareas-style design note (~14 ms/job). P9b order: p59 → hir 1–3 → b09 → hir 4–5 → lir.opt → p54.

- 10-18 generics-gpu = ac3e6473 (integ29 green: matrix 62/62, stdlib 180/180, sf 17/17, backlog b09/b11 only; stdlibr_narrow 406–410, full 418–425, empty after stdlibr 34–39, 1 MB 52.7, ready 0.8 s; load ~4–5). Includes the P3 const fold + canonical deferred, P13 d3, P7a soft class.
- 10-18 integ2 = 227ad609 (ac3e6473 + P9b zero-init faab83b2). Ungated; next is integ30.
- 10-18 P3 imported-type key design APPROVED (S/p3/imported_key_design.txt): J=span+root, tag 7 via deps/16b. 2-page probe p61 first (possible multi-page bug in argument_pattern_ids). Const overflow = compile error (my ruling, to tell the user). Type-level fold comes after the key work.
- 10-18 P7a catalog_freeze fix (uncommitted, pin afae5a63): w30k freeze 38–40 → 10–11 ms (dependency_pages to_bytes ×1000 → PartialEq short-circuit). But P7a's branch measured w30k 860 / stdlibr 535 ms (stale base?) → told to rebase onto ac3e6473 and re-measure; asked for the PartialEq/bytes equivalence argument + a debug assert. Lazy snapshot bytes are next.
- 10-18 P12: vc on the P3 fold gets 62/117 modules (was 25). The rest are blocked by private-type fields in pub structs (0x8000 'cannot export type' ICE) → ruling (b) Rust-like, P12 owns it after the writer path + layout assert. Link fixes: stdlibr −12 ms (pages 7.6 → 5.1), byte-identical; committing.
- 10-18 P11 D1 hold 26q quiet: full1mb 285→217, narrow1mb 272→196, narrowproj 264→197, stdlibr ≈0 (needs D1b), plain flat. fb89a1dd = indirect export + named fallbacks (depth>6 → whole-unit closure ignored → copy runs). It conflicts with integ2 in resident.rs → P11 to merge 227ad609 and rerun probes + an interleaved empty-after A/B (closure on was 43–46 vs off 40–41). p62/p63 allocated.
- 10-18 P12 (b) design APPROVED: hidden decls (DECL_FLAG_HIDDEN, closure in 08c, LNC0075 for pub signatures). Conditions: hidden impls must stay reachable from library generic bodies (p65), closure depth fails closed (>16), coordinate 05/06 edits with P3. p64/p65 allocated.
- 10-18 integ2 = 8b797c90 (+ P13 a263363a: p60, tests/known_test_failures.txt + tools/check_known_test_failures.py). b14 = UFCS for self methods, never implemented.
- 10-18 HEADLINE on integ29 (P7a quiet, pin 73ef3881): w30k identical 273.1 / first edit 331.2 / edit median 312.5 ms; stdlibr_narrow 411. Freeze on integ29 is 27–30 ms traced on w30k; P7a's fix (4c742fd3 + lazy bytes e8bc3216) gates on r2.
- 10-18 P12 scratch (a): with 9 helper types made pub (transitively), vc compiles 117/117 modules and both entries (2.6 MB / 2.4 MB ELFs). Private field types are the last compile blocker. Asked for vc SLOC + a warm compile bench (a candidate headline row) and a vc run row after the hidden-decl work.
- 10-18 SCALED DOWN to 4 agents (P10, P9b, P11+D1b/D7b, P12). Parked: P3, P4, P7a, P9, P13, P14, each committing, cancelling its heavy jobs and writing S/<agent>/HANDOFF.md. The lead gates parked branches later (P7a freeze r2 first: worth ~28 ms on w30k).
- 10-18 P4 PARKED: p4-never 554f7a34 (WIP, ungated; 10 never_type tests pass on pin40) on top of d618d60d (imported-key docs, ready to merge). b11 needs P9b's lowering + the panic '-> !' change. See S/p4/HANDOFF.md.
- 10-18 P14 PARKED: D1b WIP bfddb320 on branch d1b (pin 7ce06665); handed to P11 via S/p14/HANDOFF.md. Open: output differs from deps-off by body order; the chains fixture records no closure.
- 10-18 P13 PARKED at 3d8efa3e (triage reasons in known_test_failures.txt). The constant-family failures are 4 causes: a REAL bug (inference loses a binding when a header has >32 generics in total), 2 stale tests, noninteger constant params giving LNC0027/0047 instead of LNC0006. b14: methods/07 skips path self methods on purpose; the plan is in S/p13/HANDOFF.md.
- 10-18 P9 PARKED: p9c-tail c1416b76 (on 44de87da). Gated in hold62, identical outputs: chunking 9ad2c872, tally fa2c062e, L1 6616fe7f, semantic_interface spans 58a20bc3. WIP: write-order check c1416b76. Quiet A/B hold62q.sh not run. Findings: a real early-submit hazard (round-0 call_inference_state write after a cut); finish.semantic_interface from_bytes ~7.5 ms, of which validate.implementations is 5.5 ms (host; a cheap target for later). Ranked TC list in S/p9/HANDOFF.md.
- 10-18 P3 PARKED: p3-ct-subst e3aa43a1 (WIP LNC0074 overflow, ungated) on 911fd020 (p61 lib test, ungated). No p61 GPU result; p61 may miss the bug (annotated locals → tag 3), so a p61b with a cross-page tag-5 call-result argument is needed. Handoff S/p3/HANDOFF.md (build39.sh → gate39.sh).
- 10-18 P10 hold 5k (pin 82f7a814): w30k identical 287, first edit 299 (no retry), edit median 305; edit load 36 → 0.6 ms. Job-sized direct ops are BUGGY (stdlibr_narrow LNC0057, order test 10/11, 7/11 with poison) → keep default off and bisect. Headroom + source refresh commit first.
- 10-18 ALL 6 PARKED. P7a: e8bc3216 on ac3e6473 (branch worktree-agent-afc9d2f4adb04a904), ungated. Lead is running the r2 build → quiet A/B → gate itself (scratchpad/lead/p7a_r2.sh, task bha8r1gme). Merge into integ2 if green.
- 10-18 HEADLINE vc (P12, scratch pub copy, P3 pin adf6812c, quiet): compiler.lani closure 105 files, 25,246 SLOC: identical 69.2 ms median, first edit 110 (frontend retry), edit median 85.5 (the ~20 ms load gap that P10's refresh fixes). So real non-generic 25 KSLOC is under 100 ms. w30k (generic-heavy, generated) is 273.
- 10-18 integ2 = dfb38d38 (+ P11 D1 839d67ad: narrow1mb −78 ms, empty-after on/off 32.0/31.8 (noise), matrix 64/64). integ30 waits for the P7a r2 check, then gates both.
- 10-18 P7a freeze check (lead-run): w30k identical 265.8 → 242.8, edit 312.6 → 284.1; stdlibr ELFs identical to integ29 (the 'DIFFERS' was against a stale pre-rebase reference). PEV 4 known failures. The predicates itest SEGFAULTED (139) after 'test result: ok', the 3rd host-teardown crash. Merged → 9e9c7851. integ30 LAUNCHED on 9e9c7851 (P9b zero-init, P13 notes, P11 D1, P7a freeze).
- 10-18 P12 bb0f210f (link copies 4af01e3f, writer path 0aaf48bd with atomic rename, assert 84 1fbcf52c, tools/vc_bench.py) merges cleanly; merge AFTER integ30 → integ31. Hidden-decls pass placed after path resolution, before canonical_candidates.

- 10-18 generics-gpu = 9e9c7851 (integ30 green: matrix 65/65, CGTE 474/7 with 0 new, stdlib 180/180, sf 17/17; stdlibr_narrow 423–432 (integ29 406–410, load 5–6 vs 4–5: WATCH), empty after stdlibr 35, 1 MB 53.5, ready 0.7 s). Includes P11 D1, P7a freeze, P9b zero-init.
- 10-18 Lead A/B integ29 vs integ30 on stdlibr_narrow (quiet, 3 rounds): i29 418–426, i30 416–428 → NO regression; the gate's 423–432 was load noise. P10: job-sized ops fixed (lir.opt.regions.ownership.clear excluded), order test 11/11 with poison, empty 37 → 29, w30k 296 → 286; flipping default ON in build 12. Commits d712e180 refresh, 79dac0e0 headroom, 4c5e51c0 job-sized. Flapping counts fixed with per-thread counters. Open: dependency_pages_preserve_record_fields... LNC0042 (pre-existing?).
- 10-18 integ31 LAUNCHED on fcf4fc49 (9e9c7851 + P12 bb0f210f + P11 D1b 76ae04c9; expect stdlibr ≈ 375–390).
- 10-18 P9b p59 fa8de8e2 ACCEPTED (token-kind identity over 1,887 streams: 4 differ, all fixes; bound_context leak fixed). Merge after integ31. x86_loads_field_after_multiword... segfaults from the CLI on i28/i29/i30 (pre-existing; possible test bug: rows past an 80-byte alloc) → #[ignore], P12. cli_daemon 79 pipelines after readiness → P10 (readiness set from the pass registry).

- 10-18 generics-gpu = fcf4fc49 (integ31 green: matrix 67/67, CGTE 475/7 with 0 new, stdlib 180/180, sf 17/17; stdlibr_narrow 361–366 (was ~420), full 375–396, empty after stdlibr 34–35, 1 MB 53.0, ready 0.8 s; load ~2). Includes P11 D1b + step 2, P12 link/writer.
- 10-18 integ32 LAUNCHED on 3fc7477a (fcf4fc49 + P9b p59 fa8de8e2 + P12 hidden decls 920ef045). The x86 indexed multiword test was a test bug (3-word slices), fixed in 920ef045, so P9b can drop the #[ignore]. After green: send P12 the pin for the real vc bench. Known gap: `laniusc check` skips the interface export, so LNC0075 is missed there.

- 10-18 generics-gpu = 3fc7477a (integ32 green: matrix 74/74, CGTE 475/7 with 0 new, stdlib 180/180, sf 17/17; stdlibr_narrow 363–376, full 377–388, empty 35, 1 MB 53.3, ready 0.8 s; load ~5). Pin target/laniusc-pins/f45d3869d5b5e750. Includes P9b p59 and P12 hidden decls.
- 10-18 REGRESSION: real vc fails on integ32 with LNC0017 'let x:[i32];' (from P9b zero-init faab83b2: rejects uninitialised slice/str/ref/enum/imported struct). P12 fixing: slice zero = empty view, imported structs zero-filled. The gate will compile vc (P12 to give the command). Failing-compile vc bound: compiler 47.8 identical / 90 first / 67.6 edit; extractor 45.1 / 82.8 / 61.1. P12 c97773d9: check exports the interface (LNC0075).
- 10-18 integ2 = bdf6dfba (+ P11 e928abf9 chains closure fix). P11 chose (b): declarations-only templates for copy runs (est. −60…−70 ms on the stdlibr app run, 3–5 days), with same-length body blanking, an identity validation mode, byte-identical output and a kill switch. D2–D6 come after. The app copy run is 119 ms (99.5 GPU) re-checking the 1.4 MB template for 9 bodies.
- 10-18 integ33 LAUNCHED on da331e89 (3fc7477a + P11 e928abf9 + P10 5a200923: source refresh, job-sized ops ON, headroom OFF (token bug), PEV pipelines at readiness (0 after ready, ready 0.77 s)). P10 w30k on its pin: identical 253, edit median 262, first edit 289 (259 with headroom). Open: headroom token-capacity bug (LNC0042) → P10 first, checking whether a shrinking edit hits it live; multi-daemon startup stall (3/5 never ready); paged-readback stale-bytes flake.
- 10-18 P9b hir item 1 611bcbf6 (walk early exit): exact (1,870-stream HIR identity), −3 ms/w30k job (noise-level end to end). Merge after integ33. Reordered P9b: b09 → lir.opt fusion proposal (dispatch counts); hir 2–3 parked. HIR runs 3×/w30k job (original + 2 copy runs?) → P11's (b) may cover it; P11 to report a w30k copy-run breakdown.

- 10-18 generics-gpu = da331e89 (integ33 green: matrix 74/74, CGTE 475/7 with 0 new, stdlib 180/180, sf 17/17; stdlibr_narrow 365–369, full 371–391, empty after stdlibr 29 (was 35), 1 MB 53.9, ready 0.8 s; load ~2). Includes P10 job-sized ops ON, source refresh, readiness PEV pipelines; P11 chains fix.
- 10-18 integ2 = 26a58be9 (+ P9b hir item 1 611bcbf6; reverted its #[ignore] 3d7ce2b2, since P12 fixed the test). integ33 w30k quiet (lead): identical 258.8, first edit 287.9, edit median 264.3. The gate now runs w30k too. P11 (b) approved (empty-brace blanking + prefix-sum remap); then D3 (bound members per instance) to remove w30k's run 2. w30k: 155 of 286 ms is 2 copy runs.
- 10-18 integ2 = 9318578e (+ P12 492f3c79: zero-init slices/imported structs p67–p67f, check exports the interface, tools/vc_run.py; the gate now compiles vc). REAL vc bench (quiet): compiler 25 KSLOC identical 69.2 / first edit 108.6 / edit median 82.9; extractor 61.1 / 103.9 / 77.8 (no P10 refresh/headroom in that pin). vc RUN row: 7/81. The vc-built compiler exits 10 on everything because vc hard-codes record sizes for 2-word slices (TREE_BYTES etc.); recorded as a known gap; ASK THE USER whether to fix vc via size_of. P12 next: validate.implementations 5.5 ms host, then the fused link proposal.
- 10-18 integ34 LAUNCHED on 9318578e (da331e89 + P9b hir1 + ignore revert + P12 zero-init/vc_run).
- 10-19 15:51 REBOOT (orderly poweroff 10-18 23:36). /tmp scratchpad WIPED: lead scripts, agent scratch, parked HANDOFF.md notes, workloads. Git work survived. Rebuilt on disk:
  target/claude-work/lead/{gate.sh,stdlib_probe.sh,cgte.sh,quiet_both.sh} (output in lead/out/); workloads in target/claude-work/bench/wl/{stdlibr_narrow (sha c6e94982, matches the original), stdlibr_full, w30k (+w30k_rs), empty}; generator recovered to bench/tools/generate_stdlib_workload.py. The gate dropped the lost ad-hoc probes (p4r, casts, probes7, a247 rcc). integ34 relaunched on 9318578e.
- 10-19 LIVE BUG (P10): a warm daemon edit that REDUCES the token count makes valid code fail (LNC0017 AGGREGATE_INIT / LNC0042), because the cached parser shape keeps the old larger token_capacity and some consumer type-check/lowering reader treats capacity as the count. Fresh daemon OK. Stopgap ordered first (retry when token_count != capacity) + a permanent test; then the root cause; the bench edit mode will alternate insert/delete. P10 committed generate_stdlib_workload.py (52792b6e).

- 10-19 generics-gpu = 9318578e (integ34 green on the rebuilt gate: matrix 81/81, CGTE 475/7 with 0 new, sf 17/17, backlog 2/4 (b09, b11), vc compile 2/2; quiet, load ~4: 1 MB 50.3, stdlibr_narrow 347.9, full 362.6, empty after stdlibr 29.3, w30k identical 247.7 / first edit 276.2 / edit median 249.3, vc compiler 61.8 / 87.9 / 62.2, vc extractor 58.7 / 78.6 / 58.2). stdlib --each not run this time (script fixed).

## 10-19 P10 token-shrink bug
- Stopgap f61a47e5 (tip 9bd8df59): REJECTED. It adds +165 ms to every warm w30k job (413 vs 248 identical) because cached capacity never equals count.
- Root cause: 3 type-check kernels (07_project_imported_fields, 02b_clear_application_index, 02c_index_closed_applications) stride by gParams.n_tokens (the capacity) but are launched with min(cap, token_count) lanes, so rows past the launched lanes (generated body rows) are skipped.
- Fix: live_type_row_lanes in build 17; headroom default back ON. Waiting on the hold: w30k headroom on/off, the shrink bench, proof the lib failures are on base, and a lib known-failure section.
- 10-19: merged P12 4fe15735 (validate.implementations linear; w30k identical about -13 ms in P12's A/B) into integ2 as 49c4c03b. Not gated yet; it goes into integ35 together with P10's fix.
- P12 next: drop the second validate within a job (keep a check mode), then instrument the 21.7 ms of the gaps phase that has no host span, then unit_facts.claims (7.9 ms). Fused link deferred (only about 2 ms).
- 10-19: P9b b09 = 27a65d25 (p9b-parser-perf), on old base 611bcbf6. Asked it to rename the probe to p70, merge integ2 and re-gate. Then lir.opt Option A (skip validation on replays, env override), then the safe fusions (-28 dispatches/run), then p54.
- 10-19: merged P9b d26f4bbd (b09 array repeat, p70) -> integ2 17aff373. Not gated yet; it joins integ35 with P12 49c4c03b and P10's fix.
- Pre-existing bug on integ2: 3 codegen_x86 slice tests fail with LNC0006 "i32 but expects usize" on arithmetic with imported usize consts (`2 * record_bytes + lowering::unit_descriptor::ALIGNMENT`, `4 * verified::token::RECORD_BYTES`). Queued for P12 after the gap instrumentation. May relate to the vc run row.
- 10-19: merged P10 aac79b1b (live-row stride fix, headroom default OFF) -> integ2 b9d954cd. Launched gate integ35 (lead/out/integ35.out) = P12 validate + P9b b09 + P10 fix. P10 next: per-thread test headroom override, then the LNC0010 capacity reader (module resolution) with headroom=1, then headroom default ON (first edit -28 ms).
- 10-19: P12 6395ab30 (skip same-job revalidate, about -3 ms) is accepted; merge after integ35. The LNC0006 x86 failures are vc test programs needing `as usize` (the consts are i32). Waiting on the user's OK to edit verified_compiler/tests and the record sizes.
- 10-19 integ35 = b9d954cd GREEN, promoted generics-gpu. Load ~2. Results: matrix 82/82, CGTE 475/7 (0 new), sf 17/17, vc compile 2/2, 1MB 50.2, stdlibr narrow/full 349.8/362.6, empty 28.3, w30k 235.2 / first edit 272.6 / edit 241.7, vc 63.3/59.2.
- Merged P12 6395ab30 -> integ2 (not gated yet).
- Fixed a heavy deadlock: a queued --quiet job took the build slots that the running --quiet GPU holder was waiting for, costing 25 min. The holder now writes /tmp/claude-1000/lanius-build.draining and queued quiet jobs yield to it. Installed by atomic mv.
- 10-19: merged P12 vc edits (29ad745c, 9ab13141) and p71/p71a -> integ2 b7fa9378 (not gated). vc run row 7/81 -> 71/81. The gate now runs the full vc_run row. P12 next: two -11 segfaults on invalid generic slice programs (backtrace), then checker gaps (`return;` in an i32 fn, non-bool while; p71b/p71c), then the gap instrumentation.
- 10-19: merged P10 686a7830 (thread-local test override + HIR scan scratch sized max(tree, token); LNC0010 fixed) -> integ2 c3b36ac1. P10 next: headroom default ON. integ36 waits for P10 item 3 + P11 (b).
- 10-19: merged P9b a8dedf6b (Option A, edits -6..-9 ms) -> integ2 813b6dd1. cgte.sh now sets LANIUS_LIR_VALIDATE_REPLAYS=1.
- P12: the -11s are oracle ELFs segfaulting at run time, because laniusc accepts a bool length and an i32 ptr in slice_from_raw_parts. backend_descriptor_slice_field is a vc test with 2-word slices; approved under the user's size approval (size_of). Checker gaps: `return;` with scalar returns, while non-bool. p71b-e = P12.
- 10-19: merged P11 (b) 0e090c31 (w30k -48, stdlibr -62 in P11's A/B) -> integ2 de34344e. Launched integ36 (out/integ36.out) = P12 vc + P10 LNC0010 + P9b Option A + P11 (b).
- 10-19: P10 e26a7090 (headroom default ON, first edit -25 ms) is accepted; merge after integ36.
- 10-19 integ36 = de34344e GREEN (load 4-5), promoted generics-gpu. matrix 86/86, CGTE 475/7 (0 new), sf 17/17, vc compile 2/2, vc run 71/81, stdlibr narrow/full 284.7/300.8, empty 27.5, w30k 181.1 / first edit 209.2 / edit 190.6. vc REGRESSED 63 -> 88 ms (extractor 59 -> 81). Suspect: vc now uses generic size_of<T> (P12's vc edits) and so takes copy runs. Running an A/B of old vs new vc src on the integ36 pin (lead/out/vcab.out).
- Merged P10 e26a7090 (headroom ON) -> integ2 74cb799f.
- 10-19: vc A/B confirms +20 ms comes from the source (size_of<T> calls), not the compiler. P12 queued: size_of of a concrete type needs no copy run, and size_of allowed in const initializers (p72).
- 10-19: merged P10 4fef73e0 (stdlibr_str workload, tools only). The quiet gate now includes stdlibr_str. (b) is just as good with strings: -64 ms. A cold first job on a new project in a warm daemon takes ~950 ms. Stdlib gap: str has no methods (.len()).
- P10 next: startup-to-ready (5 runs), a fresh w30k breakdown and the cold first-job trace -> reports/BREAKDOWN_10-19.md.
- 10-19: merged P11 5590a010 (lowering cache capacity floor; new-shape rep1 w30k 325 -> 223) -> integ2 4c6f025b. Launched integ37 (out/integ37.out). P11 next: D3, then rodata.
- 10-19: P12 5ab2ee08 (checker gaps -> LNC0006; p71b-e; matrix 88/88; vc run 75/81) is accepted; merge after integ37. size_of: copy run of 3 instances confirmed (+19 ms). Ruling: skip the host fold (step 1); do step 2 (checker intrinsic, constant value, usable in const) AFTER the gap instrumentation. Gap noted: a full path core::mem::size_of without an import is rejected. backend_descriptor_slice_field gets the literal fix.
- 10-19: P9b F1 cb5b6363 (radix bases folded, -12 dispatches/run, ~noise) is accepted; merge after integ37. Fusions stopped; P9b on p54. Redirect P9b from P10's breakdown.
- 10-19 integ37 = 4c6f025b: everything green EXCEPT the 1 MB perf rc=1. Every warm sample creates about 69 bind groups after priming (workspace_request_kind cold_or_grown); compile 48.9 ms. Load 6. w30k identical 193.7 (vs 181.1), first edit 185.0, edit 185.0; stdlibr 284/296/294 (str); vc 85.8/78.8. NOT promoted yet. Running a headroom 0-vs-default A/B on the 1 MB check (out/perfhr_*.out).
- 10-19: headroom confirmed as the cause of the 1 MB bind-group churn (=0 passes on the same pin); sent to P10 as urgent. Merged P12 5ab2ee08 + P9b cb5b6363 -> integ2 88b5b7f0 (not gated). generics-gpu stays de34344e.
- 10-19: merged P12 87f2f9e8 (vc test 3-word layout, vc run 76/81; 5 tcs known failures) -> integ2 be963b1b. P12 on gap instrumentation (branch p12-gaps).
- 10-19 P12 gap breakdown (traced w30k job 235.6 ms): original 80.6, 2 replays 84.0, gaps 71.0. Gap 0 is 43.7 ms (unit_facts 12, check.solve 13.6). Approved order: (1) proof-store capacity floor + Work seed rounded to a power of two (~-4..5 ms; a retry every job); (2) solver waves default ON (~-2..3 ms; lead ruling since P7a is parked); (3) GPU-packed unit-facts rows (~-6..8 ms). Host bookkeeping (~12 ms) is next round. size_of step-2 design: target/p12/size_of_step2_design.md in P12's worktree.
- 10-19: merged P11 D3 8f875e6f (w30k copy runs 2 -> 1; quiet A/B w30k ~205 -> ~162 ms; ELFs -1998 B per removed run) -> integ2 263a2685 (not gated). P11 next: rodata (p73/p74), then an analysis of the remaining copy-run cost.
- Determinism bug, pre-existing: repro_nominal_parameter_after_field_assignment gives 2700 or 2728 bytes (an extra spill pair), 10-40% of runs. Given to P9b ahead of p54.
- 10-19: merged P10 150907a0 (topology bind groups marked used; 1 MB churn fixed) -> integ2 e5e8c1b6. Launched integ38 (out/integ38.out) = D3 + P12 checker/vc + P9b F1 + P10 fix. P10 measures on e5e8c1b6 (incl. settling jobs 1-2).
- 10-19 integ38 = e5e8c1b6 GREEN, promoted generics-gpu. matrix 90/90, CGTE 475/7 (0 new), sf 17/17, vc compile 2/2, vc run 76/81, 1 MB perf rc 0, stdlibr 289.0/304.2/298.4 (str), empty 31.5, w30k 147.2 / first edit 154.0 / edit 149.9, vc 84.7/79.9 (size_of copy run, P12 step 2).
- 10-19: merged P11 e6c49058 (rodata rebase, string guard removed, p73/p74) -> integ2 a93b602f (not gated). Check that p73's probe fix is in the commit.
- 10-19 BREAKDOWN_10-19.md (P10, e5e8c1b6): STARTUP to ready 675 ms median / 696 max (goal < 5 s MET). First job after ready: w30k 760 ms. Multi-daemon stall intermittent (2/8). w30k traced: GPU busy ~117 ms; top items: copy run 53 ms (re-runs the whole frontend), LIR 31.6, parser 26.2 + 37 ms of readback waits, evidence 21.7, generic-call TC 19, unit_facts 15, specialization host 15.5, TC recording 13.5. Settling takes 2 jobs.
- Assignments: P11 = a copy-run frontend-reuse design (before building), then evidence / TC generic calls / unit_facts / spec. P9b = determinism, then the parser readback waits (proposal), LIR, hot spots. P12 = current 3 fixes, then settling, TC recording, cold workspace sizing, multi-daemon stall, tail. P10 = commit tools + startup after a shader change + hand-off, then park.
- 10-19: merged P12 8aefd3f0 (PEV capacity floor, about -4.7 ms) -> integ2 9359436b (not gated).
- 10-19 decision: P11 starts the E plan (D2 -> D4 -> D5 -> D6, virtual rows; deletes the copy run, net ~-40 ms w30k), flag-gated and in increments. D (count-sized dispatches, 16 big ones) -> P9b with #9. #6 unit_facts local_lookups -> P12 entirely. #4 evidence waits (P11 only if D2 stalls). A/B/C skipped. Path to < 100: E -40, P12 host -12..16, P9b parser readbacks + D -10+ => ~80-95 ms.
- stdlibr_str rodata A/B: noise (+0.45% tokens blanked).
- 10-19: merged P10 tools 8ad16194 -> integ2 38e0dcfa. P10 is finishing the post-shader-change startup measurement, then the hand-off and park.
- 10-19: P10 PARKED. Hand-off: target/claude-work/handoff/P10.md. Startup after a 1-pipeline shader change: 679 ms (+20-30 ms per changed pipeline). Active agents: P9b, P11, P12.
- 10-19: merged P12 166e027d (solver waves default ON; edit -3.5 ms) -> integ2 9c7c6f78. Launched integ39 (out/integ39.out) = P11 rodata + P12 floor + waves + P10 tools.
- 10-19 integ39 = 9c7c6f78 GREEN, promoted generics-gpu. matrix 92/92, CGTE 475/7 (0 new), sf 17/17, vc 2/2 + run 76/81, 1 MB ok, stdlibr 290.5/297.1/289.1 (str), empty 29.7, w30k 137.1 / first edit 144.7 / edit 144.7, vc 84.5/81.0. NOTE: stdlibr (~1.4 MB, the realistic one) is still about 290 ms; its copy run is core-cross-unit, so the E plan is needed for both.
- 10-19: P11 says D2-D6 can't reach the cross-unit core copy run (stdlibr). Warm path = D7b, staffed with NEW agent P15 (Opus, worktree, D7b library instance cache; design first). Miss path = D7c dependency template band, scheduled after D5; D2a builds the (source, row) indirection now. Agents: P9b, P11, P12, P15.
- 10-19 USER DECISION: slow down to 2 agents (P15 D7b, P11 D2+). P9b and P12 park with hand-offs in target/claude-work/handoff/.
- Merged P9b 944825ab (visible_type race fix; fresh-daemon determinism test) -> integ2; removed 41 stray lanius-capture dumps + .gitignore in 9e7709f0 (not gated). P9b parking now (atomic-order audit item in its hand-off). P12 finishes packed unit facts, then parks.
- 10-19: P9b PARKED, hand-off at handoff/P9b.md. Open: the atomic-order audit; WASM BUG: struct copies alias (modifying a copy changes the original; x86 is correct; nested structs need a Wasm storage rework); p54 WIP at 639b1925; p9b/det/dump2 = 3.3 GB, deletable after the audit.
- 10-19: P15 D7b design approved (per-instance keys, whole-run values, admit_cached_instances, 32 MB UnitCache, check mode). Notes: impl-binding key uses app HIR row (pessimistic), one-check soundness via check mode on matrix + sweep, hit/miss per job type, rebase onto 9e7709f0.
- 10-19: merged P12 603ac0c2 (unit-facts row reads; w30k -8.9 identical / -6.2 edit) -> integ2 62e43f17. P12 PARKED (handoff/P12.md, P12_size_of_step2_design.md).
- Headroom bug (from e26a7090): record_token_file_ids records token_capacity*4 bytes but the cached copy is validated at min(lexer, parser) size -> panic in type_checker_semantics, poisoning 227 tests. Lead fix (uncommitted, main checkout): clamp to copy.size() (driver.rs ~1270, buffer.rs size()). Testing with lead/tcs.sh hrfix.
- Active agents: P11 (D2a), P15 (D7b).
- 10-19: P11 D2a c4ac7e34 (instance table + D′ check; flag off by default) accepted; merge after the tcs build. P11 owns const-param u32/usize normalization (p75), then D2b.
- 10-19: lead fix 146ede90 (token file-id copy clamp; tcs 249/5, 0 new) + merged P11 D2a c4ac7e34 -> integ2 1bf94dcd. The gate now also runs type_checker_semantics (lead/tcs.sh). Launched integ40 (out/integ40.out).
- 10-19 integ40 = 1bf94dcd GREEN, promoted generics-gpu. matrix 92/92, CGTE 475/7, tcs 249/5 (0 new), sf 17/17, vc 2/2 + run 76/81, 1 MB ok, stdlibr 289.2/293.8/285.7, empty 30.7, w30k 132.2 / first edit 139.7 / edit 139.7, vc 84.3/80.0.
- 10-19: P11's u32 length is ct_realize's count convention, not a bug; D′ compares lengths as counts; p75 pins it. Removed a stray '--help' file (from 944825ab) in 895873b8 = integ2.
- 10-19: merged P15 D7b 3c4ec5da (stdlibr -31..34 ms; check mode 0 mismatches over the matrix, workloads and 994 stdlib ELFs; w30k unchanged) -> integ2 8769552b (not gated). FINDING: library id 0 != stdlib (w30k's app unit is 0:0). P15 is auditing D7-0 (unit_cache.rs:869) for an accidental app-unit cache on w30k identical jobs -- a possible bench-honesty problem. Then the gap from -31 to -55..65.
- 10-19: merged P11 d8c5b690 (D′ counts class, p75) -> integ2 d5df495b. Language gap: no array len() (like str methods). P11 D2b plan: MATCH/RETURN rows, bound-call rows (03c), 03c const pattern params (p46).
- 10-19 P15 audit: D7-0 NEVER caches an app unit (w30k takes the Resident path, which never calls compile_cached_pending_original_unit; loaders give library 0 only to the stdlib root). The w30k headline numbers are clean. The D7b -31..34 ms = the whole core run on today's pin (55-65 was an old figure); a hit costs 3.2 ms. P15 next: explicit stdlib flag in SourcePackJob, then stdlibr specialization.scan (28 ms host) + 30 ms unspanned (proposal first).
- 10-19: launched integ41 = d5df495b (D7b + P11 D′ counts).
- 10-19 integ41 = d5df495b GREEN, promoted generics-gpu. matrix 93/93, CGTE 475/7, tcs 249/5, sf 17/17, vc 2/2 + run 76/81, 1 MB ok, stdlibr 252.8/253.8/249.3 (D7b -36..40), empty 29.5, w30k 135.5 / first edit 140.6 / edit 135.2, vc 65.4/60.2 (D7b caches the size_of instances -> back to the pre-edit level).
- 10-19: merged P11 D2b-1 77c00b10 -> integ2 f109d10c. p76 = P11 bound-call probe (D2b-2).
- 10-19: merged P11 D2b-2 56f2c0f4 (D′ differ 0 on the matrix; 06_table_rows 16.3k) -> integ2 d2c67174. p77 = P11 const pattern probe (D2b-3).
- 10-19: merged P11 D2b-3 2172bbbe (D′ exact on the matrix 128/128, workloads exact; p46/p77 ELFs -2 KB, one fewer run) -> integ2 469ef333. P11 plan: measure the copy-run share first, then D3a, D4a, D5a-e (6-10 sessions; D5c needs decl/region bands, which were P9b/P12's, both parked), then D6a. First time win ~2 weeks; the D6-w30k milestone (switch units as their shapes are covered) is approved.
- 10-19 P11 measurement (469ef333, traced): removable by D6 = ~29% of a warm job: w30k ~53.5 of 185 traced -> ~97 ms quiet; narrow ~82.8 of 285 -> ~182 ms quiet. narrow then still needs its original compile (120 traced, 65 of call-inference waits). specialization.scan is 27.4 ms on narrow vs 4.0 on w30k (P15 is investigating). P11 now on D3a.
- 10-19: merged P15 52860025 (explicit stdlib identity) + 65946963 (spans) -> integ2 d6e5b88a. stdlibr host residue is all app-side: scan 25.7 ms (75% in checked_replay_environment over 18k call sites -> ~70 bodies), append_call_inventory 11.2, evidence host ~5, release 4.6. Approved S1 (memoize the replay env within the scan, -20..24 ms) then S2 (call-inventory interning, ~20 ms, check mode + kill switch). The stale stdlib_path test expectation goes to P15.
- 10-19: merged P15 S1 bfcc206f + f31d78b8 (scan memo; stdlibr ~246 -> ~225 ms; stdlib_path fix) -> integ2 68cf8fe7 (not gated). P15 on S2.
- 10-19: launched integ42 = 68cf8fe7 (D2b-1..3, P15 stdlib flag + S1).

## integ42 (68cf8fe7) — PROMOTED generics-gpu = 68cf8fe7 (2026-10-19)
Adds D2b-1..3, P15 explicit stdlib identity, S1 scan-env memo.
build ok; matrix 95/95; stdlib probe sf 17/17, backlog 2/3 (expected); CGTE 475/7 0 new; TCS 249/5 0 new;
vc compile 2/2; vc run 76/81 (known vc-side diffs); 1 MB perf ok.
Quiet: stdlibr narrow 227.9 (was 252.8), full 231.8, str 234.4, empty 30.1; w30k 135.7 (first edit 140.6, edit med 137.4);
vc compiler 66.4, extractor 62.0. Load after 4.19.
Next: P15 S2 (packet call-inventory interning, ~20 ms), P11 D3a -> D4a -> D5a.

## 10-20 status
- P15 PARKED (handoff target/claude-work/handoff/P15.md). S2 merged into integ2 as 29e12f33 (not yet gated; gate with P11 D3a+D4a).
- P11 D3a = 46297e0e (p11-monomorphization worktree), accepted; P11 now on D4a. Merge D3a+D4a together, then gate integ43.
- P16 (new, replaces P15 to keep 2 agents): cross-language compile benchmarks for user — Vx (vx-lang/Vx v0.0.3), V, TypeScript tsc (npm typescript, TS7), tsrs (oxc-project/tsrs, Cloudflare), D (dmd + ldc2), Go latest; toolchains in target/claude-work/toolchains; viewer labels in tools/perf-viewer. User approved those downloads.
- 10-20: user paused compiler-perf work ("stop the subagents working on making the compiler faster for now"). P11 STOPPED mid-D4a; its uncommitted work saved as a WIP commit on p11-monomorphization (worktree agent-a08326ac3a65a8f70) on top of D3a 46297e0e. D4a origins check was exact (matrix 97 roots/31 parents, w30k 16 parents, 0 differ) but its commit gate never ran. integ2 = 29e12f33 (S2 merged, ungated). generics-gpu stays 68cf8fe7. Only P16 (benchmarks) active.
- 10-20: user asked for the latest stable merged into one branch: local main fast-forwarded 23cd8234 -> 68cf8fe7 (= generics-gpu, integ42). Not pushed. integ2 = main + S2 (ungated).
- 10-20: main fast-forwarded to integ2 515cf3ee (S2 + D3a; integ43 correctness steps all passed, perf steps skipped at user request). Only P11's D4a WIP (94a2eb29) is off main.
- 10-20 cleanup: removed 22 agent worktrees (kept P16's), deleted 54 branches merged into main, deleted old pins (>1 day) and p11/pins, p9b/det dumps. Notes from worktrees archived in target/claude-work/archive/worktree-notes. p2 uncommitted edits saved as WIP commit on p2-stdlib-generics. 27 unmerged WIP/backup branches kept (no disk cost). Disk 81% -> 21%.
- 10-20: P16 done, merged; main = 90b2a001 (cross-language benchmarks + viewer). Last worktree removed; run data in target/claude-work/xlang (bins dropped), toolchains + MANIFEST in target/claude-work/toolchains. Viewer: .claude/launch.json 'perf-viewer' (lanius_perf.py serve :8765). No agents running.
- 10-20: P17 started (worktree): finish never type from p4-never WIP 554f7a34; stdlib panic -> !; b11 -> matrix p78. Fast tests only (no gates/perf). Next candidate: Wasm (44/115 red; P9b's untested AGGREGATE_COPY fix on p54-wip).
- 10-20: never type merged; main = edbd5d8c (P17). Matrix 96/96 (p78 = old b11). Found pre-existing unlisted failures: stdlib_runtime_contract alloc_allocator_pointer_result_contract_type_checks_fail_closed_through_stdlib_root (LNC0005 qualified const); Wasm enum tests wasm_executes_enum_pattern_before_wildcard_default_with_node + wasm_executes_multi_payload_enum_constructor_and_pattern_with_node; Wasm non-void call statement not dropped.
- 10-20: P18 started (worktree): Wasm backend — p54-wip 639b1925 AGGREGATE_COPY+LNC0036 first, then enum matches, drop/assert bugs, CONST_I64. Fast tests only.
- 10-20: Wasm merged; main = 8c52c538 (P18). codegen_wasm 1/121 red (generic calls on Wasm need Wasm body specialization). x86: matrix 96/96, CGTE 0 new, TCS 260/5 0 new. Shared fixes: alias/const result types, region_parent_step depth (>16 nesting failed on both targets).
- 10-20: P19 started (worktree): generics on Wasm; prefer target-independent specialization; add --target wasm to generics_matrix.py.
- 10-20: Wasm generics merged; main = fa468b99 (P19). Matrix Wasm 86/96 (left: references/&self p10 p14 p21 p25 p55 p67b; slice stride/len p52 p67a; byte slices p73 p74), x86 96/96; codegen_wasm 122/122; CGTE/TCS 0 new. Leftovers: linked Wasm declares 16384 initial pages (1 GiB); StrictPublished dead-code warning; every Wasm compile now runs admission+specialization+GPU link.
- 10-20: P20 started (worktree): target-neutral memory model — shared LIR layout parameterized by pointer size, shadow stack for address-taken locals on Wasm, Wasm backend consumes shared layout (delete 4-byte-word heap model), fix 1 GiB initial pages. Goal matrix 96/96 on both targets, x86 ELFs byte-identical.
