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
  have term_eq : ∀ {arity : Nat} (world : ReadOnly.World)
      (environment : Env arity) (term : Term Core.signature arity),
      termCallsSatisfy allowed term = true →
      Term.evaluate
          (termMachine (Effectful.evaluateOperation program first)) world
          environment term =
        Term.evaluate
          (termMachine (Effectful.evaluateOperation program second)) world
          environment term := by
    intro arity world environment term supported
    exact termMachine_evaluate_eq_of_callsSatisfy agreement term supported
  have action_eq : ∀ {arity : Nat} (world : ReadOnly.World)
      (environment : Env arity) (operation : actions.Action arity),
      Action.callsSatisfy allowed operation = true →
      evaluateActionWith (Effectful.evaluateOperation program first) world
          environment operation =
        evaluateActionWith (Effectful.evaluateOperation program second) world
          environment operation := by
    intro arity world environment operation supported
    exact evaluateActionWith_eq_of_callsSatisfy agreement supported
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
  apply @Command.Evaluates.rec Core.signature actions
    (termMachine (Effectful.evaluateOperation program first))
    (machineWith program (Effectful.evaluateOperation program first)) motive
  case skip =>
      intro _world _arity _environment supported
      exact .skip
  case sequenceNext =>
      intro beforeWorld _arity beforeEnvironment firstCommand middleWorld
        middleEnvironment secondCommand completion afterWorld afterEnvironment
        firstResult secondResult firstIH secondIH supported
      simp only [Command.callsSatisfy, Bool.and_eq_true] at supported
      exact .sequenceNext
        (firstIH supported.1) (secondIH supported.2)
  case sequenceStop =>
      intro beforeWorld _arity beforeEnvironment firstCommand completion
        afterWorld afterEnvironment secondCommand firstResult stops firstIH
        supported
      simp only [Command.callsSatisfy, Bool.and_eq_true] at supported
      exact .sequenceStop (firstIH supported.1) stops
  case letValue =>
      intro beforeWorld _arity beforeEnvironment initializer value initializedWorld
        body completion afterWorld extendedEnvironment type initializerResult
        bodyResult bodyIH supported
      simp only [Command.callsSatisfy, Bool.and_eq_true] at supported
      rw [term_eq _ _ _ supported.1]
        at initializerResult
      exact .letValue initializerResult (bodyIH supported.2)
  case setLocal =>
      intro beforeWorld _arity beforeEnvironment value result afterWorld target
        valueResult supported
      rw [term_eq _ _ _ (by simpa only [Command.callsSatisfy] using supported)]
        at valueResult
      exact .setLocal valueResult
  case updateLocal =>
      intro beforeWorld _arity beforeEnvironment value right afterWorld operation
        target result valueResult updateResult supported
      rw [term_eq _ _ _ (by simpa only [Command.callsSatisfy] using supported)]
        at valueResult
      exact .updateLocal valueResult updateResult
  case action =>
      intro beforeWorld _arity beforeEnvironment operation afterWorld actionResult
        supported
      change evaluateActionWith (Effectful.evaluateOperation program first)
        beforeWorld beforeEnvironment operation = .ok afterWorld at actionResult
      rw [action_eq _ _ _ (by
        simpa only [Command.callsSatisfy] using supported)] at actionResult
      exact .action actionResult
  case ifTrue =>
      intro beforeWorld _arity beforeEnvironment condition conditionWorld
        thenBranch completion afterWorld afterEnvironment elseBranch
        conditionResult branchResult branchIH supported
      simp only [Command.callsSatisfy, Bool.and_eq_true] at supported
      rw [term_eq _ _ _ supported.1.1]
        at conditionResult
      exact .ifTrue conditionResult (branchIH supported.1.2)
  case ifFalse =>
      intro beforeWorld _arity beforeEnvironment condition conditionWorld
        elseBranch completion afterWorld afterEnvironment thenBranch
        conditionResult branchResult branchIH supported
      simp only [Command.callsSatisfy, Bool.and_eq_true] at supported
      rw [term_eq _ _ _ supported.1.1]
        at conditionResult
      exact .ifFalse conditionResult (branchIH supported.2)
  case whileFalse =>
      intro beforeWorld _arity beforeEnvironment condition afterWorld body
        conditionResult supported
      simp only [Command.callsSatisfy, Bool.and_eq_true] at supported
      rw [term_eq _ _ _ supported.1]
        at conditionResult
      exact .whileFalse conditionResult
  case whileNext =>
      intro beforeWorld _arity beforeEnvironment condition conditionWorld body
        bodyWorld bodyEnvironment completion afterWorld afterEnvironment
        conditionResult bodyResult restResult bodyIH restIH supported
      have loopSupported := supported
      simp only [Command.callsSatisfy, Bool.and_eq_true] at supported
      rw [term_eq _ _ _ supported.1]
        at conditionResult
      exact .whileNext conditionResult (bodyIH supported.2)
        (restIH loopSupported)
  case whileContinue =>
      intro beforeWorld _arity beforeEnvironment condition conditionWorld body
        bodyWorld bodyEnvironment completion afterWorld afterEnvironment
        conditionResult bodyResult restResult bodyIH restIH supported
      have loopSupported := supported
      simp only [Command.callsSatisfy, Bool.and_eq_true] at supported
      rw [term_eq _ _ _ supported.1]
        at conditionResult
      exact .whileContinue conditionResult (bodyIH supported.2)
        (restIH loopSupported)
  case whileBreak =>
      intro beforeWorld _arity beforeEnvironment condition conditionWorld body
        afterWorld afterEnvironment conditionResult bodyResult bodyIH supported
      simp only [Command.callsSatisfy, Bool.and_eq_true] at supported
      rw [term_eq _ _ _ supported.1]
        at conditionResult
      exact .whileBreak conditionResult (bodyIH supported.2)
  case whileReturn =>
      intro beforeWorld _arity beforeEnvironment condition conditionWorld body value
        afterWorld afterEnvironment conditionResult bodyResult bodyIH supported
      simp only [Command.callsSatisfy, Bool.and_eq_true] at supported
      rw [term_eq _ _ _ supported.1]
        at conditionResult
      exact .whileReturn conditionResult (bodyIH supported.2)
  case returnNone =>
      intro _world _arity _environment supported
      exact .returnNone
  case returnSome =>
      intro beforeWorld _arity beforeEnvironment value result afterWorld valueResult
        supported
      rw [term_eq _ _ _ (by simpa only [Command.callsSatisfy] using supported)]
        at valueResult
      exact .returnSome valueResult
  case breakLoop =>
      intro _world _arity _environment supported
      exact .breakLoop
  case continueLoop =>
      intro _world _arity _environment supported
      exact .continueLoop
  exact evaluated

end Command.Evaluates

end Lanius.FunctionalView.Core.Stateful
