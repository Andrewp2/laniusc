import Lanius.Semantics.CellOnly.Step

namespace Lanius.Semantics.CellOnly

open Lanius.Core Lanius.Separation

theorem statementFrame (step : Step fuel program allowed)
    (supported : statement allowed input = true)
    (executed : execStmt (fuel + 1) program before input = .done result after) :
    HeapFrame before after := by
  cases input with
  | skip | breakLoop | continueLoop => cases executed; exact HeapFrame.refl _
  | expression input =>
    simp only [statement] at supported
    simp only [execStmt] at executed
    split at executed
    · obtain ⟨rfl, rfl⟩ := Outcome.done.inj executed
      exact step.expression supported (by assumption)
    all_goals contradiction
  | sequence first second =>
    simp only [statement, Bool.and_eq_true] at supported
    simp only [execStmt] at executed
    cases run : execStmt fuel program before first with
    | done entry next =>
      have frame := step.statement supported.1 run
      cases entry <;> simp only [run] at executed
      all_goals first
        | exact frame.trans (step.statement supported.2 executed)
        | (obtain ⟨rfl, rfl⟩ := Outcome.done.inj executed; exact frame)
    | _ => simp [run] at executed
  | letLocal id type initializer body =>
    simp only [statement, Bool.and_eq_true] at supported
    simp only [execStmt] at executed
    cases run : evalExpr fuel program before initializer with
    | done entry next =>
      have frame := step.expression supported.1 run
      simp only [run] at executed
      have bodyFrame := restoredStatement step supported.2 executed
      exact frame.trans ⟨bodyFrame.heap, bodyFrame.views⟩
    | _ => simp [run] at executed
  | letUninitialized id type body =>
    simp only [statement] at supported
    simp only [execStmt] at executed
    have frame := restoredStatement step supported executed
    exact ⟨frame.heap, frame.views⟩
  | ifThenElse condition yes no =>
    simp only [statement, Bool.and_eq_true] at supported
    simp only [execStmt] at executed
    split at executed
    · exact (step.expression supported.1.1 (by assumption)).trans (step.statement supported.1.2 executed)
    · exact (step.expression supported.1.1 (by assumption)).trans (step.statement supported.2 executed)
    all_goals contradiction
  | whileLoop condition body =>
    have loopSupported := supported
    simp only [statement, Bool.and_eq_true] at supported
    simp only [execStmt] at executed
    cases run : evalExpr fuel program before condition with
    | done entry next =>
      have frame := step.expression supported.1 run
      cases entry <;> simp only [run] at executed
      all_goals try contradiction
      case boolean flag =>
        cases flag with
        | false => obtain ⟨rfl, rfl⟩ := Outcome.done.inj executed; exact frame
        | true =>
          cases bodyRun : execStmt fuel program next body with
          | done entry completed =>
            have bodyFrame := step.statement supported.2 bodyRun
            cases entry <;> simp only [bodyRun] at executed
            all_goals first
              | exact frame.trans (bodyFrame.trans (step.statement loopSupported executed))
              | (obtain ⟨rfl, rfl⟩ := Outcome.done.inj executed; exact frame.trans bodyFrame)
          | _ => simp [bodyRun] at executed
    | _ => simp [run] at executed
  | forValues => contradiction
  | forRange id start stop inclusive body =>
    simp only [statement, Bool.and_eq_true] at supported
    simp only [execStmt] at executed
    split at executed
    · have startFrame := step.expression supported.1.1 (by assumption)
      cases stop with
      | none => exact startFrame.trans (step.forRange supported.2 executed)
      | some stopExpression =>
        simp only [] at executed
        split at executed
        · exact startFrame.trans ((step.expression supported.1.2 (by assumption)).trans
            (step.forRange supported.2 executed))
        all_goals contradiction
    all_goals contradiction
  | returnValue input =>
    cases input with
    | none => cases executed; exact HeapFrame.refl _
    | some input =>
      simp only [execStmt] at executed
      split at executed
      · obtain ⟨rfl, rfl⟩ := Outcome.done.inj executed
        exact step.expression supported (by assumption)
      all_goals contradiction

theorem rangeFrame {id : VarId} (step : Step fuel program allowed)
    (supported : statement allowed body = true)
    (executed : execForRange (fuel + 1) program before id current stop inclusive body = .done result after) :
    HeapFrame before after := by
  simp only [execForRange] at executed
  split at executed
  · cases executed; exact HeapFrame.refl _
  · cases run : execStmt fuel program (before.bindLocal id (.signed .i32 current)) body with
    | done entry next =>
      have bodyFrame := step.statement supported run
      have frame : HeapFrame before (restoreLocals before next) := bodyFrame.closeLocal before id (.signed .i32 current)
      cases entry <;> simp only [run] at executed
      all_goals repeat' first | split at executed | contradiction
      all_goals first
        | exact frame.trans (step.forRange supported executed)
        | (obtain ⟨rfl, rfl⟩ := Outcome.done.inj executed; exact frame)
    | _ => simp [run] at executed

end Lanius.Semantics.CellOnly
