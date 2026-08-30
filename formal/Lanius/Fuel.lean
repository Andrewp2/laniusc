import Lanius.Execution

namespace Lanius.Fuel

open Lanius
open Lanius.Core
open Lanius.Semantics

/-- A terminal evaluator outcome is an actual language observation. Running
    out of proof fuel is deliberately excluded. -/
def Terminal : Outcome α → Prop
  | .done _ _ | .trapped _ _ | .exited _ _ => True
  | .outOfFuel => False

/-- The mutually recursive evaluator is stable at `fuel` when every terminal
    result remains identical after adding an arbitrary amount of fuel. -/
structure EvaluatorFuelStableAt (fuel : Nat) : Prop where
  expr : ∀ extra program state expression,
    Terminal (evalExpr fuel program state expression) →
      evalExpr (extra + fuel) program state expression =
        evalExpr fuel program state expression
  exprs : ∀ extra program state expressions,
    Terminal (evalExprs fuel program state expressions) →
      evalExprs (extra + fuel) program state expressions =
        evalExprs fuel program state expressions
  matchArms : ∀ extra program state value arms,
    Terminal (evalMatchArms fuel program state value arms) →
      evalMatchArms (extra + fuel) program state value arms =
        evalMatchArms fuel program state value arms
  place : ∀ extra program state place,
    Terminal (evalPlace fuel program state place) →
      evalPlace (extra + fuel) program state place =
        evalPlace fuel program state place
  forValues : ∀ extra program state id values body,
    Terminal (execForValues fuel program state id values body) →
      execForValues (extra + fuel) program state id values body =
        execForValues fuel program state id values body
  forRange : ∀ extra program state id current stop inclusive body,
    Terminal (execForRange fuel program state id current stop inclusive body) →
      execForRange (extra + fuel) program state id current stop inclusive body =
        execForRange fuel program state id current stop inclusive body
  stmt : ∀ extra program state statement,
    Terminal (execStmt fuel program state statement) →
      execStmt (extra + fuel) program state statement =
        execStmt fuel program state statement

theorem evaluatorFuelStableAt_zero : EvaluatorFuelStableAt 0 := by
  constructor <;> simp [Terminal, evalExpr, evalExprs, evalMatchArms,
    evalPlace, execForValues, execForRange, execStmt]

theorem EvaluatorFuelStableAt.expr_eq
    (stable : EvaluatorFuelStableAt fuel) (extra : Nat)
    (evaluated : evalExpr fuel program state expression = result)
    (terminal : Terminal result) :
    evalExpr (extra + fuel) program state expression = result := by
  rw [stable.expr extra program state expression (by simpa [evaluated])]
  exact evaluated

theorem EvaluatorFuelStableAt.exprs_eq
    (stable : EvaluatorFuelStableAt fuel) (extra : Nat)
    (evaluated : evalExprs fuel program state expressions = result)
    (terminal : Terminal result) :
    evalExprs (extra + fuel) program state expressions = result := by
  rw [stable.exprs extra program state expressions (by simpa [evaluated])]
  exact evaluated

theorem EvaluatorFuelStableAt.matchArms_eq
    (stable : EvaluatorFuelStableAt fuel) (extra : Nat)
    (evaluated : evalMatchArms fuel program state value arms = result)
    (terminal : Terminal result) :
    evalMatchArms (extra + fuel) program state value arms = result := by
  rw [stable.matchArms extra program state value arms (by simpa [evaluated])]
  exact evaluated

theorem EvaluatorFuelStableAt.place_eq
    (stable : EvaluatorFuelStableAt fuel) (extra : Nat)
    (place : Place)
    (evaluated : evalPlace fuel program state place = result)
    (terminal : Terminal result) :
    evalPlace (extra + fuel) program state place = result := by
  rw [stable.place extra program state place (by simpa [evaluated])]
  exact evaluated

theorem EvaluatorFuelStableAt.forValues_eq
    (stable : EvaluatorFuelStableAt fuel) (extra : Nat)
    (id : VarId)
    (evaluated : execForValues fuel program state id values body = result)
    (terminal : Terminal result) :
    execForValues (extra + fuel) program state id values body = result := by
  rw [stable.forValues extra program state id values body (by simpa [evaluated])]
  exact evaluated

theorem EvaluatorFuelStableAt.forRange_eq
    (stable : EvaluatorFuelStableAt fuel) (extra : Nat)
    (id : VarId)
    (evaluated : execForRange fuel program state id current stop inclusive body = result)
    (terminal : Terminal result) :
    execForRange (extra + fuel) program state id current stop inclusive body = result := by
  rw [stable.forRange extra program state id current stop inclusive body
    (by simpa [evaluated])]
  exact evaluated

theorem EvaluatorFuelStableAt.stmt_eq
    (stable : EvaluatorFuelStableAt fuel) (extra : Nat)
    (evaluated : execStmt fuel program state statement = result)
    (terminal : Terminal result) :
    execStmt (extra + fuel) program state statement = result := by
  rw [stable.stmt extra program state statement (by simpa [evaluated])]
  exact evaluated

theorem evalExprs_fuel_stable_succ
    (previous : EvaluatorFuelStableAt fuel) :
    ∀ extra program state expressions,
      Terminal (evalExprs (fuel + 1) program state expressions) →
        evalExprs (extra + (fuel + 1)) program state expressions =
          evalExprs (fuel + 1) program state expressions := by
  intro extra program state expressions terminal
  cases expressions with
  | nil => simp [evalExprs]
  | cons expression expressions =>
      simp only [evalExprs, Nat.add_succ] at terminal ⊢
      cases headResult : evalExpr fuel program state expression with
      | done value next =>
          have headStable := previous.expr_eq extra headResult (by simp [Terminal])
          cases tailResult : evalExprs fuel program next expressions with
          | done values completed =>
              have tailStable := previous.exprs_eq extra tailResult
                (by simp [Terminal])
              simp [headResult, headStable, tailResult, tailStable]
          | trapped reason completed =>
              have tailStable := previous.exprs_eq extra tailResult
                (by simp [Terminal])
              simp [headResult, headStable, tailResult, tailStable]
          | exited code exitedState =>
              have tailStable := previous.exprs_eq extra tailResult
                (by simp [Terminal])
              simp [headResult, headStable, tailResult, tailStable]
          | outOfFuel => simp [headResult, tailResult, Terminal] at terminal
      | trapped reason next =>
          have headStable := previous.expr_eq extra headResult (by simp [Terminal])
          simp [headResult, headStable]
      | exited code exitedState =>
          have headStable := previous.expr_eq extra headResult (by simp [Terminal])
          simp [headResult, headStable]
      | outOfFuel => simp [headResult, Terminal] at terminal

theorem evalMatchArms_fuel_stable_succ
    (previous : EvaluatorFuelStableAt fuel) :
    ∀ extra program state value arms,
      Terminal (evalMatchArms (fuel + 1) program state value arms) →
        evalMatchArms (extra + (fuel + 1)) program state value arms =
          evalMatchArms (fuel + 1) program state value arms := by
  intro extra program state value arms terminal
  cases arms with
  | nil => simp [evalMatchArms]
  | cons arm arms =>
      obtain ⟨pattern, body⟩ := arm
      simp only [evalMatchArms, Nat.add_succ] at terminal ⊢
      cases matched : matchPattern pattern value with
      | none =>
          cases armsResult : evalMatchArms fuel program state value arms with
          | done result next =>
              have stable := previous.matchArms_eq extra armsResult
                (by simp [Terminal])
              simp [matched, armsResult, stable]
          | trapped reason next =>
              have stable := previous.matchArms_eq extra armsResult
                (by simp [Terminal])
              simp [matched, armsResult, stable]
          | exited code next =>
              have stable := previous.matchArms_eq extra armsResult
                (by simp [Terminal])
              simp [matched, armsResult, stable]
          | outOfFuel => simp [matched, armsResult, Terminal] at terminal
      | some bindings =>
          cases bodyResult : evalExpr fuel program (state.bindLocals bindings) body with
          | done result next =>
              have stable := previous.expr_eq extra bodyResult (by simp [Terminal])
              simp [matched, bodyResult, stable, restoreOutcomeLocals]
          | trapped reason next =>
              have stable := previous.expr_eq extra bodyResult (by simp [Terminal])
              simp [matched, bodyResult, stable, restoreOutcomeLocals]
          | exited code next =>
              have stable := previous.expr_eq extra bodyResult (by simp [Terminal])
              simp [matched, bodyResult, stable, restoreOutcomeLocals]
          | outOfFuel =>
              simp [matched, bodyResult, restoreOutcomeLocals, Terminal] at terminal

