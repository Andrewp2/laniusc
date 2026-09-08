import Lanius.Extraction.Parser.Derivation.Slot
import Lanius.Extraction.Parser.Derivation.Guards

namespace Lanius.Extraction.ParserDerivation

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler.Parser Lanius.Extraction.ParserRecognize

/-- Source section after the three child-field initializers, in standalone
    parser symbol coordinates. -/
def guardedStores (stores : ChildStores) (tail : CheckedCursorTail stores)
    (offsetId tokenCountId : VarId) : Stmt :=
  let negativeOne := Expr.unary .negate (.value (.signed .i32 1))
  let reject := Stmt.sequence (.returnValue (some negativeOne)) .skip
  let guard := fun condition => Stmt.ifThenElse condition reject .skip
  .sequence
    (guard (.binary .logicalOr
      (.binary .logicalOr (.binary .lessEqual (.local tail.previous) negativeOne)
        (.binary .greaterEqual (.local tail.previous) (.local stores.current)))
      (.binary .lessEqual (.local stores.payload) negativeOne)))
    (.sequence
      (.ifThenElse (.binary .equal (.local stores.tag) (.constant 38))
        (.sequence (guard (.binary .greaterEqual (.local stores.payload) (.local tokenCountId))) .skip)
        (.sequence (guard (.binary .logicalOr
          (.binary .notEqual (.local stores.tag) (.constant 39))
          (.binary .greaterEqual (.local stores.payload) (.local stores.current)))) .skip))
      (.letLocal stores.slot parserI32Type
        (.binary .add (.binary .add (.local offsetId) (.value (.signed .i32 4)))
          (.binary .multiply
            (.binary .subtract (.local tail.remaining) (.value (.signed .i32 1)))
            (.value (.signed .i32 3)))) stores.body))

/-- This section is definitionally the suffix of the inspected reader
    iteration, not a second implementation of the guarded algorithm. -/
theorem iterationBody_guardedStores (stores : ChildStores) (tail : CheckedCursorTail stores)
    (production origin offsetId tokenCountId : VarId) :
    let readField := fun field => Expr.call stores.accessor
      [.local stores.workspace, .local stores.base, .local stores.current, .constant (28 + field)]
    let mismatch := fun field localId => Expr.binary .notEqual (readField field) (.local localId)
    let reject := Stmt.sequence
      (.returnValue (some (.unary .negate (.value (.signed .i32 1))))) .skip
    iterationBody stores tail production origin offsetId tokenCountId 28 =
      .sequence
        (.ifThenElse (.binary .logicalOr
          (.binary .logicalOr (mismatch 1 tail.remaining) (mismatch 0 production))
          (mismatch 2 origin)) reject .skip)
        (.letLocal tail.previous parserI32Type (readField 5)
          (.letLocal stores.tag parserI32Type (readField 6)
            (.letLocal stores.payload parserI32Type (readField 7)
              (guardedStores stores tail offsetId tokenCountId)))) := by
  rfl

/-- Sound backpointers discharge both rejection guards. No guard result,
    slot calculation, or store execution is assumed. -/
