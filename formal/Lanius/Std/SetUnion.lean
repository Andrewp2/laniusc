import Lanius.Std.SetSymmetric
import Lanius.Std.VecExtend

/-! # `try_union`

It counts the items of `right` not in `left`, checks that `len(left)` plus
that fits `MAX_CAPACITY`, reserves that many slots, copies `left` in with
`try_extend_from_slice`, then appends the counted items of `right`. With
room in the heap, the result is a fresh set of
`xs ++ whereIn eqv xs false ys`. -/

namespace Lanius.Std

open Lanius Lanius.Core Lanius.Semantics Lanius.Memory

variable {P : Program} {T : Ty} {ids : VecIds} {g : GrowIds} {mo : MoreIds} {size : Nat}

/-- Locals 0 `left`, 1 `right`, 2 `extra`, 3 `count`, 4 `output`. -/
def setUnionFn (ids : VecIds) (sid : TypeId) (f cw rf aw sn ext : FunctionId) (si : SetIds) : Function where
  id := f
  parameters := [(0, setTy sid), (1, setTy sid)]
  returnType := setTy sid
  body := some <|
    .letLocal 2 i32Ty (.call cw [.local 1, .local 0, .value (.boolean false)])
    (.sequence
      (.ifThenElse (.binary .greater (.local 2) (.binary .subtract (int 2147483647) (.call si.sl [.local 0])))
        (.returnValue (some (.call sn []))) .skip)
    (.letLocal 3 i32Ty (.binary .add (.call si.sl [.local 0]) (.local 2))
    (.letLocal 4 (vecTy ids) (.call rf [.local 3])
    (.sequence
      (.ifThenElse (.binary .less (.call ids.capacity [.local 4]) (.local 3)) (.returnValue (some (.call sn []))) .skip)
    (.sequence
      (.expression (.assign .set (.local 4)
        (.call ext [.local 4, .call si.asl [.field (.local 0) 0], .call si.sl [.local 0]])))
      (.returnValue (some (.structValue sid [.call aw [.local 4, .local 1, .local 0, .value (.boolean false)]]))))))))

/-- A vector's items, read through its prefix view. -/
theorem VecRep.sliceRep {vec : TypeId} {h : Heap} {p cap : Nat} {xs : List Value}
    (rep : VecRep P T size vec h (.structure vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]) xs) :
    SliceRep P T size h (prefixAddr T size p cap xs.length) xs.length (slotLo T size p cap) xs := by
  obtain ⟨_, lenLe, _, _, reads⟩ := rep.fields
  intro j inside other within
  have addr : prefixAddr T size p cap xs.length = viewAddr T size p cap := by
    unfold prefixAddr; rw [if_neg (by omega)]
  rw [addr, readRawSliceIndex_shorter inside lenLe]
  exact reads j inside other within

