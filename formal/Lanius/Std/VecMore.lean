import Lanius.Std.VecPush

/-! # `destroy`, `try_with_capacity` and `try_swap_remove`

Templates in the front end's reading, as in `VecGrow.lean`, and their specs:
`destroy` frees the storage, `try_with_capacity(n)` is `try_reserve(new(), n)`,
and `try_swap_remove(v, i)` moves the last element into slot `i`. -/

namespace Lanius.Std

open Lanius Lanius.Core Lanius.Semantics Lanius.Memory

/-- The callee ids of the functions in this file. -/
structure MoreIds where
  destroy : FunctionId
  tryWithCapacity : FunctionId
  trySwapRemove : FunctionId
  tryClone : FunctionId

section templates
variable (ids : VecIds) (g : GrowIds) (mo : MoreIds) (T : Ty)

/-- `pub fn destroy<T>(value: Vec<T>)` -/
def destroyFn : Function where
  id := mo.destroy
  parameters := [(0, vecTy ids)]
  returnType := .unit
  body := some <|
    .letLocal 1 usizeTy (.call g.sizeOf [])
    (.ifThenElse (.binary .logicalAnd (.binary .greater (.field (.local 0) 2) (int 0))
        (.binary .greater (.local 1) (usize 0)))
      (.expression (.dealloc (.field (.local 0) 0)
        (.binary .multiply (.local 1) (.cast (.unsigned .usize) (.field (.local 0) 2))) (usize 8)))
      .skip)

/-- `pub fn try_with_capacity<T>(initial_capacity: i32) -> Vec<T>` -/
def tryWithCapacityFn : Function where
  id := mo.tryWithCapacity
  parameters := [(0, i32Ty)]
  returnType := vecTy ids
  body := some <|
    .letLocal 1 (vecTy ids) (.call ids.new [])
    (.returnValue (some (.call g.tryReserve [.local 1, .local 0])))

/-- `pub fn try_swap_remove<T>(value: Vec<T>, index: i32) -> Vec<T>` -/
def trySwapRemoveFn : Function where
  id := mo.trySwapRemove
  parameters := [(0, vecTy ids), (1, i32Ty)]
  returnType := vecTy ids
  body := some <|
    guardReturn (outOfRange 1) (.local 0)
    (.letLocal 2 (.slice T) (.call ids.slots [.local 0])
    (.sequence (.expression (.assign .set (.index (.local 2) (.local 1))
        (.index (.local 2) (.binary .subtract (.field (.local 0) 1) (int 1)))))
      (.returnValue (some (.structValue ids.vec
        [.field (.local 0) 0, .binary .subtract (.field (.local 0) 1) (int 1), .field (.local 0) 2])))))

/-- `pub fn try_clone<T>(value: Vec<T>) -> Vec<T>` -/
def tryCloneFn : Function where
  id := mo.tryClone
  parameters := [(0, vecTy ids)]
  returnType := vecTy ids
  body := some <|
    .letLocal 1 (vecTy ids) (.call mo.tryWithCapacity [.field (.local 0) 1])
    (.sequence
      (.ifThenElse (.binary .less (.field (.local 1) 2) (.field (.local 0) 1))
        (.letLocal 2 (vecTy ids) (.call ids.new []) (.returnValue (some (.local 2))))
        .skip)
    (.letLocal 3 (.slice T) (.call ids.slots [.local 0])
    (.letLocal 4 (.slice T) (.call ids.slots [.local 1])
    (.letLocal 5 i32Ty (int 0)
    (.sequence (copyLoop 5 0 3 4)
      (.returnValue (some (.structValue ids.vec [.field (.local 1) 0, .field (.local 0) 1, .field (.local 1) 2]))))))))

end templates

/-- A program holding the functions of this file. -/
structure MoreInstance (P : Program) (T : Ty) (ids : VecIds) (g : GrowIds) (mo : MoreIds) : Prop where
  grow : GrowInstance P T ids g
  destroy : P.function? mo.destroy = some (destroyFn ids g mo)
  tryWithCapacity : P.function? mo.tryWithCapacity = some (tryWithCapacityFn ids g mo)
  trySwapRemove : P.function? mo.trySwapRemove = some (trySwapRemoveFn ids mo T)
  tryClone : P.function? mo.tryClone = some (tryCloneFn ids mo T)

