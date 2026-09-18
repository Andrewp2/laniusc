import Lanius.Semantics.Capacity.State
import Lanius.Semantics.Capacity.Projection

namespace Lanius.Semantics.Capacity
open Lanius.Core Lanius.Properties

private theorem replace_cells (config : Config) (entries : List Cell) (id : CellId) (replacement : Value) :
    replaceCell (entries.map (cell config)) id (stored config id replacement) =
      (replaceCell entries id replacement).map (cell config) := by
  induction entries with
  | nil => rfl
  | cons first rest ih =>
    by_cases same : first.id = id <;> simp [replaceCell, cell, same, ih]

theorem assignCell (config : Config) (before : State) (id : CellId) (replacement : Value) :
    (state config before).assignCell id (stored config id replacement) =
      (before.assignCell id replacement).map (state config) := by
  simp only [State.assignCell, cellEntry, Option.isSome_map]
  split
  · simp [state, replace_cells]
  · rfl

theorem Ready.assignCell {id : CellId} (ready : Ready config before)
    (replacementClosed : closed config replacement = true)
    (rootArray : id = config.root → ∃ entries, replacement = .array entries)
    (assigned : before.assignCell id replacement = some after) : Ready config after := by
  have shape := assignCell_state assigned
  refine ⟨by simpa only [shape] using ready.frontier, ?_, by simpa only [shape] using ready.locals, ?_⟩
  · by_cases same : id = config.root
    · obtain ⟨entries, rfl⟩ := rootArray same
      exact ⟨entries, by simp only [State.cell?, ← same, assignCell_finds_assigned assigned, Option.bind_some]⟩
    · obtain ⟨entries, found⟩ := ready.root
      exact ⟨entries, by simpa only [State.cell?, assignCell_preserves_other assigned (Ne.symm same)] using found⟩
  · intro entry member reachable contents found
    rw [shape, replaceCell_eq_map] at member
    obtain ⟨original, old, rfl⟩ := List.mem_map.mp member
    split at found
    · cases found; exact replacementClosed
    · rename_i different
      exact ready.cells original old (by simpa [different] using reachable) contents found

theorem readCellProjection_eq_cell (before : State) (id : CellId) (path : List ValueProjection)
    (found : before.cell? id = some original) :
    Semantics.readCellProjection before id path = Semantics.projectedValue original path := by
  obtain ⟨entry, selected, contents⟩ := Option.bind_eq_some_iff.mp found
  rcases entry with ⟨entryId, entryContents⟩
  change entryContents = some original at contents
  simp only [Semantics.readCellProjection, selected, contents]

theorem readCellProjection (config : Config) (ready : Ready config before) {id : CellId}
    (reachable : config.reachable id = true) (path : List ValueProjection)
    (notWhole : id = config.root → path ≠ [])
    (read : Semantics.readCellProjection before id path = .ok result) :
    Semantics.readCellProjection (state config before) id path = .ok (value config result) ∧
      closed config result = true := by
  cases selected : before.cellEntry? id with
  | none => simp [Semantics.readCellProjection, selected] at read
  | some entry =>
    rcases entry with ⟨entryId, entryContents⟩
    cases contents : entryContents with
    | none => simp [Semantics.readCellProjection, selected, contents] at read
    | some original =>
      have found : before.cell? id = some original := by simp [State.cell?, selected, contents]
      rw [readCellProjection_eq_cell before id path found] at read
      have transformed : (state config before).cell? id = some (stored config id original) := by rw [cellValue, found]; rfl
      refine ⟨?_, projectedValue_closed config original path (ready.cellClosed reachable found) read⟩
      rw [readCellProjection_eq_cell _ _ _ transformed]
      by_cases same : id = config.root
      · obtain ⟨entries, rootFound⟩ := ready.root
        have originalArray : original = .array entries := Option.some.inj (found.symm.trans (same ▸ rootFound))
        subst original
        cases path with
        | nil => exact False.elim (notWhole same rfl)
        | cons projection rest =>
          simpa only [stored, same, ↓reduceIte] using projectedValue_append config entries projection rest read
      · rw [stored_reachable config reachable same, projectedValue, read]; rfl