theorem execForValues_fuel_stable_succ
    (previous : EvaluatorFuelStableAt fuel) :
    ∀ extra program state id values body,
      Terminal (execForValues (fuel + 1) program state id values body) →
        execForValues (extra + (fuel + 1)) program state id values body =
          execForValues (fuel + 1) program state id values body := by
  intro extra program state id values body terminal
  cases values with
  | nil => simp [execForValues]
  | cons value values =>
      simp only [execForValues, Nat.add_succ] at terminal ⊢
      cases bodyResult : execStmt fuel program (state.bindLocal id value) body with
      | done completion completed =>
          have bodyStable := previous.stmt_eq extra bodyResult (by simp [Terminal])
          cases completion with
          | next | continueLoop =>
              cases restResult : execForValues fuel program
                  (restoreLocals state completed) id values body with
              | done result next =>
                  have restStable := previous.forValues_eq extra id restResult
                    (by simp [Terminal])
                  simp [bodyResult, bodyStable, restResult, restStable]
              | trapped reason next =>
                  have restStable := previous.forValues_eq extra id restResult
                    (by simp [Terminal])
                  simp [bodyResult, bodyStable, restResult, restStable]
              | exited code next =>
                  have restStable := previous.forValues_eq extra id restResult
                    (by simp [Terminal])
                  simp [bodyResult, bodyStable, restResult, restStable]
              | outOfFuel =>
                  simp [bodyResult, restResult, Terminal] at terminal
          | breakLoop => simp [bodyResult, bodyStable]
          | returned value => simp [bodyResult, bodyStable]
      | trapped reason completed =>
          have bodyStable := previous.stmt_eq extra bodyResult (by simp [Terminal])
          simp [bodyResult, bodyStable]
      | exited code completed =>
          have bodyStable := previous.stmt_eq extra bodyResult (by simp [Terminal])
          simp [bodyResult, bodyStable]
      | outOfFuel => simp [bodyResult, Terminal] at terminal

theorem execForRange_fuel_stable_succ
    (previous : EvaluatorFuelStableAt fuel) :
    ∀ extra program state id current stop inclusive body,
      Terminal (execForRange (fuel + 1) program state id current stop inclusive body) →
        execForRange (extra + (fuel + 1)) program state id current stop inclusive body =
          execForRange (fuel + 1) program state id current stop inclusive body := by
  intro extra program state id current stop inclusive body terminal
  by_cases isFinished : rangeFinished current stop inclusive = true
  · simp [execForRange, isFinished]
  · have notFinished : rangeFinished current stop inclusive = false := by
      cases finished : rangeFinished current stop inclusive <;> simp_all
    simp only [execForRange, notFinished, Bool.false_eq_true,
      ↓reduceIte, Nat.add_succ] at terminal ⊢
    cases bodyResult : execStmt fuel program
        (state.bindLocal id (.signed .i32 current)) body with
    | done completion completed =>
        have bodyStable := previous.stmt_eq extra bodyResult (by simp [Terminal])
        cases completion with
        | next | continueLoop =>
            let unbound := restoreLocals state completed
            by_cases atInclusiveEnd : (inclusive && stop == some current) = true
            · simp [bodyResult, bodyStable, unbound, atInclusiveEnd]
            · have notAtEnd : (inclusive && stop == some current) = false := by
                cases atEnd : inclusive && stop == some current <;> simp_all
              let next := wrapSigned program.target .i32 (current + 1)
              cases restResult : execForRange fuel program unbound id next stop
                  inclusive body with
              | done result nextState =>
                  have restStable := previous.forRange_eq extra id restResult
                    (by simp [Terminal])
                  simp [bodyResult, bodyStable, unbound, atInclusiveEnd, notAtEnd,
                    next, restResult, restStable]
              | trapped reason nextState =>
                  have restStable := previous.forRange_eq extra id restResult
                    (by simp [Terminal])
                  simp [bodyResult, bodyStable, unbound, atInclusiveEnd, notAtEnd,
                    next, restResult, restStable]
              | exited code nextState =>
                  have restStable := previous.forRange_eq extra id restResult
                    (by simp [Terminal])
                  simp [bodyResult, bodyStable, unbound, atInclusiveEnd, notAtEnd,
                    next, restResult, restStable]
              | outOfFuel =>
                  simp [bodyResult, unbound, atInclusiveEnd, notAtEnd, next,
                    restResult, Terminal] at terminal
        | breakLoop => simp [bodyResult, bodyStable]
        | returned value => simp [bodyResult, bodyStable]
    | trapped reason completed =>
        have bodyStable := previous.stmt_eq extra bodyResult (by simp [Terminal])
        simp [bodyResult, bodyStable]
    | exited code completed =>
        have bodyStable := previous.stmt_eq extra bodyResult (by simp [Terminal])
        simp [bodyResult, bodyStable]
    | outOfFuel => simp [bodyResult, Terminal] at terminal

theorem evalPlace_fuel_stable_succ
    (previous : EvaluatorFuelStableAt fuel) :
    ∀ extra program state place,
      Terminal (evalPlace (fuel + 1) program state place) →
        evalPlace (extra + (fuel + 1)) program state place =
          evalPlace (fuel + 1) program state place := by
  intro extra program state place terminal
  cases place with
  | «local» id => simp [evalPlace]
  | field base field =>
      simp only [evalPlace, Nat.add_succ] at terminal ⊢
      cases baseResult : evalPlace fuel program state base with
      | done resolved next =>
          have baseStable := previous.place_eq extra base baseResult
            (by simp [Terminal])
          simp [baseResult, baseStable]
      | trapped reason next =>
          have baseStable := previous.place_eq extra base baseResult
            (by simp [Terminal])
          simp [baseResult, baseStable]
      | exited code next =>
          have baseStable := previous.place_eq extra base baseResult
            (by simp [Terminal])
          simp [baseResult, baseStable]
      | outOfFuel => simp [baseResult, Terminal] at terminal
  | index base indexExpression =>
      simp only [evalPlace, Nat.add_succ] at terminal ⊢
      cases baseResult : evalPlace fuel program state base with
      | done resolved afterBase =>
          have baseStable := previous.place_eq extra base baseResult
            (by simp [Terminal])
          cases valueResult : resolved.value with
          | none => simp [baseResult, baseStable, valueResult]
          | some value =>
              cases value with
              | array elements =>
                  cases indexResult : evalExpr fuel program afterBase
                      indexExpression with
                  | done indexValue afterIndex =>
                      have indexStable := previous.expr_eq extra indexResult
                        (by simp [Terminal])
                      simp [baseResult, baseStable, valueResult, indexResult,
                        indexStable]
                  | trapped reason next =>
                      have indexStable := previous.expr_eq extra indexResult
                        (by simp [Terminal])
                      simp [baseResult, baseStable, valueResult, indexResult,
                        indexStable]
                  | exited code next =>
                      have indexStable := previous.expr_eq extra indexResult
                        (by simp [Terminal])
                      simp [baseResult, baseStable, valueResult, indexResult,
                        indexStable]
                  | outOfFuel =>
                      simp [baseResult, valueResult, indexResult, Terminal] at terminal
              | slice elementType cell projections start length =>
                  cases indexResult : evalExpr fuel program afterBase
                      indexExpression with
                  | done indexValue afterIndex =>
                      have indexStable := previous.expr_eq extra indexResult
                        (by simp [Terminal])
                      simp [baseResult, baseStable, valueResult, indexResult,
                        indexStable]
                  | trapped reason next =>
                      have indexStable := previous.expr_eq extra indexResult
                        (by simp [Terminal])
                      simp [baseResult, baseStable, valueResult, indexResult,
                        indexStable]
                  | exited code next =>
                      have indexStable := previous.expr_eq extra indexResult
                        (by simp [Terminal])
                      simp [baseResult, baseStable, valueResult, indexResult,
                        indexStable]
                  | outOfFuel =>
                      simp [baseResult, valueResult, indexResult, Terminal] at terminal
              | _ => simp [baseResult, baseStable, valueResult]
      | trapped reason next =>
          have baseStable := previous.place_eq extra base baseResult
            (by simp [Terminal])
          simp [baseResult, baseStable]
      | exited code next =>
          have baseStable := previous.place_eq extra base baseResult
            (by simp [Terminal])
          simp [baseResult, baseStable]
      | outOfFuel => simp [baseResult, Terminal] at terminal

