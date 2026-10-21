import Lanius.Memory
import Lean.Elab.Tactic.Omega

namespace Lanius.Memory

private def changeBytes (base : Address) (change : List UInt8 → List UInt8)
    (block : Block) : Block :=
  if block.base == base then { block with bytes := change block.bytes } else block

/-- A specification of a byte-only change; allocation identity, size,
    alignment, liveness, and ownership remain intact. -/
def Heap.changeBytes (heap : Heap) (base : Address)
    (change : List UInt8 → List UInt8) : Heap :=
  { heap with blocks := heap.blocks.map (Memory.changeBytes base change) }

private theorem changeBytes_base (base : Address) (change : List UInt8 → List UInt8)
    (block : Block) : (changeBytes base change block).base = block.base := by
  unfold changeBytes; split <;> rfl

private theorem changeBytes_live (base : Address) (change : List UInt8 → List UInt8)
    (block : Block) : (changeBytes base change block).live = block.live := by
  unfold changeBytes; split <;> rfl

private theorem find_changeBytes (heap : Heap) (base : Address)
    (change : List UInt8 → List UInt8) (predicate : Block → Bool)
    (stable : ∀ block, predicate (changeBytes base change block) = predicate block) :
    (heap.changeBytes base change).blocks.find? predicate =
      (heap.blocks.find? predicate).map (changeBytes base change) := by
  simp only [Heap.changeBytes, List.find?_map]
  have same : predicate ∘ changeBytes base change = predicate := funext stable
  rw [same]

theorem Heap.containingBlock?_changeBytes (heap : Heap) (base address : Address)
    (change : List UInt8 → List UInt8) :
    (heap.changeBytes base change).containingBlock? address =
      (heap.containingBlock? address).map (Memory.changeBytes base change) := by
  apply find_changeBytes
  intro block
  unfold Memory.changeBytes
  split <;> rfl

theorem Heap.block?_changeBytes (heap : Heap) (base address : Address)
    (change : List UInt8 → List UInt8) :
    (heap.changeBytes base change).block? address =
      (heap.block? address).map (Memory.changeBytes base change) := by
  apply find_changeBytes
  intro block
  rw [changeBytes_base]

theorem HeapBlockBasesUnique.changeBytes
    (unique : HeapBlockBasesUnique heap) : HeapBlockBasesUnique (heap.changeBytes base change) := by
  intro left leftMem right rightMem same
  change left ∈ heap.blocks.map (Memory.changeBytes base change) at leftMem
  change right ∈ heap.blocks.map (Memory.changeBytes base change) at rightMem
  obtain ⟨oldLeft, oldLeftMem, rfl⟩ := List.mem_map.mp leftMem
  obtain ⟨oldRight, oldRightMem, rfl⟩ := List.mem_map.mp rightMem
  have equal := unique oldLeft oldLeftMem oldRight oldRightMem (by
    simpa only [changeBytes_base] using same)
  rw [equal]

private theorem replaceBlock_eq_map (blocks : List Block) (replacement : Block) :
    replaceBlock blocks replacement =
      blocks.map (fun block => if block.base == replacement.base then replacement else block) := by
  induction blocks with
  | nil => rfl
  | cons block rest ih => simp only [replaceBlock, List.map_cons, ih]

private theorem setByte_eq_set (bytes : List UInt8) (index : Nat) (value : UInt8) :
    setByte bytes index value = bytes.set index value := by
  induction bytes generalizing index with
  | nil => rfl
  | cons byte rest ih => cases index <;> simp [setByte, List.set, ih]

theorem Heap.loadByte_ok_iff {heap : Heap} : heap.loadByte pointer offset = .ok value ↔
    ∃ block, heap.containingBlock? (pointer + offset) = some block ∧
      block.bytes[pointer + offset - block.base]? = some value := by
  cases found : heap.containingBlock? (pointer + offset) with
  | none =>
    simp only [Heap.loadByte, found]
    split <;> (try split) <;> simp
  | some block =>
    simp only [Heap.loadByte, found]
    cases read : block.bytes[pointer + offset - block.base]? <;> simp [read]

