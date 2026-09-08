import Lanius.Extraction.VerifiedFrontend.Parser.Recognize.Setup
import Lanius.FunctionalViewCoreSimulation
import Lanius.Separation.CallFrame
import Lanius.Extraction.BufferCopy.RecognizeSource

namespace Lanius.Extraction.ParserRecognize

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler.Parser Lanius.Extraction
open Lanius.Extraction.ParserAccessors Lanius.Extraction.ParserFind
open Lanius.FunctionalView.Core

/-- The source region's arguments read the caller's existing buffers without
    changing state. Physical token capacity and logical token count stay distinct. -/
theorem recognition_arguments
    (region : BufferCopy.Recognition)
    (grammarLocal : caller.local? region.grammarId =
      some (parserGrammarValue words grammarCell))
    (grammarLengthLocal : caller.local? region.grammarLengthId =
      some (.signed .i32 (Int.ofNat words.length)))
    (tokensLocal : caller.local? region.locals.destination =
      some (parserTokenBufferValue tokenCapacity tokensCell))
    (tokenCountLocal : caller.local? region.locals.count =
      some (.signed .i32 (Int.ofNat tokens.length)))
    (workspaceLocal : caller.local? region.workspaceId =
      some (workspaceValue workspaceValues workspaceCell))
    (workspaceLengthLocal : caller.local? region.workspaceLengthId =
      some (.signed .i32 (Int.ofNat workspaceValues.length))) :
    Lanius.CallContracts.ArgumentsEvaluateTo program caller
      [.local region.grammarId, .local region.grammarLengthId,
       .local region.locals.destination, .local region.locals.count,
       .local region.workspaceId, .local region.workspaceLengthId]
      (parserRecognizeValues words tokens tokenCapacity workspaceValues
        grammarCell tokensCell workspaceCell) caller := by
  have localRead {id : Lanius.VarId} {value : Value}
      (found : caller.local? id = some value) :
      Evaluates program caller (.local id) value caller := by
    exact ⟨1, evalLocal_of_local 0 program caller id value found⟩
  exact .cons (localRead grammarLocal) (.cons (localRead grammarLengthLocal)
    (.cons (localRead tokensLocal) (.cons (localRead tokenCountLocal)
      (.cons (localRead workspaceLocal) (.cons (localRead workspaceLengthLocal)
        (.nil program caller))))))

/-- Build the callee's resources from caller storage and grammar facts.
    Parameter values and backing preservation follow from the call protocol. -/
