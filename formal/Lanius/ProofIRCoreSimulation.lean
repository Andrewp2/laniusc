import Lanius.ProofIRCore
import Lanius.Separation

namespace Lanius.ProofIR.Core

open Lanius
open Lanius.Core
open Lanius.Semantics
open Lanius.Properties
open Lanius.Separation
open Lanius.ProofIR

/-! # Generic simulation into structural Core

This file proves the administrative part once: scoped Proof IR lets become
fresh Core cells, branches and early returns compose, and every lexical frame
is restored. A dialect-specific proof supplies only the meaning of primitive
operations and its relation between an abstract world and Core memory.
-/

inductive ExpressionsEvaluate (program : Program) (state : State) :
    List Expr → List Value → Prop where
  | nil : ExpressionsEvaluate program state [] []
  | cons
      (head : Evaluates program state expression value state)
      (tail : ExpressionsEvaluate program state expressions values) :
      ExpressionsEvaluate program state
        (expression :: expressions) (value :: values)

/-- What a proof dialect must establish at the semantic boundary. Primitive
    operations may evolve an abstract proof world, but their structural Core
    implementation must be read-only. Physical lexical-cell allocation is
    handled by the generic block simulation below. -/
structure ReadOnlyBridge (machine : Machine signature) (program : Program) where
  Represents : machine.World → State → Prop
  operation : ∀ {beforeWorld afterWorld state operation expressions values value},
    Represents beforeWorld state →
    ExpressionsEvaluate program state expressions values →
    machine.evalOperation beforeWorld operation values =
      .ok (value, afterWorld) →
    Evaluates program state (operation.lower expressions) value state ∧
      Represents afterWorld state
  bindLocal : ∀ {world state id value},
    Represents world state → Represents world (state.bindLocal id value)
  restoreLocals : ∀ {world caller completed},
    Represents world completed →
      Represents world (Lanius.Semantics.restoreLocals caller completed)

def EnvironmentMatches (layout : Layout arity) (environment : Env arity)
    (state : State) : Prop :=
  ∀ index, state.local? (layout index) = some (environment index)

def LayoutBelow (layout : Layout arity) (nextLocal : VarId) : Prop :=
  ∀ index, layout index < nextLocal

theorem LayoutBelow.push
    (below : LayoutBelow layout nextLocal) :
    LayoutBelow (Layout.push layout nextLocal) (nextLocal + 1) := by
  intro index
  simp only [Layout.push]
  split
  · exact Nat.lt_trans (below _) (Nat.lt_succ_self nextLocal)
  · exact Nat.lt_succ_self nextLocal

theorem LayoutBelow.mono
    (below : LayoutBelow layout nextLocal) (larger : nextLocal ≤ later) :
    LayoutBelow layout later := by
  intro index
  exact Nat.lt_of_lt_of_le (below index) larger

theorem EnvironmentMatches.push
    (environmentMatches : EnvironmentMatches layout environment state)
    (below : LayoutBelow layout nextLocal)
    (wellFormed : StateWellFormed state) (value : Value) :
    EnvironmentMatches (Layout.push layout nextLocal)
      (Env.push environment value) (state.bindLocal nextLocal value) := by
  intro index
  simp only [Layout.push, Env.push]
  split
  · apply bindLocal_preserves_other_local wellFormed
      (Nat.ne_of_lt (below _)).symm |>.trans
    exact environmentMatches _
  · exact bindLocal_finds_local state nextLocal value wellFormed

theorem EnvironmentMatches.preserve
    (environmentMatches : EnvironmentMatches layout environment before)
    (wellFormed : StateWellFormed before)
    (effect : ModifiesOnly CellSet.empty before after) :
    EnvironmentMatches layout environment after := by
  intro index
  exact effect.empty_preserves_local wellFormed (environmentMatches index)