theorem ChildStores.execute_guarded {workspace : LogicalWorkspace}
    (stores : ChildStores) (tail : CheckedCursorTail stores)
    (accessor : stores.accessor = extractedParserStateValueFunction.id)
    (selector : stores.selector = 36)
    (artifact : RecognizerWorkspaceArtifact layout workspace workspaceValues workspaceCell before)
    (wellFormed : StateWellFormed before)
    (sound : WorkspaceBackpointersSound grammar tokens workspace)
    (found : workspace.state? stateId = some state) (nonempty : state.dot ≠ 0)
    (distinctBuffers : outputCell ≠ workspaceCell)
    (fits : offset + 4 + count * 3 ≤ values.length)
    (capacityBound : values.length ≤ 2147483647)
    (remainingBound : remaining + 1 ≤ count)
    (freshSlot : ∀ localId ∈ [stores.output, stores.workspace, stores.base,
      stores.tag, stores.payload, stores.current, tail.remaining, tail.previous],
      stores.slot ≠ localId)
    (offsetLocal : before.local? offsetId = some (.signed .i32 (Int.ofNat offset)))
    (tokenCountLocal : before.local? tokenCountId = some (.signed .i32 (Int.ofNat tokens.length)))
    (outputLocal : before.local? stores.output = some (.slice parserI32Type outputCell [] 0 values.length))
    (workspaceLocal : before.local? stores.workspace = some
      (.slice parserI32Type workspaceCell [] 0 workspaceValues.length))
    (baseLocal : before.local? stores.base = some (.signed .i32 (Int.ofNat (stateBase layout.tokenCount))))
    (tagLocal : before.local? stores.tag = some (.signed .i32 (childTag state.child)))
    (payloadLocal : before.local? stores.payload = some (.signed .i32 (childPayload state.child)))
    (currentOwned : (Assertion.localPointsTo stores.current currentCell
      (some (.signed .i32 (Int.ofNat stateId)))).holds before)
    (remainingOwned : (Assertion.localPointsTo tail.remaining remainingCell
      (some (.signed .i32 (Int.ofNat (remaining + 1))))).holds before)
    (distinctCursors : currentCell ≠ remainingCell)
    (previousLocal : before.local? tail.previous = some (.signed .i32 (previousValue state.previous)))
    (backing : before.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values values)) }) :
    let slot := offset + 4 + remaining * 3
    ∃ after, Executes verifiedParserCore before (guardedStores stores tail offsetId tokenCountId) .next after ∧
      (Assertion.localPointsTo stores.current currentCell
        (some (.signed .i32 (previousValue state.previous)))).holds after ∧
      (Assertion.localPointsTo tail.remaining remainingCell
        (some (.signed .i32 (Int.ofNat remaining)))).holds after ∧
      RecognizerWorkspaceArtifact layout workspace workspaceValues workspaceCell after ∧
      after.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values
          (((values.set slot (childTag state.child)).set (slot + 1)
            (childPayload state.child)).set (slot + 2) (childKind state.child)))) } ∧
      CellEffect (CellSet.union (CellSet.singleton outputCell)
        (CellSet.union (CellSet.singleton currentCell) (CellSet.singleton remainingCell))) before after := by
  obtain ⟨previousId, previous, pointer, _, earlier, _⟩ := sound.predecessor found nonempty
  have pointerValue : previousValue state.previous = (previousId : Int) := by
    simp [pointer, previousValue, encodeStateId]
  have childValid := sound.reader_child_guard found nonempty
  have currentLocal := Assertion.localPointsTo_local _ _ _ _ currentOwned
  have predecessor := predecessor_guard_executes (program := verifiedParserCore)
    previousLocal currentLocal payloadLocal
    (by rw [pointerValue]; omega)
    (by rw [pointerValue]; change (previousId : Int) < (stateId : Int); omega)
    (by omega)
  let reject := Stmt.sequence
    (.returnValue (some (.unary .negate (.value (.signed .i32 1))))) .skip
  have branch := child_branch_executes tagLocal payloadLocal tokenCountLocal currentLocal childValid.2 reject
  obtain ⟨after, execution, currentAfter, remainingAfter, artifactAfter, backingAfter, effect⟩ :=
    stores.execute_slot tail accessor selector artifact wellFormed found distinctBuffers fits capacityBound
      remainingBound freshSlot offsetLocal outputLocal workspaceLocal baseLocal tagLocal payloadLocal
      currentOwned remainingOwned distinctCursors previousLocal backing
  refine ⟨after, ?_, currentAfter, remainingAfter, artifactAfter, backingAfter, effect⟩
  exact executesSequence (executesIfFalse predecessor (executesSkip verifiedParserCore before))
    (executesSequence branch execution)

end Lanius.Extraction.ParserDerivation
