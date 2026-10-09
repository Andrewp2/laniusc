import Lanius.Semantics.MutableLocal
import Lanius.Semantics.Assignment
import Lanius.Semantics.ProofFacts
import Lanius.Semantics.ScalarAssignment
import Lanius.Semantics.StatementProof

namespace Lanius.Semantics

open Lanius Lanius.Core

variable {base before current after : State} {firstId secondId : VarId}
  {first second replacement : Value}

/-- Two fresh mutable cells, with all preexisting cells retained as a prefix.
    Heap and world effects are separate from this local-state invariant. -/
structure LocalPair (base current : State) (firstId secondId : VarId) (first second : Value) : Prop where
  cells : FreshCellFrame base current
  different : firstId ≠ secondId
  locals : current.locals = (secondId, base.nextCell + 1) :: (firstId, base.nextCell) :: base.locals
  first : current.local? firstId = some first
  second : current.local? secondId = some second

theorem LocalPair.start (formed : base.CellsWellFormed) (different : firstId ≠ secondId) :
    LocalPair base ((base.bindLocal firstId first).bindLocal secondId second)
      firstId secondId first second := by
  refine ⟨(FreshCellFrame.bindLocal base firstId first).trans
    (FreshCellFrame.bindLocal _ secondId second), different, rfl, ?_, ?_⟩
  · exact State.bindLocal_local?_of_ne _ (formed.bindLocal _ _) _ _ _ _
      (Ne.symm different) (formed.bindLocal_local _ _)
  · exact (formed.bindLocal _ _).bindLocal_local _ _

theorem LocalPair.firstCell (pair : LocalPair base current firstId secondId first second) :
    current.cellId? firstId = some base.nextCell := by
  simp [State.cellId?, pair.locals, Ne.symm pair.different]

theorem LocalPair.secondCell (pair : LocalPair base current firstId secondId first second) :
    current.cellId? secondId = some (base.nextCell + 1) := by
  simp [State.cellId?, pair.locals]

@[core_local_rule] theorem LocalPair.read
    (pair : LocalPair base current firstId secondId first second)
    (differentFirst : localId ≠ firstId) (differentSecond : localId ≠ secondId)
    (found : base.local? localId = some value) : current.local? localId = some value :=
  pair.cells.localFoundAt
    (by simp [State.cellId?, pair.locals, Ne.symm differentFirst, Ne.symm differentSecond]) _ found

theorem LocalPair.transCells
    (pair : LocalPair base before firstId secondId first second)
    (cells : FreshCellFrame before after) (locals : after.locals = before.locals) :
    LocalPair base after firstId secondId first second :=
  ⟨pair.cells.trans cells, pair.different, locals.trans pair.locals,
    cells.localFound locals _ _ pair.first, cells.localFound locals _ _ pair.second⟩

theorem LocalPair.assignFirst
    (pair : LocalPair base before firstId secondId first second) (formed : base.CellsWellFormed)
    (assigned : before.assignLocal firstId replacement = some after) :
    LocalPair base after firstId secondId replacement second := by
  have cellAssigned := assignLocal_assignCell _ _ _ pair.firstCell assigned
  have effect := assignCell_effect cellAssigned
  refine ⟨pair.cells.assignCellFresh formed _ _ (Nat.le_refl _) cellAssigned,
    pair.different, effect.locals.trans pair.locals,
    assignLocal_finds_assigned _ _ _ pair.firstCell assigned, ?_⟩
  apply assignCell_preserves_other_local_of_cellId _ _ _ cellAssigned pair.second
  rw [pair.secondCell]
  simp

theorem LocalPair.assignSecond
    (pair : LocalPair base before firstId secondId first second) (formed : base.CellsWellFormed)
    (assigned : before.assignLocal secondId replacement = some after) :
    LocalPair base after firstId secondId first replacement := by
  have cellAssigned := assignLocal_assignCell _ _ _ pair.secondCell assigned
  have effect := assignCell_effect cellAssigned
  refine ⟨pair.cells.assignCellFresh formed (base.nextCell + 1) replacement (Nat.le_succ _) cellAssigned,
    pair.different, effect.locals.trans pair.locals, ?_,
    assignLocal_finds_assigned _ _ _ pair.secondCell assigned⟩
  apply assignCell_preserves_other_local_of_cellId _ _ _ cellAssigned pair.first
  rw [pair.firstCell]
  simp

/-- A proved read-only computation can replace the first fresh cell without
    rebuilding either local lookup or the caller's frame. -/
theorem LocalPair.replaceFirst
    (pair : LocalPair base before firstId secondId first second) (formed : base.CellsWellFormed)
    (noViews : before.i32ArrayViews = [])
    (right : ∃ ready, RunsExpr program before expression replacement ready ∧ PureFrame before ready) :
    ∃ after, RunsExpr program before (.assign .set (.local firstId) expression) .unit after ∧
      LocalPair base after firstId secondId replacement second ∧ after.heap = before.heap ∧
      after.world = before.world ∧ after.i32ArrayViews = before.i32ArrayViews := by
  obtain ⟨ready, read, pure⟩ := right
  obtain ⟨after, run, assigned, effect⟩ := RunsExpr.assignValueAfter pair.firstCell pair.first
    read (pure.views.trans noViews)
  exact ⟨after, run, (pair.transCells pure.cells pure.locals).assignFirst formed assigned,
    effect.heap.trans pure.heap, effect.world.trans pure.world, effect.views.trans pure.views⟩