theorem execStmt_fuel_stable_succ
    (previous : EvaluatorFuelStableAt fuel) :
    ∀ extra program state statement,
      Terminal (execStmt (fuel + 1) program state statement) →
        execStmt (extra + (fuel + 1)) program state statement =
          execStmt (fuel + 1) program state statement := by
  intro extra program state statement terminal
  cases statement with
  | skip => simp [execStmt]
  | expression expression =>
      simp only [execStmt, Nat.add_succ] at terminal ⊢
      cases expressionResult : evalExpr fuel program state expression with
      | done value next =>
          have stable := previous.expr_eq extra expressionResult (by simp [Terminal])
          simp [expressionResult, stable]
      | trapped reason next =>
          have stable := previous.expr_eq extra expressionResult (by simp [Terminal])
          simp [expressionResult, stable]
      | exited code next =>
          have stable := previous.expr_eq extra expressionResult (by simp [Terminal])
          simp [expressionResult, stable]
      | outOfFuel => simp [expressionResult, Terminal] at terminal
  | sequence first second =>
      simp only [execStmt, Nat.add_succ] at terminal ⊢
      cases firstResult : execStmt fuel program state first with
      | done completion next =>
          have firstStable := previous.stmt_eq extra firstResult (by simp [Terminal])
          cases completion with
          | next =>
              cases secondResult : execStmt fuel program next second with
              | done completion completed =>
                  have secondStable := previous.stmt_eq extra secondResult
                    (by simp [Terminal])
                  simp [firstResult, firstStable, secondResult, secondStable]
              | trapped reason completed =>
                  have secondStable := previous.stmt_eq extra secondResult
                    (by simp [Terminal])
                  simp [firstResult, firstStable, secondResult, secondStable]
              | exited code completed =>
                  have secondStable := previous.stmt_eq extra secondResult
                    (by simp [Terminal])
                  simp [firstResult, firstStable, secondResult, secondStable]
              | outOfFuel =>
                  simp [firstResult, secondResult, Terminal] at terminal
          | returned value => simp [firstResult, firstStable]
          | breakLoop => simp [firstResult, firstStable]
          | continueLoop => simp [firstResult, firstStable]
      | trapped reason next =>
          have firstStable := previous.stmt_eq extra firstResult (by simp [Terminal])
          simp [firstResult, firstStable]
      | exited code next =>
          have firstStable := previous.stmt_eq extra firstResult (by simp [Terminal])
          simp [firstResult, firstStable]
      | outOfFuel => simp [firstResult, Terminal] at terminal
  | letLocal id type initializer body =>
      simp only [execStmt, Nat.add_succ] at terminal ⊢
      cases initializerResult : evalExpr fuel program state initializer with
      | done value next =>
          have initializerStable := previous.expr_eq extra initializerResult
            (by simp [Terminal])
          cases bodyResult : execStmt fuel program (next.bindLocal id value) body with
          | done completion completed =>
              have bodyStable := previous.stmt_eq extra bodyResult (by simp [Terminal])
              simp [initializerResult, initializerStable, bodyResult, bodyStable,
                restoreOutcomeLocals]
          | trapped reason completed =>
              have bodyStable := previous.stmt_eq extra bodyResult (by simp [Terminal])
              simp [initializerResult, initializerStable, bodyResult, bodyStable,
                restoreOutcomeLocals]
          | exited code completed =>
              have bodyStable := previous.stmt_eq extra bodyResult (by simp [Terminal])
              simp [initializerResult, initializerStable, bodyResult, bodyStable,
                restoreOutcomeLocals]
          | outOfFuel =>
              simp [initializerResult, bodyResult, restoreOutcomeLocals,
                Terminal] at terminal
      | trapped reason next =>
          have initializerStable := previous.expr_eq extra initializerResult
            (by simp [Terminal])
          simp [initializerResult, initializerStable]
      | exited code next =>
          have initializerStable := previous.expr_eq extra initializerResult
            (by simp [Terminal])
          simp [initializerResult, initializerStable]
      | outOfFuel => simp [initializerResult, Terminal] at terminal
  | letUninitialized id type body =>
      simp only [execStmt, Nat.add_succ] at terminal ⊢
      cases bodyResult : execStmt fuel program (state.bindUninitialized id) body with
      | done completion completed =>
          have bodyStable := previous.stmt_eq extra bodyResult (by simp [Terminal])
          simp [bodyResult, bodyStable, restoreOutcomeLocals]
      | trapped reason completed =>
          have bodyStable := previous.stmt_eq extra bodyResult (by simp [Terminal])
          simp [bodyResult, bodyStable, restoreOutcomeLocals]
      | exited code completed =>
          have bodyStable := previous.stmt_eq extra bodyResult (by simp [Terminal])
          simp [bodyResult, bodyStable, restoreOutcomeLocals]
      | outOfFuel =>
          simp [bodyResult, restoreOutcomeLocals, Terminal] at terminal
  | ifThenElse condition thenBranch elseBranch =>
      simp only [execStmt, Nat.add_succ] at terminal ⊢
      cases conditionResult : evalExpr fuel program state condition with
      | done value next =>
          have conditionStable := previous.expr_eq extra conditionResult
            (by simp [Terminal])
          cases value with
          | boolean flag =>
              cases flag with
              | false =>
                  cases branchResult : execStmt fuel program next elseBranch with
                  | done completion completed =>
                      have branchStable := previous.stmt_eq extra branchResult
                        (by simp [Terminal])
                      simp [conditionResult, conditionStable, branchResult, branchStable]
                  | trapped reason completed =>
                      have branchStable := previous.stmt_eq extra branchResult
                        (by simp [Terminal])
                      simp [conditionResult, conditionStable, branchResult, branchStable]
                  | exited code completed =>
                      have branchStable := previous.stmt_eq extra branchResult
                        (by simp [Terminal])
                      simp [conditionResult, conditionStable, branchResult, branchStable]
                  | outOfFuel =>
                      simp [conditionResult, branchResult, Terminal] at terminal
              | true =>
                  cases branchResult : execStmt fuel program next thenBranch with
                  | done completion completed =>
                      have branchStable := previous.stmt_eq extra branchResult
                        (by simp [Terminal])
                      simp [conditionResult, conditionStable, branchResult, branchStable]
                  | trapped reason completed =>
                      have branchStable := previous.stmt_eq extra branchResult
                        (by simp [Terminal])
                      simp [conditionResult, conditionStable, branchResult, branchStable]
                  | exited code completed =>
                      have branchStable := previous.stmt_eq extra branchResult
                        (by simp [Terminal])
                      simp [conditionResult, conditionStable, branchResult, branchStable]
                  | outOfFuel =>
                      simp [conditionResult, branchResult, Terminal] at terminal
          | _ => simp [conditionResult, conditionStable]
      | trapped reason next =>
          have conditionStable := previous.expr_eq extra conditionResult
            (by simp [Terminal])
          simp [conditionResult, conditionStable]
      | exited code next =>
          have conditionStable := previous.expr_eq extra conditionResult
            (by simp [Terminal])
          simp [conditionResult, conditionStable]
      | outOfFuel => simp [conditionResult, Terminal] at terminal
  | returnValue value =>
      cases value with
      | none => simp [execStmt]
      | some expression =>
          simp only [execStmt, Nat.add_succ] at terminal ⊢
          cases expressionResult : evalExpr fuel program state expression with
          | done value next =>
              have stable := previous.expr_eq extra expressionResult (by simp [Terminal])
              simp [expressionResult, stable]
          | trapped reason next =>
              have stable := previous.expr_eq extra expressionResult (by simp [Terminal])
              simp [expressionResult, stable]
          | exited code next =>
              have stable := previous.expr_eq extra expressionResult (by simp [Terminal])
              simp [expressionResult, stable]
          | outOfFuel => simp [expressionResult, Terminal] at terminal
  | breakLoop => simp [execStmt]
  | continueLoop => simp [execStmt]
  | whileLoop condition body =>
      simp only [execStmt, Nat.add_succ] at terminal ⊢
      cases conditionResult : evalExpr fuel program state condition with
      | done value next =>
          have conditionStable := previous.expr_eq extra conditionResult
            (by simp [Terminal])
          cases value with
          | boolean flag =>
              cases flag with
              | false => simp [conditionResult, conditionStable]
              | true =>
                  cases bodyResult : execStmt fuel program next body with
                  | done completion completed =>
                      have bodyStable := previous.stmt_eq extra bodyResult
                        (by simp [Terminal])
                      cases completion with
                      | next | continueLoop =>
                          cases loopResult : execStmt fuel program completed
                              (.whileLoop condition body) with
                          | done result finalState =>
                              have loopStable := previous.stmt_eq extra loopResult
                                (by simp [Terminal])
                              simp [conditionResult, conditionStable, bodyResult,
                                bodyStable, loopResult, loopStable]
                          | trapped reason finalState =>
                              have loopStable := previous.stmt_eq extra loopResult
                                (by simp [Terminal])
                              simp [conditionResult, conditionStable, bodyResult,
                                bodyStable, loopResult, loopStable]
                          | exited code finalState =>
                              have loopStable := previous.stmt_eq extra loopResult
                                (by simp [Terminal])
                              simp [conditionResult, conditionStable, bodyResult,
                                bodyStable, loopResult, loopStable]
                          | outOfFuel =>
                              simp [conditionResult, bodyResult, loopResult,
                                Terminal] at terminal
                      | returned result =>
                          simp [conditionResult, conditionStable, bodyResult, bodyStable]
                      | breakLoop =>
                          simp [conditionResult, conditionStable, bodyResult, bodyStable]
                  | trapped reason completed =>
                      have bodyStable := previous.stmt_eq extra bodyResult
                        (by simp [Terminal])
                      simp [conditionResult, conditionStable, bodyResult, bodyStable]
                  | exited code completed =>
                      have bodyStable := previous.stmt_eq extra bodyResult
                        (by simp [Terminal])
                      simp [conditionResult, conditionStable, bodyResult, bodyStable]
                  | outOfFuel =>
                      simp [conditionResult, bodyResult, Terminal] at terminal
          | _ => simp [conditionResult, conditionStable]
      | trapped reason next =>
          have conditionStable := previous.expr_eq extra conditionResult
            (by simp [Terminal])
          simp [conditionResult, conditionStable]
      | exited code next =>
          have conditionStable := previous.expr_eq extra conditionResult
            (by simp [Terminal])
          simp [conditionResult, conditionStable]
      | outOfFuel => simp [conditionResult, Terminal] at terminal
  | forValues id iterable body =>
      simp only [execStmt, Nat.add_succ] at terminal ⊢
      cases iterableResult : evalExpr fuel program state iterable with
      | done value next =>
          have iterableStable := previous.expr_eq extra iterableResult
            (by simp [Terminal])
          cases value with
          | array values =>
              cases loopResult : execForValues fuel program next id values body with
              | done completion completed =>
                  have loopStable := previous.forValues_eq extra id loopResult
                    (by simp [Terminal])
                  simp [iterableResult, iterableStable, loopResult, loopStable]
              | trapped reason completed =>
                  have loopStable := previous.forValues_eq extra id loopResult
                    (by simp [Terminal])
                  simp [iterableResult, iterableStable, loopResult, loopStable]
              | exited code completed =>
                  have loopStable := previous.forValues_eq extra id loopResult
                    (by simp [Terminal])
                  simp [iterableResult, iterableStable, loopResult, loopStable]
              | outOfFuel =>
                  simp [iterableResult, loopResult, Terminal] at terminal
          | slice elementType cell projections start length =>
              cases sliced : sliceValues next cell projections start length with
              | error reason => simp [iterableResult, iterableStable, sliced]
              | ok values =>
                  cases loopResult : execForValues fuel program next id values body with
                  | done completion completed =>
                      have loopStable := previous.forValues_eq extra id loopResult
                        (by simp [Terminal])
                      simp [iterableResult, iterableStable, sliced, loopResult,
                        loopStable]
                  | trapped reason completed =>
                      have loopStable := previous.forValues_eq extra id loopResult
                        (by simp [Terminal])
                      simp [iterableResult, iterableStable, sliced, loopResult,
                        loopStable]
                  | exited code completed =>
                      have loopStable := previous.forValues_eq extra id loopResult
                        (by simp [Terminal])
                      simp [iterableResult, iterableStable, sliced, loopResult,
                        loopStable]
                  | outOfFuel =>
                      simp [iterableResult, sliced, loopResult, Terminal] at terminal
          | _ => simp [iterableResult, iterableStable]
      | trapped reason next =>
          have iterableStable := previous.expr_eq extra iterableResult
            (by simp [Terminal])
          simp [iterableResult, iterableStable]
      | exited code next =>
          have iterableStable := previous.expr_eq extra iterableResult
            (by simp [Terminal])
          simp [iterableResult, iterableStable]
      | outOfFuel => simp [iterableResult, Terminal] at terminal
  | forRange id start stop inclusive body =>
      simp only [execStmt, Nat.add_succ] at terminal ⊢
      cases startResult : evalExpr fuel program state start with
      | done value afterStart =>
          have startStable := previous.expr_eq extra startResult (by simp [Terminal])
          cases value with
          | signed signedType startValue =>
              cases signedType with
              | i32 =>
                  cases stop with
                  | none =>
                      cases loopResult : execForRange fuel program afterStart id
                          startValue none inclusive body with
                      | done completion completed =>
                          have loopStable := previous.forRange_eq extra id loopResult
                            (by simp [Terminal])
                          simp [startResult, startStable, loopResult, loopStable]
                      | trapped reason completed =>
                          have loopStable := previous.forRange_eq extra id loopResult
                            (by simp [Terminal])
                          simp [startResult, startStable, loopResult, loopStable]
                      | exited code completed =>
                          have loopStable := previous.forRange_eq extra id loopResult
                            (by simp [Terminal])
                          simp [startResult, startStable, loopResult, loopStable]
                      | outOfFuel =>
                          simp [startResult, loopResult, Terminal] at terminal
                  | some stopExpression =>
                      cases stopResult : evalExpr fuel program afterStart stopExpression with
                      | done stopValue afterStop =>
                          have stopStable := previous.expr_eq extra stopResult
                            (by simp [Terminal])
                          cases stopValue with
                          | signed stopType stopValue =>
                              cases stopType with
                              | i32 =>
                                  cases loopResult : execForRange fuel program afterStop id
                                      startValue (some stopValue) inclusive body with
                                  | done completion completed =>
                                      have loopStable := previous.forRange_eq extra id
                                        loopResult (by simp [Terminal])
                                      simp [startResult, startStable, stopResult, stopStable,
                                        loopResult, loopStable]
                                  | trapped reason completed =>
                                      have loopStable := previous.forRange_eq extra id
                                        loopResult (by simp [Terminal])
                                      simp [startResult, startStable, stopResult, stopStable,
                                        loopResult, loopStable]
                                  | exited code completed =>
                                      have loopStable := previous.forRange_eq extra id
                                        loopResult (by simp [Terminal])
                                      simp [startResult, startStable, stopResult, stopStable,
                                        loopResult, loopStable]
                                  | outOfFuel =>
                                      simp [startResult, stopResult, loopResult,
                                        Terminal] at terminal
                              | _ =>
                                  simp [startResult, startStable, stopResult, stopStable]
                          | _ => simp [startResult, startStable, stopResult, stopStable]
                      | trapped reason next =>
                          have stopStable := previous.expr_eq extra stopResult
                            (by simp [Terminal])
                          simp [startResult, startStable, stopResult, stopStable]
                      | exited code next =>
                          have stopStable := previous.expr_eq extra stopResult
                            (by simp [Terminal])
                          simp [startResult, startStable, stopResult, stopStable]
                      | outOfFuel =>
                          simp [startResult, stopResult, Terminal] at terminal
              | _ => simp [startResult, startStable]
          | _ => simp [startResult, startStable]
      | trapped reason next =>
          have startStable := previous.expr_eq extra startResult (by simp [Terminal])
          simp [startResult, startStable]
      | exited code next =>
          have startStable := previous.expr_eq extra startResult (by simp [Terminal])
          simp [startResult, startStable]
      | outOfFuel => simp [startResult, Terminal] at terminal

