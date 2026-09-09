import Lanius.Extraction.CompactOutput.Tokens.Entry

namespace Lanius.Extraction.CompactOutput.Tokens

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

/-- Execute the whole token iteration on exhaustion, preserving its exact
partial output and returning before the token counter is incremented. -/
theorem Entry.failure (entry : Entry before) (word : Word.Checked program byte digit)
    (full : entry.outcome = .full retained) :
    ∃ after, Executes program.core before (step word.source.function.id)
        (.returned (some (.signed .i32 (-1)))) after ∧
      after.cellEntry? entry.outputCell = some {
        id := entry.outputCell, value := some (.array (signedI32Values retained)) } ∧
      CellEffect (CellSet.union (CellSet.singleton entry.outputCell) (CellSet.singleton entry.cursorCell)) before after := by
  obtain ⟨rowRead, startRead, finishRead, _, _, _, _, _⟩ := initialize_fields program.core entry.tokens entry.index
    entry.wellFormed entry.input entry.indexRead entry.bound entry.sizeFit
  obtain ⟨first, second, written, guard, firstRun, secondRun, thirdRun, cursor, backing, effect⟩ := entry.write word
  have nextRead := local_evaluates program.core (Assertion.localPointsTo_local _ _ _ _ cursor)
  rw [full] at nextRead backing
  have failed : Evaluates program.core written failureGuard (.boolean true) written := by
    apply evaluatesEagerBinary (by decide) (by decide) nextRead (negativeOne_evaluates program.core written)
    simp [evalBinaryValue, evalSignedBinary, AppendOutcome.position]
  have tailRun : Executes program.core entry.scope
      (.sequence (.ifThenElse fieldGuard (returned negativeOne) .skip)
        (.sequence (.expression (kindWrite word.source.function.id))
          (.sequence (.expression (startWrite word.source.function.id))
            (.sequence (.expression (finishWrite word.source.function.id))
              (.sequence (.ifThenElse failureGuard (returned negativeOne) .skip)
                (.sequence (.expression increment) .skip))))))
      (.returned (some (.signed .i32 (-1)))) written :=
    executesSequence (executesIfFalse guard (executesSkip _ _))
      (executesSequence (executesExpression firstRun)
        (executesSequence (executesExpression secondRun)
          (executesSequence (executesExpression thirdRun)
            (executesSequenceReturned (executesIfTrue failed
              (executesSequenceReturned (executesReturnValue (negativeOne_evaluates program.core written))))))))
  have rowWF : StateWellFormed (rowState before entry.index) := bindLocal_preserves_well_formed _ _ _ entry.wellFormed
  have startWF : StateWellFormed (startState before entry.index entry.token) := bindLocal_preserves_well_formed _ _ _ rowWF
  have run := executesLetLocal (id := 9) (type := i32) rowRead
    (executesLetLocal (id := 10) (type := i32) startRead
      (executesLetLocal (id := 11) (type := i32) finishRead tailRun))
  have closed := CellEffect.closeLocal before 9 (.signed .i32 (3 * entry.index : Nat)) entry.wellFormed
    (CellEffect.closeLocal (rowState before entry.index) 10 (.signed .i32 entry.token.start) rowWF
      (CellEffect.closeLocal (startState before entry.index entry.token) 11 (.signed .i32 entry.token.finish) startWF effect))
  exact ⟨restoreLocals before written, run, backing, closed⟩

end Lanius.Extraction.CompactOutput.Tokens
