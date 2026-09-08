import Lanius.Separation

namespace Lanius.Separation

open Lanius.Core Lanius.Semantics Lanius.Properties

private theorem bindLocals_cellId_lower_bound
    (bindings : List (VarId × Value)) (state : State) (lower : Nat)
    (nextBound : lower ≤ state.nextCell)
    (localsBound : ∀ id cell, state.cellId? id = some cell → lower ≤ cell) :
    ∀ id cell, (state.bindLocals bindings).cellId? id = some cell → lower ≤ cell := by
  induction bindings generalizing state with
  | nil => exact localsBound
  | cons binding rest ih =>
    apply ih (state.bindLocal binding.1 binding.2)
    · simpa only [State.bindLocal, State.bindCell] using Nat.le_step nextBound
    · intro id cell found
      by_cases same : binding.1 = id
      · subst id
        have cellEq : state.nextCell = cell := by
          simpa [State.bindLocal, State.bindCell, State.cellId?] using found
        exact cellEq ▸ nextBound
      · rw [bindLocal_preserves_other_cellId state binding.1 id binding.2 same] at found
        exact localsBound id cell found

/-- Every callee parameter cell is fresh relative to the caller's store. -/
theorem enterCall_cellId_fresh
    {id : VarId}
    (found : (enterCall caller bindings).cellId? id = some cell) :
    caller.nextCell ≤ cell := by
  exact bindLocals_cellId_lower_bound bindings { caller with locals := [] }
    caller.nextCell (Nat.le_refl _) (by
      intro id cell impossible
      simp [State.cellId?] at impossible) id cell found

/-- A callee's local-binding frame is disjoint from every pre-existing cell,
    regardless of parameter names, values, or shadowing. -/
theorem enterCall_frame_disjoint_old_cell
    (old : cell < caller.nextCell) :
    CellSet.Disjoint (localBindingFrameFootprint (enterCall caller bindings) frame)
      (CellSet.singleton cell) := by
  intro other member written
  change other = cell at written
  subst other
  obtain ⟨id, _, found⟩ := member
  exact (Nat.not_lt_of_ge (enterCall_cellId_fresh found)) old

end Lanius.Separation
