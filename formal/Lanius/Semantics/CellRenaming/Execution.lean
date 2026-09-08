import Lanius.Semantics.CellRenaming.Execution.Expression
import Lanius.Semantics.CellRenaming.Execution.Arguments
import Lanius.Semantics.CellRenaming.Execution.Match
import Lanius.Semantics.CellRenaming.Execution.Place
import Lanius.Semantics.CellRenaming.Execution.Iteration
import Lanius.Semantics.CellRenaming.Execution.Statement

namespace Lanius.Semantics.CellRenaming.Execution
open Lanius.Core

/-- Successful internal-program evaluation is equivariant under a bounded
permutation of runtime cell identities. Fresh allocation and raw addresses
remain unchanged. The program-invariance premise must be supplied separately. -/
theorem atFuel {rename : Permutation boundary}
    (invariant : ProgramInvariant rename.forward program) : ∀ fuel, Step fuel rename program := by
  intro fuel
  induction fuel with
  | zero => exact zero rename program
  | succ fuel induction =>
      constructor
      · intro before input result after ready evaluated
        exact expression induction invariant before input result after ready evaluated
      · intro before input result after ready evaluated
        exact expressions induction before input result after ready evaluated
      · intro before input branches result after ready evaluated
        exact arms induction before input branches result after ready evaluated
      · intro before input result after ready evaluated
        exact place induction before input result after ready evaluated
      · intro before id input body result after ready executed
        exact forValues induction before id input body result after ready executed
      · intro before id current stop inclusive body result after ready executed
        exact forRange induction before id current stop inclusive body result after ready executed
      · intro before input result after ready executed
        exact statement induction before input result after ready executed

theorem evaluates {rename : Permutation boundary}
    (invariant : ProgramInvariant rename.forward program) (ready : boundary ≤ before.nextCell)
    (evaluated : Evaluates program before input result after) :
    Evaluates program (state rename.forward before) (CellRenaming.expression rename.forward input)
      (value rename.forward result) (state rename.forward after) ∧ boundary ≤ after.nextCell := by
  obtain ⟨fuel, evaluated⟩ := evaluated
  obtain ⟨transport, afterReady⟩ := (atFuel invariant fuel).expression ready evaluated
  exact ⟨⟨fuel, transport⟩, afterReady⟩

theorem executes {rename : Permutation boundary}
    (invariant : ProgramInvariant rename.forward program) (ready : boundary ≤ before.nextCell)
    (executed : Executes program before input result after) :
    Executes program (state rename.forward before) (CellRenaming.statement rename.forward input)
      (completion rename.forward result) (state rename.forward after) ∧ boundary ≤ after.nextCell := by
  obtain ⟨fuel, executed⟩ := executed
  obtain ⟨transport, afterReady⟩ := (atFuel invariant fuel).statement ready executed
  exact ⟨⟨fuel, transport⟩, afterReady⟩

end Lanius.Semantics.CellRenaming.Execution
