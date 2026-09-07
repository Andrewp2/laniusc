import Lanius.Semantics.Relocation.Execution.Step

namespace Lanius.Semantics.Relocation.Execution

open Lanius.Core

theorem expressions (step : Step fuel symbols smaller larger)
    (before : State) (expressions : List Expr) (values : List Value) (after : State)
    (evaluated : evalExprs (fuel + 1) smaller before expressions = .done values after) :
    evalExprs (fuel + 1) larger (state symbols before) (Core.Relocation.expressions symbols expressions) =
      .done (Core.Relocation.values symbols values) (state symbols after) := by
  cases expressions with
  | nil =>
      cases evaluated
      rfl
  | cons first rest =>
      simp only [evalExprs] at evaluated
      cases headRun : evalExpr fuel smaller before first with
      | done head next =>
          simp only [headRun] at evaluated
          cases tailRun : evalExprs fuel smaller next rest with
          | done tail completed =>
              simp only [tailRun, Outcome.done.injEq] at evaluated
              obtain ⟨rfl, rfl⟩ := evaluated
              simp only [Core.Relocation.expressions, evalExprs, step.expression headRun,
                step.expressions tailRun, Core.Relocation.values]
          | _ => simp [tailRun] at evaluated
      | _ => simp [headRun] at evaluated

end Lanius.Semantics.Relocation.Execution
