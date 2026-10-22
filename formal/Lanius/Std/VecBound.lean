import Lanius.Std.VecExtend

/-! # The binary-search loop

`lower_bound` and `upper_bound` share one loop:
`while (low < high) { let middle = low + (high - low) / 2;
if (cmp) { .. } else { .. } }`, where one branch sets `low = middle + 1`
and the other `high = middle`. Given a predicate `right` on indices that
holds on a prefix (the indices to the right of which the answer lies), the
loop ends with `low` the length of that prefix. -/

namespace Lanius.Std

open Lanius Lanius.Core Lanius.Semantics Lanius.Memory

variable {P : Program} {T : Ty} {ids : VecIds} {size : Nat}

/-! ## Helpers -/

theorem local_above2 {base s : State} (frame : FreshCellFrame base s) {a b id : VarId} {c d : CellId}
    (locals : s.locals = (a, c) :: (b, d) :: base.locals) (na : id ≠ a) (nb : id ≠ b) {v : Value}
    (found : base.local? id = some v) : s.local? id = some v := by
  let M : State := { s with locals := (b, d) :: base.locals }
  have fM : FreshCellFrame base M := frame
  have m := local_above fM rfl nb found
  exact local_above (base := M) (s := s) ⟨[], by simp [M], Nat.le_refl _, by simp⟩ locals na m

/-- `x = e;` for a local `x`. -/
theorem assign_run {st after : State} {idx : VarId} {cell : CellId} {old new : Value} {e : Expr}
    (cellFound : st.cellId? idx = some cell) (found : st.local? idx = some old)
    (rhs : RunsExpr P st e new st) (oldFree : valueMayContainI32ArrayView old = false)
    (newFree : valueMayContainI32ArrayView new = false)
    (assigned : st.assignLocal idx new = some after) :
    RunsStmt P st (.expression (.assign .set (.local idx) e)) .next after := by
  obtain ⟨threshold, right, locals⟩ := rhs
  refine RunsStmt.expression (RunsExpr.ofStable (Lanius.Extraction.CertificateEmitterFrame.StableExpr.assignSetLocal
    P st idx cell _ _ _ st after cellFound found right rfl assigned oldFree newFree) ?_)
  exact (assignLocal_preserves_frame (protectedId := idx) assigned).1

/-! ## The template -/

def setLow : Stmt := .expression (.assign .set (.local 3) (.binary .add (.local 5) (int 1)))
def setHigh : Stmt := .expression (.assign .set (.local 4) (.local 5))

/-- The branch taken when the comparison is true: with `flip = false` the
comparison says "go right". -/
def searchThen : Bool → Stmt
  | false => setLow
  | true => setHigh

def searchElse : Bool → Stmt
  | false => setHigh
  | true => setLow

/-- `low + (high - low) / 2` -/
def middleExpr : Expr :=
  .binary .add (.local 3) (.binary .divide (.binary .subtract (.local 4) (.local 3)) (int 2))

def searchBody (cmp : Expr) (flip : Bool) : Stmt :=
  .letLocal 5 i32Ty middleExpr (.ifThenElse cmp (searchThen flip) (searchElse flip))

/-- The loop, with `low`, `high` and `middle` the locals 3, 4 and 5. -/
def searchLoop (cmp : Expr) (flip : Bool) : Stmt :=
  .whileLoop (.binary .less (.local 3) (.local 4)) (searchBody cmp flip)

/-! ## The loop -/

