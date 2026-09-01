import Lanius.ExecutionRules

namespace Lanius.Relational.CoreSuccess

open Lanius
open Lanius.Core
open Lanius.Semantics

/-! # Structural successful Core executions

Core's authoritative semantics is fuelled.  Reflection proofs need to invert a
successful run by statement structure, not reason about the particular fuel
witness.  `StmtExecutes` is an inductive view of exactly the statement subset
emitted by action-free FunctionalView commands.  `ofExecStmt` derives that view
from an actual successful evaluator result without assuming termination.
-/

def Supported : Stmt → Bool
  | .skip | .expression _ | .returnValue _ | .breakLoop | .continueLoop => true
  | .sequence first second => Supported first && Supported second
  | .letLocal _ _ _ body => Supported body
  | .ifThenElse _ thenBranch elseBranch =>
      Supported thenBranch && Supported elseBranch
  | .whileLoop _ body => Supported body
  | .letUninitialized _ _ _ | .forValues _ _ _ | .forRange _ _ _ _ _ => false

inductive StmtExecutes (program : Program) :
    State → Stmt → Completion → State → Prop where
  | skip : StmtExecutes program state .skip .next state
  | expression
      (evaluated : Evaluates program before expression value after) :
      StmtExecutes program before (.expression expression) .next after
  | sequenceNext
      (firstResult : StmtExecutes program before first .next middle)
      (secondResult : StmtExecutes program middle second completion after) :
      StmtExecutes program before (.sequence first second) completion after
  | sequenceStop
      (firstResult : StmtExecutes program before first completion after)
      (stops : completion ≠ .next) :
      StmtExecutes program before (.sequence first second) completion after
  | letLocal
      (initializerResult : Evaluates program before initializer value initialized)
      (bodyResult : StmtExecutes program (initialized.bindLocal localId value) body
        completion completed) :
      StmtExecutes program before (.letLocal localId type initializer body)
        completion (restoreLocals initialized completed)
  | ifTrue
      (conditionResult : Evaluates program before condition (.boolean true)
        conditionState)
      (branchResult : StmtExecutes program conditionState thenBranch
        completion after) :
      StmtExecutes program before
        (.ifThenElse condition thenBranch elseBranch) completion after
  | ifFalse
      (conditionResult : Evaluates program before condition (.boolean false)
        conditionState)
      (branchResult : StmtExecutes program conditionState elseBranch
        completion after) :
      StmtExecutes program before
        (.ifThenElse condition thenBranch elseBranch) completion after
  | whileFalse
      (conditionResult : Evaluates program before condition (.boolean false)
        after) :
      StmtExecutes program before (.whileLoop condition body) .next after
  | whileNext
      (conditionResult : Evaluates program before condition (.boolean true)
        conditionState)
      (bodyResult : StmtExecutes program conditionState body .next bodyState)
      (restResult : StmtExecutes program bodyState (.whileLoop condition body)
        completion after) :
      StmtExecutes program before (.whileLoop condition body) completion after
  | whileContinue
      (conditionResult : Evaluates program before condition (.boolean true)
        conditionState)
      (bodyResult : StmtExecutes program conditionState body .continueLoop
        bodyState)
      (restResult : StmtExecutes program bodyState (.whileLoop condition body)
        completion after) :
      StmtExecutes program before (.whileLoop condition body) completion after
  | whileBreak
      (conditionResult : Evaluates program before condition (.boolean true)
        conditionState)
      (bodyResult : StmtExecutes program conditionState body .breakLoop after) :
      StmtExecutes program before (.whileLoop condition body) .next after
  | whileReturn
      (conditionResult : Evaluates program before condition (.boolean true)
        conditionState)
      (bodyResult : StmtExecutes program conditionState body (.returned value)
        after) :
      StmtExecutes program before (.whileLoop condition body) (.returned value)
        after
  | returnNone :
      StmtExecutes program state (.returnValue none) (.returned none) state
  | returnSome
      (evaluated : Evaluates program before expression value after) :
      StmtExecutes program before (.returnValue (some expression))
        (.returned (some value)) after
  | breakLoop :
      StmtExecutes program state .breakLoop .breakLoop state
  | continueLoop :
      StmtExecutes program state .continueLoop .continueLoop state

