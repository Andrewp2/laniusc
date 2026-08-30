import Lanius.FunctionalViewCore
import Lanius.Separation
import Lanius.CallContracts

namespace Lanius.FunctionalView.Core

open Lanius
open Lanius.Core
open Lanius.Semantics
open Lanius.Properties
open Lanius.Separation
open Lanius.FunctionalView

/-! # Generic simulation into structural Core

This file proves the administrative part once: scoped Functional View lets become
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

/-- Read-only FunctionalView operands are ordinary left-to-right Core
    arguments whose intermediate state happens to remain unchanged. -/
theorem ExpressionsEvaluate.toArgumentsEvaluateTo
    (evaluated : ExpressionsEvaluate program state expressions values) :
    CallContracts.ArgumentsEvaluateTo program state expressions values state := by
  induction evaluated with
  | nil => exact CallContracts.ArgumentsEvaluateTo.nil program state
  | cons head tail induction =>
      exact CallContracts.ArgumentsEvaluateTo.cons head induction

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
    Evaluates program state (operation.toCoreExpr expressions) value state ∧
      Represents afterWorld state
  bindLocal : ∀ {world state id value},
    Represents world state → Represents world (state.bindLocal id value)
  restoreLocals : ∀ {world caller completed},
    Represents world completed →
      Represents world (Lanius.Semantics.restoreLocals caller completed)

def EnvironmentMatches (layout : Layout arity) (environment : Env arity)
    (state : State) : Prop :=
  ∀ index, state.local? (layout index) = some (environment index)

/-- Dense source-call bindings corresponding to a FunctionalView
    environment. The source extractor numbers parameters from zero, so this
    is the canonical bridge between an immutable proof environment and the
    structural call protocol. -/
def parameterBindings (environment : Env arity) : List (VarId × Value) :=
  (List.finRange arity).map fun index => (index.val, environment index)

@[simp] theorem parameterBindings_length {arity : Nat}
    (environment : Env arity) :
    (parameterBindings environment).length = arity := by
  simp [parameterBindings]

@[simp] theorem parameterBindings_getElem
    {arity : Nat} (environment : Env arity)
    (index : Nat) (bound : index < arity) :
    (parameterBindings environment)[index]'(by simpa using bound) =
      (index, environment ⟨index, bound⟩) := by
  simp [parameterBindings]

/-- Entering a call with canonical dense bindings realizes the entire
    FunctionalView environment at once. Clients no longer prove one local
    lookup for every source parameter. -/
theorem enterCall_parameterBindings_matches
    (callerWellFormed : StateWellFormed caller) :
    EnvironmentMatches identityLayout environment
      (enterCall caller (parameterBindings environment)) := by
  intro index
  let bindings := parameterBindings environment
  have indexBound : index.val < bindings.length := by
    simpa [bindings] using index.isLt
  have selected : bindings[index.val] =
      (index.val, environment index) := by
    simpa [bindings] using
      parameterBindings_getElem environment index.val index.isLt
  have decomposition : bindings =
      bindings.take index.val ++
        (index.val, environment index) :: bindings.drop (index.val + 1) := by
    calc
      bindings = bindings.take index.val ++ bindings.drop index.val :=
        (List.take_append_drop index.val bindings).symm
      _ = bindings.take index.val ++
          bindings[index.val] :: bindings.drop (index.val + 1) := by
        rw [List.getElem_cons_drop indexBound]
      _ = bindings.take index.val ++
          (index.val, environment index) ::
            bindings.drop (index.val + 1) := by rw [selected]
  have notRebound : ∀ binding,
      binding ∈ bindings.drop (index.val + 1) →
        binding.1 ≠ index.val := by
    intro binding member same
    rw [List.mem_drop_iff_getElem] at member
    obtain ⟨later, laterBound, laterAt⟩ := member
    have positionBound : index.val + 1 + later < bindings.length := by
      omega
    have laterValue : bindings[index.val + 1 + later] =
        (index.val + 1 + later,
          environment ⟨index.val + 1 + later, by
            simpa [bindings] using positionBound⟩) := by
      apply parameterBindings_getElem
    rw [laterValue] at laterAt
    have idsEqual : index.val + 1 + later = binding.1 := by
      simpa using congrArg Prod.fst laterAt
    have impossible : index.val + 1 + later = index.val :=
      idsEqual.trans same
    omega
  change (enterCall caller bindings).local? index.val =
    some (environment index)
  rw [decomposition]
  exact enterCall_local_of_binding caller (bindings.take index.val)
    (bindings.drop (index.val + 1)) index.val (environment index)
    callerWellFormed notRebound

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

