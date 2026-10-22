import Lanius.Std.VecInsert

/-! # `reverse`

`reverse` swaps `items[low]` and `items[high]` through a local `held` while
`low < high`. The loop state carries the counters `low` and `high` (locals 2
and 3, both assigned) and the fresh cell of each iteration's `held`, so the
invariant describes the state by its locals, not by its shape. -/

namespace Lanius.Std

open Lanius Lanius.Core Lanius.Semantics Lanius.Memory

variable {P : Program} {T : Ty} {ids : VecIds} {size : Nat}

/-! ## Helpers -/

private theorem replaceCell_append'' (cs ds : List Cell) (id : CellId) (w : Value) :
    replaceCell (cs ++ ds) id w = replaceCell cs id w ++ replaceCell ds id w := by
  induction cs with
  | nil => rfl
  | cons c rest ih =>
      simp only [List.cons_append, replaceCell]
      split <;> rw [ih] <;> rfl

private theorem replaceCell_absent'' (cs : List Cell) (id : CellId) (w : Value)
    (absent : ∀ cell ∈ cs, cell.id ≠ id) : replaceCell cs id w = cs := by
  induction cs with
  | nil => rfl
  | cons c rest ih =>
      have head : (c.id == id) = false := by simpa using absent c (by simp)
      simp only [replaceCell, head]
      rw [ih (fun cell member => absent cell (by simp [member]))]
      rfl

