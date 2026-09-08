import Lanius.Semantics.Restriction.Step
import Std.Tactic

namespace Lanius.Semantics.Restriction
open Lanius.Core

theorem place (step : Step fuel allowed original restricted)
    (before : State) (code : Place) (result : ResolvedPlace) (after : State)
    (evaluated : evalPlace (fuel + 1) original before code = .done result after)
    (closed : Dependencies.place allowed code = true) :
    evalPlace (fuel + 1) restricted before code = .done result after := by
  cases code <;> simp only [Dependencies.place, Bool.and_eq_true] at closed
  all_goals repeat' (rcases closed with ⟨closed, rightClosed⟩)
  all_goals simp only [evalPlace] at evaluated ⊢
  all_goals
    repeat' first
      | contradiction
      | rw [step.expression (by assumption) (by assumption)]
      | rw [step.place (by assumption) (by assumption)]
      | simp_all only [Outcome.done.injEq]
      | split at evaluated
    all_goals try exact evaluated
    all_goals try rfl

end Lanius.Semantics.Restriction
