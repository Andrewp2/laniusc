import Lanius.Semantics.CellRenaming.Execution.Step
import Lanius.Semantics.CellRenaming.Execution.Program

namespace Lanius.Semantics.CellRenaming.Execution
open Lanius.Core

theorem call {rename : Permutation boundary} (step : Step fuel rename program)
    (invariant : ProgramInvariant rename.forward program)
    (before : State) (id : FunctionId) (arguments : List Expr) (result : Value) (after : State)
    (ready : boundary ≤ before.nextCell)
    (evaluated : evalExpr (fuel + 1) program before (.call id arguments) = .done result after) :
    evalExpr (fuel + 1) program (state rename.forward before)
        (.call id (CellRenaming.expressions rename.forward arguments)) =
      .done (value rename.forward result) (state rename.forward after) ∧ boundary ≤ after.nextCell := by
  simp only [evalExpr] at evaluated ⊢
  cases argumentRun : evalExprs fuel program before arguments with
  | done entries afterArguments =>
      obtain ⟨argumentTransport, argumentsReady⟩ := step.expressions ready argumentRun
      rw [argumentTransport]
      simp only [argumentRun] at evaluated
      cases found : program.function? id with
      | none => simp [found] at evaluated
      | some declaration =>
          obtain ⟨body, hasBody, fixed⟩ := invariant.function id declaration found
          simp only [found, hasBody, bindParameters] at evaluated ⊢
          cases bound : Semantics.bindParameters declaration.parameters entries with
          | none => simp [bound] at evaluated
          | some locals =>
              simp only [bound, Option.map] at evaluated ⊢
              have calleeBound :
                  ({ state rename.forward afterArguments with locals := [] }).bindLocals
                      (bindings rename.forward locals) =
                    state rename.forward (({ afterArguments with locals := [] }).bindLocals locals) :=
                (bindLocals rename { afterArguments with locals := [] } argumentsReady locals).symm
              rw [calleeBound]
              cases bodyRun : execStmt fuel program
                  (({ afterArguments with locals := [] }).bindLocals locals) body with
              | done returned completed =>
                  obtain ⟨bodyTransport, completedReady⟩ := step.statement
                    (bindLocals_ready { afterArguments with locals := [] } locals argumentsReady) bodyRun
                  rw [fixed] at bodyTransport
                  rw [bodyTransport]
                  cases returned with
                  | breakLoop | continueLoop => simp [bodyRun] at evaluated
                  | next =>
                      simp only [bodyRun, completion] at evaluated ⊢
                      split at evaluated
                      · obtain ⟨rfl, rfl⟩ := Outcome.done.inj evaluated
                        exact ⟨by simp_all only [↓reduceIte]; rfl, completedReady⟩
                      · contradiction
                  | returned entry =>
                      cases entry with
                      | none =>
                          simp only [bodyRun, completion, Option.map] at evaluated ⊢
                          split at evaluated
                          · obtain ⟨rfl, rfl⟩ := Outcome.done.inj evaluated
                            exact ⟨by simp_all only [↓reduceIte]; rfl, completedReady⟩
                          · contradiction
                      | some entry =>
                          simp only [bodyRun, completion, Option.map] at evaluated ⊢
                          obtain ⟨rfl, rfl⟩ := Outcome.done.inj evaluated
                          exact ⟨rfl, completedReady⟩
              | _ => simp [bodyRun] at evaluated
  | _ => simp [argumentRun] at evaluated

theorem constant (invariant : ProgramInvariant rename program)
    (before : State) (id : ConstantId) (result : Value) (after : State)
    (ready : boundary ≤ before.nextCell)
    (evaluated : evalExpr (fuel + 1) program before (.constant id) = .done result after) :
    evalExpr (fuel + 1) program (state rename before) (.constant id) =
      .done (value rename result) (state rename after) ∧ boundary ≤ after.nextCell := by
  simp only [evalExpr] at evaluated ⊢
  cases found : program.constant? id with
  | none => simp [found] at evaluated
  | some declaration =>
      simp only [found, Outcome.done.injEq] at evaluated
      obtain ⟨rfl, rfl⟩ := evaluated
      exact ⟨by rw [invariant.constant id declaration found], ready⟩

end Lanius.Semantics.CellRenaming.Execution
