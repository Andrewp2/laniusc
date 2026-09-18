import Lanius.Semantics.Capacity.Execution.Arguments

namespace Lanius.Semantics.Capacity.Execution
open Lanius.Core

theorem call {id : FunctionId} (valid : config.Valid) (step : Step fuel config allowed program)
    (checked : Fragment.Checked program allowed) (ready : Ready config before)
    (included : allowed id = true) (supported : Fragment.expressions allowed arguments = true)
    (evaluated : evalExpr (fuel + 1) program before (.call id arguments) = .done result after) :
    evalExpr (fuel + 1) program (state config before) (.call id arguments) = .done (value config result) (state config after) ∧
      Ready config after ∧ closed config result = true := by
  simp only [evalExpr] at evaluated ⊢
  cases argumentRun : evalExprs fuel program before arguments with
  | done entries afterArguments =>
    obtain ⟨argumentTransport, argumentsReady, argumentsClosed⟩ := step.expressions ready supported argumentRun
    rw [argumentTransport]
    simp only [argumentRun] at evaluated
    cases found : program.function? id with
    | none => simp [found] at evaluated
    | some declaration =>
      obtain ⟨body, hasBody, bodySupported⟩ := checked.function id declaration included found
      simp only [found, hasBody, parameters] at evaluated ⊢
      cases bound : Semantics.bindParameters declaration.parameters entries with
      | none => simp [bound] at evaluated
      | some locals =>
        simp only [bound, Option.map] at evaluated ⊢
        have localsClosed := parameters_closed argumentsClosed bound
        obtain ⟨calleeTransport, calleeReady⟩ := bindLocals valid argumentsReady.clearLocals localsClosed
        change ({ state config afterArguments with locals := [] }).bindLocals (bindings config locals) = _ at calleeTransport
        rw [calleeTransport]
        cases bodyRun : execStmt fuel program (({ afterArguments with locals := [] }).bindLocals locals) body with
        | done returned completed =>
          obtain ⟨bodyTransport, completedReady, resultClosed⟩ := step.statement calleeReady bodySupported bodyRun
          rw [bodyTransport]
          cases returned with
          | breakLoop | continueLoop => simp [bodyRun] at evaluated
          | next =>
            simp only [bodyRun, completion] at evaluated ⊢
            split at evaluated
            · obtain ⟨rfl, rfl⟩ := Outcome.done.inj evaluated
              exact ⟨by simp_all only [↓reduceIte]; rfl, completedReady.restoreLocals argumentsReady, rfl⟩
            · contradiction
          | returned entry =>
            cases entry with
            | none =>
              simp only [bodyRun, completion, Option.map] at evaluated ⊢
              split at evaluated
              · obtain ⟨rfl, rfl⟩ := Outcome.done.inj evaluated
                exact ⟨by simp_all only [↓reduceIte]; rfl, completedReady.restoreLocals argumentsReady, rfl⟩
              · contradiction
            | some entry =>
              simp only [bodyRun, completion, Option.map] at evaluated ⊢
              obtain ⟨rfl, rfl⟩ := Outcome.done.inj evaluated
              exact ⟨rfl, completedReady.restoreLocals argumentsReady, resultClosed⟩
        | _ => simp [bodyRun] at evaluated
  | _ => simp [argumentRun] at evaluated

theorem constant {id : ConstantId} (checked : Fragment.Checked program allowed) (ready : Ready config before)
    (evaluated : evalExpr (fuel + 1) program before (.constant id) = .done result after) :
    evalExpr (fuel + 1) program (state config before) (.constant id) = .done (value config result) (state config after) ∧
      Ready config after ∧ closed config result = true := by
  simp only [evalExpr] at evaluated ⊢
  cases found : program.constant? id with
  | none => simp [found] at evaluated
  | some declaration =>
    simp only [found, Outcome.done.injEq] at evaluated
    obtain ⟨rfl, rfl⟩ := evaluated
    exact ⟨by rw [plain_fixed config _ (checked.constant id declaration found)], ready,
      plain_closed config _ (checked.constant id declaration found)⟩

end Lanius.Semantics.Capacity.Execution
