import Lanius.Semantics.CellRenaming.Execution.Step
import Lanius.Semantics.CellRenaming.Projection
import Lanius.Semantics.CellRenaming.Execution.Bounds

namespace Lanius.Semantics.CellRenaming.Execution
open Lanius.Core

theorem arrayToSliceExpression {rename : Permutation boundary} (step : Step fuel rename program)
    (before : State) (type : Ty) (input : Expr) (result : Value) (after : State)
    (ready : boundary ≤ before.nextCell)
    (evaluated : evalExpr (fuel + 1) program before (.arrayToSlice type input) = .done result after) :
    evalExpr (fuel + 1) program (state rename.forward before)
        (.arrayToSlice type (CellRenaming.expression rename.forward input)) =
      .done (value rename.forward result) (state rename.forward after) ∧ boundary ≤ after.nextCell := by
  simp only [evalExpr, expressionPlace] at evaluated ⊢
  cases located : expressionPlace? input with
  | some place =>
      simp only [located, Option.map] at evaluated ⊢
      cases run : evalPlace fuel program before place with
      | done resolved next =>
          obtain ⟨transport, nextReady⟩ := step.place ready run
          rw [transport]
          cases resolved with
          | mk root path contents =>
              cases contents with
              | none => simp [run] at evaluated
              | some entry =>
                  cases entry <;> simp only [run] at evaluated
                  all_goals try contradiction
                  case array entries =>
                    obtain ⟨rfl, rfl⟩ := Outcome.done.inj evaluated
                    exact ⟨by simp [resolvedPlace, value, values_eq_map], nextReady⟩
      | _ => simp [run] at evaluated
  | none =>
      simp only [located, Option.map] at evaluated ⊢
      cases run : evalExpr fuel program before input with
      | done entry next =>
          obtain ⟨transport, nextReady⟩ := step.expression ready run
          rw [transport]
          cases entry <;> simp only [run] at evaluated
          all_goals try contradiction
          case array entries =>
            simp only [State.allocateTemporary, Outcome.done.injEq] at evaluated
            obtain ⟨rfl, rfl⟩ := evaluated
            constructor
            · simp [value, State.allocateTemporary, state, cell, values_eq_map,
                rename.fresh next.nextCell nextReady]
            · exact Nat.le_trans nextReady (Nat.le_succ next.nextCell)
      | _ => simp [run] at evaluated

theorem arrayPointerExpression {rename : Permutation boundary} (step : Step fuel rename program)
    (before : State) (input : Expr) (result : Value) (after : State)
    (ready : boundary ≤ before.nextCell)
    (evaluated : evalExpr (fuel + 1) program before (.i32ArrayDataPtr input) = .done result after) :
    evalExpr (fuel + 1) program (state rename.forward before)
        (.i32ArrayDataPtr (CellRenaming.expression rename.forward input)) =
      .done (value rename.forward result) (state rename.forward after) ∧ boundary ≤ after.nextCell := by
  simp only [evalExpr, expressionPlace] at evaluated ⊢
  cases located : expressionPlace? input with
  | some place =>
      simp only [located, Option.map] at evaluated ⊢
      cases run : evalPlace fuel program before place with
      | done resolved next =>
          obtain ⟨transport, nextReady⟩ := step.place ready run
          rw [transport]
          cases resolved with
          | mk root path contents =>
              cases contents with
              | none => simp [run] at evaluated
              | some entry =>
                  cases entry <;> simp only [run] at evaluated
                  all_goals try contradiction
                  case array entries =>
                    simp only [resolvedPlace, Option.map, value, CellRenaming.mapI32ArrayView,
                      evaluated, outcome]
                    exact ⟨trivial, (arrayView_nextCell next after root path entries result evaluated) ▸ nextReady⟩
      | _ => simp [run] at evaluated
  | none =>
      simp only [located, Option.map] at evaluated ⊢
      cases run : evalExpr fuel program before input with
      | done entry next =>
          obtain ⟨transport, nextReady⟩ := step.expression ready run
          rw [transport]
          cases entry <;> simp only [run] at evaluated
          all_goals try contradiction
          case array entries =>
            have allocation := allocateTemporary rename next nextReady (.array entries)
            simp only [value] at allocation
            simp only [value]
            rw [allocation]
            have exposed := CellRenaming.mapI32ArrayView rename
              (next.allocateTemporary (.array entries)).2 next.nextCell [] entries
            rw [rename.fresh next.nextCell nextReady] at exposed
            simp only [State.allocateTemporary] at evaluated exposed ⊢
            rw [exposed, evaluated]
            have same := arrayView_nextCell (next.allocateTemporary (.array entries)).2
              after next.nextCell [] entries result evaluated
            exact ⟨rfl, same ▸ Nat.le_trans nextReady (Nat.le_succ next.nextCell)⟩
      | _ => simp [run] at evaluated

end Lanius.Semantics.CellRenaming.Execution
