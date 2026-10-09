import Lanius.Semantics.Assignment
import Lanius.Semantics.StmtList

namespace Lanius.Semantics

open Lanius.Core

/-- A computed i32 right-hand side and a proved scalar operation suffice for
    local assignment. Place resolution precedes the right-hand computation;
    view synchronization is unnecessary for scalar cells. -/
theorem StableExpr.assignI32
    (cellFound : before.cellId? localId = some cell)
    (localFound : before.local? localId = some (.signed .i32 current))
    (right : StableExpr threshold program before expression (.signed .i32 operand) before)
    (operation : evalAssignValue program.target op (some (.signed .i32 current))
      (.signed .i32 operand) = .ok (.signed .i32 replacement))
    (assigned : before.assignLocal localId (.signed .i32 replacement) = some after) :
    StableExpr (max 1 threshold + 1) program before
      (.assign op (.local localId) expression) .unit after := by
  have assignedCell := assignLocal_assignCell localId cell _ cellFound assigned
  intro fuel enough
  have place (access : PlaceAccess) := evalPlace_local_of_local? (fuel - 2) program before
    access localId cell _ cellFound localFound
  rw [show (fuel - 2).succ = fuel - 1 by omega] at place
  have evaluated := right (fuel - 1) (by omega)
  rw [show fuel = (fuel - 1).succ by omega, evalExpr.eq_def]
  simp only [place, evaluated, operation]
  simp [writeResolvedPlaceNative, writeResolvedPlace, assignedCell,
    ResolvedPlace.viewFreeRootWrite, valueMayContainI32ArrayView]

/-- Derive the assignment's existence from a present scalar local, not from an
    assumed successful assignment. The exact cell effect can be framed by callers. -/
theorem RunsExpr.assignI32
    (cellFound : before.cellId? localId = some cell)
    (localFound : before.local? localId = some (.signed .i32 current))
    (right : RunsExpr program before expression (.signed .i32 operand) before)
    (operation : evalAssignValue program.target op (some (.signed .i32 current))
      (.signed .i32 operand) = .ok (.signed .i32 replacement)) :
    ∃ after, RunsExpr program before (.assign op (.local localId) expression) .unit after ∧
      before.assignLocal localId (.signed .i32 replacement) = some after ∧
      CellEffect before after cell (.signed .i32 replacement) := by
  obtain ⟨after, assigned⟩ := assignLocal_exists before localId _ _ cell cellFound localFound
  have effect := assignCell_effect (assignLocal_assignCell _ _ _ cellFound assigned)
  exact ⟨after, .ofStable (StableExpr.assignI32 cellFound localFound right.choose_spec.1 operation assigned)
    effect.locals, assigned, effect⟩

/-- A local root may be uninitialized, and RHS evaluation may mutate its old
    value. The evaluator-wide identity law retains its liveness automatically.
    Native synchronization must either be unnecessary or have no views. -/
theorem RunsExpr.assignCellAfter
    (cellFound : before.cellId? localId = some cell)
    (entryFound : before.cellEntry? cell = some entry)
    (right : RunsExpr program before expression replacement ready)
    (synchronizable :
      entry.value.any valueMayContainI32ArrayView = false ∧ valueMayContainI32ArrayView replacement = false ∨
      ready.i32ArrayViews = []) :
    ∃ after, RunsExpr program before (.assign .set (.local localId) expression) .unit after ∧
      ready.assignLocal localId replacement = some after ∧ CellEffect ready after cell replacement := by
  have cellReady : ready.cellId? localId = some cell := by
    simpa only [State.cellId?, right.choose_spec.2] using cellFound
  let after := { ready with cells := replaceCell ready.cells cell replacement }
  have live := right.inventory.retainsCell entryFound
  have assignedCell : ready.assignCell cell replacement = some after := by
    simp only [State.assignCell, live, ↓reduceIte]
    rfl
  have assigned : ready.assignLocal localId replacement = some after := by
    simp only [State.assignLocal, cellReady, Option.bind_some, assignedCell]
  have effect := assignCell_effect assignedCell
  refine ⟨after, ⟨max 2 right.choose + 1, ?_, effect.locals.trans right.choose_spec.2⟩, assigned, effect⟩
  intro fuel enough
  have place : evalPlace (fuel - 1) program before .address (.local localId) =
      .done { root := cell, projections := [], value := entry.value } before := by
    rw [show fuel - 1 = (fuel - 2).succ by omega, evalPlace.eq_def]
    simp only [cellFound, entryFound]
  have evaluated := right.choose_spec.1 (fuel - 1) (by omega)
  rw [show fuel = (fuel - 1).succ by omega, evalExpr.eq_def]
  simp only [place, evaluated]
  rcases synchronizable with viewFree | noViews
  · simp [evalAssignValue, assignOpBinary?, writeResolvedPlaceNative, writeResolvedPlace, assignedCell,
      ResolvedPlace.viewFreeRootWrite, viewFree.1, viewFree.2]
  · simp [evalAssignValue, assignOpBinary?, writeResolvedPlaceNative, writeResolvedPlace, assignedCell,
      ResolvedPlace.viewFreeRootWrite, syncI32ViewsToHeap, syncI32ViewsToHeapFrom, effect.views.trans noViews]

/-- Scalar replacement needs no native synchronization. RHS cells may change;
    only the destination identity and caller's lexical bindings are retained. -/
theorem RunsExpr.assignI32After
    (cellFound : before.cellId? localId = some cell)
    (localFound : before.local? localId = some (.signed .i32 current))
    (right : RunsExpr program before expression (.signed .i32 replacement) ready) :
    ∃ after, RunsExpr program before (.assign .set (.local localId) expression) .unit after ∧
      ready.assignLocal localId (.signed .i32 replacement) = some after ∧
      CellEffect ready after cell (.signed .i32 replacement) :=
  RunsExpr.assignCellAfter cellFound (cellEntry_of_local _ _ _ _ cellFound localFound) right (.inl ⟨rfl, rfl⟩)

/-- Assign a computed aggregate to a local when no cell-backed native views
    are registered. Unlike the scalar rule, this keeps the synchronization
    premise explicit; aggregates are not silently treated as view-free. -/
theorem RunsExpr.assignValueAfter {current replacement : Value}
    (cellFound : before.cellId? localId = some cell)
    (localFound : before.local? localId = some current)
    (right : RunsExpr program before expression replacement ready)
    (noViews : ready.i32ArrayViews = []) :
    ∃ after, RunsExpr program before (.assign .set (.local localId) expression) .unit after ∧
      ready.assignLocal localId replacement = some after ∧ CellEffect ready after cell replacement :=
  RunsExpr.assignCellAfter cellFound (cellEntry_of_local _ _ _ _ cellFound localFound) right (.inr noViews)

#print axioms RunsExpr.assignCellAfter

end Lanius.Semantics
