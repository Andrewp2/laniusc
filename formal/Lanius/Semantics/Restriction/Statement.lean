import Lanius.Semantics.Restriction.Step
import Std.Tactic

namespace Lanius.Semantics.Restriction
open Lanius.Core

theorem statement (step : Step fuel allowed original restricted)
    (before : State) (code : Stmt) (result : Completion) (after : State)
    (executed : execStmt (fuel + 1) original before code = .done result after)
    (closed : Dependencies.statement allowed code = true) :
    execStmt (fuel + 1) restricted before code = .done result after := by
  cases code <;> simp only [Dependencies.statement, Bool.and_eq_true] at closed
  all_goals repeat' (rcases closed with ⟨closed, rightClosed⟩)
  all_goals simp only [execStmt] at executed ⊢
  all_goals
    repeat' first
      | contradiction
      | rw [step.expression (by assumption) (by assumption)]
      | rw [step.statement (by assumption) (by assumption)]
      | rw [step.forValues (by assumption) (by assumption)]
      | rw [step.forRange (by assumption) (by assumption)]
      | simp_all only [Stmt.returnValue.injEq, Dependencies.optional, Outcome.done.injEq]
      | split at executed
    all_goals first
      | exact step.statement executed (by simp_all only [Dependencies.statement, Bool.and_eq_true, and_true])
      | exact step.forValues executed (by assumption)
      | exact step.forRange executed (by assumption)
      | exact restoredStatement step _ _ _ _ _ executed (by assumption)
      | exact executed
      | rfl

end Lanius.Semantics.Restriction
