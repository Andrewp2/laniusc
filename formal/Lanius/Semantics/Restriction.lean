import Lanius.Semantics.Restriction.Expression
import Lanius.Semantics.Restriction.Arguments
import Lanius.Semantics.Restriction.Place
import Lanius.Semantics.Restriction.Iteration
import Lanius.Semantics.Restriction.Statement

namespace Lanius.Semantics.Restriction
open Lanius.Core

/-- Successful execution depends only on the retained, transitively closed
function set. The state and result are unchanged, not merely related. -/
theorem atFuel (matching : Agreement allowed original restricted) :
    ∀ fuel, Step fuel allowed original restricted := by
  intro fuel
  induction fuel with
  | zero => exact zero allowed original restricted
  | succ fuel induction =>
      constructor
      · intro before code value after evaluated closed
        exact expression induction matching before code value after evaluated closed
      · intro before code values after evaluated closed
        exact expressions induction before code values after evaluated closed
      · intro before value code result after evaluated closed
        exact arms induction before value code result after evaluated closed
      · intro before code result after evaluated closed
        exact place induction before code result after evaluated closed
      · intro before id values body result after executed closed
        exact forValues induction before id values body result after executed closed
      · intro before id current stop inclusive body result after executed closed
        exact forRange induction before id current stop inclusive body result after executed closed
      · intro before code result after executed closed
        exact statement induction before code result after executed closed

theorem evaluates (matching : Agreement allowed original restricted)
    (evaluated : Evaluates original before code value after)
    (closed : Dependencies.expression allowed code = true) :
    Evaluates restricted before code value after := by
  obtain ⟨fuel, evaluated⟩ := evaluated
  exact ⟨fuel, (atFuel matching fuel).expression evaluated closed⟩

theorem executes (matching : Agreement allowed original restricted)
    (executed : Executes original before code result after)
    (closed : Dependencies.statement allowed code = true) :
    Executes restricted before code result after := by
  obtain ⟨fuel, executed⟩ := executed
  exact ⟨fuel, (atFuel matching fuel).statement executed closed⟩

end Lanius.Semantics.Restriction