/-- Constructor-precise view of a successful while execution.  Unlike the
general statement judgment, the statement shape is a parameter rather than an
index, so proofs can recurse over loop iterations without generalizing a
syntactic equality. -/
inductive WhileExecutes (program : Program) (condition : Expr) (body : Stmt) :
    State → Completion → State → Prop where
  | false
      (conditionResult : Evaluates program before condition (.boolean false)
        after) :
      WhileExecutes program condition body before .next after
  | next
      (conditionResult : Evaluates program before condition (.boolean true)
        conditionState)
      (bodyResult : StmtExecutes program conditionState body .next bodyState)
      (restResult : WhileExecutes program condition body bodyState completion
        after) :
      WhileExecutes program condition body before completion after
  | continue
      (conditionResult : Evaluates program before condition (.boolean true)
        conditionState)
      (bodyResult : StmtExecutes program conditionState body .continueLoop
        bodyState)
      (restResult : WhileExecutes program condition body bodyState completion
        after) :
      WhileExecutes program condition body before completion after
  | break
      (conditionResult : Evaluates program before condition (.boolean true)
        conditionState)
      (bodyResult : StmtExecutes program conditionState body .breakLoop after) :
      WhileExecutes program condition body before .next after
  | returned
      (conditionResult : Evaluates program before condition (.boolean true)
        conditionState)
      (bodyResult : StmtExecutes program conditionState body (.returned value)
        after) :
      WhileExecutes program condition body before (.returned value) after

theorem StmtExecutes.whileInversion
    (executed : StmtExecutes program before (.whileLoop condition body)
      completion after) :
    WhileExecutes program condition body before completion after := by
  generalize statementEq : Stmt.whileLoop condition body = statement at executed
  induction executed with
  | whileFalse conditionResult =>
      obtain ⟨rfl, rfl⟩ := Stmt.whileLoop.inj statementEq
      exact .false conditionResult
  | whileNext conditionResult bodyResult restResult _bodyIH restIH =>
      obtain ⟨rfl, rfl⟩ := Stmt.whileLoop.inj statementEq
      exact .next conditionResult bodyResult (restIH rfl)
  | whileContinue conditionResult bodyResult restResult _bodyIH restIH =>
      obtain ⟨rfl, rfl⟩ := Stmt.whileLoop.inj statementEq
      exact .continue conditionResult bodyResult (restIH rfl)
  | whileBreak conditionResult bodyResult _bodyIH =>
      obtain ⟨rfl, rfl⟩ := Stmt.whileLoop.inj statementEq
      exact .break conditionResult bodyResult
  | whileReturn conditionResult bodyResult _bodyIH =>
      obtain ⟨rfl, rfl⟩ := Stmt.whileLoop.inj statementEq
      exact .returned conditionResult bodyResult
  | skip | expression | sequenceNext | sequenceStop | letLocal | ifTrue |
      ifFalse | returnNone | returnSome | breakLoop | continueLoop =>
      simp at statementEq

theorem WhileExecutes.toStmtExecutes
    (executed : WhileExecutes program condition body before completion after) :
    StmtExecutes program before (.whileLoop condition body) completion after := by
  induction executed with
  | false conditionResult => exact .whileFalse conditionResult
  | next conditionResult bodyResult _restResult restIH =>
      exact .whileNext conditionResult bodyResult restIH
  | «continue» conditionResult bodyResult _restResult restIH =>
      exact .whileContinue conditionResult bodyResult restIH
  | «break» conditionResult bodyResult =>
      exact .whileBreak conditionResult bodyResult
  | returned conditionResult bodyResult =>
      exact .whileReturn conditionResult bodyResult

