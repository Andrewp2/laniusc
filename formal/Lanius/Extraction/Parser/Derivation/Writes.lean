import Lanius.Extraction.Parser.Workspace.Artifact
import Lanius.Separation.SliceStore
import Lanius.Extraction.VerifiedFrontend.Parser.Reads
import Lanius.Extraction.Parser.Derivation.Reads
import Lanius.Extraction.Parser.Derivation.Arithmetic

namespace Lanius.Extraction.ParserRecognize

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

/-- One concrete reader output store preserves the retained parser workspace.
    The right-hand side may call the read-only workspace accessor. -/
theorem RecognizerWorkspaceArtifact.store_output
    (artifact : RecognizerWorkspaceArtifact layout workspace workspaceValues workspaceCell before)
    (wellFormed : StateWellFormed before)
    (distinct : outputCell ≠ workspaceCell)
    (inBounds : index < values.length)
    (outputLocal : before.local? outputId = some
      (.slice (.scalar (.signed .i32)) outputCell [] 0 values.length))
    (indexResult : Evaluates program before indexExpression (.signed .i32 (Int.ofNat index)) before)
    (rightResult : Evaluates program before right (.signed .i32 replacement) afterRight)
    (rightEffect : CellEffect CellSet.empty before afterRight)
    (backing : before.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values values)) }) :
    ∃ after, Evaluates program before
        (.assign .set (.index (.local outputId) indexExpression) right) .unit after ∧
      after.cellEntry? outputCell = some {
        id := outputCell,
        value := some (.array (signedI32Values (values.set index replacement))) } ∧
      RecognizerWorkspaceArtifact layout workspace workspaceValues workspaceCell after ∧
      after.local? outputId = some
        (.slice (.scalar (.signed .i32)) outputCell [] 0 values.length) ∧
      CellEffect (CellSet.singleton outputCell) before after := by
  obtain ⟨after, executed, output, effect⟩ := evaluatesSliceStore program before afterRight
    values outputId indexExpression right outputCell index replacement wellFormed inBounds
    outputLocal indexResult rightResult rightEffect backing
  have outputStill := effect.preserves_local_of_distinct_value wellFormed outputLocal backing
    (by simp)
  refine ⟨after, executed, output, ?_, outputStill, effect⟩
  exact {
    workspaceLength := artifact.workspaceLength
    workspaceEncoded := artifact.workspaceEncoded
    workspaceBacking := effect.preserves_entry wellFormed artifact.workspaceBacking
      (by simpa [CellSet.singleton] using Ne.symm distinct)
  }

/-- Compose the reader's three consecutive stores. Operand contracts apply
    after output-only effects, so accessor allocations and earlier stores
    are included in the states at which later operands are evaluated. -/