variable {P : Program} {T : Ty} {ids : VecIds} {g : GrowIds} {mo : MoreIds} {size : Nat}

/-! ## Helpers -/

/-- A unit call whose body is a `Grow` run falling through. -/
theorem Grow.callUnit {caller : State} {f : FunctionId} {fn : Function} {body : Stmt} {vs : List Value}
    {bindings : List (VarId × Value)} {Q : Heap → Prop}
    (found : P.function? f = some fn) (bodyFound : fn.body = some body) (returnsUnit : fn.returnType = .unit)
    (parameters : bindParameters fn.parameters vs = some bindings)
    (run : Grow P (({ caller with locals := [] } : State).bindLocals bindings) body .next Q) :
    ∃ after, RunsExpr P caller (.call f (vs.map Expr.value)) .unit after ∧ FreshCellFrame caller after ∧
      after.world = caller.world ∧ after.i32ArrayViews = caller.i32ArrayViews ∧ Q after.heap := by
  obtain ⟨completed, r, e, q⟩ := run
  have entry : FreshCellFrame caller (({ caller with locals := [] } : State).bindLocals bindings) :=
    (show FreshCellFrame caller { caller with locals := [] } from ⟨[], by simp, Nat.le_refl _, by simp⟩).trans
      (FreshCellFrame.bindLocals _ bindings)
  exact ⟨restoreLocals caller completed,
    RunsExpr.callUnit found bodyFound returnsUnit (RunsExprs.values _) parameters r,
    (entry.trans e.cells).restoreLocals, e.world.trans (bindLocals_world _ _),
    e.views.trans (bindLocals_views _ _), q⟩

theorem RunsExpr.logicalAndBool {S : State} {l r : Expr} {a b : Bool}
    (left : RunsExpr P S l (.boolean a) S) (right : RunsExpr P S r (.boolean b) S) :
    RunsExpr P S (.binary .logicalAnd l r) (.boolean (a && b)) S := by
  obtain ⟨_, left, locals⟩ := left
  obtain ⟨_, right, _⟩ := right
  exact .ofStable (StableExpr.logicalAnd left right) locals

theorem eval_usize_gt (t : Target) (a b : Nat) :
    evalBinaryValue t .greater (.unsigned .usize a) (.unsigned .usize b) = .ok (.boolean (decide (a > b))) := by
  simp [evalBinaryValue, evalUnsignedBinary]

/-- A raw-slice read at a computed index. -/
theorem StableExpr.rawSliceIndexAt {state : State} {sourceId : VarId} {element : Ty}
    {address length position k : Nat} {indexExpr : Expr} {value : Value}
    (source : state.local? sourceId = some (.rawSlice element address length))
    (index : StableExpr k P state indexExpr (.signed .i32 (Int.ofNat position)) state)
    (readable : readRawSliceIndex P state element address length position = .ok value) :
    StableExpr (k + 2) P state (.index (.local sourceId) indexExpr) value state := by
  intro fuel enough
  rw [show fuel = (fuel - 2).succ.succ by omega, evalExpr.eq_def]
  dsimp only
  simp only [evalExpr_local_of_local? _ _ _ _ _ source, index ((fuel - 2).succ) (by omega)]
  have nonnegative : ¬((position : Int) < 0) := Int.not_lt_of_ge (Int.natCast_nonneg position)
  simp only [integerIndex, Int.ofNat_eq_natCast, nonnegative, ↓reduceIte,
    Int.toNat_natCast, readable]

