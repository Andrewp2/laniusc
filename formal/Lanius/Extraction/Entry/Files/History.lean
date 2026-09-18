import Lanius.Extraction.Entry.File.Certificate
import Lanius.Extraction.Entry.Framing
import Lanius.Extraction.Entry.Header

namespace Lanius.Extraction.Entry.Files
open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Extraction.CompactOutput

/-- The prefix already emitted before the final Lean-module suffix. The
header count describes the whole request, while `units` records progress. -/
def bytes (count : Nat) (units : List CompactDecode.UnitData) : List Nat :=
  Framing.bytes.map UInt8.toNat ++ PackHeader.encoding count ++ units.flatMap CompactDecode.UnitData.encoding

theorem bytes_append (count : Nat) (units : List CompactDecode.UnitData) (unit : CompactDecode.UnitData) :
    bytes count (units ++ [unit]) = bytes count units ++ unit.encoding := by
  simp only [bytes, List.flatMap_append, List.flatMap_cons, List.flatMap_nil, List.append_nil, List.append_assoc]

/-- Ordered accepted syntax evidence and its exact output prefix. Source
order is retained separately from path identity, so repeated paths are not
deduplicated or silently reordered. -/
structure History (count : Nat) (units : List CompactDecode.UnitData)
    (sources : List SourceFile) (position : Int) (contents : List Int) : Prop where
  countBound : units.length ≤ count
  encodable : ∀ unit ∈ units, unit.Encodable
  nonempty : ∀ unit ∈ units, unit.nodes ≠ []
  accepted : ∀ unit ∈ units, checkParseArtifact unit.artifact = true
  sources : units.flatMap (fun unit => unit.artifact.sources) = sources
  cursor : position = (bytes count units).length
  output : contents.take (bytes count units).length = (bytes count units).map Int.ofNat

/-- Initialize history from the existing startup theorem's exact buffer,
without re-running the prefix writer or compact-header emitter. -/
theorem History.start (count : Nat) (original : List Int) :
    History count [] [] (Framing.bytes.length + 16 : Nat)
      (Header.contents (Input.copiedBuffer [] original Framing.bytes) Framing.bytes.length count) := by
  have copied : (Input.copiedBuffer [] original Framing.bytes).take Framing.bytes.length =
      (Framing.bytes.map UInt8.toNat).map Int.ofNat := by
    simpa only [Input.copiedBuffer, List.nil_append, List.length_map, List.map_map, Function.comp_def,
      Int.ofNat_eq_natCast] using
      (List.take_left (l₁ := Framing.bytes.map (fun byte => (byte.toNat : Int))) (l₂ := original.drop Framing.bytes.length))
  have buffer : Header.contents (Input.copiedBuffer [] original Framing.bytes) Framing.bytes.length count =
      (bytes count []).map Int.ofNat ++
        (Input.copiedBuffer [] original Framing.bytes).drop (Framing.bytes.length + 16) := by
    simp only [Header.contents, copied, bytes, List.flatMap_nil, List.append_nil, List.map_append]
  refine ⟨by simp, by simp, by simp, by simp, rfl, ?_, ?_⟩
  · simp only [bytes, List.flatMap_nil, List.append_nil, List.length_append, List.length_map, Header.encoding_length]
  · rw [buffer]
    simpa only [List.length_map] using
      (List.take_left (l₁ := (bytes count []).map Int.ofNat)
        (l₂ := (Input.copiedBuffer [] original Framing.bytes).drop (Framing.bytes.length + 16)))

/-- Appending one certified unit extends both bytes and source history in
the same order. The old output prefix remains intact. -/
theorem History.append {count : Nat} {units : List CompactDecode.UnitData} {sources : List SourceFile}
    {position : Int} {contents : List Int} (history : History count units sources position contents)
    (unit : CompactDecode.UnitData) (source : SourceFile)
    (encodable : unit.Encodable) (nonempty : unit.nodes ≠ [])
    (accepted : checkParseArtifact unit.artifact = true) (sourceIdentity : unit.artifact.sources = [source])
    (remaining : units.length < count) :
    History count (units ++ [unit]) (sources ++ [source])
      ((bytes count units).length + unit.encoding.length : Nat)
      (contents.take (bytes count units).length ++ unit.encoding.map Int.ofNat ++
        contents.drop ((bytes count units).length + unit.encoding.length)) := by
  have buffer : contents.take (bytes count units).length ++ unit.encoding.map Int.ofNat ++
      contents.drop ((bytes count units).length + unit.encoding.length) =
      (bytes count (units ++ [unit])).map Int.ofNat ++
        contents.drop ((bytes count units).length + unit.encoding.length) := by
    rw [history.output, bytes_append, List.map_append]
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_⟩
  · simp only [List.length_append, List.length_singleton]; omega
  · intro found member
    rcases List.mem_append.mp member with old | last
    · exact history.encodable found old
    · rcases List.mem_singleton.mp last with rfl
      exact encodable
  · intro found member
    rcases List.mem_append.mp member with old | last
    · exact history.nonempty found old
    · rcases List.mem_singleton.mp last with rfl
      exact nonempty
  · intro found member
    rcases List.mem_append.mp member with old | last
    · exact history.accepted found old
    · rcases List.mem_singleton.mp last with rfl
      exact accepted
  · simp only [List.flatMap_append, List.flatMap_cons, List.flatMap_nil, List.append_nil, history.sources, sourceIdentity]
  · rw [bytes_append, List.length_append]
  · rw [buffer]
    simpa only [List.length_map] using
      (List.take_left (l₁ := (bytes count (units ++ [unit])).map Int.ofNat)
        (l₂ := contents.drop ((bytes count units).length + unit.encoding.length)))

end Lanius.Extraction.Entry.Files
