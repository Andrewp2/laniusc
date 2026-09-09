import Lanius.Extraction.CompactOutput.Assignments.Scope

namespace Lanius.Extraction.CompactOutput.Assignments

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

/-- The complete source iteration on output exhaustion: read both fields,
declare locals, validate, execute both writes, return -1, and close scopes.
The token increment is not executed. -/
theorem Entry.failure (entry : Entry before) (word : Word.Checked program byte digit)
    (full : entry.outcome = .full retained) :
    ∃ after, Executes program.core before (step word.source.function.id)
        (.returned (some (.signed .i32 (-1)))) after ∧
      after.cellEntry? entry.outputCell = some {
        id := entry.outputCell, value := some (.array (signedI32Values retained)) } ∧
      CellEffect (CellSet.union (CellSet.singleton entry.outputCell) (CellSet.singleton entry.cursorCell)) before after := by
  obtain ⟨firstRead, secondRead, _, _, _, _⟩ := initialize_fields program.core entry.assignments entry.index
    entry.wellFormed entry.input entry.indexRead entry.bound entry.sizeFit
  obtain ⟨middle, written, guard, firstRun, secondRun, cursor, backing, effect⟩ := entry.write word
  have nextRead := local_evaluates program.core (Assertion.localPointsTo_local _ _ _ _ cursor)
  rw [full] at nextRead backing
  have failed : Evaluates program.core written failureGuard (.boolean true) written := by
    apply evaluatesEagerBinary (by decide) (by decide) nextRead (negativeOne_evaluates program.core written)
    simp [evalBinaryValue, evalSignedBinary, AppendOutcome.position]
  have tailRun : Executes program.core entry.scope
      (.sequence (.ifThenElse fieldGuard (returned negativeOne) .skip)
        (.sequence (.expression (firstWrite word.source.function.id))
          (.sequence (.expression (secondWrite word.source.function.id))
            (.sequence (.ifThenElse failureGuard (returned negativeOne) .skip)
              (.sequence (.expression increment) .skip)))))
      (.returned (some (.signed .i32 (-1)))) written :=
    executesSequence (executesIfFalse guard (executesSkip _ _))
      (executesSequence (executesExpression firstRun)
        (executesSequence (executesExpression secondRun)
          (executesSequenceReturned (executesIfTrue failed
            (executesSequenceReturned (executesReturnValue (negativeOne_evaluates program.core written)))))))
  let firstState := before.bindLocal 8 (.signed .i32 entry.assignment.first)
  have firstWF : StateWellFormed firstState := bindLocal_preserves_well_formed _ _ _ entry.wellFormed
  have run := executesLetLocal (id := 8) (type := i32) firstRead
    (executesLetLocal (id := 9) (type := i32) secondRead tailRun)
  have closed := CellEffect.closeLocal before 8 (.signed .i32 entry.assignment.first) entry.wellFormed
    (CellEffect.closeLocal firstState 9 (.signed .i32 (secondWord entry.assignment)) firstWF effect)
  exact ⟨restoreLocals before written, run, backing, closed⟩

end Lanius.Extraction.CompactOutput.Assignments