/-- `new()` returns the null vector. -/
theorem newRun (inst : VecInstance P T ids) {caller : State} (formed : caller.CellsWellFormed) :
    ∃ after, RunsExpr P caller (.call ids.new []) (.structure ids.vec [.pointer 0, .signed .i32 0, .signed .i32 0])
      after ∧ PureFrame caller after := by
  refine PureRun.call (vs := []) inst.new rfl rfl formed ?_
  let E : State := { caller with locals := [] }
  have f0 : E.CellsWellFormed := formed
  change PureRun P E _ _
  refine PureRun.letPure f0 (RunsExpr.value' (.pointer 0)) ?_
  have l0 := local_bound f0 0 (.pointer 0)
  exact PureRun.ret (f0.bindLocal _ _) (RunsExprs.toRun (RunsExprs.three (RunsExpr.local' l0)
    (RunsExpr.value' _) (RunsExpr.value' _)))

/-! ## `destroy` -/

/-- `destroy(v)` frees the storage of a vector with capacity, and changes
nothing for a vector without. -/
theorem destroy_spec (inst : MoreInstance P T ids g mo) (kind : ElemKind P T size)
    {caller : State} (formed : caller.CellsWellFormed) {xs : List Value} {p cap : Nat}
    (rep : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]) xs)
    (unique : HeapBlockBasesUnique caller.heap) (noViews : caller.i32ArrayViews = []) :
    ∃ after, RunsExpr P caller (.call mo.destroy
        ([Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]].map Expr.value))
      .unit after ∧ FreshCellFrame caller after ∧ after.world = caller.world ∧
      after.i32ArrayViews = caller.i32ArrayViews ∧ Freed caller.heap after.heap p (size * cap) := by
  have target := inst.grow.vec.target
  obtain ⟨_, _, capBound, buffer, _⟩ := rep.fields
  let vv := Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]
  refine Grow.callUnit (vs := [vv]) (Q := fun H => Freed caller.heap H p (size * cap)) inst.destroy rfl rfl rfl ?_
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  let E := E0.bindLocal 0 vv
  change Grow P E _ _ _
  have fE : E.CellsWellFormed := f0.bindLocal _ _
  have l0 : E.local? 0 = some vv := local_bound f0 0 _
  obtain ⟨E2, sizeRun, fr⟩ := size_of_spec target kind inst.grow.sizeOf fE
  refine Grow.letRun sizeRun (Ext.ofPure fr) ?_
  have fE2 := fr.afterFormed
  let B := E2.bindLocal 1 (.unsigned .usize size)
  have fB : B.CellsWellFormed := fE2.bindLocal _ _
  have b1 : B.local? 1 = some (.unsigned .usize size) := local_bound fE2 1 _
  have b0 : B.local? 0 = some vv := local_kept fE2 _ (by decide) (fr.localFound l0)
  have hB : B.heap = caller.heap := fr.heap
  have vB : B.i32ArrayViews = [] := fr.views.trans noViews
  have positive := kind.size_pos
  have cond := RunsExpr.logicalAndBool
    (RunsExpr.binary (operation := .greater) (program := P) (RunsExpr.field' (j := 2) (RunsExpr.local' b0) rfl)
      (RunsExpr.value' (.signed .i32 0)) (by decide) (eval_i32_gt _ _ _))
    (RunsExpr.binary (operation := .greater) (RunsExpr.local' b1) (RunsExpr.value' (.unsigned .usize 0))
      (by decide) (eval_usize_gt _ _ _))
  rw [show decide (size > 0) = true by simp; omega, Bool.and_true] at cond
  by_cases capPos : 0 < cap
  · rw [show decide ((cap : Int) > 0) = true by simp; omega] at cond
    obtain ⟨h', freedRun, freed⟩ := dealloc_buffer (h := B.heap) (by rw [hB]; exact buffer capPos) (by rw [hB]; exact unique)
    have sizeSmall := kind.size_le
    have deallocRun := RunsExpr.dealloc' (P := P) (S := B) (RunsExprs.three
      (RunsExpr.field' (j := 0) (RunsExpr.local' b0) rfl)
      (RunsExpr.binary (operation := .multiply) (RunsExpr.local' b1)
        (RunsExpr.cast' (RunsExpr.field' (j := 2) (RunsExpr.local' b0) rfl)
          (by rw [target]; exact cast_usize_of_i32 (by omega))) (by decide)
        (by rw [target]; exact eval_usize_mul (a := size) (b := cap) (by
          have := Nat.mul_le_mul_left size (Nat.le_of_lt capBound); omega)))
      (RunsExpr.value' (.unsigned .usize 8))) vB freedRun
    rw [hB] at freed
    exact ⟨_, RunsStmt.ifThenElseTrue cond (RunsStmt.expression deallocRun), Ext.heap fB h', freed⟩
  · rw [show decide ((cap : Int) > 0) = false by simp; omega] at cond
    refine ⟨B, RunsStmt.ifThenElseFalse cond (RunsStmt.skip P B), Ext.refl fB, ?_⟩
    rw [hB]
    exact Freed.refl _ _ _

/-! ## `try_reserve` without growth and `try_with_capacity` -/

/-- `try_reserve(v, min)` with `min ≤ capacity(v)` returns `v`. -/
theorem tryReserve_skip_spec (inst : GrowInstance P T ids g) {caller : State} (formed : caller.CellsWellFormed)
    {ptr len : Value} {cap min : Int} (enough : min ≤ cap) :
    ∃ after, RunsExpr P caller (.call g.tryReserve
        ([Value.structure ids.vec [ptr, len, .signed .i32 cap], .signed .i32 min].map Expr.value))
      (.structure ids.vec [ptr, len, .signed .i32 cap]) after ∧ PureFrame caller after := by
  let vv := Value.structure ids.vec [ptr, len, .signed .i32 cap]
  refine PureRun.call inst.tryReserve rfl rfl formed ?_
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  have f1 := f0.bindLocal 0 vv
  let E := (E0.bindLocal 0 vv).bindLocal 1 (.signed .i32 min)
  change PureRun P E _ _
  have fE : E.CellsWellFormed := f1.bindLocal _ _
  have l1 : E.local? 1 = some (.signed .i32 min) := local_bound f1 1 _
  have l0 : E.local? 0 = some vv := local_kept f1 _ (by decide) (local_bound f0 0 _)
  have cond := RunsExpr.binary (operation := .lessEqual) (program := P) (RunsExpr.local' l1)
    (RunsExpr.field' (j := 2) (RunsExpr.local' l0) rfl) (by decide) (eval_i32_le _ _ _)
  rw [show decide (min ≤ cap) = true by simp; omega] at cond
  exact PureRun.guardTaken cond (PureRun.ret fE (RunsExpr.local' l0)) nofun

/-- `try_with_capacity(n)` with `0 < n ≤ capacity_limit()` and room in the
heap: a fresh empty vector of capacity `n`. -/
theorem tryWithCapacity_spec (inst : MoreInstance P T ids g mo) (kind : ElemKind P T size)
    {caller : State} (formed : caller.CellsWellFormed) {n : Nat} (positive : 0 < n)
    (fits : size * n ≤ 2147483647)
    {budget : Option Nat} (available : consumeBudget caller.heap.remaining (size * n) = some budget)
    (room : caller.heap.allocationAddress 8 + size * n < 2 ^ 64)
    (below : HeapBlocksBelowNext caller.heap) (unique : HeapBlockBasesUnique caller.heap)
    (noViews : caller.i32ArrayViews = []) :
    ∃ after, RunsExpr P caller (.call mo.tryWithCapacity ([Value.signed .i32 n].map Expr.value))
      (.structure ids.vec [.pointer (caller.heap.allocationAddress 8), .signed .i32 0, .signed .i32 n])
      after ∧ FreshCellFrame caller after ∧ after.world = caller.world ∧
      after.i32ArrayViews = caller.i32ArrayViews ∧
      Grown P T size ids.vec caller.heap 0 0 (caller.heap.allocationAddress 8) n [] after.heap := by
  refine Grow.call inst.tryWithCapacity rfl rfl ?_
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  let E := E0.bindLocal 0 (.signed .i32 n)
  change Grow P E _ _ _
  have fE : E.CellsWellFormed := f0.bindLocal _ _
  have l0 : E.local? 0 = some (.signed .i32 n) := local_bound f0 0 _
  obtain ⟨E1, newCall, fr⟩ := newRun inst.grow.vec fE
  refine Grow.letRun newCall (Ext.ofPure fr) ?_
  have fE1 := fr.afterFormed
  let empty := Value.structure ids.vec [.pointer 0, .signed .i32 0, .signed .i32 0]
  let B := E1.bindLocal 1 empty
  have fB : B.CellsWellFormed := fE1.bindLocal _ _
  have b1 : B.local? 1 = some empty := local_bound fE1 1 _
  have b0 : B.local? 0 = some (.signed .i32 n) := local_kept fE1 _ (by decide) (fr.localFound l0)
  have hB : B.heap = caller.heap := fr.heap
  obtain ⟨R, reserveRun, cells, world, views, grown⟩ := tryReserve_grow_spec inst.grow kind fB (xs := [])
    (p := 0) (cap := 0) (min := n) ⟨0, 0, rfl, Nat.le_refl _, by decide, nofun, nofun⟩ positive fits
    (by rw [hB]; exact available) (by rw [hB]; exact room) (by rw [hB]; exact below) (by rw [hB]; exact unique)
    (fr.views.trans noViews) nofun
  rw [hB] at reserveRun grown
  exact ⟨R, RunsStmt.returnValue (callArgs (RunsExprs.two (RunsExpr.local' b1) (RunsExpr.local' b0)) reserveRun),
    ⟨fB, cells, world, views⟩, grown⟩

/-- `try_with_capacity(n)` with `n ≤ 0` returns `new()`. -/
theorem tryWithCapacity_empty_spec (inst : MoreInstance P T ids g mo) {caller : State}
    (formed : caller.CellsWellFormed) {n : Int} (nonpositive : n ≤ 0) :
    ∃ after, RunsExpr P caller (.call mo.tryWithCapacity ([Value.signed .i32 n].map Expr.value))
      (.structure ids.vec [.pointer 0, .signed .i32 0, .signed .i32 0]) after ∧ PureFrame caller after := by
  refine PureRun.call inst.tryWithCapacity rfl rfl formed ?_
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  let E := E0.bindLocal 0 (.signed .i32 n)
  change PureRun P E _ _
  have fE : E.CellsWellFormed := f0.bindLocal _ _
  have l0 : E.local? 0 = some (.signed .i32 n) := local_bound f0 0 _
  obtain ⟨E1, newCall, fr⟩ := newRun inst.grow.vec fE
  refine PureRun.letRun newCall fr ?_
  have fE1 := fr.afterFormed
  let empty := Value.structure ids.vec [.pointer 0, .signed .i32 0, .signed .i32 0]
  let B := E1.bindLocal 1 empty
  have fB : B.CellsWellFormed := fE1.bindLocal _ _
  have b1 : B.local? 1 = some empty := local_bound fE1 1 _
  have b0 : B.local? 0 = some (.signed .i32 n) := local_kept fE1 _ (by decide) (fr.localFound l0)
  obtain ⟨R, reserveRun, frame⟩ := tryReserve_skip_spec inst.grow fB (ptr := .pointer 0) (len := .signed .i32 0)
    (cap := 0) nonpositive
  exact ⟨R, RunsStmt.returnValue (callArgs (RunsExprs.two (RunsExpr.local' b1) (RunsExpr.local' b0)) reserveRun),
    frame⟩

/-! ## `try_swap_remove` -/

/-- The list after moving the last element into slot `i` and dropping the
last slot. -/
def swapRemoved (xs : List Value) (i : Nat) : List Value :=
  (xs.set i (xs[xs.length - 1]?.getD .unit)).dropLast

/-- `try_swap_remove(v, i)` in range: the last element is stored into slot
`i`, which is the only change to the heap, and the length drops by one. -/
theorem trySwapRemove_spec (inst : MoreInstance P T ids g mo) (kind : ElemKind P T size)
    {caller : State} (formed : caller.CellsWellFormed) {xs : List Value} {p cap : Nat}
    (rep : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]) xs)
    {i : Nat} (inside : i < xs.length) (stores : ∀ y ∈ xs, ElemStore P T size y)
    (noViews : caller.i32ArrayViews = []) (unique : HeapBlockBasesUnique caller.heap) :
    ∃ after, RunsExpr P caller (.call mo.trySwapRemove
        ([Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap], .signed .i32 i].map
          Expr.value))
      (.structure ids.vec [.pointer p, .signed .i32 (swapRemoved xs i).length, .signed .i32 cap]) after ∧
      FreshCellFrame caller after ∧ after.world = caller.world ∧
      after.i32ArrayViews = caller.i32ArrayViews ∧
      VecRep P T size ids.vec after.heap
        (.structure ids.vec [.pointer p, .signed .i32 (swapRemoved xs i).length, .signed .i32 cap])
        (swapRemoved xs i) ∧
      HeapRegionWrite caller.heap after.heap (slotLo T size p cap i) size := by
  have target := inst.grow.vec.target
  obtain ⟨_, lenLe, capBound, buffer, reads⟩ := rep.fields
  let n := xs.length
  have nPos : 0 < xs.length := by omega
  let last := xs[xs.length - 1]'(by omega)
  have lastEq : xs[xs.length - 1]?.getD .unit = last := by simp [last, List.getElem?_eq_getElem (by omega : xs.length - 1 < xs.length)]
  have store : ElemStore P T size last := stores last (List.getElem_mem _)
  have ysLen : (swapRemoved xs i).length = xs.length - 1 := by simp [swapRemoved]
  let vv := Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]
  have hcap : i < cap := by omega
  have lastCap : xs.length - 1 < cap := by omega
  refine Grow.call (vs := [vv, .signed .i32 i]) (Q := fun H => VecRep P T size ids.vec H
      (.structure ids.vec [.pointer p, .signed .i32 (swapRemoved xs i).length, .signed .i32 cap]) (swapRemoved xs i) ∧
      HeapRegionWrite caller.heap H (slotLo T size p cap i) size) inst.trySwapRemove rfl rfl ?_
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  have f1 := f0.bindLocal 0 vv
  let E := (E0.bindLocal 0 vv).bindLocal 1 (.signed .i32 i)
  change Grow P E _ _ _
  have fE : E.CellsWellFormed := f1.bindLocal _ _
  have l1 : E.local? 1 = some (.signed .i32 i) := local_bound f1 1 _
  have l0 : E.local? 0 = some vv := local_kept f1 _ (by decide) (local_bound f0 0 _)
  have cond := outOfRange_run (P := P) l0 l1
  rw [show (decide ((i : Int) < 0) || decide ((i : Int) ≥ xs.length)) = false by simp; omega] at cond
  refine Grow.guardSkip cond (Ext.refl fE) ?_
  obtain ⟨S', slots, frame⟩ := slots_call inst.grow.vec kind fE l0 capBound buffer
  have fS : S'.CellsWellFormed := frame.afterFormed
  let view := Value.rawSlice T (viewAddr T size p cap) cap
  let B := S'.bindLocal 2 view
  have fB : B.CellsWellFormed := fS.bindLocal _ _
  have hB : B.heap = caller.heap := frame.heap
  have src : B.local? 2 = some view := local_bound fS 2 _
  have idx : B.local? 1 = some (.signed .i32 (Int.ofNat i)) := local_kept fS _ (by decide) (frame.localFound l1)
  have v0 : B.local? 0 = some vv := local_kept fS _ (by decide) (frame.localFound l0)
  -- the right-hand side: items[value.length - 1]
  have lastIndex := RunsExpr.binary (operation := .subtract) (RunsExpr.field' (j := 1) (RunsExpr.local' v0) rfl)
    (RunsExpr.value' (P := P) (S := B) (.signed .i32 1)) (by decide)
    (by rw [target]; exact eval_i32_sub (by omega) (by omega))
  rw [show (xs.length : Int) - 1 = Int.ofNat (xs.length - 1) by simp; omega] at lastIndex
  obtain ⟨_, lastStable, _⟩ := lastIndex
  have readLast : readRawSliceIndex P B T (viewAddr T size p cap) cap (xs.length - 1) = .ok last :=
    reads (xs.length - 1) (by omega) B (by rw [hB]; exact ReadsWithin.refl _ _ _)
  have right := StableExpr.rawSliceIndexAt src lastStable readLast
  -- the store into slot i
  let lo := slotLo T size p cap i
  let base := elemBase T size p cap i
  have slotEq : slotOf T size base = lo := slotOf_elemBase kind.size_eight
  have readable : caller.heap.Readable lo size := by
    have within := slot_inside (T := T) (size := size) (p := p) hcap
    unfold slotLo at within
    exact (buffer (by omega)).2.1.subrange (start := size * slotIndex T cap i) (by omega)
  have roomBase : size ≤ base + 8 := by
    show size ≤ elemBase T size p cap i + 8
    unfold elemBase
    by_cases scalar : T = i32Ty
    · rw [if_pos scalar, kind.i32_size scalar]; omega
    · rw [if_neg scalar]; have := kind.size_eight scalar; omega
  obtain ⟨h', stored, readBack, effect⟩ :=
    store B B.heap base roomBase (by rw [slotEq, hB]; exact readable) (by rw [hB]; exact unique)
  rw [slotEq, hB] at effect
  have nv : B.i32ArrayViews = [] := frame.views.trans noViews
  have assign := StableExpr.assignRaw (before := B) (indexed := B) (ready := B) (heap := h')
    (sourceId := 2) src (StableExpr.local idx) hcap (elementAddress kind hcap) nv right stored
  let C : State := { B with heap := h' }
  have c0 : C.local? 0 = some vv := v0
  have shorter := RunsExpr.binary (operation := .subtract) (RunsExpr.field' (j := 1) (RunsExpr.local' c0) rfl)
    (RunsExpr.value' (P := P) (S := C) (.signed .i32 1)) (by decide)
    (by rw [target]; exact eval_i32_sub (by omega) (by omega))
  rw [show (xs.length : Int) - 1 = ((swapRemoved xs i).length : Int) by
    rw [show (swapRemoved xs i).length = xs.length - 1 from ysLen]; omega] at shorter
  refine ⟨restoreLocals S' C, RunsStmt.letLocal slots (RunsStmt.sequenceNext
      (RunsStmt.expression (RunsExpr.ofStable assign rfl))
      (RunsStmt.returnValue (RunsExprs.toRun (RunsExprs.three (RunsExpr.field' (j := 0) (RunsExpr.local' c0) rfl)
        shorter (RunsExpr.field' (j := 2) (RunsExpr.local' c0) rfl))))),
    (((Ext.ofPure frame).trans (Ext.bindLocal fS 2 view)).trans (Ext.heap fB h')).restore S', ?_, effect⟩
  refine ⟨p, cap, rfl, by omega, capBound, fun positive => (buffer positive).afterWrite effect, ?_⟩
  intro j jInside other within
  have jLen : j < xs.length - 1 := by omega
  have elem : (swapRemoved xs i)[j]'jInside = (xs.set i last)[j]'(by simp; omega) := by
    simp only [swapRemoved, lastEq, List.getElem_dropLast]
  rw [elem]
  by_cases same : j = i
  · subst same
    rw [List.getElem_set_self, readRawSliceIndex_elem other kind hcap]
    exact readBack other.heap (by rw [slotEq]; exact within)
  · rw [List.getElem_set_ne (fun h => same h.symm)]
    exact reads j (by omega) other
      (ReadsWithin.trans (HeapRegionWrite.readsApart effect (slots_apart hcap (by omega) (fun h => same h.symm))) within)

#print axioms destroy_spec
#print axioms tryReserve_skip_spec
#print axioms tryWithCapacity_spec
#print axioms tryWithCapacity_empty_spec
#print axioms trySwapRemove_spec

end Lanius.Std