theorem evalExpr_fuel_stable_succ
    (previous : EvaluatorFuelStableAt fuel) :
    ∀ extra program state expression,
      Terminal (evalExpr (fuel + 1) program state expression) →
        evalExpr (extra + (fuel + 1)) program state expression =
          evalExpr (fuel + 1) program state expression := by
  intro extra program state expression terminal
  cases expression with
  | value value => simp [evalExpr]
  | «local» id => simp [evalExpr]
  | constant id => simp [evalExpr]
  | cast target operand =>
      simp only [evalExpr, Nat.add_succ] at terminal ⊢
      cases operandResult : evalExpr fuel program state operand with
      | done value next =>
          have stable := previous.expr_eq extra operandResult (by simp [Terminal])
          simp [operandResult, stable]
      | trapped reason next =>
          have stable := previous.expr_eq extra operandResult (by simp [Terminal])
          simp [operandResult, stable]
      | exited code next =>
          have stable := previous.expr_eq extra operandResult (by simp [Terminal])
          simp [operandResult, stable]
      | outOfFuel => simp [operandResult, Terminal] at terminal
  | unary op operand =>
      simp only [evalExpr, Nat.add_succ] at terminal ⊢
      cases operandResult : evalExpr fuel program state operand with
      | done value next =>
          have stable := previous.expr_eq extra operandResult (by simp [Terminal])
          simp [operandResult, stable]
      | trapped reason next =>
          have stable := previous.expr_eq extra operandResult (by simp [Terminal])
          simp [operandResult, stable]
      | exited code next =>
          have stable := previous.expr_eq extra operandResult (by simp [Terminal])
          simp [operandResult, stable]
      | outOfFuel => simp [operandResult, Terminal] at terminal
  | binary op left right =>
      cases op with
      | logicalAnd =>
          simp only [evalExpr, Nat.add_succ] at terminal ⊢
          cases leftResult : evalExpr fuel program state left with
          | done value next =>
              have leftStable := previous.expr_eq extra leftResult (by simp [Terminal])
              cases value with
              | boolean flag =>
                  cases flag with
                  | false => simp [leftResult, leftStable]
                  | true =>
                      cases rightResult : evalExpr fuel program next right with
                      | done result completed =>
                          have rightStable := previous.expr_eq extra rightResult
                            (by simp [Terminal])
                          simp [leftResult, leftStable, rightResult, rightStable]
                      | trapped reason completed =>
                          have rightStable := previous.expr_eq extra rightResult
                            (by simp [Terminal])
                          simp [leftResult, leftStable, rightResult, rightStable]
                      | exited code completed =>
                          have rightStable := previous.expr_eq extra rightResult
                            (by simp [Terminal])
                          simp [leftResult, leftStable, rightResult, rightStable]
                      | outOfFuel =>
                          simp [leftResult, rightResult, Terminal] at terminal
              | _ => simp [leftResult, leftStable]
          | trapped reason next =>
              have leftStable := previous.expr_eq extra leftResult (by simp [Terminal])
              simp [leftResult, leftStable]
          | exited code next =>
              have leftStable := previous.expr_eq extra leftResult (by simp [Terminal])
              simp [leftResult, leftStable]
          | outOfFuel => simp [leftResult, Terminal] at terminal
      | logicalOr =>
          simp only [evalExpr, Nat.add_succ] at terminal ⊢
          cases leftResult : evalExpr fuel program state left with
          | done value next =>
              have leftStable := previous.expr_eq extra leftResult (by simp [Terminal])
              cases value with
              | boolean flag =>
                  cases flag with
                  | true => simp [leftResult, leftStable]
                  | false =>
                      cases rightResult : evalExpr fuel program next right with
                      | done result completed =>
                          have rightStable := previous.expr_eq extra rightResult
                            (by simp [Terminal])
                          simp [leftResult, leftStable, rightResult, rightStable]
                      | trapped reason completed =>
                          have rightStable := previous.expr_eq extra rightResult
                            (by simp [Terminal])
                          simp [leftResult, leftStable, rightResult, rightStable]
                      | exited code completed =>
                          have rightStable := previous.expr_eq extra rightResult
                            (by simp [Terminal])
                          simp [leftResult, leftStable, rightResult, rightStable]
                      | outOfFuel =>
                          simp [leftResult, rightResult, Terminal] at terminal
              | _ => simp [leftResult, leftStable]
          | trapped reason next =>
              have leftStable := previous.expr_eq extra leftResult (by simp [Terminal])
              simp [leftResult, leftStable]
          | exited code next =>
              have leftStable := previous.expr_eq extra leftResult (by simp [Terminal])
              simp [leftResult, leftStable]
          | outOfFuel => simp [leftResult, Terminal] at terminal
      | _ =>
          simp only [evalExpr, Nat.add_succ] at terminal ⊢
          cases leftResult : evalExpr fuel program state left with
          | done leftValue afterLeft =>
              have leftStable := previous.expr_eq extra leftResult (by simp [Terminal])
              cases rightResult : evalExpr fuel program afterLeft right with
              | done rightValue afterRight =>
                  have rightStable := previous.expr_eq extra rightResult
                    (by simp [Terminal])
                  simp [leftResult, leftStable, rightResult, rightStable]
              | trapped reason next =>
                  have rightStable := previous.expr_eq extra rightResult
                    (by simp [Terminal])
                  simp [leftResult, leftStable, rightResult, rightStable]
              | exited code next =>
                  have rightStable := previous.expr_eq extra rightResult
                    (by simp [Terminal])
                  simp [leftResult, leftStable, rightResult, rightStable]
              | outOfFuel => simp [leftResult, rightResult, Terminal] at terminal
          | trapped reason next =>
              have leftStable := previous.expr_eq extra leftResult (by simp [Terminal])
              simp [leftResult, leftStable]
          | exited code next =>
              have leftStable := previous.expr_eq extra leftResult (by simp [Terminal])
              simp [leftResult, leftStable]
          | outOfFuel => simp [leftResult, Terminal] at terminal
  | array elementType elements =>
      simp only [evalExpr, Nat.add_succ] at terminal ⊢
      cases elementsResult : evalExprs fuel program state elements with
      | done values next =>
          have stable := previous.exprs_eq extra elementsResult (by simp [Terminal])
          simp [elementsResult, stable]
      | trapped reason next =>
          have stable := previous.exprs_eq extra elementsResult (by simp [Terminal])
          simp [elementsResult, stable]
      | exited code next =>
          have stable := previous.exprs_eq extra elementsResult (by simp [Terminal])
          simp [elementsResult, stable]
      | outOfFuel => simp [elementsResult, Terminal] at terminal
  | structValue id fields =>
      simp only [evalExpr, Nat.add_succ] at terminal ⊢
      cases fieldsResult : evalExprs fuel program state fields with
      | done values next =>
          have stable := previous.exprs_eq extra fieldsResult (by simp [Terminal])
          simp [fieldsResult, stable]
      | trapped reason next =>
          have stable := previous.exprs_eq extra fieldsResult (by simp [Terminal])
          simp [fieldsResult, stable]
      | exited code next =>
          have stable := previous.exprs_eq extra fieldsResult (by simp [Terminal])
          simp [fieldsResult, stable]
      | outOfFuel => simp [fieldsResult, Terminal] at terminal
  | enumValue id variant payload =>
      simp only [evalExpr, Nat.add_succ] at terminal ⊢
      cases payloadResult : evalExprs fuel program state payload with
      | done values next =>
          have stable := previous.exprs_eq extra payloadResult (by simp [Terminal])
          simp [payloadResult, stable]
      | trapped reason next =>
          have stable := previous.exprs_eq extra payloadResult (by simp [Terminal])
          simp [payloadResult, stable]
      | exited code next =>
          have stable := previous.exprs_eq extra payloadResult (by simp [Terminal])
          simp [payloadResult, stable]
      | outOfFuel => simp [payloadResult, Terminal] at terminal
  | arrayToSlice elementType array =>
      simp only [evalExpr, Nat.add_succ] at terminal ⊢
      cases placeResult : expressionPlace? array with
      | none =>
          cases arrayResult : evalExpr fuel program state array with
          | done value next =>
              have stable := previous.expr_eq extra arrayResult (by simp [Terminal])
              simp [placeResult, arrayResult, stable]
          | trapped reason next =>
              have stable := previous.expr_eq extra arrayResult (by simp [Terminal])
              simp [placeResult, arrayResult, stable]
          | exited code next =>
              have stable := previous.expr_eq extra arrayResult (by simp [Terminal])
              simp [placeResult, arrayResult, stable]
          | outOfFuel => simp [placeResult, arrayResult, Terminal] at terminal
      | some place =>
          cases evaluated : evalPlace fuel program state place with
          | done resolved next =>
              have stable := previous.place_eq extra place evaluated (by simp [Terminal])
              simp [placeResult, evaluated, stable]
          | trapped reason next =>
              have stable := previous.place_eq extra place evaluated (by simp [Terminal])
              simp [placeResult, evaluated, stable]
          | exited code next =>
              have stable := previous.place_eq extra place evaluated (by simp [Terminal])
              simp [placeResult, evaluated, stable]
          | outOfFuel => simp [placeResult, evaluated, Terminal] at terminal
  | index base index =>
      simp only [evalExpr, Nat.add_succ] at terminal ⊢
      cases baseResult : evalExpr fuel program state base with
      | done value afterBase =>
          have baseStable := previous.expr_eq extra baseResult (by simp [Terminal])
          cases value with
          | array elements | slice _ _ _ _ _ =>
              cases indexResult : evalExpr fuel program afterBase index with
              | done indexValue afterIndex =>
                  have indexStable := previous.expr_eq extra indexResult
                    (by simp [Terminal])
                  simp [baseResult, baseStable, indexResult, indexStable]
              | trapped reason next =>
                  have indexStable := previous.expr_eq extra indexResult
                    (by simp [Terminal])
                  simp [baseResult, baseStable, indexResult, indexStable]
              | exited code next =>
                  have indexStable := previous.expr_eq extra indexResult
                    (by simp [Terminal])
                  simp [baseResult, baseStable, indexResult, indexStable]
              | outOfFuel => simp [baseResult, indexResult, Terminal] at terminal
          | _ => simp [baseResult, baseStable]
      | trapped reason next =>
          have baseStable := previous.expr_eq extra baseResult (by simp [Terminal])
          simp [baseResult, baseStable]
      | exited code next =>
          have baseStable := previous.expr_eq extra baseResult (by simp [Terminal])
          simp [baseResult, baseStable]
      | outOfFuel => simp [baseResult, Terminal] at terminal
  | field base field =>
      simp only [evalExpr, Nat.add_succ] at terminal ⊢
      cases baseResult : evalExpr fuel program state base with
      | done value next =>
          have stable := previous.expr_eq extra baseResult (by simp [Terminal])
          simp [baseResult, stable]
      | trapped reason next =>
          have stable := previous.expr_eq extra baseResult (by simp [Terminal])
          simp [baseResult, stable]
      | exited code next =>
          have stable := previous.expr_eq extra baseResult (by simp [Terminal])
          simp [baseResult, stable]
      | outOfFuel => simp [baseResult, Terminal] at terminal
  | matchValue scrutinee arms =>
      simp only [evalExpr, Nat.add_succ] at terminal ⊢
      cases scrutineeResult : evalExpr fuel program state scrutinee with
      | done value next =>
          have scrutineeStable := previous.expr_eq extra scrutineeResult
            (by simp [Terminal])
          cases armsResult : evalMatchArms fuel program next value arms with
          | done result completed =>
              have armsStable := previous.matchArms_eq extra armsResult
                (by simp [Terminal])
              simp [scrutineeResult, scrutineeStable, armsResult, armsStable]
          | trapped reason completed =>
              have armsStable := previous.matchArms_eq extra armsResult
                (by simp [Terminal])
              simp [scrutineeResult, scrutineeStable, armsResult, armsStable]
          | exited code completed =>
              have armsStable := previous.matchArms_eq extra armsResult
                (by simp [Terminal])
              simp [scrutineeResult, scrutineeStable, armsResult, armsStable]
          | outOfFuel =>
              simp [scrutineeResult, armsResult, Terminal] at terminal
      | trapped reason next =>
          have stable := previous.expr_eq extra scrutineeResult (by simp [Terminal])
          simp [scrutineeResult, stable]
      | exited code next =>
          have stable := previous.expr_eq extra scrutineeResult (by simp [Terminal])
          simp [scrutineeResult, stable]
      | outOfFuel => simp [scrutineeResult, Terminal] at terminal
  | assign op place valueExpression =>
      simp only [evalExpr, Nat.add_succ] at terminal ⊢
      cases placeResult : evalPlace fuel program state place with
      | done resolved afterPlace =>
          have placeStable := previous.place_eq extra place placeResult
            (by simp [Terminal])
          cases valueResult : evalExpr fuel program afterPlace valueExpression with
          | done value afterValue =>
              have valueStable := previous.expr_eq extra valueResult (by simp [Terminal])
              simp [placeResult, placeStable, valueResult, valueStable]
          | trapped reason next =>
              have valueStable := previous.expr_eq extra valueResult (by simp [Terminal])
              simp [placeResult, placeStable, valueResult, valueStable]
          | exited code next =>
              have valueStable := previous.expr_eq extra valueResult (by simp [Terminal])
              simp [placeResult, placeStable, valueResult, valueStable]
          | outOfFuel => simp [placeResult, valueResult, Terminal] at terminal
      | trapped reason next =>
          have placeStable := previous.place_eq extra place placeResult
            (by simp [Terminal])
          simp [placeResult, placeStable]
      | exited code next =>
          have placeStable := previous.place_eq extra place placeResult
            (by simp [Terminal])
          simp [placeResult, placeStable]
      | outOfFuel => simp [placeResult, Terminal] at terminal
  | borrow referent place =>
      simp only [evalExpr, Nat.add_succ] at terminal ⊢
      cases placeResult : evalPlace fuel program state place with
      | done resolved next =>
          have stable := previous.place_eq extra place placeResult (by simp [Terminal])
          simp [placeResult, stable]
      | trapped reason next =>
          have stable := previous.place_eq extra place placeResult (by simp [Terminal])
          simp [placeResult, stable]
      | exited code next =>
          have stable := previous.place_eq extra place placeResult (by simp [Terminal])
          simp [placeResult, stable]
      | outOfFuel => simp [placeResult, Terminal] at terminal
  | dereference reference =>
      simp only [evalExpr, Nat.add_succ] at terminal ⊢
      cases referenceResult : evalExpr fuel program state reference with
      | done value next =>
          have stable := previous.expr_eq extra referenceResult (by simp [Terminal])
          simp [referenceResult, stable]
      | trapped reason next =>
          have stable := previous.expr_eq extra referenceResult (by simp [Terminal])
          simp [referenceResult, stable]
      | exited code next =>
          have stable := previous.expr_eq extra referenceResult (by simp [Terminal])
          simp [referenceResult, stable]
      | outOfFuel => simp [referenceResult, Terminal] at terminal
  | call id arguments =>
      simp only [evalExpr, Nat.add_succ] at terminal ⊢
      cases argumentsResult : evalExprs fuel program state arguments with
      | done values afterArguments =>
          have argumentsStable := previous.exprs_eq extra argumentsResult
            (by simp [Terminal])
          cases functionFound : program.function? id with
          | none => simp [argumentsResult, argumentsStable, functionFound]
          | some function =>
              cases bodyFound : function.body with
              | none =>
                  cases parametersBound : bindParameters function.parameters values with
                  | none =>
                      simp [argumentsResult, argumentsStable, functionFound, bodyFound,
                        parametersBound]
                  | some locals =>
                      simp [argumentsResult, argumentsStable, functionFound, bodyFound,
                        parametersBound]
              | some body =>
                  cases parametersBound : bindParameters function.parameters values with
                  | none =>
                      simp [argumentsResult, argumentsStable, functionFound, bodyFound,
                        parametersBound]
                  | some locals =>
                      let callee :=
                        ({ afterArguments with locals := [] }).bindLocals locals
                      cases bodyResult : execStmt fuel program callee body with
                      | done completion completed =>
                          have bodyStable := previous.stmt_eq extra bodyResult
                            (by simp [Terminal])
                          simp [argumentsResult, argumentsStable, functionFound, bodyFound,
                            parametersBound, callee, bodyResult, bodyStable]
                      | trapped reason completed =>
                          have bodyStable := previous.stmt_eq extra bodyResult
                            (by simp [Terminal])
                          simp [argumentsResult, argumentsStable, functionFound, bodyFound,
                            parametersBound, callee, bodyResult, bodyStable]
                      | exited code completed =>
                          have bodyStable := previous.stmt_eq extra bodyResult
                            (by simp [Terminal])
                          simp [argumentsResult, argumentsStable, functionFound, bodyFound,
                            parametersBound, callee, bodyResult, bodyStable]
                      | outOfFuel =>
                          simp [argumentsResult, functionFound, bodyFound, parametersBound,
                            callee, bodyResult, Terminal] at terminal
      | trapped reason next =>
          have argumentsStable := previous.exprs_eq extra argumentsResult
            (by simp [Terminal])
          simp [argumentsResult, argumentsStable]
      | exited code next =>
          have argumentsStable := previous.exprs_eq extra argumentsResult
            (by simp [Terminal])
          simp [argumentsResult, argumentsStable]
      | outOfFuel => simp [argumentsResult, Terminal] at terminal
  | intrinsic operation argument =>
      simp only [evalExpr, Nat.add_succ] at terminal ⊢
      cases argumentResult : evalExpr fuel program state argument with
      | done value next =>
          have stable := previous.expr_eq extra argumentResult (by simp [Terminal])
          simp [argumentResult, stable]
      | trapped reason next =>
          have stable := previous.expr_eq extra argumentResult (by simp [Terminal])
          simp [argumentResult, stable]
      | exited code next =>
          have stable := previous.expr_eq extra argumentResult (by simp [Terminal])
          simp [argumentResult, stable]
      | outOfFuel => simp [argumentResult, Terminal] at terminal
  | i32ArrayDataPtr array =>
      simp only [evalExpr, Nat.add_succ] at terminal ⊢
      cases placeResult : expressionPlace? array with
      | none =>
          cases arrayResult : evalExpr fuel program state array with
          | done value next =>
              have stable := previous.expr_eq extra arrayResult (by simp [Terminal])
              simp [placeResult, arrayResult, stable]
          | trapped reason next =>
              have stable := previous.expr_eq extra arrayResult (by simp [Terminal])
              simp [placeResult, arrayResult, stable]
          | exited code next =>
              have stable := previous.expr_eq extra arrayResult (by simp [Terminal])
              simp [placeResult, arrayResult, stable]
          | outOfFuel => simp [placeResult, arrayResult, Terminal] at terminal
      | some place =>
          cases evaluated : evalPlace fuel program state place with
          | done resolved next =>
              have stable := previous.place_eq extra place evaluated (by simp [Terminal])
              simp [placeResult, evaluated, stable]
          | trapped reason next =>
              have stable := previous.place_eq extra place evaluated (by simp [Terminal])
              simp [placeResult, evaluated, stable]
          | exited code next =>
              have stable := previous.place_eq extra place evaluated (by simp [Terminal])
              simp [placeResult, evaluated, stable]
          | outOfFuel => simp [placeResult, evaluated, Terminal] at terminal
  | alloc size alignment =>
      simp only [evalExpr, Nat.add_succ] at terminal ⊢
      cases sizeResult : evalExpr fuel program state size with
      | done sizeValue afterSize =>
          have sizeStable := previous.expr_eq extra sizeResult (by simp [Terminal])
          cases sizeValue with
          | unsigned sizeType sizeValue =>
              cases sizeType with
              | usize =>
                  cases alignmentResult : evalExpr fuel program afterSize alignment with
                  | done alignmentValue afterAlignment =>
                      have alignmentStable := previous.expr_eq extra alignmentResult
                        (by simp [Terminal])
                      simp [sizeResult, sizeStable, alignmentResult, alignmentStable]
                  | trapped reason next =>
                      have alignmentStable := previous.expr_eq extra alignmentResult
                        (by simp [Terminal])
                      simp [sizeResult, sizeStable, alignmentResult, alignmentStable]
                  | exited code next =>
                      have alignmentStable := previous.expr_eq extra alignmentResult
                        (by simp [Terminal])
                      simp [sizeResult, sizeStable, alignmentResult, alignmentStable]
                  | outOfFuel =>
                      simp [sizeResult, alignmentResult, Terminal] at terminal
              | _ => simp [sizeResult, sizeStable]
          | _ => simp [sizeResult, sizeStable]
      | trapped reason next =>
          have sizeStable := previous.expr_eq extra sizeResult (by simp [Terminal])
          simp [sizeResult, sizeStable]
      | exited code next =>
          have sizeStable := previous.expr_eq extra sizeResult (by simp [Terminal])
          simp [sizeResult, sizeStable]
      | outOfFuel => simp [sizeResult, Terminal] at terminal
  | realloc pointer oldSize newSize alignment =>
      simp only [evalExpr, Nat.add_succ] at terminal ⊢
      cases argumentsResult : evalExprs fuel program state
          [pointer, oldSize, newSize, alignment] with
      | done values next =>
          have stable := previous.exprs_eq extra argumentsResult (by simp [Terminal])
          simp [argumentsResult, stable]
      | trapped reason next =>
          have stable := previous.exprs_eq extra argumentsResult (by simp [Terminal])
          simp [argumentsResult, stable]
      | exited code next =>
          have stable := previous.exprs_eq extra argumentsResult (by simp [Terminal])
          simp [argumentsResult, stable]
      | outOfFuel => simp [argumentsResult, Terminal] at terminal
  | dealloc pointer size alignment =>
      simp only [evalExpr, Nat.add_succ] at terminal ⊢
      cases argumentsResult : evalExprs fuel program state
          [pointer, size, alignment] with
      | done values next =>
          have stable := previous.exprs_eq extra argumentsResult (by simp [Terminal])
          simp [argumentsResult, stable]
      | trapped reason next =>
          have stable := previous.exprs_eq extra argumentsResult (by simp [Terminal])
          simp [argumentsResult, stable]
      | exited code next =>
          have stable := previous.exprs_eq extra argumentsResult (by simp [Terminal])
          simp [argumentsResult, stable]
      | outOfFuel => simp [argumentsResult, Terminal] at terminal
  | loadByte pointer offset =>
      simp only [evalExpr, Nat.add_succ] at terminal ⊢
      cases argumentsResult : evalExprs fuel program state [pointer, offset] with
      | done values next =>
          have stable := previous.exprs_eq extra argumentsResult (by simp [Terminal])
          simp [argumentsResult, stable]
      | trapped reason next =>
          have stable := previous.exprs_eq extra argumentsResult (by simp [Terminal])
          simp [argumentsResult, stable]
      | exited code next =>
          have stable := previous.exprs_eq extra argumentsResult (by simp [Terminal])
          simp [argumentsResult, stable]
      | outOfFuel => simp [argumentsResult, Terminal] at terminal
  | storeByte pointer offset value =>
      simp only [evalExpr, Nat.add_succ] at terminal ⊢
      cases argumentsResult : evalExprs fuel program state [pointer, offset, value] with
      | done values next =>
          have stable := previous.exprs_eq extra argumentsResult (by simp [Terminal])
          simp [argumentsResult, stable]
      | trapped reason next =>
          have stable := previous.exprs_eq extra argumentsResult (by simp [Terminal])
          simp [argumentsResult, stable]
      | exited code next =>
          have stable := previous.exprs_eq extra argumentsResult (by simp [Terminal])
          simp [argumentsResult, stable]
      | outOfFuel => simp [argumentsResult, Terminal] at terminal

