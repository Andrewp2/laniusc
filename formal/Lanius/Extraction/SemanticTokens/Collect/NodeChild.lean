import Lanius.Extraction.SemanticTokens.Collect.Record
import Lanius.Separation.LocalStore

namespace Lanius.Extraction.SemanticTokens.Collect

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.Compiler.Parser ParserTreeLayout

/-- Execute the actual state-child branch. The earlier-node lookup, stored
headers, and ordered span are derived from the selected frontend tree, not
from a caller-supplied successful read or accepted-record assumption. -/
theorem node_child_execute {record : RecordVisit} {nodeIndex childIndex childId start finish : Nat}
    (data : CollectionRecords grammar tokens tree 0 0)
    (program : Program) (symbols : Symbols)
    (stateTag : ParserTreeSource.constantValue program symbols.childState 2)
    (found : data.records[nodeIndex]? = some record)
    (childFound : record.children[childIndex]? = some (.node childId start finish))
    (wellFormed : StateWellFormed before)
    (recordsOwned : I32PrefixLocal before 4 recordsCell (treeFrom 0 0 tree).words)
    (offsetsOwned : I32PrefixLocal before 6 offsetsCell ((treeFrom 0 0 tree).offsets.map Int.ofNat))
    (lengthRead : before.local? 5 = some (.signed .i32 (treeFrom 0 0 tree).words.length))
    (countRead : before.local? 3 = some (.signed .i32 tokens.length))
    (nodeRead : before.local? 13 = some (.signed .i32 nodeIndex))
    (payloadRead : before.local? 19 = some (.signed .i32 childId))
    (slotRead : before.local? 18 = some (.signed .i32 (record.offset + 4 + childIndex * 3)))
    (cursor : (Assertion.localPointsTo 16 cursorCell (some (.signed .i32 start))).holds before)
    (wordsFit : (treeFrom 0 0 tree).words.length ≤ 2147483647)
    (tokensFit : tokens.length * 2 ≤ 2147483647) :
    ∃ after, Executes program before (nodeChildBody symbols) .next after ∧
      (Assertion.localPointsTo 16 cursorCell (some (.signed .i32 finish))).holds after ∧
      CellEffect (CellSet.singleton cursorCell) before after := by
  have member := List.mem_of_getElem? found
  have childMember := List.mem_of_getElem? childFound
  obtain ⟨_, earlier, nested, nestedFound, sameStart, sameFinish⟩ :=
    data.linked nodeIndex record found (.node childId start finish) childMember
  simp only [Nat.sub_zero] at nestedFound
  simp only [Nat.zero_add] at earlier
  have nestedMember := List.mem_of_getElem? nestedFound
  have stored := data.stored record member
  have nestedStored := data.stored nested nestedMember
  have ordered : start ≤ finish := (data.valid record member).member childMember |>.1
  have finishBound : finish ≤ tokens.length * 2 := by
    have bound := data.bounded nested nestedMember
    simpa only [sameFinish, finalPosition] using bound
  have offsetFound : ((treeFrom 0 0 tree).offsets.map Int.ofNat)[childId]? = some (Int.ofNat nested.offset) := by
    rw [← data.offsets]
    simp [List.getElem?_map, nestedFound]
  obtain ⟨tag, _, _⟩ := record_child_read program recordsOwned stored childFound
    (read 18) (local_evaluates program slotRead) wordsFit
  have tagCheck : Evaluates program before
      (binary .notEqual (atIndex 4 (read 18)) (.constant symbols.childState)) (.boolean false) before :=
    evaluatesEagerBinary (by decide) (by decide) tag (evaluatesConstant stateTag) rfl
  have earlierCheck := greaterEqual_evaluates (local_evaluates program payloadRead) (local_evaluates program nodeRead)
  have earlierFalse : ¬ ((nodeIndex : Int) ≤ childId) := by omega
  have firstGuard := evaluatesPureLogicalOr tagCheck earlierCheck
  simp only [earlierFalse, decide_false, Bool.false_or] at firstGuard
  have offsetRead := read_word program offsetsOwned (read 19) childId offsetFound
    (local_evaluates program payloadRead)
  let entered := before.bindLocal 20 (.signed .i32 nested.offset)
  have enteredWF : StateWellFormed entered := bindLocal_preserves_well_formed _ _ _ wellFormed
  have nestedRead : entered.local? 20 = some (.signed .i32 nested.offset) := bindLocal_finds_local _ _ _ wellFormed
  have lengthStill : entered.local? 5 = some (.signed .i32 (treeFrom 0 0 tree).words.length) :=
    (bindLocal_preserves_other_local wellFormed (by decide : (20 : VarId) ≠ 5)).trans lengthRead
  have countStill : entered.local? 3 = some (.signed .i32 tokens.length) :=
    (bindLocal_preserves_other_local wellFormed (by decide : (20 : VarId) ≠ 3)).trans countRead
  have cursorStill := bindLocal_preserves_localPointsTo_of_ne before 20 16
    (.signed .i32 nested.offset) cursorCell _ wellFormed (by decide) cursor
  have recordsStill := recordsOwned.bindLocal wellFormed 20 (.signed .i32 nested.offset) (by decide)
  have room := nestedStored.bounds
  have headerGuard := recordGuard_pass program 20 nested.offset (treeFrom 0 0 tree).words.length
    nestedRead lengthStill (by omega) wordsFit
  obtain ⟨startRead, finishRead, _⟩ := record_header_read program recordsStill nestedStored
    (read 20) (local_evaluates program nestedRead) wordsFit
  rw [sameStart] at startRead
  rw [sameFinish] at finishRead
  have cursorRead := local_evaluates program (Assertion.localPointsTo_local _ _ _ _ cursorStill)
  have sameCheck : Evaluates program entered
      (binary .notEqual (atIndex 4 (binary .add (read 20) (number 1))) (read 16)) (.boolean false) entered :=
    evaluatesEagerBinary (by decide) (by decide) startRead cursorRead (by simp [evalBinaryValue, scalarEqual])
  have orderedCheck := negate_evaluates (lessEqual_evaluates cursorRead finishRead)
  have totalRead := evaluatesNatI32Multiply (leftValue := tokens.length) (rightValue := 2)
    (local_evaluates program countStill) (show Evaluates program entered (number 2) (.signed .i32 2) entered from ⟨1, rfl⟩) tokensFit
  have boundedCheck := negate_evaluates (lessEqual_evaluates finishRead totalRead)
  have spanGuard := evaluatesPureLogicalOr (evaluatesPureLogicalOr sameCheck orderedCheck) boundedCheck
  have orderedInt : (start : Int) ≤ finish := by omega
  have boundedInt : (finish : Int) ≤ (tokens.length * 2 : Nat) := by omega
  simp only [Int.ofNat_eq_natCast, orderedInt, boundedInt, decide_true, Bool.not_true, Bool.false_or] at spanGuard
  obtain ⟨completed, assigned, cursorAfter, effect⟩ := evaluatesOwnedLocalUpdate enteredWF cursorStill finishRead
    (show evalAssignValue program.target .set (some (.signed .i32 start)) (.signed .i32 finish) =
      .ok (.signed .i32 finish) from rfl)
  have nestedRun := executesSequence (executesIfFalse (thenBranch := returned (negative 1)) headerGuard (executesSkip _ _))
    (executesSequence (executesIfFalse (thenBranch := returned (negative 1)) spanGuard (executesSkip _ _))
      (executesSequence (executesExpression assigned) (executesSkip _ _)))
  have run := executesSequence (executesIfFalse (thenBranch := returned (negative 1)) firstGuard (executesSkip _ _))
    (executesLetLocal (id := 20) (type := i32) offsetRead nestedRun)
  exact ⟨restoreLocals before completed, run, ⟨cursor.1, cursorAfter.2⟩,
    CellEffect.closeLocal before 20 (.signed .i32 nested.offset) wellFormed effect⟩

end Lanius.Extraction.SemanticTokens.Collect
