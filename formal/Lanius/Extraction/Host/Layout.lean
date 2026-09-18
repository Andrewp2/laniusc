import Lanius.Extraction.Allocation.Registry
import Lanius.Semantics.I32Views.Borrowed
import Lanius.Separation.HeapFrame

namespace Lanius.Extraction.Host

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.Memory

/-- Native registration layout, independent of cell contents. Keeping this
separate is essential when a logical source array is temporarily shortened:
the physical allocation and its registration do not become shorter. -/
structure ViewLayout (state : State) : Prop where
  heapWellFormed : HeapWellFormed state.heap
  blocks : ∀ view ∈ state.i32ArrayViews, I32ArrayViewBlockWellFormed state.heap view
  roots : ∀ view ∈ state.i32ArrayViews, view.projections = []
  bounded : ∀ view ∈ state.i32ArrayViews, view.root < state.nextCell
  distinct : state.i32ArrayViews.Pairwise fun left right => left.root ≠ right.root
  addresses : state.i32ArrayViews.Pairwise fun left right => left.address ≠ right.address

theorem ViewLayout.ofRegistry (initial : Allocation.Registry state) : ViewLayout state :=
  ⟨initial.wellFormed.heapWellFormed, initial.blocks, initial.roots,
    fun _ member => initial.root_lt_next member, initial.distinct, initial.addresses⟩

theorem ViewLayout.frame (initial : ViewLayout before) (frame : HeapFrame before after)
    (next : before.nextCell ≤ after.nextCell) : ViewLayout after := by
  refine ⟨frame.heap.symm ▸ initial.heapWellFormed, ?_, ?_, ?_, ?_, ?_⟩
  · simpa only [frame.heap, frame.views] using initial.blocks
  · simpa only [frame.views] using initial.roots
  · intro view member
    exact Nat.lt_of_lt_of_le (initial.bounded view (frame.views ▸ member)) next
  · simpa only [frame.views] using initial.distinct
  · simpa only [frame.views] using initial.addresses

theorem ViewLayout.borrowed (initial : ViewLayout before)
    (resources : I32BorrowedResources before count after) (wellFormed : StateWellFormed after) :
    ViewLayout after := by
  obtain ⟨address, elements, views, block, cells, _, _, addressLower⟩ := resources.storage
  have freshBound : before.nextCell < after.nextCell := wellFormed.cellIdsBelowNext
    { id := before.nextCell, value := some (.array elements) } (by rw [cells]; simp)
  refine ⟨wellFormed.heapWellFormed, ?_, ?_, ?_, ?_, ?_⟩
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
  · intro view member
    rw [views] at member
    rcases List.mem_append.mp member with old | fresh
    · exact Nat.lt_trans (initial.bounded view old) freshBound
    · simp only [List.mem_singleton] at fresh
      subst view
      exact freshBound
  · rw [views, List.pairwise_append]
    refine ⟨initial.distinct, by simp, ?_⟩
    intro view member other fresh
    simp only [List.mem_singleton] at fresh
    subst other
    exact Nat.ne_of_lt (initial.bounded view member)
  · rw [views, List.pairwise_append]
    refine ⟨initial.addresses, by simp, ?_⟩
    intro view member other fresh
    simp only [List.mem_singleton] at fresh
    subst other
    exact Nat.ne_of_lt (Nat.lt_of_lt_of_le
      (i32View_address_below_frontier initial.heapWellFormed (initial.blocks view member)) addressLower)

end Lanius.Extraction.Host
