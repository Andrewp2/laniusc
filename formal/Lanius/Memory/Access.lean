import Lanius.Properties

namespace Lanius.Memory

variable {heap : Heap} {block : Block} {pointer offset count address : Nat}

theorem Heap.storeByte_remaining {after : Heap} {byte : UInt8}
    (stored : heap.storeByte pointer offset byte = .ok after) :
    after.remaining = heap.remaining := by
  cases found : heap.containingBlock? (pointer + offset) with
  | some block =>
      simp only [Heap.storeByte, found, Except.ok.injEq] at stored
      cases stored
      rfl
  | none =>
      cases base : heap.containingBlock? pointer <;>
        cases exactBlock : heap.block? pointer <;>
        simp [Heap.storeByte, found, base, exactBlock] at stored
      split at stored <;> contradiction

theorem storeBytesFrom_remaining {after : Heap} {bytes : List UInt8}
    (stored : storeBytesFrom heap pointer offset bytes = .ok after) :
    after.remaining = heap.remaining := by
  induction bytes generalizing heap offset with
  | nil => cases stored; rfl
  | cons byte rest ih =>
      cases first : heap.storeByte pointer offset byte with
      | error reason => simp [storeBytesFrom, first] at stored
      | ok next =>
          have tail : storeBytesFrom next pointer (offset + 1) rest = .ok after := by
            simpa only [storeBytesFrom, first] using stored
          exact (ih tail).trans (heap.storeByte_remaining first)

theorem Heap.containingBlock_exists
    (member : block ∈ heap.blocks) (live : block.live = true)
    (lower : block.base ≤ address) (upper : address < block.base + block.size) :
    ∃ found, heap.containingBlock? address = some found := by
  cases found : heap.containingBlock? address with
  | some block => exact ⟨block, rfl⟩
  | none =>
      have absent := List.find?_eq_none.mp found block member
      simp [live, lower, upper] at absent

