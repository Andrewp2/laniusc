import Lanius.Memory.Borrow

namespace Lanius.Memory

variable {heap : Heap} {block : Block} {bytes values : List UInt8} {byte : UInt8}
  {words pointer offset index count : Nat} {owned : Bool} {budget : Option Nat}

/-- Fresh four-byte-aligned storage, with ownership and budget explicit.
    This is the post-state model shared by owned allocation and raw views. -/
def Heap.appendI32 (heap : Heap) (bytes : List UInt8) (owned : Bool) (budget : Option Nat) : Heap :=
  { heap with
    blocks := heap.blocks ++ [{
      base := heap.borrowedAddress, size := bytes.length,
      alignment := 4, bytes := bytes, owned := owned }]
    nextAddress := heap.borrowedAddress + max bytes.length 1
    remaining := budget }

def Heap.allocatedI32 (heap : Heap) (words : Nat) (budget : Option Nat) : Heap :=
  heap.appendI32 (List.replicate (words * 4) 0) true budget

theorem consumeBudget_of_capacity {remaining : Option Nat} {size : Nat}
    (capacity : ∀ available, remaining = some available → size ≤ available) :
    consumeBudget remaining size = some (remaining.map (fun available => available - size)) := by
  cases remaining with
  | none => rfl
  | some available => simp only [consumeBudget, if_pos (capacity available rfl), Option.map_some]

/-- The real allocator either consumes the available budget and adds zeroed
    storage, or reports exhaustion without changing the heap. -/
theorem Heap.allocate_i32 (heap : Heap) (words : Nat) :
    heap.allocate (words * 4) 4 =
      match consumeBudget heap.remaining (words * 4) with
      | none => .exhausted heap
      | some budget => .allocated heap.borrowedAddress (heap.allocatedI32 words budget) := by
  simp only [Heap.allocate, show validAlignment 4 = true by decide,
    Bool.not_true, Bool.false_eq_true, ↓reduceIte]
  cases h : consumeBudget heap.remaining (words * 4) <;>
    simp only [Heap.allocatedI32, Heap.appendI32, Heap.borrowedAddress, List.length_replicate]

theorem Heap.appendI32_oldRead (read : heap.loadByte pointer offset = .ok byte) :
    (heap.appendI32 bytes owned budget).loadByte pointer offset = .ok byte := by
  obtain ⟨block, found, value⟩ := Heap.loadByte_ok_iff.mp read
  apply Heap.loadByte_ok_iff.mpr
  refine ⟨block, ?_, value⟩
  simp only [Heap.containingBlock?, Heap.appendI32, List.find?_append] at found ⊢
  rw [found, Option.some_or]

theorem Heap.appendI32_oldReadable (readable : heap.Readable pointer count) :
    (heap.appendI32 bytes owned budget).Readable pointer count := by
  intro index inside
  obtain ⟨byte, read⟩ := readable index inside
  exact ⟨byte, Heap.appendI32_oldRead read⟩

private theorem oldBefore (below : HeapBlocksBelowNext heap) (member : block ∈ heap.blocks) :
    block.base + max block.size 1 ≤ heap.borrowedAddress :=
  Nat.le_trans (below block member) heap.borrowedAddress_ge

private theorem oldBaseBefore (below : HeapBlocksBelowNext heap) (member : block ∈ heap.blocks) :
    block.base < heap.borrowedAddress := by
  have bound := oldBefore below member
  have positive := Nat.le_max_right block.size 1
  dsimp only [Lanius.Address] at *
  omega

theorem Heap.appendI32_block (below : HeapBlocksBelowNext heap) :
    (heap.appendI32 bytes owned budget).block? heap.borrowedAddress = some {
      base := heap.borrowedAddress, size := bytes.length, alignment := 4, bytes := bytes, owned := owned } := by
  have missing : heap.block? heap.borrowedAddress = none := by
    apply List.find?_eq_none.mpr
    intro block member
    change ¬ (block.base == heap.borrowedAddress) = true
    simp only [beq_iff_eq]
    exact Nat.ne_of_lt (oldBaseBefore below member)
  simp only [Heap.block?, Heap.appendI32, List.find?_append] at missing ⊢
  rw [missing]
  simp

theorem Heap.appendI32_read (below : HeapBlocksBelowNext heap) (found : bytes[index]? = some byte) :
    (heap.appendI32 bytes owned budget).loadByte heap.borrowedAddress index = .ok byte := by
  have inside := (List.getElem?_eq_some_iff.mp found).1
  have missing : heap.containingBlock? (heap.borrowedAddress + index) = none := by
    apply List.find?_eq_none.mpr
    intro block member
    have bound := oldBefore below member
    change ¬ (block.live && block.base ≤ heap.borrowedAddress + index &&
      heap.borrowedAddress + index < block.base + block.size) = true
    simp only [Bool.and_eq_true, decide_eq_true_eq]
    dsimp only [Lanius.Address] at *
    omega
  apply Heap.loadByte_ok_iff.mpr
  refine ⟨{ base := heap.borrowedAddress, size := bytes.length, alignment := 4, bytes := bytes, owned := owned }, ?_, ?_⟩
  · simp only [Heap.containingBlock?, Heap.appendI32, List.find?_append] at missing ⊢
    simp [missing, inside]
  · simpa using found

