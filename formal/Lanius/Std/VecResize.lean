import Lanius.Std.VecFill

/-! # `try_resize`

`try_resize(v, n, fill)` keeps the prefix when `n ≤ len(v)`, fills in place
when `n` fits the capacity, and otherwise grows to exactly `n` through
`try_reserve` and fills the new storage. -/

namespace Lanius.Std

open Lanius Lanius.Core Lanius.Semantics Lanius.Memory

variable {P : Program} {T : Ty} {ids : VecIds} {g : GrowIds} {size : Nat}

section templates
variable (ids : VecIds) (g : GrowIds) (T : Ty)

/-- The end of `try_resize`, with `value`, `new_len`, `fill`, `grown`,
`items` and `index` the locals 0 to 5. -/
def resizeTail : Stmt :=
  .letLocal 4 (.slice T) (.call ids.slots [.local 3])
  (.letLocal 5 i32Ty (.field (.local 3) 1)
  (.sequence (fillLoop 5 1 4 2)
    (.returnValue (some (.structValue ids.vec [.field (.local 3) 0, .local 1, .field (.local 3) 2])))))

/-- `pub fn try_resize<T>(value: Vec<T>, new_len: i32, fill: T) -> Vec<T>` -/
def tryResizeFn (f : FunctionId) : Function where
  id := f
  parameters := [(0, vecTy ids), (1, i32Ty), (2, T)]
  returnType := vecTy ids
  body := some <|
    guardReturn (.binary .less (.local 1) (int 0)) (.local 0)
    (guardReturn (.binary .lessEqual (.local 1) (.field (.local 0) 1))
      (.structValue ids.vec [.field (.local 0) 0, .local 1, .field (.local 0) 2])
    (.letLocal 3 (vecTy ids) (.local 0)
    (.sequence
      (.ifThenElse (.binary .less (.field (.local 3) 2) (.local 1))
        (.sequence (.expression (.assign .set (.local 3) (.call g.tryReserve [.local 3, .local 1])))
          (.ifThenElse (.binary .less (.field (.local 3) 2) (.local 1)) (.returnValue (some (.local 0))) .skip))
        .skip)
    (resizeTail ids T))))

end templates

/-- The list `try_resize` grows to. -/
def resized (xs : List Value) (n : Nat) (x : Value) : List Value := xs ++ List.replicate (n - xs.length) x

theorem resized_length {xs : List Value} {n : Nat} (x : Value) (longer : xs.length ≤ n) :
    (resized xs n x).length = n := by
  simp [resized]; omega

