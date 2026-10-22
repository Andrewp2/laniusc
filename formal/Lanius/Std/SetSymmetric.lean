import Lanius.Std.SetAlgebra

/-! # `try_symmetric_difference`

It counts the items of `left` not in `right` and of `right` not in `left`,
checks that the sum fits `MAX_CAPACITY`, reserves that many slots, and
appends the first group, then the second. With room in the heap, the
result is a fresh set of `whereIn eqv ys false xs ++ whereIn eqv xs false ys`. -/

namespace Lanius.Std

open Lanius Lanius.Core Lanius.Semantics Lanius.Memory

variable {P : Program} {T : Ty} {ids : VecIds} {g : GrowIds} {mo : MoreIds} {size : Nat}

/-- Locals 0 `left`, 1 `right`, 2 `from_left`, 3 `from_right`, 4 `count`,
5 `output`. -/
def setSymDiffFn (ids : VecIds) (sid : TypeId) (f cw rf aw sn : FunctionId) : Function where
  id := f
  parameters := [(0, setTy sid), (1, setTy sid)]
  returnType := setTy sid
  body := some <|
    .letLocal 2 i32Ty (.call cw [.local 0, .local 1, .value (.boolean false)])
    (.letLocal 3 i32Ty (.call cw [.local 1, .local 0, .value (.boolean false)])
    (.sequence
      (.ifThenElse (.binary .greater (.local 3) (.binary .subtract (int 2147483647) (.local 2)))
        (.returnValue (some (.call sn []))) .skip)
    (.letLocal 4 i32Ty (.binary .add (.local 2) (.local 3))
    (.letLocal 5 (vecTy ids) (.call rf [.local 4])
    (.sequence
      (.ifThenElse (.binary .less (.call ids.capacity [.local 5]) (.local 4)) (.returnValue (some (.call sn []))) .skip)
    (.sequence
      (.expression (.assign .set (.local 5) (.call aw [.local 5, .local 0, .local 1, .value (.boolean false)])))
      (.returnValue (some (.structValue sid [.call aw [.local 5, .local 1, .local 0, .value (.boolean false)]])))))))))

theorem local_cell_ne_next {S : State} (formed : S.CellsWellFormed) {id : VarId} {v : Value}
    (found : S.local? id = some v) : S.cellId? id ≠ some S.nextCell := by
  intro cell
  unfold State.local? at found
  rw [cell] at found
  simp [State.cell?, formed.cellEntry_nextCell] at found

