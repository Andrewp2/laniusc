import Lanius.Extraction.Entry.Files.Control
import Lanius.Extraction.CompactArtifact
import Lanius.Extraction.CompactDecode.Buffer

namespace Lanius.Extraction.Entry.Files
open Lanius.Core Lanius.Semantics Lanius.Properties

variable {count : Nat} {units : List CompactDecode.UnitData} {sources : List SourceFile}
variable {position : Int} {contents : List Int}

/-- The ordered history retains semantic evidence, not just bytes which a
caller must separately assume will pass a validator. -/
theorem History.syntax (history : History count units sources position contents) :
    CompactSyntaxUnitsValid (units.map CompactDecode.UnitData.artifact) := by
  have accepted := history.accepted
  clear history
  induction units with
  | nil => exact .nil
  | cons unit rest ih =>
    exact .cons (checkParseArtifact_sound (accepted unit List.mem_cons_self))
      (ih (fun found member => accepted found (List.mem_cons_of_mem _ member)))

/-- Recover the complete compact payload from the physical output prefix.
Only the Lean module framing is removed; unit order and the header are kept. -/
theorem History.payload (history : History count units sources position contents) :
    (contents.take position.toNat).drop Framing.bytes.length =
      (CompactOutput.PackHeader.encoding count ++ units.flatMap CompactDecode.UnitData.encoding).map Int.ofNat := by
  rw [history.cursor, Int.toNat_natCast, history.output]
  have offset : Framing.bytes.length = ((Framing.bytes.map UInt8.toNat).map Int.ofNat).length := by simp only [List.length_map]
  rw [offset]
  simp only [bytes, List.map_append, List.append_assoc, List.drop_left]

/-- Assemble the public source-bound certificate from the completed history
and the bytes supplied to the actual compact decoder. This proves decoder
success; it does not require a second parser run or assumed acceptance. The
remaining byte equality is the boundary supplied by final output packing. -/
theorem History.certificate (history : History count units sources position contents)
    (complete : units.length = count) (positive : 0 < count) (countFit : count < 4294967296)
    (encoded : String)
    (backing : encoded.toUTF8.toList.map (fun byte => Int.ofNat byte.toNat) =
      (contents.take position.toNat).drop Framing.bytes.length) :
    Nonempty (CheckedCompactSyntaxSourcePack encoded sources) := by
  have wire := backing.trans history.payload
  have encoding : CompactDecode.EncodedAt encoded.toUTF8 0
      (CompactOutput.PackHeader.encoding units.length ++ units.flatMap CompactDecode.UnitData.encoding) := by
    apply CompactDecode.EncodedAt.of_buffer [] []
    simpa only [List.nil_append, List.append_nil, complete] using wire
  have size := congrArg List.length wire
  simp only [List.length_map, CompactDecode.byteArray_toList, Array.length_toList,
    List.length_append, Header.encoding_length] at size
  have nonempty : units ≠ [] := by intro empty; rw [empty] at complete; simp only [List.length_nil] at complete; omega
  have decoded := CompactDecode.readPack_encoding units
    (fun unit member => ⟨history.encodable unit member, history.nonempty unit member⟩)
    nonempty (complete.symm ▸ countFit) encoding (by simpa only [Nat.zero_add, ByteArray.size] using size)
  refine ⟨⟨⟨⟨schemaVersion, units.map CompactDecode.UnitData.artifact⟩, ?_, rfl, history.syntax⟩, ?_⟩⟩
  · simp only [decodeCompactArtifactPack?, decoded, Option.map_some]
  · simpa only [compactPackSources, List.flatMap_map, Function.comp_def] using history.sources

end Lanius.Extraction.Entry.Files
