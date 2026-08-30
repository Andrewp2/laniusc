import Lanius.FunctionalViewCoreReadOnly

namespace Lanius.FunctionalView.Core.Effectful

open Lanius
open Lanius.Core
open Lanius.Semantics
open Lanius.Properties
open Lanius.Separation
open Lanius.CallContracts
open Lanius.FunctionalView
open Lanius.FunctionalView.Core

/-!
# Effectful FunctionalView simulation

`ReadOnlyBridge` deliberately maps every FunctionalView term to a Core
expression that leaves the structural state unchanged.  Source-language
calls do not satisfy that representation condition: even a logically pure
call allocates fresh parameter cells before restoring the caller's locals.

This bridge threads those representation-only effects explicitly.  Primitive
operations receive the already-simulated, left-to-right argument evaluation
and return a framed Core transition.  The generic term proof composes those
transitions; call registries and other dialects only prove primitive leaves.
-/

theorem evaluateTerms_length
    (evaluated : evaluateTerms machine world environment terms =
      .ok (values, afterWorld)) :
    terms.length = values.length := by
  induction terms generalizing world values afterWorld with
  | nil =>
      simp only [evaluateTerms] at evaluated
      obtain ⟨rfl, rfl⟩ := evaluated
      rfl
  | cons head tail induction =>
      rw [evaluateTerms] at evaluated
      cases headResult : Term.evaluate machine world environment head with
      | error reason =>
          rw [headResult] at evaluated
          contradiction
      | ok result =>
          obtain ⟨headValue, headWorld⟩ := result
          rw [headResult] at evaluated
          simp only [bind, Except.bind] at evaluated
          cases tailResult : evaluateTerms machine headWorld environment tail with
          | error reason =>
              rw [tailResult] at evaluated
              contradiction
          | ok result =>
              obtain ⟨tailValues, tailWorld⟩ := result
              rw [tailResult] at evaluated
              obtain ⟨rfl, rfl⟩ := evaluated
              simp [induction tailResult]

structure Bridge (machine : Machine signature) (program : Program) where
  Represents : machine.World → State → Prop
  operation : ∀ {arity : Nat} {layout : Layout arity}
    {environment : Env arity}
    {argumentsWorld afterWorld : machine.World}
    {before afterArguments : State} {operation : signature.Op}
    {arguments : List (Term signature arity)} {values : List Value}
    {value : Value} {argumentWrites : CellSet},
    StateWellFormed afterArguments →
    Represents argumentsWorld afterArguments →
    EnvironmentMatches layout environment afterArguments →
    arguments.length = values.length →
    ArgumentsEvaluateTo program before (toCoreExprs layout arguments)
      values afterArguments →
    ModifiesOnly argumentWrites before afterArguments →
    machine.evalOperation argumentsWorld operation values =
      .ok (value, afterWorld) →
    ∃ after writes,
      Evaluates program before
        (Operation.toCoreExpr operation (toCoreExprs layout arguments))
        value after ∧
      StateWellFormed after ∧
      Represents afterWorld after ∧
      EnvironmentMatches layout environment after ∧
      ModifiesOnly writes before after

def TermSimulates (bridge : Bridge machine program)
    (layout : Layout arity) (environment : Env arity)
    (beforeWorld : machine.World) (before : State)
    (term : Term signature arity) (value : Value)
    (afterWorld : machine.World) : Prop :=
  ∃ after writes,
    Evaluates program before (toCoreExpr layout term) value after ∧
    StateWellFormed after ∧
    bridge.Represents afterWorld after ∧
    EnvironmentMatches layout environment after ∧
    ModifiesOnly writes before after