def resolvedPlace (config : Config) (place : ResolvedPlace) : ResolvedPlace :=
  { place with value := place.value.map (value config) }

structure PlaceReady (config : Config) (place : ResolvedPlace) : Prop where
  reachable : config.reachable place.root = true
  notWhole : place.root = config.root → place.projections ≠ []
  contents : ∀ entry, place.value = some entry → closed config entry = true

theorem writeResolvedPlace (config : Config) (ready : Ready config before)
    (placeReady : PlaceReady config place) (replacementClosed : closed config replacement = true)
    (written : Semantics.writeResolvedPlace before place replacement = .ok after) :
    Semantics.writeResolvedPlace (state config before) (resolvedPlace config place) (value config replacement) = .ok (state config after) ∧
      Ready config after := by
  rcases place with ⟨root, path, oldValue⟩
  cases path with
  | nil =>
    have different : root ≠ config.root := fun same => placeReady.notWhole same rfl
    simp only [Semantics.writeResolvedPlace] at written
    cases assigned : before.assignCell root replacement with
    | none => simp [assigned] at written
    | some next =>
      simp only [assigned, Except.ok.injEq] at written
      subst after
      refine ⟨?_, ready.assignCell replacementClosed (fun same => False.elim (different same)) assigned⟩
      simp only [resolvedPlace, Semantics.writeResolvedPlace]
      rw [← stored_reachable config placeReady.reachable different, assignCell, assigned]
      rfl
  | cons projection rest =>
    cases selected : before.cellEntry? root with
    | none => simp [Semantics.writeResolvedPlace, selected] at written
    | some entry =>
      rcases entry with ⟨entryId, entryContents⟩
      cases contents : entryContents with
      | none => simp [Semantics.writeResolvedPlace, selected, contents] at written
      | some original =>
        have found : before.cell? root = some original := by simp [State.cell?, selected, contents]
        have sameId : entryId = root := by simpa using List.find?_some selected
        simp only [Semantics.writeResolvedPlace, selected, contents] at written
        cases replaced : Semantics.replaceProjectedValue original (projection :: rest) replacement with
        | error reason => simp [replaced] at written
        | ok updated =>
          simp only [replaced] at written
          cases assigned : before.assignCell root updated with
          | none => simp [assigned] at written
          | some next =>
            simp only [assigned, Except.ok.injEq] at written
            subst after
            have updateClosed := replaceProjectedValue_closed config original replacement (projection :: rest)
              (ready.cellClosed placeReady.reachable found) replacementClosed replaced
            have transport : Semantics.replaceProjectedValue (stored config root original) (projection :: rest)
                (value config replacement) = .ok (stored config root updated) := by
              by_cases same : root = config.root
              · obtain ⟨entries, rootFound⟩ := ready.root
                have originalArray : original = .array entries := Option.some.inj (found.symm.trans (same ▸ rootFound))
                subst original
                obtain ⟨updatedEntries, rfl, transported⟩ := replaceProjectedValue_append config entries projection rest replacement updated replaced
                simpa only [stored, same, ↓reduceIte] using transported
              · simp only [stored_reachable config placeReady.reachable same, replaceProjectedValue, replaced, Except.map]
            have rootArray : root = config.root → ∃ entries, updated = .array entries := by
              intro same
              obtain ⟨entries, rootFound⟩ := ready.root
              have originalArray : original = .array entries := Option.some.inj (found.symm.trans (same ▸ rootFound))
              subst original
              obtain ⟨updatedEntries, array, _⟩ := replaceProjectedValue_append config entries projection rest replacement updated replaced
              exact ⟨updatedEntries, array⟩
            refine ⟨?_, ready.assignCell updateClosed rootArray assigned⟩
            simp only [resolvedPlace, Semantics.writeResolvedPlace, cellEntry, selected, Option.map_some,
              cell, contents, sameId, transport, assignCell, assigned]

end Lanius.Semantics.Capacity
