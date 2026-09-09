import Lanius.Extraction.CompactDecode.Grammar
import Lanius.Extraction.OutputPacking.Loop

namespace Lanius.Extraction.CompactDecode

open Lanius.Core Lanius.Semantics Lanius.Separation

/-- Recover the packing loop's exact byte prefix from the physical emitter
buffer. Equality of independently assumed logical byte lists is not required. -/
theorem packing_input_prefix
    (initial : OutputPacking.LoopInvariant memory locals processed state)
    (output : state.cellEntry? memory.inputCell = some {
      id := memory.inputCell, value := some (.array (signedI32Values values)) }) :
    memory.bytes.map (fun b => Int.ofNat b.toNat) = values.take memory.bytes.length := by
  have entries := initial.inputContents.symm.trans output
  have encoded : signedI32Values memory.inputValues = signedI32Values values := by
    have cells := congrArg (fun entry => entry.value) (Option.some.inj entries)
    exact Value.array.inj (Option.some.inj cells)
  have same := signedI32Values_injective encoded
  rw [← same]
  change memory.bytes.map (fun b => Int.ofNat b.toNat) =
    (memory.bytes.map (fun b => Int.ofNat b.toNat) ++ memory.inputTail).take memory.bytes.length
  rw [← List.length_map (f := fun b : UInt8 => Int.ofNat b.toNat) (as := memory.bytes), List.take_left]

theorem packing_decode_unit
    (storage : CompactOutput.Unit.Storage emission result collection before)
    (wellFormed : Lanius.Properties.StateWellFormed before)
    (path : String)
    (pathBytes : path.toUTF8.toList.map UInt8.toNat = emission.path.map Fin.val)
    (sameGrammar : emission.data.grammar.grammar = laniusGrammar)
    (position : Nat) (positionEq : emission.position = position)
    (room : position + (emission.encoding collection.assignments collection.records).length ≤ emission.capacity)
    (initial : OutputPacking.LoopInvariant memory locals [] state)
    (inputCell : memory.inputCell = emission.outputCell)
    (output : state.cellEntry? emission.outputCell = some {
      id := emission.outputCell, value := some (.array (signedI32Values
        (CompactOutput.appendAll emission.capacity (emission.encoding collection.assignments collection.records)
          emission.position emission.original).contents)) })
    (count : memory.bytes.length = position + (emission.encoding collection.assignments collection.records).length) :
    readArtifact.run {bytes := ⟨memory.bytes.toArray⟩, offset := position} =
      some ((emissionUnit emission path collection.assignments collection.records).artifact,
        {bytes := ⟨memory.bytes.toArray⟩,
          offset := position + (emission.encoding collection.assignments collection.records).length}) := by
  apply storage_decode_same_grammar storage wellFormed path pathBytes sameGrammar position positionEq room
  rw [byteArray_toList]
  simp only [List.toList_toArray]
  have prefixBytes := packing_input_prefix initial (by simpa only [inputCell] using output)
  simpa only [count] using prefixBytes

end Lanius.Extraction.CompactDecode