theorem parserRecognizeCallee_resources
    (wellFormed : StateWellFormed caller)
    (grammarEncoded : EncodesGrammar grammarLayout grammar words)
    (grammarWellFormed : grammar.WellFormed)
    (wordsI32 : words.length ≤ 2147483647)
    (tokensI32 : tokens.length ≤ 2147483647)
    (workspaceLength : workspaceValues.length = workspaceLayout.workspaceLength)
    (workspaceTokenCount : workspaceLayout.tokenCount = tokens.length)
    (grammarBacking : caller.cellEntry? grammarCell = some {
      id := grammarCell, value := some (.array (signedI32Values words)) })
    (tokenStorage : I32Prefix caller tokensCell tokenCapacity (tokens.map Int.ofNat))
    (workspaceBacking : caller.cellEntry? workspaceCell = some {
      id := workspaceCell, value := some (.array (signedI32Values workspaceValues)) })
    (grammarWorkspaceDistinct : grammarCell ≠ workspaceCell)
    (tokensWorkspaceDistinct : tokensCell ≠ workspaceCell) :
    RecognizerResources grammarLayout grammar words tokens workspaceLayout
      workspaceValues grammarCell tokensCell workspaceCell
      (parserRecognizeCallee caller words tokens tokenCapacity workspaceValues
        grammarCell tokensCell workspaceCell) := by
  let environment : Lanius.FunctionalView.Env 6 := fun slot => [
    parserGrammarValue words grammarCell,
    .signed .i32 (Int.ofNat words.length),
    parserTokenBufferValue tokenCapacity tokensCell,
    .signed .i32 (Int.ofNat tokens.length),
    workspaceValue workspaceValues workspaceCell,
    .signed .i32 (Int.ofNat workspaceValues.length)].get slot
  have parameters := enterCall_parameterBindings_matches
    (environment := environment) wellFormed
  have bindingsEq : parameterBindings environment =
      parserRecognizeBindings words tokens tokenCapacity workspaceValues
        grammarCell tokensCell workspaceCell := by rfl
  rw [bindingsEq] at parameters
  have preserve {cell : Lanius.CellId} {value : Option Value}
      (backing : caller.cellEntry? cell = some { id := cell, value := value }) :
      (parserRecognizeCallee caller words tokens tokenCapacity workspaceValues
        grammarCell tokensCell workspaceCell).cellEntry? cell =
        some { id := cell, value := value } :=
    ((enterCall_effect caller
      (parserRecognizeBindings words tokens tokenCapacity workspaceValues
        grammarCell tokensCell workspaceCell)).oldCells cell
      (StateWellFormed.cell_lt_next_of_entry wellFormed backing)
      (by simp [CellSet.empty])).trans backing
  exact {
    grammarEncoded, grammarWellFormed, wordsI32, tokensI32,
    workspaceLength, workspaceTokenCount,
    wellFormed := enterCall_preserves_wellFormed wellFormed,
    grammarLocal := parameters ⟨0, by decide⟩,
    grammarLengthLocal := parameters ⟨1, by decide⟩,
    tokenStorage := parserRecognizeCallee_tokenStorage wellFormed tokenStorage,
    tokenCountLocal := parameters ⟨3, by decide⟩,
    workspaceLocal := parameters ⟨4, by decide⟩,
    workspaceLengthLocal := parameters ⟨5, by decide⟩,
    grammarBacking := preserve grammarBacking,
    workspaceBacking := preserve workspaceBacking,
    grammarWorkspaceDistinct, tokensWorkspaceDistinct
  }

/-- The resource constructor also discharges separation: all parameter cells
    are allocated after the caller's workspace cell. -/
theorem parserRecognizeCallee_entry
    (wellFormed : StateWellFormed caller)
    (grammarEncoded : EncodesGrammar grammarLayout grammar words)
    (grammarWellFormed : grammar.WellFormed)
    (wordsI32 : words.length ≤ 2147483647)
    (tokensI32 : tokens.length ≤ 2147483647)
    (workspaceLength : workspaceValues.length = workspaceLayout.workspaceLength)
    (workspaceTokenCount : workspaceLayout.tokenCount = tokens.length)
    (grammarBacking : caller.cellEntry? grammarCell = some {
      id := grammarCell, value := some (.array (signedI32Values words)) })
    (tokenStorage : I32Prefix caller tokensCell tokenCapacity (tokens.map Int.ofNat))
    (workspaceBacking : caller.cellEntry? workspaceCell = some {
      id := workspaceCell, value := some (.array (signedI32Values workspaceValues)) })
    (grammarWorkspaceDistinct : grammarCell ≠ workspaceCell)
    (tokensWorkspaceDistinct : tokensCell ≠ workspaceCell) :
    RecognizerEntryResources grammarLayout grammar words tokens workspaceLayout
      workspaceValues grammarCell tokensCell workspaceCell
      (parserRecognizeCallee caller words tokens tokenCapacity workspaceValues
        grammarCell tokensCell workspaceCell) := {
  resources := parserRecognizeCallee_resources wellFormed grammarEncoded
    grammarWellFormed wordsI32 tokensI32 workspaceLength workspaceTokenCount
    grammarBacking tokenStorage workspaceBacking grammarWorkspaceDistinct
    tokensWorkspaceDistinct
  parameterWorkspaceSeparate := enterCall_frame_disjoint_old_cell
    (StateWellFormed.cell_lt_next_of_entry wellFormed workspaceBacking)
}

