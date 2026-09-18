import Lanius.X86.Storage.Heap
import Lanius.Memory.Borrowed

namespace Lanius.X86.Storage.Heap

open Lanius.Properties

variable {heap after : Lanius.Memory.Heap} {memory : Machine.Memory} {locations : Locations}
  {block : Lanius.Memory.Block} {pointer size alignment : Nat} {native : Machine.Address}

private def borrowAt (pointer : Nat) (block : Lanius.Memory.Block) : Lanius.Memory.Block :=
  { block with owned := if block.base = pointer then false else block.owned }

/-- Ownership does not enter any byte, offset, or native-separation premise.
Transport the correspondence through this exact metadata-only map. -/
private theorem ownership (related : Correspondence heap memory locations)
    (wellFormed : Lanius.Memory.HeapWellFormed after)
    (blocks : after.blocks = heap.blocks.map (borrowAt pointer)) : Correspondence after memory locations := by
  refine ⟨wellFormed, ?_, ?_, ?_, ?_⟩
  · intro candidate member base mapped
    rw [blocks] at member
    obtain ⟨original, present, equal⟩ := List.mem_map.mp member
    subst candidate
    have represented := related.mappedBlock original present base mapped
    exact ⟨represented.live, represented.logicalBound, represented.nativeBound, represented.aligned, represented.bytes⟩
  · intro candidate member base mapped offset inside
    rw [blocks] at member
    obtain ⟨original, present, equal⟩ := List.mem_map.mp member
    subst candidate
    exact related.offsets original present base mapped offset inside
  · intro address base mapped nonnull
    obtain ⟨original, originalBase, offset, member, baseMap, inside, logical, physical⟩ :=
      related.covered address base mapped nonnull
    refine ⟨borrowAt pointer original, originalBase, offset, ?_, baseMap, inside, logical, physical⟩
    rw [blocks]
    exact List.mem_map.mpr ⟨original, member, rfl⟩
  · intro left leftMember leftBase leftMap right rightMember rightBase rightMap different
    rw [blocks] at leftMember rightMember
    obtain ⟨oldLeft, oldLeftMember, leftEqual⟩ := List.mem_map.mp leftMember
    obtain ⟨oldRight, oldRightMember, rightEqual⟩ := List.mem_map.mp rightMember
    subst left right
    exact related.disjoint oldLeft oldLeftMember leftBase leftMap oldRight oldRightMember rightBase rightMap different

/-- Compose an actual successful protection with a prior correspondence.
The native memory and every pointer/slice/string location remain identical;
only the selected Core block's ownership flag can change. -/
theorem Correspondence.protect_success (related : Correspondence heap memory locations)
    (protection : heap.protectAsBorrowed pointer size alignment = .ok after) :
    Correspondence after memory locations := by
  cases found : heap.block? pointer with
  | none => simp [Lanius.Memory.Heap.protectAsBorrowed, found] at protection
  | some selected =>
      have member : selected ∈ heap.blocks := List.mem_of_find?_eq_some found
      cases live : selected.live with
      | false => simp [Lanius.Memory.Heap.protectAsBorrowed, found, live] at protection
      | true =>
          cases mismatch : (selected.size != size || selected.alignment != alignment) with
          | true => simp [Lanius.Memory.Heap.protectAsBorrowed, found, live, mismatch] at protection
          | false =>
              have shape : after = { heap with blocks := (Lanius.Memory.replaceBlock heap.blocks
                  { selected with owned := false }) } := by
                simpa only [Lanius.Memory.Heap.protectAsBorrowed, found, live, Bool.not_true,
                  Bool.false_eq_true, mismatch, ↓reduceIte, Except.ok.injEq] using protection.symm
              apply ownership related (protectAsBorrowed_preserves_heap_well_formed related.wellFormed protection)
                (pointer := selected.base)
              rw [shape, replaceBlock_eq_map]
              apply List.map_congr_left
              intro candidate present
              by_cases same : candidate.base = selected.base
              · have equal := related.wellFormed.blockBasesUnique candidate present selected member same
                subst candidate
                simp [borrowAt]
              · simp [borrowAt, same]

