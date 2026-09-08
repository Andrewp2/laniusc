import Lanius.Semantics.CellRenaming.Execution.Step

namespace Lanius.Semantics.CellRenaming.Execution
open Lanius.Core

theorem arms {rename : Permutation boundary} (step : Step fuel rename program)
    (before : State) (input : Value) (branches : List (Pattern × Expr)) (result : Value) (after : State)
    (ready : boundary ≤ before.nextCell)
    (evaluated : evalMatchArms (fuel + 1) program before input branches = .done result after) :
    evalMatchArms (fuel + 1) program (state rename.forward before) (value rename.forward input)
        (CellRenaming.arms rename.forward branches) =
      .done (value rename.forward result) (state rename.forward after) ∧ boundary ≤ after.nextCell := by
  cases branches with
  | nil => cases evaluated
  | cons arm rest =>
      obtain ⟨pattern, body⟩ := arm
      simp only [CellRenaming.arms, evalMatchArms, CellRenaming.matchPattern] at evaluated ⊢
      cases matched : Semantics.matchPattern pattern input with
      | none =>
          simp only [matched, Option.map] at evaluated ⊢
          exact step.arms ready evaluated
      | some entries =>
          simp only [matched, Option.map] at evaluated ⊢
          rw [← bindLocals rename before ready]
          cases run : evalExpr fuel program (before.bindLocals entries) body with
          | done result completed =>
              obtain ⟨transport, completedReady⟩ :=
                step.expression (bindLocals_ready before entries ready) run
              rw [transport]
              simp only [run, Semantics.restoreOutcomeLocals, Outcome.done.injEq] at evaluated
              obtain ⟨rfl, rfl⟩ := evaluated
              exact ⟨rfl, completedReady⟩
          | _ => simp [run, Semantics.restoreOutcomeLocals] at evaluated

end Lanius.Semantics.CellRenaming.Execution