theorem Heap.loadByte_alias {heap : Heap} (read : heap.loadByte pointer offset = .ok value)
    (same : otherPointer + otherOffset = pointer + offset) :
    heap.loadByte otherPointer otherOffset = .ok value := by
  rw [Heap.loadByte_ok_iff] at read ⊢
  simpa only [same] using read

theorem loadBytesFrom_spec
    (loaded : loadBytesFrom heap pointer offset count = .ok bytes) :
    bytes.length = count ∧ ∀ index value, bytes[index]? = some value →
      heap.loadByte pointer (offset + index) = .ok value := by
  induction count generalizing offset bytes with
  | zero =>
    simp only [loadBytesFrom, Except.ok.injEq] at loaded
    subst bytes
    exact ⟨rfl, by simp⟩
  | succ count ih =>
    cases head : heap.loadByte pointer offset with
    | error reason => simp [loadBytesFrom, head] at loaded
    | ok byte =>
      cases tail : loadBytesFrom heap pointer (offset + 1) count with
      | error reason => simp [loadBytesFrom, head, tail] at loaded
      | ok rest =>
        simp only [loadBytesFrom, head, tail, Except.ok.injEq] at loaded
        subst bytes
        obtain ⟨length, get⟩ := ih tail
        refine ⟨by simp [length], ?_⟩
        intro index value found
        cases index with
        | zero => simpa using (by simpa using found : byte = value) ▸ head
        | succ index =>
          simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using
            get index value (by simpa using found)

theorem Heap.loadBytes_get {heap : Heap} (loaded : heap.loadBytes pointer count = .ok bytes)
    (found : bytes[index]? = some value) : heap.loadByte pointer index = .ok value := by
  simpa using (loadBytesFrom_spec loaded).2 index value found

/-- A valid byte write, including its frame over all other readable or invalid
    addresses. This does not assume a successful store. -/
structure ByteWrite (before after : Heap) (address : Address) (value : UInt8) : Prop where
  reads : ∀ pointer offset, after.loadByte pointer offset =
    if pointer + offset = address then .ok value else before.loadByte pointer offset
  unique : HeapBlockBasesUnique after
  frontier : after.nextAddress = before.nextAddress
  budget : after.remaining = before.remaining
  layout : after.blocks.map (fun block => { block with bytes := [] }) =
    before.blocks.map (fun block => { block with bytes := [] })

private theorem changeBytes_layout (heap : Heap) (base : Address)
    (change : List UInt8 → List UInt8) :
    (heap.changeBytes base change).blocks.map (fun block => { block with bytes := [] }) =
      heap.blocks.map (fun block => { block with bytes := [] }) := by
  simp only [Heap.changeBytes, List.map_map]
  apply List.map_congr_left
  intro block _
  dsimp only [Function.comp_def]
  unfold changeBytes
  split <;> rfl