mutual

  theorem term_evaluates
      (bridge : ReadOnlyBridge machine program)
      (represented : bridge.Represents world state)
      (environmentMatches : EnvironmentMatches layout environment state)
      (evaluated : Term.evaluate machine world environment term =
        .ok (value, afterWorld)) :
      Evaluates program state (lowerTerm layout term) value state ∧
        bridge.Represents afterWorld state := by
    cases term with
    | reference reference =>
        cases reference with
        | slot index =>
            simp only [Term.evaluate, Ref.evaluate, lowerTerm, lowerRef]
              at evaluated ⊢
            cases evaluated
            exact ⟨⟨1, evalLocal_of_local 0 program state _ _
              (environmentMatches index)⟩, represented⟩
        | literal literalValue =>
            simp only [Term.evaluate, Ref.evaluate, lowerTerm, lowerRef]
              at evaluated ⊢
            cases evaluated
            exact ⟨⟨1, rfl⟩, represented⟩
    | apply operation arguments =>
        simp only [lowerTerm]
        rw [Term.evaluate] at evaluated
        cases argumentsResult :
          evaluateTerms machine world environment arguments with
        | error error =>
          rw [argumentsResult] at evaluated
          change Except.error error = Except.ok (value, afterWorld) at evaluated
          contradiction
        | ok pair =>
          obtain ⟨argumentValues, argumentsWorld⟩ := pair
          rw [argumentsResult] at evaluated
          change machine.evalOperation argumentsWorld operation argumentValues =
            Except.ok (value, afterWorld) at evaluated
          have argumentsSound := terms_evaluate bridge represented environmentMatches
            argumentsResult
          exact bridge.operation argumentsSound.2 argumentsSound.1 evaluated

  theorem terms_evaluate
      (bridge : ReadOnlyBridge machine program)
      (represented : bridge.Represents world state)
      (environmentMatches : EnvironmentMatches layout environment state)
      (evaluated : evaluateTerms machine world environment terms =
        .ok (values, afterWorld)) :
      ExpressionsEvaluate program state (lowerTerms layout terms) values ∧
        bridge.Represents afterWorld state := by
    cases terms with
    | nil =>
        simp only [evaluateTerms, lowerTerms] at evaluated ⊢
        cases evaluated
        exact ⟨.nil, represented⟩
    | cons head tail =>
        rw [evaluateTerms] at evaluated
        cases headResult :
          Term.evaluate machine world environment head with
        | error error =>
          rw [headResult] at evaluated
          change Except.error error = Except.ok (values, afterWorld) at evaluated
          contradiction
        | ok pair =>
          obtain ⟨headValue, headWorld⟩ := pair
          rw [headResult] at evaluated
          simp only [bind, Except.bind] at evaluated
          cases tailResult :
            evaluateTerms machine headWorld environment tail with
          | error error =>
            rw [tailResult] at evaluated
            change Except.error error = Except.ok (values, afterWorld) at evaluated
            contradiction
          | ok pair =>
            obtain ⟨tailValues, tailWorld⟩ := pair
            rw [tailResult] at evaluated
            change Except.ok (headValue :: tailValues, tailWorld) =
              Except.ok (values, afterWorld) at evaluated
            cases evaluated
            have headSound := term_evaluates bridge represented environmentMatches headResult
            have tailSound := terms_evaluate bridge headSound.2 environmentMatches tailResult
            exact ⟨.cons headSound.1 tailSound.1, tailSound.2⟩

end

def lowerCompletion : ProofIR.Completion → Semantics.Completion
  | .next => .next
  | .returned value => .returned value

/-- Generic structural simulation for the straight-line/conditional Proof IR
    subset. In addition to execution, it proves that the generated lexical
    cells are the only state change and that all caller locals remain valid. -/
