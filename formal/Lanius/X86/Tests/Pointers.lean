import Lanius.X86.Storage.Value
import Lanius.X86.Storage.Pointer
import Lanius.X86.Storage.Heap
import Lanius.X86.Storage.Heap.Store
import Lanius.X86.Storage.Heap.Allocate
import Lanius.X86.Transport.Core
import Lean.Elab.Term
import Lean.Util.CollectAxioms

namespace Lanius.X86.Tests.Pointers

open Lanius.Core Lanius.X86

private def pointerMap (value : Nat) : Option Machine.Address :=
  if value = 0 then some 0
  else if value = 4 then some 0x1000
  else if value = 5 then some 0x1001
  else if value = 18446744073709551620 then some 0x2000
  else none

private def locations : Storage.Locations where
  slice := fun _ _ _ => 0
  string := fun _ => 0
  pointer := pointerMap
  pointer_null := rfl
  pointer_eq_null := by
    intro value mapped
    unfold pointerMap at mapped
    split at mapped
    · assumption
    · repeat' split at mapped
      all_goals simp_all

-- Pointer representation uses the explicit map, not numeric identity.
example : Storage.shape locations (.pointer 4) = some [.full 0x1000] := by simp [locations, pointerMap]
example : Storage.shape locations (.unsigned .usize 4) = some [.full 4] := by simp [Storage.shape_usize]
example : Storage.shape locations (.pointer 0) = some [.full 0] := Storage.shape_null locations
example : Storage.shape locations (.pointer 6) = none := by simp [locations, pointerMap]
example : Storage.shape locations (.pointer 0x1000) = none := by simp [locations, pointerMap]
example : Storage.shape locations (Lanius.Semantics.pointerOffset .x86_64 false 4 1) = some [.full 0x1001] := by
  change Storage.shape locations (.pointer 5) = _
  simp [locations, pointerMap]
example : Storage.shape locations (Lanius.Semantics.pointerOffset .x86_64 false 4 2) = none := by
  change Storage.shape locations (.pointer 6) = _
  simp [locations, pointerMap]

private theorem injective : locations.PointerInjective := by
  intro left right native leftMapped rightMapped
  simp only [locations, pointerMap] at leftMapped rightMapped
  repeat' first | split at leftMapped | split at rightMapped
  all_goals simp_all
  all_goals
    have same := congrArg BitVec.toNat (leftMapped.trans rightMapped.symm)
    simp at same

example : Lanius.Semantics.evalBinaryValue .x86_64 .equal (.pointer 4) (.pointer 5) = .ok (.boolean false) := by
  exact Storage.Pointer.equal locations injective (leftNative := 0x1000) (rightNative := 0x1001) rfl rfl

example : Lanius.Semantics.evalBinaryValue .x86_64 .equal (.pointer 4) (.pointer 4) = .ok (.boolean true) := by
  exact Storage.Pointer.equal locations injective (leftNative := 0x1000) (rightNative := 0x1000) rfl rfl

example : Lanius.Semantics.evalBinaryValue .x86_64 .notEqual (.pointer 4) (.pointer 0) = .ok (.boolean true) := by
  exact Storage.Pointer.notEqual locations injective (leftNative := 0x1000) (rightNative := 0) rfl rfl

-- This is a word-representation test, not a claim that every abstract Nat
-- can be produced by x86 pointer arithmetic or serialized as a literal.
example : Storage.shape locations (.pointer 18446744073709551620) = some [.full 0x2000] := by simp [locations, pointerMap]
example : Storage.shape locations (.unsigned .usize 18446744073709551620) = none := by simp [Storage.shape_usize]

theorem relocated_word (memory : Machine.Memory) :
    Storage.Represents locations (Machine.write64 memory 0x3000 0x1000) 0x3000 (.pointer 4) := by
  apply Storage.Represents.pointer_iff.mpr
  exact ⟨0x1000, rfl, Machine.read64_write64 _ _ _⟩

theorem identity_word_rejected (memory : Machine.Memory) :
    ¬ Storage.Represents locations (Machine.write64 memory 0x3000 4) 0x3000 (.pointer 4) := by
  rw [Storage.Represents.pointer_iff]
  simp [locations, pointerMap, Machine.read64_write64]

theorem missing_word_rejected (memory : Machine.Memory) (address : Machine.Address) :
    ¬ Storage.Represents locations memory address (.pointer 6) := by
  rw [Storage.Represents.pointer_iff]
  simp [locations, pointerMap]

