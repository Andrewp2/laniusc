import Lanius.Semantics.Typing.Projection
import Lanius.Semantics.Assignment

namespace Lanius.Semantics

open Lanius.Core Lanius.Typing

/-- A live, initialized, typed cell supplies a correctly typed projected read. -/
theorem readCellProjection_typed {state : State}
    (path : ProjectionHasType program rootType projections type)
    (typed : ValueHasType program root rootType)
    (stored : state.cellEntry? cell = some { id := cell, value := some root }) :
    ∃ value, readCellProjection state cell projections = .ok value ∧
      ValueHasType program value type := by
  obtain ⟨value, evaluated, valueTyped⟩ := projectedValue_typed path typed
  exact ⟨value, by simpa [readCellProjection, stored] using evaluated, valueTyped⟩

/-- The cell-backed branch of the native-aware writer succeeds, preserves the
    root type and returns the replacement on read-back. The cell effect frames other cells,
    locals, heap, host world and registered views. Native-heap writes and view
    synchronization require their separate contracts. -/
theorem writeResolvedPlaceNative_typed {state : State} {place : ResolvedPlace}
    (cellBacked : place.raw = none)
    (path : ProjectionHasType program rootType place.projections type)
    (typed : ValueHasType program root rootType)
    (stored : state.cellEntry? place.root = some { id := place.root, value := some root })
    (replacementTyped : ValueHasType program replacement type) :
    ∃ after updated, writeResolvedPlaceNative program state place replacement = .ok after ∧
      after.cellEntry? place.root = some { id := place.root, value := some updated } ∧
      ValueHasType program updated rootType ∧
      readCellProjection after place.root place.projections = .ok replacement ∧
      replaceProjectedValue root place.projections replacement = .ok updated ∧
      CellEffect state after place.root updated := by
  obtain ⟨updated, evaluated, updatedTyped, readBack⟩ := replaceProjectedValue_typed path typed replacementTyped
  let after := { state with cells := replaceCell state.cells place.root updated }
  have assigned : state.assignCell place.root updated = some after := by
    simp [State.assignCell, stored, after]
  have written : writeResolvedPlace state place replacement = .ok after := by
    cases projections : place.projections with
    | nil =>
      have same : replacement = updated := by
        simpa [replaceProjectedValue, projections] using evaluated
      simp [writeResolvedPlace, projections, same, assigned]
    | cons head tail =>
      rw [projections] at evaluated
      simp [writeResolvedPlace, projections, stored, evaluated, assigned]
  have present := assignCell_finds_assigned assigned
  exact ⟨after, updated, by simpa [writeResolvedPlaceNative, cellBacked] using written, present, updatedTyped,
    by simpa [readCellProjection, present] using readBack, evaluated, assignCell_effect assigned⟩

#print axioms readCellProjection_typed
#print axioms writeResolvedPlaceNative_typed

end Lanius.Semantics
