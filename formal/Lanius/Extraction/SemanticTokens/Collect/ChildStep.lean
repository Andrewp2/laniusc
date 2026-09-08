import Lanius.Extraction.SemanticTokens.Collect.ChildMemory

namespace Lanius.Extraction.SemanticTokens.Collect

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.Compiler.Parser ParserTreeLayout

/-- One complete iteration, including the two outer scopes, tag dispatch,
the proven branch, child-index increment, and restored caller resources. -/
theorem child_step {memory : ChildMemory} {record : RecordVisit} {child : ChildVisit}
    (program : Program) (symbols : Symbols)
    (tokenTag : ParserTreeSource.constantValue program symbols.childToken 1)
    (stateTag : ParserTreeSource.constantValue program symbols.childState 2)
    (found : memory.data.collection.records[nodeIndex]? = some record)
    (childFound : record.children[index]? = some child)
    (held : ChildOwned memory record nodeIndex index child.start visited before)
    (unique : ((visited ++ child.uses ++ remaining).map Use.slot).Nodup) :
    ∃ after, Executes program before (childBody symbols) .next after ∧
      ChildOwned memory record nodeIndex (index + 1) child.finish (visited ++ child.uses) after ∧
      CellEffect memory.writes before after := by
  have member := List.mem_of_getElem? found
  have childMember := List.mem_of_getElem? childFound
  have stored := memory.data.collection.stored record member
  have bounds := stored.bounds
  have active := (List.getElem?_eq_some_iff.mp childFound).1
  have wordsFit := memory.data.wordsFit
  let slot := record.offset + 4 + index * 3
  have slotBound : slot + 2 < (treeFrom 0 0 memory.data.tree).words.length := by dsimp [slot]; omega
  have slotResult : Evaluates program before
      (binary .add (binary .add (read 14) (number 4)) (binary .multiply (read 17) (number 3)))
      (.signed .i32 (Int.ofNat slot)) before := by
    apply evaluatesNatI32Add (leftValue := record.offset + 4) (rightValue := index * 3)
    · exact evaluatesNatI32Add (leftValue := record.offset) (rightValue := 4)
        (local_evaluates program held.offset) ⟨1, rfl⟩ (by omega)
    · exact evaluatesNatI32Multiply (leftValue := index) (rightValue := 3)
        (local_evaluates program (Assertion.localPointsTo_local _ _ _ _ held.child)) ⟨1, rfl⟩ (by omega)
    · dsimp [slot] at slotBound; omega
  let first := before.bindLocal 18 (.signed .i32 (Int.ofNat slot))
  have firstHeld : ChildOwned memory record nodeIndex index child.start visited first :=
    held.bindLocal 18 _ (by decide)
  have slotFirst : first.local? 18 = some (.signed .i32 (Int.ofNat slot)) := bindLocal_finds_local _ _ _ held.wellFormed
  obtain ⟨_, payloadResult, _⟩ := record_child_read program firstHeld.records stored childFound
    (read 18) (local_evaluates program slotFirst) wordsFit
  let second := first.bindLocal 19 (.signed .i32 (childPayload child.reference))
  have secondHeld : ChildOwned memory record nodeIndex index child.start visited second :=
    firstHeld.bindLocal 19 _ (by decide)
  have payloadSecond : second.local? 19 = some (.signed .i32 (childPayload child.reference)) :=
    bindLocal_finds_local _ _ _ firstHeld.wellFormed
  have slotSecond : second.local? 18 = some (.signed .i32 (Int.ofNat slot)) :=
    (bindLocal_preserves_other_local firstHeld.wellFormed (by decide : (19 : VarId) ≠ 18)).trans slotFirst
  have payloadCheck := lessEqual_evaluates (local_evaluates program payloadSecond) (negativeOne_evaluates program second)
  have nonnegative : ¬ (childPayload child.reference ≤ -1) := by
    cases child <;> simp only [ChildVisit.reference, childPayload, Int.ofNat_eq_natCast] <;> omega
  simp only [nonnegative, decide_false] at payloadCheck
  obtain ⟨tagRead, _, _⟩ := record_child_read program secondHeld.records stored childFound
    (read 18) (local_evaluates program slotSecond) wordsFit
  have branch : ∃ middle,
      Executes program second (.ifThenElse (binary .equal (atIndex 4 (read 18)) (.constant symbols.childToken))
        tokenBody (nodeChildBody symbols)) .next middle ∧
      (Assertion.localPointsTo 16 memory.positionCell (some (.signed .i32 child.finish))).holds middle ∧
      middle.cellEntry? memory.data.outputCell = some {
        id := memory.data.outputCell,
        value := some (.array (signedI32Values (written memory.data.original memory.data.tokens.length (visited ++ child.uses)))) } ∧
      CellEffect (CellSet.union (CellSet.singleton memory.data.outputCell) (CellSet.singleton memory.positionCell)) second middle := by
    cases child with
    | token use =>
      obtain ⟨valid, _, tokenBound, _⟩ := memory.data.collection.token_child member childMember
      have slotSmall : use.slot < memory.data.tokens.length * 2 := by
        have remainder := Nat.mod_lt use.position (by decide : 0 < 2)
        simp only [Use.slot]
        omega
      have available := written_available (original := memory.data.original) (visited := visited) (remaining := remaining) slotSmall
        (by simpa only [ChildVisit.uses, List.append_assoc, List.singleton_append] using unique)
      have grammarSeparate : memory.data.grammarCell ≠ memory.data.outputCell := by
        intro same
        exact memory.inputs _ (by simp) (Or.inl (Or.inl same))
      obtain ⟨middle, run, cursor, contents, effect⟩ := token_child_execute memory.data.grammar program valid stored childFound
        secondHeld.wellFormed secondHeld.grammar (by simpa only [List.map_map, Function.comp_def] using secondHeld.kinds)
        secondHeld.records (by simpa only [List.length_map] using secondHeld.count)
        secondHeld.kindCount secondHeld.canonicalOffset payloadSecond slotSecond secondHeld.cursor
        (by simpa only [written_length memory.data.capacity] using secondHeld.output) secondHeld.backing available
        grammarSeparate wordsFit (by simpa only [List.length_map] using memory.data.tokensFit)
      have dispatch : Evaluates program second
          (binary .equal (atIndex 4 (read 18)) (.constant symbols.childToken)) (.boolean true) second :=
        evaluatesEagerBinary (by decide) (by decide) tagRead (evaluatesConstant tokenTag) rfl
      exact ⟨middle, executesIfTrue dispatch run, cursor,
        by simpa only [ChildVisit.uses, List.length_map, written_snoc] using contents, effect⟩
    | node id start finish =>
      obtain ⟨middle, run, cursor, effect⟩ := node_child_execute memory.data.collection program symbols stateTag
        found childFound secondHeld.wellFormed secondHeld.records secondHeld.offsets secondHeld.wordLength
        secondHeld.count secondHeld.node payloadSecond slotSecond secondHeld.cursor wordsFit memory.data.tokensFit
      have dispatch : Evaluates program second
          (binary .equal (atIndex 4 (read 18)) (.constant symbols.childToken)) (.boolean false) second :=
        evaluatesEagerBinary (by decide) (by decide) tagRead (evaluatesConstant tokenTag) rfl
      exact ⟨middle, executesIfFalse dispatch run, cursor,
        by simpa only [ChildVisit.uses, List.append_nil] using effect.preserves_entry secondHeld.wellFormed secondHeld.backing memory.distinct.1,
        effect.weaken CellSet.subset_union_right⟩
  obtain ⟨middle, branchRun, cursorAfter, contents, branchEffect⟩ := branch
  have childStill := branchEffect.preserves_localPointsTo secondHeld.wellFormed secondHeld.child
    (by intro changed; rcases changed with same | same
        · exact memory.distinct.2.1 same.symm
        · exact memory.distinct.2.2 same.symm)
  obtain ⟨completed, incremented, finalWF, childAfter, incrementEffect⟩ := executesIncrementOwnedI32Local
    program middle 17 memory.childCell index branchEffect.wellFormed childStill (by omega)
  have incrementFrame := CellEffect.ofModifiesOnly incrementEffect finalWF
  have finalCursor := incrementFrame.preserves_localPointsTo branchEffect.wellFormed cursorAfter memory.distinct.2.2
  have finalContents := incrementFrame.preserves_entry branchEffect.wellFormed contents memory.distinct.2.1
  have innerEffect : CellEffect memory.writes second completed :=
    (branchEffect.weaken CellSet.subset_union_left).trans (incrementFrame.weaken CellSet.subset_union_right)
  have firstEffect := CellEffect.closeLocal first 19 (.signed .i32 (childPayload child.reference)) firstHeld.wellFormed innerEffect
  have effect := CellEffect.closeLocal before 18 (.signed .i32 (Int.ofNat slot)) held.wellFormed firstEffect
  have cursorRestored : (Assertion.localPointsTo 16 memory.positionCell (some (.signed .i32 child.finish))).holds
      (restoreLocals before completed) := ⟨held.cursor.1, finalCursor.2⟩
  have childRestored : (Assertion.localPointsTo 17 memory.childCell (some (.signed .i32 (Int.ofNat (index + 1))))).holds
      (restoreLocals before completed) := ⟨held.child.1, childAfter.2⟩
  refine ⟨restoreLocals before completed, ?_, held.advance effect finalContents cursorRestored childRestored, effect⟩
  have coreRun := executesSequence (executesIfFalse (thenBranch := returned (negative 1)) payloadCheck (executesSkip _ _))
    (executesSequence branchRun incremented)
  have innerRun := executesLetLocal (id := 19) (type := i32) payloadResult coreRun
  have wholeRun := executesLetLocal (id := 18) (type := i32) slotResult innerRun
  exact wholeRun

end Lanius.Extraction.SemanticTokens.Collect
