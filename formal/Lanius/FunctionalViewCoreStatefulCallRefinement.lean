import Lanius.FunctionalViewCoreEffectfulRefinement
import Lanius.FunctionalViewCoreStateful

namespace Lanius.FunctionalView.Core.Stateful

open Lanius
open Lanius.Core
open Lanius.FunctionalView
open Lanius.FunctionalView.Stateful
open Lanius.FunctionalView.Core.Effectful

/-! # Call-model refinement for stateful FunctionalView commands

An enclosing parser command may provide more source-call routes than a
smaller command used inside it.  This file makes that composition explicit:
an action or command can move between call models only when all calls in the
command satisfy a policy on which the two models agree.
-/

namespace Action

/-- Every source call in an indexed-slice mutation satisfies `allowed`. -/
def callsSatisfy (allowed : FunctionId → Bool) : Action arity → Bool
  | .setI32Index _ index value =>
      termCallsSatisfy allowed index && termCallsSatisfy allowed value

end Action

namespace Command

/-- Every source call nested in a stateful command satisfies `allowed`. -/
def callsSatisfy (allowed : FunctionId → Bool) :
    Command Core.signature actions arity → Bool
  | .skip | .breakLoop | .continueLoop | .returnValue none => true
  | .sequence first second =>
      callsSatisfy allowed first && callsSatisfy allowed second
  | .letValue _ initializer body =>
      termCallsSatisfy allowed initializer && callsSatisfy allowed body
  | .setLocal _ value | .updateLocal _ _ value =>
      termCallsSatisfy allowed value
  | .action operation => Action.callsSatisfy allowed operation
  | .ifThenElse condition thenBranch elseBranch =>
      termCallsSatisfy allowed condition &&
        callsSatisfy allowed thenBranch && callsSatisfy allowed elseBranch
  | .whileLoop condition body =>
      termCallsSatisfy allowed condition && callsSatisfy allowed body
  | .returnValue (some value) => termCallsSatisfy allowed value

end Command

theorem termMachine_evaluate_eq_of_callsSatisfy
    (agreement : first.AgreesWhere allowed second)
    (term : Term Core.signature arity)
    (supported : termCallsSatisfy allowed term = true) :
    Term.evaluate
        (termMachine (Effectful.evaluateOperation program first)) world
        environment term =
      Term.evaluate
        (termMachine (Effectful.evaluateOperation program second)) world
        environment term := by
  simpa [termMachine, Effectful.machine] using
    (Effectful.Term.evaluate_eq_of_callsSatisfy agreement term supported
      (program := program) (world := world) (environment := environment))

theorem evaluateActionWith_eq_of_callsSatisfy
    (agreement : first.AgreesWhere allowed second)
    (supported : Action.callsSatisfy allowed operation = true) :
    evaluateActionWith (Effectful.evaluateOperation program first) world
        environment operation =
      evaluateActionWith (Effectful.evaluateOperation program second) world
        environment operation := by
  cases operation with
  | setI32Index base index value =>
      have components : termCallsSatisfy allowed index = true ∧
          termCallsSatisfy allowed value = true := by
        simpa only [Action.callsSatisfy, Bool.and_eq_true] using supported
      simp only [evaluateActionWith]
      rw [termMachine_evaluate_eq_of_callsSatisfy
        (program := program) (first := first) (second := second)
        (world := world) (environment := environment) agreement index
        components.1]
      apply bind_congr
      intro indexResult
      obtain ⟨indexValue, afterIndex⟩ := indexResult
      rw [termMachine_evaluate_eq_of_callsSatisfy
        (program := program) (first := first) (second := second)
        (world := afterIndex) (environment := environment) agreement value
        components.2]
      rfl

namespace Command.Evaluates

/-- Transport a complete stateful execution between call registries that
    agree on every source call occurring in the command. -/
