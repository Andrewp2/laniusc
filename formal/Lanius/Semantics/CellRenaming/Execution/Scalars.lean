import Lanius.Semantics.CellRenaming.Execution.Step

namespace Lanius.Semantics.CellRenaming.Execution
open Lanius.Core

theorem castExpression {rename : Permutation boundary} (step : Step fuel rename program)
    (before : State) (op : ScalarTy) (input : Expr) (result : Value) (after : State)
    (ready : boundary ≤ before.nextCell)
    (evaluated : evalExpr (fuel + 1) program before (.cast op input) = .done result after) :
    evalExpr (fuel + 1) program (state rename.forward before)
        (.cast op (CellRenaming.expression rename.forward input)) =
      .done (value rename.forward result) (state rename.forward after) ∧ boundary ≤ after.nextCell := by
  simp only [evalExpr] at evaluated ⊢
  cases run : evalExpr fuel program before input with
  | done entry next =>
      obtain ⟨transport, nextReady⟩ := step.expression ready run
      rw [transport]
      simp only [run] at evaluated
      simp only [CellRenaming.cast]
      cases computed : evalScalarCast program.target op entry with
      | error reason => simp [computed] at evaluated
      | ok answer =>
          simp only [computed, Outcome.done.injEq] at evaluated
          obtain ⟨rfl, rfl⟩ := evaluated
          exact ⟨by simp [computed, Except.map], nextReady⟩
  | _ => simp [run] at evaluated

theorem unaryExpression {rename : Permutation boundary} (step : Step fuel rename program)
    (before : State) (op : UnaryOp) (input : Expr) (result : Value) (after : State)
    (ready : boundary ≤ before.nextCell)
    (evaluated : evalExpr (fuel + 1) program before (.unary op input) = .done result after) :
    evalExpr (fuel + 1) program (state rename.forward before)
        (.unary op (CellRenaming.expression rename.forward input)) =
      .done (value rename.forward result) (state rename.forward after) ∧ boundary ≤ after.nextCell := by
  simp only [evalExpr] at evaluated ⊢
  cases run : evalExpr fuel program before input with
  | done entry next =>
      obtain ⟨transport, nextReady⟩ := step.expression ready run
      rw [transport]
      simp only [run] at evaluated
      simp only [CellRenaming.unary]
      cases computed : evalUnaryValue program.target op entry with
      | error reason => simp [computed] at evaluated
      | ok answer =>
          simp only [computed, Outcome.done.injEq] at evaluated
          obtain ⟨rfl, rfl⟩ := evaluated
          exact ⟨by simp [computed, Except.map], nextReady⟩
  | _ => simp [run] at evaluated

theorem binaryExpression {rename : Permutation boundary} (step : Step fuel rename program)
    (before : State) (op : BinaryOp) (left right : Expr) (result : Value) (after : State)
    (ready : boundary ≤ before.nextCell)
    (evaluated : evalExpr (fuel + 1) program before (.binary op left right) = .done result after) :
    evalExpr (fuel + 1) program (state rename.forward before)
        (.binary op (CellRenaming.expression rename.forward left) (CellRenaming.expression rename.forward right)) =
      .done (value rename.forward result) (state rename.forward after) ∧ boundary ≤ after.nextCell := by
  cases op with
  | logicalAnd =>
      simp only [evalExpr] at evaluated ⊢
      cases run : evalExpr fuel program before left with
      | done entry next =>
          obtain ⟨transport, nextReady⟩ := step.expression ready run
          rw [transport]
          cases entry <;> simp only [run] at evaluated
          all_goals try contradiction
          case boolean flag =>
            cases flag <;> simp only [value]
            all_goals first
              | exact step.expression nextReady evaluated
              | obtain ⟨rfl, rfl⟩ := Outcome.done.inj evaluated; exact ⟨rfl, nextReady⟩
      | _ => simp [run] at evaluated
  | logicalOr =>
      simp only [evalExpr] at evaluated ⊢
      cases run : evalExpr fuel program before left with
      | done entry next =>
          obtain ⟨transport, nextReady⟩ := step.expression ready run
          rw [transport]
          cases entry <;> simp only [run] at evaluated
          all_goals try contradiction
          case boolean flag =>
            cases flag <;> simp only [value]
            all_goals first
              | exact step.expression nextReady evaluated
              | obtain ⟨rfl, rfl⟩ := Outcome.done.inj evaluated; exact ⟨rfl, nextReady⟩
      | _ => simp [run] at evaluated
  | _ =>
      simp only [evalExpr] at evaluated ⊢
      cases leftRun : evalExpr fuel program before left with
      | done leftValue afterLeft =>
          obtain ⟨leftTransport, leftReady⟩ := step.expression ready leftRun
          rw [leftTransport]
          simp only []
          simp only [leftRun] at evaluated
          cases rightRun : evalExpr fuel program afterLeft right with
          | done rightValue afterRight =>
              obtain ⟨rightTransport, rightReady⟩ := step.expression leftReady rightRun
              rw [rightTransport]
              simp only [rightRun] at evaluated
              simp only [CellRenaming.binary]
              repeat' first | contradiction | split at evaluated
              all_goals
                obtain ⟨rfl, rfl⟩ := Outcome.done.inj evaluated
                exact ⟨by simp_all only [Except.map], rightReady⟩
          | _ => simp [rightRun] at evaluated
      | _ => simp [leftRun] at evaluated

end Lanius.Semantics.CellRenaming.Execution
