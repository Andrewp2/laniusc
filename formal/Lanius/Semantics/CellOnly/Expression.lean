import Lanius.Semantics.CellOnly.Step

namespace Lanius.Semantics.CellOnly

open Lanius.Core Lanius.Separation Lanius.Properties

theorem localFrame {id : VarId}
    (evaluated : evalExpr (fuel + 1) program before (.local id) = .done result after) :
    HeapFrame before after := by
  simp only [evalExpr] at evaluated
  repeat' first | split at evaluated | contradiction
  all_goals cases evaluated; exact HeapFrame.refl _

theorem castFrame (step : Step fuel program allowed)
    (supported : expression allowed input = true)
    (evaluated : evalExpr (fuel + 1) program before (.cast type input) = .done result after) :
    HeapFrame before after := by
  simp only [evalExpr] at evaluated
  repeat' first | split at evaluated | contradiction
  all_goals
    obtain ⟨rfl, rfl⟩ := Outcome.done.inj evaluated
    exact step.expression supported (by assumption)

theorem unaryFrame (step : Step fuel program allowed)
    (supported : expression allowed input = true)
    (evaluated : evalExpr (fuel + 1) program before (.unary op input) = .done result after) :
    HeapFrame before after := by
  simp only [evalExpr] at evaluated
  repeat' first | split at evaluated | contradiction
  all_goals
    obtain ⟨rfl, rfl⟩ := Outcome.done.inj evaluated
    exact step.expression supported (by assumption)

theorem binaryFrame (step : Step fuel program allowed)
    (leftSupported : expression allowed left = true) (rightSupported : expression allowed right = true)
    (evaluated : evalExpr (fuel + 1) program before (.binary op left right) = .done result after) :
    HeapFrame before after := by
  cases op <;> simp only [evalExpr] at evaluated
  all_goals repeat' first | split at evaluated | contradiction
  all_goals first
    | exact (step.expression leftSupported (by assumption)).trans (step.expression rightSupported evaluated)
    | (obtain ⟨rfl, rfl⟩ := Outcome.done.inj evaluated
       first
         | exact step.expression leftSupported (by assumption)
         | exact (step.expression leftSupported (by assumption)).trans (step.expression rightSupported (by assumption)))

theorem arrayFrame (step : Step fuel program allowed)
    (supported : expressions allowed entries = true)
    (evaluated : evalExpr (fuel + 1) program before (.array type entries) = .done result after) :
    HeapFrame before after := by
  simp only [evalExpr] at evaluated
  split at evaluated
  · obtain ⟨rfl, rfl⟩ := Outcome.done.inj evaluated
    exact step.expressions supported (by assumption)
  all_goals contradiction

theorem structFrame (step : Step fuel program allowed)
    (supported : expressions allowed entries = true)
    (evaluated : evalExpr (fuel + 1) program before (.structValue type entries) = .done result after) :
    HeapFrame before after := by
  simp only [evalExpr] at evaluated
  split at evaluated
  · obtain ⟨rfl, rfl⟩ := Outcome.done.inj evaluated
    exact step.expressions supported (by assumption)
  all_goals contradiction

theorem enumFrame (step : Step fuel program allowed)
    (supported : expressions allowed entries = true)
    (evaluated : evalExpr (fuel + 1) program before (.enumValue type variant entries) = .done result after) :
    HeapFrame before after := by
  simp only [evalExpr] at evaluated
  split at evaluated
  · obtain ⟨rfl, rfl⟩ := Outcome.done.inj evaluated
    exact step.expressions supported (by assumption)
  all_goals contradiction

theorem fieldFrame (step : Step fuel program allowed)
    (supported : expression allowed input = true)
    (evaluated : evalExpr (fuel + 1) program before (.field input field) = .done result after) :
    HeapFrame before after := by
  simp only [evalExpr] at evaluated
  repeat' first | split at evaluated | contradiction
  all_goals
    obtain ⟨rfl, rfl⟩ := Outcome.done.inj evaluated
    exact step.expression supported (by assumption)

theorem indexFrame (step : Step fuel program allowed)
    (baseSupported : expression allowed base = true) (indexSupported : expression allowed index = true)
    (evaluated : evalExpr (fuel + 1) program before (.index base index) = .done result after) :
    HeapFrame before after := by
  simp only [evalExpr] at evaluated
  repeat' first | split at evaluated | contradiction
  all_goals
    obtain ⟨rfl, rfl⟩ := Outcome.done.inj evaluated
    exact (step.expression baseSupported (by assumption)).trans (step.expression indexSupported (by assumption))