theorem RecognizerWorkspaceArtifact.store_output_three
    (artifact : RecognizerWorkspaceArtifact layout workspace workspaceValues workspaceCell before)
    (wellFormed : StateWellFormed before)
    (distinct : outputCell ≠ workspaceCell)
    (room : slot + 2 < values.length)
    (outputLocal : before.local? outputId = some
      (.slice (.scalar (.signed .i32)) outputCell [] 0 values.length))
    (backing : before.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values values)) })
    (indices rights : Nat → Expr) (words : Nat → Int)
    (operands : ∀ offset, offset < 3 → ∀ runtime,
      CellEffect (CellSet.singleton outputCell) before runtime →
      Evaluates program runtime (indices offset) (.signed .i32 (Int.ofNat (slot + offset))) runtime ∧
      ∃ afterRight, Evaluates program runtime (rights offset) (.signed .i32 (words offset)) afterRight ∧
        CellEffect CellSet.empty runtime afterRight) :
    ∃ after, Executes program before
      (.sequence (.expression (.assign .set (.index (.local outputId) (indices 0)) (rights 0)))
        (.sequence (.expression (.assign .set (.index (.local outputId) (indices 1)) (rights 1)))
          (.expression (.assign .set (.index (.local outputId) (indices 2)) (rights 2)))))
      .next after ∧
      after.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values
          (((values.set slot (words 0)).set (slot + 1) (words 1)).set (slot + 2) (words 2)))) } ∧
      RecognizerWorkspaceArtifact layout workspace workspaceValues workspaceCell after ∧
      after.local? outputId = some
        (.slice (.scalar (.signed .i32)) outputCell [] 0 values.length) ∧
      CellEffect (CellSet.singleton outputCell) before after := by
  obtain ⟨index0, rightState0, right0, rightEffect0⟩ :=
    operands 0 (by decide) before (CellEffect.refl wellFormed)
  obtain ⟨after0, store0, backing0, artifact0, local0, effect0⟩ :=
    artifact.store_output wellFormed distinct (by omega) outputLocal index0 right0 rightEffect0 backing
  obtain ⟨index1, rightState1, right1, rightEffect1⟩ := operands 1 (by decide) after0 effect0
  obtain ⟨after1, store1, backing1, artifact1, local1, effect1⟩ :=
    artifact0.store_output effect0.wellFormed distinct
      (by simpa only [List.length_set] using (show slot + 1 < values.length by omega))
      (by simpa only [List.length_set] using local0) index1 right1 rightEffect1 backing0
  have combined := effect0.trans effect1
  obtain ⟨index2, rightState2, right2, rightEffect2⟩ := operands 2 (by decide) after1 combined
  obtain ⟨after2, store2, backing2, artifact2, local2, effect2⟩ :=
    artifact1.store_output combined.wellFormed distinct
      (by simpa only [List.length_set] using room)
      (by simpa only [List.length_set] using local1) index2 right2 rightEffect2 backing1
  refine ⟨after2, executesSequence (executesExpression store0)
    (executesSequence (executesExpression store1) (executesExpression store2)),
    backing2, artifact2, ?_, combined.trans effect2⟩
  simpa only [List.length_set] using local2

open Lanius.Compiler.Parser Lanius.CallContracts

/-- Copy a retained state field through the actual accessor and indexed store.
    The accessor's execution and allocation effect are proved, not assumed. -/
theorem RecognizerWorkspaceArtifact.copy_field
    (artifact : RecognizerWorkspaceArtifact layout workspace workspaceValues workspaceCell before)
    (wellFormed : StateWellFormed before)
    (found : workspace.state? stateId = some state)
    (fieldBound : field < stateWords)
    (distinct : outputCell ≠ workspaceCell)
    (inBounds : index < values.length)
    (outputLocal : before.local? outputId = some
      (.slice (.scalar (.signed .i32)) outputCell [] 0 values.length))
    (indexResult : Evaluates verifiedParserCore before indexExpression
      (.signed .i32 (Int.ofNat index)) before)
    (argumentsResult : ArgumentsEvaluateTo verifiedParserCore before arguments [
      .slice parserI32Type workspaceCell [] 0 workspaceValues.length,
      .signed .i32 (Int.ofNat (stateBase layout.tokenCount)),
      .signed .i32 (Int.ofNat stateId), .signed .i32 (Int.ofNat field)] before)
    (backing : before.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values values)) }) :
    ∃ after, Evaluates verifiedParserCore before
        (.assign .set (.index (.local outputId) indexExpression)
          (.call extractedParserStateValueFunction.id arguments)) .unit after ∧
      after.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values
          (values.set index (stateFieldValue workspace stateId state field)))) } ∧
      RecognizerWorkspaceArtifact layout workspace workspaceValues workspaceCell after ∧
      after.local? outputId = some
        (.slice (.scalar (.signed .i32)) outputCell [] 0 values.length) ∧
      CellEffect (CellSet.singleton outputCell) before after := by
  have read := extractedParserStateValueCall_reads_encoded layout workspace workspaceValues
    workspaceCell artifact.workspaceLength artifact.workspaceEncoded state stateId field
    found fieldBound before before arguments wellFormed argumentsResult artifact.workspaceBacking
  exact artifact.store_output wellFormed distinct inBounds outputLocal indexResult read
    (CellEffect.ofModifiesOnly parserStateValueCallState_effect
      (parserStateValueCallState_well_formed wellFormed)) backing

