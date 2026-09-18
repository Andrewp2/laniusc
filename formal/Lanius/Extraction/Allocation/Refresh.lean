import Lanius.Extraction.Allocation.Storage

namespace Lanius.Extraction.Allocation

open Lanius.Core Lanius.Semantics Lanius.Properties

/-- Refresh root arrays from their existing byte blocks. This proves that
refresh succeeds, not that array contents are unchanged: coherence and
non-aliasing are separate obligations at a host boundary. -/
theorem Registry.refresh (initial : Registry before) :
    ∃ after, syncI32ViewsFromHeap before = .ok after ∧ Registry after ∧
      after.heap = before.heap ∧ after.i32ArrayViews = before.i32ArrayViews ∧
      after.nextCell = before.nextCell ∧ after.locals = before.locals ∧ after.world = before.world ∧
      (∀ cell, (∀ view ∈ before.i32ArrayViews, cell ≠ view.root) →
        after.cellEntry? cell = before.cellEntry? cell) := by
  obtain ⟨after, refreshed⟩ := syncI32RootViewsFromHeapFrom_exists initial.wellFormed.heapWellFormed
    initial.blocks initial.roots (fun view member => by
      obtain ⟨values, _, found⟩ := initial.storage member
      exact ⟨_, found⟩)
  obtain ⟨wellFormed, heap, views, next⟩ :=
    syncI32RootViewsFromHeapFrom_preserves_structure initial.roots initial.wellFormed refreshed
  refine ⟨after, refreshed, ⟨wellFormed, ?_, ?_, ?_, ?_, ?_⟩, heap, views, next,
    syncI32RootViewsFromHeapFrom_preserves_locals initial.roots refreshed,
    syncI32ViewsFromHeapFrom_preserves_world refreshed,
    fun _ apart => syncI32RootViewsFromHeapFrom_preserves_other_cell initial.roots apart refreshed⟩
  · simpa only [views, heap] using initial.blocks
  · simpa only [views] using initial.roots
  · simpa only [views] using initial.distinct
  · simpa only [views] using syncI32RootViewsFromHeapFrom_arrays initial.roots initial.distinct refreshed
  · simpa only [views] using initial.addresses

theorem Registry.withWorld (initial : Registry before) (world : Lanius.World.State) :
    Registry { before with world } :=
  ⟨⟨initial.wellFormed.heapWellFormed, initial.wellFormed.cellIdsUnique,
      initial.wellFormed.cellIdsBelowNext, initial.wellFormed.localsReferenceCells⟩,
    initial.blocks, initial.roots, initial.distinct, initial.arrays, initial.addresses⟩

end Lanius.Extraction.Allocation
