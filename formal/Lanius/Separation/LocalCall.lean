import Lanius.Separation.CellEffect
import Lanius.Separation.HeapFrame

namespace Lanius.Separation

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Fuel

/-- Assign the result of an effectful call to a retained local. Unlike the
older ModifiesOnly interface, the RHS may allocate borrowed storage; only
the destination's ownership must survive the call. -/
theorem evaluatesOwnedLocalSet
    (ownedBefore : (Assertion.localPointsTo localId cell current).holds before)
    (rightResult : Evaluates program before right value afterRight)
    (rightEffect : CellEffect writes before afterRight)
    (ownedAfter : (Assertion.localPointsTo localId cell current).holds afterRight) :
    ∃ after, Evaluates program before (.assign .set (.local localId) right) .unit after ∧
      (Assertion.localPointsTo localId cell (some value)).holds after ∧
      CellEffect (CellSet.union writes (CellSet.singleton cell)) before after ∧
      CellEffect (CellSet.singleton cell) afterRight after ∧ HeapFrame afterRight after ∧
      after.nextCell = afterRight.nextCell := by
  let after : State := { afterRight with cells := replaceCell afterRight.cells cell value }
  have assigned : afterRight.assignCell cell value = some after := by
    simp [State.assignCell, ownedAfter.2, after]
  have place : evalPlace 1 program before (.local localId) =
      .done { root := cell, projections := [], value := current } before := by
    rw [evalPlace.eq_def]
    simp [ownedBefore.1, ownedBefore.2]
  have written : writeResolvedPlace afterRight
      { root := cell, projections := [], value := current } value = .ok after := by
    simp [writeResolvedPlace, assigned]
  obtain ⟨rightFuel, rightRun⟩ := rightResult
  let fuel := max 1 rightFuel
  have run : Evaluates program before (.assign .set (.local localId) right) .unit after := by
    refine ⟨fuel + 1, ?_⟩
    rw [evalExpr.eq_def]
    simp only
    rw [evalPlace_done_at_larger_fuel (Nat.le_max_left 1 rightFuel) place]
    simp only
    rw [evalExpr_done_at_larger_fuel (Nat.le_max_right 1 rightFuel) rightRun]
    simp only [evalAssignValue, assignOpBinary?, written]
  have effect := CellEffect.ofModifiesOnly (assignCell_effect assigned)
    (assignCell_preserves_well_formed rightEffect.wellFormed assigned)
  exact ⟨after, run, assignCell_localPointsTo ownedAfter assigned,
    (rightEffect.weaken CellSet.subset_union_left).trans (effect.weaken CellSet.subset_union_right),
    effect, ⟨rfl, rfl⟩, rfl⟩

end Lanius.Separation
