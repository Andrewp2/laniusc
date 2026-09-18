import Lanius.X86.Storage.Heap.Extend
import Lanius.Memory.Access

namespace Lanius.X86.Storage.Heap

open Lanius.Memory Lanius.Properties

/-- The complete fresh native mapping, including alignment and page padding,
not just the logical payload requested by the program. -/
structure AllocationRegion where
  base : Machine.Address
  size : Nat

def AllocationRegion.Contains (region : AllocationRegion) (address : Machine.Address) : Prop :=
  region.base.toNat ≤ address.toNat ∧ address.toNat < region.base.toNat + region.size

/-- Required effect of a successful native allocator call. This is an
allocator proof obligation, not an assertion that mmap and its emitted
wrapper have already been verified. Bytes outside the complete fresh mapping
remain unchanged, while unused padding inside it may also be initialized. -/
-- The enclosing runtime proof must also place code and caller storage
-- outside the new region; this heap relation does not supply that fact.
structure AllocationEffect (before after : Machine.Memory) (base : Machine.Address)
    (size alignment : Nat) (region : AllocationRegion) : Prop where
  nonnull : base ≠ 0
  regionBound : region.base.toNat + region.size ≤ 2^64
  contained : region.base.toNat ≤ base.toNat ∧
    base.toNat + max size 1 ≤ region.base.toNat + region.size
  aligned : base.toNat % alignment = 0
  zeroed : ∀ offset, offset < size → after (base + BitVec.ofNat 64 offset) = 0
  frame : ∀ address, ¬ region.Contains address →
    after address = before address

theorem AllocationEffect.bounded (effect : AllocationEffect before after base size alignment region) :
    base.toNat + max size 1 ≤ 2^64 := Nat.le_trans effect.contained.2 effect.regionBound

def allocatedBlock (pointer size alignment : Nat) : Block := {
  base := pointer, size, alignment, bytes := List.replicate size 0 }

/-- Extract the fresh abstract block and frontier from the actual reference
allocation operation. Native allocation placement is not constrained by this
abstract frontier. -/
theorem allocation_shape
    {heap after : Lanius.Memory.Heap} {size alignment pointer : Nat}
    (allocated : heap.allocate size alignment = .allocated pointer after) :
    after.blocks = heap.blocks ++ [allocatedBlock pointer size alignment] ∧
      heap.nextAddress ≤ pointer ∧ after.nextAddress = pointer + max size 1 := by
  unfold Lanius.Memory.Heap.allocate at allocated
  split at allocated
  · contradiction
  · rename_i alignmentValid
    cases budget : consumeBudget heap.remaining size with
    | none => simp [budget] at allocated
    | some remaining =>
        rw [budget] at allocated
        cases allocated
        refine ⟨rfl, ?_, rfl⟩
        apply Nat.le_trans (Nat.le_max_left _ _)
        apply alignUp_ge
        apply valid_alignment_is_nonzero
        simpa using alignmentValid

theorem AllocationEffect.address_toNat (effect : AllocationEffect before after base size alignment region)
    (inside : offset < max size 1) :
    (base + BitVec.ofNat 64 offset).toNat = base.toNat + offset := by
  have bounded := effect.bounded
  simp only [BitVec.toNat_add, BitVec.toNat_ofNat]
  omega

/-- The allocator's ordinary memory frame and disjoint placement preserve
every previously represented byte; no equality of abstract/native addresses
or ordering between old and new native allocations is assumed. -/
theorem AllocationEffect.old_frame
    (effect : AllocationEffect before after base size alignment region)
    (related : Correspondence heap before locations)
    (separate : ∀ old ∈ heap.blocks, ∀ oldBase,
      locations.pointer old.base = some oldBase →
      oldBase.toNat + max old.size 1 ≤ region.base.toNat ∨
        region.base.toNat + region.size ≤ oldBase.toNat) :
    ∀ old ∈ heap.blocks, ∀ oldBase, locations.pointer old.base = some oldBase →
      ∀ offset, offset < old.size →
        after (oldBase + BitVec.ofNat 64 offset) = before (oldBase + BitVec.ofNat 64 offset) := by
  intro old member oldBase mapped offset inside
  have represented := related.mappedBlock old member oldBase mapped
  apply effect.frame
  intro overlaps
  unfold AllocationRegion.Contains at overlaps
  rw [represented.address_toNat (by omega)] at overlaps
  rcases separate old member oldBase mapped with left | right <;> omega

