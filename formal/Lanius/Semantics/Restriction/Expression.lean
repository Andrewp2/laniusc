import Lanius.Semantics.Restriction.Step
import Std.Tactic

namespace Lanius.Semantics.Restriction

open Lanius.Core

theorem expression (step : Step fuel allowed original restricted)
    (matching : Agreement allowed original restricted)
    (before : State) (code : Expr) (value : Value) (after : State)
    (evaluated : evalExpr (fuel + 1) original before code = .done value after)
    (closed : Dependencies.expression allowed code = true) :
    evalExpr (fuel + 1) restricted before code = .done value after := by
  cases code <;> simp only [Dependencies.expression, Bool.and_eq_true] at closed
  all_goals repeat' (rcases closed with ⟨closed, rightClosed⟩)
  all_goals simp only [evalExpr] at evaluated ⊢
  all_goals
    repeat' first
      | contradiction
      | rw [step.expression (by assumption) (by assumption)]
      | rw [step.expressions (by assumption) (by simp_all only [Dependencies.expressions, Bool.and_eq_true, and_true, true_and])]
      | rw [step.place (by assumption) (by assumption)]
      | rw [step.place (by assumption) (expressionPlace_closed _ _ (by assumption) (by assumption))]
      | rw [step.arms (by assumption) (by assumption)]
      | rw [step.statement (by assumption)
          (matching.body _ _ _ (by assumption) (by assumption) (by assumption))]
      | rw [matching.constantFound (by assumption)]
      | rw [matching.functionFound (by assumption) (by assumption)]
      | simp_all only [Expr.binary.injEq, Bool.and_eq_true, Outcome.done.injEq, ← matching.target]
      | split at evaluated
    all_goals first
      | exact step.expression evaluated (by assumption)
      | exact step.arms evaluated (by assumption)
      | skip
    all_goals try obtain ⟨rfl, rfl⟩ := evaluated
    all_goals try rfl

end Lanius.Semantics.Restriction
