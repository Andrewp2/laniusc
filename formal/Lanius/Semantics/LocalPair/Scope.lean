import Lanius.Semantics.LocalPair
import Lanius.Semantics.LocalScope

namespace Lanius.Semantics

open Lanius.Core

variable {base before ready after : State} {firstId secondId assignedId : VarId}
  {first second replacement : Value}

/-- Assign either captured fresh cell through temporary lexical scope. The
    prefix may have heap/world effects; only its fresh-cell frame is needed. -/
theorem LocalPair.assignScoped
    (pair : LocalPair base before firstId secondId first second)
    (formed : base.CellsWellFormed) (cells : FreshCellFrame before ready)
    (firstCaptured : ready.cellId? firstId = before.cellId? firstId)
    (secondCaptured : ready.cellId? secondId = before.cellId? secondId)
    (selected : assignedId = firstId ∨ assignedId = secondId)
    (assigned : ready.assignLocal assignedId replacement = some after) :
    LocalPair base (restoreLocals before after) firstId secondId
      (if assignedId = firstId then replacement else first)
      (if assignedId = secondId then replacement else second) := by
  have firstCell := firstCaptured.trans pair.firstCell
  have secondCell := secondCaptured.trans pair.secondCell
  have firstFound := cells.localFoundAt firstCaptured _ pair.first
  have secondFound := cells.localFoundAt secondCaptured _ pair.second
  rcases selected with selected | selected
  · subst assignedId
    simp only [if_pos rfl, if_neg pair.different]
    have written := assignLocal_assignCell _ _ _ firstCell assigned
    have effect := assignCell_effect written
    have nextCells := (pair.cells.trans cells).assignCellFresh formed _ _ (Nat.le_refl _) written
    have firstAfter := assignLocal_finds_assigned _ _ _ firstCell assigned
    have secondAfter := assignCell_preserves_other_local_of_cellId _ _ _ written secondFound
      (by rw [secondCell]; simp)
    have firstCellAfter : after.cellId? firstId = some base.nextCell := by
      simpa only [State.cellId?, effect.locals] using firstCell
    have secondCellAfter : after.cellId? secondId = some (base.nextCell + 1) := by
      simpa only [State.cellId?, effect.locals] using secondCell
    exact ⟨nextCells.restoreLocals, pair.different, pair.locals,
      restoreLocals_local?_of_same_cell pair.firstCell firstCellAfter firstAfter,
      restoreLocals_local?_of_same_cell pair.secondCell secondCellAfter secondAfter⟩
  · subst assignedId
    simp only [if_neg (Ne.symm pair.different), if_pos rfl]
    have written := assignLocal_assignCell _ _ _ secondCell assigned
    have effect := assignCell_effect written
    have nextCells := (pair.cells.trans cells).assignCellFresh formed _ _ (Nat.le_succ _) written
    have secondAfter := assignLocal_finds_assigned _ _ _ secondCell assigned
    have firstAfter := assignCell_preserves_other_local_of_cellId _ _ _ written firstFound
      (by rw [firstCell]; simp)
    have firstCellAfter : after.cellId? firstId = some base.nextCell := by
      simpa only [State.cellId?, effect.locals] using firstCell
    have secondCellAfter : after.cellId? secondId = some (base.nextCell + 1) := by
      simpa only [State.cellId?, effect.locals] using secondCell
    exact ⟨nextCells.restoreLocals, pair.different, pair.locals,
      restoreLocals_local?_of_same_cell pair.firstCell firstCellAfter firstAfter,
      restoreLocals_local?_of_same_cell pair.secondCell secondCellAfter secondAfter⟩

#print axioms LocalPair.assignScoped

end Lanius.Semantics
