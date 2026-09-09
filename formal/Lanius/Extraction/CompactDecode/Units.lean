import Lanius.Extraction.CompactDecode.Unit
import Lanius.Extraction.CompactDecode.Pack

namespace Lanius.Extraction.CompactDecode

theorem reads_units (units : List UnitData)
    (valid : ∀ unit ∈ units, unit.Encodable ∧ unit.nodes ≠ [])
    (encoded : EncodedAt bytes offset (units.flatMap UnitData.encoding)) :
    Reads readArtifact {bytes, offset} (units.map UnitData.artifact)
      {bytes, offset := offset + (units.flatMap UnitData.encoding).length} := by
  induction units generalizing offset with
  | nil => exact Reads.nil
  | cons unit units ih =>
    have fits := valid unit List.mem_cons_self
    have head := unit.decode fits.1 encoded.left
    have notEmpty : unit.nodes.isEmpty = false := by
      cases eq : unit.nodes <;> simp_all
    simp only [notEmpty, Bool.false_eq_true, ↓reduceIte] at head
    have tail := ih (fun u h => valid u (List.mem_cons_of_mem unit h)) encoded.right
    simpa only [List.map_cons, List.flatMap_cons, List.length_append, Nat.add_assoc]
      using Reads.cons head tail

theorem unit_encoding_min_length (unit : UnitData) : 40 ≤ unit.encoding.length := by
  simp only [UnitData.encoding, UnitData.chunks, List.flatten_cons, List.flatten_nil,
    List.length_append, List.length_nil, CompactOutput.hexDigits_length]
  omega

theorem units_encoding_min_length (units : List UnitData) :
    units.length * 40 ≤ (units.flatMap UnitData.encoding).length := by
  induction units with
  | nil => exact Nat.le_refl 0
  | cons unit units ih =>
    have head := unit_encoding_min_length unit
    simp only [List.flatMap_cons, List.length_append, List.length_cons]
    omega

theorem readPack_encoding (units : List UnitData)
    (valid : ∀ unit ∈ units, unit.Encodable ∧ unit.nodes ≠ [])
    (nonempty : units ≠ []) (countFit : units.length < 4294967296)
    (encoded : EncodedAt bytes offset (CompactOutput.PackHeader.encoding units.length ++
      units.flatMap UnitData.encoding))
    (endOfInput : bytes.size = offset + 16 + (units.flatMap UnitData.encoding).length) :
    readPack.run {bytes, offset} = some (⟨schemaVersion, units.map UnitData.artifact⟩,
      {bytes, offset := bytes.size}) := by
  have payload := encoded.right
  simp only [CompactOutput.PackHeader.encoding, List.length_append, CompactOutput.hexDigits_length] at payload
  have room := Nat.le_trans (units_encoding_min_length units) payload.remaining
  have reads := reads_units units valid payload
  have result := readPack_units (units.map UnitData.artifact)
    (by simpa only [List.length_map] using countFit)
    (by simpa only [List.length_map] using encoded.left)
    (by simpa only [List.length_map] using room) reads
  have notEmpty : (units.map UnitData.artifact).isEmpty = false := by
    cases units <;> simp_all
  simpa only [notEmpty, Bool.false_eq_true, ↓reduceIte, ← endOfInput] using result

end Lanius.Extraction.CompactDecode
