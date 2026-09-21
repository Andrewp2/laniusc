import Lanius.Semantics.WellFormed

namespace Lanius.Semantics

open Lanius.Core

/-! A pure call may retain old cells and append only fresh parameter or body cells. -/
def FreshCellFrame (before after : State) : Prop :=
  ∃ extra : List Cell,
    after.cells = before.cells ++ extra ∧
    before.nextCell ≤ after.nextCell ∧
    ∀ cell ∈ extra, before.nextCell ≤ cell.id ∧ cell.id < after.nextCell

theorem FreshCellFrame.trans {before middle after : State}
    (first : FreshCellFrame before middle)
    (second : FreshCellFrame middle after) : FreshCellFrame before after := by
  rcases first with ⟨left, cells, frontier, fresh⟩
  rcases second with ⟨right, cells', frontier', fresh'⟩
  refine ⟨left ++ right, by rw [cells', cells, List.append_assoc],
    Nat.le_trans frontier frontier', ?_⟩
  intro cell member
  rcases List.mem_append.mp member with member | member
  · exact ⟨(fresh cell member).1,
      Nat.lt_of_lt_of_le (fresh cell member).2 frontier'⟩
  · exact ⟨Nat.le_trans frontier (fresh' cell member).1, (fresh' cell member).2⟩

theorem FreshCellFrame.bindLocal
    (state : State) (id : VarId) (value : Value) :
    FreshCellFrame state (state.bindLocal id value) := by
  refine ⟨[{ id := state.nextCell, value := some value }], rfl,
    Nat.le_succ _, ?_⟩
  intro cell member
  simp only [List.mem_singleton] at member
  subst cell
  exact ⟨Nat.le_refl _, Nat.lt_succ_self _⟩

theorem FreshCellFrame.restoreLocals {before completed : State}
    (frame : FreshCellFrame before completed) :
    FreshCellFrame before (restoreLocals before completed) := by
  rcases frame with ⟨extra, cells, frontier, fresh⟩
  refine ⟨extra, ?_, frontier, fresh⟩
  change completed.cells = before.cells ++ extra
  exact cells

theorem FreshCellFrame.after_cellsWellFormed
    {before after : State} (formed : before.CellsWellFormed)
    (frame : FreshCellFrame before after) : after.CellsWellFormed := by
  rcases frame with ⟨extra, cells, frontier, fresh⟩
  intro cell member
  rw [cells] at member
  rcases List.mem_append.mp member with old | new
  · exact Nat.lt_of_lt_of_le (formed cell old) frontier
  · exact (fresh cell new).2

theorem FreshCellFrame.localFound
    {before after : State} (frame : FreshCellFrame before after)
    (locals : after.locals = before.locals) (id : VarId) (value : Value)
    (localFound : before.local? id = some value) :
    after.local? id = some value := by
  rcases frame with ⟨extra, cells, _, _⟩
  unfold State.local? at localFound ⊢
  have cellIdEq : after.cellId? id = before.cellId? id := by
    simp [State.cellId?, locals]
  rw [cellIdEq]
  cases cell : before.cellId? id with
  | none => simp [cell] at localFound ⊢
  | some cellId =>
      simp only [cell, Option.bind_some] at localFound ⊢
      unfold State.cell? State.cellEntry? at localFound ⊢
      rw [cells, List.find?_append]
      cases entry : before.cells.find? (fun cell : Cell => cell.id == cellId) with
      | none => simp [entry] at localFound
      | some entry => simpa only [entry, Option.some_or] using localFound

end Lanius.Semantics
