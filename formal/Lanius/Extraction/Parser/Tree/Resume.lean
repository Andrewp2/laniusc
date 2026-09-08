import Lanius.Extraction.Parser.Tree.Execution
import Lanius.Separation.LocalStore

namespace Lanius.Extraction.ParserTreeSource

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

private theorem local_read {id : Lanius.VarId} (found : before.local? id = some value) :
    Evaluates program before (.local id) value before :=
  ⟨1, evalLocal_of_local 0 program before id value found⟩

/-- The write footprint of the continuation after a recursive child returns. -/
def childResultWrites (recordsCell nodesCell wordsCell : CellId) : CellSet :=
  CellSet.union (CellSet.singleton recordsCell)
    (CellSet.union (CellSet.singleton nodesCell) (CellSet.singleton wordsCell))

/-- Execute the inspected continuation after a successful recursive result has
    been bound. This lemma proves the stores, not the recursive call itself;
    the whole-state induction must establish that call and this result value. -/
theorem CheckedVisit.resume_child (checked : CheckedVisit program)
    (wellFormed : StateWellFormed before)
    (resultLocal : before.local? 17 = some (resultValue checked.symbols.resultType 0 (Int.ofNat nodes) (Int.ofNat words)))
    (slotLocal : before.local? 16 = some (.signed .i32 (Int.ofNat slot)))
    (nodesOwned : (Assertion.localPointsTo 14 nodesCell (some (.signed .i32 oldNodes))).holds before)
    (wordsOwned : (Assertion.localPointsTo 13 wordsCell (some (.signed .i32 oldWords))).holds before)
    (distinctCursors : nodesCell ≠ wordsCell)
    (recordsLocal : before.local? 5 = some
      (.slice (.scalar (.signed .i32)) recordsCell [] 0 records.length))
    (recordsBacking : before.cellEntry? recordsCell = some {
      id := recordsCell, value := some (.array (signedI32Values records)) })
    (room : slot + 1 < records.length) (capacityBound : records.length ≤ 2147483647)
    (nonempty : 0 < nodes) (nodesBound : nodes ≤ 2147483647) :
    ∃ after, Executes program.core before (childResult checked.symbols) .next after ∧
      after.cellEntry? recordsCell = some {
        id := recordsCell, value := some (.array (signedI32Values (records.set (slot + 1) (Int.ofNat (nodes - 1))))) } ∧
      (Assertion.localPointsTo 14 nodesCell (some (.signed .i32 (Int.ofNat nodes)))).holds after ∧
      (Assertion.localPointsTo 13 wordsCell (some (.signed .i32 (Int.ofNat words)))).holds after ∧
      CellEffect (childResultWrites recordsCell nodesCell wordsCell) before after := by
  have nodesLocal := Assertion.localPointsTo_local _ _ _ _ nodesOwned
  have wordsLocal := Assertion.localPointsTo_local _ _ _ _ wordsOwned
  have nodesNotRecords : nodesCell ≠ recordsCell :=
    local_cell_ne_of_distinct_value nodesLocal recordsBacking (by intro impossible; cases impossible) nodesOwned.1
  have wordsNotRecords : wordsCell ≠ recordsCell :=
    local_cell_ne_of_distinct_value wordsLocal recordsBacking (by intro impossible; cases impossible) wordsOwned.1
  have slotEvaluation : Evaluates program.core before
      (.binary .add (.local 16) (.value (.signed .i32 1))) (.signed .i32 (Int.ofNat (slot + 1))) before :=
    evaluatesNatI32Add (local_read slotLocal) ⟨1, rfl⟩ (by omega)
  have rootEvaluation : Evaluates program.core before
      (.binary .subtract (.field (.local 17) 1) (.value (.signed .i32 1)))
      (.signed .i32 (Int.ofNat (nodes - 1))) before :=
    evaluatesNatI32Subtract (evaluatesStructureField (local_read resultLocal) rfl) ⟨1, rfl⟩ (by omega) (by omega)
  obtain ⟨stored, store, backing, storedEffect⟩ := evaluatesSliceStore program.core before before records
    5 (.binary .add (.local 16) (.value (.signed .i32 1)))
    (.binary .subtract (.field (.local 17) 1) (.value (.signed .i32 1)))
    recordsCell (slot + 1) (Int.ofNat (nodes - 1)) wellFormed room recordsLocal slotEvaluation rootEvaluation
    (CellEffect.refl wellFormed) recordsBacking
  have storedResult := storedEffect.preserves_local_of_distinct_value wellFormed resultLocal recordsBacking
    (by intro impossible; cases impossible)
  have storedNodes := storedEffect.preserves_localPointsTo wellFormed nodesOwned nodesNotRecords
  have storedWords := storedEffect.preserves_localPointsTo wellFormed wordsOwned wordsNotRecords
  obtain ⟨advanced, setNodes, advancedNodes, nodeEffect⟩ := evaluatesOwnedLocalUpdate storedEffect.wellFormed storedNodes
    (evaluatesStructureField (local_read storedResult) (show
      [Value.signed .i32 0, .signed .i32 (Int.ofNat nodes), .signed .i32 (Int.ofNat words)][1]? =
        some (.signed .i32 (Int.ofNat nodes)) from rfl))
    (show evalAssignValue program.core.target .set (some (.signed .i32 oldNodes)) (.signed .i32 (Int.ofNat nodes)) =
      .ok (.signed .i32 (Int.ofNat nodes)) from rfl)
  have advancedResult := nodeEffect.preserves_local_of_distinct_value storedEffect.wellFormed storedResult storedNodes.2
    (by intro impossible; cases impossible)
  have advancedWords := nodeEffect.preserves_localPointsTo storedEffect.wellFormed storedWords (Ne.symm distinctCursors)
  have advancedBacking := nodeEffect.preserves_entry storedEffect.wellFormed backing (Ne.symm nodesNotRecords)
  obtain ⟨after, setWords, finalWords, wordEffect⟩ := evaluatesOwnedLocalUpdate nodeEffect.wellFormed advancedWords
    (evaluatesStructureField (local_read advancedResult) (show
      [Value.signed .i32 0, .signed .i32 (Int.ofNat nodes), .signed .i32 (Int.ofNat words)][2]? =
        some (.signed .i32 (Int.ofNat words)) from rfl))
    (show evalAssignValue program.core.target .set (some (.signed .i32 oldWords)) (.signed .i32 (Int.ofNat words)) =
      .ok (.signed .i32 (Int.ofNat words)) from rfl)
  have finalNodes := wordEffect.preserves_localPointsTo nodeEffect.wellFormed advancedNodes distinctCursors
  have finalBacking := wordEffect.preserves_entry nodeEffect.wellFormed advancedBacking (Ne.symm wordsNotRecords)
  have storedWrites := storedEffect.weaken (show CellSet.Subset (CellSet.singleton recordsCell)
      (childResultWrites recordsCell nodesCell wordsCell) by intro cell member; exact Or.inl member)
  have nodeWrites := nodeEffect.weaken (show CellSet.Subset (CellSet.singleton nodesCell)
      (childResultWrites recordsCell nodesCell wordsCell) by intro cell member; exact Or.inr (Or.inl member))
  have wordWrites := wordEffect.weaken (show CellSet.Subset (CellSet.singleton wordsCell)
      (childResultWrites recordsCell nodesCell wordsCell) by intro cell member; exact Or.inr (Or.inr member))
  refine ⟨after, ?_, finalBacking, finalNodes, finalWords, storedWrites.trans (nodeWrites.trans wordWrites)⟩
  apply executesSequence (middle := before)
  · apply executesIfFalse (afterCondition := before)
    · exact evaluatesEagerBinary (by decide) (by decide)
        (evaluatesStructureField (local_read resultLocal) (show
          [Value.signed .i32 0, .signed .i32 (Int.ofNat nodes), .signed .i32 (Int.ofNat words)][0]? = some (.signed .i32 0) from rfl))
        (evaluatesConstant checked.statuses.1) rfl
    · exact executesSkip _ _
  · exact executesSequence (executesExpression store)
      (executesSequence (executesExpression setNodes)
        (executesSequence (executesExpression setWords) (executesSkip _ _)))