private theorem loadByte_changed
    (unique : HeapBlockBasesUnique heap)
    (found : heap.containingBlock? address = some block)
    (read : block.bytes[address - block.base]? = some old)
    (value : UInt8) (pointer offset : Nat) :
    (heap.changeBytes block.base (fun bytes => setByte bytes (address - block.base) value)).loadByte
      pointer offset =
        if pointer + offset = address then .ok value else heap.loadByte pointer offset := by
  have member := List.mem_of_find?_eq_some found
  have lower : block.base ≤ address := by
    have contains := List.find?_some found
    simp only [Bool.and_eq_true, decide_eq_true_eq] at contains
    exact contains.1.2
  cases queried : heap.containingBlock? (pointer + offset) with
  | none =>
    have different : pointer + offset ≠ address := by
      intro same
      rw [same, found] at queried
      cases queried
    simp only [different, ↓reduceIte, Heap.loadByte, Heap.containingBlock?_changeBytes,
      Heap.block?_changeBytes, queried, Option.map_none]
    cases hp : heap.containingBlock? pointer <;> cases hb : heap.block? pointer <;>
      simp only [Option.map_none, Option.map_some, changeBytes_live]
  | some selected =>
    have selectedMember := List.mem_of_find?_eq_some queried
    by_cases sameBase : selected.base = block.base
    · have sameBlock := unique selected selectedMember block member sameBase
      subst selected
      have selectedLower : block.base ≤ pointer + offset := by
        have contains := List.find?_some queried
        simp only [Bool.and_eq_true, decide_eq_true_eq] at contains
        exact contains.1.2
      by_cases same : pointer + offset = address
      · have bound := (List.getElem?_eq_some_iff.mp read).1
        simp [Heap.loadByte, Heap.containingBlock?_changeBytes, found, Memory.changeBytes,
          same, setByte_eq_set, List.getElem?_set_self bound]
      · have different : address - block.base ≠ pointer + offset - block.base := by
          intro equal
          apply same
          calc
            pointer + offset = (pointer + offset - block.base) + block.base := (Nat.sub_add_cancel selectedLower).symm
            _ = (address - block.base) + block.base := congrArg (· + block.base) equal.symm
            _ = address := Nat.sub_add_cancel lower
        simp [Heap.loadByte, Heap.containingBlock?_changeBytes, queried, Memory.changeBytes,
          same, setByte_eq_set, List.getElem?_set_ne different]
    · have different : pointer + offset ≠ address := by
        intro same
        rw [same, found] at queried
        cases queried
        exact sameBase rfl
      simp [Heap.loadByte, Heap.containingBlock?_changeBytes, queried, Memory.changeBytes, sameBase, different]

theorem Heap.storeByte_of_read
    (unique : HeapBlockBasesUnique heap)
    (read : heap.loadByte pointer offset = .ok old) (value : UInt8) :
    ∃ after, heap.storeByte pointer offset value = .ok after ∧
      ByteWrite heap after (pointer + offset) value := by
  obtain ⟨block, found, contents⟩ := Heap.loadByte_ok_iff.mp read
  let after := heap.changeBytes block.base
    (fun bytes => setByte bytes (pointer + offset - block.base) value)
  refine ⟨after, ?_, ⟨loadByte_changed unique found contents value,
    unique.changeBytes, rfl, rfl, changeBytes_layout _ _ _⟩⟩
  simp only [Heap.storeByte, found, after, Heap.changeBytes, replaceBlock_eq_map]
  congr 2
  apply List.map_congr_left
  intro candidate member
  have blockMember := List.mem_of_find?_eq_some found
  by_cases same : candidate.base = block.base
  · have equal := unique candidate member block blockMember same
    subst candidate
    simp [Memory.changeBytes]
  · simp [Memory.changeBytes, same]

/-- Exact effects of writing a byte sequence, including reads through aliases
    and unchanged allocation metadata. -/
structure BytesWrite (before after : Heap) (address : Address) (bytes : List UInt8) : Prop where
  reads : ∀ pointer offset, after.loadByte pointer offset =
    if address ≤ pointer + offset then
      match bytes[pointer + offset - address]? with
      | some value => .ok value
      | none => before.loadByte pointer offset
    else before.loadByte pointer offset
  unique : HeapBlockBasesUnique after
  frontier : after.nextAddress = before.nextAddress
  budget : after.remaining = before.remaining
  layout : after.blocks.map (fun block => { block with bytes := [] }) =
    before.blocks.map (fun block => { block with bytes := [] })

theorem BytesWrite.refl (unique : HeapBlockBasesUnique heap) :
    BytesWrite heap heap address [] :=
  ⟨by intros; simp, unique, rfl, rfl, rfl⟩

