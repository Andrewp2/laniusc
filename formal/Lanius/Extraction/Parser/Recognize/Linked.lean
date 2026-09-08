import Lanius.Extraction.VerifiedFrontend.Parser.Soundness
import Lanius.Semantics.Relocation.Link
import Lanius.Semantics.Relocation.Ownership
import Lanius.Extraction.Parser.Recognize.Caller
import Lanius.Separation.Relocation

namespace Lanius.Extraction.ParserRecognize

open Lanius.Core Lanius.Semantics Lanius.Compiler.Parser Lanius.Properties Lanius.Separation
open Lanius.Extraction.ParserAccessors Lanius.Extraction.ParserFind

theorem RecognizerCallExecution.linked_workspace
    (execution : RecognizerCallExecution grammarLayout grammar words tokens
      workspaceLayout workspaceValues grammarCell tokensCell workspaceCell
      before afterArguments arguments) (symbols : Core.Relocation.Symbols) :
    RecognizerWorkspaceArtifact workspaceLayout execution.finalWorkspace
      execution.finalWorkspaceValues workspaceCell
      (Semantics.Relocation.state symbols execution.after) :=
  execution.workspaceArtifact.relocated symbols

/-- Decode a parse result using its linked structure identifier. -/
def linkedParseResultStatus? (typeId : Lanius.TypeId) : Value → Option Int
  | .structure id fields =>
      if id = typeId then
        match fields with
        | [.signed .i32 status, _, _, _] => some status
        | _ => none
      else none
  | _ => none

theorem linkedParseResultStatus_relocated (symbols : Core.Relocation.Symbols)
    (injective : Function.Injective symbols.typeId) (result : Value) :
    linkedParseResultStatus? (symbols.typeId 0) (Core.Relocation.value symbols result) =
      parseResultStatus? result := by
  cases result <;> try rfl
  case «structure» id fields =>
    by_cases same : id = 0
    case neg =>
      have different : symbols.typeId id ≠ symbols.typeId 0 :=
        fun equal => same (injective equal)
      cases id with
      | zero => exact (same rfl).elim
      | succ id => simp [linkedParseResultStatus?, Core.Relocation.value,
          different, parseResultStatus?]
    subst id
    simp only [Core.Relocation.value, linkedParseResultStatus?, if_pos rfl]
    cases fields with
    | nil => rfl
    | cons first rest =>
      cases rest with
      | nil =>
        cases first <;> try rfl
        case signed width status => cases width <;> rfl
      | cons second rest =>
        cases rest with
        | nil =>
          cases first <;> try rfl
          case signed width status => cases width <;> rfl
        | cons third rest =>
          cases rest with
          | nil =>
            cases first <;> try rfl
            case signed width status => cases width <;> rfl
          | cons fourth rest =>
            cases rest with
            | cons fifth rest =>
              cases first <;> try rfl
              case signed width status => cases width <;> rfl
            | nil =>
              cases first <;> try rfl
              case signed width status =>
                cases width <;> try rfl

/-- Transport the public parser execution, including its semantic outcome,
    into a program with checked symbol relocation. No parser computation is
    rerun to establish the linked execution. -/
theorem RecognizerCallExecution.linked_evaluation
    (execution : RecognizerCallExecution grammarLayout grammar words tokens
      workspaceLayout workspaceValues grammarCell tokensCell workspaceCell
      before afterArguments arguments)
    (link : Semantics.Relocation.Link allowed symbols verifiedParserCore linked)
    (injective : Function.Injective symbols.typeId)
    (closed : Dependencies.expression allowed
      (.call extractedParserRecognizeFunction.id arguments) = true) :
    Evaluates linked (Semantics.Relocation.state symbols before)
      (Core.Relocation.expression symbols
        (.call extractedParserRecognizeFunction.id arguments))
      (Core.Relocation.value symbols execution.outcome.resultValue)
      (Semantics.Relocation.state symbols execution.after) :=
  link.evaluates injective execution.evaluation closed

