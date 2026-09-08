import Lanius.Semantics.CellRenaming.Execution.Step
import Lanius.Semantics.CellRenaming.Projection
import Lanius.Semantics.CellRenaming.Execution.Bounds
import Std.Tactic

namespace Lanius.Semantics.CellRenaming.Execution
open Lanius.Core

theorem localExpression (rename : Permutation boundary)
    (before : State) (id : VarId) (result : Value) (after : State)
    (ready : boundary ≤ before.nextCell)
    (evaluated : evalExpr (fuel + 1) program before (.local id) = .done result after) :
    evalExpr (fuel + 1) program (state rename.forward before) (.local id) =
      .done (value rename.forward result) (state rename.forward after) ∧ boundary ≤ after.nextCell := by
  simp only [evalExpr, cellId] at evaluated ⊢
  cases found : before.cellId? id with
  | none => simp [found] at evaluated
  | some root =>
      simp only [found, Option.map, cellEntry] at evaluated ⊢
      cases entry : before.cellEntry? root with
      | none => simp [entry] at evaluated
      | some contents =>
          cases contents with
          | mk id contents =>
              cases contents with
              | none => simp [entry] at evaluated
              | some contents =>
                  simp only [entry, Outcome.done.injEq] at evaluated
                  obtain ⟨rfl, rfl⟩ := evaluated
                  exact ⟨by simp [entry, cell], ready⟩

theorem borrowExpression {rename : Permutation boundary} (step : Step fuel rename program)
    (before : State) (type : Ty) (input : Place) (result : Value) (after : State)
    (ready : boundary ≤ before.nextCell)
    (evaluated : evalExpr (fuel + 1) program before (.borrow type input) = .done result after) :
    evalExpr (fuel + 1) program (state rename.forward before)
        (.borrow type (CellRenaming.place rename.forward input)) =
      .done (value rename.forward result) (state rename.forward after) ∧ boundary ≤ after.nextCell := by
  simp only [evalExpr] at evaluated ⊢
  cases run : evalPlace fuel program before input with
  | done resolved next =>
      obtain ⟨transport, nextReady⟩ := step.place ready run
      rw [transport]
      cases resolved with
      | mk root path contents =>
          cases contents with
          | none => simp [run] at evaluated
          | some contents =>
              simp only [run, Outcome.done.injEq] at evaluated
              obtain ⟨rfl, rfl⟩ := evaluated
              exact ⟨rfl, nextReady⟩
  | _ => simp [run] at evaluated

theorem dereferenceExpression {rename : Permutation boundary} (step : Step fuel rename program)
    (before : State) (input : Expr) (result : Value) (after : State)
    (ready : boundary ≤ before.nextCell)
    (evaluated : evalExpr (fuel + 1) program before (.dereference input) = .done result after) :
    evalExpr (fuel + 1) program (state rename.forward before)
        (.dereference (CellRenaming.expression rename.forward input)) =
      .done (value rename.forward result) (state rename.forward after) ∧ boundary ≤ after.nextCell := by
  simp only [evalExpr] at evaluated ⊢
  cases run : evalExpr fuel program before input with
  | done entry next =>
      obtain ⟨transport, nextReady⟩ := step.expression ready run
      rw [transport]
      simp only [run] at evaluated
      simp only [CellRenaming.dereferenceValue]
      cases loaded : Semantics.dereferenceValue next entry with
      | error reason => simp [loaded] at evaluated
      | ok contents =>
          simp only [loaded, Outcome.done.injEq] at evaluated
          obtain ⟨rfl, rfl⟩ := evaluated
          exact ⟨by simp [loaded, Except.map], nextReady⟩
  | _ => simp [run] at evaluated

theorem assignExpression {rename : Permutation boundary} (step : Step fuel rename program)
    (before : State) (op : AssignOp) (place : Place) (input : Expr) (result : Value) (after : State)
    (ready : boundary ≤ before.nextCell)
    (evaluated : evalExpr (fuel + 1) program before (.assign op place input) = .done result after) :
    evalExpr (fuel + 1) program (state rename.forward before)
        (.assign op (CellRenaming.place rename.forward place) (CellRenaming.expression rename.forward input)) =
      .done (value rename.forward result) (state rename.forward after) ∧ boundary ≤ after.nextCell := by
  simp only [evalExpr] at evaluated ⊢
  cases placeRun : evalPlace fuel program before place with
  | done resolved afterPlace =>
      obtain ⟨placeTransport, placeReady⟩ := step.place ready placeRun
      rw [placeTransport]
      simp only []
      simp only [placeRun] at evaluated
      cases valueRun : evalExpr fuel program afterPlace input with
      | done entry afterValue =>
          obtain ⟨valueTransport, valueReady⟩ := step.expression placeReady valueRun
          rw [valueTransport]
          simp only [valueRun] at evaluated
          simp only [resolvedPlace, CellRenaming.assignment]
          cases computed : evalAssignValue program.target op resolved.value entry with
          | error reason => simp [computed] at evaluated
          | ok contents =>
              simp only [computed, Except.map] at evaluated ⊢
              have writeTransport := writeResolvedPlace rename afterValue resolved contents
              simp only [resolvedPlace] at writeTransport
              rw [writeTransport]
              cases written : Semantics.writeResolvedPlace afterValue resolved contents with
              | error reason => simp [written] at evaluated
              | ok completed =>
                  have same := writePlace_nextCell afterValue completed resolved contents written
                  simp only [written, Outcome.done.injEq] at evaluated
                  obtain ⟨rfl, rfl⟩ := evaluated
                  exact ⟨by simp [written, Except.map, value], same ▸ valueReady⟩
      | _ => simp [valueRun] at evaluated
  | _ => simp [placeRun] at evaluated

end Lanius.Semantics.CellRenaming.Execution
