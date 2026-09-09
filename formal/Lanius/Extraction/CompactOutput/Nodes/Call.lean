import Lanius.Extraction.CompactOutput.Nodes.Function
import Lanius.Extraction.CompactOutput.Nodes.Arguments

namespace Lanius.Extraction.CompactOutput.Nodes

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.Extraction.SemanticTokens

/-- Execute the source-checked public node serializer for valid stored records
and references. The complete nested traversal and exact output are derived. -/
theorem Checked.write (checked : Checked program byte digit word tokenTag stateTag)
    (tokenConstant : ParserTreeSource.constantValue program.core tokenTag 1)
    (stateConstant : ParserTreeSource.constantValue program.core stateTag 2)
    (records : List RecordVisit) (words : List Int) (inputLength count capacity : Nat) (position : Int)
    (wellFormed : StateWellFormed before)
    (input : I32Prefix before inputCell inputCapacity words)
    (offsets : I32Prefix before offsetCell offsetCapacity (records.map (fun record => (record.offset : Int))))
    (distinctInput : outputCell ≠ inputCell) (distinctOffsets : outputCell ≠ offsetCell)
    (inputRoom : words.length ≤ inputLength) (inputFit : inputLength ≤ 2147483647)
    (countFit : count ≤ 2147483647) (nodesFit : records.length ≤ 2147483647)
    (stored : ∀ record ∈ records, record.Stored 0 words)
    (fields : ∀ record ∈ records, record.production ≤ 2147483647 ∧ record.start ≤ 2147483647 ∧ record.finish ≤ 2147483647)
    (linked : ∀ (index : Nat) (record : RecordVisit), records[index]? = some record → ∀ child ∈ record.children, child.Linked 0 records index)
    (tokenBound : ∀ record ∈ records, ∀ child ∈ record.children, ∀ use, child = .token use → use.token < count)
    (capacityBound : capacity ≤ original.length) (capacityFit : capacity ≤ 2147483647)
    (backing : before.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values original)) })
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments
      (argumentsValues (.slice i32 inputCell [] 0 inputCapacity) (.slice i32 offsetCell [] 0 offsetCapacity)
        (.slice i32 outputCell [] 0 original.length) inputLength records.length count capacity position) before) :
    ∃ after, Evaluates program.core caller (.call checked.source.function.id arguments)
        (.signed .i32 (appendAll capacity (encodeAll records) position original).position) after ∧
      after.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values
          (appendAll capacity (encodeAll records) position original).contents)) } ∧
      CellEffect (CellSet.singleton outputCell) before after := by
  let params := bindings (.slice i32 inputCell [] 0 inputCapacity) (.slice i32 offsetCell [] 0 offsetCapacity)
    (.slice i32 outputCell [] 0 original.length) inputLength records.length count capacity position
  have locals (index : Fin 8) : (enterCall before params).local? index.val = some
      ((argumentsValues (.slice i32 inputCell [] 0 inputCapacity) (.slice i32 offsetCell [] 0 offsetCapacity)
        (.slice i32 outputCell [] 0 original.length) inputLength records.length count capacity position).get index) :=
    enterCall_parameterBindings_matches wellFormed index
  have keepInput {cell : CellId} {physicalCapacity : Nat} {values : List Int}
      (owned : I32Prefix before cell physicalCapacity values) :
      I32Prefix (enterCall before params) cell physicalCapacity values := by
    obtain ⟨unused, size, contents⟩ := owned
    exact ⟨unused, size, ((enterCall_effect before params).oldCells cell
      (StateWellFormed.cell_lt_next_of_entry wellFormed contents) (by simp [CellSet.empty])).trans contents⟩
  let entry : Function.Entry (enterCall before params) := {
    records, words, inputLength, count, inputCell, offsetCell, outputCell, capacity, position, contents := original
    inputRoom, inputFit, countFit, nodesFit, capacityFit, stored, fields, linked, tokenBound, distinctInput, distinctOffsets
    wellFormed := enterCall_preserves_wellFormed wellFormed, room := capacityBound
    input := ⟨inputCapacity, locals ⟨0, by decide⟩, keepInput input⟩
    offsets := ⟨offsetCapacity, locals ⟨2, by decide⟩, keepInput offsets⟩
    lengthRead := locals ⟨1, by decide⟩, nodes := locals ⟨3, by decide⟩
    countRead := locals ⟨4, by decide⟩, output := locals ⟨5, by decide⟩
    capacityRead := locals ⟨6, by decide⟩, positionRead := locals ⟨7, by decide⟩
    backing := ((enterCall_effect before params).oldCells outputCell
      (StateWellFormed.cell_lt_next_of_entry wellFormed backing) (by simp [CellSet.empty])).trans backing }
  obtain ⟨completed, run, contents, effect⟩ := entry.execute word tokenConstant stateConstant
  have called := checked.call wellFormed argumentsResult (bindings := params) rfl run effect
  exact ⟨restoreLocals before completed, called.1, contents, called.2⟩

end Lanius.Extraction.CompactOutput.Nodes
