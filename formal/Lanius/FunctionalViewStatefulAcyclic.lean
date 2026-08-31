import Lanius.FunctionalViewStateful

namespace Lanius.FunctionalView.Stateful.Acyclic

open Lanius
open Lanius.FunctionalView
open Lanius.FunctionalView.Stateful

/-! A proved executable semantics for loop-free FunctionalView commands.

This is deliberately partial at `whileLoop`: callers use it only after exact
reification has established that the checked source body is acyclic.  Unlike a
second source model, `run?` consumes the recovered FunctionalView command
itself.
-/

def run? (termMachine : FunctionalView.Machine termSignature)
    (machine : Stateful.Machine termMachine actions) :
    termMachine.World → Env arity →
      Command termSignature actions arity →
      Option (Stateful.Completion × termMachine.World × Env arity)
  | world, environment, .skip => some (.next, world, environment)
  | world, environment, .sequence first second =>
      match run? termMachine machine world environment first with
      | some (.next, middleWorld, middleEnvironment) =>
          run? termMachine machine middleWorld middleEnvironment second
      | some (completion, afterWorld, afterEnvironment) =>
          some (completion, afterWorld, afterEnvironment)
      | none => none
  | world, environment, .letValue _ initializer body =>
      match Term.evaluate termMachine world environment initializer with
      | .ok (value, initializedWorld) =>
          match run? termMachine machine initializedWorld
              (environment.push value) body with
          | some (completion, afterWorld, extendedEnvironment) =>
              some (completion, afterWorld, Env.pop extendedEnvironment)
          | none => none
      | .error _ => none
  | world, environment, .setLocal target value =>
      match Term.evaluate termMachine world environment value with
      | .ok (result, afterWorld) =>
          some (.next, afterWorld, Env.set environment target result)
      | .error _ => none
  | world, environment, .updateLocal operation target value =>
      match Term.evaluate termMachine world environment value with
      | .ok (right, afterWorld) =>
          match machine.evalLocalUpdate operation (environment target) right with
          | .ok result =>
              some (.next, afterWorld, Env.set environment target result)
          | .error _ => none
      | .error _ => none
  | world, environment, .action operation =>
      match machine.evalAction world environment operation with
      | .ok afterWorld => some (.next, afterWorld, environment)
      | .error _ => none
  | world, environment, .ifThenElse condition thenBranch elseBranch =>
      match Term.evaluate termMachine world environment condition with
      | .ok (.boolean true, conditionWorld) =>
          run? termMachine machine conditionWorld environment thenBranch
      | .ok (.boolean false, conditionWorld) =>
          run? termMachine machine conditionWorld environment elseBranch
      | _ => none
  | _, _, .whileLoop _ _ => none
  | world, environment, .returnValue none =>
      some (.returned none, world, environment)
  | world, environment, .returnValue (some value) =>
      match Term.evaluate termMachine world environment value with
      | .ok (result, afterWorld) =>
          some (.returned (some result), afterWorld, environment)
      | .error _ => none
  | world, environment, .breakLoop =>
      some (.breakLoop, world, environment)
  | world, environment, .continueLoop =>
      some (.continueLoop, world, environment)

theorem run?_sound
    (ran : run? termMachine machine world environment command =
      some (completion, afterWorld, afterEnvironment)) :
    Command.Evaluates termMachine machine world environment command
      completion afterWorld afterEnvironment := by
  induction command generalizing world completion afterWorld with
  | skip =>
      simp [run?] at ran
      obtain ⟨rfl, rfl, rfl⟩ := ran
      exact .skip
  | sequence first second firstIH secondIH =>
      simp only [run?] at ran
      cases firstResult : run? termMachine machine world environment first with
      | none => simp [firstResult] at ran
      | some result =>
          obtain ⟨firstCompletion, middleWorld, middleEnvironment⟩ := result
          rw [firstResult] at ran
          cases firstCompletion with
          | next =>
              exact .sequenceNext (firstIH firstResult) (secondIH ran)
          | returned value =>
              obtain ⟨rfl, rfl, rfl⟩ := Option.some.inj ran
              exact .sequenceStop (firstIH firstResult) (by simp)
          | breakLoop =>
              obtain ⟨rfl, rfl, rfl⟩ := Option.some.inj ran
              exact .sequenceStop (firstIH firstResult) (by simp)
          | continueLoop =>
              obtain ⟨rfl, rfl, rfl⟩ := Option.some.inj ran
              exact .sequenceStop (firstIH firstResult) (by simp)
  | letValue type initializer body bodyIH =>
      simp only [run?] at ran
      split at ran
      next value initializedWorld initializerResult =>
        split at ran
        next bodyCompletion bodyWorld extendedEnvironment bodyRan =>
          obtain ⟨rfl, rfl, rfl⟩ := ran
          exact .letValue initializerResult (bodyIH bodyRan)
        next => contradiction
      next => contradiction
  | setLocal target value =>
      simp only [run?] at ran
      split at ran
      next result valueWorld valueResult =>
        obtain ⟨rfl, rfl, rfl⟩ := ran
        exact .setLocal valueResult
      next => contradiction
  | updateLocal operation target value =>
      simp only [run?] at ran
      split at ran
      next right valueWorld valueResult =>
        split at ran
        next result updateResult =>
          obtain ⟨rfl, rfl, rfl⟩ := ran
          exact .updateLocal valueResult updateResult
        next => contradiction
      next => contradiction
  | action operation =>
      simp only [run?] at ran
      split at ran
      next actionWorld actionResult =>
        obtain ⟨rfl, rfl, rfl⟩ := ran
        exact .action actionResult
      next => contradiction
  | ifThenElse condition thenBranch elseBranch thenIH elseIH =>
      cases conditionResult : Term.evaluate termMachine world environment
          condition with
      | error reason => simp [run?, conditionResult] at ran
      | ok result =>
          obtain ⟨conditionValue, conditionWorld⟩ := result
          cases conditionValue <;> simp [run?, conditionResult] at ran
          case boolean conditionBoolean =>
            cases conditionBoolean
            · exact .ifFalse conditionResult (elseIH ran)
            · exact .ifTrue conditionResult (thenIH ran)
  | whileLoop => simp [run?] at ran
  | returnValue value =>
      cases value with
      | none =>
          simp [run?] at ran
          obtain ⟨rfl, rfl, rfl⟩ := ran
          exact .returnNone
      | some value =>
          simp only [run?] at ran
          split at ran
          next result valueWorld valueResult =>
            obtain ⟨rfl, rfl, rfl⟩ := ran
            exact .returnSome valueResult
          next => contradiction
  | breakLoop =>
      simp [run?] at ran
      obtain ⟨rfl, rfl, rfl⟩ := ran
      exact .breakLoop
  | continueLoop =>
      simp [run?] at ran
      obtain ⟨rfl, rfl, rfl⟩ := ran
      exact .continueLoop

end Lanius.FunctionalView.Stateful.Acyclic