/-- Invert one successful short-circuit conjunction without constructing a
second execution. -/
theorem evaluatesLogicalAndInversion
    (evaluated : Evaluates program before (.binary .logicalAnd left right)
      value after) :
    (value = .boolean false ∧
      Evaluates program before left (.boolean false) after) ∨
    (∃ middle,
      Evaluates program before left (.boolean true) middle ∧
      Evaluates program middle right value after) := by
  obtain ⟨fuel, evaluated⟩ := evaluated
  cases fuel with
  | zero => simp [evalExpr] at evaluated
  | succ fuel =>
      rw [evalExpr.eq_def] at evaluated
      simp only at evaluated
      generalize leftEq : evalExpr fuel program before left = outcome
        at evaluated
      cases outcome with
      | outOfFuel => simp at evaluated
      | trapped reason state => simp at evaluated
      | exited code state => simp at evaluated
      | done leftValue middle =>
          cases leftValue with
          | boolean decision =>
              cases decision with
              | false =>
                  obtain ⟨rfl, rfl⟩ := Outcome.done.inj evaluated
                  exact .inl ⟨rfl, ⟨fuel, leftEq⟩⟩
              | true =>
                  exact .inr ⟨middle, ⟨fuel, leftEq⟩, ⟨fuel, evaluated⟩⟩
          | _ => simp at evaluated

/-- Invert one successful short-circuit disjunction without constructing a
second execution. -/
theorem evaluatesLogicalOrInversion
    (evaluated : Evaluates program before (.binary .logicalOr left right)
      value after) :
    (value = .boolean true ∧
      Evaluates program before left (.boolean true) after) ∨
    (∃ middle,
      Evaluates program before left (.boolean false) middle ∧
      Evaluates program middle right value after) := by
  obtain ⟨fuel, evaluated⟩ := evaluated
  cases fuel with
  | zero => simp [evalExpr] at evaluated
  | succ fuel =>
      rw [evalExpr.eq_def] at evaluated
      simp only at evaluated
      generalize leftEq : evalExpr fuel program before left = outcome
        at evaluated
      cases outcome with
      | outOfFuel => simp at evaluated
      | trapped reason state => simp at evaluated
      | exited code state => simp at evaluated
      | done leftValue middle =>
          cases leftValue with
          | boolean decision =>
              cases decision with
              | false =>
                  exact .inr ⟨middle, ⟨fuel, leftEq⟩, ⟨fuel, evaluated⟩⟩
              | true =>
                  obtain ⟨rfl, rfl⟩ := Outcome.done.inj evaluated
                  exact .inl ⟨rfl, ⟨fuel, leftEq⟩⟩
          | _ => simp at evaluated

/-- Forget the structural view and recover the authoritative fuel-independent
Core execution relation.  This is useful for applying existing generic leaf
lemmas without reconstructing evaluator fuel. -/
theorem StmtExecutes.toExecutes
    (executed : StmtExecutes program before statement completion after) :
    Executes program before statement completion after := by
  induction executed with
  | skip => exact executesSkip _ _
  | expression evaluated => exact executesExpression evaluated
  | sequenceNext _ _ firstIH secondIH =>
      exact executesSequence firstIH secondIH
  | sequenceStop _ stops firstIH =>
      exact executesSequenceNonNext firstIH stops
  | letLocal initializerResult _ bodyIH =>
      exact executesLetLocal initializerResult bodyIH
  | ifTrue conditionResult _ branchIH =>
      exact executesIfTrue conditionResult branchIH
  | ifFalse conditionResult _ branchIH =>
      exact executesIfFalse conditionResult branchIH
  | whileFalse conditionResult => exact executesWhileFalse conditionResult
  | whileNext conditionResult _ _ bodyIH restIH =>
      exact executesWhileTrueThen conditionResult bodyIH restIH
  | whileContinue conditionResult _ _ bodyIH restIH =>
      exact executesWhileContinueThen conditionResult bodyIH restIH
  | whileBreak conditionResult _ bodyIH =>
      exact executesWhileBreak conditionResult bodyIH
  | whileReturn conditionResult _ bodyIH =>
      exact executesWhileReturned conditionResult bodyIH
  | returnNone => exact executesReturnNone _ _
  | returnSome evaluated => exact executesReturnValue evaluated
  | breakLoop => exact executesBreak _ _
  | continueLoop => exact executesContinue _ _

