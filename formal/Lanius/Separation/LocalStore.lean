import Lanius.Separation.HeapFrame

namespace Lanius.Separation

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Fuel

/-- Assignment resolves its local before executing the RHS. An effectful RHS
may update its own footprint while retaining that captured cell. The final
write is to the captured cell, not a second lookup after the RHS returns. -/
theorem evaluatesFramedLocalUpdate
    (wellFormed : StateWellFormed before)
    (owned : (Assertion.localPointsTo localId cell current).holds before)
    (rightResult : Evaluates program before right value middle)
    (rightEffect : CellEffect writes before middle) (untouched : ¬ writes cell)
    (operation : evalAssignValue program.target op current value = .ok replacement) :
    ∃ after, Evaluates program before (.assign op (.local localId) right) .unit after ∧
      (Assertion.localPointsTo localId cell (some replacement)).holds after ∧
      CellEffect (CellSet.union writes (CellSet.singleton cell)) before after ∧
      HeapFrame middle after ∧ CellEffect (CellSet.singleton cell) middle after := by
  have retained := rightEffect.preserves_localPointsTo wellFormed owned untouched
  let after : State := { middle with cells := replaceCell middle.cells cell replacement }
  have assigned : middle.assignCell cell replacement = some after := by
    simp [State.assignCell, retained.2, after]
  have placeResult : evalPlace 1 program before (.local localId) =
      .done { root := cell, projections := [], value := current } before := by
    rw [evalPlace.eq_def]
    simp [owned.1, owned.2]
  have written : writeResolvedPlace middle
      { root := cell, projections := [], value := current } replacement = .ok after := by
    simp [writeResolvedPlace, assigned]
  have updateEffect : CellEffect (CellSet.singleton cell) middle after :=
    CellEffect.ofModifiesOnly (assignCell_effect assigned)
      (assignCell_preserves_well_formed rightEffect.wellFormed assigned)
  obtain ⟨rightFuel, rightAtFuel⟩ := rightResult
  let fuel := max 1 rightFuel
  have placeAtFuel := evalPlace_done_at_larger_fuel (Nat.le_max_left 1 rightFuel) placeResult
  have rightAtCommon := evalExpr_done_at_larger_fuel (Nat.le_max_right 1 rightFuel) rightAtFuel
  refine ⟨after, ⟨fuel + 1, ?_⟩, assignCell_localPointsTo retained assigned,
    (rightEffect.weaken CellSet.subset_union_left).trans
      (updateEffect.weaken CellSet.subset_union_right), ⟨rfl, rfl⟩, updateEffect⟩
  rw [evalExpr.eq_def]
  simp only
  rw [placeAtFuel]
  simp only
  rw [rightAtCommon]
  simp only
  rw [operation]
  simp only [written]

/-- Update an owned local using a pure RHS, for either plain or compound
    assignment. The operator's checked arithmetic result is explicit. -/
theorem evaluatesOwnedLocalUpdate
    (wellFormed : StateWellFormed before)
    (owned : (Assertion.localPointsTo localId cell current).holds before)
    (rightResult : Evaluates program before right value before)
    (operation : evalAssignValue program.target op current value = .ok replacement) :
    ∃ after, Evaluates program before (.assign op (.local localId) right) .unit after ∧
      (Assertion.localPointsTo localId cell (some replacement)).holds after ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  let after : State := { before with cells := replaceCell before.cells cell replacement }
  have assigned : before.assignCell cell replacement = some after := by
    simp [State.assignCell, owned.2, after]
  have placeResult : evalPlace 1 program before (.local localId) =
      .done { root := cell, projections := [], value := current } before := by
    rw [evalPlace.eq_def]
    simp [owned.1, owned.2]
  have written : writeResolvedPlace before
      { root := cell, projections := [], value := current } replacement = .ok after := by
    simp [writeResolvedPlace, assigned]
  obtain ⟨rightFuel, rightAtFuel⟩ := rightResult
  let fuel := max 1 rightFuel
  have placeAtFuel := evalPlace_done_at_larger_fuel (Nat.le_max_left 1 rightFuel) placeResult
  have rightAtCommon := evalExpr_done_at_larger_fuel (Nat.le_max_right 1 rightFuel) rightAtFuel
  refine ⟨after, ?_, assignCell_localPointsTo owned assigned,
    CellEffect.ofModifiesOnly (assignCell_effect assigned)
      (assignCell_preserves_well_formed wellFormed assigned), ⟨rfl, rfl⟩⟩
  refine ⟨fuel + 1, ?_⟩
  rw [evalExpr.eq_def]
  simp only
  rw [placeAtFuel]
  simp only
  rw [rightAtCommon]
  simp only
  rw [operation]
  simp only [written]

/-- The reader's `remaining -= 1` cannot wrap on a nonempty iteration. -/
theorem evaluatesDecrementOwnedI32Local
    (wellFormed : StateWellFormed before)
    (owned : (Assertion.localPointsTo localId cell
      (some (.signed .i32 (Int.ofNat (remaining + 1))))).holds before)
    (bounded : remaining + 1 ≤ 2147483647) :
    ∃ after, Evaluates program before
      (.assign .subtract (.local localId) (.value (.signed .i32 1))) .unit after ∧
      (Assertion.localPointsTo localId cell (some (.signed .i32 (Int.ofNat remaining)))).holds after ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  apply evaluatesOwnedLocalUpdate wellFormed owned
    (show Evaluates program before (.value (.signed .i32 1)) (.signed .i32 1) before from ⟨1, rfl⟩)
  have subtraction : Int.ofNat (remaining + 1) - 1 = Int.ofNat remaining := by
    change ((remaining + 1 : Nat) : Int) - 1 = (remaining : Int)
    omega
  simp only [evalAssignValue, assignOpBinary?, evalBinaryValue,
    beq_self_eq_true, if_true, evalSignedBinary]
  rw [subtraction, wrapSigned_i32_ofNat program.target remaining (by omega)]

end Lanius.Separation
