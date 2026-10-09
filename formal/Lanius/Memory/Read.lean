import Lanius.Memory.Store

namespace Lanius.Memory

/-- Readability of a byte range, independent of its current contents. -/
def Heap.Readable (heap : Heap) (address count : Nat) : Prop :=
  ∀ index, index < count → ∃ byte, heap.loadByte address index = .ok byte

private theorem loadBytesFrom_exists {heap : Heap} (count : Nat)
    (readable : ∀ index, index < count → ∃ byte, heap.loadByte address (offset + index) = .ok byte) :
    ∃ bytes, loadBytesFrom heap address offset count = .ok bytes := by
  induction count generalizing offset with
  | zero => exact ⟨[], rfl⟩
  | succ count ih =>
      obtain ⟨byte, head⟩ := readable 0 (by omega)
      obtain ⟨bytes, tail⟩ := ih (offset := offset + 1) (fun index bound => by
        simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using readable (index + 1) (by omega))
      exact ⟨byte :: bytes, by simp only [loadBytesFrom, Nat.add_zero] at head ⊢; rw [head, tail]⟩

theorem Heap.Readable.loadBytes {heap : Heap} (readable : heap.Readable address count) :
    ∃ bytes, heap.loadBytes address count = .ok bytes := by
  exact loadBytesFrom_exists count (by simpa only [Heap.Readable, Nat.zero_add] using readable)

theorem Heap.Readable.subrange {heap : Heap} (readable : heap.Readable address count)
    (bounds : start + length ≤ count) : heap.Readable (address + start) length := by
  intro index bound
  obtain ⟨byte, read⟩ := readable (start + index) (by omega)
  exact ⟨byte, Heap.loadByte_alias read (Nat.add_assoc _ _ _)⟩

theorem Heap.Readable.of_loadBytes {heap : Heap}
    (loaded : heap.loadBytes address count = .ok bytes) : heap.Readable address count := by
  intro index bound
  have length := (loadBytesFrom_spec loaded).1
  have inside : index < bytes.length := by omega
  exact ⟨bytes[index], Heap.loadBytes_get loaded (List.getElem?_eq_getElem inside)⟩

theorem Heap.Readable.belowNext (readable : heap.Readable address count)
    (positive : 0 < count) (below : HeapBlocksBelowNext heap) :
    address + count ≤ heap.nextAddress := by
  obtain ⟨byte, read⟩ := readable (count - 1) (Nat.sub_lt positive (by decide))
  obtain ⟨block, found, _⟩ := Heap.loadByte_ok_iff.mp read
  have contains := List.find?_some found
  have bound := below block (List.mem_of_find?_eq_some found)
  simp only [Bool.and_eq_true, decide_eq_true_eq] at contains
  dsimp only [Lanius.Address] at *
  omega

theorem loadBytesFrom_of_reads (bytes : List UInt8)
    (reads : ∀ index byte, bytes[index]? = some byte →
      heap.loadByte pointer (offset + index) = .ok byte) :
    loadBytesFrom heap pointer offset bytes.length = .ok bytes := by
  induction bytes generalizing offset with
  | nil => rfl
  | cons byte bytes ih =>
      have head := reads 0 byte (by rfl)
      have tail := ih (offset := offset + 1) (by
        intro index value found
        simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using
          reads (index + 1) value (by simpa using found))
      simp only [List.length_cons, loadBytesFrom, Nat.add_zero] at head ⊢
      rw [head, tail]

theorem Heap.loadBytes_congr {before after : Heap}
    (loaded : before.loadBytes pointer count = .ok bytes)
    (same : ∀ index, index < count → after.loadByte pointer index = before.loadByte pointer index) :
    after.loadBytes pointer count = .ok bytes := by
  obtain ⟨length, _⟩ := loadBytesFrom_spec loaded
  rw [← length]
  apply loadBytesFrom_of_reads
  intro index byte found
  rw [Nat.zero_add, same index (by
    have := (List.getElem?_eq_some_iff.mp found).1
    omega)]
  exact Heap.loadBytes_get loaded found

theorem ByteWrite.readable (effect : ByteWrite before after address byte)
    (input : before.Readable pointer count) : after.Readable pointer count := by
  intro index bound
  rw [effect.reads]
  split
  · exact ⟨byte, rfl⟩
  · exact input index bound

theorem ByteWrite.loadBytes_disjoint (effect : ByteWrite before after address byte)
    (loaded : before.loadBytes pointer count = .ok bytes)
    (outside : address < pointer ∨ pointer + count ≤ address) :
    after.loadBytes pointer count = .ok bytes := by
  apply Heap.loadBytes_congr loaded
  intro index bound
  have different : pointer + index ≠ address := by
    rcases outside with left | right
    · exact Nat.ne_of_gt (Nat.lt_of_lt_of_le left (Nat.le_add_right pointer index))
    · exact Nat.ne_of_lt (Nat.lt_of_lt_of_le (Nat.add_lt_add_left bound pointer) right)
  rw [effect.reads, if_neg different]

theorem BytesWrite.readable (effect : BytesWrite before after address bytes)
    (input : before.Readable pointer count) : after.Readable pointer count := by
  intro index bound
  rw [effect.reads]
  split
  · cases found : bytes[pointer + index - address]? with
    | some byte => exact ⟨byte, rfl⟩
    | none => exact input index bound
  · exact input index bound

theorem BytesWrite.loadBytes (effect : BytesWrite before after address bytes) :
    after.loadBytes address bytes.length = .ok bytes := by
  apply loadBytesFrom_of_reads
  intro index byte found
  rw [Nat.zero_add, effect.reads, if_pos (Nat.le_add_right _ _)]
  simp only [Nat.add_sub_cancel_left, found]

theorem BytesWrite.loadBytes_disjoint (effect : BytesWrite before after address bytes)
    (loaded : before.loadBytes pointer count = .ok values)
    (outside : address + bytes.length ≤ pointer ∨ pointer + count ≤ address) :
    after.loadBytes pointer count = .ok values := by
  apply Heap.loadBytes_congr loaded
  intro index bound
  rw [effect.reads]
  split
  · have past : bytes.length ≤ pointer + index - address := by
      dsimp only [Lanius.Address] at *
      rcases outside with left | right
      · omega
      · omega
    rw [List.getElem?_eq_none past]
  · rfl

end Lanius.Memory
