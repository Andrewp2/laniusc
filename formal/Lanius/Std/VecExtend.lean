import Lanius.Std.VecCopy

/-! # `try_extend_from_slice`

`try_extend_from_slice(v, items, count)` appends the `count` elements of the
slice `items`, growing through `grown_capacity` and `try_reserve` when the
vector lacks room. The source is a `SliceRep` apart from the old storage;
when the vector grows it must also lie below the frontier, which every live
slice does. -/

namespace Lanius.Std

open Lanius Lanius.Core Lanius.Semantics Lanius.Memory

variable {P : Program} {T : Ty} {ids : VecIds} {g : GrowIds} {size : Nat}

section templates
variable (ids : VecIds) (g : GrowIds) (T : Ty)

/-- The end of `try_extend_from_slice`, with `value`, `items`, `count`,
`needed`, `grown`, `to` and `index` the locals 0 to 6. -/
def extendTail : Stmt :=
  .letLocal 5 (.slice T) (.call ids.slots [.local 4])
  (.letLocal 6 i32Ty (int 0)
  (.sequence (extendLoop 6 2 5 1 4)
    (.returnValue (some (.structValue ids.vec [.field (.local 4) 0, .local 3, .field (.local 4) 2])))))

/-- `pub fn try_extend_from_slice<T>(value: Vec<T>, items: [T], count: i32) -> Vec<T>` -/
def tryExtendFn (f : FunctionId) : Function where
  id := f
  parameters := [(0, vecTy ids), (1, .slice T), (2, i32Ty)]
  returnType := vecTy ids
  body := some <|
    guardReturn (.binary .logicalOr (.binary .lessEqual (.local 2) (int 0))
        (.binary .greater (.local 2) (.binary .subtract (int 2147483647) (.field (.local 0) 1)))) (.local 0)
    (.letLocal 3 i32Ty (.binary .add (.field (.local 0) 1) (.local 2))
    (.letLocal 4 (vecTy ids) (.local 0)
    (.sequence
      (.ifThenElse (.binary .less (.field (.local 4) 2) (.local 3))
        (.letLocal 5 i32Ty (.call g.grownCapacity [.local 4, .local 3])
          (.sequence (.expression (.assign .set (.local 4) (.call g.tryReserve [.local 4, .local 5])))
            (.ifThenElse (.binary .less (.field (.local 4) 2) (.local 3))
              (.returnValue (some (.local 0))) .skip)))
        .skip)
    (extendTail ids T))))

end templates

