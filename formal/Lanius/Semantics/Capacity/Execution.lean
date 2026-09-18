import Lanius.Semantics.Capacity.Execution.Expression
import Lanius.Semantics.Capacity.Execution.Place
import Lanius.Semantics.Capacity.Execution.Statement
import Lanius.Semantics.Capacity.Execution.Iteration

namespace Lanius.Semantics.Capacity
open Lanius.Core

/-- Successful computations in the checked fragment are invariant under
extension of one reachable backing array and its slice capacity. The unused
tail is retained exactly; no re-execution premise for the expanded state is
required. -/
theorem execution (valid : config.Valid) (checked : Fragment.Checked program allowed) (fuel : Nat) :
    Execution.Step fuel config allowed program := by
  induction fuel with
  | zero => exact Execution.zero config allowed program
  | succ fuel ih =>
    exact ⟨Execution.expression valid checked ih, Execution.expressions ih,
      Execution.place valid ih, Execution.forRange valid ih, Execution.statement valid ih⟩

end Lanius.Semantics.Capacity
