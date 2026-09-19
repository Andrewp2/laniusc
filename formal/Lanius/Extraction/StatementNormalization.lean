import Lanius.ExecutionRules

namespace Lanius.Extraction

open Lanius
open Lanius.Core
open Lanius.Semantics
open Lanius.Fuel

/-- Remove the operationally redundant `skip` that terminates a lowered
    source statement list. This is a verified Core-to-Core normalization, not
    part of the trusted extractor. -/
def removeTrailingSkips : Stmt → Stmt
  | .skip => .skip
  | .expression expression => .expression expression
  | .sequence first second =>
      let first := removeTrailingSkips first
      match removeTrailingSkips second with
      | .skip => first
      | second => .sequence first second
  | .letLocal id ty initializer body =>
      .letLocal id ty initializer (removeTrailingSkips body)
  | .letUninitialized id ty body =>
      .letUninitialized id ty (removeTrailingSkips body)
  | .ifThenElse condition thenBranch elseBranch =>
      .ifThenElse condition (removeTrailingSkips thenBranch)
        (removeTrailingSkips elseBranch)
  | .whileLoop condition body => .whileLoop condition (removeTrailingSkips body)
  | .forValues id iterable body => .forValues id iterable (removeTrailingSkips body)
  | .forRange id start stop inclusive body =>
      .forRange id start stop inclusive (removeTrailingSkips body)
  | .returnValue value => .returnValue value
  | .breakLoop => .breakLoop
  | .continueLoop => .continueLoop

/-- Executable recognition of the structured control-flow subset covered by
    the first normalization proof. -/
def skipNormalizationSupported : Stmt → Bool
  | .skip | .expression _ | .returnValue _ | .breakLoop | .continueLoop => true
  | .sequence first second =>
      skipNormalizationSupported first && skipNormalizationSupported second
  | .letLocal _ _ _ body | .letUninitialized _ _ body |
      .whileLoop _ body => skipNormalizationSupported body
  | .ifThenElse _ thenBranch elseBranch =>
      skipNormalizationSupported thenBranch &&
        skipNormalizationSupported elseBranch
  | .forValues _ _ _ | .forRange _ _ _ _ _ => false

/-- The first normalization proof covers the structured control-flow subset
    used by the verified lexer scanners. Collection/range loops will be added
    with the mutually recursive loop evaluators when their extracted programs
    are connected. -/
def SkipNormalizationSupported (statement : Stmt) : Prop :=
  skipNormalizationSupported statement = true

instance (statement : Stmt) : Decidable (SkipNormalizationSupported statement) :=
  inferInstanceAs (Decidable (skipNormalizationSupported statement = true))