/-- `try_symmetric_difference(left, right)` when the heap has room for both
groups. -/
theorem setSymDiff_spec (more : MoreInstance P T ids g mo) (kind : ElemKind P T size) {sid : TypeId}
    {si : SetIds} (inst : SetInstance P T ids sid si) {f cw rf aw sn : FunctionId}
    (found : P.function? f = some (setSymDiffFn ids sid f cw rf aw sn))
    (cwFound : P.function? cw = some (setCountWhereFn sid cw si.sl si.sc si.atf))
    (rfFound : P.function? rf = some (setReservedForFn ids mo rf))
    (awFound : P.function? aw = some (setAppendWhereFn ids g T sid aw si))
    {eqv : Value → Value → Bool} {vals : List Value} (eqSpec : EqSpec P si.eq eqv vals)
    {caller : State} (formed : caller.CellsWellFormed) {xs ys : List Value} {p cap r rc : Nat}
    (repL : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]) xs)
    (repR : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer r, .signed .i32 ys.length, .signed .i32 rc]) ys)
    (subL : ∀ z ∈ xs, z ∈ vals) (subR : ∀ z ∈ ys, z ∈ vals)
    (storesL : ∀ y ∈ xs, ElemStore P T size y) (storesR : ∀ y ∈ ys, ElemStore P T size y)
    (alloc : 0 < (whereIn eqv ys false xs ++ whereIn eqv xs false ys).length →
      size * (whereIn eqv ys false xs ++ whereIn eqv xs false ys).length ≤ 2147483647 ∧
      (∃ budget : Option Nat, consumeBudget caller.heap.remaining
        (size * (whereIn eqv ys false xs ++ whereIn eqv xs false ys).length) = some budget) ∧
      caller.heap.allocationAddress 8 + size * (whereIn eqv ys false xs ++ whereIn eqv xs false ys).length < 2 ^ 64)
    (below : HeapBlocksBelowNext caller.heap) (unique : HeapBlockBasesUnique caller.heap)
    (apart : HeapApart caller.heap) (noViews : caller.i32ArrayViews = []) :
    ∃ (after : State) (q m : Nat), RunsExpr P caller (.call f
        ([Value.structure sid [.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]],
          .structure sid [.structure ids.vec [.pointer r, .signed .i32 ys.length, .signed .i32 rc]]].map Expr.value))
      (.structure sid [.structure ids.vec
        [.pointer q, .signed .i32 (whereIn eqv ys false xs ++ whereIn eqv xs false ys).length, .signed .i32 m]])
        after ∧
      FreshCellFrame caller after ∧ after.world = caller.world ∧ after.i32ArrayViews = caller.i32ArrayViews ∧
      (0 < m → caller.heap.nextAddress ≤ q) ∧
      AlgebraOut P T size ids.vec caller.heap q m (whereIn eqv ys false xs ++ whereIn eqv xs false ys)
        after.heap := by
  have positive : 0 < size := kind.size_pos
  have target := inst.vec.target
  obtain ⟨_, _, _, bufL, _⟩ := repL.fields
  obtain ⟨_, _, _, bufR, _⟩ := repR.fields
  let W1 := whereIn eqv ys false xs
  let W2 := whereIn eqv xs false ys
  let a := W1.length
  let b := W2.length
  let n := a + b
  have nLen : (W1 ++ W2).length = n := List.length_append
  have nMax : n ≤ 2147483647 := by
    by_cases zero : n = 0
    · omega
    · have := (alloc (by rw [nLen]; omega)).1
      rw [nLen] at this
      have : n ≤ size * n := Nat.le_mul_of_pos_left n positive
      omega
  let vvL := Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]
  let vvR := Value.structure ids.vec [.pointer r, .signed .i32 ys.length, .signed .i32 rc]
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  have f1 := f0.bindLocal 0 (.structure sid [vvL])
  let E := (E0.bindLocal 0 (.structure sid [vvL])).bindLocal 1 (.structure sid [vvR])
  have fE : E.CellsWellFormed := f1.bindLocal _ _
  have l1 : E.local? 1 = some (.structure sid [vvR]) := local_bound f1 1 _
  have l0 : E.local? 0 = some (.structure sid [vvL]) := local_kept f1 _ (by decide) (local_bound f0 0 _)
  have disjoint := apart.disjoint unique
  -- from_left = count_where(left, right, false)
  obtain ⟨c1, count1, pc1⟩ := setCountWhere_spec inst.vec kind cwFound inst.sl inst.sc inst.vc inst.indexOf
    inst.atf inst.asl inst.pf eqSpec fE (caller := E) repL repR subL subR disjoint false
  have call1 := callArgs (RunsExprs.three (RunsExpr.local' l0) (RunsExpr.local' l1) (RunsExpr.value' _)) count1
  have fc1 := pc1.afterFormed
  let S2 := c1.bindLocal 2 (.signed .i32 a)
  have fS2 : S2.CellsWellFormed := fc1.bindLocal _ _
  have t2 : S2.local? 2 = some (.signed .i32 a) := local_bound fc1 2 _
  have t1 : S2.local? 1 = some (.structure sid [vvR]) := local_kept fc1 _ (by decide) (pc1.localFound l1)
  have t0 : S2.local? 0 = some (.structure sid [vvL]) := local_kept fc1 _ (by decide) (pc1.localFound l0)
  -- from_right = count_where(right, left, false)
  obtain ⟨c2, count2, pc2⟩ := setCountWhere_spec inst.vec kind cwFound inst.sl inst.sc inst.vc inst.indexOf
    inst.atf inst.asl inst.pf eqSpec fS2 (caller := S2) (by rw [show S2.heap = caller.heap from pc1.heap]; exact repR)
    (by rw [show S2.heap = caller.heap from pc1.heap]; exact repL) subR subL
    (by rw [show S2.heap = caller.heap from pc1.heap]; exact disjoint) false
  have call2 := callArgs (RunsExprs.three (RunsExpr.local' t1) (RunsExpr.local' t0) (RunsExpr.value' _)) count2
  have fc2 := pc2.afterFormed
  let S3 := c2.bindLocal 3 (.signed .i32 b)
  have fS3 : S3.CellsWellFormed := fc2.bindLocal _ _
  have u3 : S3.local? 3 = some (.signed .i32 b) := local_bound fc2 3 _
  have u2 : S3.local? 2 = some (.signed .i32 a) := local_kept fc2 _ (by decide) (pc2.localFound t2)
  have u1 : S3.local? 1 = some (.structure sid [vvR]) := local_kept fc2 _ (by decide) (pc2.localFound t1)
  have u0 : S3.local? 0 = some (.structure sid [vvL]) := local_kept fc2 _ (by decide) (pc2.localFound t0)
  -- from_right > MAX_CAPACITY - from_left
  have guard1 := RunsExpr.binary (operation := .greater) (program := P) (RunsExpr.local' u3)
    (RunsExpr.binary (operation := .subtract) (RunsExpr.value' (.signed .i32 2147483647)) (RunsExpr.local' u2)
      (by decide) (by rw [target]; exact eval_i32_sub (by omega) (by omega))) (by decide) (eval_i32_gt _ _ _)
  rw [show decide ((b : Int) > 2147483647 - (a : Int)) = false by simp; omega] at guard1
  -- count = from_left + from_right
  have sum := RunsExpr.binary (operation := .add) (program := P) (RunsExpr.local' u2) (RunsExpr.local' u3)
    (by decide) (by rw [target]; exact eval_i32_add (by omega) (by omega))
  rw [show (a : Int) + (b : Int) = ((a + b : Nat) : Int) by omega] at sum
  let S4 := S3.bindLocal 4 (.signed .i32 n)
  have fS4 : S4.CellsWellFormed := fS3.bindLocal _ _
  have v4 : S4.local? 4 = some (.signed .i32 n) := local_bound fS3 4 _
  have v1 : S4.local? 1 = some (.structure sid [vvR]) := local_kept fS3 _ (by decide) u1
  have v0 : S4.local? 0 = some (.structure sid [vvL]) := local_kept fS3 _ (by decide) u0
  have hS4 : S4.heap = caller.heap := pc2.heap.trans pc1.heap
  have vS4 : S4.i32ArrayViews = [] := (pc2.views.trans pc1.views).trans noViews
  -- the rest, from the run of reserved_for(count)
  have tail : ∀ (S5' : State) (q m : Nat),
      RunsExpr P S4 (.call rf [.local 4]) (.structure ids.vec [.pointer q, .signed .i32 0, .signed .i32 m]) S5' →
      Ext S4 S5' → S5'.i32ArrayViews = [] → n ≤ m →
      VecRep P T size ids.vec S5'.heap
        (.structure ids.vec [.pointer q, .signed .i32 ([] : List Value).length, .signed .i32 m]) [] →
      VecRep P T size ids.vec S5'.heap vvL xs → VecRep P T size ids.vec S5'.heap vvR ys →
      (0 < cap → (p + size * cap ≤ q ∨ q + size * m ≤ p)) →
      (0 < rc → (r + size * rc ≤ q ∨ q + size * m ≤ r)) →
      HeapBlocksBelowNext S5'.heap → HeapBlockBasesUnique S5'.heap → HeapApart S5'.heap →
      Kept caller.heap S5'.heap q (size * m) →
      Grow P S4 (.letLocal 5 (vecTy ids) (.call rf [.local 4])
        (.sequence
          (.ifThenElse (.binary .less (.call ids.capacity [.local 5]) (.local 4)) (.returnValue (some (.call sn []))) .skip)
        (.sequence
          (.expression (.assign .set (.local 5) (.call aw [.local 5, .local 0, .local 1, .value (.boolean false)])))
          (.returnValue (some (.structValue sid [.call aw [.local 5, .local 1, .local 0, .value (.boolean false)]]))))))
        (.returned (some (.structure sid [.structure ids.vec
          [.pointer q, .signed .i32 (W1 ++ W2).length, .signed .i32 m]])))
        (AlgebraOut P T size ids.vec caller.heap q m (W1 ++ W2)) := by
    intro S5' q m rfRun ext5 views5 nm repO repL5 repR5 apL apR below5 unique5 apart5 kept5
    have loc5 : S5'.locals = S4.locals := rfRun.choose_spec.2
    have f5' := ext5.afterFormed
    let outv := Value.structure ids.vec [.pointer q, .signed .i32 0, .signed .i32 m]
    let S5 := S5'.bindLocal 5 outv
    have fS5 : S5.CellsWellFormed := f5'.bindLocal _ _
    have w0' : S5'.local? 0 = some (.structure sid [vvL]) := ext5.cells.localFound loc5 0 _ v0
    have w1' : S5'.local? 1 = some (.structure sid [vvR]) := ext5.cells.localFound loc5 1 _ v1
    have w5 : S5.local? 5 = some outv := local_bound f5' 5 _
    have w4 : S5.local? 4 = some (.signed .i32 n) := local_kept f5' _ (by decide) (ext5.cells.localFound loc5 4 _ v4)
    have w1 : S5.local? 1 = some (.structure sid [vvR]) := local_kept f5' _ (by decide) w1'
    have w0 : S5.local? 0 = some (.structure sid [vvL]) := local_kept f5' _ (by decide) w0'
    -- capacity(output) < count
    obtain ⟨c6, capRun, pc6⟩ := capacity_exact inst.vec fS5 q (.signed .i32 0) m
    have cond := RunsExpr.binary (operation := .less) (callArgs (RunsExprs.one (RunsExpr.local' w5)) capRun)
      (RunsExpr.local' (pc6.localFound w4)) (by decide) (eval_i32_lt _ _ _)
    rw [show decide ((m : Int) < (n : Int)) = false by simp; omega] at cond
    have hc6 : c6.heap = S5'.heap := pc6.heap
    have fc6 := pc6.afterFormed
    have vc6 : c6.i32ArrayViews = [] := pc6.views.trans views5
    have x5 := pc6.localFound w5
    have x0 := pc6.localFound w0
    have x1 := pc6.localFound w1
    -- output = append_where(output, left, right, false)
    obtain ⟨R, append1, cellsR, worldR, viewsR, repR1, keptR1, belowR1, uniqueR1, apartR1⟩ :=
      setAppendWhere_spec more.grow kind inst awFound eqSpec fc6 (acc := [])
        (by rw [hc6]; exact repO) (by rw [hc6]; exact repL5) (by rw [hc6]; exact repR5) apL apR false
        (by show 0 + a ≤ m; omega) subL subR storesL (by rw [hc6]; exact below5) (by rw [hc6]; exact unique5)
        (by rw [hc6]; exact apart5) vc6
    rw [hc6] at keptR1
    have right := callArgs (RunsExprs.cons (RunsExpr.local' x5)
      (RunsExprs.three (RunsExpr.local' x0) (RunsExpr.local' x1) (RunsExpr.value' _))) append1
    have rLocals : R.locals = c6.locals := right.choose_spec.2
    have cell5 : c6.cellId? 5 = some S5'.nextCell := by
      have : c6.locals = S5.locals := pc6.locals
      simp [State.cellId?, this, S5, State.bindLocal, State.bindCell]
    let nv := Value.structure ids.vec [.pointer q, .signed .i32 ([] ++ W1).length, .signed .i32 m]
    obtain ⟨A, assignRun, assigned, _⟩ := RunsExpr.assignCellAfter (before := c6) cell5
      (cellEntry_of_local c6 5 _ outv cell5 x5) right (Or.inr (viewsR.trans vc6))
    have cR5 : R.cellId? 5 = some S5'.nextCell := by unfold State.cellId? at cell5 ⊢; rw [rLocals]; exact cell5
    have cellA := assignLocal_assignCell 5 S5'.nextCell nv cR5 assigned
    have frameR : FreshCellFrame S5' R := ((FreshCellFrame.bindLocal S5' 5 outv).trans pc6.cells).trans cellsR
    obtain ⟨frameA, localsA, heapA, worldA, viewsA⟩ := FreshCellFrame.assignFresh f5'
      (FreshCellFrame.after_cellsWellFormed f5' frameR) frameR (Nat.le_refl _) cellA
    have fA := FreshCellFrame.after_cellsWellFormed f5' frameA
    have sameCell : ∀ id, id ≠ 5 → R.cellId? id = S5'.cellId? id := fun id ne => by
      have : R.cellId? id = S5.cellId? id := by unfold State.cellId?; rw [rLocals, pc6.locals]
      rw [this, cellId_bindLocal_ne S5' _ (Ne.symm ne)]
    have y5 : A.local? 5 = some nv := assignLocal_finds_assigned 5 S5'.nextCell nv cR5 assigned
    have y0 : A.local? 0 = some (.structure sid [vvL]) :=
      assignCell_preserves_other_local_of_cellId 0 S5'.nextCell nv cellA (cellsR.localFound rLocals 0 _ x0)
        (by rw [sameCell 0 (by decide)]; exact local_cell_ne_next f5' w0')
    have y1 : A.local? 1 = some (.structure sid [vvR]) :=
      assignCell_preserves_other_local_of_cellId 1 S5'.nextCell nv cellA (cellsR.localFound rLocals 1 _ x1)
        (by rw [sameCell 1 (by decide)]; exact local_cell_ne_next f5' w1')
    -- return Set { items: append_where(output, right, left, false) }
    have hA : A.heap = R.heap := heapA
    have repLA : VecRep P T size ids.vec A.heap vvL xs := by
      rw [hA]; exact repL5.keptApart keptR1 apL positive
    have repRA : VecRep P T size ids.vec A.heap vvR ys := by
      rw [hA]; exact repR5.keptApart keptR1 apR positive
    obtain ⟨F, append2, cellsF, worldF, viewsF, repF, keptF, belowF, uniqueF, apartF⟩ :=
      setAppendWhere_spec more.grow kind inst awFound eqSpec fA (acc := W1) (by rw [hA]; exact repR1)
        repRA repLA apR apL false (by show W1.length + b ≤ m; omega) subR subL storesR
        (by rw [hA]; exact belowR1) (by rw [hA]; exact uniqueR1) (by rw [hA]; exact apartR1)
        (viewsA.trans (viewsR.trans vc6))
    rw [hA] at keptF
    have retRun := RunsStmt.returnValue (RunsExpr.structValue (typeId := sid) (RunsExprs.cons
      (callArgs (RunsExprs.cons (RunsExpr.local' y5) (RunsExprs.three (RunsExpr.local' y1) (RunsExpr.local' y0)
        (RunsExpr.value' _))) append2) RunsExprs.nil))
    have bodyRun := RunsStmt.sequenceNext (RunsStmt.ifThenElseFalse (thenBranch := .returnValue (some (.call sn []))) cond (RunsStmt.skip P c6))
      (RunsStmt.sequenceNext (RunsStmt.expression assignRun) retRun)
    have frameF : FreshCellFrame S5' F := frameA.trans cellsF
    exact ⟨restoreLocals S5' F, RunsStmt.letLocal rfRun bodyRun,
      (ext5.trans ⟨f5', frameF, (worldF.trans (worldA.trans (worldR.trans (pc6.world)))),
        viewsF.trans (viewsA.trans (viewsR.trans (pc6.views)))⟩).restore S5',
      repF, (kept5.trans keptR1).trans keptF, belowF, uniqueF, apartF⟩
  have whole : ∀ (S5' : State) (q m : Nat) (body : Grow P S4 _ _ (AlgebraOut P T size ids.vec caller.heap q m (W1 ++ W2))),
      (0 < m → caller.heap.nextAddress ≤ q) →
      ∃ (after : State) (q m : Nat), RunsExpr P caller (.call f
          ([Value.structure sid [vvL], .structure sid [vvR]].map Expr.value))
        (.structure sid [.structure ids.vec [.pointer q, .signed .i32 (W1 ++ W2).length, .signed .i32 m]]) after ∧
        FreshCellFrame caller after ∧ after.world = caller.world ∧ after.i32ArrayViews = caller.i32ArrayViews ∧
        (0 < m → caller.heap.nextAddress ≤ q) ∧ AlgebraOut P T size ids.vec caller.heap q m (W1 ++ W2) after.heap :=
    fun _ q m body newer => by
      obtain ⟨after, call, cells, world, views, out⟩ := Grow.call
        (vs := [.structure sid [vvL], .structure sid [vvR]])
        (bindings := [(0, .structure sid [vvL]), (1, .structure sid [vvR])])
        (Q := AlgebraOut P T size ids.vec caller.heap q m (W1 ++ W2)) found rfl rfl
        (Grow.letRun call1 (Ext.ofPure pc1) (Grow.letRun call2 (Ext.ofPure pc2)
          (Grow.guardSkip guard1 (Ext.refl fS3) (Grow.letRun sum (Ext.refl fS3) body))))
      exact ⟨after, q, m, call, cells, world, views, newer, out⟩
  by_cases zero : n = 0
  · obtain ⟨S5', run, pure5⟩ := setReservedFor_empty_spec more rfFound fS4 (n := (n : Int)) (by omega)
    have h5 : S5'.heap = caller.heap := pure5.heap.trans hS4
    have k5 : Kept caller.heap S5'.heap 0 (size * 0) := by rw [h5]; exact Kept.same _ _ _
    exact whole S5' 0 0 (tail S5' 0 0 (callArgs (RunsExprs.one (RunsExpr.local' v4)) run) (Ext.ofPure pure5)
      (pure5.views.trans vS4) (by omega) (VecRep.emptyAt P T size ids.vec _) (by rw [h5]; exact repL)
      (by rw [h5]; exact repR) (fun _ => Or.inr (by omega)) (fun _ => Or.inr (by omega)) (by rw [h5]; exact below)
      (by rw [h5]; exact unique) (by rw [h5]; exact apart) k5) (fun none => absurd none (Nat.lt_irrefl 0))
  · have npos : 0 < n := Nat.pos_of_ne_zero zero
    obtain ⟨fits, ⟨budget, available⟩, room⟩ := alloc (by rw [nLen]; exact npos)
    rw [nLen] at fits available room
    let q := caller.heap.allocationAddress 8
    have fresh : caller.heap.nextAddress ≤ q := Heap.allocationAddress_ge _ (by decide)
    obtain ⟨S5', run, cells5, world5, views5, grown⟩ := setReservedFor_spec more kind rfFound fS4 npos fits
      (by rw [hS4]; exact available) (by rw [hS4]; exact room) (by rw [hS4]; exact below)
      (by rw [hS4]; exact unique) vS4
    rw [hS4] at run grown
    obtain ⟨rep1, kept1, below1, unique1, _, apart1⟩ := grown
    have oldL : 0 < cap → p + size * cap ≤ q := fun pos => by
      have := ((bufL pos).2.1).belowNext (Nat.mul_pos positive pos) below
      dsimp only [Lanius.Address] at *; omega
    have oldR : 0 < rc → r + size * rc ≤ q := fun pos => by
      have := ((bufR pos).2.1).belowNext (Nat.mul_pos positive pos) below
      dsimp only [Lanius.Address] at *; omega
    exact whole S5' q n (tail S5' q n (callArgs (RunsExprs.one (RunsExpr.local' v4)) run)
      ⟨fS4, cells5, world5, views5⟩ (views5.trans vS4) (Nat.le_refl _) rep1
      (repL.keptApart kept1 (fun _ => Or.inr (Nat.zero_le _)) positive)
      (repR.keptApart kept1 (fun _ => Or.inr (Nat.zero_le _)) positive)
      (fun pos => Or.inl (oldL pos)) (fun pos => Or.inl (oldR pos)) below1 unique1 (apart1 apart)
      (kept1.ofNone q (size * n))) (fun _ => fresh)

#print axioms setSymDiff_spec

end Lanius.Std
