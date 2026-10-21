import Lanius.Memory.Borrow

namespace Lanius.Memory

private theorem setByte_same (read : bytes[index]? = some byte) : setByte bytes index byte = bytes := by
  induction bytes generalizing index with
  | nil => simp at read
  | cons head tail ih => cases index <;> simp_all [setByte]

/-- Writing the byte already present leaves the actual heap unchanged. -/
theorem Heap.storeByte_same (unique : HeapBlockBasesUnique heap)
    (read : heap.loadByte pointer offset = .ok byte) : heap.storeByte pointer offset byte = .ok heap := by
  obtain ⟨block, found, contents⟩ := Heap.loadByte_ok_iff.mp read
  have replaced := replaceBlock_self heap.blocks block (fun other member same =>
    unique other member block (List.mem_of_find?_eq_some found) same)
  simp only [Heap.storeByte, found, setByte_same contents, replaced]

private theorem storeBytesFrom_same (unique : HeapBlockBasesUnique heap)
    (reads : ∀ index byte, bytes[index]? = some byte → heap.loadByte pointer (offset + index) = .ok byte) :
    storeBytesFrom heap pointer offset bytes = .ok heap := by
  induction bytes generalizing offset with
  | nil => rfl
  | cons byte bytes ih =>
      have head := reads 0 byte (by rfl)
      rw [Nat.add_zero] at head
      rw [storeBytesFrom, Heap.storeByte_same unique head]
      apply ih
      intro index value found
      simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using reads (index + 1) value (by simpa using found)

theorem Heap.storeBytes_same (unique : HeapBlockBasesUnique heap)
    (read : heap.loadBytes pointer bytes.length = .ok bytes) : heap.storeBytes pointer bytes = .ok heap :=
  storeBytesFrom_same unique (fun _ _ found => by simpa using Heap.loadBytes_get read found)

end Lanius.Memory
