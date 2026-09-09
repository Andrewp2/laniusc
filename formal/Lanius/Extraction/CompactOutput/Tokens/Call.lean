import Lanius.Extraction.CompactOutput.Tokens.Function
import Lanius.Extraction.CompactOutput.Tokens.Arguments

namespace Lanius.Extraction.CompactOutput.Tokens

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.Compiler.Lexer
open Lanius.Extraction.CanonicalTokens.CanonicalizeModel

/-- Public execution of the complete token serializer. The input prefix
is the frontend's canonical token representation. Partial output and the caller frame are retained. -/
theorem Checked.write (checked : Checked program byte digit word)
    (tokens : List RawToken) (inputLength sourceLength capacity : Nat) (position : Int)
    (wellFormed : StateWellFormed before)
    (input : I32Prefix before inputCell physicalCapacity (encodeTokens tokens))
    (distinctBuffers : outputCell ≠ inputCell)
    (inputRoom : 3 * tokens.length ≤ inputLength) (lengthFit : inputLength ≤ 2147483647)
    (sourceFit : sourceLength ≤ 2147483647)
    (fields : ∀ token ∈ tokens, token.kind.gpuCode ≤ 2147483647 ∧
      token.start ≤ token.finish ∧ token.finish ≤ sourceLength)
    (capacityBound : capacity ≤ original.length) (capacityFit : capacity ≤ 2147483647)
    (backing : before.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values original)) })
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments
      (argumentsValues (.slice i32 inputCell [] 0 physicalCapacity)
        (.slice i32 outputCell [] 0 original.length) inputLength tokens.length sourceLength capacity position) before) :
    ∃ after, Evaluates program.core caller (.call checked.source.function.id arguments)
        (.signed .i32 (appendAll capacity (encodeAll tokens) position original).position) after ∧
      after.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values
          (appendAll capacity (encodeAll tokens) position original).contents)) } ∧
      CellEffect (CellSet.singleton outputCell) before after := by
  let params := bindings (.slice i32 inputCell [] 0 physicalCapacity)
    (.slice i32 outputCell [] 0 original.length) inputLength tokens.length sourceLength capacity position
  have locals (index : Fin 7) : (enterCall before params).local? index.val = some
      ((argumentsValues (.slice i32 inputCell [] 0 physicalCapacity)
        (.slice i32 outputCell [] 0 original.length) inputLength tokens.length sourceLength capacity position).get index) :=
    enterCall_parameterBindings_matches wellFormed index
  have inputCallee : I32Prefix (enterCall before params) inputCell physicalCapacity
      (encodeTokens tokens) := by
    obtain ⟨unused, size, contents⟩ := input
    exact ⟨unused, size, ((enterCall_effect before params).oldCells inputCell
      (StateWellFormed.cell_lt_next_of_entry wellFormed contents) (by simp [CellSet.empty])).trans contents⟩
  let entry : Function.Entry (enterCall before params) := {
    inputCell, outputCell, tokens, contents := original, position, capacity
    wellFormed := enterCall_preserves_wellFormed wellFormed
    room := capacityBound, capacityFit, inputLength, inputRoom, lengthFit, sourceLength, sourceFit, fields, distinctBuffers
    input := ⟨physicalCapacity, locals ⟨0, by decide⟩, inputCallee⟩
    lengthRead := locals ⟨1, by decide⟩
    countRead := locals ⟨2, by decide⟩
    sourceRead := locals ⟨3, by decide⟩
    output := locals ⟨4, by decide⟩
    capacityRead := locals ⟨5, by decide⟩
    positionRead := locals ⟨6, by decide⟩
    backing := ((enterCall_effect before params).oldCells outputCell
      (StateWellFormed.cell_lt_next_of_entry wellFormed backing) (by simp [CellSet.empty])).trans backing
  }
  obtain ⟨completed, run, contents, effect⟩ := entry.execute word
  have called := checked.call wellFormed argumentsResult (bindings := params) rfl run effect
  exact ⟨restoreLocals before completed, called.1, contents, called.2⟩

end Lanius.Extraction.CompactOutput.Tokens

