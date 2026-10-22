import Lanius.Std.VecRemove

/-! # `try_shrink_to_fit`

A nonempty vector with spare capacity moves to fresh storage of capacity
`len`: allocate, copy, free the old storage. -/

namespace Lanius.Std

open Lanius Lanius.Core Lanius.Semantics Lanius.Memory

variable {P : Program} {T : Ty} {ids : VecIds} {g : GrowIds} {mo : MoreIds} {size : Nat}

/-- `pub fn try_shrink_to_fit<T>(value: Vec<T>) -> Vec<T>`, with `value`,
`size`, `empty`, `next`, `from`, `to` and `index` the locals 0 to 6. -/
def tryShrinkToFitFn (ids : VecIds) (g : GrowIds) (mo : MoreIds) (T : Ty) (f : FunctionId) : Function where
  id := f
  parameters := [(0, vecTy ids)]
  returnType := vecTy ids
  body := some <|
    .letLocal 1 usizeTy (.call g.sizeOf [])
    (guardReturn (.binary .logicalOr (.binary .equal (.field (.local 0) 2) (.field (.local 0) 1))
        (.binary .equal (.local 1) (usize 0))) (.local 0)
    (.sequence
      (.ifThenElse (.binary .equal (.field (.local 0) 1) (int 0))
        (.sequence (.expression (.call mo.destroy [.local 0]))
          (.letLocal 2 (vecTy ids) (.call ids.new []) (.returnValue (some (.local 2)))))
        .skip)
    (.letLocal 3 ptrTy (.alloc (.binary .multiply (.local 1) (.cast (.unsigned .usize) (.field (.local 0) 1))) (usize 8))
    (guardReturn (.binary .equal (.local 3) (.value (.pointer 0))) (.local 0)
    (.letLocal 4 (.slice T) (.call ids.slots [.local 0])
    (.letLocal 5 (.slice T) (.call ids.fromStorage [.local 3, .field (.local 0) 1])
    (.letLocal 6 i32Ty (int 0)
    (.sequence (copyLoop 6 0 4 5)
    (.sequence (.expression (.dealloc (.field (.local 0) 0)
        (.binary .multiply (.local 1) (.cast (.unsigned .usize) (.field (.local 0) 2))) (usize 8)))
      (.returnValue (some (.structValue ids.vec [.local 3, .field (.local 0) 1, .field (.local 0) 1]))))))))))))

