import Lanius.Memory.Footprint

namespace Lanius.Memory

/-- A written prefix and unchanged tail within a buffer. Other buffers may
    change; unlike `BytesWrite`, this is not a whole-heap frame. -/
def BufferPrefix (before after : Heap) (address limit : Nat) (bytes : List UInt8) : Prop :=
  ∀ index, index < limit → match bytes[index]? with
    | some byte => after.loadByte address index = .ok byte
    | none => after.loadByte address index = before.loadByte address index

theorem BufferPrefix.refl : BufferPrefix heap heap address limit [] := fun _ _ => rfl

theorem BufferPrefix.frame (stored : BufferPrefix before middle address limit bytes)
    (write : HeapWritesOn middle after allowed)
    (apart : ∀ index, index < limit → ¬allowed (address + index)) :
    BufferPrefix before after address limit bytes := by
  intro index bound
  cases found : bytes[index]? <;> simp only [found]
  all_goals rw [write.outside _ _ (apart index bound)]; simpa only [found] using stored index bound

theorem BufferPrefix.append (stored : BufferPrefix before middle address limit bytes)
    (write : BytesWrite middle after (address + bytes.length) more) :
    BufferPrefix before after address limit (bytes ++ more) := by
  intro index bound
  rw [List.getElem?_append]
  by_cases early : index < bytes.length
  · rw [if_pos early]
    cases found : bytes[index]? <;> simp only [found]
    all_goals rw [write.reads, if_neg (by dsimp only [Lanius.Address]; omega)]; simpa only [found] using stored index bound
  · rw [if_neg early]
    have old : bytes[index]? = none := List.getElem?_eq_none (by omega)
    have offset : address + index - (address + bytes.length) = index - bytes.length := by omega
    cases found : more[index - bytes.length]? <;> simp only [found]
    · rw [write.reads, if_pos (by dsimp only [Lanius.Address]; omega), offset, found]
      simpa only [old] using stored index bound
    · rw [write.reads, if_pos (by dsimp only [Lanius.Address]; omega), offset, found]

theorem BufferPrefix.loaded (stored : BufferPrefix before after address limit bytes)
    (within : bytes.length ≤ limit) : after.loadBytes address bytes.length = .ok bytes := by
  apply loadBytesFrom_of_reads
  intro index value found
  have bound := (List.getElem?_eq_some_iff.mp found).1
  simpa only [Nat.zero_add, found] using stored index (by omega)

theorem BufferPrefix.tail (stored : BufferPrefix before after address limit bytes)
    (past : bytes.length ≤ index) (bound : index < limit) :
    after.loadByte address index = before.loadByte address index := by
  simpa only [List.getElem?_eq_none past] using stored index bound

#print axioms BufferPrefix.append

end Lanius.Memory