def TermsSimulate (bridge : Bridge machine program)
    (layout : Layout arity) (environment : Env arity)
    (beforeWorld : machine.World) (before : State)
    (terms : List (Term signature arity)) (values : List Value)
    (afterWorld : machine.World) : Prop :=
  ∃ after writes,
    ArgumentsEvaluateTo program before (toCoreExprs layout terms) values after ∧
    StateWellFormed after ∧
    bridge.Represents afterWorld after ∧
    EnvironmentMatches layout environment after ∧
    ModifiesOnly writes before after

mutual

  theorem term_evaluates
      (bridge : Bridge machine program)
      (wellFormed : StateWellFormed state)
      (represented : bridge.Represents world state)
      (environmentMatches : EnvironmentMatches layout environment state)
      (evaluated : Term.evaluate machine world environment term =
        .ok (value, afterWorld)) :
      TermSimulates bridge layout environment world state term value
        afterWorld := by
    cases term with
    | reference reference =>
        cases reference with
        | slot index =>
            simp only [Term.evaluate, Ref.evaluate, toCoreExpr, refToCoreExpr]
              at evaluated ⊢
            obtain ⟨rfl, rfl⟩ := evaluated
            exact ⟨state, CellSet.empty,
              ⟨1, evalLocal_of_local 0 program state _ _
                (environmentMatches index)⟩,
              wellFormed, represented, environmentMatches,
              ModifiesOnly.refl state⟩
        | literal literalValue =>
            simp only [Term.evaluate, Ref.evaluate, toCoreExpr, refToCoreExpr]
              at evaluated ⊢
            obtain ⟨rfl, rfl⟩ := evaluated
            exact ⟨state, CellSet.empty, ⟨1, rfl⟩, wellFormed,
              represented, environmentMatches, ModifiesOnly.refl state⟩
    | apply operation arguments =>
        rw [Term.evaluate] at evaluated
        cases argumentsResult :
          evaluateTerms machine world environment arguments with
        | error reason =>
            rw [argumentsResult] at evaluated
            contradiction
        | ok result =>
            obtain ⟨values, argumentsWorld⟩ := result
            rw [argumentsResult] at evaluated
            change machine.evalOperation argumentsWorld operation values =
              .ok (value, afterWorld) at evaluated
            obtain ⟨afterArguments, argumentWrites, argumentsExecution,
              argumentsWellFormed, argumentsRepresented, argumentsMatch,
              argumentsEffect⟩ :=
              terms_evaluate bridge wellFormed represented environmentMatches
                argumentsResult
            exact bridge.operation argumentsWellFormed argumentsRepresented
              argumentsMatch (evaluateTerms_length argumentsResult)
              argumentsExecution argumentsEffect evaluated
    | logicalAnd left right =>
        rw [Term.evaluate] at evaluated
        cases leftResult : Term.evaluate machine world environment left with
        | error reason =>
            simp only [leftResult, bind, Except.bind] at evaluated
            contradiction
        | ok result =>
            obtain ⟨leftValue, leftWorld⟩ := result
            simp only [leftResult, bind, Except.bind] at evaluated
            have leftSound := term_evaluates bridge wellFormed represented
              environmentMatches leftResult
            obtain ⟨afterLeft, leftWrites, leftExecution, leftWellFormed,
              leftRepresented, leftMatches, leftEffect⟩ := leftSound
            cases leftValue with
            | boolean leftBoolean =>
                cases leftBoolean with
                | false =>
                    obtain ⟨rfl, rfl⟩ := evaluated
                    exact ⟨afterLeft, leftWrites,
                      evaluatesLogicalAndFalse leftExecution,
                      leftWellFormed, leftRepresented, leftMatches, leftEffect⟩
                | true =>
                    have rightSound := term_evaluates bridge leftWellFormed
                      leftRepresented leftMatches evaluated
                    obtain ⟨after, rightWrites, rightExecution,
                      afterWellFormed, afterRepresented, afterMatches,
                      rightEffect⟩ := rightSound
                    exact ⟨after, CellSet.union leftWrites rightWrites,
                      evaluatesLogicalAndTrue leftExecution rightExecution,
                      afterWellFormed, afterRepresented, afterMatches,
                      leftEffect.trans rightEffect⟩
            | _ => contradiction
    | logicalOr left right =>
        rw [Term.evaluate] at evaluated
        cases leftResult : Term.evaluate machine world environment left with
        | error reason =>
            simp only [leftResult, bind, Except.bind] at evaluated
            contradiction
        | ok result =>
            obtain ⟨leftValue, leftWorld⟩ := result
            simp only [leftResult, bind, Except.bind] at evaluated
            have leftSound := term_evaluates bridge wellFormed represented
              environmentMatches leftResult
            obtain ⟨afterLeft, leftWrites, leftExecution, leftWellFormed,
              leftRepresented, leftMatches, leftEffect⟩ := leftSound
            cases leftValue with
            | boolean leftBoolean =>
                cases leftBoolean with
                | false =>
                    have rightSound := term_evaluates bridge leftWellFormed
                      leftRepresented leftMatches evaluated
                    obtain ⟨after, rightWrites, rightExecution,
                      afterWellFormed, afterRepresented, afterMatches,
                      rightEffect⟩ := rightSound
                    exact ⟨after, CellSet.union leftWrites rightWrites,
                      evaluatesLogicalOrFalse leftExecution rightExecution,
                      afterWellFormed, afterRepresented, afterMatches,
                      leftEffect.trans rightEffect⟩
                | true =>
                    obtain ⟨rfl, rfl⟩ := evaluated
                    exact ⟨afterLeft, leftWrites,
                      evaluatesLogicalOrTrue leftExecution,
                      leftWellFormed, leftRepresented, leftMatches, leftEffect⟩
            | _ => contradiction

  theorem terms_evaluate
      (bridge : Bridge machine program)
      (wellFormed : StateWellFormed state)
      (represented : bridge.Represents world state)
      (environmentMatches : EnvironmentMatches layout environment state)
      (evaluated : evaluateTerms machine world environment terms =
        .ok (values, afterWorld)) :
      TermsSimulate bridge layout environment world state terms values
        afterWorld := by
    cases terms with
    | nil =>
        simp only [evaluateTerms, toCoreExprs] at evaluated ⊢
        obtain ⟨rfl, rfl⟩ := evaluated
        exact ⟨state, CellSet.empty, ArgumentsEvaluateTo.nil program state,
          wellFormed, represented, environmentMatches, ModifiesOnly.refl state⟩
    | cons head tail =>
        rw [evaluateTerms] at evaluated
        cases headResult : Term.evaluate machine world environment head with
        | error reason =>
            rw [headResult] at evaluated
            contradiction
        | ok result =>
            obtain ⟨headValue, headWorld⟩ := result
            rw [headResult] at evaluated
            simp only [bind, Except.bind] at evaluated
            cases tailResult :
              evaluateTerms machine headWorld environment tail with
            | error reason =>
                rw [tailResult] at evaluated
                contradiction
            | ok result =>
                obtain ⟨tailValues, tailWorld⟩ := result
                rw [tailResult] at evaluated
                obtain ⟨rfl, rfl⟩ := evaluated
                obtain ⟨afterHead, headWrites, headExecution,
                  headWellFormed, headRepresented, headMatches, headEffect⟩ :=
                  term_evaluates bridge wellFormed represented
                    environmentMatches headResult
                obtain ⟨after, tailWrites, tailExecution,
                  afterWellFormed, afterRepresented, afterMatches, tailEffect⟩ :=
                  terms_evaluate bridge headWellFormed headRepresented
                    headMatches tailResult
                exact ⟨after, CellSet.union headWrites tailWrites,
                  ArgumentsEvaluateTo.cons headExecution tailExecution,
                  afterWellFormed, afterRepresented, afterMatches,
                  headEffect.trans tailEffect⟩

end

end Lanius.FunctionalView.Core.Effectful