theorem LocalPair.incrementSecond {index : Nat}
    (pair : LocalPair base before firstId secondId first (.signed .i32 index))
    (formed : base.CellsWellFormed) (fits : index + 1 < 2 ^ 31) :
    ∃ after, RunsExpr program before (.assign .add (.local secondId) (.value (.signed .i32 1))) .unit after ∧
      LocalPair base after firstId secondId first (.signed .i32 (index + 1 : Nat)) ∧
      after.heap = before.heap ∧ after.world = before.world ∧ after.i32ArrayViews = before.i32ArrayViews := by
  obtain ⟨after, run, assigned, effect⟩ := RunsExpr.assignI32 (program := program)
    (op := .add) (operand := 1) (replacement := (index + 1 : Nat))
    pair.secondCell pair.second (.ofStable .value rfl) (by
      simpa only [evalAssignValue, assignOpBinary?, Int.natCast_add, Int.natCast_one] using
        eval_i32_addNat program.target index 1 fits)
  exact ⟨after, run, pair.assignSecond formed assigned, effect.heap, effect.world, effect.views⟩

/-- A scoped read/check followed by cursor replacement and counter increment.
    Temporary locals and the two fresh mutable cells are framed once here. -/
theorem LocalPair.scopedAdvance
    {index : Nat} {nextCursor : Int}
    (pair : LocalPair base before firstId secondId (.signed .i32 cursor) (.signed .i32 index))
    (formed : base.CellsWellFormed) (differentFirst : temporary ≠ firstId)
    (differentSecond : temporary ≠ secondId) (fits : index + 1 < 2 ^ 31)
    (initial : RunsExpr program before initializer value before)
    (check : RunsStmt program (before.bindLocal temporary value) prefixStmt .next (before.bindLocal temporary value))
    (read : RunsExpr program (before.bindLocal temporary value) expression (.signed .i32 nextCursor)
      (before.bindLocal temporary value)) :
    ∃ after, RunsStmt program before
      (.letLocal temporary type initializer (.sequence prefixStmt
        (.sequence (.expression (.assign .set (.local firstId) expression))
          (.sequence (.expression (.assign .add (.local secondId) (.value (.signed .i32 1)))) .skip))))
      .next after ∧ LocalPair base after firstId secondId (.signed .i32 nextCursor) (.signed .i32 (index + 1 : Nat)) ∧
      after.heap = before.heap ∧ after.world = before.world ∧ after.i32ArrayViews = before.i32ArrayViews := by
  let ready := before.bindLocal temporary value
  have beforeFormed := pair.cells.after_cellsWellFormed formed
  have firstCell : ready.cellId? firstId = some base.nextCell := by
    rw [State.bindLocal_cellId_of_ne _ _ _ differentFirst]; exact pair.firstCell
  have secondCell : ready.cellId? secondId = some (base.nextCell + 1) := by
    rw [State.bindLocal_cellId_of_ne _ _ _ differentSecond]; exact pair.secondCell
  have firstFound : ready.local? firstId = some (.signed .i32 cursor) :=
    State.bindLocal_local?_of_ne before beforeFormed _ _ _ value differentFirst pair.first
  have secondFound : ready.local? secondId = some (.signed .i32 index) :=
    State.bindLocal_local?_of_ne before beforeFormed _ _ _ value differentSecond pair.second
  obtain ⟨middle, firstRun, firstAssigned, firstEffect⟩ := RunsExpr.assignI32
    (op := .set) firstCell firstFound read rfl
  have secondCell' : middle.cellId? secondId = some (base.nextCell + 1) := by
    simpa only [State.cellId?, firstEffect.locals] using secondCell
  have secondFound' := assignCell_preserves_other_local_of_cellId _ _ _
    (assignLocal_assignCell _ _ _ firstCell firstAssigned) secondFound (by rw [secondCell]; simp)
  obtain ⟨completed, secondRun, secondAssigned, secondEffect⟩ := RunsExpr.assignI32
    (op := .add) (replacement := (index + 1 : Nat)) secondCell' secondFound' (.ofStable .value rfl) (by
      simpa only [evalAssignValue, assignOpBinary?, Int.natCast_add, Int.natCast_one] using
        eval_i32_addNat program.target index 1 fits)
  have firstCell' : completed.cellId? firstId = some base.nextCell := by
    simpa only [State.cellId?, secondEffect.locals, firstEffect.locals] using firstCell
  have secondCell'' : completed.cellId? secondId = some (base.nextCell + 1) := by
    simpa only [State.cellId?, secondEffect.locals] using secondCell'
  have firstFound' := assignCell_preserves_other_local_of_cellId _ _ _
    (assignLocal_assignCell _ _ _ secondCell' secondAssigned)
    (assignLocal_finds_assigned _ _ _ firstCell firstAssigned) (by
      have preserved : middle.cellId? firstId = some base.nextCell := by
        simpa only [State.cellId?, firstEffect.locals] using firstCell
      rw [preserved]; simp)
  have secondFound'' := assignLocal_finds_assigned _ _ _ secondCell' secondAssigned
  have cells := ((pair.cells.trans (FreshCellFrame.bindLocal before temporary value)).assignCellFresh
    formed _ _ (Nat.le_refl _) (assignLocal_assignCell _ _ _ firstCell firstAssigned)).assignCellFresh
    formed _ _ (Nat.le_succ _) (assignLocal_assignCell _ _ _ secondCell' secondAssigned)
  refine ⟨restoreLocals before completed, RunsStmt.letLocal initial (by core_stmt),
    ⟨cells.restoreLocals, pair.different, pair.locals, ?_, ?_⟩,
    secondEffect.heap.trans firstEffect.heap, secondEffect.world.trans firstEffect.world,
    secondEffect.views.trans firstEffect.views⟩
  · change (before.cellId? firstId).bind completed.cell? = _
    simpa only [State.local?, firstCell', pair.firstCell] using firstFound'
  · change (before.cellId? secondId).bind completed.cell? = _
    simpa only [State.local?, secondCell'', pair.secondCell] using secondFound''

end Lanius.Semantics