/-- `try_shrink_to_fit(v)` with `0 < len(v) < capacity(v)` and room in the
heap for `len(v)` elements: the vector moves to fresh storage of capacity
`len(v)` and the old storage is freed. -/
theorem tryShrinkToFit_spec (inst : GrowInstance P T ids g) (kind : ElemKind P T size)
    {f : FunctionId} (found : P.function? f = some (tryShrinkToFitFn ids g mo T f))
    {caller : State} (formed : caller.CellsWellFormed) {xs : List Value} {p cap : Nat}
    (rep : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]) xs)
    (nonempty : 0 < xs.length) (spare : xs.length < cap)
    {budget : Option Nat} (available : consumeBudget caller.heap.remaining (size * xs.length) = some budget)
    (room : caller.heap.allocationAddress 8 + size * xs.length < 2 ^ 64)
    (below : HeapBlocksBelowNext caller.heap) (unique : HeapBlockBasesUnique caller.heap)
    (noViews : caller.i32ArrayViews = []) (stores : ∀ x ∈ xs, ElemStore P T size x) :
    ∃ after, RunsExpr P caller (.call f
        ([Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]].map Expr.value))
      (.structure ids.vec [.pointer (caller.heap.allocationAddress 8), .signed .i32 xs.length,
        .signed .i32 xs.length]) after ∧
      FreshCellFrame caller after ∧ after.world = caller.world ∧
      after.i32ArrayViews = caller.i32ArrayViews ∧
      Grown P T size ids.vec caller.heap p (size * cap) (caller.heap.allocationAddress 8) xs.length xs
        after.heap := by
  have target := inst.vec.target
  obtain ⟨_, lenLe, capBound, buffer, reads⟩ := rep.fields
  have positive := kind.size_pos
  have sizeBound := kind.size_le
  let n := xs.length
  have nBound : xs.length < 2 ^ 31 := by omega
  have bytesPos : 0 < size * xs.length := Nat.mul_pos positive nonempty
  let q := caller.heap.allocationAddress 8
  have qPos : 0 < q := Heap.allocationAddress_pos _ (by decide)
  have fresh : caller.heap.nextAddress ≤ q := Heap.allocationAddress_ge _ (by decide)
  let H1 := caller.heap.allocatedBytes (size * xs.length) 8 budget
  have bufQ : Buffer H1 q (size * xs.length) := alloc_buffer below bytesPos room
  have capPos : 0 < cap := by omega
  have apart : p + size * cap ≤ q := by
    have := ((buffer capPos).2.1).belowNext (Nat.mul_pos positive capPos) below
    dsimp only [Lanius.Address] at *; omega
  let vv := Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]
  refine Grow.call (vs := [vv]) (Q := Grown P T size ids.vec caller.heap p (size * cap) q xs.length xs)
    found rfl rfl ?_
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  let E := E0.bindLocal 0 vv
  change Grow P E _ _ _
  have fE : E.CellsWellFormed := f0.bindLocal _ _
  have l0 : E.local? 0 = some vv := local_bound f0 0 _
  -- let size = size_of()
  obtain ⟨E1, sizeRun, fr1⟩ := size_of_spec target kind inst.sizeOf fE
  refine Grow.letRun sizeRun (Ext.ofPure fr1) ?_
  have fE1 := fr1.afterFormed
  let B1 := E1.bindLocal 1 (.unsigned .usize size)
  have fB1 : B1.CellsWellFormed := fE1.bindLocal _ _
  have b1_1 : B1.local? 1 = some (.unsigned .usize size) := local_bound fE1 1 _
  have b1_0 : B1.local? 0 = some vv := local_kept fE1 _ (by decide) (fr1.localFound l0)
  have hB1 : B1.heap = caller.heap := fr1.heap
  have vB1 : B1.i32ArrayViews = [] := fr1.views.trans noViews
  -- value.reserved == value.length || size == 0
  have cond1 := RunsExpr.logicalOrBool
    (RunsExpr.binary (operation := .equal) (program := P) (RunsExpr.field' (j := 2) (RunsExpr.local' b1_0) rfl)
      (RunsExpr.field' (j := 1) (RunsExpr.local' b1_0) rfl) (by decide) (eval_i32_eq _ _ _))
    (RunsExpr.binary (operation := .equal) (RunsExpr.local' b1_1) (RunsExpr.value' (.unsigned .usize 0))
      (by decide) (eval_usize_eq _ _ _))
  rw [show ((cap : Int) == (xs.length : Int)) = false by simp; omega,
    show (size == 0) = false by simp; omega, Bool.or_false] at cond1
  refine Grow.guardSkip cond1 (Ext.refl fB1) ?_
  -- value.length == 0
  have cond2 := RunsExpr.binary (operation := .equal) (program := P)
    (RunsExpr.field' (j := 1) (RunsExpr.local' b1_0) rfl) (RunsExpr.value' (.signed .i32 0)) (by decide)
    (eval_i32_eq _ _ _)
  rw [show ((xs.length : Int) == 0) = false by simp only [beq_eq_false_iff_ne]; omega] at cond2
  refine Grow.guardSkip cond2 (Ext.refl fB1) ?_
  -- let next = alloc(size * value.length, 8)
  have bytesRun : RunsExpr P B1 (.binary .multiply (.local 1) (.cast (.unsigned .usize) (.field (.local 0) 1)))
      (.unsigned .usize (size * xs.length)) B1 :=
    RunsExpr.binary (RunsExpr.local' b1_1) (RunsExpr.cast' (RunsExpr.field' (j := 1) (RunsExpr.local' b1_0) rfl)
      (by rw [target]; exact cast_usize_of_i32 (by omega))) (by decide)
      (by rw [target]; exact eval_usize_mul (by
        have := Nat.mul_le_mul_left size (Nat.le_of_lt nBound); omega))
  have allocRun := RunsExpr.allocAt (P := P) bytesRun (RunsExpr.value' (.unsigned .usize 8))
    (show consumeBudget B1.heap.remaining (size * xs.length) = some budget by rw [hB1]; exact available)
  rw [hB1] at allocRun
  refine Grow.letRun allocRun (Ext.heap fB1 H1) ?_
  let A3 : State := { B1 with heap := H1 }
  have fA3 : A3.CellsWellFormed := fB1
  let B3 := A3.bindLocal 3 (.pointer q)
  have fB3 : B3.CellsWellFormed := fA3.bindLocal _ _
  have b3_3 : B3.local? 3 = some (.pointer q) := local_bound fA3 3 _
  have b3_1 : B3.local? 1 = some (.unsigned .usize size) := local_kept fA3 _ (by decide) b1_1
  have b3_0 : B3.local? 0 = some vv := local_kept fA3 _ (by decide) b1_0
  have cond3 := RunsExpr.binary (operation := .equal) (program := P) (RunsExpr.local' b3_3)
    (RunsExpr.value' (.pointer 0)) (by decide) (eval_ptr_eq _ _ _)
  rw [show (q == 0) = false by simpa using Nat.ne_of_gt qPos] at cond3
  refine Grow.guardSkip cond3 (Ext.refl fB3) ?_
  -- let from = slots(value)
  obtain ⟨F4, fromRun, fr4⟩ := slots_call inst.vec kind fB3 b3_0 capBound (fun _ => (buffer capPos).afterAlloc)
  refine Grow.letRun fromRun (Ext.ofPure fr4) ?_
  have fF4 := fr4.afterFormed
  let B4 := F4.bindLocal 4 (.rawSlice T (viewAddr T size p cap) cap)
  have fB4 : B4.CellsWellFormed := fF4.bindLocal _ _
  have hB4 : B4.heap = H1 := fr4.heap
  have b4_3 : B4.local? 3 = some (.pointer q) := local_kept fF4 _ (by decide) (fr4.localFound b3_3)
  have b4_0 : B4.local? 0 = some vv := local_kept fF4 _ (by decide) (fr4.localFound b3_0)
  -- let to = typed_slice_from_storage(next, value.length)
  obtain ⟨F5, toRun, fr5⟩ := fromStorage_spec inst.vec kind fB4 nBound (fun _ => by rw [hB4]; exact bufQ)
  have toCall := callArgs (RunsExprs.two (RunsExpr.local' b4_3)
    (RunsExpr.field' (j := 1) (RunsExpr.local' b4_0) rfl)) toRun
  refine Grow.letRun toCall (Ext.ofPure fr5) ?_
  have fF5 := fr5.afterFormed
  let B5 := F5.bindLocal 5 (.rawSlice T (viewAddr T size q xs.length) xs.length)
  have fB5 : B5.CellsWellFormed := fF5.bindLocal _ _
  have hB5 : B5.heap = H1 := fr5.heap.trans hB4
  have keep5 : ∀ (id : VarId) (v : Value), id ≠ 4 → id ≠ 5 → B3.local? id = some v → B5.local? id = some v :=
    fun id v n4 n5 found => local_kept fF5 _ (Ne.symm n5)
      (fr5.localFound (local_kept fF4 _ (Ne.symm n4) (fr4.localFound found)))
  have b5_0 := keep5 0 vv (by decide) (by decide) b3_0
  have b5_1 := keep5 1 _ (by decide) (by decide) b3_1
  have b5_3 := keep5 3 _ (by decide) (by decide) b3_3
  have b5_4 : B5.local? 4 = some (.rawSlice T (viewAddr T size p cap) cap) :=
    local_kept fF5 _ (by decide) (fr5.localFound (local_bound fF4 4 _))
  have b5_5 : B5.local? 5 = some (.rawSlice T (viewAddr T size q xs.length) xs.length) := local_bound fF5 5 _
  have vB5 : B5.i32ArrayViews = [] := ((fr5.views.trans fr4.views)).trans vB1
  -- the copy loop
  obtain ⟨h2, loopRun, effect, copied⟩ := copy_loop_spec target kind fB5 (idx := 6) (vec := 0) (src := 4)
    (dst := 5) (by decide) (by decide) (by decide) b5_0 b5_4 b5_5 lenLe (Nat.le_refl _) nBound
    (fun i inside other within => reads i inside other (ReadsWithin.trans
      (by rw [hB5]; exact ReadsWithin.afterAlloc _ _ _ _ _ _) within))
    (fun _ => by rw [hB5]; exact bufQ) (Or.inl apart) stores vB5
    (by rw [hB5]; exact Heap.allocatedBytes_unique below unique (by decide))
  rw [hB5] at effect
  -- dealloc(value.storage, size * value.reserved, 8)
  have bufP2 : Buffer h2 p (size * cap) := ((buffer capPos).afterAlloc).afterWrite effect
  obtain ⟨h3, freedRun, freed⟩ := dealloc_buffer bufP2 effect.unique
  let W : State := { B5 with heap := h2 }
  have fW : W.CellsWellFormed := fB5
  let C6 := W.bindLocal 6 (.signed .i32 xs.length)
  have c6_0 : C6.local? 0 = some vv := local_kept fW _ (by decide) b5_0
  have c6_1 : C6.local? 1 = some (.unsigned .usize size) := local_kept fW _ (by decide) b5_1
  have c6_3 : C6.local? 3 = some (.pointer q) := local_kept fW _ (by decide) b5_3
  have deallocRun := RunsExpr.dealloc' (P := P) (S := C6) (RunsExprs.three
    (RunsExpr.field' (j := 0) (RunsExpr.local' c6_0) rfl)
    (RunsExpr.binary (operation := .multiply) (RunsExpr.local' c6_1)
      (RunsExpr.cast' (RunsExpr.field' (j := 2) (RunsExpr.local' c6_0) rfl)
        (by rw [target]; exact cast_usize_of_i32 (by omega))) (by decide)
      (by rw [target]; exact eval_usize_mul (a := size) (b := cap) (by
        have := Nat.mul_le_mul_left size (Nat.le_of_lt capBound); omega)))
    (RunsExpr.value' (.unsigned .usize 8))) vB5 freedRun
  let D := { C6 with heap := h3 }
  have d0 : D.local? 0 = some vv := c6_0
  have d3 : D.local? 3 = some (.pointer q) := c6_3
  have ret : RunsStmt P D (.returnValue (some (.structValue ids.vec [.local 3, .field (.local 0) 1, .field (.local 0) 1])))
      (.returned (some (.structure ids.vec [.pointer q, .signed .i32 xs.length, .signed .i32 xs.length]))) D :=
    RunsStmt.returnValue (RunsExprs.toRun (RunsExprs.three (RunsExpr.local' d3)
      (RunsExpr.field' (j := 1) (RunsExpr.local' d0) rfl) (RunsExpr.field' (j := 1) (RunsExpr.local' d0) rfl)))
  refine ⟨restoreLocals B5 D, RunsStmt.letLocal (RunsExpr.value' _)
      (RunsStmt.sequenceNext loopRun (RunsStmt.sequenceNext (RunsStmt.expression deallocRun) ret)),
    (((Ext.heap fB5 h2).trans (Ext.bindLocal fW 6 _)).trans (Ext.heap (fW.bindLocal _ _) h3)).restore B5, ?_⟩
  show Grown P T size ids.vec caller.heap p (size * cap) q xs.length xs h3
  refine ⟨⟨q, xs.length, rfl, Nat.le_refl _, nBound,
      fun _ => freed.buffer bytesPos (Or.inr apart) (bufQ.afterWrite effect),
      fun i inside other within => copied i inside other (ReadsWithin.trans (freed.reads (Or.inr ?_)) within)⟩,
    ((Kept.afterAlloc caller.heap p (size * cap) (size * xs.length) 8 budget).afterFreshWrite below fresh
      effect).afterFree freed,
    freed.below (effect.below (Heap.allocatedBytes_below below (by decide))), freed.unique effect.unique, ?_,
      fun ap => freed.apart (HeapApart.ofWrite effect (ap.afterAlloc below _ _ _ (by decide)))⟩
  · have := slot_inside (T := T) (size := size) (p := q) (show i < xs.length by omega); omega
  · rw [freed.next, effect.frontier]
    show q + max (size * xs.length) 1 = q + size * xs.length
    rw [Nat.max_eq_left bytesPos]

#print axioms tryShrinkToFit_spec

end Lanius.Std