/-- Invoke the proved recognizer from the source region's caller facts.
    This is in parser-program coordinates; relocation to the complete extractor
    remains a separate, checked execution-transport step. -/
noncomputable def executeRecognitionRegion
    (region : BufferCopy.Recognition)
    (grammarLocal : caller.local? region.grammarId =
      some (parserGrammarValue words grammarCell))
    (grammarLengthLocal : caller.local? region.grammarLengthId =
      some (.signed .i32 (Int.ofNat words.length)))
    (tokensLocal : caller.local? region.locals.destination =
      some (parserTokenBufferValue tokenCapacity tokensCell))
    (tokenCountLocal : caller.local? region.locals.count =
      some (.signed .i32 (Int.ofNat tokens.length)))
    (workspaceLocal : caller.local? region.workspaceId =
      some (workspaceValue workspaceValues workspaceCell))
    (workspaceLengthLocal : caller.local? region.workspaceLengthId =
      some (.signed .i32 (Int.ofNat workspaceValues.length)))
    (wellFormed : StateWellFormed caller)
    (grammarEncoded : EncodesGrammar grammarLayout grammar words)
    (grammarWellFormed : grammar.WellFormed)
    (wordsI32 : words.length ≤ 2147483647)
    (tokensI32 : tokens.length ≤ 2147483647)
    (workspaceLength : workspaceValues.length = workspaceLayout.workspaceLength)
    (workspaceTokenCount : workspaceLayout.tokenCount = tokens.length)
    (grammarBacking : caller.cellEntry? grammarCell = some {
      id := grammarCell, value := some (.array (signedI32Values words)) })
    (tokenStorage : I32Prefix caller tokensCell tokenCapacity (tokens.map Int.ofNat))
    (workspaceBacking : caller.cellEntry? workspaceCell = some {
      id := workspaceCell, value := some (.array (signedI32Values workspaceValues)) })
    (grammarWorkspaceDistinct : grammarCell ≠ workspaceCell)
    (tokensWorkspaceDistinct : tokensCell ≠ workspaceCell) :
    RecognizerCallExecution grammarLayout grammar words tokens workspaceLayout
      workspaceValues grammarCell tokensCell workspaceCell caller caller
      [.local region.grammarId, .local region.grammarLengthId,
       .local region.locals.destination, .local region.locals.count,
       .local region.workspaceId, .local region.workspaceLengthId] :=
  executeRecognizerCall
    (recognition_arguments region grammarLocal grammarLengthLocal tokensLocal
      tokenCountLocal workspaceLocal workspaceLengthLocal)
    (parserRecognizeCallee_entry wellFormed grammarEncoded grammarWellFormed
      wordsI32 tokensI32 workspaceLength workspaceTokenCount grammarBacking
      tokenStorage workspaceBacking grammarWorkspaceDistinct tokensWorkspaceDistinct)

/-- Tie the execution result to the region's callee, not just its arguments. -/
theorem recognition_region_evaluates
    (region : BufferCopy.Recognition)
    (callee : region.functionId = extractedParserRecognizeFunction.id)
    (execution : RecognizerCallExecution grammarLayout grammar words tokens workspaceLayout
      workspaceValues grammarCell tokensCell workspaceCell caller caller
      [.local region.grammarId, .local region.grammarLengthId,
       .local region.locals.destination, .local region.locals.count,
       .local region.workspaceId, .local region.workspaceLengthId]) :
    Evaluates verifiedParserCore caller
      (.call region.functionId [.local region.grammarId, .local region.grammarLengthId,
       .local region.locals.destination, .local region.locals.count,
       .local region.workspaceId, .local region.workspaceLengthId])
      execution.outcome.resultValue execution.after := by
  rw [callee]
  exact execution.evaluation

end Lanius.Extraction.ParserRecognize
