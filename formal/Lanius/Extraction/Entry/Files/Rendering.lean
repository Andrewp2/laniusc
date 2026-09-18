import Lanius.Extraction.Entry.Files.Certificate
import Lanius.Extraction.CompactDecode.Rendering
import Lanius.Extraction.Entry.Suffix.Source

namespace Lanius.Extraction.Entry.Files
open Lanius.Core Lanius.Semantics Lanius.Extraction.CompactOutput

/-- Completed file history supplies the exact rendered module consumed by
packing. Neither a second byte list nor decoder acceptance is assumed. The
unused buffer tail remains outside the module and its certificate. -/
theorem History.rendered
    {count : Nat} {units : List CompactDecode.UnitData} {sources : List SourceFile}
    {earlier untouched : List Int}
    (history : History count units sources earlier.length (earlier ++ untouched))
    (complete : units.length = count) (positive : 0 < count) (countFit : count < 4294967296) :
    Nonempty (CheckedCompactSyntaxSourcePack (CompactDecode.renderedPack count units) sources) ∧
    Input.copiedBuffer earlier untouched Suffix.bytes =
      (Lanius.World.utf8Bytes (ExtractorContract.renderedModule (CompactDecode.renderedPack count units))).map
        (fun byte => Int.ofNat byte.toNat) ++ untouched.drop Suffix.bytes.length := by
  have payload := CompactDecode.renderedPack_bytes count units
  have earlierLength : earlier.length = (bytes count units).length := by
    exact Int.ofNat.inj history.cursor
  have earlierBytes : earlier = (bytes count units).map Int.ofNat := by
    have output := history.output
    rw [← earlierLength, List.take_left] at output
    exact output
  constructor
  · apply history.certificate complete positive countFit _
    exact payload.trans history.payload.symm
  · simp only [Input.copiedBuffer, earlierBytes, ExtractorContract.renderedModule,
      Lanius.World.utf8Bytes, String.toUTF8_eq_toByteArray, String.toByteArray_append,
      CompactDecode.byteArray_toList, ByteArray.toList_data_append, List.map_append]
    change (bytes count units).map Int.ofNat ++
      Suffix.bytes.map (fun byte => Int.ofNat byte.toNat) ++ untouched.drop Suffix.bytes.length = _
    rw [bytes, List.map_append, List.map_append]
    simp only [List.map_map, Function.comp_def, Int.ofNat_eq_natCast]
    simp only [String.toUTF8_eq_toByteArray, CompactDecode.byteArray_toList,
      List.map_append, Int.ofNat_eq_natCast] at payload
    rw [payload]
    simp only [Framing.bytes, Suffix.bytes, Lanius.World.utf8Bytes,
      String.toUTF8_eq_toByteArray, List.append_assoc]

end Lanius.Extraction.Entry.Files