/-- If every evaluator component is stable at `fuel`, one additional unit of
    fuel is also stable. This packages the mutually dependent successor
    lemmas into the same semantic invariant. -/
theorem evaluatorFuelStableAt_succ
    (previous : EvaluatorFuelStableAt fuel) :
    EvaluatorFuelStableAt (fuel + 1) := {
  expr := evalExpr_fuel_stable_succ previous
  exprs := evalExprs_fuel_stable_succ previous
  matchArms := evalMatchArms_fuel_stable_succ previous
  place := evalPlace_fuel_stable_succ previous
  forValues := execForValues_fuel_stable_succ previous
  forRange := execForRange_fuel_stable_succ previous
  stmt := execStmt_fuel_stable_succ previous
}

/-- Terminal evaluator observations are independent of how much additional
    proof fuel is supplied. -/
theorem evaluatorFuelStableAt (fuel : Nat) : EvaluatorFuelStableAt fuel := by
  induction fuel with
  | zero => exact evaluatorFuelStableAt_zero
  | succ fuel inductionHypothesis =>
      simpa [Nat.succ_eq_add_one] using
        evaluatorFuelStableAt_succ inductionHypothesis

theorem evalExpr_more_fuel
    (terminal : Terminal (evalExpr fuel program state expression)) :
    evalExpr (extra + fuel) program state expression =
      evalExpr fuel program state expression :=
  (evaluatorFuelStableAt fuel).expr extra program state expression terminal

