import Lanius.X86.Buffer.Word

namespace Lanius.X86.Buffer

/-- The buffer effect of a finite consecutive sequence of byte stores. -/
def writtenBytes (values : List Int) (position : Nat) : List Nat → List Int
  | [] => values
  | byte :: bytes => writtenBytes (values.set position byte) (position + 1) bytes

@[simp] theorem writtenBytes_length :
    (writtenBytes values position bytes).length = values.length := by
  induction bytes generalizing values position with
  | nil => rfl
  | cons byte bytes ih => simp only [writtenBytes, ih, List.length_set]

/-- Consecutive emitter calls write the concatenation of their bytes. -/
theorem writtenBytes_append :
    writtenBytes values position (first ++ second) =
      writtenBytes (writtenBytes values position first) (position + first.length) second := by
  induction first generalizing values position with
  | nil => simp [writtenBytes]
  | cons byte rest ih =>
      simpa only [List.cons_append, writtenBytes, List.length_cons, Nat.add_assoc,
        Nat.add_comm 1] using ih (values := values.set position byte) (position := position + 1)

theorem writtenBytes_frame
    (outside : index < position ∨ position + bytes.length ≤ index) :
    (writtenBytes values position bytes)[index]? = values[index]? := by
  induction bytes generalizing values position with
  | nil => rfl
  | cons byte bytes ih =>
      rw [writtenBytes, ih (by simp only [List.length_cons] at outside; omega)]
      exact List.getElem?_set_ne (by simp only [List.length_cons] at outside; omega)

theorem writtenBytes_lane (room : position + bytes.length ≤ values.length)
    (bound : lane < bytes.length) :
    (writtenBytes values position bytes)[position + lane]? = some (bytes[lane] : Int) := by
  induction bytes generalizing values position lane with
  | nil => simp at bound
  | cons byte bytes ih =>
      cases lane with
      | zero =>
          rw [writtenBytes, writtenBytes_frame (Or.inl (by omega))]
          simp only [Nat.add_zero, List.getElem_cons_zero]
          exact List.getElem?_set_self (by simp only [List.length_cons] at room; omega)
      | succ lane =>
          simpa only [writtenBytes, Nat.add_assoc, Nat.add_comm 1 lane, List.getElem_cons_succ] using
            ih (values := values.set position byte) (position := position + 1) (lane := lane)
              (by simp only [List.length_set, List.length_cons] at *; omega)
              (by simp only [List.length_cons] at bound; omega)

theorem writtenBytes_slice (room : position + bytes.length ≤ values.length) :
    ((writtenBytes values position bytes).drop position).take bytes.length =
      bytes.map Int.ofNat := by
  apply List.ext_getElem?
  intro lane
  by_cases bound : lane < bytes.length
  · rw [List.getElem?_take_of_lt bound, List.getElem?_drop, writtenBytes_lane room bound]
    simp only [List.getElem?_map, List.getElem?_eq_getElem bound, Option.map_some, Int.ofNat_eq_natCast]
  · rw [List.getElem?_eq_none (by simp only [List.length_take]; omega)]
    rw [List.getElem?_eq_none (by simp only [List.length_map]; omega)]

theorem writtenBytes_byteSlice (room : position + bytes.length ≤ values.length) :
    byteSlice (writtenBytes values position bytes) position bytes.length =
      bytes.map UInt8.ofNat := by
  simp only [byteSlice, writtenBytes_slice room, List.map_map]
  rfl

/-- The common emitter layout: a variable-length byte header followed by a
signed disp32/immediate word. The final word cannot overwrite the header. -/
theorem writtenHeaderWord_byteSlice (header : List Nat) (word : Int)
    (room : position + header.length + 4 ≤ values.length) :
    byteSlice (writtenWord (writtenBytes values position header) (position + header.length) word)
      position (header.length + 4) = header.map UInt8.ofNat ++ Lanius.Semantics.i32Bytes word := by
  let initial := writtenBytes values position header
  have first : byteSlice (writtenWord initial (position + header.length) word) position header.length =
      byteSlice initial position header.length := by
    apply List.ext_getElem?
    intro index
    by_cases bound : index < header.length
    · rw [byteSlice_get bound, byteSlice_get bound, writtenWord_frame (Or.inl (by omega))]
    · rw [List.getElem?_eq_none (by simp only [byteSlice, List.length_map, List.length_take]; omega),
        List.getElem?_eq_none (by simp only [byteSlice, List.length_map, List.length_take]; omega)]
  have split (written : List Int) : byteSlice written position (header.length + 4) =
      byteSlice written position header.length ++ byteSlice written (position + header.length) 4 := by
    unfold byteSlice
    rw [List.take_add, List.map_append, List.drop_drop]
  rw [split, first, writtenWord_byteSlice (by simp only [writtenBytes_length]; omega),
    writtenBytes_byteSlice (by omega)]

end Lanius.X86.Buffer