/-- Assigning a cell created after `base` keeps the frame. -/
theorem FreshCellFrame.assignFresh {base s s' : State} (formedBase : base.CellsWellFormed)
    (formed : s.CellsWellFormed) (frame : FreshCellFrame base s) {c : CellId} {w : Value}
    (fresh : base.nextCell ≤ c) (assigned : s.assignCell c w = some s') :
    FreshCellFrame base s' ∧ s'.locals = s.locals ∧ s'.heap = s.heap ∧
      s'.world = s.world ∧ s'.i32ArrayViews = s.i32ArrayViews := by
  rw [assignCell_state assigned]
  obtain ⟨extra, cells, frontier, freshCells⟩ := frame
  have absent : ∀ cell ∈ base.cells, cell.id ≠ c := fun cell member => by
    have lt : cell.id < base.nextCell := formedBase cell member
    exact Nat.ne_of_lt (Nat.lt_of_lt_of_le lt fresh)
  refine ⟨⟨replaceCell extra c w, ?_, frontier, ?_⟩, rfl, rfl, rfl, rfl⟩
  · show replaceCell s.cells c w = _
    rw [cells, replaceCell_append'', replaceCell_absent'' _ _ _ absent]
  · intro cell member
    obtain ⟨old, oldMember, same⟩ := mem_replaceCell member
    rw [← same]; exact freshCells old oldMember

theorem cellId_of_local {s : State} {id : VarId} {v : Value} (found : s.local? id = some v) :
    ∃ c, s.cellId? id = some c := by
  cases h : s.cellId? id with
  | none => simp [State.local?, h] at found
  | some c => exact ⟨c, rfl⟩

theorem decrement_run (target : P.target = Target.x86_64) {st after : State} {idx : VarId} {cell : CellId}
    {v v' : Int} (lo : -2147483648 ≤ v - 1) (hi : v - 1 < 2147483648) (eq : v - 1 = v')
    (cellFound : st.cellId? idx = some cell) (found : st.local? idx = some (.signed .i32 v))
    (assigned : st.assignLocal idx (.signed .i32 v') = some after) :
    RunsStmt P st (decrement idx) .next after := by
  obtain ⟨threshold, diff, locals⟩ := RunsExpr.binary (program := P) (operation := .subtract) (RunsExpr.local' found)
    (RunsExpr.value' (.signed .i32 1)) (by decide) (by rw [target, eval_i32_sub lo hi, eq])
  refine RunsStmt.expression (RunsExpr.ofStable (Lanius.Extraction.CertificateEmitterFrame.StableExpr.assignSetLocal
    P st idx cell _ _ _ st after cellFound found diff rfl assigned rfl rfl) ?_)
  exact (assignLocal_preserves_frame (protectedId := idx) assigned).1

/-! ## The template -/

/-- The swap loop of `reverse`, with `value`, `items`, `low`, `high` and
`held` the locals 0 to 4. -/
def reverseLoop (T : Ty) : Stmt :=
  .whileLoop (.binary .less (.local 2) (.local 3))
    (.letLocal 4 T (.index (.local 1) (.local 2))
      (.sequence (.expression (.assign .set (.index (.local 1) (.local 2)) (.index (.local 1) (.local 3))))
      (.sequence (.expression (.assign .set (.index (.local 1) (.local 3)) (.local 4)))
      (.sequence (increment 2) (decrement 3)))))

/-- `pub fn reverse<T>(value: Vec<T>) -> Vec<T>` -/
def reverseFn (ids : VecIds) (T : Ty) (f : FunctionId) : Function where
  id := f
  parameters := [(0, vecTy ids)]
  returnType := vecTy ids
  body := some <|
    .letLocal 1 (.slice T) (.call ids.slots [.local 0])
    (.letLocal 2 i32Ty (int 0)
    (.letLocal 3 i32Ty (.binary .subtract (.field (.local 0) 1) (int 1))
    (.sequence (reverseLoop T) (.returnValue (some (.local 0))))))

/-- Which element slot `j` of `n` holds after `k` swaps. -/
def revFrom (n k j : Nat) : Nat := if j < k ∨ n - k ≤ j then n - 1 - j else j

/-! ## The spec -/

/-- `reverse(v)` returns `v`, which then represents `xs.reverse`; only its
storage changed. -/
theorem reverse_spec (inst : VecInstance P T ids) (kind : ElemKind P T size)
    {f : FunctionId} (found : P.function? f = some (reverseFn ids T f))
    {caller : State} (formed : caller.CellsWellFormed) {xs : List Value} {p cap : Nat}
    (rep : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]) xs)
    (stores : ∀ y ∈ xs, ElemStore P T size y)
    (noViews : caller.i32ArrayViews = []) (unique : HeapBlockBasesUnique caller.heap) :
    ∃ after, RunsExpr P caller (.call f
        ([Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]].map Expr.value))
      (.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]) after ∧
      FreshCellFrame caller after ∧ after.world = caller.world ∧
      after.i32ArrayViews = caller.i32ArrayViews ∧
      VecRep P T size ids.vec after.heap
        (.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]) xs.reverse ∧
      HeapRegionWrite caller.heap after.heap p (size * cap) := by
  have target := inst.target
  obtain ⟨_, lenLe, capBound, buffer, reads⟩ := rep.fields
  obtain ⟨n, hn⟩ : ∃ n, xs.length = n := ⟨_, rfl⟩
  let vv := Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]
  refine Grow.call (vs := [vv]) (Q := fun H => VecRep P T size ids.vec H vv xs.reverse ∧
    HeapRegionWrite caller.heap H p (size * cap)) found rfl rfl ?_
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  let E := E0.bindLocal 0 vv
  change Grow P E _ _ _
  have fE : E.CellsWellFormed := f0.bindLocal _ _
  have l0 : E.local? 0 = some vv := local_bound f0 0 _
  obtain ⟨S1, slots, frame⟩ := slots_call inst kind fE l0 capBound buffer
  have fS1 := frame.afterFormed
  let view := Value.rawSlice T (viewAddr T size p cap) cap
  let B0 := S1.bindLocal 1 view
  have fB0 : B0.CellsWellFormed := fS1.bindLocal _ _
  have hB0 : B0.heap = caller.heap := frame.heap
  have b0_0 : B0.local? 0 = some vv := local_kept fS1 _ (by decide) (frame.localFound l0)
  have b0_1 : B0.local? 1 = some view := local_bound fS1 1 _
  obtain ⟨c0, b0c0⟩ := cellId_of_local b0_0
  obtain ⟨c1, b0c1⟩ := cellId_of_local b0_1
  have c0Lt : c0 < B0.nextCell := fB0.localCellBound b0c0 b0_0
  have c1Lt : c1 < B0.nextCell := fB0.localCellBound b0c1 b0_1
  let c2 := B0.nextCell
  let c3 := B0.nextCell + 1
  have c32 : c3 ≠ c2 := Nat.succ_ne_self _
  have c30 : c3 ≠ c0 := Nat.ne_of_gt (Nat.lt_succ_of_lt c0Lt)
  have c31 : c3 ≠ c1 := Nat.ne_of_gt (Nat.lt_succ_of_lt c1Lt)
  have c23 : c2 ≠ c3 := fun e => c32 e.symm
  have c20 : c2 ≠ c0 := Nat.ne_of_gt c0Lt
  have c21 : c2 ≠ c1 := Nat.ne_of_gt c1Lt
  let B2 := B0.bindLocal 2 (.signed .i32 0)
  have fB2 : B2.CellsWellFormed := fB0.bindLocal _ _
  have b2_0 : B2.local? 0 = some vv := local_kept fB0 _ (by decide) b0_0
  have subRun := RunsExpr.binary (operation := .subtract) (RunsExpr.field' (j := 1) (RunsExpr.local' b2_0) rfl)
    (RunsExpr.value' (P := P) (S := B2) (.signed .i32 1)) (by decide)
    (by rw [target]; exact eval_i32_sub (by omega) (by omega))
  let B3 := B2.bindLocal 3 (.signed .i32 ((xs.length : Int) - 1))
  let L := B3.locals
  have hL : L = (3, c3) :: (2, c2) :: B0.locals := rfl
  have cid : ∀ s : State, s.locals = L → s.cellId? 0 = some c0 ∧ s.cellId? 1 = some c1 ∧
      s.cellId? 2 = some c2 ∧ s.cellId? 3 = some c3 := by
    intro s hs
    have e0 : s.cellId? 0 = B0.cellId? 0 := by simp [State.cellId?, hs, hL]
    have e1 : s.cellId? 1 = B0.cellId? 1 := by simp [State.cellId?, hs, hL]
    refine ⟨e0.trans b0c0, e1.trans b0c1, by simp [State.cellId?, hs, hL], by simp [State.cellId?, hs, hL]⟩
  -- the loop invariant
  let Inv : Nat → State → Prop := fun k s => ∃ h, s.locals = L ∧ s.heap = h ∧ s.i32ArrayViews = [] ∧
    s.world = caller.world ∧ FreshCellFrame B0 s ∧ s.local? 0 = some vv ∧ s.local? 1 = some view ∧
    s.local? 2 = some (.signed .i32 (k : Int)) ∧ s.local? 3 = some (.signed .i32 ((n : Int) - 1 - k)) ∧
    HeapRegionWrite caller.heap h p (size * cap) ∧
    ∀ j, j < n → ∀ other : State, ReadsWithin h other.heap (slotLo T size p cap j) size →
      readRawSliceIndex P other T (viewAddr T size p cap) cap j = .ok (xs.getD (revFrom n k j) .unit)
  have condAt : ∀ k s, s.local? 2 = some (.signed .i32 (k : Int)) →
      s.local? 3 = some (.signed .i32 ((n : Int) - 1 - k)) →
      RunsExpr P s (.binary .less (.local 2) (.local 3)) (.boolean (decide ((k : Int) < (n : Int) - 1 - k))) s :=
    fun k s a b => RunsExpr.binary (RunsExpr.local' a) (RunsExpr.local' b) (by decide) (eval_i32_lt _ _ _)
  let measure : State → Nat := fun s => n - counter 2 s
  let body : Stmt := .letLocal 4 T (.index (.local 1) (.local 2))
      (.sequence (.expression (.assign .set (.index (.local 1) (.local 2)) (.index (.local 1) (.local 3))))
      (.sequence (.expression (.assign .set (.index (.local 1) (.local 3)) (.local 4)))
      (.sequence (increment 2) (decrement 3))))
  let spec : CountdownWhileSpec measure P (.binary .less (.local 2) (.local 3)) body (n / 2) := {
    Inv := Inv
    Done := fun completion s => completion = .next ∧ Inv (n / 2) s
    terminal := by
      intro s invariant
      obtain ⟨h, _, _, _, _, _, _, _, s2, s3, _⟩ := id invariant
      have run := condAt _ s s2 s3
      rw [show decide (((n / 2 : Nat) : Int) < (n : Int) - 1 - ((n / 2 : Nat) : Int)) = false by simp; omega] at run
      obtain ⟨threshold, stable, _⟩ := run
      exact ⟨threshold, _, stable, rfl, invariant⟩
    step := by
      intro k s kLt invariant
      obtain ⟨h, sL, sH, sV, sW, sF, s_0, s_1, s_2, s_3, effect, done⟩ := invariant
      have fs : s.CellsWellFormed := FreshCellFrame.after_cellsWellFormed fB0 sF
      obtain ⟨sc0, sc1, sc2, sc3⟩ := cid s sL
      obtain ⟨hi, hiDef⟩ : ∃ hi, hi = n - 1 - k := ⟨_, rfl⟩
      have loHi : k < hi := by omega
      have hiN : hi < n := by omega
      have hiCap : hi < cap := by omega
      have loCap : k < cap := by omega
      have run := condAt k s s_2 s_3
      rw [show decide ((k : Int) < (n : Int) - 1 - k) = true by simp; omega] at run
      obtain ⟨condThreshold, condStable, _⟩ := run
      have hiEq : (n : Int) - 1 - k = Int.ofNat hi := by simp only [Int.ofNat_eq_natCast]; omega
      have s_3' : s.local? 3 = some (.signed .i32 (Int.ofNat hi)) := by rw [← hiEq]; exact s_3
      have s_2' : s.local? 2 = some (.signed .i32 (Int.ofNat k)) := s_2
      have readAt : ∀ j (jN : j < xs.length), revFrom n k j = j → readRawSliceIndex P s T (viewAddr T size p cap) cap j =
          .ok (xs[j]'jN) := fun j jN same => by
        have r := done j (by omega) s (by rw [sH]; exact ReadsWithin.refl _ _ _)
        rw [same, getD_of_lt jN] at r; exact r
      have loRead := readAt k (by omega) (by simp [revFrom]; omega)
      have hiRead := readAt hi (by omega) (by simp [revFrom]; omega)
      -- let held = items[low]
      let a := xs[k]'(by omega)
      let s1 := s.bindLocal 4 a
      have fs1 : s1.CellsWellFormed := fs.bindLocal _ _
      have s1_1 : s1.local? 1 = some view := local_kept fs _ (by decide) s_1
      have s1_2 : s1.local? 2 = some (.signed .i32 (Int.ofNat k)) := local_kept fs _ (by decide) s_2'
      have s1_3 : s1.local? 3 = some (.signed .i32 (Int.ofNat hi)) := local_kept fs _ (by decide) s_3'
      have s1_4 : s1.local? 4 = some a := local_bound fs 4 _
      have heldRun : RunsExpr P s (.index (.local 1) (.local 2)) a s := RunsExpr.rawIndex s_1 s_2' loRead
      -- items[low] = items[high]
      have readable : ∀ (hh : Heap) (j : Nat), j < cap → HeapRegionWrite caller.heap hh p (size * cap) →
          hh.Readable (slotOf T size (elemBase T size p cap j)) size := fun hh j jc write => by
        rw [slotOf_elemBase kind.size_eight]
        have within := slot_inside (T := T) (size := size) (p := p) jc
        unfold slotLo at within ⊢
        exact ((buffer (by omega)).afterWrite write).2.1.subrange (start := size * slotIndex T cap j) (by omega)
      have roomAt : ∀ j, size ≤ elemBase T size p cap j + 8 := fun j => by
        unfold elemBase
        by_cases scalar : T = i32Ty
        · rw [if_pos scalar, kind.i32_size scalar]; omega
        · rw [if_neg scalar]; have := kind.size_eight scalar; omega
      have slotEq : ∀ j, slotOf T size (elemBase T size p cap j) = slotLo T size p cap j :=
        fun j => slotOf_elemBase kind.size_eight
      obtain ⟨h1, stored1, readBack1, written1⟩ := stores (xs[hi]'(by omega)) (List.getElem_mem _) s1 h
        (elemBase T size p cap k) (roomAt k) (readable h k loCap effect) effect.unique
      rw [slotEq] at written1
      have assign1 := StableExpr.assignRaw (before := s1) (indexed := s1) (ready := s1) (heap := h1)
        (sourceId := 1) s1_1 (StableExpr.local s1_2) loCap (elementAddress kind loCap)
        (show s1.i32ArrayViews = [] from sV)
        (StableExpr.rawSliceIndex s1_1 s1_3 (show readRawSliceIndex P s1 T _ cap hi = _ from hiRead))
        (by rw [show s1.heap = h from sH]; exact stored1)
      let s2 : State := { s1 with heap := h1 }
      have effect1 : HeapRegionWrite caller.heap h1 p (size * cap) := by
        have sl := slot_inside (T := T) (size := size) (p := p) loCap
        exact effect.trans (written1.enlarge sl.1 sl.2)
      -- items[high] = held
      obtain ⟨h2, stored2, readBack2, written2⟩ := stores a (List.getElem_mem _) s2 h1
        (elemBase T size p cap hi) (roomAt hi) (readable h1 hi hiCap effect1) effect1.unique
      rw [slotEq] at written2
      have assign2 := StableExpr.assignRaw (before := s2) (indexed := s2) (ready := s2) (heap := h2)
        (sourceId := 1) (show s2.local? 1 = some view from s1_1)
        (StableExpr.local (show s2.local? 3 = some (.signed .i32 (Int.ofNat hi)) from s1_3)) hiCap
        (elementAddress kind hiCap) (show s2.i32ArrayViews = [] from sV)
        (StableExpr.local (show s2.local? 4 = some a from s1_4)) stored2
      let s3 : State := { s2 with heap := h2 }
      have effect2 : HeapRegionWrite caller.heap h2 p (size * cap) := by
        have sl := slot_inside (T := T) (size := size) (p := p) hiCap
        exact effect1.trans (written2.enlarge sl.1 sl.2)
      -- low += 1
      have s3c : ∀ id, id ≠ 4 → s3.cellId? id = s.cellId? id := fun id ne => cellId_bindLocal_ne s a (Ne.symm ne)
      have s3_2 : s3.local? 2 = some (.signed .i32 (Int.ofNat k)) := s1_2
      have s3_3 : s3.local? 3 = some (.signed .i32 (Int.ofNat hi)) := s1_3
      have s3_0 : s3.local? 0 = some vv := local_kept fs _ (by decide) s_0
      have s3_1 : s3.local? 1 = some view := s1_1
      obtain ⟨s4, assigned4⟩ := assignLocal_exists s3 2 _ (.signed .i32 (Int.ofNat (k + 1))) c2
        ((s3c 2 (by decide)).trans sc2) s3_2
      have inc := increment_run target (show k + 1 < 2 ^ 31 by omega) ((s3c 2 (by decide)).trans sc2) s3_2 assigned4
      have cell4 := assignLocal_assignCell 2 c2 _ ((s3c 2 (by decide)).trans sc2) assigned4
      have eff4 := assignCell_effect cell4
      have s4_2 : s4.local? 2 = some (.signed .i32 (Int.ofNat (k + 1))) :=
        assignLocal_finds_assigned 2 c2 _ ((s3c 2 (by decide)).trans sc2) assigned4
      have s4c : ∀ id, s4.cellId? id = s3.cellId? id := fun id => by unfold State.cellId?; rw [eff4.locals]
      have keep4 : ∀ id v c, s3.cellId? id = some c → c ≠ c2 → s3.local? id = some v → s4.local? id = some v :=
        fun id v c cf ne lf => assignCell_preserves_other_local_of_cellId id c2 _ cell4 lf
          (by rw [cf]; exact fun e => ne (Option.some.inj e))
      have s4_3 := keep4 3 _ c3 ((s3c 3 (by decide)).trans sc3) c32 s3_3
      have s4_0 := keep4 0 _ c0 ((s3c 0 (by decide)).trans sc0) (fun e => c20 e.symm) s3_0
      have s4_1 := keep4 1 _ c1 ((s3c 1 (by decide)).trans sc1) (fun e => c21 e.symm) s3_1
      -- high -= 1
      have c3s4 : s4.cellId? 3 = some c3 := (s4c 3).trans ((s3c 3 (by decide)).trans sc3)
      obtain ⟨s5, assigned5⟩ := assignLocal_exists s4 3 _ (.signed .i32 ((n : Int) - 1 - ((k + 1 : Nat) : Int))) c3
        c3s4 s4_3
      have dec := decrement_run target (v := Int.ofNat hi) (by simp; omega) (by simp; omega) (by simp; omega)
        c3s4 s4_3 assigned5
      have cell5 := assignLocal_assignCell 3 c3 _ c3s4 assigned5
      have eff5 := assignCell_effect cell5
      have s5_3 := assignLocal_finds_assigned 3 c3 _ c3s4 assigned5
      have keep5 : ∀ id v c, s4.cellId? id = some c → c ≠ c3 → s4.local? id = some v → s5.local? id = some v :=
        fun id v c cf ne lf => assignCell_preserves_other_local_of_cellId id c3 _ cell5 lf
          (by rw [cf]; exact fun e => ne (Option.some.inj e))
      have s5_2 := keep5 2 _ c2 ((s4c 2).trans ((s3c 2 (by decide)).trans sc2)) c23 s4_2
      have s5_0 := keep5 0 _ c0 ((s4c 0).trans ((s3c 0 (by decide)).trans sc0)) (fun e => c30 e.symm) s4_0
      have s5_1 := keep5 1 _ c1 ((s4c 1).trans ((s3c 1 (by decide)).trans sc1)) (fun e => c31 e.symm) s4_1
      -- the body
      have bodyRun : RunsStmt P s body .next (restoreLocals s s5) :=
        RunsStmt.letLocal heldRun (RunsStmt.sequenceNext (RunsStmt.expression (RunsExpr.ofStable assign1 rfl))
          (RunsStmt.sequenceNext (RunsStmt.expression (RunsExpr.ofStable assign2 rfl))
            (RunsStmt.sequenceNext inc dec)))
      obtain ⟨bodyThreshold, bodyStable, _⟩ := bodyRun
      let s' := restoreLocals s s5
      have s5c : ∀ id, id ≠ 4 → s'.cellId? id = s5.cellId? id := fun id ne => by
        show s.cellId? id = s5.cellId? id
        have l5 : s5.cellId? id = s4.cellId? id := by unfold State.cellId?; rw [eff5.locals]
        rw [l5, s4c, s3c id ne]
      have lift : ∀ id v, id ≠ 4 → s5.local? id = some v → s'.local? id = some v := fun id v ne lf =>
        (local?_congr (s := s') (t := s5) rfl (s5c id ne)).trans lf
      -- the frame
      have frame3 : FreshCellFrame B0 s3 := by
        obtain ⟨e, c, nx, fr⟩ := sF.trans (FreshCellFrame.bindLocal s 4 a)
        exact ⟨e, c, nx, fr⟩
      have fs3 := FreshCellFrame.after_cellsWellFormed fB0 frame3
      obtain ⟨frame4, _, _, _, _⟩ := FreshCellFrame.assignFresh fB0 fs3 frame3 (Nat.le_refl _) cell4
      have fs4 := FreshCellFrame.after_cellsWellFormed fB0 frame4
      obtain ⟨frame5, _, _, _, _⟩ := FreshCellFrame.assignFresh fB0 fs4 frame4 (Nat.le_succ _) cell5
      refine ⟨condThreshold, bodyThreshold, _, _, condStable, bodyStable, ?_, ?_⟩
      · show n - counter 2 s' < n - counter 2 s
        rw [counter_eq (lift 2 _ (by decide) s5_2), counter_eq s_2']; omega
      · refine ⟨h2, sL, by show s5.heap = h2; rw [eff5.heap, eff4.heap], by show s5.i32ArrayViews = []; rw [eff5.views, eff4.views]; exact sV,
          by show s5.world = caller.world; rw [eff5.world, eff4.world]; exact sW,
          by obtain ⟨e, c, nx, fr⟩ := frame5; exact ⟨e, c, nx, fr⟩,
          lift 0 _ (by decide) s5_0, lift 1 _ (by decide) s5_1, lift 2 _ (by decide) s5_2,
          lift 3 _ (by decide) s5_3, effect2, ?_⟩
        intro j jN other within
        by_cases isLo : j = k
        · rw [isLo, readRawSliceIndex_elem other kind loCap,
            show revFrom n (k + 1) k = hi by unfold revFrom; rw [if_pos (by omega)]; omega, getD_of_lt (by omega)]
          rw [isLo] at within
          exact readBack1 other.heap (by
            rw [slotEq]
            exact ReadsWithin.trans (HeapRegionWrite.readsApart written2 (slots_apart hiCap loCap (by omega)))
              within)
        · by_cases isHi : j = hi
          · rw [isHi, readRawSliceIndex_elem other kind hiCap,
              show revFrom n (k + 1) hi = k by unfold revFrom; rw [if_pos (by omega)]; omega, getD_of_lt (by omega)]
            rw [isHi] at within
            exact readBack2 other.heap (by rw [slotEq]; exact within)
          · rw [show revFrom n (k + 1) j = revFrom n k j by
              unfold revFrom
              by_cases h1 : j < k ∨ n - k ≤ j
              · rw [if_pos h1, if_pos (by omega)]
              · rw [if_neg h1, if_neg (by omega)]]
            exact done j jN other (ReadsWithin.trans
              (HeapRegionWrite.readsApart written1 (slots_apart loCap (by omega) (fun e => isLo e.symm)))
              (ReadsWithin.trans
                (HeapRegionWrite.readsApart written2 (slots_apart hiCap (by omega) (fun e => isHi e.symm))) within)) }
  -- the initial state
  have init : Inv 0 B3 := by
    refine ⟨B0.heap, rfl, rfl, frame.views.trans noViews, frame.world,
      (FreshCellFrame.bindLocal B0 2 _).trans (FreshCellFrame.bindLocal B2 3 _),
      local_kept fB2 _ (by decide) b2_0, local_kept fB2 _ (by decide) (local_kept fB0 _ (by decide) b0_1),
      local_kept fB2 _ (by decide) (local_bound fB0 2 _), ?_, ?_, ?_⟩
    · rw [show (n : Int) - 1 - ((0 : Nat) : Int) = (xs.length : Int) - 1 by omega]
      exact local_bound fB2 3 _
    · rw [hB0]; exact HeapRegionWrite.refl _ unique
    · intro j jN other within
      rw [show revFrom n 0 j = j by simp [revFrom]; omega, getD_of_lt (by omega)]
      exact reads j (by omega) other (by rw [hB0] at within; exact within)
  obtain ⟨threshold, completion, final, loopRun, done⟩ :=
    executeTotalWhile measure P _ _ (countdownWhileOracle measure P _ _ (n / 2) spec) B3 ⟨0, Nat.zero_le _, init⟩
  obtain ⟨rfl, h, fL, fH, fV, fW, fF, f_0, _, _, _, effect, revd⟩ := done
  have ret : RunsStmt P final (.returnValue (some (.local 0))) (.returned (some vv)) final :=
    RunsStmt.returnValue (RunsExpr.local' f_0)
  have loopStmt : RunsStmt P B3 (reverseLoop T) .next final := ⟨threshold, loopRun, fL⟩
  have tail : RunsStmt P B3 (.sequence (reverseLoop T) (.returnValue (some (.local 0))))
      (.returned (some vv)) final := RunsStmt.sequenceNext loopStmt ret
  have run3 := RunsStmt.letLocal (type := i32Ty) (id := 3) subRun tail
  have run2 := RunsStmt.letLocal (type := i32Ty) (id := 2) (RunsExpr.value' (P := P) (S := B0) (.signed .i32 0)) run3
  have run1 := RunsStmt.letLocal (type := .slice T) (id := 1) slots run2
  have extB0 : Ext E B0 := (Ext.ofPure frame).trans (Ext.bindLocal fS1 1 view)
  have extFinal : Ext E final := ⟨fE, extB0.cells.trans fF, fW, fV.trans noViews.symm⟩
  refine ⟨_, run1, ((extFinal.restore B2).restore B0).restore S1, ?_⟩
  show VecRep P T size ids.vec final.heap vv xs.reverse ∧ HeapRegionWrite caller.heap final.heap p (size * cap)
  rw [fH]
  refine ⟨⟨p, cap, by rw [List.length_reverse], by rw [List.length_reverse]; exact lenLe, capBound,
    fun positive => (buffer positive).afterWrite effect, fun j jInside other within => ?_⟩, effect⟩
  rw [List.length_reverse] at jInside
  rw [List.getElem_reverse]
  have read := revd j (by omega) other within
  rw [show revFrom n (n / 2) j = xs.length - 1 - j by
    unfold revFrom
    by_cases h1 : j < n / 2 ∨ n - n / 2 ≤ j
    · rw [if_pos h1]; omega
    · rw [if_neg h1]; omega, getD_of_lt (by omega)] at read
  exact read

#print axioms reverse_spec

end Lanius.Std
