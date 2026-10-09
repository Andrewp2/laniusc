import Lanius.Semantics.StatementProof
import Lanius.Semantics.ScalarAssignment

namespace Lanius.Semantics

open Lanius.Core

/-- A fresh mutable counter with the caller's cells retained as a prefix.
    Heap and world effects are independent of this local-state invariant. -/
structure CountedLocal (base current : State) (counterId : VarId) (index : Int) : Prop where
  cells : FreshCellFrame base current
  locals : current.locals = (counterId, base.nextCell) :: base.locals
  counter : current.local? counterId = some (.signed .i32 index)

theorem CountedLocal.start (formed : base.CellsWellFormed) (counterId : VarId) (index : Int) :
    CountedLocal base (base.bindLocal counterId (.signed .i32 index)) counterId index :=
  ⟨FreshCellFrame.bindLocal base counterId _, rfl, formed.bindLocal_local _ _⟩

@[core_local_rule] theorem CountedLocal.read (frame : CountedLocal base current counterId index)
    (localId : VarId) (value : Value) (different : localId ≠ counterId)
    (found : base.local? localId = some value) : current.local? localId = some value :=
  frame.cells.localFoundAt (by simp [State.cellId?, frame.locals, Ne.symm different]) value found

theorem CountedLocal.transCells (frame : CountedLocal base before counterId index)
    (cells : FreshCellFrame before after) (locals : after.locals = before.locals) :
    CountedLocal base after counterId index :=
  ⟨frame.cells.trans cells, locals.trans frame.locals, cells.localFound locals _ _ frame.counter⟩

/-- Discharge temporary scope once, using the retained counter identity and
    caller-cell frame. Returning host/guard paths need no synthetic assignment. -/
theorem CountedLocal.restoreScoped (frame : CountedLocal base before counterId index)
    (cells : FreshCellFrame base completed) (cell : completed.cellId? counterId = some base.nextCell)
    (found : completed.local? counterId = some (.signed .i32 replacement)) :
    CountedLocal base (restoreLocals before completed) counterId replacement := by
  refine ⟨cells.restoreLocals, frame.locals, ?_⟩
  change (before.cellId? counterId).bind completed.cell? = _
  have lookup : before.cellId? counterId = some base.nextCell := by simp [State.cellId?, frame.locals]
  rw [lookup]
  simpa only [State.local?, cell, Option.bind_some] using found

/-- Update the fresh counter using a proved state-preserving computation and
    scalar operation. Scope may contain temporary locals; restoring it
    preserves the caller's cells. -/
theorem CountedLocal.assignScoped {index replacement operand : Int}
    (frame : CountedLocal base before counterId index) (formed : base.CellsWellFormed)
    (cells : FreshCellFrame base ready)
    (cell : ready.cellId? counterId = some base.nextCell)
    (found : ready.local? counterId = some (.signed .i32 index))
    (right : RunsExpr program ready expression (.signed .i32 operand) ready)
    (operation : evalAssignValue program.target op (some (.signed .i32 index)) (.signed .i32 operand) =
      .ok (.signed .i32 replacement)) :
    ∃ after, RunsExpr program ready (.assign op (.local counterId) expression)
      .unit after ∧ CountedLocal base (restoreLocals before after) counterId replacement ∧
      after.heap = ready.heap ∧ after.world = ready.world ∧ after.i32ArrayViews = ready.i32ArrayViews := by
  obtain ⟨after, run, assigned, effect⟩ := RunsExpr.assignI32
    (program := program) cell found right operation
  have retained := cells.assignCellFresh formed _ _ (Nat.le_refl _)
    (assignLocal_assignCell _ _ _ cell assigned)
  have lookup : after.cellId? counterId = some base.nextCell := by
    simpa only [State.cellId?, effect.locals] using cell
  exact ⟨after, run, frame.restoreScoped retained lookup (assignLocal_finds_assigned _ _ _ cell assigned),
    effect.heap, effect.world, effect.views⟩

/-- The reverse traversal's terminal value is -1, not truncated Nat zero. -/
theorem CountedLocal.decrementScoped {index : Nat}
    (frame : CountedLocal base before counterId index) (formed : base.CellsWellFormed)
    (cells : FreshCellFrame base ready) (cell : ready.cellId? counterId = some base.nextCell)
    (found : ready.local? counterId = some (.signed .i32 index)) (fits : index < 2 ^ 31) :
    ∃ after, RunsExpr program ready (.assign .subtract (.local counterId) (.value (.signed .i32 1)))
      .unit after ∧ CountedLocal base (restoreLocals before after) counterId ((index : Int) - 1) ∧
      after.heap = ready.heap ∧ after.world = ready.world ∧ after.i32ArrayViews = ready.i32ArrayViews :=
  frame.assignScoped formed cells cell found (.ofStable .value rfl) (by
    simpa only [evalAssignValue, assignOpBinary?] using eval_i32_predecessor program.target index fits)