theorem borrowFrame (step : Step fuel program allowed)
    (supported : place allowed input = true)
    (evaluated : evalExpr (fuel + 1) program before (.borrow type input) = .done result after) :
    HeapFrame before after := by
  simp only [evalExpr] at evaluated
  repeat' first | split at evaluated | contradiction
  all_goals
    obtain ⟨rfl, rfl⟩ := Outcome.done.inj evaluated
    exact step.place supported (by assumption)

theorem dereferenceFrame (step : Step fuel program allowed)
    (supported : expression allowed input = true)
    (evaluated : evalExpr (fuel + 1) program before (.dereference input) = .done result after) :
    HeapFrame before after := by
  simp only [evalExpr] at evaluated
  repeat' first | split at evaluated | contradiction
  all_goals
    obtain ⟨rfl, rfl⟩ := Outcome.done.inj evaluated
    exact step.expression supported (by assumption)

theorem assignmentFrame (step : Step fuel program allowed)
    (targetSupported : place allowed target = true) (valueSupported : expression allowed input = true)
    (evaluated : evalExpr (fuel + 1) program before (.assign op target input) = .done result after) :
    HeapFrame before after := by
  simp only [evalExpr] at evaluated
  repeat' first | split at evaluated | contradiction
  all_goals
    obtain ⟨rfl, rfl⟩ := Outcome.done.inj evaluated
    have targetFrame := step.place targetSupported (by assumption)
    have valueFrame := step.expression valueSupported (by assumption)
    have stored := writeResolvedPlace_preserves_heap_and_views (by assumption)
    exact targetFrame.trans (valueFrame.trans ⟨stored.1, stored.2⟩)

theorem callFrame {id : FunctionId} (checked : Checked program allowed) (step : Step fuel program allowed)
    (included : allowed id = true) (supported : expressions allowed arguments = true)
    (evaluated : evalExpr (fuel + 1) program before (.call id arguments) = .done result after) :
    HeapFrame before after := by
  simp only [evalExpr] at evaluated
  cases argsRun : evalExprs fuel program before arguments with
  | done values afterArguments =>
    have argsFrame := step.expressions supported argsRun
    simp only [argsRun] at evaluated
    cases found : program.function? id with
    | none => simp [found] at evaluated
    | some declaration =>
      obtain ⟨body, bodyEq, bodySupported⟩ := checked.function id declaration included found
      simp only [found, bodyEq] at evaluated
      cases bindingsEq : bindParameters declaration.parameters values with
      | none => simp [bindingsEq] at evaluated
      | some bindings =>
        simp only [bindingsEq] at evaluated
        repeat' first | split at evaluated | contradiction
        all_goals
          obtain ⟨rfl, rfl⟩ := Outcome.done.inj evaluated
          have bodyFrame := step.statement bodySupported (by assumption)
          exact argsFrame.trans (bodyFrame.closeCall afterArguments bindings)
  | _ => simp [argsRun] at evaluated

theorem expressionFrame (checked : Checked program allowed) (step : Step fuel program allowed)
    (supported : expression allowed input = true)
    (evaluated : evalExpr (fuel + 1) program before input = .done result after) :
    HeapFrame before after := by
  cases input <;> simp only [expression, Bool.and_eq_true] at supported
  case value => cases evaluated; exact HeapFrame.refl _
  case «local» => exact localFrame evaluated
  case constant =>
    simp only [evalExpr] at evaluated
    split at evaluated
    · cases evaluated; exact HeapFrame.refl _
    · contradiction
  case cast => exact castFrame step supported evaluated
  case unary => exact unaryFrame step supported evaluated
  case binary => exact binaryFrame step supported.1 supported.2 evaluated
  case array => exact arrayFrame step supported evaluated
  case index => exact indexFrame step supported.1 supported.2 evaluated
  case structValue => exact structFrame step supported evaluated
  case field => exact fieldFrame step supported evaluated
  case enumValue => exact enumFrame step supported evaluated
  case assign => exact assignmentFrame step supported.1 supported.2 evaluated
  case borrow => exact borrowFrame step supported evaluated
  case dereference => exact dereferenceFrame step supported evaluated
  case call => exact callFrame checked step supported.1 supported.2 evaluated
  all_goals contradiction

end Lanius.Semantics.CellOnly
