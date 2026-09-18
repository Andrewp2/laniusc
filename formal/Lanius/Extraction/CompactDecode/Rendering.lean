import Lanius.Extraction.CompactDecode.Unit
import Lanius.Extraction.CompactOutput.PackHeader

namespace Lanius.Extraction.CompactDecode
open CompactOutput

private theorem hex_ascii (value count : Nat) : ∀ digit ∈ hexDigits value count, digit < 128 := by
  induction count with
  | zero => simp [hexDigits]
  | succ count ih =>
    intro digit member
    rcases List.mem_cons.mp member with rfl | member
    · unfold hexDigit
      split <;> omega
    · exact ih digit member

/-- All compact payload fields are emitted as ASCII hex, including UTF-8
paths and source bytes. No validity or decoder-success premise is needed. -/
theorem UnitData.encoding_ascii (data : UnitData) : ∀ value ∈ data.encoding, value < 128 := by
  simp only [UnitData.encoding, UnitData.chunks, List.flatten_cons, List.flatten_nil,
    List.forall_mem_append, List.forall_mem_flatMap, Tokens.encoding,
    Assignments.encodeAll, Assignments.encoding, Nodes.encodeRecord, Nodes.encodeHeader,
    Nodes.encodeChildren, Nodes.encodeChild, Nodes.childEncoding]
  repeat' first | exact hex_ascii _ _ | apply And.intro | contradiction | intro

/-- The only finite fact needed to interpret an ASCII payload as a string.
This is kernel reduction over 128 one-character encodings, not native trust. -/
private theorem ascii_character (value : Fin 128) :
    String.utf8EncodeChar (Char.ofNat value.val) = [UInt8.ofNat value.val] := by
  revert value
  decide +kernel

private theorem ascii_bytes (values : List Nat) (ascii : ∀ value ∈ values, value < 128) :
    ((values.map Char.ofNat).utf8Encode).data.toList = values.map UInt8.ofNat := by
  induction values with
  | nil => simp
  | cons value rest ih =>
    have single := ascii_character ⟨value, ascii value List.mem_cons_self⟩
    have tail := ih (fun found member => ascii found (List.mem_cons_of_mem _ member))
    rw [List.map_cons, List.utf8Encode_cons, List.utf8Encode_singleton, single]
    simp only [ByteArray.toList_data_append, List.toList_data_toByteArray, tail, List.singleton_append,
      List.map_cons]

/-- A proof view of the already-emitted hex payload, not another runtime
serializer. Its UTF-8 encoding is exactly the original byte values. -/
def renderedPack (count : Nat) (units : List UnitData) : String :=
  String.ofList ((PackHeader.encoding count ++ units.flatMap UnitData.encoding).map Char.ofNat)

theorem renderedPack_bytes (count : Nat) (units : List UnitData) :
    (renderedPack count units).toUTF8.toList.map (fun byte => Int.ofNat byte.toNat) =
      (PackHeader.encoding count ++ units.flatMap UnitData.encoding).map Int.ofNat := by
  have ascii : ∀ value ∈ PackHeader.encoding count ++ units.flatMap UnitData.encoding, value < 128 := by
    simp only [PackHeader.encoding, List.forall_mem_append, List.forall_mem_flatMap]
    repeat' first | exact hex_ascii _ _ | exact UnitData.encoding_ascii _ | apply And.intro | intro
  rw [renderedPack, String.toUTF8_eq_toByteArray, String.toByteArray_ofList, byteArray_toList, ascii_bytes _ ascii]
  simp only [List.map_map]
  apply List.map_congr_left
  intro value member
  have bounded := ascii value member
  simp only [Function.comp_def, UInt8.toNat_ofNat', Nat.mod_eq_of_lt (by omega : value < 256)]

end Lanius.Extraction.CompactDecode
