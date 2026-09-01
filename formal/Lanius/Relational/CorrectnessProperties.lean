import Lanius.Relational.CallContract
import Lanius.Dynamics

namespace Lanius.Relational

open Lanius.Core
open Lanius.Semantics
open Lanius.Properties
open Lanius.Separation
open Lanius.CallContracts
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.ReadOnly
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.FreshSimulation

/-! # Independent compiler-function correctness properties

`ReturnsCorrectly` constrains successful calls.  The definitions in this file
name the two orthogonal availability properties over the same represented
call-site assumptions.  In particular, neither is a hidden premise of
`ReturnsCorrectly` or of the relational call rule.
-/

/-- All evidence describing one valid concrete call site for a contract.
This package deliberately stops before evaluating the call itself. -/
structure RepresentedCallSite
    {program : CheckedProgram} {signature : FnSignature}
    {function : program.FnRef signature}
    (contract : FnContract program signature function) where
  arity : Nat
  layout : Layout arity
  localCell : Fin arity → CellId
  environment : Env arity
  beforeWorld : ReadOnly.World
  before : State
  afterArguments : State
  arguments : List (Term Core.signature arity)
  argumentWrites : CellSet
  args : contract.Args
  abstractBefore : contract.AbstractState
  pre : contract.Pre args abstractBefore
  abstractBeforeRep : contract.AbstractStateRep abstractBefore beforeWorld
  afterArgumentsWellFormed : StateWellFormed afterArguments
  represented : Representation layout localCell beforeWorld environment
    afterArguments
  argumentsExecution : ArgumentsEvaluateTo program.core before
    (Core.toCoreExprs layout arguments) (contract.encodeArgs args)
    afterArguments
  argumentsEffect : ModifiesOnly argumentWrites before afterArguments

def RepresentedCallSite.expression
    {program : CheckedProgram} {signature : FnSignature}
    {function : program.FnRef signature}
    {contract : FnContract program signature function}
    (site : RepresentedCallSite contract) : Expr :=
  .call function.function.id (Core.toCoreExprs site.layout site.arguments)

/-- No represented, precondition-satisfying call can produce a terminal Core
trap.  Fuel exhaustion is not a trap and therefore cannot prove this property
vacuously. -/
def DoesNotTrap
    {program : CheckedProgram} {signature : FnSignature}
    {function : program.FnRef signature}
    (contract : FnContract program signature function) : Prop :=
  ∀ site : RepresentedCallSite contract, ∀ reason after,
    ¬ Traps program.core site.before site.expression reason after

/-- The two non-trapping terminal observations admitted by the compiler
function termination contract. -/
inductive TerminationResult (program : Program) (before : State)
    (expression : Expr) : Prop where
  | returned
      (evaluated : Evaluates program before expression value after) :
      TerminationResult program before expression
  | rejected
      (evaluated : Lanius.Dynamics.ExprEvaluatesTo program before expression
        (.exited code after)) :
      TerminationResult program before expression

/-- Every represented, precondition-satisfying call either returns normally or
reaches an explicit process rejection/exit at some finite fuel.  This is a
constructive liveness property, not a premise of partial correctness. -/
def Terminates
    {program : CheckedProgram} {signature : FnSignature}
    {function : program.FnRef signature}
    (contract : FnContract program signature function) : Prop :=
  ∀ site : RepresentedCallSite contract,
    TerminationResult program.core site.before site.expression

/-- The intentionally non-collapsed total-correctness bundle.  Keeping three
named fields makes it impossible for callers of partial correctness to acquire
a termination or safety premise accidentally. -/
structure TotalCorrect
    {program : CheckedProgram} {signature : FnSignature}
    {function : program.FnRef signature}
    (contract : FnContract program signature function) : Prop where
  returnsCorrectly : ReturnsCorrectly contract
  doesNotTrap : DoesNotTrap contract
  terminates : Terminates contract

theorem TotalCorrect.returned
    {program : CheckedProgram} {signature : FnSignature}
    {function : program.FnRef signature}
    {contract : FnContract program signature function}
    (total : TotalCorrect contract)
    (site : RepresentedCallSite contract)
    (evaluated : Evaluates program.core site.before site.expression value after) :
    ∃ result abstractAfter afterWorld,
      value = contract.encodeResult result ∧
      contract.AbstractStateRep abstractAfter afterWorld ∧
      contract.Post site.args result site.abstractBefore abstractAfter ∧
      contract.Frame site.abstractBefore abstractAfter ∧
      StateWellFormed after ∧
      Representation site.layout site.localCell afterWorld site.environment after ∧
      ModifiesOnly site.argumentWrites site.before after := by
  exact total.returnsCorrectly site.args site.abstractBefore site.pre
    site.abstractBeforeRep site.afterArgumentsWellFormed site.represented
    site.argumentsExecution site.argumentsEffect evaluated

end Lanius.Relational
