import Lanius.Std.VecSift

/-! # `sort`

`sort(value)` heapsorts the slots of `value` in place: the build loop sifts
every inner node down (`build_start`, `build_step`), and the extraction loop
swaps the root to the end of the heap and sifts the new root down
(`sort_start`, `sort_swap`, `sort_after`, `sort_done`). The result is the
same vector, holding a sorted permutation of its elements.

Locals: 0 `value`, 1 `items`, 2 `start`, 3 `end`, 4 `held`. -/

namespace Lanius.Std

open Lanius Lanius.Core Lanius.Semantics Lanius.Memory

variable {P : Program} {T : Ty} {ids : VecIds} {size : Nat}

/-- `while (start > 0) { start -= 1; sift_down(items, start, value.length); }` -/
def buildLoop (sd : FunctionId) : Stmt :=
  .whileLoop (.binary .greater (.local 2) (int 0))
    (.sequence (decrement 2) (.expression (.call sd [.local 1, .local 2, .field (.local 0) 1])))

/-- `end -= 1; let held = items[0]; items[0] = items[end]; items[end] = held;
sift_down(items, 0, end);` -/
def extractBody (T : Ty) (sd : FunctionId) : Stmt :=
  .sequence (decrement 3)
    (.letLocal 4 T (.index (.local 1) (int 0))
      (.sequence (.expression (.assign .set (.index (.local 1) (int 0)) (.index (.local 1) (.local 3))))
      (.sequence (.expression (.assign .set (.index (.local 1) (.local 3)) (.local 4)))
        (.expression (.call sd [.local 1, int 0, .local 3])))))

def extractLoop (T : Ty) (sd : FunctionId) : Stmt :=
  .whileLoop (.binary .greater (.local 3) (int 1)) (extractBody T sd)

def sortFn (ids : VecIds) (T : Ty) (f sd : FunctionId) : Function where
  id := f
  parameters := [(0, vecTy ids)]
  returnType := vecTy ids
  body := some <|
    .letLocal 1 (.slice T) (.call ids.slots [.local 0])
    (.letLocal 2 i32Ty (.binary .divide (.field (.local 0) 1) (int 2))
    (.sequence (buildLoop sd)
    (.letLocal 3 i32Ty (.field (.local 0) 1)
    (.sequence (extractLoop T sd) (.returnValue (some (.local 0)))))))

/-! ## The build loop -/