theorem CountedLocal.increment {index : Nat}
    (frame : CountedLocal base before counterId index) (formed : base.CellsWellFormed)
    (fits : index + 1 < 2 ^ 31) :
    ∃ after, RunsExpr program before (.assign .add (.local counterId) (.value (.signed .i32 1)))
      .unit after ∧ CountedLocal base after counterId (index + 1 : Nat) ∧
      after.heap = before.heap ∧ after.world = before.world ∧ after.i32ArrayViews = before.i32ArrayViews := by
  obtain ⟨after, run, counter, heap, world, views⟩ := frame.assignScoped (program := program)
    (op := .add) (operand := 1) (replacement := (index + 1 : Nat)) formed frame.cells
    (by simp [State.cellId?, frame.locals]) frame.counter (.ofStable .value rfl) (by
      simpa only [evalAssignValue, assignOpBinary?, Int.natCast_one] using eval_i32_addNat program.target index 1 fits)
  have restored : restoreLocals before after = after := by
    unfold restoreLocals
    rw [← run.choose_spec.2]
  exact ⟨after, run, by simpa only [restored] using counter, heap, world, views⟩

/-- One read/action/increment iteration. The action is already proved at its
    own boundary; it may change the heap or world, but not preexisting cells.
    Temporary scope and fresh-cell framing are discharged once here. -/
theorem CountedLocal.stepWith {index : Nat}
    (frame : CountedLocal base before counterId index) (formed : base.CellsWellFormed)
    (different : temporary ≠ counterId) (fits : index + 1 < 2 ^ 31)
    (read : RunsExpr program before initializer value before)
    (actionRun : RunsStmt program (before.bindLocal temporary value) action .next middle)
    (actionCells : FreshCellFrame (before.bindLocal temporary value) middle) :
    ∃ after, RunsStmt program before
        (.letLocal temporary type initializer (.sequence action
          (.sequence (.expression (.assign .add (.local counterId) (.value (.signed .i32 1)))) .skip)))
        .next after ∧ CountedLocal base after counterId (index + 1 : Nat) ∧
      after.heap = middle.heap ∧ after.world = middle.world ∧
      after.i32ArrayViews = middle.i32ArrayViews := by
  let ready := before.bindLocal temporary value
  have beforeFormed := frame.cells.after_cellsWellFormed formed
  have localBefore : ready.local? counterId = some (.signed .i32 index) :=
    State.bindLocal_local?_of_ne before beforeFormed _ _ _ _ different frame.counter
  have localMiddle := actionCells.localFound actionRun.choose_spec.2 _ _ localBefore
  have cellBefore : ready.cellId? counterId = some base.nextCell := by
    rw [State.bindLocal_cellId_of_ne _ _ _ different]
    simp [State.cellId?, frame.locals]
  have cellMiddle : middle.cellId? counterId = some base.nextCell := by
    simpa only [State.cellId?, actionRun.choose_spec.2] using cellBefore
  obtain ⟨next, addRun, counted, heap, world, views⟩ := frame.assignScoped
    (program := program) (op := .add) (operand := 1) (replacement := (index + 1 : Nat)) formed
    ((frame.cells.trans (FreshCellFrame.bindLocal before temporary value)).trans actionCells)
    cellMiddle localMiddle (.ofStable .value rfl) (by
      simpa only [evalAssignValue, assignOpBinary?, Int.natCast_one] using
        eval_i32_addNat program.target index 1 fits)
  exact ⟨restoreLocals before next, RunsStmt.letLocal read (by core_stmt), counted, heap, world, views⟩

theorem CountedLocal.step {index : Nat}
    (frame : CountedLocal base before counterId index) (formed : base.CellsWellFormed)
    (different : temporary ≠ counterId) (fits : index + 1 < 2 ^ 31)
    (read : RunsExpr program before initializer value before)
    (actionRun : RunsExpr program (before.bindLocal temporary value) action result middle)
    (actionCells : FreshCellFrame (before.bindLocal temporary value) middle) :
    ∃ after, RunsStmt program before
        (.letLocal temporary type initializer (.sequence (.expression action)
          (.sequence (.expression (.assign .add (.local counterId) (.value (.signed .i32 1)))) .skip)))
        .next after ∧ CountedLocal base after counterId (index + 1 : Nat) ∧
      after.heap = middle.heap ∧ after.world = middle.world ∧
      after.i32ArrayViews = middle.i32ArrayViews :=
  stepWith frame formed different fits read (.expression actionRun) actionCells

#print axioms CountedLocal.assignScoped

end Lanius.Semantics