/-- Derive successful exact-block protection from the represented block's
liveness. The returned lookup retains all bytes and bounds but sets owned
to false; neither the native representation nor allocator budget changes. -/
theorem Correspondence.protect_exact (related : Correspondence heap memory locations)
    (found : heap.block? pointer = some block) (mapped : locations.pointer pointer = some native) :
    ∃ after, heap.protectAsBorrowed pointer block.size block.alignment = .ok after ∧
      Correspondence after memory locations ∧
      after.block? pointer = some { block with owned := false } ∧
      after.nextAddress = heap.nextAddress ∧ after.remaining = heap.remaining := by
  have member : block ∈ heap.blocks := List.mem_of_find?_eq_some found
  have base : block.base = pointer := beq_iff_eq.mp
    (List.find?_some (p := fun candidate : Lanius.Memory.Block => candidate.base == pointer) found)
  have blockMap : locations.pointer block.base = some native := by rw [base]; exact mapped
  have live := (related.mappedBlock block member native blockMap).live
  let after : Lanius.Memory.Heap := { heap with blocks := (Lanius.Memory.replaceBlock heap.blocks
    { block with owned := false }) }
  have protection : heap.protectAsBorrowed pointer block.size block.alignment = .ok after := by
    simp [Lanius.Memory.Heap.protectAsBorrowed, found, live, after]
  refine ⟨after, protection, related.protect_success protection, ?_, rfl, rfl⟩
  have original : heap.blocks.find? (fun candidate => candidate.base == block.base) = some block := by
    simpa only [base, Lanius.Memory.Heap.block?] using found
  change (Lanius.Memory.replaceBlock heap.blocks { block with owned := false }).find?
    (fun candidate => candidate.base == pointer) = some { block with owned := false }
  simpa only [base] using replaceBlock_find_same heap.blocks { block with owned := false } block original

/-- Raw deallocation of a live borrowed block is rejected for every supplied
size and alignment, including an empty block's reserved identity address. -/
theorem borrowed_deallocate (wellFormed : Lanius.Memory.HeapWellFormed heap)
    (found : heap.block? pointer = some block) (live : block.live = true) (borrowed : block.owned = false)
    (size alignment : Nat) : heap.deallocate pointer size alignment = .error .allocatorContract := by
  have base : block.base = pointer := beq_iff_eq.mp
    (List.find?_some (p := fun candidate : Lanius.Memory.Block => candidate.base == pointer) found)
  have nonnull := (wellFormed.blocksWellFormed block (List.mem_of_find?_eq_some found)).1
  rw [base] at nonnull
  simp [Lanius.Memory.Heap.deallocate, nonnull, found, live, borrowed]

/-- Reallocation cannot evade borrowed ownership by requesting zero bytes:
that path delegates to the same rejected deallocation. -/
theorem borrowed_reallocate (wellFormed : Lanius.Memory.HeapWellFormed heap)
    (found : heap.block? pointer = some block) (live : block.live = true) (borrowed : block.owned = false)
    (oldSize newSize alignment : Nat) :
    heap.reallocate pointer oldSize newSize alignment = .trapped .allocatorContract heap := by
  have base : block.base = pointer := beq_iff_eq.mp
    (List.find?_some (p := fun candidate : Lanius.Memory.Block => candidate.base == pointer) found)
  have nonnull := (wellFormed.blocksWellFormed block (List.mem_of_find?_eq_some found)).1
  rw [base] at nonnull
  have refused := borrowed_deallocate wellFormed found live borrowed oldSize alignment
  by_cases zero : newSize = 0 <;>
    simp [Lanius.Memory.Heap.reallocate, nonnull, zero, found, live, borrowed, refused]

end Lanius.X86.Storage.Heap
