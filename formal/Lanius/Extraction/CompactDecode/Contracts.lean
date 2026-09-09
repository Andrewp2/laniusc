import Lanius.Extraction.CompactDecode.Emission
import Lanius.Extraction.CompactDecode.Buffer

namespace Lanius.Extraction.CompactDecode

open CompactOutput SemanticTokens Lanius.Compiler.Parser

theorem nodeInput_encodable (input : Unit.NodeInput state count outputCell)
    (countFit : count ≤ 2147483647)
    (productions : ∀ record ∈ input.records, ∃ p,
      laniusGrammar.production? record.production = some p) :
    ∀ record ∈ input.records, NodeEncodable record := by
  intro record member
  have fields := input.fields record member
  have stored := (input.stored record member).bounds
  have room := input.inputRoom
  have inputFit := input.inputFit
  obtain ⟨index, indexBound, atIndex⟩ := List.mem_iff_getElem.mp member
  have linked := input.linked index record (by rw [List.getElem?_eq_getElem indexBound, atIndex])
  refine ⟨productions record member, by omega, by omega, by omega, by omega, ?_⟩
  intro child childMember
  have childFields := Nodes.child_fields child count index countFit
    (by have := input.nodesFit; omega) (linked child childMember)
    (input.tokenBound record member child childMember)
  omega

theorem storage_encodable (storage : Unit.Storage emission result collection before)
    (wellFormed : Lanius.Properties.StateWellFormed before) (path : String)
    (pathBytes : path.toUTF8.toList.map UInt8.toNat = emission.path.map Fin.val)
    (productions : ∀ record ∈ collection.records, ∃ p,
      laniusGrammar.production? record.production = some p) :
    (emissionUnit emission path collection.assignments collection.records).Encodable := by
  let inputs := storage.inputs wellFormed
  have pathCount := congrArg List.length pathBytes
  simp only [List.length_map, byteArray_toList, Array.length_toList, ByteArray.size_data] at pathCount
  have sourceCount : inputs.source.values.length = emission.data.request.source.length := List.length_map ..
  have sourceFit := inputs.source.lengthFit
  rw [sourceCount] at sourceFit
  have rawRoom := inputs.raw.inputRoom
  have rawFit := inputs.raw.lengthFit
  have tokenRoom := inputs.canonical.inputRoom
  have tokenFit := inputs.canonical.lengthFit
  have rawCount : emission.data.raw.length ≤ 2147483647 := by
    change 3 * emission.data.raw.length ≤ _ at rawRoom
    omega
  have tokenCount : emission.data.tokens.length ≤ 2147483647 := by
    change 3 * emission.data.tokens.length ≤ _ at tokenRoom
    omega
  refine {
    pathFit := by have := storage.pathFit; change path.toUTF8.size < _; omega
    sourceFit := by change (sourceArray emission.data.request.source).size < _; rw [sourceArray_size]; omega
    rawFit := by change emission.data.raw.length < _; omega
    tokenFit := by change emission.data.tokens.length < _; omega
    nodeFit := by
      have bound := inputs.nodes.nodesFit
      change collection.records.length ≤ _ at bound
      change collection.records.length < _
      omega
    rawFields := ?_
    tokenFields := ?_
    assignments := ?_
    assignmentCount := ?_
    nodes := nodeInput_encodable inputs.nodes tokenCount productions }
  · intro token member
    have fields := inputs.raw.fields token member
    rw [sourceCount] at fields
    omega
  · intro token member
    have fields := inputs.canonical.fields token member
    rw [sourceCount] at fields
    omega
  · intro assignment member
    have fields := collection.assignment_fields storage.kindsFit assignment member
    constructor <;> omega
  · change collection.assignments.length = emission.data.tokens.length
    simpa only [SemanticTokens.artifactTokens, List.length_map] using collection.lengthEq

theorem storage_decode (storage : Unit.Storage emission result collection before)
    (wellFormed : Lanius.Properties.StateWellFormed before) (path : String)
    (pathBytes : path.toUTF8.toList.map UInt8.toNat = emission.path.map Fin.val)
    (productions : ∀ record ∈ collection.records, ∃ p,
      laniusGrammar.production? record.production = some p)
    (encoded : EncodedAt bytes offset (emission.encoding collection.assignments collection.records)) :
    readArtifact.run {bytes, offset} =
      some ((emissionUnit emission path collection.assignments collection.records).artifact,
        {bytes, offset := offset + (emission.encoding collection.assignments collection.records).length}) := by
  have run := emission_decode emission path collection.assignments collection.records pathBytes
    (storage_encodable storage wellFormed path pathBytes productions) encoded
  have positive := collection.nonempty result.parse
  have nonempty : collection.records.isEmpty = false := by
    cases eq : collection.records <;> simp_all
  simpa only [nonempty, Bool.false_eq_true, ↓reduceIte] using run

theorem storage_decode_output (storage : Unit.Storage emission result collection before)
    (wellFormed : Lanius.Properties.StateWellFormed before) (path : String)
    (pathBytes : path.toUTF8.toList.map UInt8.toNat = emission.path.map Fin.val)
    (productions : ∀ record ∈ collection.records, ∃ p,
      laniusGrammar.production? record.production = some p)
    (position : Nat) (positionEq : emission.position = position)
    (room : position + (emission.encoding collection.assignments collection.records).length ≤ emission.capacity)
    (backing : bytes.toList.map (fun b => Int.ofNat b.toNat) =
      (appendAll emission.capacity (emission.encoding collection.assignments collection.records)
        emission.position emission.original).contents.take
        (position + (emission.encoding collection.assignments collection.records).length)) :
    readArtifact.run {bytes, offset := position} =
      some ((emissionUnit emission path collection.assignments collection.records).artifact,
        {bytes, offset := position + (emission.encoding collection.assignments collection.records).length}) := by
  rw [positionEq] at backing
  exact storage_decode storage wellFormed path pathBytes productions
    (EncodedAt.after_append emission.capacity position _ emission.original room storage.room backing)

end Lanius.Extraction.CompactDecode
