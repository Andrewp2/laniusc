import Lanius.Extraction.CompactDecode.Rendering
import Lanius.Extraction.CompactDecode.Units
import Lanius.Extraction.CompactArtifact

namespace Lanius.Extraction.CompactDecode

/-- Authenticate the complete byte image through the serializer's existing
ASCII theorem, without running the byte reader at every use. -/
theorem renderedPack_byteArray (count : Nat) (units : List UnitData) :
    (renderedPack count units).toUTF8.toList =
      (CompactOutput.PackHeader.encoding count ++ units.flatMap UnitData.encoding).map UInt8.ofNat := by
  have bytes := congrArg (List.map (fun value : Int => UInt8.ofNat value.toNat))
    (renderedPack_bytes count units)
  simpa only [List.map_map, Function.comp_def, Int.toNat,
    UInt8.ofNat_toNat, List.map_id'] using bytes

/-- The public decoder inverts the existing serializer on all encodable,
nonempty packs. This is a theorem about the actual decoder, not a second
implementation or an assumed successful validation. -/
theorem decode_renderedPack (units : List UnitData)
    (valid : ∀ unit ∈ units, unit.Encodable ∧ unit.nodes ≠ [])
    (nonempty : units ≠ []) (countFit : units.length < 4294967296) :
    decodeCompactArtifactPack? (renderedPack units.length units) =
      some ⟨schemaVersion, units.map UnitData.artifact⟩ := by
  have bytes := renderedPack_byteArray units.length units
  have encoded : EncodedAt (renderedPack units.length units).toUTF8 0
      (CompactOutput.PackHeader.encoding units.length ++ units.flatMap UnitData.encoding) := by
    intro index value found
    have atIndex : (renderedPack units.length units).toUTF8.data[index]? =
        some (UInt8.ofNat value) := by
      simpa only [byteArray_toList, Array.getElem?_toList, List.getElem?_map,
        found, Option.map_some] using
        congrArg (fun values : List UInt8 => values[index]?) bytes
    simpa only [Nat.zero_add, getElem?_def, ByteArray.size,
      ByteArray.getElem_eq_getElem_data] using atIndex
  have endOfInput := congrArg List.length bytes
  simp only [byteArray_toList, Array.length_toList, ByteArray.size_data,
    List.length_map, List.length_append, CompactOutput.PackHeader.encoding,
    CompactOutput.hexDigits_length] at endOfInput
  have decoded := readPack_encoding units valid nonempty countFit encoded
    (by simpa only [Nat.zero_add] using endOfInput)
  simp only [decodeCompactArtifactPack?, decoded, Option.map_some]

end Lanius.Extraction.CompactDecode