theorem SliceRep.transfer {h h' : Heap} {address length : Nat} {lo : Nat → Nat} {ys : List Value}
    (source : SliceRep P T size h address length lo ys)
    (kept : ∀ j, j < ys.length → ReadsWithin h h' (lo j) size) :
    SliceRep P T size h' address length lo ys :=
  fun j inside other within => source j inside other (ReadsWithin.trans (kept j inside) within)

/-- The end of `try_extend_from_slice`: local 4 is a vector with room for
the `count` (local 2) elements of the slice in local 1. -/
theorem extendTail_spec (inst : VecInstance P T ids) (kind : ElemKind P T size) {Y : State}
    (formed : Y.CellsWellFormed) {xs ys : List Value} {q m sA sL : Nat} {lo : Nat → Nat}
    (rep : VecRep P T size ids.vec Y.heap
      (.structure ids.vec [.pointer q, .signed .i32 xs.length, .signed .i32 m]) xs)
    (room : xs.length + ys.length ≤ m)
    (l4 : Y.local? 4 = some (.structure ids.vec [.pointer q, .signed .i32 xs.length, .signed .i32 m]))
    (l3 : Y.local? 3 = some (.signed .i32 (xs ++ ys).length))
    (l2 : Y.local? 2 = some (.signed .i32 ys.length))
    (l1 : Y.local? 1 = some (.rawSlice T sA sL))
    (source : SliceRep P T size Y.heap sA sL lo ys)
    (apart : ∀ j, j < ys.length → lo j + size ≤ q ∨ q + size * m ≤ lo j)
    (stores : ∀ y ∈ ys, ElemStore P T size y)
    (noViews : Y.i32ArrayViews = []) (unique : HeapBlockBasesUnique Y.heap) :
    Grow P Y (extendTail ids T)
      (.returned (some (.structure ids.vec [.pointer q, .signed .i32 (xs ++ ys).length, .signed .i32 m])))
      (fun h => VecRep P T size ids.vec h
          (.structure ids.vec [.pointer q, .signed .i32 (xs ++ ys).length, .signed .i32 m]) (xs ++ ys) ∧
        HeapRegionWrite Y.heap h q (size * m)) := by
  have target := inst.target
  obtain ⟨_, _, capBound, buffer, reads⟩ := rep.fields
  let vv := Value.structure ids.vec [.pointer q, .signed .i32 xs.length, .signed .i32 m]
  obtain ⟨S5, slots, frame⟩ := slots_call inst kind formed l4 capBound buffer
  have fS : S5.CellsWellFormed := frame.afterFormed
  let view := Value.rawSlice T (viewAddr T size q m) m
  let B := S5.bindLocal 5 view
  have fB : B.CellsWellFormed := fS.bindLocal _ _
  have hB : B.heap = Y.heap := frame.heap
  have b5 : B.local? 5 = some view := local_bound fS 5 _
  have b4 : B.local? 4 = some vv := local_kept fS _ (by decide) (frame.localFound l4)
  have b3 : B.local? 3 = some (.signed .i32 (xs ++ ys).length) := local_kept fS _ (by decide) (frame.localFound l3)
  have b2 : B.local? 2 = some (.signed .i32 ys.length) := local_kept fS _ (by decide) (frame.localFound l2)
  have b1 : B.local? 1 = some (.rawSlice T sA sL) := local_kept fS _ (by decide) (frame.localFound l1)
  obtain ⟨h1, loopRun, effect1, copied, untouched⟩ := extend_loop_spec target kind fB (idx := 6) (cnt := 2)
    (dst := 5) (src := 1) (vec := 4) (by decide) (by decide) (by decide) (by decide) b2 b5 b4 b1 room capBound
    (fun positive => by rw [hB]; exact buffer positive)
    (fun j jIn other within => source j jIn other (by rw [hB] at within; exact within)) apart stores
    (frame.views.trans noViews) (by rw [hB]; exact unique)
  rw [hB] at effect1 untouched
  let W0 : State := { B with heap := h1 }
  have fW0 : W0.CellsWellFormed := fB
  let F := W0.bindLocal 6 (.signed .i32 ys.length)
  have f4 : F.local? 4 = some vv := local_kept fW0 _ (by decide) b4
  have f3 : F.local? 3 = some (.signed .i32 (xs ++ ys).length) := local_kept fW0 _ (by decide) b3
  have ret : RunsStmt P F
      (.returnValue (some (.structValue ids.vec [.field (.local 4) 0, .local 3, .field (.local 4) 2])))
      (.returned (some (.structure ids.vec [.pointer q, .signed .i32 (xs ++ ys).length, .signed .i32 m]))) F :=
    RunsStmt.returnValue (RunsExprs.toRun (RunsExprs.three (RunsExpr.field' (j := 0) (RunsExpr.local' f4) rfl)
      (RunsExpr.local' f3) (RunsExpr.field' (j := 2) (RunsExpr.local' f4) rfl)))
  have inner := RunsStmt.letLocal (type := i32Ty) (id := 6) (RunsExpr.value' (P := P) (S := B) (.signed .i32 0))
    (RunsStmt.sequenceNext loopRun ret)
  refine ⟨_, RunsStmt.letLocal slots inner,
    (((Ext.ofPure frame).trans (Ext.bindLocal fS 5 view)).trans
      (((Ext.heap fB h1).trans (Ext.bindLocal fW0 6 _)).restore B)).restore S5, ?_, effect1⟩
  refine ⟨q, m, rfl, by rw [List.length_append]; exact room, capBound,
    fun positive => (buffer positive).afterWrite effect1, ?_⟩
  intro j jInside other within
  rw [List.length_append] at jInside
  by_cases left : j < xs.length
  · rw [List.getElem_append_left left]
    exact reads j left other (ReadsWithin.trans (untouched j left) within)
  · have r := copied (j - xs.length) (by omega) other
      (by rw [show xs.length + (j - xs.length) = j by omega]; exact within)
    rw [show xs.length + (j - xs.length) = j by omega, getD_of_lt (by omega)] at r
    rw [List.getElem_append_right (by omega)]
    exact r

/-- The arguments of `try_extend_from_slice`. -/
abbrev extendArgs (ids : VecIds) (T : Ty) (p len cap sA sL count : Nat) : List Expr :=
  [Value.structure ids.vec [.pointer p, .signed .i32 len, .signed .i32 cap], .rawSlice T sA sL,
    .signed .i32 count].map Expr.value

theorem extendGuard_run (target : P.target = Target.x86_64) {S : State} {vec : TypeId} {ptr cap : Value}
    {len c : Nat} (l0 : S.local? 0 = some (.structure vec [ptr, .signed .i32 len, cap]))
    (l2 : S.local? 2 = some (.signed .i32 c)) (positive : 0 < c) (small : len + c ≤ 2147483647) :
    RunsExpr P S (.binary .logicalOr (.binary .lessEqual (.local 2) (int 0))
        (.binary .greater (.local 2) (.binary .subtract (int 2147483647) (.field (.local 0) 1))))
      (.boolean false) S := by
  have r := RunsExpr.logicalOrBool (P := P)
    (RunsExpr.binary (RunsExpr.local' l2) (RunsExpr.value' (.signed .i32 0)) (by decide) (eval_i32_le _ _ _))
    (RunsExpr.binary (RunsExpr.local' l2)
      (RunsExpr.binary (operation := .subtract) (RunsExpr.value' (P := P) (S := S) (.signed .i32 2147483647))
        (RunsExpr.field' (j := 1) (RunsExpr.local' l0) rfl) (by decide)
        (by rw [target]; exact eval_i32_sub (by omega) (by omega)))
      (by decide) (eval_i32_gt _ _ _))
  rw [show (decide ((c : Int) ≤ 0) || decide ((c : Int) > 2147483647 - len)) = false by
    simp only [Bool.or_eq_false_iff, decide_eq_false_iff_not]; omega] at r
  exact r

/-- The first two steps of `try_extend_from_slice`: the guard passes and
`needed` is bound. -/
theorem extend_prefix (target : P.target = Target.x86_64) {caller : State} (formed : caller.CellsWellFormed)
    {xs ys : List Value} {p cap sA sL : Nat} (positive : 0 < ys.length)
    (small : xs.length + ys.length ≤ 2147483647) {rest : Stmt} {k : Completion} {Q : Heap → Prop}
    (tail : Grow P ((((({ caller with locals := [] } : State).bindLocal 0
        (.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap])).bindLocal 1
        (.rawSlice T sA sL)).bindLocal 2 (.signed .i32 ys.length)).bindLocal 3 (.signed .i32 (xs ++ ys).length))
      rest k Q) :
    Grow P (((({ caller with locals := [] } : State).bindLocal 0
        (.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap])).bindLocal 1
        (.rawSlice T sA sL)).bindLocal 2 (.signed .i32 ys.length))
      (guardReturn (.binary .logicalOr (.binary .lessEqual (.local 2) (int 0))
        (.binary .greater (.local 2) (.binary .subtract (int 2147483647) (.field (.local 0) 1)))) (.local 0)
        (.letLocal 3 i32Ty (.binary .add (.field (.local 0) 1) (.local 2)) rest)) k Q := by
  let vv := Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  have f1 := f0.bindLocal 0 vv
  have f2 := f1.bindLocal 1 (.rawSlice T sA sL)
  let E := ((E0.bindLocal 0 vv).bindLocal 1 (.rawSlice T sA sL)).bindLocal 2 (.signed .i32 ys.length)
  have fE : E.CellsWellFormed := f2.bindLocal _ _
  have l2 : E.local? 2 = some (.signed .i32 ys.length) := local_bound f2 2 _
  have l0 : E.local? 0 = some vv :=
    local_kept f2 _ (by decide) (local_kept f1 _ (by decide) (local_bound f0 0 _))
  refine Grow.guardSkip (extendGuard_run target l0 l2 positive small) (Ext.refl fE) ?_
  have needed := RunsExpr.binary (operation := .add) (program := P)
    (RunsExpr.field' (j := 1) (RunsExpr.local' l0) rfl) (RunsExpr.local' l2) (by decide)
    (by rw [target]; exact eval_i32_add (by omega) (by omega))
  rw [show (xs.length : Int) + (ys.length : Int) = ((xs ++ ys).length : Int) by
    rw [List.length_append]; omega] at needed
  exact Grow.letRun needed (Ext.refl fE) tail

/-- `try_extend_from_slice(v, items, n)` with room for the `n ≥ 1` items:
copied in place. -/
theorem tryExtend_room_spec (inst : VecInstance P T ids) (kind : ElemKind P T size)
    {f : FunctionId} (found : P.function? f = some (tryExtendFn ids g T f))
    {caller : State} (formed : caller.CellsWellFormed) {xs ys : List Value} {p cap sA sL : Nat}
    {lo : Nat → Nat}
    (rep : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]) xs)
    (positive : 0 < ys.length) (room : xs.length + ys.length ≤ cap)
    (source : SliceRep P T size caller.heap sA sL lo ys)
    (apart : ∀ j, j < ys.length → lo j + size ≤ p ∨ p + size * cap ≤ lo j)
    (stores : ∀ y ∈ ys, ElemStore P T size y)
    (below : HeapBlocksBelowNext caller.heap) (unique : HeapBlockBasesUnique caller.heap)
    (noViews : caller.i32ArrayViews = []) :
    ∃ after, RunsExpr P caller (.call f (extendArgs ids T p xs.length cap sA sL ys.length))
      (.structure ids.vec [.pointer p, .signed .i32 (xs ++ ys).length, .signed .i32 cap]) after ∧
      FreshCellFrame caller after ∧ after.world = caller.world ∧
      after.i32ArrayViews = caller.i32ArrayViews ∧
      Pushed P T size ids.vec caller.heap p cap p cap (xs ++ ys) after.heap := by
  have target := inst.target
  obtain ⟨_, _, capBound, _, _⟩ := rep.fields
  let vv := Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]
  let sv := Value.rawSlice T sA sL
  refine Grow.call (vs := [vv, sv, .signed .i32 ys.length])
    (Q := Pushed P T size ids.vec caller.heap p cap p cap (xs ++ ys)) found rfl rfl ?_
  refine extend_prefix target formed positive (by omega) ?_
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  have f1 := f0.bindLocal 0 vv
  have f2 := f1.bindLocal 1 sv
  let E := ((E0.bindLocal 0 vv).bindLocal 1 sv).bindLocal 2 (.signed .i32 ys.length)
  have fE : E.CellsWellFormed := f2.bindLocal _ _
  let nv := Value.signed .i32 (xs ++ ys).length
  let E3 := E.bindLocal 3 nv
  have fE3 : E3.CellsWellFormed := fE.bindLocal _ _
  have e3_0 : E3.local? 0 = some vv := local_kept fE _ (by decide)
    (local_kept f2 _ (by decide) (local_kept f1 _ (by decide) (local_bound f0 0 _)))
  refine Grow.letRun (RunsExpr.local' e3_0) (Ext.refl fE3) ?_
  let B := E3.bindLocal 4 vv
  have fB : B.CellsWellFormed := fE3.bindLocal _ _
  have b4 : B.local? 4 = some vv := local_bound fE3 4 _
  have b3 : B.local? 3 = some nv := local_kept fE3 _ (by decide) (local_bound fE 3 _)
  have b2 : B.local? 2 = some (.signed .i32 ys.length) :=
    local_kept fE3 _ (by decide) (local_kept fE _ (by decide) (local_bound f2 2 _))
  have b1 : B.local? 1 = some sv := local_kept fE3 _ (by decide)
    (local_kept fE _ (by decide) (local_kept f2 _ (by decide) (local_bound f1 1 _)))
  have cond := RunsExpr.binary (operation := .less) (program := P)
    (RunsExpr.field' (j := 2) (RunsExpr.local' b4) rfl) (RunsExpr.local' b3) (by decide) (eval_i32_lt _ _ _)
  rw [show decide ((cap : Int) < ((xs ++ ys).length : Int)) = false by
    simp only [List.length_append, decide_eq_false_iff_not]; omega] at cond
  refine Grow.guardSkip cond (Ext.refl fB) ?_
  obtain ⟨after, run, ext, rep', effect⟩ := extendTail_spec inst kind fB rep room b4 b3 b2 b1 source apart
    stores noViews unique
  exact ⟨after, run, ext, rep', Kept.ofWrite effect ⟨Nat.le_refl _, Nat.le_refl _⟩, effect.below below,
    effect.unique, Or.inl ⟨rfl, rfl, effect.frontier⟩⟩

/-- The capacity `try_extend_from_slice` grows to. -/
def extendTarget (size cap needed : Nat) : Nat := grownTarget (capLimit size) cap needed

theorem extendTarget_bounds (kind : ElemKind P T size) {cap needed : Nat} (grows : cap < needed)
    (fits : size * needed ≤ 2147483647) :
    needed ≤ extendTarget size cap needed ∧ size * extendTarget size cap needed ≤ 2147483647 := by
  have positive := kind.size_pos
  have small := kind.size_le
  have neededLe : needed ≤ capLimit size := (Nat.le_div_iff_mul_le positive).mpr (by rw [Nat.mul_comm]; exact fits)
  have four : 4 ≤ capLimit size := (Nat.le_div_iff_mul_le positive).mpr (by omega)
  have bounds : needed ≤ extendTarget size cap needed ∧ extendTarget size cap needed ≤ capLimit size := by
    unfold extendTarget grownTarget
    generalize capLimit size = L at neededLe four
    dsimp only
    (repeat' split) <;> omega
  refine ⟨bounds.1, ?_⟩
  calc size * extendTarget size cap needed ≤ size * capLimit size := Nat.mul_le_mul_left _ bounds.2
    _ ≤ 2147483647 := Nat.mul_div_le 2147483647 size

/-- `try_extend_from_slice(v, items, n)` without room, with room in the heap
for `extendTarget`: grown as by `try_reserve`, then copied. The source must
lie below the frontier and apart from the old storage. -/
theorem tryExtend_grow_spec (inst : GrowInstance P T ids g) (kind : ElemKind P T size)
    {f : FunctionId} (found : P.function? f = some (tryExtendFn ids g T f))
    {caller : State} (formed : caller.CellsWellFormed) {xs ys : List Value} {p cap sA sL : Nat}
    {lo : Nat → Nat}
    (rep : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]) xs)
    (positive : 0 < ys.length) (short : cap < xs.length + ys.length)
    (fits : size * (xs.length + ys.length) ≤ 2147483647)
    {budget : Option Nat}
    (available : consumeBudget caller.heap.remaining
      (size * extendTarget size cap (xs.length + ys.length)) = some budget)
    (roomHeap : caller.heap.allocationAddress 8 + size * extendTarget size cap (xs.length + ys.length) < 2 ^ 64)
    (source : SliceRep P T size caller.heap sA sL lo ys)
    (apart : ∀ j, j < ys.length → lo j + size ≤ p ∨ p + size * cap ≤ lo j)
    (sourceBelow : ∀ j, j < ys.length → lo j + size ≤ caller.heap.nextAddress)
    (stores : ∀ y ∈ xs, ElemStore P T size y) (storesNew : ∀ y ∈ ys, ElemStore P T size y)
    (below : HeapBlocksBelowNext caller.heap) (unique : HeapBlockBasesUnique caller.heap)
    (noViews : caller.i32ArrayViews = []) :
    ∃ after, RunsExpr P caller (.call f (extendArgs ids T p xs.length cap sA sL ys.length))
      (.structure ids.vec [.pointer (caller.heap.allocationAddress 8), .signed .i32 (xs ++ ys).length,
        .signed .i32 (extendTarget size cap (xs.length + ys.length))]) after ∧
      FreshCellFrame caller after ∧ after.world = caller.world ∧
      after.i32ArrayViews = caller.i32ArrayViews ∧
      Pushed P T size ids.vec caller.heap p cap (caller.heap.allocationAddress 8)
        (extendTarget size cap (xs.length + ys.length)) (xs ++ ys) after.heap := by
  have target := inst.vec.target
  obtain ⟨_, _, capBound, _, _⟩ := rep.fields
  obtain ⟨enough, mFits⟩ := extendTarget_bounds kind short fits
  obtain ⟨m, hm⟩ : ∃ m, extendTarget size cap (xs.length + ys.length) = m := ⟨_, rfl⟩
  rw [hm] at available roomHeap enough mFits ⊢
  have positiveSize := kind.size_pos
  have small : xs.length + ys.length ≤ 2147483647 := by
    have := Nat.le_mul_of_pos_left (xs.length + ys.length) positiveSize; omega
  let vv := Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]
  let sv := Value.rawSlice T sA sL
  let Q := caller.heap.allocationAddress 8
  refine Grow.call (vs := [vv, sv, .signed .i32 ys.length])
    (Q := Pushed P T size ids.vec caller.heap p cap Q m (xs ++ ys)) found rfl rfl ?_
  refine extend_prefix target formed positive small ?_
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  have f1 := f0.bindLocal 0 vv
  have f2 := f1.bindLocal 1 sv
  let E := ((E0.bindLocal 0 vv).bindLocal 1 sv).bindLocal 2 (.signed .i32 ys.length)
  have fE : E.CellsWellFormed := f2.bindLocal _ _
  let nv := Value.signed .i32 (xs ++ ys).length
  let E3 := E.bindLocal 3 nv
  have fE3 : E3.CellsWellFormed := fE.bindLocal _ _
  have e3_0 : E3.local? 0 = some vv := local_kept fE _ (by decide)
    (local_kept f2 _ (by decide) (local_kept f1 _ (by decide) (local_bound f0 0 _)))
  have e3_3 : E3.local? 3 = some nv := local_bound fE 3 _
  have e3_2 : E3.local? 2 = some (.signed .i32 ys.length) :=
    local_kept fE _ (by decide) (local_bound f2 2 _)
  have e3_1 : E3.local? 1 = some sv :=
    local_kept fE _ (by decide) (local_kept f2 _ (by decide) (local_bound f1 1 _))
  -- let grown = value
  let B := E3.bindLocal 4 vv
  have fB : B.CellsWellFormed := fE3.bindLocal _ _
  have b4 : B.local? 4 = some vv := local_bound fE3 4 _
  have b3 : B.local? 3 = some nv := local_kept fE3 _ (by decide) e3_3
  have cB : B.cellId? 4 = some E3.nextCell := bindLocal_cellId E3 4 vv
  have cond2 := RunsExpr.binary (operation := .less) (program := P)
    (RunsExpr.field' (j := 2) (RunsExpr.local' b4) rfl) (RunsExpr.local' b3) (by decide) (eval_i32_lt _ _ _)
  rw [show decide ((cap : Int) < ((xs ++ ys).length : Int)) = true by
    simp only [List.length_append, decide_eq_true_eq]; omega] at cond2
  -- let target = grown_capacity(grown, needed)
  obtain ⟨B1, grownRun, gFrame⟩ := grown_capacity_spec inst kind fB (p := p) (len := .signed .i32 xs.length)
    (xs ++ ys).length capBound
  rw [show grownTarget (capLimit size) cap (xs ++ ys).length = m by
    rw [List.length_append]; exact hm] at grownRun
  have grownCall := callArgs (RunsExprs.two (RunsExpr.local' b4) (RunsExpr.local' b3)) grownRun
  have fB1 := gFrame.afterFormed
  let D := B1.bindLocal 5 (.signed .i32 m)
  have fD : D.CellsWellFormed := fB1.bindLocal _ _
  have d4 : D.local? 4 = some vv := local_kept fB1 _ (by decide) (gFrame.localFound b4)
  have d5 : D.local? 5 = some (.signed .i32 m) := local_bound fB1 5 _
  have cB1 : B1.cellId? 4 = some E3.nextCell := by unfold State.cellId? at cB ⊢; rw [gFrame.locals]; exact cB
  have cD : D.cellId? 4 = some E3.nextCell := (cellId_bindLocal_ne B1 _ (by decide)).trans cB1
  have hD : D.heap = caller.heap := gFrame.heap
  have vD : D.i32ArrayViews = [] := gFrame.views.trans noViews
  -- grown = try_reserve(grown, target)
  obtain ⟨R, reserveRun, rCells, rWorld, rViews, grown⟩ := tryReserve_grow_spec inst kind fD
    (xs := xs) (p := p) (cap := cap) (min := m) (by rw [hD]; exact rep) (by omega) mFits
    (by rw [hD]; exact available) (by rw [hD]; exact roomHeap) (by rw [hD]; exact below)
    (by rw [hD]; exact unique) vD stores
  rw [hD] at reserveRun grown
  let nvec := Value.structure ids.vec [.pointer Q, .signed .i32 xs.length, .signed .i32 m]
  have right := callArgs (RunsExprs.two (RunsExpr.local' d4) (RunsExpr.local' d5)) reserveRun
  have rLocals : R.locals = D.locals := right.choose_spec.2
  obtain ⟨A, assignRun, assigned, effectA⟩ := RunsExpr.assignCellAfter (before := D) cD
    (cellEntry_of_local D 4 _ vv cD d4) right (Or.inr (rViews.trans vD))
  have cR : R.cellId? 4 = some E3.nextCell := by unfold State.cellId? at cD ⊢; rw [rLocals]; exact cD
  have a4 : A.local? 4 = some nvec := assignLocal_finds_assigned 4 E3.nextCell nvec cR assigned
  have aLocals : A.locals = D.locals := effectA.locals.trans rLocals
  have extER : Ext E3 R := (((Ext.bindLocal fE3 4 vv).trans (Ext.ofPure gFrame)).trans (Ext.bindLocal fB1 5 _)).trans
    ⟨fD, rCells, rWorld, rViews⟩
  obtain ⟨frameA, _, _, heapA, worldA, viewsA⟩ := FreshCellFrame.assignCounter fE3 extER.afterFormed extER.cells
    (assignLocal_assignCell 4 E3.nextCell nvec cR assigned)
  have extEA : Ext E3 A := ⟨fE3, frameA, worldA.trans extER.world, viewsA.trans extER.views⟩
  let A' := restoreLocals B1 A
  have extEA' : Ext E3 A' := extEA.restore B1
  have fA' : A'.CellsWellFormed := extEA'.afterFormed
  have cA : A.cellId? 4 = some E3.nextCell := by unfold State.cellId? at cR ⊢; rw [effectA.locals]; exact cR
  have a'4 : A'.local? 4 = some nvec := (local?_congr (s := A') (t := A) rfl
    ((show A'.cellId? 4 = some E3.nextCell from cB1).trans cA.symm)).trans a4
  have a'Locals : A'.locals = (4, E3.nextCell) :: E3.locals := gFrame.locals
  have a'3 : A'.local? 3 = some nv := local_above extEA'.cells a'Locals (by decide) e3_3
  have a'2 : A'.local? 2 = some (.signed .i32 ys.length) := local_above extEA'.cells a'Locals (by decide) e3_2
  have a'1 : A'.local? 1 = some sv := local_above extEA'.cells a'Locals (by decide) e3_1
  have a3 : A.local? 3 = some nv := by
    refine (local?_congr (s := A) (t := A') rfl ?_).trans a'3
    have l : A.cellId? 3 = D.cellId? 3 := by unfold State.cellId?; rw [aLocals]
    exact l.trans (cellId_bindLocal_ne B1 _ (by decide))
  have cond3 := RunsExpr.binary (operation := .less) (program := P)
    (RunsExpr.field' (j := 2) (RunsExpr.local' a4) rfl) (RunsExpr.local' a3) (by decide) (eval_i32_lt _ _ _)
  rw [show decide ((m : Int) < ((xs ++ ys).length : Int)) = false by
    simp only [List.length_append, decide_eq_false_iff_not]; omega] at cond3
  have branch : RunsStmt P B
      (.letLocal 5 i32Ty (.call g.grownCapacity [.local 4, .local 3])
        (.sequence (.expression (.assign .set (.local 4) (.call g.tryReserve [.local 4, .local 5])))
          (.ifThenElse (.binary .less (.field (.local 4) 2) (.local 3))
            (.returnValue (some (.local 0))) .skip)))
      .next (restoreLocals B1 A) :=
    RunsStmt.letLocal grownCall (RunsStmt.sequenceNext (RunsStmt.expression assignRun)
      (RunsStmt.ifThenElseFalse cond3 (RunsStmt.skip P A)))
  have hA' : A'.heap = R.heap := heapA
  have vA' : A'.i32ArrayViews = [] := viewsA.trans (rViews.trans vD)
  obtain ⟨rep2, kept2, below2, unique2, next2⟩ := grown
  have fresh : caller.heap.nextAddress ≤ Q := Heap.allocationAddress_ge caller.heap (by decide)
  have source2 : SliceRep P T size A'.heap sA sL lo ys := by
    rw [hA']; exact source.transfer (fun j inside => kept2.reads _ _ (apart j inside))
  obtain ⟨F, tailRun, extTail, rep3, effect3⟩ := extendTail_spec inst.vec kind fA' (xs := xs) (ys := ys)
    (q := Q) (m := m) (by rw [hA']; exact rep2) enough a'4 a'3 a'2 a'1 source2
    (fun j inside => Or.inl (Nat.le_trans (sourceBelow j inside) fresh)) storesNew vA' (by rw [hA']; exact unique2)
  rw [hA'] at effect3
  refine ⟨restoreLocals E3 F, RunsStmt.letLocal (RunsExpr.local' e3_0)
    (RunsStmt.sequenceNext (RunsStmt.ifThenElseTrue cond2 branch) tailRun), (extEA'.trans extTail).restore E3, ?_⟩
  exact ⟨rep3, kept2.afterFreshWrite below fresh effect3, effect3.below below2, effect3.unique,
    Or.inr ⟨rfl, effect3.frontier.trans next2⟩⟩

#print axioms extendTail_spec
#print axioms tryExtend_room_spec
#print axioms tryExtend_grow_spec

end Lanius.Std
