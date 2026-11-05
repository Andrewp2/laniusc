# f6v resume (agent f6v, worktree /home/andrew-peterson/code/laniusc-wt/rfront, branch f6v)
Task (11-02): (0) oracle difftest end-to-end checks of array calls (rfront 3.6);
(1) SEMANTIC_DECISIONS "Addressed locals" point 5: i32_array_data_ptr (heap view);
(2) point 6: str. Report to coordinator after each of (1) and (2).
## State
- 11-02 start: branch f6v at origin/lang 54f3c9577.
- step 0: oracle_difftest.py ARRAYS generator (array fns with [i32]/[u8] params, entry array locals,
  array calls at letEval/discard), Native stub sets r10/rbx (frame memory). frontend_difftest sets ARRAYS off.
- step 0 DONE b5b1d9ec5: oracle array calls; quick gate 24/24; oracle-300 seeds 1,2 pass.
  Found: laniusc lends [u8;N] at stride -8, Core/verified compiler 1 (SEMANTIC_DECISIONS point 2 "Lent u8 arrays", open).
  Seed 3 oracle-300: laniusc LNC0057 codegen failure on a chunk; repro f6v/laniusc-codegen-repro.lani (9 programs; each alone builds).
  Worktree target/release now symlinks main's release (old one in target/release.old-1031).
- step 1 (point 5, i32_array_data_ptr): next.
- step 1 plan written to SEMANTIC_DECISIONS point 5 ("The plan (decided 11-02, f6v)"): stages (a)-(e).
  Baseline stdlib oracle (14 std::io*/random modules, --calls 16 seed 1): 120 testable, 71 compiled,
  39 unread (all "array": i32_array_data_ptr lets), 10 uncompiled (extern callee), 446 calls agree.
  Files: f6v/so_before.txt, f6v/so_before/unread.txt.
- stage (a) DONE 6fa6c5b1b: formal/Lanius/Mini/Views.lean (ViewsHold, syncTo_ok/syncFrom_ok, frame/bindCell/
  bindLocals/assignCell/Owns.allocate). LaniusMini builds.
