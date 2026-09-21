import Lanius.Semantics.MutableLocal
import Lanius.Semantics.Assignment

namespace Lanius.Semantics

open Lanius.Core

@[simp] theorem restoreLocals_locals (base completed : State) :
    (restoreLocals base completed).locals = base.locals := rfl

@[simp] theorem restoreLocals_cells (base completed : State) :
    (restoreLocals base completed).cells = completed.cells := rfl

@[simp] theorem restoreLocals_heap (base completed : State) :
    (restoreLocals base completed).heap = completed.heap := rfl

@[simp] theorem restoreLocals_world (base completed : State) :
    (restoreLocals base completed).world = completed.world := rfl

@[simp] theorem restoreLocals_views (base completed : State) :
    (restoreLocals base completed).i32ArrayViews = completed.i32ArrayViews := rfl

theorem restoreLocals_local?_of_same_cell
    {base completed : State} {id : VarId} {cell : CellId} {value : Value}
    (baseCell : base.cellId? id = some cell)
    (completedCell : completed.cellId? id = some cell)
    (completedLocal : completed.local? id = some value) :
    (restoreLocals base completed).local? id = some value := by
  unfold State.local? at completedLocal ⊢
  rw [show (restoreLocals base completed).cellId? id = base.cellId? id by rfl,
    baseCell]
  simp only [Option.bind_some]
  change completed.cell? cell = some value
  rw [completedCell] at completedLocal
  simp only [Option.bind_some] at completedLocal
  simpa using completedLocal

theorem restoreLocals_local?_of_cellId_eq
    {base completed : State} {id : VarId} {value : Value}
    (cellEq : completed.cellId? id = base.cellId? id)
    (completedLocal : completed.local? id = some value) :
    (restoreLocals base completed).local? id = some value := by
  unfold State.local? at completedLocal
  cases h : completed.cellId? id with
  | none => simp [h] at completedLocal
  | some cell =>
      have baseCell : base.cellId? id = some cell := by
        rw [← cellEq, h]
      exact restoreLocals_local?_of_same_cell baseCell h completedLocal

theorem bindLocal_assignLocal_cellId_of_ne
    {base after : State} (temporary assignedId protectedId : VarId)
    (temporaryValue replacement : Value) (assignedCell cell : CellId)
    (baseCell : base.cellId? protectedId = some cell)
    (different : temporary ≠ protectedId)
    (boundAssignedCell : (base.bindLocal temporary temporaryValue).cellId? assignedId =
      some assignedCell)
    (assigned : (base.bindLocal temporary temporaryValue).assignLocal assignedId replacement =
      some after) :
    after.cellId? protectedId = some cell := by
  have boundCell : (base.bindLocal temporary temporaryValue).cellId? protectedId = some cell := by
    rw [State.bindLocal_cellId_of_ne base protectedId temporary different temporaryValue]
    exact baseCell
  have assignedCell' := assignLocal_assignCell assignedId assignedCell replacement
    boundAssignedCell assigned
  have idEq : after.cellId? protectedId =
      (base.bindLocal temporary temporaryValue).cellId? protectedId := by
    rw [assignCell_state assignedCell']
    rfl
  rw [idEq, boundCell]

end Lanius.Semantics
