import Lanius.Extraction.Parser.Derivation.Caller
import Lanius.Extraction.Parser.Derivation.Postcondition
import Lanius.Extraction.Parser.Recognize.Linked

namespace Lanius.Extraction.ParserDerivation

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.Compiler.Parser Lanius.Extraction.ParserRecognize

/-- Reader arguments contain only integer scalars and integer slices, so
    symbol relocation leaves their values and fresh parameter allocation fixed. -/
theorem readerCallee_relocated (symbols : Core.Relocation.Symbols) :
    Semantics.Relocation.state symbols
      (readerCallee caller workspaceValues outputValues workspaceCell outputCell tokenCount stateCount stateId offset) =
      readerCallee (Semantics.Relocation.state symbols caller) workspaceValues outputValues
        workspaceCell outputCell tokenCount stateCount stateId offset := by
  simp only [readerCallee, enterCall, Semantics.Relocation.bindLocals]
  rfl

/-- A linked call contract with the body execution discharged, rather than
    supplied as a premise. Argument evaluation may use the caller's own expressions. -/
theorem LinkedReader.call_state {reader : CheckedReader program}
    (checked : LinkedReader reader allowed symbols)
    (sound : WorkspaceBackpointersSound grammar tokens workspace)
    (found : workspace.state? stateId = some state)
    (wellFormed : StateWellFormed caller)
    (artifact : RecognizerWorkspaceArtifact layout workspace workspaceValues workspaceCell caller)
    (layoutTokens : layout.tokenCount = tokens.length)
    (output : caller.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values outputValues)) })
    (distinctBuffers : outputCell ≠ workspaceCell)
    (capacityBound : outputValues.length ≤ 2147483647)
    (fits : offset + 4 + state.dot * 3 ≤ outputValues.length)
    (argumentsResult : ArgumentsEvaluateTo program.core (Semantics.Relocation.state symbols caller) arguments
      (readerValues workspaceValues outputValues workspaceCell outputCell layout.tokenCount
        workspace.states.length stateId offset) (Semantics.Relocation.state symbols caller)) :
    ∃ children after, children.length = state.dot ∧
      derivationChildren? workspace (stateId + 1) stateId = some children ∧
      Evaluates program.core (Semantics.Relocation.state symbols caller)
        (.call reader.source.function.id arguments) (.signed .i32 (Int.ofNat state.dot)) after ∧
      after.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values
          (outputValues.take offset ++ derivationRecordWords state children ++
            outputValues.drop (offset + 4 + state.dot * 3)))) } ∧
      RecognizerWorkspaceArtifact layout workspace workspaceValues workspaceCell after ∧
      CellEffect (CellSet.singleton outputCell) (Semantics.Relocation.state symbols caller) after := by
  obtain ⟨children, completed, length, computed, execution, written, retained, effect⟩ :=
    reader.execute_state sound found wellFormed artifact layoutTokens output distinctBuffers capacityBound fits
  have body := checked.executes execution
  rw [readerCallee_relocated] at body
  have linkedEffect := effect.relocate symbols
  rw [readerCallee_relocated] at linkedEffect
  refine ⟨children, restoreLocals (Semantics.Relocation.state symbols caller)
    (Semantics.Relocation.state symbols completed), length, computed, ?_, ?_, ?_, ?_⟩
  · exact reader.call_returns argumentsResult body
  · exact relocate_words symbols written
  · exact (retained.relocated symbols).transfer_cells rfl
  · exact CellEffect.closeCall _ _ (Semantics.Relocation.state_wellFormed symbols wellFormed) linkedEffect

/-- A state child emitted by the parent reader is a completed, earlier stored
    derivation. Read it using the same linked call contract, with no separate
    child-membership or completeness assumption. Capacity is stated for the
    uniquely stored child, without imposing a whole-workspace worst-case bound. -/
