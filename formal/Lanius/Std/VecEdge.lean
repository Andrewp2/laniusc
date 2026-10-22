import Lanius.Std.VecShrink

/-! # `reserve` and the remaining cases of `try_clone` and `try_shrink_to_fit`

`reserve` is `try_reserve` with a panic when the capacity stays short; the
specs here are the cases where it does not. `try_clone` of an empty vector
returns `new()`; `try_shrink_to_fit` returns a full vector unchanged and
frees the storage of an empty one. -/

namespace Lanius.Std

open Lanius Lanius.Core Lanius.Semantics Lanius.Memory

variable {P : Program} {T : Ty} {ids : VecIds} {g : GrowIds} {mo : MoreIds} {size : Nat}

/-- `pub fn reserve<T>(value: Vec<T>, minimum_capacity: i32) -> Vec<T>` -/
def reserveFn (ids : VecIds) (g : GrowIds) (f : FunctionId) : Function where
  id := f
  parameters := [(0, vecTy ids), (1, i32Ty)]
  returnType := vecTy ids
  body := some <|
    .letLocal 2 (vecTy ids) (.call g.tryReserve [.local 0, .local 1])
    (.sequence
      (.ifThenElse (.binary .less (.field (.local 2) 2) (.local 1)) (.expression (.call g.panic [])) .skip)
      (.returnValue (some (.local 2))))

/-! ## Combinators -/

theorem Grow.guardTaken {S : State} {c : Expr} {t rest : Stmt} {k : Completion} {Q : Heap → Prop}
    (cond : RunsExpr P S c (.boolean true) S) (branch : Grow P S t k Q) (notNext : k ≠ .next) :
    Grow P S (.sequence (.ifThenElse c t .skip) rest) k Q := by
  obtain ⟨after, run, e, q⟩ := branch
  exact ⟨after, RunsStmt.sequenceCompleted (RunsStmt.ifThenElseTrue cond run) notNext rest, e, q⟩

