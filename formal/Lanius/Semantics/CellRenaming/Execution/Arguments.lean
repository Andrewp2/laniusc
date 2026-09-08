import Lanius.Semantics.CellRenaming.Execution.Step

namespace Lanius.Semantics.CellRenaming.Execution
open Lanius.Core

theorem expressions {rename : Permutation boundary} (step : Step fuel rename program)
    (before : State) (input : List Expr) (result : List Value) (after : State)
    (ready : boundary ≤ before.nextCell)
    (evaluated : evalExprs (fuel + 1) program before input = .done result after) :
    evalExprs (fuel + 1) program (state rename.forward before) (CellRenaming.expressions rename.forward input) =
      .done (values rename.forward result) (state rename.forward after) ∧ boundary ≤ after.nextCell := by
  cases input with
  | nil =>
      cases evaluated
      exact ⟨rfl, ready⟩
  | cons first rest =>
      simp only [evalExprs] at evaluated
      cases headRun : evalExpr fuel program before first with
      | done head next =>
          obtain ⟨headTransport, nextReady⟩ := step.expression ready headRun
          simp only [headRun] at evaluated
          cases tailRun : evalExprs fuel program next rest with
          | done tail completed =>
              obtain ⟨tailTransport, completedReady⟩ := step.expressions nextReady tailRun
              simp only [tailRun, Outcome.done.injEq] at evaluated
              obtain ⟨rfl, rfl⟩ := evaluated
              exact ⟨by simp only [CellRenaming.expressions, evalExprs, headTransport,
                tailTransport, values], completedReady⟩
          | _ => simp [tailRun] at evaluated
      | _ => simp [headRun] at evaluated

end Lanius.Semantics.CellRenaming.Execution