theorem LayoutBelow.identity :
    LayoutBelow (identityLayout (arity := arity)) arity :=
  fun index => index.isLt

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
      Evaluates program state (toCoreExpr layout term) value state ∧
        bridge.Represents afterWorld state := by
    cases term with
    | reference reference =>
        cases reference with
        | slot index =>
            simp only [Term.evaluate, Ref.evaluate, toCoreExpr, refToCoreExpr]
              at evaluated ⊢
            cases evaluated
            exact ⟨⟨1, evalLocal_of_local 0 program state _ _
              (environmentMatches index)⟩, represented⟩
        | literal literalValue =>
            simp only [Term.evaluate, Ref.evaluate, toCoreExpr, refToCoreExpr]
              at evaluated ⊢
            cases evaluated
            exact ⟨⟨1, rfl⟩, represented⟩
    | apply operation arguments =>
        simp only [toCoreExpr]
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
    | logicalAnd left right =>
        simp only [toCoreExpr]
        rw [Term.evaluate] at evaluated
        cases leftResult : Term.evaluate machine world environment left with
        | error reason =>
            simp only [leftResult, bind, Except.bind] at evaluated
            contradiction
        | ok pair =>
            obtain ⟨leftValue, leftWorld⟩ := pair
            simp only [leftResult, bind, Except.bind] at evaluated
            cases leftValue with
            | boolean leftBoolean =>
                cases leftBoolean with
                | false =>
                    cases evaluated
                    have leftSound := term_evaluates bridge represented
                      environmentMatches leftResult
                    exact ⟨evaluatesLogicalAndFalse leftSound.1, leftSound.2⟩
                | true =>
                    have leftSound := term_evaluates bridge represented
                      environmentMatches leftResult
                    have rightSound := term_evaluates bridge leftSound.2
                      environmentMatches evaluated
                    exact ⟨evaluatesLogicalAndTrue leftSound.1 rightSound.1,
                      rightSound.2⟩
            | _ => contradiction
    | logicalOr left right =>
        simp only [toCoreExpr]
        rw [Term.evaluate] at evaluated
        cases leftResult : Term.evaluate machine world environment left with
        | error reason =>
            simp only [leftResult, bind, Except.bind] at evaluated
            contradiction
        | ok pair =>
            obtain ⟨leftValue, leftWorld⟩ := pair
            simp only [leftResult, bind, Except.bind] at evaluated
            cases leftValue with
            | boolean leftBoolean =>
                cases leftBoolean with
                | false =>
                    have leftSound := term_evaluates bridge represented
                      environmentMatches leftResult
                    have rightSound := term_evaluates bridge leftSound.2
                      environmentMatches evaluated
                    exact ⟨evaluatesLogicalOrFalse leftSound.1 rightSound.1,
                      rightSound.2⟩
                | true =>
                    cases evaluated
                    have leftSound := term_evaluates bridge represented
                      environmentMatches leftResult
                    exact ⟨evaluatesLogicalOrTrue leftSound.1, leftSound.2⟩
            | _ => contradiction

  theorem terms_evaluate
      (bridge : ReadOnlyBridge machine program)
      (represented : bridge.Represents world state)
      (environmentMatches : EnvironmentMatches layout environment state)
      (evaluated : evaluateTerms machine world environment terms =
        .ok (values, afterWorld)) :
      ExpressionsEvaluate program state (toCoreExprs layout terms) values ∧
        bridge.Represents afterWorld state := by
    cases terms with
    | nil =>
        simp only [evaluateTerms, toCoreExprs] at evaluated ⊢
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

def toCoreCompletion : FunctionalView.Completion → Semantics.Completion
  | .next => .next
  | .returned value => .returned value

/-- Generic structural simulation for the straight-line/conditional Functional View
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
      Executes program state (toCoreStmt layout nextLocal block)
        (toCoreCompletion completion) after ∧
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

/-- Allocation-free Functional View blocks execute in the original structural state.
    This stronger specialization is useful for pure classifiers: callers keep
    an exact final-state contract without proving every conditional and early
    return directly in structural Core. -/