/-- Bind a successful recursive result and execute all of `childExpansion`.
    This composes an actual recursive evaluation with the checked continuation;
    the recursive evaluation is an induction obligation, not a trust assumption. -/
theorem CheckedVisit.child_success (checked : CheckedVisit program)
    (call : Evaluates program.core before (recursiveCall checked.symbols)
      (resultValue checked.symbols.resultType 0 (Int.ofNat nodes) (Int.ofNat words)) afterCall)
    (wellFormed : StateWellFormed afterCall)
    (slotLocal : afterCall.local? 16 = some (.signed .i32 (Int.ofNat slot)))
    (nodesOwned : (Assertion.localPointsTo 14 nodesCell (some (.signed .i32 oldNodes))).holds afterCall)
    (wordsOwned : (Assertion.localPointsTo 13 wordsCell (some (.signed .i32 oldWords))).holds afterCall)
    (distinctCursors : nodesCell ≠ wordsCell)
    (recordsLocal : afterCall.local? 5 = some
      (.slice (.scalar (.signed .i32)) recordsCell [] 0 records.length))
    (recordsBacking : afterCall.cellEntry? recordsCell = some {
      id := recordsCell, value := some (.array (signedI32Values records)) })
    (room : slot + 1 < records.length) (capacityBound : records.length ≤ 2147483647)
    (nonempty : 0 < nodes) (nodesBound : nodes ≤ 2147483647) :
    ∃ after, Executes program.core before (childExpansion checked.symbols) .next after ∧
      after.cellEntry? recordsCell = some {
        id := recordsCell, value := some (.array (signedI32Values (records.set (slot + 1) (Int.ofNat (nodes - 1))))) } ∧
      (Assertion.localPointsTo 14 nodesCell (some (.signed .i32 (Int.ofNat nodes)))).holds after ∧
      (Assertion.localPointsTo 13 wordsCell (some (.signed .i32 (Int.ofNat words)))).holds after ∧
      CellEffect (childResultWrites recordsCell nodesCell wordsCell) afterCall after := by
  let value := resultValue checked.symbols.resultType 0 (Int.ofNat nodes) (Int.ofNat words)
  let bound := afterCall.bindLocal 17 value
  have boundWF : StateWellFormed bound := bindLocal_preserves_well_formed _ _ _ wellFormed
  have resultLocal : bound.local? 17 = some value := bindLocal_finds_local _ _ _ wellFormed
  have slotBound : bound.local? 16 = some (.signed .i32 (Int.ofNat slot)) :=
    (bindLocal_preserves_other_local wellFormed (show (17 : Lanius.VarId) ≠ 16 by decide)).trans slotLocal
  have nodesBoundOwned := bindLocal_preserves_localPointsTo_of_ne afterCall 17 14 value nodesCell _
    wellFormed (by decide) nodesOwned
  have wordsBoundOwned := bindLocal_preserves_localPointsTo_of_ne afterCall 17 13 value wordsCell _
    wellFormed (by decide) wordsOwned
  have recordsBoundLocal : bound.local? 5 = some
      (.slice (.scalar (.signed .i32)) recordsCell [] 0 records.length) :=
    (bindLocal_preserves_other_local wellFormed (show (17 : Lanius.VarId) ≠ 5 by decide)).trans recordsLocal
  have backing : bound.cellEntry? recordsCell = some {
      id := recordsCell, value := some (.array (signedI32Values records)) } :=
    ((bindLocal_effect afterCall 17 value).oldCells recordsCell
      (StateWellFormed.cell_lt_next_of_entry wellFormed recordsBacking) (by simp [CellSet.empty])).trans recordsBacking
  obtain ⟨completed, resumed, written, finalNodes, finalWords, effect⟩ := checked.resume_child boundWF
    resultLocal slotBound nodesBoundOwned wordsBoundOwned distinctCursors recordsBoundLocal backing
    room capacityBound nonempty nodesBound
  exact ⟨restoreLocals afterCall completed, executesLetLocal call resumed, written,
    ⟨nodesOwned.1, finalNodes.2⟩, ⟨wordsOwned.1, finalWords.2⟩,
    CellEffect.closeLocal afterCall 17 value wellFormed effect⟩

