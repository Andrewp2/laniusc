import Lanius.Semantics.Relocation.Execution.Step

namespace Lanius.Semantics.Relocation.Execution

open Lanius.Core

theorem arms (step : Step fuel symbols smaller larger)
    (injective : Function.Injective symbols.typeId)
    (before : State) (value : Value) (arms : List (Pattern × Expr)) (result : Value) (after : State)
    (evaluated : evalMatchArms (fuel + 1) smaller before value arms = .done result after) :
    evalMatchArms (fuel + 1) larger (state symbols before) (Core.Relocation.value symbols value)
        (Core.Relocation.arms symbols arms) =
      .done (Core.Relocation.value symbols result) (state symbols after) := by
  cases arms with
  | nil => cases evaluated
  | cons arm rest =>
      obtain ⟨pattern, body⟩ := arm
      simp only [Core.Relocation.arms, evalMatchArms, Relocation.matchPattern symbols injective] at evaluated ⊢
      cases matched : Semantics.matchPattern pattern value with
      | none =>
          simp only [matched, Option.map] at evaluated ⊢
          exact step.arms evaluated
      | some entries =>
          simp only [matched, Option.map, ← bindLocals] at evaluated ⊢
          cases run : evalExpr fuel smaller (before.bindLocals entries) body with
          | done value completed =>
              rw [step.expression run]
              simp only [run, Semantics.restoreOutcomeLocals, Outcome.done.injEq] at evaluated
              obtain ⟨rfl, rfl⟩ := evaluated
              rfl
          | _ => simp [run, Semantics.restoreOutcomeLocals] at evaluated

end Lanius.Semantics.Relocation.Execution
