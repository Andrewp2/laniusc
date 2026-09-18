import Lanius.Extraction.Allocation.Registry
import Lanius.Semantics.I32Views.Borrowed

namespace Lanius.Extraction.Allocation

open Lanius.Core Lanius.Semantics Lanius.Memory Lanius.Properties

/-- A freshly borrowed string extends the existing registry without losing
the blocks, distinct roots, or typed arrays required by later host calls. -/
theorem Registry.borrowed (initial : Registry before)
    (resources : I32BorrowedResources before count after) (wellFormed : StateWellFormed after) :
    Registry after := by
  obtain ⟨address, elements, views, block, cells, length, typed, addressLower⟩ := resources.storage
  refine ⟨wellFormed, ?_, ?_, ?_, ?_, ?_⟩
  · intro view member
    rw [views] at member
    rcases List.mem_append.mp member with old | fresh
    · exact resources.viewsPreserved view old (initial.blocks view old)
    · simp only [List.mem_singleton] at fresh
      subst view
      exact block
  · intro view member
    rw [views] at member
    rcases List.mem_append.mp member with old | fresh
    · exact initial.roots view old
    · simp only [List.mem_singleton] at fresh
      subst view
      rfl
  · rw [views, List.pairwise_append]
    refine ⟨initial.distinct, by simp, ?_⟩
    intro view member other fresh
    simp only [List.mem_singleton] at fresh
    subst other
    exact Nat.ne_of_lt (initial.root_lt_next member)
  · intro view member
    rw [views] at member
    rcases List.mem_append.mp member with old | fresh
    · obtain ⟨stored, read, size, storedTyped⟩ := initial.arrays view old
      have kept : after.cellEntry? view.root = before.cellEntry? view.root := by
        have kept := allocateTemporary_preserves_old_cell before (.array elements) view.root
          (initial.root_lt_next old)
        simpa only [State.allocateTemporary, State.cellEntry?, cells] using kept
      exact ⟨stored, by simpa only [readCellProjection, kept] using read, size, storedTyped⟩
    · simp only [List.mem_singleton] at fresh
      subst view
      have entry : after.cellEntry? before.nextCell = some {
          id := before.nextCell, value := some (.array elements) } := by
        have entry := allocateTemporary_finds_fresh_cell before (.array elements) initial.wellFormed
        simpa only [State.allocateTemporary, State.cellEntry?, cells] using entry
      exact ⟨elements, by simp [readCellProjection, entry, projectedValue], length, typed⟩
  · rw [views, List.pairwise_append]
    refine ⟨initial.addresses, by simp, ?_⟩
    intro view member other fresh
    simp only [List.mem_singleton] at fresh
    subst other
    exact Nat.ne_of_lt (Nat.lt_of_lt_of_le
      (i32View_address_below_frontier initial.wellFormed.heapWellFormed (initial.blocks view member)) addressLower)

end Lanius.Extraction.Allocation
