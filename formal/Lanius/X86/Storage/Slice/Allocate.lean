import Lanius.X86.Storage.Heap.Allocate
import Lanius.X86.Storage.Slice.Raw

namespace Lanius.X86.Storage.Slice.Allocate

open Lanius.Semantics Lanius.Properties

variable {before : State} {allocatedHeap : Lanius.Memory.Heap} {address count : Nat}
  {memory nextMemory : Machine.Memory} {base : Machine.Address} {locations : Locations}
  {region : Heap.AllocationRegion}

/-- Allocate an exact i32 payload and run the actual Core raw-slice
constructor on the resulting state. Exact block size, alignment, liveness,
byte decoding, and the borrowed backing are derived, not supplied as
independent slice assumptions. Zero-length allocations follow the same path.

The native allocation effect and fresh region separation remain explicit
runtime obligations. This theorem proves neither allocator instruction
execution nor descriptor emission. Freshness applies to valid old views;
StateWellFormed alone does not validate arbitrary registry entries. -/
theorem construct (wellFormed : StateWellFormed before)
    (related : Heap.Correspondence before.heap memory locations)
    (allocated : before.heap.allocate (count * 4) 4 = .allocated address allocatedHeap)
    (logicalBound : address + max (count * 4) 1 ≤ 2^64)
    (effect : Heap.AllocationEffect memory nextMemory base (count * 4) 4 region)
    (separate : ∀ old ∈ before.heap.blocks, ∀ oldBase,
      locations.pointer old.base = some oldBase →
      oldBase.toNat + max old.size 1 ≤ region.base.toNat ∨
        region.base.toNat + region.size ≤ oldBase.toNat) :
    ∃ afterLocations after values,
      Raw.Constructed { before with heap := allocatedHeap } after address count
        nextMemory base afterLocations values ∧
      (∀ old oldBase, locations.pointer old = some oldBase → afterLocations.pointer old = some oldBase) ∧
      afterLocations.slice = locations.slice ∧ afterLocations.string = locations.string ∧
      (∀ view, I32ArrayViewBlockWellFormed before.heap view → view.address < address) := by
  obtain ⟨afterLocations, allocatedRelated, mapped, oldPointers, slices, strings⟩ :=
    related.allocate allocated logicalBound effect separate
  have allocatedWF : StateWellFormed { before with heap := allocatedHeap } :=
    ⟨allocatedRelated.wellFormed, wellFormed.cellIdsUnique, wellFormed.cellIdsBelowNext,
      wellFormed.localsReferenceCells⟩
  have found : allocatedHeap.block? address = some (Heap.allocatedBlock address (count * 4) 4) :=
    Lanius.Memory.Heap.allocated_block wellFormed.heapWellFormed allocated
  obtain ⟨after, values, constructed⟩ := Raw.map allocatedWF allocatedRelated found mapped rfl rfl
  refine ⟨afterLocations, after, values, constructed, oldPointers, slices, strings, ?_⟩
  intro view valid
  exact Nat.lt_of_lt_of_le (i32View_address_below_frontier wellFormed.heapWellFormed valid)
    (Heap.allocation_shape allocated).2.1

end Lanius.X86.Storage.Slice.Allocate
