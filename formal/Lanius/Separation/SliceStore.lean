import Lanius.Separation.CellEffect

namespace Lanius.Separation

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Fuel

theorem local_cell_ne_of_distinct_value {before : State} {value oldValue : Value}
    {written cell : CellId} {id : VarId}
    (localValue : before.local? id = some value)
    (backing : before.cellEntry? written = some { id := written, value := some oldValue })
    (different : value ≠ oldValue) (binding : before.cellId? id = some cell) : cell ≠ written := by
  intro same
  subst cell
  have oldLocal : before.local? id = some oldValue := by simp [State.local?, binding, State.cell?, backing]
  exact different (Option.some.inj (localValue.symm.trans oldLocal))

theorem CellEffect.preserves_local_of_distinct_value {id : VarId}
    (frame : CellEffect (CellSet.singleton written) before after)
    (wellFormed : StateWellFormed before) (localValue : before.local? id = some value)
    (backing : before.cellEntry? written = some { id := written, value := some oldValue })
    (different : value ≠ oldValue) : after.local? id = some value := by
  apply frame.preserves_local wellFormed localValue
  intro cell binding changed
  exact local_cell_ne_of_distinct_value localValue backing different binding changed

/-- An indexed store whose right-hand side may allocate borrowed storage.
The location is resolved before the right-hand side, as in Core semantics. -/
theorem evaluatesSliceStore (program : Program) (before afterRight : State)
    (values : List Int) (sliceId : VarId) (indexExpression right : Expr)
    (cell : CellId) (index : Nat) (replacement : Int)
    (wellFormed : StateWellFormed before) (inBounds : index < values.length)
    (sliceLocal : before.local? sliceId = some
      (.slice (.scalar (.signed .i32)) cell [] 0 values.length))
    (indexResult : Evaluates program before indexExpression (.signed .i32 (Int.ofNat index)) before)
    (rightResult : Evaluates program before right (.signed .i32 replacement) afterRight)
    (rightEffect : CellEffect CellSet.empty before afterRight)
    (backing : before.cellEntry? cell = some {
      id := cell, value := some (.array (signedI32Values values)) }) :
    ∃ after, Evaluates program before
        (.assign .set (.index (.local sliceId) indexExpression) right) .unit after ∧
      after.cellEntry? cell = some {
        id := cell, value := some (.array (signedI32Values (values.set index replacement))) } ∧
      CellEffect (CellSet.singleton cell) before after := by
  have backingAtWrite := rightEffect.empty_preserves_entry wellFormed backing
  obtain ⟨placeFuel, placeResult⟩ := evaluatesSignedI32SlicePlace program before before
    values sliceId indexExpression cell index inBounds sliceLocal indexResult backing
  obtain ⟨rightFuel, rightAtFuel⟩ := rightResult
  let updated := values.set index replacement
  let after : State := { afterRight with
    cells := replaceCell afterRight.cells cell (.array (signedI32Values updated)) }
  have assigned : afterRight.assignCell cell (.array (signedI32Values updated)) = some after := by
    simp [State.assignCell, backingAtWrite, after]
  have valueAt : (signedI32Values values)[index]? =
      some (.signed .i32 (values.get ⟨index, inBounds⟩)) := by
    simp [signedI32Values, inBounds]
  have written : writeResolvedPlace afterRight {
      root := cell, projections := [.index index],
      value := some (.signed .i32 (values.get ⟨index, inBounds⟩))
    } (.signed .i32 replacement) = .ok after := by
    simp [writeResolvedPlace, backingAtWrite, replaceProjectedValue, valueAt,
      setValue_signedI32Values, setI32Value, updated, assigned]
  let fuel := max placeFuel rightFuel
  have placeAtFuel := evalPlace_done_at_larger_fuel (Nat.le_max_left placeFuel rightFuel) placeResult
  have rightAtCommonFuel := evalExpr_done_at_larger_fuel (Nat.le_max_right placeFuel rightFuel) rightAtFuel
  have execution : Evaluates program before
      (.assign .set (.index (.local sliceId) indexExpression) right) .unit after := by
    refine ⟨fuel + 1, ?_⟩
    rw [evalExpr.eq_def]
    simp only
    rw [placeAtFuel]
    simp only
    rw [rightAtCommonFuel]
    simp only [evalAssignValue, assignOpBinary?]
    rw [written]
  have afterWF := assignCell_preserves_well_formed rightEffect.wellFormed assigned
  have storeEffect := CellEffect.ofModifiesOnly (assignCell_effect assigned) afterWF
  exact ⟨after, execution, assignCell_finds_assigned assigned,
    (rightEffect.weaken CellSet.empty_subset).trans storeEffect⟩

end Lanius.Separation
