import Lanius.Extraction.CompactOutput.Word.Call
import Lanius.Separation.LocalCall

namespace Lanius.Extraction.CompactOutput.Word

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts

/-- Shared statement used by token, assignment, and node serializers. The
value expression is evaluated in the real caller before entering hex_u32. -/
def assignCall (functionId : FunctionId) (cursorId : VarId)
    (output capacity value : Expr) : Expr :=
  .assign .set (.local cursorId) (.call functionId [output, capacity, read cursorId, value])

theorem assign_word (checked : Checked program byte digit)
    (position : Int) (capacity value : Nat)
    (wellFormed : StateWellFormed before)
    (capacityBound : capacity ≤ original.length) (capacityFit : capacity ≤ 2147483647)
    (valueFit : value ≤ 2147483647)
    (cursor : (Assertion.localPointsTo cursorId cursorCell (some (.signed .i32 position))).holds before)
    (backing : before.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values original)) })
    (outputResult : Evaluates program.core before outputExpression (.slice i32 outputCell [] 0 original.length) before)
    (capacityResult : Evaluates program.core before capacityExpression (.signed .i32 capacity) before)
    (valueResult : Evaluates program.core before valueExpression (.signed .i32 value) before) :
    ∃ after, Evaluates program.core before
        (assignCall checked.source.function.id cursorId outputExpression capacityExpression valueExpression) .unit after ∧
      (Assertion.localPointsTo cursorId cursorCell
        (some (.signed .i32 (appendAll capacity (hexDigits value 8) position original).position))).holds after ∧
      after.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values
          (appendAll capacity (hexDigits value 8) position original).contents)) } ∧
      CellEffect (CellSet.union (CellSet.singleton outputCell) (CellSet.singleton cursorCell)) before after := by
  have distinct : outputCell ≠ cursorCell := by
    intro same
    rw [same, cursor.2] at backing
    cases backing
  obtain ⟨written, run, contents, writeEffect⟩ := checked.write position capacity value wellFormed
    capacityBound capacityFit valueFit backing
    (.cons outputResult (.cons capacityResult
      (.cons (local_evaluates program.core (Assertion.localPointsTo_local _ _ _ _ cursor))
        (.cons valueResult (.nil _ _)))))
  have cursorStill := writeEffect.preserves_localPointsTo wellFormed cursor
    (by simpa only [CellSet.singleton] using Ne.symm distinct)
  obtain ⟨after, assigned, cursorAfter, effect, assignmentEffect⟩ :=
    evaluatesOwnedLocalSet cursor run writeEffect cursorStill
  exact ⟨after, assigned, cursorAfter, assignmentEffect.preserves_entry writeEffect.wellFormed contents
    (by simpa only [CellSet.singleton] using distinct), effect⟩

end Lanius.Extraction.CompactOutput.Word