theorem execStmt_more_fuel
    (terminal : Terminal (execStmt fuel program state statement)) :
    execStmt (extra + fuel) program state statement =
      execStmt fuel program state statement :=
  (evaluatorFuelStableAt fuel).stmt extra program state statement terminal

/-- A successful expression evaluation remains successful at any larger fuel
    bound. This packages the subtraction arithmetic needed to use
    `evalExpr_more_fuel` with an ordered pair of fuel bounds. -/
theorem evalExpr_done_at_larger_fuel
    {small large : Nat} (enough : small ≤ large)
    (result : evalExpr small program state expression = .done value finalState) :
    evalExpr large program state expression = .done value finalState := by
  have terminal : Terminal (evalExpr small program state expression) := by
    rw [result]
    trivial
  have stable := evalExpr_more_fuel (extra := large - small) terminal
  rw [Nat.sub_add_cancel enough] at stable
  exact stable.trans result

/-- A successful argument-list evaluation remains successful at any larger
    fuel bound. -/
theorem evalExprs_done_at_larger_fuel
    {small large : Nat} (enough : small ≤ large)
    (result : evalExprs small program state expressions =
      .done values finalState) :
    evalExprs large program state expressions = .done values finalState := by
  have terminal : Terminal (evalExprs small program state expressions) := by
    rw [result]
    trivial
  have stable := (evaluatorFuelStableAt small).exprs
    (large - small) program state expressions terminal
  rw [Nat.sub_add_cancel enough] at stable
  exact stable.trans result