/-- A failed child returns its exact status and advanced counters immediately;
    the parent performs no payload or cursor store after that result. -/
theorem CheckedVisit.resume_failure (checked : CheckedVisit program)
    (resultLocal : before.local? 17 = some (resultValue checked.symbols.resultType code nodes words))
    (failed : code ≠ 0) :
    Executes program.core before (childResult checked.symbols)
      (.returned (some (resultValue checked.symbols.resultType code nodes words))) before := by
  apply executesSequenceReturned
  apply executesIfTrue (afterCondition := before)
  · exact evaluatesEagerBinary (by decide) (by decide)
      (evaluatesStructureField (local_read resultLocal) (show
        [Value.signed .i32 code, .signed .i32 nodes, .signed .i32 words][0]? = some (.signed .i32 code) from rfl))
      (evaluatesConstant checked.statuses.1)
      (by simp [evalBinaryValue, scalarEqual, failed])
  · exact executesSequenceReturned (executesReturnValue (local_read resultLocal))

/-- Propagate a recursive call's failure through the actual result-binding
    scope. Its possibly partial outputs are preserved, not rewritten or
    represented as a successful tree. The recursive call remains an explicit
    composition premise here, to be discharged by the whole-call induction. -/
theorem CheckedVisit.child_failure (checked : CheckedVisit program)
    (call : Evaluates program.core before (recursiveCall checked.symbols)
      (resultValue checked.symbols.resultType code nodes words) afterCall)
    (wellFormed : StateWellFormed afterCall) (failed : code ≠ 0) :
    ∃ after, Executes program.core before (childExpansion checked.symbols)
      (.returned (some (resultValue checked.symbols.resultType code nodes words))) after ∧
      ModifiesOnly CellSet.empty afterCall after ∧ StateWellFormed after := by
  let value := resultValue checked.symbols.resultType code nodes words
  let bound := afterCall.bindLocal 17 value
  have resultLocal : bound.local? 17 = some value := bindLocal_finds_local afterCall 17 value wellFormed
  have effect := bindLocal_effect afterCall 17 value
  exact ⟨restoreLocals afterCall bound, executesLetLocal call (checked.resume_failure resultLocal failed),
    effect.restoreLocals, effect.restoreLocals_wellFormed wellFormed (bindLocal_preserves_well_formed _ _ _ wellFormed)⟩

end Lanius.Extraction.ParserTreeSource