theorem Heap.loadByte_exists (wellFormed : HeapWellFormed heap)
    (member : block ∈ heap.blocks) (live : block.live = true)
    (lower : block.base ≤ pointer + offset) (upper : pointer + offset < block.base + block.size) :
    ∃ byte, heap.loadByte pointer offset = .ok byte := by
  obtain ⟨found, lookup⟩ := heap.containingBlock_exists (address := pointer + offset) member live lower upper
  have bounds := List.find?_some lookup
  change (found.live && found.base ≤ pointer + offset && pointer + offset < found.base + found.size) = true at bounds
  simp only [Bool.and_eq_true, decide_eq_true_eq] at bounds
  have valid := wellFormed.blocksWellFormed found (List.mem_of_find?_eq_some lookup)
  have within : pointer + offset - found.base < found.bytes.length := by
    have size := valid.2.2.1
    have lowerFound := bounds.1.2
    have upperFound := bounds.2
    rw [size]
    exact (Nat.sub_lt_iff_lt_add' lowerFound).mpr upperFound
  refine ⟨found.bytes[pointer + offset - found.base], ?_⟩
  simp only [Heap.loadByte, lookup, List.getElem?_eq_getElem within]

theorem loadBytesFrom_exists (wellFormed : HeapWellFormed heap)
    (member : block ∈ heap.blocks) (live : block.live = true)
    (lower : block.base ≤ pointer + offset)
    (upper : pointer + offset + count ≤ block.base + block.size) :
    ∃ bytes, loadBytesFrom heap pointer offset count = .ok bytes := by
  induction count generalizing offset with
  | zero => exact ⟨[], rfl⟩
  | succ count ih =>
      obtain ⟨byte, first⟩ := heap.loadByte_exists (pointer := pointer) (offset := offset) wellFormed member live lower (by omega)
      obtain ⟨bytes, rest⟩ := ih (offset := offset + 1)
        (Nat.le_trans lower (by omega)) (by simpa only [Nat.add_assoc, Nat.add_comm 1 count] using upper)
      exact ⟨byte :: bytes, by simp only [loadBytesFrom, first, rest]⟩

theorem Heap.loadBytes_exists (wellFormed : HeapWellFormed heap)
    (member : block ∈ heap.blocks) (live : block.live = true)
    (lower : block.base ≤ pointer) (upper : pointer + count ≤ block.base + block.size) :
    ∃ bytes, heap.loadBytes pointer count = .ok bytes :=
  loadBytesFrom_exists wellFormed member live (by simpa using lower) (by simpa using upper)

theorem Heap.storeByte_exists (byte : UInt8)
    (member : block ∈ heap.blocks) (live : block.live = true)
    (lower : block.base ≤ pointer + offset) (upper : pointer + offset < block.base + block.size) :
    ∃ after, heap.storeByte pointer offset byte = .ok after := by
  obtain ⟨found, lookup⟩ := heap.containingBlock_exists (address := pointer + offset) member live lower upper
  simp only [Heap.storeByte, lookup]
  exact ⟨_, rfl⟩

theorem loadBytesFrom_length {bytes : List UInt8}
    (loaded : loadBytesFrom heap pointer offset count = .ok bytes) :
    bytes.length = count := by
  induction count generalizing offset bytes with
  | zero => cases loaded; rfl
  | succ count ih =>
      cases first : heap.loadByte pointer offset with
      | error reason => simp [loadBytesFrom, first] at loaded
      | ok byte =>
          cases rest : loadBytesFrom heap pointer (offset + 1) count with
          | error reason => simp [loadBytesFrom, first, rest] at loaded
          | ok tail =>
              simp only [loadBytesFrom, first, rest, Except.ok.injEq] at loaded
              subst bytes
              simp only [List.length_cons, ih rest]

theorem Heap.loadBytes_length {bytes : List UInt8}
    (loaded : heap.loadBytes pointer count = .ok bytes) : bytes.length = count :=
  loadBytesFrom_length loaded

open Lanius.Semantics Lanius.Properties

theorem storeBytesFrom_view_exists {view : I32ArrayView} {bytes : List UInt8}
    (wellFormed : HeapWellFormed heap)
    (valid : I32ArrayViewBlockWellFormed heap view)
    (bounded : offset + bytes.length ≤ view.length * 4) :
    ∃ after, storeBytesFrom heap view.address offset bytes = .ok after := by
  induction bytes generalizing heap offset with
  | nil => exact ⟨heap, rfl⟩
  | cons byte rest ih =>
      obtain ⟨block, lookup, live, owned, size, alignment⟩ := valid
      have base : block.base = view.address := by
        have found := List.find?_some lookup
        simpa only [beq_iff_eq] using found
      obtain ⟨next, stored⟩ := heap.storeByte_exists (pointer := view.address) (offset := offset) byte
        (List.mem_of_find?_eq_some lookup) live
        (by rw [base]; exact Nat.le_add_right _ _)
        (by rw [base, size]; simp only [List.length_cons] at bounded; omega)
      have nextWellFormed := storeByte_preserves_heap_well_formed wellFormed stored
      have nextValid := storeByte_preserves_i32_array_view_blocks (views := [view]) wellFormed stored
        view (by simp) ⟨block, lookup, live, owned, size, alignment⟩
      obtain ⟨after, completed⟩ := ih (offset := offset + 1) nextWellFormed nextValid (by
        simp only [List.length_cons] at bounded
        omega)
      exact ⟨after, by simp only [storeBytesFrom, stored, completed]⟩

theorem Heap.storeBytes_view_exists {view : I32ArrayView} {bytes : List UInt8}
    (wellFormed : HeapWellFormed heap)
    (valid : I32ArrayViewBlockWellFormed heap view)
    (bounded : bytes.length ≤ view.length * 4) :
    ∃ after, heap.storeBytes view.address bytes = .ok after :=
  storeBytesFrom_view_exists wellFormed valid (by simpa using bounded)

theorem Heap.allocated_block {size alignment address : Nat} {after : Heap}
    (wellFormed : HeapWellFormed heap)
    (allocated : heap.allocate size alignment = .allocated address after) :
    after.block? address = some {
      base := address, size, alignment, bytes := List.replicate size 0 } := by
  unfold Heap.allocate at allocated
  split at allocated
  · contradiction
  · rename_i alignmentValid
    cases budget : consumeBudget heap.remaining size with
    | none => simp [budget] at allocated
    | some remaining =>
        rw [budget] at allocated
        cases allocated
        have valid : validAlignment alignment = true := by simpa using alignmentValid
        have frontier := Nat.le_trans (Nat.le_max_left heap.nextAddress 1)
          (alignUp_ge (max heap.nextAddress 1) alignment
            (valid_alignment_is_nonzero alignment valid))
        have found := block?_append_fresh (block := {
          base := alignUp (max heap.nextAddress 1) alignment,
          size, alignment, bytes := List.replicate size 0 }) wellFormed frontier
        simpa only [Heap.block?] using found

theorem Heap.allocate_exists {size alignment : Nat}
    (valid : validAlignment alignment = true)
    (room : ∀ available, heap.remaining = some available → size ≤ available) :
    ∃ address after, heap.allocate size alignment = .allocated address after := by
  cases budget : heap.remaining with
  | none =>
      simp only [Heap.allocate, valid, Bool.not_true, Bool.false_eq_true, ↓reduceIte,
        consumeBudget, budget]
      exact ⟨_, _, rfl⟩
  | some available =>
      have enough := room available budget
      simp only [Heap.allocate, valid, Bool.not_true, Bool.false_eq_true, ↓reduceIte,
        consumeBudget, budget]
      simp [enough]

theorem Heap.allocate_remaining {size alignment address : Nat} {after : Heap}
    (allocated : heap.allocate size alignment = .allocated address after) :
    after.remaining = heap.remaining.map (fun available => available - size) := by
  unfold Heap.allocate at allocated
  split at allocated
  · contradiction
  · cases budget : heap.remaining with
    | none =>
        simp only [consumeBudget, budget] at allocated
        cases allocated
        rfl
    | some available =>
        by_cases enough : size ≤ available
        · simp only [consumeBudget, budget, if_pos enough] at allocated
          cases allocated
          rfl
        · simp [consumeBudget, budget, enough] at allocated

theorem Heap.allocate_leaves_room {size rest alignment address : Nat} {after : Heap}
    (room : ∀ available, heap.remaining = some available → size + rest ≤ available)
    (allocated : heap.allocate size alignment = .allocated address after) :
    ∀ available, after.remaining = some available → rest ≤ available := by
  intro available remaining
  rw [heap.allocate_remaining allocated] at remaining
  cases budget : heap.remaining with
  | none => simp [budget] at remaining
  | some initial =>
      have enough := room initial budget
      simp only [budget, Option.map_some, Option.some.injEq] at remaining
      omega

end Lanius.Memory