/-- A successfully resolved place remains resolved at any larger fuel bound. -/
theorem evalPlace_done_at_larger_fuel
    {small large : Nat} (enough : small ≤ large)
    (result : evalPlace small program state place = .done resolved finalState) :
    evalPlace large program state place = .done resolved finalState := by
  have terminal : Terminal (evalPlace small program state place) := by
    rw [result]
    trivial
  have stable := (evaluatorFuelStableAt small).place
    (large - small) program state place terminal
  rw [Nat.sub_add_cancel enough] at stable
  exact stable.trans result

/-- A successfully completed statement remains completed at any larger fuel
    bound. -/
theorem execStmt_done_at_larger_fuel
    {small large : Nat} (enough : small ≤ large)
    (result : execStmt small program state statement =
      .done completion finalState) :
    execStmt large program state statement = .done completion finalState := by
  have terminal : Terminal (execStmt small program state statement) := by
    rw [result]
    trivial
  have stable := execStmt_more_fuel (extra := large - small) terminal
  rw [Nat.sub_add_cancel enough] at stable
  exact stable.trans result

/-- Successful structural expression evaluation is functional even when two
    proofs use different fuel witnesses.  Both observations are replayed at
    their common maximum before executable determinism is applied. -/
theorem evaluates_deterministic
    (left : Evaluates program state expression leftValue leftState)
    (right : Evaluates program state expression rightValue rightState) :
    leftValue = rightValue ∧ leftState = rightState := by
  obtain ⟨leftFuel, leftResult⟩ := left
  obtain ⟨rightFuel, rightResult⟩ := right
  let common := max leftFuel rightFuel
  have leftCommon : evalExpr common program state expression =
      .done leftValue leftState :=
    evalExpr_done_at_larger_fuel (Nat.le_max_left _ _) leftResult
  have rightCommon : evalExpr common program state expression =
      .done rightValue rightState :=
    evalExpr_done_at_larger_fuel (Nat.le_max_right _ _) rightResult
  have same := leftCommon.symm.trans rightCommon
  injection same with valueEq stateEq
  exact ⟨valueEq, stateEq⟩

