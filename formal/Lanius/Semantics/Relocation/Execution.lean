import Lanius.Semantics.Relocation.Execution.Expression
import Lanius.Semantics.Relocation.Execution.Arguments
import Lanius.Semantics.Relocation.Execution.Match
import Lanius.Semantics.Relocation.Execution.Place
import Lanius.Semantics.Relocation.Execution.Iteration
import Lanius.Semantics.Relocation.Execution.Statement

namespace Lanius.Semantics.Relocation.Execution

open Lanius.Core

/-- Check the internal-call boundary with evidence, rather than assuming that
the source modules contain no external function declarations. -/
def checkInternal? (program : Program) : Option (PLift (Internal program)) :=
  if bodies : program.functions.all (fun declaration => declaration.body.isSome) then
    some ⟨by
      intro id declaration found
      exact List.all_eq_true.mp bodies declaration (List.mem_of_find?_eq_some found)⟩
  else none

/-- Successful executions of an internal module survive relocation into a
larger program. The lookup checker supplies exact function/constant matches;
injectivity prevents enum-pattern collisions. No evaluation is trusted. -/
theorem atFuel (matching : Core.Relocation.ProgramMatch symbols smaller larger)
    (injective : Function.Injective symbols.typeId) (internal : Internal smaller) :
    ∀ fuel, Step fuel symbols smaller larger := by
  intro fuel
  induction fuel with
  | zero => exact zero symbols smaller larger
  | succ fuel induction =>
      constructor
      · intro before expr value after evaluated
        exact expression induction matching internal before expr value after evaluated
      · intro before exprs values after evaluated
        exact expressions induction before exprs values after evaluated
      · intro before value branches result after evaluated
        exact arms induction injective before value branches result after evaluated
      · intro before location result after evaluated
        exact place induction before location result after evaluated
      · intro before id values body result after executed
        exact forValues induction before id values body result after executed
      · intro before id current stop inclusive body result after executed
        exact forRange induction matching.target before id current stop inclusive body result after executed
      · intro before body result after executed
        exact statement induction before body result after executed

theorem evaluates (matching : Core.Relocation.ProgramMatch symbols smaller larger)
    (injective : Function.Injective symbols.typeId) (internal : Internal smaller)
    (evaluated : Evaluates smaller before expr value after) :
    Evaluates larger (state symbols before) (Core.Relocation.expression symbols expr)
      (Core.Relocation.value symbols value) (state symbols after) := by
  obtain ⟨fuel, evaluated⟩ := evaluated
  exact ⟨fuel, (atFuel matching injective internal fuel).expression evaluated⟩

theorem executes (matching : Core.Relocation.ProgramMatch symbols smaller larger)
    (injective : Function.Injective symbols.typeId) (internal : Internal smaller)
    (executed : Executes smaller before body result after) :
    Executes larger (state symbols before) (Core.Relocation.statement symbols body)
      (completion symbols result) (state symbols after) := by
  obtain ⟨fuel, executed⟩ := executed
  exact ⟨fuel, (atFuel matching injective internal fuel).statement executed⟩

end Lanius.Semantics.Relocation.Execution