/-- `try_extend_from_slice(v, items, 0)` returns `v`. -/
theorem tryExtend_none_spec (inst : VecInstance P T ids) {f : FunctionId}
    (found : P.function? f = some (tryExtendFn ids g T f)) {caller : State} (formed : caller.CellsWellFormed)
    {ptr cap : Value} {len : Nat} (small : len ≤ 2147483647) (sA sL : Nat) :
    ∃ after, RunsExpr P caller (.call f
        ([Value.structure ids.vec [ptr, .signed .i32 len, cap], .rawSlice T sA sL, .signed .i32 0].map Expr.value))
      (.structure ids.vec [ptr, .signed .i32 len, cap]) after ∧ PureFrame caller after := by
  refine PureRun.call found rfl rfl formed ?_
  let vv := Value.structure ids.vec [ptr, .signed .i32 len, cap]
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  have f1 := f0.bindLocal 0 vv
  have f2 := f1.bindLocal 1 (.rawSlice T sA sL)
  let E := ((E0.bindLocal 0 vv).bindLocal 1 (.rawSlice T sA sL)).bindLocal 2 (.signed .i32 0)
  change PureRun P E _ _
  have fE : E.CellsWellFormed := f2.bindLocal _ _
  have l2 : E.local? 2 = some (.signed .i32 0) := local_bound f2 2 _
  have l0 : E.local? 0 = some vv :=
    local_kept f2 _ (by decide) (local_kept f1 _ (by decide) (local_bound f0 0 _))
  have le := RunsExpr.binary (operation := .lessEqual) (program := P) (RunsExpr.local' l2)
    (RunsExpr.value' (.signed .i32 0)) (by decide) (eval_i32_le _ _ _)
  rw [show decide ((0 : Int) ≤ 0) = true by decide] at le
  exact PureRun.guardTaken (RunsExpr.logicalOrTrue' le) (PureRun.ret fE (RunsExpr.local' l0)) (by simp)

/-- `try_extend_from_slice(output, as_slice(v), len(v))` into an empty
`output` with room for `v`'s items, whose storage is apart from `v`'s. -/
theorem extendFresh_spec (inst : VecInstance P T ids) (kind : ElemKind P T size) {ext : FunctionId}
    (found : P.function? ext = some (tryExtendFn ids g T ext))
    {caller : State} (formed : caller.CellsWellFormed) {xs : List Value} {q m p cap : Nat}
    (repO : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer q, .signed .i32 ([] : List Value).length, .signed .i32 m]) [])
    (repL : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]) xs)
    (room : xs.length ≤ m) (apartL : 0 < cap → (p + size * cap ≤ q ∨ q + size * m ≤ p))
    (stores : ∀ y ∈ xs, ElemStore P T size y)
    (below : HeapBlocksBelowNext caller.heap) (unique : HeapBlockBasesUnique caller.heap)
    (noViews : caller.i32ArrayViews = []) :
    ∃ after, RunsExpr P caller (.call ext
        ([Value.structure ids.vec [.pointer q, .signed .i32 0, .signed .i32 m],
          .rawSlice T (prefixAddr T size p cap xs.length) xs.length, .signed .i32 xs.length].map Expr.value))
      (.structure ids.vec [.pointer q, .signed .i32 xs.length, .signed .i32 m]) after ∧
      FreshCellFrame caller after ∧ after.world = caller.world ∧ after.i32ArrayViews = caller.i32ArrayViews ∧
      VecRep P T size ids.vec after.heap (.structure ids.vec [.pointer q, .signed .i32 xs.length, .signed .i32 m]) xs ∧
      Kept caller.heap after.heap q (size * m) ∧ HeapBlocksBelowNext after.heap ∧
      HeapBlockBasesUnique after.heap ∧ (HeapApart caller.heap → HeapApart after.heap) := by
  obtain ⟨_, lenLe, _, _, _⟩ := repL.fields
  obtain ⟨_, _, mBound, _, _⟩ := repO.fields
  cases xs with
  | nil =>
      obtain ⟨after, run, pure⟩ := tryExtend_none_spec (g := g) inst found formed (ptr := .pointer q)
        (cap := .signed .i32 m) (len := 0) (by omega) (prefixAddr T size p cap 0) 0
      have h : after.heap = caller.heap := pure.heap
      exact ⟨after, run, pure.cells, pure.world, pure.views, by rw [h]; exact repO, by rw [h]; exact Kept.same _ _ _,
        by rw [h]; exact below, by rw [h]; exact unique, fun ap => by rw [h]; exact ap⟩
  | cons x rest =>
      have positive : 0 < size := kind.size_pos
      obtain ⟨after, run, cells, world, views, rep, kept, below', unique', apart', _⟩ :=
        tryExtend_room_spec (g := g) inst kind found formed (xs := []) (ys := x :: rest) repO (Nat.succ_pos _)
          (by show 0 + (rest.length + 1) ≤ m; simp only [List.length_cons] at room; omega) repL.sliceRep
          (fun j inside => by
            have := slot_inside (T := T) (size := size) (p := p) (show j < cap by omega)
            have := apartL (by omega)
            omega)
          stores below unique noViews
      exact ⟨after, run, cells, world, views, rep, kept, below', unique', apart'⟩

