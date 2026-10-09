import Lanius.Memory.Read

namespace Lanius.Memory

/-- Read an encoded subrange using one already proved block-selection fact.
    Neither the heap nor unrelated bytes need to be reduced for each field.
    The selection fact covers the whole interval: a single successful lookup
    at its first address alone would not exclude overlapping earlier blocks. -/
theorem Heap.loadBytes_of_block_slice {heap : Heap} {block : Block}
    {start : Nat} {bytes : List UInt8}
    (selected : ∀ address, block.base ≤ address → address < block.base + block.size →
      heap.containingBlock? address = some block)
    (bounds : start + bytes.length ≤ block.size)
    (slice : (block.bytes.drop start).take bytes.length = bytes) :
    heap.loadBytes (block.base + start) bytes.length = .ok bytes := by
  apply loadBytesFrom_of_reads
  intro index byte found
  have inside := (List.getElem?_eq_some_iff.mp found).1
  have contents : block.bytes[start + index]? = some byte := by
    rw [← slice] at found
    rw [List.getElem?_take_of_lt inside, List.getElem?_drop] at found
    exact found
  dsimp only [Lanius.Address] at *
  apply Heap.loadByte_ok_iff.mpr
  refine ⟨block, selected _ (by omega) (by omega), ?_⟩
  simpa only [Nat.zero_add, Nat.add_assoc, Nat.add_sub_cancel_left] using contents

#print axioms Heap.loadBytes_of_block_slice

/-- Select one contiguous encoded segment without repeatedly normalizing
    slices of its opaque prefix and suffix. Byte identity and prefix geometry
    are checked separately from the already proved block selection. -/
theorem Heap.loadBytes_of_block_segment {heap : Heap} {block : Block}
    {start : Nat} {front bytes back : List UInt8}
    (selected : ∀ address, block.base ≤ address → address < block.base + block.size →
      heap.containingBlock? address = some block)
    (bounds : start + bytes.length ≤ block.size)
    (position : start = front.length)
    (contents : block.bytes = front ++ bytes ++ back) :
    heap.loadBytes (block.base + start) bytes.length = .ok bytes := by
  apply Heap.loadBytes_of_block_slice selected bounds
  rw [position, contents, List.append_assoc, List.drop_append_length,
    List.take_append_length]

#print axioms Heap.loadBytes_of_block_segment

/-- Reuse a checked parent read to read a slice, without selecting blocks or
    evaluating any encoding again. Slice identity also covers empty slices. -/
theorem Heap.loadBytes_of_read_slice {heap : Heap} {pointer count start : Nat}
    {all bytes : List UInt8}
    (loaded : heap.loadBytes pointer count = .ok all)
    (slice : (all.drop start).take bytes.length = bytes) :
    heap.loadBytes (pointer + start) bytes.length = .ok bytes := by
  apply loadBytesFrom_of_reads
  intro index byte found
  have inside := (List.getElem?_eq_some_iff.mp found).1
  have contents : all[start + index]? = some byte := by
    rw [← slice] at found
    rw [List.getElem?_take_of_lt inside, List.getElem?_drop] at found
    exact found
  exact Heap.loadByte_alias (Heap.loadBytes_get loaded contents) (by
    simp only [Nat.zero_add, Nat.add_assoc])

#print axioms Heap.loadBytes_of_read_slice

end Lanius.Memory