theorem search_loop_spec (target : P.target = Target.x86_64) {B : State} (fB : B.CellsWellFormed)
    {n : Nat} (nSmall : n < 2 ^ 31) (right : Nat → Bool)
    (part : ∀ i j, i ≤ j → j < n → right j = true → right i = true) (flip : Bool) (cmp : Expr)
    (cmpSpec : ∀ (s : State) (mid : Nat), mid < n → s.CellsWellFormed → FreshCellFrame B s →
      s.heap = B.heap → s.i32ArrayViews = B.i32ArrayViews → s.local? 5 = some (.signed .i32 mid) →
      (∀ id v, id ≠ 3 → id ≠ 4 → id ≠ 5 → B.local? id = some v → s.local? id = some v) →
      ∃ after, RunsExpr P s cmp (.boolean (right mid != flip)) after ∧ PureFrame s after) :
    ∃ (after : State) (r : Nat), RunsStmt P ((B.bindLocal 3 (.signed .i32 0)).bindLocal 4 (.signed .i32 n)) (searchLoop cmp flip)
        .next after ∧
      FreshCellFrame B after ∧ after.heap = B.heap ∧ after.world = B.world ∧
      after.i32ArrayViews = B.i32ArrayViews ∧ after.local? 3 = some (.signed .i32 r) ∧ r ≤ n ∧
      (∀ i, i < r → right i = true) ∧ (∀ i, r ≤ i → i < n → right i = false) := by
  let c3 := B.nextCell
  let c4 := B.nextCell + 1
  have c43 : c4 ≠ c3 := Nat.succ_ne_self _
  let B3 := B.bindLocal 3 (.signed .i32 0)
  have fB3 : B3.CellsWellFormed := fB.bindLocal _ _
  let B4 := B3.bindLocal 4 (.signed .i32 n)
  let L := B4.locals
  have hL : L = (4, c4) :: (3, c3) :: B.locals := rfl
  let Frame : State → Prop := fun s => FreshCellFrame B s ∧ s.locals = L ∧ s.heap = B.heap ∧
    s.world = B.world ∧ s.i32ArrayViews = B.i32ArrayViews ∧ s.CellsWellFormed
  have cell3 : ∀ s, Frame s → s.cellId? 3 = some c3 := fun s fr => by simp [State.cellId?, fr.2.1, hL]
  have cell4 : ∀ s, Frame s → s.cellId? 4 = some c4 := fun s fr => by simp [State.cellId?, fr.2.1, hL]
  have old : ∀ s, Frame s → ∀ id v, id ≠ 3 → id ≠ 4 → B.local? id = some v → s.local? id = some v :=
    fun s fr id v n3 n4 f => local_above2 fr.1 fr.2.1 n4 n3 f
  let Inv : State → Prop := fun s => ∃ lo hi : Nat, Frame s ∧ s.local? 3 = some (.signed .i32 lo) ∧
    s.local? 4 = some (.signed .i32 hi) ∧ lo ≤ hi ∧ hi ≤ n ∧ (∀ i : Nat, i < lo → right i = true) ∧
    (∀ i : Nat, hi ≤ i → i < n → right i = false)
  let measure : State → Nat := fun s => counter 4 s - counter 3 s
  let oracle : TotalWhileOracle measure P (.binary .less (.local 3) (.local 4)) (searchBody cmp flip) := {
    Inv := Inv
    Done := fun c s => c = .next ∧ ∃ lo : Nat, Frame s ∧ s.local? 3 = some (.signed .i32 lo) ∧ lo ≤ n ∧
      (∀ i : Nat, i < lo → right i = true) ∧ (∀ i : Nat, lo ≤ i → i < n → right i = false)
    step := by
      intro s inv
      obtain ⟨lo, hi, fr, s3, s4, le, hn, below, above⟩ := inv
      have cond := RunsExpr.binary (program := P) (RunsExpr.local' s3) (RunsExpr.local' s4) (by decide)
        (eval_i32_lt _ _ _)
      by_cases more : lo < hi
      · rw [show decide ((lo : Int) < hi) = true by simp; omega] at cond
        obtain ⟨condThreshold, condStable, _⟩ := cond
        obtain ⟨mid, hmid⟩ : ∃ mid, mid = lo + (hi - lo) / 2 := ⟨_, rfl⟩
        have midLo : lo ≤ mid := by omega
        have midHi : mid < hi := by omega
        -- let middle = low + (high - low) / 2
        have diff := RunsExpr.binary (operation := .subtract) (program := P) (RunsExpr.local' s4)
          (RunsExpr.local' s3) (by decide) (by rw [target]; exact eval_i32_sub (by omega) (by omega))
        rw [show (hi : Int) - (lo : Int) = ((hi - lo : Nat) : Int) by omega] at diff
        have half := RunsExpr.binary (operation := .divide) diff (RunsExpr.value' (P := P) (S := s) (.signed .i32 2))
          (by decide) (by rw [target]; exact eval_i32_div2 (by omega))
        have midRun := RunsExpr.binary (operation := .add) (RunsExpr.local' s3) half (by decide)
          (by rw [target]; exact eval_i32_add (by omega) (by omega))
        rw [show (lo : Int) + (((hi - lo) / 2 : Nat) : Int) = (mid : Int) by omega] at midRun
        let s5 := s.bindLocal 5 (.signed .i32 mid)
        have fs : s.CellsWellFormed := fr.2.2.2.2.2
        have fs5 : s5.CellsWellFormed := fs.bindLocal _ _
        have s5_5 : s5.local? 5 = some (.signed .i32 mid) := local_bound fs 5 _
        have frame5 : FreshCellFrame B s5 := fr.1.trans (FreshCellFrame.bindLocal s 5 _)
        obtain ⟨a1, cmpRun, pure1⟩ := cmpSpec s5 mid (by omega) fs5 frame5 fr.2.2.1 fr.2.2.2.2.1 s5_5
          (fun id v n3 n4 n5 f => local_kept fs _ (Ne.symm n5) (old s fr id v n3 n4 f))
        have fa1 : a1.CellsWellFormed := pure1.afterFormed
        have frameA1 : FreshCellFrame B a1 := frame5.trans pure1.cells
        have a1c : ∀ id, a1.cellId? id = s5.cellId? id := fun id => by unfold State.cellId?; rw [pure1.locals]
        have a1_3 : a1.local? 3 = some (.signed .i32 lo) := pure1.localFound (local_kept fs _ (by decide) s3)
        have a1_4 : a1.local? 4 = some (.signed .i32 hi) := pure1.localFound (local_kept fs _ (by decide) s4)
        have a1_5 : a1.local? 5 = some (.signed .i32 mid) := pure1.localFound s5_5
        have c3a1 : a1.cellId? 3 = some c3 :=
          (a1c 3).trans ((cellId_bindLocal_ne s _ (by decide)).trans (cell3 s fr))
        have c4a1 : a1.cellId? 4 = some c4 :=
          (a1c 4).trans ((cellId_bindLocal_ne s _ (by decide)).trans (cell4 s fr))
        -- the state after the body, given the assignment
        have post : ∀ a2 c w, a1.assignCell c w = some a2 → B.nextCell ≤ c →
            Frame (restoreLocals s a2) ∧
            ∀ id v, id ≠ 5 → a2.local? id = some v → (restoreLocals s a2).local? id = some v := by
          intro a2 c w cellA fresh
          have eff := assignCell_effect cellA
          obtain ⟨frameA2, _, _, _, _⟩ := FreshCellFrame.assignFresh fB fa1 frameA1 fresh cellA
          have frame' : FreshCellFrame B (restoreLocals s a2) := by
            obtain ⟨e, c, nx, f⟩ := frameA2; exact ⟨e, c, nx, f⟩
          refine ⟨⟨frame', fr.2.1, ?_, ?_, ?_, FreshCellFrame.after_cellsWellFormed fB frame'⟩, ?_⟩
          · show a2.heap = B.heap; rw [eff.heap, pure1.heap]; exact fr.2.2.1
          · show a2.world = B.world; rw [eff.world, pure1.world]; exact fr.2.2.2.1
          · show a2.i32ArrayViews = B.i32ArrayViews; rw [eff.views, pure1.views]; exact fr.2.2.2.2.1
          · intro id v ne f
            refine (local?_congr (s := restoreLocals s a2) (t := a2) rfl ?_).trans f
            show s.cellId? id = a2.cellId? id
            have l2 : a2.cellId? id = a1.cellId? id := by unfold State.cellId?; rw [eff.locals]
            rw [l2, a1c, cellId_bindLocal_ne s _ (Ne.symm ne)]
        -- low = middle + 1
        have lowCase : right mid = true → ∃ a2, RunsStmt P a1 setLow .next a2 ∧
            measure (restoreLocals s a2) < measure s ∧ Inv (restoreLocals s a2) := by
          intro yes
          obtain ⟨a2, assigned⟩ := assignLocal_exists a1 3 _ (.signed .i32 ((mid + 1 : Nat) : Int)) c3 c3a1 a1_3
          have rhs := RunsExpr.binary (operation := .add) (program := P) (RunsExpr.local' a1_5)
            (RunsExpr.value' (P := P) (S := a1) (.signed .i32 1)) (by decide)
            (by rw [target]; exact eval_i32_add (by omega) (by omega))
          rw [show (mid : Int) + 1 = ((mid + 1 : Nat) : Int) by omega] at rhs
          have cellA := assignLocal_assignCell 3 c3 _ c3a1 assigned
          obtain ⟨fr', lift⟩ := post a2 c3 _ cellA (Nat.le_refl _)
          have a2_3 := assignLocal_finds_assigned 3 c3 _ c3a1 assigned
          have a2_4 := assignCell_preserves_other_local_of_cellId 4 c3 _ cellA a1_4
            (by rw [c4a1]; exact fun e => c43 (Option.some.inj e))
          have n3 := lift 3 _ (by decide) a2_3
          have n4 := lift 4 _ (by decide) a2_4
          refine ⟨a2, assign_run c3a1 a1_3 rhs rfl rfl assigned, ?_, mid + 1, hi, fr', n3, n4, by omega, hn,
            fun i lt => ?_, above⟩
          · show counter 4 _ - counter 3 _ < counter 4 s - counter 3 s
            rw [counter_eq n3, counter_eq n4, counter_eq s3, counter_eq s4]; omega
          · by_cases low : i < lo
            · exact below i low
            · exact part i mid (by omega) (by omega) yes
        -- high = middle
        have highCase : right mid = false → ∃ a2, RunsStmt P a1 setHigh .next a2 ∧
            measure (restoreLocals s a2) < measure s ∧ Inv (restoreLocals s a2) := by
          intro no
          obtain ⟨a2, assigned⟩ := assignLocal_exists a1 4 _ (.signed .i32 (mid : Int)) c4 c4a1 a1_4
          have cellA := assignLocal_assignCell 4 c4 _ c4a1 assigned
          obtain ⟨fr', lift⟩ := post a2 c4 _ cellA (Nat.le_succ _)
          have a2_4 := assignLocal_finds_assigned 4 c4 _ c4a1 assigned
          have a2_3 := assignCell_preserves_other_local_of_cellId 3 c4 _ cellA a1_3
            (by rw [c3a1]; exact fun e => c43 (Option.some.inj e).symm)
          have n3 := lift 3 _ (by decide) a2_3
          have n4 := lift 4 _ (by decide) a2_4
          refine ⟨a2, assign_run c4a1 a1_4 (RunsExpr.local' a1_5) rfl rfl assigned, ?_, lo, mid, fr', n3, n4,
            midLo, by omega, below, fun i ge lt => ?_⟩
          · show counter 4 _ - counter 3 _ < counter 4 s - counter 3 s
            rw [counter_eq n3, counter_eq n4, counter_eq s3, counter_eq s4]; omega
          · cases h : right i with
            | false => rfl
            | true => rw [part mid i ge lt h] at no; cases no
        right
        have finish : ∀ (st : Stmt) (a2 : State),
            RunsStmt P s5 (.ifThenElse cmp (searchThen flip) (searchElse flip)) .next a2 →
            measure (restoreLocals s a2) < measure s → Inv (restoreLocals s a2) →
            ∃ conditionThreshold bodyThreshold conditionAfter completion bodyAfter,
              StableExpr conditionThreshold P s (.binary .less (.local 3) (.local 4)) (.boolean true)
                conditionAfter ∧
              StableStmt bodyThreshold P conditionAfter (searchBody cmp flip) completion bodyAfter ∧
              (completion ≠ .next ∧ completion ≠ .continueLoop →
                (fun c s => c = .next ∧ ∃ lo : Nat, Frame s ∧ s.local? 3 = some (.signed .i32 lo) ∧ lo ≤ n ∧
                  (∀ i : Nat, i < lo → right i = true) ∧ (∀ i : Nat, lo ≤ i → i < n → right i = false))
                  (normalizeCompletion completion) bodyAfter) ∧
              (completion = .next ∨ completion = .continueLoop →
                measure bodyAfter < measure s ∧ Inv bodyAfter) := by
          intro _ a2 branch lt inv'
          obtain ⟨bodyThreshold, bodyStable, _⟩ := RunsStmt.letLocal (type := i32Ty) midRun branch
          exact ⟨condThreshold, bodyThreshold, s, .next, _, condStable, bodyStable,
            fun h => absurd rfl h.1, fun _ => ⟨lt, inv'⟩⟩
        cases hr : right mid with
        | true =>
            obtain ⟨a2, run, lt, inv'⟩ := lowCase hr
            rw [hr] at cmpRun
            cases flip with
            | false => exact finish setLow a2 (RunsStmt.ifThenElseTrue cmpRun run) lt inv'
            | true => exact finish setLow a2 (RunsStmt.ifThenElseFalse cmpRun run) lt inv'
        | false =>
            obtain ⟨a2, run, lt, inv'⟩ := highCase hr
            rw [hr] at cmpRun
            cases flip with
            | false => exact finish setHigh a2 (RunsStmt.ifThenElseFalse cmpRun run) lt inv'
            | true => exact finish setHigh a2 (RunsStmt.ifThenElseTrue cmpRun run) lt inv'
      · left
        rw [show decide ((lo : Int) < hi) = false by simp; omega] at cond
        obtain ⟨threshold, stable, _⟩ := cond
        exact ⟨threshold, s, stable, rfl, lo, fr, s3, by omega, below, fun i ge lt => above i (by omega) lt⟩ }
  have frame0 : Frame B4 := ⟨(FreshCellFrame.bindLocal B 3 _).trans (FreshCellFrame.bindLocal B3 4 _), rfl, rfl,
    rfl, rfl, fB3.bindLocal _ _⟩
  obtain ⟨threshold, completion, after, loopStable, rfl, lo, fr, a3, le, below, above⟩ :=
    executeTotalWhile measure P _ _ oracle B4
      ⟨0, n, frame0, local_kept fB3 _ (by decide) (local_bound fB 3 _), local_bound fB3 4 _, Nat.zero_le _,
        Nat.le_refl _, fun i lt => absurd lt (Nat.not_lt_zero _), fun i ge lt => absurd lt (by omega)⟩
  exact ⟨after, lo, ⟨threshold, loopStable, fr.2.1⟩, fr.1, fr.2.2.1, fr.2.2.2.1, fr.2.2.2.2.1, a3, le, below, above⟩

#print axioms search_loop_spec

end Lanius.Std