/-- The source-shaped child-store triple, including the real accessor for
    its last word. All index and local operand contracts are discharged. -/
theorem RecognizerWorkspaceArtifact.store_child
    (artifact : RecognizerWorkspaceArtifact layout workspace workspaceValues workspaceCell before)
    (wellFormed : StateWellFormed before)
    (found : workspace.state? stateId = some state)
    (distinct : outputCell ≠ workspaceCell)
    (room : slot + 2 < values.length) (slotBound : slot + 2 ≤ 2147483647)
    (outputLocal : before.local? outputId = some
      (.slice parserI32Type outputCell [] 0 values.length))
    (workspaceLocal : before.local? workspaceId = some
      (.slice parserI32Type workspaceCell [] 0 workspaceValues.length))
    (baseLocal : before.local? baseId = some (.signed .i32 (Int.ofNat (stateBase layout.tokenCount))))
    (currentLocal : before.local? currentId = some (.signed .i32 (Int.ofNat stateId)))
    (slotLocal : before.local? slotId = some (.signed .i32 (Int.ofNat slot)))
    (tagLocal : before.local? tagId = some (.signed .i32 (childTag state.child)))
    (payloadLocal : before.local? payloadId = some (.signed .i32 (childPayload state.child)))
    (backing : before.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values values)) }) :
    let indices := fun offset : Nat => if offset = 0 then Expr.local slotId else
      .binary .add (.local slotId) (.value (.signed .i32 (Int.ofNat offset)))
    let rights := fun offset : Nat => if offset = 0 then Expr.local tagId else
      if offset = 1 then .local payloadId else .call extractedParserStateValueFunction.id
        [.local workspaceId, .local baseId, .local currentId, .constant 36]
    let store := fun offset => Stmt.expression
      (.assign .set (.index (.local outputId) (indices offset)) (rights offset))
    ∃ after, Executes verifiedParserCore before
      (.sequence (store 0) (.sequence (store 1) (store 2))) .next after ∧
      after.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values
          (((values.set slot (childTag state.child)).set (slot + 1)
            (childPayload state.child)).set (slot + 2) (childKind state.child)))) } ∧
      RecognizerWorkspaceArtifact layout workspace workspaceValues workspaceCell after ∧
      after.local? outputId = some (.slice parserI32Type outputCell [] 0 values.length) ∧
      CellEffect (CellSet.singleton outputCell) before after := by
  dsimp only
  apply artifact.store_output_three wellFormed distinct room outputLocal backing
    (fun offset => if offset = 0 then Expr.local slotId else
      .binary .add (.local slotId) (.value (.signed .i32 (Int.ofNat offset))))
    (fun offset => if offset = 0 then Expr.local tagId else
      if offset = 1 then .local payloadId else .call extractedParserStateValueFunction.id
        [.local workspaceId, .local baseId, .local currentId, .constant 36])
    (fun offset => if offset = 0 then childTag state.child else
      if offset = 1 then childPayload state.child else childKind state.child)
  intro offset offsetBound runtime effect
  refine ⟨ParserDerivation.output_index_operand wellFormed slotLocal backing effect
    offset offsetBound slotBound, ?_⟩
  have alternatives : offset = 0 ∨ offset = 1 ∨ offset = 2 := by omega
  rcases alternatives with rfl | rfl | rfl
  · exact ⟨runtime, ParserDerivation.output_local_operand wellFormed tagLocal backing effect,
      CellEffect.refl effect.wellFormed⟩
  · exact ⟨runtime, ParserDerivation.output_local_operand wellFormed payloadLocal backing effect,
      CellEffect.refl effect.wellFormed⟩
  · exact artifact.read_field_after_output wellFormed found (show 8 < stateWords by decide)
      distinct workspaceLocal baseLocal currentLocal backing effect (child_kind_selector_evaluates runtime)

end Lanius.Extraction.ParserRecognize