theorem BytesWrite.below (written : BytesWrite before after address bytes)
    (below : HeapBlocksBelowNext before) : HeapBlocksBelowNext after := by
  intro block member
  have masked : { block with bytes := [] } ∈ after.blocks.map (fun item => { item with bytes := [] }) :=
    List.mem_map.mpr ⟨block, member, rfl⟩
  rw [written.layout] at masked
  obtain ⟨old, oldMember, same⟩ := List.mem_map.mp masked
  have shape := congrArg (fun item : Block => item.base + max item.size 1) same
  simpa only [written.frontier, shape] using below old oldMember

/-- Consecutive native or byte chunks extend one exact prefix, including
    unchanged reads through aliases and invalid pointers outside that prefix. -/
theorem BytesWrite.append {address : Nat} (written : BytesWrite before middle address bytes)
    (last : BytesWrite middle after (address + bytes.length) suffix) :
    BytesWrite before after address (bytes ++ suffix) := by
  refine ⟨?_, last.unique, last.frontier.trans written.frontier,
    last.budget.trans written.budget, last.layout.trans written.layout⟩
  intro pointer offset
  dsimp only [Lanius.Address] at *
  rw [last.reads, written.reads]
  by_cases start : address ≤ pointer + offset
  · simp only [if_pos start]
    by_cases inside : pointer + offset - address < bytes.length
    · have next : ¬ (address + bytes.length ≤ pointer + offset) := by omega
      simp only [if_neg next,
        List.getElem?_append_left inside]
    · have next : address + bytes.length ≤ pointer + offset := by omega
      simp only [if_pos next,
        List.getElem?_append_right (Nat.le_of_not_gt inside),
        List.getElem?_eq_none (l := bytes) (Nat.le_of_not_gt inside), Nat.sub_add_eq]
  · have next : ¬ address + bytes.length ≤ pointer + offset := by omega
    simp only [if_neg start, if_neg next]

/-- A single-byte effect is the exact singleton chunk effect. -/
theorem ByteWrite.asBytes {address : Nat} (write : ByteWrite before after address byte) :
    BytesWrite before after address [byte] := by
  refine ⟨?_, write.unique, write.frontier, write.budget, write.layout⟩
  intro pointer offset
  rw [write.reads]
  by_cases same : pointer + offset = address
  · simp [same]
  · by_cases start : address ≤ pointer + offset
    · have past : 1 ≤ pointer + offset - address := by omega
      simp only [if_neg same, if_pos start,
        List.getElem?_eq_none (l := [byte]) (by simpa only [List.length_singleton] using past)]
    · simp [same, start]

theorem BytesWrite.snoc (written : BytesWrite before middle address bytes)
    (last : ByteWrite middle after (address + bytes.length) byte) :
    BytesWrite before after address (bytes ++ [byte]) := written.append last.asBytes

/-- Prepend the last write to an already written suffix. The chronology is
    right-to-left, unlike a forward store of a byte followed by its tail. -/
theorem BytesWrite.cons
    (written : BytesWrite before middle (address + 1) bytes)
    (last : ByteWrite middle after address byte) :
    BytesWrite before after address (byte :: bytes) := by
  refine ⟨?_, last.unique, last.frontier.trans written.frontier,
    last.budget.trans written.budget, last.layout.trans written.layout⟩
  intro pointer offset
  dsimp only [Lanius.Address] at *
  rw [last.reads]
  by_cases same : pointer + offset = address
  · simp [same]
  · rw [if_neg same, written.reads]
    by_cases start : address ≤ pointer + offset
    · have next : address + 1 ≤ pointer + offset := Nat.lt_of_le_of_ne start (Ne.symm same)
      have positive : 1 ≤ pointer + offset - address :=
        Nat.le_sub_of_add_le (by simpa only [Nat.add_comm] using next)
      have successor : pointer + offset - address = pointer + offset - (address + 1) + 1 := by
        simpa only [Nat.sub_add_eq] using (Nat.sub_add_cancel positive).symm
      simp only [start, next, ↓reduceIte, successor, List.getElem?_cons_succ]
    · have notNext : ¬ address + 1 ≤ pointer + offset :=
        fun next => start (Nat.le_trans (Nat.le_add_right address 1) next)
      simp [start, notNext]