theorem build_loop_spec (target : P.target = Target.x86_64) (kind : ElemKind P T size) {sd lt : FunctionId}
    (siftFound : P.function? sd = some (siftDownFn T sd lt))
    {ltv : Value → Value → Bool} {vals : List Value} (ltSpec : LtSpec P lt ltv vals)
    (order : NegTrans ltv) (asymm : Asymm ltv)
    {B : State} (fB : B.CellsWellFormed) {tid : TypeId} {fields : List Value} {p cap n : Nat}
    {xs : List Value} {h0 : Heap}
    (b0 : B.local? 0 = some (.structure tid fields)) (nField : fields[1]? = some (.signed .i32 (n : Int)))
    (b1 : B.local? 1 = some (.rawSlice T (viewAddr T size p cap) cap))
    (lenEq : xs.length = n) (len : n ≤ cap) (small : 2 * n < 2 ^ 31)
    (buffer : 0 < cap → Buffer h0 p (size * cap)) (effect0 : HeapRegionWrite h0 B.heap p (size * cap))
    (arr0 : ArrayAt P T size B.heap p cap xs) (sub : ∀ z ∈ xs, z ∈ vals)
    (stores : ∀ y ∈ xs, ElemStore P T size y) (noViews : B.i32ArrayViews = []) :
    ∃ (final : State) (a : List Value),
      RunsStmt P (B.bindLocal 2 (.signed .i32 ((n / 2 : Nat) : Int))) (buildLoop sd) .next final ∧
      FreshCellFrame B final ∧ final.locals = (B.bindLocal 2 (.signed .i32 ((n / 2 : Nat) : Int))).locals ∧
      final.world = B.world ∧ final.i32ArrayViews = [] ∧
      ArrayAt P T size final.heap p cap a ∧ HeapRegionWrite h0 final.heap p (size * cap) ∧
      a.length = n ∧ a.Perm xs ∧ HeapFrom ltv a 0 n := by
  let B2 := B.bindLocal 2 (.signed .i32 ((n / 2 : Nat) : Int))
  let c2 := B.nextCell
  have cell2 : ∀ s : State, s.locals = B2.locals → s.cellId? 2 = some c2 := fun s hs => by
    simp [State.cellId?, hs, B2, State.bindLocal, State.bindCell, c2]
  have subOf : ∀ a : List Value, a.Perm xs → ∀ z ∈ a, z ∈ vals := fun a perm z m => sub z (perm.mem_iff.mp m)
  have storesOf : ∀ a : List Value, a.Perm xs → ∀ y ∈ a, ElemStore P T size y :=
    fun a perm y m => stores y (perm.mem_iff.mp m)
  let Inv : State → Prop := fun s => ∃ (a : List Value) (st : Nat), st ≤ n / 2 ∧ s.locals = B2.locals ∧
    FreshCellFrame B s ∧ s.world = B.world ∧ s.i32ArrayViews = [] ∧ s.local? 2 = some (.signed .i32 (st : Int)) ∧
    ArrayAt P T size s.heap p cap a ∧ HeapRegionWrite h0 s.heap p (size * cap) ∧ a.length = n ∧ a.Perm xs ∧
    HeapFrom ltv a st n
  let Done : Completion → State → Prop := fun c s => c = .next ∧ s.locals = B2.locals ∧ FreshCellFrame B s ∧
    s.world = B.world ∧ s.i32ArrayViews = [] ∧ ∃ a, ArrayAt P T size s.heap p cap a ∧
    HeapRegionWrite h0 s.heap p (size * cap) ∧ a.length = n ∧ a.Perm xs ∧ HeapFrom ltv a 0 n
  let measure : State → Nat := fun s => counter 2 s
  let oracle : TotalWhileOracle measure P (.binary .greater (.local 2) (int 0))
      (.sequence (decrement 2) (.expression (.call sd [.local 1, .local 2, .field (.local 0) 1]))) := {
    Inv := Inv
    Done := Done
    step := by
      intro s invariant
      obtain ⟨a, st, stLe, sL, sF, sW, sV, s2, arr, effect, alen, perm, heap⟩ := invariant
      have fs : s.CellsWellFormed := FreshCellFrame.after_cellsWellFormed fB sF
      have cond := RunsExpr.binary (operation := .greater) (program := P) (RunsExpr.local' s2)
        (RunsExpr.value' (P := P) (S := s) (.signed .i32 0)) (by decide) (eval_i32_gt _ _ _)
      by_cases zero : st = 0
      · subst zero
        rw [show decide (((0 : Nat) : Int) > 0) = false by simp] at cond
        obtain ⟨threshold, stable, _⟩ := cond
        exact Or.inl ⟨threshold, s, stable, rfl, sL, sF, sW, sV, a, arr, effect, alen, perm, heap⟩
      rw [show decide ((st : Int) > 0) = true by simp; omega] at cond
      obtain ⟨condThreshold, condStable, _⟩ := cond
      right
      have sc2 := cell2 s sL
      obtain ⟨s1, assigned⟩ := assignLocal_exists s 2 _ (.signed .i32 ((st - 1 : Nat) : Int)) c2 sc2 s2
      have dec := decrement_run target (by omega) (by omega) (by omega) sc2 s2 assigned
      have cellA := assignLocal_assignCell 2 c2 _ sc2 assigned
      obtain ⟨frame1, fs1, locals1, heap1, world1, views1⟩ := FreshCellFrame.assignCounter fB fs sF cellA
      have s1L : s1.locals = B2.locals := locals1.trans sL
      have s1_0 : s1.local? 0 = some (.structure tid fields) := local_above frame1 s1L (by decide) b0
      have s1_1 : s1.local? 1 = some (.rawSlice T (viewAddr T size p cap) cap) := local_above frame1 s1L (by decide) b1
      have s1_2 := assignLocal_finds_assigned 2 c2 _ sc2 assigned
      have pos : 0 < st := by omega
      obtain ⟨R, a', callRun, frameR, worldR, viewsR, arrR, effR, sifted⟩ :=
        siftDown_spec target kind siftFound ltSpec order asymm fs1 (p := p) (cap := cap) (root := st - 1) (cnt := n)
          (a0 := a) (h0 := h0) (by omega) (by omega) small (build_step heap pos (by omega)) buffer
          (by rw [heap1]; exact effect) (by rw [heap1]; exact arr) (subOf a perm) (storesOf a perm) (views1.trans sV)
      have argsRun : RunsExprs P s1 [.local 1, .local 2, .field (.local 0) 1]
          [.rawSlice T (viewAddr T size p cap) cap, .signed .i32 ((st - 1 : Nat) : Int), .signed .i32 (n : Int)] s1 :=
        RunsExprs.three (RunsExpr.local' s1_1) (RunsExpr.local' s1_2) (RunsExpr.field' (RunsExpr.local' s1_0) nField)
      have call := callArgs argsRun callRun
      obtain ⟨_, _, locR⟩ := id call
      obtain ⟨bodyThreshold, bodyStable, _⟩ : RunsStmt P s
          (.sequence (decrement 2) (.expression (.call sd [.local 1, .local 2, .field (.local 0) 1]))) .next R :=
        RunsStmt.sequenceNext dec (RunsStmt.expression call)
      have R2 : R.local? 2 = some (.signed .i32 ((st - 1 : Nat) : Int)) :=
        FreshCellFrame.localFound frameR locR 2 _ s1_2
      obtain ⟨alen', perm', heap', _, _⟩ := sifted
      refine ⟨condThreshold, bodyThreshold, s, .next, R, condStable, bodyStable, fun h => absurd rfl h.1,
        fun _ => ⟨?_, a', st - 1, by omega, locR.trans s1L, frame1.trans frameR, worldR.trans (world1.trans sW),
          viewsR.trans (views1.trans sV), R2, arrR, effR, alen'.trans alen, perm'.trans perm, heap'⟩⟩
      show counter 2 R < counter 2 s
      rw [counter_eq R2, counter_eq s2]; omega }
  have init : Inv B2 := ⟨xs, n / 2, Nat.le_refl _, rfl, FreshCellFrame.bindLocal B 2 _, rfl, noViews,
    local_bound fB 2 _, arr0, effect0, lenEq, List.Perm.refl _, build_start ltv xs n⟩
  obtain ⟨threshold, completion, final, loopStable, done⟩ := executeTotalWhile measure P _ _ oracle B2 init
  obtain ⟨rfl, fL, fF, fW, fV, a, arr, eff, alen, perm, heap⟩ := done
  exact ⟨final, a, ⟨threshold, loopStable, fL⟩, fF, fL, fW, fV, arr, eff, alen, perm, heap⟩

/-! ## The extraction loop -/

theorem extract_loop_spec (target : P.target = Target.x86_64) (kind : ElemKind P T size) {sd lt : FunctionId}
    (siftFound : P.function? sd = some (siftDownFn T sd lt))
    {ltv : Value → Value → Bool} {vals : List Value} (ltSpec : LtSpec P lt ltv vals)
    (order : NegTrans ltv) (asymm : Asymm ltv)
    {B : State} (fB : B.CellsWellFormed) {p cap n : Nat} {a0 : List Value} {h0 : Heap}
    (b1 : B.local? 1 = some (.rawSlice T (viewAddr T size p cap) cap))
    (alen0 : a0.length = n) (len : n ≤ cap) (small : 2 * n < 2 ^ 31)
    (buffer : 0 < cap → Buffer h0 p (size * cap)) (effect0 : HeapRegionWrite h0 B.heap p (size * cap))
    (arr0 : ArrayAt P T size B.heap p cap a0) (heap0 : HeapFrom ltv a0 0 n) (sub : ∀ z ∈ a0, z ∈ vals)
    (stores : ∀ y ∈ a0, ElemStore P T size y) (noViews : B.i32ArrayViews = []) :
    ∃ (final : State) (a : List Value),
      RunsStmt P (B.bindLocal 3 (.signed .i32 (n : Int))) (extractLoop T sd) .next final ∧
      FreshCellFrame B final ∧ final.locals = (B.bindLocal 3 (.signed .i32 (n : Int))).locals ∧
      final.world = B.world ∧ final.i32ArrayViews = [] ∧
      ArrayAt P T size final.heap p cap a ∧ HeapRegionWrite h0 final.heap p (size * cap) ∧
      a.length = n ∧ a.Perm a0 ∧ Sorted ltv a := by
  let B3 := B.bindLocal 3 (.signed .i32 (n : Int))
  let c3 := B.nextCell
  have cell3 : ∀ s : State, s.locals = B3.locals → s.cellId? 3 = some c3 := fun s hs => by
    simp [State.cellId?, hs, B3, State.bindLocal, State.bindCell, c3]
  have subOf : ∀ a : List Value, a.Perm a0 → ∀ z ∈ a, z ∈ vals := fun a perm z m => sub z (perm.mem_iff.mp m)
  have storesOf : ∀ a : List Value, a.Perm a0 → ∀ y ∈ a, ElemStore P T size y :=
    fun a perm y m => stores y (perm.mem_iff.mp m)
  let Inv : State → Prop := fun s => ∃ (a : List Value) (e : Nat), e ≤ n ∧ s.locals = B3.locals ∧
    FreshCellFrame B s ∧ s.world = B.world ∧ s.i32ArrayViews = [] ∧ s.local? 3 = some (.signed .i32 (e : Int)) ∧
    ArrayAt P T size s.heap p cap a ∧ HeapRegionWrite h0 s.heap p (size * cap) ∧ a.length = n ∧ a.Perm a0 ∧
    SortInv ltv a e n
  let Done : Completion → State → Prop := fun c s => c = .next ∧ s.locals = B3.locals ∧ FreshCellFrame B s ∧
    s.world = B.world ∧ s.i32ArrayViews = [] ∧ ∃ a, ArrayAt P T size s.heap p cap a ∧
    HeapRegionWrite h0 s.heap p (size * cap) ∧ a.length = n ∧ a.Perm a0 ∧ Sorted ltv a
  let measure : State → Nat := fun s => counter 3 s
  let oracle : TotalWhileOracle measure P (.binary .greater (.local 3) (int 1)) (extractBody T sd) := {
    Inv := Inv
    Done := Done
    step := by
      intro s invariant
      obtain ⟨a, e, eLe, sL, sF, sW, sV, s3, arr, effect, alen, perm, sinv⟩ := invariant
      have fs : s.CellsWellFormed := FreshCellFrame.after_cellsWellFormed fB sF
      have cond := RunsExpr.binary (operation := .greater) (program := P) (RunsExpr.local' s3)
        (RunsExpr.value' (P := P) (S := s) (.signed .i32 1)) (by decide) (eval_i32_gt _ _ _)
      by_cases last : e ≤ 1
      · rw [show decide ((e : Int) > 1) = false by simp; omega] at cond
        obtain ⟨threshold, stable, _⟩ := cond
        have whole : SortInv ltv a e a.length := by rw [alen]; exact sinv
        exact Or.inl ⟨threshold, s, stable, rfl, sL, sF, sW, sV, a, arr, effect, alen, perm, sort_done whole last⟩
      rw [show decide ((e : Int) > 1) = true by simp; omega] at cond
      obtain ⟨condThreshold, condStable, _⟩ := cond
      right
      have sc3 := cell3 s sL
      obtain ⟨s1, assigned⟩ := assignLocal_exists s 3 _ (.signed .i32 ((e - 1 : Nat) : Int)) c3 sc3 s3
      have dec := decrement_run target (by omega) (by omega) (by omega) sc3 s3 assigned
      have cellA := assignLocal_assignCell 3 c3 _ sc3 assigned
      obtain ⟨frame1, fs1, locals1, heap1, world1, views1⟩ := FreshCellFrame.assignCounter fB fs sF cellA
      have s1L : s1.locals = B3.locals := locals1.trans sL
      have s1_1 : s1.local? 1 = some (.rawSlice T (viewAddr T size p cap) cap) := local_above frame1 s1L (by decide) b1
      have s1_3 := assignLocal_finds_assigned 3 c3 _ sc3 assigned
      -- the swap
      have swapPerm : (swapAt a 0 (e - 1)).Perm a0 := (swapAt_perm (by omega) (by omega)).trans perm
      obtain ⟨h2, arrNew, effNew, cont⟩ := swap_run kind fs1 (items := 1) (held := 4) (ei := int 0)
        (ej := .local 3) (i := 0) (j := e - 1) s1_1 (by decide) (fun _ _ => ⟨1, StableExpr.value⟩)
        (fun _ ag => ⟨1, StableExpr.local (ag 3 _ (by decide) s1_3)⟩) (by omega) (by omega) (by omega) (by omega)
        buffer (by rw [heap1]; exact effect) (by rw [heap1]; exact arr) (storesOf a perm) (views1.trans sV)
      let s5 : State := { s1.bindLocal 4 (elt a 0) with heap := h2 }
      have fs5 : s5.CellsWellFormed := fs1.bindLocal 4 (elt a 0)
      have s5_1 : s5.local? 1 = some (.rawSlice T (viewAddr T size p cap) cap) := local_kept (new := 4) fs1 (elt a 0) (by decide) s1_1
      have s5_3 : s5.local? 3 = some (.signed .i32 ((e - 1 : Nat) : Int)) := local_kept (new := 4) fs1 (elt a 0) (by decide) s1_3
      have frame5 : FreshCellFrame B s5 := by
        obtain ⟨x, cl, nx, fx⟩ := frame1.trans (FreshCellFrame.bindLocal s1 4 (elt a 0)); exact ⟨x, cl, nx, fx⟩
      -- sift_down(items, 0, end)
      obtain ⟨R, a', callRun, frameR, worldR, viewsR, arrR, effR, sifted⟩ :=
        siftDown_spec target kind siftFound ltSpec order asymm fs5 (p := p) (cap := cap) (root := 0) (cnt := e - 1)
          (a0 := swapAt a 0 (e - 1)) (h0 := h0) (by rw [length_swapAt]; omega) (by rw [length_swapAt]; omega)
          (by omega) (sort_swap sinv (by omega) (by omega)) buffer effNew arrNew (subOf _ swapPerm)
          (storesOf _ swapPerm) (views1.trans sV)
      have argsRun : RunsExprs P s5 [.local 1, int 0, .local 3]
          [.rawSlice T (viewAddr T size p cap) cap, .signed .i32 ((0 : Nat) : Int), .signed .i32 ((e - 1 : Nat) : Int)]
          s5 :=
        RunsExprs.three (RunsExpr.local' s5_1) (RunsExpr.value' _) (RunsExpr.local' s5_3)
      have call := callArgs argsRun callRun
      obtain ⟨_, _, locR⟩ := id call
      have swapStmt := cont _ _ R (RunsStmt.expression call)
      obtain ⟨bodyThreshold, bodyStable, _⟩ : RunsStmt P s (extractBody T sd) .next (restoreLocals s1 R) :=
        RunsStmt.sequenceNext dec swapStmt
      let s' := restoreLocals s1 R
      have R3 : R.local? 3 = some (.signed .i32 ((e - 1 : Nat) : Int)) := FreshCellFrame.localFound frameR locR 3 _ s5_3
      have s'_3 : s'.local? 3 = some (.signed .i32 ((e - 1 : Nat) : Int)) := by
        refine (local?_congr (s := s') (t := R) rfl ?_).trans R3
        show s1.cellId? 3 = R.cellId? 3
        have l : R.cellId? 3 = s5.cellId? 3 := by unfold State.cellId?; rw [locR]
        rw [l]
        exact (cellId_bindLocal_ne s1 _ (by decide)).symm
      have frame' : FreshCellFrame B s' := by
        obtain ⟨x, cl, nx, fx⟩ := frame5.trans frameR; exact ⟨x, cl, nx, fx⟩
      obtain ⟨alen', perm', _, _, _⟩ := id sifted
      refine ⟨condThreshold, bodyThreshold, s, .next, s', condStable, bodyStable, fun h => absurd rfl h.1,
        fun _ => ⟨?_, a', e - 1, by omega, s1L, frame', worldR.trans (world1.trans sW),
          viewsR.trans (views1.trans sV), s'_3, arrR, effR, by rw [alen', length_swapAt]; exact alen,
          perm'.trans swapPerm, sort_after order asymm sinv (by omega) (by omega) sifted⟩⟩
      show counter 3 s' < counter 3 s
      rw [counter_eq s'_3, counter_eq s3]; omega }
  have init : Inv B3 := ⟨a0, n, Nat.le_refl _, rfl, FreshCellFrame.bindLocal B 3 _, rfl, noViews,
    local_bound fB 3 _, arr0, effect0, alen0, List.Perm.refl _, sort_start heap0⟩
  obtain ⟨threshold, completion, final, loopStable, done⟩ := executeTotalWhile measure P _ _ oracle B3 init
  obtain ⟨rfl, fL, fF, fW, fV, a, arr, eff, alen, perm, sorted⟩ := done
  exact ⟨final, a, ⟨threshold, loopStable, fL⟩, fF, fL, fW, fV, arr, eff, alen, perm, sorted⟩

/-! ## The spec -/

/-- `sort(v)` returns `v`, which then represents a sorted permutation of
`xs`; only its storage changed. `2 * len < 2^31` keeps `parent * 2 + 1` in
`sift_down` from overflowing. -/
theorem sort_spec (inst : VecInstance P T ids) (kind : ElemKind P T size) {f sd lt : FunctionId}
    (found : P.function? f = some (sortFn ids T f sd)) (siftFound : P.function? sd = some (siftDownFn T sd lt))
    {ltv : Value → Value → Bool} {vals : List Value} (ltSpec : LtSpec P lt ltv vals)
    (order : NegTrans ltv) (asymm : Asymm ltv)
    {caller : State} (formed : caller.CellsWellFormed) {xs : List Value} {p cap : Nat}
    (rep : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]) xs)
    (small : 2 * xs.length < 2 ^ 31) (sub : ∀ z ∈ xs, z ∈ vals) (stores : ∀ y ∈ xs, ElemStore P T size y)
    (noViews : caller.i32ArrayViews = []) (unique : HeapBlockBasesUnique caller.heap) :
    ∃ after, RunsExpr P caller (.call f
        ([Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]].map Expr.value))
      (.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]) after ∧
      FreshCellFrame caller after ∧ after.world = caller.world ∧
      after.i32ArrayViews = caller.i32ArrayViews ∧
      ∃ ys, ys.Perm xs ∧ Sorted ltv ys ∧
        VecRep P T size ids.vec after.heap (.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]) ys ∧
        HeapRegionWrite caller.heap after.heap p (size * cap) := by
  have target := inst.target
  obtain ⟨_, lenLe, capBound, buffer, reads⟩ := rep.fields
  let vv := Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]
  refine Grow.call (vs := [vv]) (Q := fun H => ∃ ys, ys.Perm xs ∧ Sorted ltv ys ∧
    VecRep P T size ids.vec H vv ys ∧ HeapRegionWrite caller.heap H p (size * cap)) found rfl rfl ?_
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  let E := E0.bindLocal 0 vv
  change Grow P E _ _ _
  have fE : E.CellsWellFormed := f0.bindLocal _ _
  have l0 : E.local? 0 = some vv := local_bound f0 0 _
  obtain ⟨S1, slots, frame⟩ := slots_call inst kind fE l0 capBound buffer
  have fS1 := frame.afterFormed
  let view := Value.rawSlice T (viewAddr T size p cap) cap
  let B1 := S1.bindLocal 1 view
  have fB1 : B1.CellsWellFormed := fS1.bindLocal _ _
  have hB1 : B1.heap = caller.heap := frame.heap
  have b1_0 : B1.local? 0 = some vv := local_kept fS1 _ (by decide) (frame.localFound l0)
  have b1_1 : B1.local? 1 = some view := local_bound fS1 1 _
  have divRun := RunsExpr.binary (operation := .divide) (RunsExpr.field' (j := 1) (RunsExpr.local' b1_0) rfl)
    (RunsExpr.value' (P := P) (S := B1) (.signed .i32 2)) (by decide)
    (by rw [target]; exact eval_i32_div2 (by omega))
  have arr0 : ArrayAt P T size B1.heap p cap xs := fun j jl other within => by
    unfold elt; rw [getD_of_lt jl]; exact reads j jl other (by rw [hB1] at within; exact within)
  obtain ⟨F1, a1, loop1, frame1, F1L, F1W, F1V, arr1, eff1, alen1, perm1, heap1⟩ :=
    build_loop_spec target kind siftFound ltSpec order asymm fB1 (n := xs.length) (xs := xs) (h0 := caller.heap)
      b1_0 rfl b1_1 rfl lenLe small buffer (by rw [hB1]; exact HeapRegionWrite.refl _ unique) arr0 sub stores
      (frame.views.trans noViews)
  have fF1 := FreshCellFrame.after_cellsWellFormed fB1 frame1
  have F1_0 : F1.local? 0 = some vv := local_above frame1 F1L (by decide) b1_0
  have F1_1 : F1.local? 1 = some view := local_above frame1 F1L (by decide) b1_1
  have endRun : RunsExpr P F1 (.field (.local 0) 1) (.signed .i32 (xs.length : Int)) F1 :=
    RunsExpr.field' (j := 1) (RunsExpr.local' F1_0) rfl
  obtain ⟨F2, a2, loop2, frame2, F2L, F2W, F2V, arr2, eff2, alen2, perm2, sorted⟩ :=
    extract_loop_spec target kind siftFound ltSpec order asymm fF1 F1_1 alen1 lenLe small buffer eff1 arr1 heap1
      (fun z m => sub z (perm1.mem_iff.mp m)) (fun y m => stores y (perm1.mem_iff.mp m)) F1V
  have F2_0 : F2.local? 0 = some vv := local_above frame2 F2L (by decide) F1_0
  have ret : RunsStmt P F2 (.returnValue (some (.local 0))) (.returned (some vv)) F2 :=
    RunsStmt.returnValue (RunsExpr.local' F2_0)
  have run3 := RunsStmt.letLocal (type := i32Ty) (id := 3) endRun (RunsStmt.sequenceNext loop2 ret)
  have run2 := RunsStmt.letLocal (type := i32Ty) (id := 2) divRun (RunsStmt.sequenceNext loop1 run3)
  have run1 := RunsStmt.letLocal (type := .slice T) (id := 1) slots run2
  have extB1 : Ext E B1 := (Ext.ofPure frame).trans (Ext.bindLocal fS1 1 view)
  have extF2 : Ext E F2 := ⟨fE, extB1.cells.trans (frame1.trans frame2), F2W.trans (F1W.trans frame.world),
    F2V.trans noViews.symm⟩
  refine ⟨_, run1, ((extF2.restore F1).restore B1).restore S1, ?_⟩
  show ∃ ys, ys.Perm xs ∧ Sorted ltv ys ∧ VecRep P T size ids.vec F2.heap vv ys ∧
    HeapRegionWrite caller.heap F2.heap p (size * cap)
  refine ⟨a2, perm2.trans perm1, sorted, ⟨p, cap, by rw [alen2], by rw [alen2]; exact lenLe, capBound,
    fun positive => (buffer positive).afterWrite eff2, fun j jInside other within => ?_⟩, eff2⟩
  have read := arr2 j jInside other within
  unfold elt at read; rw [getD_of_lt jInside] at read
  exact read

#print axioms build_loop_spec
#print axioms extract_loop_spec
#print axioms sort_spec

end Lanius.Std
