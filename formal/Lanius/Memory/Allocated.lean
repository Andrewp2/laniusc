import Lanius.Memory.Read

namespace Lanius.Memory

variable {heap : Heap} {block : Block} {size alignment offset count pointer : Nat}
  {budget : Option Nat} {byte : UInt8}

def Heap.allocationAddress (heap : Heap) (alignment : Nat) : Address :=
  alignUp (max heap.nextAddress 1) alignment

def Heap.allocationBlock (heap : Heap) (size alignment : Nat) : Block := {
  base := heap.allocationAddress alignment, size, alignment, bytes := List.replicate size 0 }

/-- The exact fresh-storage state of the allocator, not an assumed successful
    result. Budget and valid alignment are checked by `allocate_of_budget`. -/
def Heap.allocatedBytes (heap : Heap) (size alignment : Nat) (budget : Option Nat) : Heap := {
  heap with
    blocks := heap.blocks ++ [heap.allocationBlock size alignment]
    nextAddress := heap.allocationAddress alignment + max size 1
    remaining := budget }

theorem Heap.allocationAddress_ge (heap : Heap) (positive : 0 < alignment) :
    heap.nextAddress ≤ heap.allocationAddress alignment := by
  have remainder := Nat.mod_lt (max heap.nextAddress 1 + alignment - 1) positive
  have division := Nat.mod_add_div (max heap.nextAddress 1 + alignment - 1) alignment
  rw [Nat.mul_comm alignment] at division
  have lower := Nat.le_max_left heap.nextAddress 1
  change heap.nextAddress ≤ ((max heap.nextAddress 1 + alignment - 1) / alignment) * alignment
  dsimp only [Lanius.Address] at *
  omega

theorem Heap.allocationAddress_aligned (heap : Heap) : heap.allocationAddress alignment % alignment = 0 := by
  simp [Heap.allocationAddress, alignUp]

theorem Heap.allocationAddress_pos (heap : Heap) (positive : 0 < alignment) :
    0 < heap.allocationAddress alignment := by
  have remainder := Nat.mod_lt (max heap.nextAddress 1 + alignment - 1) positive
  have division := Nat.mod_add_div (max heap.nextAddress 1 + alignment - 1) alignment
  rw [Nat.mul_comm alignment] at division
  have lower := Nat.le_max_right heap.nextAddress 1
  change 0 < ((max heap.nextAddress 1 + alignment - 1) / alignment) * alignment
  dsimp only [Lanius.Address] at *
  omega

theorem Heap.allocate_of_budget (valid : validAlignment alignment = true)
    (available : consumeBudget heap.remaining size = some budget) :
    heap.allocate size alignment = .allocated (heap.allocationAddress alignment)
      (heap.allocatedBytes size alignment budget) := by
  simp only [Heap.allocate, valid, Bool.not_true, Bool.false_eq_true, ↓reduceIte, available]
  rfl

private theorem oldBefore (below : HeapBlocksBelowNext heap) (positive : 0 < alignment)
    (member : block ∈ heap.blocks) : block.base + max block.size 1 ≤ heap.allocationAddress alignment :=
  Nat.le_trans (below block member) (heap.allocationAddress_ge positive)

theorem Heap.allocatedBytes_containing (below : HeapBlocksBelowNext heap) (positive : 0 < alignment)
    (inside : offset < size) :
    (heap.allocatedBytes size alignment budget).containingBlock? (heap.allocationAddress alignment + offset) =
      some (heap.allocationBlock size alignment) := by
  have missing : heap.containingBlock? (heap.allocationAddress alignment + offset) = none := by
    apply List.find?_eq_none.mpr
    intro block member
    have bound := oldBefore below positive member
    change ¬ (block.live && block.base ≤ heap.allocationAddress alignment + offset &&
      heap.allocationAddress alignment + offset < block.base + block.size) = true
    simp only [Bool.and_eq_true, decide_eq_true_eq]
    dsimp only [Lanius.Address] at *
    omega
  simp only [Heap.containingBlock?, Heap.allocatedBytes, List.find?_append] at missing ⊢
  simp [missing, Heap.allocationBlock, inside]

theorem Heap.allocatedBytes_read (below : HeapBlocksBelowNext heap) (positive : 0 < alignment)
    (inside : offset < size) :
    (heap.allocatedBytes size alignment budget).loadByte (heap.allocationAddress alignment) offset = .ok 0 := by
  apply Heap.loadByte_ok_iff.mpr
  refine ⟨heap.allocationBlock size alignment, heap.allocatedBytes_containing below positive inside, ?_⟩
  simpa only [Heap.allocationBlock, Nat.add_sub_cancel_left] using List.getElem?_replicate_of_lt inside (a := (0 : UInt8))

theorem Heap.allocatedBytes_zeroRange (below : HeapBlocksBelowNext heap) (positive : 0 < alignment)
    (bounds : offset + count ≤ size) :
    (heap.allocatedBytes size alignment budget).loadBytes (heap.allocationAddress alignment + offset) count =
      .ok (List.replicate count 0) := by
  have loaded := loadBytesFrom_of_reads (List.replicate count (0 : UInt8)) (heap := heap.allocatedBytes size alignment budget)
    (pointer := heap.allocationAddress alignment + offset) (offset := 0) (by
      intro index byte found
      have inside : index < count := by simpa only [List.length_replicate] using (List.getElem?_eq_some_iff.mp found).1
      have zero : byte = 0 := by simpa only [List.getElem?_replicate_of_lt inside, Option.some.injEq] using found.symm
      subst byte
      exact Heap.loadByte_alias (heap.allocatedBytes_read below positive (by omega : offset + index < size)) (by omega))
  simpa only [Heap.loadBytes, List.length_replicate] using loaded

theorem Heap.allocatedBytes_unique (below : HeapBlocksBelowNext heap) (unique : HeapBlockBasesUnique heap)
    (positive : 0 < alignment) : HeapBlockBasesUnique (heap.allocatedBytes size alignment budget) := by
  intro left hl right hr same
  simp only [Heap.allocatedBytes, List.mem_append, List.mem_singleton] at hl hr
  have apart : ∀ block ∈ heap.blocks, block.base < heap.allocationAddress alignment := by
    intro block member
    have bound := oldBefore below positive member
    have reserved := Nat.le_max_right block.size 1
    dsimp only [Lanius.Address] at *
    omega
  rcases hl with hl | rfl <;> rcases hr with hr | rfl
  · exact unique left hl right hr same
  · exact False.elim ((Nat.ne_of_lt (apart left hl)) same)
  · exact False.elim ((Nat.ne_of_lt (apart right hr)) same.symm)
  · rfl

theorem Heap.allocatedBytes_oldRead (read : heap.loadByte pointer offset = .ok byte) :
    (heap.allocatedBytes size alignment budget).loadByte pointer offset = .ok byte := by
  obtain ⟨block, found, contents⟩ := Heap.loadByte_ok_iff.mp read
  apply Heap.loadByte_ok_iff.mpr
  refine ⟨block, ?_, contents⟩
  simp only [Heap.containingBlock?, Heap.allocatedBytes, List.find?_append] at found ⊢
  rw [found, Option.some_or]

theorem Heap.allocatedBytes_below (below : HeapBlocksBelowNext heap) (positive : 0 < alignment) :
    HeapBlocksBelowNext (heap.allocatedBytes size alignment budget) := by
  intro block member
  rcases List.mem_append.mp member with old | fresh
  · exact Nat.le_trans (oldBefore below positive old) (Nat.le_add_right _ _)
  · simp only [List.mem_singleton] at fresh
    subst block
    exact Nat.le_refl _

end Lanius.Memory
