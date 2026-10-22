import Lanius.Memory.Read

namespace Lanius.Memory

/-- Fresh aligned storage for the packed-i32 host interface. -/
def Heap.borrowedAddress (heap : Heap) : Address := alignUp (max heap.nextAddress 1) 4

def Heap.borrowedI32 (heap : Heap) (bytes : List UInt8) : Heap :=
  { heap with
    blocks := heap.blocks ++ [{
      base := heap.borrowedAddress, size := bytes.length, alignment := 4, bytes := bytes, owned := false }],
    nextAddress := heap.borrowedAddress + max bytes.length 1 }

theorem Heap.borrowedAddress_ge (heap : Heap) : heap.nextAddress ≤ heap.borrowedAddress := by
  change heap.nextAddress ≤ ((max heap.nextAddress 1 + 4 - 1) / 4) * 4
  have lower : heap.nextAddress ≤ max heap.nextAddress 1 := Nat.le_max_left _ _
  have positive : 1 ≤ max heap.nextAddress 1 := Nat.le_max_right _ _
  dsimp only [Address] at *
  omega

theorem Heap.borrowedAddress_pos (heap : Heap) : 0 < heap.borrowedAddress := by
  change 0 < ((max heap.nextAddress 1 + 4 - 1) / 4) * 4
  have positive := Nat.le_max_right heap.nextAddress 1
  dsimp only [Address] at *
  omega

theorem Heap.mapBorrowed_i32 (heap : Heap) (bytes : List UInt8) :
    heap.mapBorrowed bytes 4 = .allocated heap.borrowedAddress (heap.borrowedI32 bytes) := by
  simp only [Heap.mapBorrowed, show validAlignment 4 = true by decide, Bool.not_true, Bool.false_eq_true,
    ↓reduceIte, Heap.borrowedAddress, Heap.borrowedI32]

/-- Appending fresh storage preserves every previously successful read. -/
theorem Heap.borrowedI32_oldRead {heap : Heap}
    (read : heap.loadByte pointer offset = .ok byte) :
    (heap.borrowedI32 bytes).loadByte pointer offset = .ok byte := by
  obtain ⟨block, found, value⟩ := Heap.loadByte_ok_iff.mp read
  apply Heap.loadByte_ok_iff.mpr
  refine ⟨block, ?_, value⟩
  simp only [Heap.containingBlock?, Heap.borrowedI32, List.find?_append] at found ⊢
  rw [found, Option.some_or]

private theorem oldBlocks_before (below : HeapBlocksBelowNext heap)
    (block : Block) (member : block ∈ heap.blocks) :
    block.base + max block.size 1 ≤ heap.borrowedAddress :=
  Nat.le_trans (below block member) heap.borrowedAddress_ge

private theorem oldBase_before (below : HeapBlocksBelowNext heap)
    (block : Block) (member : block ∈ heap.blocks) : block.base < heap.borrowedAddress :=
  Nat.lt_of_lt_of_le (Nat.lt_add_of_pos_right
    (Nat.lt_of_lt_of_le (by decide : 0 < 1) (Nat.le_max_right block.size 1)))
    (oldBlocks_before below block member)

theorem Heap.borrowedI32_block (below : HeapBlocksBelowNext heap) (bytes : List UInt8) :
    (heap.borrowedI32 bytes).block? heap.borrowedAddress = some {
      base := heap.borrowedAddress, size := bytes.length, alignment := 4, bytes := bytes, owned := false } := by
  have missing : heap.block? heap.borrowedAddress = none := by
    apply List.find?_eq_none.mpr
    intro block member
    have bound := oldBase_before below block member
    change ¬ (block.base == heap.borrowedAddress) = true
    simp only [beq_iff_eq]
    exact Nat.ne_of_lt bound
  simp only [Heap.block?, Heap.borrowedI32, List.find?_append] at missing ⊢
  rw [missing]
  simp

/-- The borrowed block is the one holding each of its addresses. -/
theorem Heap.borrowedI32_containing (below : HeapBlocksBelowNext heap) (inside : index < bytes.length) :
    (heap.borrowedI32 bytes).containingBlock? (heap.borrowedAddress + index) = some {
      base := heap.borrowedAddress, size := bytes.length, alignment := 4, bytes := bytes, owned := false } := by
  have missing : heap.containingBlock? (heap.borrowedAddress + index) = none := by
    apply List.find?_eq_none.mpr
    intro block member
    have bound : block.base + block.size ≤ heap.borrowedAddress :=
      Nat.le_trans (Nat.add_le_add_left (Nat.le_max_left block.size 1) block.base)
        (oldBlocks_before below block member)
    change ¬ (block.live && block.base ≤ heap.borrowedAddress + index &&
      heap.borrowedAddress + index < block.base + block.size) = true
    simp only [Bool.and_eq_true, decide_eq_true_eq]
    dsimp only [Address] at *
    omega
  simp only [Heap.containingBlock?, Heap.borrowedI32, List.find?_append] at missing ⊢
  simp [missing, inside]

theorem Heap.borrowedI32_read (below : HeapBlocksBelowNext heap)
    (found : bytes[index]? = some byte) :
    (heap.borrowedI32 bytes).loadByte heap.borrowedAddress index = .ok byte := by
  have inside := (List.getElem?_eq_some_iff.mp found).1
  apply Heap.loadByte_ok_iff.mpr
  refine ⟨_, Heap.borrowedI32_containing below inside, ?_⟩
  simpa using found

theorem Heap.borrowedI32_loadBytes (below : HeapBlocksBelowNext heap)
    (bytes : List UInt8) (length : Nat) :
    (heap.borrowedI32 bytes).loadBytes heap.borrowedAddress (bytes.take length).length =
      .ok (bytes.take length) := by
  apply loadBytesFrom_of_reads
  intro index byte found
  have bound := (List.getElem?_eq_some_iff.mp found).1
  have source : bytes[index]? = some byte := by
    rw [List.getElem?_take_of_lt (by simpa using Nat.lt_of_lt_of_le bound (List.length_take_le _ _))] at found
    exact found
  simpa using Heap.borrowedI32_read below source

theorem Heap.borrowedI32_unique (below : HeapBlocksBelowNext heap)
    (unique : HeapBlockBasesUnique heap) : HeapBlockBasesUnique (heap.borrowedI32 bytes) := by
  intro left leftMem right rightMem same
  simp only [Heap.borrowedI32, List.mem_append, List.mem_singleton] at leftMem rightMem
  rcases leftMem with oldLeft | rfl <;> rcases rightMem with oldRight | rfl
  · exact unique left oldLeft right oldRight same
  · exact False.elim ((Nat.ne_of_lt (oldBase_before below left oldLeft)) same)
  · exact False.elim ((Nat.ne_of_lt (oldBase_before below right oldRight)) same.symm)
  · rfl

theorem replaceBlock_self (blocks : List Block) (block : Block)
    (same : ∀ other ∈ blocks, other.base = block.base → other = block) :
    replaceBlock blocks block = blocks := by
  induction blocks with
  | nil => rfl
  | cons head rest ih =>
    have tail := ih (fun other member => same other (by simp [member]))
    simp only [replaceBlock, tail]
    split
    · rename_i equal
      rw [← same head (by simp) (by simpa using equal)]
    · rfl

end Lanius.Memory