example (memory : Machine.Memory) :
    Storage.Represents locations (Machine.write64 memory 0x3000 4) 0x3000 (.unsigned .usize 4) := by
  exact Storage.Represents.usize_iff.mpr ⟨by decide, Machine.read64_write64 _ _ _⟩

example (memory : Machine.Memory) :
    Storage.Represents locations (Machine.write64 memory 0x3000 0) 0x3000 (.pointer 0) := by
  exact (Storage.Represents.null_iff locations).mpr (Machine.read64_write64 _ _ _)

private def heapMap (value : Nat) : Option Machine.Address :=
  if value = 0 then some 0 else if value = 4 then some 0x1000
  else if value = 5 then some 0x1001 else if value = 6 then some 0x1002
  else if value = 7 then some 0x1003 else if value = 20 then some 0x2000 else none

private def heapLocations : Storage.Locations where
  slice := fun _ _ _ => 0
  string := fun _ => 0
  pointer := heapMap
  pointer_null := rfl
  pointer_eq_null := by
    intro value mapped
    unfold heapMap at mapped
    split at mapped
    · assumption
    · repeat' split at mapped
      all_goals simp_all

private def firstBlock : Lanius.Memory.Block :=
  { base := 4, size := 4, alignment := 4, bytes := [1, 2, 3, 4] }
private def secondBlock : Lanius.Memory.Block :=
  { base := 20, size := 1, alignment := 4, bytes := [9] }
private def heap : Lanius.Memory.Heap := { blocks := [firstBlock, secondBlock], nextAddress := 24 }
private def memory (address : Machine.Address) : UInt8 :=
  if address = 0x1000 then 1 else if address = 0x1001 then 2
  else if address = 0x1002 then 3 else if address = 0x1003 then 4
  else if address = 0x2000 then 9 else 0

private theorem heapWellFormed : Lanius.Memory.HeapWellFormed heap := by
  constructor <;>
    simp [heap, firstBlock, secondBlock, Lanius.Memory.null, Lanius.Memory.HeapBlockBasesUnique,
      Lanius.Memory.BlockWellFormed, Lanius.Memory.HeapBlocksDisjoint, Lanius.Memory.BlockIntervalsDisjoint,
      Lanius.Memory.HeapBlocksBelowNext, Lanius.Memory.validAlignment]
  all_goals cbv

private theorem firstRepresented : Storage.Heap.BlockRep firstBlock memory 0x1000 := by
  refine ⟨rfl, by decide, by decide, by decide, ?_⟩
  intro offset inside
  have cases : offset = 0 ∨ offset = 1 ∨ offset = 2 ∨ offset = 3 := by
    change offset < 4 at inside
    omega
  rcases cases with rfl | rfl | rfl | rfl <;> cbv

private theorem secondRepresented : Storage.Heap.BlockRep secondBlock memory 0x2000 := by
  refine ⟨rfl, by decide, by decide, by decide, ?_⟩
  intro offset inside
  have zero : offset = 0 := by change offset < 1 at inside; omega
  subst offset
  rfl

private theorem mappedCases (mapped : heapLocations.pointer pointer = some native) :
    (pointer = 0 ∧ native = 0) ∨ (pointer = 4 ∧ native = 0x1000) ∨
    (pointer = 5 ∧ native = 0x1001) ∨ (pointer = 6 ∧ native = 0x1002) ∨
    (pointer = 7 ∧ native = 0x1003) ∨ (pointer = 20 ∧ native = 0x2000) := by
  simp only [heapLocations, heapMap] at mapped
  repeat' split at mapped
  all_goals simp_all

