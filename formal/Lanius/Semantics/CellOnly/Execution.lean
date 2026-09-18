import Lanius.Semantics.CellOnly.Expression
import Lanius.Semantics.CellOnly.Storage
import Lanius.Semantics.CellOnly.Statement

namespace Lanius.Semantics.CellOnly

open Lanius.Core Lanius.Separation

/-- Every successful evaluation in a checked cell-only call closure preserves
the native heap and view registrations. Cell contents and local bindings may
change. This theorem covers recursion without a source-specific induction. -/
theorem execution (checked : Checked program allowed) (fuel : Nat) : Step fuel program allowed := by
  induction fuel with
  | zero => exact zero program allowed
  | succ fuel ih =>
    exact ⟨expressionFrame checked ih, argumentsFrame ih, placeFrame ih, rangeFrame ih, statementFrame ih⟩

theorem Checked.evaluates (checked : Checked program allowed)
    (supported : expression allowed input = true)
    (evaluated : Evaluates program before input result after) : HeapFrame before after := by
  obtain ⟨fuel, evaluated⟩ := evaluated
  exact (execution checked fuel).expression supported evaluated

theorem Checked.executes (checked : Checked program allowed)
    (supported : statement allowed input = true)
    (executed : Executes program before input result after) : HeapFrame before after := by
  obtain ⟨fuel, executed⟩ := executed
  exact (execution checked fuel).statement supported executed

end Lanius.Semantics.CellOnly