/-- `try_union(left, right)` when the heap has room for the union. -/
theorem setUnion_spec (more : MoreInstance P T ids g mo) (kind : ElemKind P T size) {sid : TypeId}
    {si : SetIds} (inst : SetInstance P T ids sid si) {f cw rf aw sn ext : FunctionId}
    (found : P.function? f = some (setUnionFn ids sid f cw rf aw sn ext si))
    (cwFound : P.function? cw = some (setCountWhereFn sid cw si.sl si.sc si.atf))
    (rfFound : P.function? rf = some (setReservedForFn ids mo rf))
    (awFound : P.function? aw = some (setAppendWhereFn ids g T sid aw si))
    (extFound : P.function? ext = some (tryExtendFn ids g T ext))
    {eqv : Value → Value → Bool} {vals : List Value} (eqSpec : EqSpec P si.eq eqv vals)
    {caller : State} (formed : caller.CellsWellFormed) {xs ys : List Value} {p cap r rc : Nat}
    (repL : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]) xs)
    (repR : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer r, .signed .i32 ys.length, .signed .i32 rc]) ys)
    (subL : ∀ z ∈ xs, z ∈ vals) (subR : ∀ z ∈ ys, z ∈ vals)
    (storesL : ∀ y ∈ xs, ElemStore P T size y) (storesR : ∀ y ∈ ys, ElemStore P T size y)
    (alloc : 0 < (xs ++ whereIn eqv xs false ys).length →
      size * (xs ++ whereIn eqv xs false ys).length ≤ 2147483647 ∧
      (∃ budget : Option Nat, consumeBudget caller.heap.remaining
        (size * (xs ++ whereIn eqv xs false ys).length) = some budget) ∧
      caller.heap.allocationAddress 8 + size * (xs ++ whereIn eqv xs false ys).length < 2 ^ 64)
    (below : HeapBlocksBelowNext caller.heap) (unique : HeapBlockBasesUnique caller.heap)
    (apart : HeapApart caller.heap) (noViews : caller.i32ArrayViews = []) :
    ∃ (after : State) (q m : Nat), RunsExpr P caller (.call f
        ([Value.structure sid [.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]],
          .structure sid [.structure ids.vec [.pointer r, .signed .i32 ys.length, .signed .i32 rc]]].map Expr.value))
      (.structure sid [.structure ids.vec
        [.pointer q, .signed .i32 (xs ++ whereIn eqv xs false ys).length, .signed .i32 m]]) after ∧
      FreshCellFrame caller after ∧ after.world = caller.world ∧ after.i32ArrayViews = caller.i32ArrayViews ∧
      (0 < m → caller.heap.nextAddress ≤ q) ∧
      AlgebraOut P T size ids.vec caller.heap q m (xs ++ whereIn eqv xs false ys) after.heap := by
  have positive : 0 < size := kind.size_pos
  have target := inst.vec.target
  obtain ⟨_, _, _, bufL, _⟩ := repL.fields
  obtain ⟨_, _, _, bufR, _⟩ := repR.fields
  let W2 := whereIn eqv xs false ys
  let b := W2.length
  let n := xs.length + b
  have nLen : (xs ++ W2).length = n := List.length_append
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
  -- extra = count_where(right, left, false)
  obtain ⟨c1, count1, pc1⟩ := setCountWhere_spec inst.vec kind cwFound inst.sl inst.sc inst.vc inst.indexOf
    inst.atf inst.asl inst.pf eqSpec fE (caller := E) repR repL subR subL disjoint false
  have call1 := callArgs (RunsExprs.three (RunsExpr.local' l1) (RunsExpr.local' l0) (RunsExpr.value' _)) count1
  have fc1 := pc1.afterFormed
  let S2 := c1.bindLocal 2 (.signed .i32 b)
  have fS2 : S2.CellsWellFormed := fc1.bindLocal _ _
  have t2 : S2.local? 2 = some (.signed .i32 b) := local_bound fc1 2 _
  have t1 : S2.local? 1 = some (.structure sid [vvR]) := local_kept fc1 _ (by decide) (pc1.localFound l1)
  have t0 : S2.local? 0 = some (.structure sid [vvL]) := local_kept fc1 _ (by decide) (pc1.localFound l0)
  have hS2 : S2.heap = caller.heap := pc1.heap
  -- extra > MAX_CAPACITY - len(left)
  obtain ⟨d1, len1, pd1⟩ := setLen_spec inst.vec inst.sl fS2 (by rw [hS2]; exact repL)
  have guard1 := RunsExpr.binary (operation := .greater) (program := P) (RunsExpr.local' t2)
    (RunsExpr.binary (operation := .subtract) (RunsExpr.value' (.signed .i32 2147483647))
      (callArgs (RunsExprs.one (RunsExpr.local' t0)) len1)
      (by decide) (by rw [target]; exact eval_i32_sub (by omega) (by omega))) (by decide) (eval_i32_gt _ _ _)
  rw [show decide ((b : Int) > 2147483647 - (xs.length : Int)) = false by simp; omega] at guard1
  have fd1 := pd1.afterFormed
  have hd1 : d1.heap = caller.heap := pd1.heap.trans hS2
  -- count = len(left) + extra
  obtain ⟨d2, len2, pd2⟩ := setLen_spec inst.vec inst.sl fd1 (by rw [hd1]; exact repL)
  have sum := RunsExpr.binary (operation := .add) (program := P)
    (callArgs (RunsExprs.one (RunsExpr.local' (pd1.localFound t0))) len2)
    (RunsExpr.local' (pd2.localFound (pd1.localFound t2))) (by decide)
    (by rw [target]; exact eval_i32_add (by omega) (by omega))
  rw [show (xs.length : Int) + (b : Int) = ((xs.length + b : Nat) : Int) by omega] at sum
  have fd2 := pd2.afterFormed
  let S3 := d2.bindLocal 3 (.signed .i32 n)
  have fS3 : S3.CellsWellFormed := fd2.bindLocal _ _
  have v3 : S3.local? 3 = some (.signed .i32 n) := local_bound fd2 3 _
  have v1 : S3.local? 1 = some (.structure sid [vvR]) :=
    local_kept fd2 _ (by decide) (pd2.localFound (pd1.localFound t1))
  have v0 : S3.local? 0 = some (.structure sid [vvL]) :=
    local_kept fd2 _ (by decide) (pd2.localFound (pd1.localFound t0))
  have hS3 : S3.heap = caller.heap := pd2.heap.trans hd1
  have vS3 : S3.i32ArrayViews = [] := ((pd2.views.trans pd1.views).trans pc1.views).trans noViews
  -- the rest, from the run of reserved_for(count)
  have tail : ∀ (S4' : State) (q m : Nat),
      RunsExpr P S3 (.call rf [.local 3]) (.structure ids.vec [.pointer q, .signed .i32 0, .signed .i32 m]) S4' →
      Ext S3 S4' → S4'.i32ArrayViews = [] → n ≤ m →
      VecRep P T size ids.vec S4'.heap
        (.structure ids.vec [.pointer q, .signed .i32 ([] : List Value).length, .signed .i32 m]) [] →
      VecRep P T size ids.vec S4'.heap vvL xs → VecRep P T size ids.vec S4'.heap vvR ys →
      (0 < cap → (p + size * cap ≤ q ∨ q + size * m ≤ p)) →
      (0 < rc → (r + size * rc ≤ q ∨ q + size * m ≤ r)) →
      HeapBlocksBelowNext S4'.heap → HeapBlockBasesUnique S4'.heap → HeapApart S4'.heap →
      Kept caller.heap S4'.heap q (size * m) →
      Grow P S3 (.letLocal 4 (vecTy ids) (.call rf [.local 3])
        (.sequence
          (.ifThenElse (.binary .less (.call ids.capacity [.local 4]) (.local 3)) (.returnValue (some (.call sn []))) .skip)
        (.sequence
          (.expression (.assign .set (.local 4)
            (.call ext [.local 4, .call si.asl [.field (.local 0) 0], .call si.sl [.local 0]])))
          (.returnValue (some (.structValue sid [.call aw [.local 4, .local 1, .local 0, .value (.boolean false)]]))))))
        (.returned (some (.structure sid [.structure ids.vec
          [.pointer q, .signed .i32 (xs ++ W2).length, .signed .i32 m]])))
        (AlgebraOut P T size ids.vec caller.heap q m (xs ++ W2)) := by
    intro S4' q m rfRun ext4 views4 nm repO repL4 repR4 apL apR below4 unique4 apart4 kept4
    have loc4 : S4'.locals = S3.locals := rfRun.choose_spec.2
    have f4' := ext4.afterFormed
    let outv := Value.structure ids.vec [.pointer q, .signed .i32 0, .signed .i32 m]
    let S4 := S4'.bindLocal 4 outv
    have fS4 : S4.CellsWellFormed := f4'.bindLocal _ _
    have w0' : S4'.local? 0 = some (.structure sid [vvL]) := ext4.cells.localFound loc4 0 _ v0
    have w1' : S4'.local? 1 = some (.structure sid [vvR]) := ext4.cells.localFound loc4 1 _ v1
    have w4 : S4.local? 4 = some outv := local_bound f4' 4 _
    have w3 : S4.local? 3 = some (.signed .i32 n) := local_kept f4' _ (by decide) (ext4.cells.localFound loc4 3 _ v3)
    have w1 : S4.local? 1 = some (.structure sid [vvR]) := local_kept f4' _ (by decide) w1'
    have w0 : S4.local? 0 = some (.structure sid [vvL]) := local_kept f4' _ (by decide) w0'
    -- capacity(output) < count
    obtain ⟨c6, capRun, pc6⟩ := capacity_exact inst.vec fS4 q (.signed .i32 0) m
    have cond := RunsExpr.binary (operation := .less) (callArgs (RunsExprs.one (RunsExpr.local' w4)) capRun)
      (RunsExpr.local' (pc6.localFound w3)) (by decide) (eval_i32_lt _ _ _)
    rw [show decide ((m : Int) < (n : Int)) = false by simp; omega] at cond
    have hc6 : c6.heap = S4'.heap := pc6.heap
    have fc6 := pc6.afterFormed
    have vc6 : c6.i32ArrayViews = [] := pc6.views.trans views4
    have x4 := pc6.localFound w4
    have x0 := pc6.localFound w0
    have x1 := pc6.localFound w1
    -- output = try_extend_from_slice(output, as_slice(left.items), len(left))
    obtain ⟨e1, sliceRun, pe1⟩ := asSlice_spec inst.vec kind inst.asl inst.pf fc6 (by rw [hc6]; exact repL4)
      (by rw [hc6]; exact apart4.disjoint unique4)
    have fe1 := pe1.afterFormed
    have he1 : e1.heap = S4'.heap := pe1.heap.trans hc6
    obtain ⟨e2, lenRun, pe2⟩ := setLen_spec inst.vec inst.sl fe1 (by rw [he1]; exact repL4)
    have fe2 := pe2.afterFormed
    have he2 : e2.heap = S4'.heap := pe2.heap.trans he1
    have ve2 : e2.i32ArrayViews = [] := (pe2.views.trans pe1.views).trans vc6
    obtain ⟨R, extRun, cellsR, worldR, viewsR, repR1, keptR1, belowR1, uniqueR1, apartR1⟩ :=
      extendFresh_spec (g := g) inst.vec kind extFound fe2 (by rw [he2]; exact repO) (by rw [he2]; exact repL4)
        (by omega) apL storesL (by rw [he2]; exact below4) (by rw [he2]; exact unique4) ve2
    rw [he2] at keptR1 apartR1
    have right := RunsExpr.callArguments (RunsExprs.cons (RunsExpr.local' x4)
      (RunsExprs.cons (callArgs (RunsExprs.one (RunsExpr.field' (j := 0) (RunsExpr.local' x0) rfl)) sliceRun)
        (RunsExprs.cons (callArgs (RunsExprs.one (RunsExpr.local' (pe1.localFound x0))) lenRun) RunsExprs.nil)))
      extRun
    have rLocals : R.locals = c6.locals := right.choose_spec.2
    have cell4 : c6.cellId? 4 = some S4'.nextCell := by
      have : c6.locals = S4.locals := pc6.locals
      simp [State.cellId?, this, S4, State.bindLocal, State.bindCell]
    let nv := Value.structure ids.vec [.pointer q, .signed .i32 xs.length, .signed .i32 m]
    obtain ⟨A, assignRun, assigned, _⟩ := RunsExpr.assignCellAfter (before := c6) cell4
      (cellEntry_of_local c6 4 _ outv cell4 x4) right (Or.inr (viewsR.trans ve2))
    have cR4 : R.cellId? 4 = some S4'.nextCell := by unfold State.cellId? at cell4 ⊢; rw [rLocals]; exact cell4
    have cellA := assignLocal_assignCell 4 S4'.nextCell nv cR4 assigned
    have frameR : FreshCellFrame S4' R :=
      ((((FreshCellFrame.bindLocal S4' 4 outv).trans pc6.cells).trans pe1.cells).trans pe2.cells).trans cellsR
    obtain ⟨frameA, localsA, heapA, worldA, viewsA⟩ := FreshCellFrame.assignFresh f4'
      (FreshCellFrame.after_cellsWellFormed f4' frameR) frameR (Nat.le_refl _) cellA
    have fA := FreshCellFrame.after_cellsWellFormed f4' frameA
    have sameCell : ∀ id, id ≠ 4 → R.cellId? id = S4'.cellId? id := fun id ne => by
      have : R.cellId? id = S4.cellId? id := by unfold State.cellId?; rw [rLocals, pc6.locals]
      rw [this, cellId_bindLocal_ne S4' _ (Ne.symm ne)]
    have rx0 : R.local? 0 = some (.structure sid [vvL]) :=
      cellsR.localFoundAt (by unfold State.cellId?; rw [rLocals, pe2.locals, pe1.locals]) _
        (pe2.localFound (pe1.localFound x0))
    have rx1 : R.local? 1 = some (.structure sid [vvR]) :=
      cellsR.localFoundAt (by unfold State.cellId?; rw [rLocals, pe2.locals, pe1.locals]) _
        (pe2.localFound (pe1.localFound x1))
    have y4 : A.local? 4 = some nv := assignLocal_finds_assigned 4 S4'.nextCell nv cR4 assigned
    have y0 : A.local? 0 = some (.structure sid [vvL]) :=
      assignCell_preserves_other_local_of_cellId 0 S4'.nextCell nv cellA rx0
        (by rw [sameCell 0 (by decide)]; exact local_cell_ne_next f4' w0')
    have y1 : A.local? 1 = some (.structure sid [vvR]) :=
      assignCell_preserves_other_local_of_cellId 1 S4'.nextCell nv cellA rx1
        (by rw [sameCell 1 (by decide)]; exact local_cell_ne_next f4' w1')
    -- return Set { items: append_where(output, right, left, false) }
    have hA : A.heap = R.heap := heapA
    have repLA : VecRep P T size ids.vec A.heap vvL xs := by
      rw [hA]; exact repL4.keptApart keptR1 apL positive
    have repRA : VecRep P T size ids.vec A.heap vvR ys := by
      rw [hA]; exact repR4.keptApart keptR1 apR positive
    obtain ⟨F, append2, cellsF, worldF, viewsF, repF, keptF, belowF, uniqueF, apartF⟩ :=
      setAppendWhere_spec more.grow kind inst awFound eqSpec fA (acc := xs) (by rw [hA]; exact repR1)
        repRA repLA apR apL false (by show xs.length + b ≤ m; omega) subR subL storesR
        (by rw [hA]; exact belowR1) (by rw [hA]; exact uniqueR1) (by rw [hA]; exact apartR1 apart4)
        (viewsA.trans (viewsR.trans ve2))
    rw [hA] at keptF
    have retRun := RunsStmt.returnValue (RunsExpr.structValue (typeId := sid) (RunsExprs.cons
      (callArgs (RunsExprs.cons (RunsExpr.local' y4) (RunsExprs.three (RunsExpr.local' y1) (RunsExpr.local' y0)
        (RunsExpr.value' _))) append2) RunsExprs.nil))
    have bodyRun := RunsStmt.sequenceNext
      (RunsStmt.ifThenElseFalse (thenBranch := .returnValue (some (.call sn []))) cond (RunsStmt.skip P c6))
      (RunsStmt.sequenceNext (RunsStmt.expression assignRun) retRun)
    have frameF : FreshCellFrame S4' F := frameA.trans cellsF
    exact ⟨restoreLocals S4' F, RunsStmt.letLocal rfRun bodyRun,
      (ext4.trans ⟨f4', frameF,
        worldF.trans (worldA.trans (worldR.trans (pe2.world.trans (pe1.world.trans pc6.world)))),
        viewsF.trans (viewsA.trans (viewsR.trans (pe2.views.trans (pe1.views.trans pc6.views))))⟩).restore S4',
      repF, (kept4.trans keptR1).trans keptF, belowF, uniqueF, apartF⟩
  have whole : ∀ (S4' : State) (q m : Nat)
      (body : Grow P S3 _ _ (AlgebraOut P T size ids.vec caller.heap q m (xs ++ W2))),
      (0 < m → caller.heap.nextAddress ≤ q) →
      ∃ (after : State) (q m : Nat), RunsExpr P caller (.call f
          ([Value.structure sid [vvL], .structure sid [vvR]].map Expr.value))
        (.structure sid [.structure ids.vec [.pointer q, .signed .i32 (xs ++ W2).length, .signed .i32 m]]) after ∧
        FreshCellFrame caller after ∧ after.world = caller.world ∧ after.i32ArrayViews = caller.i32ArrayViews ∧
        (0 < m → caller.heap.nextAddress ≤ q) ∧ AlgebraOut P T size ids.vec caller.heap q m (xs ++ W2) after.heap :=
    fun _ q m body newer => by
      obtain ⟨after, call, cells, world, views, out⟩ := Grow.call
        (vs := [.structure sid [vvL], .structure sid [vvR]])
        (bindings := [(0, .structure sid [vvL]), (1, .structure sid [vvR])])
        (Q := AlgebraOut P T size ids.vec caller.heap q m (xs ++ W2)) found rfl rfl
        (Grow.letRun call1 (Ext.ofPure pc1)
          (Grow.guardSkip guard1 (Ext.ofPure pd1) (Grow.letRun sum (Ext.ofPure pd2) body)))
      exact ⟨after, q, m, call, cells, world, views, newer, out⟩
  by_cases zero : n = 0
  · obtain ⟨S4', run, pure4⟩ := setReservedFor_empty_spec more rfFound fS3 (n := (n : Int)) (by omega)
    have h4 : S4'.heap = caller.heap := pure4.heap.trans hS3
    have k4 : Kept caller.heap S4'.heap 0 (size * 0) := by rw [h4]; exact Kept.same _ _ _
    exact whole S4' 0 0 (tail S4' 0 0 (callArgs (RunsExprs.one (RunsExpr.local' v3)) run) (Ext.ofPure pure4)
      (pure4.views.trans vS3) (by omega) (VecRep.emptyAt P T size ids.vec _) (by rw [h4]; exact repL)
      (by rw [h4]; exact repR) (fun _ => Or.inr (by omega)) (fun _ => Or.inr (by omega)) (by rw [h4]; exact below)
      (by rw [h4]; exact unique) (by rw [h4]; exact apart) k4) (fun none => absurd none (Nat.lt_irrefl 0))
  · have npos : 0 < n := Nat.pos_of_ne_zero zero
    obtain ⟨fits, ⟨budget, available⟩, room⟩ := alloc (by rw [nLen]; exact npos)
    rw [nLen] at fits available room
    let q := caller.heap.allocationAddress 8
    have fresh : caller.heap.nextAddress ≤ q := Heap.allocationAddress_ge _ (by decide)
    obtain ⟨S4', run, cells4, world4, views4, grown⟩ := setReservedFor_spec more kind rfFound fS3 npos fits
      (by rw [hS3]; exact available) (by rw [hS3]; exact room) (by rw [hS3]; exact below)
      (by rw [hS3]; exact unique) vS3
    rw [hS3] at run grown
    obtain ⟨rep1, kept1, below1, unique1, _, apart1⟩ := grown
    have oldL : 0 < cap → p + size * cap ≤ q := fun pos => by
      have := ((bufL pos).2.1).belowNext (Nat.mul_pos positive pos) below
      dsimp only [Lanius.Address] at *; omega
    have oldR : 0 < rc → r + size * rc ≤ q := fun pos => by
      have := ((bufR pos).2.1).belowNext (Nat.mul_pos positive pos) below
      dsimp only [Lanius.Address] at *; omega
    exact whole S4' q n (tail S4' q n (callArgs (RunsExprs.one (RunsExpr.local' v3)) run)
      ⟨fS3, cells4, world4, views4⟩ (views4.trans vS3) (Nat.le_refl _) rep1
      (repL.keptApart kept1 (fun _ => Or.inr (Nat.zero_le _)) positive)
      (repR.keptApart kept1 (fun _ => Or.inr (Nat.zero_le _)) positive)
      (fun pos => Or.inl (oldL pos)) (fun pos => Or.inl (oldR pos)) below1 unique1 (apart1 apart)
      (kept1.ofNone q (size * n))) (fun _ => fresh)

#print axioms tryExtend_none_spec
#print axioms extendFresh_spec
#print axioms setUnion_spec

end Lanius.Std
