import Lanius.FunctionalViewCoreEffectfulStateful
import Lanius.CallContracts
import Lanius.FunctionalViewCoreFreshSimulation
import Lanius.FunctionalViewCoreCallFrame

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

/-- Compose a checked command execution with its source-call frame.  The
    command runs in the canonical fresh parameter frame; the caller's
    representation and argument effect are carried through local restoration. -/
theorem callPreservesFrame
    {program : Program} {calls : Effectful.CallModel}
    {callerArity calleeArity : Nat} {callerLayout : Layout callerArity}
    {callerCell : Fin callerArity → CellId}
    {world afterWorld : ReadOnly.World}
    {callerEnvironment : Env callerArity}
    {calleeEnvironment : Env calleeArity}
    {afterEnvironment : Env calleeArity}
    {before afterArguments : State} {arguments : List (Term Core.signature callerArity)}
    {values : List Value} {argumentWrites : CellSet}
    {function : Function} {body : Stmt} {result : Value}
    {command : Stateful.Command Core.signature Core.Stateful.actions calleeArity}
    (callSoundness : FreshSimulation.FramePreservingCallSoundness program calls)
    (argumentsResult : ArgumentsEvaluateTo program before
      (Core.toCoreExprs callerLayout arguments) values afterArguments)
    (argumentsEffect : ModifiesOnly argumentWrites before afterArguments)
    (functionFound : program.function? function.id = some function)
    (parametersBound : bindParameters function.parameters values =
      some (parameterBindings calleeEnvironment))
    (functionBody : function.body = some body)
    (functionalEvaluation : Stateful.Command.Evaluates
      (Effectful.machine program calls)
      (Stateful.machineWith program (Effectful.evaluateOperation program calls))
      world calleeEnvironment command (.returned (some result))
      afterWorld afterEnvironment)
    (actionFree : FreshSimulation.actionFree command = true)
    (commandExact : Lanius.FunctionalView.Core.Stateful.toCoreStmt
      actionAdapter identityLayout calleeArity command = body)
    (afterArgumentsWellFormed : StateWellFormed afterArguments)
    (represented : Representation callerLayout callerCell world callerEnvironment
      afterArguments) :
    ∃ after,
      Evaluates program before
        (.call function.id (Core.toCoreExprs callerLayout arguments)) result after ∧
      StateWellFormed after ∧
      Representation callerLayout callerCell world callerEnvironment after ∧
      ModifiesOnly argumentWrites before after := by
  let callee := enterCall afterArguments (parameterBindings calleeEnvironment)
  let operations := FreshSimulation.operationSoundness program calls callSoundness
  have simulation := FreshSimulation.commandSoundness operations
    functionalEvaluation actionFree
    (represented.enterCallParameters afterArgumentsWellFormed
      (environment := calleeEnvironment))
    (LayoutBelow.identity (arity := calleeArity))
    (enterCall_preserves_wellFormed afterArgumentsWellFormed)
    (frontier := afterArguments.nextCell)
    (by intro index; simp [callLocalCells])
    (by simpa [callee] using
      (enterCall_effect afterArguments (parameterBindings calleeEnvironment)).nextCell)
  obtain ⟨completed, bodyExecution, completedWellFormed,
      _completedRepresented, bodyEffect⟩ := simulation
  rw [commandExact] at bodyExecution
  change Executes program callee body (.returned (some result)) completed at bodyExecution
  exact represented.callReturned argumentsResult argumentsEffect functionFound
    parametersBound functionBody (by simpa [callee] using bodyExecution)
    afterArgumentsWellFormed completedWellFormed bodyEffect
    (by intro cell written; exact written)

end Lanius.FunctionalView.Core.CheckedSimulation
