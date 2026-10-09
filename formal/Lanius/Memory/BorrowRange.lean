import Lanius.Memory.Borrow

namespace Lanius.Memory

private def borrowedBlock (base : Address) (block : Block) : Block :=
  { block with owned := if block.base == base then false else block.owned }

/-- Ownership transfer changes no allocation identity, liveness or bytes. -/
def Heap.borrowBlock (heap : Heap) (base : Address) : Heap :=
  { heap with blocks := heap.blocks.map (borrowedBlock base) }

theorem Heap.borrowBlock_idempotent (heap : Heap) (base : Address) :
    (heap.borrowBlock base).borrowBlock base = heap.borrowBlock base := by
  simp only [Heap.borrowBlock, List.map_map]
  congr 1
  apply List.map_congr_left
  intro block _
  simp only [Function.comp_def, borrowedBlock]
  split <;> rfl

private theorem borrowFind (heap : Heap) (base : Address) (predicate : Block → Bool)
    (stable : ∀ block, predicate (borrowedBlock base block) = predicate block) :
    (heap.borrowBlock base).blocks.find? predicate =
      (heap.blocks.find? predicate).map (borrowedBlock base) := by
  simp only [Heap.borrowBlock, List.find?_map]
  rw [show predicate ∘ borrowedBlock base = predicate from funext stable]

theorem Heap.containingBlock?_borrowBlock (heap : Heap) (base address : Address) :
    (heap.borrowBlock base).containingBlock? address =
      (heap.containingBlock? address).map (borrowedBlock base) :=
  borrowFind heap base _ (fun _ => rfl)

theorem Heap.containingBlock?_borrowSelected {heap : Heap} {block : Block} {pointer : Address}
    (found : heap.containingBlock? pointer = some block) :
    (heap.borrowBlock block.base).containingBlock? pointer = some { block with owned := false } := by
  rw [Heap.containingBlock?_borrowBlock, found]
  simp only [Option.map_some, borrowedBlock, BEq.rfl, ↓reduceIte]

theorem Heap.block?_borrowBlock (heap : Heap) (base address : Address) :
    (heap.borrowBlock base).block? address =
      (heap.block? address).map (borrowedBlock base) :=
  borrowFind heap base _ (fun _ => rfl)

theorem Heap.loadByte_borrowBlock (heap : Heap) (base pointer offset : Address) :
    (heap.borrowBlock base).loadByte pointer offset = heap.loadByte pointer offset := by
  simp only [Heap.loadByte, Heap.containingBlock?_borrowBlock, Heap.block?_borrowBlock]
  cases heap.containingBlock? (pointer + offset) <;>
    cases heap.containingBlock? pointer <;> cases heap.block? pointer <;> rfl

theorem Heap.loadBytes_borrowBlock (heap : Heap) (base pointer count : Nat) :
    (heap.borrowBlock base).loadBytes pointer count = heap.loadBytes pointer count := by
  change loadBytesFrom (heap.borrowBlock base) pointer 0 count = loadBytesFrom heap pointer 0 count
  generalize 0 = offset
  induction count generalizing offset with
  | zero => rfl
  | succ count ih => simp only [loadBytesFrom, Heap.loadByte_borrowBlock, ih]

theorem HeapBlockBasesUnique.borrowBlock (unique : HeapBlockBasesUnique heap) :
    HeapBlockBasesUnique (heap.borrowBlock base) := by
  intro left leftMem right rightMem same
  change left ∈ heap.blocks.map (borrowedBlock base) at leftMem
  change right ∈ heap.blocks.map (borrowedBlock base) at rightMem
  obtain ⟨oldLeft, oldLeftMember, rfl⟩ := List.mem_map.mp leftMem
  obtain ⟨oldRight, oldRightMember, rfl⟩ := List.mem_map.mp rightMem
  exact congrArg (borrowedBlock base) (unique oldLeft oldLeftMember oldRight oldRightMember same)

theorem HeapBlocksBelowNext.borrowBlock (below : HeapBlocksBelowNext heap) :
    HeapBlocksBelowNext (heap.borrowBlock base) := by
  intro block member
  obtain ⟨original, oldMember, rfl⟩ := List.mem_map.mp member
  exact below original oldMember

private theorem replaceBlock_borrow (blocks : List Block) (block : Block)
    (same : ∀ other ∈ blocks, other.base = block.base → other = block) :
    replaceBlock blocks { block with owned := false } = blocks.map (borrowedBlock block.base) := by
  induction blocks with
  | nil => rfl
  | cons head rest ih =>
      have tail := ih (fun other member equal => same other (by simp [member]) equal)
      simp only [replaceBlock, List.map_cons, tail, borrowedBlock]
      split
      · rename_i equal
        have sameHead := same head (by simp) (by simpa using equal)
        subst head
        rfl
      · rfl

/-- Derive the real interior-range borrow from one live allocation. Neither
    descriptor construction nor successful borrowing is an input premise. -/
theorem Heap.protectRangeAsBorrowed_of_block
    (found : heap.containingBlock? pointer = some block)
    (positive : 0 < size) (aligned : pointer % alignment = 0)
    (valid : validAlignment alignment = true) (enough : alignment ≤ block.alignment)
    (bounds : pointer + size ≤ block.base + block.size) (unique : HeapBlockBasesUnique heap) :
    heap.protectRangeAsBorrowed pointer size alignment = .ok (heap.borrowBlock block.base) := by
  have member := List.mem_of_find?_eq_some found
  have replacement := replaceBlock_borrow heap.blocks block (fun other belongs same => unique other belongs block member same)
  simp [Heap.protectRangeAsBorrowed, Nat.ne_of_gt positive, aligned, valid, found,
    show ¬block.alignment < alignment by omega, show ¬pointer + size > block.base + block.size by omega,
    replacement, Heap.borrowBlock]

end Lanius.Memory