theorem Grow.sequenceExpr {S S' : State} {e : Expr} {v : Value} {rest : Stmt} {k : Completion}
    {Q : Heap → Prop} (run : RunsExpr P S e v S') (ext : Ext S S') (tail : Grow P S' rest k Q) :
    Grow P S (.sequence (.expression e) rest) k Q := by
  obtain ⟨after, r, e', q⟩ := tail
  exact ⟨after, RunsStmt.sequenceNext (RunsStmt.expression run) r, ext.trans e', q⟩

theorem Grow.ret {S : State} {e : Expr} {v : Value} {Q : Heap → Prop} (formed : S.CellsWellFormed)
    (run : RunsExpr P S e v S) (q : Q S.heap) : Grow P S (.returnValue (some e)) (.returned (some v)) Q :=
  ⟨S, RunsStmt.returnValue run, Ext.refl formed, q⟩

/-! ## `reserve` -/

/-- `reserve(v, min)` with `capacity(v) < min ≤ capacity_limit()` and room
in the heap: as `try_reserve`, and the capacity check passes. -/
theorem reserve_grow_spec (inst : GrowInstance P T ids g) (kind : ElemKind P T size)
    {f : FunctionId} (found : P.function? f = some (reserveFn ids g f))
    {caller : State} (formed : caller.CellsWellFormed) {xs : List Value} {p cap min : Nat}
    (rep : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]) xs)
    (grows : cap < min) (fits : size * min ≤ 2147483647)
    {budget : Option Nat} (available : consumeBudget caller.heap.remaining (size * min) = some budget)
    (room : caller.heap.allocationAddress 8 + size * min < 2 ^ 64)
    (below : HeapBlocksBelowNext caller.heap) (unique : HeapBlockBasesUnique caller.heap)
    (noViews : caller.i32ArrayViews = []) (stores : ∀ x ∈ xs, ElemStore P T size x) :
    ∃ after, RunsExpr P caller (.call f
        ([Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap], .signed .i32 min].map
          Expr.value))
      (.structure ids.vec [.pointer (caller.heap.allocationAddress 8), .signed .i32 xs.length, .signed .i32 min])
      after ∧ FreshCellFrame caller after ∧ after.world = caller.world ∧
      after.i32ArrayViews = caller.i32ArrayViews ∧
      Grown P T size ids.vec caller.heap p (size * cap) (caller.heap.allocationAddress 8) min xs after.heap := by
  let vv := Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]
  refine Grow.call (vs := [vv, .signed .i32 min])
    (Q := Grown P T size ids.vec caller.heap p (size * cap) (caller.heap.allocationAddress 8) min xs)
    found rfl rfl ?_
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  have f1 := f0.bindLocal 0 vv
  let E := (E0.bindLocal 0 vv).bindLocal 1 (.signed .i32 min)
  change Grow P E _ _ _
  have fE : E.CellsWellFormed := f1.bindLocal _ _
  have l1 : E.local? 1 = some (.signed .i32 min) := local_bound f1 1 _
  have l0 : E.local? 0 = some vv := local_kept f1 _ (by decide) (local_bound f0 0 _)
  obtain ⟨R, run, cells, world, views, grown⟩ := tryReserve_grow_spec inst kind fE rep grows fits available room
    below unique noViews stores
  have call := callArgs (RunsExprs.two (RunsExpr.local' l0) (RunsExpr.local' l1)) run
  have locals : R.locals = E.locals := call.choose_spec.2
  refine Grow.letRun call ⟨fE, cells, world, views⟩ ?_
  have fR := FreshCellFrame.after_cellsWellFormed fE cells
  let nv := Value.structure ids.vec [.pointer (caller.heap.allocationAddress 8), .signed .i32 xs.length,
    .signed .i32 min]
  let B := R.bindLocal 2 nv
  have fB : B.CellsWellFormed := fR.bindLocal _ _
  have b2 : B.local? 2 = some nv := local_bound fR 2 _
  have b1 : B.local? 1 = some (.signed .i32 min) := local_kept fR _ (by decide) (cells.localFound locals 1 _ l1)
  have cond := RunsExpr.binary (operation := .less) (program := P)
    (RunsExpr.field' (j := 2) (RunsExpr.local' b2) rfl) (RunsExpr.local' b1) (by decide) (eval_i32_lt _ _ _)
  rw [show decide ((min : Int) < min) = false by simp] at cond
  exact Grow.guardSkip cond (Ext.refl fB) (Grow.ret fB (RunsExpr.local' b2) grown)

/-- `reserve(v, min)` with `min ≤ capacity(v)` returns `v`. -/
theorem reserve_skip_spec (inst : GrowInstance P T ids g) {f : FunctionId}
    (found : P.function? f = some (reserveFn ids g f)) {caller : State} (formed : caller.CellsWellFormed)
    {ptr len : Value} {cap min : Int} (enough : min ≤ cap) :
    ∃ after, RunsExpr P caller (.call f
        ([Value.structure ids.vec [ptr, len, .signed .i32 cap], .signed .i32 min].map Expr.value))
      (.structure ids.vec [ptr, len, .signed .i32 cap]) after ∧ PureFrame caller after := by
  let vv := Value.structure ids.vec [ptr, len, .signed .i32 cap]
  refine PureRun.call found rfl rfl formed ?_
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  have f1 := f0.bindLocal 0 vv
  let E := (E0.bindLocal 0 vv).bindLocal 1 (.signed .i32 min)
  change PureRun P E _ _
  have fE : E.CellsWellFormed := f1.bindLocal _ _
  have l1 : E.local? 1 = some (.signed .i32 min) := local_bound f1 1 _
  have l0 : E.local? 0 = some vv := local_kept f1 _ (by decide) (local_bound f0 0 _)
  obtain ⟨R, run, frame⟩ := tryReserve_skip_spec inst fE (ptr := ptr) (len := len) enough
  refine PureRun.letRun (callArgs (RunsExprs.two (RunsExpr.local' l0) (RunsExpr.local' l1)) run) frame ?_
  have fR := frame.afterFormed
  let B := R.bindLocal 2 vv
  have b2 : B.local? 2 = some vv := local_bound fR 2 _
  have b1 : B.local? 1 = some (.signed .i32 min) := local_kept fR _ (by decide) (frame.localFound l1)
  have cond := RunsExpr.binary (operation := .less) (program := P)
    (RunsExpr.field' (j := 2) (RunsExpr.local' b2) rfl) (RunsExpr.local' b1) (by decide) (eval_i32_lt _ _ _)
  rw [show decide (cap < min) = false by simp; omega] at cond
  exact PureRun.guardSkip cond (PureRun.ret (fR.bindLocal _ _) (RunsExpr.local' b2))

/-! ## `try_clone` of an empty vector -/

/-- `try_clone(v)` of an empty vector returns `new()`; the heap reads as
before. -/
theorem tryClone_empty_spec (inst : MoreInstance P T ids g mo) (kind : ElemKind P T size)
    {caller : State} (formed : caller.CellsWellFormed) {p cap : Nat}
    (rep : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer p, .signed .i32 0, .signed .i32 cap]) [])
    (unique : HeapBlockBasesUnique caller.heap) (noViews : caller.i32ArrayViews = []) :
    ∃ after, RunsExpr P caller (.call mo.tryClone
        ([Value.structure ids.vec [.pointer p, .signed .i32 0, .signed .i32 cap]].map Expr.value))
      (.structure ids.vec [.pointer 0, .signed .i32 0, .signed .i32 0]) after ∧
      FreshCellFrame caller after ∧ after.world = caller.world ∧
      after.i32ArrayViews = caller.i32ArrayViews ∧ HeapRegionWrite caller.heap after.heap 0 0 := by
  have target := inst.grow.vec.target
  obtain ⟨_, _, capBound, buffer, _⟩ := rep.fields
  let vv := Value.structure ids.vec [.pointer p, .signed .i32 0, .signed .i32 cap]
  refine Grow.call (vs := [vv]) (Q := fun H => HeapRegionWrite caller.heap H 0 0) inst.tryClone rfl rfl ?_
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  let E := E0.bindLocal 0 vv
  change Grow P E _ _ _
  have fE : E.CellsWellFormed := f0.bindLocal _ _
  have l0 : E.local? 0 = some vv := local_bound f0 0 _
  obtain ⟨R, wcRun, fr⟩ := tryWithCapacity_empty_spec inst fE (n := 0) (Int.le_refl _)
  have wcCall := callArgs (RunsExprs.one (RunsExpr.field' (j := 1) (RunsExpr.local' l0) rfl)) wcRun
  refine Grow.letRun wcCall (Ext.ofPure fr) ?_
  have fR := fr.afterFormed
  let copy := Value.structure ids.vec [.pointer 0, .signed .i32 0, .signed .i32 0]
  let B1 := R.bindLocal 1 copy
  have fB1 : B1.CellsWellFormed := fR.bindLocal _ _
  have b1 : B1.local? 1 = some copy := local_bound fR 1 _
  have b0 : B1.local? 0 = some vv := local_kept fR _ (by decide) (fr.localFound l0)
  have hB1 : B1.heap = caller.heap := fr.heap
  have cond := RunsExpr.binary (operation := .less) (program := P)
    (RunsExpr.field' (j := 2) (RunsExpr.local' b1) rfl) (RunsExpr.field' (j := 1) (RunsExpr.local' b0) rfl)
    (by decide) (eval_i32_lt _ _ _)
  rw [show decide ((0 : Int) < 0) = false by decide] at cond
  refine Grow.guardSkip cond (Ext.refl fB1) ?_
  obtain ⟨S3, fromRun, fr3⟩ := slots_call (xs := []) inst.grow.vec kind fB1 b0 capBound
    (fun pos => by rw [hB1]; exact buffer pos)
  refine Grow.letRun fromRun (Ext.ofPure fr3) ?_
  have fS3 := fr3.afterFormed
  let B3 := S3.bindLocal 3 (.rawSlice T (viewAddr T size p cap) cap)
  have fB3 : B3.CellsWellFormed := fS3.bindLocal _ _
  have b3_1 : B3.local? 1 = some copy := local_kept fS3 _ (by decide) (fr3.localFound b1)
  obtain ⟨S4, toRun, fr4⟩ := slots_call (xs := []) (p := 0) (cap := 0) inst.grow.vec kind fB3 b3_1 (by decide)
    nofun
  refine Grow.letRun toRun (Ext.ofPure fr4) ?_
  have fS4 := fr4.afterFormed
  let B4 := S4.bindLocal 4 (.rawSlice T (viewAddr T size 0 0) 0)
  have fB4 : B4.CellsWellFormed := fS4.bindLocal _ _
  have hB4 : B4.heap = caller.heap := (fr4.heap.trans fr3.heap).trans hB1
  have keep4 : ∀ (id : VarId) (v : Value), id ≠ 3 → id ≠ 4 → B1.local? id = some v → B4.local? id = some v :=
    fun id v n3 n4 found => local_kept fS4 _ (Ne.symm n4)
      (fr4.localFound (local_kept fS3 _ (Ne.symm n3) (fr3.localFound found)))
  have b4_0 := keep4 0 vv (by decide) (by decide) b0
  have b4_1 := keep4 1 copy (by decide) (by decide) b1
  have b4_3 : B4.local? 3 = some (.rawSlice T (viewAddr T size p cap) cap) :=
    local_kept fS4 _ (by decide) (fr4.localFound (local_bound fS3 3 _))
  have b4_4 : B4.local? 4 = some (.rawSlice T (viewAddr T size 0 0) 0) := local_bound fS4 4 _
  obtain ⟨h2, loopRun, effect, _⟩ := copy_loop_spec (xs := []) target kind fB4 (idx := 5) (vec := 0) (src := 3)
    (dst := 4) (by decide) (by decide) (by decide) b4_0 b4_3 b4_4 (Nat.zero_le _) (Nat.le_refl _) (by decide)
    (fun i inside => absurd inside (by simp)) nofun (Or.inr (Nat.zero_le _)) (fun _ m => by simp at m)
    ((fr4.views.trans fr3.views).trans (fr.views.trans noViews)) (by rw [hB4]; exact unique)
  rw [hB4, Nat.mul_zero] at effect
  let W := ({ B4 with heap := h2 } : State).bindLocal 5 (.signed .i32 ([] : List Value).length)
  have fW0 : ({ B4 with heap := h2 } : State).CellsWellFormed := fB4
  have w0 : W.local? 0 = some vv := local_kept fW0 _ (by decide) b4_0
  have w1 : W.local? 1 = some copy := local_kept fW0 _ (by decide) b4_1
  have ret : RunsStmt P W (.returnValue (some (.structValue ids.vec
      [.field (.local 1) 0, .field (.local 0) 1, .field (.local 1) 2])))
      (.returned (some (.structure ids.vec [.pointer 0, .signed .i32 0, .signed .i32 0]))) W :=
    RunsStmt.returnValue (RunsExprs.toRun (RunsExprs.three (RunsExpr.field' (j := 0) (RunsExpr.local' w1) rfl)
      (RunsExpr.field' (j := 1) (RunsExpr.local' w0) rfl) (RunsExpr.field' (j := 2) (RunsExpr.local' w1) rfl)))
  exact ⟨restoreLocals B4 W, RunsStmt.letLocal (RunsExpr.value' _) (RunsStmt.sequenceNext loopRun ret),
    ((Ext.heap fB4 h2).trans (Ext.bindLocal fW0 5 _)).restore B4, effect⟩

/-! ## `try_shrink_to_fit` without moving -/

/-- `try_shrink_to_fit(v)` with `capacity(v) = len(v)` returns `v`. -/
theorem tryShrinkToFit_same_spec (inst : GrowInstance P T ids g) (kind : ElemKind P T size)
    {f : FunctionId} (found : P.function? f = some (tryShrinkToFitFn ids g mo T f))
    {caller : State} (formed : caller.CellsWellFormed) {ptr : Value} {len : Int} :
    ∃ after, RunsExpr P caller (.call f
        ([Value.structure ids.vec [ptr, .signed .i32 len, .signed .i32 len]].map Expr.value))
      (.structure ids.vec [ptr, .signed .i32 len, .signed .i32 len]) after ∧ PureFrame caller after := by
  have target := inst.vec.target
  let vv := Value.structure ids.vec [ptr, .signed .i32 len, .signed .i32 len]
  refine PureRun.call found rfl rfl formed ?_
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  let E := E0.bindLocal 0 vv
  change PureRun P E _ _
  have fE : E.CellsWellFormed := f0.bindLocal _ _
  have l0 : E.local? 0 = some vv := local_bound f0 0 _
  obtain ⟨E1, sizeRun, fr1⟩ := size_of_spec target kind inst.sizeOf fE
  refine PureRun.letRun sizeRun fr1 ?_
  have fE1 := fr1.afterFormed
  have b0 : (E1.bindLocal 1 (.unsigned .usize size)).local? 0 = some vv :=
    local_kept fE1 _ (by decide) (fr1.localFound l0)
  have cond := RunsExpr.logicalOrTrue' (r := .binary .equal (.local 1) (usize 0))
    (RunsExpr.binary (operation := .equal) (program := P) (RunsExpr.field' (j := 2) (RunsExpr.local' b0) rfl)
      (RunsExpr.field' (j := 1) (RunsExpr.local' b0) rfl) (by decide)
      (by rw [show evalBinaryValue P.target .equal (.signed .i32 len) (.signed .i32 len) = .ok (.boolean true) by
        rw [eval_i32_eq]; simp]))
  exact PureRun.guardTaken cond (PureRun.ret (fE1.bindLocal _ _) (RunsExpr.local' b0)) nofun

/-- `try_shrink_to_fit(v)` of an empty vector with capacity frees the
storage through `destroy` and returns `new()`. -/
theorem tryShrinkToFit_empty_spec (inst : MoreInstance P T ids g mo) (kind : ElemKind P T size)
    {f : FunctionId} (found : P.function? f = some (tryShrinkToFitFn ids g mo T f))
    {caller : State} (formed : caller.CellsWellFormed) {p cap : Nat}
    (rep : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer p, .signed .i32 0, .signed .i32 cap]) [])
    (capPos : 0 < cap) (unique : HeapBlockBasesUnique caller.heap) (noViews : caller.i32ArrayViews = []) :
    ∃ after, RunsExpr P caller (.call f
        ([Value.structure ids.vec [.pointer p, .signed .i32 0, .signed .i32 cap]].map Expr.value))
      (.structure ids.vec [.pointer 0, .signed .i32 0, .signed .i32 0]) after ∧
      FreshCellFrame caller after ∧ after.world = caller.world ∧
      after.i32ArrayViews = caller.i32ArrayViews ∧ Freed caller.heap after.heap p (size * cap) := by
  have target := inst.grow.vec.target
  let vv := Value.structure ids.vec [.pointer p, .signed .i32 0, .signed .i32 cap]
  refine Grow.call (vs := [vv]) (Q := fun H => Freed caller.heap H p (size * cap)) found rfl rfl ?_
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  let E := E0.bindLocal 0 vv
  change Grow P E _ _ _
  have fE : E.CellsWellFormed := f0.bindLocal _ _
  have l0 : E.local? 0 = some vv := local_bound f0 0 _
  obtain ⟨E1, sizeRun, fr1⟩ := size_of_spec target kind inst.grow.sizeOf fE
  refine Grow.letRun sizeRun (Ext.ofPure fr1) ?_
  have fE1 := fr1.afterFormed
  let B1 := E1.bindLocal 1 (.unsigned .usize size)
  have fB1 : B1.CellsWellFormed := fE1.bindLocal _ _
  have b1_1 : B1.local? 1 = some (.unsigned .usize size) := local_bound fE1 1 _
  have b1_0 : B1.local? 0 = some vv := local_kept fE1 _ (by decide) (fr1.localFound l0)
  have hB1 : B1.heap = caller.heap := fr1.heap
  have positive := kind.size_pos
  have cond1 := RunsExpr.logicalOrBool
    (RunsExpr.binary (operation := .equal) (program := P) (RunsExpr.field' (j := 2) (RunsExpr.local' b1_0) rfl)
      (RunsExpr.field' (j := 1) (RunsExpr.local' b1_0) rfl) (by decide) (eval_i32_eq _ _ _))
    (RunsExpr.binary (operation := .equal) (RunsExpr.local' b1_1) (RunsExpr.value' (.unsigned .usize 0))
      (by decide) (eval_usize_eq _ _ _))
  rw [show ((cap : Int) == 0) = false by simp only [beq_eq_false_iff_ne]; omega,
    show (size == 0) = false by simp; omega, Bool.or_false] at cond1
  refine Grow.guardSkip cond1 (Ext.refl fB1) ?_
  have cond2 := RunsExpr.binary (operation := .equal) (program := P)
    (RunsExpr.field' (j := 1) (RunsExpr.local' b1_0) rfl) (RunsExpr.value' (.signed .i32 0)) (by decide)
    (eval_i32_eq _ _ _)
  rw [show ((0 : Int) == 0) = true by decide] at cond2
  refine Grow.guardTaken cond2 ?_ nofun
  obtain ⟨D, destroyRun, cells, world, views, freed⟩ := destroy_spec inst kind fB1 (xs := [])
    (by rw [hB1]; exact rep) (by rw [hB1]; exact unique) (fr1.views.trans noViews)
  rw [hB1] at freed
  have destroyCall := callArgs (RunsExprs.one (RunsExpr.local' b1_0)) destroyRun
  refine Grow.sequenceExpr destroyCall ⟨fB1, cells, world, views⟩ ?_
  have fD := FreshCellFrame.after_cellsWellFormed fB1 cells
  obtain ⟨D1, newCall, frNew⟩ := newRun inst.grow.vec fD
  refine Grow.letRun newCall (Ext.ofPure frNew) ?_
  have fD1 := frNew.afterFormed
  refine Grow.ret (fD1.bindLocal _ _) (RunsExpr.local' (local_bound fD1 2 _)) ?_
  show Freed caller.heap D1.heap p (size * cap)
  rw [frNew.heap]; exact freed

#print axioms reserve_grow_spec
#print axioms reserve_skip_spec
#print axioms tryClone_empty_spec
#print axioms tryShrinkToFit_same_spec
#print axioms tryShrinkToFit_empty_spec

end Lanius.Std
