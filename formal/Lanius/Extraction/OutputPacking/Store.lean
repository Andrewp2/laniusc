import Lanius.Extraction.OutputPacking.Byte
import Lanius.Memory.Store

namespace Lanius.Extraction.OutputPacking

open Lanius.Memory Lanius.Semantics

/-- The writer stores a complete i32 word, but its observable heap effect is
    exactly one byte. Neighboring bytes, aliases, and allocation metadata are
    covered by the shared memory contract. -/
theorem storeByte (heap : Heap) (address : Nat)
    (word : BitVec 32) (lane : Fin 4) (byte : BitVec 8)
    (unique : HeapBlockBasesUnique heap)
    (contents : heap.loadBytes address 4 = .ok (i32Bytes word.toInt)) :
    ∃ after, heap.storeBytes address (i32Bytes (replaceByte word lane byte).toInt) = .ok after ∧
      ByteWrite heap after (address + lane.val) (UInt8.ofBitVec byte) := by
  obtain ⟨after, stored, frame⟩ := heap.storeBytes_of_readable
    (i32Bytes (replaceByte word lane byte).toInt) unique (by
      intro index bound
      have bound : index < 4 := by simpa [i32Bytes] using bound
      exact ⟨_, Heap.loadBytes_get contents (i32Bytes_at word ⟨index, bound⟩)⟩)
  refine ⟨after, stored, ⟨?_, frame.unique, frame.frontier, frame.budget, frame.layout⟩⟩
  intro pointer offset
  rw [frame.reads]
  by_cases lower : address ≤ pointer + offset
  · rw [if_pos lower]
    by_cases bound : pointer + offset - address < 4
    · let index : Fin 4 := ⟨pointer + offset - address, bound⟩
      have absolute : pointer + offset = address + index.val := by
        simpa [index, Nat.add_comm] using (Nat.sub_add_cancel lower).symm
      have same : index = lane ↔ pointer + offset = address + lane.val := by
        constructor
        · intro equal; simpa [equal] using absolute
        · intro equal
          apply Fin.ext
          exact Nat.add_left_cancel (absolute.symm.trans equal)
      change (match (i32Bytes (replaceByte word lane byte).toInt)[index.val]? with
          | some value => Except.ok value | none => heap.loadByte pointer offset) = _
      rw [i32Bytes_replaceByte]
      by_cases selected : index = lane
      · simp [selected, same.mp selected]
      · have different := mt same.mpr selected
        have oldRead := Heap.loadBytes_get contents (i32Bytes_at word index)
        simp [selected, different, i32Bytes_at,
          Heap.loadByte_alias oldRead absolute]
    · have missing : (i32Bytes (replaceByte word lane byte).toInt)[pointer + offset - address]? = none := by
        apply List.getElem?_eq_none_iff.mpr
        simpa [i32Bytes] using Nat.le_of_not_gt bound
      have different : pointer + offset ≠ address + lane.val := by
        intro equal
        apply bound
        simpa only [equal, Nat.add_sub_cancel_left] using lane.isLt
      simp [missing, different]
  · have different : pointer + offset ≠ address + lane.val := by
      intro equal
      apply lower
      rw [equal]
      exact Nat.le_add_right _ _
    simp [lower, different]

end Lanius.Extraction.OutputPacking
