import Lanius.Semantics.I32Views

namespace Lanius.Semantics

open Lanius.Core Lanius.Memory

theorem syncI32ViewsFromHeapFrom_cons_invert
    (synced : syncI32ViewsFromHeapFrom (view :: rest) before = .ok after) :
    ∃ bytes elements middle,
      before.heap.loadBytes view.address (view.length * 4) = .ok bytes ∧
      decodeI32Array view.length bytes = .ok elements ∧
      writeResolvedPlace before
        { root := view.root, projections := view.projections, value := none }
        (.array elements) = .ok middle ∧
      syncI32ViewsFromHeapFrom rest middle = .ok after := by
  cases loaded : before.heap.loadBytes view.address (view.length * 4) with
  | error reason => simp [syncI32ViewsFromHeapFrom, loaded] at synced
  | ok bytes =>
      cases decoded : decodeI32Array view.length bytes with
      | error reason => simp [syncI32ViewsFromHeapFrom, loaded, decoded] at synced
      | ok elements =>
          cases written : writeResolvedPlace before
              { root := view.root, projections := view.projections, value := none }
              (.array elements) with
          | error reason => simp [syncI32ViewsFromHeapFrom, loaded, decoded, written] at synced
          | ok middle =>
              exact ⟨bytes, elements, middle, rfl, decoded, written,
                by simpa [syncI32ViewsFromHeapFrom, loaded, decoded, written] using synced⟩

theorem syncI32ViewsFromHeapFrom_preserves_heap
    (synced : syncI32ViewsFromHeapFrom pending before = .ok after) :
    after.heap = before.heap := by
  induction pending generalizing before with
  | nil => simp [syncI32ViewsFromHeapFrom] at synced; subst after; rfl
  | cons view rest induction =>
      obtain ⟨_, _, _, _, _, written, remaining⟩ := syncI32ViewsFromHeapFrom_cons_invert synced
      exact (induction remaining).trans (writeResolvedPlace_preserves_heap written)

theorem syncI32ViewsFromHeapFrom_preserves_other_cell
    (different : ∀ view ∈ pending, cell ≠ view.root)
    (synced : syncI32ViewsFromHeapFrom pending before = .ok after) :
    after.cellEntry? cell = before.cellEntry? cell := by
  induction pending generalizing before with
  | nil => simp [syncI32ViewsFromHeapFrom] at synced; subst after; rfl
  | cons view rest induction =>
      obtain ⟨_, _, middle, _, _, written, remaining⟩ := syncI32ViewsFromHeapFrom_cons_invert synced
      have restDifferent : ∀ view ∈ rest, cell ≠ view.root :=
        fun candidate member => different candidate (by simp [member])
      exact (induction restDifferent remaining).trans
        (writeResolvedPlace_preserves_other_cell written (different view (by simp)))

theorem syncI32ViewsFromHeapFrom_view_read
    (member : view ∈ pending)
    (synced : syncI32ViewsFromHeapFrom pending before = .ok after) :
    ∃ bytes elements,
      before.heap.loadBytes view.address (view.length * 4) = .ok bytes ∧
      decodeI32Array view.length bytes = .ok elements := by
  induction pending generalizing before with
  | nil => simp at member
  | cons head rest induction =>
      obtain ⟨bytes, elements, middle, loaded, decoded, written, remaining⟩ :=
        syncI32ViewsFromHeapFrom_cons_invert synced
      rcases List.mem_cons.mp member with same | inRest
      · subst head
        exact ⟨bytes, elements, loaded, decoded⟩
      · obtain ⟨bytes, elements, loaded, decoded⟩ := induction inRest remaining
        rw [writeResolvedPlace_preserves_heap written] at loaded
        exact ⟨bytes, elements, loaded, decoded⟩

/-- A whole-cell view receives exactly the decoded host bytes. Later refresh
steps cannot overwrite it when their roots are distinct. This is the link
from the host read buffer to the words read by the Lanius unpacking loop. -/
theorem syncI32ViewsFromHeapFrom_reads_view
    {pending : List I32ArrayView}
    (distinct : pending.Pairwise fun left right => left.root ≠ right.root)
    (member : view ∈ pending) (wholeCell : view.projections = [])
    (loaded : before.heap.loadBytes view.address (view.length * 4) = .ok bytes)
    (decoded : decodeI32Array view.length bytes = .ok elements)
    (synced : syncI32ViewsFromHeapFrom pending before = .ok after) :
    after.cellEntry? view.root = some { id := view.root, value := some (.array elements) } := by
  induction pending generalizing before with
  | nil => simp at member
  | cons head rest induction =>
      obtain ⟨headBytes, headElements, middle, headLoaded, headDecoded, written, remaining⟩ :=
        syncI32ViewsFromHeapFrom_cons_invert synced
      obtain ⟨headDifferent, restDifferent⟩ := List.pairwise_cons.mp distinct
      rcases List.mem_cons.mp member with same | inRest
      · subst head
        have bytesSame : headBytes = bytes := Except.ok.inj (headLoaded.symm.trans loaded)
        subst headBytes
        have elementsSame : headElements = elements := Except.ok.inj (headDecoded.symm.trans decoded)
        subst headElements
        have assigned : before.assignCell view.root (.array elements) = some middle := by
          cases assignment : before.assignCell view.root (.array elements) with
          | none => simp [writeResolvedPlace, wholeCell, assignment] at written
          | some assigned =>
              have same : assigned = middle := by
                simpa [writeResolvedPlace, wholeCell, assignment] using written
              exact congrArg some same
        have preserved := syncI32ViewsFromHeapFrom_preserves_other_cell headDifferent remaining
        exact preserved.trans (Lanius.Properties.assignCell_finds_assigned assigned)
      · have middleLoaded : middle.heap.loadBytes view.address (view.length * 4) = .ok bytes := by
          rw [writeResolvedPlace_preserves_heap written]
          exact loaded
        exact induction restDifferent inRest middleLoaded remaining

end Lanius.Semantics
