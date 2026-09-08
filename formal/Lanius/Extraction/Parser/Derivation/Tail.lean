import Lanius.Extraction.Parser.Derivation.Writes
import Lanius.Extraction.Parser.Derivation.Cursor
import Lanius.Extraction.Parser.Derivation.Call

namespace Lanius.Extraction.ParserDerivation

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler.Parser Lanius.Extraction.ParserRecognize

/-- Execute all post-guard mutations in one reader iteration, with no
    assumed operand or substatement executions. This is in standalone parser
    coordinates; the checked link must transport it to the current program. -/
theorem ChildStores.execute_tail {workspace : LogicalWorkspace} {slot : Nat}
    (stores : ChildStores) (tail : CheckedCursorTail stores)
    (accessor : stores.accessor = extractedParserStateValueFunction.id)
    (selector : stores.selector = 36)
    (artifact : RecognizerWorkspaceArtifact layout workspace workspaceValues workspaceCell before)
    (wellFormed : StateWellFormed before)
    (found : workspace.state? stateId = some state)
    (distinctBuffers : outputCell ≠ workspaceCell)
    (room : slot + 2 < values.length) (slotBound : slot + 2 ≤ 2147483647)
    (outputLocal : before.local? stores.output = some (.slice parserI32Type outputCell [] 0 values.length))
    (workspaceLocal : before.local? stores.workspace = some
      (.slice parserI32Type workspaceCell [] 0 workspaceValues.length))
    (baseLocal : before.local? stores.base = some (.signed .i32 (Int.ofNat (stateBase layout.tokenCount))))
    (slotLocal : before.local? stores.slot = some (.signed .i32 (Int.ofNat slot)))
    (tagLocal : before.local? stores.tag = some (.signed .i32 (childTag state.child)))
    (payloadLocal : before.local? stores.payload = some (.signed .i32 (childPayload state.child)))
    (currentOwned : (Assertion.localPointsTo stores.current currentCell
      (some (.signed .i32 (Int.ofNat stateId)))).holds before)
    (remainingOwned : (Assertion.localPointsTo tail.remaining remainingCell
      (some (.signed .i32 (Int.ofNat (remaining + 1))))).holds before)
    (distinctCursors : currentCell ≠ remainingCell)
    (previousLocal : before.local? tail.previous = some (.signed .i32 previous))
    (remainingBound : remaining + 1 ≤ 2147483647)
    (backing : before.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values values)) }) :
    ∃ after, Executes verifiedParserCore before stores.body .next after ∧
      (Assertion.localPointsTo stores.current currentCell (some (.signed .i32 previous))).holds after ∧
      (Assertion.localPointsTo tail.remaining remainingCell
        (some (.signed .i32 (Int.ofNat remaining)))).holds after ∧
      RecognizerWorkspaceArtifact layout workspace workspaceValues workspaceCell after ∧
      after.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values
          (((values.set slot (childTag state.child)).set (slot + 1)
            (childPayload state.child)).set (slot + 2) (childKind state.child)))) } ∧
      CellEffect (CellSet.union (CellSet.singleton outputCell)
        (CellSet.union (CellSet.singleton currentCell) (CellSet.singleton remainingCell))) before after := by
  have currentLocal := Assertion.localPointsTo_local _ _ _ _ currentOwned
  obtain ⟨middle, stored, backingAfter, artifactAfter, _, storeEffect⟩ :=
    artifact.store_child wellFormed found distinctBuffers room slotBound outputLocal workspaceLocal
      baseLocal currentLocal slotLocal tagLocal payloadLocal backing
  have fragment : Executes verifiedParserCore before stores.fragment .next middle := by
    simpa only [ChildStores.fragment, ChildStores.store, accessor, selector] using stored
  have currentDifferent : currentCell ≠ outputCell :=
    local_cell_ne_of_distinct_value currentLocal backing (by simp) currentOwned.1
  have remainingLocal := Assertion.localPointsTo_local _ _ _ _ remainingOwned
  have remainingDifferent : remainingCell ≠ outputCell :=
    local_cell_ne_of_distinct_value remainingLocal backing (by simp) remainingOwned.1
  have currentStill := storeEffect.preserves_localPointsTo wellFormed currentOwned currentDifferent
  have remainingStill := storeEffect.preserves_localPointsTo wellFormed remainingOwned remainingDifferent
  have previousStill := storeEffect.preserves_local_of_distinct_value wellFormed previousLocal backing (by simp)
  obtain ⟨after, updated, currentAfter, remainingAfter, finalArtifact, finalBacking, updateEffect⟩ :=
    artifactAfter.update_cursor storeEffect.wellFormed currentStill remainingStill distinctCursors
      previousStill remainingBound backingAfter
  have continuation : Executes verifiedParserCore middle stores.rest .next after := by
    rw [tail.exactTail]
    exact updated
  exact ⟨after, stores.continue fragment continuation, currentAfter, remainingAfter,
    finalArtifact, finalBacking, (storeEffect.weaken CellSet.subset_union_left).trans
      (updateEffect.weaken CellSet.subset_union_right)⟩

end Lanius.Extraction.ParserDerivation