theorem block_executes
    (bridge : ReadOnlyBridge machine program)
    (represented : bridge.Represents world state)
    (environmentMatches : EnvironmentMatches layout environment state)
    (below : LayoutBelow layout nextLocal)
    (wellFormed : StateWellFormed state)
    (evaluated : Block.evaluate machine world environment block =
      .done completion afterWorld) :
    ∃ after,
      Executes program state (lowerBlock layout nextLocal block)
        (lowerCompletion completion) after ∧
      ModifiesOnly CellSet.empty state after ∧
      StateWellFormed after ∧
      bridge.Represents afterWorld after ∧
      EnvironmentMatches layout environment after := by
  induction block generalizing world state nextLocal completion
      afterWorld with
  | skip =>
      simp only [Block.evaluate] at evaluated
      cases evaluated
      exact ⟨state, executesSkip program state, ModifiesOnly.refl state,
        wellFormed, represented, environmentMatches⟩
  | returnValue returnValue =>
      cases returnValue with
      | none =>
          simp only [Block.evaluate] at evaluated
          cases evaluated
          exact ⟨state, executesReturnNone program state,
            ModifiesOnly.refl state, wellFormed, represented, environmentMatches⟩
      | some expression =>
          rw [Block.evaluate] at evaluated
          generalize expressionResult :
            Term.evaluate machine world environment expression = result at evaluated
          cases result with
          | error error => simp at evaluated
          | ok pair =>
            obtain ⟨returnValue, returnWorld⟩ := pair
            cases evaluated
            have sound := term_evaluates bridge represented environmentMatches
              expressionResult
            exact ⟨state, executesReturnValue sound.1, ModifiesOnly.refl state,
              wellFormed, sound.2, environmentMatches⟩
  | sequence first second firstInduction secondInduction =>
      simp only [Block.evaluate] at evaluated
      generalize firstResult : Block.evaluate machine world environment first =
        result at evaluated
      cases result with
      | trapped reason trappedWorld => simp at evaluated
      | done firstCompletion firstWorld =>
          cases firstCompletion with
          | returned returnValue =>
              cases evaluated
              obtain ⟨after, execution, effect, afterWellFormed,
                afterRepresented, afterMatches⟩ :=
                firstInduction represented environmentMatches below wellFormed
                  firstResult
              exact ⟨after, executesSequenceReturned execution, effect,
                afterWellFormed, afterRepresented, afterMatches⟩
          | next =>
              obtain ⟨afterFirst, firstExecution, firstEffect,
                firstWellFormed, firstRepresented, firstMatches⟩ :=
                firstInduction represented environmentMatches below wellFormed
                  firstResult
              have secondBelow := below.mono
                (Nat.le_add_right nextLocal (localCapacity first))
              obtain ⟨afterSecond, secondExecution, secondEffect,
                secondWellFormed, secondRepresented, secondMatches⟩ :=
                secondInduction firstRepresented firstMatches secondBelow
                  firstWellFormed evaluated
              exact ⟨afterSecond, executesSequence firstExecution secondExecution,
                firstEffect.trans_same secondEffect, secondWellFormed,
                secondRepresented, secondMatches⟩
  | letValue type initializer body induction =>
      simp only [Block.evaluate] at evaluated
      generalize initializerResult :
        Term.evaluate machine world environment initializer = result at evaluated
      cases result with
      | error reason => simp at evaluated
      | ok pair =>
          obtain ⟨value, initializerWorld⟩ := pair
          have initializerSound := term_evaluates bridge represented environmentMatches
            initializerResult
          let bound := state.bindLocal nextLocal value
          have boundWellFormed := bindLocal_preserves_well_formed state
            nextLocal value wellFormed
          have boundMatches := environmentMatches.push below wellFormed value
          have boundRepresented := bridge.bindLocal
            (id := nextLocal) (value := value) initializerSound.2
          obtain ⟨completed, bodyExecution, bodyEffect, completedWellFormed,
            completedRepresented, _⟩ :=
            induction boundRepresented boundMatches below.push
              boundWellFormed evaluated
          let after := Lanius.Semantics.restoreLocals state completed
          have scopeEffect : ModifiesOnly CellSet.empty state after := by
            exact temporaryLocal_effect nextLocal value bodyEffect.toStoreEffect
          have afterWellFormed : StateWellFormed after := by
            have beforeRestore : StoreEffect CellSet.empty state completed :=
              (bindLocal_effect state nextLocal value).trans_same
                bodyEffect.toStoreEffect
            simpa [after] using
              beforeRestore.restoreLocals_wellFormed wellFormed
                completedWellFormed
          have afterRepresented : bridge.Represents afterWorld after := by
            exact bridge.restoreLocals completedRepresented
          have afterMatches := environmentMatches.preserve wellFormed scopeEffect
          exact ⟨after, executesLetLocal initializerSound.1 bodyExecution,
            scopeEffect, afterWellFormed, afterRepresented, afterMatches⟩
  | ifThenElse condition thenBranch elseBranch thenInduction elseInduction =>
      simp only [Block.evaluate] at evaluated
      generalize conditionResult :
        Term.evaluate machine world environment condition = result at evaluated
      cases result with
      | error reason => simp at evaluated
      | ok pair =>
          obtain ⟨conditionValue, conditionWorld⟩ := pair
          have conditionSound := term_evaluates bridge represented environmentMatches
            conditionResult
          cases conditionValue with
          | boolean conditionValue =>
              cases conditionValue with
              | false =>
                  obtain ⟨after, execution, effect, afterWellFormed,
                    afterRepresented, afterMatches⟩ :=
                    elseInduction conditionSound.2 environmentMatches below wellFormed
                      evaluated
                  exact ⟨after, executesIfFalse conditionSound.1 execution,
                    effect, afterWellFormed, afterRepresented, afterMatches⟩
              | true =>
                  obtain ⟨after, execution, effect, afterWellFormed,
                    afterRepresented, afterMatches⟩ :=
                    thenInduction conditionSound.2 environmentMatches below wellFormed
                      evaluated
                  exact ⟨after, executesIfTrue conditionSound.1 execution,
                    effect, afterWellFormed, afterRepresented, afterMatches⟩
          | _ => simp at evaluated

end Lanius.ProofIR.Core
