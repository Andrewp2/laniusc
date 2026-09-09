import Lanius.Extraction.CompactOutput.Tokens.Entry
import Lanius.Extraction.CompactOutput.Outcome

namespace Lanius.Extraction.CompactOutput.Tokens

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

theorem Entry.success {result : Int} {contents : List Int}
    (entry : Entry before) (word : Word.Checked program byte digit)
    (indexOwned : (Assertion.localPointsTo 8 indexCell (some (.signed .i32 entry.index))).holds before)
    (distinct : entry.cursorCell ≠ indexCell)
    (done : entry.outcome = .done result contents) :
    ∃ after, Executes program.core before (step word.source.function.id) .next after ∧
      after.cellEntry? entry.outputCell = some {
        id := entry.outputCell, value := some (.array (signedI32Values contents)) } ∧
      (Assertion.localPointsTo 7 entry.cursorCell (some (.signed .i32 result))).holds after ∧
      (Assertion.localPointsTo 8 indexCell (some (.signed .i32 (entry.index + 1 : Nat)))).holds after ∧
      CellEffect (CellSet.union
        (CellSet.union (CellSet.singleton entry.outputCell) (CellSet.singleton entry.cursorCell))
        (CellSet.singleton indexCell)) before after := by
  obtain ⟨rowRead, startRead, finishRead, scopeWF, _, _, _, _⟩ := initialize_fields program.core entry.tokens entry.index
    entry.wellFormed entry.input entry.indexRead entry.bound entry.sizeFit
  obtain ⟨first, second, written, guard, firstRun, secondRun, thirdRun, cursor, backing, effect⟩ := entry.write word
  have nonnegative : 0 ≤ result := appendAll_done_nonnegative _ (by
    simp only [encoding, hexDigits, List.cons_append, ne_eq, List.cons_ne_nil, not_false_eq_true]) done
  have nextRead := local_evaluates program.core (Assertion.localPointsTo_local _ _ _ _ cursor)
  rw [done] at nextRead backing cursor
  have passed : Evaluates program.core written failureGuard (.boolean false) written := by
    apply evaluatesEagerBinary (by decide) (by decide) nextRead (negativeOne_evaluates program.core written)
    simp only [evalBinaryValue, evalSignedBinary, AppendOutcome.position, beq_self_eq_true,
      if_true, Except.ok.injEq, Value.boolean.injEq]
    exact decide_eq_false (by omega)
  have rowWF : StateWellFormed (rowState before entry.index) := bindLocal_preserves_well_formed _ _ _ entry.wellFormed
  have startWF : StateWellFormed (startState before entry.index entry.token) := bindLocal_preserves_well_formed _ _ _ rowWF
  have indexRow := bindLocal_preserves_localPointsTo_of_ne before 9 8
    (.signed .i32 (3 * entry.index : Nat)) indexCell _ entry.wellFormed (by decide) indexOwned
  have indexStart := bindLocal_preserves_localPointsTo_of_ne (rowState before entry.index) 10 8
    (.signed .i32 entry.token.start) indexCell _ rowWF (by decide) indexRow
  have indexScope := bindLocal_preserves_localPointsTo_of_ne (startState before entry.index entry.token) 11 8
    (.signed .i32 entry.token.finish) indexCell _ startWF (by decide) indexStart
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
    program.core written 8 indexCell entry.index effect.wellFormed indexWritten
    (by have := entry.sizeFit; have := entry.bound; omega)
  have incrementEffect := CellEffect.ofModifiesOnly modifies advancedWF
  have cursorAdvanced := incrementEffect.preserves_localPointsTo effect.wellFormed cursor
    (by simpa only [CellSet.singleton] using distinct)
  have outputAdvanced := incrementEffect.preserves_entry effect.wellFormed backing
    (by simpa only [CellSet.singleton] using outputIndex)
  have tailRun : Executes program.core entry.scope
      (.sequence (.ifThenElse fieldGuard (returned negativeOne) .skip)
        (.sequence (.expression (kindWrite word.source.function.id))
          (.sequence (.expression (startWrite word.source.function.id))
            (.sequence (.expression (finishWrite word.source.function.id))
              (.sequence (.ifThenElse failureGuard (returned negativeOne) .skip)
                (.sequence (.expression increment) .skip)))))) .next advanced :=
    executesSequence (executesIfFalse guard (executesSkip _ _))
      (executesSequence (executesExpression firstRun)
        (executesSequence (executesExpression secondRun)
          (executesSequence (executesExpression thirdRun)
            (executesSequence (executesIfFalse passed (executesSkip _ _))
              (executesSequence (executesExpression incremented) (executesSkip _ _))))))
  have run := executesLetLocal (id := 9) (type := i32) rowRead
    (executesLetLocal (id := 10) (type := i32) startRead
      (executesLetLocal (id := 11) (type := i32) finishRead tailRun))
  have combined := (effect.weaken CellSet.subset_union_left).trans
    (incrementEffect.weaken CellSet.subset_union_right)
  have closed := CellEffect.closeLocal before 9 (.signed .i32 (3 * entry.index : Nat)) entry.wellFormed
    (CellEffect.closeLocal (rowState before entry.index) 10 (.signed .i32 entry.token.start) rowWF
      (CellEffect.closeLocal (startState before entry.index entry.token) 11 (.signed .i32 entry.token.finish) startWF combined))
  exact ⟨restoreLocals before advanced, run, outputAdvanced,
    ⟨entry.cursor.1, cursorAdvanced.2⟩, ⟨indexOwned.1, indexAdvanced.2⟩, closed⟩

end Lanius.Extraction.CompactOutput.Tokens
