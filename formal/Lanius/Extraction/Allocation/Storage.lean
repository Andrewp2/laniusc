import Lanius.Extraction.Allocation.Registry
import Lanius.Separation.CellEffect

namespace Lanius.Extraction.Allocation

open Lanius.Core Lanius.Semantics

private theorem signedValues (elements : List Value)
    (typed : ∀ element ∈ elements, ∃ value, element = .signed .i32 value) :
    ∃ values : List Int, elements = signedI32Values values := by
  induction elements with
  | nil => exact ⟨[], rfl⟩
  | cons element rest ih =>
      obtain ⟨value, rfl⟩ := typed element (by simp)
      obtain ⟨values, rfl⟩ := ih (fun element member => typed element (List.mem_cons_of_mem _ member))
      exact ⟨value :: values, rfl⟩

/-- Recover concrete typed storage from the registry rather than assuming a
separate array backing fact at each caller. -/
theorem Registry.storage (registry : Registry state) (member : view ∈ state.i32ArrayViews) :
    ∃ values : List Int, values.length = view.length ∧
      state.cellEntry? view.root = some {
        id := view.root, value := some (.array (signedI32Values values)) } := by
  obtain ⟨elements, read, length, typed⟩ := registry.arrays view member
  obtain ⟨values, rfl⟩ := signedValues elements typed
  refine ⟨values, by simpa [signedI32Values] using length, ?_⟩
  rw [registry.roots view member] at read
  cases found : state.cellEntry? view.root with
  | none => simp [readCellProjection, found] at read
  | some entry =>
      have identity : entry.id = view.root := by simpa using List.find?_some found
      rcases entry with ⟨id, stored⟩
      dsimp at identity
      subst id
      cases value : stored with
      | none => simp [readCellProjection, found, value] at read
      | some root =>
          have exactRoot : root = .array (signedI32Values values) := by
            simpa [readCellProjection, found, value, projectedValue] using read
          simp_all

end Lanius.Extraction.Allocation
