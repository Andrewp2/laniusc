import Lanius.X86.Buffer.Bytes

namespace Lanius.X86.Buffer

/-- A byte window produced in a caller-owned output buffer. The contract
retains the untouched integer slots, not just their truncated byte values. -/
structure Emission (original : List Int) (cursor : Nat) (code : List UInt8) (emitted : List Int) : Prop where
  length : emitted.length = original.length
  bytes : byteSlice emitted cursor code.length = code
  frame : ∀ index, index < cursor ∨ cursor + code.length ≤ index → emitted[index]? = original[index]?

theorem writtenBytes_emission (room : start + bytes.length ≤ values.length) :
    Emission values start (bytes.map UInt8.ofNat) (writtenBytes values start bytes) := by
  refine ⟨writtenBytes_length, ?_, ?_⟩
  · simpa only [List.length_map] using writtenBytes_byteSlice room
  · simpa only [List.length_map] using (fun index outside => writtenBytes_frame (values := values) (index := index) outside)

theorem byteSlice_congr (same : ∀ index, index < count → first[position + index]? = second[position + index]?) :
    byteSlice first position count = byteSlice second position count := by
  apply List.ext_getElem?
  intro index
  by_cases inside : index < count
  · rw [byteSlice_get inside, byteSlice_get inside, same index inside]
  · rw [List.getElem?_eq_none (by simp only [byteSlice, List.length_map, List.length_take]; omega),
      List.getElem?_eq_none (by simp only [byteSlice, List.length_map, List.length_take]; omega)]

theorem byteSlice_append : byteSlice values position (first + second) =
    byteSlice values position first ++ byteSlice values (position + first) second := by
  unfold byteSlice
  rw [List.take_add, List.map_append, List.drop_drop]

/-- Sequential emissions compose without evaluating either emitter again. -/
theorem Emission.append (first : Emission original cursor left middle)
    (second : Emission middle (cursor + left.length) right final) :
    Emission original cursor (left ++ right) final := by
  refine ⟨second.length.trans first.length, ?_, ?_⟩
  · rw [List.length_append, byteSlice_append, second.bytes,
      byteSlice_congr (fun index inside => second.frame (cursor + index) (Or.inl (by omega))), first.bytes]
  · intro index outside
    rw [second.frame index (by simp only [List.length_append] at outside; omega),
      first.frame index (by simp only [List.length_append] at outside; omega)]

end Lanius.X86.Buffer