theorem LinkedReader.call_child {reader : CheckedReader program}
    (checked : LinkedReader reader allowed symbols)
    (sound : WorkspaceBackpointersSound grammar tokens workspace)
    (parentFound : workspace.state? parentId = some parent)
    (parentComputed : derivationChildren? workspace (parentId + 1) parentId = some parentChildren)
    (member : Child.state childId ∈ parentChildren)
    (wellFormed : StateWellFormed caller)
    (artifact : RecognizerWorkspaceArtifact layout workspace workspaceValues workspaceCell caller)
    (layoutTokens : layout.tokenCount = tokens.length)
    (output : caller.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values outputValues)) })
    (distinctBuffers : outputCell ≠ workspaceCell)
    (capacityBound : outputValues.length ≤ 2147483647)
    (fits : ∀ childState, workspace.state? childId = some childState →
      offset + 4 + childState.dot * 3 ≤ outputValues.length)
    (argumentsResult : ArgumentsEvaluateTo program.core (Semantics.Relocation.state symbols caller) arguments
      (readerValues workspaceValues outputValues workspaceCell outputCell layout.tokenCount
        workspace.states.length childId offset) (Semantics.Relocation.state symbols caller)) :
    childId < parentId ∧
    ∃ childState, workspace.state? childId = some childState ∧
      ∃ productionBound : childState.production < grammar.productionCount,
        childState.dot = (grammar.productionAt ⟨childState.production, productionBound⟩).rhs.length ∧
        ∃ children after, children.length = childState.dot ∧
          derivationChildren? workspace (childId + 1) childId = some children ∧
          Evaluates program.core (Semantics.Relocation.state symbols caller)
            (.call reader.source.function.id arguments) (.signed .i32 (Int.ofNat childState.dot)) after ∧
          after.cellEntry? outputCell = some {
            id := outputCell, value := some (.array (signedI32Values
              (outputValues.take offset ++ derivationRecordWords childState children ++
                outputValues.drop (offset + 4 + childState.dot * 3)))) } ∧
          RecognizerWorkspaceArtifact layout workspace workspaceValues workspaceCell after ∧
          CellEffect (CellSet.singleton outputCell) (Semantics.Relocation.state symbols caller) after := by
  obtain ⟨earlier, childState, found, productionBound, complete⟩ :=
    sound.derivationChildren_state_before parentFound (Nat.lt_succ_self _) parentComputed member
  exact ⟨earlier, childState, found, productionBound, complete,
    checked.call_state sound found wellFormed artifact layoutTokens output distinctBuffers
      capacityBound (fits childState found) argumentsResult⟩

private theorem value_arguments (values : List Value) :
    ArgumentsEvaluateTo program caller (values.map Expr.value) values caller := by
  induction values with
  | nil => exact .nil program caller
  | cons value rest ih => exact .cons ⟨1, rfl⟩ ih

/-- Connect the two verified source functions at their value-level call
    boundary. The root and state-count arguments come from the recognizer's
    certified return, and no reader execution or semantic-workspace premise remains. -/
theorem LinkedReader.recognize_then_read {reader : CheckedReader program}
    (checked : LinkedReader reader allowed symbols)
    (argumentsResult : ArgumentsEvaluateTo verifiedParserCore before arguments
      (parserRecognizeValues words tokens tokenCapacity initialWorkspaceValues grammarCell tokensCell workspaceCell)
      afterArguments)
    (entry : RecognizerEntryResources grammarLayout grammar words tokens workspaceLayout initialWorkspaceValues
      grammarCell tokensCell workspaceCell
      (parserRecognizeCallee afterArguments words tokens tokenCapacity initialWorkspaceValues
        grammarCell tokensCell workspaceCell))
    (closed : Dependencies.expression allowed (.call extractedParserRecognizeFunction.id arguments) = true)
    (success : parseResultStatus? (executeRecognizerCall argumentsResult entry).outcome.resultValue = some 0)
    (wellFormed : StateWellFormed afterArguments)
    (layoutTokens : workspaceLayout.tokenCount = tokens.length)
    (output : afterArguments.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values outputValues)) })
    (distinctBuffers : outputCell ≠ workspaceCell)
    (capacityBound : outputValues.length ≤ 2147483647)
    (fits : offset + 4 + ((executeRecognizerCall argumentsResult entry).successRoot success).root.dot * 3 ≤ outputValues.length) :
    let recognition := executeRecognizerCall argumentsResult entry
    let root := recognition.successRoot success
    let values := readerValues recognition.finalWorkspaceValues outputValues workspaceCell outputCell
      workspaceLayout.tokenCount recognition.finalWorkspace.states.length root.rootState offset
    Evaluates program.core (Semantics.Relocation.state symbols before)
      (Core.Relocation.expression symbols (.call extractedParserRecognizeFunction.id arguments))
      (Core.Relocation.value symbols recognition.outcome.resultValue)
      (Semantics.Relocation.state symbols recognition.after) ∧
    ∃ children after, children.length = root.root.dot ∧
      derivationChildren? recognition.finalWorkspace (root.rootState + 1) root.rootState = some children ∧
      Evaluates program.core (Semantics.Relocation.state symbols recognition.after)
        (.call reader.source.function.id (values.map Expr.value)) (.signed .i32 (Int.ofNat root.root.dot)) after ∧
      after.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values
          (outputValues.take offset ++ derivationRecordWords root.root children ++
            outputValues.drop (offset + 4 + root.root.dot * 3)))) } ∧
      RecognizerWorkspaceArtifact workspaceLayout recognition.finalWorkspace
        recognition.finalWorkspaceValues workspaceCell after ∧
      CellEffect (CellSet.singleton outputCell) (Semantics.Relocation.state symbols recognition.after) after := by
  let recognition := executeRecognizerCall argumentsResult entry
  have unchanged := (recognition.effect.oldCells outputCell
    (StateWellFormed.cell_lt_next_of_entry wellFormed output) distinctBuffers).trans output
  exact ⟨recognition.linked_evaluation checked.link checked.injective closed,
    checked.call_state (recognition.successRoot success).stored.backpointersSound
      (recognition.successRoot success).found (recognition.preservesWellFormed wellFormed)
      recognition.workspaceArtifact layoutTokens unchanged distinctBuffers capacityBound fits (value_arguments _)⟩

end Lanius.Extraction.ParserDerivation