/-- Framing a caller word requires its own separation premise. A heap-block
correspondence alone says nothing about unrepresented stack/code storage. -/
theorem AllocationEffect.read64_frame
    (effect : AllocationEffect before after base size alignment region)
    (separate : ∀ lane : Fin 8, ¬ region.Contains (address + BitVec.ofNat 64 lane.val)) :
    Machine.read64 after address = Machine.read64 before address := by
  apply Machine.read64_congr
  intro lane
  exact effect.frame _ (separate lane)

theorem AllocationEffect.payload_separate
    (effect : AllocationEffect before after base size alignment region)
    {oldBase : Machine.Address} {oldSize : Nat}
    (separate : oldBase.toNat + max oldSize 1 ≤ region.base.toNat ∨
      region.base.toNat + region.size ≤ oldBase.toNat) :
    oldBase.toNat + max oldSize 1 ≤ base.toNat ∨
      base.toNat + max size 1 ≤ oldBase.toNat := by
  have contained := effect.contained
  rcases separate with left | right
  · exact Or.inl (Nat.le_trans left contained.1)
  · exact Or.inr (Nat.le_trans contained.2 right)

/-- A successful *actual Core allocation* and the stated native allocator
effect extend the existing correspondence. The returned native address may
be below older native allocations. Null, old pointer mappings, and descriptor
location functions retain their meaning; only the fresh abstract range is
added. Stored caller words additionally require a memory-framing premise.

This theorem does not supply allocator execution, allocation success, or the
native separation premise. Those remain runtime obligations. -/
theorem Correspondence.allocate (related : Correspondence heap before locations)
    (allocated : heap.allocate size alignment = .allocated pointer afterHeap)
    (logicalBound : pointer + max size 1 ≤ 2^64)
    (effect : AllocationEffect before after base size alignment region)
    (separate : ∀ old ∈ heap.blocks, ∀ oldBase,
      locations.pointer old.base = some oldBase →
      oldBase.toNat + max old.size 1 ≤ region.base.toNat ∨
        region.base.toNat + region.size ≤ oldBase.toNat) :
    ∃ afterLocations, Correspondence afterHeap after afterLocations ∧
      afterLocations.pointer pointer = some base ∧
      (∀ old oldBase, locations.pointer old = some oldBase →
        afterLocations.pointer old = some oldBase) ∧
      afterLocations.slice = locations.slice ∧ afterLocations.string = locations.string := by
  obtain ⟨appended, frontier, _⟩ := allocation_shape allocated
  have afterWF : HeapWellFormed afterHeap := by
    simpa only [allocated, AllocationResultWellFormed] using
      allocate_preserves_heap_well_formed (size := size) (alignment := alignment) related.wellFormed
  have positive : 0 < pointer := by
    exact Nat.lt_of_lt_of_le related.wellFormed.nextAddressPositive frontier
  have represented : BlockRep (allocatedBlock pointer size alignment) after base := by
    refine ⟨rfl, logicalBound, effect.bounded, effect.aligned, ?_⟩
    intro offset inside
    change offset < size at inside
    simp [allocatedBlock, inside, effect.zeroed offset inside]
  let afterLocations := locations.extend (allocatedBlock pointer size alignment) base
    positive effect.nonnull effect.bounded
  refine ⟨afterLocations, ?_, ?_, ?_, rfl, rfl⟩
  · exact related.extend frontier appended afterWF represented effect.nonnull
      (effect.old_frame related separate)
      (fun old member oldBase mapped => effect.payload_separate (separate old member oldBase mapped))
  · exact Locations.extend_base
  · intro old oldBase mapped
    exact related.extend_old (allocatedBlock pointer size alignment) base frontier
      positive effect.nonnull effect.bounded mapped

end Lanius.X86.Storage.Heap
