import Lanius.Semantics.Typing.Store
import Lanius.Semantics.ScalarAssignment

namespace Lanius.Semantics

open Lanius Lanius.Core Lanius.Typing

theorem State.CellsHaveTypes.retained {before after : State}
    (store : before.CellsHaveTypes program types) (frame : FreshCellFrame before after) :
    after.CellsHaveTypes program types := by
  intro cell type declared
  obtain ⟨contents, present, typed⟩ := store cell type declared
  exact ⟨contents, frame.cellEntryFound present, typed⟩

/-- Local root assignment may initialize a slot and may follow an RHS which
    mutates old cells. Its induction contract supplies the resulting typed
    store; liveness follows from execution, not an unchanged-value frame. -/
theorem RunsExpr.assignLocalTyped {before ready : State}
    (store : before.CellsHaveTypes program types) (declared : types cell = some type)
    (replacementTyped : ValueHasType program replacement type)
    (cellFound : before.cellId? localId = some cell)
    (right : RunsExpr program before expression replacement ready)
    (readyStore : ready.CellsHaveTypes program types) (noViews : ready.i32ArrayViews = []) :
    ∃ after, RunsExpr program before (.assign .set (.local localId) expression) .unit after ∧
      after.CellsHaveTypes program types ∧ after.local? localId = some replacement := by
  obtain ⟨contents, entryFound, _⟩ := store cell type declared
  obtain ⟨after, run, assigned, effect⟩ := RunsExpr.assignCellAfter cellFound entryFound right (.inr noViews)
  have readyCell : ready.cellId? localId = some cell := by
    simpa only [State.cellId?, right.choose_spec.2] using cellFound
  exact ⟨after, run, readyStore.cellEffect effect declared replacementTyped,
    assignLocal_finds_assigned _ _ _ readyCell assigned⟩

#print axioms RunsExpr.assignLocalTyped

end Lanius.Semantics
