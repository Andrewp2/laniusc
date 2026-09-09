import Lanius.Extraction.CompactOutput.Nodes.Entry
import Lanius.Extraction.CompactOutput.Outcome

namespace Lanius.Extraction.CompactOutput.Nodes

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler.Parser ParserTreeLayout Lanius.Extraction.SemanticTokens

theorem ChildEntry.success {result : Int} {contents : List Int}
    (entry : ChildEntry before) (word : Word.Checked program byte digit)
    (tokenConstant : ParserTreeSource.constantValue program.core tokenTag 1)
    (stateConstant : ParserTreeSource.constantValue program.core stateTag 2)
    (indexOwned : (Assertion.localPointsTo 13 indexCell (some (.signed .i32 entry.index))).holds before)
    (distinct : entry.cursorCell ≠ indexCell)
    (done : entry.outcome = .done result contents) :
    ∃ after, Executes program.core before (childStep word.source.function.id tokenTag stateTag) .next after ∧
      after.cellEntry? entry.outputCell = some {
        id := entry.outputCell, value := some (.array (signedI32Values contents)) } ∧
      (Assertion.localPointsTo 8 entry.cursorCell (some (.signed .i32 result))).holds after ∧
      (Assertion.localPointsTo 13 indexCell (some (.signed .i32 (entry.index + 1 : Nat)))).holds after ∧
      CellEffect (CellSet.union
        (CellSet.union (CellSet.singleton entry.outputCell) (CellSet.singleton entry.cursorCell))
        (CellSet.singleton indexCell)) before after := by
  obtain ⟨rowRead, startRead, finishRead, scopeWF, _, _, _⟩ := initialize_child program.core entry.record entry.child entry.index
    entry.wellFormed entry.input entry.stored entry.found entry.recordRead entry.indexRead entry.sizeFit
  obtain ⟨middle, written, firstRun, secondRun, cursor, backing, effect⟩ := entry.write word
  have nonnegative : 0 ≤ result := appendAll_done_nonnegative _ (by
    simp only [encodeChild, childEncoding, hexDigits, List.cons_append, ne_eq, List.cons_ne_nil, not_false_eq_true]) done
  have nextRead := local_evaluates program.core (Assertion.localPointsTo_local _ _ _ _ cursor)
  rw [done] at nextRead backing cursor
  have passed : Evaluates program.core written failureGuard (.boolean false) written := by
    apply evaluatesEagerBinary (by decide) (by decide) nextRead (negativeOne_evaluates program.core written)
    simp only [evalBinaryValue, evalSignedBinary, AppendOutcome.position, beq_self_eq_true,
      if_true, Except.ok.injEq, Value.boolean.injEq]
    exact decide_eq_false (by omega)
  have rowWF : StateWellFormed (slotState before entry.record entry.index) := bindLocal_preserves_well_formed _ _ _ entry.wellFormed
  have startWF : StateWellFormed (tagState before entry.record entry.index entry.child) := bindLocal_preserves_well_formed _ _ _ rowWF
  have indexRow := bindLocal_preserves_localPointsTo_of_ne before 14 13
    (.signed .i32 (entry.record.offset + 4 + entry.index * 3 : Nat)) indexCell _ entry.wellFormed (by decide) indexOwned
  have indexStart := bindLocal_preserves_localPointsTo_of_ne (slotState before entry.record entry.index) 15 13
    (.signed .i32 (childTag entry.child.reference)) indexCell _ rowWF (by decide) indexRow
  have indexScope := bindLocal_preserves_localPointsTo_of_ne (tagState before entry.record entry.index entry.child) 16 13
    (.signed .i32 (childPayload entry.child.reference)) indexCell _ startWF (by decide) indexStart
  have outputIndex : entry.outputCell ≠ indexCell := by
    intro same
    have original := entry.backing
    rw [same, indexOwned.2] at original
    cases original
  have indexWritten := effect.preserves_localPointsTo scopeWF indexScope (by
    intro changed
    rcases changed with output | next
    · exact outputIndex output.symm
    · exact distinct next.symm)
  obtain ⟨advanced, incremented, advancedWF, indexAdvanced, modifies⟩ := evaluatesIncrementOwnedI32Local
    program.core written 13 indexCell entry.index effect.wellFormed indexWritten
    (by have := entry.sizeFit; have := entry.stored.bounds
        have := (List.getElem?_eq_some_iff.mp entry.found).1; omega)
  have incrementEffect := CellEffect.ofModifiesOnly modifies advancedWF
  have cursorAdvanced := incrementEffect.preserves_localPointsTo effect.wellFormed cursor
    (by simpa only [CellSet.singleton] using distinct)
  have outputAdvanced := incrementEffect.preserves_entry effect.wellFormed backing
    (by simpa only [CellSet.singleton] using outputIndex)
  have writesRun : Executes program.core entry.scope
      (.sequence (.expression (tagWrite word.source.function.id))
        (.sequence (.expression (payloadWrite word.source.function.id))
          (.sequence (.ifThenElse failureGuard (returned negativeOne) .skip)
            (.sequence (.expression childIncrement) .skip)))) .next advanced :=
    executesSequence (executesExpression firstRun)
      (executesSequence (executesExpression secondRun)
        (executesSequence (executesIfFalse passed (executesSkip _ _))
          (executesSequence (executesExpression incremented) (executesSkip _ _))))
  have tailRun := entry.validate program.core tokenConstant stateConstant writesRun
  have run := executesLetLocal (id := 14) (type := i32) rowRead
    (executesLetLocal (id := 15) (type := i32) startRead
      (executesLetLocal (id := 16) (type := i32) finishRead tailRun))
  have combined := (effect.weaken CellSet.subset_union_left).trans
    (incrementEffect.weaken CellSet.subset_union_right)
  have closed := CellEffect.closeLocal before 14 (.signed .i32 (entry.record.offset + 4 + entry.index * 3 : Nat)) entry.wellFormed
    (CellEffect.closeLocal (slotState before entry.record entry.index) 15 (.signed .i32 (childTag entry.child.reference)) rowWF
      (CellEffect.closeLocal (tagState before entry.record entry.index entry.child) 16 (.signed .i32 (childPayload entry.child.reference)) startWF combined))
  exact ⟨restoreLocals before advanced, run, outputAdvanced,
    ⟨entry.cursor.1, cursorAdvanced.2⟩, ⟨indexOwned.1, indexAdvanced.2⟩, closed⟩

end Lanius.Extraction.CompactOutput.Nodes