theorem Heap.appendI32_unique (below : HeapBlocksBelowNext heap) (unique : HeapBlockBasesUnique heap) :
    HeapBlockBasesUnique (heap.appendI32 bytes owned budget) := by
  intro left leftMem right rightMem same
  simp only [Heap.appendI32, List.mem_append, List.mem_singleton] at leftMem rightMem
  rcases leftMem with oldLeft | rfl <;> rcases rightMem with oldRight | rfl
  · exact unique left oldLeft right oldRight same
  · exact False.elim ((Nat.ne_of_lt (oldBaseBefore below oldLeft)) same)
  · exact False.elim ((Nat.ne_of_lt (oldBaseBefore below oldRight)) same.symm)
  · rfl

theorem Heap.appendI32_below (below : HeapBlocksBelowNext heap) :
    HeapBlocksBelowNext (heap.appendI32 bytes owned budget) := by
  intro block member
  rcases List.mem_append.mp member with old | fresh
  · exact Nat.le_trans (oldBefore below old) (Nat.le_add_right _ _)
  · simp only [List.mem_singleton] at fresh
    subst block
    exact Nat.le_refl _

private theorem replaceBlock_appendFresh (blocks : List Block) (fresh replacement : Block)
    (same : fresh.base = replacement.base)
    (missing : ∀ block ∈ blocks, block.base ≠ replacement.base) :
    replaceBlock (blocks ++ [fresh]) replacement = blocks ++ [replacement] := by
  induction blocks with
  | nil => simp [replaceBlock, same]
  | cons block blocks ih =>
      have different := missing block (by simp)
      simp [replaceBlock, different, ih (fun item member => missing item (by simp [member]))]

/-- Protecting freshly allocated storage changes ownership, not its bytes,
    frontier, or already-consumed allocation budget. -/
theorem Heap.appendI32_protect (below : HeapBlocksBelowNext heap) :
    (heap.appendI32 bytes owned budget).protectAsBorrowed heap.borrowedAddress bytes.length 4 =
      .ok (heap.appendI32 bytes false budget) := by
  simp only [Heap.protectAsBorrowed, Heap.appendI32_block below, Bool.not_true,
    Bool.false_eq_true, ↓reduceIte]
  have replaced := replaceBlock_appendFresh heap.blocks
    { base := heap.borrowedAddress, size := bytes.length, alignment := 4, bytes, owned }
    { base := heap.borrowedAddress, size := bytes.length, alignment := 4, bytes, owned := false }
    rfl (fun block member => Nat.ne_of_lt (oldBaseBefore below member))
  simp [Heap.appendI32, replaced]

theorem Heap.allocatedI32_protect (below : HeapBlocksBelowNext heap) :
    (heap.allocatedI32 words budget).protectAsBorrowed heap.borrowedAddress (words * 4) 4 =
      .ok (heap.appendI32 (List.replicate (words * 4) 0) false budget) := by
  simpa only [Heap.allocatedI32, List.length_replicate] using
    Heap.appendI32_protect (bytes := List.replicate (words * 4) 0) (owned := true) (budget := budget) below

theorem Heap.appendI32_readable (below : HeapBlocksBelowNext heap) :
    (heap.appendI32 bytes owned budget).Readable heap.borrowedAddress bytes.length := by
  intro index inside
  exact ⟨bytes[index], Heap.appendI32_read below (List.getElem?_eq_getElem inside)⟩

theorem Heap.allocatedI32_readable (below : HeapBlocksBelowNext heap) :
    (heap.allocatedI32 words budget).Readable heap.borrowedAddress (words * 4) := by
  simpa only [Heap.allocatedI32, List.length_replicate] using
    Heap.appendI32_readable (bytes := List.replicate (words * 4) 0) (owned := true) (budget := budget) below

theorem Heap.allocatedI32_oldReadable (readable : heap.Readable pointer count) :
    (heap.allocatedI32 words budget).Readable pointer count :=
  Heap.appendI32_oldReadable readable

theorem Heap.allocatedI32_unique (below : HeapBlocksBelowNext heap) (unique : HeapBlockBasesUnique heap) :
    HeapBlockBasesUnique (heap.allocatedI32 words budget) :=
  Heap.appendI32_unique below unique

theorem Heap.appendI32_oldLoad (loaded : heap.loadBytes pointer count = .ok values) :
    (heap.appendI32 bytes owned budget).loadBytes pointer count = .ok values := by
  have length := (loadBytesFrom_spec loaded).1
  rw [← length]
  apply loadBytesFrom_of_reads
  intro index byte found
  simpa using Heap.appendI32_oldRead (Heap.loadBytes_get loaded found)

theorem Heap.appendI32_zeroWord (below : HeapBlocksBelowNext heap) (inside : index < words) :
    (heap.appendI32 (List.replicate (words * 4) 0) owned budget).loadBytes
      (heap.borrowedAddress + index * 4) 4 = .ok (List.replicate 4 0) := by
  have result := loadBytesFrom_of_reads
    (heap := heap.appendI32 (List.replicate (words * 4) 0) owned budget)
    (pointer := heap.borrowedAddress + index * 4) (offset := 0) (List.replicate 4 0) (by
    intro offset byte found
    have bound : offset < 4 := by
      have := (List.getElem?_eq_some_iff.mp found).1
      simpa only [List.length_replicate] using this
    have zero : byte = 0 := by simpa only [List.getElem?_replicate_of_lt bound, Option.some.injEq] using found.symm
    subst byte
    have fresh := Heap.appendI32_read (bytes := List.replicate (words * 4) 0) (owned := owned) (budget := budget)
      below (List.getElem?_replicate_of_lt (by omega : index * 4 + offset < words * 4))
    exact Heap.loadByte_alias fresh (by omega))
  simpa only [Heap.loadBytes, List.length_replicate] using result

end Lanius.Memory