/-- Success decoded from the linked value entails declarative recognition. -/
theorem RecognizerCallExecution.linked_success
    (execution : RecognizerCallExecution grammarLayout grammar words tokens
      workspaceLayout workspaceValues grammarCell tokensCell workspaceCell
      before afterArguments arguments)
    (link : Semantics.Relocation.Link allowed symbols verifiedParserCore linked)
    (injective : Function.Injective symbols.typeId)
    (closed : Dependencies.expression allowed
      (.call extractedParserRecognizeFunction.id arguments) = true)
    (success : linkedParseResultStatus? (symbols.typeId 0)
      (Core.Relocation.value symbols execution.outcome.resultValue) = some 0) :
    Evaluates linked (Semantics.Relocation.state symbols before)
      (Core.Relocation.expression symbols
        (.call extractedParserRecognizeFunction.id arguments))
      (Core.Relocation.value symbols execution.outcome.resultValue)
      (Semantics.Relocation.state symbols execution.after) ∧
    RecognizesInput grammar tokens := by
  rw [linkedParseResultStatus_relocated symbols injective] at success
  exact ⟨execution.linked_evaluation link injective closed,
    execution.success_recognizesInput success⟩

/-- Execute the real linked recognizer from caller locals and storage. Symbol
coordinates and parameter resources are constructed internally. Retain the
complete semantic outcome and physical workspace, including resource failure,
so later tree construction need not assume an independent valid parse. -/
theorem recognize_region_at
    (region : BufferCopy.Recognition)
    (link : Semantics.Relocation.Link allowed symbols verifiedParserCore linked)
    (injective : Function.Injective symbols.typeId)
    (inverseType : Lanius.TypeId → Lanius.TypeId)
    (inverse : Function.RightInverse inverseType symbols.typeId)
    (retained : allowed extractedParserRecognizeFunction.id = true)
    (callee : region.functionId = symbols.functionId extractedParserRecognizeFunction.id)
    (grammarLocal : caller.local? region.grammarId = some (parserGrammarValue words grammarCell))
    (grammarLengthLocal : caller.local? region.grammarLengthId = some (.signed .i32 (Int.ofNat words.length)))
    (tokensLocal : caller.local? region.locals.destination = some (parserTokenBufferValue tokenCapacity tokensCell))
    (tokenCountLocal : caller.local? region.locals.count = some (.signed .i32 (Int.ofNat tokens.length)))
    (workspaceLocal : caller.local? region.workspaceId = some (workspaceValue workspaceValues workspaceCell))
    (workspaceLengthLocal : caller.local? region.workspaceLengthId = some (.signed .i32 (Int.ofNat workspaceValues.length)))
    (wellFormed : StateWellFormed caller)
    (grammarEncoded : EncodesGrammar grammarLayout grammar words)
    (grammarWellFormed : grammar.WellFormed)
    (wordsI32 : words.length ≤ 2147483647) (tokensI32 : tokens.length ≤ 2147483647)
    (workspaceLength : workspaceValues.length = workspaceLayout.workspaceLength)
    (workspaceTokenCount : workspaceLayout.tokenCount = tokens.length)
    (grammarBacking : caller.cellEntry? grammarCell = some {
      id := grammarCell, value := some (.array (signedI32Values words)) })
    (tokenStorage : I32Prefix caller tokensCell tokenCapacity (tokens.map Int.ofNat))
    (workspaceBacking : caller.cellEntry? workspaceCell = some {
      id := workspaceCell, value := some (.array (signedI32Values workspaceValues)) })
    (grammarWorkspaceDistinct : grammarCell ≠ workspaceCell)
    (tokensWorkspaceDistinct : tokensCell ≠ workspaceCell) :
    ∃ completion, ∃ (outcome : RecognizerInitialContinuationOutcome grammarLayout grammar words tokens workspaceLayout completion),
      ∃ finalWorkspace finalValues after,
      Evaluates linked caller (.call region.functionId [.local region.grammarId, .local region.grammarLengthId,
        .local region.locals.destination, .local region.locals.count, .local region.workspaceId,
        .local region.workspaceLengthId]) (Core.Relocation.value symbols outcome.resultValue) after ∧
      outcome.workspaceAgrees finalWorkspace ∧
      WorkspaceAppendClosure workspaceLayout.capacity emptyWorkspace finalWorkspace ∧
      RecognizerWorkspaceArtifact workspaceLayout finalWorkspace finalValues workspaceCell after ∧
      CellEffect (CellSet.singleton workspaceCell) caller after := by
  let unrelocate : Core.Relocation.Symbols := ⟨inverseType, id, id⟩
  have restored : Semantics.Relocation.state symbols (Semantics.Relocation.state unrelocate caller) = caller :=
    Semantics.Relocation.state_leftInverse symbols unrelocate inverse caller
  have relocatedLocal {id : Lanius.VarId} {value : Value}
      (found : caller.local? id = some value) (fixed : Core.Relocation.value unrelocate value = value) :
      (Semantics.Relocation.state unrelocate caller).local? id = some value := by
    simp only [Semantics.Relocation.localValue, found, Option.map_some, fixed]
  have relocatedWords {cell : Lanius.CellId} {values : List Int}
      (found : caller.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) }) :
      (Semantics.Relocation.state unrelocate caller).cellEntry? cell =
        some { id := cell, value := some (.array (signedI32Values values)) } := by
    simp only [Semantics.Relocation.cellEntry, found, Option.map_some, Semantics.Relocation.cell,
      Core.Relocation.value, Semantics.Relocation.signedI32Values_fixed]
  have relocatedTokens : I32Prefix (Semantics.Relocation.state unrelocate caller) tokensCell tokenCapacity
      (tokens.map Int.ofNat) := by
    obtain ⟨unused, length, backing⟩ := tokenStorage
    exact ⟨unused, length, relocatedWords backing⟩
  have inverseWF := Semantics.Relocation.state_wellFormed unrelocate wellFormed
  let execution := executeRecognitionRegion region
    (relocatedLocal grammarLocal rfl) (relocatedLocal grammarLengthLocal rfl)
    (relocatedLocal tokensLocal rfl) (relocatedLocal tokenCountLocal rfl)
    (relocatedLocal workspaceLocal rfl) (relocatedLocal workspaceLengthLocal rfl)
    inverseWF grammarEncoded grammarWellFormed wordsI32 tokensI32 workspaceLength workspaceTokenCount
    (relocatedWords grammarBacking) relocatedTokens (relocatedWords workspaceBacking)
    grammarWorkspaceDistinct tokensWorkspaceDistinct
  have closed : Dependencies.expression allowed (.call extractedParserRecognizeFunction.id
      [.local region.grammarId, .local region.grammarLengthId, .local region.locals.destination,
        .local region.locals.count, .local region.workspaceId, .local region.workspaceLengthId]) = true := by
    simp only [Dependencies.expression, Dependencies.expressions, retained, Bool.true_and]
  have evaluated := execution.linked_evaluation link injective closed
  rw [restored] at evaluated
  have effect := (CellEffect.ofModifiesOnly execution.effect (execution.preservesWellFormed inverseWF)).relocate symbols
  rw [restored] at effect
  refine ⟨execution.outcomeCompletion, execution.outcome, execution.finalWorkspace, execution.finalWorkspaceValues,
    Semantics.Relocation.state symbols execution.after, ?_, execution.outcomeWorkspace, execution.growth,
    execution.linked_workspace symbols, effect⟩
  simpa only [Core.Relocation.expression, Core.Relocation.expressions, callee] using evaluated

end Lanius.Extraction.ParserRecognize
