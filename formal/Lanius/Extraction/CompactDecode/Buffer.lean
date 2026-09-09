import Lanius.Extraction.CompactDecode.Path
import Lanius.Extraction.CompactOutput.Buffer

namespace Lanius.Extraction.CompactDecode

/-- Transport a byte-backed buffer interval into the actual decoder's input
relation. Prefix and suffix contents are unrestricted. -/
theorem EncodedAt.of_buffer (leading suffix : List Int) (values : List Nat)
    (backing : bytes.toList.map (fun b => Int.ofNat b.toNat) =
      leading ++ values.map Int.ofNat ++ suffix) :
    EncodedAt bytes leading.length values := by
  intro index value found
  have bound : index < values.length := (List.getElem?_eq_some_iff.mp found).choose
  have atIndex := congrArg (fun list : List Int => list[leading.length + index]?) backing
  simp only [List.getElem?_map] at atIndex
  have expected : (leading ++ values.map Int.ofNat ++ suffix)[leading.length + index]? = some (Int.ofNat value) := by
    rw [List.append_assoc, List.getElem?_append_right (by omega)]
    simp only [Nat.add_sub_cancel_left]
    rw [List.getElem?_append_left (by simpa using bound), List.getElem?_map, found]
    rfl
  rw [expected] at atIndex
  obtain ⟨byte, byteAt, number⟩ := Option.map_eq_some_iff.mp atIndex
  have equal : byte = UInt8.ofNat value := by
    have natEqual : byte.toNat = value := Int.ofNat_inj.mp number
    rw [← natEqual]
    simp
  rw [byteArray_toList] at byteAt
  change bytes.data[leading.length + index]? = some (UInt8.ofNat value)
  simpa only [Array.getElem?_toList, equal] using byteAt

theorem EncodedAt.after_append (capacity position : Nat) (values : List Nat) (original : List Int)
    (room : position + values.length ≤ capacity) (storage : capacity ≤ original.length)
    (backing : bytes.toList.map (fun b => Int.ofNat b.toNat) =
      (CompactOutput.appendAll capacity values position original).contents.take (position + values.length)) :
    EncodedAt bytes position values := by
  rw [CompactOutput.appendAll_success capacity position values original room storage] at backing
  dsimp only [CompactOutput.AppendOutcome.contents] at backing
  have leadingLength : (original.take position).length = position := by
    rw [List.length_take, Nat.min_eq_left (by omega)]
  have writtenLength : (original.take position ++ values.map Int.ofNat).length = position + values.length := by
    simp only [List.length_append, leadingLength, List.length_map]
  rw [← writtenLength, List.take_left] at backing
  have encoded := EncodedAt.of_buffer (original.take position) [] values (by simpa only [List.append_nil] using backing)
  simpa only [leadingLength] using encoded

end Lanius.Extraction.CompactDecode
