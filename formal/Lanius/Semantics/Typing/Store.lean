import Lanius.Semantics.Typing.Cell

namespace Lanius.Semantics

open Lanius Lanius.Core Lanius.Typing

/-- One declared type per cell identity, shared by all aliases of that root. -/
abbrev CellTypes := CellId → Option Ty

/-- Declared cells are live; their contents, when initialized, have the declared
    type. Unmapped cells and validity of reference/native-heap targets are not
    asserted. This is proof-library state, not another emitted typing tree. -/
def State.CellsHaveTypes (state : State) (program : Program) (types : CellTypes) : Prop :=
  ∀ cell type, types cell = some type → ∃ contents,
    state.cellEntry? cell = some { id := cell, value := contents } ∧
      match contents with
      | none => True
      | some value => ValueHasType program value type

/-- A cell-backed place follows its root's declared type, irrespective of the
    cached value in `ResolvedPlace`. Thus old aliases remain valid after writes. -/
def CellPlaceHasType (program : Program) (types : CellTypes) (place : ResolvedPlace) (type : Ty) : Prop :=
  ∃ rootType, types place.root = some rootType ∧
    ProjectionHasType program rootType place.projections type ∧ place.raw = none

/-- Allocation extends the declared store at the fresh identity, including a
    typed but uninitialized slot. Existing aliases retain their root types. -/
theorem State.CellsHaveTypes.bindCell {state : State}
    (store : state.CellsHaveTypes program types) (formed : state.CellsWellFormed)
    (typed : match contents with | none => True | some value => ValueHasType program value type) :
    (state.bindCell localId contents).CellsHaveTypes program
      (fun cell => if cell = state.nextCell then some type else types cell) := by
  intro cell declared found
  by_cases same : cell = state.nextCell
  · subst cell
    simp only at found
    cases found
    refine ⟨contents, ?_, typed⟩
    have fresh := formed.cellEntry_nextCell
    unfold State.cellEntry? at fresh ⊢
    simp [State.bindCell, List.find?_append, fresh]
  · have old : types cell = some declared := by simpa only [if_neg same] using found
    obtain ⟨previous, present, previousTyped⟩ := store cell declared old
    refine ⟨previous, ?_, previousTyped⟩
    unfold State.cellEntry? at present ⊢
    simp [State.bindCell, List.find?_append, present]

theorem State.CellsHaveTypes.cellEffect {before after : State}
    (store : before.CellsHaveTypes program types) (effect : CellEffect before after cell replacement)
    (declared : types cell = some type) (typed : ValueHasType program replacement type) :
    after.CellsHaveTypes program types := by
  intro queried queriedType found
  obtain ⟨contents, present, contentsTyped⟩ := store queried queriedType found
  by_cases same : queried = cell
  · subst queried
    have sameType : queriedType = type := Option.some.inj (found.symm.trans declared)
    subst queriedType
    refine ⟨some replacement, ?_, typed⟩
    unfold State.cellEntry? at present ⊢
    rw [effect.cells, replaceCell_find_same before.cells cell replacement _ present]
  · exact ⟨contents, effect.otherCell same present, contentsTyped⟩

/-- Initialized, declared storage supplies a correctly typed read through any
    alias path; being shape-typed as a reference alone is not enough. -/
theorem State.CellsHaveTypes.read {state : State}
    (store : state.CellsHaveTypes program types) (placeTyped : CellPlaceHasType program types place type)
    (initialized : state.cell? place.root ≠ none) :
    ∃ value, readCellProjection state place.root place.projections = .ok value ∧
      ValueHasType program value type := by
  obtain ⟨rootType, declared, path, _⟩ := placeTyped
  obtain ⟨contents, stored, typed⟩ := store place.root rootType declared
  cases contents with
  | none => simp [State.cell?, stored] at initialized
  | some root => exact readCellProjection_typed path typed stored

/-- A typed cell write preserves the entire declared store and reads back the
    replacement. Root assignment may initialize a slot; the only permitted
    failure is a nested write into an uninitialized root. No success is assumed. -/
theorem State.CellsHaveTypes.write {state : State}
    (store : state.CellsHaveTypes program types) (placeTyped : CellPlaceHasType program types place type)
    (replacementTyped : ValueHasType program replacement type) :
    match writeResolvedPlaceNative program state place replacement with
    | .ok after => after.CellsHaveTypes program types ∧
        readCellProjection after place.root place.projections = .ok replacement
    | .error reason => reason = .uninitializedLocal ∧ place.projections ≠ [] := by
  obtain ⟨rootType, declared, path, cellBacked⟩ := placeTyped
  obtain ⟨contents, stored, contentsTyped⟩ := store place.root rootType declared
  cases projections : place.projections with
  | nil =>
    have sameType : rootType = type := by rw [projections] at path; cases path; rfl
    subst rootType
    let after := { state with cells := replaceCell state.cells place.root replacement }
    have assigned : state.assignCell place.root replacement = some after := by
      simp [State.assignCell, stored, after]
    have present := assignCell_finds_assigned assigned
    have written : writeResolvedPlaceNative program state place replacement = .ok after := by
      simp [writeResolvedPlaceNative, cellBacked, writeResolvedPlace, projections, assigned]
    rw [written]
    exact ⟨store.cellEffect (assignCell_effect assigned) declared replacementTyped,
      by simp [readCellProjection, present, projectedValue]⟩
  | cons head tail =>
    cases contents with
    | none => simp [writeResolvedPlaceNative, cellBacked, writeResolvedPlace, projections, stored]
    | some root =>
      obtain ⟨after, updated, written, _, updatedTyped, readBack, _, effect⟩ :=
        writeResolvedPlaceNative_typed cellBacked path contentsTyped stored replacementTyped
      rw [written]
      exact ⟨store.cellEffect effect declared updatedTyped, by simpa only [projections] using readBack⟩

#print axioms State.CellsHaveTypes.write

end Lanius.Semantics
