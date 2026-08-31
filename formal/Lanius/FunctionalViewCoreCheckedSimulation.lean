import Lanius.FunctionalViewCoreEffectfulStateful
import Lanius.CallContracts

namespace Lanius.FunctionalView.Core.CheckedSimulation

open Lanius.Core
open Lanius.Semantics
open Lanius.Properties
open Lanius.Separation
open Lanius.CallContracts
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Stateful

/-- Transport an evaluated Core FunctionalView command to execution of the
exact checked Core body while preserving its separation-logic effect. -/
theorem bodyExecutes
    {program : Program} {arity : Nat}
    {calls : Effectful.CallModel}
    {world afterWorld : ReadOnly.World}
    {environment afterEnvironment : Env arity}
    {command : Stateful.Command Core.signature actions arity}
    {completion : Stateful.Completion}
    {layout : Layout arity} {localCell : Fin arity → CellId}
    {state : State} {nextLocal : VarId} {body : Stmt}
    (callSoundness : EffectfulStateful.CallSoundness program calls)
    (evaluated : Stateful.Command.Evaluates
      (termMachine (Effectful.evaluateOperation program calls))
      (machineWith program (Effectful.evaluateOperation program calls))
      world environment command completion afterWorld afterEnvironment)
    (represented : Representation layout localCell world environment state)
    (below : LayoutBelow layout nextLocal)
    (wellFormed : StateWellFormed state)
    (exact : Lanius.FunctionalView.Core.Stateful.toCoreStmt
      actionAdapter layout nextLocal command = body) :
    ∃ after writes,
      Executes program state body (Stateful.toCoreCompletion completion) after ∧
      StateWellFormed after ∧
      Representation layout localCell afterWorld afterEnvironment after ∧
      ModifiesOnly writes state after := by
  obtain ⟨after, writes, execution, afterWellFormed, afterRepresented,
      effect⟩ := command_executes
    (EffectfulStateful.expressionSoundness program calls callSoundness)
    (EffectfulStateful.actionSoundness program calls callSoundness)
    evaluated represented below wellFormed
  rw [exact] at execution
  exact ⟨after, writes, execution, afterWellFormed, afterRepresented, effect⟩

/-- Transport an evaluated exact FunctionalView command through the checked
function-call rule. -/
theorem callExecutes
    {program : Program} {arity : Nat}
    {calls : Effectful.CallModel}
    {world afterWorld : ReadOnly.World}
    {environment afterEnvironment : Env arity}
    {command : Stateful.Command Core.signature actions arity}
    {localCell : Fin arity → CellId}
    {before afterArguments : State} {arguments : List Expr}
    {values : List Value} {function : Function} {body : Stmt}
    {result : Value}
    (callSoundness : EffectfulStateful.CallSoundness program calls)
    (argumentsResult : ArgumentsEvaluateTo program before arguments values
      afterArguments)
    (parametersBound : bindParameters function.parameters values =
      some (parameterBindings environment))
    (functionFound : program.function? function.id = some function)
    (functionBody : function.body = some body)
    (evaluated : Stateful.Command.Evaluates
      (termMachine (Effectful.evaluateOperation program calls))
      (machineWith program (Effectful.evaluateOperation program calls))
      world environment command (.returned (some result))
      afterWorld afterEnvironment)
    (represented : Representation identityLayout localCell world environment
      (enterCall afterArguments (parameterBindings environment)))
    (calleeWellFormed : StateWellFormed
      (enterCall afterArguments (parameterBindings environment)))
    (exact : Lanius.FunctionalView.Core.Stateful.toCoreStmt
      actionAdapter identityLayout arity command = body) :
    ∃ completed writes,
      Evaluates program before (.call function.id arguments) result
        (restoreLocals afterArguments completed) ∧
      StateWellFormed completed ∧
      Representation identityLayout localCell afterWorld afterEnvironment
        completed ∧
      ModifiesOnly writes
        (enterCall afterArguments (parameterBindings environment)) completed := by
  obtain ⟨completed, writes, bodyExecution, completedWellFormed,
      completedRepresented, bodyEffect⟩ :=
    bodyExecutes callSoundness evaluated represented
      (LayoutBelow.identity (arity := arity)) calleeWellFormed exact
  exact ⟨completed, writes,
    evaluatesCallReturned argumentsResult functionFound parametersBound
      functionBody bodyExecution,
    completedWellFormed, completedRepresented, bodyEffect⟩

end Lanius.FunctionalView.Core.CheckedSimulation
