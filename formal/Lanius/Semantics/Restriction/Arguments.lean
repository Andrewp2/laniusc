import Lanius.Semantics.Restriction.Step

namespace Lanius.Semantics.Restriction

open Lanius.Core

theorem expressions (step : Step fuel allowed original restricted)
    (before : State) (code : List Expr) (values : List Value) (after : State)
    (evaluated : evalExprs (fuel + 1) original before code = .done values after)
    (closed : Dependencies.expressions allowed code = true) :
    evalExprs (fuel + 1) restricted before code = .done values after := by
  cases code with
  | nil => cases evaluated; rfl
  | cons first rest =>
      obtain ⟨headClosed, tailClosed⟩ := Bool.and_eq_true_iff.mp closed
      simp only [evalExprs] at evaluated ⊢
      cases headRun : evalExpr fuel original before first with
      | done head next =>
          rw [step.expression headRun headClosed]
          simp only []
          simp only [headRun] at evaluated
          cases tailRun : evalExprs fuel original next rest with
          | done tail completed =>
              rw [step.expressions tailRun tailClosed]
              simpa only [tailRun] using evaluated
          | _ => simp [tailRun] at evaluated
      | _ => simp [headRun] at evaluated

theorem arms (step : Step fuel allowed original restricted)
    (before : State) (value : Value) (code : List (Pattern × Expr)) (result : Value) (after : State)
    (evaluated : evalMatchArms (fuel + 1) original before value code = .done result after)
    (closed : Dependencies.arms allowed code = true) :
    evalMatchArms (fuel + 1) restricted before value code = .done result after := by
  cases code with
  | nil => cases evaluated
  | cons arm rest =>
      obtain ⟨pattern, body⟩ := arm
      obtain ⟨bodyClosed, tailClosed⟩ := Bool.and_eq_true_iff.mp closed
      simp only [evalMatchArms] at evaluated ⊢
      cases matched : matchPattern pattern value with
      | none =>
          simp only [matched] at evaluated ⊢
          exact step.arms evaluated tailClosed
      | some entries =>
          simp only [matched] at evaluated ⊢
          cases run : evalExpr fuel original (before.bindLocals entries) body with
          | done value completed =>
              rw [step.expression run bodyClosed]
              simpa only [run] using evaluated
          | _ => simp [run, restoreOutcomeLocals] at evaluated

end Lanius.Semantics.Restriction
