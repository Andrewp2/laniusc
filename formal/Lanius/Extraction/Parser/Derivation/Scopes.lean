import Lanius.Extraction.Parser.Derivation.Reads

namespace Lanius.Extraction.ParserRecognize

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler.Parser

/-- A lexical temporary cannot overwrite the retained recognizer workspace. -/
theorem RecognizerWorkspaceArtifact.bind_local
    (artifact : RecognizerWorkspaceArtifact layout workspace values workspaceCell before)
    (wellFormed : StateWellFormed before) (localId : VarId) (value : Value) :
    RecognizerWorkspaceArtifact layout workspace values workspaceCell
      (before.bindLocal localId value) := by
  refine ⟨artifact.workspaceLength, artifact.workspaceEncoded, ?_⟩
  exact ((bindLocal_effect before localId value).oldCells workspaceCell
    (StateWellFormed.cell_lt_next_of_entry wellFormed artifact.workspaceBacking)
    (by simp [CellSet.empty])).trans artifact.workspaceBacking

/-- Run a real state-field accessor, enter its result's lexical scope, and
    close that scope after the continuation. The continuation receives both
    workspace ownership and the initializer's frame; accessor execution is
    derived here, not required as a premise. -/
theorem RecognizerWorkspaceArtifact.let_field
    {post : State → Prop}
    (artifact : RecognizerWorkspaceArtifact layout workspace values workspaceCell before)
    (wellFormed : StateWellFormed before)
    (found : workspace.state? stateId = some state) (fieldBound : field < stateWords)
    (workspaceLocal : before.local? workspaceId = some
      (.slice parserI32Type workspaceCell [] 0 values.length))
    (baseLocal : before.local? baseId = some
      (.signed .i32 (Int.ofNat (stateBase layout.tokenCount))))
    (currentLocal : before.local? currentId = some (.signed .i32 (Int.ofNat stateId)))
    (selector : verifiedParserCore.constant? selectorId = some {
      id := selectorId, type := parserI32Type, value := .signed .i32 (Int.ofNat field) })
    (continuation : ∀ initialized,
      CellEffect CellSet.empty before initialized →
      StateWellFormed (initialized.bindLocal localId
        (.signed .i32 (stateFieldValue workspace stateId state field))) →
      RecognizerWorkspaceArtifact layout workspace values workspaceCell
        (initialized.bindLocal localId (.signed .i32 (stateFieldValue workspace stateId state field))) →
      ∃ completed,
        Executes verifiedParserCore
          (initialized.bindLocal localId (.signed .i32 (stateFieldValue workspace stateId state field)))
          body completion completed ∧
        post (restoreLocals initialized completed) ∧
        CellEffect writes
          (initialized.bindLocal localId (.signed .i32 (stateFieldValue workspace stateId state field)))
          completed) :
    ∃ after, Executes verifiedParserCore before
      (.letLocal localId parserI32Type
        (.call extractedParserStateValueFunction.id
          [.local workspaceId, .local baseId, .local currentId, .constant selectorId]) body)
      completion after ∧ post after ∧ CellEffect writes before after := by
  obtain ⟨initialized, read, initializedArtifact, effect⟩ :=
    artifact.read_field_locals wellFormed found fieldBound workspaceLocal baseLocal currentLocal selector
  obtain ⟨completed, execution, result, bodyEffect⟩ := continuation initialized effect
    (bindLocal_preserves_well_formed _ _ _ effect.wellFormed)
    (initializedArtifact.bind_local effect.wellFormed _ _)
  exact ⟨_, executesLetLocal read execution, result,
    (effect.weaken CellSet.empty_subset).trans
      (CellEffect.closeLocal initialized localId _ effect.wellFormed bodyEffect)⟩

end Lanius.Extraction.ParserRecognize
