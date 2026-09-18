import Lanius.Semantics.Capacity.Storage

namespace Lanius.Semantics.Capacity
open Lanius.Core

def extent (config : Config) (root : CellId) (path : List ValueProjection) (length : Nat) : Nat :=
  if root = config.root ∧ path = [] then length + config.tail.length else length

theorem extent_le (config : Config) (root : CellId) (path : List ValueProjection) (length : Nat) :
    length ≤ extent config root path length := by unfold extent; split <;> omega

private theorem slice_contents (read : Semantics.sliceValues before root path start length = .ok entries) :
    ∃ original, Semantics.readCellProjection before root path = .ok (.array original) ∧
      start + length ≤ original.length ∧ entries = (original.drop start).take length := by
  unfold Semantics.sliceValues at read
  split at read
  · rename_i original found
    split at read
    · rename_i bound
      exact ⟨original, found, bound, (Except.ok.inj read).symm⟩
    · contradiction
  · contradiction
  · contradiction

/-- Only indexes already valid in the logical slice are transported. New
capacity is deliberately not claimed to contain meaningful source data. -/
theorem slice_index (config : Config) (ready : Ready config before) {root : CellId}
    (reachable : config.reachable root = true)
    (inside : index < length)
    (read : Semantics.sliceValues before root path start length = .ok entries)
    (selected : entries[index]? = some result) :
    ∃ expanded, Semantics.sliceValues (state config before) root path start (extent config root path length) = .ok expanded ∧
      expanded[index]? = some (value config result) ∧ closed config result = true := by
  obtain ⟨original, projected, bounded, rfl⟩ := slice_contents read
  have found : original[start + index]? = some result := by
    simpa only [List.getElem?_take_of_lt inside, List.getElem?_drop] using selected
  by_cases whole : root = config.root ∧ path = []
  · rcases whole with ⟨rfl, rfl⟩
    obtain ⟨rootEntries, rootFound⟩ := ready.root
    rw [readCellProjection_eq_cell _ _ _ rootFound] at projected
    cases projected
    have transformed : (state config before).cell? config.root = some (.array (values config original ++ config.tail)) := by
      simp only [cellValue, rootFound, Option.map_some, stored, ↓reduceIte]
    have expandedBound : start + extent config config.root [] length ≤ (values config original ++ config.tail).length := by
      simp only [extent, and_self, ↓reduceIte, List.length_append, values_length]
      omega
    refine ⟨((values config original ++ config.tail).drop start).take (extent config config.root [] length), ?_, ?_, ?_⟩
    · simp only [Semantics.sliceValues, readCellProjection_eq_cell _ _ _ transformed, Semantics.projectedValue, expandedBound, ↓reduceIte]
    · rw [List.getElem?_take_of_lt (Nat.lt_of_lt_of_le inside (extent_le config _ _ _)), List.getElem?_drop,
        List.getElem?_append_left (by simp only [values_length]; omega), values_getElem?, found]
      rfl
    · exact (closeds_iff config original).mp (ready.cellClosed reachable rootFound) result (List.mem_of_getElem? found)
  · have notWhole : root = config.root → path ≠ [] := fun same empty => whole ⟨same, empty⟩
    obtain ⟨transport, arrayClosed⟩ := readCellProjection config ready reachable path notWhole projected
    have expandedBound : start + extent config root path length ≤ (values config original).length := by
      simpa only [extent, whole, ↓reduceIte, values_length] using bounded
    refine ⟨((values config original).drop start).take (extent config root path length), ?_, ?_, ?_⟩
    · simp only [Semantics.sliceValues, transport, value, expandedBound, ↓reduceIte]
    · rw [List.getElem?_take_of_lt (Nat.lt_of_lt_of_le inside (extent_le config _ _ _)), List.getElem?_drop,
        values_getElem?, found]
      rfl
    · exact (closeds_iff config original).mp arrayClosed result (List.mem_of_getElem? found)

end Lanius.Semantics.Capacity
