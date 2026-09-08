import Lanius.Extraction.Parser.Workspace.Artifact
import Lanius.Semantics.Relocation.Link
import Lanius.Extraction.VerifiedFrontend.Parser.Reads
import Lanius.Separation.SliceStore

namespace Lanius.Extraction.ParserRecognize

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.CallContracts
open Lanius.Separation
open Lanius.Compiler.Parser

/-- Exact standalone Core declaration for `STATE_CHILD_KIND`; relocation
    transports this constant along with the accessor in a linked program. -/
theorem verifiedParser_child_kind_selector :
    verifiedParserCore.constant? 36 = some {
      id := 36, type := .scalar (.signed .i32), value := .signed .i32 8 } := by
  rfl

theorem child_kind_selector_evaluates (runtime : State) :
    Evaluates verifiedParserCore runtime (.constant 36) (.signed .i32 8) runtime :=
  evaluatesConstant verifiedParser_child_kind_selector

/-- Read any retained state field through the real accessor in a checked
    linked program, using the workspace artifact returned by recognition. -/
theorem RecognizerWorkspaceArtifact.read_linked_field
    (artifact : RecognizerWorkspaceArtifact layout workspace values workspaceCell afterArguments)
    (found : workspace.state? stateId = some state)
    (fieldBound : field < stateWords)
    (wellFormed : StateWellFormed afterArguments)
    (argumentsResult : ArgumentsEvaluateTo verifiedParserCore before arguments [
      .slice parserI32Type workspaceCell [] 0 values.length,
      .signed .i32 (Int.ofNat (stateBase layout.tokenCount)),
      .signed .i32 (Int.ofNat stateId),
      .signed .i32 (Int.ofNat field)] afterArguments)
    (link : Semantics.Relocation.Link allowed symbols verifiedParserCore linked)
    (injective : Function.Injective symbols.typeId)
    (closed : Dependencies.expression allowed
      (.call extractedParserStateValueFunction.id arguments) = true) :
    ∃ after, Evaluates linked (Semantics.Relocation.state symbols before)
      (Core.Relocation.expression symbols
        (.call extractedParserStateValueFunction.id arguments))
      (.signed .i32 (stateFieldValue workspace stateId state field))
      (Semantics.Relocation.state symbols after) ∧
      StateWellFormed after ∧
      ModifiesOnly CellSet.empty afterArguments after ∧
      RecognizerWorkspaceArtifact layout workspace values workspaceCell
        (Semantics.Relocation.state symbols after) := by
  have read := extractedParserStateValueCall_reads_encoded layout workspace values workspaceCell
    artifact.workspaceLength artifact.workspaceEncoded state stateId field found fieldBound
    before afterArguments arguments wellFormed argumentsResult artifact.workspaceBacking
  have transported := link.evaluates injective read closed
  let after := parserStateValueCallState afterArguments
    (.slice parserI32Type workspaceCell [] 0 values.length)
    (Int.ofNat (stateBase layout.tokenCount)) (Int.ofNat stateId) (Int.ofNat field)
  have effect : ModifiesOnly CellSet.empty afterArguments after :=
    parserStateValueCallState_effect
  have preserved : RecognizerWorkspaceArtifact layout workspace values workspaceCell after := {
    workspaceLength := artifact.workspaceLength
    workspaceEncoded := artifact.workspaceEncoded
    workspaceBacking := effect.preserves_entry wellFormed artifact.workspaceBacking
      (by simp [CellSet.empty])
  }
  exact ⟨after, transported, parserStateValueCallState_well_formed wellFormed,
    effect, preserved.relocated symbols⟩

/-- The real field accessor remains executable after output-only writes.
    Its first three arguments and workspace backing are derived from the
    entry state; only the field-selector expression is supplied separately. -/