/-- Successful structural statement execution is likewise functional across
    independently chosen fuel witnesses. -/
theorem executes_deterministic
    (left : Executes program state statement leftCompletion leftState)
    (right : Executes program state statement rightCompletion rightState) :
    leftCompletion = rightCompletion ∧ leftState = rightState := by
  obtain ⟨leftFuel, leftResult⟩ := left
  obtain ⟨rightFuel, rightResult⟩ := right
  let common := max leftFuel rightFuel
  have leftCommon : execStmt common program state statement =
      .done leftCompletion leftState :=
    execStmt_done_at_larger_fuel (Nat.le_max_left _ _) leftResult
  have rightCommon : execStmt common program state statement =
      .done rightCompletion rightState :=
    execStmt_done_at_larger_fuel (Nat.le_max_right _ _) rightResult
  have same := leftCommon.symm.trans rightCommon
  injection same with completionEq stateEq
  exact ⟨completionEq, stateEq⟩

/-- A whole-program observation is terminal exactly when it is a return,
    explicit exit, or trap. Fuel exhaustion is not an observation of the
    language program. -/
def ExecutionTerminal : Execution.Result → Prop
  | .returned _ _ | .exited _ _ | .trapped _ _ => True
  | .outOfFuel => False

/-- Once whole-program execution produces a terminal observation, supplying
    more proof fuel produces exactly the same observation and final state. -/
theorem execution_more_fuel
    (terminal : ExecutionTerminal (Execution.run fuel executable initial)) :
    Execution.run (extra + fuel) executable initial =
      Execution.run fuel executable initial := by
  unfold Execution.run at terminal ⊢
  cases evaluated : evalExpr fuel executable.program initial
      (.call executable.entrypoint []) with
  | done value finalState =>
      have stable := (evaluatorFuelStableAt fuel).expr_eq extra evaluated
        (by simp [Terminal])
      simp [evaluated, stable]
  | trapped reason finalState =>
      have stable := (evaluatorFuelStableAt fuel).expr_eq extra evaluated
        (by simp [Terminal])
      simp [evaluated, stable]
  | exited code finalState =>
      have stable := (evaluatorFuelStableAt fuel).expr_eq extra evaluated
        (by simp [Terminal])
      simp [evaluated, stable]
  | outOfFuel => simp [evaluated, ExecutionTerminal] at terminal
end Lanius.Fuel
