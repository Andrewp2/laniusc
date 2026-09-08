import Lanius.Extraction.Parser.Workspace.Artifact
import Lanius.Separation.LocalStore

namespace Lanius.Extraction.ParserRecognize

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

/-- Execute the loop's cursor updates. Array storage cannot alias either
    integer local, so both retained buffers survive without extra premises. -/
theorem RecognizerWorkspaceArtifact.update_cursor
    (artifact : RecognizerWorkspaceArtifact layout workspace workspaceValues workspaceCell before)
    (wellFormed : StateWellFormed before)
    (currentOwned : (Assertion.localPointsTo currentId currentCell
      (some (.signed .i32 current))).holds before)
    (remainingOwned : (Assertion.localPointsTo remainingId remainingCell
      (some (.signed .i32 (Int.ofNat (remaining + 1))))).holds before)
    (distinct : currentCell ≠ remainingCell)
    (previousLocal : before.local? previousId = some (.signed .i32 previous))
    (bounded : remaining + 1 ≤ 2147483647)
    (outputBacking : before.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values outputValues)) }) :
    ∃ after, Executes program before
      (.sequence (.expression (.assign .set (.local currentId) (.local previousId)))
        (.sequence (.expression (.assign .subtract (.local remainingId)
          (.value (.signed .i32 1)))) .skip)) .next after ∧
      (Assertion.localPointsTo currentId currentCell (some (.signed .i32 previous))).holds after ∧
      (Assertion.localPointsTo remainingId remainingCell
        (some (.signed .i32 (Int.ofNat remaining)))).holds after ∧
      RecognizerWorkspaceArtifact layout workspace workspaceValues workspaceCell after ∧
      after.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values outputValues)) } ∧
      CellEffect (CellSet.union (CellSet.singleton currentCell)
        (CellSet.singleton remainingCell)) before after := by
  have previousRead : Evaluates program before (.local previousId) (.signed .i32 previous) before :=
    ⟨1, evalLocal_of_local 0 program before previousId _ previousLocal⟩
  obtain ⟨middle, assigned, currentAfter, assignEffect⟩ :=
    evaluatesOwnedLocalUpdate wellFormed currentOwned previousRead (show
      evalAssignValue program.target .set (some (.signed .i32 current))
        (.signed .i32 previous) = .ok (.signed .i32 previous) from rfl)
  have remainingStill := assignEffect.preserves_localPointsTo wellFormed remainingOwned
    (by simpa [CellSet.singleton] using Ne.symm distinct)
  obtain ⟨after, decremented, remainingAfter, decrementEffect⟩ :=
    evaluatesDecrementOwnedI32Local assignEffect.wellFormed remainingStill bounded
  have effect := (assignEffect.weaken CellSet.subset_union_left).trans
    (decrementEffect.weaken CellSet.subset_union_right)
  have arrayUntouched {bufferCell : Lanius.CellId} {values : List Int}
      (backing : before.cellEntry? bufferCell = some {
        id := bufferCell, value := some (.array (signedI32Values values)) }) :
      ¬ CellSet.union (CellSet.singleton currentCell)
        (CellSet.singleton remainingCell) bufferCell := by
    intro written
    rcases written with same | same
    · change bufferCell = currentCell at same
      subst bufferCell
      simp [currentOwned.2] at backing
    · change bufferCell = remainingCell at same
      subst bufferCell
      simp [remainingOwned.2] at backing
  refine ⟨after, executesSequence (executesExpression assigned)
    (executesSequence (executesExpression decremented) (executesSkip program after)),
    decrementEffect.preserves_localPointsTo assignEffect.wellFormed currentAfter
      (by simpa [CellSet.singleton] using distinct), remainingAfter, ?_,
    effect.preserves_entry wellFormed outputBacking (arrayUntouched outputBacking), effect⟩
  exact {
    workspaceLength := artifact.workspaceLength
    workspaceEncoded := artifact.workspaceEncoded
    workspaceBacking := effect.preserves_entry wellFormed artifact.workspaceBacking
      (arrayUntouched artifact.workspaceBacking)
  }

end Lanius.Extraction.ParserRecognize