theorem RecognizerWorkspaceArtifact.read_field_after_output
    (artifact : RecognizerWorkspaceArtifact layout workspace values workspaceCell before)
    (wellFormed : StateWellFormed before)
    (found : workspace.state? stateId = some state)
    (fieldBound : field < stateWords)
    (distinct : outputCell ≠ workspaceCell)
    (workspaceLocal : before.local? workspaceId = some
      (.slice parserI32Type workspaceCell [] 0 values.length))
    (baseLocal : before.local? baseId = some
      (.signed .i32 (Int.ofNat (stateBase layout.tokenCount))))
    (currentLocal : before.local? currentId = some (.signed .i32 (Int.ofNat stateId)))
    (backing : before.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values outputValues)) })
    (effect : CellEffect (CellSet.singleton outputCell) before runtime)
    (fieldRead : Evaluates verifiedParserCore runtime fieldExpression
      (.signed .i32 (Int.ofNat field)) runtime) :
    ∃ after, Evaluates verifiedParserCore runtime
      (.call extractedParserStateValueFunction.id
        [.local workspaceId, .local baseId, .local currentId, fieldExpression])
      (.signed .i32 (stateFieldValue workspace stateId state field)) after ∧
      CellEffect CellSet.empty runtime after := by
  have workspaceStill := effect.preserves_local_of_distinct_value wellFormed workspaceLocal backing
    (by simp)
  have baseStill := effect.preserves_local_of_distinct_value wellFormed baseLocal backing (by simp)
  have currentStill := effect.preserves_local_of_distinct_value wellFormed currentLocal backing (by simp)
  have backingStill := effect.preserves_entry wellFormed artifact.workspaceBacking
    (by simpa [CellSet.singleton] using Ne.symm distinct)
  have localRead {localId : Lanius.VarId} {value : Value}
      (localValue : runtime.local? localId = some value) :
      Evaluates verifiedParserCore runtime (.local localId) value runtime :=
    ⟨1, evalLocal_of_local 0 verifiedParserCore runtime localId value localValue⟩
  have arguments := ArgumentsEvaluateTo.cons (localRead workspaceStill)
    (.cons (localRead baseStill) (.cons (localRead currentStill)
      (.cons fieldRead (.nil verifiedParserCore runtime))))
  have read := extractedParserStateValueCall_reads_encoded layout workspace values workspaceCell
    artifact.workspaceLength artifact.workspaceEncoded state stateId field found fieldBound
    runtime runtime _ effect.wellFormed arguments backingStill
  exact ⟨_, read, CellEffect.ofModifiesOnly parserStateValueCallState_effect
    (parserStateValueCallState_well_formed effect.wellFormed)⟩

/-- Read a field directly from caller locals and a checked constant selector. -/
theorem RecognizerWorkspaceArtifact.read_field_locals
    (artifact : RecognizerWorkspaceArtifact layout workspace values workspaceCell before)
    (wellFormed : StateWellFormed before)
    (found : workspace.state? stateId = some state) (fieldBound : field < stateWords)
    (workspaceLocal : before.local? workspaceId = some
      (.slice parserI32Type workspaceCell [] 0 values.length))
    (baseLocal : before.local? baseId = some (.signed .i32 (Int.ofNat (stateBase layout.tokenCount))))
    (currentLocal : before.local? currentId = some (.signed .i32 (Int.ofNat stateId)))
    (selector : verifiedParserCore.constant? selectorId = some {
      id := selectorId, type := parserI32Type, value := .signed .i32 (Int.ofNat field) }) :
    ∃ after, Evaluates verifiedParserCore before
      (.call extractedParserStateValueFunction.id
        [.local workspaceId, .local baseId, .local currentId, .constant selectorId])
      (.signed .i32 (stateFieldValue workspace stateId state field)) after ∧
      RecognizerWorkspaceArtifact layout workspace values workspaceCell after ∧
      CellEffect CellSet.empty before after := by
  have localRead {localId : Lanius.VarId} {value : Value}
      (localValue : before.local? localId = some value) :
      Evaluates verifiedParserCore before (.local localId) value before :=
    ⟨1, evalLocal_of_local 0 verifiedParserCore before localId value localValue⟩
  have arguments := ArgumentsEvaluateTo.cons (localRead workspaceLocal)
    (.cons (localRead baseLocal) (.cons (localRead currentLocal)
      (.cons (evaluatesConstant selector) (.nil verifiedParserCore before))))
  have read := extractedParserStateValueCall_reads_encoded layout workspace values workspaceCell
    artifact.workspaceLength artifact.workspaceEncoded state stateId field found fieldBound
    before before _ wellFormed arguments artifact.workspaceBacking
  have effect := CellEffect.ofModifiesOnly
    (parserStateValueCallState_effect (state := before)
      (workspaceValue := .slice parserI32Type workspaceCell [] 0 values.length)
      (base := Int.ofNat (stateBase layout.tokenCount)) (stateId := Int.ofNat stateId)
      (field := Int.ofNat field))
    (parserStateValueCallState_well_formed wellFormed)
  refine ⟨_, read, ?_, effect⟩
  exact {
    workspaceLength := artifact.workspaceLength
    workspaceEncoded := artifact.workspaceEncoded
    workspaceBacking := effect.empty_preserves_entry wellFormed artifact.workspaceBacking
  }

end Lanius.Extraction.ParserRecognize