theorem changeCallModel
    {arity : Nat} {command : Command Core.signature actions arity}
    {beforeWorld afterWorld : ReadOnly.World}
    {beforeEnvironment afterEnvironment : Env arity}
    {completion : Lanius.FunctionalView.Stateful.Completion}
    (agreement : first.AgreesWhere allowed second)
    (supported : Command.callsSatisfy allowed command = true)
    (evaluated : Command.Evaluates
      (termMachine (Effectful.evaluateOperation program first))
      (machineWith program (Effectful.evaluateOperation program first))
      beforeWorld beforeEnvironment command completion afterWorld
      afterEnvironment) :
    Command.Evaluates
      (termMachine (Effectful.evaluateOperation program second))
      (machineWith program (Effectful.evaluateOperation program second))
      beforeWorld beforeEnvironment command completion afterWorld
      afterEnvironment := by
  revert supported
  let motive : {arity : Nat} →
      (beforeWorld : ReadOnly.World) →
      (beforeEnvironment : Env arity) →
      (command : Command Core.signature actions arity) →
      (completion : Lanius.FunctionalView.Stateful.Completion) →
      (afterWorld : ReadOnly.World) →
      (afterEnvironment : Env arity) →
      Command.Evaluates
        (termMachine (Effectful.evaluateOperation program first))
        (machineWith program (Effectful.evaluateOperation program first))
        beforeWorld beforeEnvironment command completion afterWorld
        afterEnvironment → Prop :=
    fun beforeWorld beforeEnvironment command completion afterWorld
        afterEnvironment _ =>
      Command.callsSatisfy allowed command = true →
        Command.Evaluates
          (termMachine (Effectful.evaluateOperation program second))
          (machineWith program (Effectful.evaluateOperation program second))
          beforeWorld beforeEnvironment command completion afterWorld
          afterEnvironment
  change motive beforeWorld beforeEnvironment command completion afterWorld
    afterEnvironment evaluated
  refine @Command.Evaluates.rec
    Core.signature actions
    (termMachine (Effectful.evaluateOperation program first))
    (machineWith program (Effectful.evaluateOperation program first))
    motive ?_ ?_ ?_ ?_ ?_ ?_ ?_ ?_ ?_ ?_ ?_ ?_ ?_ ?_ ?_ ?_ ?_ ?_
    arity beforeWorld beforeEnvironment command completion afterWorld
    afterEnvironment evaluated
  case refine_1 =>
      intro world x environment supported
      exact .skip
  case refine_2 =>
      intro beforeWorld x beforeEnvironment firstCommand middleWorld
        middleEnvironment secondCommand completion afterWorld afterEnvironment
        firstResult secondResult firstIH secondIH supported
      have components : Command.callsSatisfy allowed firstCommand = true ∧
          Command.callsSatisfy allowed secondCommand = true := by
        simpa only [Command.callsSatisfy, Bool.and_eq_true] using supported
      exact .sequenceNext
        (firstIH components.1) (secondIH components.2)
  case refine_3 =>
      intro beforeWorld x beforeEnvironment firstCommand completion afterWorld
        afterEnvironment secondCommand firstResult stops firstIH supported
      have components : Command.callsSatisfy allowed firstCommand = true ∧
          Command.callsSatisfy allowed secondCommand = true := by
        simpa only [Command.callsSatisfy, Bool.and_eq_true] using supported
      exact .sequenceStop
        (firstIH components.1) stops
  case refine_4 =>
      intro beforeWorld x beforeEnvironment initializer value initializedWorld
        body completion afterWorld extendedEnvironment type initializerResult
        bodyResult bodyIH supported
      have components : termCallsSatisfy allowed initializer = true ∧
          Command.callsSatisfy allowed body = true := by
        simpa only [Command.callsSatisfy, Bool.and_eq_true] using supported
      have initializerResult' := initializerResult
      rw [termMachine_evaluate_eq_of_callsSatisfy agreement _ components.1]
        at initializerResult'
      exact .letValue initializerResult' (bodyIH components.2)
  case refine_5 =>
      intro beforeWorld x beforeEnvironment value result afterWorld target
        valueResult supported
      have valueResult' := valueResult
      rw [termMachine_evaluate_eq_of_callsSatisfy agreement _ (by
        simpa only [Command.callsSatisfy] using supported)] at valueResult'
      exact .setLocal valueResult'
  case refine_6 =>
      intro beforeWorld x beforeEnvironment value right afterWorld operation
        target result valueResult updateResult supported
      have valueResult' := valueResult
      rw [termMachine_evaluate_eq_of_callsSatisfy agreement _ (by
        simpa only [Command.callsSatisfy] using supported)] at valueResult'
      exact .updateLocal valueResult' updateResult
  case refine_7 =>
      intro beforeWorld x beforeEnvironment operation afterWorld actionResult
        supported
      change ReadOnly.World at beforeWorld afterWorld
      have actionResult' := actionResult
      change evaluateActionWith (Effectful.evaluateOperation program first)
        _ _ _ = .ok _ at actionResult'
      rw [evaluateActionWith_eq_of_callsSatisfy
        (program := program) (first := first) (second := second)
        (world := beforeWorld) (environment := beforeEnvironment) agreement (by
        simpa only [Command.callsSatisfy] using supported)] at actionResult'
      exact .action actionResult'
  case refine_8 =>
      intro beforeWorld x beforeEnvironment condition conditionWorld
        thenBranch completion afterWorld afterEnvironment elseBranch
        conditionResult branchResult branchIH supported
      have components :
          (termCallsSatisfy allowed condition = true ∧
            Command.callsSatisfy allowed thenBranch = true) ∧
          Command.callsSatisfy allowed elseBranch = true := by
        simpa only [Command.callsSatisfy, Bool.and_eq_true] using supported
      have conditionResult' := conditionResult
      rw [termMachine_evaluate_eq_of_callsSatisfy agreement _ components.1.1]
        at conditionResult'
      exact .ifTrue conditionResult' (branchIH components.1.2)
  case refine_9 =>
      intro beforeWorld x beforeEnvironment condition conditionWorld
        elseBranch completion afterWorld afterEnvironment thenBranch
        conditionResult branchResult branchIH supported
      have components :
          (termCallsSatisfy allowed condition = true ∧
            Command.callsSatisfy allowed thenBranch = true) ∧
          Command.callsSatisfy allowed elseBranch = true := by
        simpa only [Command.callsSatisfy, Bool.and_eq_true] using supported
      have conditionResult' := conditionResult
      rw [termMachine_evaluate_eq_of_callsSatisfy agreement _ components.1.1]
        at conditionResult'
      exact .ifFalse conditionResult' (branchIH components.2)
  case refine_10 =>
      intro beforeWorld x beforeEnvironment condition afterWorld body
        conditionResult supported
      have components : termCallsSatisfy allowed condition = true ∧
          Command.callsSatisfy allowed body = true := by
        simpa only [Command.callsSatisfy, Bool.and_eq_true] using supported
      have conditionSupported := components.1
      have conditionResult' := conditionResult
      rw [termMachine_evaluate_eq_of_callsSatisfy agreement _
        conditionSupported] at conditionResult'
      exact .whileFalse conditionResult'
  case refine_11 =>
      intro beforeWorld x beforeEnvironment condition conditionWorld body
        bodyWorld bodyEnvironment completion afterWorld afterEnvironment
        conditionResult bodyResult restResult bodyIH restIH supported
      have components : termCallsSatisfy allowed condition = true ∧
          Command.callsSatisfy allowed body = true := by
        simpa only [Command.callsSatisfy, Bool.and_eq_true] using supported
      have conditionResult' := conditionResult
      rw [termMachine_evaluate_eq_of_callsSatisfy agreement _ components.1]
        at conditionResult'
      exact .whileNext conditionResult' (bodyIH components.2)
        (restIH supported)
  case refine_12 =>
      intro beforeWorld x beforeEnvironment condition conditionWorld body
        bodyWorld bodyEnvironment completion afterWorld afterEnvironment
        conditionResult bodyResult restResult bodyIH restIH supported
      have components : termCallsSatisfy allowed condition = true ∧
          Command.callsSatisfy allowed body = true := by
        simpa only [Command.callsSatisfy, Bool.and_eq_true] using supported
      have conditionResult' := conditionResult
      rw [termMachine_evaluate_eq_of_callsSatisfy agreement _ components.1]
        at conditionResult'
      exact .whileContinue conditionResult' (bodyIH components.2)
        (restIH supported)
  case refine_13 =>
      intro beforeWorld x beforeEnvironment condition conditionWorld body
        afterWorld afterEnvironment conditionResult bodyResult bodyIH supported
      have components : termCallsSatisfy allowed condition = true ∧
          Command.callsSatisfy allowed body = true := by
        simpa only [Command.callsSatisfy, Bool.and_eq_true] using supported
      have conditionResult' := conditionResult
      rw [termMachine_evaluate_eq_of_callsSatisfy agreement _ components.1]
        at conditionResult'
      exact .whileBreak conditionResult' (bodyIH components.2)
  case refine_14 =>
      intro beforeWorld x beforeEnvironment condition conditionWorld body value
        afterWorld afterEnvironment conditionResult bodyResult bodyIH supported
      have components : termCallsSatisfy allowed condition = true ∧
          Command.callsSatisfy allowed body = true := by
        simpa only [Command.callsSatisfy, Bool.and_eq_true] using supported
      have conditionResult' := conditionResult
      rw [termMachine_evaluate_eq_of_callsSatisfy agreement _ components.1]
        at conditionResult'
      exact .whileReturn conditionResult' (bodyIH components.2)
  case refine_15 =>
      intro world x environment supported
      exact .returnNone
  case refine_16 =>
      intro beforeWorld x beforeEnvironment value result afterWorld valueResult
        supported
      have valueResult' := valueResult
      rw [termMachine_evaluate_eq_of_callsSatisfy agreement _ (by
        simpa only [Command.callsSatisfy] using supported)] at valueResult'
      exact .returnSome valueResult'
  case refine_17 =>
      intro world x environment supported
      exact .breakLoop
  case refine_18 =>
      intro world x environment supported
      exact .continueLoop

end Command.Evaluates

end Lanius.FunctionalView.Core.Stateful