theorem block_executes_without_locals
    (bridge : ReadOnlyBridge machine program)
    (represented : bridge.Represents world state)
    (environmentMatches : EnvironmentMatches layout environment state)
    (noLocals : localCapacity block = 0)
    (evaluated : Block.evaluate machine world environment block =
      .done completion afterWorld) :
    Executes program state (toCoreStmt layout nextLocal block)
        (toCoreCompletion completion) state ∧
      bridge.Represents afterWorld state := by
  induction block generalizing world completion afterWorld nextLocal with
  | skip =>
      simp only [Block.evaluate] at evaluated
      cases evaluated
      exact ⟨executesSkip program state, represented⟩
  | returnValue value =>
      cases value with
      | none =>
          simp only [Block.evaluate] at evaluated
          cases evaluated
          exact ⟨executesReturnNone program state, represented⟩
      | some expression =>
          rw [Block.evaluate] at evaluated
          generalize expressionResult :
            Term.evaluate machine world environment expression = result
              at evaluated
          cases result with
          | error reason => simp at evaluated
          | ok pair =>
              obtain ⟨value, resultWorld⟩ := pair
              cases evaluated
              have sound := term_evaluates bridge represented
                environmentMatches expressionResult
              exact ⟨executesReturnValue sound.1, sound.2⟩
  | letValue type initializer body induction =>
      simp [localCapacity] at noLocals
  | sequence first second firstInduction secondInduction =>
      simp only [localCapacity] at noLocals
      have firstNoLocals : localCapacity first = 0 := by
        omega
      have secondNoLocals : localCapacity second = 0 := by
        omega
      simp only [Block.evaluate] at evaluated
      generalize firstResult : Block.evaluate machine world environment first =
        result at evaluated
      cases result with
      | trapped reason trappedWorld => simp at evaluated
      | done firstCompletion firstWorld =>
          cases firstCompletion with
          | returned value =>
              cases evaluated
              have firstSound := firstInduction represented environmentMatches
                firstNoLocals firstResult (nextLocal := nextLocal)
              simpa [toCoreStmt, toCoreCompletion, firstNoLocals] using
                And.intro (executesSequenceReturned firstSound.1) firstSound.2
          | next =>
              have firstSound := firstInduction represented environmentMatches
                firstNoLocals firstResult (nextLocal := nextLocal)
              have secondSound := secondInduction firstSound.2
                environmentMatches secondNoLocals evaluated
                (nextLocal := nextLocal)
              simpa [toCoreStmt, firstNoLocals] using
                And.intro (executesSequence firstSound.1 secondSound.1)
                  secondSound.2
  | ifThenElse condition thenBranch elseBranch thenInduction elseInduction =>
      have thenNoLocals : localCapacity thenBranch = 0 := by
        simp [localCapacity] at noLocals
        omega
      have elseNoLocals : localCapacity elseBranch = 0 := by
        simp [localCapacity] at noLocals
        omega
      simp only [Block.evaluate] at evaluated
      generalize conditionResult :
        Term.evaluate machine world environment condition = result at evaluated
      cases result with
      | error reason => simp at evaluated
      | ok pair =>
          obtain ⟨conditionValue, conditionWorld⟩ := pair
          have conditionSound := term_evaluates bridge represented
            environmentMatches conditionResult
          cases conditionValue with
          | boolean value =>
              cases value with
              | false =>
                  have branchSound := elseInduction conditionSound.2
                    environmentMatches elseNoLocals evaluated
                    (nextLocal := nextLocal)
                  exact ⟨executesIfFalse conditionSound.1 branchSound.1,
                    branchSound.2⟩
              | true =>
                  have branchSound := thenInduction conditionSound.2
                    environmentMatches thenNoLocals evaluated
                    (nextLocal := nextLocal)
                  exact ⟨executesIfTrue conditionSound.1 branchSound.1,
                    branchSound.2⟩
          | _ => simp at evaluated

/-- A dependent read-only `let` converts to one scoped Core computation. The
    initializer may feed the body, while the generic proof owns the fresh
    local, environment extension, and restoration of the caller's locals. -/
theorem block_executes_single_let_without_nested_locals
    (bridge : ReadOnlyBridge machine program)
    (represented : bridge.Represents world state)
    (environmentMatches : EnvironmentMatches layout environment state)
    (below : LayoutBelow layout nextLocal)
    (wellFormed : StateWellFormed state)
    (initializerResult : Term.evaluate machine world environment initializer =
      .ok (value, initializerWorld))
    (bodyNoLocals : localCapacity body = 0)
    (evaluated : Block.evaluate machine world environment
        (.letValue type initializer body) = .done completion afterWorld) :
    Executes program state
        (toCoreStmt layout nextLocal (.letValue type initializer body))
        (toCoreCompletion completion)
        (Lanius.Semantics.restoreLocals state
          (state.bindLocal nextLocal value)) ∧
      bridge.Represents afterWorld
        (Lanius.Semantics.restoreLocals state
          (state.bindLocal nextLocal value)) := by
  have initializerSound := term_evaluates bridge represented
    environmentMatches initializerResult
  have boundMatches := environmentMatches.push below wellFormed value
  have boundRepresented := bridge.bindLocal
    (id := nextLocal) (value := value) initializerSound.2
  rw [Block.evaluate, initializerResult] at evaluated
  have bodySound := block_executes_without_locals
    (nextLocal := nextLocal + 1) bridge boundRepresented boundMatches
    bodyNoLocals evaluated
  exact ⟨by
      simpa [toCoreStmt] using
        executesLetLocal initializerSound.1 bodySound.1,
    bridge.restoreLocals bodySound.2⟩

end Lanius.FunctionalView.Core