private theorem ByteWrite.prepend
    (first : ByteWrite before middle address byte)
    (rest : BytesWrite middle after (address + 1) bytes) :
    BytesWrite before after address (byte :: bytes) := by
  refine ⟨?_, rest.unique, rest.frontier.trans first.frontier,
    rest.budget.trans first.budget, rest.layout.trans first.layout⟩
  intro pointer offset
  rw [rest.reads]
  by_cases beforeStart : pointer + offset < address
  · have notStart : ¬ address ≤ pointer + offset := Nat.not_le_of_lt beforeStart
    have notNext : ¬ address + 1 ≤ pointer + offset := Nat.not_le_of_lt (Nat.lt_succ_of_lt beforeStart)
    have different : pointer + offset ≠ address := Nat.ne_of_lt beforeStart
    simp [notStart, notNext, first.reads, different]
  · by_cases same : pointer + offset = address
    · simp [same, first.reads, Nat.not_succ_le_self]
    · have start : address ≤ pointer + offset := Nat.le_of_not_gt beforeStart
      have next : address + 1 ≤ pointer + offset := Nat.lt_of_le_of_ne start (Ne.symm same)
      have successor : pointer + offset - address = (pointer + offset - (address + 1)) + 1 := by omega
      simp only [start, next, ↓reduceIte, successor, List.getElem?_cons_succ]
      cases bytes[pointer + offset - (address + 1)]? <;> simp [first.reads, same]

theorem storeBytesFrom_of_readable (bytes : List UInt8)
    (unique : HeapBlockBasesUnique heap)
    (readable : ∀ index, index < bytes.length →
      ∃ value, heap.loadByte pointer (offset + index) = .ok value) :
    ∃ after, storeBytesFrom heap pointer offset bytes = .ok after ∧
      BytesWrite heap after (pointer + offset) bytes := by
  induction bytes generalizing heap offset with
  | nil =>
    refine ⟨heap, rfl, ⟨?_, unique, rfl, rfl, rfl⟩⟩
    intro query index
    simp
  | cons byte bytes ih =>
    obtain ⟨old, read⟩ := readable 0 (by simp)
    obtain ⟨middle, stored, first⟩ := heap.storeByte_of_read unique (by simpa using read) byte
    have remaining : ∀ index, index < bytes.length →
        ∃ value, middle.loadByte pointer (offset + 1 + index) = .ok value := by
      intro index bound
      obtain ⟨value, original⟩ := readable (index + 1) (by simpa using bound)
      refine ⟨value, ?_⟩
      rw [first.reads, if_neg (by omega)]
      simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using original
    obtain ⟨after, storedRest, rest⟩ := ih first.unique remaining
    refine ⟨after, ?_, ?_⟩
    · simp only [storeBytesFrom, stored, storedRest]
    · exact first.prepend (by simpa [Nat.add_assoc] using rest)

/-- Validity is expressed by readable input storage, not successful output. -/
theorem Heap.storeBytes_of_readable (bytes : List UInt8)
    (unique : HeapBlockBasesUnique heap)
    (readable : ∀ index, index < bytes.length → ∃ value, heap.loadByte pointer index = .ok value) :
    ∃ after, heap.storeBytes pointer bytes = .ok after ∧ BytesWrite heap after pointer bytes := by
  exact storeBytesFrom_of_readable bytes unique (by simpa using readable)

#print axioms BytesWrite.append
#print axioms ByteWrite.asBytes
#print axioms BytesWrite.snoc

end Lanius.Memory