/-- The fill at the end of `try_resize`. -/
theorem resizeTail_spec (inst : VecInstance P T ids) (kind : ElemKind P T size) {Y : State}
    (formed : Y.CellsWellFormed) {xs : List Value} {q m N : Nat} {x : Value}
    (rep : VecRep P T size ids.vec Y.heap
      (.structure ids.vec [.pointer q, .signed .i32 xs.length, .signed .i32 m]) xs)
    (longer : xs.length ≤ N) (fits : N ≤ m)
    (l3 : Y.local? 3 = some (.structure ids.vec [.pointer q, .signed .i32 xs.length, .signed .i32 m]))
    (l1 : Y.local? 1 = some (.signed .i32 N)) (l2 : Y.local? 2 = some x) (store : ElemStore P T size x)
    (noViews : Y.i32ArrayViews = []) (unique : HeapBlockBasesUnique Y.heap) :
    Grow P Y (resizeTail ids T)
      (.returned (some (.structure ids.vec [.pointer q, .signed .i32 N, .signed .i32 m])))
      (fun h => VecRep P T size ids.vec h (.structure ids.vec [.pointer q, .signed .i32 N, .signed .i32 m])
          (resized xs N x) ∧ HeapRegionWrite Y.heap h q (size * m)) := by
  have target := inst.target
  obtain ⟨_, _, capBound, buffer, reads⟩ := rep.fields
  let vv := Value.structure ids.vec [.pointer q, .signed .i32 xs.length, .signed .i32 m]
  obtain ⟨S4, slots, frame⟩ := slots_call inst kind formed l3 capBound buffer
  have fS : S4.CellsWellFormed := frame.afterFormed
  let view := Value.rawSlice T (viewAddr T size q m) m
  let B := S4.bindLocal 4 view
  have fB : B.CellsWellFormed := fS.bindLocal _ _
  have hB : B.heap = Y.heap := frame.heap
  have b4 : B.local? 4 = some view := local_bound fS 4 _
  have b3 : B.local? 3 = some vv := local_kept fS _ (by decide) (frame.localFound l3)
  have b1 : B.local? 1 = some (.signed .i32 N) := local_kept fS _ (by decide) (frame.localFound l1)
  have b2 : B.local? 2 = some x := local_kept fS _ (by decide) (frame.localFound l2)
  obtain ⟨h', loopRun, effect, filled, untouched⟩ := fill_loop_spec target kind fB (idx := 5) (len := 1)
    (dst := 4) (fill := 2) (by decide) (by decide) (by decide) b1 b4 b2 longer fits capBound
    (fun positive => by rw [hB]; exact buffer positive) store (frame.views.trans noViews)
    (by rw [hB]; exact unique)
  rw [hB] at effect untouched
  let W := ({ B with heap := h' } : State).bindLocal 5 (.signed .i32 N)
  have fW0 : ({ B with heap := h' } : State).CellsWellFormed := fB
  have w3 : W.local? 3 = some vv := local_kept fW0 _ (by decide) b3
  have w1 : W.local? 1 = some (.signed .i32 N) := local_kept fW0 _ (by decide) b1
  have ret : RunsStmt P W (.returnValue (some (.structValue ids.vec [.field (.local 3) 0, .local 1, .field (.local 3) 2])))
      (.returned (some (.structure ids.vec [.pointer q, .signed .i32 N, .signed .i32 m]))) W :=
    RunsStmt.returnValue (RunsExprs.toRun (RunsExprs.three (RunsExpr.field' (j := 0) (RunsExpr.local' w3) rfl)
      (RunsExpr.local' w1) (RunsExpr.field' (j := 2) (RunsExpr.local' w3) rfl)))
  have inner := RunsStmt.letLocal (type := i32Ty) (RunsExpr.field' (j := 1) (RunsExpr.local' b3) rfl)
    (RunsStmt.sequenceNext loopRun ret)
  refine ⟨_, RunsStmt.letLocal slots inner,
    (((Ext.ofPure frame).trans (Ext.bindLocal fS 4 view)).trans
      (((Ext.heap fB h').trans (Ext.bindLocal fW0 5 _)).restore B)).restore S4, ?_, effect⟩
  have lenEq := resized_length x longer
  refine ⟨q, m, by rw [lenEq], by omega, capBound, fun positive => (buffer positive).afterWrite effect, ?_⟩
  intro i inside other within
  rw [lenEq] at inside
  have qm : i < m := by omega
  by_cases old : i < xs.length
  · have e : (resized xs N x)[i]'(by omega) = xs[i] := by
      simp only [resized]; exact List.getElem_append_left old
    rw [e]
    exact reads i old other (ReadsWithin.trans (untouched i old) within)
  · have e : (resized xs N x)[i]'(by omega) = x := by
      simp [resized, List.getElem_append, old]
    rw [e]
    exact filled i (by omega) inside other within

/-- What `try_resize` leaves in the heap when it lengthens. -/
def Resized (P : Program) (T : Ty) (size : Nat) (vec : TypeId) (h : Heap) (p cap q m N : Nat)
    (ys : List Value) (H : Heap) : Prop :=
  VecRep P T size vec H (.structure vec [.pointer q, .signed .i32 N, .signed .i32 m]) ys ∧
    Kept h H p (size * cap) ∧ HeapBlocksBelowNext H ∧ HeapBlockBasesUnique H ∧
    (q = p ∧ m = cap ∧ H.nextAddress = h.nextAddress ∨
      q = h.allocationAddress 8 ∧ H.nextAddress = q + size * m)

/-- The arguments of `try_resize`. -/
abbrev resizeArgs (ids : VecIds) (p len cap : Nat) (n : Int) (x : Value) : List Expr :=
  [Value.structure ids.vec [.pointer p, .signed .i32 len, .signed .i32 cap], .signed .i32 n, x].map Expr.value

/-- `try_resize(v, n, fill)` with `0 ≤ n ≤ len(v)`: the prefix, in place. -/
theorem tryResize_shrink_spec {f : FunctionId} (found : P.function? f = some (tryResizeFn ids g T f))
    {caller : State} (formed : caller.CellsWellFormed) {xs : List Value} {p cap : Nat}
    (rep : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]) xs)
    {N : Nat} (shorter : N ≤ xs.length) (x : Value) :
    ∃ after, RunsExpr P caller (.call f (resizeArgs ids p xs.length cap N x))
      (.structure ids.vec [.pointer p, .signed .i32 (xs.take N).length, .signed .i32 cap]) after ∧
      PureFrame caller after ∧
      VecRep P T size ids.vec caller.heap
        (.structure ids.vec [.pointer p, .signed .i32 (xs.take N).length, .signed .i32 cap]) (xs.take N) := by
  obtain ⟨_, lenLe, capBound, buffer, reads⟩ := rep.fields
  let vv := Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]
  have takeLen : (xs.take N).length = N := by simp; omega
  obtain ⟨after, run, frame⟩ : ∃ after, RunsExpr P caller (.call f (resizeArgs ids p xs.length cap N x))
      (.structure ids.vec [.pointer p, .signed .i32 (xs.take N).length, .signed .i32 cap]) after ∧
      PureFrame caller after := by
    refine PureRun.call found rfl rfl formed ?_
    let E0 : State := { caller with locals := [] }
    have f0 : E0.CellsWellFormed := formed
    have f1 := f0.bindLocal 0 vv
    have f2 := f1.bindLocal 1 (.signed .i32 N)
    let E := ((E0.bindLocal 0 vv).bindLocal 1 (.signed .i32 N)).bindLocal 2 x
    change PureRun P E _ _
    have fE : E.CellsWellFormed := f2.bindLocal _ _
    have l1 : E.local? 1 = some (.signed .i32 N) := local_kept f2 _ (by decide) (local_bound f1 1 _)
    have l0 : E.local? 0 = some vv :=
      local_kept f2 _ (by decide) (local_kept f1 _ (by decide) (local_bound f0 0 _))
    have cond1 := RunsExpr.binary (operation := .less) (program := P) (RunsExpr.local' l1)
      (RunsExpr.value' (.signed .i32 0)) (by decide) (eval_i32_lt _ _ _)
    rw [show decide ((N : Int) < 0) = false by simp] at cond1
    refine PureRun.guardSkip cond1 ?_
    have cond2 := RunsExpr.binary (operation := .lessEqual) (program := P) (RunsExpr.local' l1)
      (RunsExpr.field' (j := 1) (RunsExpr.local' l0) rfl) (by decide) (eval_i32_le _ _ _)
    rw [show decide ((N : Int) ≤ xs.length) = true by simp; omega] at cond2
    refine PureRun.guardTaken cond2 (PureRun.ret fE (RunsExprs.toRun (RunsExprs.three
      (RunsExpr.field' (j := 0) (RunsExpr.local' l0) rfl) ?_ (RunsExpr.field' (j := 2) (RunsExpr.local' l0) rfl))))
      nofun
    rw [takeLen]; exact RunsExpr.local' l1
  refine ⟨after, run, frame, p, cap, rfl, by omega, capBound, buffer, fun i inside other within => ?_⟩
  rw [List.getElem_take]; exact reads i (by simp at inside; omega) other within

/-- `try_resize(v, n, fill)` with `len(v) < n ≤ capacity(v)`: filled in place. -/
theorem tryResize_room_spec (inst : VecInstance P T ids) (kind : ElemKind P T size)
    {f : FunctionId} (found : P.function? f = some (tryResizeFn ids g T f))
    {caller : State} (formed : caller.CellsWellFormed) {xs : List Value} {p cap : Nat}
    (rep : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]) xs)
    {N : Nat} (longer : xs.length < N) (fits : N ≤ cap) {x : Value} (store : ElemStore P T size x)
    (below : HeapBlocksBelowNext caller.heap) (unique : HeapBlockBasesUnique caller.heap)
    (noViews : caller.i32ArrayViews = []) :
    ∃ after, RunsExpr P caller (.call f (resizeArgs ids p xs.length cap N x))
      (.structure ids.vec [.pointer p, .signed .i32 N, .signed .i32 cap]) after ∧
      FreshCellFrame caller after ∧ after.world = caller.world ∧
      after.i32ArrayViews = caller.i32ArrayViews ∧
      Resized P T size ids.vec caller.heap p cap p cap N (resized xs N x) after.heap := by
  let vv := Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]
  refine Grow.call (vs := [vv, .signed .i32 N, x])
    (Q := Resized P T size ids.vec caller.heap p cap p cap N (resized xs N x)) found rfl rfl ?_
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  have f1 := f0.bindLocal 0 vv
  have f2 := f1.bindLocal 1 (.signed .i32 N)
  let E := ((E0.bindLocal 0 vv).bindLocal 1 (.signed .i32 N)).bindLocal 2 x
  change Grow P E _ _ _
  have fE : E.CellsWellFormed := f2.bindLocal _ _
  have l2 : E.local? 2 = some x := local_bound f2 2 _
  have l1 : E.local? 1 = some (.signed .i32 N) := local_kept f2 _ (by decide) (local_bound f1 1 _)
  have l0 : E.local? 0 = some vv :=
    local_kept f2 _ (by decide) (local_kept f1 _ (by decide) (local_bound f0 0 _))
  have cond1 := RunsExpr.binary (operation := .less) (program := P) (RunsExpr.local' l1)
    (RunsExpr.value' (.signed .i32 0)) (by decide) (eval_i32_lt _ _ _)
  rw [show decide ((N : Int) < 0) = false by simp] at cond1
  refine Grow.guardSkip cond1 (Ext.refl fE) ?_
  have cond2 := RunsExpr.binary (operation := .lessEqual) (program := P) (RunsExpr.local' l1)
    (RunsExpr.field' (j := 1) (RunsExpr.local' l0) rfl) (by decide) (eval_i32_le _ _ _)
  rw [show decide ((N : Int) ≤ xs.length) = false by simp; omega] at cond2
  refine Grow.guardSkip cond2 (Ext.refl fE) ?_
  refine Grow.letRun (RunsExpr.local' l0) (Ext.refl fE) ?_
  let B := E.bindLocal 3 vv
  have fB : B.CellsWellFormed := fE.bindLocal _ _
  have b3 : B.local? 3 = some vv := local_bound fE 3 _
  have b1 : B.local? 1 = some (.signed .i32 N) := local_kept fE _ (by decide) l1
  have b2 : B.local? 2 = some x := local_kept fE _ (by decide) l2
  have cond3 := RunsExpr.binary (operation := .less) (program := P)
    (RunsExpr.field' (j := 2) (RunsExpr.local' b3) rfl) (RunsExpr.local' b1) (by decide) (eval_i32_lt _ _ _)
  rw [show decide ((cap : Int) < N) = false by simp; omega] at cond3
  refine Grow.guardSkip cond3 (Ext.refl fB) ?_
  obtain ⟨after, run, ext, rep', effect⟩ := resizeTail_spec inst kind fB rep (Nat.le_of_lt longer) fits b3 b1 b2
    store noViews unique
  exact ⟨after, run, ext, rep', Kept.ofWrite effect ⟨Nat.le_refl _, Nat.le_refl _⟩, effect.below below,
    effect.unique, Or.inl ⟨rfl, rfl, effect.frontier⟩⟩

/-- `try_resize(v, n, fill)` with `capacity(v) < n ≤ capacity_limit()` and
room in the heap: grown to capacity `n` in fresh storage, then filled. -/
theorem tryResize_grow_spec (inst : GrowInstance P T ids g) (kind : ElemKind P T size)
    {f : FunctionId} (found : P.function? f = some (tryResizeFn ids g T f))
    {caller : State} (formed : caller.CellsWellFormed) {xs : List Value} {p cap : Nat}
    (rep : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]) xs)
    {N : Nat} (grows : cap < N) (fits : size * N ≤ 2147483647)
    {budget : Option Nat} (available : consumeBudget caller.heap.remaining (size * N) = some budget)
    (roomHeap : caller.heap.allocationAddress 8 + size * N < 2 ^ 64)
    {x : Value} (store : ElemStore P T size x) (stores : ∀ y ∈ xs, ElemStore P T size y)
    (below : HeapBlocksBelowNext caller.heap) (unique : HeapBlockBasesUnique caller.heap)
    (noViews : caller.i32ArrayViews = []) :
    ∃ after, RunsExpr P caller (.call f (resizeArgs ids p xs.length cap N x))
      (.structure ids.vec [.pointer (caller.heap.allocationAddress 8), .signed .i32 N, .signed .i32 N]) after ∧
      FreshCellFrame caller after ∧ after.world = caller.world ∧
      after.i32ArrayViews = caller.i32ArrayViews ∧
      Resized P T size ids.vec caller.heap p cap (caller.heap.allocationAddress 8) N N (resized xs N x)
        after.heap := by
  obtain ⟨_, lenLe, capBound, _, _⟩ := rep.fields
  let vv := Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]
  let Q := caller.heap.allocationAddress 8
  refine Grow.call (vs := [vv, .signed .i32 N, x])
    (Q := Resized P T size ids.vec caller.heap p cap Q N N (resized xs N x)) found rfl rfl ?_
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  have f1 := f0.bindLocal 0 vv
  have f2 := f1.bindLocal 1 (.signed .i32 N)
  let E := ((E0.bindLocal 0 vv).bindLocal 1 (.signed .i32 N)).bindLocal 2 x
  change Grow P E _ _ _
  have fE : E.CellsWellFormed := f2.bindLocal _ _
  have l2 : E.local? 2 = some x := local_bound f2 2 _
  have l1 : E.local? 1 = some (.signed .i32 N) := local_kept f2 _ (by decide) (local_bound f1 1 _)
  have l0 : E.local? 0 = some vv :=
    local_kept f2 _ (by decide) (local_kept f1 _ (by decide) (local_bound f0 0 _))
  have cond1 := RunsExpr.binary (operation := .less) (program := P) (RunsExpr.local' l1)
    (RunsExpr.value' (.signed .i32 0)) (by decide) (eval_i32_lt _ _ _)
  rw [show decide ((N : Int) < 0) = false by simp] at cond1
  refine Grow.guardSkip cond1 (Ext.refl fE) ?_
  have cond2 := RunsExpr.binary (operation := .lessEqual) (program := P) (RunsExpr.local' l1)
    (RunsExpr.field' (j := 1) (RunsExpr.local' l0) rfl) (by decide) (eval_i32_le _ _ _)
  rw [show decide ((N : Int) ≤ xs.length) = false by simp; omega] at cond2
  refine Grow.guardSkip cond2 (Ext.refl fE) ?_
  -- let grown = value
  let B := E.bindLocal 3 vv
  have fB : B.CellsWellFormed := fE.bindLocal _ _
  have b3 : B.local? 3 = some vv := local_bound fE 3 _
  have b1 : B.local? 1 = some (.signed .i32 N) := local_kept fE _ (by decide) l1
  have cB : B.cellId? 3 = some E.nextCell := bindLocal_cellId E 3 vv
  have cond3 := RunsExpr.binary (operation := .less) (program := P)
    (RunsExpr.field' (j := 2) (RunsExpr.local' b3) rfl) (RunsExpr.local' b1) (by decide) (eval_i32_lt _ _ _)
  rw [show decide ((cap : Int) < N) = true by simp; omega] at cond3
  -- grown = try_reserve(grown, new_len)
  obtain ⟨R, reserveRun, rCells, rWorld, rViews, grown⟩ := tryReserve_grow_spec inst kind fB
    (xs := xs) (p := p) (cap := cap) (min := N) rep grows fits available roomHeap below unique noViews stores
  let nv := Value.structure ids.vec [.pointer Q, .signed .i32 xs.length, .signed .i32 N]
  have right := callArgs (RunsExprs.two (RunsExpr.local' b3) (RunsExpr.local' b1)) reserveRun
  have rLocals : R.locals = B.locals := right.choose_spec.2
  obtain ⟨A, assignRun, assigned, effectA⟩ := RunsExpr.assignCellAfter (before := B) cB
    (cellEntry_of_local B 3 _ vv cB b3) right (Or.inr (rViews.trans noViews))
  have cR : R.cellId? 3 = some E.nextCell := by unfold State.cellId? at cB ⊢; rw [rLocals]; exact cB
  have a3 : A.local? 3 = some nv := assignLocal_finds_assigned 3 E.nextCell nv cR assigned
  have extER : Ext E R := (Ext.bindLocal fE 3 vv).trans ⟨fB, rCells, rWorld, rViews⟩
  obtain ⟨frameA, _, _, heapA, worldA, viewsA⟩ := FreshCellFrame.assignCounter fE extER.afterFormed extER.cells
    (assignLocal_assignCell 3 E.nextCell nv cR assigned)
  have extEA : Ext E A := ⟨fE, frameA, worldA.trans extER.world, viewsA.trans extER.views⟩
  have fA : A.CellsWellFormed := extEA.afterFormed
  have aLocals : A.locals = (3, E.nextCell) :: E.locals := effectA.locals.trans rLocals
  have a1 : A.local? 1 = some (.signed .i32 N) := local_above frameA aLocals (by decide) l1
  have a2 : A.local? 2 = some x := local_above frameA aLocals (by decide) l2
  have cond4 := RunsExpr.binary (operation := .less) (program := P)
    (RunsExpr.field' (j := 2) (RunsExpr.local' a3) rfl) (RunsExpr.local' a1) (by decide) (eval_i32_lt _ _ _)
  rw [show decide ((N : Int) < N) = false by simp] at cond4
  have vA : A.i32ArrayViews = [] := viewsA.trans (rViews.trans noViews)
  obtain ⟨rep2, kept2, below2, unique2, next2, apart2⟩ := grown
  have hA : A.heap = R.heap := heapA
  obtain ⟨F, tailRun, extTail, rep3, effect3⟩ := resizeTail_spec inst.vec kind fA (xs := xs) (q := Q) (m := N)
    (N := N) (by rw [hA]; exact rep2) (by omega) (Nat.le_refl _) a3 a1 a2 store vA (by rw [hA]; exact unique2)
  rw [hA] at effect3
  refine ⟨restoreLocals E F, RunsStmt.letLocal (RunsExpr.local' l0)
    (RunsStmt.sequenceNext (RunsStmt.ifThenElseTrue cond3 (RunsStmt.sequenceNext
      (RunsStmt.expression assignRun) (RunsStmt.ifThenElseFalse cond4 (RunsStmt.skip P A)))) tailRun),
    (extEA.trans extTail).restore E, ?_⟩
  have fresh : caller.heap.nextAddress ≤ Q := Heap.allocationAddress_ge caller.heap (by decide)
  exact ⟨rep3, kept2.afterFreshWrite below fresh effect3, effect3.below below2, effect3.unique,
    Or.inr ⟨rfl, effect3.frontier.trans next2⟩⟩

#print axioms resizeTail_spec
#print axioms tryResize_shrink_spec
#print axioms tryResize_room_spec
#print axioms tryResize_grow_spec

end Lanius.Std