private theorem correspondence : Storage.Heap.Correspondence heap memory heapLocations := by
  refine ⟨heapWellFormed, ?_, ?_, ?_, ?_⟩
  · intro block member base mapped
    simp only [heap, List.mem_cons, List.not_mem_nil, or_false] at member
    rcases member with rfl | rfl
    · have same : base = 0x1000 := by simpa [heapLocations, heapMap, firstBlock] using mapped.symm
      subst base
      exact firstRepresented
    · have same : base = 0x2000 := by simpa [heapLocations, heapMap, secondBlock] using mapped.symm
      subst base
      exact secondRepresented
  · intro block member base mapped offset inside
    simp only [heap, List.mem_cons, List.not_mem_nil, or_false] at member
    rcases member with rfl | rfl
    · have same : base = 0x1000 := by simpa [heapLocations, heapMap, firstBlock] using mapped.symm
      subst base
      have cases : offset = 0 ∨ offset = 1 ∨ offset = 2 ∨ offset = 3 := by
        change offset < 4 at inside
        omega
      rcases cases with rfl | rfl | rfl | rfl <;> cbv
    · have same : base = 0x2000 := by simpa [heapLocations, heapMap, secondBlock] using mapped.symm
      subst base
      have zero : offset = 0 := by change offset < 1 at inside; omega
      subst offset
      rfl
  · intro pointer native mapped nonzero
    rcases mappedCases mapped with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩
    · exact False.elim (nonzero rfl)
    · exact ⟨firstBlock, 0x1000, 0, by simp [heap], rfl, by decide, rfl, rfl⟩
    · exact ⟨firstBlock, 0x1000, 1, by simp [heap], rfl, by decide, rfl, rfl⟩
    · exact ⟨firstBlock, 0x1000, 2, by simp [heap], rfl, by decide, rfl, rfl⟩
    · exact ⟨firstBlock, 0x1000, 3, by simp [heap], rfl, by decide, rfl, rfl⟩
    · exact ⟨secondBlock, 0x2000, 0, by simp [heap], rfl, by decide, rfl, rfl⟩
  · intro left lm leftBase leftMapped right rm rightBase rightMapped distinct
    simp only [heap, List.mem_cons, List.not_mem_nil, or_false] at lm rm
    rcases lm with rfl | rfl <;> rcases rm with rfl | rfl <;>
      simp_all [heapLocations, heapMap, firstBlock, secondBlock]
    all_goals rw [← leftMapped, ← rightMapped]; decide

example : heapLocations.PointerInjective := correspondence.pointer_injective
example : heapLocations.pointer (4 + 1 + 2) = some ((0x1000 + 1) + 2) :=
  (correspondence.within_add (block := firstBlock) (by simp [heap]) rfl
    (start := 1) (offset := 2) (by decide)).1
example : heap.loadByte (4 + 1) 2 = .ok (memory ((0x1000 + 1) + 2)) :=
  correspondence.load_byte (block := firstBlock) (by simp [heap]) rfl (by decide)
example : (heap.loadBytes 4 4).map Lanius.Semantics.decodeI32 = .ok 0x04030201 := by
  have read := correspondence.load_i32 (block := firstBlock) (by simp [heap]) rfl (start := 0) (by decide)
  simpa [firstBlock, Machine.read32, memory, readBytes] using read

-- No map may manufacture a location outside all represented blocks.
-- This fixture deliberately has a gap after the first block.
example (other : Storage.Locations) (mapped : other.pointer 8 = some 0x1004) :
    ¬ Storage.Heap.Correspondence heap memory other := by
  intro related
  obtain ⟨block, base, offset, member, _, inside, address, _⟩ := related.covered 8 0x1004 mapped (by decide)
  simp only [heap, List.mem_cons, List.not_mem_nil, or_false] at member
  rcases member with rfl | rfl <;> simp [firstBlock, secondBlock] at inside address <;> omega

example : heapLocations.pointer 8 = none := rfl
example : heap.loadByte 4 4 = .error .rawMemoryBounds := by cbv

-- Current Core pointers are numbers, not allocation-provenance tokens.
-- With an adjacent allocation, that same address denotes the next block;
-- the within-block theorem above intentionally does not cover this case.
example : ({ blocks := [firstBlock, { secondBlock with base := 8 }], nextAddress := 12 } : Lanius.Memory.Heap).loadByte 4 4 =
    .ok 9 := by cbv

example : ¬ Storage.Heap.Correspondence
    { heap with blocks := [{ firstBlock with live := false }, secondBlock] } memory heapLocations := by
  intro related
  have represented := related.mappedBlock { firstBlock with live := false } (by simp) 0x1000 rfl
  have impossible := represented.live
  contradiction

example (other : Storage.Locations) (aliasLeft : other.pointer 4 = some 0x1000)
    (aliasRight : other.pointer 20 = some 0x1000) :
    ¬ Storage.Heap.Correspondence heap memory other := by
  intro related
  have same : (4 : Nat) = 20 := related.pointer_injective aliasLeft aliasRight
  contradiction