private theorem removeTrailingSkips_complete_at_fuel :
    ∀ fuel statement program state completion finalState,
      SkipNormalizationSupported statement →
      execStmt fuel program state (removeTrailingSkips statement) =
        .done completion finalState →
      ∃ rawFuel, execStmt rawFuel program state statement =
        .done completion finalState := by
  intro fuel
  induction fuel with
  | zero =>
      intro statement program state completion finalState supported execution
      simp [execStmt] at execution
  | succ fuel fuelIH =>
      intro statement program state completion finalState supported execution
      induction statement generalizing program state completion finalState with
      | skip | expression _ | returnValue _ | breakLoop | continueLoop =>
          exact ⟨fuel + 1, execution⟩
      | sequence first second firstIH secondIH =>
          simp only [SkipNormalizationSupported, skipNormalizationSupported,
            Bool.and_eq_true] at supported
          rcases supported with ⟨firstSupported, secondSupported⟩
          simp only [removeTrailingSkips] at execution
          split at execution
          next normalizedSecond normalizedSecondEq =>
            have firstExecution := firstIH program state completion finalState
              firstSupported execution
            have secondNormalizedSkip : removeTrailingSkips second = .skip := by
              simpa using normalizedSecondEq
            have secondSkipExecution :
                execStmt (fuel + 1) program finalState
                  (removeTrailingSkips second) = .done .next finalState := by
              rw [secondNormalizedSkip]
              rfl
            have secondExecution := secondIH program finalState .next finalState
              secondSupported secondSkipExecution
            cases completion with
            | next =>
                exact executesSequence firstExecution secondExecution
            | returned _ | breakLoop | continueLoop =>
                exact executesSequenceNonNext firstExecution (by simp)
          next normalizedSecond normalizedSecondEq =>
            simp only [execStmt] at execution
            cases firstResult :
                execStmt fuel program state (removeTrailingSkips first) with
            | outOfFuel | trapped _ _ | exited _ _ => simp [firstResult] at execution
            | done firstCompletion middle =>
                rw [firstResult] at execution
                have firstExecution := fuelIH first program state firstCompletion middle
                  firstSupported firstResult
                cases firstCompletion with
                | next =>
                    have secondExecution := fuelIH second program middle completion
                      finalState secondSupported execution
                    exact executesSequence firstExecution secondExecution
                | returned _ | breakLoop | continueLoop =>
                    cases execution
                    exact executesSequenceNonNext firstExecution (by simp)
      | letLocal id ty initializer body bodyIH =>
          simp only [SkipNormalizationSupported, skipNormalizationSupported] at supported
          simp only [removeTrailingSkips, execStmt] at execution
          cases initializerResult : evalExpr fuel program state initializer with
          | outOfFuel | trapped _ _ | exited _ _ => simp [initializerResult] at execution
          | done value afterInitializer =>
              simp only [initializerResult] at execution
              cases bodyResult : execStmt fuel program
                  (afterInitializer.bindLocal id value)
                  (removeTrailingSkips body) with
              | outOfFuel | trapped _ _ | exited _ _ =>
                  simp [bodyResult, restoreOutcomeLocals] at execution
              | done bodyCompletion completed =>
                  simp only [bodyResult, restoreOutcomeLocals] at execution
                  have bodyExecution := fuelIH body program
                    (afterInitializer.bindLocal id value) bodyCompletion completed
                    supported bodyResult
                  cases execution
                  exact executesLetLocal ⟨fuel, initializerResult⟩ bodyExecution
      | letUninitialized id ty body bodyIH =>
          simp only [SkipNormalizationSupported, skipNormalizationSupported] at supported
          simp only [removeTrailingSkips, execStmt] at execution
          cases bodyResult : execStmt fuel program (state.bindUninitialized id)
              (removeTrailingSkips body) with
          | outOfFuel | trapped _ _ | exited _ _ =>
              simp [bodyResult, restoreOutcomeLocals] at execution
          | done bodyCompletion completed =>
              simp only [bodyResult, restoreOutcomeLocals] at execution
              have bodyExecution := fuelIH body program
                (state.bindUninitialized id) bodyCompletion completed supported bodyResult
              cases execution
              obtain ⟨bodyFuel, bodyExecution⟩ := bodyExecution
              refine ⟨bodyFuel + 1, ?_⟩
              simp only [execStmt]
              rw [bodyExecution]
              rfl
      | ifThenElse condition thenBranch elseBranch thenIH elseIH =>
          simp only [SkipNormalizationSupported, skipNormalizationSupported,
            Bool.and_eq_true] at supported
          rcases supported with ⟨thenSupported, elseSupported⟩
          simp only [removeTrailingSkips, execStmt] at execution
          cases conditionResult : evalExpr fuel program state condition with
          | outOfFuel | trapped _ _ | exited _ _ => simp [conditionResult] at execution
          | done value afterCondition =>
              simp only [conditionResult] at execution
              cases value with
              | boolean conditionValue =>
                  cases conditionValue with
                  | false =>
                      have branchExecution := fuelIH elseBranch program afterCondition
                        completion finalState elseSupported execution
                      exact executesIfFalse ⟨fuel, conditionResult⟩ branchExecution
                  | true =>
                      have branchExecution := fuelIH thenBranch program afterCondition
                        completion finalState thenSupported execution
                      exact executesIfTrue ⟨fuel, conditionResult⟩ branchExecution
              | _ => simp at execution
      | whileLoop condition body bodyIH =>
          simp only [SkipNormalizationSupported, skipNormalizationSupported] at supported
          simp only [removeTrailingSkips, execStmt] at execution
          cases conditionResult : evalExpr fuel program state condition with
          | outOfFuel | trapped _ _ | exited _ _ => simp [conditionResult] at execution
          | done value afterCondition =>
              simp only [conditionResult] at execution
              cases value with
              | boolean conditionValue =>
                  cases conditionValue with
                  | false =>
                      cases execution
                      exact executesWhileFalse ⟨fuel, conditionResult⟩
                  | true =>
                      cases bodyResult : execStmt fuel program afterCondition
                          (removeTrailingSkips body) with
                      | outOfFuel | trapped _ _ | exited _ _ => simp [bodyResult] at execution
                      | done bodyCompletion afterBody =>
                          simp only [bodyResult] at execution
                          have bodyExecution := fuelIH body program afterCondition
                            bodyCompletion afterBody supported bodyResult
                          cases bodyCompletion with
                          | next =>
                              have restExecution := fuelIH
                                (.whileLoop condition body) program afterBody completion
                                finalState (by simpa [SkipNormalizationSupported,
                                  skipNormalizationSupported] using supported)
                                execution
                              exact executesWhileTrueThen ⟨fuel, conditionResult⟩
                                bodyExecution restExecution
                          | continueLoop =>
                              have restExecution := fuelIH
                                (.whileLoop condition body) program afterBody completion
                                finalState (by simpa [SkipNormalizationSupported,
                                  skipNormalizationSupported] using supported)
                                execution
                              exact executesWhileContinueThen
                                ⟨fuel, conditionResult⟩ bodyExecution restExecution
                          | breakLoop =>
                              cases execution
                              exact executesWhileBreak ⟨fuel, conditionResult⟩
                                bodyExecution
                          | returned returnValue =>
                              cases execution
                              exact executesWhileReturned ⟨fuel, conditionResult⟩
                                bodyExecution
              | _ => simp at execution
      | forValues _ _ _ _ | forRange _ _ _ _ _ =>
          simp [SkipNormalizationSupported, skipNormalizationSupported] at supported

/-- Completeness of trailing-skip removal for successful executions of the
    structured statement subset. The induction is simultaneously on evaluator
    fuel and syntax: syntax handles an erased outer sequence, while decreasing
    fuel handles repeated `while` iterations. -/
theorem removeTrailingSkips_executes_complete
    (supported : SkipNormalizationSupported statement)
    (execution : Executes program state (removeTrailingSkips statement)
      completion finalState) :
    Executes program state statement completion finalState := by
  obtain ⟨fuel, execution⟩ := execution
  exact removeTrailingSkips_complete_at_fuel fuel statement program state
    completion finalState supported execution

end Lanius.Extraction