private theorem ofExecStmtFuel : ∀ fuel program before statement completion after,
    Supported statement = true →
    execStmt fuel program before statement = .done completion after →
    StmtExecutes program before statement completion after
  | 0, _, _, _, _, _, _, executed => by
      simp [execStmt] at executed
  | fuel + 1, program, before, statement, completion, after, supported,
      executed => by
      simp only [execStmt] at executed
      cases statement with
      | skip =>
          simp only at executed
          obtain ⟨rfl, rfl⟩ := Outcome.done.inj executed
          exact .skip
      | expression expression =>
          simp only at executed
          generalize expressionResult : evalExpr fuel program before expression =
            outcome at executed
          cases outcome with
          | outOfFuel => simp at executed
          | trapped reason state => simp at executed
          | exited code state => simp at executed
          | done value expressionState =>
              obtain ⟨rfl, rfl⟩ := Outcome.done.inj executed
              exact .expression ⟨fuel, expressionResult⟩
      | sequence first second =>
          simp only at executed
          simp only [Supported, Bool.and_eq_true] at supported
          generalize firstResult : execStmt fuel program before first = outcome
            at executed
          cases outcome with
          | outOfFuel => simp at executed
          | trapped reason state => simp at executed
          | exited code state => simp at executed
          | done firstCompletion middle =>
              cases firstCompletion with
              | next =>
                  exact .sequenceNext
                    (ofExecStmtFuel fuel program before first .next middle
                      supported.1 firstResult)
                    (ofExecStmtFuel fuel program middle second completion after
                      supported.2 executed)
              | returned value =>
                  obtain ⟨rfl, rfl⟩ := Outcome.done.inj executed
                  exact .sequenceStop
                    (ofExecStmtFuel fuel program before first (.returned value)
                      middle supported.1 firstResult) (by simp)
              | breakLoop =>
                  obtain ⟨rfl, rfl⟩ := Outcome.done.inj executed
                  exact .sequenceStop
                    (ofExecStmtFuel fuel program before first .breakLoop middle
                      supported.1 firstResult) (by simp)
              | continueLoop =>
                  obtain ⟨rfl, rfl⟩ := Outcome.done.inj executed
                  exact .sequenceStop
                    (ofExecStmtFuel fuel program before first .continueLoop middle
                      supported.1 firstResult) (by simp)
      | letLocal id type initializer body =>
          simp only at executed
          simp only [Supported] at supported
          generalize initializerResult :
            evalExpr fuel program before initializer = outcome at executed
          cases outcome with
          | outOfFuel => simp at executed
          | trapped reason state => simp at executed
          | exited code state => simp at executed
          | done value initialized =>
              generalize bodyResult : execStmt fuel program
                (initialized.bindLocal id value) body = bodyOutcome at executed
              simp only [bodyResult] at executed
              cases bodyOutcome with
              | outOfFuel => simp [restoreOutcomeLocals] at executed
              | trapped reason state => simp [restoreOutcomeLocals] at executed
              | exited code state => simp [restoreOutcomeLocals] at executed
              | done bodyCompletion completed =>
                  simp only [restoreOutcomeLocals] at executed
                  obtain ⟨rfl, rfl⟩ := Outcome.done.inj executed
                  exact .letLocal ⟨fuel, initializerResult⟩
                    (ofExecStmtFuel fuel program
                      (initialized.bindLocal id value) body bodyCompletion completed
                      supported bodyResult)
      | letUninitialized id type body => simp [Supported] at supported
      | ifThenElse condition thenBranch elseBranch =>
          simp only at executed
          simp only [Supported, Bool.and_eq_true] at supported
          generalize conditionResult : evalExpr fuel program before condition =
            outcome at executed
          cases outcome with
          | outOfFuel => simp at executed
          | trapped reason state => simp at executed
          | exited code state => simp at executed
          | done value conditionState =>
              cases value with
              | boolean decision =>
                  cases decision with
                  | false =>
                      exact .ifFalse ⟨fuel, conditionResult⟩
                        (ofExecStmtFuel fuel program conditionState elseBranch
                          completion after supported.2 executed)
                  | true =>
                      exact .ifTrue ⟨fuel, conditionResult⟩
                        (ofExecStmtFuel fuel program conditionState thenBranch
                          completion after supported.1 executed)
              | _ => simp at executed
      | whileLoop condition body =>
          simp only at executed
          simp only [Supported] at supported
          generalize conditionResult : evalExpr fuel program before condition =
            outcome at executed
          cases outcome with
          | outOfFuel => simp at executed
          | trapped reason state => simp at executed
          | exited code state => simp at executed
          | done value conditionState =>
              cases value with
              | boolean decision =>
                  cases decision with
                  | false =>
                      simp only at executed
                      obtain ⟨rfl, rfl⟩ := Outcome.done.inj executed
                      exact .whileFalse ⟨fuel, conditionResult⟩
                  | true =>
                      simp only at executed
                      generalize bodyResult : execStmt fuel program
                        conditionState body = bodyOutcome at executed
                      cases bodyOutcome with
                      | outOfFuel => simp at executed
                      | trapped reason state => simp at executed
                      | exited code state => simp at executed
                      | done bodyCompletion bodyState =>
                          cases bodyCompletion with
                          | next =>
                              exact .whileNext ⟨fuel, conditionResult⟩
                                (ofExecStmtFuel fuel program conditionState body
                                  .next bodyState supported bodyResult)
                                (ofExecStmtFuel fuel program bodyState
                                  (.whileLoop condition body) completion after
                                  supported executed)
                          | continueLoop =>
                              exact .whileContinue ⟨fuel, conditionResult⟩
                                (ofExecStmtFuel fuel program conditionState body
                                  .continueLoop bodyState supported bodyResult)
                                (ofExecStmtFuel fuel program bodyState
                                  (.whileLoop condition body) completion after
                                  supported executed)
                          | breakLoop =>
                              obtain ⟨rfl, rfl⟩ := Outcome.done.inj executed
                              exact .whileBreak ⟨fuel, conditionResult⟩
                                (ofExecStmtFuel fuel program conditionState body
                                  .breakLoop bodyState supported bodyResult)
                          | returned value =>
                              obtain ⟨rfl, rfl⟩ := Outcome.done.inj executed
                              exact .whileReturn ⟨fuel, conditionResult⟩
                                (ofExecStmtFuel fuel program conditionState body
                                  (.returned value) bodyState supported bodyResult)
              | _ => simp at executed
      | forValues id iterable body => simp [Supported] at supported
      | forRange id start stop inclusive body => simp [Supported] at supported
      | returnValue value =>
          cases value with
          | none =>
              simp only at executed
              obtain ⟨rfl, rfl⟩ := Outcome.done.inj executed
              exact .returnNone
          | some expression =>
              simp only at executed
              generalize expressionResult :
                evalExpr fuel program before expression = outcome at executed
              cases outcome with
              | outOfFuel => simp at executed
              | trapped reason state => simp at executed
              | exited code state => simp at executed
              | done value expressionState =>
                  obtain ⟨rfl, rfl⟩ := Outcome.done.inj executed
                  exact .returnSome ⟨fuel, expressionResult⟩
      | breakLoop =>
          simp only at executed
          obtain ⟨rfl, rfl⟩ := Outcome.done.inj executed
          exact .breakLoop
      | continueLoop =>
          simp only at executed
          obtain ⟨rfl, rfl⟩ := Outcome.done.inj executed
          exact .continueLoop

theorem ofExecutes
    (supported : Supported statement = true)
    (executed : Executes program before statement completion after) :
    StmtExecutes program before statement completion after := by
  obtain ⟨fuel, result⟩ := executed
  exact ofExecStmtFuel fuel program before statement completion after supported
    result

end Lanius.Relational.CoreSuccess