private def emptyBlock : Lanius.Memory.Block := { base := 32, size := 0, alignment := 4, bytes := [] }
example : Storage.Heap.BlockRep emptyBlock memory 0x4000 := by
  refine ⟨rfl, by decide, by decide, by decide, ?_⟩
  intro offset inside
  change offset < 0 at inside
  omega
example : ({ blocks := [emptyBlock], nextAddress := 33 } : Lanius.Memory.Heap).loadByte 32 0 =
    .error .rawMemoryBounds := by cbv

theorem store_retains_other_block :
    ∃ after, heap.storeByte 5 1 170 = .ok after ∧
      Storage.Heap.Correspondence after (Storage.Heap.writeByte memory 0x1002 170) heapLocations ∧
      after.loadByte 20 0 = .ok 9 := by
  obtain ⟨after, stored, blocks, _, _, related⟩ := correspondence.store_byte
    (block := firstBlock) (by simp [heap]) rfl (start := 1) (offset := 1) (by decide) 170
  have member : secondBlock ∈ after.blocks := by
    rw [blocks]
    simp [heap, Lanius.Memory.replaceBlock, firstBlock, secondBlock]
  have read := related.load_byte (block := secondBlock) member rfl (start := 0) (offset := 0) (by decide)
  exact ⟨after, by simpa [firstBlock] using stored, by simpa using related,
    by simpa [secondBlock, Storage.Heap.writeByte, memory] using read⟩

/-- All signed and wrapping i32 payloads, not just an example byte pattern. -/
theorem word_store_roundtrip (value : Int) :
    let native := Machine.write32 memory 0x1000 (BitVec.ofInt 32 value)
    ∃ after, heap.storeBytes 4 (Lanius.Semantics.i32Bytes value) = .ok after ∧
      Storage.Heap.Correspondence after native heapLocations ∧
      after.loadBytes 4 4 = .ok (Lanius.Semantics.i32Bytes value) ∧
      after.loadBytes 20 1 = .ok [9] ∧
      Machine.read32 native 0x1000 = BitVec.ofInt 32 value ∧ native 0x2000 = 9 ∧
      after.nextAddress = heap.nextAddress ∧ after.remaining = heap.remaining := by
  obtain ⟨after, stored, frontier, budget, related⟩ := correspondence.store_i32
    (block := firstBlock) (by simp [heap]) rfl (start := 0) (by decide) value
  have read := heap.loadBytes_after_store correspondence.wellFormed stored
  have other := heap.loadBytes_after_store_disjoint correspondence.wellFormed stored
    (query := 20) (count := 1) (bytes := [9]) (by cbv)
    (by right; simp [firstBlock, Lanius.Semantics.i32Bytes])
  exact ⟨after, stored, by simpa using related,
    by simpa [firstBlock, Lanius.Semantics.i32Bytes] using read, other, Machine.read32_write32 _ _ _,
    by simp [Machine.write32, memory], frontier, budget⟩

theorem middle_bulk_store :
    ∃ after, heap.storeBytes 5 [254, 255] = .ok after ∧
      Storage.Heap.Correspondence after (Storage.Heap.writeBytes memory 0x1001 [254, 255]) heapLocations := by
  obtain ⟨after, stored, _, _, related⟩ := correspondence.store_bytes
    (block := firstBlock) (by simp [heap]) rfl (start := 1) (bytes := [254, 255]) (by decide)
  exact ⟨after, stored, related⟩

example : (heap.storeBytes 5 [254, 255]).bind (fun after => after.loadBytes 4 4) =
    .ok [1, 254, 255, 4] := by cbv
example : (heap.storeBytes 4 (Lanius.Semantics.i32Bytes (-2))).bind
    (fun after => (after.loadBytes 4 4).map Lanius.Semantics.decodeI32) = .ok (-2) := by cbv
example : heap.storeBytes 7 [254, 255] = .error .rawMemoryBounds := by cbv

/-- Empty writes at the end of an allocation need no one-past mapping. -/
example : ∃ after, heap.storeBytes 8 [] = .ok after ∧
    Storage.Heap.Correspondence after memory heapLocations := by
  obtain ⟨after, stored, _, _, related⟩ := correspondence.store_bytes
    (block := firstBlock) (by simp [heap]) rfl (start := 4) (bytes := []) (by decide)
  exact ⟨after, stored, related⟩