- stage (b) next: Fresh/Grows/Keeps generalized (54 `views = []` sites).
- stage (b) design (11-02): Core never range-checks i32s (encodeI32Array), so a *semantic* "views hold" is
  false for ill-typed programs. Split: (1) Grows becomes unconditional: next ≤ next' ∧ views only grow
  (Core only appends views, mapI32ArrayView). (2) Fresh := cells<next ∧ ViewsHold (value level, IsI32),
  established by the simulation proofs (they already return st'.Fresh). (3) sync_ok/syncFrom_ok take ViewsHold.
  (4) HostReturns: ViewsHold st → World.call returned heap world ∧ syncFrom {st with heap, world} = ok st'
  (host reads write into view blocks: the stdlib io pattern). Needs L2: Live blocks + syncFrom ok → ViewsHold.
  (5) Keeps exempts view roots; Corr gets "non-View bindings' cells are no view roots".
  Owns to be redefined: mem, sized, live, borrowed(owned=false), alone (ranges incl. max size 1 disjoint).
- RULE (coordinator 11-02): never run `ulimit -c 0` (apport dialogs); shells start at 1 byte, leave it.
- stage (b) DONE b18d8217d: Fresh = cells<next ∧ ViewsHold (trusted hash a593873d90485ed8, TRUSTED_BASE updated);
  Grows.views is EQUALITY for now (+ Grows.empty for Faithful's views=[]); stage (c) must relax it to "grows at end"
  (or give Faithful its own no-views invariant). Unhit/SliceIn in UndefTraps (raw write traps undefined only where no
  view roots), HoldsAt.unhit from fc.unviewed. Quick gate 24/24.
- stage (c) next: SrcType.View n / LetView in compiler.lani (lower_func loose_views), proofs (HoldsAt.view,
  Corr.viewed), regenerate Gen, rebuild whole library + certificates, trusted hash.
- stage (c) IN PROGRESS (uncommitted, worktree dirty): SrcType.View n / SrcStmt.LetView(id,n,fields,p,body) in both .lani,
  extracted; trusted SourceCore toCore/HoldsAt.view; Grows = next ≤ ∧ views prefix (Grows.empty removed); Guard letView_lower_inv;
  TypeSound done; LowerStmt builds; LowerEval:4372 needs stmt_letView. Backup compiler.lani: f6v/scratch/compiler.lani.before-view.
  Stdlib reads/writes the array after taking the pointer (slot[0], cell[0]=0) => View bindings stay in scope; later stage: index on View
  = heap load/store at the address in the View's first slot.
  DECIDED Corr/Keeps design: Corr.unviewed only for b.ty.isView = false; new Corr.viewed: b.ty = .view n →
  ∃ w ∈ views, w.root = cell ∧ w.address = (env slot).toNat ∧ w.length = n. Keeps gains persist (old views stay) and
  fresh : st.Fresh → st'.Fresh, so Corr.keeps rebuilds view-binding values from ViewsHold st'. lower_view assigns
  slot := pointer after the stores. Corr.sameCells for `cells_congr rfl fun _ _ => rfl` sites.
- 11-02 later: IMPLEMENTED (not committed): lani: same(View,View)=false, lower_view assigns slot:=pointer after stores,
  free fn viewed_type (placed before lower_enum_value so no P part renames; is_view/is_viewed names renamed parts!),
  params_valid / arm_bind / lower_match_arms reject viewed_type. Lean: Corr.unviewed (viewedType b.ty = false →),
  Corr.viewed (w root, address = env slot, length n, 0<n); Keeps.persist + Keeps.arrays (HeldArray: cell holds i32 array);
  Corr.sameCells; cells_congr takes nv + hold; push/alias/let_tail take nv (autoParam rfl|assumption);
  nv lemmas lowerValue_nv/lowerCall_nv/wordElement_nv/SrcType.same_view. LowerStmt + ArrayCall + TypeSound build;
  LowerEval fixing next (then stmt_letView at the statement induction).
  Extraction gotcha: lani_extract builds the extractor against current P files; if a P file breaks, hand-patch it then rerun.
- 11-02 (after compaction): LaniusMini builds (530 jobs) with stmt_letView (new Lanius/Mini/ViewLower.lean), HoldsAt.view/HeldArray
  carry length, lower_view rejects length >= 2^31, Stops.assignFrom moved Fails -> ViewLower. Next: Faithful cascade build,
  regenerate Gen manually (faithful_current.py steps, own workdir f6v/faithful), trusted hash, gate, commit.
- stage (c) DONE 6c015d2cc: LetView lowered + proved; Faithful uses Grows.next only, no-views from Ran.inv; Gen/term/GenB
  regenerated (f6v/regen_gen.py WORKDIR [term]; GenB: budget_certs.py f6v/faithful/Self.lean OUT lx_raw, copy SelfBCert0).
  trusted e8d6d7939ebcedcf. Quick gate 24/24. frontend_difftest template has letView/view.
- stage (d) next: front end reads `let a: [i32; n] = [..]; let p = core::mem::i32_array_data_ptr(a);` as LetView.
- stage (d) DONE 7478dea6e: front end reads the two lets as LetView (StmtsR.letView, CallPathHeadR.view, viewPath reserved,
  stmtsR_noViewHead); frontend cases view_array/view_repeat/reject_view_gap/reject_view_type (110 cases, 0 problems);
  trusted cbbfa2c060f54f28; quick gate 24/24. regen_gen.py must be RUN TWICE (SelfNeeds' import closure reads the real Gen dir).
- next: stage (e) stdlib oracle after; then reads/writes of View bindings (slot[0]) if the oracle shows they block the targets.
- stage (e) DONE (docs commit after 7478dea6e): oracle after: 120 testable, 76 compiled, 3 unread (i32_slice_data_ptr), 41 uncompiled
  (extern callee), 593 agree, 0 disagreements (f6v/so_after.txt, so_after/). Point 5 reported to coordinator.
  Left in point 5: View index reads/writes (blocked behind extern calls for the oracle). Next: point 6 (str).
- 11-02 merge 28ce43018: origin/lang into f6v (lang's budget_certs.py: GenB = budget_certs.py DUMP formal/Lanius/Faithful/GenB
  front_end_words grammar compile_words; 74 proof modules, build in batches of ~25). BudgetFree/BudgetMono letView cases.
  Whole library builds except orphan Lanius.Semantics.RawFieldStore (fails on lang too, imported by nothing). Gate 24/24.
- next: point 6 (str). slot[0] and i32_slice_data_ptr wait for the extern-host blocker (coordinator 11-02).
## Point 6 (str), started 11-02 after lang merge 4954f2692; plan commit 5b1865324 (SEMANTIC_DECISIONS point 6)
Refined stage (a) design (decided while reading the code; update SEMANTIC_DECISIONS when committing (a)):
- r8 = static region's MINI base (staticBase), set by the startup (`mov r8, imm64`, startup 75->85 bytes, image at elfBase+215,
  ret address 195->205; constants only in Mini/Process.lean). r8 is non-Scratch and unused. No rip-relative, no Contract/imageBase coupling.
- Mini Heap gets `staticBase : Nat := 0`, `statics : List UInt8 := []` (bytes NOT in heap.bytes, so HeapCorr's zero premise is untouched;
  no Exec rule changes them). New Exec rules only: `static target offset` (target := ofNat(staticBase+offset)) and
  `loadByteStatic` (staticBase ≤ a < staticBase+len → target := statics[a-staticBase]). Existing load rules unchanged.
- compiler.lani: Stmt::Static(target, offset); Instr::Static(offset) = lea rax,[r8+disp32] = [73,141,128]++le32 (7 bytes), then Store.
  Binary gets statics (image = code ++ statics); Program gets statics: List<u8>; linkProgram/modules: statics []; Static encodes
  position-independently so link_eq needs no rejection. within: locals > target && 2^31 > offset.
  Every Stmt match arm: mirror Frame (agree fns false, static_agrees new, facts_after kill_shared, ignores true, kills false).
- Abstract machine: Instr Static step; LoadAt static step. Simulation: Rel/HeapAt/Fits gain r8 = staticBase, static bytes at
  heapBase+staticBase+i in entry memory, apart from heap/window, top ≤ staticBase, staticBase+len ≤ 2^64. HeapAt/Contract trusted: TRUSTED_BASE.

## 11-02 point 6 stage (a) DONE: commit 276bd837b (f6v)
- Design as built: r8 = x86 ADDRESS of statics (startup `mov r8, imm64` = elfBase+215+linkedSize codes);
  Instr.static = lea rax,[r8+off]; sub rax,r12 (10 bytes). Heap.staticBase/statics; Exec.loadByteStatic needs
  heap.top <= staticBase. Step.call premises after.staticBase/statics = caller's (Exec.statics in CompileCorrect).
  Rel.static/Rel.statics (Frame.StaticByte base bytes k); HeapAt.static/statics; elfHeap binary ... with
  elfStaticBase (wrapped 2^64 + S - elfTop); compileSource_layout; startup 9 steps.
- Trusted hash 64acd215bab52adb (4675). ixTimes now 106 (Budget.lean, SelfAgree.lean hard-code it).
- Gate exes (runAll, x86ModelTest, srcDump, extract, floatTest) must be rebuilt by hand: lake build them.
- fn_difftest: View lengths and `length` params kept short (lower_view 678303 hung the gate).
- Next: stage (b) str in the verified compiler (SrcType.str, literal let, string_data_ptr copy loop, Corr.str,
  lowering must emit Program.statics; top <= staticBase must become a Corr invariant).
- 11-02 coordinator: 276bd837b merged+pushed. Stale-exe claim was WRONG (gate builds exes; lake cache restores old
  mtimes; my rebuilt x86ModelTest digest equalled the gate's). Told coordinator.
- Stage (b) scoping: stdlib pattern = `let text: str = "..."; return core::mem::typed_slice_from_raw_parts(
  core::mem::string_data_ptr(text), N);` (unicode_*_data, 9 files) -> needs (1) a combined LetStr form like LetView
  (str local used only by string_data_ptr; Core mapStringDataPtr = mapBorrowed (stringStorage v) 4, bytes padded
  to 4), (2) `core::mem::typed_slice_from_raw_parts` path (front end reads only bare `slice_from_raw_parts`; Core
  typedSliceFromRawParts -> mapRawNominalSlice, check it equals the bare form for u8), (3) [u8] raw-slice return
  (return_slice exists). resolver_config/cli pass str PARAMETERS (out of scope for now).
  LetView touched 49 Lean files; ViewLower.lean 710 lines is the model for the lowering proof.
## 11-02 point 6 stage (b) DONE: commit 7435a9dac (f6v)
- SrcStmt.LetStr(pointer, chars: List<usize>, body) = Core `let pointer: rawPtr = string_data_ptr("chars")` (no str local,
  no SrcType.str). lower_str: Alloc(next,2,4*words) + str_stores (constant M32 word stores), ASCII nonempty < 2^31 only.
  Proof Mini/StrLower.lean (str_entered, stmt_letStr, stops_letStr), Grows.strPtr_run/strPtr_grows, Guard.letStr_lower_inv.
  u32 chars failed `faithful` (BitVec `<` + && in str_ascii) -> switched to usize.
- New P part strStores split storeArray: added `import all/public import ...P.strStores` beside storeArray in hand-written
  files; faithful_pure.py SelfNeeds import list gained 'strStores'.
- frontend_difftest.py Lean template: letStr arms (serStmt, bindersOf, renStmt).
- trusted a2b318bf5c30f9cb (4678). Quick gate 24/24.
- Next: stage (c) front end: `let text: str = "lit"; return core::mem::typed_slice_from_raw_parts[<u8>](core::mem::string_data_ptr(text), N);`
  -> LetStr(p, chars, LetSlice(r, u8, local p, N, Return(local r))); also `let p = core::mem::string_data_ptr("lit")`.
  Then oracle after (before: 27 testable, 11 compiled, 16 unread, 75 agree, 0 disagree).
## 11-02 point 6 stage (c) DONE: commits 00edbf652 (code) + 79e4c22fe (docs) (f6v)
- frontend.lani "string literals" section: is_str_let (one test keeps let_first small: an inline 6-conjunct
  condition pushed Gen/SelfProofF_litIf past 285 s), string_let/string_return/... -> MLetStr(x, chars,
  MLetSlice(r, u8, Local x, n, MReturn(Local r))). string_byte is `extract: inline` (mutual pub fns split
  across parts break the build); callees must precede callers in the .lani (Lean def order).
- Lean: Reading/Stmts.lean StrType/StringInit/StringLiteral/PlainStringByte/TreeNames/DataPtrOf/TypedSlicePath/
  StringReturnR + StmtsR.letStr; Det/Stmts.lean *_noString lemmas + letStr cases; Close.lean StmtClosed.letStr.
- New Frontend P parts (stringLast took allocLet..ifOrEval from i32ArrayLength): import all ...P.stringLast etc.
- trusted 85851955686d2177 (4701). Quick gate 24/24; frontend-cases 115.
- Oracle after (oracle-str-after.txt): compiled 11->18, unread 16->9, agree 75->157, 30 native traps checked, 0 disagree.
- Next (not asked yet): str parameters (std::cli, resolver_config, test::check).
## 11-02 merge origin/lang DONE: c9c4bc250 (f6v)
- Gen/term/GenB/HB/GenP P00-13 regenerated; text_typed_slice_from_raw_parts = "typed_" ++ text_slice_from_raw_parts
  (26-literal cost lemma timed out in GenP P11), typed_slice_spellings -> Bool is_typed_slice_segments (omega failed).
  trusted 8e49c84069f2b7bf (4700); whole library builds; quick gate 24/24.
- Traps (f6v/traps/: so_traps.py records signals, trapcause.py replays the index arithmetic): all 30 (and 28 of a
  4-module rerun) are table index out of range in unicode_table::hex: native SIGFPE (failed check = 1/0),
  laniusc exit 101 (bounds). Causes: negative or huge offset/index args, start+width past the 50-byte turkic table or a
  chunk's end, packed(value > 0x10FFFF) -> first(block) past the last 2118-byte chunk.
- Next chosen: str parameters (std::cli, resolver_config, test::check).
## 11-03 str parameters: before numbers, paused for coordinator
- Oracle before (oracle-strp-before.txt): std::cli, resolver_config, test::check: 12 targets, 0 testable
  (Outcome 6, Command, View<u8>, Result x2, Family, Label). Wider run over the 14 str modules
  (oracle-strp-wide-before.txt): 216 targets, 121 testable, 119 compiled, 2 unread (test::bench::report,
  test::suite::arguments: both also need extern write_text / process externs, + i32_array_data_ptr), 336 agree.
  52 untestable "type str" targets are all std::file*/std::io (path: str to host externs, F8).
  => str parameters change no oracle number until F8 externs take str. Asked coordinator.
- Commit: oracle empty-manifest fix (stdlib_oracle.py).
## 11-03 coordinator: option 2 = F8 host externs with str/pointer args (write_text, write_byte, then files,
## then str params, then command_raw syscall6). Record extern contracts in TRUSTED_BASE + SEMANTIC_DECISIONS,
## oracle stdout/stderr + file effects, before/after numbers per piece.
- Findings: write_byte (std::io, handle 1/2) is already host id 2^32. write_text(handle, text: str) needs str
  VALUES (every caller passes a str param: io::write_line/println, test::suite/bench text, file::write_text_once),
  so piece 1 = str values + write_text (+ write_newline, cheap). File externs: open_*_path(path: str), read/write/
  close(handle, ptr, len), open_read/write/append(ptr, len). Core specs exist (World.lean callSimple/call).
- Plan piece 1 (str values):
  S1 compiler.lani: SrcType::Str (2 slots: static mini address, length), SrcExpr::Str(offset, chars) lowered to
     Static(t, offset) + Const(t+1, len); SrcProgram.statics bytes checked by the compiler (extract = chars).
     HoldsAt/FieldsHold/Corr gain a Statics param sx = (heap.staticBase, statics) (content truth in HoldsAt.str).
  S2 front end: str params, str literal args, offsets placed by a front-end pass (compiler re-checks).
  S3 mini Syscall.write may read the static region; x86 proof via Rel.statics.
  S4 host write_text (id 2^32+8): handle 1/2 chunked Sys write, returns 0; else -1. write_newline too.
  S5 oracle: str params take a literal index (wrapper if-chain of calls over a fixed literal set).
- before (prog-text-before.txt): programs_oracle --match println|write_text|eprintln|write_line --sample 40 seed 1: 40 of 149, 4 no parse, 0 compiled; gaps: 16 str, 11 refs, 4 arrays. Commit tool fixes 9dfc57a1f.
## 11-03 piece 1 stage S1 (str values) IN PROGRESS (not committed)
- STAGED: write_text/write_newline branches REMOVED from eval_host again (lani + P hostRandomCode.lean hand-edited);
  host_text_code/host_newline_code stay defined (unused). hostService? +8/+9 and hostFuncs stay (Grows/TypeSound/ShapeHost done).
  So S1 = SrcType.str + EStr literal + sx threading; S3/S4 (Syscall.write from statics, host write_text) next commit.
- eval_str also checks offset+len <= statics.length (lani + P wordStride.lean hand-edited, doc comment too).
- Design: Heap.StaticsAt gains `fits : staticBase + statics.length < 2^64`. class StaticsOf sp sx (sx.bytes = sp.decls.statics)
  is an instance binder in StmtSound/EvalSound/EffStops/SrcStops (`intro bud sx _ places ...`), `variable [StaticsOf sp sx]`
  in Statements/Cases/Calls sections, f6v/bin/addinst.py adds it to theorem headers. Top theorems take
  (statics : heap.StaticsAt sx) (ofSp : sx.bytes = sp.decls.statics); process theorems use elfStatics binary stack
  (elfHeap_statics, compileSource_statics, compileOptimized_statics). ClosedProgram gains p.statics = [].
- LaniusMini + Lanius build (11-03). Next: exes, Gen/term/GenB/HB/GenP regen, TRUSTED_BASE (statements + hash), gate.
## 11-03 piece 1 stage S1 DONE: commit 2d085d510 (f6v)
- Faithful cascade: addalt.py/addstr.py (f6v/bin) add eStr/str alternatives next to eLen/view arms; Grows (DeclStep)
  keeps statics; declsSame compares statics; faithful_certs/faithful_pure emit statics (SelfProg prog, decls, decls_start);
  term_gen.lean, frontend_difftest.py, oracle_difftest.py, trap_test.py templates updated.
- static_byte_is compares `((b as i32) as u32) as u64 == c as u64` (u8 var compare left faithful stuck; extract subset
  compares no i32). Lani comments become P doc comments: editing one after extraction makes `extract` stale.
- Type ids shifted: SelfFaithful RepList 37 RepRule; ixTimes 105 (Budget.lean, SelfAgree.lean). SafeDriver needs
  `import all ...P.SrcType_same`. SelfCompiler: selfHeap_statics, self_statics.
- trusted 9c1a21481238db7d (4741). Quick gate 24/24.
- Next: S3 (mini Syscall.write reads static region), S4 (eval_host write_text/newline + proofs), S2 front end, S5 oracle.
- 11-03 coordinator: 2d085d510 merged+pushed. Fast-forwarded f6v to origin/lang 9b76a2495 (open-statement graph:
  formal/OPEN_STATEMENTS.md, gate step `open`, Lanius/Open/F14/* import GenB SelfBModel5, SelfPre/HB, SelfBounded,
  Frontend P parts). NEVER edit a Stmt.lean on lang: if my changes break one, tell coordinator (owner writes V2).
  leafA designs F5 (&mut, memory model) on my str/F8 representation decisions: keep SEMANTIC_DECISIONS current.
## 11-03 S3+S4 IN PROGRESS (uncommitted)
- S3 done: Heap.span (write reads static region), run_write/run_write_static, hostText_exec (WorldTrace), bytesAt_span (Simulation).
- S4: eval_host branches 2^32+8 writeText [i32,str], +9 writeNewline [i32]; Grows *_returns; LowerEval eval_host_text;
  TypeSound + EvalStops eff_call 5-way shape. LaniusMini builds. Next: Lanius lib, exes, regen Gen x2/term/GenB/HB/GenP, trusted, gate.
## 11-03 S3+S4 DONE: commit c7212ef22 (f6v), not pushed
- eval_host falls back to eval_host_text (10-arm chain overflowed budget simp); new P part evalHost.lean (evalHost, evalCall);
  `import all ...P.evalHost` added next to hostRandomCode imports; simp lists [evalHost, evalHostText].
- GenP: lang tracks only SelfP00-06 (pre_certs makes 8; P07 in progress elsewhere) -> copy 00-06 only, never add P07.
- trusted 515b4e769e2308d2 (4742: Heap.span new, Syscall.run). Quick gate 25/25 incl. open.
- ALWAYS `git status --short --untracked-files=all formal | grep ??` before commit (new Gen files!).
- Next: S2 (front end reads str params / str literal args, places statics), S5 oracle (before: prog-text-before.txt).
## 11-03 S2 design (front end: str params + str literal args), started after c7212ef22
- Ty gains TyStr (prim `str`: primitive("str") = Str, src_ty Str -> TyStr, scalar_src TyStr -> Str). WellNamed then
  forbids user types named str (fine).
- MEff gains XStr(chars): read ONLY as a call argument (EffArgs.str : StringInit c chars -> BindArg .. (xStr chars) ..),
  never by EffR, so letInitR_noString / LetStr determinism stay as they are (literal has no EffR reading).
- Close: xStr chars -> SrcEff.eStr 0 chars. Placement: untyped_rejected returns place_program(fs) (new lani pass
  over SrcStmt/SrcEff assigning offsets = statics length so far, statics ++ bytes). Reading's ClosedProgram:
  p = placeProgram gs (P fn, trusted; meaning-neutral since toCore ignores offsets/statics).
- host_id: write_text -> 2^32+8, write_newline -> 2^32+9 (Reading/Funcs uses P hostId directly).
- Watch: Open statements import Frontend P parts wideLeftStmt, readCountedBytes, grammarPart13 (names must not
  change); PostFrontEndWords Proof uses post_build_files (GenP). Don't touch build_files/front_end_words bodies.
## 11-03 S2 DONE: commit 087d4c75c (f6v), not pushed
- placement pass threads `before: List<u8>` (offset = length(before), concat): a Nat `base` made GenP pre_step_place_* fail (no bound on base).
- PostFrontEndWords/Proof.lean now imports GenP SelfP00-06 (post_build_files moved P02 -> P03). SrcDump tyName .tyStr.
- trusted 5be562f6ab9cc7a1 (4777). gate 25/25. frontend cases 120.
- Next: S5 oracle before/after (before: prog-text-before.txt).
## 11-03 S5 DONE (commit after 087d4c75c): oracle str args (STR_TEXTS selector, oracle_str_call), runAll ' statics [..]',
  stub sets r8. strp-wide: testable 121->124, agree 336->384, 0->435 bytes stdout/stderr alike, 0 disagree.
  programs_oracle (prog-text-after.txt): str gap 16->8 (escapes, non-ASCII, literals in struct/array/let), compiled 0 (refs, arrays, externs).
- Next: file externs (std::fs/std::file str paths now excluded by oracle 'type str'), then str broader, syscall6.
## 11-03 merges: 9396100dc (lang eb14cd171), 159671a0f (lang 11239b11e). Trusted d4b28d95eed2bc3b (4810). Gate 25/25.
- merge recipe: resolve frontend.lani/TRUSTED_BASE by hand; checkout --theirs generated; lb extract first (stale P part:
  hand-patch arms), extract frontend then compiler; LaniusMini; regen Gen x3, term, GenB, hb_gen (plain/--sum/--slots),
  pre_certs.py GenB Lanius/Faithful/SelfPre/GenP build_files (in place: module names follow OUTDIR); build; trusted; gate.
- GenPC (compile side, orphan) left as lang's. lang moved to e51443e05 after (leafB/F14, hb_gen --nums): not merged.
## 11-03 piece 2 (files) PLAN: SEMANTIC_DECISIONS str point (8). laniusc file externs = raw syscalls (runtime_path_ops.s,
  runtime_abi.slang: close=sys3, read=sys0, write=sys1, open 2 with 0/0x241/0x441 mode 0666). Core becomes kernel-faithful:
  one fd table (0,1,2 std), lowest free fd, -errno (-2,-9,-20,-21; path copy -36,-22,-14), simple relative paths only.
  Stages: (a) Core World.lean + proofs (HeapCorr.closed -> only std streams), (b) mini syscalls + x86 Linux model,
  (c) oracle sandbox (fresh dir + seed files per call, compare trees, single-call mode like stdin), (d) .lani lowering
  (tell coordinator BEFORE merging; queue: leafA limits, leafC F5 S3 first).
  before (oracle-file-before.txt): 9 file modules, 176 targets, 71 testable/compiled, 276 agree, 105 untestable (str 32, Path 23, &File 17, extern 14).
## 11-03 files stage (a) DONE: bfc3e1e3d (f6v, not pushed), trusted 374c7c482d5ab210 (4824), gate 25/25.
- World.lean kernel-faithful openFile/read/write/close; HostCall read lemmas take 3<=handle, count<=transferLimit.
- Known gaps for later: write_text/writeI32/writeByte/writeNewline to a file fd still return -1 on bad fd (laniusc: write loop);
  remove_file/rename with open descriptors (make unavailable); read_i32.
- Next: stage (b) mini syscalls open/read/close + file system in mini io + x86 Linux model; (c) oracle sandbox; (d) .lani.
- Merges: use formal/tools/regen.py --resolve (lang 640385095), see formal/tools/README.md.
- 11-03 merge e9b7d159b (lang 5f7f1dcd4, leafA limits): trusted 6db99dcc5c70f4dc, gate 25/25. Next: (b), (c); tell coordinator before (d) (.lani; queue: leafC S3, leafA frame_block).
- 11-03 branch f6v-b from origin/lang 6163ae1f2 for stage (b); report each commit after quick gate (no .lani). New F5/F8 proof files need module header (OPEN_STATEMENTS.md). (d) queued after leafC S5b+S6b.
## 11-04 stage (b) IN PROGRESS on f6v-b (uncommitted): new Lanius/Files.lean (System, openPath/readBytes/writeBytes/closeHandle,
  read/write/close results -9, openFlags/openWith); World.State.fs replaces files/directories/fileHandles; Io.files +
  Io.readFile/writeFile/closeFile/openFile, descriptor (low 32 bits); Kernel readFile/writeFile/openFile(cString)/close;
  mini Syscall.run read/write fd>=3 branches; Simulation storing_simulates/sending_simulates; Kernel.agree rewritten;
  StepDet/Process arms. HeapCorr.closed = w.fs.handles = []. Docs written (TB section 8 bullet, SD point 8 stage b).
  open/close mini constructors need compiler.lani -> go with (d). LaniusMini builds; Lanius/LaniusOpen building (Faithful rebuild).
  Remaining: build, TB last-change entry + regen trusted hash, quick gate, commit, report.
- 11-04 stage (b) COMMITTED 787491a3b on f6v-b (from lang 6163ae1f2), trusted a8dc55cc48e2ea01 (4930), quick gate 26/26. Reported. Next: stage (c) oracle sandbox.
- 11-04 merge 5fe661e3e (lang 55ca5a914) trusted b06f70b8860a4fde gate 26/26. Disk-full at 02:14 left a 0-byte cached artifact 21c42906adea99f5 (removed). Next: stage (c).
- 11-04 merge of local lang 07bb5c4a3 into f6v-b IN PROGRESS (uncommitted, MERGE_HEAD set): TRUSTED_BASE resolved (both entries,
  merge entry hash MERGEHASH000000), regen --resolve 0 files. Build stopped by the 5-min total rule: 7 passes of 288 s
  (~34 min), last at 2307/2415 jobs. Rebuilding: all of Faithful/Gen (Self*C/F, SelfTerm*, SelfOk*, SelfLiveOk*),
  Faithful/GenB (SelfBModel*, SelfBProof*), then GenP and Open/F5, Open/F14, because Lanius.World imports Lanius.Files
  and nearly everything imports World. Remaining after build: regen --only trusted --trusted, fill hash, quick gate, commit.
- 11-04 05:14 redid the merge against local lang 7985ec7e1 (aborted the 07bb5c4a3 one; one merge commit): TRUSTED_BASE resolved
  (MERGEHASH000000 placeholder), lv regen --resolve 0 files. Two lv build passes allowed and used (216 + 247 jobs, 0 errors);
  stopped. Left: rest of the Faithful GenB build, then GenP/Open; then lv regen --only trusted --trusted, fill hash, lv gate, commit.
- 11-04 merge COMMITTED a7946754b (lang 7985ec7e1), trusted a3928fc9730d146a, gate 26/26. Next: stage (c).

## 11-04 ~05:57 Files/World split (branch f6v-split from local lang 663115dab, uncommitted)
- New Files/Model.lean, World/Model.lean (exposed types), World/Files.lean (non-exposed services, import all Files);
  Files.lean + Io's file calls non-exposed; call's remove_file/create_dir/remove_dir/rename via removeFilePath etc.
- Test (fresh openPath body edit, reverted): rebuilt Files, World.Files + 30 non-module Semantics files, 210 jobs 58 s;
  World/Semantics/Mini/X86 cut off. The earlier "106 modules" was staleness from a prior World change, not the edit.
- Whole library: 2200 files downstream of World, 1301 non-module (748 GenB, 100 Open.F5, 48 F14, 44 Lexer) - those always rebuild.
- TRUSTED_BASE (HASHTODO placeholder in the last-change entry) and SEMANTIC_DECISIONS point 8 updated.
- Remaining: full lv build (pass 1 stopped at 284 s, 170 jobs, waiting on lean slots) -> needs coordinator allowance;
  then regen --only trusted --trusted, fill HASHTODO, gate, commit (ff of local lang).
- 11-04 17:14: f6v-split fast-forwarded to local lang b05dd7020 (no overlap), split edits uncommitted on top.
  Build passes 1-4 used (4 allowed): last stopped at [1901/1936], 0 errors; leftover mostly Faithful.Gen/GenB + Lanius root,
  much time spent waiting for lean slots. Next: one more pass (needs allowance) -> regen --only trusted --trusted -> HASHTODO -> gate -> commit.
  Coordinator: cutting to 2 agents (usage 80%); stage (c) waits until after the Saturday reset.
- 11-04 17:20: merged local lang 52118889e (fast-forward), final allowed pass stopped at [2125/2311], 0 errors.
  Committed WIP 5fb94397a on f6v-split (parent 52118889e, "not fully built"). Still to do: finish build,
  regen --only trusted --trusted, replace HASHTODO in TRUSTED_BASE, gate, then a final commit. Stopped per coordinator.
  Stage (c) waits until after the Saturday reset.