example : Machine.read32 (Storage.Heap.writeBytes memory 0xffffffffffffffff
    (Lanius.Semantics.i32Bytes (-2147483648))) 0xffffffffffffffff = 0x80000000 := by
  rw [Storage.Heap.writeBytes_i32, Machine.read32_write32]
  rfl

private def storeMachine : Machine.State := {
  registers := fun register => if register = 9 then BitVec.ofInt 64 (-2)
    else if register = 12 then 0x1004 else 77
  memory := fun address => if address.toNat < 8 then
    ([0x45, 0x89, 0x8c, 0x24, 0xfc, 0xff, 0xff, 0xff] : List UInt8)[address.toNat]!
    else memory address
  rip := 0, flags := 0x202 }

/-- Extended registers, a SIB base, and negative disp32 exercise the real
decoder and an instruction loaded from memory, not an assumed native step. -/
theorem relocated_store_step :
    Machine.Step storeMachine (storeMachine.store32 9 12 (BitVec.ofInt 32 (-4)) 8) ∧
    Machine.read32 (storeMachine.store32 9 12 (BitVec.ofInt 32 (-4)) 8).memory 0x1000 =
      BitVec.ofInt 32 (-2) ∧
    (storeMachine.store32 9 12 (BitVec.ofInt 32 (-4)) 8).memory 0x2000 = 9 := by
  refine ⟨.decoded [0x45, 0x89, 0x8c, 0x24, 0xfc, 0xff, 0xff, 0xff] ?_
    (.store32 9 12 (BitVec.ofInt 32 (-4))) 8 (by decide) rfl, by decide, by decide⟩
  intro index bound
  have bytes : ∀ index : Fin 8, storeMachine.memory (BitVec.ofNat 64 index.val) =
      ([0x45, 0x89, 0x8c, 0x24, 0xfc, 0xff, 0xff, 0xff] : List UInt8)[index.val] := by decide
  change storeMachine.memory (0#64 + BitVec.ofNat 64 index) = _
  simpa using bytes ⟨index, bound⟩

example : ¬ Storage.Heap.BlockRep firstBlock memory 0xffffffffffffffff := by
  intro represented
  have bound := represented.nativeBound
  change 18446744073709551615 + 4 ≤ 18446744073709551616 at bound
  omega

example : Machine.decode [0x48, 0x39, 0xc1] = some (.compare64 1 0, 3) := by decide

private def firstRegion : Storage.Heap.AllocationRegion := { base := 0x800, size := 16 }
private def secondRegion : Storage.Heap.AllocationRegion := { base := 0x400, size := 8 }
private def firstMemory := Storage.Heap.writeByte memory 0x80c 77
private def secondMemory := Storage.Heap.writeByte firstMemory 0x404 88
private def firstHeap : Lanius.Memory.Heap := {
  heap with blocks := heap.blocks ++ [Storage.Heap.allocatedBlock 24 4 4], nextAddress := 28 }
private def secondHeap : Lanius.Memory.Heap := {
  firstHeap with blocks := firstHeap.blocks ++ [Storage.Heap.allocatedBlock 28 0 4], nextAddress := 29 }

private theorem firstAllocated : heap.allocate 4 4 = .allocated 24 firstHeap := by cbv
private theorem secondAllocated : firstHeap.allocate 0 4 = .allocated 28 secondHeap := by cbv

-- These effects intentionally modify padding outside the payload. They
-- model the declared allocator contract, not an execution proof for mmap.
private theorem firstEffect : Storage.Heap.AllocationEffect memory firstMemory 0x800 4 4 firstRegion := by
  refine ⟨by decide, by decide, by decide, by decide, ?_, ?_⟩
  · intro offset inside
    have cases : offset = 0 ∨ offset = 1 ∨ offset = 2 ∨ offset = 3 := by omega
    rcases cases with rfl | rfl | rfl | rfl <;> cbv
  · intro address outside
    change (if address = 0x80c then 77 else memory address) = memory address
    apply if_neg
    intro same
    subst address
    exact outside (by unfold Storage.Heap.AllocationRegion.Contains; decide)

private theorem secondEffect : Storage.Heap.AllocationEffect firstMemory secondMemory 0x400 0 4 secondRegion := by
  refine ⟨by decide, by decide, by decide, by decide, ?_, ?_⟩
  · intro offset inside
    omega
  · intro address outside
    change (if address = 0x404 then 88 else firstMemory address) = firstMemory address
    apply if_neg
    intro same
    subst address
    exact outside (by unfold Storage.Heap.AllocationRegion.Contains; decide)

theorem descending_allocations :
    heap.allocate 4 4 = .allocated 24 firstHeap ∧
    firstHeap.allocate 0 4 = .allocated 28 secondHeap ∧
    ∃ finalLocations, Storage.Heap.Correspondence secondHeap secondMemory finalLocations ∧
      finalLocations.pointer 4 = some 0x1000 ∧ finalLocations.pointer 20 = some 0x2000 ∧
      finalLocations.pointer 24 = some 0x800 ∧ finalLocations.pointer 28 = some 0x400 := by
  refine ⟨firstAllocated, secondAllocated, ?_⟩
  have separate : ∀ old ∈ heap.blocks, ∀ oldBase,
      heapLocations.pointer old.base = some oldBase →
      oldBase.toNat + max old.size 1 ≤ firstRegion.base.toNat ∨
        firstRegion.base.toNat + firstRegion.size ≤ oldBase.toNat := by
    intro old member oldBase mapped
    simp only [heap, List.mem_cons, List.not_mem_nil, or_false] at member
    rcases member with rfl | rfl <;>
      simp [heapLocations, heapMap, firstBlock, secondBlock] at mapped
    all_goals rw [← mapped]; exact Or.inr (by decide)
  obtain ⟨middleLocations, middle, firstPointer, retained, _, _⟩ :=
    correspondence.allocate firstAllocated (by decide) firstEffect separate
  have leftMap : middleLocations.pointer 4 = some 0x1000 := retained _ _ rfl
  have rightMap : middleLocations.pointer 20 = some 0x2000 := retained _ _ rfl
  have nextSeparate : ∀ old ∈ firstHeap.blocks, ∀ oldBase,
      middleLocations.pointer old.base = some oldBase →
      oldBase.toNat + max old.size 1 ≤ secondRegion.base.toNat ∨
        secondRegion.base.toNat + secondRegion.size ≤ oldBase.toNat := by
    intro old member oldBase mapped
    simp only [firstHeap, heap, List.cons_append, List.nil_append,
      List.mem_cons, List.not_mem_nil, or_false] at member
    rcases member with rfl | rfl | rfl
    · have same := Option.some.inj (leftMap.symm.trans mapped)
      rw [← same]
      exact Or.inr (by decide)
    · have same := Option.some.inj (rightMap.symm.trans mapped)
      rw [← same]
      exact Or.inr (by decide)
    · have same := Option.some.inj (firstPointer.symm.trans mapped)
      rw [← same]
      exact Or.inr (by decide)
  obtain ⟨finalLocations, final, secondPointer, oldPointers, _, _⟩ :=
    middle.allocate secondAllocated (by decide) secondEffect nextSeparate
  exact ⟨finalLocations, final, oldPointers _ _ leftMap, oldPointers _ _ rightMap,
    oldPointers _ _ firstPointer, secondPointer⟩

example : firstMemory 0x80c = 77 ∧ secondMemory 0x404 = 88 ∧ secondMemory 0x1000 = 1 := by cbv
example : secondHeap.loadByte 28 0 = .error .rawMemoryBounds := by cbv

-- Core allocation identities are not executable address literals. Null is
-- the sole portable pointer literal; usize retains its full numeric domain.
example : Transport.literal? (.pointer 0) = some [4, 0, 0] := by decide
example : Transport.literal? (.pointer 4) = none := by decide
example : Transport.literal? (.pointer 4096) = none := by decide
example : Transport.literal? (.pointer 4294967296) = none := by decide
example : Transport.literal? (.pointer 18446744073709551615) = none := by decide
example : Transport.literal? (.unsigned .usize 4) = some [3, 4, 0] := by decide
example : Transport.literal? (.unsigned .usize 4294967296) = some [3, 0, 1] := by decide
example : Transport.literal? (.unsigned .usize 18446744073709551615) = some [3, -1, -1] := by decide

private def returning (type : Ty) (expression : Expr) : Program := {
  functions := [{ id := 0, parameters := [], returnType := type, body := some (.returnValue (some expression)) }] }

private def constantProgram (type : Ty) (value : Value) : Program := {
  returning type (.constant 7) with constants := [{ id := 7, type, value }] }

example : Transport.expression? {} (.value (.pointer 4)) = none := by cbv
example : Transport.expression? {} (.value (.pointer 0)) = some [0, 4, 0, 0] := by cbv
example : Transport.expression? (constantProgram (.scalar .rawPtr) (.pointer 4)) (.constant 7) = none := by cbv
example : Transport.expression? (constantProgram (.scalar .rawPtr) (.pointer 0)) (.constant 7) = some [13, 7] := by cbv

example : Transport.program? (returning (.scalar .rawPtr) (.value (.pointer 4))) 0 = none := by cbv
example : Transport.program? (constantProgram (.scalar .rawPtr) (.pointer 4)) 0 = none := by cbv
example : (Transport.program? (returning (.scalar .rawPtr) (.value (.pointer 0))) 0).isSome = true := by cbv
example : (Transport.program? (constantProgram (.scalar .rawPtr) (.pointer 0)) 0).isSome = true := by cbv
example : (Transport.program? (constantProgram (.scalar (.unsigned .usize)) (.unsigned .usize 4)) 0).isSome = true := by cbv
example : (Transport.program? (constantProgram (.scalar (.unsigned .usize))
    (.unsigned .usize 18446744073709551615)) 0).isSome = true := by cbv

run_elab do
  let standard := [``propext, ``Classical.choice, ``Quot.sound]
  for name in [``Storage.Locations.pointer_null_iff, ``Storage.Locations.pointer_eq_iff,
      ``Machine.arithmeticFlags_zero, ``Machine.compare_equal, ``Machine.compare_notEqual,
      ``Storage.Pointer.equal, ``Storage.Pointer.notEqual, ``Storage.Pointer.compare_equal, ``Storage.Pointer.compare_notEqual,
      ``Storage.Pointer.compare_step, ``Storage.Pointer.comparison_steps, ``Storage.Heap.BlockRep.address_toNat,
      ``Storage.Heap.Correspondence.pointer_injective, ``Storage.Heap.Correspondence.within_add,
      ``Storage.Heap.containing_block, ``Storage.Heap.Correspondence.load_byte,
      ``Storage.Heap.Correspondence.load_bytes4, ``Storage.Heap.Correspondence.load_i32,
      ``Storage.Heap.BlockRep.frame, ``Storage.Heap.BlockRep.store,
      ``Storage.Heap.Correspondence.byte_disjoint, ``Storage.Heap.Correspondence.store_byte,
      ``Storage.Heap.writeBytes_i32, ``Storage.Heap.Correspondence.store_bytes,
      ``Storage.Heap.Correspondence.store_i32, ``Storage.Heap.Correspondence.store_i32_step,
      ``Storage.Locations.extend_slice, ``Storage.Locations.extend_string,
      ``Storage.Locations.extend_outside, ``Storage.Locations.extend_below,
      ``Storage.Locations.extend_inside, ``Storage.Locations.extend_base,
      ``Storage.Heap.Correspondence.extend_old, ``Storage.Heap.Correspondence.extend,
      ``Storage.Heap.allocation_shape, ``Storage.Heap.AllocationEffect.bounded,
      ``Storage.Heap.AllocationEffect.address_toNat, ``Storage.Heap.AllocationEffect.old_frame,
      ``Storage.Heap.AllocationEffect.read64_frame, ``Storage.Heap.AllocationEffect.payload_separate,
      ``Storage.Heap.Correspondence.allocate,
      ``Storage.shape_pointer, ``Storage.shape_pointer_some, ``Storage.shape_pointer_none,
      ``Storage.shape_null, ``Storage.shape_usize, ``Storage.shape_usize_some, ``Storage.shape_usize_none,
      ``Storage.Stored.full_iff, ``Storage.Represents.pointer_iff, ``Storage.Represents.null_iff,
      ``Storage.Represents.usize_iff, ``Transport.literal_pointer_accepted, ``Transport.literal_pointer_rejected,
      ``relocated_word, ``identity_word_rejected, ``missing_word_rejected, ``store_retains_other_block,
      ``word_store_roundtrip, ``middle_bulk_store, ``relocated_store_step,
      ``descending_allocations] do
    for assumption in ← Lean.collectAxioms name do
      unless standard.contains assumption do
        throwError "pointer storage theorem {name} adds unexpected axiom {assumption}"
  Lean.logInfo "Kernel-only pointer checks: relocated words and heap bytes, pointer equality, null/missing/dangling/alias/bounds rejection, framed stores, descending native allocations with padding and zero-size identity, and nonnull-literal transport rejection; all audited proofs use only standard axioms"

end Lanius.X86.Tests.Pointers
